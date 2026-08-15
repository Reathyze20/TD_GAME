# Midjourney prompty pro level art

Cíl: vygenerovat concept art, který jde **beze změny kódu** nasadit do Godotu a dál rozšiřovat
o další levely. Proto jsou prompty stavěné na dvě konkrétní věci, které hra už umí načíst:

| Co            | Kam to jde                                  | Formát, který kód očekává                          |
|---------------|---------------------------------------------|----------------------------------------------------|
| Level background | `res://assets/background.jpg` (`game.gd:134`) | 1920×1080 plát, nebo dlaždice 512² s `--tile`     |
| Level high ground | `res://assets/terrain/high_ground_atlas.png` | **přesně 192×192 px**, 4×4 dlaždic po 48 px, s alfou |

Tyhle dva soubory jsou jediné, co se mění. TileSet `data/terrain/high_ground_tileset.tres`
odkazuje na atlas **cestou**, ne obsahem — takže přepsáním PNG se automaticky přemaluje
celý terén ve hře i v map editoru. Nic dalšího se nesahá.

---

## 0. Než začneš — proč to má tuhle podobu

**Proč `--tile`.** Midjourney s tímhle přepínačem generuje texturu, které navazuje sama na
sebe na všech čtyřech okrajích. Bez toho uvidíš ve hře viditelné švy v místě, kde se obrázek
opakuje. Pro background i pro povrch high groundu je to povinné.

**Proč přesně 192×192.** Grid hry je 40×19 buněk po 48 px (`scripts/data.gd:11`).
`texture_region_size` v TileSetu je 48 px, takže atlas musí být 4×48 = 192 px na stranu.
Větší atlas Godot nezmenší — vykreslil by dlaždice přerostlé přes sousední buňky.
Generuj tedy v MJ na 1024² a **zmenši až na konci** na 192².

**Proč to znamená hrubé tvary.** Jedna dlaždice je ve hře 48×48 px. Cokoliv jemnějšího než
~4 px se při zmenšení z 1024 na 192 rozmaže do šedi. Prompty proto explicitně říkají
*bold low-frequency shapes* a *readable at small size* — to není omáčka, to je požadavek.

**Proč `--sref`.** Background a high ground musí vypadat jako jeden svět. Nejdřív vygeneruj
background, ulož si URL finálního obrázku a všechny další prompty pusť s
`--sref <ta URL> --sw 100`. Midjourney převezme paletu, materiál i míru stylizace.
Tohle je ta jediná věc, která zajistí, že level 2 a 3 nebudou vypadat z jiné hry.

---

## 1. Paleta — vyber si jednu, ostatní jsou pro další levely

Hra má definovanou paletu v `scripts/ui.gd:18`. Držet se jí znamená, že HUD, sprity a mapa
sedí dohromady.

> ⚠️ **`[PALETTE]` je zástupka, ne součást promptu.** Musíš ji fyzicky přepsat celým řádkem
> jedné z variant níž. Když ji tam necháš, Midjourney ji přečte jako text, barvu si vymyslí
> a dostaneš béžový kámen. V sekci 2 je jedna varianta předvyplněná k rovnou zkopírování.

**A — Deep Focus** (sedí na současný `background.jpg` a na celé UI, doporučeno pro Level 1)
```
near-black navy base #0a0c14, desaturated indigo mid-tones #161b2c, cool slate #262c40 structure, sparse pale teal light traces #7ef2e6, occasional soft blue accent #9bd0ff
```

**B — Overload** (přehlcený mozek — sedí na Level 2 „The Feed Fights Back")
```
deep bruised maroon base #1a0c14, warm magenta tissue mid-tones #3a1a2e, inflamed pink structure, hot amber light traces #ff8a3d, occasional angry red accent #ff6b6b
```

**C — Recovered** (klidný, uzdravený mozek — pro pozdější level nebo victory obrazovku)
```
deep forest-navy base #0a1410, muted sage mid-tones #16241c, soft mint structure, gentle green light traces #7cffb2, occasional pale teal accent #7ef2e6
```

---

## 2. PROMPT — Level background (dlaždicová verze, doporučená)

```
seamless tileable top-down texture of living brain matter fused with dormant circuitry, soft cortical folds, thin myelin fibers, faint dendrite filaments, shallow engraved grid channels running orthogonally, deep bruised maroon base #1a0c14, warm magenta tissue mid-tones #3a1a2e, inflamed pink structure, hot amber light traces #ff8a3d, occasional angry red accent #ff6b6b, flat orthographic overhead view, completely even ambient light, no cast shadows, deliberately low contrast and quiet, subtle organic noise, clean stylized 2D game art, unobtrusive background plate for a tower defense map --tile --ar 1:1 --style raw --s 100 --v 7 --no text, letters, numbers, watermark, signature, characters, creatures, buildings, props, perspective, horizon, vignette, harsh highlights, strong shadows, busy detail, focal point
```

`--no focal point` a `--no busy detail` tam jsou schválně: background nesmí přetahovat
pozornost, po něm chodí nepřátelé a stojí na něm věže.

## 2b. PROMPT — Level background (celoobrazovkový plát 16:9)

Použij, pokud chceš pro každý level jeden unikátní backdrop místo opakované dlaždice.
Hra ho kreslí přes celé plátno, takže se generuje rovnou v poměru obrazovky.

```
full-screen top-down backdrop for a tower defense level, a vast cross-section of living brain tissue fused with dormant circuitry, cortical folds and myelin fiber bundles, faint synaptic nodes, thin engraved grid channels, colour palette strictly limited to five values: [PALETTE], overall very dark and moody, flat shaded stylized 2D game art, hand-painted matte surface, large soft shapes with minimal fine detail, flat orthographic overhead view, even ambient light, no cast shadows, composition deliberately calm and empty in the centre with detail concentrated toward the edges and corners, low contrast so gameplay sprites read clearly on top --ar 16:9 --style raw --s 100 --v 7 --no photorealistic, photograph, macro photography, stone, rock, concrete, marble, cracked earth, dry mud, sand, beige, tan, brown, white, text, letters, numbers, watermark, signature, characters, creatures, buildings, towers, UI, perspective, horizon, vignette, harsh highlights, strong shadows, fine cracks, centre focal point
```

Výstup upscaluj na 1920×1080 a ulož jako `assets/background.jpg` (přepiš stávající).

---

## 3. PROMPT — High ground: povrch (základ pro atlas)

Tohle je **ta důležitá varianta**. Negeneruje 16 dlaždic, ale jeden bezešvý materiál povrchu
plošiny — z něj se atlas složí skriptem, pixelově přesně. Viz sekce 6.

```
seamless tileable top-down texture of a raised neural plateau, compacted brain tissue armoured with hardened glial plating, tightly packed myelin ridges, matte ceramic-like surface, clearly lighter, cooler and denser than the surrounding soft tissue floor, colour palette strictly limited to five values: [PALETTE], but shifted two steps brighter and more saturated, flat shaded stylized 2D game texture, hand-painted matte surface, bold low-frequency shapes readable at small size, flat orthographic overhead view, even ambient light, no cast shadows --tile --ar 1:1 --style raw --s 90 --v 7 --sref <URL_BACKGROUNDU> --sw 100 --no photorealistic, photograph, macro photography, stone, rock, concrete, marble, cracked earth, dry mud, sand, beige, tan, brown, white, text, letters, watermark, characters, props, perspective, vignette, drop shadow, thin detail, fine cracks, fine noise
```

Klíčová fráze je *clearly lighter, cooler and denser than the surrounding floor* — high ground
musí být na první pohled odlišitelný od podlahy, protože nese informaci „sem se dá stavět
a tudy nepřítel neprojde".

## 4. PROMPT — High ground: hrana a zkosení

Referenční obrázek jedné plošiny, ze kterého se vezme způsob zpracování okraje
(fazeta, rim light, kontaktní stín). Skript ho pak aplikuje na všech 16 dlaždic.

```
a single raised neural platform slab seen exactly from directly above, orthographic top-down, square footprint filling the frame, thick chamfered bevelled edge, crisp pale rim highlight along the top and left edges, soft dark contact edge along the bottom and right, hardened glial plating surface, colour palette strictly limited to five values: [PALETTE], shifted brighter, faint light glow tracing the outline, flat shaded stylized 2D game asset, hand-painted matte surface, isolated on flat pure black, perfectly centered, no perspective distortion, no cast shadow --ar 1:1 --style raw --s 50 --v 7 --sref <URL_BACKGROUNDU> --sw 100 --no photorealistic, photograph, stone, rock, concrete, marble, beige, tan, brown, white, text, watermark, background scenery, characters, perspective, tilt, multiple objects
```

## 5. PROMPT — High ground: celý 4×4 atlas (concept, ne finál)

Midjourney **neumí** vygenerovat mřížku 16 dlaždic v pixelově přesném rastru a bez alfy.
Tenhle prompt slouží k tomu, aby sis vizuálně odsouhlasil, jak mají napojení vypadat —
finální atlas z něj nedělej, dělej ho postupem ze sekce 6.

```
game tileset asset sheet, a strict 4 by 4 grid of 16 separate square tiles, identical size, identical even spacing, pure flat black background between tiles, each tile is a raised neural platform block seen straight from directly above, orthographic, chamfered edges with a pale rim light, the tiles show connector arms reaching toward different edges: isolated pillars, straight corridors, right-angle corners, T junctions, and one full four-way cross, hardened glial plating surface, colour palette strictly limited to five values: [PALETTE], shifted brighter, flat shaded stylized 2D game art, flat even lighting, no perspective, no cast shadows --ar 1:1 --style raw --s 50 --v 7 --sref <URL_BACKGROUNDU> --sw 100 --no photorealistic, photograph, stone, rock, concrete, beige, tan, brown, white, text, labels, numbers, watermark, drop shadows, perspective, background scenery, characters, uneven spacing
```

---

## 6. Cesta z Midjourney do Godotu

### Background
1. Upscale finálního obrázku v MJ.
2. Dlaždicová verze → zmenši na 512×512, ulož jako `assets/terrain/bg_tile.png`.
   Celoobrazovková verze → 1920×1080, přepiš `assets/background.jpg`.
3. Dlaždici ve scéně nasadíš přes `TextureRect` se `stretch_mode = Tile`, nebo přes
   `Sprite2D` s `texture_repeat = TEXTURE_REPEAT_ENABLED`. Celoobrazovkový plát se načte
   sám, protože `game.gd` už tu cestu zná.

### High ground
Atlas musí být 192×192 px, 4×4 dlaždic po 48 px, **s průhledností** tam, kde plošina není.
Midjourney alfu neumí — proto tenhle postup:

1. Z promptu 3 vezmi bezešvý povrch, zmenši na 48×48 (nebo 96×96 a nech skript downsamplovat).
2. Z promptu 4 vezmi hranu jako referenci vzhledu.
3. Skript `tools/build_terrain_tileset.gd` už dneska kreslí těch 16 dlaždic proceduálně
   (jen jako barevné placeholdery). Rozšíří se tak, aby místo plné barvy vzorkoval tvůj
   MJ povrch a na okraje maskoval fazetu podle bitmasky. Výsledek je pixelově přesný atlas
   se správnou alfou, kde napojení sedí na milimetr.

Rozložení slotů v atlasu (tohle **musí** sedět, jinak budou ve zdech díry) —
`bit 1 = nahoru, 2 = doprava, 4 = dolů, 8 = doleva`, pozice `x = index % 4, y = index / 4`:

```
        x=0            x=1            x=2            x=3
y=0   0 samostatný   1 ↑            2 →            3 ↑→
y=1   4 ↓            5 ↑↓ svislá    6 →↓           7 ↑→↓
y=2   8 ←            9 ↑←          10 ←→ vodorovná 11 ↑→←
y=3  12 ↓←          13 ↑↓←         14 →↓←         15 ✚ kříž
```

Slot 15 je vnitřek velké plošiny, slot 0 osamocený pilíř. Zdroj: `tools/build_terrain_tileset.gd:20`.

---

## 7. Jak z toho udělat další levely

Tohle je celý smysl toho, proč se generuje materiál a ne hotová mapa:

1. Vygeneruj **jednou** background pro Level 1 a ulož si jeho URL jako master `--sref`.
2. Pro každý další level pusť ty samé prompty, jen vyměň `[PALETTE]` (sekce 1) a přidej
   jednu tematickou frázi navíc — `inflamed and swollen tissue` pro overload level,
   `scarred and healing tissue` pro pozdní level.
3. `--sref` drž pořád stejný. Dostaneš jiný nádech, ale stejnou hru.
4. Layout mapy se **negeneruje v Midjourney** — ten se maluje v `scenes/MapEditor.tscn`
   nad tímhle tilesetem. Midjourney dodává materiál, editor dodává tvar. Proto lze
   přidat level 5 bez jediného nového obrázku.

---

## 8. Tilemapa přes Midjourney — s vektorovými koncepty jako předlohou

Od chvíle, co existuje `assets/src/concepts/`, se dá Midjourney zadat úplně jinak: místo
popisu slovy mu dáš **hotový obrázek** a řekneš „tohle, ale s materiálem". Tím odpadá
většina hádání, kvůli kterému minule vyšel béžový kámen.

Ve složce jsou na to připravené předlohy v 1024×1024:
`_mj_ref_1_veins.png` … `_mj_ref_6_fracture.png`.

### Prompt A — materiál povrchu (tohle použij především)

Nejvyšší výtěžnost ze všech. Negeneruje dlaždice, ale bezešvý materiál, ze kterého se
dlaždice složí v Inkscape (postup níž). Žádnou předlohu nepotřebuje.

```
seamless tileable top-down texture of a raised neural platform surface, compacted brain tissue armoured with hardened glial plating, packed myelin ridges and faint synaptic nodes, colour palette strictly limited to five values: deep slate indigo #2d334a base, cool blue-grey #454f73 mid-tones, pale steel blue #5a6690 highlights, near-black #1b2033 recesses, one sparse teal #7ef2e6 accent node, flat shaded stylized 2D game texture, hand-painted matte surface, bold low-frequency shapes that stay readable when scaled down to 48 pixels, flat orthographic overhead view, even ambient light, no cast shadows --tile --ar 1:1 --style raw --s 90 --v 7 --no photorealistic, photograph, macro photography, stone, rock, concrete, marble, cracked earth, dry mud, sand, beige, tan, brown, white, text, letters, watermark, characters, props, perspective, vignette, drop shadow, fine cracks, thin detail
```

### Prompt B — celý 4×4 list podle předlohy

Nahraj do Midjourney jeden z `_mj_ref_*.png`, zkopíruj jeho URL a dej ji **na začátek**
promptu:

```
<URL_PREDLOHY> game tileset sheet in exactly the same 4 by 4 grid layout and the same tile boundaries as the reference image, sixteen square tiles, each tile a raised neural platform seen from directly above, keep the bevelled edges and the pale rim light exactly where the reference has them, but replace the flat surface with richly detailed brain tissue armoured with glial plating, colour palette strictly limited to the reference colours, deep slate indigo and cool blue-grey with one sparse teal accent, flat shaded stylized 2D game art, hand-painted matte surface, flat orthographic top-down, even lighting, no cast shadows --iw 2 --ar 1:1 --style raw --s 80 --v 7 --no photorealistic, photograph, stone, rock, concrete, beige, tan, brown, white, text, labels, numbers, watermark, drop shadows, perspective, background scenery, characters, uneven spacing
```

`--iw 2` je váha předlohy (rozsah 0–3, výchozí 1). Dvojka drží kompozici dost pevně na to,
aby zůstala mřížka 4×4, a přitom nechá Midjourney přemalovat povrch.

**Počítej s tím, že rastr nebude přesný.** Ani s `--iw 2` netrefí hranice dlaždic na pixel
a alfu neumí vůbec. Výstup z promptu B je předloha, ne hotový atlas.

### Jak z toho udělat použitelný atlas — hybrid

Tohle je ta část, která rozhoduje, jestli z Midjourney něco doopravdy dostaneš do hry.
Nech Midjourney dělat **texturu** a šablonu dělat **geometrii**:

1. Z promptu A si upscaluj nejlepší výsledek a zmenši ho na **48×48 px**. Je to bezešvý
   materiál jedné dlaždice.
2. Otevři kterýkoliv koncept z `assets/src/concepts/`.
3. `Ctrl+Shift+L` → přepni se na vrstvu **2 povrch** a smaž z ní všechny klony.
4. `Ctrl+I` (Import) → vyber tu 48×48 texturu → zvol **Vložit** (embed), ne odkaz.
   Jinak ti PNG bude chybět, až soubor přesuneš.
5. Umísti ji přesně na `x=144, y=144` (slot 15) — souřadnice přepiš v horní liště
   nebo v `Ctrl+Shift+X`. Velikost musí být přesně 48×48.
6. Označ ji a `Alt+D` (klon), klon posuň přes `Shift+Ctrl+M` → Posun → Relativně
   o násobky 48. Opakuj na všech šestnáct pozic.
7. Vrstvy **3 hrany tmavé** a **4 hrany světlé** nech nahoře — fazety se vykreslí přes
   texturu a plošina dostane objem, který Midjourney sám neudělá.
8. Export: `Esc` → `Ctrl+Shift+E` → **Page** → **192 × 192** → PNG →
   `assets/terrain/high_ground_atlas.png`.

Výsledek má materiál z Midjourney a geometrii z šablony — tedy pixelově přesné hranice,
správnou alfu a napojení, které sedí. Ani jedno z toho by čistý Midjourney nedal.

---

## 9. Mozková tkáň — opravené prompty

První pokus vyšel jako kovové panely s prasklinami. Za to mohly dvě věci v promptu
a je dobré vědět které, protože stejnou chybu uděláš zítra znovu:

- **`glial plating`** doslova znamená „obrněné destičky". Midjourney to vzal vážně.
  Slovo *plating* z promptu musí pryč.
- **Předloha měla praskliny.** `_mj_ref_1_veins.png` i `_mj_ref_6_fracture.png` mají
  na povrchu lomené čáry a s `--iw 2` je model poslušně zopakoval. Předloha řídí
  výsledek víc než text — když v ní je struktura, kterou nechceš, text ji nepřebije.

Slovník, který mozek naopak vyvolá: `cerebral cortex`, `gyri`, `sulci`,
`convoluted folds`, `winding tissue ridges`, `soft moist organic tissue`.

### Prompt A-mozek — materiál (použij především)

```
seamless tileable top-down texture of living cerebral cortex, dense convoluted brain folds, winding gyri ridges and deep sulci grooves, soft moist organic tissue with a subtle translucent sheen, colour palette strictly limited to five values: deep plum #5c2a40 grooves, muted rose #a85c78 mid tissue, warm pale pink #e8a0b4 raised folds, near-black maroon #2a0f1c shadow, one sparse teal #7ef2e6 synaptic spark, flat shaded stylized 2D game texture, hand-painted matte surface, bold low-frequency folds that stay readable when scaled down to 48 pixels, flat orthographic overhead view, even ambient light, no cast shadows --tile --ar 1:1 --style raw --s 90 --v 7 --no photorealistic, photograph, macro photography, medical scan, gore, blood, wet specimen, stone, rock, concrete, metal, armour, plating, panels, cracks, crackle, spiderweb, beige, tan, brown, white, text, watermark, characters, perspective, vignette, drop shadow, fine detail
```

### Prompt B-mozek — celý 4×4 list

Jako předlohu nahraj **`_mj_ref_7_cortex.png`** — má správnou tématiku i správný rastr,
takže Midjourney nemá odkud vzít praskliny.

```
<URL_PREDLOHY> game tileset sheet, keep exactly the same 4 by 4 grid layout, the same tile boundaries and the same bevelled edges as the reference image, sixteen square tiles, each tile a raised platform of living brain tissue seen from directly above, dense convoluted cerebral cortex, winding gyri ridges and deep sulci grooves, soft moist organic tissue, warm pale pink raised folds over deep plum grooves, a crisp teal rim light along the bevelled edges exactly as in the reference, flat shaded stylized 2D game art, hand-painted matte surface, flat orthographic top-down, even lighting, no cast shadows --iw 2 --ar 1:1 --style raw --s 80 --v 7 --no photorealistic, photograph, medical scan, gore, blood, stone, rock, concrete, metal, armour, plating, panels, cracks, crackle, beige, tan, brown, white, text, labels, numbers, watermark, drop shadows, perspective, background scenery, characters, uneven spacing
```

### Paleta tkáně

Doplněk k sekci 1 — tahle paleta patří **plošině**, ne podlaze. Podlaha zůstává tmavě
modrá (`#0a0c14`), a právě ten kontrast je funkční: hráč musí na první pohled poznat,
kam se dá stavět.

```
deep plum #5c2a40 grooves, muted rose #a85c78 mid tissue, warm pale pink #e8a0b4 raised folds, near-black maroon #2a0f1c shadow, one sparse teal #7ef2e6 synaptic spark
```

Pro level 2 („The Feed Fights Back") vyměň za zanícenou variantu:
`#4a1224` / `#b0435c` / `#ff8a3d` / `#26060f`, jiskra `#ffd479`.

### Proč prompt B pravděpodobně zahodíš

Až obojí uvidíš vedle sebe, hybrid z promptu A skoro jistě vyhraje. Prompt B je tu proto,
aby sis to ověřil sám a ne proto, že bych ho doporučoval — šestnáct dlaždic, které si musíš
ručně narovnat do rastru, je víc práce než jedna textura, kterou naklonuješ.

---

# ČÁST II — Pixel art

Jiný režim práce než všechno výše. Midjourney tu dělá **jen předlohu**, kterou překreslíš
rukou v pixel art editoru. Proto nemusí být bezešvá, nemusí mít alfu ani přesný rastr —
stačí, aby ukázala kompozici, barvy a náladu. Tohle je disciplína, ve které Midjourney
opravdu funguje, protože jeho slabiny nese tvoje ruka.

## 10. Měřítko — přečti dřív než začneš kreslit

Hra běží na 1920×1080 s dlaždicí 48 px. Kreslit pixel art přímo v téhle velikosti nedává
smysl: 48×48 je na ruční pixel art zbytečně velké plátno a výsledek nebude vypadat jako
pixel art, ale jako rozmazaná ilustrace.

**Kresli ve třetinovém rozlišení a zvětši 3×.**

| Co | Kresli v | Zvětšit | Výsledek |
|---|---|---|---|
| Dlaždice terénu | **16 × 16** | 3× | 48 × 48 |
| Pozadí levelu | **640 × 360** | 3× | 1920 × 1080 |

Trojka vychází přesně, 48/3 = 16 a 1920/3 = 640. Jeden nakreslený pixel bude na obrazovce
čtvereček 3×3 — dost velký, aby byl vidět, dost malý, aby se dal nakreslit obličej věže.
A 16×16 dlaždice je standardní pixel art velikost, na kterou najdeš tisíc tutoriálů.

Zvětšuj **vždy metodou Nearest Neighbor**, nikdy bilineárně, jinak si pixely rozmažeš.

### Godot to musí vědět taky

Projekt teď nemá nastavený filtr textur, takže jede na výchozím **lineárním** — ten by ti
pixel art rozmazal. Před prvním importem přepni:

`Project → Project Settings → Rendering → Textures → Canvas Textures → Default Texture Filter` → **Nearest**

Bez toho bude všechno, co nakreslíš, vypadat měkce a nepochopíš proč.

## 11. PROMPT — pozadí levelu (začni tímhle)

```
top-down pixel art background for a tower defense game level, 16-bit era game art, a dark neural circuit landscape seen from directly above, faint orthogonal data channels, dormant synaptic nodes, thin glowing traces, orthographic straight-down view, drawn at a very low resolution with large chunky clearly visible square pixels, hard pixel edges, no anti-aliasing, strictly limited palette of about twelve colours: near-black navy #0a0c14, deep indigo #161b2c, slate #262c40, steel blue #3d5a99, pale teal #7ef2e6, soft blue #9bd0ff, subtle ordered dithering where tones meet, deliberately calm and low contrast, empty and quiet in the centre with detail concentrated toward the edges and corners --ar 16:9 --style raw --s 120 --v 7 --no smooth shading, gradients, anti-aliasing, blur, soft edges, photorealistic, 3d render, vector art, isometric, perspective, horizon, text, letters, numbers, watermark, characters, creatures, buildings, towers, UI, high contrast, busy centre
```

`--no isometric` tam musí být. Pixel art tower defense je v trénovacích datech skoro vždycky
isometrický a tahle hra je čistě shora dolů — bez toho zákazu dostaneš kosočtverce.

`large chunky clearly visible square pixels` je druhá klíčová fráze. Bez ní Midjourney
udělá jemný faux-pixel detail, který ve 640×360 nenakreslíš.

## 12. PROMPT — dlaždice terénu (až po pozadí)

```
pixel art tile set study for a top-down tower defense game, several variations of a raised platform block made of neural circuitry, each seen from directly above, orthographic, chunky visible square pixels, hard pixel edges, no anti-aliasing, clear one pixel dark outline around each block, a bright pixel rim highlight along the top and left edges and a dark edge along the bottom and right, strictly limited palette: slate indigo #2d334a body, cool blue grey #454f73, pale steel #5a6690 highlight, near-black #1b2033 shadow, one sparse teal #7ef2e6 accent, bold simple shapes readable at sixteen pixels square, plain dark background between the blocks --ar 1:1 --style raw --s 100 --v 7 --no smooth shading, gradients, anti-aliasing, blur, photorealistic, 3d render, isometric, perspective, drop shadow, text, labels, numbers, watermark, characters, tiny detail
```

Tenhle si nech na potom. Pozadí určí paletu a náladu; dlaždice se pak ladí proti němu,
ne naopak.

## 13. Jak z předlohy udělat asset

1. Vyber výsledek, upscaluj, ulož do `assets/src/mj/`.
2. V pixel art editoru (Aseprite, nebo zdarma LibreSprite / Piskel) založ plátno
   **640×360** pro pozadí nebo **16×16** pro dlaždici.
3. Předlohu si vlož jako **spodní referenční vrstvu** a ztlum ji na ~40 %. Nekresli přes ni
   obtahováním — dívej se na ni a maluj vedle. Obtahování AI obrázku dá vždycky nečitelný
   výsledek, protože ta předloha nemá pixelovou logiku.
4. Drž se palety z `scripts/ui.gd`. Dvanáct barev je hodně, ne málo.
5. Export → zvětšit 3× Nearest Neighborem → do `assets/`.
6. Dlaždice pak skládej do atlasu 192×192 stejnou šablonou jako doteď
   (`assets/src/high_ground_atlas_template.svg`, rozložení slotů v sekci 6).
