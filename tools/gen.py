# Generator spritu, lokalne na tve karte. Zadny PixelLab, zadna cena za obrazek.
#
#   python tools/gen.py "energy drink creature with legs" --name endrink --n 8
#   python tools/gen.py "..." --size 32 --steps 30 --seed 7
#   python tools/gen.py --list                    # co uz je vygenerovane
#
#   python tools/gen.py "energy drink creature" --from build/gen/endrink/cand_03.png
#   python tools/gen.py "energy drink creature" --from ...png --animate walk
#
# JAK TO FUNGUJE A PROC PRAVE TAKHLE
#
# Difuzni modely jsou trenovane na 1024 px. Vygenerovat rovnou 32x32 sprite nejde — je to
# mimo jejich distribuci a vyleze sum. Vsichni proto generuji velke a chytre zmensuji, a
# kvalita toho ZMENSENI je pak dobra polovina vysledku. Postup je:
#
#   1. SDXL + pixel-art LoRA na 1024 px, na plochem pozadi
#   2. odstraneni pozadi zaplavou od rohu (model se prompt-uje na jednolite pozadi,
#      takze zaplava je spolehlivejsi i levnejsi nez dalsi neuronka)
#   3. orez na postavu a doplneni na ctverec — bez toho by prisera na spritu byla mala
#   4. zmenseni MEDIANEM po blocich, ne prumerem: prumer michá barvy sousedu a udela
#      z ostre hrany kasi, median vybere tu, ktera v bloku prevlada
#   5. sprite_cleanup.py — paleta a sum, tytez funkce, ktere cistí PixelLabu
#   6. art_check.py — znamka, tytez miry, kterymi se meri zbytek hry
#
# Kroky 5 a 6 se IMPORTUJI, nekopiruji. Kdyby generator mel vlastni kopii cisteni, rozejde
# se s tim, co dela zbytek pipeline, a "prosel u generatoru" prestane znamenat "projde u
# lintru".
#
# Vysledek jde do build/gen/<jmeno>/ a NIKDY primo do assets/. Mezi "vygenerovano" a "ve
# hre" musi byt tvoje rozhodnuti — jinak jsme zpatky u toho, ze se do hry dostane rozbity
# art a zjisti se to za mesic.
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(PROJ, "models")
OUT = os.path.join(PROJ, "build", "gen")

# Vahy patri do models/ (v .gitignore), ne do ~/.cache — projekt tak zustane prenositelny
# a je videt, co zabira misto. Musí se nastavit PRED importem diffusers.
os.environ.setdefault("HF_HOME", MODELS)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sprite_cleanup import build_palette, despeckle, remap, to_oklab   # noqa: E402
from art_check import isolated_ratio, palette_budget                   # noqa: E402

BASE_MODEL = "stabilityai/stable-diffusion-xl-base-1.0"
VAE_MODEL = "madebyollin/sdxl-vae-fp16-fix"   # fp16 SDXL VAE jinak vyrabí cerne obrazky
LORA = "nerijs/pixel-art-xl"

# Model kresli, co se mu rekne, vcetne veci, ktere sprite zabijeji: stinu pod postavou,
# gradientniho pozadi, rozmazanych okraju. Tohle je levnejsi nez to pak opravovat.
STYLE = ("pixel art sprite, flat solid magenta background, full body, centered, "
         "front view, crisp hard edges, limited palette, no anti-aliasing, no shadow")
# "magenta character" v negativu neni preklep. Rict do promptu "magenta background"
# znamena poslat model tou barvou i k subjektu — kazda vygenerovana prisera vysla ruzova.
# Klicova barva musi byt v promptu (jinak nevznikne plocha, kterou lze odstranit) a
# zaroven v negativu (jinak proteče do tela). Ty dva pokyny si neodporuji: jeden mluvi
# o pozadi, druhy o postave.
NEGATIVE = ("photo, realistic, 3d render, blurry, soft edges, gradient background, "
            "drop shadow, text, watermark, multiple characters, cropped, "
            "magenta character, pink tint, purple tint")

# Pozadi, na ktere je prompt nastaveny a ktere umi cut_background odstranit zaplavou.
# Konstanta proto, aby img2img skladalo sprite na TUTEZ barvu, jakou si model sam kresli —
# jinak by dostal vychozi obrazek s jinym pozadim, nez ho ucili malovat.
MAGENTA = (255, 0, 255)


# ------------------------------------------------------------------ generovani


def build_pipe():
    import torch
    from diffusers import AutoencoderKL, StableDiffusionXLPipeline

    if not torch.cuda.is_available():
        sys.exit("CUDA nenalezena — generovani na CPU by trvalo desitky minut na obrazek.")

    print(f"načítám model (poprvé se stáhne ~7 GB do {os.path.relpath(MODELS, PROJ)}/)…")
    vae = AutoencoderKL.from_pretrained(VAE_MODEL, torch_dtype=torch.float16)
    pipe = StableDiffusionXLPipeline.from_pretrained(
        BASE_MODEL, vae=vae, torch_dtype=torch.float16, variant="fp16", use_safetensors=True)
    pipe.load_lora_weights(LORA)
    pipe.to("cuda")
    # 12 GB VRAM staci, ale attention slicing stoji par procent rychlosti a odstrani
    # riziko, ze to spadne na OOM pri vetsim batchi.
    pipe.enable_attention_slicing()
    pipe.set_progress_bar_config(disable=True)
    return pipe


def generate(pipe, prompt, n, steps, seed, cfg=7.5):
    import torch
    full = f"{prompt}, {STYLE}"
    imgs = []
    for i in range(n):
        g = torch.Generator("cuda").manual_seed(seed + i)
        img = pipe(prompt=full, negative_prompt=NEGATIVE, num_inference_steps=steps,
                   guidance_scale=cfg, generator=g, width=1024, height=1024).images[0]
        imgs.append(img)
        print(f"  kandidát {i + 1}/{n}")
    return imgs


# ------------------------------------------------------------------ na sprite


def cut_background(img, tol=60):
    """Alfa zaplavou od vsech ctyr rohu.

    Prompt zada jednolite magentove pozadi, takze zaplava od rohu ho odstrani spolehlive
    a bez dalsiho modelu. Zaplava, ne prosty barevny klic: klic by vykousal i magentove
    pixely UVNITR prisery, zaplava se k nim nedostane."""
    rgb = img.convert("RGB")
    mark = (1, 254, 1)                      # barva, kterou model prakticky nikdy netrefi
    d = ImageDraw.floodfill
    for xy in ((0, 0), (img.width - 1, 0), (0, img.height - 1), (img.width - 1, img.height - 1)):
        try:
            d(rgb, xy, mark, thresh=tol)
        except Exception:
            pass
    a = np.array(rgb)
    bg = (np.abs(a.astype(int) - np.array(mark)).max(axis=-1) < 8)
    out = np.dstack([np.array(img.convert("RGB")),
                     np.where(bg, 0, 255).astype(np.uint8)])
    return out


def crop_to_subject(a, pad=0.04):
    """Orez na postavu a doplneni na ctverec.

    Bez tohohle sedi prisera uprostred 1024px platna jako mala skvrna a po zmenseni na
    32 px z ni zbyde deset pixelu. Ctverec proto, aby zmenseni nedeformovalo pomery."""
    m = a[..., 3] > 32
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return a
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    side = max(x1 - x0, y1 - y0) + 1
    side = int(side * (1.0 + pad * 2))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    out = np.zeros((side, side, 4), dtype=a.dtype)
    sx, sy = cx - side // 2, cy - side // 2
    for yy in range(side):
        for xx in range(side):
            py, px = sy + yy, sx + xx
            if 0 <= py < a.shape[0] and 0 <= px < a.shape[1]:
                out[yy, xx] = a[py, px]
    return out


def downscale_median(a, size):
    """Zmenseni medianem po blocich.

    Prumer (a tim i BOX/BILINEAR) michá barvy sousednich oblasti, takze z ostre hrany
    udela prechod pres tri odstiny — presne to, co pak v artu meríme jako sum. Median
    vybere barvu, ktera v bloku prevlada, cimz hrana zustane hrana. Pruhledne pixely se
    do medianu nepocitaji, jinak by okraje ztmavly smerem k pozadi."""
    h, w = a.shape[:2]
    out = np.zeros((size, size, 4), dtype=np.uint8)
    ys = np.linspace(0, h, size + 1).astype(int)
    xs = np.linspace(0, w, size + 1).astype(int)
    for j in range(size):
        for i in range(size):
            blk = a[ys[j]:ys[j + 1], xs[i]:xs[i + 1]]
            if blk.size == 0:
                continue
            op = blk[blk[..., 3] > 32]
            # Blok je neprusvitny, jen kdyz je neprusvitna jeho vetsina — jinak by
            # kolem prisery zustal vencik polovicnich pixelu.
            if len(op) * 2 < blk.shape[0] * blk.shape[1]:
                continue
            out[j, i, :3] = np.median(op[:, :3], axis=0).astype(np.uint8)
            out[j, i, 3] = 255
    return out


def clean(a, colors=16):
    """Paleta a sum — tytez funkce, ktere cistí PixelLabu (sprite_cleanup.py)."""
    from collections import Counter
    m = a[..., 3] > 32
    if not m.any():
        return a
    pool = Counter(map(tuple, a[..., :3][m]))
    pal = build_palette(pool, colors, 0.5)
    pal_lab = to_oklab(pal)
    rgb = remap(a[..., :3].astype(np.int64), m, pal, pal_lab)
    lab_of = {tuple(c): l for c, l in zip(map(tuple, pal), pal_lab)}
    rgb, _, _ = despeckle(rgb, m, lab_of, 5, 0.12)
    return np.dstack([rgb.astype(np.uint8), a[..., 3]])


# ------------------------------------------------------------------ iterace a animace
#
# ITERACE JE RODOKMEN. Jedno spusteni generatoru da sest RUZNYCH priser a ty si z nich
# jednu vybereš. Tim to ale konci — dalsi spusteni s upravenym promptem vyrobi zase sest
# uplne jinych. Iterace je opak: vezme HOTOVY sprite jako vychozi obrazek a prekresli na
# nem jen tolik, kolik dovoli strength. Vznikne DITE, ne cizi prisera.
#
# Vsechno tady proto pracuje s dvojici rodic -> dite a kazdy krok si pamatuje, z ceho
# vznikl (meta.json ve slozce). Bez toho by po peti iteracich byla ve slozce hromada
# spritu, o kterych nikdo nevi, ze spolu souvisi, a nedalo by se vratit o krok zpatky.
#
# PROC SAMOTNA ITERACE NESTACI. Difuze je nahodny proces, takze kazdy pruchod barvy trochu
# posune — model si pokazde vybere vlastni odstin. Po trech krocich uz to neni tataz
# prisera, jen podobna, i kdyz kazdy jednotlivy krok vypadal jako drobna uprava. Proti tomu
# jsou ZAMKY: lock_palette prebarvi dite na paletu rodice, lock_silhouette mu vnuti i
# rodicuv obrys. Zamky delaji z iterace ladeni misto driftu.
#
# ANIMACE stoji na tomtez: vsechny framy vznikaji z JEDNOHO zakladu, lisi se jen pose
# promptem a maji nizkou strength. Konzistence tedy neni vysledek stesti, ale konstrukce.

# Poza na FRAME, ne popis animace. Model neumi nakreslit "cyklus chuze", umi nakreslit
# jednu pozu; cyklus vznikne az tim, ze pozy jdou za sebou. Ctyri fáze proto, ze na nich
# stoji klasicky walk cycle (kontakt, prochod, kontakt, prochod) a kazdy frame navic je
# dalsi minuta generovani i dalsi sance na odchylku. Kdyz ctyri nestaci, --poses vezme
# vlastni seznam libovolne delky.
WALK_POSES = [
    "walking, left leg forward and right leg back, arms swinging",
    "walking, legs together passing under the body, body lifted slightly higher",
    "walking, right leg forward and left leg back, arms swinging the other way",
    "walking, legs together passing under the body, body dipped slightly lower",
]

# Idle se nesmi hybat skoro vubec — na 32px spritu je "nadechnuti" jeden pixel. Proto
# vsechny ctyri pozy popisuji TOTEZ stani, jen s jinym dechem.
IDLE_POSES = [
    "standing still, relaxed, arms hanging down",
    "standing still, breathing in, body stretched a little taller",
    "standing still, relaxed, arms hanging down",
    "standing still, breathing out, body squashed a little shorter",
]

POSES = {"walk": WALK_POSES, "idle": IDLE_POSES}


def build_img2img(pipe):
    """Img2img roura ze STEJNYCH vah, ktere uz drzi textova roura.

    Sdili moduly (UNet, VAE, oba text encodery i nactenou LoRu) misto toho, aby se model
    nacetl podruhe — jinak by prvni doladeni stalo dalsich 7 GB VRAM a pul minuty cekani,
    a to na karte, kde uz jedna kopie modelu sedi."""
    from diffusers import StableDiffusionXLImg2ImgPipeline as I2I

    # hasattr, a ne try/except AttributeError: from_pipe si uvnitr saha na spoustu atributu
    # a AttributeError zevnitr by se tise tvarila jako "stary diffusers" — spadlo by to az
    # o kus dal na necem uplne jinem.
    p = I2I.from_pipe(pipe) if hasattr(I2I, "from_pipe") else I2I(**pipe.components)
    p.enable_attention_slicing()
    p.set_progress_bar_config(disable=True)
    return p


def sprite_to_init(a, size=1024, margin=0.08):
    """Hotovy sprite -> vstupni obrazek pro img2img: NEAREST zvetseni na magentovem ctverci.

    NEAREST a ne bilinearni je tady to podstatne rozhodnuti. Difuze prekresluje to, co
    VIDI; kdyz dostane vyhlazenou predlohu, vrati vyhlazenou kresbu a pixel-art charakter
    je pryc uz po prvni iteraci. Tvrde ctverce naopak model precte jako styl a drzi se ho.

    Zvetsuje se CELOCISELNYM nasobkem a zbytek do ctverce se doplni pozadim. Nasobek 21.33
    by ctyri pixely delal siroke 21 a paty 22, takze i pri NEAREST by mrizka prestala byt
    pravidelna — presne v tom, co ma model precist jako styl.

    Magenta proto, ze presne tu si STYLE vynucuje jako pozadi, takze ji na vystupu zase
    odstrani cut_background touz cestou jako u generovani. Okraj kolem spritu tam je kvuli
    zaplave od rohu: sprite dotykajici se rohu by si nechal vykousnout nohu."""
    src = np.asarray(a)
    h, w = src.shape[:2]
    side = int(max(h, w)) or 1
    sq = np.zeros((side, side, 4), dtype=np.uint8)
    oy, ox = (side - h) // 2, (side - w) // 2
    sq[oy:oy + h, ox:ox + w] = src

    # Alfa se sklada na magentu rucne, ne pastou pres masku: poloprusvitne okraje by jinak
    # zustaly poloprusvitne a model by dostal predlohu s mekkym lemem, kteremu se vyhybame.
    al = sq[..., 3:4].astype(np.float64) / 255.0
    rgb = sq[..., :3].astype(np.float64) * al + np.array(MAGENTA, float) * (1.0 - al)
    im = Image.fromarray(rgb.round().astype(np.uint8), "RGB")

    zoom = int(size * (1.0 - margin * 2)) // side
    if zoom < 1:                          # predloha vetsi nez cil — neni co zvetsovat
        return im.resize((size, size), Image.NEAREST)
    im = im.resize((side * zoom, side * zoom), Image.NEAREST)
    out = Image.new("RGB", (size, size), MAGENTA)
    out.paste(im, ((size - im.width) // 2, (size - im.height) // 2))
    return out


def lock_to_palette(a, parent_rgba, colors=16):
    """Prebarvi dite paletou RODICE.

    Bez tohohle kazda iterace barvy trochu posune — model si pokazde zvoli vlastni odstin
    modre — a po tretim kroku mas jinou priseru, i kdyz kazdy jednotlivy krok vypadal jako
    drobna uprava. Paleta se pocita jen z rodice, ne ze smesi obou, aby drift nemel kudy
    vlezt; a pocita se tymiz funkcemi, kterymi ji pocita sprite_cleanup."""
    from collections import Counter
    pm = parent_rgba[..., 3] > 32
    m = a[..., 3] > 32
    if not pm.any() or not m.any():
        return a
    pal = build_palette(Counter(map(tuple, parent_rgba[..., :3][pm])), colors, 0.5)
    rgb = remap(a[..., :3].astype(np.int64), m, pal, to_oklab(pal))
    return np.dstack([rgb.astype(np.uint8), a[..., 3]])


def lock_to_silhouette(a, parent_rgba):
    """Tvrdsi zamek: silueta se prevezme od rodice, meni se jen povrch.

    Pixely, ktere rodic ma a dite ne, nemaji zadnou barvu — downscale_median necha
    pruhledny blok nulovy, takze prosté prilepeni rodicovy alfy by kolem prisery udelalo
    cerny lem. Dotahnou se proto dilataci od sousedu, a to barvou DITETE: obrys je
    rodicuv, ale povrch je to jedine, co se v tomhle rezimu smi menit."""
    from collections import Counter
    pa = parent_rgba[..., 3]
    if pa.shape != a.shape[:2]:
        pa = np.array(Image.fromarray(pa.astype(np.uint8), "L").resize(
            (a.shape[1], a.shape[0]), Image.NEAREST))
    rgb = a[..., :3].copy()
    have = a[..., 3] > 32
    need = (pa > 32) & ~have
    h, w = rgb.shape[:2]
    for _ in range(8):                       # osm dilataci staci i na tlustsiho rodice
        todo = list(zip(*np.nonzero(need)))
        if not todo:
            break
        moved = False
        for y, x in todo:
            neigh = Counter()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and have[yy, xx]:
                        neigh[tuple(rgb[yy, xx])] += 1
            if neigh:
                rgb[y, x] = neigh.most_common(1)[0][0]
                have[y, x] = True
                need[y, x] = False
                moved = True
        if not moved:
            break
    return np.dstack([rgb.astype(np.uint8), pa.astype(np.uint8)])


def _i2i_sprite(pipe_i2i, init, prompt, strength, steps, seed, size, cfg=7.5):
    """Jeden pruchod img2img a tataz cesta na sprite jako u generate, jeste BEZ palety.

    Paleta zamerne az venku: refine ji zamyká na rodice, animate na celou sadu framu. Kdyby
    ji delala uz tahle funkce, animate by kvantoval dvakrat — nejdriv po framech a pak
    spolecne — a to je horsi, nez to zni: kazdy frame si vlastni kvantizaci vybere trochu
    jiny odstin tela, spolecna paleta pak vidi dva odstiny misto jednoho a nechá oba. Tedy
    presne to blikani, kvuli kteremu spolecna paleta existuje."""
    import torch
    strength = float(min(1.0, max(0.05, strength)))
    # Diffusers denoisuje jen int(steps * strength) kroku. Pri strength 0.2 a 4 krocich je
    # to nula: model neudela nic a tise vrati predlohu. Radsi kroky pridat.
    if int(steps * strength) < 1:
        steps = int(np.ceil(1.0 / strength))
    g = torch.Generator("cuda").manual_seed(seed)
    img = pipe_i2i(prompt=f"{prompt}, {STYLE}", negative_prompt=NEGATIVE, image=init,
                   strength=strength, num_inference_steps=steps, guidance_scale=cfg,
                   generator=g).images[0]
    a = cut_background(img)
    a = crop_to_subject(a)
    return downscale_median(a, size)


def refine(pipe_i2i, base_rgba, prompt, strength=0.35, steps=28, seed=1,
           size=32, colors=16, lock_palette=True, lock_silhouette=False):
    """Z hotoveho spritu udelej jeho DITE: tataz prisera, jinak nakreslena.

    strength rika, kolik z rodice smi model prepsat: 0.2 posune detail, 0.5 uz je jina
    prisera. Skutecny pocet kroku je steps*strength, takze slaba iterace je i rychla.

    Vystup jde TOUTEZ cestou jako generate (cut_background -> crop_to_subject ->
    downscale_median -> clean). Kdyby mela iterace vlastni zmensovani, rozesla by se prvni
    generace s druhou a "doladil jsem to" by znamenalo "vypada to jinak, protoze se to
    jinak zmensilo".

    Poradi zamku a cistky neni libovolne: lock_to_palette bezi PRED clean. Po nem ma sprite
    nejvyse `colors` barev, takze build_palette uvnitr clean je vrati beze zmeny a jeho
    remap je identita — ale despeckle porad probehne, a to uz na finalnich barvach. Opacne
    poradi by sum vycistilo a hned nato barvy premlelo znovu, cimz by cast sumu vznikla
    zpatky."""
    a = _i2i_sprite(pipe_i2i, sprite_to_init(base_rgba), prompt,
                    strength, steps, seed, size)
    if lock_silhouette:
        a = lock_to_silhouette(a, base_rgba)
    if lock_palette:
        a = lock_to_palette(a, base_rgba, colors)
    return clean(a, colors)


def unify_palette(frames, colors=16):
    """Jedna paleta pres vsechny framy animace.

    Tataz oprava, kterou dela sprite_cleanup na hotovem artu, jen o krok driv: barva,
    ktera v jednom framu je a v druhem ne, se ve hre projevi jako varici se povrch. Kdyz
    vsechny framy sdileji paletu, blikani nema z ceho vzniknout.

    Despeckle az tady, a ne po jednotlivych framech: potrebuje lab_of te SPOLECNE palety,
    aby "kontrastni detail" znamenalo totez ve vsech framech. Jinak by oko v jednom framu
    prezilo a ve druhem se vsáklo do tvare — a to je zase blikani."""
    from collections import Counter
    pool = Counter()
    for a in frames:
        for c in map(tuple, a[..., :3][a[..., 3] > 32]):
            pool[c] += 1
    if not pool:
        return [a.copy() for a in frames]
    pal = build_palette(pool, colors, 0.5)
    pal_lab = to_oklab(pal)
    lab_of = {tuple(c): l for c, l in zip(map(tuple, pal), pal_lab)}
    out = []
    for a in frames:
        m = a[..., 3] > 32
        rgb = remap(a[..., :3].astype(np.int64), m, pal, pal_lab)
        rgb, _, _ = despeckle(rgb, m, lab_of, 5, 0.12)
        out.append(np.dstack([rgb.astype(np.uint8), a[..., 3]]))
    return out


def frame_anchor(a):
    """(teziste X, spodni hrana) siluety — dva body, proti kterym se frame zarovnava.

    Presne tyhle dve miry pocita i addons/td_anim_lab: teziste odhali ujizdeni do strany,
    spodni hrana poskakovani."""
    m = a[..., 3] > 32
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return None
    return float(xs.mean()), int(ys.max())


def shift_frame(a, dx, dy):
    """Posun o cele pixely s doplnenim PRUHLEDNOSTI.

    np.roll sam o sobe wrapuje: noha, ktera vyjede vlevo, vleze zpatky zprava a v animaci
    problikne u opacneho okraje. Zarolovany pruh se proto vynuluje — nula je v RGBA
    (0,0,0,0), tedy pruhledno."""
    h, w = a.shape[:2]
    if abs(dx) >= w or abs(dy) >= h:
        return np.zeros_like(a)          # cely obsah by stejne vyjel z platna
    out = np.roll(np.roll(a, dy, axis=0), dx, axis=1)
    if dy > 0:
        out[:dy] = 0
    elif dy < 0:
        out[dy:] = 0
    if dx > 0:
        out[:, :dx] = 0
    elif dx < 0:
        out[:, dx:] = 0
    return out


def align_frames(frames):
    """Zarovnani framu na median — tataz matematika jako "Srovnat nohy" a "Srovnat střed"
    v Animation Labu, jen davkove a rovnou pri vzniku.

    Kazdy frame vznikl vlastnim orezem na vlastni obalku, takze prisera, ktera pri chuzi
    rozpazi, je v tom framu sirsi a cely sprite se orezem posune. Ve hre to vypada, ze
    prisera ujizdi do strany a poskakuje, i kdyz je kazdy frame sam o sobe v poradku.

    Median a ne prvni frame proto, ze prave prvni frame muze byt ten ukroceny — pak by se
    podle nej srovnalo spatne vsechno ostatni.

    Obe reference berou DOLNI median, tedy hodnotu NEKTEREHO z framu, ne prumer dvou
    prostrednich (to dela np.median u sude sady). Duvod je zaokrouhlovani: posouva se o
    cele pixely, takze pri referenci na x.5 vyjde pulka posunu na +0.5 a pulka na -0.5 — a
    Python zaokrouhluje .5 k sudemu cislu, takze cast framu skonci o pixel vedle druhe.
    Reference, kterou nektery frame trefuje presne, tuhle past nema: sada, ktera se lisi
    jen posunutim, se pak srovna na nulovy rozptyl. Tataz uvaha je v td_anim_lab (base_ref).

    Prazdne framy se do medianu nepocitaji a nehybe se s nimi — jejich nulova spodni hrana
    neni misto, kde prisera stoji."""
    anchors = [frame_anchor(a) for a in frames]
    good = [t for t in anchors if t is not None]
    if not good:
        return [a.copy() for a in frames]
    mid = len(good) // 2
    mcx = sorted(c for c, _ in good)[mid]
    mbase = sorted(b for _, b in good)[mid]
    out = []
    for a, t in zip(frames, anchors):
        if t is None:
            out.append(a.copy())
            continue
        out.append(shift_frame(a, int(round(mcx - t[0])), int(mbase - t[1])))
    return out


def animate(pipe_i2i, base_rgba, pose_prompts, strength=0.3, steps=28, seed=1,
            size=32, colors=16, on_frame=None):
    """Framy animace z JEDNOHO zakladu, kazdy s vlastni pozou.

    Konzistence tim neni odhad ani stesti, ale konstrukce: vsechny framy maji stejneho
    rodice a stejne nizkou silu, takze se od sebe nemuzou lisit vic, nez kolik ta sila
    dovoli. Generovat framy nezavisle (osmkrat text2img) vyrobi osm ruznych priser —
    presne ten "zprzeny" vzhled, ktery uz pak nikdo nedozarovna.

    Stejny seed pro vsechny framy, a to schvalne. Pri img2img urcuje seed sum primichany
    do predlohy, takze stejny seed znamena, ze se framy lisi JEN pozou. Seed po framech by
    pridal jeste nahodnou variaci povrchu — presne to kmitani, ktere pak sprite_cleanup
    meri jako blikajici pixely.

    pose_prompts jsou HOTOVE prompty, ne pripony. Slozit "<prisera>, <poza>" umi jen
    volajici — jen on vi, jestli ma popis prisery stat pred pozou nebo za ni.

    Palety se tady nezamykaji na rodice, protoze framy dostanou spolecnou paletu az
    nakonec: zamek na rodice by kazdy frame tahl jinam nez ostatni."""
    init = sprite_to_init(base_rgba)
    frames = []
    for i, pose in enumerate(pose_prompts):
        frames.append(_i2i_sprite(pipe_i2i, init, pose, strength, steps, seed, size))
        if on_frame:
            on_frame(i + 1, len(pose_prompts))
    return align_frames(unify_palette(frames, colors))


# ------------------------------------------------------------------ znamkovani


def score(a):
    """Znamka podle tychz mer, kterymi art_check meri zbytek hry.

    Nehodnoti, jestli je to hezke — to skript neumi a umet nebude. Hodnoti, jestli je to
    POUZITELNY pixel art: kolik barev, kolik sumu, kolik plochy prisera zabira."""
    m = a[..., 3] > 32
    opaque = int(m.sum())
    if opaque < 20:
        return {"grade": 0.0, "cols": 0, "iso": 1.0, "fill": 0.0, "note": "prázdné"}
    cols = len({tuple(c) for c in a[..., :3][m]})
    iso = isolated_ratio(a)
    fill = opaque / float(a.shape[0] * a.shape[1])
    budget = palette_budget(opaque)

    g_pal = max(0.0, 1.0 - max(0.0, cols - budget) / float(budget))
    g_iso = max(0.0, 1.0 - max(0.0, iso - 0.15) / 0.35)
    # Prisera ma zabirat pres pul spritu; pod tim je to bod uprostred prazdna, nad 85 %
    # se dotyka okraju a orizne se jí hlava.
    g_fill = 1.0 - min(1.0, abs(fill - 0.55) / 0.45)
    grade = round(10.0 * (0.4 * g_pal + 0.4 * g_iso + 0.2 * g_fill), 1)
    note = []
    if cols > budget:
        note.append(f"{cols} barev (rozpočet {budget})")
    if iso > 0.30:
        note.append(f"{iso * 100:.0f} % šumu")
    if fill < 0.25:
        note.append("moc malá")
    return {"grade": grade, "cols": cols, "iso": iso, "fill": fill,
            "note": ", ".join(note) or "ok"}


def contact_sheet(items, path, zoom=6, pad=8, bg=(24, 24, 30)):
    if not items:
        return
    from PIL import ImageDraw as D
    tw = items[0][0].shape[1] * zoom
    cols = min(4, len(items))
    rows = (len(items) + cols - 1) // cols
    W = cols * (tw + pad) + pad
    H = rows * (tw + pad + 18) + pad
    sheet = Image.new("RGB", (W, H), bg)
    dr = D.Draw(sheet)
    for k, (a, sc, name) in enumerate(items):
        r, c = divmod(k, cols)
        x = pad + c * (tw + pad)
        y = pad + r * (tw + pad + 18)
        im = Image.fromarray(a, "RGBA").resize((tw, tw), Image.NEAREST)
        sheet.paste(im, (x, y), im)
        dr.text((x, y + tw + 3), f"{name}  {sc['grade']}/10  {sc['note']}",
                fill=(200, 200, 212))
    sheet.save(path)


# ------------------------------------------------------------------ main


def main():
    ap = argparse.ArgumentParser(description="Lokální generátor pixel-art spritů.")
    ap.add_argument("prompt", nargs="?", help="co nakreslit (anglicky)")
    ap.add_argument("--name", help="jméno sady (složka v build/gen/)")
    ap.add_argument("--n", type=int, default=6, help="kolik kandidátů (default 6)")
    ap.add_argument("--size", type=int, default=32, help="cílová velikost spritu (default 32)")
    ap.add_argument("--colors", type=int, default=16, help="barev v paletě (default 16)")
    ap.add_argument("--steps", type=int, default=28)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keep-raw", action="store_true", help="ulož i renderu 1024 px")
    ap.add_argument("--list", action="store_true", help="vypiš, co už je vygenerované")
    # dest="src", protože `from` je v Pythonu klíčové slovo a args.from by byla chyba
    # syntaxe — na attribut by se pak dalo dostat jen přes getattr.
    ap.add_argument("--from", dest="src", metavar="PNG",
                    help="dolaď hotový sprite místo generování od nuly (img2img)")
    ap.add_argument("--strength", type=float, default=0.35, metavar="F",
                    help="kolik z původního spritu smí model přepsat: 0.2 = retuš, "
                         "0.5 = už jiná příšera (default 0.35)")
    ap.add_argument("--animate", choices=sorted(POSES), metavar="DRUH",
                    help="místo kandidátů vyrob animaci ze --from spritu (walk, idle)")
    ap.add_argument("--poses", metavar="A;B;C",
                    help="vlastní pózy pro animaci, oddělené středníkem (přebijí --animate)")
    args = ap.parse_args()

    if args.list:
        if not os.path.isdir(OUT):
            print("zatím nic")
            return
        for d in sorted(os.listdir(OUT)):
            fs = os.listdir(os.path.join(OUT, d))
            # Animace se pocitaji zvlast: sada osmi framu chuze neni "osm kandidatu",
            # ze kterych se vybira jeden, ale jedna vec, ktera drzi pohromade.
            nc = len([f for f in fs if f.startswith("cand_")])
            nf = len([f for f in fs if f.startswith("frame_")])
            what = f"{nc} kandidátů" if nc else ""
            what += (", " if what and nf else "") + (f"{nf} framů animace" if nf else "")
            print(f"  {d:<30}{what or '—'}")
        return

    # Pozy urcuji, jestli se dela animace. --poses prebiji --animate, protoze rucne psany
    # seznam je vzdycky konkretnejsi zamer nez volba z nabidky.
    poses = None
    if args.poses:
        poses = [p.strip() for p in args.poses.split(";") if p.strip()]
    elif args.animate:
        poses = POSES[args.animate]

    if poses and not args.src:
        sys.exit("Animace potřebuje základ: --from <sprite.png>.\n"
                 "Framy vznikají z JEDNOHO spritu — bez něj by každý frame byla jiná "
                 "příšera.")

    if not args.prompt:
        sys.exit("Chybí prompt. Příklady:\n"
                 '  python tools/gen.py "energy drink creature with legs" --name endrink\n'
                 '  python tools/gen.py "energy drink creature" --from build/gen/x/cand_03.png')

    if args.src:
        if not os.path.isfile(args.src):
            sys.exit(f"Sprite neexistuje: {args.src}")
        parent = np.array(Image.open(args.src).convert("RGBA"))
        # Vychozi jmeno nese rodokmen: <sada rodice>_<soubor rodice>_<co se delo>. Dite se
        # tak nikdy netrefi do slozky rodice a je z nej videt, z ceho vzniklo.
        stem = os.path.splitext(os.path.basename(args.src))[0]
        pset = os.path.basename(os.path.dirname(os.path.abspath(args.src)))
        name = args.name or f"{pset}_{stem}_{args.animate or 'refine'}"
    else:
        parent = None
        name = args.name or "".join(ch if ch.isalnum() else "_" for ch in args.prompt)[:32]

    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)

    # scores se klice SOUBOREM, ne poradim v items: items se u kandidatu jeste seradi podle
    # znamky, takze "treti v seznamu" uz neznamena cand_03.png.
    items, scores = [], {}

    def keep(a, fn, label):
        sc = score(a)
        Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
        scores[fn] = sc
        items.append((a, sc, label))

    if parent is None:
        pipe = build_pipe()
        print(f'generuji {args.n}× „{args.prompt}"')
        raws = generate(pipe, args.prompt, args.n, args.steps, args.seed)
        for i, img in enumerate(raws, 1):
            if args.keep_raw:
                img.save(os.path.join(d, f"raw_{i:02d}.png"))
            a = cut_background(img)
            a = crop_to_subject(a)
            a = downscale_median(a, args.size)
            keep(clean(a, args.colors), f"cand_{i:02d}.png", f"#{i}")
    else:
        pipe2 = build_img2img(build_pipe())
        if poses:
            print(f"animace {len(poses)}× z {args.src}")
            frames = animate(pipe2, parent, [f"{args.prompt}, {p}" for p in poses],
                             strength=args.strength, steps=args.steps, seed=args.seed,
                             size=args.size, colors=args.colors,
                             on_frame=lambda i, n: print(f"  frame {i}/{n}"))
            for i, a in enumerate(frames, 1):
                keep(a, f"frame_{i:02d}.png", f"f{i}")
        else:
            print(f"dolaďuji {args.n}× z {args.src} (síla {args.strength})")
            for i in range(1, args.n + 1):
                a = refine(pipe2, parent, args.prompt, strength=args.strength,
                           steps=args.steps, seed=args.seed + i - 1, size=args.size,
                           colors=args.colors)
                keep(a, f"cand_{i:02d}.png", f"#{i}")
                print(f"  kandidát {i}/{args.n}")

    # Framy animace se NESERAZUJI podle znamky — poradi framu JE ta animace. U kandidatu je
    # to naopak to hlavni, co chces videt.
    if not poses:
        items.sort(key=lambda t: -t[1]["grade"])
    contact_sheet(items, os.path.join(d, "_prehled.png"))

    # meta.json cte i Sprite Studio (gen_ui.py). Rodic a sila jsou tu proto, ze bez nich je
    # rodokmen jen v hlave toho, kdo prikaz psal.
    json.dump({"prompt": args.prompt, "parent": args.src or None,
               "strength": args.strength if args.src else None,
               "poses": poses or [], "scores": scores},
              open(os.path.join(d, "meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    head = "frame" if poses else "kandidát"
    print(f"\n{head:<10}{'známka':>8}{'barev':>7}{'šum':>7}{'plocha':>8}  poznámka")
    for a, sc, nm in items:
        print(f"{nm:<10}{sc['grade']:>8}{sc['cols']:>7}{sc['iso'] * 100:>6.0f}%"
              f"{sc['fill'] * 100:>7.0f}%  {sc['note']}")
    if poses:
        print("\nframy jsou v pořadí cyklu — známka je tu jen na kontrolu, ne na výběr.")
    else:
        best = items[0]
        print(f"\nnejlepší: {best[2]} ({best[1]['grade']}/10)")
    print(f"výstup:   {os.path.relpath(d, PROJ)}  (_prehled.png = všichni vedle sebe)")
    print("do hry to nejde samo — až tohle projdeš, nainstaluje se to zvlášť.")


if __name__ == "__main__":
    main()
