# Kostry pro ControlNet: tvar zvenci misto tvaru z promptu.
#
# PROC TENHLE SOUBOR VUBEC EXISTUJE
#
# Faze 2 zmerila, ze img2img pohled nezmeni — sestnact "smeru" byly cele celni pohledy
# (docs/art/rotace.md). ControlNet je jedina zbyla cesta, ale je u nej past, kterou puvodni
# plan mel spatne:
#
#     ControlNet NEUMI OTOCIT POSTAVU. Umi ji nakreslit do tvaru, ktery mu das.
#
# Puvodni plan chtel ridici obrazek delat ze siluety zakladniho spritu. Jenze zakladni
# sprite je CELNI pohled, takze by se jeho celni silueta vnutila i "severu" a "vychodu" —
# tedy presne ta vada z faze 2, tentokrat vynucena konstrukci. Otazka neni "jak zapojit
# ControlNet", ale ODKUD VZIT TVAR PRO KAZDY SMER.
#
# Tenhle soubor je odpoved: kostra se kresli z uhlu, ne z predlohy. Telo je popsane v
# souradnicich POSTAVY (do strany, dopredu, dolu) a promita se do obrazovky podle natoceni.
# Osm smeru je pak osm hodnot jednoho uhlu, ne osm rucnich kreseb.
#
# Kde to nefunguje: openpose je kostra CLOVEKA. Na avokadoveho mnicha sedne, na kouli mlhy
# nema co popsat. To ale neni tak zle, jak to zni — u koule je pohled zezadu skoro tentyz
# obrazek jako zepredu, takze tam, kde kostra nedava smysl, otaceni skoro neni potreba.
#
# Format je COCO18, jak ho kresli openpose annotator (ridici obrazky, na kterych se
# ControlNet trenoval): cerne pozadi, koncetiny jako barevne elipsy pres sebe s pruhlednosti
# 0.6, klouby jako plne kotouce. Barvy nejsou dekorace — model je cte jako urceni, ktera
# cast tela to je, takze se nesmi menit.
import math

from PIL import Image, ImageDraw

# Poradi bodu COCO18. Index je soucast formatu, neprehazovat.
NOSE, NECK = 0, 1
R_SHO, R_ELB, R_WRI = 2, 3, 4
L_SHO, L_ELB, L_WRI = 5, 6, 7
R_HIP, R_KNE, R_ANK = 8, 9, 10
L_HIP, L_KNE, L_ANK = 11, 12, 13
R_EYE, L_EYE, R_EAR, L_EAR = 14, 15, 16, 17

# Dvojice, ktere spojuje koncetina. Poradi urcuje i barvu (COLORS[k] pro k-tou koncetinu).
LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10),
         (1, 11), (11, 12), (12, 13), (1, 0), (0, 14), (14, 16), (0, 15), (15, 17)]

COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0),
          (85, 255, 0), (0, 255, 0), (0, 255, 85), (0, 255, 170), (0, 255, 255),
          (0, 170, 255), (0, 85, 255), (0, 0, 255), (85, 0, 255), (170, 0, 255),
          (255, 0, 255), (255, 0, 170), (255, 0, 85)]

# Telo v souradnicich POSTAVY. Trojice (u, w, y):
#
#   u  do strany, kladne k LEVE ruce postavy
#   w  dopredu, tedy tam, kam se postava diva
#   y  dolu, 0 je temeno a 1 jsou paty
#
# DVA KANONY A PROC. Openpose se ucil na FOTKACH LIDI, takze osmihlavy kanon je to, co
# model zna — a taky to, co poslusne nakresli. Jenze hra je chibi: avokadovy mnich ma
# hlavu pres pulku vysky a ghoul zhruba 45 %. Lidska kostra proto vyrobi hubeneho
# clovicka, ktery do hry nepatri, i kdyz ji model poslechne dokonale.
#
# Zmereno 18. 8. 2026 na prvni kourove zkousce: lidsky kanon dal z chibi ghoula lanky
# postavu, znamka 7,4. Odtud druhy kanon.
#
# Obchod je tady na obe strany a nedá se z nej vyklouznout:
#
#   human  model kostru zna a poslechne ji, ale vysledek neni v herním stylu
#   chibi  vysledek je ve stylu, ale kostra je mimo to, co model videl pri treninku,
#          takze ji muze brat volneji
#
# Ktery vyhraje, rozhoduje mereni, ne uvaha — proto tu jsou oba.
CANONS = {
    # Osmihlavy dospely clovek. To, na cem se ControlNet ucil.
    "human": {
        NOSE:  (0.000, 0.055, 0.055),
        NECK:  (0.000, 0.000, 0.135),
        R_SHO: (-0.105, 0.000, 0.155),
        L_SHO: (0.105, 0.000, 0.155),
        R_ELB: (-0.135, 0.000, 0.305),
        L_ELB: (0.135, 0.000, 0.305),
        R_WRI: (-0.145, 0.000, 0.455),
        L_WRI: (0.145, 0.000, 0.455),
        R_HIP: (-0.062, 0.000, 0.500),
        L_HIP: (0.062, 0.000, 0.500),
        R_KNE: (-0.068, 0.000, 0.720),
        L_KNE: (0.068, 0.000, 0.720),
        R_ANK: (-0.072, 0.000, 0.945),
        L_ANK: (0.072, 0.000, 0.945),
        R_EYE: (-0.028, 0.058, 0.038),
        L_EYE: (0.028, 0.058, 0.038),
        R_EAR: (-0.055, 0.012, 0.048),
        L_EAR: (0.055, 0.012, 0.048),
    },
    # Zhruba tri hlavy. KOMPROMIS, ne odmerena hra: hra sama je na dve hlavy (avokadovy
    # mnich ma hlavu pres pulku vysky), jenze pri dvou hlavach se hlavove body odtrhnou od
    # krku do siroke tycky, ktera se vznasi nad telem — a to uz model necte jako cloveka,
    # ale jako dva objekty. Tri hlavy jsou nejchibiovatejsi kanon, ktery jeste drzi
    # pohromade. Jestli to staci, rozhodne mereni, ne tenhle odstavec.
    "chibi": {
        NOSE:  (0.000, 0.130, 0.200),
        NECK:  (0.000, 0.000, 0.340),
        R_SHO: (-0.120, 0.000, 0.400),
        L_SHO: (0.120, 0.000, 0.400),
        R_ELB: (-0.155, 0.000, 0.550),
        L_ELB: (0.155, 0.000, 0.550),
        R_WRI: (-0.170, 0.000, 0.680),
        L_WRI: (0.170, 0.000, 0.680),
        R_HIP: (-0.070, 0.000, 0.620),
        L_HIP: (0.070, 0.000, 0.620),
        R_KNE: (-0.075, 0.000, 0.800),
        L_KNE: (0.075, 0.000, 0.800),
        R_ANK: (-0.080, 0.000, 0.960),
        L_ANK: (0.080, 0.000, 0.960),
        R_EYE: (-0.060, 0.125, 0.160),
        L_EYE: (0.060, 0.125, 0.160),
        R_EAR: (-0.140, 0.025, 0.180),
        L_EAR: (0.140, 0.025, 0.180),
    },
}

# Kanon, ktery se pouzije, kdyz volajici nerekne jinak. Chibi proto, ze tenhle modul
# existuje pro tuhle hru a ta je chibi — lidsky kanon je tu na srovnani.
CANON = "chibi"

BODY = CANONS["human"]      # jmeno z prvni verze; nechano, at se na nej da odkazat

# Vykrok: o kolik dopredu/dozadu jde ktery kloub. Prava ruka a leva noha jdou dopredu
# spolu, jak to dela clovek pri chuzi.
#
# Neni to jen ozdoba. Z boku (uhel 90) maji obe ramena TOTEZ x, protoze do strany se
# promitne nula — bez vykroku by kostra z profilu zdegenerovala do jedne cary a model by
# z ni nevycetl nic. Vykrok koncetiny rozestoupi prave v tom pohledu, kde je to potreba.
STRIDE = {R_ELB: 0.05, R_WRI: 0.09, L_ELB: -0.05, L_WRI: -0.09,
          R_KNE: -0.06, R_ANK: -0.10, L_KNE: 0.06, L_ANK: 0.10}

# Vykrok je v jednotkach vysky, ale chibi ma koncetiny kratsi (~0,3 vysky proti ~0,45 u
# cloveka), takze tentyz vykrok by u nej byl nepomerne velky. Tohle to srovna.
CANON_STRIDE = {"human": 1.0, "chibi": 0.7}

# Odkud uz kloub nevidime. Oblicej zmizi pri pohledu zezadu, usi drzi skoro porad — presne
# tak se chova i skutecny annotator na fotce cloveka zezadu. Ostatni klouby se kresli vzdy:
# openpose odhaduje i zakryte telo.
HIDE_BEHIND = {NOSE: -0.02, R_EYE: -0.02, L_EYE: -0.02, R_EAR: -0.05, L_EAR: -0.05}


def project(yaw, stride=0.35, canon=None):
    """Body tela promitnute do obrazovky pro dane natoceni -> {index: (x, y, hloubka)}.

    x je vodorovne v jednotkach VYSKY postavy (0 je osa), y svisle (0 temeno, 1 paty),
    hloubka je kladna smerem ke kamere a slouzi jen k rozhodnuti, co je videt.

    Uhel se pocita tak, jak ho ma gen.DIRECTIONS: 0 = celem k divakovi (jih), 90 = doprava
    (vychod), 180 = zady (sever). Promitnuti je jedna otocka kolem svisle osy:

        x       = u*cos(uhel) + w*sin(uhel)
        hloubka = w*cos(uhel) - u*sin(uhel)

    Zkouska: pri 0 je x rovno u (vidime sirku ramen) a hloubka je w (nos miri k nam), pri
    90 je x rovno w (ramena splynou, nos ukazuje doprava) a pri 180 je x rovno -u, tedy
    obraz je zrcadlove prevraceny a nos ma zapornou hloubku — neni videt."""
    canon = canon or CANON
    body = CANONS[canon]
    stride = stride * CANON_STRIDE.get(canon, 1.0)
    t = math.radians(yaw)
    cos, sin = math.cos(t), math.sin(t)
    out = {}
    for i, (u, w, y) in body.items():
        w = w + STRIDE.get(i, 0.0) * stride
        out[i] = (u * cos + w * sin, y, w * cos - u * sin)
    return out


def _ellipse_poly(p0, p1, width, steps=24):
    """Elipsa natazena z p0 do p1 jako mnohouhelnik. Tohle kresli annotator jako koncetinu;
    tlusta cara by mela jine konce a model je zvykly na tenhle tvar."""
    (x0, y0), (x1, y1) = p0, p1
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    length = math.hypot(x1 - x0, y1 - y0)
    ang = math.atan2(y1 - y0, x1 - x0)
    ca, sa = math.cos(ang), math.sin(ang)
    a, b = length / 2.0, width / 2.0
    pts = []
    for k in range(steps):
        t = 2.0 * math.pi * k / steps
        ex, ey = a * math.cos(t), b * math.sin(t)
        pts.append((cx + ex * ca - ey * sa, cy + ex * sa + ey * ca))
    return pts


def skeleton(yaw, size=(1024, 1024), stride=0.35, height=0.86, stick=None, canon=None):
    """Ridici obrazek openpose pro dane natoceni. Vraci PIL RGB na cernem pozadi.

    `stick` je sirka koncetiny v pixelech. Vychozi hodnota roste s platnem, protoze
    annotator kresli sirku 4 na obrazku 512 — na 1024 je pak 8 tataz kostra, jen vetsi.
    Kdyby zustala 4, dostal by model nitkovou kostru, jakou pri treninku nevidel."""
    W, H = size
    S = min(W, H)
    stick = stick if stick else max(2, round(4.0 * S / 512.0))
    dot = max(2, round(stick * 1.0))

    pts = project(yaw, stride, canon)
    fig_h = H * height                       # vyska postavy v pixelech
    top = (H - fig_h) / 2.0
    cx = W / 2.0

    def to_px(i):
        x, y, _ = pts[i]
        return (cx + x * fig_h, top + y * fig_h)

    vis = {i: pts[i][2] > HIDE_BEHIND.get(i, -9.0) for i in pts}

    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    # Koncetiny se kresli od nejvzdalenejsi k nejblizsi, aby pri pohledu z boku prekryla
    # blizsi ruka tu vzadu, a ne naopak.
    order = sorted(range(len(LIMBS)),
                   key=lambda k: (pts[LIMBS[k][0]][2] + pts[LIMBS[k][1]][2]) / 2.0)
    for k in order:
        i, j = LIMBS[k]
        if not (vis[i] and vis[j]):
            continue
        # Pruhlednost 0.6 pres uz nakreslene: annotator to dela pres addWeighted a
        # prekryvajici se koncetiny tim dostanou charakteristicky poloprusvitny prekryv.
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(_ellipse_poly(to_px(i), to_px(j), stick),
                                      fill=COLORS[k] + (153,))
        canvas = Image.alpha_composite(canvas.convert("RGBA"), layer).convert("RGB")

    dr = ImageDraw.Draw(canvas)
    for i in sorted(pts, key=lambda i: pts[i][2]):
        if not vis[i]:
            continue
        x, y = to_px(i)
        dr.ellipse([x - dot, y - dot, x + dot, y + dot], fill=COLORS[i])
    return canvas


def for_direction(direction, dirs, **kw):
    """Kostra pro pojmenovany smer. `dirs` je gen.DIRECTIONS — poradi v nem JE uhel
    (index krat 45), takze se tu nedrzi druha kopie tehoz slovniku, ktera by se casem
    rozesla s tou v gen.py."""
    try:
        yaw = dirs.index(direction) * (360.0 / len(dirs))
    except ValueError:
        yaw = 0.0
    return skeleton(yaw, **kw)


def sheet(path, dirs, size=256, **kw):
    """Kontaktni list vsech smeru vedle sebe. Kostru je levne zkontrolovat okem drive, nez
    se na ni pusti karta — spatne otocena kostra by se jinak poznala az na spritech."""
    ims = [(d, skeleton(i * (360.0 / len(dirs)), size=(size, size), **kw))
           for i, d in enumerate(dirs)]
    gap, pad = 6, 16
    out = Image.new("RGB", (gap + len(ims) * (size + gap), pad + size + gap + pad),
                    (24, 22, 30))
    dr = ImageDraw.Draw(out)
    for k, (d, im) in enumerate(ims):
        x = gap + k * (size + gap)
        out.paste(im, (x, pad))
        dr.text((x, pad + size + 4), d, fill=(200, 195, 210))
    out.save(path)
    return path
