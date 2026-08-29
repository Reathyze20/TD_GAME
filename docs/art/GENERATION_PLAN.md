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
| 0 | Kontrast cesty proti tkáni | 2 | 1 | 40 |
| 1 | Zbytek terénu a rekvizity | 5 | 2 | 60 |
| 2 | Focus core a jeden habit | 2 | 2 | 60 |
| 3 | Zbytek habitů, distractions po rodinách, obránci | 31 | 21 | 440 |
| **celkem** | | **40** | **26** | **600** |

**40 entit, 26 volání, 600 generací** (pesimisticky — horní hranice každého pásma,
viz STYLE_BIBLE.md §9). Animace se sem nepočítají, jsou vlastní kolo.

Rozpad podle druhu:

| kind | entit | volání | generací | velikost |
|---|---|---|---|---|
| defender | 4 | 4 | 80 | 32 px |
| distraction | 12 | 12 | 240 | 32 px |
| distraction_elite | 1 | 1 | 40 | 64 px |
| focus_core | 1 | 1 | 40 | 96 px |
| habit | 15 | 5 | 100 | 64 px |
| prop | 4 | 1 | 20 | 16 px |
| terrain | 3 | 2 | 80 | 16 px |

## Co platí pro každé jedno volání

1. **Povinný suffix** je na konci každého `description` / `item_description`,
   doslova. Zdroj: STYLE_BIBLE.md §7.
2. **Paleta jde obrázkem, ne slovy** — `color_image_url` na `docs/art/palette_48.png`.
   Žádný prompt neobsahuje hex ani vlastní seznam barev, a 32barevná varianta
   palety (ta, co podle měření škodí 6 z 10 příšer) se sem nedostane ani jednou.
3. **`get_balance` před dávkou.** Kvóta se počítá po generacích, ne po voláních.
4. **Fronta pod deset.** Jedenáctý souběžný job se vrátí *jako text, ne jako
   chyba* — tělo odpovědi se musí číst, jinak skript čeká na job, který nevznikl.
5. **Výsledky drží ~8 hodin.** Stáhni hned, `curl` na download URL
   (nekončí na `.png`), `Authorization: Bearer`. Žádný base64 do kontextu.
6. **Id se mezi voláním a vyzvednutím přejmenovává:** `get_image(job_id=…)`,
   `get_tiles_pro(tile_id=…)`, `get_character(character_id=…)`,
   `get_object(object_id=…)`. Stav, na který se čeká, je `creating`, ne
   `processing`.
7. **Po výměně PNG na disku `--headless --import`**, jinak hra tiše kreslí
   staré textury z cache.
8. **Objednávka může být větší než cíl.** U postav se generuje na dvojnásobku
   a půlí se **přesně jednou** — dvakrát půlený obrázek se rozpadne, a `size`
   menší než obsah kotvy job rovnou odmítne. Každý záznam má obě čísla zvlášť.
9. **`animate_character` nad 64 px tiše eskaluje na `pro`** = 20–40 generací
   *na směr*, když se nepošle `mode:"v3"` výslovně. Do animací se nesahá dřív,
   než statická sada projde bránou fáze 3.

Kotva označená v `STYLE_BIBLE.md` §6 jako `FORBIDDEN` (opuštěná rodina) se
v tomhle plánu neobjevuje ani jednou — a `scenes/_test_art_prompts.tscn` to
ověřuje na celém souboru, ne jen na promptech.

---

## Fáze 0 — Kontrast cesty proti tkáni

**Cena:** 40 generací · **volání:** 1 · **entit:** 2

**Brána, než se pustí další fáze:** Změř terrain_tissue a terrain_axon z toho jednoho tilesetu: obě brány „cesta vs. tkáň“ z §4 musí projít (jas >= +60, odstín >= 140). Neprojde-li to, oprav prompt a opakuj — do fáze 1 se nesmí, dokud to nesedí.

**Proč je fáze 0 první — a proč je to jedno jediné volání.**

Kontrast cesty proti tkáni je jediné pravidlo v tomhle souboru, které se **nedá opravit
později**. Špatný habit se přegeneruje za 1 generaci. Špatná dlaždice země se
nepřegeneruje sama — přegeneruje se s ní *všechno*, co na ní stojí, protože každá postava
byla vážená a laděná proti jasu podlahy, na které měla být vidět. Když se cesta od tkáně
neodliší, je nečitelná celá deska bez ohledu na to, jak dobré jsou sprity na ní.

K tomu se přidává druhá věc: `style_images` **přebírá i rozměr, nejen styl**
(`iso_bible.md` §5). První dlaždice tedy nefixuje jen barvu — fixuje rastr celé sady.
Špatná první dlaždice otráví každou další.

A třetí, čistě ekonomická: fáze 0 je **jedno jediné volání** (jeden `create_tiles_pro`
vyrábí oba terény naráz, tkáň i axon), riskuje tedy nejmenší možnou částku, aby ochránila
**celý zbytek plánu** — každou další dlaždici, každý habit i každou postavu, které se
proti té podlaze vážou jasem. Je to nejlevnější místo, kde se ta otázka dá položit,
a jediné, kde se dá zodpovědět měřením místo dohadem.

> **Nulová varianta, která stojí 0 generací a stojí za zvážení dřív, než se utratí
> cokoli:** `tools/flat_terrain.py` už dnes instaluje ploché barvy přesně na cílových
> hodnotách 78 / 146 / 484. Když je cíl „plochý terén jako Rogue Tower“
> (`user-rogue-tower-jednoduchost`), fáze 0 i fáze 1 se dají celé nahradit tím skriptem
> a celý rozpočet zůstane postavám. Generovat terén má smysl jen tehdy, když se vědomě
> chce zpátky textura — a `iso_bible.md` §2b má naměřeno, proč se nechtěla.

### 1. `terrain_axon` — terrain, 16 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_tiles_pro` |
| mode | `standard` |
| vyzvednutí | `get_tiles_pro(tile_id)` |
| velikost na disku | 16 art px (STYLE_BIBLE.md §5, kind `terrain`) |
| velikost objednávky | 16 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | terrain_tissue je v tomhle volání druhý terén |
| dávka | `tileset_terrain_axon` |
| cena | 40 generací (tier `tileset`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "1). a myelinated axon read from above, one continuous warm amber conductive track laid into the tissue, smooth sheath, slightly raised 2). dark synaptic tissue, wet and grooved, deep indigo, one continuous unbroken surface with nothing on it that competes for attention; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline_mode": "segmentation",
  "seed": 34610,
  "tile_feature": "tileset",
  "tile_size": 16,
  "tile_type": "square_topdown",
  "tile_view": "top-down"
}
```

**Prompt**

```text
1). a myelinated axon read from above, one continuous warm amber conductive track laid into the tissue, smooth sheath, slightly raised 2). dark synaptic tissue, wet and grooved, deep indigo, one continuous unbroken surface with nothing on it that competes for attention; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 2. `terrain_tissue` — terrain, 16 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_tiles_pro` |
| mode | `standard` |
| vyzvednutí | `get_tiles_pro(tile_id)` |
| velikost na disku | 16 art px (STYLE_BIBLE.md §5, kind `terrain`) |
| velikost objednávky | 16 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | vzniká jako druhý terén ve volání entity terrain_axon — vlastní volání nemá a neplatí se |
| dávka | `tileset_terrain_axon` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `tileset_terrain_axon` |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "1). a myelinated axon read from above, one continuous warm amber conductive track laid into the tissue, smooth sheath, slightly raised 2). dark synaptic tissue, wet and grooved, deep indigo, one continuous unbroken surface with nothing on it that competes for attention; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline_mode": "segmentation",
  "seed": 34610,
  "tile_feature": "tileset",
  "tile_size": 16,
  "tile_type": "square_topdown",
  "tile_view": "top-down"
}
```

**Prompt**

```text
1). a myelinated axon read from above, one continuous warm amber conductive track laid into the tissue, smooth sheath, slightly raised 2). dark synaptic tissue, wet and grooved, deep indigo, one continuous unbroken surface with nothing on it that competes for attention; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

---

## Fáze 1 — Zbytek terénu a rekvizity

**Cena:** 60 generací · **volání:** 2 · **entit:** 5

**Brána, než se pustí další fáze:** Všechny dlaždice mají 16 px stranu změřenou ze souboru, ne z parametru; dláždění nemá díry ani překryv; zdi projdou branami „zdi vs. cesta“ a „zdi, matnost“ z §4.

### 3. `decor_knot` — prop, 16 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 16 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px — a pak **půlit přesně jednou** na 16 |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity terrain_tissue (dědí styl i rozměr) |
| dávka | `prop_01` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a small tangled knot of fibres resting on the tissue, scenery only; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 9425,
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a small tangled knot of fibres resting on the tissue, scenery only; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 4. `decor_synapse` — prop, 16 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 16 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px — a pak **půlit přesně jednou** na 16 |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity terrain_tissue (dědí styl i rozměr) |
| dávka | `prop_01` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `prop_01` |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a small synaptic cleft between two processes, scenery only, never reads as a collectable; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 13147,
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a small synaptic cleft between two processes, scenery only, never reads as a collectable; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 5. `prop_dopamine` — prop, 16 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 16 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px — a pak **půlit přesně jednou** na 16 |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity terrain_tissue (dědí styl i rozměr) |
| dávka | `prop_01` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `prop_01` |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a synaptic vesicle, a small round warm amber droplet swollen to bursting, translucent membrane; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 49370,
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a synaptic vesicle, a small round warm amber droplet swollen to bursting, translucent membrane; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 6. `prop_spawn` — prop, 16 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 16 art px (STYLE_BIBLE.md §5, kind `prop`) |
| velikost objednávky | 32 px — a pak **půlit přesně jednou** na 16 |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity terrain_tissue (dědí styl i rozměr) |
| dávka | `prop_01` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `prop_01` |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a torn opening in the tissue where something comes through, ragged cold edges, dark and empty inside; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 32926,
  "size": 32,
  "view": "top-down"
}
```

**Prompt**

```text
a torn opening in the tissue where something comes through, ragged cold edges, dark and empty inside; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 7. `terrain_spine` — terrain, 16 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_tiles_pro` |
| mode | `standard` |
| vyzvednutí | `get_tiles_pro(tile_id)` |
| velikost na disku | 16 art px (STYLE_BIBLE.md §5, kind `terrain`) |
| velikost objednávky | 16 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | terrain_tissue je v tomhle volání druhý terén |
| dávka | `tileset_terrain_spine` |
| cena | 40 generací (tier `tileset`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "1). a dense thicket of dendritic spines seen from above, bone coloured ivory, matte and desaturated, packed close enough to read as solid ground 2). dark synaptic tissue, wet and grooved, deep indigo, one continuous unbroken surface with nothing on it that competes for attention; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline_mode": "segmentation",
  "seed": 1263,
  "tile_feature": "tileset",
  "tile_size": 16,
  "tile_type": "square_topdown",
  "tile_view": "top-down"
}
```

**Prompt**

```text
1). a dense thicket of dendritic spines seen from above, bone coloured ivory, matte and desaturated, packed close enough to read as solid ground 2). dark synaptic tissue, wet and grooved, deep indigo, one continuous unbroken surface with nothing on it that competes for attention; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

---

## Fáze 2 — Focus core a jeden habit

**Cena:** 60 generací · **volání:** 2 · **entit:** 2

**Brána, než se pustí další fáze:** focus_timer stojí na terrain_spine, dotýká se jí (mezi spodkem obsahu a stínem není ani řádek holé zdi) a jeho tělo neleží do +-60 jasu od zdi pod ním. Teprve pak se generuje zbylých 14 habitů.

### 8. `focus_timer` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity terrain_spine (dědí styl i rozměr) |
| dávka | `habit_02` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a round glial cell body with one coiled process wound like a spring and a single warm amber node, working in bursts; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 56129,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a round glial cell body with one coiled process wound like a spring and a single warm amber node, working in bursts; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 9. `prop_focus_core` — focus_core, 96 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 96 art px (STYLE_BIBLE.md §5, kind `focus_core`) |
| velikost objednávky | 96 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity terrain_tissue (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 40 generací (tier `pro_velky`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a single large neuron soma with many radiating processes, warm and unhurried, the one still thing on the board, gold white; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 28204,
  "size": 96,
  "view": "top-down"
}
```

**Prompt**

```text
a single large neuron soma with many radiating processes, warm and unhurried, the one still thing on the board, gold white; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

---

## Fáze 3 — Zbytek habitů, distractions po rodinách, obránci

**Cena:** 440 generací · **volání:** 21 · **entit:** 31

**Brána, než se pustí další fáze:** Každá vygenerovaná postava má siluetu rozeznatelnou od ostatních v kontaktním listu v herním měřítku a jas nad pásmem cesty (146).

### 10. `accountability` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_03` |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a nest of several small round glial bodies sharing one teal membrane, a place others come out of; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 50114,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a nest of several small round glial bodies sharing one teal membrane, a place others come out of; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 11. `anchor` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_03` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_03` |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a squat glial body rooted into the tissue by thick processes, one cyan crystal node, it holds and does not fire; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 56790,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a squat glial body rooted into the tissue by thick processes, one cyan crystal node, it holds and does not fire; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 12. `broccoli_knight` — defender, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | žádná, tohle je kořen rodiny |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a broccoli knight in riveted armour, florets first, a wall that soaks hits and pins whole clumps in place; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "broccoli_knight",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 20749,
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a broccoli knight in riveted armour, florets first, a wall that soaks hits and pins whole clumps in place; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 13. `clickbait` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | žádná, tohle je kořen rodiny |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a pathogen dominated by one huge lidless eye with a barbed rim, pink, armoured against fast small hits; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "clickbait",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 88817,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a pathogen dominated by one huge lidless eye with a barbed rim, pink, armoured against fast small hits; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 14. `exercise` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_03` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_03` |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a thick walled glial body with a glowing orange core showing through the membrane, heavy and slow; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 29841,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a thick walled glial body with a glowing orange core showing through the membrane, heavy and slow; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 15. `focus_pillar` — habit, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_1_direction_object` |
| mode | `pro` |
| vyzvednutí | `get_object(object_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `habit`) |
| velikost objednávky | 64 px, bez půlení |
| kotva | žádná — není to postava, rodinu drží dědičnost níž |
| závislost | style_images = hotové PNG entity focus_timer (dědí styl i rozměr) |
| dávka | `habit_03` — jede v už otevřeném volání |
| cena | 0 — placeno v dávce `habit_03` |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a fluted round glial column with a single cyan crystal at its crown, quiet and upright; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 97771,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a fluted round glial column with a single cyan crystal at its crown, quiet and upright; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 16. `focus_timer_2` — habit, 64 px

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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "the same cell escalated, the coil tighter and doubled, the amber node brighter, one added ring; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 72153,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the coil tighter and doubled, the amber node brighter, one added ring; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 17. `mindfulness` — habit, 64 px

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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a round glial cell under a wide crown of fine violet dendritic processes, reaching over everything nearby; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 5667,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a round glial cell under a wide crown of fine violet dendritic processes, reaching over everything nearby; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a slender glial column fraying at the top into many fine golden fibres, reaching further than anything else; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 47447,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a slender glial column fraying at the top into many fine golden fibres, reaching further than anything else; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "a spherical glial bulb held inside one standing cyan ring, still until it releases; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 40257,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
a spherical glial bulb held inside one standing cyan ring, still until it releases; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "the same cell escalated, two more bodies in the nest, the teal membrane brighter; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 83445,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, two more bodies in the nest, the teal membrane brighter; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 21. `adult_content` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a heavy orange sac with hooked barbs and a slick membrane, low to the ground and dragging; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "adult_content",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 32329,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a heavy orange sac with hooked barbs and a slick membrane, low to the ground and dragging; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 22. `autoplay` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "an amber spore chain of three fused capsules that keeps unrolling forward, each capsule budding the next; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "autoplay",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 10849,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
an amber spore chain of three fused capsules that keeps unrolling forward, each capsule budding the next; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 23. `avocado_monk` — defender, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity broccoli_knight (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "an avocado monk with wrapped fists and a stone pit core, calm, mends the defenders around it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "avocado_monk",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 56257,
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
an avocado monk with wrapped fists and a stone pit core, calm, mends the defenders around it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 24. `chilli_berserker` — defender, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity broccoli_knight (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a chilli berserker with two burning knives and no patience, thin and fast, every slash keeps searing; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "chilli_berserker",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 85348,
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
a chilli berserker with two burning knives and no patience, thin and fast, every slash keeps searing; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 25. `comparison` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a bleached cyan mimic blob wearing a half finished copy of another creature, edges unresolved; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "comparison",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 47378,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a bleached cyan mimic blob wearing a half finished copy of another creature, edges unresolved; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 26. `doomscroll` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a long green ciliated ribbon that flows head first, segmented, with no visible end to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "doomscroll",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 85912,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a long green ciliated ribbon that flows head first, segmented, with no visible end to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 27. `energy_drink` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a swollen teal cyst under pressure, ribbed, with a torn neck venting, faster the more damaged it is; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "energy_drink",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 24123,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a swollen teal cyst under pressure, ribbed, with a torn neck venting, faster the more damaged it is; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 28. `exercise_2` — habit, 64 px

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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "the same cell escalated, the wall thicker and the orange core burning brighter through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 47385,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the wall thicker and the orange core burning brighter through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 29. `fomo` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a darting magenta filament with a bright head and a dissolving tail, already half gone before it arrives; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "fomo",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 25904,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a darting magenta filament with a bright head and a dissolving tail, already half gone before it arrives; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 30. `garlic_mage` — defender, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `defender`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `fa8294b1-c3ec-4ae5-92fb-39570ced0f65` (general) |
| závislost | style_images = hotové PNG entity broccoli_knight (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "an ivory garlic bulb sage with a root staff, its pungent air slows everything shuffling through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "garlic_mage",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 50626,
  "size": 64,
  "style_character_id": "fa8294b1-c3ec-4ae5-92fb-39570ced0f65",
  "view": "low top-down"
}
```

**Prompt**

```text
an ivory garlic bulb sage with a root staff, its pungent air slows everything shuffling through it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 31. `group_chat` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a knot of six small green spores sharing one membrane, all of them mouths, none of them a head; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "group_chat",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 69814,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a knot of six small green spores sharing one membrane, all of them mouths, none of them a head; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 32. `jackpot` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a crimson gland with three swollen lobes and one bright wet core, pulsing on a slow rhythm; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "jackpot",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 61556,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a crimson gland with three swollen lobes and one bright wet core, pulsing on a slow rhythm; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 33. `just_one_more` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a violet cluster of four loosely bound spores pulling apart at the seams, about to become four of itself; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "just_one_more",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 64549,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a violet cluster of four loosely bound spores pulling apart at the seams, about to become four of itself; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 34. `mindfulness_2` — habit, 64 px

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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "the same cell escalated, the dendritic crown denser and wider, the violet deeper; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 45672,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the dendritic crown denser and wider, the violet deeper; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 35. `notification` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "the smallest and fastest spore of the swarm, a hard red shell and one twitching cilium, almost nothing to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "notification",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 15044,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
the smallest and fastest spore of the swarm, a hard red shell and one twitching cilium, almost nothing to it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 36. `phantom_buzz` — distraction, 32 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 32 art px (STYLE_BIBLE.md §5, kind `distraction`) |
| velikost objednávky | 64 px — a pak **půlit přesně jednou** na 32 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 20 generací (tier `pro`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a hollow blue spore husk that hovers, no legs, a sharp vibrating rim, and nothing at all inside it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "phantom_buzz",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 2923,
  "size": 64,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a hollow blue spore husk that hovers, no legs, a sharp vibrating rim, and nothing at all inside it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 37. `real_hobby_2` — habit, 64 px

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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "the same cell escalated, more golden fibres, fraying further down the column; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 48896,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, more golden fibres, fraying further down the column; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 38. `social_media_binge` — distraction_elite, 64 px

| | |
|---|---|
| nástroj | `mcp__pixellab__create_character` |
| mode | `pro` |
| vyzvednutí | `get_character(character_id)` |
| velikost na disku | 64 art px (STYLE_BIBLE.md §5, kind `distraction_elite`) |
| velikost objednávky | 128 px — a pak **půlit přesně jednou** na 64 |
| kotva | `62772f73-28d8-442b-add6-f33684f16415` (junk_food) |
| závislost | style_images = hotové PNG entity clickbait (dědí styl i rozměr) |
| dávka | samostatné volání |
| cena | 40 generací (tier `pro_velky`) |

**Parametry**

```json
{
  "color_image_url": "docs/art/palette_48.png",
  "description": "a violet colonial mass of fused spores, many eyes, a shielding outer membrane, dragging a train of smaller buds behind it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow",
  "mode": "pro",
  "name": "social_media_binge",
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "outline": "single color black outline",
  "seed": 42287,
  "size": 128,
  "style_character_id": "62772f73-28d8-442b-add6-f33684f16415",
  "view": "low top-down"
}
```

**Prompt**

```text
a violet colonial mass of fused spores, many eyes, a shielding outer membrane, dragging a train of smaller buds behind it; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 39. `zen_pulsar_2a` — habit, 64 px

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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "the same cell escalated, a second concentric cyan ring standing outside the first; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 4772,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, a second concentric cyan ring standing outside the first; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

### 40. `zen_pulsar_2b` — habit, 64 px

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
  "color_image_url": "docs/art/palette_48.png",
  "item_descriptions": [
    "the same cell escalated, the single ring split into two smaller counter turning half rings; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow"
  ],
  "negative_description": "photorealistic, 3d render, smooth vector art, anti-aliased edges, gradient mesh, machinery, gears, screws, circuit board, computer screen, cables, anatomical brain diagram, medical illustration, text, watermark, signature",
  "seed": 7051,
  "size": 64,
  "view": "top-down"
}
```

**Prompt**

```text
the same cell escalated, the single ring split into two smaller counter turning half rings; organic neural tissue, curved fibrous forms, no mechanical parts, no panels or screws, not a literal brain or organ; 1px outline in a darker shade of the same hue, never black; three shading tones with the shadow tone hue-shifted at least 20 degrees toward cool; no dithering, no anti-aliasing, no gradient banding; colours taken only from the supplied reference palette image; no text, no numbers, no UI, no logo, no frame, no baked drop shadow
```

---

## Pořadí a závislosti

| # | fáze | id | závisí na | dávka |
|---|---|---|---|---|
| 1 | 0 | `terrain_axon` | `terrain_tissue` | `tileset_terrain_axon` |
| 2 | 0 | `terrain_tissue` | — | `tileset_terrain_axon` |
| 3 | 1 | `decor_knot` | `terrain_tissue` | `prop_01` |
| 4 | 1 | `decor_synapse` | `terrain_tissue` | `prop_01` |
| 5 | 1 | `prop_dopamine` | `terrain_tissue` | `prop_01` |
| 6 | 1 | `prop_spawn` | `terrain_tissue` | `prop_01` |
| 7 | 1 | `terrain_spine` | `terrain_tissue` | `tileset_terrain_spine` |
| 8 | 2 | `focus_timer` | `terrain_spine` | `habit_02` |
| 9 | 2 | `prop_focus_core` | `terrain_tissue` | — |
| 10 | 3 | `accountability` | `focus_timer` | `habit_03` |
| 11 | 3 | `anchor` | `focus_timer` | `habit_03` |
| 12 | 3 | `broccoli_knight` | — | — |
| 13 | 3 | `clickbait` | — | — |
| 14 | 3 | `exercise` | `focus_timer` | `habit_03` |
| 15 | 3 | `focus_pillar` | `focus_timer` | `habit_03` |
| 16 | 3 | `focus_timer_2` | `focus_timer` | `habit_04` |
| 17 | 3 | `mindfulness` | `focus_timer` | `habit_04` |
| 18 | 3 | `real_hobby` | `focus_timer` | `habit_04` |
| 19 | 3 | `zen_pulsar` | `focus_timer` | `habit_04` |
| 20 | 3 | `accountability_2` | `accountability` | `habit_05` |
| 21 | 3 | `adult_content` | `clickbait` | — |
| 22 | 3 | `autoplay` | `clickbait` | — |
| 23 | 3 | `avocado_monk` | `broccoli_knight` | — |
| 24 | 3 | `chilli_berserker` | `broccoli_knight` | — |
| 25 | 3 | `comparison` | `clickbait` | — |
| 26 | 3 | `doomscroll` | `clickbait` | — |
| 27 | 3 | `energy_drink` | `clickbait` | — |
| 28 | 3 | `exercise_2` | `exercise` | `habit_05` |
| 29 | 3 | `fomo` | `clickbait` | — |
| 30 | 3 | `garlic_mage` | `broccoli_knight` | — |
| 31 | 3 | `group_chat` | `clickbait` | — |
| 32 | 3 | `jackpot` | `clickbait` | — |
| 33 | 3 | `just_one_more` | `clickbait` | — |
| 34 | 3 | `mindfulness_2` | `mindfulness` | `habit_05` |
| 35 | 3 | `notification` | `clickbait` | — |
| 36 | 3 | `phantom_buzz` | `clickbait` | — |
| 37 | 3 | `real_hobby_2` | `real_hobby` | `habit_05` |
| 38 | 3 | `social_media_binge` | `clickbait` | — |
| 39 | 3 | `zen_pulsar_2a` | `zen_pulsar` | `habit_06` |
| 40 | 3 | `zen_pulsar_2b` | `zen_pulsar` | `habit_06` |

