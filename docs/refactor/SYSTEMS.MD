## S1 — Charakterizační testy ekonomiky
Model: sonnet
Needs-me: no
Status: done
`scripts/_test_economy_characterization.gd` existuje a je zelený.
Zmapuj, jak se počítá dopamine, jak ho ovlivňuje Tolerance a Streak, jak Quick Hit
zasahuje do obojího. Napiš testy, které zafixují SOUČASNÉ chování včetně hranic.
Hotovo když: 20+ testů, všechny zelené. Chování neměň.

## S2 — Deterministický simulátor levelu
Model: opus
Needs-me: no
Status: done
`scripts/level_simulator.gd` + `_test_level_simulator.gd`, commit `5e2fb9e`.
Headless simulátor, který odehraje level bez renderu podle skriptu rozhodnutí
(kam postavit co, kdy zmáčknout Quick Hit) a vrátí výsledek: přežil/padl,
zbývající Focus, konečná Tolerance, celkový dopamine. Seedovaný, deterministický.
Hotovo když: dvakrát spuštěný stejný seed dá bit-identický výsledek.

## S3 — Report o balanci
Model: sonnet
Needs-me: no
Status: done
`docs/BALANCE.md` existuje.
Pomocí S2 projeď každý level třemi strategiemi (nic nestavět / stavět levné věže
rovnoměrně / spamovat Quick Hit) a zapiš výsledky do docs/BALANCE.md.
Hotovo když: tabulka level × strategie × výsledek. Nedělej závěry, jen data.

## S4 — Palette-swap shader
Model: sonnet
Needs-me: yes
Status: blocked
BLOCKED.md:532 — mechanicky hotovo (`shaders/palette_swap.gdshader`,
`_shot_palette_swap.gd/.tscn`), ale „Hotovo když" žádá posoudit screenshot —
CLAUDE.md stop rule pro vizuální posouzení. Čeká, až se podíváš na
`build/palette_swap_variants.png`.
Shader v shaders/, který mapuje master paletu na alternativní sadu. Použitelný
na sprity distractions. Přidej testovací scénu se třemi variantami stejného spritu.
Hotovo když: scéna existuje, screenshot ukazuje tři barevné varianty.

## S5 — Datová vrstva pro hordy
Model: sonnet
Needs-me: no
Status: obsolete

**PŘEKONÁNO 2026-09-02 (srovnáno se skutečností).** Zadání níž stojí na tom, že „pozice =
vzdálenost podél cesty" — a to **přestalo platit**. `PATHFINDING.MD` P4 to říká ve vlastní
hlavičce: *„POZOR — zadání bylo opraveno. Starší znění (S5 v SYSTEMS.md) mluvilo o pozici
jako o vzdálenosti podél cesty. To platilo jen pro jednu cestu a s flow fieldem už
neplatí."* P4 (`9d47688`) místo toho postavil pozici jako `Vector2` na mřížce a zaměřování
jako rozsahový dotaz nad **prostorovým hashem** (`Game._distraction_hash`), což je ta část
S5, která smysl dávala — a bench je v `docs/PERF.md` §„Tower targeting spatial hash (P4)".

Zbytek S5 (přepsat `Distraction` z uzlů na pole struktur) nikdo nepotřebuje: P5 vyřešil
výkon vykreslování bez toho, viz S6.
BLOCKED.md:427 — nezapočato. Zásah do celé simulační smyčky nepřátel (enemy.gd,
StatusManager, ArcProfile, GridProjection targeting) a jedna reálná otázka:
má procedurální vektorová kresba DistractionAnimatoru (CLAUDE.md komponenta)
tuhle přestavbu přežít, a jak?
Přepiš stav nepřátel z uzlů na pole struktur: pozice = vzdálenost podél cesty,
pole seřazené, zaměřování jako rozsahový dotaz. Vykreslování zatím neřeš.
Hotovo když: S1 testy zelené, bench z T11 zopakovaný a zapsaný do PERF.md.

## S6 — Vykreslování hordy přes MultiMeshInstance2D
Model: sonnet
Needs-me: no
Status: done

**HOTOVO 2026-09-02 (srovnáno se skutečností) — shipnulo to `PATHFINDING.MD` P5**, commit
`bd39167`, jako `scripts/components/horde_renderer.gd` + `scripts/components/horde_atlas.gd`,
s fixture `_test_horde_renderer` a benchem v `docs/PERF.md` §„Horde performance, MultiMesh
batching (P5)".

**Rozpor, na kterém tenhle úkol stál, se vyřešil, ne obešel.** Poznámka níž správně říká,
že `MultiMeshInstance2D` neumí per-instanci `_draw()`, na čem stojí `DistractionAnimator`.
P5 to vyřešil `HordeAtlas` — procedurální kresba se pořád dělá, jen se **předpeče do
atlasu** a MultiMesh z něj bere instance. `DistractionAnimator` tedy zůstal, jak ho
`CLAUDE.md` popisuje.
BLOCKED.md:427 (stejný záznam jako S5 — jsou to dvě strany jednoho úkolu).
MultiMeshInstance2D neumí per-instanci `_draw()`, což je přesně to, na čem stojí
DistractionAnimator; rozpor nevyřešitelný bez tvého rozhodnutí. Čeká na S5.
Nahraď jeden-uzel-na-nepřítele jedním MultiMeshInstance2D na hordu.
Hotovo když: bench pro N=500 aspoň 3× rychlejší než baseline, testy zelené.

## S7 — Tvar spawnu ve waves
Model: sonnet
Needs-me: yes
Status: blocked
BLOCKED.md:471 — schéma a runtime chování hotové (`WaveCurveEntryData.shape`,
`SpawnBatchData.shape`), ale zbývající dvě části (validace v editoru, ukázkový
obsah) sahají do `addons/td_level_designer/` teritoria — CLAUDE.md stop rule.
Přidej do wave resource pole pro tvar spawnu (souvislý proud / shluky / náhlá
vlna) a počty v desítkách až stovkách. Zachovej validaci, přegeneruj ROSTER.md.
Hotovo když: validátor projde, S2 simulátor odehraje všechny levely bez chyby.

## S8 — Save/load round-trip
Model: sonnet
Needs-me: no
Status: done
`scripts/_test_save_round_trip.gd` existuje.
Testy, které ověří, že uložený a načtený stav hry je identický: rozestavěné věže,
Tolerance, dopamine, postup vlnou, MetaProgression.
Hotovo když: property-based test s náhodnými stavy, 100 iterací, žádný rozdíl.

## S9 — Úklid podle vlastních pravidel
Model: sonnet
Needs-me: no
Status: done
`docs/DEBT.md` existuje, mechanické opravy aplikovány.
Projdi scripts/ proti pravidlům v CLAUDE.md. Vypiš do docs/DEBT.md každé porušení:
chybějící typové hinty, hardcoded hodnoty místo @export, přímé $Node cesty místo
signálů, Godot 3 idiomy. Oprav ta, která jsou mechanická a testy zůstanou zelené;
ostatní jen vypiš.
Hotovo když: DEBT.md existuje, verify.sh projde.
