# Iso Art Bible — „Deep Focus: Cortex Terrace"

> Platí pro isometrickou desku (`Data.GRID` = 64×32, diamond-down). Nahrazuje
> art směr z `project-art-direction-mapa` **jen pro iso** — top-down levely 1/2 na něj
> nesahají. Recepty do generátoru žijí v `tools/pl_iso.py` (`RECIPES`), aby se nedaly
> ztratit přepsáním chatu; tenhle soubor je *proč*, ten skript je *co*.

## 1. Věta, ze které všechno plyne

**Soustředění je tma a ticho. Distrakce je světlo a hluk. A návyk je něco, co si
nad tím chaosem *postavíš*.**

První dvě věty projekt už měl. Třetí je nová a je to celá iso art direction:
isometrie umí ukázat výšku, tak ať výška něco znamená. Nízká zem je živá tkáň —
tmavá, vlhká, nepostavitelná, tudy se valí distrakce. Vysoká zem je **stavba**:
světlá keramická terasa, kterou tam někdo záměrně vyzdvihl. Návyk = architektura
nad tkání.

To není jen metafora. Je to **herní informace zdarma**: hráč nepotřebuje overlay
„Build only on high ground", protože světlé plochy jsou postavitelné a tmavé ne.

### 1b. Čím ty vrstvy JSOU (a proč zrovna tím)

Hodnotová hierarchie sama o sobě je jen jas. Musí mít i **látku**, jinak vyjde
obecný dungeon, který by mohl být z jakékoli hry. Látka se bere ze skutečné
neuroanatomie, protože ta tuhle hru popisuje doslova:

| vrstva | co to je | proč to sedí |
|---|---|---|
| nízká zem | **šedá hmota** — vlhká, tmavá, zbrázděná | tady se myslí a tady je chaos |
| pruh | **dopaminová dráha** vypálená do tkáně | teplá zlatá `ffd479` je přímo barva Dopaminu v HUDu (`game.gd:4743`) |
| vysoká zem | **myelin / bílá hmota** — bledý voskový svazek vláken | myelinizovaná dráha = **návyk**. Myelin je bledý a dělá signál rychlým a automatickým. To není přirovnání, to je ta hra. |
| věže | **struktury vyrostlé z myelinu**, bioluminiscenční akcent | návyk není stroj postavený na tkáni, je to tkáň, která se přerostla |
| jádro FOCUS | jediné klidné teplé světlo | to, co se brání |

**Past, na kterou tohle kolo šláplo:** první terasa (`terrace2`) měla jas přesně
v pásmu (medián 400 proti cíli 380–450) a přesto byla špatně — bylo to **kamenné
zdivo**. Hodnota se dá změřit, téma ne, a měřitelná věc svede pozornost. Platí
`feedback-organicky-tvar-nad-doslovnosti`: posuzuj art podle tématu hry, ne podle
toho, jestli prošel metrikou.

## 2. Hodnotová hierarchie (tohle je ta vymahatelná část)

Měří se součtem RGB, stejnou metrikou jako top-down deska.

| Vrstva | součet RGB | odstín | role |
|---|---|---|---|
| prázdno za deskou | ~20 | studená čerň | rám, oko sem nechodí |
| **tkáň** (nízká zem) | **60–110** | tmavá indigo/violet | největší plocha, musí být TICHÁ |
| **pruh** (cesta distrakcí) | **120–160** | matná jantarová bronz | jediná teplá věc na zemi |
| **vrch terasy** (stavitelné) | **380–450** | bledá kost/keramika | „sem se dá stavět" |
| zeď terasy — osvětlená | ~280 (70 % vrchu) | táž keramika | drží výšku |
| zeď terasy — stín | ~180 (45 % vrchu) | táž keramika, studenější | drží výšku |
| synapse akcent | 300+ | cyan / zlatá | ≤ 6 % plochy, **ve shlucích** |
| **jádro FOCUS** | nejvyšší v obraze | teplá zlatobílá | jediné klidné světlo |

Poměr vrch : světlá stěna : stínová stěna = **100 : 70 : 45** není vkus, ale
jediný důsledný zdroj světla shora. První verze téhle tabulky měla stěny na 150/70
proti vrchu 400 — to je stěna tmavší, než jaké světlo dopadá, a terasa by čtla jako
plovoucí deska bez boků.

Dvě pravidla, která už tenhle projekt jednou stála kolo práce:

1. **Akcent se shlukuje, nerozsypává.** 6 % v pramíncích je klidnější než 10 %
   rovnoměrně (viz `ACCENT_SHARE` / `ACCENT_STRAND` v `game.gd`). Rovnoměrné losování
   z jednoho poolu je konfetový posyp při *jakémkoli* podílu.
2. **Podlaha nesmí přebít terén.** Kdyby byl akcent tkáně světlejší než hrana zdi,
   deska se rozpadne na šum — přesně to, co dnes iso deska dělá.

## 2b. PLOCHÝ STYL — zavedeno 21. 8. 2026

Terén nemá texturu. Ploché barvy, výška se čte **jen** z poměru vrch : levý bok :
pravý bok. Referencí je Rogue Tower; rozhodl o tom uživatel
(viz `docs/design/fae_theme.md`, a proč PixelLab tuhle třídu artu nezvládá).

**Důvod je měřitelný, ne vkusový.** Hlučný povrch se při dláždění 3×3 rozpadne na mřížku
opakovaných hrbolů — změřeno na generovaných blocích: rozptyl jasu na vrchu 227 a 142
proti 32 u ručního artu, a čtly jako vaflový plát. **Plochá plocha ten problém nemá
z definice: není co opakovat.**

Nainstalované hodnoty (`tools/flat_terrain.py`):

| plocha | součet RGB | pásmo z kap. 2 |
|---|---|---|
| zem | 74 | 60–110 ✔ |
| zem, akcentová varianta | 99 | 60–110 ✔ |
| pruh | 146 | 120–160 ✔ |
| vrch terasy | 484 | 380–450 — nad pásmem, ale je to nejsvětlejší plocha ve hře |
| terasa celkem | **100 : 70 : 45**, světlo zleva | přesně |

**Jak to nástroj dělá bezpečně:** u každého souboru **zachová přesnou alfu** a přebarví
jen RGB. Silueta se nemůže změnit ani o pixel, takže nemůžou vzniknout spáry ani posuny
proti mřížce — což je jediný způsob, jak měnit terén bez rizika opakování historie
`TERRAIN_ART_PX`. Záloha je v `build/_flat_backup/`, návrat `--restore`.

**Jedna vědomá ztráta:** maskované dlaždice pruhu (16 variant podle sousedů) přestaly být
vidět — všechny jsou týž jantar. Ta informace byla nesena texturou; teď ji nese tvar
souvislé plochy, takže pruh čte jako **jedna cesta** místo jako sada dílků. Kód se
nezměnil, masky se pořád vybírají, jen na nich nezáleží.

### Ploché je jen POZADÍ. Herci zůstávají detailní.

Rozhodnuto uživatelem 21. 8. 2026: *„nepřátele chceme zanechat detailní, aby hráč
rozeznal vzhledem, o jakého nepřítele jde. To chceme právě zkombit."*

To není kompromis mezi dvěma styly, je to **důvod, proč plochý terén funguje**. Hluk je
rozpočet a má se utratit tam, kde nese informaci. Terén nese jedinou informaci — *kde se
dá stavět a kudy se chodí* — a tu unesou tři ploché tóny. Který nepřítel to je, unese
jen silueta a barva. Tichá zem znamená, že detail na nepříteli je konečně vidět.

**Pravidlo:** čím kratší dobu je věc na obrazovce a čím rychleji o ní hráč musí
rozhodnout, tím víc detailu si zaslouží. Terén je tam pořád → nejmíň. Nepřítel má tři
vteřiny, než dojde k jádru → nejvíc.

**Změřený stav 21. 8. 2026** (10 z 13 distrakcí má sprite):

| | rozsah | čte se? |
|---|---|---|
| odstín | 28°–315° | ✔ zlatá, purpurová, azurová, fialová — vzájemně rozlišitelné |
| sytost | 0,08–0,94 | ✔ |
| plocha siluety | 661–5218 px | ✔ |
| jas | 44–680 | 9 z 10 nad pásmem pruhu (146) |

**Dvě vady, které z toho měření vypadly:**

1. **`comparison`, `fomo` a `just_one_more` nemají sprite vůbec** a kreslí se vektorem.
   Právě u nich na rozeznatelnosti záleží nejvíc: Wisp, The Dance a The Fetch jsou tři
   nejsilnější figury v `docs/design/fae_theme.md` §6.
2. **`adult_content` má jas 44, tedy TMAVŠÍ než zem (74).** Splývá s podlahou, po které
   chodí, a sytost 0,08 znamená skoro šedou. Zvednutí země z 51 na 74 (viz tabulka výše)
   tu vadu zhoršilo — dřív byl o 7 nad zemí, teď je o 30 pod ní.

Kontaktní list v herním měřítku: `build/_enemies_on_flat.png`.

### 2c. Věže: tmavé tělo, svítící akcent — zavedeno 21. 8. 2026

Plochá deska tuhle vadu konečně **zviditelnila i změřila**: 7 z 8 hlav leželo do ±60 jasu
od terasy, na které stojí (482–611 proti 484). Čtyři kostěné se do ní ztrácely; čtyři
azurové přežívaly **jen odstínem** — a to je křehké, protože Tolerance barvy vysává
(`shaders/flatten.gdshader`), takže právě když je hráč v úzkých, zmizely by i ty.

`tools/tower_band.py` dělí sprite podle **sytosti**: kostěné tělo pod 0,25, akcenty nad
0,45. Tělo se vynásobí na cíl **300**, akcent si jas nechá. Bible to předepisovala od
začátku (kap. 1b, *„útvary vyrostlé z tkáně s jedním bioluminiscenčním akcentem"*) —
splývalo TĚLO, ne akcent.

Podíl pixelů do ±60 od terasy, před → po:

| hlava | před | po |
|---|---|---|
| exercise | 31,5 % | **11,0 %** |
| focus_pillar | 22,9 % | **5,8 %** |
| real_hobby | 20,5 % | **6,6 %** |
| anchor | 27,5 % | 17,2 % |
| accountability | 30,1 % | 21,9 % |
| focus_timer | 24,3 % | 14,6 % |
| mindfulness | 8,8 % | 2,1 % |
| zen_pulsar | 29,6 % | 27,8 % |

`zen_pulsar` se skoro nezlepšil — je z velké části sytě azurový, takže mu většina plochy
padla do „akcentu" a jas si nechala. Není to vada nástroje, je to vada zadání toho
spritu: **akcent má být menšina plochy, ne většina.**

První verze násobila všechno včetně akcentů. Číslem to bylo správně a vypadalo to šedivě
— zlaté vejce zhnědlo, krystaly zmatněly. Poučení: **ztlumit se má to, co splývá, ne
celý sprite.**

Záloha `build/_tower_backup/`, návrat `--restore`.

**Co plochý styl NEDOŘEŠIL a je to vidět:**
- **Dekorace a spawn rift zůstaly texturované** a teď jako jediné trčí.
- ~~Hrana je po buňce~~ — **VYŘEŠENO tentýž den.** První verze kreslila tmavou linku po
  každé buňce *včetně terasy* a uživatel to poznal okamžitě. Na terase je to vada: masiv
  se rozpadne na dlážděnou podlahu a souvislá stěna na svislé panely, takže přestane
  číst jako **těleso** — a to je jediná informace, kterou terasa nese. Stavební bloky
  3×3 navíc už značí tečky v `_draw_static_field()`, takže tu informaci linka nenesla
  ani náhodou.

  Na **podlaze** jsem ji nechal s odůvodněním „dá měřítko vzdálenosti". Uživatel ji o kolo
  později nahlásil znovu a měl pravdu podruhé: **čte to jako MEZERY mezi dlaždicemi**, ne
  jako mřížka. Vysvětlení je v geometrii — alfa dlaždice není čisté 2:1 (řádky rostou po
  6 px místo po 4), takže se sousedé **překrývají**. Změřeno na skutečném dláždění:
  **0 děr, 2720 překrývajících se pixelů.** Tmavý lem jedné dlaždice tím pádem leží na
  vnitřku sousední a vznikne tmavá mříž.

  Skutečné mezery to nejsou a nikdy nebyly. Výchozí je proto `--edge none`.

  Zároveň se ztlumily akcentové dlaždice země (99 → 82, `--accent`): na hladké podlaze
  dělal ten rozdíl viditelné schody mezi světlejšími a tmavšími ostrovy.

  Obecné poučení: **mřížka JE textura.** Linka po dlaždici je běžná technika, ale bojuje
  přesně s tím, proč je terén plochý — a na překrývajících se dlaždicích navíc lže.
- **Věže a nepřátelé mají pořád starý detailní styl** — ti se podle
  `docs/design/fae_theme.md` §7 generují znovu a je to další kolo.

## 2d. Co stojí na terase, musí se DOTÝKAT terasy

*Zavedeno 22. 8. 2026, když věže viditelně visely ve vzduchu.*

Sprite se kotví **spodkem plátna**, ale stojí **spodkem obsahu**. Mezi nimi bývá pár
prázdných řádků a přesně o ně se věc vznáší. Naměřeno na `build/_aim_board.png`,
sloupec x=352: sprite končil na y=266, terasa svítila plných 484 až do y=272 a stín
začínal teprve na y=273. **Šest řádků holé země mezi věží a jejím stínem.**

Nebyla to vada jedné věže — prázdný okraj má každá hlava v rejstříku, od 5 řádků
(`real_hobby`) po 12 (`accountability`). Proto se to měří v kódu a ne ořezává v artu:
`Habit._measure_foot_pad()` spočítá okraj při načtení a `_draw_head_sprite()` o něj
sprite posune. Bere se **minimum přes všech osm směrů**, ne každý zvlášť — jinak by
rajče při otáčení poskakovalo nahoru a dolů, protože hlaveň v některých směrech klesá níž.

Druhá polovina té mezery byl stín: kreslil se 6,7 px **přímo pod** bod dotyku. Světlo
jde zleva shora (kap. 2), takže posun patří dolů-**doprava** a má být malý. Teď je to
`base_r * (0,16 ; 0,10)`.

**Pravidlo:** když se cokoli nového postaví na terasu, změř sloupec pixelů pod tím.
Mezi spodkem objektu a začátkem jeho stínu nesmí být ani jeden řádek čisté terasy.

## 2e. Snímky z harnessů dělej v 1920×1080, jinak výřezy míjejí

*Zapsáno 22. 8. 2026, po několika výřezech, které ukazovaly prázdnou zem.*

Projekt renderuje v **1920×1080** se `stretch/mode="canvas_items"` (`project.godot`).
Když se harness pustí v menším okně, Godot celé plátno **zmenší**: při `--resolution
900x300` vyjde snímek 533×300, tedy měřítko 0,278. Souřadnice uzlů zůstávají v základním
prostoru, pixely snímku ne — takže výřez podle `global_position` sáhne úplně jinam.

Poznat se to dá jedním číslem: `vyska_snimku / 1080`. Když to není 1, výřezy se musí
násobit, nebo — lépe — **pusť harness v 1920×1080** a měřítko je 1.

Tohle stálo dnes tři špatné závěry po sobě: nejdřív jsem hledal chybu v `get_canvas_
transform()`, pak v `get_global_transform_with_canvas()`, a ani jedna tam nebyla.

## 3. Co bylo na desce špatně — VYŘEŠENO 21. 8. 2026

Zápis zůstává, protože to jsou přesně ty vady, na které se má dívat příští kolo.
Výchozí snímek `iso_slice_test.png`, výsledek `build/iso_board.png`.

- **Podlaha je hlučná modrá tapeta.** Ta „circuit board" dlaždice je akcent
  povýšený na základ. Přesný opak bodu 1 — deska nemá kde odpočinout.
- **Vrch terasy kreslí `floor_tile.png`, tedy tutéž texturu jako zem**
  (`game.gd:463`). Vysoká a nízká zem jsou nerozeznatelné, takže hru musí
  zachraňovat červený nápis „Build only on high ground". Textem se neopravuje
  to, co má říct obraz.
- **Pruh se nekreslí vůbec.** `_build_path_layer()` (`game.gd:934`) natírá
  *všechny* buňky týmiž třemi variantami; `level.path_cells` se nikdy nepoužije.
  Hráč nevidí, kudy nepřítel půjde — to je ta nejdražší chybějící informace na desce.
- **Zdi jsou černé pruhy.** Materiál je tak tmavý, že rozdíl `shade` 1.0 / 0.72
  nemá co odstínit, a svislá kresba čte jako díra, ne jako stěna.

Ukázalo se, že **tři ze čtyř byly ve skutečnosti kódové**, ne assetové — pruh se
nekreslil, vrch terasy bral cizí texturu a akcenty se losovaly rovnoměrně. Nové
dlaždice by samy o sobě nespravily nic. To je poučení, které tenhle projekt dostává
opakovaně: *než objednáš art, ověř, že ho kód vůbec umí nakreslit.*

## 4. Rastr — nedohadovat se, měřit

Buňka je **64×32 px obrazovky**. PixelLab `tile_size=64` u isometrických nástrojů
má dát diamant 64×32. **Ověřit změřením souboru, ne přečtením parametru** — tenhle
projekt už jednou měsíc běžel na rozejitém rastru, protože `TERRAIN_ART_PX` říkalo
24 a na disku ležel 16px art (viz `data.gd` a `project-pixel-velikost`).

Kontrola je v `tools/pl_iso.py check` — ta se pouští **před** instalací do `assets/`,
ne po ní.

## 5. Rozdělení práce generátor / kód

Zůstává beze změny, protože je to jediná věc, která tady historicky fungovala:

> **Generátor dodává MATERIÁL. Kód dodává GEOMETRII.**

Zeď se nesmí generovat jako hotový iso rovnoběžník — dvě nezávisle generovaná
umělecká díla se nikdy neshodnou na sdílené hraně (ověřeno, 3px mimo, viz hlavička
`iso_pilot.gd`). `IsoWallSegment` počítá rohy z téže konstanty `TILE_SIZE` jako
podlaha, takže spára *nemůže* vzniknout, a art jen vyplňuje plochu.

**Výjimka, ověřená měřením 21. 8. 2026:** `create_building_kit` geometrii dodávat
**smí**. Všechny jeho kusy leží na jednom platně 102×83 s jednou kotvou a jeho
podlahový diamant měří 64×33 a rozšiřuje se přesně o 4 px na řádek — mřížkově přesný
2:1 diamant.

Ostatní izo nástroje ji dodávat **nesmí**:

| nástroj | co vrátil | vydláždění |
|---|---|---|
| `create_building_kit` | 64×33, přesný | bez mezer ✔ |
| `create_path_tiles` | 64×32 vč. 10px skirtu | **0 uzavřených děr** ✔ |
| `create_tiles_pro` (holý) | 64×28..30, roztřepené šířky | 1143 px děr ✘ |
| `create_tiles_pro` + `tile_height=32` | 64×27 | 76 px děr ✘ |
| `create_tiles_pro` + `style_images` | dědí rozměr reference | bez mezer ✔ |

**`style_images` přebírá i ROZMĚR, nejen styl.** To je nejlevnější způsob, jak držet
sadu pohromadě: vygeneruj jednu dlaždici pořádně a všechno ostatní zřeť podle ní.
Totéž platí pro objekty (`create_1_direction_object`) — osm věží ze společné kotvy
vypadá jako rodina, osm samostatných volání ne.

## 6. Seznam assetů

### Země (dávka `ground`) — zadáno
| asset | nástroj | co řeší |
|---|---|---|
| `terrace` | `create_building_kit` iso 64 | bledá keramická terasa: vrch + stěny + schody + sloup |
| `lane` | `create_path_tiles` iso 64 | pruh distrakcí, 18 napojitelných konfigurací |
| `tissue` | `create_tiles_pro` iso 64 | 4 varianty tiché tmavé tkáně |

### Hotovo a nainstalováno
| asset | zdroj | kde leží |
|---|---|---|
| tkáň (8 tichých + 8 s akcentem) | `tissue3` = `create_tiles_pro` + `style_images` z `lane3` | `assets/terrain/iso/ground/` |
| dopaminová dráha (17 masek + plná deska) | `lane3` = `create_path_tiles` | `assets/terrain/iso/lane/` |
| terasa (hranol, vrch, sloup, schody) | `terrace2` = `create_building_kit`, zaroubovaný vrch + teplý posun | `assets/terrain/iso/terrace/` |
| 8 věží | `towers_b` + `towers_c` = `create_1_direction_object` ze společné kotvy | `assets/towers/head_*.png` |
| jádro, trhlina spawnu, 2 dekorace | `props_b` | `assets/terrain/iso/props/` |

Věže: ne stroje, ale **útvary vyrostlé z tkáně** — bledá voskovitá hmota s jedním
bioluminiscenčním akcentem, hlubokomořská logika. Silueta rozlišuje habit, barva ho
pojmenovává (`color` v `.tres`):

| habit | útvar | akcent |
|---|---|---|
| Focus Timer | kroucený nervový sloup, jantarový uzel + prstenec | jantar |
| Mindfulness | dendritická koruna | `b07dff` |
| Exercise | tlustý kloub se svítícím jádrem | `ff8a3d` |
| Deep Reading | štíhlá věž tříštící se do vláken | `ffc766` |
| Zen Pulsar | synaptická baňka s prstencem | `5fe4f6` |
| Guild | hnízdo buněčných těl | `2bd6c0` |
| Anchor | zakořeněná kotva s krystalem | `33e6f2` |
| Focus Pillar | vroubkovaný sloup s krystalem | `5fe4f6` |

### Zbývá
- **Nepřátelé** — 8 směrů. Jediná vrstva, která ještě mluví jazykem top-down desky.
- **Dekorace** — `decor_synapse` / `decor_knot` jsou hotové, ale nikam se nekladou.

## 6b. Dvě pasti, které stály kolo navíc

1. **Kit dělá MÍSTNOSTI, ne vyvýšenou zem.** Jeho `sides`/`outer_*` kusy jsou zdi
   *stoupající z podlahy*, takže vybírat je podle odkrytých stran udělá z terasy
   vanu. Správně je jeden hotový hranol (`tile_53`) na každou solid buňku, kreslený
   zezadu dopředu — vnitřní stěny zakryje soused, co stojí před nimi, a testovat
   sousedy netřeba vůbec.
2. **Hranol má vlastní vrch s lemem.** Vydlážděný 3×3 se z terasy stane hromada
   krabic, protože se každá buňka sama obkrouží. Řeší to zaroubování prosté
   podlahové dlaždice na vrch (`tools/install_iso_art.py`). A materiál, jehož
   podlaha je kreslená jako samostatná zaoblená deska, se nedá zachránit ani
   zaroubováním — proto v repu není `terrace5`, ačkoli jako kost vypadal líp.

## 7. Kódové dluhy, které art sám nespraví

Zapsané tady, aby se nezaměnily za vadu artu:

HOTOVO 21. 8. 2026 (ověřeno na `build/iso_board.png`):
1. ~~`_build_path_layer()` musí sáhnout na `level.path_cells`~~ — kreslí pruh
   autotilingem podle masky sousedů, plus shlukované akcenty.
2. ~~`_build_wall_segments()` musí brát vrch terasy z vlastní textury~~ —
   `_build_terrace_blocks()` kreslí hranol z kitu; `WALL_HEIGHT` 48 → **32**.
3. Věže: `has_own_pedestal = true` a `head_aims = false` na všech 15 habitech.
   Osmiúhelníková podstava i `tower_base.png` jsou pryč, sprite je kotvený za nohy
   a izo stavba se už neotáčí za cílem (Focus Timer ležel na boku).
4. ~~Jádro FOCUS kreslí starý drobný sprite~~ — `_core_prop_tex` kreslí kouli
   v kostěné kolébce. Prstence kolem **zůstaly**: nesou stav (oblouk = zbývající
   Focus, tempo vln = jak tvrdě to schytává), což sprite ukázat neumí. Barva zdraví
   přežila jako *tint*, takže „jádro zčervená" pořád platí.
5. ~~Podstava pod věžemi~~ — `has_own_pedestal` ji vypnul. **Pozor:** větev pro
   podpůrné habity (`tower.gd`, `def.is_support()`) vyžadovala `_base_tex` *i* hlavu
   zároveň, takže Anchor svůj sprite tiše ztratil a spadl na vektorový pylon. Disk je
   teď volitelný, hlava povinná.

ZBÝVÁ:
6. **Spawn zóna se kreslí jako `Rect2`** — v iso má být diamant. Prop je hotový
   (`props/spawn_rift.png`), chybí ho zapojit.
7. **Věže přišly o animaci nabíjení.** Staré snímky jsou v
   `assets/towers/_topdown_backup/`; `_advance_charge_anim()` vázal animaci na reload,
   takže z pouhého spritu šlo poznat, že habit pracuje nebo má pauzu. Než se
   vygenerují izo animace (`animate_object`), je ta zpětná vazba pryč — **známá
   regrese, ne přehlédnutí.**
8. **Nepřátelé jsou pořád top-down sprity** — jediná vrstva, která ještě nemluví
   stejným jazykem jako zbytek desky.
