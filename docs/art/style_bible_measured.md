# Stylová bible — TD Project

*Odvozeno měřením 734 shipped PNG, ne od stolu. Přeměř kdykoli:*
`python tools/style_audit.py`

---

## Pravidlo nula: rastr

Buňka je **48 bodů obrazovky** (`Data.GRID.tile`) a svět se kreslí na **×3**
(`Data.pixel_scale()`). Z toho plyne jediné číslo, ze kterého vychází všechno ostatní:

> **Jedna buňka = 16 pixelů artu.**

Každá strana každého spritu proto musí být buď **násobek 16** (celé buňky), nebo jeho
**čistý dělitel** (8 = půl buňky, u půlené dlaždice zdi). Číslo jako 24 nebo 40 nesedne
na mřížku ani jedním způsobem a vykreslí se jiným měřítkem než jeho okolí.

Nejde o estetiku, jde o to, že měřítko je jedno na celou obrazovku. Sprite s jinou
velikostí pixelu než země pod ním se čte jako nalepený na obrázku, ne jako součást
scény — a žádný stín ani záře to nespraví, protože neshoda je v samotném rastru.

Kontrola: `python tools/style_audit.py` (sekce 0).

## Pravidla

| | |
|---|---|
| **Rozlišení** | podlaha `background.png` **640×304** (16 px na buňku) · 16×16 dlaždice, dekorace, hlava věže, podstavec · 32×32 příšery, obránci, hlavy věží 2. stupně · 64×64 boss |
| **Logický pixel** | ×1 v PNG (žádné zdvojování); zvětšuje až engine, vždy ×3 |
| **Paleta** | `docs/art/palette_48.hex` — 48 barev, celý projekt |
| **Barev na sprite** | **cíl ~40, strop 56** — všechny z master palety (viz níž) |
| **Obrys** | 1px tmavší odstín **téže** barvy, ne černá. Postavy a věže ano, terén ne |
| **Stínování** | 3 tóny. Stín posunutý v odstínu ≥ 20° do chladna. Bez ditheringu. U objemných objektů (věže, rekvizity): odstupňované pásy podle formy + jeden směr světla shora, viz níž |
| **Počty snímků** | chůze 6 · útok 5 · smrt 8 · idle 2 |
| **Časování** | základ 10 FPS. Nárazový snímek držet 3×, nápřah 1× |
| **Proporce** | příšera 26–30 px vysoká ve 32px plátně · obránce 29 px · boss ≤ 1,8× |
| **Pozadí při generování** | magenta `#FF00FF` — v těle nesmí zůstat ani stopa |

---

## Proč zrovna tahle čísla

**48 barev.** Průměrná odchylka pixelu od master palety vypadá jako koleno na 32:

```
16 barev → 0.0507 Oklab
32 barev → 0.0369
48 barev → 0.0342
```

Ten průměr ale lže. Rozepsané po tvorech se ukázalo, že 32 barev **měřitelně ubližuje
šesti příšerám z deseti** — `clickbait` sedí ve vlastní paletě na 0,009 a v master paletě
na 0,050, tedy pětkrát hůř. Při 48 zbydou dva a při 64 taky dva, takže 48 je bod, kde se
přestává platit za věrnost. `jackpot` je na 48 dokonce **lepší** než se svou vlastní
šestnáctibarevnou — 16 barev na něj bylo málo.

**Kolik barev na jeden sprite — opraveno proti laťce.** Dřív tu stálo „≤ 24" a
`palette_budget()` počítal `12 + √plocha × 0,35`. Obojí byla úvaha, ne měření.
Přeměřeno na 1623 originálech z PixelLabu, tedy na laťce, kterou jsme si sami zvolili:

```
pásmo     ks    med. plocha   med. barev   p90 barev   starý rozpočet
32-47      39       234           44           52            17
48-79    1022      1414           38           53            25
80+       562      1776           45           56            26
```

Dvě věci z toho plynou. **Počet barev na laťce skoro nezávisí na velikosti spritu**
(38–45 napříč pásmy), takže odmocninová křivka neseděla na nic — správný tvar je
plochý. A starý rozpočet byl pod laťkou 1,5×; **88 % originálů z PixelLabu by jím
neprošlo**. Kontrola tedy netrestala šum, ale bohatost, a tím tlačila vlastní art
k plochosti — přesně k tomu, co na mapě vidíme jako mrtvo.

Nový strop je **56** (p90 laťky): kontrola má hlásit, co je neobvyklé i na laťce,
ne všechno barevné. Cíl generování je **40**.

Pod 120 pixelů artu laťka **mlčí** — v celých 1623 originálech není jediný sprite
pod 32 px. Číslo 24 pro dlaždice je proto vědomý odhad a je tak i označený.

**Neutrály se musí bránit.** Šedý pixel má chroma skoro nulovou, leží blízko středu
Oklabu a je odtud stejně daleko na všechny strany; když v paletě žádná šeď není,
rozhodne jas a pixel spadne na nejbližší **sytou** barvu z cizího tvora. Růžový
`clickbait` tak dostal na tělo tyrkysové flíčky. `sprite_cleanup.py` proto v režimu
`--master` váží barevné osy 2,5× (`CHROMA_WEIGHT`): přidat barvu neutrálnímu pixelu je
pak drahé a šeď hledá šeď.

**Obrys jako tmavší odstín, ne černá.** Postavy ho už mají a je silný — medián rozdílu
jasu vnitřek↔okraj je +0,23 (distrakce), +0,18 (obránci). Pravidlo jen zapisuje, co
ruka už dělá. Černá by ten posun odstínu, který je jinde přes celý art, na okraji zabila.

**Hue shift ≥ 20°.** Naměřeno: distrakce 58°, věže 86°, obránci 29°, dekorace 48°.
Práh je nízko schválně — je to podlaha, ne cíl.

**Tvar stínu je jiná osa než barva stínu — obě platí zároveň (19. 8. 2026).**
Hue shift výš říká, *jaký odstín* stín má. Neříká nic o tom, *podle jakého tvaru* se
stín rozkládá po objektu — a to je vada, kterou hue shift sám o sobě nezachytí: sprite
může mít správně vychladlý stín a přesto být plochý, protože ten stín je jen jedna
plošná skvrna na siluetě, ne odezva na skutečný tvar objektu.

Vzniklo z rozboru referenčního obrázku (mobilní TD, uživatelem schváleno přebrat **jen
sochařskost**, ne paletu ani styl): kuželovité věže tam čtou objem, protože jsou
odstupňované do pásů podle formy — základna, střední prstenec, koruna — každý pás
vlastní tón podle natočení ke světlu, jeden konzistentní zdroj světla shora (vršek
nejsvětlejší, boky tmavší, spodek skoro ve stínu), zaoblené/zkosené hrany místo pravých
úhlů, měkký kontaktní stín/AO u paty, drobný rim-light na osvětlené horní hraně.

Pravidlo pro každý objemný objekt (věže, velké rekvizity — ne ploché dlaždice terénu,
tam objem není co číst):

1. **Rozděl formu na nejmíň tři odstupněné pásy/fazety** (typicky základna → tělo →
   koruna), ne jednu siluetu s domalovanými detaily na povrchu.
2. **Jeden konzistentní směr světla, shora.** Horní plochy nejsvětlejší, boční tmavší,
   spodní téměř v stínu — a stejně přes celý objekt, ne po objektu paprskovitě.
3. **Zaoblené/zkosené hrany**, ne ostré pravoúhlé lomy.
4. **Kontaktní AO u paty**, ať forma opticky váží, ne jen leží na dlaždici.
5. **Rim-light** na horní hraně osvětlené strany — malý, ne plošný.

**Co si z reference NEBRAT** (uživatel to explicitně odmítl): teplou/jasnou paletu
trávy a hlíny, hladké malované přechody bez pixelové struktury (žádný anti-aliasing —
platí Pravidlo nula výš), karikaturní proporce. Mění se JEN tvarová řeč stínování, ne
téma ani paleta Deep Focus.

**Kde už to funguje: `assets/src/pixel/towers/tower_01_FOCUS_final.png`** (obelisk,
64×64, mimo `SHIPPED`). Naměřeno: horní třetina spritu medián jasu 95,7, spodní třetina
63,8 — konzistentní spád shora dolů (+32) přes stupňovitou základnu, dřík i korunu s
tyrkysovým jádrem. **Kde ne: `assets/towers/head_focus_timer.png`,
`head_mindfulness.png`** — obě jsou jedna zaoblená hmota (baňka / drahokam na soklu)
bez odstupňovaných pásů; u `head_focus_timer` navíc směr jasu jde **obráceně** (spodní
třetina 117,0 proti horní 50,9), protože baňka je zdroj světla, ne osvětlená plocha —
ukazuje to přesně ten rozdíl mezi „něco svítí" a „něco je sochařsky nasvícené".
Tahle dvě čísla (medián horní/spodní třetiny) jsou hrubý odhad, ne ověřená metrika jako
hue shift — matou je objekty, které samy září (glow), takže se nedají brát jako
automatický test bez ručního pohledu na kontaktní list.

**Počty snímků dolů.** Viz níže; je to největší jediná změna v celé bibli.

---

## Kde se art od bible dnes liší

### 1. Věže nesedí na rastr — jediná kategorie, která nesedí

```
24×24  55 souborů   ← mimo mřížku
40×40  10 souborů   ← mimo mřížku
32×32  19 souborů   ✓
```

Zbytek hry je na šestnáctce už dnes: dekorace 16, značky 16, dlaždice 16, příšery 32,
obránci 32, boss 64, podlaha 16 na buňku. **Věže jsou výjimka, ne pravidlo** — byly
kreslené pro ×2 svět, kde je buňka 24 pixelů artu, zatímco terén vznikal pro ×3.

Cíl: hlava a podstavec **16×16** (jedna buňka, na obrazovce 48 px — přesně jako dnes,
takže se velikost věže nezmění), hlavy vyšších stupňů **32×32** (dvě buňky, aby vylepšená
věž byla znát). Nedá se to dostat zmenšením 24 → 16, ten poměr je 2:3 a rozbil by kresbu.
Musí se vygenerovat nativně.

Do té doby kreslí podstavec i hlava na ×3, takže spolu aspoň souhlasí — věž jen přesahuje
svou buňku o 12 px na stranu. Až dorazí 16px art, obojí se srovná samo.

Věže jsou i jediná kategorie s rozkolísaným obrysem: 64 % tmavý, 27 % žádný, **8 % má
světlý lem** — to není styl, to je zbytek po zmenšování.

### 2. Terén je plochý a je to změřitelné

```
distrakce   58,3°  posun odstínu    hue shift u 85 % spritů
obránci     29,2°                            83 %
věže        86,4°                            96 %
terén        4,2°                            10 %   ← ztmavování do černé u 76 %
```

Tohle je **měřená odpověď na „mapa působí plochá"**. Postavy žijí v hue-shiftovaném
světě, terén pod nimi v šedém. Rozdíl není v rozlišení ani v detailu, je v tom, že
terén nemá barevný stín.

**Přeměřeno 18. 8. 2026** (684 shipped PNG, `python tools/style_audit.py`), po nedávné
— necommitnuté — úpravě kontaktních stínů zdí. Číslo drží: 4,2° / 10 % beze změny,
protože ho táhne dolů `path/` (28 z 38 souborů terénu), kterého se ta úprava netýkala:

```
terrain/path/*.png (28 souborů)      2,2–4,2°    podlaha, 100 % hracího času, nedotčeno
terrain/high_ground_atlas.png         8,7°        skutečný atlas zdí (jedno čtení přes 48 dlaždic)
terrain/face/*.png (3 soubory)       10,8–11,2°   přední stěna — právě upravena, zlepšeno, práh 15° ne
```

`face/` je dnes nejlepší kus terénu a přesně tam se sahalo naposledy — směr je
správný, jen nedotažený přes práh. `path/` je většina plochy podlahy a úpravy se
nedotkla, proto drží celkový průměr dole. Pořadí podle dopadu: **path (vidět pořád)
→ atlas (druhá největší plocha) → face (už rozjeto, jen dotáhnout).**

Pět souborů `assets/terrain/brain_*.png` a `high_ground_corner_atlas.png` audit
započítal (leží v `assets/terrain/`), ale hra je nikde nenačítá (bez odkazu
v `.gd`/`.tscn`/`.tres` — ověřeno grepem). `brain_floor_soft_pastel.png` vyšel na
1,5°, nejhorší číslo z celého projektu, a má nulový dopad. Patří do `assets/src/`,
ne do `SHIPPED`.

**Opraveno 19. 8. 2026 — `tools/terrain_cool_shadow.py`.** Rozbor palety ukázal PROČ
bylo číslo nízké: světlé i tmavé tóny `path/`, `face/` i atlasu leží skoro na
STEJNÉM odstínu (~257–290°, modro-fialová), liší se jen jasem L. Není to tedy jiný
materiál, co chybí — je to ROTACE. Oprava je čistý post-process (žádná nová generace
v PixelLabu, žádný zásah do dual-grid renderu): paleta každé skupiny (celé `path/`
dohromady, celé `face/` dohromady, atlas zvlášť) se převede do Oklabu a odstín
tmavších pixelů se pootočí směrem k fialové — `ROT_MAX * t^GAMMA` stupňů podle
relativní tmavosti pixelu v rámci vlastní skupiny (`t=0` nejsvětlejší, `t=1`
nejtmavší), s mírným posílením sytosti u nejtmavších tónů, aby rotace byla vůbec
vidět (zdrojová chroma stínů byla jen 0,02–0,06). **L (jas) se neměnil** — jde o
barvu stínu, ne o rozpočet jasu scény.

```
             pred        po        median sum(RGB) pred -> po
path/*.png    2,2–4,2°   17,3–43,0°     77–100 -> 88–111   (28 souboru, min. 23,7°)
face/*.png   10,8–11,2°  34,5–55,2°    124–145 -> 129–151   (3 soubory)
atlas         8,7°       46,1°         145 -> 151           (1 soubor, 81 barev)
```

Směr rotace (k vyšším stupňům, ne nižším) není libovolný: světlé tóny už ležely
kolem 257–265°, což je v Oklabu čistě modrá. Posun stínu STEJNÝM směrem by splynul
s barvou samotnou; posun k fialové (~290–320°) je přesně to, co PIXELLAB.md a tenhle
dokument popisují frází „shadow tones shift toward cool blue/violet" — světlo je
modré, stín je hlubší, fialovější modrá. Obojí zůstává v modro-fialové rodině (žádný
skok do červené/zelené), takže materiál se nezměnil, jen dostal směr. Ověřeno vizuálně
na kompozitu v herním měřítku (`build/terrain_cool_shadow/_field_compare.png`,
NEAREST ×2 pro podlahu / ×1 stretch do 48×24 pro čelo zdi — stejné volání jako
`game.gd::_build_path_layer` a `WallFace._draw`), ne na izolovaném náhledu.

Celková `terrain` skupina: medián hue shift 4,2° → **40,5°**, podíl nad 15° 10 % →
**94 %**, podíl ztmavování pod 8° 76 % → **2 %** (zbytek jsou nenačtené
`brain_*.png`, viz výš — netýká se hry). Obrys terénu zůstal beze změny (medián
+0,015, 92 % „žádný") — postup mění jen odstín, ne siluetu ani hranu, takže pravidlo
„terén bez obrysu" platí dál. `python tools/style_audit.py --only terrain --import`
a headless `--import` ověřeny bez chyby.

Sochařská forma (odstupňované pásy, kontaktní AO, rim-light) se na zdi cíleně
NEDOPLŇOVALA — atlas ji už měl (severní hrana = `RIM`, jižní = `SHADE 0,55`,
`build_wall_atlas.py`) a čelo zdi taky (`LIGHT_TOP/LIGHT_BOTTOM` rampa + `LIP_LEVEL`
v `build_wall_face.py`), navíc kontaktní stín u paty kreslí `WallShadow` v kódu, ne
textura. Jediná měřená vada byla barva stínu, ne jeho tvar — proto žádný zásah do
`build_wall_atlas.py`/`build_wall_face.py`/`game.gd`, jen barevná rotace nad hotovým
výstupem.

**Opraveno 19. 8. 2026 (pokračování) — raster: `path/` a atlas neseděly na kanonickou
buňku.** Barva stínu (výš) byla hotová, ale samotný rastr terénu ne — hra od zjemnění
mřížky 18. 8. běží na `Data.GRID.tile = 16`, `TERRAIN_ART_PX = 16`, tedy měřítko **×1**
(jeden art pixel = jeden pixel obrazovky). Dva soubory na disku tomu neodpovídaly:

```
terrain/path/path_00–27.png   byly 24×24   (art z období, kdy TERRAIN_ART_PX bylo 24)
terrain/high_ground_atlas.png byl 192×576  (4×4 sloty po 48 px, 3 varianty — stará
                                             buňka 48 z doby PŘED zjemněním mřížky)
```

**`path/`** se za běhu tiše zmenšovalo v `game.gd::_build_path_layer`
(`img.resize(tile, tile, Image.INTERPOLATE_NEAREST)`, `tile = 16`) — NEAREST na poměr
24→16 (2:3, ne celé číslo) vybírá skoro nahodilý zdrojový pixel na cíl, takže se
kresba tkáně měnila v šum při každém načtení levelu. Opraveno přegenerováním zdrojových
PNG na nativních **16×16** (`Image.BOX`, ne NEAREST — správný filtr pro nedělitelný
poměr, viz `sprite_16.halve()` — tady šlo o plošný materiál, ne o siluetu s jedním
akcentem, takže `halve()` sám nešel použít, ale stejný princip „BOX, ne NEAREST" ano).
Změřeno (`tools/style_audit.hue_shift`, lokální kontrast = průměrný rozdíl sousedních
pixelů, proxy za šum):

```
lokální kontrast (šum)   7,26 (runtime NEAREST 24→16)  →  5,72 (BOX, na disku)   -21 %
hue shift (28 souborů)   průměr 36,0°  →  33,1°   (barevná rotace ze stínového postupu
                                                     výš přežila resize, práh 15° drží)
medián sum(RGB)          92,1 → 92,6   (rozpočet jasu beze změny)
```

**Atlas** měl vážnější vadu než šum — byl to aktivní vizuální bug. `_build_corner_terrain`
čte `texture_region_size = Vector2i(tile, tile)` = **16×16**, ale soubor na disku měl
sloty **48×48** (změřeno: největší jednolitý blok v každém slotu je 3×3 stejných pixelů,
tedy skutečný obsah je nativně 16 art px, jen 3× zvětšený z doby staré buňky 48).
Hra tak z každé 48px dlaždice četla jen **levý horní roh 16×16** — ne celou kresbu.
Simulace přesně té indexace (stejný vzorec jako `game.gd`, na testovací mapě z
`tools/tiles.py`) to potvrdila vizuálně: zdi se vůbec nenapojovaly, mapa byla
rozsypaná na útržky místo místnosti a chodby. Oprava: atlas přebalen z 48px slotů na
nativní **16px sloty** (`64×192`, pořád 3 varianty) čistým ÷3 NEAREST — bezztrátově,
protože obsah byl už doopravdy jen 3× zvětšená 16px kresba, žádná nová generace.
Kompozit před/po (`tools/tiles.py`-stylová testovací mapa, skutečná herní indexace
atlasu) je v `build/terrain_raster_fix/` sesterské session; verdikt: OLD = nesouvislé
útržky, NEW = správně napojená místnost i chodba.

**`face/*.png` (16×24) se NEMĚNILY** — `WallFace._draw()` v `game.gd` kreslí texturu
přímo do obdélníku `Rect2(…, tile, WALL_FACE_H)` = **16×24 obrazovkových px beze
škálování** (`WALL_FACE_H = 24` je záměrná konstanta poloviny staré 48px buňky, nezávislá
na `TERRAIN_ART_PX`, viz komentář u `WALL_FACE_H` v `game.gd`). Soubor na disku už přesně
16×24 je, takže `draw_texture_rect` je 1:1 kopie, ne škálování — `refit_wall_face.py`
tohle vyřešil dřív a nebylo co opravovat.

**Vedlejší nález, NEOPRAVENO (mimo doménu — je to kreslicí/editorní kód, ne obsah
textury):** `tools/stylized_renderer.gd` (živý náhled v editoru levelů) má natvrdo
`const CELL := 48` a `tools/scale_pixel_atlas.gd` natvrdo `const TARGET := 192`
(komentář tvrdí „4 tiles x Data.GRID.tile", ale 4×16 = 64, ne 192) — oba jsou pozůstatek
staré buňky 48 a **nečtou `Data.GRID.tile`/`game_raster.py` jako zdroj pravdy**, na rozdíl
od `tools/tiles.py`. Právě proto starý 192×576 atlas v editorovém náhledu vypadal
v pořádku (náhled si sám dopočítal krok 48 px, který sedl na starý soubor), zatímco
skutečná hra (`game.gd`, pevných 16 px) kreslila rozbité útržky — desynchronizace mezi
editorem a hrou, kterou žádný dosavadní kontrolní obrázek nemohl odhalit. Patří to
`render-fx`/engine agentovi, ne sem — nepřebarvoval jsem to.

Ověřeno: `python tools/style_audit.py --only terrain` (jediné soubory mimo násobek
16 px jsou teď `face/*.png` s uznanou výjimkou výš), `godot --headless --import` bez
chyby. Zálohy: `assets/terrain/high_ground_atlas.png.bak(2)`,
`build/terrain_raster_fix/path_24px_pre_fix/` (28 originálů 24×24).

### 3. Palety jsou nad rozpočtem a nesdílené

Medián barev na sprite: distrakce 34, obránci 30, věže 21, dekorace 6.
Cíl je 24. Hlavní problém ale není počet — je to, že **žádná společná paleta neexistuje**;
každý tvor si přivezl vlastní.

### 4. Animace: moc snímků, nulové časování

```
útok    16 snímků  ×5 tvorů      (shipped hry: 3–6)
smrt    11 snímků  ×10
chůze    8–9 snímků             (shipped hry: 4–6)
obránci  6 snímků  ×18           ← tady je to správně
```

`data/anim_tuning.tres` **nemá jediné FPS** → všechno běží na výchozích 12 a každý
snímek drží stejně dlouho.

Dvojnásobný počet snímků oproti běžné praxi a k tomu ploché časování je nejhorší možná
kombinace. A u AI artu to bolí dvakrát: **každý snímek navíc je další příležitost, aby
model ujel.** Šestnáctisnímkový útok má šestnáct šancí na drift, pětisnímkový pět.

Zkrácení tedy není ústupek. Je to zároveň bližší tomu, co dělají vydané hry, **a** přímá
oprava toho, proč animace z generátoru působí rozsypaně.

### 5. Drobnost

`assets/distractions/phantom_buzz_spritesheet.png` je 1024×1024 zdrojový list ležící
mezi shipped sprity. Patří do `assets/src/`.

### 6. Věže: silný průměr, dvě konkrétní hlavy ne

Kategorie má medián 85,3° a 89 % nad prahem — nejlepší číslo v projektu vedle nového
landmark obelisku (171,7°, mimo `SHIPPED`, zatím nenapojený na `HabitData`). Průměr
ale kryje dvě celé animované rodiny, které se prahu skoro nikdy nedotknou:
`head_mindfulness*.png` (9 souborů, 6,7–30,0°) a `head_focus_timer_frame_{4,5,7,8}.png`
(6,2–10,7°). Obě věže patří mezi levné základní habity — staví se často a hlava běží
ve smyčce celý zápas, takže tohle není jeden snímek z devíti, co blikne a zmizí, je to
tón, který hráč vidí většinu hry.

Stejné dvě věže jsou zároveň nejlepší dostupný „před" příklad pro **pravidlo sochařské
formy** výš (§2, „Tvar stínu je jiná osa"): obě jsou jedna zaoblená hmota bez
odstupňovaných pásů, zatímco `tower_01_FOCUS_final.png` (obelisk) formu má. Nepřegenerovat
teď — jen zapsáno jako kandidát, až se na věže znovu sáhne.

---

## Co bible **není**

Neříká, kolik místa sprite zabere. To plyne z rastru samo: velikost na obrazovce je
vždy `strana × 3`, takže 16px art je jedna buňka, 32px dvě, 64px čtyři. Kdo chce věc
na obrazovce větší, kreslí větší art — měřítkem se to nedělá, to je pro celý svět jedno.

Měření posunu odstínu neumí odlišit **hue-shiftované stínování** od **pestrého spritu**.
Zelený obránce s červenou přilbou vykáže velký posun, i kdyby stínoval do černé. Čísla
výše proto berte jako podlahu, ne jako důkaz techniky.
