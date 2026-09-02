# STYLE_BIBLE.md — jedna centrální definice stylu

> **Tohle je jediný zdroj pravdy pro generování artu.** Všechno ostatní z něj čerpá:
> `tools/gen_art_prompts.py` tenhle soubor **parsuje** a staví z něj
> `docs/art/GENERATION_PLAN.md`; `scripts/_test_art_prompts.gd` proti němu ten plán
> ověřuje. Když se změní pravidlo, mění se **tady** — ne v generátoru a ne v promptu.
>
> Bloky označené `<!-- gen:klic -->` jsou **strojově čtené**. Needituj jim strukturu
> (počet sloupců, pořadí, název klíče) bez úpravy parseru v `tools/gen_art_prompts.py`;
> obsah řádků se měnit smí a je to zamýšlený způsob práce.

## Co tenhle soubor nahrazuje a co ne

| soubor | vztah |
|---|---|
| `docs/art/iso_bible.md` | **nahrazen pro top-down desku.** Izometrická deska už se negeneruje (větev `iso-to-topdown`). Zůstává jako záznam měření a pastí — kapitoly 2b (plochý terén), 4 (rastr měř, nedohaduj se), 5 (generátor dodává materiál, kód geometrii) a 6b platí dál a jsou sem převzaté. |
| `docs/art/style_bible_measured.md` | **doplněk, ne konkurent.** Ten soubor je *měření* 734 shipnutých PNG (paleta, počet barev, obrys, hue-shift stínu, počty snímků). Tenhle soubor je *norma* (co kreslit a proč). Čísla, která odsud cituju, jsou odtamtud a nemám je přepisovat od stolu. Přejmenován ze `style_bible.md` 29. 8. 2026 — proč, viz `BLOCKED.md`. |
| `docs/art_style.md` | shrnutí pro AI nástroje; po téhle migraci popisuje izo desku a je v části „Raster“ zastaralý. Neruším ho, ale při konfliktu platí tenhle soubor. |
| `docs/design/fae_theme.md` | **NEPOUŽÍVAT.** Odloženo 21. 8. 2026, `docs/art_style.md` to říká výslovně. Jména Wisp / Hob / Trod jsou mrtvá. |

---

## 0. Věta, ze které všechno plyne

> **Soustředění je tkáň. Distrakce je jev, který se tou tkání valí. Návyk je řád,
> který do ní hráč vloží.**

**Revize 2. 9. 2026 (rozhodl uživatel, směr A — viz §12).** Do téhle věty do dneška
patřilo *„Distrakce je patogen. Návyk je buňka, která tkáň brání."* Obě poloviny byly
imunologické, a to je přesně ta vada, kterou směr A odstraňuje: habity i distrakce
kreslila **táž organická látka** a lišily se jen tím, jak je ta látka zubatá. Rozdíl,
který má hráč přečíst na první pohled, tak stál na jediné ose (hladký obrys vs. roztřepený)
a druhá osa — barva — mu ho v mlze a pod Tolerancí vzala (§2a). Směr A ten jediný registr
**rozděluje na dva**: distrakce zůstávají organické a beztvaré, habity přecházejí na
geometrii. Tkáň jako podklad se nemění; mění se to, co po ní jde, a to, co na ní hráč staví.

Předchozí kolo mělo „soustředění je tma a ticho, distrakce světlo a hluk, návyk je něco,
co si nad tím postavíš“ — a *postavíš* z toho udělalo architekturu (keramická terasa,
zdivo). Top-down deska nemá výšku, kterou by architektura mohla ukázat, takže ta metafora
tady nemá co nést. Nahrazuje ji **imunologie**: nic se nestaví, všechno je živé.
Návyk není stroj přišroubovaný na tkáň, je to tkáň, která přerostla.

> **Poslední věta předchozího odstavce už neplatí pro habity** (směr A, 2. 9. 2026).
> Zůstává tu jako záznam, proč se sem imunologie vůbec dostala — ta úvaha platí dál pro
> **tkáň a distrakce**. Návyk už ale není „tkáň, která přerostla": je to jediná
> geometrická věc na desce, a právě tím se pozná, že ho tam dal hráč (§12).

## 1. Vizuální jazyk — organická neurální tkáň

**Rozsah po směru A (2. 9. 2026): tahle sekce platí pro TERÉN a DISTRAKCE, ne pro habity.**
Habity mají od směru A vlastní, záměrně protichůdný jazyk (§12) — geometrii. Není to
výjimka, kterou by šlo přehlédnout: je to ta osa, na které hráč pozná svoje věci od cizích,
takže se pravidla níž na habity **nesmí** vztáhnout „pro konzistenci“.

**ANO:** křivky, vlákna, membrány, výběžky, měkké uzly, věci, které vyrostly.
**NE:** hrany, součástky, panely, šrouby, ozubená kola, obrazovky, kabely, mechanika.
**NE:** doslovný mozek v řezu, doslovný orgán, anatomický model, lékařský diagram.

Ta třetí řádka je ta, kterou generátor poruší nejdřív. „Neurální“ mu zavání učebnicí
anatomie; potřebujeme **látku**, ne ilustraci orgánu. Když se v náhledu objeví
rozpoznatelný mozek se závity, je to špatně, i kdyby to prošlo všemi metrikami — platí
`feedback-organicky-tvar-nad-doslovnosti`: posuzuj art podle tématu hry, ne podle
doslovnosti reference.

Druhá past je opačná: „organické“ svede generátor k hladké vektorové kaňce. Silueta musí
zůstat **čitelná na 32 px** a rozeznatelná od ostatních — proto
`docs/art/style_bible_measured.md` trvá na 1px obrysu a třech tónech, ne na měkkém
přechodu.

**Rozpočet detailu je asymetrický a je to záměr** (převzato z `iso_bible.md` §2b): terén
je na obrazovce pořád a nese jedinou informaci (kudy se chodí / kde se dá stavět) —
dostane nejmíň detailu, ploché barvy. Nepřítel má tři vteřiny, než dojde k jádru, a hráč
podle něj musí okamžitě rozhodnout — dostane nejvíc. Tichá zem je *důvod*, proč je detail
na nepříteli konečně vidět.

## 2. Mapování herních prvků na vizuální slovník

<!-- gen:vocabulary -->

| element | vizuální protějšek | tón | součet RGB | odstín | září |
|---|---|---|---|---|---|
| zem | synaptická tkáň — vlhká, zbrázděná, tichá | tmavá, studená | 60–110 | studená indigo/violet 220–280° | ne |
| cesta | myelinizovaný axon — souvislá vodivá dráha | světlá, teplá | 120–160 | teplá jantarová 20–50° | ano |
| zdi | dendritické trny — hustý porost výběžků | matné, odbarvené | 380–450 | kostěná, sytost do 0.30 | ne |
| Focus | soma s výběžky — jediné klidné světlo na desce | teplá zlatobílá | 500+ | teplá 30–60° | ano |
| Habits | geometrické jádro — hranatá nebo kruhová základna, ostrá hrana, symetrie | chladný, tichý, akcent svítí | tělo ~300, akcent 300+ | studená polovina (ocel, teal, ledová modř) | ano |
| Distractions | amorfní jev — beztvarý organický shluk s nepravidelným okrajem | teplý, sytý, lákavý | 200+ | teplá „dopaminová“ (magenta, oranžová, jantarová) | ne |
| Dopamine | synaptický váček — kapka nabitá k prasknutí | teplá jantarová | 300+ | teplá 30–50° | ano |

<!-- /gen:vocabulary -->

Tři věci na téhle tabulce nejsou vkus:

0. **Teplo a chlad si 2. 9. 2026 vyměnily strany a je to záměr, ne překlep** (rozhodl
   uživatel, směr A). Do té doby měly habity teplou polovinu palety a distrakce studenou
   a jedovatou — logika byla biologická (zdravá buňka vs. jed). Směr A přepíná logiku
   z biologie na **téma hry**: distrakce nejsou jed, jsou to *návnady*, a návnada, která
   vypadá odpudivě, nemá co dělat ve hře o tom, proč se člověk nechá strhnout. Proto
   dostávají teplou sytou „dopaminovou“ zónu (magenta, oranžová, jantarová) — lákají.
   Habity naopak nesou klid a kontrolu, tedy studenou tichou zónu. **Barva tím zůstává
   druhou vrstvou, ne první** (§2a) — mění se jen to, která strana kterou zónu drží.
   Důsledek, který tahle změna NEUDĚLALA sama od sebe: `color` v existujících
   `data/habits/*.tres` a `data/distractions/*.tres` je pořád podle starého rozdělení
   a přepíše se až při autorování fáze 1 nad schválenými mastery (§12) — zapsáno jako
   viditelný dluh v `docs/art/ART_DEBT.md`, ne opraveno potichu.
1. **Distractions nezáří.** Patogen je vidět kontrastem a barvou, ne světlem — kdyby
   zářil, deska by při vlně byla samá záře a hráč by přestal vidět, co postavil. To je
   přesně opačná chyba než ta, kterou izo deska udělala s akcenty (§3).
2. **Zdi jsou nejsvětlejší plocha země a přesto matné.** Není v tom rozpor: jas není záře
   (§3). Vysoký jas dělá „sem se dá stavět“ bez jediného písmene UI — to je informace
   zadarmo, kterou izo deska musela zachraňovat červeným nápisem „Build only on high
   ground“ (`iso_bible.md` §3). Matnost dělá to, že se hráčovy věže na té ploše neztratí.

## 2a. Habity vs. distractions rozlišuje SILUETA, ne kotva

Kotva je pro celý projekt jedna (§6). Rozdíl mezi tím, co hráč postavil, a tím, co na něj
jde, proto **nesmí** stát na tom, že by se generovalo z jiné reference — musí být v kresbě
samotné, a musí přežít i to nejhorší, co s ní hra udělá.

<!-- gen:silhouette -->

| | Habits (geometrie) | Distractions (amorfní jevy) |
|---|---|---|
| obrys siluety | rovné hrany a čisté oblouky, uzavřený, ostře řezaný | nepravidelný, rozpadající se, žádné dvě hrany stejné |
| směr tvarů | symetrie kolem svislé osy, stojící, zakotvené | ven a vpřed, valící se, těžiště nahoře |
| zóna palety | studená a tichá (ocel, teal, ledová modř) | teplá a sytá „dopaminová“ (magenta, oranžová, jantarová) |
| silueta v černé | poznat mnohoúhelník nebo čistý kruh | poznat beztvarou kaňku s roztřepeným okrajem |
| měřitelně | kompaktnost <= 1.60 (§12) | kompaktnost >= 2.40 (§12) |

<!-- /gen:silhouette -->

**Proč zrovna silueta, a ne barva:** protože barva je to první, o co hra hráče připraví.

1. **Brain Fog zakrývá skoro celou desku.** Vidět je jen to, na co dosáhne světlo — jádro,
   usazené Anchory, pracující habity (`TOWER_LIGHT_RADIUS = 150`) a obránci (90).
   `docs/core/14` to říká natvrdo: *„Enemies **never** emit light. They are the dark
   arriving."* Distrakci tedy hráč neuvidí nikdy celou a nikdy nasvícenou — uvidí ji
   v okamžiku, kdy vstoupí do **jeho** světla, na kraji radiálního dopadu, kde je jas
   stlačený a sytost sražená. Z kresby v tu chvíli zbývá tvar.
2. **Tolerance barvu vysává i mimo mlhu** (`shaders/flatten.gdshader`) — a dělá to právě
   tehdy, když je hráč v úzkých, tedy když na rozpoznání záleží nejvíc. Systém, který stojí
   na odstínu, selže přesně v nejhorší možný okamžik.
3. **Sprite je na obrazovce 64 px a jede.** Na dvou buňkách v pohybu nemá jemný odstín kam
   se projevit; obrys ano.

Takže: **v brainfogu je silueta jediná spolehlivě čitelná informace.** Barevná zóna palety
je druhá vrstva, která pomůže, když světlo je — ne první, na které se staví.

Praktický důsledek pro prompt: tvarová slova nesou víc než barevná a mají v popisu stát
dřív. Po směru A se ta dvojice slovníků rozešla ještě víc — habity „geometric", „flat
faces", „hard edges", „symmetrical" proti distrakcím „amorphous", „irregular",
„dissolving edge", „no two edges alike". Barva se pojmenovává slovem a na přesnou paletu
se dotahuje až po generování přes `reduce_colors` (§7a) — v promptu žádný hex.

## 3. Pravidlo záře

> **Září jen cesta a to, co hráč postavil. Nic jiného.**

Vymahatelná definice, protože „záře“ se jinak dohaduje:

| | jas | halo vně siluety | sytý horký střed |
|---|---|---|---|
| **záře** (cesta, habity, Dopamine, Focus core) | libovolný | ano, 1–2 px, měkčí a světlejší než tělo | ano |
| **matné** (zem, zdi, distractions, dekorace) | libovolný | ne, ani jeden pixel | ne |

Takže: zeď se součtem RGB 484 je matná, protože nemá halo ani horký střed. Habit s tělem
na 300 září, protože má akcent a halo. **Jas se měří, záře se pozná podle toho, co
přetéká přes okraj siluety.**

Proč je to takhle úzké: co září, je *hráčovo*. Zář na desce je odměna. V okamžiku, kdy
začne zářit i to, co hráč nepostavil, přestane zář cokoli znamenat — a s ní i celý
mechanismus, kterým se hra učí (Tolerance vysává barvu přes `shaders/flatten.gdshader`;
když je hráč v úzkých, musí zmizet **jeho** světlo, aby to bolelo).

## 4. Kontrastní pravidlo — cesta proti tkáni

Na tomhle stojí čitelnost celé desky, takže je to jediné pravidlo v tomhle souboru, které
má **číselnou bránu** a fázi generování jen pro sebe (§10, fáze 0).

Metrika je **součet RGB kanálů, 0–765** — stejná, jakou tenhle projekt používá na audit
každého shipnutého PNG (`iso_bible.md` §2, `docs/art_style.md`). Ne relativní luminance,
ne Lab: měřit se má tím, čím se měřilo dosud, jinak se čísla nedají srovnat se staršími.

<!-- gen:contrast -->

| brána | pravidlo | naměřeno na tom, co je nainstalované |
|---|---|---|
| cesta vs. tkáň, jas | soucet(cesta) - soucet(tkan) >= 60 | 146 − 78 = **+68** |
| cesta vs. tkáň, odstín | kruhový rozdíl odstínů >= 140 | 247.5° vs 34.8° = **147.3°** |
| zdi vs. cesta, jas | soucet(zdi) - soucet(cesta) >= 200 | 484 − 146 = **+338** |
| zdi, matnost | sytost zdi <= 0.30 | 49/184 = **0.27** |
| akcent na zemi | <= 6 % plochy a ve shlucích, nikdy rovnoměrně | ACCENT_SHARE 0.06, ACCENT_STRAND 4 |

<!-- /gen:contrast -->

Referenční hodnoty jsou ty, co dnes reálně leží na disku (`tools/flat_terrain.py`): tkáň
`rgb(20, 17, 41)` = 78, cesta `rgb(78, 52, 16)` = 146, zdi `rgb(184, 165, 135)` = 484.
Nejsou vymyšlené pro tenhle dokument — jsou to instalované barvy, které už jednou prošly.

**Proč zrovna 140° a ne kulatých 150:** protože 150 by shipnutá dvojice o 2,7° neprošla.
Práh se nastavuje podle měření, ne naopak — to je celý smysl toho, že tady vůbec je.

**Proč se to musí ověřit na vygenerované dlaždici, a ne spočítat dopředu:** generátor
nedostane hex a nevrátí hex. Dostane slovo („amber“, „indigo“) a vrátí kresbu, jejíž
medián může skončit kdekoli. Jediné, co s tím jde dělat, je **vygenerovat a změřit**.

## 5. Velikosti

Tabulka je v **artových pixelech**, tedy v tom, co se objedná u generátoru a co leží
v PNG na disku. Kolik z toho bude na obrazovce, určuje `Data.pixel_scale()` a **není to
věc artu**: dnes vrací `ISO_PIXEL_SCALE = 1.0`, předizometrický top-down vzorec byl
`GRID.tile / TERRAIN_ART_PX` = 32 / 16 = **2.0** (`scripts/data.gd:89–129`). Sloupec
„buňky“ platí pro ×2; při dnešní 1.0 je všechno na obrazovce poloviční.

Klíč je **`kind`**, tentýž, kterým se řídí tabulka forem (§8), nástrojů (§9) i fází (§10).
Jedna entita má právě jeden `kind`, takže jí z toho vyjde právě jedna velikost a nedá se
o ní hádat.

<!-- gen:sizes -->

| kind | art_px | gen_px | bunky_pri_x2 | zdroj |
|---|---|---|---|---|
| distraction | 32 | 64 | 2 | zadání — „běžný distraction 32px“; ART_PIPELINE.md §588 „64px → ÷2 na 32“ |
| distraction_boss | 64 | 128 | 4 | `is_boss = true` v datech; ART_PIPELINE.md §457 „size:64 (boss 128)“ |
| habit | 64 | 64 | 4 | zadání — „habit 64px“; věže se generovaly rovnou na 64 |
| focus_core | 96 | 96 | 6 | zadání — „Focus core 96px“ |
| defender | 64 | 64 | 4 | rozhodl uživatel 30. 8. 2026 — 32 px u detailní postavy ztratilo siluetu i čitelnost (Phase 0 kontaktní list, §5b); bez půlení |
| prop | 32 | 32 | 2 | rozhodl uživatel 29. 8. 2026 — 32 px, bez kotvy |

<!-- /gen:sizes -->

**`art_px` je cíl na disku, `gen_px` je to, co se objedná.** Nejsou to dvě čísla pro
totéž — je to jediné místo, kde se ta dvě čísla smějí lišit, a má to dva nezávislé důvody:

1. **Půlení je měřený krok pipeline, ne zaokrouhlení.** `ART_PIPELINE.md` §588 ho píše
   doslova: *„64px → ÷2 na 32“*. `PIXELLAB.md` §332 má i protipól — *„Proč se 16 px nedá
   zmenšit“* — a pravidlo z toho je **generuj na dvojnásobku a půl přesně jednou**. Dvakrát
   půlený obrázek se rozpadne, negenerovaný malý vyjde prázdný.
2. **`style_character_id` má spodní hranici.** Job spadne hned, když je `size` menší než
   obsah kotvy, a hlásí požadovanou velikost. Kotva `62772f73-…` je 64px postava, takže
   žádná distrakce se nesmí objednat na 32 — musí na 64 a teprve pak se půlí.

Cena se počítá z **`gen_px`**, ne z `art_px`, a vychází přesně na čísla, která tenhle
projekt reálně zaplatil: distrakce 20 generací, boss 40 (`ART_PIPELINE.md` §457-458).

- **Pásmo „elite" 48–64 px je zrušené** (uživatel, 29. 8. 2026): v `data/` nikdy
  neexistovalo. `DistractionData` má jediný příznak tieru, `is_boss`, a nic neleží mezi
  70 HP (nejsilnější běžná, `clickbait`) a 900 HP (`social_media_binge`). Zůstal tedy
  `distraction_boss` — a ten už není vymyšlené pásmo, ale **přímý odraz dat**: kdo má
  `is_boss = true`, je boss. Kdyby boss spadl na 32 px jako běžná distrakce, byl by na
  desce k nerozeznání od notifikace, a to je právě ta informace, kterou má velikost nést.
- Strana každého spritu musí být **násobek nebo čistý dělitel 16**
  (`style_bible_measured.md`, „Pravidlo nula: rastr“). 32 / 64 / 96 to splňují.

### 5a. Přesah: nahoru a dozadu ano, do stran nikdy

*Rozhodl uživatel 29. 8. 2026.*

Habit má 64 art px = 128 px obrazovky při ×2, ale stavební blok je 3×3 buňky = 96.
Šestnáct pixelů na každou stranu tedy někam přetéct musí. Kam smí:

<!-- gen:overhang -->

| směr | povoleno | proč |
|---|---|---|
| nahoru | ano | koruna, prstenec, výběžky — nad blokem nic není a hloubka se čte z y-sortu |
| dozadu (nad severní hranu) | ano | to, co je za věží, je stejně zakryté tělem věže |
| doleva | ne | ukradlo by to sousední stavební místo |
| doprava | ne | totéž |
| dopředu (přes jižní hranu) | ne | zakrylo by to cestu a nepřítele, který po ní jde |

<!-- /gen:overhang -->

Pravidlo není estetické, je to **ochrana čitelnosti mřížky**. Blok 3×3 je jednotka,
kterou hráč klikáním vybírá; jakmile do něj vyčnívá soused, přestane být jasné, co se
kliknutím trefí. Nahoru a dozadu se přeteče do prostoru, kde stejně nic interaktivního
není. Dopředu ne, protože jižní hrana je ta, ke které se chodí — a habit, který zakrývá
distrakci, ruší přesně to rozhodování, kvůli kterému tam stojí.

**Prakticky pro prompt:** objekt má být zakotvený u spodní hrany plátna a růst vzhůru,
ne vycentrovaný. Šířka obsahu se drží do **96 z 128 px** (tři čtvrtiny plátna), výška
smí plátno využít celé.

### 5b. Downsample 64→32 selhal u detailní postavy (Phase 0, 30. 8. 2026)

**Detailní postava nepřežije 32 px.** Fáze 0 vygenerovala `broccoli_knight` na
64 px a půlila přesně jednou na 32 podle pravidla v §5 — mechanicky správně,
ale výsledek na kontaktním listu (`.dev/screenshots/phase0.png`,
`phase0_candidates_art.png`) ztrácí siluetu i čitelnost: brnění, florety a
zbraň se při 32 px slijí do jedné tmavé skvrny. Není to chyba půlení (dvakrát
půlený obrázek se rozpadne — tohle se půlilo jen jednou, přesně podle
pravidla) — je to hustota detailu v současné kotvě samotné, která na 32 px
nemá kam ustoupit. Proto `defender` v tabulce §5 výše dostal `art_px = 64` a
`gen_px` zůstává na svém stávajícím 64, takže se u obránců **od teď nepůlí
vůbec** — co přijde z generátoru, to se shipuje.

**U hordových distrakcí (`distraction`, dnes pořád 32 px) se stejný test
provede znovu, až bude existovat jednodušší kotva** (viz §6a níže) — ne proto,
že by 32 px bylo teoreticky vyloučené, ale protože důkaz o selhání se váže na
TUHLE kotvu (`fa8294b1-…`, vysoký detail), ne na velikost samu o sobě.
Jednodušší kotva se může na 32 px chovat jinak. Dokud tenhle test neproběhne,
`distraction` v tabulce §5 zůstává na 32/64 beze změny — to není přehlédnutí,
je to vědomě neroztažené rozhodnutí.

## 6. Style anchor — jeden na celý projekt

> ⚠ **Kotva `general` je od 2. 9. 2026 opuštěná (směr A, §12), ale v tabulce níž
> zůstává platná.** Není to nedopatření: odepsat ji bez náhradního id shodí generátor
> i `_test_art_prompts.gd` naráz — proč přesně, a co se musí stát dřív, je v §12c.
> Nová volání pro směr A se řídí §12, ne tímhle odstavcem.

Zkopírováno doslova z `CLAUDE.md`. **Necituj je zpaměti, ber je odsud nebo z CLAUDE.md.**
`style_character_id` bere **jen `mode="pro"`**.

Rozhodnuto uživatelem 29. 8. 2026: **jedna kotva pro celý projekt**. Junk-food větev je
odpískaná — nebyla to jen výměna reference, ale celý směr, který `docs/ART_PIPELINE.md`
§3b zrušil už 17. 8. 2026 (*„Junk food je odpískaný"*). CLAUDE.md tou dobou zůstalo
neaktualizované a mandátovalo zrušenou kotvu dál; tenhle rozpor je teď vyřešený v CLAUDE.md,
ne obcházený tady.

<!-- gen:anchors -->

| rodina | style_character_id | co to je | plati_pro |
|---|---|---|---|
| general | fa8294b1-c3ec-4ae5-92fb-39570ced0f65 | Broccoli Knight, obránce z Nutrition Guild — jediná kotva projektu. Ověřeno 29. 8. 2026 přes get_character: 64x64, 8 směrů, kompletní | defender, distraction, distraction_boss |
| ODPISKANA_junkfood_a | 62772f73-28d8-442b-add6-f33684f16415 | clickbait varianta A — junk-food rodina, zrušena 17. 8. 2026 spolu s celým junk-food směrem | nic |
| ODPISKANA_junkfood_b | 0ef2d964-dd67-4132-97b9-39083228db14 | clickbait_b, sesterská reference téže zrušené rodiny | nic |
| ODPISKANA_scroller | 7ba5d829-5a10-4ed9-b038-52978ec20782 | jednooká scrollerka, obvazový styl — nejstarší opuštěná rodina | nic |

<!-- /gen:anchors -->

**Řádek s `plati_pro = nic` je zákaz, ne archiv.** Ta tři id se nesmí objevit nikde —
ani v promptu, ani v parametru, ani v próze plánu. `scripts/_test_art_prompts.gd` to
kontroluje na celém vygenerovaném souboru, ne jen na promptech, protože kotva se do
volání dostane parametrem, a ten by kontrola omezená na text promptu minula.

**Kotva má spodní hranici velikosti a `gen_px` na ní přesně sedí.** Job spadne hned, když
je `size` menší než obsah kotvy. Čtecí dotaz z 29. 8. 2026 vrátil `size: 64x64px`, takže
64 je minimum — a `gen_px` je u distrakcí i obránců **přesně 64**, u bosse 128. Tabulka
v §5 tím pádem platí beze změny; kdyby kdokoli `gen_px` snížil na cílových 32, každé
jedno volání by spadlo hned na startu.

**Terén, věže a rekvizity kotvu nemají a mít nemají.** Nejsou to postavy —
`style_character_id` na ně nesedí ani parametrem. Rodinu jim drží `style_images`, které
podle měření z 21. 8. 2026 (`iso_bible.md` §5) **přebírá i rozměr, nejen styl**: vygeneruj
jeden kus pořádně a všechno ostatní zřeť podle něj. Osm věží ze společné kotvy vypadá jako
rodina, osm samostatných volání ne.

## 6a. Sonda na plošší kotvu (30. 8. 2026, UZAVŘENO směrem A)

> **Uzavřeno 2. 9. 2026, §12.** Otázka téhle sondy zněla „má plošší styl šanci jako NOVÁ
> kotva pro brokolicového rytíře". Směr A ji ruší v zadání, ne v odpovědi: figurální
> postava se neopouští proto, že by byla moc detailní, ale proto, že to má být **jev,
> ne bytost**. Kandidáti v `assets/raw/anchor_flat/` zůstávají na disku jako legacy
> (`ART_DEBT.md`), nemažou se. Měření níž platí dál a je i po uzavření užitečné —
> zjištění „bez `style_character_id` se ztrácí i barva a téma, ne jen hustota kresby"
> je přesně to, s čím musí počítat generování masteru ve směru A (§12f).

Uživatel: současná kotva (`fa8294b1-…`, Broccoli Knight) je výrazně detailnější
než `prop_focus_core`/`focus_timer` (fáze 0) a na jednom boardu podle
kontaktního listu nesedí. Otázka: má plošší styl šanci jako NOVÁ kotva?

**Sonda, ne rozhodnutí.** `tools/anchor_flat_candidates.py`: jedno volání
`create_character`, `mode="pro"`, `size=64`, stejný tvor
(„a broccoli knight in riveted armour, florets first, a wall that soaks hits
and pins whole clumps in place") + `flat shading, minimal dithering, clean
readable shapes, limited detail, bold silhouette, no texture noise` +
aktuální suffix (§7, včetně margin opravy). **Záměrně bez
`style_character_id`** — cíl je kandidát na NOVOU kotvu, ne variace staré; s
odkazem na starou kotvu by šlo o protichůdné zadání (napodob detailní styl A
zároveň buď plochý). `get_balance` před (4880) a po (4860): **20 generací**,
tier `pro` beze změny. 8 kandidátů staženo do `assets/raw/anchor_flat/`
(`cand_00`–`cand_07`), nic z toho není v paletě.

**Zjištění, ne verdikt — mechanické, ne estetické:** bez `style_character_id`
žádný z 8 kandidátů nedrží identitu zadaného tvora. Nikde není zelená ani
zeleninový motiv; všech osm je lidská postava s kůží barvy pleti, hnědou
kulatou „hlavou" (nejblíž floretu ze zadání zůstal jen tvar, ne barva) a u
některých tmavými nárameníky (jediný pozůstatek „riveted armour"). Jinak
řečeno: tahle dávka netestuje „plošší brokolicový rytíř" — testuje „plošší
obecná postava", protože se ztratilo víc než jen detail. To je samo o sobě
užitečné zjištění (odstranění kotvy stahuje s sebou i barvu/téma, ne jen
hustotu kresby), ale znamená to, že otázka „sedí plošší styl k neuronům" a
otázka „drží tenhle tvor bez kotvy svou identitu" se v jednom volání nedají
zodpovědět odděleně.

Kontaktní list vedle vybraného `prop_focus_core cand_00` a `focus_timer
cand_04`: `.dev/screenshots/anchor_flat_candidates.png`
(`scripts/_shot_anchor_flat.gd`). **Nevybíráno, nehodnoceno** — čeká na
uživatele.

**Co zůstává otevřené:** jestli se má zkusit znovu SE `style_character_id`
(varianta staré kotvy, ne nová) ale s výraznějším prompt-tlakem na plochost, nebo
jestli se má tenhle text-only přístup zkusit na jiném/jednoduším tvoru, který
sám o sobě míň závisí na barvě k rozpoznání. `gen:anchors` (§6) zůstává
beze změny, dokud se nerozhodne — `fa8294b1-…` je pořád jediná platná kotva
projektu.

## 6b. Druhá sonda: zjednodušení siluety (2. 9. 2026, UZAVŘENO směrem A)

> **Uzavřeno 2. 9. 2026, §12** — týž den, co sonda proběhla, a týmž rozhodnutím jako §6a.
> Sonda hledala, kolik siluetových prvků smí brokolicový rytíř ztratit; směr A tu otázku
> nezodpovídá, protože rytíř sám odchází. Kandidáti v `assets/raw/anchor_simplify/`
> zůstávají na disku jako legacy (`ART_DEBT.md`). **Jedno zjištění z ní ale přechází do
> §12 jako pravidlo:** mechanický pipeline lepí za KAŽDÝ prompt §7 i §7b doslova, takže
> forma, která si s nimi odporuje, vyrobí protichůdné zadání. Proto §7b nese od dneška
> vlastní seznam rozporů, které směr A otevřel, místo aby se na ně přišlo až na
> kontaktním listu.

**Jiná osa než §6a, schválně.** §6a odstranila detail (`flat shading, minimal
dithering, ..., no texture noise`) a zjistila, že se s ním ztrácí i identita
tvora — bez kotvy nezůstala zelená ani zeleninový motiv, výsledkem byla
„plošší obecná postava", ne „plošší brokolicový rytíř". Tahle sonda jde
opačným směrem: **dithering, tři stínovací tóny a materiálová textura zůstávají
v promptu** (přesně to, co §6a smazala) a mění se jen počet prvků, které lámou
siluetu — méně nýtů/přezek/drobného lemu, tělo čtené jako tři silné tvary
(hlava, zbraň, štít) místo mnoha malých.

**Proč zrovna tahle proměnná.** Mechanický pipeline (`gen_art_prompts.py`) lepí
za KAŽDÝ prompt doslova §7 (suffix) i §7b (design constraints), včetně postav.
U bohatě zbrojené 64px postavy to vyrábí spor, který cand_03 (živá kotva) přežil
jen proto, že ho model neposlechl doslova: forma žádá „riveted armour", §7 ve
stejném volání říká „organic neural tissue, ..., no mechanical parts, no panels
or screws" — zbroj se poptává a zároveň zakazuje jako „mechanická". Zákaz
ditheringu se navíc v assemblovaném popisu objevuje DVAKRÁT (§7b's řádek
„detail" i §7 samo), což na detailní postavě zplošťuje kresbu.

**Co se proto v promptu vědomě NEpoužilo doslova:** `bible["suffix"]` (§7) ani
§7b's řádek „detail" (`gen:design_constraints`) — to jsou přesně ty dva zdroje
sporu. Zbytek §7b (oči/obličej, končetiny, tón, postoj, perspektiva) a
standardní rámování/zákaz textu zůstaly v duchu původního textu, protože si
nekonfliktují s ničím výše. Uživatel žádal popis psaný kladně, s bany jen pro
kameru/rámování — tahle věta z toho má dvě vědomé výjimky (`no rivets, straps,
buckles, or small trim anywhere` a `no eyes and no face anywhere on the head`),
obě převzaté doslova ze zadání jako nejspolehlivější způsob, jak konkrétní
prvky opravdu potlačit, ne jako přehlédnutí kontrolou na spor.

Plný odeslaný popis (`tools/anchor_simplify_candidates.py`, `DESCRIPTION`):

```text
a broccoli knight defender, florets first, a wall that soaks hits and pins
whole clumps in place; large continuous armour plates cover the body, with
no rivets, straps, buckles, or small trim anywhere; the silhouette is broken
by exactly three strong shapes and nothing else: a rounded floret-crowned
head, a single held weapon, and a broad shield; standing on two legs, holding
its weapon and shield in visible arms; no eyes and no face anywhere on the
head; reads warm, calm and inviting, like the other habits and defenders;
stands planted and grounded, anchored to the ground, not floating or
hovering; gritty pixel dithering and three shading tones give the armour
weight and volume, the shadow tone hue-shifted at least 20 degrees toward
cool; visible material texture across the armour and floret surfaces; 1px
outline in a darker shade of the same hue, never black; colours taken only
from the supplied reference palette image; camera is a low top-down view
straight at the subject, front-facing, zero isometric tilt, no camera pitch;
centered, full object visible, margin on all sides; no text, no numbers, no
UI, no logo, no frame, no baked drop shadow
```

Parametry: `mode="pro"`, `size=64`, `view="low top-down"`,
`outline="single color black outline"`, `name="anchor_simplify_probe"`.
**Záměrně bez `style_character_id`** — stejný důvod jako §6a: cíl je kandidát
na NOVOU/upravenou kotvu, ne variace staré, takže odkaz na starou by žádal
napodobit její detail a zároveň ho zjednodušit, protichůdně.

`negative_description` (`bible["negative"]` doslova) se do `params` dal, ale
`adapt_to_schema` ho stejně jako u zbytku rejstříku zahodil — živé schéma
(`tools/pixellab_schema.json`) ho na `create_character` nemá (A0b). Nic se tím
neztratilo, protože negativa už nese slovně samotný popis.

**`get_balance`: 4820 před, 4820 po — beze změny, i když job doběhl a stáhl
8 kandidátů.** To NENÍ konzistentní s §6a (4880 → 4860, čistých −20) a je to
zapsáno jako naměřený fakt, ne domyšlené na −20: mezi §6a (30. 8. 2026) a
touhle sondou (2. 9. 2026) přeskočil `subscription` na „Tier 3: Pixel
Architect" s `generations_total` poznámkou „prorated on a mid-cycle upgrade" —
možné vysvětlení je změna účtovacího modelu na tomhle tieru, ne že by se
generace stala zadarmo omylem. Nepotvrzeno, nedomýšleno dál.

8 kandidátů staženo do `assets/raw/anchor_simplify/` (`cand_00`–`cand_07`),
žádná paleta (nevybíralo se). **`assets/raw/broccoli_knight/` zůstalo
nedotčené** — `cand_03.png` (zdroj živé kotvy) i zbytek složky beze změny,
ověřeno `git status` před i po (jediné netracked položky v ní,
`idle/` a `simplified_silhouette/`, existovaly už před touhle sondou a
nesouvisí s ní).

**Zjištění, ne verdikt — mechanické, ne estetické:** na rozdíl od §6a si
všech 8 kandidátů drží identitu tvora — zelená paleta, floretová hlava, zbroj
a štít jsou na první pohled rozpoznatelné jako brokolicový rytíř, ne obecná
lidská postava. Kontaktní list (barevný řádek i silueta) ukazuje siluety
s menším počtem drobných výstupků než živá kotva cand_03 (jejíž silueta má
zubatý obrys od pláště a hole) — u většiny kandidátů se obrys čte jako
hlava/tělo/štít-a-zbraň, blíž zadaným „třem silným tvarům" než cand_03.
Nezaznamenáno jako důkaz, že tenhle přístup je lepší — jen že se prompt na
kontaktním listu chová v souladu s tím, co žádal.

Kontaktní list: `.dev/screenshots/anchor_simplify_candidates.png`
(`tools/anchor_simplify_candidates.py sheet`) — barevný řádek a siluetový
řádek vedle sebe, `cand_03` vlevo jako živá kotva pro srovnání.
**Nevybíráno, nehodnoceno** — čeká na uživatele.

**Co zůstává otevřené:** stejná otázka jako §6a — jestli tenhle směr (detail
zůstává, siluetových prvků ubývá) sedí líp než §6a's úplné zplošťování, a
jestli se má zkusit jako revize `fa8294b1-…` (SE `style_character_id`, jako
skutečná varianta živé kotvy) místo jako kandidát na úplně novou. `gen:anchors`
(§6) zůstává beze změny, dokud se nerozhodne.

## 7. Povinný suffix

Jde do **`description` každého promptu**, doslova, na konci, oddělený `; `. Testuje se
přesná shoda — nepřepisuj ho v generátoru, přepiš ho tady.

<!-- gen:suffix -->

```suffix
1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; not a literal brain or organ, no anatomical diagram, no medical illustration; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

<!-- /gen:suffix -->

**Úvodní klauzule o organické tkáni odsud 2. 9. 2026 ODEŠLA (směr A).** Suffix začínal
slovy *„organic neural tissue, curved fibrous forms, no mechanical parts, no panels or
screws"* — a od chvíle, kdy jsou habity geometrické (§12), by to byl **přímý spor
v každém habitím promptu**: „geometric, flat faces, hard cut edges" a „curved fibrous
forms, no mechanical parts" v jedné větě. Nešlo o vkus, ale o zařazení: §7b sama
deklaruje dělbu práce *„§7 řeší JAK se to kreslí, §7b řeší CO se smí objevit v obsahu"*,
a organická tkáň je obsah, ne technika. Klauzule se proto přesunula do §7b, kde je
**vázaná na rodinu** — distrakce ji nesou dál (a s nimi i zákaz mechanických dílů),
habity ne. Zákaz doslovného mozku zůstal tady, protože platí pro všechno.

Přesně tenhle druh sporu naměřila §6b u `broccoli_knight` („riveted armour" proti
„no mechanical parts"); tady se odstranil u zdroje, ne obcházel v jednotlivém promptu.

**`centered, full object visible, margin on all sides` přidáno 30. 8. 2026.**
`prop_focus_core`'s `cand_02` v Phase 0 kontaktním listu přetékal přes okraj
plátna — bez rezervy kolem obsahu generátor občas ořízne, co má být vidět
celé. Platí od teď pro každý budoucí prompt; nic z už staženého Phase 0 se
tím nepřegeneruje samo.

## 7a. Vybraní kandidáti (výsledky generování)

Fáze 0 vrátila u každé entity víc kandidátů k výběru (`review (N candidates)` —
`create_character`/`create_1_direction_object` samy o sobě žádný parametr na
počet kandidátů nemají, N si volí server). Tahle tabulka zaznamenává, který
kandidát byl vybraný jako ten, co reálně shipuje — **nevybrané zůstávají na
disku** (`assets/raw/<entita>/`), nemažou se, jsou to alternativy pro pozdější
varianty, ne odpad.

<!-- gen:selected -->

| id | kandidat | soubor | poznamka |
|---|---|---|---|
| prop_focus_core | cand_00 | assets/raw/prop_focus_core/cand_00.png | vybráno uživatelem 30. 8. 2026; paleta už hotová (cand_00_pal48.png) |
| focus_timer | cand_04 | assets/raw/focus_timer/cand_04.png | vybráno uživatelem 30. 8. 2026; paleta zatím neproběhla |
| broccoli_knight | cand_03 | assets/raw/broccoli_knight/cand_03.png | vybráno uživatelem 30. 8. 2026; paleta zatím neproběhla — kotva sama je teď ve hře (§6a), regenerace možná dřív, než na paletě záleží |

<!-- /gen:selected -->

A k němu jeden pevný `negative_description`:

<!-- gen:negative -->

```negative
photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature
```

<!-- /gen:negative -->

**Paleta se nevynucuje slovy, ani v tomhle volání obrázkem.** Prompt nesmí obsahovat
žádný hex ani vlastní seznam barev. **Oprava 30. 8. 2026 (A0b):** `color_image_url`
byl tu dřív popsaný jako mechanismus vynucení — podle živého schématu
(`tools/pixellab_schema.json`) ho ale `create_character` ani
`create_1_direction_object` vůbec nemají a tiše by ho zahodily. Paleta na
`docs/art/palette_48.png` (48 barev, celý projekt z ní čerpá) se vynucuje AŽ PO
generování, přes `reduce_colors(palette_image_url=…)` na staženém výsledku
(GENERATION_PLAN.md bod 2). `palette_32.hex` v repu existuje, ale **měřitelně škodí
6 z 10 příšer a nesmí se objevit nikde v žádném promptu ani parametru.** Barvy se
v promptu pojmenovávají slovem („amber“, „indigo“, „teal“) — slovo generátor posune
k tónu, který `reduce_colors` pak dotáhne na přesnou paletu; hex by mu dal záminku
vyrobit si vlastní.

## 7b. Design constraints — vynuceno DOSLOVA v každém promptu

*Přidáno 30. 8. 2026, priorita před zbytkem fáze 1.* Kontaktní list fáze 0 (28 kandidátů)
ukázal, že šest základních otázek se dá zodpovědět jinak pokaždé, když se nechá na
generátoru — a oprava po vygenerování je regenerace, ne úprava. Tahle sekce je proto
stejný mechanismus jako §7 (povinný suffix), jen o úroveň výš: **§7 řeší JAK se to kreslí**
(obrys, stínování, dithering), **tahle sekce řeší CO se smí a nesmí objevit v obsahu**, a
obojí jde do promptu doslova, ne odkazem — jinak to generátor při první příležitosti poruší
(stejný důvod, proč §1 už varuje před doslovným mozkem).

Šest otázek, které musí mít odpověď před KAŽDÝM voláním:

<!-- gen:design_constraints_table -->

| otázka | pravidlo | výjimka |
|---|---|---|
| oči a obličej | žádná entita nemá oči ani obličej, žádné obočí, žádná ústa | **žádná** — výjimka pro `clickbait` (jedno velké holé oko) padla se směrem A 2. 9. 2026; `clickbait`ův popis v §8 ji ale pořád nese, viz dluh pod tabulkou |
| tvar | habits jsou geometrické (rovné plochy, čisté oblouky, hranatá nebo kruhová základna, symetrie kolem svislé osy, ostře řezaná hrana); distractions jsou amorfní organické shluky s nepravidelným rozpadajícím se okrajem a bez kusu geometrie | žádná — tohle je hlavní rozlišovací osa směru A (§12) a nesmí se změkčovat „pro konzistenci desky“ |
| končetiny | žádná entita nemá ruce ani nohy | **jediná výjimka: čtyři obránci Nutrition Guild** (`broccoli_knight`, `avocado_monk`, `chilli_berserker`, `garlic_mage`) — drží zbraň nebo nástroj (kopí, pěsti, nůž, hůl), a to bez rukou nejde. ⚠ Směr A opouští figurální styl, takže tahle výjimka je na spadnutí — **nechal jsem ji v platnosti schválně** a čeká na rozhodnutí, viz dluh pod tabulkou |
| tón | habits chladné, tiché a kontrolované; distractions teplé, syté a lákavé; terén, props a focus core neutrální a tiché | žádná — **pozor, oproti stavu do 1. 9. 2026 je to prohozené**, důvod je v §2 bodu 0 |
| detail | ploché barvy, žádný dithering, žádná textura, žádný gradient | shoduje se s §7 — schválně zdvojeno, protože tahle sekce jde do promptu jinam a dřív |
| postoj | postavené věci (habits, defenders, props, focus core) sedí zakotvené a nehybné; cokoli, co se hýbe (distractions), zůstává nízko a v kontaktu s povrchem, nikdy ve vzduchu | ⚠ **v rozporu s dnešním textem `phantom_buzz`** (§8: „hovers“, „no legs“) — schválně to tady neopravuji sám, viz poznámka pod tabulkou |
| perspektiva | low top-down, čelní pohled, nulový izometrický náklon, žádný náklon kamery | žádná |

<!-- /gen:design_constraints_table -->

**Dluh, který směrem A vznikl a NENÍ tímhle commitem opravený (2. 9. 2026).** Tabulka
výš a doslovný blok níž se změnily; **popisy jednotlivých entit v §8 ne.** Fáze 1 (zbytek
rejstříku) je podle §10 stejně zamčená za schválením masterů, takže se z těch popisů
zatím negeneruje — přepíšou se při autorování fáze 1 nad schválenými mastery, ne teď
od stolu. Do té doby si tyhle tři rozpory drží §8 dál a jsou vědomé, ne přehlédnuté:

1. **`clickbait` má v §8 „one huge lidless eye"**, zatímco pravidlo očí už výjimku nemá.
2. **Patnáct habitů má v §8 „glial cell / glial body / glial bulb"** — organický popis
   proti geometrickému pravidlu tvaru.
3. **Barvy v §8 i v `data/**/*.tres` drží staré rozdělení** (habity teplé, distrakce
   studené), opačné než §2 a než blok níž.

Všechny tři jsou zapsané v `docs/art/ART_DEBT.md`. Kdyby se z §8 generovalo dřív, než se
přepíše, prompt by si **sám sobě odporoval** — přesně ta vada, kterou §6b naměřila
u `broccoli_knight` (forma žádá „riveted armour", suffix zakazuje mechaniku).

**Proč zrovna tahle sekce, a ne spolehnutí na `view` parametr (§9):** `create_1_direction_object`
(nástroj pro `prop`, `focus_core`, `habit`) má jiný enum `view` než `create_character` a
**„low top-down" mu poslat nejde** — to už §9 zdokumentovalo jako past. Pro tři z šesti
`kind` tedy perspektiva **nemá jinou cestu do generátoru než text promptu**. Tahle sekce
je ta cesta — a jde do promptu pro všech šest `kind`, ne jen pro ty tři, aby se pravidlo
nemuselo pamatovat dvakrát.

**Nevyřešený rozpor, čeká na rozhodnutí:** `phantom_buzz` je v §8 popsaný jako „a hollow
blue spore husk that hovers, no legs, a sharp vibrating rim" — to je vznášení, a pravidlo
postoje výše říká „nikdy ve vzduchu". Nepřepisuju §8 sám, protože nevím, jestli je vznášení
u týhle jedný entity záměr (přízračná distrakce, na rozdíl od ostatních, co lezou/tečou po
tkáni) nebo jen nedopatření z doby, než tahle sekce existovala. Až se schválí, buď (a) se
`phantom_buzz` v §8 přepíše na „flows low" apod., nebo (b) se do výjimky u postoje přidá
`phantom_buzz` po vzoru výjimky u očí — obojí je jednořádková změna, jen ji nemám dělat bez
tebe.

Doslovný text, co jde do každého promptu (parsuje `tools/gen_art_prompts.py`, ověřuje
`scripts/_test_art_prompts.gd`):

<!-- gen:design_constraints -->

```design_constraints
no eyes and no face anywhere, no brows and no mouth on any entity; no arms and no legs anywhere, except the four Nutrition Guild defenders, who hold a weapon or tool and therefore have hands; every habit is geometric, built from flat faces and clean arcs on a square or circular base, symmetrical about its vertical axis, with hard cut edges, and reads cool, quiet and controlled; every distraction, including the boss, is an amorphous organic mass of curved fibrous matter with an irregular dissolving edge, no two edges alike, no geometry anywhere in it and no mechanical parts, panels or screws, and reads warm, saturated and enticing; terrain, props and the focus core read neutral and quiet; flat colour fields only, no dithering, no texture noise, no gradient banding; built and rooted things sit still and anchored to the tissue, anything that moves stays low and in contact with the surface, nothing floats or hovers clear of the ground; camera is a low top-down view straight at the subject, front-facing, zero isometric tilt, no camera pitch
```

<!-- /gen:design_constraints -->

**Kam v promptu jde:** hned za popis formy (`form` z §8) a před povinný suffix (§7) — obsah
dřív, technika kresby až po něm. Test `scripts/_test_art_prompts.gd` ověřuje, že blok je
v KAŽDÉM promptu v `docs/art/GENERATION_PLAN.md`, stejným mechanismem, jakým už ověřuje §7.

## 8. Rodiny a formy jednotlivých entit

`kind` řídí, kterým nástrojem se to generuje (§9) a do které fáze to spadá (§10).
`family` je klíč do tabulky kotev (§6); `-` znamená bez kotvy, drží ji `style_images`.
`base` je id, ze kterého se dědí (`style_images`, u tier-2 habitů `init_image_url`) —
prázdné znamená, že tenhle kus je kořen rodiny a musí vzniknout dřív než ti, kdo se na něj
váží.

<!-- gen:forms -->

| id | kind | family | base | form |
|---|---|---|---|---|
| prop_focus_core | focus_core | - | - | a single large neuron soma with many radiating processes, warm and unhurried, the one still thing on the board, gold white |
| prop_dopamine | prop | - | prop_focus_core | a synaptic vesicle, a small round warm amber droplet swollen to bursting, translucent membrane |
| prop_spawn | prop | - | prop_focus_core | a torn opening in the tissue where something comes through, ragged cold edges, dark and empty inside |
| decor_synapse | prop | - | prop_focus_core | a small synaptic cleft between two processes, scenery only, never reads as a collectable |
| decor_knot | prop | - | prop_focus_core | a small tangled knot of fibres resting on the tissue, scenery only |
| broccoli_knight | defender | general | - | a broccoli knight in riveted armour, florets first, a wall that soaks hits and pins whole clumps in place |
| avocado_monk | defender | general | broccoli_knight | an avocado monk with wrapped fists and a stone pit core, calm, mends the defenders around it |
| chilli_berserker | defender | general | broccoli_knight | a chilli berserker with two burning knives and no patience, thin and fast, every slash keeps searing |
| garlic_mage | defender | general | broccoli_knight | an ivory garlic bulb sage with a root staff, its pungent air slows everything shuffling through it |
| clickbait | distraction | general | - | a pathogen dominated by one huge lidless eye with a barbed rim, pink, armoured against fast small hits |
| notification | distraction | general | clickbait | the smallest and fastest spore of the swarm, a hard red shell and one twitching cilium, almost nothing to it |
| phantom_buzz | distraction | general | clickbait | a hollow blue spore husk that hovers, no legs, a sharp vibrating rim, and nothing at all inside it |
| autoplay | distraction | general | clickbait | an amber spore chain of three fused capsules that keeps unrolling forward, each capsule budding the next |
| fomo | distraction | general | clickbait | a darting magenta filament with a bright head and a dissolving tail, already half gone before it arrives |
| energy_drink | distraction | general | clickbait | a swollen teal cyst under pressure, ribbed, with a torn neck venting, faster the more damaged it is |
| just_one_more | distraction | general | clickbait | a violet cluster of four loosely bound spores pulling apart at the seams, about to become four of itself |
| doomscroll | distraction | general | clickbait | a long green ciliated ribbon that flows head first, segmented, with no visible end to it |
| group_chat | distraction | general | clickbait | a knot of six small green spores sharing one membrane, all of them mouths, none of them a head |
| comparison | distraction | general | clickbait | a bleached cyan mimic blob wearing a half finished copy of another creature, edges unresolved |
| jackpot | distraction | general | clickbait | a crimson gland with three swollen lobes and one bright wet core, pulsing on a slow rhythm |
| adult_content | distraction | general | clickbait | a heavy orange sac with hooked barbs and a slick membrane, low to the ground and dragging |
| social_media_binge | distraction_boss | general | clickbait | a violet colonial mass of fused spores, many eyes, a shielding outer membrane, dragging a train of smaller buds behind it |
| focus_timer | habit | - | prop_focus_core | a round glial cell body with one coiled process wound like a spring and a single warm amber node, working in bursts |
| mindfulness | habit | - | focus_timer | a round glial cell under a wide crown of fine violet dendritic processes, reaching over everything nearby |
| exercise | habit | - | focus_timer | a thick walled glial body with a glowing orange core showing through the membrane, heavy and slow |
| real_hobby | habit | - | focus_timer | a slender glial column fraying at the top into many fine golden fibres, reaching further than anything else |
| zen_pulsar | habit | - | focus_timer | a spherical glial bulb held inside one standing cyan ring, still until it releases |
| accountability | habit | - | focus_timer | a nest of several small round glial bodies sharing one teal membrane, a place others come out of |
| anchor | habit | - | focus_timer | a squat glial body rooted into the tissue by thick processes, one cyan crystal node, it holds and does not fire |
| focus_pillar | habit | - | focus_timer | a fluted round glial column with a single cyan crystal at its crown, quiet and upright |
| focus_timer_2 | habit | - | focus_timer | the same cell escalated, the coil tighter and doubled, the amber node brighter, one added ring |
| mindfulness_2 | habit | - | mindfulness | the same cell escalated, the dendritic crown denser and wider, the violet deeper |
| exercise_2 | habit | - | exercise | the same cell escalated, the wall thicker and the orange core burning brighter through it |
| real_hobby_2 | habit | - | real_hobby | the same cell escalated, more golden fibres, fraying further down the column |
| zen_pulsar_2a | habit | - | zen_pulsar | the same cell escalated, a second concentric cyan ring standing outside the first |
| zen_pulsar_2b | habit | - | zen_pulsar | the same cell escalated, the single ring split into two smaller counter turning half rings |
| accountability_2 | habit | - | accountability | the same cell escalated, two more bodies in the nest, the teal membrane brighter |

<!-- /gen:forms -->

Poznámky, které z tabulky nejsou vidět, ale řídí sloupec `base`:

- **Kořen distrakcí je `clickbait`, protože kotva rodiny JE clickbait varianta A.** Ostatní
  se na něj vážou přes `style_images`, aby si vzaly i rozměr.
- **Tier 2 habitu je TÁŽ kresba, ne jiný objekt** (`PIXELLAB.md` §5f). Proto se generuje
  jako img2img z tier-1 PNG (`init_image_url`), ne novým voláním od nuly — jinak vzniknou
  dvě různé věci a hráč nepozná, že to je jeho vylepšený návyk.
- **`focus_timer` je kořen habitů** (nejlevnější věž, staví se první, má na disku jako
  jediná kompletní osmisměrnou sadu) a váže se na `terrain_spine`, protože habit stojí na
  zdi a musí z ní materiálově vyrůstat, ne na ni být položený.
- **`broccoli_knight` je kotva sám sobě** — je to `fa8294b1-…`. Jeho záznam v plánu je
  „kotva rodiny, regeneruj jen když se mění celá rodina“, ne nová objednávka.

**Co v tabulce vědomě není:** `data/ads`, `data/cards`, `data/interventions`,
`data/growth`, `data/insight_cards`. Žádná z těch tříd nemá pole na texturu a žádná se
nekreslí ze spritu — `AdOverlay` je dokonce **schválně mimo styl projektu**
(`scripts/ad_overlay.gd:12–14`: „Deliberately drawn OFF the project's style… never has to
meet the art bar“). Nejsou to opomenuté entity, jsou to entity bez vizuálního protějšku.

## 9. Nástroje a ceny

<!-- gen:tools -->

| kind | mcp_tool | mode | poll | pevne_parametry |
|---|---|---|---|---|
| prop | mcp__pixellab__create_1_direction_object | pro | get_object(object_id) | view=top-down |
| focus_core | mcp__pixellab__create_1_direction_object | pro | get_object(object_id) | view=top-down |
| habit | mcp__pixellab__create_1_direction_object | pro | get_object(object_id) | view=top-down |
| defender | mcp__pixellab__create_character | pro | get_character(character_id) | view=low top-down, outline=single color black outline |
| distraction | mcp__pixellab__create_character | pro | get_character(character_id) | view=low top-down, outline=single color black outline |
| distraction_boss | mcp__pixellab__create_character | pro | get_character(character_id) | view=low top-down, outline=single color black outline |

<!-- /gen:tools -->

Čtyři věci na téhle tabulce byly v prvním návrhu **špatně** a stojí za to, aby tu zůstalo
proč — jsou to přesně ty omyly, na které se dá znova šlápnout:

- **`create_1_direction_object` NENÍ standard, je pro (20–40).** Zadarmo to není a plán to
  musí započítat.
- **Jeho `view` má jiný enum než ostatní nástroje** — jen `top-down | sidescroller`.
  „low top-down“ mu poslat nejde, i když ho berou `create_character`
  a `create_8_direction_object`.
- **`create_character` v `mode="pro"` dělá vždycky 8 směrů** a `n_directions` ignoruje.
  Posílat `n_directions=4` je zbytečné a matoucí.
- **`tile_feature="tileset"` se nedá kombinovat se `style_images`.** Terén tedy rodinu
  přes `style_images` držet nemůže — drží ji tím, že v každém volání je `terrain_tissue`
  druhým terénem a překreslí se s ním. Proto má terén vlastní strategii v §9b.

`view` u postav je **„low top-down“** a ne „high top-down“: shipnutá rodina je promptovaná
jako *„front-facing low top-down RPG perspective, zero isometric tilt“*
(`ART_PIPELINE.md` §441–455) a kotva `62772f73-…` je z ní. Jiný pohled by kotvu popíral.

### 9b. Dávkování

<!-- gen:batching -->

| kind | strategie | max_v_davce | zdroj |
|---|---|---|---|
| prop | item_descriptions v jednom create_1_direction_object | 4 | build/iso_art/jobs.json, dávka props_b |
| focus_core | vlastní volání, nemíchá se do dávky | 1 | jediný kus na desce, nesmí soutěžit o kandidáty |
| habit | item_descriptions v jednom create_1_direction_object | 4 | build/iso_art/jobs.json, dávky towers_b a towers_c |
| defender | vlastní volání | 1 | create_character je vždy jedna postava |
| distraction | vlastní volání | 1 | create_character je vždy jedna postava |
| distraction_boss | vlastní volání | 1 | create_character je vždy jedna postava |

<!-- /gen:batching -->

**Proč zrovna 4 a ne 16.** `create_1_direction_object` vrátí v jednom volání víc kandidátů
podle `size` (do 42 px → 64 kandidátů, do 85 → 16, do 170 → 4) a `item_descriptions` smí
být tolik, kolik kandidátů vyjde. Teoreticky by se tedy všech 15 habitů vešlo do jednoho
volání. **Dávka 4 je jediná, kterou tenhle projekt reálně proběhl** (`towers_b`,
`towers_c`, `props_b`) — a plán, který si vymyslí neověřenou dávku 16, riskuje 40 generací
na jednu kartu. Až se 16 změří, změní se to tady, ne v generátoru.

<!-- gen:pricing -->

| tier | generaci | zdroj |
|---|---|---|
| standard | 1 | CLAUDE.md — „Ceny: standard=1, v3=2-9, pro=20-40 generací“ |
| v3 | 9 | CLAUDE.md — horní hranice pásma 2–9, počítá se pesimisticky |
| pro | 20 | CLAUDE.md, pásmo 20–40; ART_PIPELINE.md §458 měří 20 při size 64 |
| pro_velky | 40 | tamtéž — 40 při size 128; platí pro size > 64 |
| tileset | 40 | PIXELLAB.md, get_balance — „create_tiles_pro stojí 20–40“, pesimisticky |
| anim | 4 | PIXELLAB.md §0 — „Postava stojí 1 generaci, animace čtyři“ |

<!-- /gen:pricing -->

`pro` vs `pro_velky` se rozhoduje podle `size`: do 64 včetně `pro`, nad 64 `pro_velky`.
V dnešním rejstříku to znamená, že jediné, co spadne do 40, je `focus_core` (96 px).

**Odhad je jinak vždy horní hranice pásma.** Rozpočet, který vyjde levněji, než se čekalo,
je dobrá zpráva; rozpočet, který vyjde dráž, je vyčerpaná kvóta uprostřed rodiny — a půlka
rodiny je horší než žádná, protože se nedá srovnat.

**Ceny animací tenhle plán nepočítá.** `animate_character` je vlastní kolo (4 generace na
postavu přes šablonu, a nad 64 px **tiše eskaluje na `pro` = 20–40 na směr**, pokud se
nepošle `mode:"v3"` výslovně). Statická sada musí projít bránou fáze 3 dřív, než se do
animací vůbec sáhne — to je přesně ta brána, kterou `tools/pixellab.py` vymáhá kódem.

Před každou dávkou `get_balance` (CLAUDE.md). Async: zafrontuj všechno naráz, pak pollni
`get_*`; **jedenáctý souběžný job se vrátí jako text, ne jako chyba** (`PIXELLAB.md` §0),
takže se fronta drží pod deseti. Žádný base64 do kontextu — jen `*_url` a `curl` na
download URL.

## 10. Fáze

<!-- gen:phases -->

| phase | title | kinds | gate |
|---|---|---|---|
| 0 | Focus core, habit a obránce-kotva | focus_core, id:focus_timer, id:broccoli_knight | ZASTAVIT A NECHAT ROZHODNOUT UŽIVATELE. Povinný krok je popsaný pod tabulkou fáze v plánu; bez jeho schválení se negeneruje ani jeden další kus rejstříku. K tomu technicky: všechny tři stojí na ploché zdi (TOP, 484) a dotýkají se jí — mezi spodkem obsahu a začátkem stínu není ani řádek holé zdi — a tělo neleží do +-60 jasu od podkladu. |
| 1 | Zbytek rejstříku | habit, distraction, distraction_boss, defender, prop | Každá vygenerovaná postava má siluetu rozeznatelnou od ostatních v kontaktním listu v herním měřítku a jas nad pásmem cesty (146). |

<!-- /gen:phases -->

<!-- gen:why0 -->

**Terén se negeneruje. Fáze 0 a 1 padly.**

Rozhodl uživatel 29. 8. 2026: terén instaluje `tools/flat_terrain.py` jako ploché barvy,
za **0 generací**. Původní fáze 0 (kontrastní sonda) a 1 (zbytek terénu) tím ztratily
předmět a jsou z plánu pryč; ušetřilo to 100 generací a celý rozpočet zůstal postavám.

Důvod není úspora, ta je až následek. Je to **brainfog**. Mlha zakrývá skoro celou desku —
vidět je jen to, na co dosáhne světlo z jádra, usazených Anchorů, pracujících habitů
(`TOWER_LIGHT_RADIUS = 150`) a obránců (90). Z terénu tedy hráč nikdy nevidí plochu, na
které by textura mohla něco vyprávět; vidí malé odhalené kapsy, a v nich rozhoduje jediná
věc — **jestli je cesta odlišitelná od tkáně**. To je čistě luminanční rozdíl, a ten se
u plochých barev nastaví přesně, na jednotky. U generované dlaždice se dá jen doufat,
změřit a případně objednat znovu.

K tomu se přidává, co už bylo naměřeno dřív (`iso_bible.md` §2b): hlučný povrch se při
dláždění 3×3 rozpadne na opakovanou mřížku — rozptyl jasu 227 a 142 na generovaných
blocích proti 32 u plochých. Plochá plocha ten problém nemá z definice, není co opakovat.

**Brány z §4 tím ale nezanikly, jen se přesunuly z generování do kódu.** Vymáhá je
`tools/check_terrain_contrast.py`, který čte prahy z bible a hodnoty z `flat_terrain.py`
a nedrží si vlastní kopii ani jednoho. Změřeno 29. 8. 2026: cesta − tkáň **+68** (práh 60),
odstín **147,3°** (práh 140), zdi − cesta **+338** (práh 200), sytost zdí **0,266**
(strop 0,30). Všechny čtyři projdou **bez jakékoli úpravy** `flat_terrain.py`.

**Proč je první fází právě jeden objekt.** Když odpadl terén, první otázka už není „jde
cesta odlišit od tkáně", ale „vypadá vůbec něco z téhle kotvy tak, jak má, až to stojí na
desce a zmenší se to do herního měřítka". Ta otázka se zodpoví na jednom kusu za 20–40
generací; zodpovídat ji na čtyřiceti stojí 600.

<!-- /gen:why0 -->

<!-- gen:gate0 -->

### Povinný krok na konci fáze 0 — bez něj se dál nejde

*Zadal uživatel 29. 8. 2026.*

1. Vygeneruj **jen** ty tři kusy, které fáze 0 vyjmenovává. Nic víc.
2. Ke každému vyrob **kontaktní list se dvěma verzemi vedle sebe**: sprite v `gen_px`
   tak, jak přišel z generátoru, a týž sprite po downsamplu na `art_px`. Obojí v herním
   měřítku, tedy zvětšené `Data.pixel_scale()`, na plochém terénu z `flat_terrain.py` —
   ne na bílém pozadí. Snímek dělej v **1920×1080**, jinak výřezy minou
   (`iso_bible.md` §2e).
3. **Předlož to uživateli a počkej.** Otázka zní: je downsample přijatelný?
4. Do schválení se **negeneruje ani jeden další kus rejstříku**. Ne polovina, ne „jen
   ještě jeden na porovnání" — nic.

**VYŘEŠENO 2026-08-30 uživatelem: možnost 1.** Fáze 0 dřív mířila jen na dva kusy
(`focus_core` 96→96, `focus_timer` 64→64), a **žádný z nich nikdy nedownsampluje** —
obě verze kontaktního listu by vyšly identické, takže samotná otázka „je downsample
přijatelný" by se na nich nedala zodpovědět. Uživatel zvolil přidání `id:broccoli_knight`
do fáze 0 místo přeškálování `focus_core` na 192→96 — je to zároveň kotva a kořen rodiny
obránců, takže musí vzniknout jako první stejně, a je to skutečná postava generovaná na
64 a půlená přesně jednou na 32 (STYLE_BIBLE.md §5, kind `defender`), tedy přesně ten
downsample, který se v hotové hře reálně používá (obránci a distrakce 64→32, boss
128→64) — na rozdíl od `focus_core`/`focus_timer`, které by downsample jen předstíraly.
Cena fáze 0 stoupá o 20 generací; celkový rozpočet celého rejstříku (520 generací) se
nemění, `broccoli_knight` v něm byl vždy započtený, jen dřív jako část fáze 1. Zbytek
brány (dotyk podkladu, jas proti zdi) platí na všechny tři kusy stejně.

<!-- /gen:gate0 -->

## 11. Co se nepřebírá z izo bible

- **Poměr vrch : levý bok : pravý bok 100 : 70 : 45** — top-down deska žádné boky nemá.
  Světlo shora zůstává, ale nese ho stínování uvnitř siluety, ne tři stěny.
- **Diamantová geometrie, `WALL_HEIGHT`, terasový kit** — bezpředmětné.
- **Kontaktní stín jako 2:1 elipsa** (squash 0.5) — v top-down je to kruh, squash 1.0.

Co se přebírá beze změny: plochý terén bez textury (§2b), „generátor dodává materiál, kód
dodává geometrii“ (§5), zákaz linky po dlaždici, a pravidlo, že se rastr **měří ze
souboru, ne čte z parametru** (§4).

## 12. Design constraints — směr A (abstraktní organické jevy)

*Rozhodl uživatel 2. 9. 2026. Tahle sekce je NORMA. Když si s ní cokoli jinde v bibli
odporuje, platí ona a to druhé je dluh — ne naopak.*

**Co se rozhodlo:** deska přechází na **směr A — abstraktní organické jevy**. Figurální
styl a kotva `broccoli_knight` se opouštějí (§12c). Distrakce nejsou bytosti, jsou to
**jevy**: beztvaré organické shluky bez obličeje a bez končetin. Habity jsou proti nim
**geometrie**: jediná pravidelná, ostře řezaná věc na desce.

**Proč zrovna tenhle rozdíl nese informaci.** Rozlišení habit/distraction musí přežít tři
věci, které hru dělají hrou, a barva ani jedné z nich neodolá (podrobně §2a): Brain Fog
zakrývá skoro celou desku, Tolerance přes `shaders/flatten.gdshader` vysává barvu právě
tehdy, když je hráč v úzkých, a sprite je na obrazovce malý a jede. Zůstává **tvar**.
Do dneška ale byly obě rodiny kreslené týmž organickým materiálem a lišily se jen mírou
roztřepení — tedy jednou osou, a ještě spojitou. Směr A z toho dělá **kategoriální rozdíl**:
organické vs. geometrické. To je rozdíl, který přežije i černou siluetu na 32 px.

### 12a. Zamčené render-osy

Platí na VŠECHNY entity, bez výjimky. Osy jsou zamčené na hodnoty, ne na doporučení —
právě proto, že styl se rozjíždí tam, kde se každé volání rozhoduje znovu (§6b).

| osa | hodnota | kde se to už vynucuje |
|---|---|---|
| základní rozlišení | 480×270, celočíselné škálování 4× na 1920×1080 | `project.godot` (`viewport_width/height`, `stretch/scale_mode="integer"`) — **ověřeno, žádný rozpor** |
| perspektiva | low top-down, čelní, nulový izo náklon | §7b (doslovný blok), §9 (`view` u postav) |
| paleta | `docs/art/palette_48.png`, vynuceno AŽ PO generování přes `reduce_colors` | §7a |
| velikost | podle `kind` v §5 (habit 64, distraction 32 z objednaných 64) | §5 — **s jednou výhradou, viz §12b** |
| stínování | ploché plochy, tři tóny, stín posunutý ≥ 20° do chladna | §7 (suffix) |
| dithering | žádný | §7 (suffix) i §7b |
| obrys | 1px, tmavší odstín téže barvy, nikdy černý | §7 (suffix) — **rozpor s §9, viz §12b** |

### 12b. Rozpory se zbytkem bible, které jsem NEOPRAVIL

Zadání znělo ověřit kolizi a rozpor nahlásit, ne ho rozhodnout. Tyhle tři jsem našel:

1. **Obrys: bible si odporuje sama, a už před směrem A.** §7 (suffix, jde do každého
   promptu) říká *„1px outline in a darker shade of the same hue, **never black**"*.
   §9 (`gen:tools`, `pevne_parametry`) posílá u všech tří druhů postav
   `outline=single color black outline`. Research ke směru A navrhuje ještě třetí
   hodnotu — `selective outline` — s odůvodněním, že černý obrys sní siluetu drobných
   tvarů v hordě. **Nezměnil jsem nic**: `pevne_parametry` řídí reálné volání, takže
   změna je změna generování, ne dokumentace. Rozhodnout je potřeba jednou pro všechny tři.
2. **Velikost distrakce: bible říká 32, na disku je 48.** §5 má u `distraction`
   `art_px = 32` (objednávka 64, půlí se přesně jednou). Naměřeno 2. 9. 2026 na
   shipnutých souborech: `assets/distractions/*_frame_1.png` jsou **48×48**
   a `social_media_binge` je **96×96** (§5 čeká 64). Ani jedno nesedí na tabulku.
   Je to legacy art z junk-food éry, ne důsledek směru A — ale znamená to, že §5's
   tabulka dnes nepopisuje disk.
3. **Půlení 64→32 u hordových distrakcí zůstává neověřené.** §5b to samo podmiňuje:
   *„U hordových distrakcí se stejný test provede znovu, až bude existovat jednodušší
   kotva."* Směr A tu jednodušší kotvu právě objednává (§12c), takže ta podmínka je
   splněná — test se má provést na masteru, ne odhadnout dopředu.

### 12c. Kotva: proč se ještě NEODEPSALA v `gen:anchors`

Kotva `fa8294b1-…` (Broccoli Knight) je směrem A **opuštěná** — je to figurální,
detailní postava, tedy přesně to, od čeho se odchází. V tabulce §6 ale zatím zůstává
jako platná, a je to vynucené, ne z nedbalosti:

- `gen:forms` váže všechny obránce i všechny distrakce na rodinu `general`, a
  `tools/gen_art_prompts.py` (`load_bible`) **spadne**, když forma odkazuje na rodinu,
  která v `gen:anchors` není.
- `scripts/_test_art_prompts.gd` kontroluje dvě věci naráz: (1) každý prompt pro postavu
  má neprázdné `style_character_id` své rodiny, (2) žádná kotva označená `plati_pro = nic`
  se v celém plánu neobjeví. Přepnout `fa8294b1-…` na `nic` bez náhradního id tedy shodí
  obě kontroly zároveň.

**Odepíše se v okamžiku, kdy schválený master ze směru A dostane vlastní
`style_character_id`** — jedna změna řádku v `gen:anchors` plus přepnutí `family`
u forem. Do té doby je opuštění zaznamenané v `docs/art/ART_DEBT.md` a tady, ne
v tabulce, kterou čte generátor.

### 12d. Failure modes — měřitelné brány

Tři z šesti testů z researche jdou zautomatizovat na souborech a jsou zapsané níž jako
brány. Vymáhá je `tools/check_style_failure_modes.py` (ve `verify.sh`); prahy čte odsud,
nedrží si vlastní kopii — stejná stavba jako `tools/check_terrain_contrast.py` vůči §4.

**Prahy jsou měřené, ne vymyšlené.** Změřeno 2. 9. 2026 na shipnutém rejstříku
(8 habitů, 10 distrakcí). Kompaktnost = `obvod² / (4π · plocha)` na alfa masce;
kruh = 1.00, roztřepený tvar roste. Dnešní stav: habity 1.08–2.50 (medián 1.61),
distrakce 1.24–3.64 (medián 2.15) — **rozsahy se překrývají, dnešní rejstřík by
siluetovým testem NEPROŠEL.** To není chyba prahu, to je přesně ta vada, kvůli které
se mění směr. Prahy jsou proto postavené na tom, co už na disku prokazatelně jde:
nejkulatější habity dnes dávají 1.08–1.18, nejrozpadlejší distrakce 2.54–3.64.

<!-- gen:failure_modes -->

| brána | metrika | prah | odkud práh |
|---|---|---|---|
| silueta, habit | kompaktnost alfa masky | <= 1.60 | naměřeno: `head_mindfulness` 1.08, `head_accountability` 1.17, `head_zen_pulsar` 1.18 už dnes projdou |
| silueta, distraction | kompaktnost alfa masky | >= 2.40 | naměřeno: `energy_drink` 3.64, `group_chat` 3.20, `autoplay` 2.54 už dnes projdou |
| silueta, odstup rodin | min(distraction) - max(habit) | >= 0.80 | odstup mezi oběma branami výš; bez něj by obě mohly doputovat k sobě a test by prošel na dotek |
| styl, barvy habitu | počet unikátních RGB v neprůhledných pixelech | <= 8 | research „max 5-6 barev" + 1px obrys a jeho stín (§7); dnešní rozptyl 9-45 je přesně ten „pět stylů" problém |
| styl, barvy distrakce | počet unikátních RGB v neprůhledných pixelech | <= 6 | research „max 3-4 barvy na jednotku, žádné vnitřní detaily" + obrys |
| styl, soudržnost rodiny | max - min počtu barev uvnitř rodiny | <= 4 | shipnuté distrakce drží 22-24 (rozptyl 2), takže těsná rodina je prokazatelně dosažitelná |
| horda, hustota | podíl plochy pole 480x270 pokrytý neprůhlednými pixely jednotek; z něj se dopočítá N (strop 200, dno 8) | = 0.15 | odvozeno: podíl neslepených jednotek u náhodně rozmístěných disků je zhruba exp(-4 * hustota), takže 0.30 stropí i dokonalý kruh na ~0.30 a nikdy neprojde branou platnosti; 0.15 dává ~0.55 a nechává bráně hlavu — ověřeno měřením, viz §12g |
| horda, platnost kontroly | separable_share kontrolního plného disku téže plochy | >= 0.50 | pojistka proti tiché nule: když neuspěje ani ideální tvar, pole je přesycené a výsledek se hlásí jako INCONCLUSIVE, nikdy jako pass |
| horda, čitelnost | podíl jednotek, které zůstanou samostatnou komponentou, dělený týmž podílem u kontrolního disku | >= 0.70 | poměr, ne absolutní číslo: kontrola říká, kolik jich při téhle hustotě může zůstat čitelných v nejlepším případě |
| horda, kontrast vůči tkáni | \|soucet RGB jednotky - soucet RGB tkáně\| | >= 60 | tentýž práh, jakým §4 dělí cestu od tkáně — deska nemá dvě různé definice „dost velkého rozdílu" |

<!-- /gen:failure_modes -->

**Jak se na barevný rozpočet vůbec dá dosáhnout — protože samotné generování ho nesplní.**
Dnešní pipeline snapuje výsledek na `palette_48` (`reduce_colors(palette_image_url=…)`,
GENERATION_PLAN bod 2), což je strop 48 barev, ne rozpočet 6. Shipnuté distrakce proto
mají 22–24 unikátních RGB a **žádná by branou neprošla**. Cesta existuje a je v živém
schématu: `reduce_colors` má vedle `palette_image_url` i **`num_colors`** a `dithering`.
Druhé, přísnější kolo (nebo tentýž krok lokálně v PIL, zadarmo a deterministicky) vybere
podmnožinu už nasnapované palety, takže se z ní nedá vypadnout. **Zatím se to nikde
nedělá** — je to známá cesta, ne hotový krok, a rozhodne se o ní na prvním masteru:
jestli projde rovnou, tenhle odstavec je zbytečný, a jestli ne, tohle je to, co se
doplní. Neladit práh proto, že ho dnešní pipeline netrefí.

**Na co se brány vztahují a na co ne.** Gatuje se jen to, co je deklarované v tabulce
`gen:direction_a` níž. Zbytek rejstříku je legacy
(§12b, `ART_DEBT.md`), měří se a vypisuje, ale nezčervená build — jinak by `verify.sh`
zůstal červený od tohohle commitu až do dokončení fáze 1 a přestal by hlídat cokoli
jiného. Je to stejná úmluva jako `KNOWN_BROKEN_TESTS` ve `verify.sh` a allowlist
v `ART_DEBT.md`: viditelné, datované, a určené ke smrštění na nulu.

**Tři testy z researche se zautomatizovat nedají a zůstávají na uživateli:** squint test,
fog test (obojí je soud o dojmu z obrazovky) a drift test přes 8 směrů a snímky animace
(vyžaduje porovnání siluety napříč snímky, které dnes u směru A nemá co porovnávat).

### 12g. Proč hordový test NEBĚŽÍ na 200 jednotkách

*Naměřeno 2. 9. 2026, při stavbě `tools/check_style_failure_modes.py`.*

Research i zadání říkaly „200 jednotek". Na TÉHLE desce to nejde a je to aritmetika, ne
názor: pole je 480×270 = **129 600 px**, jedna distrakce má neprůhlednou plochu zhruba
660–1540 px, takže 200 kopií je **132 000–308 000 px** — 102 až 238 % celé obrazovky.
Změřeno na všech 42 shipnutých distrakcích: při N=200 vyjde `separable_share` **0.000
i kontrolnímu plnému disku**, tedy nejlepšímu možnému tvaru. Brána, která dá stejnou
nulu dokonalému kruhu i nejhorší kaši, neměří kvalitu siluety — měří jen to, že se pole
přeplnilo. (Kontrola: totéž pole při N=20 dá 0.400/0.400, plné 1920×1080 při N=200 dá
0.575/0.655 — čísla se vrátí, jakmile hustota klesne pod saturaci.)

Číslo 200 pochází z researche o žánru, kde ho nesou hry s jiným poměrem sprite:deska
(Bloons, Orc Problem). Tahle hra dnes navíc pouští vlny po **pěti** jednotkách
(`data/levels/level_1.tres`: `base_count = 5`, `wave_count = 3`), takže 200 souběžných
distrakcí není ani cíl, ani současný stav.

**Co se místo toho měří:** hustota se drží na **15 % plochy** a **N se z ní dopočítá**
podle toho, jak velký je testovaný sprite (strop 200, dno 8) — test tak zůstává ve
stejném, rozlišujícím režimu bez ohledu na velikost. K tomu jistí `horda, platnost
kontroly`: když neuspěje ani ideální disk, výsledek je `INCONCLUSIVE`, ne pass. Tichá
nula, která by se dala splést se splněnou branou, je přesně ta vada, kvůli které
`verify.sh` hlídá i osiřelé scény.

**Proč zrovna 15 %, a ne 30 %, na kterých ta oprava začala.** První pokus po zrušení
N=200 dal hustotu 0.30 a **pořád nerozlišoval**: 39 ze 42 shipnutých distrakcí skončilo
`INCONCLUSIVE`, protože ani ideální disk se při té hustotě nedostal přes bránu platnosti
(naměřeno 0.21–0.56). Není to náhoda ani vlastnost těch spritů — plyne to z rozmístění:
u náhodně rozházených disků je podíl těch, které se ničeho nedotknou, zhruba
**exp(-4 · hustota)**. Pro 0.30 to dává ~0.30, tedy strop *pod* branou platnosti 0.50 —
brána by nemohla projít, ani kdyby byl tvar dokonalý. Pro 0.15 vychází ~0.55, což
bránu splní a nechá nad ní rezervu na to, co má test vlastně měřit: o kolik je
skutečný tvar horší než ideální.

Pro 32px distrakci směru A to znamená **N ≈ 39 jednotek** — což je mimochodem řádově
to, co tahle hra reálně pouští (vlny po pěti, několik dávek naráz), na rozdíl od 200.

**Boss se hordovým testem neměří vůbec.** `Data.build_waves()` mu dává natvrdo
`count = 1` (`scripts/data.gd:475`) — jedna jednotka za celý level. Test na slepení
dvou set kopií nemá u něčeho, co nikdy nestojí vedle sebe, co říct; u 96px spritu by
navíc N spadlo na dno 8 a hustota by vyskočila zpátky k saturaci. Vynechává se proto
adresně, ne mlčky.

### 12e. Co se gatuje — rejstřík artu směru A

Prázdná tabulka je **správný** výchozí stav, ne chybějící práce: dokud nejsou schválené
mastery (§12f), žádný soubor směru A neexistuje. `tools/check_style_failure_modes.py`
v tom případě vypíše měření celého rejstříku jako `LEGACY` a projde — a řekne nahlas,
že gatuje nula souborů, aby se prázdná brána nedala splést s branou splněnou.

Sloupec `soubor` je cesta od kořene repa. `rodina` je `habit` nebo `distraction` a
rozhoduje, která dvojice prahů z `gen:failure_modes` se na řádek použije.

<!-- gen:direction_a -->

| id | rodina | soubor |
|---|---|---|

<!-- /gen:direction_a -->

### 12f. Postup, kterým se sem zapisuje první řádek

*Zadal uživatel 2. 9. 2026, v tomhle pořadí a ne jiném.*

1. Vygenerovat **jeden** master distraction a **jeden** master habit podle §12a–12d.
   Ne osm, ne celý rejstřík — dva sprity.
2. Projet je `tools/check_style_failure_modes.py`.
3. **Předložit uživateli a počkat.** Do schválení se nezapisuje řádek do `gen:direction_a`,
   nepřepisuje se `gen:anchors` (§12c) a negeneruje se nic dalšího.
4. Až je uživatel schválí, stanou se style referencí pro fázi 1 — a teprve tehdy se
   přepisují popisy entit v §8 a barvy v `data/**/*.tres` (dluh z §7b).

`get_balance` před každou dávkou a zůstatek do `PROGRESS.md` (CLAUDE.md).
