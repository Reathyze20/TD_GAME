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
Status: todo

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

## P5 — vykreslování hordy přes MultiMeshInstance2D
Model: sonnet
Needs-me: no
Status: todo

Nahraď jeden-uzel-na-nepřítele jedním `MultiMeshInstance2D` na hordu.

Hotovo když: bench N=500 je **aspoň 3× rychlejší** než baseline z T11.

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
Status: todo

Rychlosti **0.25× / 1× / 2× / 4×**, pauza s možností zadávat příkazy během ní,
skip to next wave, plné staty habitu i distrakce na hover.

Není to jen QoL. Podle researche je to stížnost číslo jedna a hráči čtou absenci
speed-upu cynicky. Navíc bez rychlostí se mizerně playtestuje a testovat budeš
potřebovat dřív, než dojdeš na konec fronty.

Hotovo když: `_test_timecontrol` ověří, že deterministický simulátor při 4×
dá **bit-identický** výsledek jako při 1×. Determinismus se nesmí rozbít rychlostí.

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