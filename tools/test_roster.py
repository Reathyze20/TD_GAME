"""Regresni test na tools/roster.py -- konkretne na uid= v [ext_resource].

    python tools/test_roster.py     # 0 = OK, 1 = regrese

PROC EXISTUJE PRAVE TENHLE TEST

roster.py cetl levely vzorem, ktery chtel `path=` hned za `type="Resource"`. Godot ale
mezi ne vklada `uid="uid://..."`, kdykoli ma cilovy zdroj UID -- a ten ho ma jen nekdy
(z 13 distrakci tri: doomscroll, energy_drink, social_media_binge). Ty tri radky se tedy
tise preskakovaly a docs/ROSTER.md, coz je GENEROVANY soupis toho, co ve hre je, o nich
lhal. Chyba, ktera nic neshodi a jen tise vynecha data, je presne ta, na kterou je test
potreba nejvic.

Test je Python, ne Godot fixture, protoze testovana vec je Python regex. Fixture ale
NESMI lezet v data/levels/ -- autoload Data nacita cely ten adresar, takze by se z ni
stal obsah hry. Lezi proto v tools/_fixtures/ vedle .gdignore, kam Godot vubec nekouka.
"""
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roster  # noqa: E402

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "_fixtures", "level_uid_fixture.tres")

# Presne ten vzor, ktery v roster.py byl do 29. 8. 2026. Zije uz jen tady, aby test
# dokazal, ze chyba byla skutecna -- test, ktery projde i na rozbite verzi, nic nehlida.
LEGACY_EXT_RE = re.compile(
    r'\[ext_resource type="Resource" path="res://data/distractions/([a-z_0-9]+)\.tres" id="([^"]+)"')

fails = 0


def check(label, ok, detail=""):
    global fails
    if ok:
        print("  ok   %s %s" % (label, detail))
    else:
        fails += 1
        print("  FAIL %s %s" % (label, detail))


def main():
    check("fixture existuje", os.path.exists(FIXTURE), FIXTURE)
    if not os.path.exists(FIXTURE):
        return 1
    text = io.open(FIXTURE, encoding="utf-8").read()

    print("\n-- fixture obsahuje oba tvary, ktere Godot zapisuje --")
    check("je v ni ext_resource BEZ uid=",
          'type="Resource" path="res://data/distractions/notification.tres"' in text)
    check("je v ni ext_resource S uid= mezi type= a path=",
          'type="Resource" uid="uid://dgleeiqemlmu" path="res://data/distractions/doomscroll.tres"'
          in text)

    print("\n-- stary vzor na te fixture SELHAVA (kdyby ne, test nic nehlida) --")
    legacy = {ext_id: name for name, ext_id in LEGACY_EXT_RE.findall(text)}
    check("stary vzor najde notification (radek bez uid=)", "4_notif" in legacy)
    check("stary vzor MINE doomscroll (radek s uid=)", "5_doom" not in legacy,
          "nasel: %s" % sorted(legacy.values()))
    check("stary vzor MINE social_media_binge (boss s uid=)", "6_boss" not in legacy)
    check("stary vzor tedy najde jen 1 ze 3", len(legacy) == 1, "nasel %d" % len(legacy))

    print("\n-- novy vzor najde vsechny tri --")
    found = roster.distraction_ext_ids(text)
    check("notification", found.get("4_notif") == "notification", str(found.get("4_notif")))
    check("doomscroll", found.get("5_doom") == "doomscroll", str(found.get("5_doom")))
    check("social_media_binge", found.get("6_boss") == "social_media_binge",
          str(found.get("6_boss")))
    check("celkem 3 a nic navic", len(found) == 3, "nasel %d: %s" % (len(found), sorted(found)))

    print("\n-- levels() nad fixture vraci spravne vlny i bosse --")
    where = roster.levels([FIXTURE])
    check("notification je ve vlne 1", where.get("notification") == ["Luid_fixture(w1)"],
          str(where.get("notification")))
    check("doomscroll je ve vlne 4 (drive chybel uplne)",
          where.get("doomscroll") == ["Luid_fixture(w4)"], str(where.get("doomscroll")))
    check("social_media_binge je boss (drive chybel uplne)",
          where.get("social_media_binge") == ["Luid_fixture(boss)"],
          str(where.get("social_media_binge")))

    print("\n-- vzor nesmi prelezt z jednoho ext_resource do druheho --")
    # Dva radky za sebou, kde path patri prvnimu a id druhemu. Kdyby vzor smel prekrocit
    # `]`, spojil by je a priradil distrakci cizi ext id -- tise a nedetekovatelne.
    trap = ('[ext_resource type="Resource" path="res://data/distractions/fomo.tres" id="A"]\n'
            '[ext_resource type="Resource" path="res://data/habits/anchor.tres" id="B"]\n')
    trapped = roster.distraction_ext_ids(trap)
    check("fomo dostane sve vlastni id, ne id souseda", trapped == {"A": "fomo"}, str(trapped))

    print("\n-- levels() bez argumentu porad cte zivy obsah --")
    live = roster.levels()
    check("volani bez argumentu nespadne", isinstance(live, dict),
          "%d distrakci ma nekde vyskyt" % len(live))

    print("\n%s (%d failures)" % ("PASSED" if fails == 0 else "FAILED", fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
