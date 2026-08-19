# Krok zpet pro art: snimek pred zapisem, navrat po zapisu.
#
#   python tools/art_undo.py list                       # co mam ulozene
#   python tools/art_undo.py show 7                     # co je uvnitr snimku 7
#   python tools/art_undo.py restore 7                  # ZKUSEBNE: co by se stalo
#   python tools/art_undo.py restore 7 --apply          # skutecne vrat
#   python tools/art_undo.py snapshot assets/towers -l rucni-uprava
#   python tools/art_undo.py prune --keep 20 --apply    # uklid stareho
#
# PROC TENHLE NASTROJ EXISTUJE
#
# Prace s artem je destruktivni. sprite_cleanup.py --apply prepise 432 PNG naraz a
# kdyz ty soubory nejsou v gitu, neexistuje nic, co by je vratilo. Vysledek je, ze
# se clovek boji sahnout na vlastni art - a to je nejhorsi mozny stav, protoze
# nedelanim se art nezlepsi.
#
# Tenhle skript je zachranna sit, ne verzovaci system. Git je porad ta spravna
# historie; tohle resi tech par minut mezi "pustil jsem nastroj" a "commitnul jsem
# vysledek", kdy git jeste nic nevi.
#
# TRI PRAVIDLA, KTERA TENHLE NASTROJ NEPORUSUJE
#
# 1. NIC SE NEZAPISE BEZ --apply. restore i prune umi ukazat, co by udelaly, a to
#    je jejich vychozi chovani. Nastroj, ktery ma delat bezpeci, nesmi prekvapit.
#
# 2. ZAPISUJE SE JEN DOVNITR PROJEKTU. Kazda cesta z manifestu se pred zapisem
#    overi, ze po slozeni a normalizaci porad lezi uvnitr slozky projektu. Manifest
#    je obycejny JSON, ktery muze nekdo rucne upravit - "C:\Windows\..." nebo
#    "../../.." z nej neprojde.
#
# 3. OBSAH SE OVERUJE HASHEM. U kazdeho souboru se pri snimku ulozi sha256. Pred
#    zapisem se zaloha precte a hash se prepocita. Kdyz nesedi, soubor se PRESKOCI
#    a nahlasi - lepsi nevratit nic nez vratit rozbity PNG.
#
# CO SE NEKOPIRUJE (a proc je to bezpecne)
#
# Soubor, jehoz presny obsah uz lezi v posledním commitu, se nekopiruje. Misto nej
# si manifest poznamena git blob hash a restore ho vytahne pres "git cat-file blob".
#
# Overuje se to spocitanim git blob hashe primo z bajtu souboru a porovnanim proti
# "git ls-tree -r HEAD". To je silnejsi test nez "git status rika, ze je cisty":
# hashuje se to, co je na disku V TU CHVILI, takze mezi kontrolou a snimkem neni
# okno, ve kterem by se soubor mohl zmenit. Kdyz se hashe lisi o jediny bajt,
# soubor se normalne zkopiruje.
#
# Na 432 nezaverzovanych PNG tohle neusetri nic (a spravne - prave ty je potreba
# kopirovat). Usetri to na slozkach, kde je vetsina artu davno commitnuta.
#
# NOVE SOUBORY SE SAME OD SEBE NEMAZOU
#
# Kdyz snimek dostane slozku, zapamatuje si i to, ktere soubory v ni tehdy byly.
# Pri navratu tak pozna soubory, ktere mezitim pribyly. NEMAZE je - jen je vypise.
# Zbytecny soubor navic je otrava, smazany soubor je ztrata dat, a tenhle nastroj
# existuje kvuli tomu druhemu. Kdo chce ciste vrceni, rekne si o --delete-new.
import argparse
import contextlib
import hashlib
import json
import ntpath
import os
import shutil
import subprocess
import sys
import time

# Windows konzole jede v cp1250 a diakritika by se rozsypala na necitelne znaky.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(PROJ, "build", "undo")

# build/ je v .gitignore, takze zalohy nezanaseji repozitar ani diffy.
# Kdyby to nekdo prehodil, snimky by se zacaly commitovat - odtud ta kontrola nize.

# Cteni po 1 MB: PNG v tomhle projektu maji jednotky kB, ale manifest muze chytit
# i atlas nebo .tres, a nacitat cely soubor do pameti neni potreba.
CHUNK = 1 << 20

# Kolik znaku labelu se vejde do jmena slozky. Zbytek se urizne - jmeno slozky je
# jen pro cloveka, pravda je v manifest.json.
LABEL_MAX = 40

MANIFEST = "manifest.json"
FILES_DIR = "files"


# ---------------------------------------------------------------- pomocne veci

def _rel(path):
    """Cesta vuci korenu projektu, vzdy s lomitkem dopredu.

    V manifestu musi byt cesty prenositelne a hlavne porovnatelne. Windows umi
    obe lomitka, takze bez tohohle by se stejny soubor jednou ulozil jako
    "assets/x.png" a podruhe jako "assets\\x.png" a porovnani by selhalo.
    """
    p = os.path.relpath(os.path.abspath(path), PROJ)
    return p.replace(os.sep, "/")


def _safe_abs(rel):
    """Z relativni cesty v manifestu udelej absolutni - nebo None, kdyz utika ven.

    Tohle je pravidlo c. 2 z hlavicky. Manifest je JSON na disku, tedy vstup,
    kteremu se neveri. normpath slozi ".." dohromady, takze "assets/../../evil"
    skonci mimo PROJ a kontrola nize ho zahodi. normcase kvuli tomu, ze na Windows
    "C:\\Users" a "c:\\users" je totez misto.
    """
    if not rel or os.path.isabs(rel) or ntpath.splitdrive(rel)[0]:
        return None
    p = os.path.normpath(os.path.join(PROJ, rel.replace("/", os.sep)))
    if os.path.normcase(p + os.sep).startswith(os.path.normcase(PROJ + os.sep)):
        return p
    return None


def _hashes(path):
    """(sha256, git_blob_sha1, velikost) na jedno precteni souboru.

    Oba hashe naraz proto, ze drahe je cteni z disku, ne hashovani. Git blob hash
    je sha1 z hlavicky "blob <delka>\\0" a obsahu - presne to, co si git uklada,
    takze se da porovnat s vystupem git ls-tree bez volani gitu.
    """
    h256 = hashlib.sha256()
    size = os.path.getsize(path)
    h1 = hashlib.sha1(b"blob %d\0" % size)
    with open(path, "rb") as f:
        while True:
            chunk = f.read(CHUNK)
            if not chunk:
                break
            h256.update(chunk)
            h1.update(chunk)
    return h256.hexdigest(), h1.hexdigest(), size


def _sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def _git(args, binary=False):
    """Zavolej git a vrat vystup, nebo None kdyz to z jakehokoliv duvodu nevyslo.

    Git je tady vylepseni, ne zavislost. Kdyz chybi, neni to repozitar nebo jeste
    neni zadny commit, nastroj proste zkopiruje uplne vsechno - to je porad spravna
    odpoved, jen zabere vic mista.
    """
    try:
        r = subprocess.run(["git"] + args, cwd=PROJ, capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def _head_blobs():
    """Mapa cesta -> blob sha pro posledni commit.

    ls-tree misto "git status --porcelain" zamerne. status odpovida na otazku
    "je to spinave", ale s odpovedi se pak musi dopocitavat, jestli je obsah
    doopravdy v commitu (soubor muze byt jen pridany do indexu a pak by ho
    uklid gitu mohl zahodit). ls-tree odpovi rovnou na tu otazku, na ktere
    zalezi: co presne je v HEAD.

    -z proto, ze git jinak cesty s diakritikou obali uvozovkami a odescapuje -
    a tenhle projekt ma soubory jako "kolac.png". Format radku je
    "<mode> <typ> <sha>\\t<cesta>".
    """
    out = _git(["ls-tree", "-r", "-z", "HEAD"])
    if not out:
        return {}
    blobs = {}
    for rec in out.split("\0"):
        if not rec:
            continue
        meta, _, path = rec.partition("\t")
        bits = meta.split()
        if len(bits) != 3 or bits[1] != "blob":
            continue
        # 120000 je symlink, 160000 submodul - obsah takoveho "souboru" neni to,
        # co je na disku, takze pro nas ten zkratka neni v gitu.
        if bits[0] not in ("100644", "100755"):
            continue
        blobs[path] = bits[2]
    return blobs


def _sanitize(label):
    """Z labelu udelej neco, co smi byt jmenem slozky.

    Label muze prijit odkudkoliv (i z argv), takze z nej musi vypadnout lomitka
    a tecky, jinak by "../../" v labelu poslal snimek mimo build/undo.
    """
    out = []
    for ch in (label or "snapshot").strip().lower():
        if ch.isalnum() and ch.isascii():
            out.append(ch)
        elif ch in " _-." and out and out[-1] != "-":
            out.append("-")
    name = "".join(out).strip("-")[:LABEL_MAX].strip("-")
    return name or "snapshot"


def _human(n):
    for unit in ("B", "kB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0


def _snapshot_dirs():
    """Vsechny snimky na disku jako (id, cesta), serazene podle id."""
    if not os.path.isdir(STORE):
        return []
    found = []
    for name in os.listdir(STORE):
        seq, _, _rest = name.partition("-")
        if not seq.isdigit():
            continue
        d = os.path.join(STORE, name)
        if os.path.isfile(os.path.join(d, MANIFEST)):
            found.append((int(seq), d))
    found.sort()
    return found


def _dir_for(snap_id):
    for sid, d in _snapshot_dirs():
        if sid == snap_id:
            return d
    return None


def _load(snap_id):
    d = _dir_for(snap_id)
    if d is None:
        raise KeyError(f"snímek {snap_id} neexistuje")
    with open(os.path.join(d, MANIFEST), "r", encoding="utf-8") as f:
        return d, json.load(f)


def _iter_files(root):
    """Vsechny soubory pod slozkou, jako relativni cesty vuci projektu.

    Zalohovat zalohy nema smysl a kazdy dalsi snimek build/ by byl dvakrat vetsi
    nez ten predchozi. .git ma vlastni historii, __pycache__ se vyrobi znovu.
    """
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "__pycache__")
                       and os.path.normcase(os.path.join(dirpath, d))
                       != os.path.normcase(STORE)]
        for fn in filenames:
            yield _rel(os.path.join(dirpath, fn)), os.path.join(dirpath, fn)


def _walk(paths):
    """Rozbal seznam cest na konkretni soubory + zapamatuj si prochazene slozky.

    Slozka se rozbaluje rekurzivne, protoze to je ergonomicky ta spravna vec:
    snapshot(["assets/distractions"]) vezme i .import soubory vedle PNG, a prave
    ty jsou u Godotu ta cast, na kterou clovek zapomene.

    Vraci (soubory, chybejici, koreny). "chybejici" je cesta, kterou volajici
    vyjmenoval, ale zatim neexistuje - typicky soubor, ktery nastroj teprve
    vyrobi. Ma smysl si ji zapsat: navrat pak vi, ze tam predtim nic nebylo.
    """
    files, missing, roots = {}, [], []
    for raw in paths:
        p = os.path.abspath(os.path.join(PROJ, raw))
        if os.path.isdir(p):
            roots.append(_rel(p))
            for rel, fp in _iter_files(p):
                files[rel] = fp
        elif os.path.isfile(p):
            files[_rel(p)] = p
        else:
            missing.append(_rel(p))
    return files, missing, roots


def _check_inside_project(files):
    """Cesta mimo projekt se do snimku nedostane.

    Duvod je symetrie s restore: kdyby snapshot pobral C:\\neco\\jineho, restore by
    to odmitl zapsat zpatky (pravidlo c. 2) a clovek by mel zalohu, kterou nejde
    pouzit. Lepsi rict to hned pri snimku.
    """
    bad = [r for r in files if _safe_abs(r) is None]
    if bad:
        raise ValueError("mimo projekt, nelze zálohovat: " + ", ".join(sorted(bad)[:5]))


# ---------------------------------------------------------------- verejne API

def snapshot(paths, label, quiet=False):
    """Uloz stav zadanych souboru a vrat id snimku.

    paths muze obsahovat soubory i slozky, absolutne i relativne vuci projektu.
    Vola se PRED zapisem - snimek je to, k cemu se pak da vratit.
    """
    if isinstance(paths, (str, bytes, os.PathLike)):
        paths = [paths]
    files, missing, roots = _walk(paths)
    _check_inside_project(files)
    for rel in missing:
        if _safe_abs(rel) is None:
            raise ValueError(f"mimo projekt, nelze sledovat: {rel}")

    head = _head_blobs()

    entries = []
    copied_bytes = 0
    skipped_git = 0
    # Kopiruje se do docasneho jmena a az uplne nakonec se prejmenuje. Kdyby to
    # spadlo v pulce (nebo to nekdo prerusil), zbyde slozka s prefixem "_wip-",
    # kterou list ani restore nevidi - misto snimku, ktery vypada uplny a neni.
    existing = _snapshot_dirs()
    seq = (existing[-1][0] + 1) if existing else 1
    name = f"{seq:04d}-{_sanitize(label)}"
    wip = os.path.join(STORE, "_wip-" + name)
    final = os.path.join(STORE, name)
    if os.path.exists(wip):
        shutil.rmtree(wip, ignore_errors=True)
    os.makedirs(wip, exist_ok=True)

    try:
        for rel in sorted(files):
            src = files[rel]
            try:
                sha, blob, size = _hashes(src)
            except OSError as e:
                raise OSError(f"nelze přečíst {rel}: {e}") from e

            if head.get(rel) == blob:
                # Presne tenhle obsah je v HEAD - git ho vrati kdykoliv.
                entries.append({"path": rel, "state": "git", "sha256": sha,
                                "size": size, "blob": blob})
                skipped_git += 1
                continue

            store_rel = FILES_DIR + "/" + rel
            dst = os.path.join(wip, store_rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            entries.append({"path": rel, "state": "file", "sha256": sha,
                            "size": size, "store": store_rel})
            copied_bytes += size

        for rel in sorted(missing):
            entries.append({"path": rel, "state": "absent"})

        man = {
            "id": seq,
            "label": label,
            "created": time.strftime("%Y-%m-%d %H:%M:%S"),
            "created_unix": int(time.time()),
            "git_head": (_git(["rev-parse", "HEAD"]) or "").strip() or None,
            "roots": sorted(set(roots)),
            "known": sorted(files) if roots else [],
            "entries": entries,
        }
        with open(os.path.join(wip, MANIFEST), "w", encoding="utf-8") as f:
            json.dump(man, f, ensure_ascii=False, indent=1)
        os.replace(wip, final)
    except BaseException:
        shutil.rmtree(wip, ignore_errors=True)
        raise

    if not quiet:
        bits = [f"{len(entries)} položek"]
        if skipped_git:
            bits.append(f"{skipped_git} už v gitu (nekopíruje se)")
        if missing:
            bits.append(f"{len(missing)} zatím neexistuje")
        print(f"snímek {seq} · {label} · " + ", ".join(bits)
              + f" · {_human(copied_bytes)} na disku")
    return seq


def list_snapshots():
    """Prehled snimku, od nejstarsiho po nejnovejsi."""
    out = []
    for sid, d in _snapshot_dirs():
        try:
            with open(os.path.join(d, MANIFEST), "r", encoding="utf-8") as f:
                man = json.load(f)
        except (OSError, ValueError):
            continue
        size = 0
        for dirpath, _dn, filenames in os.walk(d):
            for fn in filenames:
                try:
                    size += os.path.getsize(os.path.join(dirpath, fn))
                except OSError:
                    pass
        out.append({
            "id": sid,
            "label": man.get("label", ""),
            "kdy": man.get("created", ""),
            "souboru": len(man.get("entries", [])),
            "velikost": size,
        })
    return out


def _plan(snap_dir, man):
    """Spocitej, co by restore udelal. Nic nezapisuje.

    Rozdeleni na kategorie je cely smysl zkusebniho behu - clovek potrebuje videt
    rozdil mezi "vrati se 432 souboru" a "vrati se 3 soubory", protoze to prvni
    znamena, ze pousti spravny snimek, a to druhe, ze si spletl cislo.
    """
    same, change, gone, new, broken = [], [], [], [], []
    for e in man.get("entries", []):
        rel = e.get("path", "")
        dst = _safe_abs(rel)
        if dst is None:
            broken.append((rel, "cesta míří mimo projekt"))
            continue

        if e.get("state") == "absent":
            if os.path.exists(dst):
                new.append(rel)
            continue

        # Zdroj obsahu overit driv, nez se kdekoliv sahne na cilovy soubor.
        if e.get("state") == "git":
            if not e.get("blob"):
                broken.append((rel, "chybí blob hash"))
                continue
        else:
            store = e.get("store") or ""
            sp = os.path.join(snap_dir, store.replace("/", os.sep))
            if not store.startswith(FILES_DIR + "/") or not os.path.isfile(sp):
                broken.append((rel, "záloha souboru chybí"))
                continue

        if os.path.isfile(dst):
            try:
                cur, _blob, _size = _hashes(dst)
            except OSError as ex:
                broken.append((rel, f"nelze přečíst: {ex}"))
                continue
            if cur == e.get("sha256"):
                same.append(rel)
            else:
                change.append(e)
        else:
            gone.append(e)

    # Soubory, ktere ve sledovanych slozkach pribyly az PO snimku. Manifest si pri
    # snimku ulozil seznam toho, co ve slozce tehdy bylo ("known"), takze rozdil
    # proti dnesku jsou prave pribyle soubory. Bez tohohle by se po navratu michal
    # stary art s vystupem spadleho nastroje a nikdo by nepoznal, co je co.
    known = set(man.get("known") or ())
    seen = {e.get("path") for e in man.get("entries", [])}
    for root in man.get("roots") or ():
        base = _safe_abs(root)
        if base is None or not os.path.isdir(base):
            continue
        for rel, _fp in _iter_files(base):
            if rel not in known and rel not in seen:
                new.append(rel)
    new.sort()
    return same, change, gone, new, broken


def _content_for(snap_dir, e):
    """Bajty, ktere se maji zapsat - overene proti hashi ze snimku.

    Pravidlo c. 3. Zaloha muze byt poskozena (spadly disk, nekdo si hral ve
    slozce, git blob zmizel po agresivnim uklidu). Vratit v takovem pripade
    poskozeny PNG by bylo horsi nez nevratit nic, protoze by to vypadalo, ze
    se navrat povedl.
    """
    if e.get("state") == "git":
        data = _git(["cat-file", "blob", e["blob"]], binary=True)
        if data is None:
            return None, "git blob už neexistuje"
    else:
        sp = os.path.join(snap_dir, e["store"].replace("/", os.sep))
        try:
            with open(sp, "rb") as f:
                data = f.read()
        except OSError as ex:
            return None, f"zálohu nelze přečíst: {ex}"
    if _sha256_bytes(data) != e.get("sha256"):
        return None, "hash zálohy nesedí, soubor je poškozený"
    return data, None


def restore(snap_id, dry_run=True, delete_new=False, quiet=False):
    """Vrat soubory do stavu ze snimku.

    Vychozi chovani je ZKUSEBNI: jen spocita a vypise, co by se stalo. Skutecny
    zapis az s dry_run=False. Vraci pocet skutecne (nebo pri zkusebnim behu
    potencialne) zmenenych souboru.
    """
    snap_dir, man = _load(snap_id)
    same, change, gone, new, broken = _plan(snap_dir, man)
    todo = change + gone

    if not quiet:
        print(f"snímek {man.get('id')} · {man.get('label')} · {man.get('created')}")
        print(f"  vrátit zpět   {len(todo):>5}  "
              f"({len(change)} změněných, {len(gone)} chybějících)")
        print(f"  beze změn     {len(same):>5}")
        if new:
            akce = "smažou se" if delete_new else "zůstanou, --delete-new je smaže"
            print(f"  nové soubory  {len(new):>5}  ({akce})")
            for rel in new[:5]:
                print(f"      + {rel}")
            if len(new) > 5:
                print(f"      … a dalších {len(new) - 5}")
        if broken:
            print(f"  NELZE VRÁTIT  {len(broken):>5}")
            for rel, why in broken[:5]:
                print(f"      ! {rel}: {why}")
            if len(broken) > 5:
                print(f"      … a dalších {len(broken) - 5}")

    if dry_run:
        if not quiet:
            print("\nzkušební běh — nic se nezapsalo.")
            print(f"  skutečně vrátit:  python tools/art_undo.py restore {snap_id} --apply")
        return len(todo)

    done, failed = 0, []
    for e in todo:
        dst = _safe_abs(e["path"])
        if dst is None:
            failed.append((e["path"], "cesta míří mimo projekt"))
            continue
        data, why = _content_for(snap_dir, e)
        if data is None:
            failed.append((e["path"], why))
            continue
        try:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            # Zapis pres docasny soubor: kdyby to spadlo uprostred, na puvodnim
            # miste zustane stara verze misto pulky nove.
            tmp = dst + ".undo-tmp"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, dst)
            done += 1
        except OSError as ex:
            failed.append((e["path"], str(ex)))

    removed = 0
    if delete_new:
        for rel in new:
            dst = _safe_abs(rel)
            if dst and os.path.isfile(dst):
                try:
                    os.remove(dst)
                    removed += 1
                except OSError as ex:
                    failed.append((rel, str(ex)))

    if not quiet:
        print(f"\nvráceno {done} souborů" + (f", smazáno {removed}" if delete_new else ""))
        if failed:
            print(f"NEPODAŘILO SE {len(failed)}:")
            for rel, why in failed[:10]:
                print(f"  ! {rel}: {why}")
    return done


def prune(keep=20, dry_run=True, quiet=False):
    """Nech si poslednich `keep` snimku, starsi smaz.

    Taky zkusebni ve vychozim stavu - je to sice jen uklid v build/, ale je to
    uklid v tom jedinem miste, ktere umi vratit art zpatky.
    """
    snaps = _snapshot_dirs()
    drop = snaps[:-keep] if keep > 0 else snaps
    if not quiet:
        print(f"snímků {len(snaps)}, ponechat {min(keep, len(snaps))}, smazat {len(drop)}")
    freed = 0
    for sid, d in drop:
        size = sum(os.path.getsize(os.path.join(dp, fn))
                   for dp, _dn, fns in os.walk(d) for fn in fns
                   if os.path.exists(os.path.join(dp, fn)))
        freed += size
        if not quiet:
            print(f"  {'smazat' if dry_run else 'mažu'} {sid:>4}  {os.path.basename(d)}  {_human(size)}")
        if not dry_run:
            shutil.rmtree(d, ignore_errors=True)
    if not quiet:
        print(f"{'uvolnilo by' if dry_run else 'uvolněno'} {_human(freed)}")
        if dry_run and drop:
            print("  skutečně smazat:  python tools/art_undo.py prune --apply")
    return [sid for sid, _d in drop]


@contextlib.contextmanager
def guard(paths, label, delete_new=False):
    """Snimek pred blokem; kdyz to uvnitr spadne, vrat vsechno zpatky.

        with art_undo.guard(["assets/distractions"], "sprite-cleanup"):
            prepis_vsechny_framy()      # spadne na 300. souboru z 432

    Bez tohohle by v assets/ zustalo 299 novych a 133 starych souboru, tedy stav,
    ktery neodpovida nicemu. Cely smysl je, ze pad vrati vsechno, ne cast.

    Chyta se BaseException, tedy i Ctrl+C - preruseni uprostred prepisovani je
    presne ta situace, kvuli ktere tohle existuje.

    delete_new je vychozi False: pad nemaze soubory. Kdyz operace neco vyrobila,
    zustane to lezet a jen se to vypise. Soubor navic se da smazat rucne, smazany
    soubor uz nikdo nevrati.
    """
    sid = snapshot(paths, label)
    try:
        yield sid
    except BaseException:
        print(f"\n!!! spadlo to — vracím snímek {sid} zpět")
        try:
            restore(sid, dry_run=False, delete_new=delete_new)
        except BaseException as ex:
            # Puvodni chybu nesmi prekryt chyba z uklidu, jinak clovek nezjisti,
            # co se doopravdy stalo. Navrat se da spustit rucne z CLI.
            print(f"!!! NÁVRAT SELHAL: {ex}")
            print(f"!!! zkus ručně: python tools/art_undo.py restore {sid} --apply")
        raise


# ---------------------------------------------------------------------- CLI

def _cmd_list(args):
    snaps = list_snapshots()
    if not snaps:
        print("žádné snímky.")
        print("  vytvoř:  python tools/art_undo.py snapshot assets/towers -l pokus")
        return 0
    print(f"{'id':>4}  {'kdy':<19}  {'souborů':>8}  {'velikost':>9}  popis")
    total = 0
    for s in snaps:
        total += s["velikost"]
        print(f"{s['id']:>4}  {s['kdy']:<19}  {s['souboru']:>8}  "
              f"{_human(s['velikost']):>9}  {s['label']}")
    print(f"\ncelkem {len(snaps)} snímků, {_human(total)} v build/undo/")
    return 0


def _cmd_show(args):
    snap_dir, man = _load(args.id)
    print(f"snímek {man['id']} · {man.get('label')} · {man.get('created')}")
    if man.get("git_head"):
        print(f"  HEAD v době snímku: {man['git_head'][:10]}")
    if man.get("roots"):
        print(f"  složky: {', '.join(man['roots'])}")
    by = {}
    for e in man.get("entries", []):
        by.setdefault(e.get("state"), []).append(e)
    popis = {"file": "zkopírováno do snímku", "git": "je v gitu, kopie netřeba",
             "absent": "tehdy neexistovalo"}
    for state, items in sorted(by.items()):
        print(f"\n  {state}  ({len(items)}×, {popis.get(state, '')})")
        for e in items[:10]:
            print(f"      {e['path']}")
        if len(items) > 10:
            print(f"      … a dalších {len(items) - 10}")
    return 0


def _cmd_restore(args):
    restore(args.id, dry_run=not args.apply, delete_new=args.delete_new)
    return 0


def _cmd_snapshot(args):
    snapshot(args.paths, args.label)
    return 0


def _cmd_prune(args):
    prune(keep=args.keep, dry_run=not args.apply)
    return 0


def main():
    ap = argparse.ArgumentParser(
        description="Krok zpět pro art: snímek před zápisem, návrat po zápisu.")
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("list", help="vypiš uložené snímky")
    p.set_defaults(fn=_cmd_list)

    p = sub.add_parser("show", help="co je uvnitř snímku")
    p.add_argument("id", type=int)
    p.set_defaults(fn=_cmd_show)

    p = sub.add_parser("restore", help="vrať soubory ze snímku (bez --apply jen ukáže)")
    p.add_argument("id", type=int)
    p.add_argument("--apply", action="store_true", help="skutečně zapsat")
    p.add_argument("--delete-new", action="store_true",
                   help="smaž i soubory, které od snímku přibyly")
    p.set_defaults(fn=_cmd_restore)

    p = sub.add_parser("snapshot", help="ulož stav souborů/složek")
    p.add_argument("paths", nargs="+")
    p.add_argument("-l", "--label", default="rucni", help="popis, ať to poznáš v seznamu")
    p.set_defaults(fn=_cmd_snapshot)

    p = sub.add_parser("prune", help="smaž staré snímky (bez --apply jen ukáže)")
    p.add_argument("--keep", type=int, default=20)
    p.add_argument("--apply", action="store_true", help="skutečně smazat")
    p.set_defaults(fn=_cmd_prune)

    args = ap.parse_args()
    if not getattr(args, "fn", None):
        ap.print_help()
        return 0
    try:
        return args.fn(args)
    except (KeyError, ValueError, OSError) as e:
        # KeyError si do str() pridava uvozovky, coz v hlasce pro cloveka vypada
        # jako preklep. args[0] je holy text.
        msg = e.args[0] if isinstance(e, KeyError) and e.args else e
        print(f"chyba: {msg}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
