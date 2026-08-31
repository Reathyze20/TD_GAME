# AUDIT.md — inventura `assets/`, co nese jaký vizuální jazyk

*Čistě popisný dokument. Netriuji, co smazat — jen fakticky roztřiďuji, kolik čeho je,
odkud to je a jak moc se to shoduje s `docs/art/STYLE_BIBLE.md` (stav k 2026-08-30,
Fáze 0 vyřešena, viz její §10 gate0). Rozhodnutí je na uživateli.*

## Metoda

- `find assets -type f ! -iname "*.import" ! -iname "*.uid"` → **1560 souborů**, roztříděno
  níž. Součet skupin dole sedí na 1560 (1559 + `assets/src/.gdignore`, který nikam
  vizuálně nepatří — je to jen Godotí ignore marker).
- Chronologie a kontext ke každé skupině: `git log --diff-filter=A` a plné commit
  message pro první i poslední commit, který danou složku/soubor upravil (repo má
  127 commitů, 2026-08-13 až dnes; větev `iso-to-topdown`).
- Cena (generace): hledáno v `PROGRESS.md` (2759 řádků, ale **začíná až 2026-08-29** —
  nepokrývá nic staršího), `docs/ART_PIPELINE.md` (777 řádků, jen ceník za kus, ne
  součty dávek), `docs/art/iso_bible.md`, `docs/art/pixellab_parita.md`,
  `docs/art/tower_prompts.md`, `docs/art/tower_concept_mj.md`, plné commit message
  všech art commitů, a `build/pixellab/_ucet.json` (lokální, gitignored účetní deník
  nástroje `tools/pixellab.py ucet` — na disku, ale obsahuje jen 2 záznamy, obojí pro
  `iso_pilot/wall_material`). Kde se číslo nenašlo, píšu **„cena nedohledána"** a kde
  jsem hledal — nevymýšlím odhad jako fakt.
- U několika sporných složek jsem otevřel skutečné PNG (`Read` jako obrázek) a přečetl
  relevantní kód (`tools/flat_terrain.py`, `scripts/game.gd`), abych zjistil, jestli
  soubor vůbec ještě něco kreslí ve hře, ne jen z názvu složky hádal.

---

## 1. Fáze 0 (A0) — nová organická kotva, čeká na zbytek rejstříku

**Adresáře:** `assets/raw/broccoli_knight/` (9), `assets/raw/focus_timer/` (17),
`assets/raw/prop_focus_core/` (5) — **31 souborů**.

Všechno jsou to **kandidáti**, ne finální shipped assety: `prop_focus_core` 4 kandidáty,
`focus_timer` 16, `broccoli_knight` 8 (plus u každé entity jeden `cand_00_pal48.png` —
verze `cand_00` po `reduce_colors` s `palette_48`). Vybraný kandidát pro každou entitu je
zapsaný v `STYLE_BIBLE.md` §7a (`broccoli_knight` → `cand_03`, `focus_timer` → `cand_04`,
`prop_focus_core` → `cand_00`) — nevybraní zůstávají na disku jako alternativy, nemažou se.

**Design language:** přesně `STYLE_BIBLE.md` — je to jediná skupina, která z ní opravdu
vzešla (povinný suffix, `style_character_id` u obránce, `reduce_colors(palette_48)`).
`prop_focus_core/cand_00.png` (soma s vyzařujícími výběžky, teplá zlatobílá) sedí na
popis „single large neuron soma... gold white" doslova.

**Cena: 63 generací** (`PROGRESS.md:2103`: „Utraceno 63 generací, ne 80 (4943 → 4880;
`generations_used` 3716 → 3779)"; potvrzeno commitem `229f92f feat(art): generate and
stage Phase 0 (A0) -- 63 generations, 4880 left`). Rozpad podle `PROGRESS.md:2095-2097`:
`prop_focus_core` 40, `focus_timer` 20, `broccoli_knight` 20 naplánováno (pesimisticky,
horní hranice pásma); reálně padlo 63, ne 80.

---

## 2. Aktuální plochý terén — `terrain/iso/{ground,lane,terrace}`

**Adresáře:** `assets/terrain/iso/ground/` (16), `assets/terrain/iso/lane/` (18),
`assets/terrain/iso/terrace/` (4) — **38 souborů**.

Název složky říká „iso", ale obsah **už dnes není isometrický styl** — je to poslední
místo, kam `tools/flat_terrain.py` zapisuje. Skript (přečteno celý) **nevolá PixelLab**:
otevře existující PNG, zachová přesně alfu (siluetu dlaždice) a přebarví jen RGB na tři
pevné konstanty odvozené z `STYLE_BIBLE.md` §4 (`GROUND=(20,17,41)` součet 78,
`LANE=(78,52,16)` součet 146, `TOP=(184,165,135)` součet 484). Je to přesně ta cesta,
kterou `STYLE_BIBLE.md` §10 popisuje jako „Terén se negeneruje... instaluje
`tools/flat_terrain.py` jako ploché barvy, za 0 generací."

**Shoduje se s `STYLE_BIBLE.md`** — je to jediná terénová skupina, která prošla
současnou kontrastní bránou (§4), a `scripts/game.gd:1240,1277` ji skutečně načítá
za běhu (`_build_path_layer()`, byť s poznámkou v kódu z 2026-08-29, že tahle vrstva má
teď i v čtvercovém režimu chybu v pozicování — to je otázka pro `render-fx`, ne pro
materiál samotný).

**Cena: 0 generací** (potvrzeno čtením `tools/flat_terrain.py` — čistě lokální
numpy/PIL přebarvení, žádné volání API). Zdrojové PNG, které skript přebarvuje, ale
původně vznikly jako izometrická „Cortex Terrace" textura (skupina 9 níž) — takže „0
generací" platí pro **tenhle krok**, ne pro historii souboru jako celku.

---

## 3. Cesta — `terrain/path/` (starší, dnes čtená jen „legacy path")

**Adresář:** `assets/terrain/path/` — **28 souborů** (`path_00.png`…`path_27.png`).

Vznikly 2026-08-15 (`6969b4f`), poslední úprava 2026-08-19 (`3dc5f53`, cool-shift
stínů). `scripts/game.gd:1199` má konstantu `PATH_TILES_DIR` s komentářem přímo nad ní:
*„Derived from high_ground directly; terrain_tiles is only read by the legacy path."*
— tedy tahle sada dnes žije jako **záložní/legacy** čtecí cesta, zatímco živá cesta
(`_build_path_layer()`) kreslí ze skupiny 2 výš (`terrain/iso/lane`).

**Design language:** texturovaná dlaždice z první pixel-art dávky (8/15), stínovaná
podle starších pravidel `style_bible_measured.md` (medián barev ~40, 1px obrys), ne
plochá barva. Vizuálně malá tmavá dlaždice s jemnou strukturou — bez viditelných zlatých
akcentů (což mimochodem sedí s pravidlem „podlaha je tichá", i když vzniklo dřív, než to
bylo rozhodnuté 14. 8.).

**Cena: cena nedohledána** (hledáno v `PROGRESS.md`, `ART_PIPELINE.md`, commit `6969b4f`
a `3dc5f53` — žádný neuvádí počet generací za tuhle dávku).

---

## 4. Zdi / vyvýšená plošina — starý generovaný atlas

**Soubory:** `assets/terrain/high_ground_atlas.png` (+ `.bak`, `.bak2`),
`assets/terrain/high_ground_corner_atlas.png`, `assets/terrain/face/face_00-02.png`
— **7 souborů** (atlas 4, z toho `.bak`/`.bak2` jsou zálohy stejného obrázku — takže
2 unikátní atlasy + face 3).

Obojí je **aktivní** — `scripts/game.gd` a `scripts/data.gd` na `high_ground_atlas`/
`high_ground_corner_atlas` odkazují, `scripts/game.gd` i na `terrain/face`. `face_*`
je materiál pro `class WallFace` — přesně ten případ z README asset-makera: PixelLab
neumí extrudovanou stěnu uvnitř dlaždice, takže textura nese jen materiál a tvar kreslí
kód.

**Design language:** `high_ground_atlas.png` je jemně strukturovaná tmavě violet-modrá
plocha s fazetami (wang-tileset rohy, `docs/TILESETY.md`) — ne plochá barva jako
skupina 2. Podle `assets/src/concepts/README.md` je to **ručně vyexportovaný Inkscape
SVG** (jeden ze šesti konceptů `atlas_1_veins`…`atlas_6_fracture`), ne přímý PixelLab
výstup. Neshoduje se s dnešním pravidlem „zdi jsou matná plochá barva, 484, sytost
≤0,30" (`STYLE_BIBLE.md` §4) — pořád nese generovanou/kreslenou texturu, ne plochu.

**Cena: 0 generací PixelLab** pro samotný export atlasu (je to Inkscape, ne API — viz
`assets/src/concepts/README.md`, „aniž bys nakreslil jedinou čáru" odkazuje na hotové
SVG, ne na generátor). Cena `face_*.png` nedohledána (mohl to být PixelLab výstup přes
`tools/build_wall_face.py`, ale žádný dokument neuvádí počet).

---

## 5. Literální mozek — mrtvé, nereferencované soubory

**Soubory:** `assets/terrain/brain_floor_dark_overload.png`,
`brain_floor_soft_pastel.png`, `brain_floor_texture.png`, `brain_high_ground_tileset.png`,
`brain_high_ground_variations.png` — **5 souborů**.

Ověřeno: `grep -rl "brain_floor\|brain_high_ground"` přes celý repo (skripty, `.tres`,
`.tscn`) **nenajde ani jednu reference** — nic je dnes nenačítá. Přidané v úplně prvním
commitu (`6a24927 Initial commit`, 2026-08-13) a od té doby nikdy neupravené — jsou to
placeholdery z doby před tím, než vůbec vznikla PixelLab pipeline (commit `6969b4f`
je výslovně popisuje jako „Replaces the placeholder JPG art").

**Design language:** doslovný řez mozkem — vlnovky napodobující gyri, neonové
purpurovo-tyrkysové synapse-hvězdičky. Je to přesný obrázkový příklad toho, co
`STYLE_BIBLE.md` §1 zakazuje větou: *„NE: doslovný mozek v řezu, doslovný orgán,
anatomický model, lékařský diagram."* Nejde o to, že by nesouhlasilo trochu — je to
učebnicová ukázka zakázaného směru.

**Cena: cena nedohledána**, pravděpodobně 0 generací PixelLab (viz výš — placeholder
předcházející pipeline), ale to je odvozeno z komentáře v commit message, ne přímo
potvrzeno.

---

## 6. Nutrition Guild — obránci (junk-food éra)

**Adresáře:** `assets/defenders/` (170), `assets/src/pixel/defenders64/` (162, zdrojová
64px předloha před uložením) — **332 souborů**. Čtyři postavy (`broccoli_knight`,
`avocado_monk`, `chilli_berserker`, `garlic_mage`) × idle/walk (4 směry)/attack/hurt/death.

Vznikly 2026-08-15 až 2026-08-17 (`8cd95a1 Art: junk-food creature family becomes the
monster style bible`, `7767eae Art: distractions redrawn at 32px, tower + terrain art
pass`, `331134c Gameplay: Nutrition Guild...`) — **12 dní před `STYLE_BIBLE.md`**
(vznikla 2026-08-29, `35b3d8c`).

**Nejistá otázka, kterou tenhle audit nemůže sám vyřešit:** `broccoli_knight` JE dnešní
jediná kotva projektu (`style_character_id = fa8294b1-…`, `CLAUDE.md`). Fáze 0 (skupina 1
výš) ho ale **znovu vygenerovala** 2026-08-30 a z osmi kandidátů vybrala `cand_03` jako
nový `broccoli_knight`. Nemám nástroj ověřit, jestli `fa8294b1-…` odkazuje na TUHLE
existující kresbu (`assets/defenders/broccoli_knight_*`) nebo na něco, co Fáze 0 právě
nahrazuje — to je otázka pro `get_character` v PixelLabu, ne pro čtení souborů, a tenhle
úkol měl výslovně zakázáno cokoli generovat nebo volat MCP. Vizuálně (`Read` na
`broccoli_knight_idle_frame_1.png` vs. `raw/broccoli_knight/cand_03.png`) jde o podobnou
siluetu (zbrojený brokolicový rytíř, nízký top-down pohled), ale nejde to z pouhého
pohledu potvrdit jako identickou generaci.

**Design language:** chibi obránce-zelenina v brnění — kulaté tvary, husté drobné
detaily brnění. Shoduje se s dnešní siluetovou tabulkou pro Habits/obránce (kulatý,
uzavřený, teplá paleta), ale vznikla měsíc před tím, než tahle tabulka existovala, a
předtím, než `STYLE_BIBLE.md` zakázala „hrany, součástky, panely, šrouby" pro *terén* —
u postav to pravidlo ostatně nikdy neplatilo, `style_character_id` běží mimo tenhle
slovník.

**Cena: cena nedohledána.** `PROGRESS.md` začíná 2026-08-29 (pozdě), `ART_PIPELINE.md`
dává jen sazebník za kus (`create_character mode:"pro"` ~20 generací, `animate_character`
~20-40/postava — `ART_PIPELINE.md:589-590`), ne skutečný součet za tuhle dávku. Podle
sazebníku by 4 obránci se 6 animacemi vyšli řádově na nízké stovky generací, ale to je
**dopočet ze sazebníku, ne zjištěné číslo** — neuvádím ho jako fakt.

---

## 7. Distractions — junk-food monster rodina

**Adresáře:** `assets/distractions/` (381: 375 PNG + 6 SVG), `assets/src/pixel/
distractions32/` (400, zdrojová 32px předloha), `assets/src/pixel/anim32/` (17,
částečný přepočet `notification`/`phantom_buzz`) — **798 souborů**.

10 unikátních příšer (`clickbait`, `notification`, `phantom_buzz`, `autoplay`,
`doomscroll`, `energy_drink`, `group_chat`, `jackpot`, `adult_content`,
`social_media_binge`), ale `distractions32/` má navíc iterace stejné příšery
(`clickbait_b`, `doomscroll_b`, `doomscroll_c`, `group_chat_b`, `_v1_energy_drink`) —
tedy víc pokusů na jednu entitu, ne 10 čistých sad. Šest `.svg` v `assets/distractions/`
(`distraction_adult_content.svg` atd.) je **ještě starší vrstva** předcházející pixel-art
pipeline (`6969b4f`), takže jsou to zřejmě mrtvé placeholdery jako skupina 5.

**Design language:** kulaté, syté "junk food" potvory (viz surový koncept
`assets/src/incoming_tiles/..._Junk_Food_Golem_made_of_doughnuts_fries..._2.png` —
maso z burgerů a hranolek), tematicky "digital obesity" (`docs/ART_PIPELINE.md` §3b).
**Neshoduje se** se siluetovou tabulkou `STYLE_BIBLE.md` §2a (distrakce mají být „ostré,
zubaté, roztřepené, hrot/trn/cíp") — tahle rodina je naopak kulatá a blobovitá, blíž
popisu, který bible přiřazuje Habits, ne Distractions.

**Cena: cena nedohledána** (stejné hledání jako u skupiny 6, stejný výsledek — žádný
dokument ani commit uvádí součet za dávku).

---

## 8. Věže / Habits — staré ikonové hlavy a zavržené iterace

**Adresáře:** `assets/towers/` root (18, aktivně načítané `scripts/tower.gd`),
`assets/towers/_topdown_backup/` (67), `assets/src/pixel/towers/` — 3 v kořeni +
`Meditation towers/` (10 testovacích PNG) + `_replaced_mindfulness/` (10) — **108
souborů celkem** (18 + 67 + 23).

**Tři různé kresby jednoho jména existují vedle sebe.** `assets/towers/
head_focus_timer.png` (dnes aktivní, načítá ho `scripts/tower.gd:623-644`) je
**rajče s ciferníkem budíku** — kulatý potravinový maskot. `assets/towers/
_topdown_backup/head_focus_timer_frame_1.png` je **modrá lahvička/přesýpací hodiny**
s tyrkysovou září — vizuálně úplně jiný objekt, `cmp` potvrzuje, že to nejsou stejná
data. Žádný z obou neodpovídá `STYLE_BIBLE.md`'s popisu `focus_timer` jako „round glial
cell body with one coiled process... single warm amber node" (§8, forms table).
`_topdown_backup/` (67 souborů) je podle vlastního názvu záloha staré předizometrické
sady, uložená a nikdy nesmazaná; `Meditation towers/test*.png` a `_replaced_mindfulness/`
jsou v ART_PIPELINE.md éře explicitně označené jako zavržené koncepty.

**Design language:** potravinové/předmětové ikony (rajče, hodiny, lahvička) — ne
gliová buňka. Věže mají dnes být „tmavé implantáty s teal akcenty" (art-direction
pravidlo tohoto projektu) — tahle skupina je jasná, barevná, maskotová, opak toho.

**Cena: cena nedohledána.**

---

## 9. Cortex Terrace — opuštěná izometrická textura

**Adresáře:** `assets/terrain/iso/*.png` v kořeni (15, vč. `_provenance.json`),
`assets/terrain/iso/props/` (4), `assets/iso_pilot/` + `iso_pilot/decor/` (16+3=19),
`assets/src/pixel/iso_pilot/` + `decor/` (6+8=14) — **52 souborů**.

Tohle je ta **původní** textura, kterou skupina 2 (dnešní plochý terén) přebarvila —
ale `tools/flat_terrain.py` sahá jen na `ground/`, `lane/`, `terrace/`; zbytek
(`floor_synaptic_*`, `wall_synaptic_*`, `pedestal_synaptic_*`, `synaptic_slab_*_clean`,
`props/core.png` atd.) zůstal nedotčený — pořád nese původní generovanou texturu **a**
diamantovou (kosočtvercovou) siluetu z izometrické éry (`405df22 feat(iso): implement
playable isometric vertical slice`, 2026-08-19). `assets/iso_pilot/decor/` má i
zavržené iterace pojmenované přímo tak (`moss_tuft_v1_rejected_crystal_read.png`,
`root_icicle_rejected.png`).

**Design language:** tematicky nejblíž dnešnímu směru ze všech starých skupin — název
„synaptic slab", „synaptic tissue" — ale **izometrická geometrie**, kterou
`STYLE_BIBLE.md` §11 výslovně nepřebírá („Diamantová geometrie... bezpředmětné") a
projektové pravidlo „Izometrie NE" zakazuje pro top-down desku.

**Cena:** z valné většiny **cena nedohledána**. Jedinou výjimkou je
`build/pixellab/_ucet.json` (lokální, negitovaný účetní deník) se dvěma záznamy:
`wall_material v1 (bubble pattern, hue 13.4, zamítnuto)` — 1 generace, a
`wall_material v2 (použito, hue 15.9 → postprocess 25.8)` — 1 generace, tedy
**2 generace celkem** — a to pokrývá jen `assets/iso_pilot/wall_material*.png`
(zlomek této 52souborové skupiny), ne zbytek.

---

## 10. Decor, rekvizity, markery, pozadí

**Adresáře/soubory:** `assets/decor/` (17), `assets/src/pixel/props/` (14, zdroj pro
decor), `assets/src/pixel/path_accents/` (6, `accent_00-05.png`), `assets/markers/` (2),
`assets/background.png` (1) — **40 souborů**.

Smíšená skupina jménem, ne stylem:

- **`path_accents/`** jsou přesně ty akcenty, které uživatel 14. 8. 2026 rozhodl na
  podlahu nedávat (viz `CLAUDE.md`: „Podlaha je záměrně úplně tichá, bez akcentů...
  Nenavrhuj je zpátky bez vyzvání.") — na disku zůstaly, ale nejsou ve hře použité.
- **`decor/`** má 14 položek se stejným jménem jako `pixel/props/` (`mug`, `clock`,
  `pill`, `notes`, `phones`, `book`, `bulb`, `eye`, `synapse`, `bones`, `screen`,
  `cables`, `shard`, `puddle`) — ty odpovídají slovníku „telefon, hrnek, budík, prášky,
  lepíky" z aktuálního zadání tématu. Ale tři položky (`burger_box.png`,
  `battery_dead.png`, `can_crushed.png`) do tohohle slovníku nepatří — jsou to
  zbytky junk-food/tech-clutter metafory, ne pozornosti/paměti.
- **`background.png`** (640×304, celá podlaha) barevně sedí na dnešní paletu (tmavě
  indigová tkáň, jantarové cesty, teal uzly) — ale je to **per-pixel šum s viditelnými
  akcentními uzly po celé keramice**, přesně to, co uživatelské rozhodnutí 14. 8.
  zrušilo. Vznikl 2026-08-15, tedy před tím rozhodnutím.
- **`markers/`** (`goal_core.png`, `spawn_portal.png`) jsou malé 16px ikony ze stejné
  8/15 dávky, nekontroverzní, jen staré.

**Cena: cena nedohledána** pro celou skupinu.

---

## 11. Syrové koncepty mimo PixelLab (Midjourney, Inkscape)

**Adresáře:** `assets/src/mj/` (1, jen README — samotné MJ soubory buď nikdy
nepřibyly, nebo skončily v `incoming_tiles/`), `assets/src/incoming_tiles/` + `clean/`
+ `new_mj/` (76+30+8=114), `assets/src/concepts/` (5) — **120 souborů**. Plus
`assets/src/.gdignore` (1 soubor, ne art — jen Godotí ignore marker, mimo tuhle
tabulku).

`assets/src/incoming_tiles/` jsou syrové Midjourney exporty (`reathyze_...png/jpg`),
Godot je ignoruje přes `.gdignore` (potvrzeno `assets/src/mj/README.txt`: „Godot je
ignoruje přes ../.gdignore"). Obsahově kříženina: junk-food golem, garlic/broccoli/
avocado/chilli koncepty, izometrické „diorama" dlaždice, testovací sheety —
inspirační materiál pro skupiny 6, 7 a 9, ne hotové assety. `assets/src/concepts/`
je šest **ručně kreslených Inkscape SVG** konceptů pro `high_ground_atlas` (README
je popisuje beze zbytku, včetně tří „mozkových" variant `atlas_7_cortex`,
`atlas_8_cortex_muted`, `atlas_9_cortex_inflamed" — tedy i tahle složka obsahuje
konceptní verze doslovného mozku, i když nikdy neshippnuté jako takové).

**Design language:** mimo tuhle klasifikaci — je to zdrojový/koncepční materiál,
ne finální herní art. Nejblíž skupinám 6/7/9 (junk-food a Cortex Terrace éra).

**Cena: PixelLab 0** (nejde o PixelLab výstupy). Cena za samotné Midjourney generování
nedohledána (externí nástroj, mimo `get_balance`/`_ucet.json` účetnictví tohoto
projektu).

---

## Souhrnná tabulka

| # | Skupina | Adresáře (zkráceně) | Soubory | Generace (PixelLab) | Shoduje se s aktuálním STYLE_BIBLE? |
|---|---|---|---|---|---|
| 1 | Fáze 0 (A0), nová kotva | `raw/{broccoli_knight,focus_timer,prop_focus_core}` | 31 | **63** (PROGRESS.md:2103) | **ano** — z bible přímo vzešly |
| 2 | Plochý terén, aktuální | `terrain/iso/{ground,lane,terrace}` | 38 | **0** (skript, ne API) | **ano** — jediná terénová skupina, co prošla bránou §4 |
| 3 | Cesta, legacy | `terrain/path/` | 28 | cena nedohledána | ne — texturovaná, dnes jen „legacy path" (`game.gd:1199`) |
| 4 | Zdi / plošina, starý atlas | `terrain/{high_ground_atlas*,face/}` | 7 | 0 (Inkscape) / nedohledáno (face) | částečně — aktivní, ale generovaná textura, ne plochá barva |
| 5 | Literální mozek, mrtvé | `terrain/brain_*` | 5 | pravděpodobně 0, nedohledáno jistě | **ne** — přímý příklad zakázaného směru; navíc nereferencované |
| 6 | Nutrition Guild, obránci | `defenders/`, `src/pixel/defenders64/` | 332 | cena nedohledána | částečně/nejisté — sdílí jméno s dnešní jedinou kotvou, vznik ale 12 dní před bibli |
| 7 | Distractions, junk-food | `distractions/`, `src/pixel/{distractions32,anim32}/` | 798 | cena nedohledána | ne — kulaté blobby monstrum místo „ostré/zubaté" siluety |
| 8 | Věže/Habits, staré ikony | `towers/`, `towers/_topdown_backup/`, `src/pixel/towers/` | 108 | cena nedohledána | ne — potravinové/předmětové maskoty, ne gliová buňka |
| 9 | Cortex Terrace, izo | `terrain/iso/*` (zbytek), `iso_pilot/`, `src/pixel/iso_pilot/` | 52 | z valné části nedohledáno; **2** doložené (`_ucet.json`, jen `wall_material`) | ne — izometrická geometrie zakázaná |
| 10 | Decor/rekvizity/markery/pozadí | `decor/`, `src/pixel/props/`, `path_accents/`, `markers/`, `background.png` | 40 | cena nedohledána | částečně — část slovníku sedí (mug/clock/pill), 3 položky ne, akcenty explicitně vyřazené |
| 11 | Syrové koncepty | `src/mj/`, `src/incoming_tiles/`, `src/concepts/` | 120 | 0 PixelLab; MJ cena nedohledána | mimo klasifikaci — zdrojový materiál |

**Součet: 1560** (11 skupin = 1559 + `assets/src/.gdignore`, 1 nevizuální soubor mimo tabulku).
