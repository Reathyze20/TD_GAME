# Parita s PixelLabem

*Odvozeno z jeho vlastního API — 76 nástrojů, staženo `python tools/pixellab.py`,
plné schéma v `build/pixellab_tools.json`. Ne z marketingu, ze seznamu funkcí.*

---

## Co z toho pro tuhle hru platí

PixelLab je obecný nástroj. Značná část jeho povrchu je pro top-down tower defense
mrtvá váha — ne proto, že by byla špatná, ale proto, že tahle hra nemá dialogy,
plošinovky ani izometrii.

| skupina | nástrojů | pro tuhle hru |
|---|---|---|
| postavy a rotace | 10 | **ano, jádro** |
| objekty (dekorace, props) | 14 | **ano** |
| dlaždice a tilesety | 17 | **částečně** — top-down a cesty ano, izometrie a plošinovka ne |
| UI prvky a fonty | 7 | ano, později |
| obrázky a úpravy | 6 | **ano, jádro** |
| mapy a jejich editace | 6 | ne — vlastní editor v Godotu je lepší |
| mluvení, viseme, lip-sync | 5 | ne — hra nemá dialogy |
| účet, joby, agenti, znalosti | 11 | ne — SaaS okolo, ne funkce |
| štítky a organizace | 2 | ano, drobnost |

Zbývá zhruba **30 nástrojů**, které mají v tomhle projektu smysl.

---

## Kde stojíme

### Máme, a je to srovnatelné

| co | u nás |
|---|---|
| generování z textu | `gen.py` — SDXL + pixel-art LoRA |
| více kandidátů a výběr | Sprite Studio, mřížka + známkování |
| instalace do hry | `/api/install` do `assets/` |

### Máme, a je to **lepší**

| co | proč lepší |
|---|---|
| **doladění promptem** | Náš `refine` udělá z kandidáta jeho **dítě** (img2img z jeho vlastních pixelů). PixelLab umí `edit_image`, ale nedrží rodokmen — u nás `meta.json` pamatuje, co z čeho vzniklo, takže po pěti krocích víš, na čem stavíš. |
| **měření artu** | `style_audit.py`, `art_check.py` — paleta, obrys, posun odstínu, rastr, kmitání. PixelLab nemá nic, čím by řekl „tenhle sprite nesedí ke zbytku". |
| **časování animace** | Animation Lab: držení jednotlivých snímků, zarovnání siluet, srovnání pohledů. PixelLab dodá snímky a končí. |
| **jedna paleta na celý svět** | `sprite_cleanup.py --master` s vážením barevných os. PixelLab paletu napříč postavami nesjednocuje. |
| **stylová bible jako pravidlo** | `docs/art/style_bible.md` + kontrola rastru. |

### Staví se právě teď

Rotace osmi směrů · referenční obrázek (3 režimy) · obdélníková rozlišení · síla LoRA
jako posuvník · knihovna PixelLabu jako záložka · vlastní prompty animací · zamknutí
na master paletu při instalaci · oprava `score()`, aby netrestala bohatost.

### Chybí

Seřazeno podle toho, co ti nejvíc chybí při skutečné práci.

**1. Přemalování jedné oblasti** (`inpaint_image`)
> Vygeneruje se znovu **jen vybraný kus**, zbytek zůstane pixel po pixelu stejný.

Tohle je nejcennější chybějící věc. Dnes když je sprite dobrý až na oči, musíš doladit
celý — a doladění mění všechno. Inpaint je odpověď na „tohle je skoro ono, jen…",
což je nejčastější věta při dělání artu.

**2. Animace podle kostry** (`animate_character`, režim skeleton)
> Pózy se zadají jako klouby, ne slovy.

My umíme jen textové pózy („left leg forward"). Kostra dá přesnou kontrolu a hlavně
**opakovatelnost**: tatáž kostra na jiném tvorovi dá tutéž chůzi.

**3. Wang tileset** (`create_topdown_tileset`) a **cesty** (`create_path_tiles`, 18 konfigurací)
> Terén, který se sám správně napojuje.

Máme `high_ground_atlas` a `tools/tiles.py`, ale generovat nový terén neumíme.
A terén je podle auditu nejplošší část hry (posun odstínu 4,2° proti 58° u příšer),
takže je to zároveň největší vizuální dluh.

**4. Stavební sada** (`create_building_kit`) — podlaha, napojitelné zdi, dveře, sloup, schody.

**5. Varianty stavu** (`create_character_state`)
> Tentýž tvor v jiném stavu, se zachovanou identitou.

Pro `_b`, `_c` varianty distrakcí, aby vlna vypadala jako dav a ne jako armáda klonů.

**6. UI panely** (`create_ui_asset`) a **pixel font** (`create_font`, vrací i `.ttf`).

**7. Fronta úloh** (`list_jobs`, `cancel_job`)
> U nás je generování blokující. Fronta znamená pustit osm věcí a jít pryč.

**8. Štítky** (`update_*_tags`) — dnes máme jen složky.

---

## Co vědomě nestavíme

Lip-sync, viseme, mluvící GIFy, izometrické dlaždice, tilesety pro plošinovky, editor
map, nasazování agentů, zůstatek na účtu. Pro tuhle hru to nemá použití a stálo by to
čas, který patří jinam. Kdyby se žánr změnil, tenhle seznam je pořád tady.

---

## Režimy `create_character` a co stojí

Vyčteno ze schématu API a ověřeno vlastními běhy.

| režim | generací | směrů | co s ním |
|---|---|---|---|
| `standard` | 1 | 4 nebo 8 | kostrová šablona, styl je jen měkké vodítko |
| `pro` | 20–40 | vždy 8 | nejdražší; jako jediný bere `style_character_id` |
| `v3` z textu | 2–9 | vždy 8 | jejich nejvyšší kvalita z popisu |
| **`v3` s `reference_image_base64`** | **1** | **vždy 8** | **otočí NÁŠ sprite do osmi směrů** |

Ten poslední řádek je nejdůležitější věc, kterou o jejich API víme.

> *„rotates this exact sprite into 8 directions — the image defines identity and
> style; description guides the rotation"*

Za **jednu generaci** dostaneme osm směrů z vlastního artu. Neplatíme jim za nápad
ani za styl — ty máme — platíme za rotaci, což je přesně ta práce, kterou náš
`rotate()` dělá nespolehlivě (osm příbuzných příšer místo jedné otočené).

Podstatné detaily: reference je jižní pohled, max 256×256, výstup dědí rozměr
reference; u čehokoli nad ~32 px dávají přednost `reference_image_url` před base64,
protože MCP klienti dlouhý base64 ořezávají. Nám to nevadí, jedeme přímé JSON-RPC.

`view` má enum `low top-down`, `high top-down`, `side`, `oblique` — na naši hru
sedí **`low top-down`**, tentýž pohled, jaký máme v promptech pro SDXL.

**Past v našem klientovi (opraveno):** `Client.call(self, name, **args)` neuměl
předat argument jménem `name` — a ten má PixelLab u `create_character`,
`animate_character` i `update_*_tags`. Spadlo to tedy právě u nejčastějších volání.
Dnes je první parametr `tool` a argumenty jdou slovníkem.

**Stavy úloh:** `queued` → `creating` (s procenty a odhadem) → `completed` / `failed`.
Ne „processing" — čekací smyčka musí hlídat `completed`.

---

## Pořadí

1. **Inpaint** — největší dopad na skutečnou práci, nejmenší kód. Maska + img2img jen v ní.
2. **Varianty stavu** — přímo řeší, že vlna vypadá jako klony.
3. **Wang tileset a cesty** — největší vizuální dluh hry.
4. **Kostra animací** — nejvíc práce, největší dlouhodobý zisk.
5. Zbytek podle chuti.

A napříč tím vším pořád platí, že poslední článek je **LoRA natrénovaná na tvém artu**.
Bez ní generátor hádá styl z textu. Datovou základnu na to máš: 1623 čistých originálů
v `build/pixellab/`.
