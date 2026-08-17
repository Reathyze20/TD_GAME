# ART_PIPELINE.md — jak v tomhle projektu vzniká grafika

Playbook pro budoucí práci (psáno pro Claude i pro člověka). Tohle je **aktuální** postup;
`ART_PROMPTS.md` (Midjourney) a `ART_INKSCAPE.md` (vektor) jsou překonané slepé uličky —
nechány jako historie, proč to neděláme jinak.

---

## 1. Výtvarná řeč (neporušovat)

- **Podlaha shora, postavy zpředu, zdi s viditelnou přední stěnou** — tříčtvrteční pohled
  (Zelda, Stardew). Drží to pohromadě díky kontaktnímu stínu pod každou postavou; bez něj
  to čte jako koláž. **Izometrie NE** (zkoušeno a zamítnuto). Extrudované stěny naopak
  ANO — od 15. 8. 2026, viz §7. První pokus selhal na metodě, ne na záměru.
- **Téma: MYSL, ne doslova mozek** (upřesněno 2026-08-14). Terén může být tkáň, ale
  slovník je širší — pozornost, vzpomínky, myšlenky, návyky. Rekvizity to nesou:
  rozbité telefony, prášky, hrnek, budík, žárovka, lepíky, kniha, zavřené oko.
  Věže = tmavé „implantáty" s teal akcenty. Nepřátelé = syté barvy podle `def.color`.
- **Vše je pixel art na společném rastru** (viz §2). Hladká vektorová čára nebo
  anti-aliasing kdekoli v poli = chyba. Ploché průhledné výplně (tint výseče) jsou OK.

## 2. Rastr — nejdůležitější pravidlo

Herní buňka je **48 px**. Art se kreslí malý a zvětšuje **celočíselně, NEAREST**:

| vrstva | autorská velikost | zvětšení | px na obrazovce / art px |
|---|---|---|---|
| pozadí | 384×216 | ×5 | 5 (hrubší = hloubka, záměr) |
| terén | 16 px / dlaždici | ×3 | 3 |
| věže | 24×24 | ×2 | 2 |
| nepřátelé (běžní) | **32×32** | ×2 | 2 |
| nepřátelé (boss) | **64×64** | ×2 | 2 |
| efekty (kód) | — | bloky 3 px | 3 |

- **Co se vejde do buňky, musí dělit 48**: 16 ✓, 24 ✓, 48 ✓ (48/32 = 1,5 → rozmazání).
  Platí na terén a věže.
- **Nepřátelé jsou z tohohle pravidla vyjmutí schválně.** Nesedí v buňce — kreslí se na
  64 px, tedy 4/3 buňky, aby přerostli mřížku a bylo vidět, že po ní nepatří. 32 × 2 = 64
  vychází celočíselně, což je jediné, na čem záleží. Bestiář byl půl dne na 16 px
  a vrátil se nahoru: na 32 px obrazovky nepřežila srst ani zuby, kvůli kterým ty potvory
  stojí za podívání (`distraction_animator.gd:224`). PixelLab pod 32×32 negeneruje vůbec,
  takže se generuje na 64 a jednou se půlí (`sprite_16.halve()`).
- Mísit hustoty na jednom objektu = „hrozně ostrý proti zbytku" (opakovaná zpětná vazba).
- Projekt kreslí s `CanvasItem.TEXTURE_FILTER_NEAREST` (nastavuje se per-node v `_ready`).

## 3. PixelLab — generátor, který funguje

MCP server `pixellab` je v configu (`claude mcp list`). Token je v `~/.claude.json`.
Pokud nástroje nejsou v session načtené, funguje přímé volání — ve scratchpadu minulé
session `mcp.py` + `pl.py` (mini MCP klient přes HTTP; snadno se napíše znovu:
initialize → tools/call, SSE odpovědi, hlavička `Mcp-Session-Id`).

**Osvědčené nástroje a nastavení:**

**SCHVÁLENÝ VÝTVARNÝ SMĚR (2026-08-14):** synaptická podlaha ze zlatých a elektricky
modrých nervových vláken + vyvýšená mozková kůra (šedobéžová gyri/sulci) s **organickými
pilíři podél spodní hrany** — ty dělají plasticitu, zeď čte jako plošina. Vzniklo z
uživatelova promptu; přesné zadání je v popisu tilesetu `7be1d47a` na PixelLab účtu a
render v `_styl_final.png`. Když budeš dělat nový terén, drž tenhle popis.

- **`create_tiles_pro` s `tile_feature:"tileset"` — TOHLE POUŽÍVEJ NA TERÉN** (od
  2026-08-14). Proti `create_topdown_tileset` má dvě zásadní výhody: vrací
  **`placement_rules` s explicitní maskou** (`NW<<3|NE<<2|SW<<1|SE`, nastavený bit =
  PRVNÍ terén), takže odpadá hádání polarity, které opakovaně obracelo zdi a podlahu;
  a zvládá **výrazně vyšší kontrast**. Použité zadání viz `_tilespro_mapa.png`.
  `tile_size: 24` → ×2 = naše buňka 48. Volá se `get_tiles_pro(tile_id=...)`,
  NE `tiles_id`. Cena 20–40 generací.
  **Past:** každá dlaždice má vlastní tmavý obrys po obvodu, takže poskládané tvoří
  viditelnou mřížku. Řeší se bez generování — okrajové pixely se přepíšou sousední
  vnitřní řadou (edge-extend); obrys tkáně kolmý na hranu zůstane, linka zmizí.
- `create_tiles_pro` bez `tile_feature` = několik NEZÁVISLÝCH dlaždic z číslovaného
  seznamu („1). tráva 2). hlína…"), to je zdroj variant povrchu. Piš SILNÁ slova —
  „faint / subtle / pale" doslova vyrobí prázdné dlaždice (ověřeno).
- `create_topdown_tileset` — starší cesta, umí zaoblené rohy (`shape_style: "round"`),
  což tiles_pro neumí. Nastavení, které fungovalo:
  `tile_size 16`, `transition_size 0`, **Side Wall Thickness 0** (jinak přidá boční
  stěnu!), Enhance descriptions **vypnout** (přepíše barvy → kámen/bláto), transition
  description přepsat (default je „crumbling muddy dirt" past). Export „Godot" =
  384×128 PNG, prázdno je **neprůhledná** #060621 → vyklíčovat na alfu.
- `create_map_object` — objekty 32×32 (min. 32, max. 400 px), `view: "high top-down"`,
  `outline: "single color outline"`. Pak **zmenšit ÷2 na 16 px** (PIL, NEAREST).
- `animate_object` s `mode: "v3"` — animace ke stávajícímu objektu, 6–9 snímků,
  popis pohybu anglicky („standing still" + co se hýbe). Trvá ~5–8 min, jede paralelně;
  `list_jobs` na polling.
- `create_image_pixflux` + `init_image_url` (data URL) — img2img pro pozadí; init obraz
  řídí kompozici víc než text.
- Kvóta: subscription ~2000 generací/měsíc, `get_balance`. Rate limit: pár volání/min,
  při `rate limit exceeded` počkat a zopakovat.
- **Stahování: curl, ne python urllib** — backblaze vrací urllib 403 (user-agent).

**Prompt lekce (platí pro každý generátor):** referenční obrázek přebije text; slova
jako „tile/grid" plodí mřížky; „glial" plodí pancíř; anti-photorealism negativy nutné;
generátory tíhnou k izometrii — chtít „floor tile / seen from directly above".

**Midjourney jako zdroj konceptů (funkční role MJ):** MJ neumí tilesety ani skutečný
pixel art, ale umí siluety a náladu. Postup: MJ koncept (plochý 2D, „flat shaded
stylized 2D game art, bold silhouette, thick dark outline", --style raw, --no
photorealistic/3D/isometric/**pixel art**, Personalization OFF) → ořez na čtverec,
zmenšit → `create_image_pixflux` s `init_image_url` (data URL; strength ~50–70) →
NEAREST na cílový rastr. Koncept řídí kompozici, pixflux drží mřížku. Barvy brát
z `def.color` v datech, ať sprite ladí s aurami a HUDem.

## 3b. Rodina příšer — vizuální bible

> ⚠️ **SMĚR SE MĚNÍ (17. 8. 2026 večer, rozpracované).** Junk food je **odpískaný** —
> uživatel: „ty postavy nemusí mít vzhled jako junk food, to to jen kazí". Sekce níž
> ho ještě popisuje; než se dopíše, drž se tohohle:
>
> **Tvor + zařízení, ne potravina.** Tělo je bytost v `def.color`, identitu nese
> hardware nebo prvek rozhraní sražený do masa. Ověřené příklady, které fungují:
> uživatelův boss (fialový digitální titán, hlava = telefonní vizor, obrazovky jako
> pancíř, notifikační pupeny na zádech) a incognito (kapuce + svítící panel).
> Uživatel dál označil za povedený **původní čtyřdílný bestiář notifikací** ze zálohy —
> hrbatí tvorové s jedním velkým okem a rohem, bohatě stínovaní. Ti mají oči, takže
> pravidlo „bez obličeje" platí jako *doporučení*, ne jako zákaz: rozhoduje, že se
> identita čte, ne čím se čte.
>
> **Nepřegenerovávej roster, dokud tenhle bod nemá potvrzenou předlohu.** Pokus
> přepsat clickbait na „thumbnail panel místo hlavy" selhal (drátěný obdélník plovoucí
> mimo tělo, 23 generací pryč) — viz „Co selhalo" níž.

**Historie směru:** kreslená groteska (15. 8.) → junk food ve stylu obránců (17. 8. ráno,
nasazeno na 10 příšer) → tvor + zařízení (17. 8. večer, probíhá).

### Trasa Midjourney → hra (od 17. 8. 2026 nejlevnější i nejlepší)

Čtyři pokusy popsat příšeru textem do `create_character` selhaly na tom, že generátor
zahodí buď tell, nebo tělo. MJ koncept to vyřešil napoprvé — a je **dvacetkrát levnější**:

| cesta | cena | výsledek |
|---|---|---|
| `create_character` `mode:"pro"` z textu | **20 generací** | 4 pokusy, 3 nepoužitelné |
| MJ koncept → `mode:"v3"` + `reference_image_base64` | **1 generace** | sedlo napoprvé |

```
MJ (--style raw --s 150 --v 7, --no pixel art)  →  upscale, stáhnout 1024×1024
  →  flood-fill pozadí od okrajů na alfu (tolerance ~78)
  →  DRUHÝ flood na zapečenou kaluž stínu (nedotýká se okraje, první ji nechytí!)
  →  čtvercový ořez ×1,04  →  složit v 128 a jednou halve() na 64
  →  cut_floor (uříznout zem)  →  kvantizace na 24 barev  →  1px tmavý obrys
  →  create_character mode:"v3", size:64, reference_image_base64
  →  animate_character, lokomoce ŠABLONOU, attack a smrt v3 s identity-lockem
  →  halve() 64→32  →  restore_outline jedním koeficientem na celou animaci
```
Celý ten řetěz je `tools/mj_to_sprite.py`; brány, na kterých se instalace zastaví,
jsou v `GATES` tamtéž.

> 🔴 **Generuj v 64 px a půl PRÁVĚ JEDNOU.**
> Toto je dvakrát opravená kapitola, tak pozor na obě strany:
>
> **Chyba A (ráno):** MJ malba → 64 → animace → *druhé* půlení na 32. `halve()` je dobrý
> na **jedno** zmenšení; nativní pixel art z PixelLabu druhé půlení snese, ale zmenšená
> malba ne — z notifikace bylo lízátko, z clickbaita růžová hromada.
>
> **Chyba B (moje přestřelená oprava):** předloha rovnou v 32 px. V 32 px **nemá
> generátor kam nakreslit obrys** a postava vyjde jako drobek: notifikace 95 px hmoty
> a rozdíl tělo/obrys 2,9 proti 451 px a 21,0 u brokolice. Vypadalo to hůř než chyba A.
>
> **Správně:** předloha 64 px, postava 64 px, animace 64 px, a **jedno** půlení až na
> hotové snímky. Přesně tak vznikl roster obránců, na který se ptáš, když se ti něco
> nelíbí.

> ⚠️ **Předlohu posílej rovnou v cílovém rastru (64×64). `size` se s referencí ignoruje.**
> Schéma tvrdí „defaults to the reference's own dimensions unless size is set", ale
> `size:64` se s 256px předlohou **neprojevil** — postava vznikla 256×256. A protože cena
> v3 animace je `ceil(šířka·výška·snímky / 65536)` na směr, vyskočila z 1 generace na
> **8 na směr**: chůze na tři směry by stála 24 místo 3. Odhaleno až v UI PixelLabu.
> Postup: `961px výřez → LANCZOS na 128 → sprite_16.halve(128→64)`. Dvoukrokově proto,
> že jednorázový LANCZOS na 64 rozmaže; `halve()` srovná paletu a vytáhne salientní pixel.

- `reference_image_base64` má strop **256×256**, ale 64px PNG je jen ~7 kB base64
  a je to zároveň správný vstup (viz výš).
- **Dvě flood-fill kola, ne jedno.** MJ pod postavu maluje stín/kámen, který se nedotýká
  okraje plátna, takže ho okrajový flood minie. Druhý seed hledej jako medián
  nízkosytých středně jasných pixelů v dolní čtvrtině.
- `size:64` nastav explicitně — jinak výstup zdědí rozměr předlohy (256).

**Skripty v repu** (potřebují `PIXELLAB_TOKEN` v proměnných prostředí, do repa nepatří):

| skript | co dělá |
|---|---|
| `tools/mj_to_sprite.py` | koncept → předloha 64 px; `--test` vypíše čísla bran |
| `tools/install_pixellab.py` | postava → snímky v `assets/distractions/`, se všemi branami |
| `tools/pixellab_client.py` | přímý JSON-RPC klient (MCP se do session nenačte, viz §3) |

```
python tools/mj_to_sprite.py koncept.png ref64.png --test
```

### Čím se pixel art liší od zmenšené malby (měřitelně)

Když si stěžuješ, že něco vypadá rozbitě, tohle jsou čísla, která ten rozdíl popisují.
Měř **na 32 px**, tedy na tom, co jde do hry:

| | bbox | hmota | barev | tělo − obrys | částí |
|---|---|---|---|---|---|
| **broccoli_knight** (laťka) | 23 × 30 | 451 px | 25 | **21,0** | 1 |
| clickbait z MJ, jen LANCZOS | 27 × 28 | 540 px | **57** | 37,2 | 1 |
| notifikace generovaná v 32 px | **9 × 12** | **83 px** | 33 | **2,9** | 1 |

Dvě nezávislé vady, které se snadno spletou dohromady:
- **57 barev** = spojité přechody z malby. Vypadá to jako rozmazaná fotka mezi pixel-art
  sousedy. Léčí adaptivní paleta na 24 barev.
- **rozdíl tělo−obrys 2,9** = silueta nemá hranu a rozteče se do pozadí. Léčí 1px tmavý
  prstenec kolem siluety.

Brány, na kterých se má instalace zastavit, jsou v `mj_to_sprite.GATES`:
`barev ≤ 32`, `tělo−obrys ≥ 15`, `částí = 1`, `segmentů < 2 px nejvýš 2`, `výška ≥ 26`.
**Krytí mezi ně schválně nepatří** — škáluje s `def.radius` té příšery (clickbait
radius 14 → 48 %, notifikace radius 9 → 28,5 % a obojí je správně).

> ⚠️ **`strip_panel()` zapínej jen tam, kdes ten panel viděl.**
> Odstraňuje tmavou plochu zapečenou za postavou tak, že floodne od okraje plátna přes
> tmavé pixely — na clickbaitově smrti to sundalo 44 % nesmyslu a postavu nechalo být.
> Na notifikaci je ale **destruktivní**: ta má tmavé *tělo* a v rozkročené běžecké póze
> se okraje plátna dotýká, takže flood pokračoval do ní a v několika snímcích zbyla
> jenom hlava. Proto je ve `install64.process` vypnuté defaultně.
> Obecné pravidlo: filtr odvozený z jedné příšery ověř na druhé, než ho zapneš plošně.

> **Chybí-li směr, nechej ho chybět.** Engine spadne zpátky na jih
> (`_facing_frames`, „degrades to *always faces the camera* instead of vanishing"), což
> je **lepší než horší profil**. Clickbait dostal `sad-walk` jen na jih právě proto:
> sever i východ z něj udělaly jinou postavu (14×21 a 15×24 px proti 20×27 zepředu),
> a jedna konzistentní příšera čelem ke kameře je čitelnější než tři různé.

> **Obrys po půlení obnov, ale jednou barvou a jedním koeficientem na celou animaci.**
> PixelLab kreslí v 64 px tenčí obrys než roster obránců a `halve()` ho smíchá s tělem:
> naměřeno 12,9 (clickbait) a 13,5 (notifikace) proti 21,0 u brokolice.
> `restore_outline()` přebarví krajní pixely — **nedilatuje**, na 32 px by 1 px navíc byl
> vidět. A ztmavovat každý pixel zvlášť nejde: obrys sice sedne, ale paleta vyskočí
> (23 → 38 barev) a sprite zase vypadá jako malba. Koeficient počítej **jednou** z jedné
> referenční snímky (`outline_color()`), jinak obrys mezi snímky bliká.

### Test životaschopnosti konceptu (zadarmo, dělej ho VŽDY před generováním)

Zmenši koncept na 32 px a změř. Ověřeno na čtyřech konceptech notifikace:

| koncept | krytí | segmentů < 2 px | výsledek |
|---|---|---|---|
| pavoučí, 4 tenké nohy, měkká záře | 26,6 % | většina | nohy se rozpadly na tečky |
| ikona aplikace + badge na anténě | 21,2 % | 30 z 63 | nejhorší, číslo i badge zmizely |
| hranatá obrazovka + 2 tlusté nohy | 37,1 % | **0 z 43** | drží, ale čte jako monitor |
| **velký kruhový badge + 2 tlusté nohy** | 28,5 % | 13 z 50 | **✅ kruh přežil dokonale** |

- **Tvrdé kritérium je počet segmentů užších než 2 px**, ne krytí. Jednopixelová noha
  při chůzi bliká a láme se na čárky.
- **Krytí NENÍ absolutní práh — škáluje s `def.radius`.** Clickbait (radius 14) sedl na
  48 %, notifikace (radius 9) na 28,5 % a je to správně: engine kreslí všechny regulérní
  stejným ×2, takže rozdíl velikosti musí být v artu. Nafouknout drobnou příšeru na 48 %
  je horší chyba než nízké krytí.
- **Co zmenšení nikdy nepřežije:** vlákna tenčí než 2 px, měkká záře a bloom, text a
  číslice menší než ~6 px, malý akcent v rohu. Co přežije vždy: **velká plná kruhová
  nebo obdélníková plocha** v kontrastní barvě.
- Zachránit tenký koncept dilatací **nejde** — zkoušeno, metrika se zlepší (30 → 6 úzkých
  segmentů), ale z nohou jsou chapadla a postava čte jako medúza.

### Chůze podle rychlosti — a proč na ni ber ŠABLONU, ne v3

Silueta má říkat, jak se to chová. Mapování na `speed` z `DistractionData`:

| rychlost | čím to udělat |
|---|---|
| 140 (`notification`) | **`running-8-frames`** — skutečný běh s letovou fází |
| 105–110 (`autoplay`, `energy_drink`) | `walking-8-frames`, svižný krok |
| 50–68 (tanky, `adult_content`… ) | `sad-walk`, těžké šourání |
| boss 50 | `walking-8-frames` (na `sad-walk` byl v profilu hrouda) |
| letci (`phantom_buzz`) | neplatí, vznáší se — nohy nemá |

> ⚠️ **Běh nepiš jako custom v3.** Zkoušeno 17. 8.: osmisnímkový sprint popsaný po
> framech („Frame 4: FLIGHT, both feet clear of the ground") **rozpustil postavu** —
> kulatá hlava se rozpadla na dvě skvrny, tělo se rozmazalo, nohy na šum. Je to stejný
> mechanismus jako u attacku (doomscrollu se roztekl telefon): **čím extrémnější pohyb
> předepíšeš, tím víc model pustí identitu.** Šablony jedou po kostře a identitu drží,
> takže na lokomoci ber vždycky je. v3 si nech na attack a smrt, kde je deformace
> částečně žádoucí.

> ✅ **Kotva stylu: `fa8294b1-c3ec-4ae5-92fb-39570ced0f65`** — Broccoli Knight. Tohle id
> patří do `style_character_id` u **každé** nové příšery. Junk-foodové kotvy z 15. 8.
> (`62772f73…`, `0ef2d964…`) jsou v kreslené grotesce a **už se nepoužívají**.

### Věta, ze které se skládá popis

Přesně ta, kterou má roster obránců — drž její pořadí, generátor na ni reaguje:

```
64x64 pixel art character sprite, <adj> <Jméno> <role> unit. <stavba těla z jídla>.
<oblečení / výstroj>. <rekvizita>. <postoj>, strictly front-facing low top-down RPG
perspective (aligned straight to square grid, zero 45-degree isometric tilt). Gritty
pixel dithering, high contrast <paleta>, crisp dark outline. Clean transparent background.
```

### Čitelnost je tvrdá podmínka: rodina × tell × barva

Hráč musí z podoby poznat, co příšera představuje. Tři vrstvy:

1. **Rodina** — junk-foodové tělo vykreslené stylem kotvy. Nese „patří k sobě".
2. **Tell** — *jeden* ikonický tvar, který nese identitu (zvonek, telefon, páka automatu).
3. **Barva** — `def.color`, protože engine kreslí pod příšerou kaluž té barvy a stejnou
   má legenda vln. **Sprite musí tu barvu obsahovat**, jinak si tělo a aura odporují.

**Test siluety:** vyplň sprite načerno. Když tell zmizí, není to tell.

> ⚠️ **Tell musí být VELKÝ TVAR, ne symbol otištěný na povrch.** Ověřeno 17. 8. na třech
> postavách naráz: „a bold solid triangular play button symbol stamped across the front"
> vyrobilo kýbl popcornu **bez trojúhelníku**, „lightning bolt stamped across the can"
> plechovku bez blesku a „four screens orbiting on tendrils" bosse bez obrazovek. Na 64 px
> generátor malý znak spolehlivě zahodí. Opravené znění, které funguje: *„its entire chest
> is one huge glowing screen panel filling most of the torso, and a single enormous solid
> black play-button triangle is cut into that screen, taking up the whole panel"*.

### Kontrast proti podlaze — měřitelné, ne od oka

Mapa Deep Focus má **průměrný jas 20**. Sprite, který se od něj neodliší, zmizí, i když
je sám o sobě krásný. Ověřený práh: **kontrast +30 a výš, a míň než ~25 % pixelů tmavších
než pozadí**. Celý roster se drží mezi +38 a +159.

Past, na kterou to našlo: uživatelova incognito postava (černý trenčkot) měla kontrast
**+5,9 a 58 % pixelů pod pozadím** — na mapě z ní byla černá skvrna a jediné, co ji
prozradilo, byla barevná kaluž pod ní. Desetinásobně horší než druhá nejtmavší příšera.

Oprava bez přegenerování, když návrh sedí a jen je tmavý: **gama na V v HSV, jen na
vnitřek, obrys nech být.** Obrys = neprůhledné pixely sousedící s průhledným (dilatace
alfa); ty se nesmí rozjasnit, jinak se ztratí ostrá silueta, která drží celý styl.

```python
body = (alpha > 128) & ~outline_mask(alpha)
hsv[..., 2][body] = (hsv[..., 2][body] / 255) ** GAMMA * 255   # H a S beze změny
```

Gamu doťukej ve smyčce, dokud kontrast nepřeleze 30 — clickbait sedl na 0,44,
incognito na 0,36.

> ⚠️ **Nepoužívej posun černého bodu v RGB** (`LIFT + rgb*(255-LIFT)/255`). Vypadá to
> v číslech nejlíp (incognito +38,9), ale **sebere sytost**: 0,664 → **0,226**, tedy dvě
> třetiny barvy, a z postavy je šedivá šmouha. Odhalilo se to až měřením sytosti vedle
> kontrastu — v samotném čísle kontrastu to není vidět. Gama na V drží sytost na desetinu
> přesně (clickbait 0,716 → 0,714).

### Teplí nepřátelé, chladní obránci

Vyšlo to samo a **stojí za udržení**: nepřátelé mají zlatou, oranžovou, červenou a pink;
obránci zelenou, ivory a dřevo. Hráč rozezná svoje od cizího bez jediného prvku UI.
Když děláš novou příšeru, drž ji teplou.

### Proč zrovna junk food

Není to jen „hezký styl". Hra učí o *digital obesity* — přejídání se levnou digitální
stimulací (`docs/core/00_overview.md`). Distrakce jako sladkosti a fastfood, které
zezelenaly a obživly, dělají tu metaforu **doslovnou bez jediného slova textu**, což je
přesně pilíř „teach through MECHANICS, not text". Každá distrakce dostane vlastní jídlo:
notifikace = donut, doomscroll = nekonečná pizza, autoplay = kýbl popcornu.

### Anatomie (tohle je ta neměnná část)

Od 17. 8. 2026 je to **humanoid**, ne beztvará hmota — stejná stavba jako zeleninoví
obránci, aby obě strany patřily do jedné hry:

1. **Podsaditá humanoidní silueta.** Trup, dvě krátké nohy, dvě ruce. Žádný krk —
   „hlava" je buď jídlo samo (kýbl popcornu, plechovka), nebo rekvizita nasazená na
   ramena (zvonek, kelímek).
2. **Trup JE to jídlo.** Ne tvor s jídlem v ruce: burger je trup, plechovka je trup,
   skleněná koule automatu je břicho. Tohle nese metaforu.
3. **Jeden tell, velký.** Viz „Čitelnost" výš. Buď je z něj hlava, nebo zabírá půlku
   trupu. Nikdy odznak.
4. **Výstroj drží rodinu pohromadě.** `tattered dark cloth wrappings`, řemínky, plátování
   — přesně to, co mají obránci. Bez nich vypadá příšera jako předmět, ne postava.
5. **Obličej NEPOTŘEBUJE.** Žádné oči, žádná ústa. Identitu nese **předmět**, ne tvář —
   telefonní vizor místo hlavy, kýbl popcornu, plechovka. Kde se hodí „pohled", udělej
   z něj kus rozhraní: buffering kolečko, notifikační badge, displej. Tvář na 32 px
   stejně nepřečteš a odvádí místo od tellu.
   *(Do 17. 8. tu stálo „jedno dominantní obří oko mimo osu" ze staré junk-food bible.
   Uživatelův boss ukázal, že bez očí je čitelnost lepší, ne horší.)*

*(Do 15.–17. 8. tu stálo „jedna velká masa bez končetin, poleva kape v rampouších" —
to byla kreslená groteska, kterou nahradil styl obránců. Kapání a beztvarost se navíc
ukázaly jako aktivní problém: v3 z nich při smrti dělá nečitelnou kaši, viz níž
`doomscroll` a `group_chat`.)*

### Paleta

Barvu těla ber z `def.color` (§4), ať sprite ladí s aurou pod sebou i s legendou vln.
Nad tím platí **teplí nepřátelé × chladní obránci** (výš).

Kotva používá tuhle sadu slov a funguje: `high contrast <dvě až tři barvy jídla>,
<jedna studená barva těla>, crisp dark outline`. Konkrétní hexy nepředepisuj —
`style_character_id` je drží líp než text.

### Čára a stínování

`Gritty pixel dithering, crisp dark outline, high contrast` — doslova ta slova z rosteru
obránců. Výrazné stíny, sytá lokální barva, čitelná silueta. **Ne kreslená groteska,
ne ploché cel výplně, ne roztomilé, ne chibi, ne 3D render, ne fotoreal.**

Staging: jedna postava, plochý jednobarevný podklad, žádné prostředí. **Nepeč do spritu
stín** — engine si kreslí vlastní kontaktní elipsu i barevnou kaluž
(`distraction_animator.gd:149-179`).

### Šablona promptu, která se osvědčila (od uživatele, 17. 8. 2026)

Přesnější než dřívější znění. Sedm bloků v tomhle pořadí, na bossovi ověřeno:

1. `64x64 pixel art character sprite,` + **role a co ztělesňuje** („colossal Social Media
   Binge final boss enemy … embodying endless scrolling and attention addiction")
2. **Hlava = předmět**, ne tvář („Head is a monolithic dark smartphone screen visor")
3. **Tell jako pevná konstrukce** s explicitním „rigidly fused directly into the flesh
   as heavy armor plates" + kde přesně („two on wide shoulders, two on hips")
4. **Druhotný detail, který nese mechaniku** („back covered in glowing red notification
   cyst pods" ← boss rodí Notifications)
5. **Postoj + kolik pixelů plátna zabírá** („filling 48x54 pixels of canvas") — tohle
   drží měřítko napříč postavami líp než cokoli jiného
6. `Strictly front-facing low top-down RPG perspective (aligned straight to square grid,
   zero isometric tilt)`
7. `Gritty pixel dithering, high contrast <hexy>, crisp dark outline.`
   **`No floor shadow, no baked ground shadow.`** `Clean transparent background.`

Hexy piš přímo do promptu (`violet (#b07dff)`), ať sprite sedí s `def.color`.

**Univerzální text do reference (`How should this image be used?`)** — jeden pro všechny
animace té postavy:

```
Use this exact <Jméno> sprite. Maintain strict character scale, <postoj>, and <barva>
body color across all directions (South, East, West, North). The <tell> must remain
rigidly fused flush into the body with zero morphing. Keep the <hlava> and <druhotný
detail> strictly consistent in all views without perspective shrinking.
No baked ground shadows.
```

> 🔑 **Ten referenční text MUSÍ být na začátku každého `action_description`.**
> `animate_character` nemá zvláštní pole pro referenci — ve webu to pole je, přes API ne.
> Když pošleš jen pohyb, animace driftuje: takhle přišel doomscroll o zelený displej
> (zezelenal → zmodral), autoplay o ▶ a energy drink o blesk. Uživatelův boss měl
> identity-lock v každém volání a nedriftoval ani jednou. Skládej to jako
> `action_description = REF + " " + POHYB`.

**Animace pak popisuj po snímcích**, ne jednou větou — `Frame 1-2: … Frame 3-4: …` plus
úvodní řádek o tom, co se hýbat NESMÍ („Rigid Armor & Stance: fused cyan screens stay
flat and anchored to flesh"). Tenhle „co zůstává pevné" řádek je to, co drží rekvizity;
bez něj se rozpouštějí (viz past u v3 níž).

### Prompt — popis do `create_character` (aktuální znění, 17. 8. 2026)

Vzor je `notification`. Vyměň jídlo a tell, zbytek věty nech být:

```
64x64 pixel art character sprite, hostile Notification enemy unit. Hunched stocky humanoid
body made of glazed pink donut dough with a torn ring-shaped hole through its torso. The head
is a heavy dark cast-iron bell fused straight onto the shoulders with a swinging clapper
hanging inside its open mouth. A solid round red alert badge disc is riveted to its chest like
a warning plate. Wearing tattered dark cloth wrappings around the waist and forearms.
Aggressive forward-leaning charging stance, strictly front-facing low top-down RPG perspective
(aligned straight to square grid, zero 45-degree isometric tilt). Gritty pixel dithering, high
contrast glazed pink, charcoal iron, and hot red alert accents, crisp dark outline. Clean
transparent background.
```

Volání: `mode:"pro"`, `style_character_id:"fa8294b1-…"`, `size:64` (boss `128`),
`view:"low top-down"`. Stojí **20 generací** (boss 40).

Kompletní roster deseti popisů, které jsou nasazené, je ve scratchpadu session
(`roster.py`); mapování jídlo → tell → `def.color` je v tabulce níž.

| id | jídlo (tělo) | tell v siluetě | `def.color` |
|---|---|---|---|
| `notification` | donut | zvonek místo hlavy + rudý badge | `ff5566` |
| `doomscroll` | role pizzy | svislý telefon vrostlý do hrudi | `33cc77` |
| `autoplay` | kýbl popcornu | celá hruď = obrazovka s obřím ▶ | `ffaa33` |
| `adult_content` | rozteklý pohár | cenzurní mozaikový pruh přes oči | `ff7700` |
| `clickbait` | burger | obří oko + špičatý banner | `e86a9b` |
| `energy_drink` | plechovka | blesk přes celou plechovku | `20c9b4` |
| `group_chat` | kýbl křidýlek | tři bubliny místo hlavy | `42c86a` |
| `jackpot` | automat na žvýkačky | páka + okénko 777 | `d92b3c` |
| `phantom_buzz` | sodovkový duch | telefon prosvítající tělem | `5ec8ff` |
| `social_media_binge` | věž z fastfoodu | čtyři obrazovky v rukou | `b07dff` |

### Prompt — nové koncepty v Midjourney

Pro další jídla (pizza, popcorn, energy drink…) vyměň jen tu potravinu:

```
character concept sheet, a single grotesque junk-food monster standing alone, one massive rounded
body with no neck and tiny stubby legs, upper half is teal-green warty creature flesh and lower
half is <JÍDLO>, melted glaze dripping heavily down over the seam and pooling on the ground, one
huge glossy asymmetric eyeball with a tiny magenta pupil, a dark toothy cavern of a mouth,
pink-frosted donuts and wafer sticks embedded in the body, warm gold and butter yellow against
cool teal and slate purple, one hot magenta accent, deep wine-red shadow puddle, thick dark
hand-drawn outline, flat shaded stylized 2D game art, bold readable silhouette, cartoon gross-out
--style raw --s 150 --v 7 --no photorealistic, 3d render, isometric, pixel art, cute, chibi,
kawaii, symmetric face, armour, weapons, background scenery, environment, text, watermark
```

`--no pixel art` tam musí zůstat: MJ dělá koncept, pixelizaci dělá až pixflux (§3).

## 4. Kam co patří a co si to samo načte

```
assets/terrain/high_ground_atlas.png   192×192, 4×4 slotů po 48 px, side-mask
                                       (bit 1=up 2=right 4=down 8=left; x=m%4, y=m/4)
assets/towers/tower_base.png           sdílený socket 16×16
assets/towers/head_<type_key>.png      statická hlava věže 16×16
assets/towers/head_<type_key>_frame_N.png  animace (N od 1, díra = konec)
assets/distractions/<id>_frame_N.png          chůze na JIH (výchozí, 16 nebo 32 px)
assets/distractions/<id>_north_frame_N.png    chůze na sever  (volitelné)
assets/distractions/<id>_east_frame_N.png     chůze na východ (západ se zrcadlí)
assets/distractions/<id>_death_frame_N.png    smrt — přehraje se jednou, pak node zmizí
assets/distractions/<id>_b_frame_N.png        2. varianta vzhledu (_b.._f)
   (kombinuje se: <id>_b_east_frame_N.png)
assets/background.png                  podlaha, 384×216 ×5 (pozor: .jpg by vyhrál nad .png!)
assets/decor/*.png                     rekvizity 16×16, kresleny ×2; nová = jen nakopírovat
assets/src/pixel/                      zdroje/zálohy (anim32/ = původní 32px snímky)
```

- Věže: načítá `tower.gd::_load_head_art()` — **volané ze `_setup_specific`, NE z
  `_ready`** (add_child běží před setup, v `_ready` je `type_key` prázdný — už jednou
  prošlápnuto). Tier 2 bez vlastních souborů dědí tier 1 (`trim_suffix("_2")`).
  Orientace artu: `ART_FACING` slovník (sniper hlaveň 45°, činka vodorovně).
- Barracks má vlastní kopii loaderu (`barracks.gd`), stejné schéma.
- Nepřátelé: `distraction_animator.gd` — snímky si najde sám, měřítko z radiusu
  (`round(r*4/src)`), 12 fps. Bez snímků kreslí procedurální tělo (fallback).
  **Varianty**: každá instance si při spawnu náhodně vybere jeden ze suffixů, které
  na disku existují (`""`, `_b`, `_c`…) — stačí přidat soubory, kód se nemění. Sady
  jsou v statické cache, takže dvacet nepřátel načte disk jednou.
  **Smrt**: `_die()` vyšle signály hned (odměna/combo nesmí čekat na animaci), a když
  existují death snímky, node dožije a uvolní se až po dohrání. Ověřeno testem.
  **Směry**: `Distraction.note_heading()` snapuje pohyb na 4 světové strany (AStar jede
  `DIAGONAL_MODE_NEVER`, takže chůze je vždy osová). Generuj jen **north + east** —
  jih už existuje a západ se kreslí jako zrcadlený východ. Chybějící směr spadne na jih,
  takže nedodělaná sada nikdy nezpůsobí zmizení spritu.
  **Záře**: pod každým nepřítelem se kreslí kaluž jeho `def.color`. Není to dekorace —
  na 32-64 px se identita příšery z kresby přečíst nedá, barva a velikost ano.

**Rodina příšer — jak ji generovat.** Jak má vypadat, je v **§3b** (junk food, od
15. 8. 2026; nahradilo „grungy zombie v obvazech" ze 14. 8.).

Nové příšery dělej `create_character` **mode="pro" + style_character_id**. Reference drží
styl napříč rodinou líp než jakýkoli textový popis, takže tenhle parametr je ta hlavní
věc na celém volání.

> ✅ **Kotva rodiny (od 15. 8. 2026): `62772f73-28d8-442b-add6-f33684f16415`** — burger
> s jedním obřím magentovým okem, `clickbait` varianta A. Je to první junk-food příšera
> podle §3b, uživatelem odsouhlasená, takže tohle id patří do `style_character_id`
> u všech dalších. Sesterská `0ef2d964-dd67-4132-97b9-39083228db14` (`clickbait_b`,
> shluk malých očí) je ze stejného promptu a jde použít jako druhá reference.
> Staré `7ba5d829-5a10-4ed9-b038-52978ec20782` (jednooká scrollerka) je v **obvazovém**
> stylu — s ním dostaneš starou rodinu. Nepoužívat.

Pak `animate_character` se šablonou chůze. 64px → ÷2 na 32. Cena: ~20-40 generací/postava,
animace levné (1 generace na směr).

**Šablon je 47, ne jedna.** Seznam nikde není — vytáhne se tak, že pošleš neexistující
`template_animation_id` a server vypíše platné:

```
backflip, breathing-idle, cross-punch, crouched-walking, crouching, drinking,
falling-back-death, fight-stance-idle-8-frames, fireball, flying-kick, front-flip,
getting-up, high-kick, hurricane-kick, jumping-1, jumping-2, lead-jab, leg-sweep,
picking-up, pull-heavy-object, pushing, roundhouse-kick, running-4-frames,
running-6-frames, running-8-frames, running-jump, running-slide, sad-walk, scary-walk,
surprise-uppercut, taking-punch, throw-object, two-footed-jump, walk, walk-1, walk-2,
walking, walking-2..walking-10, walking-4-frames, walking-6-frames, walking-8-frames
```

Nasazené: regulérní distrakce **`sad-walk`** (šouravá chůze sedí k distrakci),
boss **`walking-8-frames`**, notifikace **`running-8-frames`**.

> 🔴 **`ai_freedom: 0` znamená „přetvaruj postavu na kostru šablony".**
> Parametr se jmenuje matoucně: 0 = rigidní následování šablony, a to **postavu
> překreslí do proporcí té kostry**. Všechny šablony jsou humanoidní, takže:
> - **notifikace** (hubený běhoun, blízko humanoidu) prošla na `ai_freedom: 0` bez
>   ztráty — hlava, rudá čočka i anténa drží přes všech 8 snímků;
> - **clickbait** (zavalitý grázl) se na témže nastavení **zúžil z 27 na 16 px** a
>   přišel o desku s ▶ v hlavě. Na `ai_freedom: 500` si objem udržel (369 px místo
>   314), ale `sad-walk` se skoro nehýbe.
>
> Pravidlo: **čím dál je silueta od humanoida, tím vyšší `ai_freedom`.** A počítej
> s tím, že tell, který je jen *otištěný symbol na povrchu* (▶ na desce), animaci
> nepřežije — musí to být velký tvar, jak stojí výš v téhle kapitole.

> ⚠️ **`ai_freedom` není součástí klíče, podle kterého server pozná duplicitu.**
> Druhé volání téže šablony na tentýž směr vrátí `status: already complete` a novou
> variantu nevyrobí, ať dáš jakékoli `ai_freedom`. Chceš-li porovnat dvě nastavení,
> musíš buď zvolit jinou šablonu, nebo starou skupinu smazat — a to až **poté**, co
> máš náhradu na disku (viz PIXELLAB.md 5d).

**Šablona rozhoduje o siluetě víc, než by člověk čekal** — a je to nejlevnější knob,
co máš. Boss prošel na stejné postavě třemi:

| šablona | výsledek na bossovi (východ) |
|---|---|
| `sad-walk` | nafouklá hrouda, v profilu nevypadá jako táž postava co zepředu |
| `scary-walk` | zepředu dobrý, v profilu se v druhé půlce cyklu kroutí |
| `walk` | jen 6 snímků, modrá deska spolkne celý trup |
| **`walking-8-frames`** | **stabilní tvar přes všech 8 snímků, jídlo i obrazovka čitelné** |

Takže když směr vyjde divně, **vyzkoušej dvě tři jiné šablony** (1 generace za směr) dřív,
než začneš přepisovat popis postavy nebo ji pregenerovávat.

**Profil je nejtěžší směr.** Cokoli, co má identitu vepředu (obří oko, displej na hrudi),
z boku zmizí. Bossovi to dělalo největší potíž, protože „věž naskládaná z jídla" je
v profilu jen hrbolatý sloup. Když se východ nepovede ani po výměně šablony, jde ho
**prostě nedodat** — `_facing_frames()` spadne na jižní sadu, takže postava bude vždycky
čelem ke kameře. U jednoho pomalého bosse je to legitimní volba, ne dluh.

**Attack sada** (`<id>_attack_frame_N.png`) šablonu nemá, jede přes `action_description`.
Generuj **jen východní směr** — `distraction_animator.gd:212` ji hraje pro všechny směry
a na západ ji zrcadlí. A **hraje ji ve smyčce**, dokud obránce příšeru drží, takže poslední
snímek musí navazovat na první („…returning to the starting pose so the motion loops
seamlessly" v popisu funguje).

> ⚠️ **v3 na attack nestačí.** Jemný popis dá sotva viditelný pohyb; když se přitvrdí
> („violently winding far back… extreme exaggerated poses"), **rozpustí se rekvizita** —
> doomscrollu se telefon roztekl do zelené kaše. Ověřeno 17. 8.: použij `mode:"pro"`
> (20 generací na příšeru, `confirm_cost:true` až po schválení uživatelem).
> **Výjimka boss:** v `pro` je počet snímků svázaný s velikostí postavy (≤64 px → 16,
> >64 px → **4**), takže 128px boss by si pohoršil proti sedmi snímkům z v3. Boss zůstává
> na v3.

Dvě věci, které u `pro` attacku hlídej (ověřeno 17. 8. na osmi příšerách):

- **Server deduplikuje podle `action_description` + směru.** Když už existuje v3 sada se
  stejným popisem, vrátí `status: already complete` a **nic nespustí** — jiný `mode`
  ani jiný `animation_name` to neobejde. Nejdřív `delete_animation` na starou skupinu.
- **Tell v `pro` sadě driftuje.** Ze čtyř z osmi zmizela nebo se přebarvila identita:
  doomscrollu zezelenalý displej zmodral (`41,226,2` → `14,242,231`), autoplay přišel
  o oranžový panel s ▶, adult_content celý zesvětlal. Kontroluj to skriptem, ne okem —
  porovnej množinu sytých barev chůze a attacku a hlas, co zmizelo. Oprava: buď přebarvit
  v postprocesu (levné, když jde o čistý swap), nebo znovu s **tellem zopakovaným
  v `action_description`** („…the huge glowing orange screen panel with the big black
  play-button triangle staying fully visible the whole time").

Attack má po `pro` **16 snímků**; při `SPRITE_FPS` 12 je to smyčka 1,33 s. U chůze by to
vadilo (příšera by měsíčkovala, viz `PIXELLAB.md` §5d), u attacku ne — příšera při
blokování stojí.

**Smrt: šablonu nepoužívej, piš ji.** `falling-back-death` umí jen „spadne dozadu" a je to
na všech deseti příšerách stejné. Tematická smrt (donut se rozdrobí, automat vysype
bonbony, plechovka se zmáčkne) je custom **v3, `directions:["south"]`** — engine jinou
sadu nečte — a stojí ~1 generaci, takže re-roll je zdarma. Dvě pravidla, která rozhodují:

- **Konec popiš jako tvrdý objekt, ne jako proces.** v3 rozpustí tělo do beztvaré kaše,
  když je proměna složitá („role pizzy se rozvine a plácne naplocho" → zlatá šmouha).
  Funguje: *„the last frames are a flat slumped body lying face down with one clearly
  outlined dark rectangular slab next to it, sharp edges, completely still"*.
- **Poslední snímek je to, co zůstane ležet.** `_draw_death_frames` přehraje sadu jednou
  a **drží poslední snímek** (`distraction_animator.gd:366`), takže půlka pohybu na konci
  zůstane na obrazovce jako chyba.

Custom smrt vrací 10 snímků + referenční = **11**, tj. 0,92 s při `DEATH_FPS` 12.

**Ověřeno 15. 8. 2026 na obou clickbait postavách** (postup i pasti: `PIXELLAB.md` §5d):
šablony stojí **1 generaci na směr**, takže celá potvora (3 směry chůze + smrt) je
**4 generace**. Chůze vrací 8 snímků, `falling-back-death` 7.

Směry: generuj **south + north + east** (4 směry, ne 8 — osm stojí dvojnásob a čtyři
z nich se nikdy nenačtou). Západ si `distraction_animator.gd` zrcadlí z východu sám.
*(Dřív tu stálo `directions:["south"]` s odůvodněním „hra směry neumí" — to už neplatí,
`distraction_animator.gd:190` čte všechny čtyři osy.)*
- Animace věží **zamrzá, když věž nepracuje** (pauza/mimo Routine/disrupt) — záměr,
  stav se čte ze spritu. Neopravovat jako bug.

## 5. Efekty = kód, ne PNG (obarvují se za běhu)

- `pixel_draw.gd` — `PixelDraw.line/arc/packet`: bloky 3 px přichycené k mřížce,
  s mezerami, dedup. Používá se na VŠECHNY čáry (dosahy, lanka, zaměřovač, pingy).
  `packet` = zářivý kousek s ohonem běžící po lince (napojení energie).
- `impact_fx.gd` — bloky; `play(color, scale)`: dopad ×1, smrt ×1.8 v barvě nepřítele.
- `projectile.gd` — tělo 3×2 bloky + bílé jádro, stopa ze zamrzlých bloků.
- AoE pulz = rozbíhající se vlna (`_draw_pulse_wave`), ne problik celé výseče.
- **LOS**: `game.cast_to_wall` je JEDINÝ zdroj pravdy — výseč, cílení, střely i vlna
  ho sdílí. Nikdy nepřidávat druhou implementaci.

## 6. Nasazení a ověření (pokaždé)

1. PNG do správné cesty (viz §4), zmenšovat NEAREST.
2. `godot --headless --path <proj> --import` — **povinné** po nových PNG a po každém
   novém `class_name` (jinak „Identifier not declared").
3. Headless smoke: dočasná scéna `_test_art.tscn` + skript (vzor v historii session) —
   postavit věže přes `build_habit("focus_timer")` (id z `data/habits/*.tres`!),
   pár `process_frame`, kontrola textur, `quit(0)`; watchdog 20 s. Pak smazat.
4. Binárka: `C:\Users\reath\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`

## 7. Ladicí konstanty (podle pocitu ze hry)

| co | kde | teď |
|---|---|---|
| rychlost/pauza paketu v lanku | game.gd (tether blok) | 110 px/s, 90 |
| fps hlav věží / distrakcí | tower.gd `HEAD_FPS` / animator `SPRITE_FPS` | 8 / 12 |
| velikost bloku efektů | pixel_draw.gd, impact_fx.gd, projectile.gd `PX` | 3.0 |
| trvání pulzní vlny | tower.gd `_pulse()` | 0.45 s |
| LOS vzorkování | game.gd `cast_to_wall` | 6 px |

## 7b. Proč svět působí mrtvě (analýza vs. Kingdom Rush, 2026-08-14)

Referencí je Kingdom Rush. Co dělá ON a my ne — v pořadí podle dopadu:

1. **Podlaha je povrch, ne prázdno.** U nás nepřátelé chodí po tmavém ničem. KR má
   světlou dlážděnou cestu s texturou. Toto je zdaleka největší rozdíl.
2. **Rekvizity, které nic nedělají** — cedule, kosti, spící drak. Zaplňují prostor mezi
   drahami. **Hotovo**: 14 kusů v `assets/decor/`, rozmisťuje `scripts/decor_layer.gd`
   (hustota 0,17 volných buněk, seed z `level.id` → stejný rozvrh po restartu, vynechává
   zdi / cíl / spawn zóny, náhodné zrcadlení). Nová rekvizita = nakopírovat PNG.
3. **Obrácený jas.** KR: světlá zem, tmavé jednotky. My: tmavá zem, světlé zdi —
   jednotky se ztrácejí v obojím.
4. **Teplá paleta** proti naší studené modrorůžové.

**3/4 pohled JE nasazený** (15. 8. 2026). Dřívější zápis „2.5D to NENÍ" platil na
konkrétní metodu, ne na záměr: tehdy se PixelLabu zadalo vyextrudovat stěnu **uvnitř
16px dlaždice** — vršek a stěna se dělily o šestnáct art pixelů, vyšel dvoubarevný pruh
a vršek zhubnul (`_mapa_25d.png`).

Co funguje: **stěna není součástí dlaždice vůbec.** Geometrii kreslí kód do buňky pod zdí
(`class WallFace` v `game.gd`, stejný vzorec jako `WallShadow`), generátor dodá jen
materiál v samostatné textuře. Přesně to rozdělení, na kterém stojí i atlas zdí.

- Materiál: `assets/terrain/face/face_NN.png`, 16×8 art px (48×24 na obrazovce, ×3).
- Postprocess je povinný: `tools/build_wall_face.py` — viz `docs/PIXELLAB.md` §5c.
- Výška stěny `Game.WALL_FACE_H = 24` (půl buňky). Kontaktní stín se o ni **posune dolů**,
  jinak by ležel přes stěnu a četl jako šmouha.
- Smazáním složky `assets/terrain/face/` se hra vrátí k plochému pohledu — kód si prázdný
  pool ohlídá sám a stín se vrátí nahoru.

Kolizi „postavy zpředu + podlaha shora" pořád řeší **kontaktní stín**, ten nikam nezmizel.

**Slepá ulička k zapamatování:** tileset s osvětlenou podlahou (`lower` = světlý povrch
místo prázdna) se nepovedl — obě vrstvy splynuly do jedné šedé hmoty, protože popisy
nebyly dost kontrastní. Když se o to pokusíš znovu, dej terénům výrazně jiný materiál
i jas, ne dvě varianty měkké tkáně. Bezpečnější cesta je podlaha jako **pozadí**
(`create_image_pixflux` 384×216), kandidát leží v `_kandidat_pozadi.png`.

## 8. Co ještě není pixel (kandidáti na příště)

FOCUS jádro (vektorové kruhy — chce sprite), distrakce doomscroll / autoplay /
group_chat / social_media_binge / adult_content (procedurální fallback), dopamine burst
(GPUParticles tečka), map editor náhled, UI texty. Postup u distrakcí: §3 objekt →
animace → ÷2 → `assets/distractions/<id>_frame_N.png`, nic víc.
