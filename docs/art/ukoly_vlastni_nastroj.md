# Vlastní generátor na úrovni PixelLabu — seznam úkolů

*Odškrtávací verze plánu z [plan_vlastni_nastroj.md](plan_vlastni_nastroj.md). Postaveno na
auditu 63 schopností a na měřeních ze 17. 8. 2026. Odhady jsou večery práce, ne ideální dny.*

**Jak to číst:** `[x]` hotovo a ověřeno · `[ ]` čeká · **⚠** blokuje něco dalšího ·
**?** rozhodnutí, ne práce

---

## Fáze 0 — tiché poruchy `HOTOVO`

> Vady, které nic neshodí, jen zhorší výsledek. Dokud žily, žádné měření nemělo váhu.

- [x] **Past s režimem „identita" ve studiu** — volba šla vybrat, ale `run_generate()` ji ignoroval
  - [x] větev pro identitu v `gen_ui.run_generate()`
  - [x] posuvník síly reference slouží oběma režimům
  - [x] zápis do `meta.json`
- [x] **Obdélníkové dlaždice se mačkaly** — 4 → 8 plných řádků z 8
  - [x] `gen_ui.to_sprite()` volá `gen.downscale((w, h))` přímo
  - [x] `crop_to_subject(aspect=…)` i ve studiu
- [x] **Prompt se tiše usekával na 77 tokenů**
  - [x] `_warn_if_truncated()` vypíše, co odpadlo
  - [x] `NEGATIVE` přerovnaný a zkrácený na 76 tokenů
- [x] **Ruční editace ničila rodokmen** — zapisuje `hand_edited` + počítadlo
- [x] **Obrys posouval odstín** — Oklab L + chroma ×0,45; 23,9° → 6,0°
- [x] **Rastr 16 vs 24** — `tools/game_raster.py` čte `data.gd`; `gen_ui`, `style_audit`, `art_check` z ní berou
  - [x] nabídka velikostí přepsaná na 24/48/96 + pracovní 64/128
- [x] ~~Sjednotit tři cesty zmenšení~~ — **záměrně ne**, audit se spletl; hranice popsaná v `gen.py`

### Zbytky z fáze 0

- [x] `hand_edited` vytáhnout do proužku předků v detailu — oranžový rámeček + `✎` s počtem úprav
- [x] Rodokmen u rotace a loutkové animace — dřív vyráběly soubory z kandidáta a do řetězu se nezapsaly vůbec
- [ ] Chunking promptu (`compel`) — zrušit strop 77 tokenů úplně *(hodiny)*
  - [ ] nejdřív **změřit**, jestli to pomůže: useknutý vs. celý vs. ručně zkrácený na 55 tokenů
  - [ ] možná zjistíme, že na 64 px je 120 tokenů přeurčení tak jako tak

---

## Fáze 1 — identita z obrázku (IP-Adapter) `HOTOVO`

> První zásah, který se skutečně projevil: +1 známka, šum na polovinu, ze skvrn těla.

- [x] `load_ip_adapter()` + předání do `generate()`
- [x] čtvrtý režim reference `identita` (CLI i studio z jednoho slovníku)
- [x] `--ip-scale`, `--ip-color`
- [x] **Odbarvení předlohy** (`gen_ref.ref_identity`) — barvy promptu 10 % → 88 %
- [x] Změřeno a zapsáno → [ip_adapter.md](ip_adapter.md)
- [x] Opraveno: attention slicing se tluče s IP-Adapterem
- [x] Opraveno: obrázkový enkodér zůstával na CPU

### Otevřená vada z fáze 1

- [ ] **⚠ Šedé pozadí u 2 ze 6 spritů** — `cut_background` nemá čeho se chytit *(hodiny)*
  - [ ] zkusit širší magentový okraj v předloze
  - [ ] nebo zvednout toleranci `cut_background`
  - [ ] ověřit na 6+ seedech, ne na dvou

---

## ⚠ Než pustíš cokoli na kartě: uvolni VRAM

Naměřeno 18. 8. 2026. Karta má 12 GB a SDXL potřebuje skoro celou. Když na ní visí něco
dalšího, model **přeteče do systémové paměti** a generování se zpomalí zhruba 10×
(6 minut na sprite místo ~40 sekund). Nespadne to, nic to nenahlásí — jen to trvá věčnost.

```bash
nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv
nvidia-smi --query-compute-apps=pid,used_memory --format=csv
```

Nejčastější žrouti, které nikoho nenapadnou: **Epic Games Launcher**, **Overwolf**,
**EOS Overlay** — Chromium aplikace s GPU akcelerací, každá pár set MB VRAM. Zavřít před
generováním; prohlížeč s mnoha panely taky.

- [x] **`from_pipe` v `build_img2img` byl skutečný viník** — VRAM 7,3 → 12,0 GB a img2img
      31× pomaleji (52 s → 1,6 s na 512 px). Opraveno na `I2I(**pipe.components)`.
- [ ] Přidat kontrolu volné VRAM do `build_pipe()` a varovat, když je jí míň než ~9 GB *(hodiny)*

---

## Fáze 2 — rotace a identita napříč směry `HOTOVO — VÝSLEDEK ZÁPORNÝ`

> Rozhodující zkouška proběhla. Odpověď: **img2img neumí změnit pohled.** Ani s
> IP-Adapterem, ani bez něj, ani při síle 0,85. Detaily → [rotace.md](rotace.md).

- [x] Napojit předlohu do rotace (`rotate_ip` opravena — `.convert("RGB")` černil pozadí)
- [x] Metrika, která pozná změnu pohledu — symetrie siluety, ne jen identita
- [x] Sweep síly 0,50 / 0,70 / 0,85 + kontrolní vzorek bez IP
- [x] **? Rozhodnuto: ControlNet JE potřeba** — žádné ladění img2img to nezachrání
- [x] Vedlejší nález: hra bere jen 3 směry a západ zrcadlí (`defender_unit.gd:415`)
- [x] Opraveno: `unload_ip_adapter()` — načtený adaptér jinak otráví celý proces
- [ ] Přejmenovat `rotate`/`rotate_ip` — dnes to nejsou rotace, ale generátory variant *(hodiny)*

---

## Fáze 3 — ControlNet `PROBÍHÁ`

> Fáze 2 změřila, že bez něj se pohled nezmění vůbec — tohle už není „možná", je to jediná
> zbývající cesta k osmi směrům vlastními silami.

### Oprava plánu: řídicí obrázek NESMÍ být ze siluety

Původní bod zněl „výroba řídicího obrázku ze siluety, `lock_to_silhouette` to už umí".
**Je špatně** a stálo za to na to přijít dřív než po dvou dnech práce:

> **ControlNet neumí otočit postavu. Umí ji nakreslit do tvaru, který mu dáš.**

Základní sprite je čelní pohled, takže jeho silueta by se vnutila i „severu" a „východu" —
tedy přesně ta vada z fáze 2, tentokrát vynucená konstrukcí. Otázka není „jak zapojit
ControlNet", ale **odkud vzít tvar pro každý směr**. Tři zdroje, podle ceny:

| zdroj tvaru | cena | kde funguje |
|---|---|---|
| **kostra kreslená z úhlu** (`tools/gen_pose.py`) | hotovo | humanoidi |
| ruční skica siluety ve studiu | minuty na postavu | cokoli |
| 3D proxy | týdny | cokoli — zamítnuto |

U koule mlhy kostra nedává smysl, ale tam otáčení skoro není potřeba: pohled zezadu je
u ní skoro tentýž obrázek jako zepředu.

- [x] Vybrat model — `xinsir/controlnet-openpose-sdxl-1.0`, **Apache 2.0** (ověřeno přes
      HF API 18. 8. 2026; scribble i union od téhož autora taky)
- [x] `build_control_pipe()` vedle stávající roury — text2img, ne img2img (init by
      kostru přetlačil čelním pohledem, viz výše)
- [x] `tools/gen_pose.py` — kostra COCO18 promítnutá z úhlu, osm směrů z jednoho vzorce
- [x] `rotate_pose()` — tři nezávislé páky: kostra = pohled, reference = identita, text = zbytek
- [x] Dva kánony kostry (`human` / `chibi`) — první zkouška ukázala, že osmihlavý kánon
      udělá z chibi postavy hubeňoura
- [x] **VRAM: SDXL + ControlNet + IP-Adapter se na 12GB kartu nevejde** → [controlnet.md](controlnet.md)
  - [x] enkodér ViT-bigG je v souboru **fp32 (3,69 GB)**, takže špička při načtení na kartu
        je přes 5 GB — a `load_ip_adapter` si ho tam stáhne sám
  - [x] **špičku nestačí uklidit, nesmí vzniknout**: po odložení hlásil `mem_get_info`
        pořád `volno 0`, protože z přelévání se v témže procesu nevycouvá
  - [x] enkodér se načítá rovnou na procesor, textové enkodéry se předpočítají a odloží
  - [x] `POSE_RENDER = 768` — změřeno, polovina času proti 1024 a na 32–64px sprite se nic
        neztratí
  - [x] **375 s → ~30 s na směr**; osm směrů z 50 minut na 4
- [x] `gen.vram()` — hlídá, protože překročení se neprojeví chybou, jen desetinásobným
      časem *(pokrývá i položku „kontrola volné VRAM" níž)*
- [x] Zapojeno do CLI: `--pose`, `--canon`, `--control-scale`
- [x] **Změřeno proti fázi 2 — profil se OTOČÍ** → [controlnet.md](controlnet.md)
  - [x] kontrolní vzorek: stejná kostra pro všechny směry dala **4× čelní pohled**
        (změna pohledu 0,00–0,05, symetrie 0,93–0,95) — metrika tedy měří, co má
  - [x] kostra podle směru: **východ a západ symetrie 0,76–0,79** proti čelním 0,93,
        změna pohledu **0,39** proti 0,003 z fáze 2 — o dva řády
  - [x] na kontaktním listu je profil vidět bez měření: hlava do strany, jedno oko,
        chodidla do profilu
- [x] Zapojeno do studia — rozbalovátko se třemi režimy, kostra výchozí
- [x] **Odladěno šesti podmínkami** → `CONTROL_SCALE = 0.9`, `POSE_IP_SCALE = 0.6`, kánon `chibi`
  - [x] **`chibi` porazil `human`** — proti očekávání; u `human` má východ symetrii 0,95,
        tedy žádný profil, a známky spadly na 7,2–7,7
  - [x] 0,9 dává čistší profily než 0,7; cenou je čelní pohled (0,93 → 0,85), což vadí míň,
        než to zní — **jižní pohled je předloha, tedy ho už máš**
  - [x] **past: bez identity to vyhrálo v číslech a prohrálo na obrázku.** Symetrie 0,21
        neznamená čistý profil, ale úplně jinou příšeru (a rozpadlý západ). Tatáž past jako
        u metriky identity ve fázi 2, jen z druhé strany — rozhoduje oko.
  - [x] `IP_SCALE = 0.4` je pro kostru málo — z avokáda se stal obecný zelený mnich
  - [ ] najít nižší `ip_scale`, kde identita drží a rotaci nebrzdí (0,6 je kompromis, ne optimum)
- [ ] **Pohled zezadu: závisí na postavě, ne na nastavení**
  - [x] kostra otočená o 180° je **zrcadlově tatáž kostra** jako zepředu; zmizí jen nos
        a oči, což model přebije svým sklonem kreslit obličeje
  - [x] zkoušený cílený negativ (`face, eyes, mouth, looking at viewer`) **nezabral** —
        0,143 → 0,171, tedy šum; na obrázku pořád obličej, jen tmavší oči. Výchozí vypnutý.
  - [x] **na avokádovém mnichovi sever ale VYŠEL** — kápě jako hladký ovál bez obličeje.
        Selže tedy jen u **holé tváře**; kde je kapuce, vlasy nebo plášť, model záda umí.
  - [ ] u postav s holou tváří: zkusit inpaint — zamaskovat obličej a přemalovat na
        „zátylek". `gen.inpaint()` už existuje, takže je to složení dílů, ne nový výzkum.

---

## Fáze 4 — vlastní LoRA `TÝDNY`

> Nejdražší a nejnejistější krok. **Až naposled** — styl je z těch tří věcí nejmíň rozbitý.

- [ ] **? Rozhodnout, co je „tvůj art"** — audit vyvrátil původní předpoklad
  - [ ] těch 1623 PNG v `build/pixellab/` jsou **výstupy PixelLabu**, ne tvoje kresba
  - [ ] LoRA z nich se naučí styl PixelLabu — možná to chceš, ale je to jiné zadání
  - [ ] alternativa: trénovat na `assets/` (hotový herní art, prošlý branami)
- [ ] Příprava dat *(dny)*
  - [ ] popisky z `character.json` na jednotlivé snímky
  - [ ] nearest-neighbor zvětšení 64 → 1024 (pixelová mřížka se musí zachovat)
  - [ ] vážení duplicit — osm směrů téže postavy je osm skoro stejných obrázků
  - [ ] train/val split
- [ ] Trénink *(dny)*
  - [ ] `kohya-ss/sd-scripts`, bf16, UNet-only (12 GB je na hraně)
  - [ ] checkpoint po každé epoše — skoro nikdy nevyhraje poslední
  - [ ] porovnat epochy na stejném promptu a seedu
- [ ] Vyhodnotit proti stávající `nerijs/pixel-art-xl` — a nechat si tu lepší
- [ ] Skládání víc LoR najednou *(hodiny)*

---

## Fáze 5 — chybějící schopnosti nástroje

Seřazeno podle poměru dopad/práce, ne podle pilířů.

- [ ] **Inpaint — přemalování jedné oblasti** *(dny)* — v auditu „nejcennější chybějící věc"
  - [ ] odpověď na „tohle je skoro ono, jen ty oči"
  - [ ] maska + img2img jen v ní
- [ ] **Vyhlazení diagonál** (jaggies / mixely) *(dny)* — jediná položka z původního plánu, která fakt chybí
- [ ] Zoom a klávesové zkratky v editoru *(hodiny)*
- [ ] Deska místo šachovnice — sprite v herním měřítku na skutečném pozadí *(hodiny)*
- [ ] Fronta úloh — generování je dnes blokující *(dny)*
- [ ] Import palety z Lospecu *(hodiny)*
- [ ] Animace podle kostry *(týdny)*

---

## Fáze 6 — art dluh

- [ ] **⚠ 65 věžových hlav mimo rastr** (55× 36 px, 10× 60 px) *(dny)*
  - [ ] **? Nejdřív ověřit, jestli je to vůbec vada** — pravidlo brány („násobek nebo
        dělitel buňky") je psané pro **dlaždice**. Volně stojící hlava se jen vystředí
        a měřítko dostane z `Data.pixel_scale()`.
  - [ ] jestli ano: **přegenerovat**, ne přeškálovat — 36 nemá celočíselnou cestou na 24
        ani na 48 (jen /3 na 12, což kresbu zničí, nebo ×2 na 72, tři buňky)
- [ ] Dokončit `raster_to_24.py` na zbytku, který na to čeká
- [ ] Doplnit citaci souhlasu Astropulse do [retrodiffusion.md](retrodiffusion.md) — placeholder tam pořád je

---

## Co záměrně nestavíme

| položka z původního zadání | proč ne |
|---|---|
| SD 1.5 jako základ | vlastní měření: na 32 px postavu neumístí, na 64 px nedá rekvizity |
| Nearest neighbor jako zmenšovač | z 1024 na 64 zahodí 255 z 256 pixelů |
| TensorRT / ONNX, odezva do 1 s | SDXL na 4070 SUPER dělá ~40 s; není to úzké hrdlo |
| Cloud GPU (Modal / RunPod) | zadání bylo „zadarmo" a karta doma stačí |
| Přepis frontendu do Reactu | Sprite Studio funguje; přepsat běžící UI místo conditioningu je záměna činnosti za pokrok |
| libimagequant | kvantizace v Oklab už je hotová a je lepší (libimagequant jede v RGB) |
| 3D proxy v Three.js | týdny na věc, kterou ControlNet zvládne z 2D siluety |
| AnimateDiff | animace se dělá loutkově, Animation Lab je hotový |

---

## Kde to celé stojí

Ze 63 schopností z auditu: **14 hotových, 27 částečně, 22 chybí** — plus to, co přibylo dnes.

Hotová je celá **měřicí** polovina (`art_check`, `style_audit`, `score`, master paleta,
rodokmen, Animation Lab, instalace do Godota). To PixelLab nemá.

Chybí **conditioning** — a to je z velké části skládání dílů pod Apache 2.0, ne výzkum.

**Nejbližší rozcestí je fáze 2.** Její výsledek rozhodne, jestli je před tebou práce na
týdny (ControlNet + LoRA), nebo jestli je díra proti PixelLabu v podstatě zavřená a zbytek
je dodělávání pohodlí.
