"""Print the content roster — habits, distractions, interventions — read from data/*.tres.

Written as a generator instead of a hand-kept table on purpose: three separate docs in
this repo already carry a "shipped roster differs from this table" warning, because a
list of content maintained by hand drifts the moment anyone touches a .tres. This reads
the same files the game reads.

    python tools/roster.py            # human table
    python tools/roster.py --md       # markdown, what docs/ROSTER.md is made of
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse(path):
    """Values from a .tres [resource] block. Absent keys mean 'script default'."""
    out = {}
    text = io.open(path, encoding="utf-8").read()
    text = text[text.find("[resource]"):]
    for line in text.splitlines():
        m = re.match(r"(\w+) = (.*)", line.strip())
        if m:
            out[m.group(1)] = m.group(2).strip()
    out["_file"] = os.path.basename(path)
    return out


def s(d, key, default=""):
    v = d.get(key, default)
    return str(v).strip('"').lstrip("&").strip('"')


def f(d, key, default=0.0):
    try:
        return float(s(d, key, default))
    except ValueError:
        return default


def upgrades_of(d):
    """`upgrades = Array[StringName]([&"focus_timer_2"])` -> ['focus_timer_2']."""
    raw = d.get("upgrades", "")
    return re.findall(r'&"([a-z_0-9]+)"', raw)


# Script defaults, for the fields that matter when a .tres overrides nothing.
# notification.tres and screen_break.tres are almost entirely defaults, so a roster that
# only read the files would show them as blank.
DIST_DEFAULTS = {"display_name": "Notification", "max_health": "5", "speed": "140.0",
                 "compulsion": "0", "rationalization": "0", "dopamine_reward": "1",
                 "focus_damage": "1", "radius": "9.0"}
# "range" was 160.0 here while HabitData's actual script default was 360.0 — a stale
# mirror that made ROSTER.md understate focus_timer (the one habit that authors no range
# of its own) by 200 px. Found during P8b's rescale sweep, 2026-08-30; every other value
# in this dict still matches habit_data.gd exactly. Keep them in step: this table is a
# COPY of the script defaults, and nothing checks it automatically.
HABIT_DEFAULTS = {"build_cost": "30", "willpower_damage": "3", "awareness_damage": "0",
                  "fire_cooldown": "0.10", "range": "180.0"}
INTV_DEFAULTS = {"name": "Screen Break", "type": "damage_aoe", "cooldown": "18.0",
                 "radius": "180.0", "rush_cost": "0"}


def archetypes(d):
    tags = []
    if s(d, "is_boss") == "true":
        tags.append("BOSS")
    if s(d, "is_flying") == "true":
        tags.append("letec")
    if f(d, "disrupt_interval") > 0:
        tags.append("disruptor")
    if f(d, "haste_interval") > 0:
        tags.append("energiser")
    if f(d, "overdrive_hp_pct") > 0:
        tags.append("overdrive")
    if f(d, "fast_shot_damage_mult", 1.0) < 1.0:
        tags.append("golem")
    return tags


def habit_tags(d):
    tags = []
    if s(d, "is_blocker") == "true":
        tags.append("barracks")
    if s(d, "aoe") == "true":
        tags.append("AoE")
    if f(d, "boredom") > 0:
        tags.append("DoT %.0f/s" % f(d, "boredom"))
    # The field on HabitData is `slow`, not `slow_factor` — this read the wrong key and
    # silently never fired, so Mindfulness' headline effect was missing from the table
    # this generator exists to keep honest.
    if 0.0 < f(d, "slow", 0.0) < 1.0:
        tags.append("slow %.0f%%" % ((1.0 - f(d, "slow")) * 100))
    if f(d, "stun_duration") > 0:
        tags.append("stun %.1fs" % f(d, "stun_duration"))
    if s(d, "dispel_haste") == "true":
        tags.append("dispel")
    if f(d, "vulnerable_mult", 1.0) > 1.0:
        tags.append("vuln +%.0f%%/%.0fs"
                    % ((f(d, "vulnerable_mult", 1.0) - 1.0) * 100, f(d, "vulnerable_duration")))
    if s(d, "has_work_cycle") == "true":
        tags.append("pomodoro")
    up = upgrades_of(d)
    if up:
        tags.append("→ " + ", ".join(up))
    return tags


def load(sub, defaults):
    out = []
    for p in sorted(glob.glob(os.path.join(ROOT, "data", sub, "*.tres"))):
        d = parse(p)
        for k, v in defaults.items():
            d.setdefault(k, '"%s"' % v)
        d["id"] = s(d, "id") or os.path.basename(p)[:-5]
        out.append(d)
    return out


# Godot vklada `uid="uid://..."` MEZI `type=` a `path=`, kdykoli ma cilovy zdroj UID --
# a ma ho jen nekdy (z 13 distrakci ho nesou tri). Puvodni vzor tady vyzadoval `path=`
# hned za `type="Resource"`, takze prave ty tri radky tise preskakoval a ROSTER.md pak
# tvrdil, ze doomscroll je jen v L2 a social_media_binge jen jako boss L2, ackoli je
# level_1 spawnoval taky. Vzor proto nesmi predepisovat, co mezi atributy lezi -- jen
# ze to nesmi prelezt pres `]`, tedy mimo tenhle jeden ext_resource.
# Regresi hlida tools/test_roster.py proti tools/_fixtures/level_uid_fixture.tres.
EXT_DISTRACTION_RE = re.compile(
    r'\[ext_resource\b[^\]]*?\btype="Resource"'
    r'[^\]]*?\bpath="res://data/distractions/([a-z_0-9]+)\.tres"'
    r'[^\]]*?\bid="([^"]+)"[^\]]*\]')


def distraction_ext_ids(text):
    """ext_resource id -> distraction id, pro jeden .tres jako text."""
    return {ext_id: name for name, ext_id in EXT_DISTRACTION_RE.findall(text)}


def levels(paths=None):
    """Which level each distraction appears in, and from which wave.

    `paths` je tu kvuli testovatelnosti: bez nej se bere zivy obsah data/levels/,
    s nim se da pustit nad fixture, ktera v data/ lezet nesmi.
    """
    where = {}
    if paths is None:
        paths = sorted(glob.glob(os.path.join(ROOT, "data", "levels", "level_*.tres")))
    for p in paths:
        if p.endswith(".bak") or ".bak" in p:
            continue
        text = io.open(p, encoding="utf-8").read()
        ext = distraction_ext_ids(text)
        lvl = os.path.basename(p)[:-5].replace("level_", "L")
        for block in text.split("[sub_resource")[1:]:
            m = re.search(r'distraction = ExtResource\("([^"]+)"\)', block)
            if not m or m.group(1) not in ext:
                continue
            w = re.search(r"from_wave = (\d+)", block)
            where.setdefault(ext[m.group(1)], []).append("%s(w%s)" % (lvl, w.group(1) if w else "1"))
        b = re.search(r'boss = ExtResource\("([^"]+)"\)', text)
        if b and b.group(1) in ext:
            where.setdefault(ext[b.group(1)], []).append("%s(boss)" % lvl)
    return where


def main():
    md = "--md" in sys.argv
    where = levels()
    bar = (lambda *a: None) if md else print

    dists = load("distractions", DIST_DEFAULTS)
    habits = load("habits", HABIT_DEFAULTS)
    intvs = load("interventions", INTV_DEFAULTS)

    if md:
        print("# Roster — co ve hře je\n")
        print("> **Generováno z `data/*.tres`.** Needituj ručně — spusť")
        print("> `python tools/roster.py --md > docs/ROSTER.md`. Ručně psané soupisy")
        print("> v tomhle repu už třikrát zvětraly (viz varování v `docs/core/11`).\n")
        print("## Distrakce (nepřátelé)\n")
        print("| id | jméno | HP | rychlost | comp | rat | Dopamin | Focus dmg | archetyp | kde |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for d in dists:
            print("| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                d["id"], s(d, "display_name"), s(d, "max_health"), s(d, "speed"),
                s(d, "compulsion"), s(d, "rationalization"), s(d, "dopamine_reward"),
                s(d, "focus_damage"), ", ".join(archetypes(d)) or "—",
                " ".join(where.get(d["id"], [])) or "**nikde**"))
        print("\n## Habity (věže)\n")
        print("| id | jméno | cena | Willpower | Awareness | cooldown | dosah | vlastnosti |")
        print("|---|---|---|---|---|---|---|---|")
        for h in habits:
            print("| `%s` | %s | %s | %s | %s | %s | %s | %s |" % (
                h["id"], s(h, "name"), s(h, "build_cost"), s(h, "willpower_damage"),
                s(h, "awareness_damage"), s(h, "fire_cooldown"), s(h, "range"),
                ", ".join(habit_tags(h)) or "—"))
        print("\n## Intervence (aktivní schopnosti)\n")
        print("| id | jméno | typ | cooldown | rádius | cena v Rush |")
        print("|---|---|---|---|---|---|")
        for i in intvs:
            print("| `%s` | %s | `%s` | %s | %s | %s |" % (
                i["id"], s(i, "name"), s(i, "type"), s(i, "cooldown"),
                s(i, "radius"), s(i, "rush_cost")))
        return

    print("=== DISTRAKCE (%d) ===" % len(dists))
    print("%-19s %-19s %5s %6s %5s %5s %5s %6s  %s" %
          ("id", "jméno", "HP", "rychl", "comp", "rat", "dopa", "focus", "archetyp / kde"))
    for d in dists:
        print("%-19s %-19s %5s %6s %5s %5s %5s %6s  %s | %s" % (
            d["id"], s(d, "display_name"), s(d, "max_health"), s(d, "speed"),
            s(d, "compulsion"), s(d, "rationalization"), s(d, "dopamine_reward"),
            s(d, "focus_damage"), ", ".join(archetypes(d)) or "-",
            " ".join(where.get(d["id"], [])) or "NIKDE"))

    print("\n=== HABITY (%d) ===" % len(habits))
    print("%-17s %-18s %5s %5s %5s %7s %7s  %s" %
          ("id", "jméno", "cena", "wp", "aw", "cd", "dosah", "vlastnosti"))
    for h in habits:
        print("%-17s %-18s %5s %5s %5s %7s %7s  %s" % (
            h["id"], s(h, "name"), s(h, "build_cost"), s(h, "willpower_damage"),
            s(h, "awareness_damage"), s(h, "fire_cooldown"), s(h, "range"),
            ", ".join(habit_tags(h)) or "-"))

    print("\n=== INTERVENCE (%d) ===" % len(intvs))
    for i in intvs:
        print("%-17s %-18s %-14s cd=%-6s r=%-6s rush=%s" % (
            i["id"], s(i, "name"), s(i, "type"), s(i, "cooldown"),
            s(i, "radius"), s(i, "rush_cost")))


if __name__ == "__main__":
    main()
