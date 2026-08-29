# PIXELLAB.md — jak v tomhle projektu volat PixelLab

Ověřeno 14. 8. 2026 proti živému serveru. Tenhle soubor je **referenční API povrch**;
výtvarná pravidla (co kreslit a proč) jsou v `ART_PIPELINE.md` a `ART_DIRECTION.md`.

---

## 0. Jak neplýtvat kredity (vymáháno kódem, ne kázní)

Znalosti o tom, kde mizí generace, byly v tomhle souboru rozeseté po kapitolách — a
dokumentace, kterou musíš mít v hlavě, nikoho neochrání. Od 18. 8. 2026 to hlídá
`tools/pixellab.py`.

```bash
python tools/pixellab.py new "<prompt>" --name "Broccoli Knight"   # 1 generace
python tools/pixellab.py check <id>                                # 0 generací — BRÁNA
python tools/pixellab.py anim <id>                                 # 4 generace
python tools/pixellab.py ucet                                      # co se utratilo
```

**Postava stojí 1 generaci, animace čtyři.** Chůze je 1 generace na směr (jih, sever,
východ), smrt jednu. Proto je mezi `new` a `anim` brána: `anim` **odmítne** postavu, která
neprošla přes `check`. Není to buzerace — je to nejdražší způsob, jak přijít o kredity:
špatný základ tě stojí čtyři generace naráz, ne jednu.

`check` nerozhoduje za tebe. Stáhne rotace, oznámkuje je stejným měřítkem jako lokální
generátor a **udělá kontaktní list, na který se musíš podívat**. Verdikt zapíše do účtu.

Co se vymáhá automaticky:

| past | co s tím dělá kód |
|---|---|
| nad 64 px si animace zvolí režim `pro` = **20–40 generací na směr** | posílá `mode:"v3"` natvrdo a upozorní |
| západ si hra zrcadlí sama | není ve výchozích směrech; když ho vynutíš, ozve se |
| jedenáctý souběžný job se vrátí **jako text, ne jako chyba** | přečte `list_jobs` a raději nezadá |
| zaplatíš podruhé za totéž | účet v `build/pixellab/_ucet.json` |

Před každým utracením se to zeptá; `--yes` to přeskočí, `--dry` ukáže, co by se poslalo,
a nepošle nic.

**Prompty ber z `tools/prompt_assist.py`.** Drží pětiblokovou strukturu ve dvou podobách
z jednoho zdroje: `PIXELLAB_TEMPLATES` je plná (sem sahej při zadávání do PixelLabu),
`RULE_TEMPLATES` krátká pro lokální náhled — ta se **musí** vejít do 77 tokenů CLIPu.
Dřív se nevešla o 43 až 89 tokenů a náhledy tiše vznikaly z půlky promptu.

---

## 1. Přístup — a co dělat, když nástroje nejsou v session

MCP server je v lokálním configu:

```
claude mcp list                 # pixellab: https://api.pixellab.ai/mcp (HTTP) - Connected
claude mcp get pixellab         # vypíše i hlavičku Authorization: Bearer <token>
```

**Častý stav: server je „Connected", ale nástroje `mcp__pixellab__*` v session nejsou.**
Pak nepomůže hledat je znovu — je potřeba buď restart Claude Code, nebo **přímý MCP klient**.
Ten je otestovaný a je to standardní cesta v tomhle projektu.

Streamable-HTTP MCP se mluví takhle (plná funkční implementace: `mcp.py` ve scratchpadu):

1. `POST` na `https://api.pixellab.ai/mcp`, hlavičky:
   - `Content-Type: application/json`
   - `Accept: application/json, text/event-stream`
   - `Authorization: Bearer <token>`
   - `MCP-Protocol-Version: 2025-06-18`
2. `initialize` → v odpovědi přijde hlavička **`Mcp-Session-Id`**, kterou musíš posílat dál.
3. `notifications/initialized` (bez `id`, je to notifikace).
4. `tools/list`, pak `tools/call` s `{"name": ..., "arguments": {...}}`.

Odpověď je buď čisté JSON, nebo **SSE** (řádky `data: {...}`) — parser musí umět obojí.
Výsledek nástroje bývá jeden textový blok, ne strukturovaný JSON; čti `result.content[0].text`.

**Pasti prostředí (Windows):**
- Konzole je cp1250 → `PYTHONIOENCODING=utf-8`, jinak `UnicodeEncodeError` na šipkách a emoji.
- Token nikdy nedávej do souboru v repu. Scratchpad session ano, repo ne.

---

## 2. Ověřená volání

Server hlásí **68 nástrojů**. Tohle jsou ta, která reálně používáme.

### `create_image_pixflux` — pozadí, volné obrázky, img2img

| parametr | pozn. |
|---|---|
| `description` | jediný povinný |
| `width`, `height` | **16–400 px na stranu**, plocha min. 32×32. Bez init obrazu default 128 |
| `init_image_url` | https **nebo `data:` URL** — funguje a je to preferovaná cesta |
| `init_image_base64` | alternativa; musí být přesně `width`×`height` |
| `init_image_strength` | **obrácená logika: vyšší = víc se zachová.** 500 skoro nezmění, 300 jemná úprava, 150 default = skutečný zásah, ~50 nechá jen kompozici |
| `color_image_url` | PNG, ze kterého se přečtou **jen barvy** → vynucená paleta. Libovolná velikost |
| `view` | `side` / `low top-down` / `high top-down` (slabé vodítko) |
| `no_background` | `False` pro scény a pozadí, `True` pro sprity |
| `text_guidance_scale` | default 8, nižší = volnější |
| `seed` | reprodukovatelnost |

Cena 1 generace, hotovo do ~30 s.

### `get_image` — vyzvednutí výsledku

**Parametr se jmenuje `job_id`, NE `image_id`** (na tom se to zaseklo; `image_id` hodí
validation error). Vrací text:

```
status: completed
id: <uuid>
frames: 1
download: https://api.pixellab.ai/mcp/images/<uuid>/download
```

**Download URL nekončí na `.png`** — regex hledající `\.png` ji mine. A vyžaduje
`Authorization` hlavičku:

```bash
curl -sSL -H "Authorization: Bearer $TOK" -o out.png \
  "https://api.pixellab.ai/mcp/images/<uuid>/download"
```

U starších/backblaze URL platí: **stahuj curlem, ne python urllib** (urllib dostane 403
kvůli user-agentu).

### Tilesety

- `create_tiles_pro` — `tile_type` (`square_topdown`, hex, isometric, oblique, octagon),
  `tile_size` 16–128 (32 doporučeno), `tile_feature: "tileset"` pro rohové přechody,
  `outline_mode`. Vyzvedává se `get_tiles_pro(tile_id=...)` — **`tile_id`, ne `tiles_id`**.
  Popis dvou terénů se píše číslovaně: `"1). vyvýšený terén 2). podlaha"`, a **nastavený
  bit = PRVNÍ terén**. `outline_mode: "segmentation"` je lepší než default `"outline"` —
  nedělá kolem každé dlaždice vlastní tmavý obrys, který by poskládaný kreslil mřížku.
- `create_topdown_tileset` — `lower_description`, `upper_description`, `tile_size` 16/32
  (64 jen s `mode: "pro"`), `transition_size` 0 / 0.25 / 0.5 / 1.0, `mode`.
  Umí zaoblené rohy, což `tiles_pro` neumí. ~100 s.

#### Rohový tileset → atlas hry: tři pasti (ověřeno 14. 8. 2026)

1. **Maska je bitově obrácená.** PixelLab vrací `NW<<3 | NE<<2 | SW<<1 | SE`,
   `game.gd` používá `bit1=NW, 2=NE, 4=SW, 8=SE`. Převod:
   ```python
   def game_to_pl(m):
       return ((8 if m & 1 else 0) | (4 if m & 2 else 0)
             | (2 if m & 4 else 0) | (1 if m & 8 else 0))
   ```
   Polaritu (co je zeď a co podlaha) si i tak ověř z pixelů: dlaždice masky 15 musí být
   celá terén 1, maska 0 celá terén 2. Kontrola průměrným jasem stačí.
2. **Nějaká maska může chybět.** V našem běhu přišel `tile_13` s maskou 8 (duplikát) a
   maska 13 chyběla úplně. Dá se dopočítat zrcadlením: horizontální zrcadlo prohodí
   NW↔NE a SW↔SE, takže `mask 13 = mirror(mask 14)`.
3. **Prázdno je NEPRŮHLEDNÉ a musí se vyklíčovat.** Dlaždice masky 0 je plná plochá
   barva podlahy (u nás `#0D0D1A`). Kdyby se nasadila tak, jak je, slot 0 by položil
   souvislou desku přes celou vrstvu cesty. Vyklíčuj tu barvu na alfu 0 ve **všech**
   dlaždicích s tolerancí ~10.

Skládání do `high_ground_atlas.png`: 4 sloupce × 4 řádky na variantu, `x = m % 4`,
`y = variant * 4 + m / 4`. Hra si počet variant odvodí z výšky (`height / 192`).
Varianty se dělají překlopením **jen symetrických slotů** (0 a 15) — překlopení okrajové
dlaždice změní, které rohy nárokuje, a rozbije napojení. Slot 15 je zároveň ten, který
se na dlouhé zdi opakuje nejčastěji, takže právě jeho varianty jsou vidět.

Jednotlivé dlaždice se občas nestáhnou (nám vypadl zrovna `tile_15`, ten nejdůležitější).
Po stažení vždy zkontroluj počet souborů a chybějící dotáhni znovu.

#### Post-processing atlasu je POVINNÝ (jinak zeď vypadá jako hradby)

Syrový výstup z generátoru se poskládat nedá. Skript: `build_atlas.py` ve scratchpadu.

1. **Srovnat rovné hrany na pevnou linku.** Generátor kreslí každou dlaždici jako
   samostatný zaoblený tvar, takže horní hranice `m=12` jde třeba 33 → 27 → **24** →
   27 → 33. Poskládáno po 48 px z toho vzniknou cimbuří. Masky s rovnou hranou jsou
   `3` (jižní), `12` (severní), `5` (východní), `10` (západní) a musí se osekat/dolít
   na **sdílenou půlku dlaždice** (`T/2`, resp. `T/2−1`). Pozor: linka musí být stejná
   pro **všechny varianty** — počítat ji per dlaždici (modus) nestačí, každá sada
   zaobluje jinak a varianty se pak o sebe zasekávají do schodů.
2. **Osekat vnitřní jiskry.** Dlaždice plného vnitřku (`m=15`) má pár výrazně světlých
   pixelů; ty se opakují každých 48 px a kreslí viditelnou mřížku. Ořež opakní pixely
   na `medián + ~55`.
3. **Přemalovat lem z alfy, ne nechat ten od generátoru.** Projdi opakní pixely: má-li
   pixel nad sebou průhledný → severní hrana → světlý lem; má-li průhledný pod sebou →
   jižní hrana → ztmavit (~0,55×). Okraj dlaždice se **nepočítá** jako hranice (nad
   `y=0` může ve složené mapě ležet další zeď). Tím zmizí komiksový obrys po bocích
   a světlo začne chodit shora.
4. **Srovnat jas mezi sadami.** Nezávisle vygenerované sady mají různý medián
   (naměřeno 133 / 141 / 163). Bez normalizace na společnou hodnotu vznikne z náhodně
   losovaných variant patchwork se svislými švy — horší než původní mřížka.

**Varianty musí být OPRAVDU jiné kresby.** Zrcadlení a překlopení téže dlaždice nestačí:
salientní shluk zůstane a oko si ho najde. Vygeneruj 2–3 nezávislé sady (různý `seed`)
a udělej z každé jednu variantu.

#### Podlaha: dva pooly a shluky, ne posyp

> **Stav k 14. 8. 2026: akcenty jsou vypnuté.** Výtvarné rozhodnutí — podlaha má být
> úplně tichá, aby nesla jen zdi, jednotky a jádro. Soubory leží v
> `assets/src/pixel/path_accents/`; zapnou se zkopírováním zpátky do
> `assets/terrain/path/`, kód se nemění (prázdný pool se přeskočí sám).
> Zbytek téhle sekce popisuje, jak to funguje, až je budeš chtít vrátit.

Dlaždice podlahy jsou rozdělené **podle názvu souboru**: `path_*.png` je klidná podlaha,
`accent_*.png` nese synapsi. `_build_path_layer` je klade různě:

- klidná podlaha rovnoměrně do všech buněk,
- akcenty v **pramíncích** — `ACCENT_SHARE` (0,06) buněk rozdělených do vláken
  po `ACCENT_STRAND` (4) buňkách, které se náhodně plazí po mřížce.

**Rovnoměrné losování z jednoho společného poolu nefunguje**, i když je poměr nízký.
Uniformní rozptyl jasných značek čte jako konfety a pole působí rušivě při jakémkoli
podílu, protože v reálném prostoru nic není rovnoměrně rozmístěné. `decor_layer.gd`
se to naučil dřív a seje hromádky; vrstva cest posypávala dál. **6 % ve shlucích
působí výrazně klidněji než 10 % rozptýlených**, při stejném počtu pixelů.

Jas: akcent podlahy musí zůstat **pod lemem zdi** (dnes 396), jinak podlaha přebíjí
terén. Aktuální strop je 285. Akcentní značky se přenášejí **jen jako kresba** na
sjednocený klidný podklad — sady mají různě světlé pozadí a bez toho by akcentní
dlaždice svítily celou plochou. Kompaktní zářící tvary (tečka, jiskra) se tlumí víc
než vláknité, jinak čtou jako sbíratelný objekt, ne jako scenérie.

`tools/stylized_renderer.gd` musí stejnou logiku i stejné konstanty kopírovat,
jinak náhled v editoru vypadá rušivěji než hra.

### `get_balance`

```
generations_remaining: 1494 / 2000    subscription: Tier 1
```

Kvóta se počítá po generacích, ne po volání — `create_tiles_pro` stojí 20–40.

---

## 3. Raster — spočítej to, nevěř dokumentaci

**Herní pole je 1920×912 px**, ne 1920×1080. Plyne to z `data.gd`:
40 sloupců × 19 řádků × 48 px = 1920×912, počátek `origin_y = 68` pod HUDem.

Pozadí se kreslí `draw_texture_rect(bg, Rect2(0, 68, 1920, 912))`, takže **autorská
velikost musí dělit 1920×912 celým číslem**, jinak se pixely rozmažou:

| autorská velikost | zvětšení | pozn. |
|---|---|---|
| 640×304 | ×3 | sedí na raster věží a terénu |
| 480×228 | ×4 | |
| **320×152** | **×6** | **jediná, co se vejde do limitu PixelLabu 400 px** |
| ~~384×216~~ | ~~×5~~ | **CHYBA v starším ART_PIPELINE.md** — 216×5 = 1080 ≠ 912 |

Proto se pozadí generuje ve **320×152**. Hrubší pixel než terén (6 vs 3) je přijatelný
a v tomhle projektu zamýšlený — pozadí má ustoupit dozadu.

### Nutná oprava v kódu

`Game` kreslí pozadí přes `draw_texture_rect` **na sobě**, a uzel nemá nastavený filtr.
`path_layer` a `terrain_layer` NEAREST mají, `Game` ne — takže nízké rozlišení pozadí
by se vyhladilo do rozmazané kaše. Před nasazením malého pozadí je potřeba v `game.gd`
v `_ready`:

```gdscript
texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
```

Dokud bylo pozadí 1920×1080 (tj. ≈1:1), tahle chyba nebyla vidět.

---

## 4. Osvědčený postup na pozadí (img2img přes vlastní kompozici)

Nejlepší výsledky nedává čistý text-to-image, ale **vlastní strukturovaný init obraz**:

1. Vygeneruj procedurálně (PIL) podklad 320×152, kde máš pod kontrolou to, co model
   neumí: rozložení hodnot, odpočinkové plochy, hustotu clusterů, kompozici vláken.
   Skript: `floor.py` ve scratchpadu.
2. Postav malý PNG s paletou (stačí pás pixelů) a pošli ho jako `color_image_url` —
   tím se zamkne paleta a model neuteče do teplých tónů.
3. Zavolej `create_image_pixflux` s `init_image_url` (data URL) a porovnej
   `init_image_strength` **200 / 155 / 110**:
   - 200 = drží tvoji kompozici, přidá řemeslo (velké klidné plochy zůstanou)
   - 110 = přemaluje to po svém, hustší tkáň, míň místa na odpočinek
   - ~155 = kompromis
4. Vyzvedni přes `get_image(job_id=...)`, stáhni curlem s hlavičkou.

**Promptové lekce (platí i tady):** referenční obrázek přebije text; slova „tile"/„grid"
plodí mřížky; „faint / subtle / pale" doslova vyrobí prázdný obrázek — sparseness se
řídí init obrazem a formulacemi typu „large empty dark areas", ne slovem „subtle".

---

## 5. Cizí koncept art → herní nepřítel (ověřeno 14. 8. 2026)

Když přijde kresba zvenčí (Midjourney apod.), platí tenhle řetěz. Každý krok existuje
proto, že ten přímější selhal.

```
koncept 1024²  →  ořez na bytost  →  pixflux img2img 64×64 (strength 300)
               →  animate_image (chůze 8, smrt 8)  →  halve() 64→32  →  32×32 do hry
```

(Když by se někdy vracelo na 16px art, poslední krok je `tools/sprite_16.py` — viz níže,
proč to není obyčejné zmenšení.)

1. **Ořez.** Bublina/stín/kouř kolem bytosti se musí vyříznout — jinak z nich generátor
   dělá šum. Největší souvislá komponenta = bytost, ale **nejdřív zaplň díry**: srst,
   která se barevně trefí do pozadí, prorazí tělo skrz naskrz a ty díry by se vymazaly
   na pozadí (tmavé krátery uprostřed spritu). Pozadí odhaduj **po řádcích** z okrajů —
   je to gradient, takže jedna vzorkovaná barva označí půl obrázku za bytost.
2. **`create_image_pixflux` s `init_image_url`.** Init **musí mít přesně `width`×`height`**,
   jinak přijde (levná, hned) chyba. Zmenši si ho sám; LANCZOS, ne nearest — předloha je
   malba, ne pixel art. `init_image_strength` **300** drží kresbu; 200 už uteklo do
   zeleného blobu, 160 nakreslilo něco jiného.
3. **`animate_image`** je **jediný animátor, který funguje na volném spritu.**
   `animate_object` i `animate_character` chtějí `object_id` něčeho, co vyrobil PixelLab,
   a importovaný obrázek objektem není. Bere `first_frame_url` (i `data:`), max 256 px,
   `frame_count` sudý. Vrací **frame_count + 1** snímků, index 0 je tvůj vstup;
   stahují se z `…/download?index=N`.
4. **Zmenšení na 16 px řeší `tools/sprite_16.py`**, ne resampling — viz níže.

**Popis smrti musí pojmenovat, co se stane s hlavním znakem.** „collapsing and bursting
apart" nechalo tělo osm snímků stát. Teprve „single huge eye cracking and going dark,
body splitting apart, fragments flying outward" dalo animaci orientační bod.

### Pasti

- **Pod 32×32 se generovat nedá** (`16x16 is too small (256px, minimum is 32x32 = 1024px)`).
  Herní sprity mají 16 px, takže poslední půlení je vždycky na nás.
- **Souběžně běží max 8 jobů.** Devátý se vrátí jako normální výsledek s textem
  `error: rate limit exceeded (8/8 jobs)` — ne jako chyba protokolu. Kdo to nekontroluje,
  tiše přijde o půlku dávky.
- **`color_image_url` se váží plochou.** Pruh palety spočítaný z celého ořezu vyšuměl do
  šedi: dominuje pozadí a tmavá srst, růžové oko je pár pixelů a median-cut ho zahodí.
  Buď paletu skládej ručně z barev, na kterých ti záleží, nebo ji nepoužívej vůbec
  a drž barvu vysokou `init_image_strength`.

### Proč se 16 px nedá zmenšit (a `tools/sprite_16.py`)

Změřeno na téhle bytosti: **64 → 16 nedá použitelný výsledek žádným filtrem.**
NEAREST vybírá jeden náhodný pixel z bloku (oko tam je, nebo není, podle štěstí),
BOX udrží siluetu a rozmaže oko po celé hlavě, výběr nejčastější barvy oko **smaže** —
ve vlastním bloku 2×2 je menšinové. **64 → 32 dvojnásobným krokem je naopak čisté.**

Proto se 16px snímek **kreslí**: silueta z pokrytí, čtyřstupňová rampa v dominantním
odstínu srsti, a **akcent se položí ručně** (min. 2×2, uprostřed nalezené kompaktní
skvrny). Na 16×16 se vejde tvar, čtyři hodnoty a **jeden** světlý znak — a který pixel
je ten znak, filtr rozhodnout neumí.

Detaily, které se musí dodržet (všechny stály jeden pokus):

- **Rampa i barva akcentu se počítají z jednoho referenčního snímku a sdílí je celá
  animace** — včetně smrti. Per snímek se tělo přebarvuje a oko bliká růžová/žlutá/červená.
  Vstupní snímek chůze a smrti je nominálně tentýž obrázek, ale generátor ho překóduje
  per job a u jedné varianty to stačilo přehodit dominantní odstín.
- **Rampa má jeden odstín z nejčetnějšího koše**, ne barvu vzorkovanou na percentilech
  jasu — nejsvětlejší nesytné pixely jsou tady béžové boule na břiše, takže z fialové
  příšery vyšla hnědá srst.
- **Z rampy vyřaď lem i akcent.** Koncept má magentu obtaženou kolem celé siluety;
  ponechána se stane nejvyšším stupněm rampy a sprite je celý pokropený růžovou.
- **Akcent hledej tvarem, ne sytostí.** Lem má stejný odstín jako oko. Kandidáti se
  filtrují na kompaktní skvrnu (výplň bboxu ≥ 0,35, bbox < 60 % spritu) a odstín
  v magenta–červeném oblouku dostane bonus, jinak vyhraje malé jantarové druhé oko.
- **Barva akcentu = nejsytější pixel, ne nejsvětlejší.** Nejsvětlejší je bílý odlesk na
  oční bulvě a jeho dosycení udělá z magentového oka jantarové.
- **Prahy rampy řež podle rozdělení blokových průměrů**, ne podle pixelů zdroje —
  průměrování bloku zvedne jeho nejtmavší pixel a celá bytost vyjde bledá.
- **Osamělé pixely zahoď.** Anténa nebo chuchvalec srsti = jeden pixel = špína na obraze.
- **Smrt na 16 px dokresli rozpadem.** Praskající oko generátor zvládne, ale tělo zůstane
  do posledního snímku celistvé a bytost působí, že zamrzla. Poslední čtyři snímky se
  ujídají shora dolů (hlava první, nohy poslední).

## 5b. Věže a chůze — co se naučilo 14. 8. 2026 večer

### Init obrázek zvětšuj LANCZOS, ne NEAREST

Když dáváš pixflux/`animate_image` jako init existující malý sprite, **zvětši ho měkkým
filtrem**. Nearest dá modelu ostrohranné bloky a on je jen obkreslí — změřeno na věžích:
`init_image_strength 300` nad nearest initem vrátilo obrázek skoro pixelově shodný se
zdrojem, žádné nové stínování. LANCZOS dá přechody, do kterých má co domalovat.

`init_image_strength` **210** je u ikon ten kompromis: 300 = beze změny, 130 = jiný design
(přesýpací hodiny zežloutly na dřevo), 210 = přibyla geometrie a identita zůstala.

### Když model sklouzne k jednoduššímu tvaru, řekni mu co to NENÍ

`head_accountability` (krystalový shluk) vycházel opakovaně jako krychle/dárková krabice.
Zabralo teprve `irregular jagged crystal cluster with several pointed shards, NOT a cube,
NOT a box`. Negativní vymezení tvaru funguje líp než další přídavná jména.

### Rozlišení věží: 24 px

`tower.gd` fituje hlavu i podstavec do buňky přes `zoom = floor(48 / tex_width)`, takže
**16px art ×3 i 24px art ×2 vyjdou na stejných 48 px** — mění se jen hustota pixelů.
24 px drží poměr umělecký:obrazovkový pixel 1:2 stejně jako nepřátelé (32px art ×2).
PixelLab negeneruje pod 32×32, takže se generuje na **48×48** a pak jednou `halve()`.
Instalace: `tools/install_towers.py`.

### Bokorys existujícího spritu: `create_character` mode v3

**Když si hráč stěžuje, že potvory „chodí pozadu", nejdřív zkontroluj, jestli vůbec mají
směrový art.** Animátor kreslí jižní sadu jako fallback pro všechny směry, takže potvora
jdoucí doleva a doprava vypadá identicky — a půlka davu se tváří, že couvá.

`create_character` s `mode:"v3"` a `reference_image_url` **otočí existující sprite do
8 směrů za 1 generaci** (~9 min). Je to jediná cesta, jak dostat bokorys z hotové kresby;
`create_1_direction_object` a spol. kreslí novou věc, netočí tvoji.

```python
mcp.call('create_character', {
    'description': '...', 'name': '...', 'mode': 'v3', 'n_directions': 8,
    'reference_image_url': data_url(sprite_64px),   # max 256 px
    'view': 'low top-down'})                        # klasické 3/4 RPG
```

- Status hlásí **`creating`**, ne `processing` — poller, který čeká jen na `processing`,
  propadne a vypíše 0 %.
- Rotace se stahují z **backblaze URL** (bez `Authorization`), ne z `api.pixellab.ai`.
- Ověř si orientaci z pixelů, ne z názvu: u nás vyšlo `east` = oko vpravo (x 44,8 z 64),
  `west` = vlevo (23,1). Sedí to na herní konvenci EAST = doprava.
- **Jižní rotace vyšla pixelově shodná se zdrojem** (medián 263 vs 263), ale
  **otočené pohledy ujedou**: východ +8 % jasu, západ +19 %, odstín o 0,05–0,08 do růžova.
  Bez srovnání potvora při zatáčení zbledne. Řeší `sprite_16.match_to_reference()`.
- Chůzi na bokorys pak udělej běžným `animate_image` z rotace east. Vyšel nejlepší poměr
  nohou ze všeho dneška (1,43) — v bokorysu jsou nohy prostě vidět líp než zepředu.
- **Západ nemusíš generovat** — `distraction_animator.gd` zrcadlí východní sadu sám.

### POZOR: metrika pohybu měří změnu pixelů, ne chůzi

**Tohle mě podvedlo, počítej s tím.** Notifikační příšery měly skóre 10,7–11,6 — vyšší než
`group_chat` (6,18), který jsem podle stejného čísla „opravoval". Přesto stály na místě.
Celé to skóre dělalo **oko, které blikalo mezi růžovou, bílou a hnědou**, ne lokomoce.

Samotné číslo tedy nestačí. Doplň ho o:

1. **Poměr dolní/horní půlky snímku.** Nohy jsou dole; když je změna soustředěná nahoře,
   bytost mává, ale nekráčí. Po opravě: varianty 1,17 / 0,79 / 1,26 / 1,07.
   ```python
   d = np.mean([np.abs(a[i]-a[(i+1) % n]) for i in range(n)], axis=0).mean(axis=(1,2))
   ratio = d[len(d)//2:].mean() / d[:len(d)//2].mean()
   ```
2. **Stabilitu akcentu přes snímky** (odstín i sytost přes `find_accent`). Kolísání = strobo,
   ne animace — a je to přesně to, co skóre nafoukne.
3. **Nakonec vždycky oko na kontaktním listu.** Tyhle dvě čísla jsou pomůcka, ne rozsudek.

**A pozor na druhý směr omylu:** u jedné varianty sytost oka kolísala 0,66–0,98 a vypadalo
to jako vada — jenže ta bytost má **hnědě lemované oko už ve zdrojovém konceptu**. Než
začneš opravovat, porovnej se zdrojovým spritem. Utratil jsem tři generace a jeden
zbytečný post-process, než jsem se podíval.

### Animaci chůze si ověř číslem, ne okem

Sady vyrobené přes `animate_object` často vyjdou jako **idle, ne chůze** — osm snímků
téže pózy. Měř střední rozdíl sousedních snímků:

```python
d = [np.abs(a[i] - a[(i+1) % n]).mean() for i in range(n)]
```

Naměřeno: `group_chat` south **1,64** (= stojí na místě) proti 10–11 u notifikací
animovaných přes `animate_image`. **Pod ~7 je to podezřelé, pod ~4 je to nehybné.**
Oprava je přeanimovat přes `animate_image` s popisem, který **pojmenuje nohy**:
`"walking forward toward the viewer, legs stepping, body bobbing up and down"`.
Po opravě: group_chat 1,64 → 6,18, doomscroll 4,89 → 9,46, group_chat_b 5,78 → 9,69.

**Pohledy zezadu (`_north`) se zlepšit nedaří** — adult_content 4,15 → 4,02,
autoplay 5,66 → 5,51. Tělo zezadu je velká statická plocha a nohy je pár pixelů, takže
číslo zůstane nízké, i když nohy reálně kráčejí. U zadních pohledů se řiď okem.

### `animate_image` má taky strop 8 souběžných jobů

Není to jen limit `create_image_pixflux`. Devátý požadavek se vrátí jako **normální
textová odpověď** `error: rate limit exceeded (8/8 jobs)`, ne jako chyba protokolu —
a taky **výsledky si stahuj hned**, joby se po dokončení drží jen 8 hodin a viděli jsme
i dřívější zmizení (`job ... not found`) při delší prodlevě.

## 5c. Přední stěna zdi (3/4 pohled) — 15. 8. 2026

**Nezadávej generátoru, aby vyextrudoval stěnu uvnitř dlaždice.** Tak to selhalo minule:
vršek a stěna se na 16 art pixelech nevejdou vedle sebe, vyjde dvoubarevný pruh a vršek
zhubne. Stěna je **samostatná textura**, geometrii kreslí kód do buňky pod zdí.

Autorská velikost 16×8 art px = 48×24 na obrazovce. Generuje se ale na **48×24**
(plocha 1152 > minimum 1024, obě strany ≥ 16) a zmenšuje ×3 — jeden art pixel tak zůstane
blok 3×3 jako všude jinde ve světě.

Prompt drží materiál mapy (nervová tkáň), **ne kámen** — slova `stone` / `rock` /
`concrete` jsou ta, co kdysi vyrobila béžovou skálu (§ART_PROMPTS). Klíčové fráze:
`vertical cliff face cross-section`, `horizontal strata layers`, `downward hanging fibers`,
`lit from above`, `seamless left to right`, `flat side view, no perspective`,
**`shadow tones shift toward cool blue/violet, never a flat black falloff`** — bez
téhle fráze generátor stín jen ztmaví do černé (změřeno: `terrain/path/*.png` 2–4°
posunu odstínu proti cíli 20°+, viz `style_bible_measured.md` §2). Stejná fráze patří i do
popisu podlahy (`lower_description`) o pár řádků výš.

### Postprocess je povinný (`tools/build_wall_face.py`)

1. **Srovnat jas na tělo zdi.** Syrový výstup měl 300–400 sum(RGB) proti mediánu zdi 144 —
   stěna by byla světlejší než plocha, ze které visí. Cíl je `FACE_LEVEL` × medián zdi;
   **0,88 je nasazené**, 0,70 zkoušeno a je moc tmavé (svislá kresba zmizí a čte to jako
   pouhý stín). Musí zůstat nad podlahou (77), jinak zeď plave na tmavém pruhu.
2. **Vynutit světlo shora.** Generátor to v promptu slíbí a nedodrží — jedna varianta měla
   světlo u paty a vypadala nasvícená zespodu. Ramp `1,10 → 0,72` shora dolů.
3. **Horní hranu namalovat, ne vzít z generátoru.** Stejný důvod jako u lemu atlasu:
   ponechána generátoru se jedna varianta trefila do lemové barvy atlasu (sum 396) po celé
   šířce a četla jako neonový pásek. Pevný násobek mediánu (`LIP_LEVEL` 1,55) dá každé
   variantě stejný ostrý zlom.
4. **Snap na paletu zdi.** Barvy se berou ze slotu 15 atlasu, takže stěna nemůže do světa
   vnést nový materiál.
5. **Wrap-blend bočních sloupců.** Každá buňka si losuje vlastní variantu, takže švy jsou
   všude. Když se každá dlaždice srovná sama se sebou, sedne pak na kteroukoli jinou.

### Co musí sedět v kódu

`Game.WALL_FACE_H` (24) a `WallShadow.face_h` — **stín začíná až pod stěnou**, jinak leží
přes ni. A `tools/stylized_renderer.gd` musí kopírovat i volbu varianty podle buňky,
jinak náhled v editoru ukáže jiný rozpis stěn než hra.

## 5d. Hotová postava z webu → nepřítel ve hře (ověřeno 15. 8. 2026)

Když příšeru vyrobí uživatel v prohlížeči, přijde jen URL
`pixellab.ai/create-character/<uuid>` — a to `<uuid>` **je** `character_id`. Celý zbytek
jede přes `animate_character`, žádný `create_character` už není potřeba.

```
get_character  →  animate_character (template ×2)  →  stáhnout snímky  →  halve() 64→32
               →  assets/distractions/<id>[_b][_north|_east|_death]_frame_N.png
```

1. **`animate_character` v template režimu stojí 1 generaci na směr.** Dvě volání na
   postavu: `sad-walk` s `directions:["south","north","east"]` a `falling-back-death`
   s `directions:["south"]` — smrt je ve hře jen jedna sada, `_load_death_frames()` směr
   nečte. Celkem **4 generace na příšeru**, hotovo do ~4 minut.
2. `animation_name` si nastav sám (`junk_walk` / `junk_death`) — podle něj se pak snímky
   v odpovědi hledají. Bez něj se skupina jmenuje po šabloně.
3. **Snímky nejsou v žádném strukturovaném poli.** `get_character` je vrací jako text:
   `  <animation_name> — 3 dir (...)` a pod tím `    <direction>: url, url, …`.
   Parsuje se to regexem (`fetch_anim.py` ve scratchpadu). URL jsou **backblaze**, takže
   `Authorization` nepotřebují — ale curl ano, urllib dostane 403.
4. Chůze vrací **8 snímků**, `falling-back-death` **7**. Index 0 je první snímek animace
   (u smrti ještě stojící postava), pořadí je tedy rovnou pořadí `_frame_1..N`.
5. **`sprite_16.halve(im, 32)` je celý downscale.** 64px výstup po zmenšení drží siluetu
   i magentové oko; ruční 16px kreslení (§5) tady není potřeba, protože cíl je 32 px.
6. Metriky z §5b po půlení klesnou zhruba o 15 % — měř je na **půlených** snímcích, jinak
   porovnáváš jiná čísla než ta v §5b. Naměřeno na clickbaitu: chůze south 7,0 / 10,7,
   east 9,0 / 7,7, north 5,2 / 6,8 (sever je nízký vždycky), smrt 14,2 / 19,7.

**Šablony vyšly na první pokus jako skutečná chůze**, žádné idle — to je proti
`animate_object` (§5b) zásadní rozdíl a je to důvod, proč u rodiny příšer jedeme přes
`create_character` + `animate_character` a ne přes volné sprity.

### Když animace vyrobil uživatel ve webu (ověřeno 15. 8. 2026)

Postavy, které si uživatel naklikal sám, přijdou s animacemi, které tvůj skript nečekal.
Tři věci, které tiše zkazí stažení:

- **Jméno skupiny může být celá věta.** Vlastní (v3) animace se jmenuje třeba
  `custom-64x64 pixel art 8-direction running animation. The`. Regex `\s{2}(\S+) — `
  na takový řádek nesedne, parser zůstane u předchozí skupiny a **všechny směry se uloží
  pod cizí jméno** (u nás skončila celá chůze ve složce `junk_death`). Ber `(.+?) — \d+ dir`.
- **Jeden směr se ve skupině může opakovat.** Přišlo `6 dir (south, south, north, south,
  north, east)` — tři pokusy o jih. Bez počítadla se všechny zapíšou do stejné složky
  a **zůstane poslední**, tedy ne nutně ten dobrý. U nás byly jižní sady 8,06 / 8,41 / 3,36
  (poslední = stojí na místě).
- **Snímků nemusí být 8.** Vlastní animace měly 16. `SPRITE_FPS` je pevných 12, takže
  16snímkový cyklus trvá dvakrát déle, potvora ujede stejnou vzdálenost a **měsíčkuje**.
  Ber každý druhý snímek (`[::2]`), ne celou sadu.

### Automatizace celého rosteru (ověřeno 17. 8. 2026 na deseti příšerách)

Pět pastí, které stály čas při hromadném přegenerování distrakcí:

- **Limit je 10 souběžných jobů, natvrdo.** Jedenáctý spadne na
  `error: need 1 job slots but only 0 available (10/10 used)` — a vrátí to jako *text
  odpovědi*, ne jako výjimku, takže si toho skript nemusí všimnout. Před každým zadáním
  čti `list_jobs` a odečítej: chůze na tři směry = 3 sloty, smrt = 1, attack = 1.
- **Skupina se jmenuje podle `animation_name`, ne podle šablony.** Zadáš
  `template_animation_id:"sad-walk"` + `animation_name:"td_walk"` a `get_character` ukáže
  `td_walk — 3 dir (…) [type=sad-walk]`. Hledat skupinu podle slugu šablony nikdy nesedne.
- **Nad 64 px si `animate_character` sám zvolí `pro` režim** (20–40 generací/směr), i když
  jsi poslal jen `action_description`. U bosse (128 px) se tak spustil pro job, který nikdo
  nechtěl. Posílej **`mode:"v3"` explicitně**, kdykoli je postava větší než 64.
- **Cache stahování musí být klíčovaná URL, ne logickým jménem.** Když se příšera
  pregeneruje jako v2 a cache je pod `<id>_<smer>_<i>.png`, vrátí se snímky v1 a na disk
  se zapíše stará podoba, zatímco na PixelLabu je nová. Tvářilo se to jako selhání
  generátoru; byla to cache. Ber `sha1(url bez query)`.
- **Maž až ve chvíli, kdy máš čím nahradit.** První verze instalátoru nejdřív smazala
  `<id>*_frame_*.png` a teprve pak zjišťovala, co zapíše — u tří příšer smazala všechno
  a nezapsala nic. Nejdřív najdi sady, pak teprve `cleanup()`.

A `failed jobs` v `get_character` čti — jeden směr se může nepovést (u automatu vypadl
sever) a v seznamu animací pak prostě není, aniž by cokoli zahlásilo chybu.
`Generation failed: Worker hiccup, please try again` je přesně to, co říká: stejné volání
znovu (klidně pod stejným `animation_name`) prošlo napodruhé beze změny čehokoli. Selhaný
záznam ve `failed jobs` zůstane i po úspěšném retry — čti ho jako historii, ne jako stav;
o stavu vypovídá jen seznam `animations`.

## 6. Kam to patří

```
assets/background.png                  320×152, engine zvětší ×6 (pozor: .jpg by vyhrál nad .png)
assets/terrain/high_ground_atlas.png    192×(192×N), 4×4 slotů po 48 px na variantu
assets/terrain/path/path_NN.png         16×16 podlaha, ×3; počet souborů = váha varianty
assets/terrain/face/face_NN.png         16×8 přední stěna zdi (3/4), ×3; smazat = plochý pohled
assets/decor/*.png                      16×16, kresleno ×3
assets/distractions/<id>_frame_N.png    32×32 chůze, hra kreslí ×2 (64 px na obrazovce)
assets/distractions/<id>_death_frame_N.png  32×32 smrt, přehraje se jednou
assets/distractions/social_media_binge* 64×64 (boss) → 128 px na obrazovce
```

**Velikost bestiáře, rozhodnuto 14. 8. 2026 večer:** hra jede na 32px artu (běžný
nepřítel 64 px na obrazovce, 4/3 buňky; boss dvojnásobek). 16px verze žila půl dne —
na 32 obrazovkových pixelech nepřežila srst ani zuby, kvůli kterým ty potvory stojí
za pohled. `tools/sprite_16.py` v repu zůstává: umí `halve()` (jediné důvěryhodné
půlení 64→32) a celý 16px pipeline pro případ návratu. 32px originály všeho jsou
v `assets/src/pixel/distractions32/`.

**Po každé výměně PNG na disku spusť `--headless --import`.** Běh scény bez editoru
reimport neudělá a hra mlčky kreslí staré textury z cache — vypadá to přesně jako
„změna se neprojevila".

**FX kolem těla ber z `_visual_radius()`, ne z `def.radius`** (`distraction_animator.gd`):
art je teď širší než hitbox a kruh dimenzovaný z radiusu skončí schovaný pod spritem —
štít, který si boss nese pod vlastní srstí, nikomu nic neoznámí.

**Varianty nepřátel jdou jen přes název souboru.** `<id>_frame_N.png` je varianta 0,
`<id>_b_…`, `_c_`, `_d_` se přidají samy (`VARIANT_SUFFIXES` v `distraction_animator.gd`);
každá instance si losuje vlastní a **smrt dědí variantu chůze**. Žádná registrace v kódu.
Notifikace tak dnes fielduje čtyři různé bytosti z jednoho konceptu.

`high_ground_corner_atlas.png` se navzdory názvu **nepoužívá** — `CORNER_ATLAS_PATH`
v `game.gd` míří na `high_ground_atlas.png`.

Vrstvy pole mají pevné `z_index` (`game.gd`): pozadí −40, cesta −30, stín zdí −25,
terén −20, dekorace −10, jednotky 0. Pozadí **nesmí** zpátky do `Game._draw()` — vlastní
`_draw()` uzlu kreslí na jeho `z_index` a zakrylo by všechny záporné vrstvy pod sebou.

### Poznámka ke GDScriptu

`for dx in (-1, 1):` je **parse error** — GDScript nemá tuple literály, patří tam
`for dx in [-1, 1]:`. Chyba se hlásí jako „Expected closing ')' after grouping expression".

## 5e. Věže na 32 px + mechanická animace (Zen Pulsar, 16. 8. 2026)

### Strop 24 px padl — hlava smí přesahovat buňku

§5b tvrdilo, že věže mají 24 px, protože `zoom = floor(48 / tex_width)` a 32px art by
spadl na ×1 (jeden art pixel na jeden obrazovkový = zakázané). To byl důsledek
**zaklínění hlavy do buňky**, ne nutnost. Nepřátelé se do buňky nikdy nevešli — 32px art
kreslí na 64 px, tedy 4/3 buňky.

`tower.gd` má teď `HEAD_ART_SPAN := 2.0` a hlava kreslí **vždy ×2**, ať měří cokoli:

| art | dřív (`floor(48/w)`) | teď (×2) |
|---|---|---|
| 16 px | ×3 → 48 px | ×2 → 32 px ⚠ |
| **24 px** | **×2 → 48 px** | **×2 → 48 px** (beze změny) |
| **32 px** | ×1 → 32 px, hustota 1:1 ⚠ | **×2 → 64 px, přesah 8 px** |

Všechny hlavy v repu jsou 24px, takže je změna zpětně kompatibilní. **Kdyby se někdy
vracel 16px art, tenhle vzorec ho zmenší** — 16px hlavy se musí zvětšit, ne obejít.

Nové hlavy: generovat **64×64** → `sprite_16.halve(im, 32)`.

### Větvící se upgrade linie rozbila fallback na art

`_head_art_key()` dělal `type_key.trim_suffix("_2")`, což fungovalo jen dokud každá linie
měla přesně jeden upgrade `<root>_2`. Zen Pulsar má dva (`_2a` / `_2b`), trim je nechal
beze změny → hlava bez artu. Opraveno na **`Data.habit_family(type_key)`**, což chodí po
skutečných `upgrades` hranách a zvládne libovolnou hloubku i větvení.

### `animate_image` tuhle animaci neudrží — a proč to nevadí

Nabíjecí cyklus (kameny se rozjedou, secvaknou) selhal třikrát:

1. **Vstup byl 24px snímek zvětšený zpátky na 48.** Model dostal mush a překreslil věž na
   **oranžového panáčka**. Lekce: `animate_image` krmit **nativním rozlišením**, nikdy ne
   zvětšeným downscalem. (§5b říká zvětšovat LANCZOS u *pixfluxu*; tady je to jinak —
   pixflux z init obrazu maluje, animátor z něj odvozuje pohyb a mush ho pustí od zdroje.)
2. **Nativní 48px + `last_frame_url` s ručně poskládanou rozevřenou pózou** siluetu udržel
   a je to obecně **ten trik na mechanický pohyb**: rozřež zdroj na pásy, posuň je, pošli
   jako koncovou pózu. Ale poslední třetina snímků stejně roztekla kámen do žluté kaše.
3. **Rozevřít víc (`growth` 6 místo 3) je nezlepšilo** — oranžová jen sežrala kámen.

Řešení je **`tools/pulse_anim.py`**: posouvá pásy *zdrojových pixelů*, negeneruje nic.
Kámen se nemůže rozpadnout, smyčka sedí na pixel, paleta neuteče. Je to stejný princip
jako `build_wall_atlas.py` — **post-processuj to, co generátor neudrží**.

Dvě pasti, obě stály jeden pokus:

- **Neease-uj float a nezaokrouhluj ho na pixel.** `round(6 * t**0.75)` vyrobilo dva
  identické snímky uprostřed nabíjení = viditelné škubnutí při `HEAD_FPS = 8`. Kroky se
  píšou explicitně (`GROWTH_STEPS`), monotónně, a jediná prodleva patří na vrchol.
- **Headroom neměř jen podle prázdných řádků.** Zúžená špička (krystal) je pár pixelů na
  řádek a utratit ji je přesně to, co kupuje pohyb; přísný clamp srazil růst 5 → 2 px a
  animace zplihla (metrika 8,9 → 5,0). Rozpočet = prázdné řádky **+ vedoucí řádky pod
  ~15 % nejširšího**.

### Animace vázaná na cooldown místo na wall-clock

`HEAD_FPS` je pevných 8, takže smyčka hlavy běží nezávisle na střelbě — u věže, která
střílí jednou za 4 s, by to čtlo jako nesmysl. `HabitData.charge_telegraph` přepne hlavu
na `_advance_charge_anim()`: snímek = postup přebíjení, takže **sprite JE odpočet**.

Pozor: `cooldown` jde do **záporu**, dokud nabitá věž čeká na cíl (resetuje se jen při
skutečném výstřelu). Bez `clampf` se index přetočí zpátky na výbojový snímek a věž vypadá,
že pálí do prázdna.

## 5f. Tome of Focus — druhý druh pohybu, a proč zase ne generátorem (16. 8. 2026)

Kniha (`real_hobby` / `real_hobby_2`) nahradila bonsaj. Statika vyšla napoprvé dobře;
zajímavé je zase jen to, co selhalo na animaci.

### Izometrie, ne bokorys

Otevřená kniha z boku je klín — stránky, celá identita, zmizí. `view: "high top-down"`
je jediný pohled, ve kterém jsou na 32 px čitelné obě stránky i hřbet.

### img2img neumí eskalovat tier

Tier 2 přes `init_image_url` z tieru 1 se **nezvedl ani na strength 170** — všechny tři
varianty přišly jako tatáž kniha s jinak zbarveným hřbetem. Prompt sliboval „blazing
white-hot fire, vortex of runes, burning pages"; init to přebil.

**Opraveno generováním nanovo + posunutím palety.** `color_image_url` se váží plochou,
takže dokud krém drží většinu pixelů, „blazing" nemá kam přistát. Nová paleta ubrala krému
a přidala oranžové/zlaté/bílé → tier 2 přišel hned. **Když se nedaří eskalovat, posuň
paletu, ne přídavná jména.**

### `animate_image`: dvě nastavení, každé zabije to druhé

| | pohyb | smyčka |
|---|---|---|
| bez `last_frame_url` | ✔ mean 8–12 | ✘ zlato **vyteklo** do 6. snímku a nevrátilo se |
| `last_frame_url` = **první snímek** | ✘ mean **1,9** (pod prahem 4 = nehybné) | ✔ šev 0,00, zlato konstantní |

Pinnutí konce na začátek je jinak **správný trik na cykličnost** — model interpoluje zpátky
do výchozí pózy. Jenže když jsou oba konce identické, nemá co interpolovat a vyjde idle.
Kompromis mezi tím neexistuje; nasadilo se procedurální řešení.

### `tools/aura_anim.py` — světlo místo geometrie

Sesterský nástroj k `pulse_anim.py`. Ten posouvá tuhé pásy (kameny Zen Pulsaru), tenhle
nechá sprite na místě a animuje jeho **světlo**: dýchající záře + stoupající runy.

Smyčka je exaktní z konstrukce — každá runa má fázi, poloha je `(fáze + i/frames) % 1`
a alfa `sin(pi*u)`, takže na obou koncích cesty je neviditelná. Není co ladit ručně.

Tři věci, které stály jeden průchod:

- **Pulz smí jen přidávat.** Symetrický `sin` stáhl záři na 0,78× a hřbet na dva z devíti
  snímků vizuálně zhasl — čte se to jako výpadek, ne jako dýchání. Vzorec je
  `1 + pulse * (0.5 + 0.5*sin)`, autorská póza je **podlaha**.
- **Runy musí být minimálně 2×2 zdrojového pixelu.** `halve()` průměruje bloky 2×2, takže
  jednopixelová runa přežije do 32 px jako čtvrtinově silný šmouh — ve hře neviditelný.
- **Maska záře musí být opravdu úzká.** Naivní „teplý pixel" (`R>150, R−B>55`) chytil i
  krémový pergamen — 994 z ~2000 neprůhledných pixelů — a runy by odlétaly z celé stránky
  místo ze hřbetu. Spawn se bere z **horní hrany** úzké masky: runa vzniklá uprostřed
  stránky čte jako smítko, runa opouštějící hřbet čte jako runa.

### Tier 2 má být TÁŽ kresba, ne jiný objekt

První pokus o tier 2 popsal hořící knihu a dostal ji — plamen, jiná silueta, jiné čtení.
Špatně: upgrade se má poznat jako **povýšená tatáž věc**, ne jako výměna.

Druhý pokus popisoval jen **rozdíl** (tmavší desky, zlaté kování, levitace, žádný oheň)
s tierem 1 jako initem — a kniha zůstala pixelově prakticky táž, což bylo přesně to,
co se chtělo. **Ale kování nepřišlo ani na jedné ze čtyř variant** (strength 170–230).

**Detail o velikosti 2×3 pixelů generátor spolehlivě neumístí**, zatímco kódem se dá dát
přesně tam, kam patří. `aura_anim.gild_corners()` ztmaví „tělo" (co není světlo ani
pergamen = kůže) a orazítkuje levý, pravý a přední roh. Čtvrtý roh je schovaný za
stránkami — orazítkovaný by dal zlatou značku doprostřed hřbetu.

**Základ tieru 2 je přímo sprite tieru 1**, ne přegenerovaná varianta. Zaručí to, že úhel
i kresba jsou identické, a celý tier 2 je pak reprodukovatelný z repa jedním příkazem.

### Oběžná dráha potřebuje místo — a hloubku

`aura_anim.py --orbit` nechá sprite na místě a **obtočí ho runami**. Dvě věci, bez kterých
to nefunguje:

- **Runy musí střídat vrstvu.** Na vzdálené půlce elipsy (`sin(úhel) < 0` v téhle
  izometrii) se kreslí **pod** sprite a ztlumené, na blízké **nad** něj. Nakresleno jako
  jeden plochý prstenec to po knize klouže jako nálepky a celé to čte jako dekal.
- **Plátno se musí zvětšit, ne kniha zmenšit.** Kniha zabírá ~27 z 32 art px, takže
  prstenec o poloměru sprite se jen lepí na siluetu a čte jako zlatý lem. `--pad 8`
  (zdrojových px) dá 40×40 art místo 32×32; `tower.gd` kreslí hlavu ×2 vystředěně, takže
  **kresba zůstane přesně stejně velká** a přibude jen prázdno kolem. Ne každá hlava
  v `assets/towers/` je tedy stejně velká — a nesmí být.

Viz `ART_PIPELINE.md` (co kreslit), `ART_DIRECTION.md` (proč tak) a paměť
`project-art-direction-mapa`.

**Sochařská forma věží (19. 8. 2026) — plné znění a prompt fráze jsou v
`ART_PIPELINE.md` §3c, ne tady.** Tenhle soubor je API povrch, ne výtvarné pravidlo
(řečeno hned v úvodu). Zkratka: kuželovitá forma odstupňovaná do pásů (základna → dřík →
koruna), jeden zdroj světla shora, zaoblené hrany, kontaktní AO u paty — jiná osa než
hue-shift stínu z §5c výš, obě platí zároveň.
