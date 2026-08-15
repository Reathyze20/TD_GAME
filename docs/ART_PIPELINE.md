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

## 3b. Rodina příšer — vizuální bible (junk food, od 2026-08-15)

**Tohle je závazný vzhled distrakcí.** Nahrazuje „grungy zombie v obvazech" z 14. 8.
Zdroj: tři MJ koncepty uživatele (viz „Předlohy" níž). Píšu to slovy proto, že koncepty
jsou obrázky a prompt potřebuje věty — ale **předloha vždycky přebije text**, takže když
je obrázek po ruce, dávej ho.

### Proč zrovna junk food

Není to jen „hezký styl". Hra učí o *digital obesity* — přejídání se levnou digitální
stimulací (`docs/core/00_overview.md`). Distrakce jako sladkosti a fastfood, které
zezelenaly a obživly, dělají tu metaforu **doslovnou bez jediného slova textu**, což je
přesně pilíř „teach through MECHANICS, not text". Každá distrakce dostane vlastní jídlo:
notifikace = donut, doomscroll = nekonečná pizza, autoplay = kýbl popcornu.

### Anatomie (tohle je ta neměnná část)

1. **Jedna velká masa, končetiny jako dodatek.** Tělo je vejce / klín / kopec — široké
   dole, zaoblené nahoře, **bez krku**. Tvoří ~80 % siluety. Nohy jsou krátké pahýly úplně
   dole, ruce visí nízko po stranách. Ve 32 px přežije jedině tenhle jasný obrys.
2. **Dvě sloučené hmoty.** Každá příšera je jídlo přivařené k tvorovi:
   - **skořápka z jídla** — těsto, sušenka, sýr, poleva. Teplá: zlatá, béžová, máslově
     žlutá, oranžová. Posypaná ovesnými vločkami, sprinkles, drobky, dírkami po vzduchu.
   - **tělo tvora** — studené: petrolejová, modrozelená, šeříkově fialová. Chlupaté nebo
     bradavičnaté, s opravdovými prsty, drápy a kopýtky.
3. **Šev mezi nimi teče.** Jídlo se **rozpouští a stéká přes** tvora — ne čistý předěl.
   (Koncept 1: petrolejová lebka teče přes sušenkové břicho. Koncept 3: sýrová čepice
   teče přes petrolejovou srst.) Poleva visí v rampouších, kape v samostatných kapkách,
   dělá na zemi kaluž. **Kapání je podpis rodiny** — bez něj to nejsou tyhle příšery.
4. **Oči nikdy symetricky.** Jedno dominantní obří oko mimo osu, lesklé, syté — plus
   jedno až dvě malá nesourodá jinde. Duhovka je obrovská vůči bělmu, zornička maličká
   a horká (magenta, červená).
5. **Tlama je tmavá jeskyně** nízko na těle. Tři ověřené varianty: široká rána
   s nepravidelnými hranatými zuby / díra s dlouhým svěšeným růžovým jazykem / **donut
   použitý jako tlama** s tesáky uvnitř.
6. **Zapíchané rekvizity.** Růžově polité donuty vtlačené do těla jako salám, oplatkové
   a churros tyčky trčící po obvodu, marshmallow pupínky, odlétávající drobky.

### Paleta

Kontrast teplé jídlo × studené maso, a **jediný horký akcent** navíc:

```
teplé jídlo:   #d9a441 zlatá kůrka, #e8cf8a bledé těsto, #f0a02c roztavený sýr
studené maso:  #5e9a9c petrolejová, #3f6d78 hluboká modrozelená, #4a3b5c šeříkově tmavá
horký akcent:  #e86a9b magenta poleva (donuty, jazyk, zorničky, pupínky)
stín na zemi:  #6b2038 vínová kaluž — NE šedá
```

Magenta je vzácná schválně: je to jediná barva, která na 32 px prořízne, takže nese
identitu. Barva těla se pořád bere z `def.color` (§4), ať sprite ladí s aurou a HUDem.

### Čára a stínování

Silný tmavý nepravidelný obrys s viditelným ručním chvěním. Převážně ploché cel výplně,
jen pár měkkých přechodů na velkých plochách. Nálada je **kreslená groteska** — *Aaahh!!!
Real Monsters*, nechutné a vtipné. **Ne roztomilé, ne chibi, ne 3D render, ne fotoreal.**

Staging konceptu: jedna postava, plochý jednobarevný podklad, kaluž stínu pod ní, žádné
prostředí.

### Předlohy

Ulož si ty tři MJ koncepty do `assets/src/concepts/` jako
`_mj_creature_1_cookie.png`, `_mj_creature_2_pizza.png`, `_mj_creature_3_cheese.png`.
**Bez nich je celá tahle sekce jen text**, a text v tomhle projektu opakovaně prohrál
s obrázkem (§9 v `ART_PROMPTS.md`, past s prasklinami).

### Prompt — popis do `create_character`

```
a grotesque junk-food monster, one large rounded body like an egg with no neck, tiny stubby
legs and small low-hanging arms, the upper body is a cool teal-green warty creature hide and
the lower body is golden baked cookie dough speckled with oats and sprinkles, thick icing
melting and running down over the seam between them in long drips, one huge glossy off-centre
eyeball with an oversized iris and a tiny hot magenta pupil plus one small mismatched eye, a
dark cavernous mouth low on the body with irregular blocky teeth, pink-frosted donuts pressed
into the body like salami, wafer sticks poking out around the edge, thick dark hand-drawn
outline, flat cel shading, cartoon gross-out style, not cute, plain flat background
```

Negativy do promptu: `no cute, no chibi, no symmetric face, no 3D render, no photorealistic,
no armour, no background scenery, no text`.

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

> ⚠️ **Kotva se musí přegenerovat.** Dosavadní `7ba5d829-5a10-4ed9-b038-52978ec20782`
> (jednooká scrollerka) je ve **starém** obvazovém stylu — s ním dostaneš starou rodinu.
> Nejdřív vyrob jednu junk-food příšeru podle §3b, tu si odsouhlas, a **její** id pak
> zapiš sem a používej jako kotvu pro všechny další.

Pak `animate_character` se šablonami **sad-walk** (chůze) a **falling-back-death** (smrt).
64px → ÷2 na 32. Cena: ~20-40 generací/postava, animace levné.

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
