# GENERATION_PLAN.md — kompletní plán generování artu

> **GENEROVÁNO** `python tools/gen_art_prompts.py` ze `docs/art/STYLE_BIBLE.md`
> a z obsahu `data/`. **Needituj ručně** — přepiš bibli a přegeneruj.
> `python tools/gen_art_prompts.py --check` vrátí 1, když je tenhle soubor zvětralý.
>
> Tenhle dokument **nic negeneruje**. Je to nákupní seznam a rozpočet.
> `mcp__pixellab__*` je v `settings` na deny a zůstává tam.

## Souhrn

| fáze | název | entit | volání | generací |
|---|---|---|---|---|
| 0 | Focus core, habit a obránce-kotva | 3 | 3 | 80 |
| 1 | Zbytek rejstříku | 34 | 21 | 440 |
| **celkem** | | **37** | **24** | **520** |

**37 entit, 24 volání, 520 generací** (pesimisticky — horní hranice každého pásma,
viz STYLE_BIBLE.md §9). Animace se sem nepočítají, jsou vlastní kolo.

Rozpad podle druhu:

| kind | entit | volání | generací | velikost |
|---|---|---|---|---|
| defender | 4 | 4 | 80 | 64 px |
| distraction | 12 | 12 | 240 | 32 px |
| distraction_boss | 1 | 1 | 40 | 64 px |
| focus_core | 1 | 1 | 40 | 96 px |
| habit | 15 | 5 | 100 | 64 px |
| prop | 4 | 1 | 20 | 32 px |

## Co platí pro každé jedno volání

1. **Design constraints** jsou hned za formou entity, doslova, v KAŽDÉM
   `description` / `item_description`. Zdroj: STYLE_BIBLE.md §7b — je to jediná
   cesta, jak dostat perspektivu ("low top-down, zero isometric tilt") do
   promptu pro `create_1_direction_object`, jehož `view` parametr "low top-down"
   neumí (§9).
2. **Povinný suffix** je na konci každého `description` / `item_description`,
   doslova, za design constraints. Zdroj: STYLE_BIBLE.md §7.
3. **Paleta se vynucuje AŽ PO generování**, ne v tomhle volání. Ověřeno proti
   živému schématu (`tools/pixellab_schema.json`): `color_image_url` na
   `create_character` ani `create_1_direction_object` neexistuje — postava a
   objekt ho po odeslání tiše zahodí. Paleta se vynutí zvlášť přes
   `reduce_colors(palette_image_url=docs/art/palette_48.png)` na staženém výsledku (A0/PROGRESS.md).
   Žádný prompt neobsahuje hex ani vlastní seznam barev, a 32barevná varianta
   palety (ta, co podle měření škodí 6 z 10 příšer) se sem nedostane ani jednou.
4. **`get_balance` před dávkou.** Kvóta se počítá po generacích, ne po voláních.
5. **Fronta pod deset.** Jedenáctý souběžný job se vrátí *jako text, ne jako
   chyba* — tělo odpovědi se musí číst, jinak skript čeká na job, který nevznikl.
6. **Výsledky drží ~8 hodin.** Stáhni hned, `curl` na download URL
   (nekončí na `.png`), `Authorization: Bearer`. Žádný base64 do kontextu.
7. **Id se mezi voláním a vyzvednutím přejmenovává:** `get_image(job_id=…)`,
   `get_tiles_pro(tile_id=…)`, `get_character(character_id=…)`,
   `get_object(object_id=…)`. Stav, na který se čeká, je `creating`, ne
   `processing`.
8. **Po výměně PNG na disku `--headless --import`**, jinak hra tiše kreslí
   staré textury z cache.
9. **Objednávka může být větší než cíl.** U postav se generuje na dvojnásobku
   a půlí se **přesně jednou** — dvakrát půlený obrázek se rozpadne, a `size`
   menší než obsah kotvy job rovnou odmítne. Každý záznam má obě čísla zvlášť.
10. **`animate_character` nad 64 px tiše eskaluje na `pro`** = 20–40 generací
    *na směr*, když se nepošle `mode:"v3"` výslovně. Do animací se nesahá dřív,
    než statická sada projde bránou fáze 3.
11. **`create_character` a `create_1_direction_object` NEMAJÍ žádný parametr pro
    seed ani jinou formu determinismu** — ověřeno proti živému schématu
    (`tools/pixellab_schema.json`, A0b). Objednávka stejné postavy/objektu
    podruhé dá JINÝ výsledek, ne reprodukci. `seed` v `params` níže u nich
    proto nikdy nedorazí k serveru (filtruje se, viz bod 3) — je to jen
    stabilní identifikátor záznamu v tomhle plánu, ne kontrola nad generováním.
    Výjimka je terén (`create_tiles_pro`, dnes v plánu nepoužitý): ten `seed`
    ve svém živém schématu MÁ, takže by u něj reprodukovatelný byl.

Kotva označená v `STYLE_BIBLE.md` §6 jako `FORBIDDEN` (opuštěná rodina) se
v tomhle plánu neobjevuje ani jednou — a `scenes/_test_art_prompts.tscn` to
ověřuje na celém souboru, ne jen na promptech.

---

## Fáze 0 — Focus core, habit a obránce-kotva

**Cena:** 80 generací · **volání:** 3 · **entit:** 3

**Brána, než se pustí další fáze:** ZASTAVIT A NECHAT ROZHODNOUT UŽIVATELE. Povinný krok je popsaný pod tabulkou fáze v plánu; bez jeho schválení se negeneruje ani jeden další kus rejstříku. K tomu technicky: všechny tři stojí na ploché zdi (TOP, 484) a dotýkají se jí — mezi spodkem obsahu a začátkem stínu není ani řádek holé zdi — a tělo neleží do +-60 jasu od podkladu.

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

### 1. `broccoli_knight` — defender, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | žádná, tohle je kořen rodiny |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a broccoli knight in riveted armour, florets first, a wall that soaks hits and pins whole clumps in place; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "broccoli_knight",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a broccoli knight in riveted armour, florets first, a wall that soaks hits and pins whole clumps in place; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

**Vybraný kandidát:** `cand_03` — `assets/raw/broccoli_knight/cand_03.png`

vybráno uživatelem 30. 8. 2026; paleta zatím neproběhla — kotva sama je teď ve hře (§6a), regenerace možná dřív, než na paletě záleží

### 2. `prop_focus_core` — focus_core, 96 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 96 art px (STYLE_BIBLE.md §5, kind `focus_core`) |
| velikost objednávky | 96 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | žádná, tohle je kořen rodiny |
| dávka | samostatné volání |
| cena | 40 generací (tier `pro_velky`) |

**Parametry**

```json
{
  "description": "a single large neuron soma with many radiating processes, warm and unhurried, the one still thing on the board, gold white; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a single large neuron soma with many radiating processes, warm and unhurried, the one still thing on the board, gold white; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 96,
  "view": "top-down"
}
```

**Prompt**

```text
a single large neuron soma with many radiating processes, warm and unhurried, the one still thing on the board, gold white; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

**Vybraný kandidát:** `cand_00` — `assets/raw/prop_focus_core/cand_00.png`

vybráno uživatelem 30. 8. 2026; paleta už hotová (cand_00_pal48.png)

### 3. `focus_timer` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity prop_focus_core (dědí styl i rozměr) |
| dávka | `habit_01` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a round glial cell body with one coiled process wound like a spring and a single warm amber node, working in bursts; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a round glial cell body with one coiled process wound like a spring and a single warm amber node, working in bursts; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a round glial cell body with one coiled process wound like a spring and a single warm amber node, working in bursts; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

**Vybraný kandidát:** `cand_04` — `assets/raw/focus_timer/cand_04.png`

vybráno uživatelem 30. 8. 2026; paleta zatím neproběhla

---

## Fáze 1 — Zbytek rejstříku

**Cena:** 440 generací · **volání:** 21 · **entit:** 34

**Brána, než se pustí další fáze:** Každá vygenerovaná postava má siluetu rozeznatelnou od ostatních v kontaktním listu v herním měřítku a jas nad pásmem cesty (146).

### 4. `accountability` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_02` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a nest of several small round glial bodies sharing one teal membrane, a place others come out of; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a nest of several small round glial bodies sharing one teal membrane, a place others come out of; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a nest of several small round glial bodies sharing one teal membrane, a place others come out of; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 5. `anchor` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_02` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_02` |

**Parametry**

```json
{
  "description": "a squat glial body rooted into the tissue by thick processes, one cyan crystal node, it holds and does not fire; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a squat glial body rooted into the tissue by thick processes, one cyan crystal node, it holds and does not fire; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a squat glial body rooted into the tissue by thick processes, one cyan crystal node, it holds and does not fire; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 6. `avocado_monk` — defender, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity broccoli_knight (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "an avocado monk with wrapped fists and a stone pit core, calm, mends the defenders around it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "avocado_monk",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
an avocado monk with wrapped fists and a stone pit core, calm, mends the defenders around it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 7. `chilli_berserker` — defender, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity broccoli_knight (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a chilli berserker with two burning knives and no patience, thin and fast, every slash keeps searing; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "chilli_berserker",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a chilli berserker with two burning knives and no patience, thin and fast, every slash keeps searing; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 8. `clickbait` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | žádná, tohle je kořen rodiny |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a pathogen dominated by one huge lidless eye with a barbed rim, pink, armoured against fast small hits; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "clickbait",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a pathogen dominated by one huge lidless eye with a barbed rim, pink, armoured against fast small hits; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 9. `decor_knot` — prop, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity prop_focus_core (dědí styl i rozměr) |
| dávka | `prop_03` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a small tangled knot of fibres resting on the tissue, scenery only; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a small tangled knot of fibres resting on the tissue, scenery only; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a small tangled knot of fibres resting on the tissue, scenery only; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 10. `decor_synapse` — prop, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity prop_focus_core (dědí styl i rozměr) |
| dávka | `prop_03` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `prop_03` |

**Parametry**

```json
{
  "description": "a small synaptic cleft between two processes, scenery only, never reads as a collectable; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a small synaptic cleft between two processes, scenery only, never reads as a collectable; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a small synaptic cleft between two processes, scenery only, never reads as a collectable; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 11. `exercise` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_02` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_02` |

**Parametry**

```json
{
  "description": "a thick walled glial body with a glowing orange core showing through the membrane, heavy and slow; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a thick walled glial body with a glowing orange core showing through the membrane, heavy and slow; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a thick walled glial body with a glowing orange core showing through the membrane, heavy and slow; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 12. `focus_pillar` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_02` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_02` |

**Parametry**

```json
{
  "description": "a fluted round glial column with a single cyan crystal at its crown, quiet and upright; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a fluted round glial column with a single cyan crystal at its crown, quiet and upright; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a fluted round glial column with a single cyan crystal at its crown, quiet and upright; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 13. `focus_timer_2` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | init_image_url = hotové PNG entity focus_timer (tier 2 je TÁŽ kresba) |
| dávka | `habit_04` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "the same cell escalated, the coil tighter and doubled, the amber node brighter, one added ring; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "the same cell escalated, the coil tighter and doubled, the amber node brighter, one added ring; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the coil tighter and doubled, the amber node brighter, one added ring; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 14. `garlic_mage` — defender, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity broccoli_knight (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "an ivory garlic bulb sage with a root staff, its pungent air slows everything shuffling through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "garlic_mage",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
an ivory garlic bulb sage with a root staff, its pungent air slows everything shuffling through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 15. `mindfulness` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_04` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_04` |

**Parametry**

```json
{
  "description": "a round glial cell under a wide crown of fine violet dendritic processes, reaching over everything nearby; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a round glial cell under a wide crown of fine violet dendritic processes, reaching over everything nearby; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a round glial cell under a wide crown of fine violet dendritic processes, reaching over everything nearby; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 16. `prop_dopamine` — prop, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity prop_focus_core (dědí styl i rozměr) |
| dávka | `prop_03` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `prop_03` |

**Parametry**

```json
{
  "description": "a synaptic vesicle, a small round warm amber droplet swollen to bursting, translucent membrane; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a synaptic vesicle, a small round warm amber droplet swollen to bursting, translucent membrane; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a synaptic vesicle, a small round warm amber droplet swollen to bursting, translucent membrane; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 17. `prop_spawn` — prop, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity prop_focus_core (dědí styl i rozměr) |
| dávka | `prop_03` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `prop_03` |

**Parametry**

```json
{
  "description": "a torn opening in the tissue where something comes through, ragged cold edges, dark and empty inside; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a torn opening in the tissue where something comes through, ragged cold edges, dark and empty inside; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a torn opening in the tissue where something comes through, ragged cold edges, dark and empty inside; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 18. `real_hobby` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_04` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_04` |

**Parametry**

```json
{
  "description": "a slender glial column fraying at the top into many fine golden fibres, reaching further than anything else; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a slender glial column fraying at the top into many fine golden fibres, reaching further than anything else; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a slender glial column fraying at the top into many fine golden fibres, reaching further than anything else; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 19. `zen_pulsar` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_04` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_04` |

**Parametry**

```json
{
  "description": "a spherical glial bulb held inside one standing cyan ring, still until it releases; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "a spherical glial bulb held inside one standing cyan ring, still until it releases; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a spherical glial bulb held inside one standing cyan ring, still until it releases; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 20. `accountability_2` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | init_image_url = hotové PNG entity accountability (tier 2 je TÁŽ kresba) |
| dávka | `habit_05` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "the same cell escalated, two more bodies in the nest, the teal membrane brighter; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "the same cell escalated, two more bodies in the nest, the teal membrane brighter; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, two more bodies in the nest, the teal membrane brighter; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 21. `adult_content` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a heavy orange sac with hooked barbs and a slick membrane, low to the ground and dragging; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "adult_content",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a heavy orange sac with hooked barbs and a slick membrane, low to the ground and dragging; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 22. `autoplay` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "an amber spore chain of three fused capsules that keeps unrolling forward, each capsule budding the next; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "autoplay",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
an amber spore chain of three fused capsules that keeps unrolling forward, each capsule budding the next; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 23. `comparison` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a bleached cyan mimic blob wearing a half finished copy of another creature, edges unresolved; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "comparison",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a bleached cyan mimic blob wearing a half finished copy of another creature, edges unresolved; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 24. `doomscroll` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a long green ciliated ribbon that flows head first, segmented, with no visible end to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "doomscroll",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a long green ciliated ribbon that flows head first, segmented, with no visible end to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 25. `energy_drink` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a swollen teal cyst under pressure, ribbed, with a torn neck venting, faster the more damaged it is; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "energy_drink",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a swollen teal cyst under pressure, ribbed, with a torn neck venting, faster the more damaged it is; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 26. `exercise_2` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | init_image_url = hotové PNG entity exercise (tier 2 je TÁŽ kresba) |
| dávka | `habit_05` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_05` |

**Parametry**

```json
{
  "description": "the same cell escalated, the wall thicker and the orange core burning brighter through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "the same cell escalated, the wall thicker and the orange core burning brighter through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the wall thicker and the orange core burning brighter through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 27. `fomo` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a darting magenta filament with a bright head and a dissolving tail, already half gone before it arrives; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "fomo",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a darting magenta filament with a bright head and a dissolving tail, already half gone before it arrives; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 28. `group_chat` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a knot of six small green spores sharing one membrane, all of them mouths, none of them a head; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "group_chat",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a knot of six small green spores sharing one membrane, all of them mouths, none of them a head; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 29. `jackpot` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a crimson gland with three swollen lobes and one bright wet core, pulsing on a slow rhythm; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "jackpot",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a crimson gland with three swollen lobes and one bright wet core, pulsing on a slow rhythm; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 30. `just_one_more` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a violet cluster of four loosely bound spores pulling apart at the seams, about to become four of itself; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "just_one_more",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a violet cluster of four loosely bound spores pulling apart at the seams, about to become four of itself; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 31. `mindfulness_2` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | init_image_url = hotové PNG entity mindfulness (tier 2 je TÁŽ kresba) |
| dávka | `habit_05` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_05` |

**Parametry**

```json
{
  "description": "the same cell escalated, the dendritic crown denser and wider, the violet deeper; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "the same cell escalated, the dendritic crown denser and wider, the violet deeper; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the dendritic crown denser and wider, the violet deeper; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 32. `notification` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "the smallest and fastest spore of the swarm, a hard red shell and one twitching cilium, almost nothing to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "notification",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
the smallest and fastest spore of the swarm, a hard red shell and one twitching cilium, almost nothing to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 33. `phantom_buzz` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "a hollow blue spore husk that hovers, no legs, a sharp vibrating rim, and nothing at all inside it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "phantom_buzz",
  "outline": "single color black outline",
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a hollow blue spore husk that hovers, no legs, a sharp vibrating rim, and nothing at all inside it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 34. `real_hobby_2` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | init_image_url = hotové PNG entity real_hobby (tier 2 je TÁŽ kresba) |
| dávka | `habit_05` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_05` |

**Parametry**

```json
{
  "description": "the same cell escalated, more golden fibres, fraying further down the column; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "the same cell escalated, more golden fibres, fraying further down the column; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, more golden fibres, fraying further down the column; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 35. `social_media_binge` — distraction_boss, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `distraction_boss`) |
| velikost objednávky | 128 px — a pak **půlit přesně jednou** na 64 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 40 generací (tier `pro_velky`) |

**Parametry**

```json
{
  "description": "a violet colonial mass of fused spores, many eyes, a shielding outer membrane, dragging a train of smaller buds behind it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "social_media_binge",
  "outline": "single color black outline",
  "size": 128,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a violet colonial mass of fused spores, many eyes, a shielding outer membrane, dragging a train of smaller buds behind it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 36. `zen_pulsar_2a` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | init_image_url = hotové PNG entity zen_pulsar (tier 2 je TÁŽ kresba) |
| dávka | `habit_06` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "description": "the same cell escalated, a second concentric cyan ring standing outside the first; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "the same cell escalated, a second concentric cyan ring standing outside the first; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, a second concentric cyan ring standing outside the first; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 37. `zen_pulsar_2b` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | init_image_url = hotové PNG entity zen_pulsar (tier 2 je TÁŽ kresba) |
| dávka | `habit_06` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_06` |

**Parametry**

```json
{
  "description": "the same cell escalated, the single ring split into two smaller counter turning half rings; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "item_descriptions": [
    "the same cell escalated, the single ring split into two smaller counter turning half rings; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the single ring split into two smaller counter turning half rings; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; centered, full object visible, margin on all sides; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

---

## Pořadí a závislosti

| # | fáze | id | závisí na | dávka |
|---|---|---|---|---|
| 1 | 0 | `broccoli_knight` | — | — |
| 2 | 0 | `prop_focus_core` | — | — |
| 3 | 0 | `focus_timer` | `prop_focus_core` | `habit_01` |
| 4 | 1 | `accountability` | `focus_timer` | `habit_02` |
| 5 | 1 | `anchor` | `focus_timer` | `habit_02` |
| 6 | 1 | `avocado_monk` | `broccoli_knight` | — |
| 7 | 1 | `chilli_berserker` | `broccoli_knight` | — |
| 8 | 1 | `clickbait` | — | — |
| 9 | 1 | `decor_knot` | `prop_focus_core` | `prop_03` |
| 10 | 1 | `decor_synapse` | `prop_focus_core` | `prop_03` |
| 11 | 1 | `exercise` | `focus_timer` | `habit_02` |
| 12 | 1 | `focus_pillar` | `focus_timer` | `habit_02` |
| 13 | 1 | `focus_timer_2` | `focus_timer` | `habit_04` |
| 14 | 1 | `garlic_mage` | `broccoli_knight` | — |
| 15 | 1 | `mindfulness` | `focus_timer` | `habit_04` |
| 16 | 1 | `prop_dopamine` | `prop_focus_core` | `prop_03` |
| 17 | 1 | `prop_spawn` | `prop_focus_core` | `prop_03` |
| 18 | 1 | `real_hobby` | `focus_timer` | `habit_04` |
| 19 | 1 | `zen_pulsar` | `focus_timer` | `habit_04` |
| 20 | 1 | `accountability_2` | `accountability` | `habit_05` |
| 21 | 1 | `adult_content` | `clickbait` | — |
| 22 | 1 | `autoplay` | `clickbait` | — |
| 23 | 1 | `comparison` | `clickbait` | — |
| 24 | 1 | `doomscroll` | `clickbait` | — |
| 25 | 1 | `energy_drink` | `clickbait` | — |
| 26 | 1 | `exercise_2` | `exercise` | `habit_05` |
| 27 | 1 | `fomo` | `clickbait` | — |
| 28 | 1 | `group_chat` | `clickbait` | — |
| 29 | 1 | `jackpot` | `clickbait` | — |
| 30 | 1 | `just_one_more` | `clickbait` | — |
| 31 | 1 | `mindfulness_2` | `mindfulness` | `habit_05` |
| 32 | 1 | `notification` | `clickbait` | — |
| 33 | 1 | `phantom_buzz` | `clickbait` | — |
| 34 | 1 | `real_hobby_2` | `real_hobby` | `habit_05` |
| 35 | 1 | `social_media_binge` | `clickbait` | — |
| 36 | 1 | `zen_pulsar_2a` | `zen_pulsar` | `habit_06` |
| 37 | 1 | `zen_pulsar_2b` | `zen_pulsar` | `habit_06` |

