# Tilesety: PixelLab → Aseprite → hra

## Jedno číslo si pamatuj: **16**

Herní buňka je 48 px. PixelLab nabízí velikost dlaždice 16, 32 nebo 64 — a **jedině 16 dělí
48 beze zbytku** (16 × 3 = 48). Při 32 nebo 64 by se dlaždice musela zvětšovat necelým číslem
a pixel art se rozmaže i s nearest filtrem.

Když si v PixelLabu nastavíš 16, všechno ostatní už dopadne samo.

## Tři kroky

**1. Vygeneruj v Aseprite.** `Pixel Lab → Generate tileset (pro)`. Nastav:

| Pole | Hodnota | Proč |
|---|---|---|
| Tile size | **16** | jediné dělí 48 beze zbytku |
| View | **High top-down** | odpovídá tomu, jak hra kreslí |
| Wall style | **Ledge** | viz past níž |
| Raggedness | 20–30 | 0 = geometricky čisté, 100 = roztřepené |
| Slope | nízko | vysoký svah ukusuje z plochy dlaždice |
| Lower terrain | podlaha — po čem se chodí | |
| Upper terrain | zeď — kudy se nedá projít | |

### Past: Wall style

`Hill` a `Cliff` mají hloubku 0,5 a 1,0 — obojí přes práh 0,4, při kterém PixelLab vyrobí
**plátno dvojnásobné výšky** (8×16 místo 8×8). Export „Tileset 15" pak nevyjde jako čtverec
a instalace ho odmítne. Drž se **Ledge** (0,25) nebo **Flat** (0,0).

Ledge je stejně to, co chceš — nízká římsa se stěnou u spodní hrany. Přesně ta plasticita,
kdy horní okraj vypadá dál než spodní.

### Jak psát popisy

Piš **anglicky** — model je na tom trénovaný a česky si vymýšlí.

Tři pravidla, každé vykoupené jedním nepovedeným pokusem:

1. **Jiný materiál, ne jiná varianta téhož.** „Soft tissue" a „soft membrane" skončily jednou
   šedou kaší, protože to je popis téhož. Kámen vs. tkáň, kov vs. látka, kost vs. sliz.
2. **Řekni světlost natvrdo.** Přidej `dark` / `pale` / `clearly lighter than the floor`.
   Když to nenapíšeš, vyjdou oba terény v půltónu a mapa nemá hloubku.
3. **Podlaha musí být nudná.** Je jí 60 % obrazovky. Napiš `matte`, `muted`, `low contrast`,
   `almost plain`. Detailní podlaha spolkne nepřátele.

Tři páry k vyzkoušení:

| | Lower terrain (podlaha) | Upper terrain (zeď) |
|---|---|---|
| **Mysl v klidu** | `dark navy blue smooth membrane, matte, very subtle texture, almost plain` | `pale grey bone-like ridged plates, chalky, clearly lighter than the floor` |
| **Přetížená mysl** | `deep charcoal surface with faint dim circuit lines, muted, low contrast` | `stacked cracked concrete slabs, warm light grey, dusty` |
| **Neuronová** | `dark violet tissue, smooth, barely visible fibers, matte` | `pale pink coral bone ridges, dry and chalky, much lighter than the floor` |

Pole **Transition (optional)** můžeš nechat prázdné. Když ho vyplníš, popisuje pruh, kde
podlaha přechází ve zeď — třeba `thin dark rim` nebo `mossy crumbling edge`.

**Seed** si zapiš, když se něco povede. Se stejným seedem a stejným popisem dostaneš totéž;
při změně jednoho slova se změní jen to slovo, ne celá sada.

**2. Vyexportuj do mřížky.** To, co po generování vidíš na plátně, **není** sada dlaždic —
je to 8×8 kousků poskládaných do souvislé mapy, aby bylo vidět, že na sebe navazují. Proto to
vypadá jako beztvarý ostrov. Uložit tohle přes `File → Save As` je nejsnazší omyl v celém
postupu (skript ti to naštěstí pozná a vynadá).

Správná cesta:

```
Edit → PixelLab → Open plugin → Map >  →  Create tileset (pro)
```

Ten dialog **je ten samý, ve kterém jsi generoval** — otevře se s tvým popisem, jak jsi ho
nechal. Sjeď úplně dolů. Pořadí prvků je:

```
[ ] Advanced options
[ Export as tileset ]      <-- tohle
[ Generate ] [ Reset ] [ Cancel ]
```

**Export as tileset sedí hned nad Generate**, proto se dá přehlédnout. Na Generate neklikej,
generoval bys znovu a zaplatil za to.

**Target Layout je jedno** — „Tileset 15", „Tileset Wang" i „Tileset 3x3" projdou. Skript
si pořadí přečte z obrázku, ne z tabulky (viz níž). Ulož jako PNG.

Export bere **aktivní sprite**, takže než klikneš, ujisti se, že máš navrchu záložku
s vygenerovaným tilesetem, ne nějaký jiný obrázek.

### Alternativní dlaždice se zachovávají

Když list obsahuje **víc dlaždic se stejným napojením** (ručně dokreslené variace), skript
je poskládá do vrstev atlasu — blok 4×4 na vrstvu — a hra si na každé buňce jednu vylosuje.
Dlouhá zeď pak neopakuje tutéž texturu. Masky s méně variantami opakují svou první, takže
nemusíš kreslit variantu ke každé. Kontrolní mapa i editor varianty losují taky.

### Jak skript pozná, co je která dlaždice

Nečte to z tabulky rozložení — u každé dlaždice ohledá čtyři rohy a spočítá masku. Proto je
jedno, jaký layout vybereš, a funguje to i na list, který si nakreslíš ručně.

Dvě věci, které to dělají spolehlivým:

**Práh jasu se nehádá, ale hledá.** Projede se celý rozsah a vezme se ten, při kterém vyjde
všech šestnáct kombinací rohů právě jednou. To je zároveň kontrola — kdyby to rohy četlo
špatně, nějaká kombinace by chyběla nebo se objevila dvakrát a skript to řekne.

**Převis stěny se počítá jako podlaha.** Ta svislá stěna u spodní hrany zdi se maluje přes
území sousední dlaždice, kde ve skutečnosti je podlaha. Jasem leží mezi oběma materiály, takže
naivní rozdělení v půlce ji hodí ke zdi a rozbije čtení. Proto práh končí blízko tmavé strany
(u naší sady vyšel na 97 při rozsahu 55–217).

Když je zeď **světlejší** než podlaha, přidej `--svetla-zed`. Skript vypíše, jak se rozhodl.

Přemalovat si dlaždice můžeš kdykoliv — buď na plátně před exportem, nebo pak přes
`tiles.py uprav` / `zpet`.

**3. Nainstaluj do hry.**

```
python tools/tiles.py instaluj tileset.png
```

Skript přepíše atlas, dogeneruje z podlahové dlaždice pozadí pole, zazálohuje předchozí verzi
a vykreslí **kontrolní mapu** do `assets/src/pixel/_kontrola_mapy.png`. Otevři ji. Jestli na sebe
zdi navazují a rohy sedí, je hotovo — jdi do Godotu, `Project → Reload Current Project`,
a stav levely v editoru.

## Ostatní příkazy

```
python tools/tiles.py instaluj cesty.png --cesty   # dlaždice cest
python tools/tiles.py uprav                        # atlas ze hry → sešit 64×64 pro Aseprite
python tools/tiles.py zpet                         # upravený sešit → zpátky do hry
python tools/tiles.py nahled                       # jen překreslit kontrolní mapu
```

`uprav` / `zpet` je cesta pro případ, že chceš sáhnout na atlas, který už ve hře je, a nemáš
po ruce původní PixelLab plátno. Edituje se v **nativních 16 px**, ne ve zvětšenině — kdybys
maloval do zvětšeného, každý tah by měl trojnásobné pixely a nebyla by cesta zpátky.
**Neměň velikost plátna.**

## Cesty nejsou napojovací sada

Hra si pro každou buňku cesty **vylosuje jednu dlaždici náhodně**. Takže každá musí dávat smysl
sama o sobě a navazovat na kteroukoliv jinou. **Stačí čtyři variace**, šestnáct je luxus.
Skript bere pořadí, ve kterém jsou — buď mřížka 4×4, nebo vodorovný pruh.

Cesta musí být od podlahy poznat na první pohled. Když je podlaha tlumená, cesta je jasnější
a hustší; nebo naopak. Stejný odstín s jiným vzorkem se ve hře ztratí.

## Hierarchie: 60 / 30 / 10

Nejčastější důvod, proč mapa vypadá špatně, není kresba jedné dlaždice, ale to, že si všechno
kolem sebe konkuruje:

- **60 % podlaha** — tlumená, málo detailu, málo kontrastu. Podklad, ne obraz.
- **30 % cesty a stavební místa** — jasně čitelné linky.
- **10 % akcenty** — nepřátelé, střely, efekty. Tohle jediné smí „svítit".

Náš dosavadní atlas tohle porušoval měřitelně: 92 barev v šestnácti dlaždicích a **nejsvětlejší
pixely v celé scéně byly na vrcholcích zdí**, ne na nepřátelích. Terén si vzal akcent, který
patří hráčově pozornosti.

Ruční pixel art si vystačí s 8–24 barvami na celou sadu. Když jich má sada 90, není to bohatší,
jen rozmazanější.

## Co se ještě nesrovnalo

Až bude nový 16px tileset v hře, přehodí se **rekvizity** (`scripts/decor_layer.gd`, `ZOOM`)
z ×2 na ×3, aby měly stejně velký pixel jako terén. Věže už ×3 jsou. Nepřátelé jsou kresleni
na 32 px a měřítko si počítají z poloměru — ty přijdou na řadu naposledy.

## Když se něco pokazí

Atlas se zálohuje ve dvou generacích: `high_ground_atlas.png.bak` a `.bak2`. Jedna záloha
nestačí — druhý běh by ji přepsal už tou rozbitou verzí. Přesně tak se v tomhle projektu
jednou přišlo o mapu.
