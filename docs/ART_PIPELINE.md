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
| terén, věže | 16 px / dlaždici | ×3 | 3 |
| nepřátelé | 16×16 | ×2 (z radiusu) | 2 |
| efekty (kód) | — | bloky 3 px | 3 |

- Autorská velikost **musí dělit 48**: 16 ✓, 24 ✓, 48 ✓. **32 a 64 NIKDY** (48/32=1,5 → rozmazání).
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

**Rodina příšer (styl od 2026-08-14):** grungy zombie v obvazech podle MJ konceptu
uživatele. Nové příšery dělej `create_character` **mode="pro" + style_character_id**
= `7ba5d829-5a10-4ed9-b038-52978ec20782` (uživatelova jednooká scrollerka) — drží styl
napříč rodinou líp než jakýkoli textový popis. Pak `animate_character` se šablonami
**sad-walk** (chůze) a **falling-back-death** (smrt), `directions:["south"]` (hra směry
neumí, 8 směrů = 8× cena). 64px → ÷2 na 32. Cena: ~20-40 generací/postava, animace levné.
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
