# Zadava hlavy vezi do PixelLabu. Veze jsou SPOJENCI-TVOROVE, ne rekvizity.
#
# PROC create_image_pixflux
#
# Zmereno ve schematu (build/pixellab_tools.json): pixflux je jediny textovy nastroj,
# ktery bere `isometric` i `color_image`. Oboji se sice v druhem kole NEPOUZIVA (viz
# nize), ale zbytek parametru sedi a je to 1 generovani misto 20-40 u create_character.
#
# POUCENI Z PRVNIHO KOLA (21. 8. 2026) -- proc se prvni rodina "nehodila"
#
# Zmereno na hotovych spritech, ne odhadnuto:
#
#   |              | nepratele | prvni veze |
#   | platno       | 48x48     | 112x112    |
#   | sytost       | 0,33-0,95 | 0,15-0,45  |
#   | BAREV        | 22-24     | 6-8        |
#   | tmavy obrys  | 70-84 %   | 17-96 %    |
#
# Tri MOJE chyby, ne chyby nastroje:
#
# 1) VYNUCENA PALETA je zabila. `color_image` s osmi svetly dal presne osm barev --
#    cil "telo 300" sedl napoprve, ale vysledek byl PLOCHY PREDMET. Nepratele ploche
#    nejsou: maji 22-24 barev a dithering. Jas se proto sesazuje az POTOM
#    (tools/tower_band.py), ktery uz umi ztlumit telo a nechat akcent svitit.
#
#    Pozor na zamenu s TERENEM: tam je plochost spravne (docs/art/iso_bible.md kap. 2b),
#    protoze pozadi ma byt ticho. Herci ticho byt nemaji.
#
# 2) ISOMETRIC=TRUE byla spatna projekce. Prompty hotovych nepratel (list_characters)
#    doslova rikaji "front-facing low top-down RPG perspective, ZERO ISOMETRIC TILT".
#    Veze kreslene izometricky a nepratele zepredu jsou dve projekce na jedne desce.
#
# 3) MRTVE REKVIZITY misto POSTAV. Kazdy nepritel je TVOR UDELANY Z PREDMETU: popcorn
#    ma nohy, hraci automat ruce, energetak sovi oblicej. Bedynka, lampa a katapult
#    nemaji nic. Hra uz spojence-tvory ma (brokolicovi rytiri z Nutrition Guild),
#    takze tvorove jsou i konzistentni volba.
#
#   python tools/pl_tower.py submit focus_timer
#   python tools/pl_iso.py poll tower_focus_timer      # ledger je spolecny
#   python tools/pl_iso.py pull tower_focus_timer
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixellab  # noqa: E402
import pl_iso  # noqa: E402

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## PREDMET + OBLICEJ + KONCETINY + postoj.
##
## Predmet rika, CO TA VEZ DELA -- odvozeno z data/habits/*.tres, ne z jejiho jmena
## (real_hobby je "Deep Reading" a strili utrzene stranky; accountability je "Nutrition
## Guild" a posila zeleninove obrance). Tvor ji dava zivot a sesazuje ji k nepratelum.
##
## Vsechny habity maji has_own_pedestal = true -- hra pod ne nekresli sokl, takze kazdy
## tvor musi stat na vlastnich nohou nebo na vlastni zakladne.
TOWERS = {
    "focus_timer": (
        "a round red tomato kitchen timer creature standing on two short sturdy legs, "
        "its face is a pale clock dial with two small eyes and black clock hands, "
        "a small brass bell on top of its head, a green leaf collar, "
        "calm determined stance"),
    "mindfulness": (
        "a calm gunner creature made of a squat machine gun on stubby tripod legs, "
        "a round pale face with half-closed serene eyes above the barrel, a neat stack "
        "of soft lilac meditation cushions loaded on its back as ammunition"),
    "exercise": (
        "a stout wooden catapult creature with two thick plank legs and stubby arms, "
        "a determined blocky face carved into its frame, holding a heavy black iron "
        "kettlebell in its bucket arm"),
    "real_hobby": (
        "a big open hardcover book creature with two thin legs and paper-thin arms, "
        "two round eyes on its open pages, loose pale pages tearing off its top edge "
        "and flying away, a worn leather cover"),
    "accountability": (
        "a friendly wooden market crate creature on two short legs with little arms, "
        "a cheerful face on the crate front, packed full of bright green broccoli "
        "spilling over the top, a small cloth awning like a hat"),
    "anchor": (
        "a warm desk lamp creature with a heavy round base for feet and a bent metal "
        "neck, its wide domed shade tilted like a head with two glowing eyes "
        "underneath, casting a warm yellow glow, steady watchful posture"),
    "zen_pulsar": (
        "a bronze singing bowl creature sitting cross-legged on a round cushion, "
        "two closed serene eyes on the bowl front, holding a small wooden mallet, "
        "one faint ring of sound around its rim"),
    "focus_pillar": (
        "a tall hourglass creature in a heavy wooden frame with two short plank legs, "
        "two round eyes in the upper glass bulb, pale sand caught mid-fall inside, "
        "thick turned wooden posts like arms"),
}

## Opsano z promptu HOTOVYCH nepratel (list_characters), aby nova rodina sedla do te
## stare. Klicove je "zero isometric tilt" -- nepratele jsou kresleni ZEPREDU.
CRAFT = ("64x64 pixel art character sprite, front-facing low top-down RPG perspective "
         "aligned straight to the square grid, zero isometric tilt. "
         "Gritty pixel dithering, high contrast, crisp dark outline, strong readable "
         "silhouette, no text, no floor shadow, no baked ground shadow, "
         "clean transparent background")


def submit(name):
    if name not in TOWERS:
        raise SystemExit("znam: " + ", ".join(TOWERS))
    args = dict(
        description="A friendly habit ally: %s. %s" % (TOWERS[name], CRAFT),
        # 64x64 jako nepratele (zmereno: platno 48x48, obsah az 40x48). Prvni kolo slo
        # na 112x112 a veze byly 2,3x vetsi nez nepratele -- prevalcovaly desku.
        width=64, height=64,
        no_background=True,
        # ZADNA vynucena paleta a ZADNA izometrie -- viz poučeni v hlavicce.
        isometric=False,
        view="low top-down",
        outline="single color black outline",
        shading="basic shading",
        detail="medium detail",
        text_guidance_scale=8.0,
        seed=6200 + sorted(TOWERS).index(name),
    )
    c = pixellab.Client()
    text, _ = c.call("create_image_pixflux", args)
    jid = pl_iso.extract_id(text)
    led = pl_iso.load_ledger()
    key = "tower_" + name
    led[key] = {"tool": "create_image_pixflux", "args": args, "id": jid,
                "raw": text[:800], "submitted": time.strftime("%Y-%m-%d %H:%M:%S")}
    pl_iso.save_ledger(led)
    print("submit %s: id=%s" % (key, jid))
    if not jid:
        print(text[:600])


def _main():
    if len(sys.argv) < 3:
        raise SystemExit("pouziti: pl_tower.py submit <jmeno> [...]  |  rotate <jmeno> <ref.png>")
    if sys.argv[1] == "submit":
        for n in sys.argv[2:]:
            submit(n)
    elif sys.argv[1] == "rotate":
        rotate(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "rotobj":
        rotobj(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit("znam: submit, rotate, rotobj")


# ------------------------------------------------------------------- 8 smeru
#
# PROC PIXELLAB A NE ROTACE BITMAPY
#
# Izometricky objekt otoceny o 90 stupnu NENI tentyz obrazek pootoceny -- vypadalo by,
# ze se preklapi. Presne proto je `head_aims` u cele rodiny vypnute (tower.gd: "art
# would read wrong spinning"). Osm skutecnych pohledu je jedina spravna cesta.
#
# `mode="v3"` s `reference_image_base64` ROTUJE PRESNE TEN SPRITE, ktery dostane, takze
# se vysledek neodchyli od konceptu z Midjourney -- na rozdil od textoveho zadani, kde
# se odchylil vzdycky.
#
#   python tools/pl_tower.py rotate focus_timer build/_tomato_ref64.png
def rotate(name, ref_png):
    import base64
    with open(ref_png, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    args = dict(
        description="A friendly habit ally turret: %s" % TOWERS.get(name, name),
        name="TD tower %s" % name,
        mode="v3",
        size=64,
        n_directions=8,
        view="low top-down",
        reference_image_base64=b64,
    )
    c = pixellab.Client()
    text, _ = c.call("create_character", args)
    jid = pl_iso.extract_id(text)
    led = pl_iso.load_ledger()
    key = "rot_" + name
    led[key] = {"tool": "create_character",
                "args": {k: v for k, v in args.items() if k != "reference_image_base64"},
                "id": jid, "raw": text[:800],
                "submitted": time.strftime("%Y-%m-%d %H:%M:%S")}
    pl_iso.save_ledger(led)
    print("submit %s: id=%s" % (key, jid))
    if not jid:
        print(text[:600])



# PROC create_8_direction_object A NE create_character(v3)
#
# Zmereno 21. 8. 2026 na rajceti: v3 vyrobil osm hezkych pohledu, ale HLAVEN v nich
# nerotovala. Uhly mosazne hlavne vysly -9, +3, +1, -33, -104, -137, -177, +34 stupnu --
# tri ruzne "smery" mely hlaven na temze miste a rozestupy nebyly 45 stupnu.
#
# Duvod: v3 bere vstup jako POSTAVU a za jeji obliceje vzal ciferník. Hlaven je pro nej
# bocni privesek, ktery nechal viceméne stat. Na divani to obstoji, na mireni ne.
#
# `create_8_direction_object` je od PROPU -- jeho vlastni popis rika "reference image of
# an OBJECT/item ... works well for props (barrels, chests)". Otaci teleso, ne postavu.
#
#   python tools/pl_tower.py rotobj focus_timer build/_tomato_ref64.png
def rotobj(name, ref_png):
    import base64
    with open(ref_png, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    args = dict(
        # Popis se drzi zneni, ktere PROSLO. 22. 8. 2026 stacilo pridat "LONG ... jutting
        # far out from its side" a PixelLab to odmitl s "Generation blocked by content
        # policy" -- slova "turret" ani "barrel" v tom nejsou, ta prosla dvakrat.
        # Velikost hlavne se tedy rika neutralne ("large flared"), ne durazem.
        description="a red tomato-shaped kitchen timer turret with a large flared brass "
                    "horn barrel on its side and a pale clock dial on its front, seated "
                    "in a low round riveted brass turret ring it swivels in",
        # ZADNE nozky ani sokl v popisu: hra kresli spolecny izometricky sokl
        # (assets/towers/pedestal_iso.png) a rotujici telo na nem stoji. Co stoji
        # na zemi, se otacet nesmi -- viz tools/tower_pedestal.py.
        # size se NEPOSILA: pri reference_image ho nastroj odmita ("the image dimensions
        # determine the output size"). Predloha je 64x64, takze vystup bude taky 64.
        view="low top-down",
        reference_image_base64=b64,
    )
    c = pixellab.Client()
    text, _ = c.call("create_8_direction_object", args)
    jid = pl_iso.extract_id(text)
    led = pl_iso.load_ledger()
    key = "obj_" + name
    led[key] = {"tool": "create_8_direction_object",
                "args": {k: v for k, v in args.items() if k != "reference_image_base64"},
                "id": jid, "raw": text[:800],
                "submitted": time.strftime("%Y-%m-%d %H:%M:%S")}
    pl_iso.save_ledger(led)
    print("submit %s: id=%s" % (key, jid))
    if not jid:
        print(text[:600])

if __name__ == "__main__":
    _main()
