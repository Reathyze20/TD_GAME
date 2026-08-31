# CLEANUP_AUDIT.md — C1, audit mrtvého kódu a souborů

Read-only audit. **Nic nebylo smazáno ani upraveno mimo tento dokument.** Model: Opus
(gate z CLAUDE.md splněn), `Needs-me: yes` splněno tím, že uživatel C1 přímo v
konverzaci potvrdil a rozhoduje podle tohoto dokumentu, ne autonomně bez něj.

## Metoda a dvě past, na které jsem sám narazil (ať se nemusí objevovat znovu)

Základ je skript v `scratchpad` (ne v `tools/` — jednorázový, ne trvalý nástroj), který
nad `git ls-files` (3308 trackovaných souborů) postaví textový korpus a pro každý
`.gd`/`.tscn`/`.tres` počítá tři nezávislé signály reference: **literální `res://` cestu**,
**`uid://...` z párového `.uid` sidecaru**, a u `.gd` navíc **`class_name`** (protože Godot
globální třídy jde použít bez jakéhokoli `preload`/`load`). Nález se počítá za mrtvý jen
když jsou všechny tři nulové.

I tak skript sám o sobě STAČIL NA DVĚ CHYBY, které jsem musel opravit před tím, než šla
čísla brát vážně:

1. **Falešná sebereference přes vlastní `.uid` sidecar.** Prvních 11 „jednoreferenčních"
   nálezů (`addons/td_anim_lab/plugin.gd`, `addons/td_level_designer/plugin.gd`,
   `scripts/floating_text.gd`, sedm nástrojů v `tools/`) mělo tu jedinou referenci ve
   VLASTNÍM `.gd.uid` souboru — ten přirozeně obsahuje `uid://` svého vlastního skriptu,
   takže substring match proti „ostatním souborům" ho omylem počítal jako cizí odkaz.
   Opraveno vyloučením vlastního sidecaru z množiny „ostatní". Po opravě: `addons/td_anim_lab/plugin.gd` a `addons/td_level_designer/plugin.gd` mají SKUTEČNOU
   živou referenci jinde (`plugin.cfg`'s `script="plugin.gd"`, relativní k adresáři pluginu
   — Godotí konvence, ne substring, který by prošel testem na `res://` cestu), takže
   zůstávají živé; `scripts/floating_text.gd` po opravě vyšel jako skutečně mrtvý (níž).
2. **Sprity nepostavené s podřízeným pořadím jsou v korpusu nedohledatelné.**
   `assets/distractions/`, `assets/defenders/`, `assets/towers/` se nikde needovávají
   plnou cestou — kód je skládá za běhu (`"res://assets/distractions/%s%s%s_frame_%d.png"
   % [base_id, suffix, dir_suffix, i]`, ověřeno přímo v
   `scripts/components/distraction_animator.gd:178`, `scripts/tower.gd:703-716`,
   `scripts/defender_unit.gd:496`). Naivní substring hledání proto u těchhle tří adresářů
   (1601 PNG) hlásilo **1535 souborů (94 MB) jako „bez reference"** — číslo, které je
   téměř celé falešně pozitivní. Opraveno druhým průchodem: vytáhl jsem živé `id` ze
   `data/distractions/*.tres`, `data/defenders/*.tres`, `data/habits/*.tres` (přesně ty
   texty, co `Data._load_indexed()`/`_list_files()` skutečně načte — viz
   `scripts/data.gd:235-276`, adresářový scan, ne jednotlivé odkazy) a porovnal je s
   předponou každého PNG jména. Zbylo z 1535 jen **35 skutečných kandidátů** (níže).
   Podobně `tools/_fixtures/level_uid_fixture.tres` vypadal jako mrtvý, protože
   `tools/test_roster.py:27` na něj odkazuje přes `os.path.join(...)`, ne přes literální
   `res://` řetězec — Python nástroje mají třetí, vlastní způsob skládání cest, který
   substring hledání taky nevidí.
3. **Jedna past, kterou jsem SÁM napsal do konceptu tohoto dokumentu a pak musel smazat:**
   35 souborů `assets/distractions/notification_*.png` jsem první průchod vyhodnotil jako
   mrtvá (žádné `id = &"notification"` v `data/distractions/*.tres` po `grep '^id = '`).
   Skutečnost: `data/distractions/notification.tres` je 6řádkový soubor **beze všech
   polí** — spoléhá na `@export var id: StringName = &"notification"`, defaultní hodnotu
   přímo ve `scripts/resources/distraction_data.gd:5` (stejný vzor jako
   `data/habits/focus_timer.tres`, který taky nemá vlastní `id =` řádek). `grep '^id = '`
   na soubor, který `id` vůbec nenastavuje, je slepý. Skutečné ověření:
   `data/levels/level_98.tres:8` má `[ext_resource ... path="res://data/distractions/
   notification.tres"]` — je to živá, spawnovaná distrakce. Vlastní art proto NENÍ v
   nálezech níž. Zůstává jako poznámka v kategorii E — ne že by byl mrtvý, ale že tenhle
   konkrétní `.tres` je nápadně prázdný oproti všem sourozencům (17-27 řádků každý).

Pro każdý nález níž je metoda ověření vypsaná zvlášť — kde to šlo, dvěma nezávislými
způsoby (grep na cestu/uid/class_name PLUS přímé čtení volajícího kódu), ne jen skriptem.

---

## A. JISTĚ MRTVÉ — nulové reference kdekoli v repu

### A1. `scripts/floating_text.gd` (43 řádků) — celá třída `FloatingText`

Nulová reference: žádná `res://scripts/floating_text.gd` cesta, žádné `uid://` z jejího
sidecaru, žádné `FloatingText` (word-boundary) mimo vlastní soubor — ověřeno i přímým
`grep -rn "FloatingText"` mimo `.claude/` (jediný zásah je ve `.claude/worktrees/…`, což
je gitignorovaný, samostatný git worktree na jiném commitu, ne živý kód téhle větve).

Kompletní, funkční `Node2D` s vlastním `_draw()`, tweeny a `finished` signálem — vypadá
jako hotová implementace „floating combat text", ale nikde se neinstancuje. Živá cesta pro
přesně tenhle účel existuje jinde: `scripts/game.gd:7108` `_pop_text(pos, text, color)`
staví vlastní `Label` + tween přímo v `game.gd` (volá se z `_on_streak_changed()` a
odjinud) — nezávislá, paralelní implementace stejné věci. `FloatingText` čte jako starší
verze, kterou `_pop_text()` nahradil, aniž by se smazala.

### A2–A5. Čtyři nezavolané buildery v `scripts/game.gd` (terén/zdi/dekorace)

Ověřeno dvakrát: (1) `grep -n "_build_X("` přes celý `game.gd` — zásah jen na řádku
definice `func _build_X()`; (2) `grep -n "\.call(\|Callable(\|call_deferred(\"_build"` —
nulový zásah, takže to není ani skryté přes reflekci/`Callable`, což
`docs/MIGRATION_AUDIT.md` (starší, iso-éra audit — viz kontext v kategorii C) sám
označoval jako neověřenou mezeru. Tady ověřeno.

- **`_build_decor_layer()`** — `game.gd:1109-1124` (16 řádků). Staví `DecorLayer.new()`,
  přidá ho do stromu, zavolá `.build(...)`. Třída `DecorLayer`
  (`scripts/decor_layer.gd`) sama **živá je** — `tools/map_editor.gd:1783` a
  `tools/stylized_renderer.gd` volají její statické `_texture_named()`/`TINT`/`ZOOM` pro
  náhled v editoru. Mrtvá je jen TAHLE metoda, tj. hák, který by dekor přidal do běžící
  hry — běžící hra dnes žádnou dekoraci nestaví.
- **`_build_wall_shadow_layer()`** — `game.gd:910-932` (23 řádků).
- **`_build_wall_face_layer()`** — `game.gd:957-1017` (61 řádků).
- **`_build_terrain_layer()`** — `game.gd:1164-1208` (45 řádků). Explicitně
  zdokumentováno jako nevolané přímo v kódu: komentář u `_build_wall_segments()`
  (`game.gd:5691`, funkce, která SE volá) říká *„Calls `_build_wall_segments()`, NOT
  `_build_terrain_layer()`. That distinction cost an [hour…]"* — autor už jednou zjistil
  tu samou věc a nechal si o tom poznámku, jen nikdy nesmazal samotnou mrtvou funkci.

Živý terén dnes staví `_build_square_terrain()` (`game.gd:760-776`, volaná z
`_build_field()` na `game.gd:577`) — plochý `SquareTerrain` uzel bez textury, přesně jak
popisuje `BLOCKED.md`'s T5 záznam („flat-color placeholder"). Žádná ze čtyř funkcí výš
není na téhle živé cestě.

### A6. `scripts/_probe_align.gd` (27 řádků) + `scenes/_probe_align.tscn` (6 řádků)

Jednorázová diagnostická sonda, přesně ten typ, který CLAUDE.md sekce „Testy jsou
smlouva" nařizuje smazat po použití: *„Dočasný jednorázový harness po použití smaž (i
`.gd.uid` sidecar)."* Použita jednou, 21. 8. 2026, k naměření (32, 0) px posunu mezi
Godotím `TileMapLayer.map_to_local()` a `Data.cell_center()` — výsledek je dnes citovaný
jen jako HISTORICKÁ hodnota ve třech komentářích (`scripts/game.gd:1322`,
`scripts/grid_projection.gd:139`, `tools/map_editor.gd:389`) a v
`docs/MIGRATION_AUDIT.md:102`. Žádný z těch citací sondu znovu nespouští ani na ni
needovává cestou/uid — jen slovně zmiňují, co kdysi naměřila. Nikdy neměl párovou
`scenes/_test_*.tscn` shodnou se jménem (má vlastní `_probe_align.tscn`, ne
`_test_probe_align.tscn`), takže ho `verify.sh` nikdy neběžel jako regresní test.

### A7. `scenes/AnimationTest.tscn` (6 řádků) + `scripts/animation_test.gd` (217 řádků)

Nulová reference kdekoli — ani cestou, ani uid, a `AnimationTest` samotný název se
nikde jinde neobjevuje (mimo gitignorovaný worktree). Není to `_test_*`/`_shot_*`/
`_play_*`/`_diag_*` podle dnešní konvence, takže ho `verify.sh` glob (`scenes/_test_*.tscn`)
nikdy nezachytí ani náhodou — je to úplně mimo jakýkoli spouštěný systém.

Vnitřní důkaz, že je to starý, neudržovaný soubor: vlastní seznam `_distraction_keys`
(`animation_test.gd:7-16`) má 9 položek, ale živý roster v `data/distractions/` má dnes
13 souborů/12 skutečných id (`comparison`, `fomo`, `group_chat`, `just_one_more` v jeho
seznamu chybí — přibyly později a soubor se nikdy neaktualizoval). Nejde o to, že by
odkazoval na SMAZANOU distrakci (viz oprava v metodické sekci výš — `notification` je
pořád živá) — jde o to, že přestal být synchronní s rostoucím rosterem, což je jiný,
ale stejně platný důkaz, že se dlouho nespouštěl.

### A8. Šest neopojených ad resources v `data/ads/`

`brain_blast.tres`, `jackpot_real.tres`, `monk_mode.tres`, `pull_the_pin.tres`,
`reward_video.tres`, `scrollr.tres` (6 souborů, ~15 KB). Na rozdíl od distrakcí/habitů
NEMÁ `AdData.id` defaultní hodnotu (`@export var id: StringName = &""`,
`scripts/resources/ad_data.gd:17`) — takže tady žádná past s prázdným `.tres` nehrozí,
každý z těch šesti svoje `id` sám explicitně nastavuje.

Ověřeno, jak se reklamy vůbec dostanou do hry: `game.gd:5215`
`_ads_left = level.ads.duplicate()` — VÝHRADNĚ z pole `ads` konkrétního levelu, žádný
adresářový scan (na rozdíl od distrakcí/habitů/karet). `grep` na každé z šesti jmen přes
celý repo (mimo `.claude/`) nenajde žádný `ext_resource` v žádném `data/levels/*.tres`.
Čtyři z šesti se objevují jen v `docs/design/dopamine_mechanics.md` jako koncepční
zmínka — autorovaný obsah, který se nikdy nezapojil do žádného levelu, ne mrtvý kód v
klasickém smyslu, ale mrtvá DATA podle stejného kritéria.

### A9. `assets/towers/_topdown_backup/` — 67 souborů, 568 KB

`tools/install_iso_art.py:225,256,271` je jediný kód, který na `_topdown_backup`
kdekoli odkazuje — a je to ZÁPIS (`backup = os.path.join(towers, "_topdown_backup")`,
přesouvá staré snímky sem, když instaluje nové). Žádný jiný `.gd`/`.py` cestu čte zpátky.
Je to čistě odkladiště vlastního zálohovacího chování instalačního skriptu, ne obsah,
který by cokoli v enginu načítalo.

### Souhrn kategorie A — úspora

| | řádky/soubory | velikost |
|---|---|---|
| Skripty + scény (A1, A2-A5, A6, A7) | ~444 řádků, 8 souborů | pár desítek KB |
| Data (A8) | 6 `.tres` | ~15 KB |
| Assety (A9) | 67 `.png` | ~568 KB |
| **Celkem** | **~444 řádků kódu, 73 souborů dat/assetů** | **~583 KB** |

(Bez B, protože B je „pravděpodobně", ne „jistě" — viz níže.)

---

## B. PRAVDĚPODOBNĚ MRTVÉ — reference existují, ale jen z jiného mrtvého kódu

### B1. `Game._build_corner_terrain()` — `game.gd:1406-1478` (73 řádků)

Řetězec: volá se JEN z `_build_terrain_layer()` (`game.gd:1166`), a `_build_terrain_layer()`
je sama v kategorii A (A2-A5, nulové volání zvenčí). Žádné jiné volání
`_build_corner_terrain()` v repu. Kdyby se smazalo A2-A5, tenhle by šel s tím —
proto B, ne samostatné A: bez svého jediného volajícího nemá smysl posuzovat zvlášť.

Používá `CORNER_ATLAS_PATH` (`assets/terrain/high_ground_atlas.png`) a Wang-corner logiku
z `tools/tiles.py` pipeline — art samotný (`high_ground_atlas.png`) NENÍ v této kategorii,
protože ho pořád čte/zapisuje `tools/tiles.py` a `addons/td_level_designer` preview
(nebylo individuálně ověřováno do hloubky, viz kategorie E).

---

## C. LEGACY PO MIGRACI — izometrie / starý pathfinding / pozice jako vzdálenost

Kontext: větev se jmenuje `iso-to-topdown` a `GridProjection.active_mode` je od T5
(29. 8. 2026) defaultně `MODE_SQUARE` — `MODE_ISO` existuje dál jen jako druhá, neaktivní
větev (`scripts/grid_projection.gd:1-21`, vlastní komentář: *„Only ever called by test
fixtures today (T5 does not call this in the running game)"*). Byl tu i starší,
samostatný audit přesně tohohle tématu — `docs/MIGRATION_AUDIT.md` (T3, komentář na
začátku: *„branch iso-to-topdown at commit 3edfef4"*) — psaný, když `Data.GRID` bylo ještě
24×24/tile 32/iso. Dnešní `Data.GRID` je 30×14/tile 16/`MODE_SQUARE` (`scripts/data.gd:16-22`)
— ten dokument je tedy sám ZASTARALÝ v čísly, i když jeho nálezy o mrtvých funkcích (A2-A5,
B1 výš) jsem ověřil, že platí dodnes. Necituju ho slepě — každou položku níž jsem ověřil
proti současnému stavu, ne proti tomu z 3edfef4.

### C1. `GridProjection.MODE_ISO` větev sama — NENÍ kandidát na smazání

Volá ji jen `scripts/_test_square_projection.gd` (přepne tam a zpátky kolem sebe) a
obecně testy, co explicitně chtějí iso matematiku ověřit. `diamond_corners()`/
`cell_diamond()` zůstávají „iso-only on purpose" podle vlastního komentáře souboru.
Tohle je udržovaná druhá větev, ne mrtvý kód — nepatří sem jako nález, jen jako kontext
pro zbytek kategorie C.

### C2. Izometrický pilot — `scenes/pilot_isometric/IsoPilot.tscn` +
`scripts/pilot_isometric/iso_pilot.gd` + `tools/shot_iso_pilot.gd` +
`tools/shot_iso_slice.gd` + `iso_slice_test.png`/`.import` (kořen repa)

Samostatná, sebeobsažená vertikální ukázka izometrického vykreslování — scéna má vlastní
skript přiřazený přímo (`[ext_resource type="Script" path="res://scripts/
pilot_isometric/iso_pilot.gd"]`), nikdy se needovává z `Menu.tscn` ani z žádné herní
cesty. `tools/shot_iso_pilot.gd`/`tools/shot_iso_slice.gd` jsou její screenshot nástroje
(oba explicitně jen `godot --script`, ne `--headless`, protože potřebují skutečný
renderer). Nejde technicky o mrtvý kód — spustí se a odfotí se — ale je to
předmigrační artefakt, nahrazený živou hrou pod `GridProjection.MODE_SQUARE`. Nebyl
individuálně ověřen, jestli `IsoPilot.tscn` ještě vůbec parsuje čistě (žádný test na
to neběží) — jen že nikam nevede.

### C3. `assets/terrain/iso/*` — NENÍ mrtvé, ale je to živá iso-only větev v běžícím kódu

`scripts/game.gd` na řadě míst (řádky 249-250, 508-509, 1211-1298) podmíněně čte
`res://assets/terrain/iso/...` přes `ResourceLoader.exists()` — pořád živý kód, který se
spustí, KDYŽ ty soubory existují (existují). `tools/map_editor.gd` a
`tools/stylized_renderer.gd` na ten samý adresář taky odkazují. Nejde o dead code v
striktním smyslu (má reference, běží), ale je to mechanismus, který dává smysl jen pod
`MODE_ISO` a v `MODE_SQUARE` (dnešní default) buď nic nedělá, nebo dělá něco, co nikdo
neprošel po přechodu — nebylo ověřováno do hloubky, kolik z téhle větve je pod
`MODE_SQUARE` skutečně mrtvý kód vs. jen neaktivní za podmínkou. Praktický dopad: rozhodni
se, jestli tahle celá podmíněná větev (ne jen assety) patří do budoucího úklidu, až bude
jasné, že se `MODE_ISO` k ničemu nevrací.

### C4. `tools/retile_levels.gd` — počítá pole, které živý renderer nečte

Přepočítává `terrain_tiles` (cell → art variant) pro každý level z `high_ground`. Ověřeno:
živý terén builder `_build_square_terrain()` (`game.gd:760-776`) `terrain_tiles` VŮBEC
nečte — staví jen plochý `SquareTerrain` z `high_ground`/`solid`. Pole `terrain_tiles`
samo přežívá ve schématu `LevelData` (perzistuje se, `tools/map_editor.gd` ho pořád
zapisuje při Bake), ale nikdo ho dnes nekreslí. Nástroj sám neselže, jen počítá věc, na
které dnes nikomu nezáleží — legacy po přechodu na plochý korner-terén, ne z iso éry.

### C5. `tools/stylized_renderer.gd`'s stará čtvercová větev (`CELL=48`)

Nebyl znovu odvozován — už zdokumentováno v `BLOCKED.md`'s `_test_mapeditor` záznamu
(RESOLVED 2026-08-29): *„The OLD square branch (CELL=48, terrain/path + terrain/face
assets) was NOT revived… left as dead code, now genuinely unreachable under both live
states."* Potvrzuju jen, že ten popis pořád sedí (nová `_draw_square()` metoda existuje
vedle ní, stará zůstala nedotčená) — nepřidávám nový nález, jen odkazuji na existující.

---

## D. DUPLICITA NÁSTROJŮ — šest skriptů, co zapisují geometrii levelů

Ověřeno pro každý: existuje soubor? na jaký grid cílí? odkazuje na něj ještě něco živého
(kód, ne jen historická zmínka v `BLOCKED.md`/`PROGRESS.md`)?

| Nástroj | Cílí na | Stav |
|---|---|---|
| `tools/map_editor.gd` (2048 řádků) | živý `Data.GRID` (30×14, tile 16) | **ŽIVÝ** — jediný autoritativní zapisovatel geometrie, pohání `addons/td_level_designer` dock i Bake. |
| `tools/build_placeholder_level.gd` (143 řádků) | živý `Data.GRID` | **ŽIVÝ** — postavil OBA levely, co dnes ship (`level_1.tres` id=1, `level_98.tres` id=98). Vlastní komentář to říká přímo. |
| `tools/refit_levels.py` (175 řádků) | 40×19 → 30×14 | **OBSOLETNÍ** — cílový formát „30×14" dnes existuje, ale žádný level dnes NEVZNIKL refitem; oba live levely postavil `build_placeholder_level.gd` nativně, ne migrací starého 40×19 obsahu (ten byl smazán celý, ne migrován — viz `BLOCKED.md`'s T6 RESOLVED záznam). Zmiňován jen v `BLOCKED.md`/`PROGRESS.md`/vlastním komentáři `regrid_levels.py`, nikde jinde. |
| `tools/regrid_levels.py` (150 řádků) | 40×19 → 120×57 | **OBSOLETNÍ** — cílová mřížka 120×57 dnes neexistuje nikde v `data/levels/`. Byl to mezikrok PŘED izometrickou fází, kterou taky smazal T6. Zmiňován jen historicky. |
| `tools/build_level_first.py` (132 řádků) | zapisuje `data/levels/level_iso_1.tres` | **OBSOLETNÍ** — cílový soubor dnes neexistuje (jen gitignorované `.bak`/`.bak2`). Nahrazen `build_placeholder_level.gd`'s id=98, který (vlastní komentář) záměrně kopíruje NE-prostorová pole z `git show 5bfa33e:data/levels/level_iso_1.tres` — tedy uznává stejný předchozí obsah, ale píše ho jinudy. |
| `tools/build_level_iso.py` (105 řádků) | zapisuje `data/levels/level_iso.tres` | **OBSOLETNÍ** — cílový soubor dnes neexistuje vůbec (ani jako `.bak`). |

Čtyři obsolentní nástroje dohromady: 562 řádků. Žádný z nich není zavolán z `verify.sh`
ani z žádného živého `.gd`/`.py` — potvrzeno `grep` na jejich jméno napříč repem mimo
`.claude/`, jediné zásahy jsou `BLOCKED.md`, `PROGRESS.md`, `docs/MIGRATION_AUDIT.md` a
vzájemné komentáře mezi sebou (`regrid_levels.py`'s docstring cituje `refit_levels.py`
jako důvod, proč vznikl).

Nebyly kontrolovány ostatní nástroje v `tools/` do stejné hloubky (viz kategorie E) —
sedm dalších `tools/*.gd` (`build_terrain_tileset.gd`, `make_test_scene.gd`,
`retile_levels.gd` — viz C4 výš, `scale_pixel_atlas.gd`, `shot_game.gd`,
`shot_iso_pilot.gd` — viz C2, `shot_iso_slice.gd` — viz C2) vyšly ze skriptu jako
„zero-ref", ale to je u nich OČEKÁVANÉ — jsou to samostatné `--script` vstupní body
spouštěné ručně (stejná konvence jako `_shot_*`/`_test_*` scény, jen bez scény), ne
duplicita geometrie levelů, takže do téhle tabulky nepatří.

---

## E. NEJISTÉ

1. **`data/distractions/notification.tres`** — živá (viz metodická sekce výš), ale
   jediná ze 13 distrakcí, co nemá ŽÁDNÉ vlastní pole (6 řádků vs. 17-27 u sourozenců).
   Buď je to záměrně holý „default" typ, nebo omylem vyprázdněný soubor. Nekontrolováno,
   co přesně dostane hráč, když se spawne (asi úplně defaultní staty z
   `DistractionData` — 0 HP? nulová rychlost?) — pokud ano, může to být živá, ale
   nehratelná/rozbitá distrakce v jediném levelu, co ji používá.
2. **Pipeline-mezistupně v `assets/src/`, `assets/raw/`** a příbuzné (`assets/decor`,
   `assets/src/pixel/anim32`, `assets/src/pixel/props`, `assets/src/pixel/path_accents`,
   `assets/src/pixel/iso_pilot`, `assets/iso_pilot/decor`, volné PNG v `docs/art/`) —
   CLAUDE.md's PixelLab sekce výslovně říká, že nevybraní kandidáti a raw výstupy se
   commitují záměrně a natrvalo („nevybraní kandidáti jsou levnější v repu než znovu
   vygenerovaní") — to NENÍ mrtvý kód podle stejného měřítka jako zbytek téhle kategorie,
   je to úmyslná archivní politika. Neaudioval jsem je soubor po souboru; jen velikosti
   z hrubého skenu (než jsem odečetl id-prefix false positives):
   `assets/src/incoming_tiles` (76 souborů, **64,9 MB** — zdaleka největší jednotlivá
   položka v celém repu), `assets/src/incoming_tiles/new_mj` (8, 7,2 MB),
   `assets/src/concepts` (4, 3,7 MB), `assets/terrain/iso` (14, 8,1 MB — ale ŽIVÉ, viz C3),
   `assets/src/pixel/iso_pilot` (6, 2,2 MB). I když politika říká „neškrtat", **64,9 MB
   v jediné složce** stojí za vědomé rozhodnutí, ne mlčení.
3. **`assets/src/pixel/towers/_replaced_mindfulness/`** (10 souborů) — název sám říká
   „nahrazeno", nebylo individuálně ověřeno čím ani kdy.
4. **Netrackované scratch soubory z `git status`** — `scripts/_diag_map_editor_fix.gd`,
   `_diag_p8b.gd`, `_diag_pausemenu_live.gd`, `_diag_q1b.gd`, `_diag_ysort_check.gd`
   (+ `.gd.uid` sidecary), `scenes/_diag_*.tscn`, `scenes/_shot_defender_pivot.tscn`,
   `scenes/_shot_squashed_tiles.tscn`, a 14 screenshotů v `.dev/screenshots/`. Grep přes
   `PROGRESS.md`/`BLOCKED.md` na jejich jména (`p_uirescale`, `ysort_check`,
   `map_editor_fix`, `pausemenu_live`, `squashed_tiles`, `defender_pivot`) **nenašel
   ŽÁDNÝ záznam** — buď rozdělaná práce z úkolu, co ještě nedoběhl do zápisu, nebo z
   úkolu mimo tenhle běh. Nehádám, jestli už dosloužily — CLAUDE.md's pravidlo pro
   jednorázové harnesse (smazat po použití) na ně jednou dopadne, ale bez záznamu o
   dokončení úkolu to nejde rozhodnout teď.
5. **`data/levels/*.bak`/`.bak2`** (`level_1.tres.bak`, `level_1.tres.bak2`,
   `level_iso_1.tres.bak`, `level_iso_1.tres.bak2`) — gitignorované (`.gitignore:9`,
   `*.bak`), tedy MIMO git-trackovaný rozsah týhle audity, ale fyzicky leží na disku a
   nic je nenačítá (`Data._list_files()` filtruje přesně `.ends_with(".tres")`, `.bak`
   neprojde). Nízká priorita, jen pro úplnost.

---

## Co jsem NEudělal (a proč to není mezera)

- Nekontroloval jsem `addons/godot_ai/` (132 `.gd` souborů) — vendorovaný MCP most,
  CLAUDE.md ho výslovně odlišuje od projektových autoloadů a `docs/MIGRATION_AUDIT.md`
  ho už jednou vyloučil ze stejného důvodu.
- Nekontroloval jsem `addons/td_level_designer/` do hloubky nad rámec toho, co je nutné
  pro referenční graf (jen `plugin.gd`/`plugin.cfg`) — CLAUDE.md žádá zastavit se u
  čehokoli, co se ho dotýká; audit/čtení není dotyk, ale nešel jsem hledat mrtvý kód
  UVNITŘ něj cíleně.
- Neprocházel jsem všech 1601 assetů jednotlivě — jen ty tři adresáře, kde jde
  mechanismus (base_id + frame číslo) ověřit strojově (distrakce, obránci, věže), plus
  cílené ruční ověření `_topdown_backup`. Zbytek je v kategorii E s velikostmi, ne
  s definitivním verdiktem.
