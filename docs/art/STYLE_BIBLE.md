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

> **Soustředění je tkáň. Distrakce je patogen. Návyk je buňka, která tkáň brání.**

Předchozí kolo mělo „soustředění je tma a ticho, distrakce světlo a hluk, návyk je něco,
co si nad tím postavíš“ — a *postavíš* z toho udělalo architekturu (keramická terasa,
zdivo). Top-down deska nemá výšku, kterou by architektura mohla ukázat, takže ta metafora
tady nemá co nést. Nahrazuje ji **imunologie**: nic se nestaví, všechno je živé.
Návyk není stroj přišroubovaný na tkáň, je to tkáň, která přerostla.

## 1. Vizuální jazyk — organická neurální tkáň

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
| Habits | gliové buňky — kulaté, teplé, obalující | tělo tmavé, akcent svítí | tělo ~300, akcent 300+ | podle color v .tres | ano |
| Distractions | patogeny — ostré, jedovaté, cizí | syté, jasné | 200+ | podle color v .tres | ne |
| Dopamine | synaptický váček — kapka nabitá k prasknutí | teplá jantarová | 300+ | teplá 30–50° | ano |

<!-- /gen:vocabulary -->

Dvě věci na téhle tabulce nejsou vkus:

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

| | Habits (gliové buňky) | Distractions (patogeny) |
|---|---|---|
| obrys siluety | kulatý, uzavřený, souvislý | ostrý, zubatý, roztřepený |
| směr tvarů | dovnitř, obalující, sedící | ven, bodající, valící se vpřed |
| zóna palety | teplá polovina (jantar, zlatá, oranžová, teal) | studená a jedovatá (magenta, violet, kyselá zelená, ledová azurová) |
| silueta v černé | poznat kruh nebo hrozen kruhů | poznat hrot, trn nebo cíp |

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

Praktický důsledek pro prompt: tvarová slova („round", „closed", „nested" vs. „barbed",
„jagged", „hooked") nesou víc než barevná a mají v popisu stát dřív. Barva se pojmenovává
slovem a zbytek dodělá `color_image_url` (§7).

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
| defender | 32 | 64 | 2 | rozhodl uživatel 29. 8. 2026 — `gen_px` stejně jako habity |
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

## 6. Style anchor — jeden na celý projekt

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

## 7. Povinný suffix

Jde do **`description` každého promptu**, doslova, na konci, oddělený `; `. Testuje se
přesná shoda — nepřepisuj ho v generátoru, přepiš ho tady.

<!-- gen:suffix -->

```suffix
organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

<!-- /gen:suffix -->

A k němu jeden pevný `negative_description`:

<!-- gen:negative -->

```negative
photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature
```

<!-- /gen:negative -->

**Paleta se nevynucuje slovy, ale obrázkem.** Prompt nesmí obsahovat žádný hex ani vlastní
seznam barev; paleta jde přes `color_image_url` na `docs/art/palette_48.png` (48 barev,
celý projekt z ní čerpá). `palette_32.hex` v repu existuje, ale **měřitelně škodí 6 z 10
příšer a nesmí se objevit nikde v žádném promptu ani parametru.** Barvy se v promptu
pojmenovávají slovem („amber“, „indigo“, „teal“) — slovo generátor posune do palety, hex
mu dá záminku vyrobit si vlastní.

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
| 0 | Focus core a jeden habit | focus_core, id:focus_timer | ZASTAVIT A NECHAT ROZHODNOUT UŽIVATELE. Povinný krok je popsaný pod tabulkou fáze v plánu; bez jeho schválení se negeneruje ani jeden další kus rejstříku. K tomu technicky: obojí stojí na ploché zdi (TOP, 484) a dotýká se jí — mezi spodkem obsahu a začátkem stínu není ani řádek holé zdi — a tělo neleží do +-60 jasu od podkladu. |
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

1. Vygeneruj **jen** ty dva kusy, které fáze 0 vyjmenovává. Nic víc.
2. Ke každému vyrob **kontaktní list se dvěma verzemi vedle sebe**: sprite v `gen_px`
   tak, jak přišel z generátoru, a týž sprite po downsamplu na `art_px`. Obojí v herním
   měřítku, tedy zvětšené `Data.pixel_scale()`, na plochém terénu z `flat_terrain.py` —
   ne na bílém pozadí. Snímek dělej v **1920×1080**, jinak výřezy minou
   (`iso_bible.md` §2e).
3. **Předlož to uživateli a počkej.** Otázka zní: je downsample přijatelný?
4. Do schválení se **negeneruje ani jeden další kus rejstříku**. Ne polovina, ne „jen
   ještě jeden na porovnání" — nic.

**Pozor, tenhle krok dnes u obou entit fáze 0 neměří to, co má.** `focus_core` má
`gen_px` 96 a `art_px` 96; `focus_timer` má 64 a 64. U obou je tedy **downsample žádný**
a obě verze kontaktního listu vyjdou identické. Downsample, na který se ta otázka ptá,
reálně nastává jen u postav — obránci a distrakce se generují na 64 a půlí na 32, boss
128 → 64.

Jsou dvě cesty, jak to spravit, obě na jeden řádek v tomhle souboru, a je to
**rozhodnutí uživatele**, ne moje:

- **přidat do fáze 0 jednu postavu** — nabízí se `id:broccoli_knight`, protože je to
  zároveň kotva a kořen rodiny obránců, takže vzniknout musí stejně první. Cena +20
  generací a brána začne měřit skutečný downsample 64 → 32.
- **nebo dát `focus_core` `gen_px` 192** a půlit na 96. Cenu to nezmění vůbec (nad 64 px
  je to `pro_velky` = 40 tak jako tak) a odpovídá to obecnému pravidlu „generuj na
  dvojnásobku a půl přesně jednou“ víc než dnešní 96 → 96.

Do rozhodnutí zůstává fáze 0 přesně tak, jak byla zadaná — dva kusy, žádná postava —
a krok 2 se u nich odbývá tím, že obě verze budou stejné. Zbytek brány (dotyk podkladu,
jas proti zdi) měří dál a smysl má.

<!-- /gen:gate0 -->

## 11. Co se nepřebírá z izo bible

- **Poměr vrch : levý bok : pravý bok 100 : 70 : 45** — top-down deska žádné boky nemá.
  Světlo shora zůstává, ale nese ho stínování uvnitř siluety, ne tři stěny.
- **Diamantová geometrie, `WALL_HEIGHT`, terasový kit** — bezpředmětné.
- **Kontaktní stín jako 2:1 elipsa** (squash 0.5) — v top-down je to kruh, squash 1.0.

Co se přebírá beze změny: plochý terén bez textury (§2b), „generátor dodává materiál, kód
dodává geometrii“ (§5), zákaz linky po dlaždici, a pravidlo, že se rastr **měří ze
souboru, ne čte z parametru** (§4).
