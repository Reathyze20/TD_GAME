# Plán: vlastní generátor na úrovni PixelLabu

*Sestaveno 17. 8. 2026 z auditu 63 schopností napříč čtyřmi pilíři. Každé tvrzení „tohle
už máme" prošlo nezávislým pokusem o vyvrácení; kde audit padl, je to dole napsané.*

---

## Co se dnes změřilo a proč to mění pořadí

Dvě měření z jednoho večera, obě proti očekávání:

**Zmenšovač není páka.** Median proti k-centroidu na sedmi renderech: známky v rozmezí
±0,3, silueta bit po bitu táž. Zmenšovač vybírá barvy, ne strukturu — viz
[zmensovani.md](zmensovani.md). Vyloučeno.

**Prompt se do modelu nedostával celý.** CLIP bere 77 tokenů, zbytek zahodí bez chyby.

| prompt | tokenů | výsledek |
|---|---|---|
| Brokolicový rytíř | 55 (vejde se) | známky 9,1–9,7 |
| Overthinking Ghoul | 120 (useknuto o 43) | kaše |

Useknutý konec byl vždycky `STYLE`, tedy `centered single creature` a
`solid magenta background`. Čím pečlivěji byl prompt napsaný, tím větší kus zadání model
neviděl. V negativním promptu (95 tokenů) odpadaly `duplicate, crowd, team` — tedy
pojistky proti davu. Roj lebek místo jedné příšery nebyl rozmar modelu.

**Závěr pro pořadí:** největší dnešní vada nebyl chybějící model, ale tichá porucha.
Proto je fáze 0 tam, kde je.

---

## Fáze 0 — tiché poruchy (hodiny, nejlepší poměr)

Vady, které nevypadají jako chyba: nic nespadne, jen výsledek je horší, než má být.
Dokud tyhle žijí, žádné další měření nemá váhu — nevíš, jestli měříš model, nebo bug.

### 0.1 Režim „identita" ve studiu je past `— vzniklo dnes, moje chyba`

`identita` se přidala do `gen_ref.REF_MODES`, čímž ji studio automaticky nabídlo
v rozbalovátku a validace ji propustí. Ale `gen_ui.run_generate()`
([gen_ui.py:548-562](../../tools/gen_ui.py)) pro ni nemá větev — **referenci mlčky zahodí
a vygeneruje čistý text2img.** Uživatel vidí volbu, vybere ji, dostane nic.

Dodělat větev (`load_ip_adapter` + `ip_image`), posuvník síly, text do nápovědy.

### 0.2 Studio měří jinou mřížku, než na které běží hra `— nejzávažnější`

V `tools/` žijí dva neslučitelné rastry:

| kde | konstanta |
|---|---|
| `gen_ui.py:77`, `style_audit.py:437` | **16** |
| `install_local.py:59`, `tiles.py:42` | **24** |
| **hra sama** — `scripts/data.gd:50` | **24** |

Brána ve Studiu tedy schvaluje 32px sprity a **odmítla by 24px, přestože hra běží na 24.**
Konstantu číst z `data.gd`, ne ji opisovat na pěti místech.

### 0.3 Obdélníkové dlaždice se ve studiu mačkají

CLI předává `crop_to_subject(aspect=tw/th)`, studio na [gen_ui.py:581](../../tools/gen_ui.py)
volá `crop_to_subject(a)` bez poměru — a `gen_ui.to_sprite()` zmenší na čtverec a pak
zmáčkne NEAREST. Změřeno: tentýž subjekt dá přes CLI 8 plných řádků, přes studio 4.
Docstring té funkce to sám přiznává.

### 0.4 Dlouhý prompt `— zčásti hotovo`

Hotovo: `NEGATIVE` přerovnaný a zkrácený na 76 tokenů (pojistky proti davu první),
`_warn_if_truncated()` vypíše, co odpadlo. Zbývá: totéž do cesty přes studio, a zvážit
chunking (`compel`) pro prompty bez stropu.

### 0.5 Ruční editace pixelů nezapisuje rodokmen

`save_edited_sprite` ([gen_ui.py:1060](../../tools/gen_ui.py)) přepíše soubor a přepočítá
známku, ale do `meta["lineage"]` nezapíše nic. Ruční úprava tedy **tiše zničí kandidáta,
na kterého ukazují jeho děti.** Totéž platí pro rotaci a loutkovou animaci.

### 0.6 Tři cesty zmenšení obcházejí přepínač

`sprite_16.halve` (BOX), `install_local.na_platno` (holý NEAREST), `raster_to_24.zmensi`
(NEAREST ×0,75). Nejsou proti sobě změřené. Sjednotit na `gen.downscale`, nebo aspoň doměřit.

### 0.7 Obrys posouvá odstín

`outline_sprite` používá `clip(…, 8, 70)` per kanál, takže u sytých barev mění hue —
`style_bible.md:33` přitom chce „tmavší odstín TÉŽE barvy". Ztmavovat v Oklab L
(`palette_morph.from_oklch` to už umí). Navíc existují **tři** implementace obrysu a ta
v produkční cestě (`restore_outline`) obrys nepřidává, jen přebarvuje krajní pixely.

---

## Fáze 1 — dokončit IP-Adapter (hodiny)

Kód je napsaný ([gen.py:196-223](../../tools/gen.py), napojení v `generate()`), ale
**ani jednou neproběhl** — stahování vah spadlo na plný disk. Do té doby je to hypotéza,
ne schopnost.

1. Dotáhnout stažení (~700 MB adaptér + ~3,5 GB ViT-bigG enkodér)
2. Pustit A/B: tentýž prompt, tytéž seedy, bez reference proti `--ip-scale` 0,4/0,6/0,8
3. Rozhodnout podle výsledku, ne podle toho, jak nadějně to zní
4. Napojit do studia (viz 0.1)

**Co se rozhodne:** jestli reference drží identitu a strukturu. Když ano, spadne tím
i „osm příbuzných příšer místo jedné otočené".

---

## Fáze 2 — ControlNet (dny) `— hlavní páka na strukturu`

V repozitáři **neexistuje ani jako slovo** — nula shod v celém stromu.

Přitom poslední odstavec `zmensovani.md` končí větou „zbývající podezřelý je struktura
1024px renderu — tedy conditioning modelu". To je přesná definice toho, co ControlNet dělá.
Projekt ví, kam jít; nikdo tam zatím nešel.

- `StableDiffusionXLControlNetPipeline`, model lineart nebo scribble
- řídicí obrázek ze siluety — `lock_to_silhouette` ([gen.py:616](../../tools/gen.py)) už siluety umí
- odladit control scale

**Proč až po IP-Adapteru:** IP-Adapter řeší „kdo to je", ControlNet „jak stojí". Když
první stačí, druhý může počkat. Když ne, teprve pak se ví, co přesně po něm chtít.

---

## Fáze 3 — vlastní LoRA (týdny) `— s opravou, která mění zadání`

`pixellab_parita.md:149` jmenuje LoRA jako „poslední článek" a odkazuje na 1623 čistých
originálů. Audit tenhle předpoklad **vyvrátil**:

> Těch 1623 obrázků jsou **výstupy PixelLabu, ne tvůj vlastní art.** LoRA z nich se naučí
> styl PixelLabu.

Což možná chceš — ale je to jiné zadání než „LoRA na mém artu" a je dobré to vědět předem.
Druhá past: osm směrů téže postavy je osm skoro stejných obrázků; bez vážení model
přetrénuje na jeden pohled.

Co je potřeba: rozhodnout, co je „tvůj art" · popisky ze `character.json` na jednotlivé
snímky · train/val split s vážením duplicit · `kohya-ss/sd-scripts`, bf16, UNet-only
(12 GB je na hraně) · nearest-neighbor zvětšení 64→1024.

---

## Fáze 4 — co zbývá podle auditu

Seřazeno podle poměru dopad/práce, ne podle pilířů:

| co | stav | odhad |
|---|---|---|
| Inpaint — přemalování jedné oblasti | chybí | dny |
| Vyhlazení diagonál (jaggies / mixels) | chybí | dny |
| Zoom a klávesové zkratky v editoru | chybí | hodiny |
| Deska místo šachovnice (sprite v herním měřítku) | chybí | hodiny |
| Fronta úloh (generování je blokující) | částečně | dny |
| Skládání víc LoR najednou | chybí | hodiny |
| Animace podle kostry | chybí | týdny |
| 3D proxy / depth mapy | chybí | týdny |

---

## Co z původního plánu NEstavět

| položka | proč ne |
|---|---|
| **SD 1.5 jako základ** | vlastní měření: na 32 px postavu neumístí, na 64 px nedá rekvizity. SDXL se štítem a kyrysem dal 9,1–9,7. |
| **Nearest neighbor jako zmenšovač** | z 1024 na 64 zahodí 255 z 256 pixelů. Median i k-centroid hlasují z celého bloku a i mezi nimi je rozdíl neměřitelný. |
| **TensorRT / ONNX, odezva do 1 s** | SDXL na 4070 SUPER dělá ~40 s na sprite. Do jedné sekundy se to nedostane a je to optimalizace věci, která není úzké hrdlo. |
| **Cloud GPU (Modal / RunPod)** | zadání bylo „zadarmo" a karta doma stačí. |
| **React / Svelte přepis frontendu** | Sprite Studio funguje. Přepsat UI, které běží, místo dodělání conditioningu je záměna činnosti za pokrok. |
| **libimagequant** | kvantizace v Oklab už je hotová a je lepší — `libimagequant` pracuje v RGB. |
| **3D proxy v Three.js** | týdny práce na věc, kterou ControlNet ze siluety zvládne z 2D podkladu. |
| **AnimateDiff** | animace se dnes dělá loutkově a Animation Lab je hotový. Difuzní animace je řešení hledající problém. |

---

## Stav k 17. 8. 2026 večer

**Fáze 0 hotová.** 0.1 past s `identita` ve studiu · 0.3 obdélníkové dlaždice (4 → 8 plných
řádků z 8) · 0.4 hlídač délky promptu · 0.5 rodokmen u ruční editace · 0.7 obrys už
neposouvá odstín (23,9° → 6,0°).

0.6 se **nedělalo záměrně** — audit se spletl. `halve`, `na_platno` a `zmensi` nejsou
konkurenční zmenšovače, je to jiná úloha, kde je NEAREST/BOX správně. Hranice je popsaná
v `gen.py` u `DOWNSCALERS`.

**0.2 rastr vyřešen** — a nebylo to rozhodnutí, bylo to dohánění. `data.gd:22` říká
„WAS 16, WITH pixel_scale x3. Moved to 24 (and so x2) on 2026-08-17". Hra je konzistentní;
zastaralé byly Python nástroje. Vzniklo `tools/game_raster.py` jako jediná čtečka `data.gd`;
`gen_ui`, `style_audit` i `art_check` z ní teď berou rastr. Nabídka velikostí přepsána na
24/48/96 s pracovními 64/128.

**Fáze 1 hotová** — viz [ip_adapter.md](ip_adapter.md). `IP_SCALE = 0.4`, `IP_NEUTRAL = True`.

### Co zbývá a proč to nejde skriptem

`assets/towers` má 55 hlav na 36 px a 10 na 60 px. Ani jedna nemá **celočíselnou cestu**
na rastr 24: 36 jde jen /3 (na 12 px, což kresbu zničí) nebo ×2 (na 72 px, tedy tři buňky
na obrazovce), 60 dolů nejde vůbec. Neceločíselné zvětšení je podle `data.gd` „the one
thing pixel art cannot survive", takže hromadná migrace je vyloučená — hlavy se musí
vygenerovat znovu na 24 nebo 48.

Zbylých 599 souborů mimo rastr leží v `assets/src/` a jsou to **zdroje**, ne herní art;
mimo rastr být mají. Dalších 6 jsou atlasy 1024 px. Poplach „673 souborů" byl tedy chybný —
skutečný dluh je 65 věžových hlav.

Otevřená otázka: pravidlo brány („násobek nebo dělitel buňky") je psané pro **dlaždice**.
Pro volně stojící sprite, který se jen vystředí na buňku, může být zbytečně přísné. Než se
přegenerují věže, stojí za to ověřit, jestli 36 px hlava ve hře doopravdy sedí špatně.

---

## Souhrn

Ze 63 schopností: **14 hotových, 27 částečně, 22 chybí.** Hotová je celá měřicí polovina —
`art_check`, `style_audit`, `score`, master paleta, rodokmen, Animation Lab, instalace do
Godota. To PixelLab nemá.

Chybí conditioning. A to je z velké části skládání dílů pod Apache 2.0, ne výzkum.

**Fáze 0 je večer práce a odblokuje všechno ostatní.** Bez ní se měří šum.
