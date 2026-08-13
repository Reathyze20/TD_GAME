# Kreslení level artu v Inkscape

Návod od nuly. Předpokládá, že jsi Inkscape nikdy neotevřel.

Připravil jsem ti dvě šablony, takže nezačínáš na prázdném plátně — mají už správné
rozměry, mřížku, paletu hry a u atlasu i hotovou geometrii všech 16 dlaždic:

| Soubor | Co to je | Kam se to exportuje |
|---|---|---|
| [assets/src/high_ground_atlas_template.svg](../assets/src/high_ground_atlas_template.svg) | 192×192, 16 dlaždic po 48 px | `assets/terrain/high_ground_atlas.png` |
| [assets/src/background_template.svg](../assets/src/background_template.svg) | 1920×1080 s vyznačenými zónami | `assets/background.png` |

Ve složce `assets/src/` je i prázdný soubor `.gdignore`. Ten říká Godotu, ať tu složku
úplně ignoruje — jinak by ti SVG naimportoval jako textury a zaneřádil projekt
`.import` soubory. Zdrojáky nejsou herní assety.

---

## 1. Instalace

Stáhni Inkscape z **inkscape.org** (zdarma, otevřený zdroj). Verze 1.2 a novější.
Při instalaci nic speciálního nastavovat nemusíš.

---

## 2. Deset věcí, které v Inkscape opravdu potřebuješ

Nauč se tohle a zbytek programu můžeš ignorovat:

| Zkratka | Co dělá |
|---|---|
| `R` | nástroj obdélník |
| `E` | nástroj elipsa |
| `B` | pero — klikáním děláš lomenou čáru, tažením oblouky |
| `N` | editor uzlů — tahá body už nakreslené křivky |
| `S` | šipka, výběr a posun |
| `Ctrl+Shift+F` | Výplň a tah — barvy, průhlednost, rozostření |
| `Ctrl+Shift+L` | panel vrstev |
| `Ctrl+Shift+X` | XML editor — ukáže přesná čísla souřadnic |
| `Ctrl+D` | duplikovat |
| `Alt+D` | **klonovat** (viz trik v sekci 3 — tohle ti ušetří hodiny) |
| `%` | zapnout/vypnout přichytávání k mřížce |
| `1` / `5` | zoom 100 % / vejít celou stránku do okna |

Barvu nastavíš tak, že objekt vybereš a v `Ctrl+Shift+F` napíšeš hex do políčka RGBA
(např. `2d334aff` — posledních dvou znaků je průhlednost). V obou šablonách máš
vedle plátna vzorník palety hry, ze kterého můžeš barvy nakapátkovat klávesou `F7`.

---

## 3. High ground atlas

### Co v šabloně najdeš

Otevři `high_ground_atlas_template.svg`. Uvidíš mřížku 4×4, celkem 16 čtverců
po 48 px. Vpravo **mimo plátno** jsou popisky — ty se do exportu nedostanou,
protože exportuješ jen stránku.

Vrstvy (`Ctrl+Shift+L`):

- **1 povrch (kresli sem)** — 16 plných čtverců. Tady vzniká materiál plošiny.
- **2 hrany tmavé** — fazeta na spodních a pravých okrajích
- **3 hrany světlé** — fazeta na horních a levých okrajích
- **9 POPISKY** — zamčená, jen orientační

### Proč to má tuhle podobu

Každá dlaždice je **plný čtverec 48×48** a liší se jen tím, na kterých stranách má
fazetu. Fazeta je tam, kde plošina **nepokračuje** k sousedovi. Slot 0 (vlevo nahoře)
je osamocený blok se čtyřmi fazetami, slot 15 (vpravo dole) je vnitřek velké plošiny
a nemá fazetu žádnou.

Tohle už je v šabloně hotové a je to ta část, kterou by sis rozbil nejsnáz. Fazety
nech být, kde jsou — jen jim případně změň barvu.

### Trik, kvůli kterému to zvládneš za odpoledne

Nekresli 16 dlaždic. Nakresli **jednu** a zbytek naklonuj:

1. Zoomni na slot 15 (vpravo dole) — je bez fazet, takže vidíš čistý povrch.
2. Nakresli na něm materiál plošiny: pár žilek perem, jemné skvrny, cokoliv.
   Drž se palety.
3. Označ všechno, co jsi nakreslil, a dej `Ctrl+G` (seskupit).
4. `Alt+D` — vznikne **klon**. Klon není kopie: je to živý odkaz na originál.
   Posuň ho na jinou dlaždici.
5. Opakuj pro všech 16 pozic.

Pointa je v tom, že když pak upravíš originál, **všech 16 klonů se změní samo**.
Materiál tak autoruješ jedinkrát. S obyčejným `Ctrl+D` bys každou změnu dělal
šestnáctkrát.

Posouvat klony přesně o 48 px: `Shift+Ctrl+M` (Transformace) → záložka Posun →
Relativní posun → Vodorovně `48`, Použít. Nikdy netahej myší, rozjede se ti to o pixel.

### Past, do které spadneš

**Nekresli detail přes okraj buňky.** Ve hře spolu sousedí různé dlaždice a v místě,
kde se stýkají, musí povrch navazovat. Žilka, která vede přes hranici čtverce, vytvoří
ve hře viditelný zlom.

Praktické pravidlo: **drž detail v prostředních 36×36 px** a vnějších ~6 px nech
klidných. Na otevřených stranách je stejně překryje fazeta.

### Export

1. `Ctrl+Shift+E` otevře export panel.
2. Nahoře vyber **Stránka** (ne Výběr, ne Kresba — Výběr by ti ořízl plátno podle
   toho, co máš zrovna označené).
3. Zkontroluj, že Šířka a Výška ukazují **192 × 192**. Když ne, přepiš je ručně.
4. Formát **PNG**.
5. Cesta: `assets/terrain/high_ground_atlas.png` — **přepiš stávající soubor**.
6. Export.

Těch 192×192 je jediné číslo, které musí sedět přesně. TileSet očekává dlaždice po
48 px a čtyři sloupce — jakákoliv jiná velikost a dlaždice budou přerostlé nebo useknuté.

---

## 4. Background

### Co v šabloně najdeš

Otevři `background_template.svg`. Barevné pruhy nejsou dekorace, ale mapa toho, co
ve hře kde bude:

- **červeně nahoře (0–68 px)** — HUD lišta, tvůj art tam nebude vidět
- **červeně dole (984–1080 px)** — spodní lišta, totéž
- **modrozeleně (68–980 px)** — hrací plocha, 40×19 buněk po 48 px
- **žlutě uprostřed** — klidová zóna. Sem **nedávej detail**: tady chodí nepřátelé
  a stojí věže, art by je překřikoval. Detail patří ke krajům a do rohů.

Mřížka po 48 px je zapnutá, takže vidíš přesně, kde jsou buňky.

### Jak k tomu přistoupit

Background má být **tichý**. Není to obraz, je to podklad. Tři vrstvy stačí:

1. Základní tmavá plocha (už tam je, `#0a0c14`).
2. Pár velkých, sotva viditelných tvarů — záhyby tkáně. Použij barvu `#161b2c`
   nebo `#262c40` a v `Ctrl+Shift+F` jim dej **průhlednost kolem 30–50 %**.
3. Tenké svítící linky (`#7ef2e6`), taky ztlumené na ~20 %. Pár jich stačí, tři čtyři.
   Pro záři jim dej v `Ctrl+Shift+F` **Rozostření 1–2 %** — víc ne, na 1920 px je
   i jedno procento hodně.

Když si nejsi jistý, jestli je to dost tiché: je. Chyba se dělá vždycky směrem
k příliš výraznému pozadí.

### Export

1. **Nejdřív skryj vrstvu „9 ZÓNY"** (`Ctrl+Shift+L`, klikni na ikonu oka).
   Tahle vrstva je uvnitř plátna, takže by se ti jinak vyexportovala i s těmi
   barevnými pruhy. Tohle je nejčastější chyba.
2. `Ctrl+Shift+E` → **Stránka** → **1920 × 1080** → PNG.
3. Ulož jako `assets/background.png`.

### Pozor na jeden detail v kódu

[game.gd:134](../scripts/game.gd#L134) hledá **nejdřív** `background.jpg` a teprve
když neexistuje, sáhne po `background.png`:

```gdscript
var bg_path := "res://assets/background.jpg"
if not FileAccess.file_exists(bg_path):
    bg_path = "res://assets/background.png"
```

V projektu ten `.jpg` zatím je. Dokud ho nepřejmenuješ nebo nesmažeš, tvoje nové
pozadí se nenačte a ty budeš hledat chybu ve špatném místě. Přejmenuj ho třeba na
`background_old.jpg.bak`.

---

## 5. Ověření v Godotu

1. Přepni se do Godotu. Reimport proběhne sám, jakmile okno dostane fokus.
2. Otevři `scenes/MapEditor.tscn` a spusť ji (`F6`).
3. Namaluj kus terénu — hlavně **plnou plochu aspoň 3×3 buňky**. Tím ověříš rohy
   a vnitřek naráz. Pak zkus osamocenou buňku a jednu dlouhou zeď.
4. Kdyby ti někde v ploše vznikla díra nebo zlom, znamená to, že se rozjelo pořadí
   slotů v atlasu. Rozložení je popsané v [ART_PROMPTS.md](ART_PROMPTS.md) v sekci 6
   a v [build_terrain_tileset.gd:20](../tools/build_terrain_tileset.gd#L20).

Kdyby ti hrany vyšly rozmazané, je to filtrování textur — projekt nemá nastavené
`rendering/textures/canvas_textures/default_texture_filter`, takže jede na výchozím
lineárním. Přepnutím na Nearest dostaneš ostré pixely.

---

## 6. Doporučené pořadí

Nedělej obojí naráz. Atlas je důležitější a rychlejší:

1. **Atlas, jen barvy.** Otevři šablonu, změň tři barvy povrchu a fazet, vyexportuj,
   podívej se na to ve hře. Zabere to deset minut a naučí tě celý cyklus
   export → Godot → kontrola, aniž bys cokoliv kreslil.
2. **Atlas, materiál.** Teprve teď kresli povrch na slotu 15 a klonuj.
3. **Background.** Až budeš vědět, jak plošiny vypadají, protože pozadí se ladí
   proti nim, ne naopak.

Ten první krok fakt nepřeskakuj. Vědět, že ti cesta ze souboru do hry funguje,
je víc než hezká první dlaždice.
