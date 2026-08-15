# Tvorba map — nativně v Godotu, se živým náhledem

Levely se malují **vestavěným editorem dlaždic**. Žádné vlastní režimy, žádné palety,
žádná klávesa, kterou by sis musel pamatovat. Vlevo maluješ abstraktní plán v sytých
legendových barvách, vpravo je **připnutý panel „Náhled hry"**, který při každém tahu
překreslí level přesně tak, jak ho vykreslí hra — rohový terén s variantami, cesty,
rekvizity, brány spawnů i jádro. **Kamera náhledu kopíruje tvůj levý pohled**: kam se
posuneš a přiblížíš, to vidíš vpravo herní grafikou.

(Stejný postup, jaký ukazoval samsfacee na r/godot: abstraktní dlaždice + tool skript,
který poslouchá změny a staví hezkou verzi + SubViewport s vlastní kamerou jako split.)

## Postup

1. **Otevři `scenes/MapEditor.tscn`** (v docku TD Designer je na to tlačítko) a dej
   **Load** — level se nasype na plátno.
2. **Zdi:** vyber ve stromu uzel **HighGroundTiles**, dole se otevře editor dlaždic,
   vyber fialovou dlaždici a maluj. Štětec, obdélník, kbelík, guma — všechno Godotí,
   včetně **Ctrl+Z**.
3. **Cesty:** vyber **PathTiles**, maluj růžovou. Nepřátelé pruh preferují; vlastní
   texturu dostane až ve hře a v náhledu.
4. **Spawny:** tlačítko **Add Zone** v docku, pak obdélník přesuň/natáhni nástrojem
   výběru. Smazání = smazat uzel (Delete).
5. **Cíl:** přesuň uzel **Objective**.
6. **Rekvizity:** pod uzlem **Props** duplikuj libovolný sprite (**Ctrl+D**), přesuň ho,
   v Inspectoru případně `flip_h`. Nový druh = nový Sprite2D s texturou z `assets/decor/`.
7. **Analyze → Bake → Playtest** v docku. **Bake zapíše všechno** — zdi, cesty,
   rekvizity, zóny i cíl — do `.tres` (předtím záloha `.bak` + `.bak2`).

## Panel „Náhled hry" (pravá strana)

- Kreslí ho `tools/stylized_renderer.gd`; panel připíná plugin k pravému okraji 2D
  pohledu. Není třeba nic mačkat — překresluje se sám při každé změně plátna a jeho
  kamera kopíruje levý pohled (pan i zoom).
- Tlačítka: **Půlka** přepíná šířku, **Sbalit** ho schová, **⟳** znovu načte grafiku —
  to zmáčkni po `tools/tiles.py instaluj …` (plus `Project → Reload Current Project`,
  ať si Godot všimne nových PNG).
- Losování variant dlaždic a cest používá **stejné seedy jako hra**, takže co vidíš
  vpravo, uvidíš i v playtestu, do posledního pixelu.

## Overlay na levé straně

Analytické vrstvy přes abstraktní plán: modrý rámeček = hranice hřiště, zelené kruhy =
dosah Routine (jádro / Anchor), oranžový nádech = traffic heatmapa, panel s metrikami
a legenda. Vypínají se v Inspectoru MapEditoru (`show_overlays`, `show_traffic`,
`show_legend`).

## ⚠ Pojistka proti přepsání mapy

Bake nahrazuje geometrii celou. Když je na plátně výrazně míň buněk, než level už má
(pod čtvrtinu), **Bake odmítne** a řekne, ať dáš nejdřív Load. Bez toho stačilo otevřít
editor s prázdným plátnem a jeden Bake smazal celou mapu — což se levelu 1 jednou stalo.

## Kde se bere grafika

Terén a cesty: **[TILESETY.md](TILESETY.md)** (PixelLab v Aseprite → `tools/tiles.py`).
Rekvizity: PNG 16×16 v `assets/decor/`. Značky spawnů a cíle: `assets/markers/`.

## Zbytek workflow

**Analyze** měří detour, build spoty v dosahu Routine a délky cest proti cílům návrhu;
**Save Settings** zapisuje vlny/ekonomiku bez geometrie; **New Level** kopíruje level do
dalšího volného `level_N.tres`. Campaign záložka v docku ukazuje přehled všech levelů.
