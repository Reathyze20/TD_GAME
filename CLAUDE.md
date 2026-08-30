# TD Project — Godot 4.7, GDScript, 2D pixel art

## Co to je
Tower defense o únosu pozornosti. Generické TD objekty jsou namapované na téma:
Focus Meter = životy, Distractions = nepřátelé, Habits = věže, Dopamine = měna,
High ground = zdi/bludiště. Nad tím Tolerance (0–100 penalizace za nadužívání)
a Quick Hit (okamžitá měna, zvyšuje Tolerance).
Učí to skrz level design, ne skrz text. Veškerý text pro hráče je anglicky.

## KTEROU DOKUMENTACI ČÍST — nečti všechno
| Úkol | Přečti nejdřív |
|---|---|
| cokoli o smyslu hry, balanci, edukativním záměru | docs/core/00_overview.md |
| levely, MapEditor, td_level_designer | docs/EDITOR_GUIDE.md |
| generování/import artu | docs/ART_PIPELINE.md, docs/PIXELLAB.md |
| dlaždice, terrain, corner rendering | docs/TILESETY.md |
| co reálně shipuje | docs/ROSTER.md (GENEROVANÝ, needituj ručně) |
| psaní nebo úprava testů | docs/REFACTOR_PLAN.md („Verification pattern") |

docs/core/ je ground truth. Píšu ho já. Když je úkol v rozporu s ním,
upozorni mě místo hádání.

## Engine a syntaxe
- Godot 4.7. NIKDY Godot 3.x API.
- Časté chyby: KinematicBody2D → CharacterBody2D | yield → await |
  .connect("x", self, "_y") → x.connect(_y) | TileMap → TileMapLayer |
  export var → @export var | starý Tween → create_tween()
- Vždy typové hinty. Vždy @export místo hardcoded hodnot.

## Architektura — respektuj existující
- Autoloady reálně registrované v `project.godot`: `SignalBus`, `Data`, `GameState`,
  `ModifierManager`, `MetaProgression`, `Sfx`, `Music`, `Mirror`. NEZAKLÁDEJ nové
  autoloady bez ptaní. Komunikace přes SignalBus — a drž rozdělení, které `signal_bus.gd`
  sám dokumentuje: `SignalBus.*` je "stalo se to" (událost, minulý čas), `GameState.*_changed`
  je "teď to je X" (stav, na který se váže HUD) — nejsou to konkurenční sběrnice.
  (Registruje se i `_mcp_game_helper` z addonu `godot_ai` — to je MCP/dev-tooling most,
  ne herní autoload; neztotožňuj ho s výše uvedenými a nesahej na něj.)
- Chování patří do `scripts/components/` jako komponenta se single responsibility.
  Než přidáš novou, zkontroluj, jestli už tohle nepokrývá jedna ze tří existujících:
  `StatusManager` (`Node` — Calm/Reframe/Boredom, "nejsilnější vyhrává" pro Calm/Reframe,
  Boredom se sčítá per-source), `ArcProfile` (`RefCounted` — přepočet úhlu kužele habitu na
  tvar poškození v prostoru), `DistractionAnimator` (`Node2D` — procedurální vektorová
  kresba nepřátel přímo v Canvas, žádné sprite listy).
- Datové třídy v `scripts/resources/` (všechny `class_name X extends Resource`):
  `AdData`, `AnimTuning`, `CardBurstData`, `CardData`, `CardEffectData`, `DefenderData`,
  `DistractionData`, `GrowthNodeData`, `HabitData`, `InsightCardData`, `InterventionData`,
  `LevelData`, `SpawnBatchData`, `TrodData`, `WaveCurveEntryData`, `WaveData`.

## Obsah je data, ne kód — TVRDÉ PRAVIDLO
- Levely, habits, distractions, waves, cards NIKDY nehardcoduj. Patří do data/ jako .tres.
- Levely se autorují v scenes/MapEditor.tscn a bakují. NEPIŠ level .tres ručně.
- Po přidání obsahu vždy přegeneruj ROSTER.md přes tools/roster.py.

## Názvy souborů
- **Dva soubory se nikdy nesmí lišit jen velikostí písmen.** Projekt běží na Windows,
  kde je souborový systém case-insensitive (`fsutil` to potvrzuje) a `git config
  core.ignorecase` je `true`. `Foo.md` a `foo.md` jsou tady **jeden a týž soubor**:
  zápis do jednoho přepíše druhý a git novou cestu vůbec nezaznamená. Naráželo se na to
  29. 8. 2026 u `STYLE_BIBLE.md` vs. `style_bible.md` — vyřešeno přejmenováním na
  `style_bible_measured.md`.

## Scény
- Needituj .tscn ručně, neměň uid= ani ext_resource ID.
- Nové scény programově: PackedScene.pack() + ResourceSaver.save() v tools/.

## Testy jsou smlouva
**Pozor, tohle se liší od obvyklého Godot projektu:** v repu není `tests/` adresář ani GUT
(`addons/gut` neexistuje, nikde v repu není zmínka o něm). Testy jsou dvojice
`scripts/_test_*.gd` (`extends Node`) + stejnojmenná `scenes/_test_*.tscn` (kořen `Node`
s tím skriptem přiřazeným) — samostatné headless harnesse, ne test framework. Vzor je
zdokumentovaný v `docs/REFACTOR_PLAN.md` pod „Verification pattern":
- `completed := false` sentinel nastavený jen na úplném konci; `Timer` watchdog, který
  při timeoutu vypíše FAIL — bez něj chyba uprostřed testu coroutine tiše ukončí a vypadá
  to jako zaseknutí nebo falešný PASS.
- Spouštěj přes `--main-scene`, NIKDY přes `--script` — v `--script` režimu nejsou
  autoloady (`Data`, `GameState`, …) ještě zaregistrované a jejich čtení je compile error.
- Harness, který instancuje `Game.tscn` a spouští distrakce bez stavění věží, musí hned
  nastavit `GameState.focus`/`max_focus` vysoko — jinak Focus spadne na 0, `_game_over()`
  zavolá `change_scene_to_file()` a to smaže celý current scene tree i s harnessem a jeho
  watchdogem (vypadá to jako hang, není to hang).
- Existující fixtures (neruš, nepřejmenovávej bez důvodu): phase2/3/4/6/7 refaktory,
  suppression stream, nutrition guild, zen pulsar, deep reading, fog & bandwidth, LOS,
  taxonomy, levels, streak, trod, mapeditor.
- `scenes/_shot_*.tscn` dělají vizuální snapshoty (žádný pass/fail), `scenes/_play_*.tscn`
  jsou manuální playtesty — nepleť je s `_test_*`.
- Když test selže, oprav kód. NIKDY neupravuj `_test_*` skript, aby prošel, bez mého souhlasu.
- **Úzká výjimka pro flaky testy** (schváleno 30. 8. 2026, viz `_test_phase3`
  v `docs/KNOWN_BROKEN.md`): smíš opravit ČASOVÁNÍ testu — nahradit pevný počet
  `process_frame` čekáním na skutečný uplynulý čas (`create_tween`/`SceneTreeTimer`),
  když je test odvozený od reálného herního běhu (`delta` v sekundách), ne od snímků —
  BEZ mého souhlasu, POKUD platí všechno tohle:
  1. Test je ve `verify.sh` veden v `FLAKY_TESTS`, ne v `KNOWN_BROKEN_TESTS` — tj. padá
     nespolehlivě, ne trvale.
  2. Mění se JEN mechanika čekání (čas místo snímků), NE žádná assertion ani očekávaná
     hodnota.
  3. Po opravě test proběhne **20x po sobě čistě** (žádná výjimka bez tohoto důkazu).
  4. Do PROGRESS.md se zapíše, proč přesně tahle oprava pod výjimku spadá.
  Když některá z podmínek neplatí — assertion by se musela změnit, nebo se 20x
  nepodaří — NEUPRAVUJ dál a zapiš do BLOCKED.md. Tahle výjimka nerozšiřuje pravidlo
  „neupravuj test" na cokoli jiného (novou logiku, nový obsah assertion, mazání
  kontrol) — jen na tenhle jeden druh opravy.
- Dočasný jednorázový harness po použití smaž (i `.gd.uid` sidecar); pojmenované fixtures
  výše jsou trvalé regresní testy a zůstávají.
- **Iso fixtures už neexistují** (P0d, 30. 8. 2026). Dřív tu stálo pravidlo přejmenovat
  `iso math` a `iso slice` na `_test_legacy_iso_*` a ve verify.sh je přeskočit. To
  pravidlo bylo postavené na omylu: ani jedna z nich nikdy nebyla fixture podle vzoru
  výš. Obě jsou `extends SceneTree` s `_initialize()`, tedy harnessy pro `--script`
  (režim, který tenhle dokument o pár řádků výš zakazuje), přišly s iso pilotem
  (`405df22`) a **odpovídající `.tscn` k nim nikdy neexistovala** — v gitu není ani
  jedna, ani smazaná. verify.sh iteruje přes `scenes/_test_*.tscn`, takže obě celou
  dobu tiše NEBĚŽELY a jen vypadaly jako pokrytí. Smazané v P0d; verify.sh teď osiřelý
  `_test_*.gd` bez scény hlásí jako FAIL, takže se to nemůže opakovat.

## PixelLab
- Katalog: @https://api.pixellab.ai/mcp/docs
- Godot návody: @pixellab://docs/godot/wang-tilesets
- Žádný base64 do kontextu. Používej *_url parametry a curl na download URL.
- Async: zafrontuj všechno naráz, pak pollni get_*. Nečekej sériově.
- Před dávkou get_balance. Ceny: standard=1, v3=2-9, pro=20-40 generací.
- Master paleta: `docs/art/palette_48.hex` (48 barev, i jako `docs/art/palette_48.png`).
  Vše z ní čerpá, nic nemá vlastní paletu. `palette_32.hex` existuje, ale měřitelně škodí
  6 z 10 příšer — nepoužívat.
- Style anchor (`style_character_id`, bere ho jen `mode="pro"`) — **jediná kotva pro celý
  projekt**: `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (Broccoli Knight, obránce z Nutrition
  Guild). Patří do `style_character_id` u **každé** postavy — obránce i distrakce.
  Ověřeno 29. 8. 2026 přes `get_character`: 64×64, 8 směrů, kompletní, tedy použitelná.
  - **Odpískané kotvy — v žádném promptu ani parametru:**
    `62772f73-28d8-442b-add6-f33684f16415` a `0ef2d964-dd67-4132-97b9-39083228db14`
    (junk-food rodina, zrušena 17. 8. 2026 spolu s celým junk-food směrem),
    `7ba5d829-5a10-4ed9-b038-52978ec20782` (jednooká scrollerka, obvazový styl).
  - **Rozdíl mezi rodinami nenese kotva, ale silueta a barevná zóna palety.** Habity kulaté
    a teplé, distrakce ostré a studeně jedovaté. Proč zrovna silueta: viz
    `docs/art/STYLE_BIBLE.md` §2a.
  - Terén, věže a rekvizity kotvu nemají a mít nemůžou — `style_character_id` bere jediný
    nástroj v katalogu (`create_character`) a ty se jím negenerují. Rodinu jim drží
    `style_images`.

## Ověření — po KAŽDÉ změně
Godot binárka NENÍ v PATH na tomhle stroji. Console build (kvůli stdoutu):
`C:\Users\reath\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`
(níž zkráceno na `godot` — nahraď plnou cestou).

```
godot --headless --path . --import
# POZOR: samotné --quit / --quit-after 1 v headless nedělá pořádný import (issue #77508)

godot --headless --path . --main-scene "res://scenes/_test_x.tscn"
# spusť konkrétní _test_* harness relevantní ke změně (viz "Testy jsou smlouva" výše);
# exit kód 0/1 hlásí get_tree().quit() na konci skriptu

python tools/roster.py --md > docs/ROSTER.md
```

`tools/roster.py` nemá `--check` flag (jen `--md`) — po změně obsahu ho spusť a podívej se
na diff `docs/ROSTER.md`, žádný samostatný kontrolní příkaz neexistuje.

`gdformat`/`gdlint` v repu nejsou nastavené — žádný config, žádná zmínka jinde v projektu.
Nespouštěj je jako závaznou kontrolu, dokud je sám nezavedeš a neřekneš mi o tom.

## tools/ — Python vs GDScript
Python: práce se soubory a obrázky mimo engine (PixelLab import, roster, atlasy).
GDScript: cokoli, co potřebuje Godot API (TileSet, SpriteFrames, PackedScene).

## Autonomní běh — pravidla
- Pracuješ na větvi, na které jsem tě spustil. NIKDY ji nepřepínej, neresetuj, nepushuj.
- Po KAŽDÉM dokončeném úkolu: ./verify.sh musí projít. Pak commit. Jeden úkol = jeden commit.
- Když verify.sh selže a neopravíš to do 3 pokusů: zapiš důvod do BLOCKED.md a přejdi na další úkol.
- Po každém úkolu připiš řádek do PROGRESS.md: datum, úkol, hotovo/blokováno, hash commitu.
- ZASTAV a zapiš do BLOCKED.md, pokud: úkol vyžaduje vizuální posouzení, chce smazat
  soubor v data/, dotýká se addons/td_level_designer/, nebo si nejsi jistý záměrem.
- Když u úkolu narazíš na návrhové rozhodnutí, které není jednoznačné, NEHÁDEJ.
  Zapiš možnosti a jejich důsledky do BLOCKED.md a přejdi na další úkol.
- Nikdy negeneruj assety v PixelLabu.

- Každý úkol ve frontě má hlavičku Model / Needs-me / Status. Pracuj VÝHRADNĚ
  na tom úkolu, který ti runner určil, i kdyby další vypadal jednodušší.
- Zkontroluj, na jakém modelu běžíš. Když má úkol `Model: opus` a ty jsi Sonnet,
  NEZAČÍNEJ — zapiš do BLOCKED.md "špatný model" a skonči.
- Když má úkol `Needs-me: yes`, nepracuj na něm. Napiš do BLOCKED.md, co ode mě
  potřebuješ rozhodnout, a skonči.
- Po dokončení přepiš Status: todo → done. Při zablokování Status: todo → blocked.

- Výjimka z pravidla „neupravuj test": _test_* smíš opravit bez ptaní jen tehdy,
  když je vadné SAMO MĚŘENÍ (čekání na snímky místo na čas, závislost na pořadí,
  race condition), a oprava nemění, CO test tvrdí o hře. Změna očekávané hodnoty,
  prahu nebo vypuštění kontroly vždy potřebuje moje svolení.
  Každou takovou opravu zapiš do PROGRESS.md s odůvodněním, proč spadá sem.