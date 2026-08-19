# Sprite Studio — rozvržení

*Odvozeno z rozhraní PixelLabu, které uživatel používá a pracuje se mu s ním dobře.
Bereme z něj ZPŮSOB PRÁCE, ne kód. Co přidáváme navíc, je vždycky věc, kterou
PixelLab vědět nemůže: že buňka je 16 pixelů artu, že paleta má 48 barev a jak
sprite vypadá na téhle konkrétní mapě.*

---

## Co si bereme a proč to funguje

### 1. Karta má velikost podle spritu

V galerii PixelLabu je karta `32×32` malá a `256×256` zabírá tři řádky. Poměry
velikostí jsou vidět **v mřížce samotné**, bez měření a bez čtení popisků.

U nás to má ještě větší cenu: neshoda rastru (příšery ×2, země ×3, podlaha ×6) byla
neviditelná celé týdny. V galerii, kde karta odpovídá skutečné velikosti, by trčela.

Pod kartou: jméno · velikost · směry. Přesně tři údaje, nic víc.

### 2. Prompt je nahoře a je pořád vidět

Jedno široké pole se symbolem hůlky a tlačítkem **Vytvořit**. Ne panel, ne dialog,
ne schované pod tlačítkem. Nejčastější činnost má být první, co vidíš.

### 3. Osm směrů je pevná mřížka 4×2, i když jsou prázdné

```
South   South-East   East   North-East
North   North-West   West   South-West
```

Vyplněné ukazují sprite, prázdné přerušovaný rámeček s hůlkou (vygenerovat) a
ozubeným kolem (nastavit). **Vidíš, co máš, i co ti chybí** — bez rozklikávání.

Tohle je konkrétní případ obecného pravidla: *chybějící věc má být vidět stejně
dobře jako existující.*

### 4. Cena stojí nad tlačítkem

PixelLab píše „Costs 2 generations." My kredity nemáme, ale máme **čas**:

```
Retro Diffusion   ~2 s      lokální, zaplaceno jednou
lokální SDXL      ~40 s     lokální
PixelLab          ~2-4 min  spotřebuje generaci
```

Stejná funkce: víš, do čeho jdeš, dřív než na to sáhneš.

### 5. Každá volba má jednu řádku vysvětlení

Ne tooltip, ne otazník. Text pod ovládacím prvkem, drobným písmem. Uživatel se učí
a nemá si pamatovat, co dělá `strength`.

### 6. Nedostupné se neschovává, vysvětluje se

PixelLab nechá `Oblique Projection` vidět a přilepí cedulku `UNAVAILABLE`; u
Quadrupeda zašedne `v3`. Zmizelé tlačítko vypadá jako chyba. Zašedlé s důvodem učí.

### 7. Velikost: přednastavení a k tomu posuvník

Řada tlačítek pro běžné velikosti, posuvník pro cokoli jiného, aktuální hodnota
pořád vidět. Rychlé i přesné zároveň.

**U nás jsou přednastavení dané rastrem, ne libovolná:**

```
16×16   dlaždice · dekorace · hlava věže        1 buňka
32×32   příšera · obránce                       2 buňky
64×64   boss                                    4 buňky
16×8    dlaždice cesty                          půl buňky
```

Posuvník smí i jiná čísla, ale co nesedí na násobek nebo dělitel šestnácti, dostane
varování hned u pole — ne až při instalaci.

### 8. Stylová předloha je jedna z tvých věcí

`Style Character` v PixelLabu: vyber vlastní postavu a její osm směrů vede tu novou.
To je jejich odpověď na „jeden svět" a je dobrá.

U nás k tomu přidáváme druhou vrstvu, kterou oni mít nemůžou: **master paletu 48
barev** z `docs/art/palette_48.hex`. Model může styl minout; paleta ne.

### 9. Zkratky se píšou na obrazovku

PixelLab má v editoru UI napsáno „Alt+click to select a shape behind another.
Ctrl/Cmd+D to duplicate." Zkratka, o které se člověk nedozví, neexistuje.

Naše:

```
Enter        generovat
šipky        mezi kandidáty
mezerník     přehrát animaci
I            nainstalovat do hry
Esc          zavřít detail
```

### 10. Jména se upravují na místě

Tužtička u jména, ne dialog.

---

## Co přidáváme navíc

Tohle PixelLab nemá a mít nebude, protože nezná tuhle hru.

### Deska místo šachovnice

PixelLab kreslí sprite na průhlednou šachovnici. My ho kreslíme **na skutečnou
mapu** — terén, měřítko ×3, kontaktní stín, barevná záře, mřížka buněk, a vedle
něj tvor, který už ve hře je.

Sprite se nikdy nedívá sám. Šachovnice lže.

### Čísla přímo na kartě

Ne report, který se spouští. U každé karty drobně: barev, šumu, sedí rastr, má obrys.
Jako ukazatel života, ne jako zpráva.

### Instalace je brána

PixelLab má `Export` — stáhne soubor. My máme **do hry**, což znamená kontrolu:
rastr, paleta, obrys. Když něco nesedí, řekne to a nabídne opravu. Nic neprojde mlčky.

### Zpátečka

Snímek před každým zápisem do `assets/`. Bez ní se člověk bojí sáhnout na vlastní art
a to je nejhorší možný stav.

### Živý pruh při generování

Model posílá rozpracovaný obrázek po každém druhém kroku. PixelLab ukazuje jen
kolečko; my ukazujeme, jak sprite vzniká ze šumu, ve výsledné velikosti a s hotovými
dávkami vlevo. Není to ozdoba: **po pěti sekundách víš, jestli má smysl čekat**,
místo abys po půl minutě zjistil, že prompt minul.

Vlastní řádek mřížky, ne plovoucí vrstva — když se objeví, obsah se posune dolů
místo aby ho přikryl.

### Seznam úkolů

Aplikace už ví, co je špatně — terén je plochý, věže jsou mimo rastr, útoky mají
šestnáct snímků. Patří to na obrazovku, seřazené podle dopadu na pohled, ne do logu.

---

## Rozvržení

```
┌──────────────────────────────────────────────────────────────────────┐
│  Hra    Generátor    Knihovna    Úkoly ③        zdroj: [Retro ▾]    │
├──────────────────────────────────────────────────────────────────────┤
│  🪄  [ prompt ......................................... ]  Vytvořit  │
│      velikost [16][32][64] ── 32×32 · 2 buňky   síla ──●── 0,55      │
│      reference: [vyber z mého artu ▾]   režim: kompozice/paleta      │
├──────────────────────────────────────────────────────────────────────┤
│  ┌────┐ ┌──────┐ ┌────┐ ┌────┐                                       │
│  │16px│ │ 32px │ │32px│ │64px│    ← karta velká podle spritu         │
│  └────┘ └──────┘ └────┘ └────┘                                       │
│  16 bar. 34 bar!  ✓rastr  ✗rastr  ← čísla na kartě                   │
└──────────────────────────────────────────────────────────────────────┘
```

Detail spritu drží pořadí PixelLabu, protože je logické: **kdo to je → jaké má
stavy → jaké má animace**. My mezi identitu a stavy vsuneme **jak vypadá ve hře**.

---

## Co z toho zatím je a co není

Hotové: měření (`style_audit`, `score`, kontrola rastru), rodokmen, **výběr zdroje**
(bod 4 — cena v sekundách stojí nad tlačítkem, ~26 s proti ~240 s), **vysvětlení u každé
volby** (bod 5) u kvality, síly LoRA i zdroje, a **zpátečka** — každá instalace do
`assets/` si předtím udělá snímek přes `art_undo`.

Nehotové: karty podle velikosti spritu, mřížka osmi směrů s prázdnými sloty, čísla na
kartách, instalace jako brána, deska místo šachovnice, seznam úkolů.

Hotové jinde než v UI: `tools/board_preview.py` (deska) a `tools/art_undo.py` umí víc,
než z aplikace jde. Zapojená je z nich zatím jen zpátečka při instalaci.
