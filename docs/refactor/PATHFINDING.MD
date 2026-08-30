# Pathfinding, multi-směr, segmenty, brainfog

Pořadí je podle poměru užitek/práce. **NEMĚŇ ho** a nepracuj na jiném úkolu,
než který ti určil runner.

## Konvence platné pro celý soubor

- **Testy:** `scripts/_test_*.gd` + `scenes/_test_*.tscn` podle „Verification pattern"
  v `docs/REFACTOR_PLAN.md`. **NEINSTALUJ GUT ani GdUnit4.** Spouštění vždy přes
  `--main-scene`, nikdy přes `--script`.
- **Po každém úkolu:** `./verify.sh` musí projít → commit → `Status: todo` přepiš
  na `done` → řádek do `PROGRESS.md`.
- **Při zablokování:** `Status: blocked`, důvod do `BLOCKED.md`, přejdi dál.
- **`Needs-me: yes`** = frontu zastav, nepřeskakuj. Jsou to rozhodovací brány.
- **Model:** zkontroluj, na jakém běžíš. Když úkol chce `opus` a ty jsi Sonnet,
  nezačínej — zapiš „špatný model" do `BLOCKED.md` a skonči.
- **Návrhové rozhodnutí, které není jednoznačné:** NEHÁDEJ. Možnosti a jejich
  důsledky do `BLOCKED.md`.

---

## P0 — zdroj pravdy mapy: ASCII vs. bakování
Model: opus
Needs-me: yes
Status: done

Rozhodnuto: **varianta B** — `.tres` zůstává autoritativní, ASCII je odvozený
bezztrátový side-car. Důvod: odkaz mezi resources (`@export var base: LevelData`)
je vlastnost grafu a text ho vyjádřit neumí, takže ASCII by segmenty skládalo
kopírováním znaků — což jde přímo proti zadání P8.

## P0b — ASCII side-car
Model: sonnet
Needs-me: no
Status: done

## P0c — duplicita v path_cells
Model: sonnet
Needs-me: no
Status: done

## P0d — úklid iso legacy
Model: sonnet
Needs-me: no
Status: done

## P0e — inventura known-broken
Model: sonnet
Needs-me: no
Status: done

## P0f — verify.sh rozlišuje known-broken
Model: sonnet
Needs-me: no
Status: done

## P1 — flow field od cíle
Model: opus
Needs-me: no
Status: done

`scripts/flow_field.gd` — jedna sdílená BFS od cíle, gradient dává směr.
Nevážená záměrně. Bench: **584 µs** proti limitu 5 ms (devítinásobná rezerva).
Napojení na `game.gd` je úkol P4.

## P2 — anti-block validace zdí
Model: opus
Needs-me: no
Status: done

`scripts/anti_block_validator.gd` (`AntiBlockValidator`) — zvolena třetí cesta
místo „union-find nebo lokální re-BFS": plný přepočet přes `FlowField` s
kandidátní zdí přidanou do `blocked`. Union-find neumí levně odbourat zeď (bourání
ve hře existuje), lokální BFS musí konzervativně uvažovat o neprošlé oblasti;
plný přepočet už dnes komfortně splňuje rozpočet. Odůvodnění v hlavičce modulu
a v BLOCKED.md.

`_test_antiblock`: vyčerpávající sweep přes všech 17 volných buněk syntetického
bludiště se DVĚMA nezávislými spawny (dokazuje, že se kontrolují OBA, ne jen
`active_spawns[0]` — ověřeno injektovanou chybou). Bench na reálné mapě
(30×14, 27 zdí): **559,5 µs/kontrola** (limit 1 ms). Rychlé stavění (30 zdí
postupně): **550,3 µs/zeď**, strop **~1817 zdí/s**, ~0,55 % intervalu mezi
kliky rychlého hráče (10/s) — číslo použité k uzavření P3. Čísla i metodika
v PROGRESS.md 2026-08-30 a BLOCKED.md.

---

## P4 — jednotky na flow fieldu
Model: sonnet
Needs-me: no
Status: done

**POZOR — zadání bylo opraveno.** Starší znění (S5 v `SYSTEMS.md`) mluvilo
o pozici jako o vzdálenosti podél cesty. To platilo jen pro jednu cestu
a s flow fieldem **už neplatí**.

- Pozice nepřítele je **`Vector2` na mřížce**, ne skalár.
- Směr čti z flow fieldu (P1), nepočítej cestu per jednotka.
- Zaměřování věží = rozsahový dotaz nad **prostorovým hashem**, ne nad seřazeným
  polem.
- Součástí úkolu je oprava `_test_suppression` z `docs/KNOWN_BROKEN.md`
  (knockback tlačí tělo 26 px do zdi) — pohyb se stejně přepisuje.

Hotovo když: existující regresní testy ekonomiky zůstanou zelené,
`_test_suppression` je zelený a vyřazený z known-broken, bench z T11 zopakován
a zapsán do `docs/PERF.md`.

`scripts/enemy.gd` (`Distraction`) — `cell_path`/`path_index` (Array přes celou trasu)
nahrazeny jedním `current_cell: Vector2i`, advancovaným jen při dojezdu na cíl kroku
(stejný "walk smoothly to next cell centre" pocit jako dřív). Směr každý krok čte
`game.flow_field.direction(current_cell)`; `game.gd` staví JEDNO sdílené
`FlowField` (`_rebuild_flow_field()`) při stavbě levelu a znovu jen tam, kde se za
běhu mění `high_ground` — což je dnes jen `_set_sunk()` (spike klesajících zdí).
`_open_trod()` pole nepřestavuje vůbec: trod jen přeřadí už volné buňky na `lane_cells`
(nikdy nesahá na `high_ground`), takže nevážené pole vidí přesně stejnou mapu před
i po — **chování se ale reálně mění**: živé jednotky teď vždy jdou surově nejkratší
cestou a otevření trodu je na ně už nepřetáhne (dřív ano, přes vážený A*). `astar`
(`AStarGrid2D`, vážený, honoring `path_off_lane_cost`) v `game.gd` zůstává živý jen
pro build-fázové náhledy tras (`_compute_path_previews`) a dev sondy — živý pohyb
už ho nikdy nevolá. Split (`spawn_split`) už nic neslicuje: dítě dostane rodičovu
aktuální buňku a čte STEJNÉ sdílené pole, takže "pokračuje, nezačíná znovu" vyjde
samo.

Knockback (`_test_suppression`, viz i `docs/KNOWN_BROKEN.md`): `apply_knockback()`
dřív kontroloval jen CÍLOVOU buňku (`Data.GRID.tile`=16px < KNOCK_BUDGET=26px, takže
šťouchnutí mohlo protunelovat jednobuněčnou zeď, aniž by cíl kdy byl ta zeď). Oprava
vzorkuje celou trasu šťouchnutí po `tile/4` krocích (`_knockback_crosses_wall()`) —
narazí-li kdekoli na `high_ground`, celé šťouchnutí se zamítne (poloha se nehne),
což odpovídá stávající all-or-nothing logice rozpočtu (`_knock_left` se odečte
i tak). Žádná assertion v `_test_suppression.gd` se neměnila.

Zaměřování věží: `game.gd` má `query_distractions_near(center, radius)` nad
`_distraction_hash` (Vector2i buňka -> Array[Distraction]), přestavovaným jednou za
snímek v `Game._process()`. `tower.gd`'s `_aoe_targets()`, `has_enemy_in_cone()`
a `_tick_auto_aim()` z něj čtou kandidáty místo plného skenu `get_live_distractions()`
— řazení/ořez podle `_profile.aoe_targets` beze změny. Přínos na TÉTO mapě je reálný,
ale skromný: většina habitů má dosah 260-560px proti hřišti 480×224px, takže dotaz
stejně obsáhne většinu desky; hash pomáhá tím, že navštíví jen OBSAZENÉ buňky, což
u hordy pochodující v jedné řadě znamená zlomek živého počtu. `defender_unit.gd`
(Ally engagement) a `projectile.gd` (hit detekce, jiná mechanika s vlastním pořadím)
záměrně nedotčeny — mimo doslovný rozsah "věže cílí", riziko rozbití jemné logiky
by nekoupilo nic měřitelného.

Bench (T11 metodika zopakována, `scripts/_perf_horde.gd` nezměněn): avg frame lepší
od N=200 výš (N=500: 62.76→52.64ms, N=1000: 88.28→65.76ms), zhruba na místě na
N=50/100. Plné číslo i vysvětlení jednoho šumového outlieru (N=50 worst frame) v
`docs/PERF.md`. Flow field se za běhu čte, ne přepočítává (přestavba je jen na
`high_ground` změnu, dnes jen sinking-walls spike) — P3 zůstává zavřené, čtení
je O(1) na jednotku i při N=1000.

## P5 — vykreslování hordy přes MultiMeshInstance2D
Model: sonnet
Needs-me: no
Status: done

Nahraď jeden-uzel-na-nepřítele jedním `MultiMeshInstance2D` na hordu.

Hotovo když: bench N=500 je **aspoň 3× rychlejší** než baseline z T11.

**Předpoklad z CLAUDE.md ("žádné sprite listy") je zastaralý.** `distraction_animator.gd`
dnes kreslí `_draw_sprite_frames()`, kdykoli na disku existuje art (`if not
_frame_textures.is_empty(): ...; return`) — sedm ručně kódovaných `_draw_*` funkcí je
FALLBACK pro typ bez artu, a podle `docs/ROSTER.md`/`assets/distractions/` ho dnes
nepoužívá ani jeden živý typ. Nešlo tedy o konflikt s MultiMesh (ten umí jen JEDNU
texturu na instanci), jen o zastaralý komentář — stojí za samostatnou opravu, není to
úkol P5.

Zvolená architektura: `HordeAtlas` (`scripts/components/horde_atlas.gd`) skládá za běhu
sdílenou atlasovou texturu ze všech chůzových snímků (south/north/east — west je
zrcadlené east, stejná konvence jako předtím), líně a inkrementálně po prvním živém
výskytu daného (typ, varianta). `HordeRenderer` (`scripts/components/horde_renderer.gd`)
drží TŘI `MultiMeshInstance2D`: tělo (atlas + `shaders/horde_atlas.gdshader`, UV rect
per-instance přes `MultiMesh.custom_data`), glow a stín (sdílené procedurální radiální
textury, per-instance barva/alfa). Přepisuje se každý snímek z `Game._process()` (na
konci, PO spawnování vlny — nový spawn je tak v batchi hned, ne o snímek později).

Do batch spadá živá, zdravá, neblokovaná distrakce s artem — to pokrývá „jen jde",
naprostou většinu populace. VYŘAZENO (zůstává na starém per-node `_draw()`, beze změny):
umírající tělo (death frames), distrakce blokovaná Allym (attack loop), typ bez artu
(procedurální fallback), a stavové aury (Boredom halo, Slow ring, Rush/Overdrive
chevrony, Reframe ring) — ty se týkají jen zlomku populace i v rušné vlně. Hit-flash
zůstal v batchi: `MultiMesh` má nativní per-instance barvu, přesně to, co potřebuje.

**Druhá páka, nezávislá na MultiMeshi:** `Distraction`/`DistractionAnimator` volaly
`queue_redraw()` bezpodmínečně každý snímek, ačkoli přesun `CanvasItem` redraw
NEVYŽADUJE (Godot přetransformuje stejný cache draw-list zdarma). Obě teď volají
`queue_redraw()` jen když `needs_own_redraw()`/`_needs_own_redraw()` vrátí true (aktivní
stav, attack loop, procedurální fallback, běžící disrupt/haste/life/autoplay). Prostý
chodec bez stavu dnes z pohybového ticku nenaplánuje ŽÁDNÝ redraw.

Y-sort kompromis (nevyhnutelný — jeden `CanvasItem` má jednu pozici v pořadí kreslení,
nemůže nahradit 500 nezávisle seřazených uzlů): tělová vrstva kreslí na pevné z-vrstvě
NAD habity/alies/neb batchovanými distrakcemi a POD projektily — distrakce jsou vždy
navrchu habitů. Vědomá ztráta přesnosti výměnou za čitelnost hordy (hráč musí vidět, co
se řítí na bludiště). Glow/stín jdou ještě níž, pod všechny jednotky bez y-sortu vůbec —
to je BLÍŽ k vlastnímu ideálu `docs/core/01_rendering_and_depth.md` ("stíny jsou jen
z-index, nikdy y-sort"), ne dál od něj: starý per-node kreslič je řadil SPOLU s tělem.

Vizuální zjednodušení (zdokumentovaná, ne tichá): stín ztratil jemné časové „bob"
zvlnění (pár procent měřítka na nízko-alfa fleku, na hordě neviditelné); glow/stín jsou
jedna pre-baked měkká radiální textura místo původních 3-4 tvrdých prstenů — blízko v
hustotě a stopě, ne pixel-identické. Ověřeno okem přes `scenes/_shot_crowd.tscn`
(`.dev/screenshots/p5_crowd_120.png`, `p5_crowd_9.png`) a samostatným zrcadlovým testem
(`.dev/screenshots/p5_mirror_compare.png` — west je opravdu horizontální zrcadlo east,
ověřeno flipnutím zachyceného ořezu v softwaru a diffem proti east ořezu).

Bench (`scripts/_perf_horde.gd` nezměněn): **N=500 avg 62.76→11.32ms, 5,5× rychlejší
než T11 baseline** (cíl byl 3×). N=1000: 88.28→22.25ms (4,0×). Zisk roste s N až do 500,
pak se mírně zužuje na 1000 — sedí to s mechanismem (batch draw calls škálují s počtem
obsazených řádků, ne s N; zbylá O(N) práce v `HordeRenderer.rebuild()` a pohybu je
levná, ale při N=1000 už měřitelná). Plné číslo i tabulka T11→P4→P5 v `docs/PERF.md`.

Regresní testy (`_test_suppression`, `_test_taxonomy`, `_test_sink`, ekonomika) zůstaly
zelené beze změny assertion — tohle je vykreslovací změna, na herní logice nic nesahá.
Nový `_test_horde_renderer` (`scripts/_test_horde_renderer.gd` +
`scenes/_test_horde_renderer.tscn`) ověřuje samotný nový mechanismus: batch-eligibilitu,
packing do atlasu, vyřazení při zablokování a návrat po uvolnění, že aktivní stav
vynutí `needs_own_redraw()` i když tělo zůstává v batchi, hit-flash tint a
south/north/east/west (zrcadlo) výběr snímku.

## P3 — dirty-region přepočet  [ROZHODNUTÍ, NE IMPLEMENTACE]
Model: sonnet
Needs-me: no
Status: obsolete

BLOCKED.md ("P3 — closed as OBSOLETE 2026-08-30, but REVISITABLE") — čísla z P2
(rychlé stavění, reálná mapa): plný přepočet ~550–560 µs/zeď, strop ~1800 zdí/s,
~0,55 % intervalu mezi kliky rychlého hráče (10/s). Hluboko pod hranicí —
složitost dirty-region kódu by kupovala výkon, který nechybí.

**NENÍ TO FINÁLNÍ jako u T6** (kde předmět úkolu úplně zanikl) — P3ovo téma dál
existuje, jen se dnes nevyplácí. P4 bude tenhle přepočet volat mnohem častěji
(za jednotku, možná za snímek) a na jiné velikosti volání záleží úplně jinak.
Poslední slovo má P4, ne P2 — pokud tam čísla ukážou jinak, tenhle úkol se
otevře znovu s těmi čísly jako odůvodněním, ne nahradí novým. BLOCKED.md už teď
upozorňuje, že skutečná otázka pro P4 nejspíš nebude „dirty-region patch jedné
buňky", ale „necachovat pole, které se mezi dvěma čteními vůbec nezměnilo".

Hotovo: výsledek je bit-identický s full rebuildem (to byl `_test_antiblock`)
a je rychlejší.

## Q1 — total time control a total information
Model: sonnet
Needs-me: no
Status: done

Rychlosti **0.25× / 1× / 2× / 4×**, pauza s možností zadávat příkazy během ní,
skip to next wave, plné staty habitu i distrakce na hover.

Není to jen QoL. Podle researche je to stížnost číslo jedna a hráči čtou absenci
speed-upu cynicky. Navíc bez rychlostí se mizerně playtestuje a testovat budeš
potřebovat dřív, než dojdeš na konec fronty.

Hotovo když: `_test_timecontrol` ověří, že deterministický simulátor při 4×
dá **bit-identický** výsledek jako při 1×. Determinismus se nesmí rozbít rychlostí.

**Mechanismus.** Nový fixní tick: `Game.FIXED_TICK_DT` (1/60 s, konstanta) a
`Game._sim_tick(delta)` — obsahuje VŠECHNO, co může ovlivnit RESULT_FIELDS
(pohyb distrakcí/projektilů/habitů, spawn vln, tolerance/burnout/cue,
intervence, routine/fog). `Game._physics_process()` je akumulátor: každý
reálný snímek přičte `_current_speed()` (0.0 při pauze) do `_tick_budget` a
odpálí `floor(budget)` volání `_sim_tick()` — 1×/snímek při 1×, až 4×/snímek
při 4×, cca 1× za 4 snímky při 0.25×. `Engine.time_scale` už neřídí nic
výsledkového — zůstal jen pro kosmetickou vrstvu (DistractionAnimator, screen
shake, glitch/flatten shadery), která běží dál na Godotím automatickém
`_process()`. Entity (Distraction/Habit/Projectile/DefenderUnit) mají
`set_process(false)` a `_process(delta)` na nich volá `_sim_tick()` explicitně
— jméno metody zůstalo `_process` schválně, aby `_test_phase4`/`_test_
suppression`/`_test_nutrition_guild`/`_test_taxonomy`, které ho volají ručně s
pevným `delta`, zůstaly beze změny (jejich očekávání zůstalo netknuté).
Přechod build↔wave zahazuje zbytek `_tick_budget` v tom snímku, kdy nastal —
jinak by při 4× mohlo v jednom snímku doběhnout víc ticků NOVÉ fáze, než
strategie/hráč vůbec stihli fázi zaznamenat (measured: early-call bonus lišící
se o pár Dopamine mezi 1×/4× kvůli tomuhle, dokud fix nepřistál).

**Vedlejší nález, který se ukázal větší než sama rychlost.** `Game.position`
je posun screen-shake (`add_shake()`), reálně-časový a nezávislý na ticku.
Několik míst v `enemy.gd`/`tower.gd`/`projectile.gd`/`game.gd` četlo
`global_position` (obsahuje ten shake) tam, kde patřilo herně-lokální
`position` — spawn distrakce, `_fire()`/`_tick_auto_aim()`/`is_point_in_cone()`/
`_aoe_targets()`/`apply_pulse_to()`, pohyb a zásah projektilu,
`_update_routine_reach()`. Bug byl v repu už předtím, ale nic ho nechytilo,
protože žádný test nesrovnával boj bit-identicky mezi dvěma běhy. Opraveno —
`_test_timecontrol`'s cheap-even blok (věže, co reálně střílí) dá teď
bit-identický výsledek při STEJNÉ rychlosti napříč libovolným počtem
samostatných spuštění (dřív rozptyl kills 29–40 na stejný seed/rychlost).

**Co zůstává otevřené.** Cross-speed (1× vs 4×) pro `cheap-even` NENÍ
bit-identický — reprodukovatelně (ne flaky) jiný přesný počet killů. Kořen
nenalezen v čase, který úkol měl; `_test_timecontrol` to teď explicitně
NEtvrdí (jen "same speed, twice" bit-identical + "4× je rychlejší"), aby test
netvrdil něco neověřeného. Viz BLOCKED.md "Q1 — cross-speed combat divergence"
pro diagnostiku a co zkusit dál. `_test_timecontrol` (passive, quick-hit-spam
— obě NEstaví, ale vlnu/spawn/tolerance/ekonomiku plně cvičí) bit-identické
1× vs 4× JSOU a zůstávají tak i po dvou desítkách opakovaných běhů.

**Skip wave** = existující "▶ Start Wave" akce (`_on_start_wave_pressed()`),
teď navíc pod druhým, jasně pojmenovaným tlačítkem "Skip ▶▶" v shluku
rychlost/pauza — přesně hook, který úkol sám navrhoval.

**Pauza + příkazy**: `Game.process_mode = PROCESS_MODE_ALWAYS` (viz `_ready()`),
`entities.process_mode = PROCESS_MODE_PAUSABLE` explicitně přišpendleno zpátky,
takže kosmetické potomky (DistractionAnimator, in-flight tweeny) pauza dál
zamrazí automaticky. Simulace mrzne přes `_tick_budget` (0 při `_paused`), ne
přes `get_tree().paused` — vstup tedy dojde na handler i za pauzy.

**Hover staty**: žádný hover tooltip předtím NEEXISTOVAL (jen klik-otevřený
panel pro postavený habit, nic pro distrakce). Nový `_hover_tooltip`
(v `_hud_root`, ALWAYS) — habit pod najetou buňkou i nejbližší živá distrakce
pod kurzorem, oba s plnými živými staty (cooldown/rest/disrupt pro habit;
HP/rychlost/rezistence/všechny aktivní statusy pro distrakci).

---

## P6 — SpawnPointData a více aktivních spawnů
Model: sonnet
Needs-me: no
Status: todo

Nová Resource třída:

```gdscript
class_name SpawnPointData extends Resource
@export var cell: Vector2i
@export var direction_id: StringName          # pro telegraf
@export var active_from_wave: int = 0
@export var requires_segment: StringName = &""
@export var telegraph_lead_time: float = 5.0
```

**Flow field se NEMĚNÍ** — víc spawnů čte stejné pole, protože pole je
„všechny zdroje → jeden cíl".

Hotovo když: `_test_multispawn` ověří, že každý aktivní spawn má v každé wave
cestu k cíli, a deterministický simulátor odehraje level s N spawny.

## P7 — telegraf směru
Model: sonnet
Needs-me: no
Status: todo

Vizuální marker směru + odpočet před aktivací nového spawnu.

**TVRDÉ PRAVIDLO: telegraf musí být pravdivý.** Když ukážeš směr, horda z něj
opravdu přijde. Poučení z They Are Billions, kde nesoulad mezi varováním
a skutečným chováním hord je nejčastější stížnost hráčů.

Hotovo když: `_test_telegraph` ověří, že se spawn aktivuje právě po uplynutí
`telegraph_lead_time` a právě na ohlášené pozici. Screenshot do `.dev/`.

## P8 — MapSegmentData a skládání levelů
Model: opus
Needs-me: yes
Status: todo

Level N+1 = LevelData N + segment, **odkazem, ne kopií** (`@export var base: LevelData`).

```gdscript
class_name MapSegmentData extends Resource
@export var id: StringName
@export var anchor_offset: Vector2i
@export var unlock_condition: StringName
@export var adds_spawns: Array[SpawnPointData]
```

**TVRDÝ LIMIT, který v původním zadání nebyl: segment se musí vejít na jednu
obrazovku.** Při 480×270 a 16px dlaždicích je viditelných 30×17 dlaždic,
současná mřížka je 30×14. Segment, který mapu rozšíří za tenhle rámec, vynutí
scrollování — a scrollující mapa podle Douceta (Defender's Quest) rozbíjí
soustředění, na kterém celá hra stojí. `_test_segments` to musí hlídat.

Hotovo když: `_test_segments` ověří, že **každá** kombinace odemčených segmentů
dá validní dokončitelnou mapu (cesta z každého aktivního spawnu k cíli),
že se vejde na obrazovku, a že skládání je deterministické.

## P8b — fog_bandwidth před P9
Model: opus
Needs-me: no
Status: todo

`_test_fog_bandwidth` hlásí, že arc nemá vliv na osvětlenou plochu (36 → 36 buněk
při arc 15 → 120) a že otočení habitu světlem nehne. Podle P0e zjisti, jestli je
mrtvý parametr, nebo se osvětlení počítá jinak než z kužele.
Oprav to, ať už je příčina jakákoli. P9 staví na tomhle a nechci stavět na
systému, o kterém nevím, jestli funguje.

Hotovo když: test zelený, vyřazený z known-broken, a v PROGRESS.md je popsaná
příčina.

---

## P9 — brainfog jako vizuál
Model: sonnet
Needs-me: no
Status: todo

Dva `SubViewport` sdílející stejný `World2D`, maska přes `ViewportTexture`.
Pokud se světla věží překrývají, zvaž shader s viditelnostní texturou místo
Light2D v mask módu — ten má při překryvu nepředvídatelné chování.

**Herní logika se NEMĚNÍ.** Zatím jen vizuál.

Hotovo když: screenshoty do `.dev/screenshots/` včetně rozostřené a odbarvené
varianty. **NEPOSUZUJ je** — vyberu sám.

## P10 — brainfog jako herní pravidlo
Model: sonnet
Needs-me: yes
Status: todo

**Nezačínej, dokud si nezahraju P9 a nepotvrdím to.** Až uvidím mlhu v pohybu,
poznám, jestli je „věž nestřílí, co nevidí" zajímavé, nebo jen otravné.
Research je v tomhle jednoznačný: fog je extrémně citlivý na férovost
a špatně udělaný působí jako náhodný trest, ne jako výzva.

Návrh k implementaci po schválení:
- `visible` grid — přepočítáván z pozic a dosahů habitů
- `explored` grid — jen se přičítá, **nikdy se nezmenšuje**
- věž smí cílit jen buňky ve `visible`
- herní logika čte grid, **ne texturu**
- nepřátelé se nesmí chovat, jako by viděli skrz mlhu, když hráč ne

Hotovo když: `_test_fog` ověří, že věž nikdy nestřílí do ne-visible buňky
a že `explored` se nikdy nezmenší.

## P11 — Quick Hit a Tolerance napojené na mlhu
Model: sonnet
Needs-me: no
Status: todo

- **Quick Hit** dočasně prosvětlí mapu (nával pozornosti)
- **Tolerance** zmenšuje poloměr odhalení (zúžená pozornost)

Obojí přes `ModifierManager`.

Tohle je moment, kdy se z generického TD stane tahle hra. Do P10 stavíš dobrý
tower defense; P11 je ta jedna vrstva, kterou používá všechen obsah — jedna nová
distrakce nebo habit se od teď násobí s každou hodnotou Tolerance.

Hotovo když: regresní testy ekonomiky zelené, `_test_fog_modifiers` ověří obě
vazby na hraničních hodnotách Tolerance 0 a 100.

## P12 — minimapa
Model: sonnet
Needs-me: no
Status: todo

Nutná, jakmile je P10 zapnuté — bez ní hráč nemůže plánovat a fog se změní
ve frustraci.

Ukazuje `explored` terén, **ne jednotky**.

Hotovo když: test ověří, že minimapa nikdy neukáže víc, než co je v `explored`.

---

## Q2 — Quick Hit jako zpočátku dominantní tah
Model: opus
Needs-me: yes
Status: todo

**Tohle je specifikace, ne návrh na doladění.** Sdělení hry dorazí jen tehdy,
když hráč lituje **vlastní optimalizace**. Když je Quick Hit vyvážený jako férový
tradeoff, hráč si ho rozmyslí, nikdy nespadne do smyčky a mechanika neřekne nic.

Přes deterministický simulátor (S2) ověř, jestli je „spamuj Quick Hit" v prvních
třech levelech objektivně nejlepší strategie. Porovnej aspoň:
- nic nestavět
- stavět levné habity rovnoměrně
- spamovat Quick Hit
- kombinace

Pokud dominantní není, navrhni úpravu čísel v `data/` tak, aby byla — ale
**čísla neměň bez mého souhlasu.** Analýzu do `BLOCKED.md` s konkrétními
hodnotami a odůvodněním.

## Q3 — capsule art specifikace
Model: sonnet
Needs-me: yes
Status: todo

**NEGENERUJ přes PixelLab.** Steam capsule art je nejčastější terč „AI slop"
kritiky a první věc, kterou hráč na Steamu vidí. Doložené případy backlashe
existují i tam, kde bylo obvinění falešné.

Připrav specifikaci: rozměry všech Steam capsule formátů, co má obrázek
komunikovat, jaké prvky ze hry použít. Art udělám nebo objednám já.

---

## Za tímto souborem

Milník **„prvních 15 minut"** — tři levely nesoucí celý oblouk: Quick Hit je
zjevně nejlepší tah, hráč ho začne spamovat, Tolerance mu zúží kužely, a přijde
okamžik, kdy kvůli tomu nevidí hordu, kterou by jinak snadno zvládl.

Není rozepsaný schválně. Bude záviset na výsledku P10 a Q2 a psát ho teď by
bylo naslepo.

## Čeká na člověka mimo tuhle frontu

- **S4** (`SYSTEMS.md`) — palette-swap shader, mechanicky hotový, čeká na vizuální
  úsudek. Odemyká barevné varianty distrakcí za nula PixelLab generací.
- **S7** (`SYSTEMS.md`) — tvary spawnu ve vlnách, schéma a runtime hotové,
  validace a obsah otevřené.