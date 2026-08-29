# Podměsíčí — tematická bible  ⚠️ ODLOŽENO 21. 8. 2026

> **NEPLATÍ jako svět hry.** Odloženo tentýž den, kdy bylo přijato, a to z konkrétního
> důvodu — ne z rozmaru.
>
> Podměsíčí se vybíralo proto, že **neuroanatomický art se špatně kreslil**: myelin
> a šedá hmota nemají siluetu (§1). Jenže ten problém se mezitím vyřešil jinak — terén
> je od 21. 8. plochý a nekreslí tkáň vůbec (`docs/art/iso_bible.md` kap. 2b).
> **Podměsíčí tedy řešilo problém, který přestal existovat.**
>
> Rozhodlo měření, ne vkus. Složili jsme rodinu nepřátel vedle rodiny věží
> (`build/_register.png`) a bylo vidět, že hra **už jedním jazykem mluví** — jen ne
> věžemi. Nepřátelé jsou popcorn, hrací automat, plechovka energeťáku, blob obalený
> mobily. To je současná mediální veteš a **fae to nikdy nebylo.** Věže byly dělané
> v druhém rejstříku (mystické útvary), a proto nesedí ony, ne oni.
>
> **Platný svět: současné konkrétní předměty.** Uživatel to popsal přesně — *„klidně to
> může být kulomet co střílí meditační polštářky… něco zábavného ale tématického."*
> Humor vzniká tím, že jsou to vážně myšlené pomůcky proti rozptýlení nasazené jako
> vojenská technika. Silueta pomodora nebo činky se přečte na 32 px; „útvar vyrostlý
> z tkáně" ne, a to je ta měřená vada.
>
> **Co z tohohle dokumentu platí dál:**
> - **§1b — řemeslo a svět jsou DVĚ rozhodnutí.** Tři tóny, ploché tónování, málo tvarů,
>   čitelná silueta. Řemeslo přežilo obě změny světa a je to jediná část, kterou nikdy
>   nebylo potřeba přepsat.
> - **§1c — který PixelLab nástroj na co**, včetně měření z 21. 8.
> - **§8 — insight karty**, věda se nemění za žádného světa.
>
> **Co neplatí:** §2–7 a §9 (premisa, jména, postavy, terén, jména levelů). V kódu z toho
> zůstal jen `TrodData` — to jméno se nechává, protože „trod" popisuje mechaniku dobře
> i bez folkloru, ale dokumentace u něj se přepíše.
>
> Dokument se **nemaže**: obsahuje poctivý zápis o tom, proč se dvakrát měnil svět a co
> to pokaždé nespravilo. To je informace, ne odpad.

# Podměsíčí — tematická bible (původní znění)

Nahrazuje neuroanatomický rámec (šedá hmota / myelin / synapse) fae folklorem.
Rozhodnuto 21. 8. 2026.

**Mechaniky se nemění. Mění se jména, art a rámec.** `id` v datech (`&"fomo"`,
`&"focus_timer"`) zůstávají — jsou to klíče v kódu, ne text pro hráče. Přejmenovává se
`display_name` a `description`, tedy 24 souborů `.tres`, a generuje se nový art pro věže
a nepřátele. Terén se dědí (viz §7).

## 1. Proč se to mění

Neuroanatomie byla poctivá — mapa doslova **byla** mozek. Ale jako zadání pro art
selhala, a to měřitelně:

- 7 z 8 hlav věží leželo do ±19 jasu od plošiny, na které stály. Zadání jim říkalo
  „bledý myelin proti tmavému pozadí", jenže stojí na nejsvětlejší ploše ve hře.
- Tkáň byla statisticky nerozeznatelná od prázdna (sd 5,4 proti 5,6).
- **Myelin, šedá hmota a synapse nemají siluetu.** Na 32 pixelech neřeknou, kdo je rychlý
  a kdo vydrží. Fantasy má tenhle slovník hotový pět set let.

A hra už měla dva jazyky naráz: brokolicový rytíř z Nutrition Guild vedle myelinové
tkáně nejsou dva styly, ale dva světy.

## 1b. Řemeslo a svět jsou DVĚ rozhodnutí

Potvrzeno 21. 8. 2026, po kole, kdy se obojí motalo dohromady a působilo to, že směr
hry není jasný. Není to jedna otázka, jsou to dvě:

**Svět** = Podměsíčí. O tom je zbytek tohohle dokumentu.

**Řemeslo** = jak se to kreslí, nezávisle na světě:

- **tři tóny na každou kostku** — vrch nejsvětlejší, jeden bok střední, druhý nejtmavší
- **plošné tónování, žádné přechody**
- **málo tvarů** — spíš tři velké než deset malých
- **čitelná silueta na nehtu**

Uživatel to popsal jako „stylem jako Settlers". To je popis řemesla, ne světa — a je
důležité je nezaměňovat, protože se stejným řemeslem jde nakreslit fae i sci-fi, kdežto
sebelepší svět špatné hodnoty nespraví.

**Změřený důkaz, že se to dá zadat a dostat** (`create_tiles_pro`, `tile_feature="tileset"`,
seed 5150): vrch 528, levý bok 276, pravý bok 368 → **100 : 52 : 70**. Tři zřetelně
oddělené tóny. Pro srovnání stará terasa: 100 : 66 : 66, tedy boky nerozeznatelné.

**A jedno poučení, které tuhle volbu zjednodušuje:** žánr tu vadu nikdy nezpůsobil.
Neuroanatomická i „hradní" verze selhaly na tomtéž — hodnotová struktura a hustota
detailu. Výběr světa řemeslo nespraví a řemeslo výběr světa nenahradí.

## 1c. Který PixelLab nástroj na co

Změřeno, ne odhadnuto — obojí stálo generování:

| chci | nástroj | proč |
|---|---|---|
| souvislý terénní přechod | `create_tiles_pro(tile_feature="tileset")` | 16dílná rohová sada, ale **bok napevno 16 px** |
| jeden vyvýšený blok | `create_isometric_tile(tile_shape="block")` | **jediný s výškou jako parametrem** (~50 % plátna), ale nedlaždicuje |
| cesta | `create_path_tiles` | |
| budovy, zdi, schody | `create_building_kit` | **jen na architekturu** |

### Vyvýšenou dlaždicovatelnou zem PixelLab neumí — změřeno 21. 8. 2026

Výška a bezešvost leží ve **dvou různých nástrojích** a nedají se spojit:

| | bok | dlaždicuje | hrany na vrchu |
|---|---|---|---|
| `create_tiles_pro(tileset)` | 16 px (`tile_height` se ignoruje) | ano | — |
| `create_isometric_tile(block)` | **32 px, přesně dle zadání** | **ne** | 35–48 % |
| stará ruční `block.png` | 33 px | ano | 25,5 % |

`create_isometric_tile` kreslí **jeden objekt**, ne dílek sady. Vydlážděný 3×3 z něj je
vaflový plát: každá buňka má vlastní obrys a vlastní hrbol. Rozptyl jasu na vrchu vyšel
227 (A) a 142 (B) proti 32 u staré dlaždice — 4 až 7× hlučnější povrch, takže opakování
je vidět. `detail="low detail"` a `shading="flat shading"` to nespraví, schéma je samo
označuje za „weakly guiding".

Druhá změřená vada: **stěny ujely do jiné barevné rodiny.** Vrch 22°/31°, ale stěny
299–329°, tedy purpur. Bible chce jeden materiál ve třech tónech, ne tři barvy. Odstín
i poměr jdou sesadit postprocesem (`tools/iso_faces.py`), hustotu detailu ne — a právě
ta je ta smrtelná.

**Závěr: terén zůstává náš.** Generuje se to, co má siluetu a stojí samostatně — věže,
nepřátelé, dekorace. Zem, která musí lícovat na mřížku, ne.

`create_building_kit` na terasu **nepoužívat**. Vyzkoušeno 21. 8. 2026: na prompt
„side of a stone plateau" vrátil cihlové zdi, schody a sloupy, protože jeho úkolem jsou
místnosti. Sám to říká ve svém popisu: *„Not a terrain set: for grass-meets-water use
create_tiles_pro(tile_feature='tileset')."*

## 2. Premisa

Za soumrakem leží **Podměsíčí** a jeho obyvatelé si tě všimli. Neútočí. **Nabízejí.**
Platí třpytem, který je nádherný a do rána se promění v listí. Čím víc ho vezmeš, tím
míň ho cítíš — a tím víc ho potřebuješ.

Ty bráníš **oheň v krbu**. Dokud hoří, patříš sobě.

## 3. Rejstřík — čtyři pravidla, která se nesmí porušit

1. **Krásné a dravé, ne roztomilé.** Glamour musí být svůdný. Ve chvíli, kdy to sklouzne
   do pohádky pro pětileté, je hra o ničem.
2. **Fae nelžou a neubližují.** Nabízejí skutečné věci za skutečnou cenu a **cenu řeknou
   předem** — jen ne dost nahlas. Přesně jako to, o čem ta hra je.
3. **Metafora musí být izomorfní.** Každé jméno níž je odvozené z toho, co mechanika
   opravdu dělá. Když se objeví jméno, které je jen ozdoba, patří pryč.
4. **Žádný Tolkien.** Ne elfové, ne skřeti, ne meče a magie. Britský a irský venkovský
   folklor: bludičky, kruhy v trávě, sliby, mléko na prahu, Divoký hon.

## 4. Ekonomika a měřidla

| kód | dnes | nově | proč |
|---|---|---|---|
| `dopamine` | Dopamine | **Glimmer** | třpyt, kterým Fae platí. Do rána z něj je listí. |
| `focus` | Focus | **Hearth** | oheň v krbu. Zhasne a jsi jejich. |
| `tolerance` | Tolerance | **Dulling** | otupení. Víc třpytu za stejný pocit. |
| `insight` | Insight | **Lore** | co ses o nich dozvěděl. Zůstává mezi levely. |
| `bandwidth` | Bandwidth | **Vigil** | kolik hlídek uneseš najednou. Rezervuje se, neutrácí. |
| `rush` | Rush | **Fever** | z těsných zásahů. Měna paniky. |
| `streak` | Streak | **Oath** | slib. Dokud ho držíš, platí. Zlomíš ho a je pryč. |
| cue | modrý záblesk | **the Bell** | zvonek z lesa, který dřív vždycky znamenal dar. |

## 5. Deska

| kód | dnes | nově | poznámka |
|---|---|---|---|
| nízká zem | šedá hmota | **the Moor** | soumračná pláň. Fialová zůstává. |
| `path_cells` | dopaminová dráha | **the Trod** | **skutečný folklorní termín** — cesta, kterou Fae chodí, a na kterou se nesmí stavět. Naše `path_cells` jsou přesně tohle. |
| vysoká zem | myelin | **the Old Stone** | vztyčené kameny. Zeď i jediné místo, kam se dá stavět. |
| objective | jádro Focus | **the Hearth** | |
| spawn | spawn zóna | **the Ring** | kruh v trávě, kterým přicházejí. |
| Routine světlo | Routine | **lantern-light** | beze změny mechaniky, jen jména. |
| `fog` | Brain Fog | **the Mist** | |

Že se na Trod nesmí stavět, je pravé folklorní tabu — a v kódu už to tak funguje, protože
na cestě stavební místa nejsou. Poprvé bude fikce a pravidlo totéž.

## 6. Postavy

### Distrakce

| `id` | nově | folklor | mechanika, která to ospravedlňuje |
|---|---|---|---|
| `fomo` | **Wisp** | bludička | světlo, co tě svede ze stezky a **nedá ti nic**. `focus_damage = 0`, zmizí sama po 7 s. Dokonalá shoda. |
| `just_one_more` | **The Dance** | tanec, ze kterého se nedá odejít | po smrti se dělí na 2 kopie, 3 generace hluboko |
| `autoplay` | **Hollow Hill** | spánek pod kopcem | přežije 18 s a probudíš se o vlnu dál |
| `comparison` | **The Fetch** | tvůj dvojník, předzvěst smrti | ztvrdne proti tomu, do čeho jsi investoval nejvíc |
| `phantom_buzz` | **Namecaller** | hlas, co tě volá jménem z lesa | cítíš vibraci, která nebyla |
| `notification` | **Knocker** | klepání ve zdi | |
| `social_media_binge` | **The Revel** | slavnost, co netrvá jednu noc | |
| `clickbait` | **Promiser** | | slíbí a nedodá |
| `doomscroll` | **The Murmur** | | roj, ne jednotlivec |
| `group_chat` | **The Chorus** | | |
| `energy_drink` | **Bright Draught** | doušek, co hoří | |
| `jackpot` | **The Wager** | sázka s Fae | |
| `adult_content` | **The Fair One** | leanan sídhe — milenka, co inspiruje a vysává | drží se v náznaku |

### Návyky

Pomalé, obyčejné, lidské. Proti třpytu stojí věci, které vydrží do rána.

| `id` | nově | proč |
|---|---|---|
| `focus_timer` | **Bellringer** | odbíjí hodiny, pracuje v intervalech, musí si odpočinout |
| `mindfulness` | **Still Pool** | v klidné vodě je vidět |
| `exercise` | **Smith** | kovář, pomalý a těžký |
| `real_hobby` | **The Loom** | tkalcovský stav, něco skutečného vzniká |
| `accountability` | **Oathkeeper** | drží slib za tebe |
| `focus_pillar` | **Standing Stone** | |
| `zen_pulsar` | **Tidestone** | pulzuje jako příliv |
| `anchor` | **Lanternkeeper** | rozsvěcí Routine — už teď je to světlonoš |

### Nutrition Guild

**Zůstává, a nově sedí líp.** Zeleninoví obránci jsou **Hobs** — domácí skřítci
z britského folkloru, kteří pomáhají výměnou za mléko na prahu. Pomalí, věcní, tvoji.
Brokolicový rytíř je doma ve fae světě víc než v mozku.

## 7. Co art dědí a co se generuje znovu

**Dědí se paleta i hodnotová pásma** — mění se jen jejich jméno:

- zlatá `ffd479` = třpyt na Trodu (dřív dopaminová dráha)
- fialová tkáň = soumračná pláň
- krémová terasa = vztyčený kámen
- poměr vrch : světlá stěna : stínová stěna 100 : 70 : 45 platí dál, je to fyzika světla

**Generuje se znovu:** věže a nepřátelé. Tedy přesně to, co je dnes rozbité.

Zadání pro věže, které dřív chybělo: **vlastní hodnotové pásmo zřetelně pod terasou**
a brief proti **světlému** pozadí, ne tmavému. Věže stojí na nejsvětlejší ploše ve hře.

## 8. Insight karty — věda zůstává

Citace se nemění. Schultz 1997, Berridge & Robinson 1998, Fiorillo 2003, Volkow 2001,
Salamone, Shaham 2003, Kahneman & Tversky 1979 zůstávají přesně tak, jak jsou.

Mění se jediná věc: **za kartu přibude odhalení.** Odehrál jsi pohádku o bytostech, které
platí něčím, co se do rána změní v listí — a pak se dozvíš, že je to doložený
mechanismus.

Nejsilnější věta, kterou ta hra může říct, je tedy **„tohle nikdy nebyla metafora."**

Jídlo od Fae je to nejlepší, co jsi kdy jedl, a nenasytí tě. To je *wanting ≠ liking*
(Berridge & Robinson 1998) v jednom obrazu, šest set let před tou studií.

## 9. Návrhy jmen levelů

- level 98 „Morning Routine" → **First Light**
- level 99 „Iso Slice" → **The Trod**
- level půstu → **A Year Without a Gift**
- finále „The Feed" → **The Wild Hunt**

## 10. Čeho se vyvarovat

- roztomilosti (víly s křidélky, duhy, Disney)
- generické fantasy (elfové, skřeti, meče)
- toho, aby se folklor stal ozdobou — každé jméno musí být odvozené z mechaniky
- kázání; odhalení na kartě nesmí být obvinění
