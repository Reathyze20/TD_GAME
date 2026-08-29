"""Klient k Retro Diffusion Lite (Aseprite extension) pres jeho websocket server.

Retro Diffusion Lite je placena Aseprite extension, ktera si veze vlastni fork
Stable Diffusion 1.5 vycvicenej na pixel art. Aseprite s nim mluvi pres
websocket na ws://127.0.0.1:8765. Aseprite bezet nemusi -- server je samostatny
proces, takze si na nej muzeme sahnout my a pouzit ho jako dalsi generator
vedle tools/gen.py (lokalni SDXL) a tools/pixellab.py (cloud API).

PROC TENHLE SOUBOR EXISTUJE
  gen.py je SDXL + pixel-art LoRA, ktery dela "obrazek, co vypada jako pixel
  art" -- musi se po nem uklizet (cut_background, downscale_median, clean).
  Retro Diffusion generuje rovnou v cilovem rastru: model bezi na platne
  512x512 a server sam vysledek stahne k-centroidem na 32x32. To je presne to,
  co potrebuje nase pravidlo rastru (1 bunka = 16 pixelu artu).

VSECHNO NIZE JE VYCTENE ZE ZDROJE, NE ODHADNUTE:
  server: %APPDATA%/Aseprite/extensions/RetroDiffusionLite/
          stable-diffusion-aseprite/scripts/image_server.py   (2828 radku)
  klient: %APPDATA%/Aseprite/extensions/RetroDiffusionLite/scripts/generator.lua

Cisla radku v komentarich odkazuji na tyhle dva soubory ve verzi lite-1.0.0.


PROTOKOL -- CO PLATI (a kde se zadani mylilo)

1) HANDSHAKE JE BRANA, NE ZDVORILOST.
   image_server.py:2772  ->  if extensionVersion == expectedVersion: ... send("connected")
                             else: jen vytiskne chybu do konzole a NEODPOVI
   Kdyz posleme spatnou verzi, server MLCI. Zadny error, zadny disconnect --
   jen ticho. Proto se verze necte natvrdo z hlavy, ale regexem primo z
   image_server.py (viz server_version()), aby update extension neshodil klienta.
   Aktualne expectedVersion = "lite-1.0.0" (POZOR: package.json rika 1.5.0,
   to je verze extension, ne verze protokolu).
   Praci posilame az PO prijeti odpovedi "connected" -- stejne to dela
   generator.lua:590.

2) FORMAT VRACENEHO OBRAZKU -- ZADANI TVRDILO "vzdy syrove bajty", NENI TO TAK.
   encodeImage() (image_server.py:607) ma dve vetve podle klice "format":
     "png"   -> base64 hotoveho PNG souboru
     jinak   -> base64 syrovych RGBA bajtu (w*h*4), rozmery zvlast ve "width"/"height"
   A ted kdo co pouziva:
     finalni vysledek  "returning"      -> format "png"    (image_server.py:2282, 2547)
     prubezny nahled   "display_image"  -> format "bytes"  (image_server.py:2244, 2510)
     palettize/rembg/kcentroid/pixelDetect -> format "png" (1040, 1126, 1395, 1454)
   Takze syrove bajty potkame JEN u nahledu behem generovani. _decode_image()
   umi obe vetve a u syrovych bajtu kontroluje len(raw) == w*h*4.

3) width/height NEJSOU ROZMERY SPRITU.
   image_server.py:2118 to rika samo:
       "... at {W}x{H} ({W // pixelSize}x{H // pixelSize} pixels)"
   W/H je platno difuze (kolik pocita SD), pixel_size je delitel. Vysledny
   sprite ma W//pixel_size x H//pixel_size pixelu. render() (image_server.py:1948)
   ten downscale dela k-centroidem.
   Pro sprite 32x32 tedy NE width=32/pixel_size=1, ale width=height=512 a
   pixel_size=16. Prevod dela plan_size().

4) "model" JE SLOVNIK, NE RETEZEC.
   image_server.py:2571  load_model(modelData["file"], ..., ["device"], ["precision"], ["optimized"])
   Musi mit vsechny ctyri klice, "file" je absolutni cesta k .pxlm.

5) img2img POSILA OBRAZKY POD KLICEM "images" (mnozne cislo), ne "image".
   image_server.py:2662 cte values["images"]. Klic "image" je jen mrtvy relikt,
   ktery txt2img packet v Lua posila jako prazdny retezec (generator.lua:616).

6) POTVRZENI {"action":"recieved"} (ano, s preklepem, image_server.py:2777).
   Server na nej odpovi {"action":"free_websocket"} a zavola clearCache().
   Bez nej se neuvolni VRAM po generovani.

7) VYSTUP txt2img NEMA ALFU.
   render() konci pres kCentroid(), ktery vraci RGB (image_server.py:969).
   Pruhlednost umi jen rembg (ISNET segmentace, bezi na CPU). Proto ma
   txt2img() parametr rembg=True -- bez nej dostanes sprite na pozadi.


ROZHODNUTI, KTERA JSEM DELAL

  websockets vs. holy socket:
    Knihovna 'websockets' v nasem Pythonu JE (16.0), takze zadny RFC 6455
    handshake rucne psat nemusime. Zavrhl jsem asyncio API (websockets.connect)
    ve prospech websockets.sync.client -- synchronni klient znamena, ze
    txt2img() je normalni funkce a UI (gen_ui.py) ji muze zavolat primo ze
    sveho vlakna v ThreadingHTTPServer. S asyncio by kazdy volajici musel
    resit event loop.

  jedno spojeni na jednu praci:
    Server je stavovy jen minimalne (globalni 'background', 'sounds'), ale
    handshake je stejne povinny. Delam to jako Lua: otevri, handshake, jedna
    prace, "recieved", zavri. Zavrhl jsem drzeni jednoho spojeni pro vic
    prompt -- server po "recieved" posle "free_websocket" a cisti cache, takze
    znovupouziti spojeni by obchazelo jeho vlastni uklid pameti.

  CREATE_NEW_CONSOLE pri startu serveru:
    Server tiskne rich progress bar s poctem kroku. Kdybych mu sebral konzoli
    (DETACHED_PROCESS + roura do souboru), uzivatel prijde o jediny zpusob, jak
    videt, ze se neco deje -- start modelu trva minuty. Necham mu vlastni okno,
    stejne jako to dela setup.lua:198.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import platform
import re
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Iterable, Sequence

import numpy as np
from PIL import Image

try:
    from websockets.exceptions import ConnectionClosed
    from websockets.sync.client import connect as _ws_connect
except ImportError:  # pragma: no cover
    _ws_connect = None

    class ConnectionClosed(Exception):
        pass


HOST = "127.0.0.1"
PORT = 8765
URI = f"ws://{HOST}:{PORT}"

# Server startuje s max_size=100*1024*1024 (image_server.py:2818). Vychozi limit
# klienta je 1 MB, coz by prasklo na prvnim nahledu 512x512 RGBA (1 MB presne
# na hrane) i na vetsim PNG. Musime ho zvednout na stejnou hodnotu.
MAX_MESSAGE = 100 * 1024 * 1024

FALLBACK_VERSION = "lite-1.0.0"

# KEEPALIVE MUSI BYT VYPNUTY. Knihovna websockets ve vychozim stavu posila ping
# kazdych 20 s a kdyz do 20 s neprijde pong, spojeni zabije. Jenze server pousti
# generovani SYNCHRONNE uvnitr async handleru (image_server.py:2581 --
# "for result in txt2img(...)" je obycejny generator, ne await), takze po celou
# dobu vzorkovani neotoci event loop a na ping fyzicky nemuze odpovedet.
# S vychozim nastavenim tedy kazde generovani delsi nez 20 s spadne na
# "keepalive ping timeout" -- a vypada to jako pad serveru, i kdyz server
# v klidu pocita dal. Aseprite ma vlastni websocket bez pingu, proto na to
# jejich klient nikdy nenarazil.
KEEPALIVE = {"ping_interval": None, "ping_timeout": None}


class RDError(RuntimeError):
    """Chyba na strane Retro Diffusion serveru nebo protokolu."""


# ---------------------------------------------------------------------------
# Hledani instalace
# ---------------------------------------------------------------------------

def _candidate_roots() -> Iterable[Path]:
    """Kandidati na slozku stable-diffusion-aseprite, od nejkonkretnejsiho.

    Nebereme jednu cestu natvrdo -- uzivatel muze mit Aseprite ze Steamu, z
    portable zipu nebo na jinem disku. Env promenna RD_ROOT ma prednost, aby
    slo prepsat cokoliv bez zasahu do kodu.
    """
    env = os.environ.get("RD_ROOT")
    if env:
        yield Path(env)

    bases: list[Path] = []
    system = platform.system()
    if system == "Windows":
        for var in ("APPDATA", "LOCALAPPDATA"):
            val = os.environ.get(var)
            if val:
                bases.append(Path(val) / "Aseprite" / "extensions")
        # Steam verze si nekdy dela vlastni profil vedle exe
        for var in ("ProgramFiles", "ProgramFiles(x86)"):
            val = os.environ.get(var)
            if val:
                bases.append(Path(val) / "Aseprite" / "extensions")
    elif system == "Darwin":
        bases.append(Path.home() / "Library" / "Application Support" / "Aseprite" / "extensions")
    else:
        bases.append(Path.home() / ".config" / "aseprite" / "extensions")

    for base in bases:
        if not base.is_dir():
            continue
        # Nejdriv presne pojmenovana slozka, pak cokoliv, co ma to podadresari.
        preferred = base / "RetroDiffusionLite" / "stable-diffusion-aseprite"
        if preferred.is_dir():
            yield preferred
        try:
            for child in sorted(base.iterdir()):
                cand = child / "stable-diffusion-aseprite"
                if cand.is_dir() and cand != preferred:
                    yield cand
        except OSError:
            pass


def _is_rd_root(path: Path) -> bool:
    return (path / "scripts" / "image_server.py").is_file()


def find_rd_root() -> Path | None:
    for cand in _candidate_roots():
        try:
            if _is_rd_root(cand):
                return cand.resolve()
        except OSError:
            continue
    return None


RD_ROOT: Path | None = find_rd_root()


def _root() -> Path:
    if RD_ROOT is None:
        raise RDError(
            "Nenašel jsem instalaci Retro Diffusion Lite. "
            "Zkusil jsem %APPDATA%\\Aseprite\\extensions\\*\\stable-diffusion-aseprite. "
            "Nastav proměnnou prostředí RD_ROOT na složku stable-diffusion-aseprite."
        )
    return RD_ROOT


def venv_python() -> Path:
    """Python z jejich venv. Nas Python to spustit nemuze -- server importuje
    ldm, torch, hitherdither a dalsi veci, ktere jsou jen tam."""
    root = _root()
    exe = root / "venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not exe.is_file():
        raise RDError(f"Chybí venv Retro Diffusion: {exe}")
    return exe


def model_dir() -> Path:
    return _root() / "models" / "base"


def lora_dir() -> Path:
    return _root() / "models" / "lora"


_VERSION_RE = re.compile(r"^expectedVersion\s*=\s*[\"']([^\"']+)[\"']", re.M)


def server_version() -> str:
    """Verze protokolu, kterou server ceka v handshake.

    Cteme ji ze zdroje serveru misto natvrdo zapsane konstanty. Duvod: kdyz
    Astropulse vyda update, zmeni se expectedVersion i generator.lua zaroven a
    nas klient by jinak tise prestal fungovat (server na spatnou verzi
    NEODPOVIDA, viz hlavicka bod 1) -- a to se hleda blbe.
    """
    try:
        src = (_root() / "scripts" / "image_server.py").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return FALLBACK_VERSION
    m = _VERSION_RE.search(src)
    return m.group(1) if m else FALLBACK_VERSION


# ---------------------------------------------------------------------------
# Kodovani a dekodovani obrazku
# ---------------------------------------------------------------------------

def _to_rgba(a: np.ndarray) -> np.ndarray:
    a = np.asarray(a)
    if a.ndim == 2:
        a = np.stack([a] * 3, axis=-1)
    if a.shape[2] == 3:
        alpha = np.full(a.shape[:2] + (1,), 255, dtype=np.uint8)
        a = np.concatenate([a, alpha], axis=2)
    return np.ascontiguousarray(a.astype(np.uint8))


def _decode_image(entry: dict) -> np.ndarray:
    """Jeden zaznam z pole "images" -> ndarray RGBA (h, w, 4) uint8.

    Server ma dva formaty (image_server.py:607 encodeImage):
      format == "png"  -> base64 celeho PNG souboru
      jinak            -> base64 syrovych RGBA bajtu, rozmery v "width"/"height"
    Prvni pouzivaji vsechny finalni odpovedi, druhy jen prubezne nahledy.
    """
    raw = base64.b64decode(entry["image"])
    fmt = entry.get("format", "png")

    if fmt == "png":
        with Image.open(io.BytesIO(raw)) as im:
            return _to_rgba(np.array(im.convert("RGBA")))

    w = int(entry["width"])
    h = int(entry["height"])
    expect = w * h * 4
    if len(raw) != expect:
        # Kdyby se format nekdy zmenil, at je videt cislo, ne jen "reshape failed".
        raise RDError(
            f"Syrová data nesedí na rozměry: {len(raw)} bajtů, "
            f"čekal jsem {w}x{h}x4 = {expect}."
        )
    return np.ascontiguousarray(np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 4))


def _encode_image(a: np.ndarray, name: str = "img") -> dict:
    """ndarray -> zaznam, ktery server prijme.

    Posilame vzdy PNG: decodeImage() na serveru (image_server.py:618) ma u
    syrove vetve chybu -- predava do Image.frombytes() vestavenou funkci
    'format' misto retezce s modem, takze ta vetev spadne vzdy. PNG je jediny
    format, ktery server umi opravdu precist.
    """
    im = Image.fromarray(_to_rgba(a), mode="RGBA")
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return {"name": name, "format": "png", "image": base64.b64encode(buf.getvalue()).decode("ascii")}


def _as_list(images) -> list[np.ndarray]:
    if isinstance(images, np.ndarray) and images.ndim == 3:
        return [images]
    return list(images)


# ---------------------------------------------------------------------------
# Zivotni cyklus serveru
# ---------------------------------------------------------------------------

def is_running(timeout: float = 1.0) -> bool:
    """Posloucha nekdo na 8765?

    Zamerne jen TCP sonda, ne plny handshake: behem nacitani modelu (desitky
    sekund) server uz port drzi, ale jeste neobslouzi zpravu. Pro otazku
    "mam ho spoustet?" je otevreny port spravna odpoved -- druhy proces na
    stejnem portu by stejne nenastartoval.
    """
    try:
        with socket.create_connection((HOST, PORT), timeout=timeout):
            return True
    except OSError:
        return False


def ping(timeout: float = 10.0) -> bool:
    """Tvrdsi test nez is_running: projde cely handshake.

    Vraci True az kdyz server odpovi "connected", cili kdyz uz opravdu obsluhuje
    zpravy A souhlasi verze protokolu.
    """
    if _ws_connect is None:
        raise RDError("Chybí knihovna 'websockets' (pip install websockets).")
    try:
        with _ws_connect(URI, max_size=MAX_MESSAGE, open_timeout=timeout,
                         close_timeout=2, **KEEPALIVE) as ws:
            ws.send(json.dumps({
                "action": "connected",
                "type": "dictionary",
                "value": {"background": True, "play_sound": False, "version": server_version()},
            }))
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                msg = json.loads(ws.recv(timeout=max(0.5, deadline - time.monotonic())))
                if msg.get("action") == "connected":
                    return True
    except Exception:
        return False
    return False


def start_server(timeout: float = 600.0, quiet: bool = False) -> bool:
    """Spusti image_server.py jejich venvem a POCKA, az zacne odpovidat.

    Ceka se na skutecny handshake, ne na sleep -- import torch + nacteni
    modelu trva jednotky minut a na pomalejsim disku i vic, takze pevna pauza
    by byla bud zbytecne dlouha, nebo nespolehliva.
    """
    if ping(timeout=5):
        return True

    root = _root()
    py = venv_python()

    kwargs: dict = {}
    if os.name == "nt":
        # Vlastni okno konzole: server v nem tiskne progress bar generovani,
        # coz je jediny zpusob, jak videt, ze se neco deje. Zaroven proces
        # prezije konec naseho skriptu, takze ho startujeme jednou za sezeni.
        kwargs["creationflags"] = subprocess.CREATE_NEW_CONSOLE
    else:
        kwargs["start_new_session"] = True

    # cwd MUSI byt koren stable-diffusion-aseprite -- server importuje ldm,
    # optimization, lora relativne a nacita "scripts/v1-inference.yaml"
    # i "logo.png" z aktualni slozky.
    subprocess.Popen([str(py), "scripts/image_server.py"], cwd=str(root), **kwargs)

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if ping(timeout=5):
            return True
        if not quiet:
            left = int(deadline - time.monotonic())
            print(f"  ... čekám na server ({left} s do vypršení)", flush=True)
        time.sleep(3)
    raise RDError(
        f"Server se nerozeběhl do {timeout:.0f} s. Podívej se do jeho okna konzole, "
        "co tam píše (typicky chybějící model nebo obsazená VRAM)."
    )


def stop_server(timeout: float = 10.0) -> bool:
    """Posle {"action":"shutdown"} (image_server.py:2789).

    Server zastavi event loop sam. Zavrhl jsem zabijeni procesu podle PID --
    korektni shutdown necha torch uvolnit VRAM.
    """
    if not is_running():
        return False
    try:
        with _ws_connect(URI, max_size=MAX_MESSAGE, open_timeout=timeout,
                         close_timeout=2, **KEEPALIVE) as ws:
            ws.send(json.dumps({"action": "shutdown"}))
    except Exception:
        pass
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not is_running(timeout=0.5):
            return True
        time.sleep(0.5)
    return not is_running()


# ---------------------------------------------------------------------------
# Jadro: jedno spojeni = jedna prace
# ---------------------------------------------------------------------------

ProgressFn = Callable[[str, list], None]


def _call(action: str, value: dict, on_progress: ProgressFn | None = None,
          timeout: float = 1800.0, background: bool = True) -> list[np.ndarray]:
    """Otevre spojeni, projde handshake, posle praci, vrati dekodovane obrazky.

    Poradi je dane serverem: dokud neprijde "connected", nema smysl posilat
    nic dalsiho (image_server.py:2772 -- pri neshode verze server jen mlci).
    """
    if _ws_connect is None:
        raise RDError("Chybí knihovna 'websockets' (pip install websockets).")
    if not is_running():
        raise RDError("Retro Diffusion server neběží. Spusť ho: python tools/retrodiffusion.py start")

    version = server_version()
    deadline = time.monotonic() + timeout

    def _recv(ws):
        left = deadline - time.monotonic()
        if left <= 0:
            raise RDError(f"Vypršel čas ({timeout:.0f} s) při čekání na odpověď serveru.")
        try:
            return json.loads(ws.recv(timeout=left))
        except ConnectionClosed as exc:
            raise RDError(
                "Server zavřel spojení uprostřed práce. Nejčastěji došla VRAM "
                "(zkus menší --size nebo menší --n); přesná hláška je v jeho okně konzole."
            ) from exc

    with _ws_connect(URI, max_size=MAX_MESSAGE, open_timeout=30,
                     close_timeout=5, **KEEPALIVE) as ws:
        ws.send(json.dumps({
            "action": "connected",
            "type": "dictionary",
            # Vsechny tri klice jsou povinne -- server je rozbaluje jednim
            # tuple unpackem (image_server.py:2750) a bez nekterého by
            # extensionVersion zustal nenastaveny.
            "value": {"background": background, "play_sound": False, "version": version},
        }))

        try:
            while True:
                msg = _recv(ws)
                if msg.get("action") == "connected":
                    break
        except (TimeoutError, RDError) as exc:
            raise RDError(
                f"Server neodpověděl na handshake. Nejčastější příčina: neshoda verze "
                f"protokolu (posílám {version!r}). Server na neshodu záměrně mlčí a "
                f"vypíše hlášku jen do svého okna konzole."
            ) from exc

        ws.send(json.dumps({"action": action, "value": value}))

        title = ""
        while True:
            msg = _recv(ws)

            # Ne kazda zprava je slovnik. Generator txt2img yielduje dvojici
            # [titulek, obrazky] a v POSLEDNIM kroku je prvni polozka prazdny
            # retezec (image_server.py:2285). Server obe polozky posila zvlast
            # (2607-2609), takze po drate prijde holy JSON retezec "".
            #
            # Aseprite klient si toho nevsimne -- v Lue je cteni klice z neceho
            # jineho nez tabulky tise nil. V Pythonu je to AttributeError, a to
            # v nejdrazsi mozny okamzik: obrazky uz jsou spocitane a zahodi se
            # na posledni zprave. Chyba se ukaze JEN pri send_progress=True.
            if not isinstance(msg, dict):
                continue

            act = msg.get("action")

            if act == "display_title":
                title = msg.get("value", {}).get("text", "")
                if on_progress:
                    on_progress(title, [])

            elif act == "display_image":
                # Nahledy dekodujeme jen kdyz je nekdo chce -- jsou to syrove
                # RGBA bajty a pri kazdem par kroku, takze zbytecna prace.
                if on_progress:
                    imgs = [_decode_image(e) for e in msg.get("value", {}).get("images", [])]
                    on_progress(title, imgs)

            elif act == "returning":
                out = [_decode_image(e) for e in msg.get("value", {}).get("images", [])]
                # Povinne potvrzeni (preklep "recieved" je v jejich kodu,
                # image_server.py:2777). Server na nej uvolni cache/VRAM.
                ws.send(json.dumps({"action": "recieved"}))
                try:
                    _recv(ws)  # {"action":"free_websocket"}
                except Exception:
                    pass
                return out

            elif act == "error":
                raise RDError(
                    f"Server ohlásil chybu při akci {action!r}. Detail (traceback) je "
                    f"jen v jeho okně konzole -- podívej se tam."
                )


# ---------------------------------------------------------------------------
# Neutralni vychozi hodnoty
# ---------------------------------------------------------------------------

# manageComposition() (image_server.py:2006) prida LECO lora za kazdou hodnotu,
# ktera se lisi od neutralu. Tyhle konkretni hodnoty davaji prazdny seznam:
#   tint 0     -> vsechny tri barevne slozky vyjdou 0
#   brightness 70 -> po deleni deseti je to 7, coz je jedina hodnota bez lora
#   saturation/contrast/outline 50 -> odchylka 0
NEUTRAL_COMPOSITION = {
    "hue": 0, "tint": 0, "brightness": 70,
    "saturation": 50, "contrast": 50, "outline": 50,
}
# apply=False preskoci cely blok se svetlem (image_server.py:2009).
NEUTRAL_LIGHTING = {"apply": False, "x": 25, "y": 0, "z": 0}


def plan_size(size, pixel_size: int | None = None, model: str | None = None):
    """(pozadovany sprite) -> (W, H, pixel_size, cesta k modelu).

    Prevod je jadro cele veci, viz hlavicka bod 3: server pocita na platne W x H
    a vysledek stahne na W//pixel_size x H//pixel_size.

    Volba pixel_size kopiruje logiku, kterou ma jejich vlastni UI
    (generator.lua:356) -- male sprity se generuji "16x16 modelem" s
    pixel_size 16, vetsi "64x64 modelem" s pixel_size 8. V obou pripadech
    vyjde platno 256-512 px, coz je rozsah, ve kterem SD 1.5 nehalucinuje
    zdvojene postavy.

    Nase pravidlo rastru (1 bunka = 16 px artu) tim vychazi presne:
      16x16 dlazdice   -> platno 256x256, pixel_size 16
      32x32 prisera    -> platno 512x512, pixel_size 16
      64x64 boss       -> platno 512x512, pixel_size 8
    """
    if isinstance(size, (tuple, list)):
        w, h = int(size[0]), int(size[1])
    else:
        w = h = int(size)
    if w <= 0 or h <= 0:
        raise ValueError("Rozměr spritu musí být kladný.")

    if pixel_size is None:
        pixel_size = 16 if max(w, h) <= 32 else 8
    pixel_size = int(pixel_size)

    if model is None:
        model = "modelmicro.pxlm" if pixel_size >= 16 else "model.pxlm"
    model_path = model if os.path.isabs(model) else str(model_dir() / model)

    W, H = w * pixel_size, h * pixel_size
    # Latentni mrizka je W//8 (image_server.py:2094); nedelitelne osmi by
    # ztratilo posledni radek pixelu.
    if W % 8 or H % 8:
        raise ValueError(f"Plátno {W}x{H} není dělitelné osmi -- zvol jiný pixel_size.")
    return W, H, pixel_size, model_path


def _model_block(model_path: str, device: str, precision: str, optimized: bool) -> dict:
    if not os.path.isfile(model_path):
        raise RDError(f"Model neexistuje: {model_path}")
    return {"file": model_path, "device": device, "precision": precision, "optimized": optimized}


def _resolve_loras(loras) -> list[dict]:
    """[("gamecharacters", 100), ...] nebo [{"file":..,"weight":..}] -> tvar pro server.

    Vahy jsou v procentech (UI ma rozsah -50 az 100, data/default_settings.json).
    """
    out = []
    for item in loras or []:
        if isinstance(item, dict):
            f, wgt = item["file"], item.get("weight", 100)
        else:
            f, wgt = item
        if not os.path.isabs(f):
            if not f.endswith(".pxlm"):
                f += ".pxlm"
            f = str(lora_dir() / f)
        if not os.path.isfile(f):
            raise RDError(f"LoRA neexistuje: {f}")
        out.append({"file": f, "weight": int(wgt)})
    return out


def _base_value(prompt, negative, W, H, pixel_size, quality, scale, seed, n,
                model_block, loras, tile, use_pixelvae, use_ella, translate,
                prompt_tuning, post_process, send_progress, max_batch_size,
                lighting, composition, background) -> dict:
    """Spolecna cast paketu txt2img a img2img.

    Kazdy klic tady je povinny -- server je cte primo (values["..."]) a chybejici
    klic skonci jako KeyError, ktery se k nam vrati jen jako {"action":"error"}
    bez naznaku, co chybelo.
    """
    return {
        "prompt": prompt,
        "negative": negative,
        "use_ella": bool(use_ella),
        "translate": bool(translate),
        "prompt_tuning": bool(prompt_tuning),
        "width": int(W),
        "height": int(H),
        "pixel_size": int(pixel_size),
        "enhance_composition": False,  # server to necte, posila to jen Lua; drzime tvar
        "quality": int(quality),
        "scale": float(scale),
        "lighting": lighting or dict(NEUTRAL_LIGHTING),
        "composition": composition or dict(NEUTRAL_COMPOSITION),
        "seed": seed,  # None => server si vylosuje (image_server.py:2080)
        "generations": int(n),
        "max_batch_size": int(max_batch_size),
        "model": model_block,
        "loras": loras,
        "tile_x": bool(tile[0]),
        "tile_y": bool(tile[1]),
        "use_pixelvae": bool(use_pixelvae),
        "send_progress": bool(send_progress),
        "post_process": bool(post_process),
        "background": bool(background),
        "play_sound": False,
    }


# ---------------------------------------------------------------------------
# Verejne API
# ---------------------------------------------------------------------------

def txt2img(prompt: str, negative: str = "", size=32, n: int = 4, seed: int | None = None,
            quality: int = 4, tile: Sequence[bool] = (False, False),
            use_pixelvae: bool = False, use_ella: bool = True,
            rembg: bool = True, palettize: bool = False, alpha_threshold: int | None = 128,
            pixel_size: int | None = None, model: str | None = None,
            loras=None, scale: float = 8.0, device: str = "cuda",
            precision: str = "fp16", optimized: bool = False,
            translate: bool = False, prompt_tuning: bool = True,
            max_batch_size: int = 512, on_progress: ProgressFn | None = None,
            timeout: float = 1800.0) -> list[np.ndarray]:
    """Vygeneruje n spritu z textu. Vraci seznam ndarray RGBA (h, w, 4).

    size je rozmer HOTOVEHO spritu v pixelech (16/32/64), ne platna difuze --
    prevod resi plan_size().

    quality ridi pocet kroku vzorkovace: steps = round(3.4 + quality^2 / 2)
    (image_server.py:2085), takze 4 -> 11 kroku. Vic nez 6 uz jen zdrzuje,
    protoze model je LCM-destilovany.

    rembg=True pusti po generovani jeste segmentaci pozadi -- txt2img sam
    vraci neprusvitne RGB (viz hlavicka bod 7). Je to zvlast round trip a
    bezi na CPU, takze u davky par sekund navic.

    use_pixelvae=False zamerne, i kdyz to zni jako "chci pixely".
    Je to jejich "Fast Pixel Decoder": misto VAE dekoduje latenty primo do
    shluku barev (run_cluster, optimization/pixelvae.py:179). Nechavam ho
    vypnuty ze dvou duvodu -- jejich vlastni data/default_settings.json ma
    "pixel_vae": false, a run_cluster obchazi cely tuning bezne cesty
    (fastNlMeansDenoising + kontrast 1.2 + sytost 1.15, image_server.py:1892).
    Server ho stejne pouzije sam jako zachranu, kdyz pri dekodovani dojde VRAM.
    """
    W, H, pixel_size, model_path = plan_size(size, pixel_size, model)
    value = _base_value(
        prompt, negative, W, H, pixel_size, quality, scale, seed, n,
        _model_block(model_path, device, precision, optimized),
        _resolve_loras(loras), tile, use_pixelvae, use_ella, translate,
        prompt_tuning, palettize, on_progress is not None, max_batch_size,
        None, None, True,
    )
    value["image"] = ""  # mrtvy klic, ktery posila i Lua (generator.lua:616)

    out = _call("txt2img", value, on_progress, timeout)
    if rembg:
        out = rembg_images(out, alpha_threshold=alpha_threshold, timeout=timeout)
    return out


def img2img(base_rgba, prompt: str, strength: int = 50, negative: str = "",
            size=None, n: int = 4, seed: int | None = None, quality: int = 4,
            tile: Sequence[bool] = (False, False), use_pixelvae: bool = False,
            use_ella: bool = True, rembg: bool = False, palettize: bool = False,
            alpha_threshold: int | None = 128,
            pixel_size: int | None = None, model: str | None = None,
            loras=None, scale: float = 8.0, device: str = "cuda",
            precision: str = "fp16", optimized: bool = False,
            translate: bool = False, prompt_tuning: bool = True,
            max_batch_size: int = 512, on_progress: ProgressFn | None = None,
            timeout: float = 1800.0) -> list[np.ndarray]:
    """Prekresli existujici sprite. strength 0-100 = jak moc se smi vzdalit.

    Vstup se posila v puvodni velikosti. Aseprite si ho pred odeslanim zvetsuje
    na 512 (generator.lua:636 resizeImage(image, 512)), ale to je jen proto, ze
    resi vyber na platne -- server si obrazek stejne prevzorkuje sam podle W/H
    (load_img). Zvetsovat nearest neighbourem na nasi strane by jen nafouklo
    zpravu, takze to nedelame.

    size=None znamena "zachovej rozmer vstupu".
    """
    base = _to_rgba(np.asarray(base_rgba))
    if size is None:
        size = (base.shape[1], base.shape[0])

    W, H, pixel_size, model_path = plan_size(size, pixel_size, model)
    value = _base_value(
        prompt, negative, W, H, pixel_size, quality, scale, seed, n,
        _model_block(model_path, device, precision, optimized),
        _resolve_loras(loras), tile, use_pixelvae, use_ella, translate,
        prompt_tuning, palettize, on_progress is not None, max_batch_size,
        None, None, True,
    )
    value["strength"] = int(strength)
    # Mnozne cislo! Server cte values["images"] (image_server.py:2662).
    value["images"] = [_encode_image(base, "i2i")]

    out = _call("img2img", value, on_progress, timeout)
    if rembg:
        out = rembg_images(out, alpha_threshold=alpha_threshold, timeout=timeout)
    return out


def _harden_alpha(a: np.ndarray, threshold: int) -> np.ndarray:
    """Zaokrouhli alfu na 0 nebo 255.

    ISNET je segmentacni sit pro fotky, takze vraci mekky prechod -- na
    namerenem spritu 32x32 melo alfa 57 ruznych hodnot. To je pro pixel art
    spatne hned dvakrat: docs/art/style_bible_measured.md chce ostry obrys a Godot by
    poloprusvitne okraje pri meritku x3 rozmazal do trojnasobne sire.
    """
    a = a.copy()
    a[..., 3] = np.where(a[..., 3] >= threshold, 255, 0).astype(np.uint8)
    return a


def rembg_images(images, alpha_threshold: int | None = 128,
                 timeout: float = 600.0) -> list[np.ndarray]:
    """Odstrani pozadi ISNET segmentaci. Vraci RGBA s opravdovou alfou.

    Bezi na CPU (segmenter/segmenter.py:22 device='cpu'), takze nesouperi
    s generovanim o VRAM, ale u velke davky to chvili trva.

    alpha_threshold ostri alfu na 0/255 (viz _harden_alpha). None ji necha
    mekkou -- to chces jen kdyz vysledek jde do dalsiho zpracovani, ktere
    s poloprusvitnosti pocita.
    """
    imgs = _as_list(images)
    if not imgs:
        return []
    value = {
        "images": [_encode_image(a, f"rembg{i}") for i, a in enumerate(imgs)],
        # Slozka s ISNET.pth; segmenter si nazev souboru doplni sam
        # (segmenter/segmenter.py:35 hypar["restore_model"] = "ISNET.pth").
        "model_folder": str(model_dir()) + os.sep,
        "background": True,
        "play_sound": False,
    }
    out = _call("rembg", value, None, timeout)
    if alpha_threshold is not None:
        out = [_harden_alpha(a, alpha_threshold) for a in out]
    return out


def _restore_alpha(originals: list[np.ndarray], results: list[np.ndarray]) -> list[np.ndarray]:
    """Vrati alfu, kterou server zahodil.

    decodeImage() na serveru dela .convert("RGB") (image_server.py:621), takze
    palettize/kcentroid/pixelDetect pruhlednost proste ztrati. Kdyz se rozmer
    nezmenil, je alfa puvodniho obrazku porad platna a muzeme ji nalepit zpet --
    jinak by kazdy pruchod palettou znicil vysledek rembg.
    """
    out = []
    for orig, res in zip(originals, results):
        if orig.shape[:2] == res.shape[:2]:
            res = res.copy()
            res[..., 3] = orig[..., 3]
        out.append(res)
    return out


def palettize(images, colors: int = 32, palette=None, dithering: int = 0,
              dither_strength: int = 0, denoise: bool = False,
              smoothness: int = 0, intensity: int = 0, source: str = "Adaptive",
              url: str = "None", keep_alpha: bool = True,
              timeout: float = 600.0) -> list[np.ndarray]:
    """Zredukuje pocet barev.

    source: "Adaptive" (pouzij 'colors'), "Automatic" (server si pocet zvoli sam),
            "Best Palette" (vybere z 'palette' seznamu), "URL".
    dithering je rad Bayerovy matice (0/2/4/8), dither_strength 0 ho vypina.

    Pozn.: nase tools/sprite_cleanup.py umi remap na master paletu 48 barev a
    hlida chromu (CHROMA_WEIGHT=2.5). Tohle je rychlejsi, ale hloupejsi --
    na finalni sprity poustej radsi sprite_cleanup.
    """
    imgs = _as_list(images)
    if not imgs:
        return []
    pal = [_encode_image(p, f"pal{i}") for i, p in enumerate(_as_list(palette or []))]
    value = {
        "images": [_encode_image(a, f"pal_in{i}") for i, a in enumerate(imgs)],
        "source": source,
        "url": url,
        "palettes": pal,
        "colors": int(colors),
        "dithering": int(dithering),
        "dither_strength": int(dither_strength),
        "denoise": bool(denoise),
        "smoothness": int(smoothness),
        "intensity": int(intensity),
        "background": True,
        "play_sound": False,
    }
    out = _call("palettize", value, None, timeout)
    return _restore_alpha(imgs, out) if keep_alpha else out


def kcentroid(images, size, centroids: int = 2, outline: bool = False,
              keep_alpha: bool = True, timeout: float = 600.0) -> list[np.ndarray]:
    """Zmensi na presny rozmer k-centroid algoritmem.

    Tohle je ten samy downscale, ktery server pouziva interne po difuzi. Je
    lepsi nez prosty nearest -- pro kazdy cilovy pixel udela k-means clustering
    zdrojove dlazdice a vezme nejcastejsi barvu (image_server.py:944), takze
    nerozmaze obrys.
    """
    imgs = _as_list(images)
    if not imgs:
        return []
    if isinstance(size, (tuple, list)):
        w, h = int(size[0]), int(size[1])
    else:
        w = h = int(size)
    value = {
        "images": [_encode_image(a, f"kc{i}") for i, a in enumerate(imgs)],
        "width": w, "height": h,
        "centroids": int(centroids),
        "outline": bool(outline),
        "background": True,
        "play_sound": False,
    }
    out = _call("kcentroid", value, None, timeout)
    # Rozmer se meni, takze alfu nalepit nejde -- musime ji zmensit sami.
    if keep_alpha:
        fixed = []
        for orig, res in zip(imgs, out):
            a = Image.fromarray(orig[..., 3], mode="L").resize((res.shape[1], res.shape[0]), Image.Resampling.NEAREST)
            res = res.copy()
            res[..., 3] = np.array(a)
            fixed.append(res)
        return fixed
    return out


def pixel_detect(image, timeout: float = 600.0) -> np.ndarray:
    """Odhadne, na jaky raster obrazek patri, a stahne ho tam.

    Hleda periodu v rozdilech sousednich pixelu (FFT/peaks, image_server.py:1052).
    Uzitecne na cizi art, u ktereho nevis, jestli je to 2x nebo 3x zvetseny
    pixel art -- coz je presne problem, ktery mame popsany v pameti projektu
    ("Velikost pixelu neni jednotna").
    """
    imgs = _as_list(image)
    value = {
        "images": [_encode_image(imgs[0], "pd")],
        "background": True,
        "play_sound": False,
    }
    return _call("pixelDetect", value, None, timeout)[0]


# Aliasy, aby sedely nazvy z zadani
rembg = rembg_images


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _cmd_check(args) -> int:
    print("Retro Diffusion Lite -- kontrola")
    if RD_ROOT is None:
        print("  instalace : NENALEZENA")
        print("  Nastav RD_ROOT na složku stable-diffusion-aseprite.")
        return 1
    print(f"  kořen     : {RD_ROOT}")
    try:
        print(f"  venv      : {venv_python()}")
    except RDError as exc:
        print(f"  venv      : CHYBÍ ({exc})")
    print(f"  verze     : {server_version()}")
    print(f"  modely    : {model_dir()}")
    for m in sorted(model_dir().glob("*.pxlm")) if model_dir().is_dir() else []:
        print(f"              {m.name}  ({m.stat().st_size / 1e6:.0f} MB)")
    loras = sorted(lora_dir().glob("*.pxlm")) if lora_dir().is_dir() else []
    print(f"  lory      : {', '.join(p.stem for p in loras) or 'žádné'}")
    print(f"  websockets: {'ano' if _ws_connect else 'CHYBÍ'}")

    running = is_running()
    print(f"  port 8765 : {'poslouchá' if running else 'zavřený'}")
    if running:
        print(f"  handshake : {'OK' if ping() else 'SELHAL (neshoda verze?)'}")
    else:
        print("  Server spustíš: python tools/retrodiffusion.py start")
    return 0


def _cmd_start(args) -> int:
    if is_running():
        print("Server už běží.")
        return 0
    print("Spouštím server (import knihoven a načtení modelu trvá minuty)...")
    t0 = time.time()
    start_server(timeout=args.timeout)
    print(f"Server odpovídá po {time.time() - t0:.0f} s.")
    return 0


def _cmd_stop(args) -> int:
    print("Zastaveno." if stop_server() else "Server neběžel.")
    return 0


def _cmd_gen(args) -> int:
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    if not is_running():
        if not args.autostart:
            print("Server neběží. Spusť 'python tools/retrodiffusion.py start' "
                  "nebo přidej --autostart.")
            return 1
        start_server()

    last = [""]

    def progress(title, imgs):
        if title != last[0]:
            last[0] = title
            print(f"  {title}", flush=True)

    t0 = time.time()
    imgs = txt2img(
        args.prompt, negative=args.negative, size=args.size, n=args.n,
        seed=args.seed, quality=args.quality, rembg=not args.no_rembg,
        palettize=args.palettize, pixel_size=args.pixel_size,
        loras=[(l, args.lora_weight) for l in args.lora],
        tile=(args.tile_x, args.tile_y),
        on_progress=progress if args.progress else None,
    )
    dt = time.time() - t0

    stem = re.sub(r"[^a-z0-9]+", "_", args.prompt.lower()).strip("_")[:40] or "rd"
    for i, a in enumerate(imgs):
        p = out_dir / f"{stem}_{i + 1}.png"
        Image.fromarray(a, mode="RGBA").save(p)
        opaque = a[..., 3] > 0
        colors = len(np.unique(a[opaque][:, :3].reshape(-1, 3), axis=0)) if opaque.any() else 0
        print(f"  {p}  {a.shape[1]}x{a.shape[0]}  barev={colors}  "
              f"neprůhledných={int(opaque.sum())}/{opaque.size}")
    print(f"Hotovo za {dt:.0f} s, {len(imgs)} obrázků v {out_dir}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="retrodiffusion",
        description="Klient k Retro Diffusion Lite (Aseprite) -- generování pixel artu.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("check", help="ověří instalaci a stav serveru").set_defaults(fn=_cmd_check)

    p = sub.add_parser("start", help="spustí server a počká na něj")
    p.add_argument("--timeout", type=float, default=600.0)
    p.set_defaults(fn=_cmd_start)

    sub.add_parser("stop", help="zastaví server").set_defaults(fn=_cmd_stop)

    p = sub.add_parser("gen", help="vygeneruje sprity z promptu")
    p.add_argument("prompt")
    p.add_argument("--negative", default="")
    p.add_argument("--size", type=int, default=32, help="hrana hotového spritu (16/32/64)")
    p.add_argument("--n", type=int, default=4)
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--quality", type=int, default=4, help="1-10, kroky = 3.4 + q^2/2")
    p.add_argument("--pixel-size", type=int, default=None, dest="pixel_size")
    p.add_argument("--lora", action="append", default=[], help="název LoRA, lze opakovat")
    p.add_argument("--lora-weight", type=int, default=100, dest="lora_weight")
    p.add_argument("--tile-x", action="store_true", dest="tile_x")
    p.add_argument("--tile-y", action="store_true", dest="tile_y")
    p.add_argument("--no-rembg", action="store_true", dest="no_rembg",
                   help="nechat pozadí (jinak se odstraňuje)")
    p.add_argument("--palettize", action="store_true")
    p.add_argument("--progress", action="store_true", help="vypisovat průběh")
    p.add_argument("--autostart", action="store_true", help="spustit server, když neběží")
    p.add_argument("--out", default="build/rd")
    p.set_defaults(fn=_cmd_gen)

    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except RDError as exc:
        print(f"CHYBA: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
