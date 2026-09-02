# Pathfinding, multi-směr, segmenty, brainfog

Pořadí je podle poměru užitek/práce. **NEMĚŇ ho** a nepracuj na jiném úkolu,
než který ti určil runner.

> **Obnoveno 2026-09-02 autonomním během.** Commit `2331f13` („test") zkrátil
> tenhle soubor z 866 řádků na 44 a přitom přepsal `Status: done` zpátky na
> `todo` u P4, P5 a Q1 — úkolů prokazatelně hotových (commity `9d47688`,
> `bd39167`, `c65dfa6`, zápisy v `PROGRESS.md`, kód na disku, zelené fixtures).
> Zkrácení navíc vyhodilo z fronty P6, P7, P8, P8b, P9, P10, P11, P12, Q2 a Q3
> úplně. `tools/next_task.py` vrací **první** `todo`, takže autonomní smyčka by
> nad hotovým kódem začala znovu dělat P4. Obsah je vrácený z
> `git show 80b56e7:docs/refactor/PATHFINDING.MD` (poslední verze před
> zkrácením), statusy srovnané podle commitů a `PROGRESS.md`, a přidán je úkol
> `_test_shadow_occlusion`, který ve staré frontě nebyl. Soubor teď žije
> v kořeni repa (`PATHFINDING.MD`), kam míří `run.sh` i `loop.sh`; stará cesta
> `docs/refactor/PATHFINDING.MD` je smazaná. Rozbor v `BLOCKED.md` →
> „Zkrácená fronta". Stejná nehoda se stala už jednou, viz `c833e76`.

> **PLNÁ AUTORIZACE 2026-09-02.** Uživatel: *„je potřeba s projektem postoupit, tak
> udělej autonomní plán beze mě, vše ti povoluji jako uživatel."* Tím padají brány
> `Needs-me: yes` u P8b, P10 a Q3 — rozhodnutí, na která čekaly, dělám sám a každé
> zapisuju s odůvodněním do `PROGRESS.md`, aby se dalo kterékoli z nich vrátit jednou
> větou. Padá i podmínka „změna assertion v `_test_*` potřebuje moje svolení".
>
> **Co ani tahle autorizace nemění, a proč:**
> - **Negeneruju v PixelLabu.** Utrácí to tvoje předplacené generace (peníze) a
>   `CLAUDE.md` to zakazuje jmenovitě. „Povoluji ti vše" v chatu nečtu jako „utrať mi
>   kredity". `_test_zen_pulsar` vyřeším bez generování.
> - **Nepushuju a nepřepínám větev** — taky explicitní pravidlo a nevratné směrem ven.
> - **Nemažu nic v `data/`.** Co je k vyřazení, vyřadím tak, že to přestane být
>   načítané, a napíšu to; smazání je tvoje.
> - **Nehodnotím vzhled, jako bych ho viděl.** Mechanismy stavím za existující
>   per-level přepínače v `LevelData` (`fog`, `shadows`, `quick_hit`, …), takže
>   estetické rozhodnutí zůstává tvoje a je to jeden bool v `.tres`.
>
> **Plán, který z toho vznikl,** je milník „prvních 15 minut" (M1–M4, M9 níž). Fronta
> si ho sama odložila slovy *„Není rozepsaný schválně. Bude záviset na výsledku P10
> a Q2."* — Q2 je hotové (`3e6a87e`) a P10 je teď odblokované, takže je čas ho napsat.
>
> **Proč právě tohle pořadí, a ne rovnou P10/P11/P12:** Q2 změřilo, že **hru dnes nejde
> vyhrát** — 24 z 24 simulovaných běhů (2 levely × 4 strategie × 3 seedy) končí porážkou,
> `victory=false` bez výjimky. `docs/core/00_overview.md` přitom hru definuje jako
> *„a small, **winnable**, easily-tuned prototype"* a jako první pilíř má *„Fun first,
> lesson second. If a level isn't fun, the lesson doesn't land."* Mlha jako pravidlo,
> modifikátory a minimapa jsou vrstvy na hře, kterou zatím nikdo neporazí — proto jdou
> M1–M4 první. Není to změna priorit od stolu: je to ten pilíř aplikovaný na měření,
> které už v repu leží.

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

**Znovu otevřen v kondenzované frontě 2026-09-02** — s `Needs-me: yes` a
zadáním „změř na reálné hře po P4/P5: přepočty za sekundu při běhu se stovkami
jednotek a při rychlém stavění zdí, nejhorší čas jednoho rebuildu; zapiš do
PERF.md a doporučení do BLOCKED.md; NEIMPLEMENTUJ". Nepracováno na tom —
`Needs-me: yes`. Část toho měření ale existuje: `docs/PERF.md` §„Does this
reopen P3 (dirty-region flow field recompute)?" je psaná po P4, tedy přesně to
„po P4/P5", které zadání žádá. Co od tebe potřebuju rozhodnout: `BLOCKED.md`
→ `## P3 (dirty-region přepočet)`.

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
Status: done

`scripts/resources/spawn_point_data.gd` (`SpawnPointData`) — přesně podle zadání, jen
s doc-komentáři. `direction_id`/`telegraph_lead_time` se nesou, ale nepoužívají (P7);
`requires_segment` neprázdný = "nikdy aktivní" (P8 neexistuje, nic ho nemůže odemknout) —
ne tichý no-op, ale explicitní rozhodnutí v `Game._active_spawn_point_cells()`.

`LevelData.spawn_points: Array[SpawnPointData] = []` — ADITIVNÍ ke `spawn_zones`, ne
náhrada. Prázdné (každý level dnes, protože to nic neautorovalo) = `_random_spawn_cell()`
se chová bit-identicky jako před P6. Neprázdné = kreslí VÝHRADNĚ z bodů aktivních pro
danou vlnu (`active_from_wave <= wave_number`), `spawn_zones` se pro ten level přestane
používat (ne sloučit, přepsat). `_start_wave()` teď volá `_random_spawn_cell(wave_index +
1)` — jediné volací místo ve hře; `wave_number` má default `1`, takže ~20 existujících
volání `game._random_spawn_cell()` bez argumentu (testy spawnující distrakce mimo vlnu)
zůstala beze změny — jejich levely nikdy `spawn_points` nenaplní, takže by na parametru
stejně nezáleželo.

Flow field se skutečně nezměnil — `Game._rebuild_flow_field()` beze změny, `_test_multispawn`
staví JEDNO pole a čte ho pro všechny vlny/spawny, přesně jak P6 předepsal.

`_test_multispawn` (`scripts/_test_multispawn.gd` + `.tscn`, ve `verify.sh`
`FIXED_FPS_TESTS`): syntetický level klonovaný z geometrie levelu id 1 (známě funkční),
`spawn_zones` schválně prázdné (bez legacy fallbacku bug v gatingu spadne jako crash, ne
tichý průchod), 5 `SpawnPointData` (dva aktivní od vlny 1, jeden od vlny 2, jeden od
poslední vlny, jeden navždy neaktivní přes `requires_segment` a schválně zazděný v
kapse). Tři nezávislé kontroly: (1) reachability — jedno `FlowField.build()`, `has_cell()`
pro aktivní spawny každé vlny, přesně postup z `AntiBlockValidator` (P2); (2) gating
wiring — přímé volání skutečné `Game._active_spawn_point_cells()`/`_random_spawn_cell()`
(instancovaná `Game.tscn`, ne reimplementace) proti ručně spočítané očekávané množině
pro vlny 1-4 plus sanity na vlně 999; (3) playthrough — `LevelSimulator.run()` s
`SimStrategyPassive` level odehraje do vítězství (Focus 999 schválně vysoko, aby
Focus nebyl to, co test ukončí dřív, než se všechny spawny stihnou aktivovat).
Fixture level je čistě in-memory (`LevelData.new()`, `SpawnPointData.new()`), zapsaný do
`Data._levels` runtime appendem (stejný vzor jako `Data._ready()` samo používá) — nikdy
žádný `.tres`, takže "NEPIŠ level .tres ručně" zůstává nedotčené.

Ověřeno: `_test_multispawn` PASS samostatně i uvnitř celého `./verify.sh`;
`_test_flowfield`, `_test_antiblock`, `_test_level_simulator`, `_test_timecontrol`,
`_test_mapeditor`, `_test_maze_validity`, `_test_effort`, `_test_streak` beze změny
(stejný baseline jako před P6). Celé `verify.sh` PASS, žádné nové known-broken.

Nedotčeno záměrně: `addons/td_level_designer/` (spawn_points není editovatelný z docku —
mimo rozsah tohoto úkolu), vizuální telegraf/marker spawn bodů (P7), segment-unlocking
logika pro `requires_segment` (P8).

## P7 — telegraf směru
Model: sonnet
Needs-me: no
Status: done

Vizuální marker směru + odpočet před aktivací nového spawnu.

**TVRDÉ PRAVIDLO: telegraf musí být pravdivý.** Když ukážeš směr, horda z něj
opravdu přijde. Poučení z They Are Billions, kde nesoulad mezi varováním
a skutečným chováním hord je nejčastější stížnost hráčů.

Hotovo když: `_test_telegraph` ověří, že se spawn aktivuje právě po uplynutí
`telegraph_lead_time` a právě na ohlášené pozici. Screenshot do `.dev/`.

**Časování (rozhodnutí, které zadání nechalo na mně):** odpočet začíná přesně v
okamžiku, kdy začne bodova VLASTNÍ vlna (`active_from_wave == wave_number`), ne o
vlnu dřív v build fázi — přímočařejší čtení, žádný nový lookahead. Bod s
`active_from_wave == 0` (výchozí, "aktivní od vlny 1") se NIKDY netelegrafuje —
není tam žádný okamžik aktivace, který by se dal ohlásit, viz vlastní komentář
`SpawnPointData.active_from_wave`. Odpočet drží `Game.wave_time` (existující pole,
nulované v `_start_wave()`, tikané jen v `_sim_tick()` dokud `wave_spawning`) —
žádná nová proměnná nebyla potřeba, je to doslova "kolik sim-sekund uběhlo od
začátku téhle vlny". Pauza ho automaticky zamrazí zadarmo: `_sim_tick()` se
nezavolá, dokud `_physics_process()`'s akumulátor negeneruje tick, a ten při
`_paused` negeneruje nic (Q1) — netřeba žádná zvláštní pauza-vs-telegraf logika.

**Mechanismus.** `Game._active_spawn_point_cells(wave_number, wave_elapsed: float =
INF)` — nový volitelný druhý parametr. Default `INF` zachovává PŘESNĚ původní
chování (`_test_multispawn`'s přímá volání s jedním argumentem dál sedí beze
změny) — telegraf gate je opt-in přes tenhle parametr, ne tichá změna toho, co
funkce už odpovídala. Bod je vynechán jen na SVÉ VLASTNÍ aktivační vlně
(`active_from_wave == wave_number`, `active_from_wave > 0`) dokud `wave_elapsed <
telegraph_lead_time` — každou další vlnu rovnost neplatí a bod je aktivní bez
ohledu na `wave_elapsed`. Nová `Game._pending_spawn_points(wave_number,
wave_elapsed)` je doplněk — přesně ty body, co gate výše vynechal — čte ji jak
kreslení marker, tak `_test_telegraph` (ne reimplementace, skutečná metoda).

**Produkční zapojení bylo chytlavější, než vypadalo.** Puvodní `_start_wave()`
řešil buňku KAŽDÉHO spawnu HNED při stavbě fronty (`_random_spawn_cell()` volané
jednou na entry, než vlna vůbec začne tikat) — kdybych na tenhle okamžik natvrdo
poslal `wave_elapsed = 0.0`, level s JEDINÝM právě aktivujícím se spawn bodem by
měl na začátku vlny prázdnou aktivní množinu a spadl by na fallbacku do
`spawn_zone_cells` (prázdné u každého levelu, co používá `spawn_points` — P6).
Řešení: pro level používající `spawn_points` (a JEN pro něj — `spawn_zones`
levely, tedy dnes všechny reálné levely, mají frontu beze změny) se buňka entry
řeší LÍNĚ, až v `_sim_tick()` v okamžiku, kdy entry skutečně vyskočí z fronty —
`_random_spawn_cell(wave_index + 1, wave_time)` se skutečným, právě natikaným
`wave_time`. To je jediné volací místo, které kdy pošle jiný `wave_elapsed` než
default. Vedlejší efekt zdarma: entry naplánovaný na dřívější čas než
`telegraph_lead_time` prostě vybere z toho, co JE aktivní (typicky starší
baseline bod) — nic nepropadne, nic nespadne, telegraf nikdy nezaláže.

**Kreslení.** `Game.TelegraphOverlay` (vnořená třída, sourozenec `PlacementOverlay`,
ne `StaticOverlay` — potřebuje kreslit KAŽDÝ reálný snímek kvůli pulzu a odpočtu,
`StaticOverlay` se překresluje jen na explicitní trigger). Nad Brain Fog
(`Z_FOG + 2`) ze stejného důvodu jako placement preview: telegraf, co není vidět
kvůli tmě, porušuje vlastní tvrdé pravidlo. `_draw_spawn_telegraph()` kreslí
pulzující kruh PŘESNĚ na `sp.cell` (to je ta polovina "pravdivosti", co nikdy
nezávisí na `direction_id`), volitelnou kompasovou šipku pro `direction_id`
("N"/"NE"/"E"/"SE"/"S"/"SW"/"W"/"NW" — konvence, kterou jsem musel zvolit, protože
ji nikde nic nepoužívalo; prázdná/neznámá hodnota jen vynechá šipku) a odpočet v
sekundách. Čistě kosmetické — čte `wave_time`/`wave_index`, nikdy je nezapisuje.

`scripts/_test_telegraph.gd` + `.tscn`: syntetický level (geometrie klonovaná z
levelu id 1, `spawn_zones` schválně prázdné) se DVĚMA `SpawnPointData` — baseline
(`active_from_wave 0`, nikdy gatovaný) a testovaný bod (`active_from_wave 1`,
`telegraph_lead_time 0.3`), aby "nikdy neuteče brzo" bylo skutečně TESTOVANÉ
(entry naplánované před crossing musí reálně existovat, ne jen chybět). Řízeno
přímými voláními `Game._sim_tick(FIXED_TICK_DT)` (žádný `--fixed-fps` potřeba —
žádný `await` mezi voláními, takže Godotí automatický `_physics_process` se nikdy
nevmísí). Tři vrstvy důkazu: (1) `_pending_spawn_points()`/
`_active_spawn_point_cells()` souhlasí na KAŽDÉM ticku s nezávislou
reimplementací zadání (`_expected_pending()`), přechod pending→live nastal
přesně jednou; (2) `SignalBus.distraction_spawned` zachytává buňku KAŽDÉHO
reálného spawnu přesně v okamžiku vzniku (dřív, než ho vlastní `_process()` stihne
posunout); (3) žádný spawn před crossing nepřistál jinde než na baseline bodu,
aspoň jeden spawn po crossing přistál PŘESNĚ na `sp.cell`. Screenshot:
`.dev/screenshots/p7_telegraph.png` (`scripts/_shot_telegraph.gd` +
`.tscn`, stejný vzor jako P5's `_shot_crowd.gd` — reálný renderer, ne headless).

Ověřeno: `_test_telegraph` PASS samostatně i uvnitř celého `./verify.sh` (36
pass, 0 fail, 4 pre-existing known-broken beze změny, 0 flaky). `_test_multispawn`
beze změny (jeho jednoargumentová volání `_active_spawn_point_cells`/
`_random_spawn_cell` dostávají default `INF`).

Nedotčeno záměrně: `addons/td_level_designer/` (žádný level dnes `spawn_points`
neautoruje — mimo rozsah), segment-unlocking pro `requires_segment` (P8).

## P8 — MapSegmentData a skládání levelů
Model: opus
Needs-me: yes
Status: done

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

**ROZHODNUTO 2026-08-30 (uživatel), tři otevřené otázky, které `Needs-me: yes`
držel.** Zadání výš je ponecháno beze změny; tohle je jeho doplnění, ne přepis.

1. **Co segment skládá.** `MapSegmentData` nenese vlastní geometrii v žádném
   novém poli — **odkazuje na další `LevelData`** (stejné „odkazem, ne kopií",
   jaké P0 už rozhodl pro `base`). Struktura výš zůstává, jak je; geometrie
   segmentu se čte z toho odkazovaného `LevelData`, umístěná na `anchor_offset`.
   Důvod: pole `adds_spawns` samo o sobě nedávalo `anchor_offset` ani limitu
   „vejde se na obrazovku" žádný smysl — spawny plochu mapy nerozšiřují.
2. **Odkud se bere místo.** **Zmenšit základní mřížku.**
   > ⚠️ **TENHLE BOD STOJÍ NA CHYBNÉM ČÍSLE — viz „VYŘEŠENO" níž.** „Viditelných
   > 30×17" (převzato ze zadání výš) je `270/16` BEZ odečtení HUD lišt; skutečně
   > viditelných je **30×14**, tedy přesně to, co `Data.GRID` už má. Mřížka se
   > proto NEZMENŠOVALA — zmenšení by volné místo sebralo, ne vytvořilo.
   > Ponecháno beze změny jako záznam toho, co bylo rozhodnuto a proč;
   > „naměřeno na skutečných datech" platí pro čísla o levelech (x≤28, y 2..11),
   > ne pro ten počet viditelných řádků.

   Naměřeno na skutečných
   datech (ne odhad): `Data.GRID` je 30×14, viditelných je 30×17.
   - Vodorovně je rezerva **nula** (480 px / 16 px = přesně 30 sloupců) a
     `level_1`/`level_98` sahají po `x = 28` (objective je `Vector2i(28, 7)` v
     obou) — volný je jediný sloupec 29. Vodorovně tedy prakticky zmenšovat
     nelze bez přeautorování levelů.
   - Svisle obsah obou levelů zabírá jen `y = 2..11`; řádky 0, 1, 12, 13 jsou
     prázdné. Mřížka smí spadnout na **12 řádků** (0..11), aniž by cokoli
     vypadlo z rozsahu. Rozpočet na růst segmentů je pak **17 − 12 = 5 řádků
     svisle, ~1 sloupec vodorovně.**
   - Pozor: **objective je na `x = 28`.** Jakékoli VODOROVNÉ zmenšení pod 29
     sloupců ho vyhodí mimo mřížku a rozbije pathfinding — přesně ta chyba, kterou
     PROGRESS.md zaznamenal u T0 („objective mimo 24×24 mřížku"). Zmenšovat tedy
     jen svisle.
3. **Co kontroluje `unlock_condition`.** **`MetaProgression`** (existující
   autoload) — odemčení přežívá napříč runy, ne per-level a ne přes growth strom.

**VYŘEŠENO 2026-08-30.** `MapSegmentData` má přesně ta čtyři pole ze zadání,
žádné navíc. Odkaz na geometrii jde OPAČNÝM směrem, než se čekalo: `LevelData` dostal
`base: LevelData` (řetěz, „odkazem ne kopií") **a `segment: MapSegmentData`** — link
s hlavičkou JE segment, jeho vlastní `high_ground`/`path_cells`/… je geometrie
segmentu, umístěná na `anchor_offset`. Důvod pro tenhle směr: segment musí být
autorovatelný, a jediná posvěcená cesta k autorování geometrie je `MapEditor.tscn`
bakující `LevelData` — takže segment se maluje existujícími nástroji a hlavička je ta
jediná malá věc navíc. Pole s geometrií na `MapSegmentData` by si vyžádalo druhý,
paralelní editor. `scripts/map_composer.gd` (`MapComposer`) chodí řetěz a vrací jeden
plochý `LevelData`; `Game._ready()` ho volá místo bývalého `level.duplicate(true)`
(pro level bez `base`/`segment`, tedy každý level na disku, JE compose ten deep copy).

**Mřížka: `Data.GRID` ZŮSTALA 30×14, záměrně.** Rozhodnutí #2 stálo na „viditelných je
17 řádků"; skutečně naměřeno je **14** — `(270 − 24 spodní lišta − 17 origin_y) / 16 =
14`, přesně kolik `Data.GRID` má. Těch 17 vyšlo z `270/16` bez odečtení HUD lišt.
Zmenšení na 12 řádků by proto místo nevytvořilo, ale **sebralo dva ze čtyř volných
řádků**: levely obsazují jen `y = 2..11`, takže řádky 0, 1, 12, 13 a sloupec 29 jsou
volné UVNITŘ existující mřížky a to je ta rezerva, kterou segmenty vyplňují. Vodorovně
se nesahalo vůbec (rozhodnutí #2 to zakazuje a naměřeno 480/16 = přesně 30 sloupců).
Skládání tak mřížku nikdy nezvětšuje — limit „vejde se na obrazovku" je strukturální,
ne jen testovaný: segment, jehož geometrie po anchoru vypadne z `board_budget()`, je
při skládání ZAHOZEN s `push_error`.

**`unlock_condition` → `MetaProgression.is_segment_unlocked()`** nad novým
`SaveGame.unlocked_segments` (vlastní seznam, ne `cleared_levels`, ne `growth_ranks` —
přesně jak rozhodnutí #3 žádá). `SpawnPointData.requires_segment` (háček z P6) se ale
neptá save souboru, nýbrž **složené desky**: `LevelData.active_segments` (runtime pole,
jako `waves`) vyplní `MapComposer`, a `Game._segment_is_live()` je jediné místo, které
ho čte. Odemčený, ale zahozený segment tedy nespawnuje — telegraf zůstává pravdivý.
Prázdné `active_segments` (každý level na disku) = neprázdný `requires_segment` je
„nikdy aktivní", bit-identicky s P6/P7.

**Determinismus:** nepodmíněná páteř se skládá od kořene, živé segmenty pak podle
`segment.id`; buňky jsou množiny řazené podle (y, x). Deska tedy závisí jen na tom,
KTERÉ segmenty jsou živé — ne na pořadí v řetězu ani na pořadí v množině odemčení.

`_test_segments` (+ `.tscn`, ve `verify.sh` `FIXED_FPS_TESTS`) — osm kontrol,
16/16 kombinací vyčerpáno, 232 tras ověřeno, 64 skládání porovnáno na shodu.
Detaily a čísla v `PROGRESS.md`.

## M1 — proč hru nejde vyhrát (DIAGNÓZA, měřením, ne dojmem)
Model: opus
Needs-me: no
Status: done

Q2 (`BLOCKED.md`) doložil: **24 z 24 běhů prohra** — obě existující úrovně, všechny
čtyři strategie, tři seedy, `victory=false` pokaždé. `docs/core/00_overview.md` říká
„a small, **winnable**, easily-tuned prototype". Tohle je nejzávažnější rozpor v repu.

Změř, kde přesně se run láme. Ne odhad — čísla:
- Efektivní DPS každého habitu proti `compulsion`/`rationalization` každé distrakce,
  a kolik sekund tedy trvá zabít jeden kus.
- Kolik sekund je distrakce vůbec v dosahu habitu na skutečné dráze levelu
  (`path_cells` + flow field), tj. kolik DPS se reálně uplatní.
- `focus_damage` × počet průniků za vlnu proti `LevelData.focus`.
- Wave curve: kolik kusů kdy přijde (`base_count` + `growth_per_wave`).
- Zvlášť pro `level_1`: proč **0 killů** i s postavenými habity. Nula je moc kulaté
  číslo na „je to těsné" — hledej vadu, ne balanc.

Rozšiř `scripts/_balance_sweep.gd` o rozpad **po vlnách** (kills, leaks, Focus na konci
vlny), aby se dalo vidět, která vlna run zabije.

Hotovo: `docs/BALANCE.md` má tabulku „kde se run láme" a **jmenuje příčinu**, ne dojem.
Žádná změna balance v tomhle úkolu — M1 měří, M2 opravuje.

**Hotovo 2026-09-02. Pět příčin, všechny změřené** (plné znění v `PROGRESS.md`,
čísla v `docs/BALANCE.md` §0–§5):

1. **Aritmetika je nepřátelská, ne těsná.** `level_1`: pool 30, leak 42 (140 %).
   `level_98`: pool 25, leak **78 (312 %)** — hráč musí zastavit **69 % hordy**.
2. **Skoro není kam stavět.** `CORE_ROUTINE_RADIUS = 165 px`, stavební bloky leží
   144–292 px od jádra, a `in_routine` gatuje **střelbu**, ne jen umístění.
   `level_1` má 3 bloky / **1 použitelný**; `level_98` má na celé desce **2**.
3. **Nejlevnější habit je proti hlavnímu tankovi jen „chip".** `focus_timer` 3 Willpower
   vs. `doomscroll` `compulsion = 4` → podlaha 1 dmg, **40 ran = 4,0 s** na jeden kus.
   `exercise` to samé zvládne 2 ranami — a **žádná z původních baseline ho nestaví**.
4. **Nic nemíří, a default směr je opačný.** `facing_angle` startuje na 0 rad = na VÝCHOD,
   všechny levely spawnují na ZÁPADĚ. Nová baseline `counter-pick + aim` (jen tahle dvě
   rozhodnutí) zvedla `level_1` z **0 na 5 killů** — takže „všechny strategie prohrály"
   se NESMĚLO číst jako „hra je nevyhratelná".
5. **`level_1` běží v defaultní konfiguraci, ne ve své.** Nenastavuje `fog`, `shadows`
   ani `routine_gates`, takže bere defaulty `true`/`true`/`true` — nejrestriktivnější
   nastavení v projektu, omylem.

Nové nástroje, obojí trvalé: `scripts/sim_recorder.gd` (rozpad po vlnách) a
`scripts/sim_strategy_counter_pick.gd` (baseline „hraje rozumně").

## M2 — level 98 „First Light" musí jít vyhrát
Model: opus
Needs-me: no
Status: done

Nejmenší datová změna podle M1, po které je `level_98` vyhratelný — a **pořád
prohratelný**. Level, který se vyhraje sám, neučí nic; pilíř je „fun first".

Hotovo: sweep dokazuje **`victory=true` pro `counter-pick + aim`** a `victory=false`
pro `passive`; `_test_levels` a `_test_maze_validity` zelené; čísla před/po
v `docs/BALANCE.md` i s tím, které pole v `data/` se hnulo a proč.

**Kritérium změněno po M1, a tady je proč.** Ráno tu stálo „`victory=true` pro
`cheap_even`". M1 změřilo, že `cheap_even` nikdy nemíří a nikdy nekoupí protilék —
level vyladěný tak, aby vyhrál i on, by musel jít vyhrát s věžemi otočenými pryč od
hordy. Nová laťka je „kdo udělá dvě zjevná rozhodnutí, vyhraje; kdo nedělá nic,
prohraje", a `cheap_even` mezi tím tvoří gradient dovednosti — vlastnost, kterou má
dobrý level mít.

**Hotovo 2026-09-02.** Změna: **čtyři čísla ve `wave_curve`** `level_98`, nic jiného
(`notification` `base_count` 6→4, `growth_per_wave` 2.5→1.5; `doomscroll` 2→1, 1.5→0.5).
Horda 67→41 kusů, celkový leak 78→46, „musí se zabránit" **54→22** (69 % → 48 % hordy).
Výsledek na třech seedech: `counter-pick + aim` **WIN/WIN/WIN** (zbylo 10, 7, 13 z 25
Focusu), `cheap_even` WIN ×3, `passive` **LOSS ×3**. Focus ani start_dopamine se
nehnuly — větší pool by level jen prodloužil, ne změnil poměr „kolik zvládnou dvě věže".
Že jsou na desce 30×14 jen **dva** stavební bloky, zůstává otevřené a patří do M3.
Sweep zároveň umí tři seedy (`SEEDS`), protože verdikt z jednoho seedu není verdikt.

## M3 — `level_1` přestane být placeholder
Model: opus
Needs-me: no
Status: done

`display_name = "Placeholder — square grid smoke test"`, 0 killů pro každou strategii,
smrt ve vlně 2 vždy. Design doc chce „start with 2 levels" — dnes je jeden nedodělaný
a jeden skoro hratelný.

Rozhodni podle M1 (obojí je legitimní, ale rozhodnutí zapiš):
- (a) udělat z něj skutečný **tutoriálový** level 1: jedna dráha, jeden druh distrakce,
  bez Quick Hitu — první level nesmí učit dvě věci naráz;
- (b) vyřadit ho z kampaně (přestat ho načítat) a povýšit `level_98` na level 1.

**NEPIŠ level `.tres` ručně** — geometrie patří přes `tools/`, jak říká CLAUDE.md.
Změna čísel (`focus`, `start_dopamine`, `wave_curve`) je běžná datová editace.

Hotovo: `data/levels/` obsahuje dva levely, které dávají smysl vedle sebe; sweep má pro
oba nenulové killy; `_test_levels`, `_test_ascii_sidecar` a side-cary zelené.

**Hotovo 2026-09-02, zvolena varianta (a).** Důvody (plně v `PROGRESS.md`): overview chce
„start with 2 levels", takže (b) by nechalo kampaň s jedním; `level_1` má **3** stavební
bloky proti dvěma na `level_98`, takže je to z obou ta LEPŠÍ tutoriálová deska; a (b) by
si vyžádalo mechanismus vyřazení, který neexistuje.

`level_1` je teď **„First Ping"**: distrakce `doomscroll` → `notification` (M1 §3:
`focus_timer` proti doomscrollu je chip, takže první level učil hráče tankem, na kterého
startovní věž nestačí), `focus` 30→**15** aby šel prohrát, a **pět polí přepsaných
z „nenastaveno" na explicitní** — `fog`/`shadows`/`routine_gates` na `false` (dřív mlčky
`true`, což samo dělalo 2 ze 3 míst nepoužitelnými), `id`, `quick_hit`, plus `streak` na
`true` podle vlastního komentáře v `LevelData`. Geometrie beze změny.

Výsledek na třech seedech: `passive` **LOSS ×3**, `cheap_even` **WIN ×3 s 15/15 Focusu**
(bez jediné ztráty), `counter-pick` WIN ×3 (13–14/15). Použitelná stavební místa **1 → 3
ze 3**. Vznikl gradient: First Ping končí na 15/15, First Light na 7–13 z 25.

## M4 — Quick Hit zapnout a doručit jeho lekci
Model: opus
Needs-me: no
Status: blocked

`LevelData.quick_hit` je `false` na **každém** levelu v projektu, takže „stiskni Quick
Hit" a „nedělej nic" jsou dnes bitově identická akce (Q2, 0 použití ve 24 bězích).
Signature mechanika #2 z `00_overview.md` tím pádem neexistuje ve hře, jen v dokumentaci.

Zapni ji na druhém levelu (overview: *„Introduced on level 2"*) a vyvaž ji tak, aby
**lekce dorazila**: spam Quick Hitu musí být zpočátku objektivně nejlepší tah a později
se vymstít přes Toleranci. Q2 už vypsalo, které páky existují — a taky že
`QUICK_HIT_BASE/COOLDOWN/SPIKE/FLOOR_GAIN` jsou konstanty v `game.gd`, ne pole
v `data/`; jestli se hýbe konstantou, patří to do zápisu.

Hotovo: sweep ukazuje `quick_hit_spam` **lepší než `cheap_even` v prvních dvou vlnách
a horší na konci levelu**, na všech třech seedech. Tohle je ta lekce, měřená.

**BLOKOVÁNO 2026-09-02 na M5 (Q1b). Změřeno je všechno, zapnuto nic** — plné znění
v `PROGRESS.md`:

- Vznikla a zůstává nová baseline `scripts/sim_strategy_cheap_even_plus_quick_hit.gd`
  (staví jako `cheap_even` **a** mačká). Bez ní lekci změřit nejde: `quick_hit_spam`
  nestaví, `habits + emergency QH` mačká až pod 30 % Focusu.
- Se zapnutým `quick_hit` byla Tolerance poprvé nenulová (19,8–29,5) — a spam vyšel
  **čistě výhodný**: víc Focusu, víc killů, +120 dopaminu na každém seedu. Hra by dnes
  učila opak toho, co má.
- Tři doložené příčiny: (1) **dopamin nemá kam odtéct** — dvě stavební místa, utratí se
  60 z 300; (2) **Quick Hit dává i Craving, což je záměrně skutečný buff** (`tower.gd`
  to sám píše), takže stisk je bojová výhoda; (3) **jediný postih Tolerance je násobič
  výplaty** na měně z bodu 1 — postih, který téma slibuje (zúžená pozornost), je P11.
- **Proč vráceno:** se zapnutým Quick Hitem padá `_test_timecontrol` — 1× vs 4×, liší se
  **jen `tolerance`** (19,873 vs 20,257), vše ostatní identické. Je to `## Q1b`
  z `BLOCKED.md`, do teď neviditelné, protože Tolerance byla vždycky 0.
- **Pokus o opravu Q1b selhal a je to zapsané**, aby to nikdo nezkoušel podruhé: číst
  `_sim_tick_count` a udělat tolik `_step()`, kolik ticků uběhlo, **situaci zhorší**
  (rozejde se i `passive`) — čtyři kroky uvnitř jednoho snímku pozorují týž simulovaný
  okamžik. Oprava musí být hook **uvnitř `Game._sim_tick()`**. To je M5.

Až M5 projde, tenhle úkol je jedna řádka v `.tres` a jeden sweep.

## M5 — Q1b: strategie musí rozhodovat na sim ticku, ne na vykresleném snímku
Model: opus
Needs-me: no
Status: done

`LevelSimulator` tiká `SimStrategy` jednou za **vykreslený snímek**, zatímco
`game.gd _physics_process()` odpálí `_current_speed()` sim ticků uvnitř každého z nich.
Při 4× tedy strategie jedná na **čtyřikrát hrubší** mřížce simulovaného času — což není
ovládání rychlosti, ale obtížnost. `sim_strategy.gd` přitom ve vlastní hlavičce slibuje
„ticked once per simulated frame".

Diagnóza je hotová (`BLOCKED.md` → `## Q1b`, 30. 8.): první akce běhu padne na sim tick 2
při 1× a na tick 6 při 4×, stejné rozhodnutí, jiný okamžik — a od druhé build fáze se to
kumuluje (507 vs 543 dopaminu, 30 vs 39 killů).

**Co NEDĚLAT** (změřeno 2. 9., zhoršuje to): číst `game._sim_tick_count` v driveru a volat
`_step()` tolikrát, kolik ticků uběhlo. Čtyři kroky uvnitř jednoho snímku pozorují týž
simulovaný okamžik, takže se granularita neopraví — a rozejde se i `passive`
(dopamine 158 vs 159), který byl předtím bit-identický.

Oprava tedy musí dostat rozhodování dovnitř `Game._sim_tick()` — volitelný pozorovatel na
autoritativních hodinách, který nastaví jen `LevelSimulator`. Pozor na dvě věci:
`_step()` řeší i draft overlay (ten žije na vykreslených snímcích, ne na ticích), a při 1×
se **nesmí změnit nic** — `docs/BALANCE.md` se generuje celé na 1× a všechna dosavadní
čísla musí zůstat srovnatelná.

Hotovo: `_test_timecontrol` je zelený i se **zapnutým** `quick_hit` na `level_98`
(`passive` i `quick-hit spam` bit-identické 1× vs 4×), `_test_level_simulator` zelený,
a sweep na 1× dá tatáž čísla jako před opravou.

**Hotovo 2026-09-02.** Řešení je `Game.sim_observer` — volitelný `Callable` volaný na
úplném konci `_sim_tick()`, hned za `_check_wave_progress()`. Nastaví ho jedině
`LevelSimulator` a před uvolněním `Game` ho vynuluje; ve skutečné hře je prázdný.

Vyšlo to **líp, než zadání žádalo**: bit-identické 1× vs 4× je teď i `cheap-even`, tedy
jediná strategie, která staví a bojuje — 7 focus / 499 dopamine / 28 killů na obou
rychlostech tam, kde dřív stálo 30 killů / 507 dopamine proti 39 / 543. Tím je zavřené
i `## Q1 — cross-speed combat divergence` v `BLOCKED.md`, otevřené od 30. 8.

A čísla při 1× se **nehnula ani o bit** — celá výsledková tabulka `docs/BALANCE.md`
(2 levely × 6 strategií × 3 seedy = 36 běhů) je před a po opravě bajtově shodná, takže
všechna měření z M1/M2/M3 zůstávají srovnatelná. Obava zapsaná v Q1b, že změna kadence
čísla rozhýbe, se nepotvrdila: sweep běží celý na 1×, kde je jeden tick na snímek.

## P8b — fog_bandwidth před P9
Model: opus
Needs-me: no
Status: todo

**Brána otevřena 2026-09-02 plná autorizací** (viz hlavičku souboru). Diagnóza níž
zůstává platná; rozhodnutí, na která čekala — přeškálovat balanc, přeautorovat layout
levelu, nebo otočit facing ve fixture — dělám sám. Sekvenčně to patří AŽ ZA M2/M3:
příčina je layout levelu a ten se v M2/M3 stejně mění, takže sahat na to dřív by
znamenalo opravovat něco, co se vzápětí přepíše.

`_test_fog_bandwidth` hlásí, že arc nemá vliv na osvětlenou plochu (36 → 36 buněk
při arc 15 → 120) a že otočení habitu světlem nehne. Podle P0e zjisti, jestli je
mrtvý parametr, nebo se osvětlení počítá jinak než z kužele.
Oprav to, ať už je příčina jakákoli. P9 staví na tomhle a nechci stavět na
systému, o kterém nevím, jestli funguje.

Hotovo když: test zelený, vyřazený z known-broken, a v PROGRESS.md je popsaná
příčina.

**DIAGNÓZA HOTOVÁ 2026-08-30, OPRAVA ZABLOKOVANÁ NA ROZHODNUTÍ.** Otázka „mrtvý
parametr, nebo se osvětlení počítá jinak" má odpověď: **ani jedno. Kód mlhy je
správně. Špatně jsou KONSTANTY — jsou naškálované pro desku, která už neexistuje.**

Zjišťováno pěti nezávislými agenty, každý pak dvakrát adversariálně ověřován
(refutace nad kódem + kontrola proti historii gitu). Čísla níž reprodukují oba
hlášené řetězce **na číslici** a shodly se na nich nezávisle.

**Mechanismus.** `26814f9` (T5) zmenšil desku z iso 24×24 @ tile 64 (1536×768 px)
na 30×14 @ tile 16 (**480×224 px**) — zhruba desetinásobek plochy pryč — a nahradil
`level_1` placeholderem. `git show 26814f9^:scripts/game.gd` ale ukazuje, že
`CORE_ROUTINE_RADIUS` 330, `ANCHOR_ROUTINE_RADIUS` 260, `TOWER_LAMP_RADIUS` 56,
`WEDGE_LIGHT_SCALE` 1.0, `LIGHT_SKIRT` 1.35 i `HabitData.range` 360 jsou před i po
**bajtově identické**. Na nové desce:

- `level_1` má objective `Vector2i(28, 7)` → jádro na `(456, 137)`, tedy u pravého
  okraje 480px široké desky. Jádro se značí PRVNÍ a jeho disk 330 px pokryje
  **35 z 50** bloků (`_lit_cells` je po 48px blocích a `world_to_cell` clampuje na
  desku, takže víc než 50 bloků neexistuje).
- `level_1` má jen **tři** build spoty — (10,4), (10,10), (19,7) — a všechny leží
  **na západ** od jádra, ve vzdálenosti 292 / 292 / 144 px, tedy všechny uvnitř 330.
  To je samo o sobě selhání č. 1 („empty spot outside the Routine"): je to obsah
  levelu, ne logika.
- Habit na (10,4) přidá svou 56px lampou přesně **1** blok → 35 + 1 = **36**.
- Test před oběma měřeními arcu nastaví `facing_angle = 0.0`, tedy kužel míří **na
  východ — přímo do disku jádra**. Všechny zbývající tmavé bloky mají `dx ≤ -48`,
  tedy leží ZA habitem. Maximální skirtovaný půlúhel je `120 × 0.5 × 1.35 = 81°`,
  což je **< 90°**, takže kužel mířící na východ na ně nedosáhne při ŽÁDNÉM
  nastavení dialu → **36 → 36**. Otočení o PI neztratí nic (jádro to drží dál) a
  získá přesně 7 → **−0, +7**.

**Oprava v KNOWN_BROKEN.md:** věta „the arc dial has no effect on lighting
whatsoever" je **nepravdivá, jak je napsaná**. Se stejným habitem otočeným na PI
tentýž test čte `38 → 50` — dial funguje. Jeho příspěvek je jen v testovaném směru
pohlcený sjednocením, na které fixture asserta (`_lit_cells.size()`).

**Co NEfunguje jako oprava (ověřeno simulací, ne odhadem).** Zmenšit
`CORE_ROUTINE_RADIUS` nestačí — `_find_spot` si spot vybírá znovu podle aktuálního
rádiusu, takže:

| CORE_ROUTINE_RADIUS | výsledek |
|---|---|
| 330 | in=(10,4), žádný out, −0/+7, 36→36 **FAIL** |
| 292 | in=(10,4), žádný out, −0/+7, 35→35 **FAIL** |
| 291 | in=(19,7), out=(10,4), −0/+19, 31→31 **FAIL** |
| 200 | in=(19,7), −0/+23, 23→23 **FAIL** |
| 144 | in=(19,7), −0/+23, 19→19 **FAIL** |
| 143 | žádný spot v Routine → habit se nepostaví, padá „a habit was built" |

Pod 292 je jediný spot v Routine (19,7) — 144 px přímo na západ od jádra — a jeho
východní bloky leží do 136 px od jádra, přičemž rádius musí být ≥ 144, aby se tam
vůbec dalo stavět. Disk jádra tedy kužel mířící na východ spolkne při **každém
přípustném rádiusu**. Ladění konstanty umí opravit jen selhání č. 1, nikdy č. 2 a 3.

**Skutečná vazba je LAYOUT LEVELU:** všechny tři build spoty jsou na západ od
objective na `x = 28` z 30 sloupců, takže na východ od jádra není kam kužel poslat.

**Širší nález, který přesahuje P8b:** stejný scale mismatch má `HabitData.range`
= **360 px na 480 px široké desce** — jedna věž pokrývá skoro celou mapu. Mlha ani
dostřel nebyly po T5 nikdy přeškálované. To se týká i P9/P10/P11 a balance obecně,
ne jen tohohle testu.

**Proč to nedokončím sám.** Každá reálná oprava spadá na jednu z tvých brzd
v CLAUDE.md: přeškálovat světla/dostřel je **balance obsahu**, přeautorovat
`level_1` jde **jen přes MapEditor** (vizuální práce), a otočit ve fixture facing
na PI je **úprava `_test_*`, aby prošel** — a ta výslovně potřebuje tvoje svolení.
Volby a jejich důsledky ti dávám v odpovědi; nehádám.

**DIAGNÓZA OVĚŘENA V ENGINU 2026-08-30. PŘEŠKÁLOVÁNÍ HOTOVO, ZBYTEK POŘÁD BLOKOVANÝ.**

Diagnóza výš vznikla čistě čtením kódu a nikdy neběžela. Teď běžela: jednorázový
harness (`_diag_p8b`, po měření smazaný) instancoval `Game.tscn` a vypsal skutečnost.
**Engine potvrdil každé číslo na číslici** — `objective_pos (456, 137)`, disk jádra
**35 z 50** bloků, tři build spoty ve vzdálenosti **292 / 292 / 144** px a všechny
uvnitř Routine, lampa habitu **+1** → **36**, arc 15→120 při facing 0 dá **36 → 36**,
otočení na PI dá **−0 / +7** a všech 14 tmavých bloků má `dx ≤ −336`, tedy leží na
západ. Nic z toho nebyl artefakt aritmetiky. (Diagnóza psala u tmavých bloků
`dx ≤ −48`; naměřeno je to `dx ≤ −336`, což její tvrzení splňuje s rezervou —
jediné číslo, kde byla konzervativnější, než musela být.)

Zároveň se potvrdilo, že **věta v `KNOWN_BROKEN.md` je nepravdivá, jak je napsaná**:
tentýž habit otočený na západ dává `arc 15 / 60 / 120 → 38 / 43 / 50` bloků. Dial
funguje. Fixture ho jen měří ve směru, kde ho disk jádra celý pohltí.

**Co se změnilo (přeškálování, schváleno uživatelem).** Faktor je **odvozený, ne
odhadnutý: přesně 0,5**, protože T5 zmenšil `GRID.tile` z 32 na 16 px a nechal
`BUILD_BLOCK` na 3 — jeden stavební blok tedy spadl z **96 px desky na 48 px**
(plocha bloku 9216 → 2304 px², tj. půlka v každém lineárním rozměru). Každý rádius
na téhle stránce znamená „dosáhne na N bloků", takže se každý dělí dvěma:

| konstanta | bylo | je | důsledek |
|---|---|---|---|
| `CORE_ROUTINE_RADIUS` | 330 | **165** | disk jádra **35 → 18** z 50 bloků (87 % → 45 % průměrem přes všechny možné pozice objective; před T5 to bylo 38 %) |
| `ANCHOR_ROUTINE_RADIUS` | 260 | **130** | poměr k jádru zůstal 0,79 |
| `TOWER_LAMP_RADIUS` | 56 | **28** | pod 48px roztečí bloků → svítí PŘESNĚ na vlastní blok, což komentář vždycky tvrdil; při 56 rozdával čtyři sousedy zdarma |
| `DEFENDER_LIGHT_RADIUS` | 90 | **45** | totéž |
| `PROJECTILE_LIGHT_RADIUS` | 26 | **13** | jen kosmetika |
| `HabitData.range` default | 360 | **180** | + všech 12 authorovaných `range` v `data/habits/` děleno dvěma |

`data/habits/anchor.tres` má `range` svázaný s `ANCHOR_ROUTINE_RADIUS` (support habit
kreslí Routine rádius jako range ring) — obojí je 130. Jeho anglický popisek
„Extends your Routine 260px" byl přepsaný na 130px, jinak by hráči lhal.

165 navíc **schválně není násobek 48**: rádius přesně na stavební mřížce položí celý
prstenec bloků na `vzdálenost == rádius`, kde o členství rozhoduje `<=` na
floatové shodě.

**Co to opravilo.** Selhání č. 1 („empty spot outside the Routine") je **zelené** —
(19,7) je ve 144 px uvnitř, (10,4) a (10,10) ve 292 px venku. Fixture spadl ze **3
selhání na 2**. Drží i `sight ⊇ fire`: kontrola „the firing edge is lit along its
whole length" prošla (0 z 6 sond ve tmě) i po zkrácení kužele, protože
`WEDGE_LIGHT_SCALE` 1,0 a `LIGHT_SKIRT` 1,35 jsou poměry, ne délky.

**Co to NEopravilo a proč — přepočítáno znovu, už s novým dosahem.** Diagnóza svou
tabulku počítala při `range` = 360; dosah se mezitím zmenšil, takže se závěr ověřoval
znovu. **Platí dál, a to pro každý přípustný rádius:**

| `CORE_ROUTINE_RADIUS` | spot, který `_find_spot` vybere | tmavé bloky NA VÝCHOD od něj |
|---|---|---|
| < 144 | žádný → habit se nepostaví | — |
| 144 … 291 | (19,7) | **žádné** (všechny leží v disku jádra) |
| ≥ 292 | (10,4) | **žádné** |

Jádro sedí na `x = 28` z 30 sloupců, všechny tři build spoty jsou na západ od něj a
fixture kužel míří na východ. Aby byl spot vůbec postavitelný, musí ho disk jádra
obsáhnout — a ten stejný disk pak nutně obsáhne i všechno, co je za spotem směrem
k jádru. Zmenšení dosahu to jen zhoršuje (kratší kužel = menší pokrytí), takže
**žádná hodnota konstanty selhání č. 2 a č. 3 nezezelení.** Vazba je layout levelu,
přesně jak diagnóza tvrdila.

**Co zbývá ROZHODNOUT (proto `Needs-me: yes`).** Dvě cesty, obě mimo to, co smím sám:
1. **Přeautorovat `level_1` v MapEditoru** tak, aby aspoň jeden build spot měl tmu na
   východ od sebe (např. posunout objective z `x = 28` doprostřed, nebo přidat spot
   na východním okraji). Ruční editace `.tres` levelu je v CLAUDE.md stop podmínka.
2. **Povolit změnu fixture** — otočit `facing_angle` na PI, nebo assertovat na
   symetrický rozdíl místo `_lit_cells.size()`. To je „úprava `_test_*`, aby prošel",
   která výslovně potřebuje tvoje svolení; nabídnuto ti to bylo a nevybral sis to.

**Širší nález ze sweepu, NEZMĚNĚNO — potřebuje vlastní rozhodnutí.** Stejný scale
mismatch po T5 nesou i tyhle, ale žádná z nich není „světlo ani dostřel", takže do
téhle autorizace nespadly:
- `Game.CUE_PULL_RADIUS` 220 — vzdálenost myši od `CUE_ORIGIN (46, 122)` na plátně
  480×270. Původně 220 z 1920 (11 % šířky), teď 46 % — „hnula se ruka?" je dnes
  splněné skoro vždycky. Měří to conditioning, ne desku; hýbalo by to `_test_attention`.
- `HabitData.guard_radius` 240 / 280 (`accountability*.tres`) — vodítko obránců je
  půl desky. Vůči dostřelu se poměr **obrátil**: bylo 240 vs 360 (0,67×), teď
  240 vs 180 (1,33×).
- `DefenderData` `move_speed` 85–100, `chase_speed` 170–240, `heal_radius` 84,
  `ward_radius` 96 a rychlosti distrakcí — pohyb přes celou desku za ~2 s.
- `Game.EXPOSED_DISRUPT_RADIUS` 110 (mechanika `sinking_walls` zatím není shipnutá)
  a `Game.CAM_PAN_SPEED` 900 px/s na desce, která se celá vejde do viewportu.

---

## P9 — brainfog jako vizuál
Model: sonnet
Needs-me: no
Status: done

Dva `SubViewport` sdílející stejný `World2D`, maska přes `ViewportTexture`.
Pokud se světla věží překrývají, zvaž shader s viditelnostní texturou místo
Light2D v mask módu — ten má při překryvu nepředvídatelné chování.

**Herní logika se NEMĚNÍ.** Zatím jen vizuál.

Hotovo když: screenshoty do `.dev/screenshots/` včetně rozostřené a odbarvené
varianty. **NEPOSUZUJ je** — vyberu sám.

**VYŘEŠENO 2026-08-30.** Polovina zadání už žila v `_light_viewport` /
`shaders/brain_fog.gdshader` (P0e-éra) — to UŽ JE „shader s viditelnostní
texturou místo Light2D v mask módu", schválně malý (240×135, jen aditivní
tvary světel, žádný terén/jednotky). Chybějící půlka — rozostřená a odbarvená
varianta — je nová: `shaders/brain_fog_preview.gdshader` (samostatný, do
`game.gd` NENAPOJENÝ soubor) + harness `scripts/_shot_p9_fog_variants.gd` /
`scenes/_shot_p9_fog_variants.tscn`, který ho na jeden snímek nasadí na
existující `_fog_rect` a vyfotí čtyři varianty.

**Druhý `SubViewport` sdílející celou scénu jsem NEPOSTAVIL — schválně.**
Zadání ho jmenuje jako výchozí techniku, ale duplicitní vykreslení CELÉ scény
(stovky `Distraction` uzlů) jen kvůli barevnému filtru by zdvojilo draw calls
za efekt, který `SCREEN_TEXTURE` (`hint_screen_texture`) dá zadarmo z rámce,
který se už kreslí — přesně tahle technika už v projektu existuje
(`shaders/flatten.gdshader`, Tolerance wash, ověřeno na stejném rendereru).
`brain_fog_preview.gdshader` tedy dělá box-blur + odbarvení (luminance drain,
stejná operace jako flatten) nad `SCREEN_TEXTURE`, ne nad druhým plným
renderem světa. Zdůvodnění i s odkazy na řádky v `PROGRESS.md`.

**Riziko `window/stretch/aspect` (souběžná session ho smazala z
`project.godot`) ověřeno empiricky, ne předpokladem:** stejný harness spuštěn
při 1920×1080 (odpovídá 16:9 desce) i při `--resolution 1000x1400` (silně
neshodující se poměr stran) — `get_viewport().get_texture()` vrátil v obou
případech bajtově identický 480×270 snímek. Vnitřní viewport se pod cizím
poměrem stran nezvětšil ani neodkryl víc světa, což je přesně chování, které
`aspect="keep"` garantuje (a které Godot 4 má jako vestavěný default i bez
explicitního řádku) — `"expand"` by tenhle test rozbil. Žádný desync masky a
světa nenalezen v žádném běhu.

Screenshoty: `.dev/screenshots/p9_fog_baseline.png` (shipped shader,
beze změny), `p9_fog_blur.png`, `p9_fog_desaturate.png`,
`p9_fog_blur_desaturate.png`, popis techniky v `.dev/screenshots/p9_notes.md`.
`_test_fog_bandwidth` beze změny (2 známá selhání, stejná jako před úkolem —
P8b, blokováno na uživateli). `./verify.sh` tally v `PROGRESS.md`.

## _test_shadow_occlusion — oprava testu
Model: sonnet
Needs-me: no
Status: done

Selhává, protože CORE_ROOTLINE_RADIUS se od napsání testu zmenšil. Regrese
v testu, ne v systému. Oprav referenční hodnoty, vyřaď z known-broken.

**Hotovo 2026-09-02.** Diagnóza v zadání seděla, ale byla to až druhá ze dvou
vad. První: `_sample()` škáloval readback konstantou `sz / 1920x1080`, zatímco
`project.godot` má 480×270 — každý vzorek se četl na čtvrtině zamýšlené pozice.
To zároveň **vyvrací** záznam „Defect 2" v `docs/KNOWN_BROKEN.md` („the lamp
adds nothing to the rendered image at all"): přeměřeno správným poměrem dává
jádrová lampa +0,1190 luma na r=10 a je nad prahem testu do r≈100. Druhá vada
je ta z pravého zadání: P8b zmenšil `CORE_ROUTINE_RADIUS` 330 → 165, mezikruží
hledání se stáhlo na (24, 132] a nejbližší zeď levelu je na 128 px — 0 kandidátů.
Rozšířit mezikruží nepomůže (za r≈100 lampa neměří nic), takže si test occluder
**staví sám**. Všechny tři původní assertions i prahy beze změny, přibyly dvě
preconditions; injektovaná chyba dokazuje, že PASS není prázdný. Odebráno
z `KNOWN_BROKEN_TESTS`, zůstává v `REQUIRES_DISPLAY_TESTS` (skutečný renderer
je trvalá potřeba, ne vada). `./verify.sh` s displejem: **41 pass, 0 fail,
3 known-broken, 0 no-display**. Detail v `PROGRESS.md` a `docs/KNOWN_BROKEN.md`.

## P10 — brainfog jako herní pravidlo
Model: opus
Needs-me: no
Status: todo

**Brána otevřena 2026-09-02 plná autorizací.** Původní brána zněla „nazačínej, dokud
si nezahraju P9 a nepotvrdím to" a byla o VIZUÁLNÍM úsudku, který si přisvojit nemůžu.
Řeším to tak, že pravidlo stavím za `LevelData.fog`, který už existuje a je `false` na
obou levelech: mechanismus vznikne a otestuje se, ale zapnout ho na konkrétním levelu
zůstane jeden bool v `.tres` — tvoje oko, ne moje.

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
Status: done

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

**Hotovo 2026-09-02**, commit `3e6a87e` (hash log `cba19a1`). Odehráno přes
`LevelSimulator` (S2), čtyři strategie × tři seedy, nic v `data/` změněno
nebylo. Hlavní zjištění, které zadání nečekalo: `LevelData.quick_hit` je
`false` v **obou** shipnutých levelech, takže „spam Quick Hitu" je dnes
bit-identický s „nic nedělat" (0 úspěšných použití ve všech 24 bězích).
Kompletní tabulka a návrh čísel: `BLOCKED.md` → `## Q2`.

## Q3 — capsule art specifikace
Model: sonnet
Needs-me: no
Status: todo

**Brána otevřena 2026-09-02 plná autorizací.** Úkol sám říká „NEGENERUJ přes PixelLab
... Art udělám nebo objednám já" — je to psaní specifikace, ne výroba artu, takže
autonomně proveditelné beze zbytku.

**NEGENERUJ přes PixelLab.** Steam capsule art je nejčastější terč „AI slop"
kritiky a první věc, kterou hráč na Steamu vidí. Doložené případy backlashe
existují i tam, kde bylo obvinění falešné.

Připrav specifikaci: rozměry všech Steam capsule formátů, co má obrázek
komunikovat, jaké prvky ze hry použít. Art udělám nebo objednám já.

## M9 — vyčistit known-broken dluh
Model: opus
Needs-me: no
Status: todo

Tři fixtures, každá jiná třída, žádná z nich už nečeká na povolení:
- `_test_deep_reading` — `head_aims = false` ve všech čtyřech `.tres`, test žádá `true`.
  Nejdřív zjisti, **která strana má pravdu** (proč se `head_aims` vypnul), teprve pak
  srovnej; změna assertion je teď povolená, ale ne jako první sáhnutí.
- `_test_fog_bandwidth` — P8b to diagnostikoval do detailu: vada je v **layoutu levelu**
  (všechny build spoty na západ od jádra), ne v kódu mlhy. Po M2/M3 může být vyřešená
  sama; ověř, než na to sáhneš.
- `_test_zen_pulsar` — chybí `assets/towers/head_zen_pulsar_frame_1..8.png`.
  **NEGENERUJ art.** Buď data ukážou na existující `head_zen_pulsar.png`, nebo se
  fixture srovná s realitou; rozhodnutí zapiš.

Hotovo: `KNOWN_BROKEN_TESTS` je prázdné, nebo každý zbylý záznam má v
`docs/KNOWN_BROKEN.md` důvod, který není „nikdo na to nesáhl".

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