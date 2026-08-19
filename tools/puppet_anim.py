# Proceduralni loutkovy animator: animace z JEDNOHO spritu bez AI.
#
#   from puppet_anim import puppet_walk, puppet_idle, puppet_attack, puppet_death
#   frames = puppet_walk(sprite_rgba, intensity=2)
#
# PROC LOUTKA A NE DIFUZE
#
# gen.animate pouziva img2img a kazdy frame generuje znovu — model si pokazde vybere
# vlastni odstin, takze povrch mezi framy "vari" (pixel boiling). pulse_anim.py uz
# dokazuje, ze cista manipulace pixelu (posun, roztazeni) funguje lip: zadny sum,
# zadna GPU, vysledek za milisekundy.
#
# Tenhle modul rozsiruje tentyz princip na POSTAVY. Sprite se rozreze na tri vrstvy
# (hlava, trup, nohy) a kazda vrstva se pohybuje podle sablony. Pixely se nikdy
# neprekresluji — jen se posouvaji, takze paleta a povrch zustavaji naprosto stabilni.
#
# SEGMENTACE
#
# Automaticka, podle distribuce neprusvitnych pixelu po radcich (kumulativni soucet
# plochy). Hranice se pocitaji z POMERU, ne z pevnych offsetu — boss 64x64 ma jine
# proporce nez 32x32 prisera. Kdyz segmentace neodpovida anatomii (prisera ma velkou
# hlavu a male nohy), intenzita pohybu se da snizit na 1 a vysledek je jemne dychani
# celeho spritu bez riskantniho rozrezavani.
#
# SABLONY
#
# Walk:   sinusovy bobbing trupu + stridavy posun nohou
# Idle:   pomale dychani (vertikalni stretch trupu ±1 px)
# Attack: naprah dozadu → vypad vpred → bounce zpet
# Death:  sesednuti + pixel dissolve od okraju siluety
#
# Vsechny sablony pracuji s CELYMI PIXELY (zadna interpolace). Posun o 0.7 px se
# zaokrouhli na 1 — subpixelova interpolace by pridala nove barvy a znicila paletu.
import math
import os
import sys

import numpy as np

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


# ------------------------------------------------------------------ segmentace


def _row_mass(a):
    """Pocet neprusvitnych pixelu v kazdem radku."""
    return (a[..., 3] > 32).sum(axis=1).astype(float)


def _content_rows(a):
    """(prvni, posledni+1) radek s obsahem."""
    m = a[..., 3] > 32
    ys = np.where(m.any(axis=1))[0]
    if len(ys) == 0:
        return 0, a.shape[0]
    return int(ys[0]), int(ys[-1]) + 1


def segment(a, head_frac=0.30, leg_frac=0.30):
    """Rozrez sprite na 4 vrstvy: hlava, trup, leva noha, prava noha.

    Rozdeleni nohou na levou a pravou pulku umoznuje realny krok (jedna noha vpred,
    druha vzad se zvednutim ze zeme), misto posouvani celeho spodku vcelku.
    """
    y0, y1 = _content_rows(a)
    if y1 <= y0:
        empty = np.zeros_like(a)
        return empty.copy(), empty.copy(), empty.copy(), empty.copy()

    mass = _row_mass(a)
    cum = np.cumsum(mass)
    total = cum[-1]
    if total < 1:
        empty = np.zeros_like(a)
        return empty.copy(), empty.copy(), empty.copy(), empty.copy()

    head_thresh = total * head_frac
    leg_thresh = total * (1.0 - leg_frac)

    head_cut = y0
    for y in range(y0, y1):
        if cum[y] >= head_thresh:
            head_cut = y + 1
            break

    leg_cut = y1
    for y in range(y0, y1):
        if cum[y] >= leg_thresh:
            leg_cut = y
            break

    if head_cut >= leg_cut:
        span = y1 - y0
        head_cut = y0 + span // 3
        leg_cut = y0 + 2 * span // 3

    # Vypocet horizontalniho teziste nohou (cx)
    leg_mask = a[leg_cut:, :, 3] > 32
    if leg_mask.any():
        _, xs = np.nonzero(leg_mask)
        cx = int(round(xs.mean()))
    else:
        cx = a.shape[1] // 2

    head = np.zeros_like(a)
    torso = np.zeros_like(a)
    leg_l = np.zeros_like(a)
    leg_r = np.zeros_like(a)

    head[:head_cut] = a[:head_cut]
    torso[head_cut:leg_cut] = a[head_cut:leg_cut]
    
    # Rozdeleni spodni casti na levou a pravou nohu podel teziste cx
    leg_l[leg_cut:, :cx] = a[leg_cut:, :cx]
    leg_r[leg_cut:, cx:] = a[leg_cut:, cx:]

    return head, torso, leg_l, leg_r


# ------------------------------------------------------------------ skladani


def _shift(layer, dx, dy):
    """Posun vrstvy o cele pixely s doplnenim pruhlednosti."""
    h, w = layer.shape[:2]
    dx, dy = int(round(dx)), int(round(dy))
    if abs(dx) >= w or abs(dy) >= h:
        return np.zeros_like(layer)
    out = np.roll(np.roll(layer, dy, axis=0), dx, axis=1)
    if dy > 0:
        out[:dy] = 0
    elif dy < 0:
        out[dy:] = 0
    if dx > 0:
        out[:, :dx] = 0
    elif dx < 0:
        out[:, dx:] = 0
    return out


def _compose_layers(layer_shifts):
    """Slozi libovolny pocet vrstev ve specifikovanem Z-poradi.
    layer_shifts = [(layer_array, (dx, dy)), ...]
    """
    if not layer_shifts:
        return np.zeros((32, 32, 4), dtype=np.uint8)
    h, w = layer_shifts[0][0].shape[:2]
    out = np.zeros((h, w, 4), dtype=np.uint8)

    for layer, (dx, dy) in layer_shifts:
        shifted = _shift(layer, dx, dy)
        mask = shifted[..., 3:4].astype(float) / 255.0
        src = shifted[..., :3].astype(float)
        dst = out[..., :3].astype(float)
        dst_a = out[..., 3:4].astype(float) / 255.0
        out_a = mask + dst_a * (1.0 - mask)
        safe = np.where(out_a > 0, out_a, 1.0)
        out[..., :3] = ((src * mask + dst * dst_a * (1.0 - mask)) / safe).astype(np.uint8)
        out[..., 3] = (out_a * 255).astype(np.uint8)[..., 0]
    return out


def _compose(head, torso, legs, dh=(0, 0), dt=(0, 0), dl=(0, 0)):
    """Zpetna kompatibilita pro 3 vrstvy."""
    return _compose_layers([(legs, dl), (torso, dt), (head, dh)])


# ------------------------------------------------------------------ sablony


def puppet_walk(a, n_frames=8, intensity=2):
    """Realisticky walk cycle: stridani leve/prave nohy se zvednutim + bobbing tela.

    Kazda noha se zvedne pri svihu vpred a polozi na zem pri zaberu vzad.
    Trup a hlava vertikalne kmitaji pri kazdem doslapu (2x za cyklus).
    """
    head, torso, leg_l, leg_r = segment(a)
    amp = max(1, int(intensity))
    frames = []

    for i in range(n_frames):
        t = (i / n_frames) * 2 * math.pi

        # LEVA NOHA: Svih vpred (t=0..pi) -> zvedne se nahoru (-dy). Zaber vzad (t=pi..2pi) -> na zemi (dy=0)
        dx_l = round(amp * 1.1 * math.sin(t))
        dy_l = -round(amp * 0.8 * max(0.0, math.sin(t)))

        # PRAVA NOHA: 180° v protifazi (t + pi)
        dx_r = round(amp * 1.1 * math.sin(t + math.pi))
        dy_r = -round(amp * 0.8 * max(0.0, math.sin(t + math.pi)))

        # TRUP: Dvakrat klesne a stoupne na kazdy doslap (frekvence 2t)
        torso_dy = round(amp * 0.45 * math.cos(2 * t))
        torso_dx = round(amp * 0.25 * math.sin(t))

        # HLAVA: Sleduje trup s jemnou fazovou setrvacnosti
        head_dy = torso_dy + round(amp * 0.2 * math.sin(2 * t - 0.4))
        head_dx = -round(amp * 0.15 * math.sin(t))

        # Slozeni vrstev: noha vzadu -> noha vpredu -> trup -> hlava
        if math.sin(t) >= 0:
            # Prava noha je vzadu, leva vepredu
            layers = [(leg_r, (dx_r, dy_r)), (leg_l, (dx_l, dy_l)), (torso, (torso_dx, torso_dy)), (head, (head_dx, head_dy))]
        else:
            # Leva noha je vzadu, prava vepredu
            layers = [(leg_l, (dx_l, dy_l)), (leg_r, (dx_r, dy_r)), (torso, (torso_dx, torso_dy)), (head, (head_dx, head_dy))]

        frames.append(_compose_layers(layers))
    return frames


def puppet_idle(a, n_frames=4, intensity=1):
    """Idle: pomale dychani — vertikalni stretch trupu ±1 px.

    Na 32px spritu je "nadechnuti" JEDEN pixel. Proto vsechny ctyri framy popisuji
    totez stani, jen s jinym dechem. Mensi intenzita nez walk — na spritu, ktery
    stoji, je kazdy pixel navic videt."""
    head, torso, leg_l, leg_r = segment(a)
    amp = max(1, int(intensity))
    frames = []
    for i in range(n_frames):
        t = (i / n_frames) * 2 * math.pi

        # Trup: pomale dychani (jemna sinusovka)
        torso_dy = round(amp * 0.5 * math.sin(t))

        # Hlava: sleduje trup s miligrave fazi
        head_dy = torso_dy + round(amp * 0.3 * math.sin(t - 0.5))

        # Nohy: staticky
        frames.append(_compose_layers([
            (leg_l, (0, 0)), (leg_r, (0, 0)),
            (torso, (0, torso_dy)),
            (head, (0, head_dy)),
        ]))
    return frames


def puppet_attack(a, n_frames=7, intensity=3):
    """Attack: naprah → vypad → bounce zpet.

    3 faze: frame 1-2 naprah (dozadu), frame 3-4 vypad (vpred+squash),
    frame 5-7 navrat s overshootem. Posledni frame musi navazovat na prvni,
    protoze ve hre se attack hraje ve smycce."""
    head, torso, leg_l, leg_r = segment(a)
    amp = max(1, int(intensity))

    # Trajektorie trupu na ose X (vpred = kladne)
    # Keyframes: naprah(-1) → vypad(+1.5) → overshoot(-0.3) → klid(0)
    keyframes_x = [-0.8, -1.0, 1.5, 1.2, -0.3, 0.1, 0.0]
    # Keyframes: vertikalni (squash pri dopadu)
    keyframes_y = [0.3, 0.5, -0.4, -0.2, 0.2, 0.1, 0.0]

    # Zarovnej pocet keyframu na pozadovany pocet framu
    while len(keyframes_x) < n_frames:
        keyframes_x.append(0.0)
        keyframes_y.append(0.0)

    frames = []
    for i in range(n_frames):
        kx = keyframes_x[i] if i < len(keyframes_x) else 0.0
        ky = keyframes_y[i] if i < len(keyframes_y) else 0.0

        torso_dx = round(amp * kx)
        torso_dy = round(amp * ky)
        # Hlava leti dal nez trup (setrvacnost)
        head_dx = round(amp * kx * 1.3)
        head_dy = round(amp * ky * 0.7)
        # Nohy: mirny protipohyb pri naprazcich, jinak stabilni
        leg_dx = round(-amp * kx * 0.2)
        leg_dy = 0

        frames.append(_compose_layers([
            (leg_l, (leg_dx, leg_dy)), (leg_r, (leg_dx, leg_dy)),
            (torso, (torso_dx, torso_dy)),
            (head, (head_dx, head_dy)),
        ]))
    return frames


def puppet_death(a, n_frames=10, intensity=2, seed=42):
    """Death: sesednuti k zemi + pixel dissolve od okraju siluety.

    Prvnich 5 framu: trup se svisle komprimuje (kazdy frame o 1-2 px), hlava klesa.
    Framu 6-10: pixely z okraje siluety mizí (dissolve s gravitaci). Posledni 2-3
    framy jsou jen kaluž (spodnich 20 % puvodni hmoty).

    Posledni frame musi byt neprazdny — distraction_animator.gd:366 ho drzi na
    obrazovce jako zbytky prisery."""
    h, w = a.shape[:2]
    rng = np.random.RandomState(seed)
    amp = max(1, int(intensity))
    frames = []

    # Faze 1: sesednuti (framy 0..n_frames//2)
    collapse_frames = n_frames // 2
    for i in range(collapse_frames):
        t = (i + 1) / collapse_frames  # 0..1

        # Vertikalni komprese: hlava klesa, trup se smrskuje
        head, torso, leg_l, leg_r = segment(a)

        # Klid → sesednuto: hlava klesa o amp*t pixelu
        head_dy = round(amp * 1.5 * t)
        # Trup: mirna komprese simulovana posunem dolu
        torso_dy = round(amp * 0.8 * t)
        # Nohy: rozestupi se mirne do stran
        leg_dx = round(amp * 0.3 * t)

        frames.append(_compose_layers([
            (leg_l, (-leg_dx, 0)), (leg_r, (leg_dx, 0)),
            (torso, (0, torso_dy)),
            (head, (0, head_dy)),
        ]))

    # Faze 2: pixel dissolve (framy collapse_frames..n_frames)
    dissolve_frames = n_frames - collapse_frames
    # Zakladni frame je posledni z faze 1
    base = frames[-1].copy() if frames else a.copy()

    for i in range(dissolve_frames):
        t = (i + 1) / dissolve_frames  # 0..1

        frame = base.copy()
        m = frame[..., 3] > 32
        if not m.any():
            frames.append(frame)
            continue

        # Procento pixelu k odstraneni roste s t^2 (zacatek pomaly, konec rychly)
        dissolve_ratio = min(0.85, t * t * 0.9)

        # Najdi okrajove pixely (mene nez 4 sousedy)
        ys, xs = np.nonzero(m)
        n_total = len(ys)
        if n_total == 0:
            frames.append(frame)
            continue

        # Priorita rozpadu: od okraju (pixely s mene sousedy se rozpousti driv)
        # + gravitace (horni pixely mizí driv nez spodni)
        neighbor_count = np.zeros(n_total, dtype=int)
        for dy_n, dx_n in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny = np.clip(ys + dy_n, 0, h - 1)
            nx = np.clip(xs + dx_n, 0, w - 1)
            neighbor_count += m[ny, nx].astype(int)

        # Skore: malo sousedu = vysoke skore (rozpada se driv),
        # vyssi radek = vysoke skore (gravitace — horni casti padaji)
        y_max = int(ys.max()) if len(ys) else h
        gravity = (y_max - ys).astype(float) / max(1, y_max)
        score = (4 - neighbor_count).astype(float) + gravity * 2
        # Pridat nahodnost
        score += rng.uniform(0, 1, size=n_total)

        # Odstranit n pixelu s nejvyssim skore
        n_remove = int(n_total * dissolve_ratio)
        if n_remove > 0:
            indices = np.argsort(score)[-n_remove:]
            frame[ys[indices], xs[indices], 3] = 0

        frames.append(frame)
        base = frame.copy()

    return frames


# ------------------------------------------------------------------ vstupni bod


def puppet_walk_side(a, n_frames=8, intensity=2):
    """Bocni chuze (east/west): nohy se hybou v ose X, trup kmita vertikalne.

    Bocni pohled ma jinou mechaniku nez predni: vidime profil, takze krok je
    posun VPRED (osa X), ne do stran. Nohy se stridaji v protifazi a ta, ktera
    je vpredu, se zvedne (dy < 0). Trup vertikalne kmita pri kazdem doslapu."""
    head, torso, leg_l, leg_r = segment(a)
    amp = max(1, int(intensity))
    frames = []

    for i in range(n_frames):
        t = (i / n_frames) * 2 * math.pi

        # "Leva" noha = predni v profilu: svih vpred
        dx_l = round(amp * 1.3 * math.sin(t))
        dy_l = -round(amp * 0.6 * max(0.0, math.sin(t)))

        # "Prava" noha = zadni v profilu: protifaze
        dx_r = round(amp * 1.3 * math.sin(t + math.pi))
        dy_r = -round(amp * 0.6 * max(0.0, math.sin(t + math.pi)))

        # Trup: dvakrat klesne za cyklus (doslap) + mirny naklon vpred
        torso_dy = round(amp * 0.4 * math.cos(2 * t))
        torso_dx = round(amp * 0.2 * math.sin(t))

        # Hlava: sleduje trup se setrvacnosti
        head_dy = torso_dy + round(amp * 0.15 * math.sin(2 * t - 0.4))
        head_dx = torso_dx

        # Predni noha je vpredu v Z-poradi
        if math.sin(t) >= 0:
            layers = [(leg_r, (dx_r, dy_r)), (leg_l, (dx_l, dy_l)),
                      (torso, (torso_dx, torso_dy)), (head, (head_dx, head_dy))]
        else:
            layers = [(leg_l, (dx_l, dy_l)), (leg_r, (dx_r, dy_r)),
                      (torso, (torso_dx, torso_dy)), (head, (head_dx, head_dy))]
        frames.append(_compose_layers(layers))
    return frames


def puppet_walk_north(a, n_frames=8, intensity=2):
    """Chuze zezadu (north): symetricky krok, silueta se meni mene nez zepredu.

    Pohled na zada je symetrictejsi nez predni — nevidime oblicej, ramena jsou
    stejna. Nohy se proto hybou symetricky s mensi amplitudou a trup jen mirne
    kmita. Efekt je jemnejsi nez u south, protoze rozdily ze zadu nejsou videt."""
    head, torso, leg_l, leg_r = segment(a)
    amp = max(1, int(intensity))
    frames = []

    for i in range(n_frames):
        t = (i / n_frames) * 2 * math.pi

        # Nohy: stridavy posun v X (mirny — ze zadu neni krok tak videt)
        dx_l = round(amp * 0.6 * math.sin(t))
        dy_l = -round(amp * 0.5 * max(0.0, math.sin(t)))

        dx_r = round(amp * 0.6 * math.sin(t + math.pi))
        dy_r = -round(amp * 0.5 * max(0.0, math.sin(t + math.pi)))

        # Trup: jemny bobbing
        torso_dy = round(amp * 0.3 * math.cos(2 * t))

        # Hlava: jeste jemnejsi
        head_dy = torso_dy + round(amp * 0.15 * math.sin(2 * t - 0.3))

        if math.sin(t) >= 0:
            layers = [(leg_r, (dx_r, dy_r)), (leg_l, (dx_l, dy_l)),
                      (torso, (0, torso_dy)), (head, (0, head_dy))]
        else:
            layers = [(leg_l, (dx_l, dy_l)), (leg_r, (dx_r, dy_r)),
                      (torso, (0, torso_dy)), (head, (0, head_dy))]
        frames.append(_compose_layers(layers))
    return frames


def puppet_hit(a, n_frames=4, intensity=2):
    """Zasah: kratky knockback dozadu + navrat.

    1-3 framy posun dozadu (zaporne X), posledni frame je zpet na miste.
    Jednodussi nez attack — v TD hre se pouziva pro reakci na utok veze.
    Posledni frame musi byt totozny s klidovym stavem."""
    head, torso, leg_l, leg_r = segment(a)
    amp = max(1, int(intensity))

    # Keyframes: zasah(-1.2) → overshoot(-0.6) → bounce(0.3) → klid(0)
    kx = [-1.2, -0.6, 0.3, 0.0]
    ky = [0.4, 0.2, -0.1, 0.0]
    while len(kx) < n_frames:
        kx.append(0.0)
        ky.append(0.0)

    frames = []
    for i in range(n_frames):
        bx = kx[i] if i < len(kx) else 0.0
        by = ky[i] if i < len(ky) else 0.0

        frames.append(_compose_layers([
            (leg_l, (round(-amp * bx * 0.15), 0)),
            (leg_r, (round(-amp * bx * 0.15), 0)),
            (torso, (round(amp * bx), round(amp * by))),
            (head, (round(amp * bx * 1.2), round(amp * by * 0.6))),
        ]))
    return frames


KINDS = {
    "walk": puppet_walk,
    "idle": puppet_idle,
    "attack": puppet_attack,
    "death": puppet_death,
    "walk_side": puppet_walk_side,
    "walk_north": puppet_walk_north,
    "hit": puppet_hit,
}


def puppet_animate(a, kind="walk", intensity=None, n_frames=None):
    """Jediny vstupni bod pro vsechny druhy animace.

    intensity=None znamena "zvolej sam podle velikosti spritu":
    32x32 → 2, 64x64 → 3. Explicitni hodnota 1..5 prebiji automatiku.

    Vraci seznam RGBA poli se stejnymi rozmery jako vstup."""
    func = KINDS.get(kind)
    if func is None:
        raise ValueError(f"neznámý druh animace: {kind} (znám: {', '.join(KINDS)})")

    if intensity is None:
        side = max(a.shape[0], a.shape[1])
        intensity = 3 if side >= 48 else 2

    kwargs = {"intensity": intensity}
    if n_frames is not None:
        kwargs["n_frames"] = n_frames

    return func(a, **kwargs)


# ------------------------------------------------------------------ CLI


def main():
    """CLI pro testovani:
        python tools/puppet_anim.py <sprite.png> <kind> [outdir] [--intensity N]
    """
    import argparse
    from PIL import Image

    ap = argparse.ArgumentParser(description="Procedurální animátor spritů bez AI.")
    ap.add_argument("sprite", help="cesta ke sprite PNG")
    ap.add_argument("kind", choices=sorted(KINDS), help="druh animace")
    ap.add_argument("outdir", nargs="?", default=None,
                    help="výstupní složka (default: vedle spritu)")
    ap.add_argument("--intensity", type=int, default=None, help="síla pohybu 1-5")
    ap.add_argument("--frames", type=int, default=None, help="počet framů")
    args = ap.parse_args()

    a = np.array(Image.open(args.sprite).convert("RGBA"))
    print(f"vstup: {a.shape[1]}×{a.shape[0]}, "
          f"{int((a[..., 3] > 32).sum())} neprusvitných pixelů")

    frames = puppet_animate(a, args.kind, args.intensity, args.frames)

    outdir = args.outdir or os.path.splitext(args.sprite)[0] + f"_{args.kind}"
    os.makedirs(outdir, exist_ok=True)
    for i, f in enumerate(frames, 1):
        p = os.path.join(outdir, f"frame_{i}.png")
        Image.fromarray(f, "RGBA").save(p)
    print(f"hotovo: {len(frames)} framů v {outdir}")


if __name__ == "__main__":
    main()
