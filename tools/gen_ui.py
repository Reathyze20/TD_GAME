# Sprite Studio: prohlizec a generator artu v prohlizeci.
#
#   python tools/gen_ui.py            # nastartuje a otevre http://localhost:8777
#   python tools/gen_ui.py --port 9000 --no-open
#
# PROC PROHLIZEC A NE DALSI DOCK V GODOTU
#
# Animation Lab umi jednu vec dobre: ladit zarovnani proti tomu, jak to kresli hra. Na
# prohlizeni celeho artu je ale dock spatne misto — je uzky, neumi mrizku a generovat z
# nej nejde, protoze generator je Python. Prohlizec zvladne oboje a nic se neinstaluje.
#
# CO TO UMI
#
#   Hra        Vsechen art po rodinach. Klik na priseru -> jeji sady (south, north,
#              east, attack, death), kazda se prehrava, da se krokovat po framech a
#              zvetsit. Znamky a miry z art_check.py u kazdeho framu.
#   Generator  Prompt -> N kandidatu vedle sebe, seřazenych podle znamky. Klik na
#              kandidata -> detail s paletou a merami. Odtud se da nainstalovat do hry.
#   Iterace    V detailu: „Doladit promptem" udela z kandidata jeho DITE (img2img z jeho
#              vlastnich pixelu). Kdo z koho vznikl, drzi meta.json v „lineage" a v
#              detailu se to kresli jako proužek predku — bez nej je slozka po peti
#              krocich hromada spritu, o kterych nikdo nevi, ze spolu souvisi.
#   Animace    Chuze nebo idle z JEDNOHO kandidata: vsechny framy maji stejneho rodice,
#              takze konzistence neni odhad, ale konstrukce.
#
# Zadny externi balicek: server je stdlib http.server, frontend je jeden HTML soubor bez
# CDN. Mereni a cisteni se importuji z art_check.py a gen.py — tretí kopie tehle
# matematiky by se rozesla se zbytkem pipeline.
import argparse
import json
import os
import shutil
import sys
import threading
import webbrowser
from collections import defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from art_check import (DISTRACTION_SUFFIXES, VARIANTS, isolated_ratio,  # noqa: E402
                       live_ids, palette_budget, split_family)

GEN_DIR = os.path.join(PROJ, "build", "gen")
ART_DIR = os.path.join(PROJ, "assets", "distractions")

# Generator se natahuje az pri prvnim pouziti — nacteni SDXL trva pul minuty a zabere
# 7 GB VRAM, coz je zbytecne, kdyz si jen prohlizis hotovy art.
_PIPE = None
_IMG2IMG = None
_PIPE_LOCK = threading.Lock()
# "cand" nese jmeno spritu, ktery uloha vyrobila — dolaďovani jinak nema jak rict, na
# ktere dite se ma detail po dobehnuti prepnout.
JOB = {"state": "idle", "msg": "", "done": 0, "total": 0, "set": "", "cand": ""}


# ------------------------------------------------------------------ mereni


def measure(path):
    try:
        a = np.array(Image.open(path).convert("RGBA"))
    except Exception:
        return None
    m = a[..., 3] > 32
    opaque = int(m.sum())
    if opaque == 0:
        return {"w": a.shape[1], "h": a.shape[0], "cols": 0, "iso": 0,
                "budget": 0, "pal": []}
    cols = top_colors(a, m)
    return {"w": a.shape[1], "h": a.shape[0], "cols": len(cols),
            "iso": round(isolated_ratio(a) * 100), "budget": palette_budget(opaque),
            "pal": ["#%02x%02x%02x" % c for c, _ in cols[:24]]}


def top_colors(a, m):
    """Barvy od nejcastejsi — v detailu se z nich kresli paleta, takze poradi nese
    informaci: prvni je ta, ktere je na spritu nejvic."""
    from collections import Counter
    return Counter(map(tuple, a[..., :3][m])).most_common()


# ------------------------------------------------------------------ sken


def scan_art():
    """assets/distractions -> [{id, sets:{suffix:[soubory]}}] ve stejnem cleneni,
    jake pouziva hra i Animation Lab."""
    ids = live_ids("distractions")
    fams = defaultdict(lambda: defaultdict(list))
    if not os.path.isdir(ART_DIR):
        return []
    import re
    fr = re.compile(r"^(.*)_frame_(\d+)\.png$")
    for f in sorted(os.listdir(ART_DIR)):
        m = fr.match(f)
        if not m:
            continue
        fam, anim = split_family(m.group(1), ids, DISTRACTION_SUFFIXES + ("",), VARIANTS)
        if fam is None:
            continue
        fams[fam][anim].append((int(m.group(2)), f))
    out = []
    for fam in sorted(fams):
        sets = {}
        for anim, lst in fams[fam].items():
            sets[(anim or "south").lstrip("_")] = [f for _, f in sorted(lst)]
        out.append({"id": fam, "sets": sets})
    return out


def read_meta(d):
    """meta.json sady se zpetnou kompatibilitou.

    Sady vygenerovane driv nemaji „lineage" ani „anims" a nikdy je mit nebudou — cteni
    proto musi projit i bez nich. Kdyby se na ne spolehalo, prvni spusteni nove verze by
    rozbilo prohlizeni vseho, co uz na disku je. Chybejici klice se doplni prazdne, takze
    zbytek kodu uz muze psat meta["lineage"][x] bez zjistovani, jak stara sada to je."""
    meta = {}
    p = os.path.join(d, "meta.json")
    if os.path.exists(p):
        try:
            meta = json.load(open(p, encoding="utf-8"))
        except Exception:
            meta = {}
    if not isinstance(meta, dict):
        meta = {}
    meta["prompt"] = meta.get("prompt") or ""
    for k in ("scores", "lineage", "anims"):
        if not isinstance(meta.get(k), dict):
            meta[k] = {}
    return meta


def write_meta(d, meta):
    json.dump(meta, open(os.path.join(d, "meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)


def scan_gen():
    out = []
    if not os.path.isdir(GEN_DIR):
        return out
    for d in sorted(os.listdir(GEN_DIR)):
        p = os.path.join(GEN_DIR, d)
        if not os.path.isdir(p):
            continue
        # Framy animace se jmenuji cand_03_walk_frame_1.png, takze by jinak vlezly do
        # mrizky kandidatu jako dalsi sprity — a osm framu chuze by vypadalo jako osm
        # novych priser. Do mrizky patri jen ten jeden sprite, ze ktereho vznikly.
        cands = sorted(f for f in os.listdir(p)
                       if f.startswith("cand_") and "_frame_" not in f)
        meta = read_meta(p)
        out.append({"name": d, "cands": cands, "prompt": meta["prompt"],
                    "scores": meta["scores"], "lineage": meta["lineage"],
                    "anims": meta["anims"]})
    return out


# ------------------------------------------------------------------ generovani


def run_generate(prompt, name, n, size, colors, steps, seed):
    global _PIPE
    import gen
    try:
        with _PIPE_LOCK:
            if _PIPE is None:
                JOB.update(state="running", msg="načítám model (poprvé se stahuje ~7 GB)…")
                _PIPE = gen.build_pipe()
        d = os.path.join(GEN_DIR, name)
        os.makedirs(d, exist_ok=True)
        JOB.update(state="running", msg="generuji", done=0, total=n, set=name)

        scores = {}
        for i in range(n):
            imgs = gen.generate(_PIPE, prompt, 1, steps, seed + i)
            a = gen.cut_background(imgs[0])
            a = gen.crop_to_subject(a)
            a = gen.downscale_median(a, size)
            a = gen.clean(a, colors)
            sc = gen.score(a)
            fn = "cand_%02d.png" % (i + 1)
            Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
            scores[fn] = sc
            JOB.update(done=i + 1, msg=f"kandidát {i + 1}/{n} — známka {sc['grade']}")

        json.dump({"prompt": prompt, "scores": scores},
                  open(os.path.join(d, "meta.json"), "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        JOB.update(state="done", msg=f"hotovo — {n} kandidátů")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


# ------------------------------------------------------------------ iterace a animace


def _img2img():
    """Lazy img2img roura VEDLE _PIPE, ne misto ni.

    Obe roury sdileji tytez vahy (gen.build_img2img), takze doladeni prvniho spritu
    nenacte model podruhe. Zamek je spolecny s _PIPE — dve soucasne ulohy by jinak zacaly
    nacitat model obe najednou a karta by dosla na OOM jeste pred prvnim krokem."""
    global _PIPE, _IMG2IMG
    import gen
    with _PIPE_LOCK:
        if _PIPE is None:
            JOB.update(state="running", msg="načítám model (poprvé se stahuje ~7 GB)…")
            _PIPE = gen.build_pipe()
        if _IMG2IMG is None:
            JOB.update(state="running", msg="připravuji img2img…")
            _IMG2IMG = gen.build_img2img(_PIPE)
    return _IMG2IMG


def load_cand(setname, cand):
    p = os.path.join(GEN_DIR, os.path.basename(setname), os.path.basename(cand))
    if not os.path.isfile(p):
        return None
    return np.array(Image.open(p).convert("RGBA"))


def next_cand(d):
    """Prvni volne cand_NN.png.

    Cislo se bere z toho, co na disku JE, ne z poctu polozek: kdyz nekoho z prostredku
    smazes, novy kandidat nesmi prepsat toho, ktery zbyl — a s nim i cely jeho rodokmen."""
    n = 0
    for f in os.listdir(d):
        if f.startswith("cand_") and f.endswith(".png") and "_frame_" not in f:
            try:
                n = max(n, int(f[len("cand_"):-len(".png")]))
            except ValueError:
                pass
    return "cand_%02d.png" % (n + 1)


def lineage_chain(setname, cand):
    """Retez predku od korene k tomuhle kandidatovi.

    Kandidat bez zaznamu je koren — tak vypadaji vsichni, kdo vznikli prvnim generovanim
    i cela stara meta.json. Pojistka proti cyklu tu je proto, ze meta.json je obycejny
    soubor na disku: staci rucni uprava na „rodic sam sebe" a server by se zatocil."""
    meta = read_meta(os.path.join(GEN_DIR, os.path.basename(setname)))
    lin = meta["lineage"]
    chain, seen, cur = [], set(), cand
    while cur and cur not in seen:
        seen.add(cur)
        rec = lin.get(cur) or {}
        chain.append({"cand": cur, "prompt": rec.get("prompt") or meta["prompt"],
                      "strength": rec.get("strength")})
        cur = rec.get("parent")
    chain.reverse()
    return chain


def run_refine(setname, cand, prompt, strength):
    """Z kandidata udelej jeho dite a zapis, ze z nej vzniklo.

    Rodic, prompt i sila jdou do „lineage" hned pri vzniku. Doplnovat je pozdeji nejde —
    za tyden uz nikdo nevi, ze cand_07 je vylepsene cand_03, a hromada spritu ve slozce
    prestane davat smysl."""
    import gen
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        parent = load_cand(setname, cand)
        if parent is None:
            JOB.update(state="error", msg="rodič neexistuje")
            return
        pipe2 = _img2img()
        JOB.update(state="running", msg="dolaďuji", done=0, total=1, set=setname, cand="")
        a = gen.refine(pipe2, parent, prompt, strength=float(strength),
                       size=max(parent.shape[:2]))
        sc = gen.score(a)
        fn = next_cand(d)
        Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
        meta = read_meta(d)
        meta["scores"][fn] = sc
        meta["lineage"][fn] = {"parent": cand, "prompt": prompt, "strength": float(strength)}
        write_meta(d, meta)
        JOB.update(state="done", done=1, cand=fn,
                   msg=f"hotovo — {fn}, známka {sc['grade']}")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def run_animate(setname, cand, kind, strength):
    """Animace z jednoho kandidata — framy vedle nej, ne do assets/.

    Prompt se bere z rodokmenu kandidata, ne z pole na obrazovce: framy maji vzniknout z
    TOHO, co je na spritu videt, ne z toho, co bylo naposledy napsane v hlavicce."""
    import gen
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            JOB.update(state="error", msg="kandidát neexistuje")
            return
        chain = lineage_chain(setname, cand)
        prompt = chain[-1]["prompt"] if chain else ""
        poses = gen.POSES.get(kind)
        if not poses:
            JOB.update(state="error", msg=f"neznámý druh animace: {kind}")
            return
        # gen.animate chce HOTOVE prompty poz, ne druh animace. Slozit je musi volajici,
        # protoze jen ten zna prompt rodice. Predat misto toho retezec by nechalo
        # `for pose in prompt` iterovat po PISMENECH a vyrobit frame na kazde z nich.
        pipe2 = _img2img()
        pose_prompts = [f"{prompt}, {ph}" if prompt else ph for ph in poses]
        JOB.update(state="running", msg="animuji", done=0, total=len(pose_prompts),
                   set=setname, cand="")
        frames = gen.animate(pipe2, base, pose_prompts, strength=float(strength),
                             size=max(base.shape[:2]),
                             on_frame=lambda i, n: JOB.update(done=i, msg=f"frame {i}/{n}"))
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand
        names = []
        for i, a in enumerate(frames, 1):
            fn = f"{stem}_{kind}_frame_{i}.png"
            Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
            names.append(fn)
        meta = read_meta(d)
        meta["anims"][f"{stem}_{kind}"] = names
        write_meta(d, meta)
        JOB.update(state="done", cand=cand, msg=f"hotovo — {len(names)} framů")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def install(setname, cand, target):
    """Kandidat -> assets/distractions/<target>_frame_1.png.

    Zamerne jen JEDEN frame. Kandidati z jednoho promptu nejsou animace — je to N pokusu
    o tutez pozu, ne osm framu chuze. Tvarit se, ze z nich cyklus slozim, by vyrobilo
    presne to kmitani, ktere celou dobu meríme a opravujeme. Animace se resi zvlast.

    Cil byl sanitizovany od zacatku, ZDROJ ne — a pritom prave ten rozhoduje, co se do
    assets/ zkopiruje. install("..\\..", "README.md", "x") soubor opravdu vyrobil."""
    src = os.path.join(GEN_DIR, os.path.basename(setname), os.path.basename(cand))
    if not os.path.exists(src):
        return False, "kandidát neexistuje"
    safe = "".join(ch for ch in target if ch.isalnum() or ch == "_")
    if not safe:
        return False, "neplatné jméno"
    dst = os.path.join(ART_DIR, f"{safe}_frame_1.png")
    if os.path.exists(dst):
        return False, f"{os.path.basename(dst)} už existuje — zvol jiné jméno"
    shutil.copyfile(src, dst)
    return True, os.path.relpath(dst, PROJ)


# ------------------------------------------------------------------ server

HTML = r"""<!doctype html><html lang="cs"><meta charset="utf-8">
<title>Sprite Studio</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#14131a;color:#dcdce4;font:14px/1.5 system-ui,-apple-system,sans-serif;
 display:grid;grid-template-columns:210px 1fr;grid-template-rows:auto 1fr;height:100vh}
header{grid-column:1/3;display:flex;gap:8px;align-items:center;padding:10px 14px;
 background:#1b1a23;border-bottom:1px solid #2a2935}
header b{font-size:15px;margin-right:6px}
input,select,button{background:#24232e;color:#dcdce4;border:1px solid #34333f;
 border-radius:6px;padding:6px 10px;font:inherit}
input:focus,select:focus{outline:1px solid #6d7cff}
button{cursor:pointer}button:hover{background:#2e2d3a}
button.p{background:#4d5bd6;border-color:#5b68e0}button.p:hover{background:#5b68e0}
button:disabled{opacity:.45;cursor:default}
#prompt{flex:1;min-width:180px}
nav{background:#191822;border-right:1px solid #2a2935;overflow:auto;padding:8px}
nav h3{font-size:11px;text-transform:uppercase;color:#7a7a8c;margin:12px 6px 6px;
 letter-spacing:.04em}
nav a{display:block;padding:6px 9px;border-radius:6px;color:#c2c2d0;cursor:pointer;
 text-decoration:none;font-size:13px}
nav a:hover{background:#23222e}nav a.on{background:#333150;color:#fff}
main{overflow:auto;padding:16px 18px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(132px,1fr));gap:12px}
.card{background:#1d1c26;border:1px solid #2a2935;border-radius:9px;padding:9px;
 cursor:pointer;text-align:center}
.card:hover{border-color:#4d5bd6}
.card img,.big img,.strip img{image-rendering:pixelated;display:block}
.card img{width:100%;background:#0e0d13;border-radius:5px}
.card .n{font-size:12px;margin-top:6px;color:#a8a8ba;display:flex;
 justify-content:space-between;align-items:center}
.badge{font-size:11px;font-weight:700;padding:1px 6px;border-radius:4px}
.g-hi{background:#1e4630;color:#7ee2a8}.g-mid{background:#4a3c1a;color:#ffcf7a}
.g-lo{background:#4a1f1f;color:#ff9188}
h2{font-size:17px;margin-bottom:4px}.sub{color:#7a7a8c;font-size:12px;margin-bottom:14px}
.row{display:flex;gap:22px;flex-wrap:wrap;margin-bottom:22px}
.setbox{background:#1d1c26;border:1px solid #2a2935;border-radius:9px;padding:10px}
.setbox h4{font-size:12px;color:#9a9aac;margin-bottom:7px;text-transform:uppercase}
.big{background:#0e0d13;border-radius:6px;display:grid;place-items:center;padding:10px}
.strip{display:flex;gap:4px;margin-top:8px;flex-wrap:wrap}
.strip img{width:38px;background:#0e0d13;border-radius:3px;border:2px solid transparent}
.strip img.on{border-color:#6d7cff}
.meta{font-size:12px;color:#8d8d9e;margin-top:8px;line-height:1.7}
.meta b{color:#c8c8d6;font-weight:600}
.pal{display:flex;flex-wrap:wrap;gap:3px;margin-top:6px}
.pal i{width:15px;height:15px;border-radius:3px;display:block;border:1px solid #00000060}
.ped{display:flex;align-items:center;gap:5px;flex-wrap:wrap;margin-bottom:10px}
.ped img{width:34px;height:34px;background:#0e0d13;border-radius:5px;cursor:pointer;
 border:2px solid #2a2935;image-rendering:pixelated}
.ped img:hover{border-color:#4d5bd6}.ped img.on{border-color:#6d7cff}
.ped s{color:#5c5c6b;text-decoration:none;font-size:13px}
.ped span{color:#7a7a8c;font-size:12px;margin-left:6px}
.box{background:#191822;border:1px solid #2a2935;border-radius:8px;padding:10px;margin-top:14px}
.box h5{font-size:11px;text-transform:uppercase;color:#7a7a8c;letter-spacing:.04em;
 margin-bottom:8px;font-weight:700}
.rowf{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.rowf input[type=range]{flex:1;min-width:120px;padding:0;accent-color:#6d7cff}
.hint{font-size:12px;color:#8d8d9e;min-width:190px}
dialog{background:#1d1c26;color:#dcdce4;border:1px solid #34333f;border-radius:12px;
 padding:18px;max-width:620px}
dialog::backdrop{background:#000a}
.warn{background:#3a2a14;border:1px solid #6b4d1c;color:#ffcf8a;padding:8px 11px;
 border-radius:7px;font-size:13px;margin-bottom:14px}
#status{font-size:12px;color:#8d8d9e}
</style>
<header>
 <b>Sprite Studio</b>
 <input id="prompt" placeholder="energy drink creature with legs — anglicky">
 <input id="name" placeholder="jméno" style="width:110px">
 <select id="n"><option>4</option><option selected>6</option><option>8</option><option>12</option></select>
 <select id="size"><option>16</option><option selected>32</option><option>64</option></select>
 <button class="p" id="go">Generovat</button>
 <span id="status"></span>
</header>
<nav id="nav"></nav>
<main id="main"></main>
<dialog id="dlg"></dialog>
<script>
let ST={art:[],gen:[]}, sel=null, timers=[];
const $=s=>document.querySelector(s);
const gcls=g=>g>=7?'g-hi':g>=4?'g-mid':'g-lo';

async function load(){
  ST=await (await fetch('/api/state')).json();
  drawNav(); if(sel) open(sel.kind,sel.key); else if(ST.art[0]) open('art',ST.art[0].id);
}
function drawNav(){
  let h='<h3>Generátor</h3>';
  h+=ST.gen.length?ST.gen.map(s=>`<a data-k="gen" data-i="${s.name}">${s.name}</a>`).join('')
    :'<a style="color:#5c5c6b;cursor:default">zatím nic</a>';
  h+='<h3>Hra</h3>'+ST.art.map(a=>`<a data-k="art" data-i="${a.id}">${a.id}</a>`).join('');
  $('#nav').innerHTML=h;
  document.querySelectorAll('nav a[data-k]').forEach(a=>
    a.onclick=()=>open(a.dataset.k,a.dataset.i));
}
function mark(){document.querySelectorAll('nav a').forEach(a=>
  a.classList.toggle('on',sel&&a.dataset.k===sel.kind&&a.dataset.i===sel.key));}

function open(kind,key){
  sel={kind,key}; mark(); timers.forEach(clearInterval); timers=[];
  kind==='art'?drawArt(key):drawGen(key);
}

function drawArt(id){
  const a=ST.art.find(x=>x.id===id); if(!a)return;
  const order=['south','north','east','west','attack','death'];
  const keys=Object.keys(a.sets).sort((x,y)=>order.indexOf(x)-order.indexOf(y));
  let h=`<h2>${id}</h2><div class="sub">${keys.length} sad — klikni na frame pro detail</div><div class="row">`;
  keys.forEach(k=>{
    const f=a.sets[k];
    h+=`<div class="setbox"><h4>${k} · ${f.length} framů</h4>
      <div class="big"><img id="pl-${k}" src="/img/art/${f[0]}" style="width:128px"></div>
      <div class="strip" id="st-${k}">${f.map((n,i)=>
        `<img src="/img/art/${n}" data-s="${k}" data-i="${i}" class="${i?'':'on'}">`).join('')}</div>
      </div>`;
  });
  $('#main').innerHTML=h+'</div>';
  keys.forEach(k=>{                       // kazda sada bezi svym tempem, jako ve hre
    const f=a.sets[k]; let i=0;
    timers.push(setInterval(()=>{i=(i+1)%f.length;
      $('#pl-'+k).src='/img/art/'+f[i];
      document.querySelectorAll(`#st-${k} img`).forEach((e,j)=>e.classList.toggle('on',i===j));
    },1000/12));
  });
  document.querySelectorAll('.strip img').forEach(im=>im.onclick=e=>{
    e.stopPropagation(); detail(new URL(im.src).pathname, null, null);});
}

function drawGen(name){
  const s=ST.gen.find(x=>x.name===name); if(!s)return;
  let h=`<h2>${name}</h2><div class="sub">${s.prompt||''}</div><div class="grid">`;
  const sorted=[...s.cands].sort((a,b)=>(s.scores[b]?.grade||0)-(s.scores[a]?.grade||0));
  sorted.forEach(c=>{const g=s.scores[c]?.grade;
    h+=`<div class="card" data-c="${c}"><img src="/img/gen/${name}/${c}">
      <div class="n"><span>${c.replace('cand_','#').replace('.png','')}</span>
      ${g!=null?`<span class="badge ${gcls(g)}">${g}</span>`:''}</div></div>`;});
  $('#main').innerHTML=h+'</div>';
  document.querySelectorAll('.card').forEach(c=>c.onclick=()=>
    detail('/img/gen/'+name+'/'+c.dataset.c, name, c.dataset.c));
}

// Sila prepisu neni cislo, ktere by nekomu neco rikalo — popisek rika, co se stane.
const sLabel=v=>v<.25?'drobná úprava, tvar zůstane':v<.4?'znatelná změna, silueta se drží'
  :v<.5?'velká změna, zůstane barevnost':'skoro nový sprite';
const esc=t=>String(t==null?'':t).replace(/[&<>"]/g,
  c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const post=async(u,b)=>(await fetch(u,{method:'POST',body:JSON.stringify(b)})).json();
// Prehravani v dialogu ma vlastni timery: ty v `timers` maze prepnuti v levem sloupci,
// ale dialog se otevira a zavira nezavisle na nem.
let dtimers=[];
function stopD(){dtimers.forEach(clearInterval);dtimers=[];}
function busy(x){['#go','#rgo','#aw','#ai'].forEach(s=>{const e=$(s);if(e)e.disabled=x;});}

async function detail(src,setname,cand){
  stopD();
  const m=await (await fetch('/api/measure?src='+encodeURIComponent(src))).json();
  const s=setname?ST.gen.find(x=>x.name===setname):null;
  const stem=cand?cand.replace(/\.png$/,''):'';
  const anims=s?Object.entries(s.anims||{}).filter(
    ([k,f])=>k.indexOf(stem+'_')===0&&f.length):[];
  let chain=[];
  if(setname&&cand)chain=(await (await fetch('/api/lineage?set='+
    encodeURIComponent(setname)+'&cand='+encodeURIComponent(cand))).json()).chain||[];

  const ped=chain.length?`<div class="ped">`+chain.map((c,i)=>(i?'<s>→</s>':'')+
      `<img src="/img/gen/${setname}/${c.cand}" data-c="${c.cand}"
        class="${c.cand===cand?'on':''}" title="${esc(c.prompt)}${
        c.strength!=null?' · síla '+c.strength:''}">`).join('')+
      `<span>${chain.length>1?'rodokmen — klikni na předka'
        :'kořen rodokmenu'}</span></div>`:'';

  const tune=setname?`<div class="box"><h5>Doladit promptem</h5>
    <input id="rp" style="width:100%" placeholder="co změnit — anglicky, např. bigger angry eyes">
    <div class="rowf" style="margin-top:8px">
      <input type="range" id="rs" min="15" max="60" value="35">
      <span class="hint" id="rsl"></span>
      <button class="p" id="rgo">Doladit</button></div>
    <div class="meta">Vznikne <b>dítě</b> tohohle spritu: model dostane jeho pixely jako
      předlohu a přepíše z nich jen tolik, kolik dovolí síla. Paleta se zamkne na rodiče,
      aby se příšera po pár krocích nezměnila v jinou.</div></div>`:'';

  const anim=setname?`<div class="box"><h5>Animace</h5>
    <div class="rowf"><button id="aw">Animace: chůze</button>
      <button id="ai">Animace: idle</button>
      <span class="hint" style="flex:1">Všechny framy vznikají z tohohle spritu, takže
        si zůstanou podobné.</span></div>
    ${anims.map(([k,f])=>`<div class="setbox" style="margin-top:10px">
      <h4>${k.slice(stem.length+1)} · ${f.length} framů</h4>
      <div class="big"><img id="ap-${k}" src="/img/gen/${setname}/${f[0]}" style="width:128px"></div>
      <div class="strip" id="as-${k}">${f.map((n,i)=>
        `<img src="/img/gen/${setname}/${n}" class="${i?'':'on'}">`).join('')}</div>
      </div>`).join('')}</div>`:'';

  $('#dlg').innerHTML=ped+`<div class="big"><img src="${src}" style="width:min(340px,60vw)"></div>
   <div class="meta"><b>${m.w}×${m.h}</b> · <b>${m.cols}</b> barev
     (rozpočet ${m.budget}) · <b>${m.iso}%</b> šumu
     <div class="pal">${(m.pal||[]).map(c=>`<i style="background:${c}"></i>`).join('')}</div></div>
   ${tune}${anim}
   ${setname?`<div style="margin-top:14px;display:flex;gap:8px">
     <input id="tgt" placeholder="id do hry, např. energy_drink_b" style="flex:1">
     <button class="p" id="inst">Nainstalovat</button></div>
     <div class="meta" id="imsg">Uloží se jako &lt;id&gt;_frame_1.png do assets/distractions/.</div>`:''}
   <div style="margin-top:16px;text-align:right"><button onclick="dlg.close()">Zavřít</button></div>`;
  // showModal na uz otevrenem dialogu vyhodi vyjimku, a rodokmen se prepina PRAVE
  // uvnitr otevreneho dialogu.
  if(!$('#dlg').open)$('#dlg').showModal();
  $('#dlg').onclose=stopD;

  anims.forEach(([k,f])=>{let i=0;dtimers.push(setInterval(()=>{
    const im=$('#ap-'+k); if(!im)return;
    i=(i+1)%f.length; im.src='/img/gen/'+setname+'/'+f[i];
    document.querySelectorAll(`#as-${k} img`).forEach((e,j)=>e.classList.toggle('on',i===j));
  },1000/10));});

  if(!setname)return;
  document.querySelectorAll('.ped img').forEach(im=>im.onclick=()=>
    detail('/img/gen/'+setname+'/'+im.dataset.c,setname,im.dataset.c));

  const sl=$('#rs'), lab=()=>$('#rsl').textContent=
    (sl.value/100).toFixed(2)+' — '+sLabel(sl.value/100);
  sl.oninput=lab; lab();

  $('#rgo').onclick=async()=>{
    const pr=$('#rp').value.trim();
    if(!pr){$('#rp').focus();return;}
    const r=await post('/api/refine',{set:setname,cand,prompt:pr,strength:sl.value/100});
    if(r.err){$('#status').textContent=r.err;return;}
    busy(true);
    pollJob(async j=>{busy(false); await load();
      // Detail se prepne na dite: dalsi doladeni uz pokracuje z nej, ne z rodice.
      detail('/img/gen/'+setname+'/'+(j.cand||cand),setname,j.cand||cand);});
  };
  const startAnim=async kind=>{
    const r=await post('/api/animate',{set:setname,cand,kind,strength:0.3});
    if(r.err){$('#status').textContent=r.err;return;}
    busy(true);
    pollJob(async()=>{busy(false); await load(); detail(src,setname,cand);});
  };
  $('#aw').onclick=()=>startAnim('walk');
  $('#ai').onclick=()=>startAnim('idle');

  $('#inst').onclick=async()=>{
    const r=await post('/api/install',{set:setname,cand,target:$('#tgt').value});
    $('#imsg').textContent=r.ok?('nainstalováno: '+r.msg):('nešlo: '+r.msg);
    if(r.ok)load();};
}

async function pollJob(done){
  const j=await (await fetch('/api/job')).json();
  $('#status').textContent=j.state==='idle'?'':
    (j.msg+(j.total?` (${j.done}/${j.total})`:''));
  if(j.state==='running'){setTimeout(()=>pollJob(done),900);return;}
  if(done)done(j);
}

$('#go').onclick=async()=>{
  const p=$('#prompt').value.trim(); if(!p)return;
  $('#go').disabled=true;
  await fetch('/api/generate',{method:'POST',body:JSON.stringify({
    prompt:p,name:$('#name').value.trim(),n:+$('#n').value,size:+$('#size').value})});
  poll();
};
async function poll(){
  const j=await (await fetch('/api/job')).json();
  $('#status').textContent=j.state==='idle'?'':
    (j.msg+(j.total?` (${j.done}/${j.total})`:''));
  if(j.state==='running'){setTimeout(poll,900);return;}
  $('#go').disabled=false;
  if(j.state==='done'){await load(); if(j.set)open('gen',j.set);}
}
load();
</script></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _file(self, path):
        if not os.path.isfile(path):
            self._send(404, {"err": "nenalezeno"})
            return
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        p = unquote(u.path)
        if p == "/":
            return self._send(200, HTML, "text/html; charset=utf-8")
        if p == "/api/state":
            return self._send(200, {"art": scan_art(), "gen": scan_gen()})
        if p == "/api/job":
            return self._send(200, JOB)
        if p == "/api/measure":
            from urllib.parse import parse_qs
            src = (parse_qs(u.query).get("src") or [""])[0]
            return self._send(200, measure(self._resolve(src)) or {})
        if p == "/api/lineage":
            from urllib.parse import parse_qs
            q = parse_qs(u.query)
            s = os.path.basename((q.get("set") or [""])[0])
            c = os.path.basename((q.get("cand") or [""])[0])
            # Prazdny retez misto chyby: kandidat ze sekce Hra zadny rodokmen nema a
            # prohlizec ho smi zobrazovat stejnym kodem jako ten z generatoru.
            return self._send(200, {"set": s, "cand": c,
                                    "chain": lineage_chain(s, c) if s and c else []})
        if p.startswith("/img/art/"):
            return self._file(os.path.join(ART_DIR, os.path.basename(p)))
        if p.startswith("/img/gen/"):
            rest = p[len("/img/gen/"):].split("/")
            if len(rest) == 2:
                # basename na OBOU castech. Cesta uz je po unquote, takze %5c je v tomhle
                # miste zpetne lomitko a bez tehle zavory sel pres jednu komponentu
                # precist libovolny soubor na disku (overeno: /img/gen/..%5c..%5cWindows/win.ini
                # vratilo 200 a obsah). _resolve o kus niz to delalo spravne, tohle ne.
                return self._file(os.path.join(GEN_DIR, os.path.basename(rest[0]),
                                               os.path.basename(rest[1])))
        self._send(404, {"err": "nenalezeno"})

    def _resolve(self, src):
        """URL obrazku -> cesta na disku.

        Prijima cestu i absolutni URL: <img>.src je v prohlizeci VZDY absolutni, takze
        porovnavat ho proti "/img/..." tise selze a detail ukaze undefined u vsech mer.
        Bere se jen basename, takze ../ nikam nevede."""
        if "://" in src:
            src = urlparse(src).path
        if src.startswith("/img/art/"):
            return os.path.join(ART_DIR, os.path.basename(src))
        if src.startswith("/img/gen/"):
            r = src[len("/img/gen/"):].split("/")
            if len(r) == 2:
                return os.path.join(GEN_DIR, os.path.basename(r[0]), os.path.basename(r[1]))
        return ""

    def do_POST(self):
        # Frontend posila JSON bez hlavicek, takze Content-Type je text/plain a prohlizec
        # to bere jako "simple request" — zadny preflight. Libovolna otevrena stranka by
        # tedy mohla poslat /api/install nebo rozjet generovani na localhost:8777.
        # Vlastni fetch Origin neposila (same-origin), takze prazdny je v poradu.
        origin = self.headers.get("Origin")
        if origin and urlparse(origin).hostname not in ("localhost", "127.0.0.1", "::1"):
            return self._send(403, {"err": "cizí origin"})
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._send(400, {"err": "špatný JSON"})
        p = urlparse(self.path).path
        if p == "/api/generate":
            if JOB["state"] == "running":
                return self._send(409, {"err": "už běží"})
            name = body.get("name") or "".join(
                ch if ch.isalnum() else "_" for ch in body.get("prompt", ""))[:28]
            t = threading.Thread(target=run_generate, kwargs=dict(
                prompt=body.get("prompt", ""), name=name, n=int(body.get("n", 6)),
                size=int(body.get("size", 32)), colors=16, steps=28, seed=1), daemon=True)
            t.start()
            return self._send(200, {"ok": True, "set": name})
        if p in ("/api/refine", "/api/animate"):
            return self._iterate(p, body)
        if p == "/api/install":
            ok, msg = install(body.get("set", ""), body.get("cand", ""), body.get("target", ""))
            return self._send(200, {"ok": ok, "msg": msg})
        self._send(404, {"err": "nenalezeno"})

    def _iterate(self, p, body):
        """Doladeni i animace: obe berou sadu + kandidata a obe zaberou celou kartu.

        JOB se prepne na "running" uz TADY, ne az ve vlaknu. Prohlizec se zepta na stav
        hned po odpovedi a to je driv, nez se vlakno rozbehne — bez toho by uvidel "idle",
        usoudil, ze je hotovo, a prekreslil detail dav pred tim, nez neco vzniklo."""
        if JOB["state"] == "running":
            return self._send(409, {"err": "už běží"})
        s = os.path.basename(body.get("set") or "")
        c = os.path.basename(body.get("cand") or "")
        if not s or not c:
            return self._send(400, {"err": "chybí sada nebo kandidát"})
        if not os.path.isfile(os.path.join(GEN_DIR, s, c)):
            return self._send(404, {"err": "kandidát neexistuje"})
        try:
            strength = float(body.get("strength", 0.35))
        except (TypeError, ValueError):
            return self._send(400, {"err": "neplatná síla"})
        strength = max(0.05, min(0.9, strength))

        if p == "/api/refine":
            prompt = (body.get("prompt") or "").strip()
            if not prompt:
                return self._send(400, {"err": "chybí prompt"})
            t = threading.Thread(target=run_refine, args=(s, c, prompt, strength),
                                 daemon=True)
        else:
            kind = body.get("kind") or "walk"
            if kind not in ("walk", "idle"):
                return self._send(400, {"err": "neznámý druh animace"})
            t = threading.Thread(target=run_animate, args=(s, c, kind, strength),
                                 daemon=True)
        JOB.update(state="running", msg="startuji…", done=0, total=0, set=s, cand="")
        t.start()
        return self._send(200, {"ok": True, "set": s})


def main():
    ap = argparse.ArgumentParser(description="Sprite Studio — prohlížeč a generátor artu.")
    ap.add_argument("--port", type=int, default=8777)
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()
    url = f"http://localhost:{args.port}"
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Sprite Studio běží na {url}   (Ctrl+C ukončí)")
    if not args.no_open:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nkonec")


if __name__ == "__main__":
    main()
