# ControlNet — tvar zvenčí

*Fáze 3 plánu. Navazuje na [rotace.md](rotace.md), kde měření ukázalo, že img2img pohled
nezmění vůbec. Kód: `tools/gen_pose.py`, `gen.rotate_pose()`.*

---

## Oprava plánu, kterou je dobré přečíst první

Původní bod v checklistu zněl „výroba řídicího obrázku ze siluety". Je špatně, a stálo za
to na to přijít před psaním kódu, ne po dvou dnech:

> **ControlNet neumí otočit postavu. Umí ji nakreslit do tvaru, který mu dáš.**

Základní sprite je čelní pohled. Jeho silueta by se tedy vnutila i „severu" a „východu" —
což je přesně ta vada z fáze 2, tentokrát vynucená konstrukcí. Otázka nezní „jak zapojit
ControlNet", ale **odkud vzít tvar pro každý směr**.

| zdroj tvaru | cena | kde funguje |
|---|---|---|
| **kostra kreslená z úhlu** — `tools/gen_pose.py` | hotovo | humanoidi |
| ruční skica siluety ve studiu | minuty na postavu | cokoli |
| 3D proxy | týdny | cokoli — zamítnuto |

Kostra je kostra **člověka**. Na avokádového mnicha sedne, na kouli mlhy nemá co popsat.
Není to tak zlé, jak to zní: u koule je pohled zezadu skoro tentýž obrázek jako zepředu,
takže tam, kde kostra nedává smysl, otáčení skoro není potřeba. Horší jsou distrakce —
`adult_con…` je v podstatě předmět a kostra na něj nesedne nikdy.

---

## Tři nezávislé páky

Poprvé je zadání rozdělené tak, že se jednotlivé věci neperou o tutéž páku:

| páka | co určuje | čím |
|---|---|---|
| `control_scale` | **jak stojí** a odkud se díváme | kostra z `gen_pose` |
| `ip_scale` | **kdo to je** — barvy, textura, doplňky | IP-Adapter |
| text | co to je a jak to má vypadat | prompt |

Žádný výchozí obrázek. Kdyby model dostal základní sprite jako `init`, přetlačil by kostru
čelním pohledem — to je ta past, kvůli které fáze 2 dopadla záporně. Proto `rotate_pose`
staví **text2img** rouru, ne img2img.

---

## Jak kostra vzniká

Tělo je popsané v souřadnicích **postavy** — do strany (`u`), dopředu (`w`), dolů (`y`) — a
promítá se do obrazovky jedním otočením kolem svislé osy:

```
x       = u·cos(úhel) + w·sin(úhel)
hloubka = w·cos(úhel) − u·sin(úhel)
```

Osm směrů je pak osm hodnot jednoho úhlu, ne osm ručních kreseb. Viditelnost vypadne
z téhož vzorce sama: při pohledu zezadu má nos zápornou hloubku, takže zmizí, kdežto uši
mají `w` skoro nulové a drží. Přesně tak se chová i skutečný annotator na fotce člověka
zezadu.

**Výkrok není ozdoba.** Z profilu mají obě ramena totéž `x`, protože do strany se promítne
nula — bez výkroku by kostra zdegenerovala do jedné čáry. Výkrok končetiny rozestoupí právě
v tom pohledu, kde je to potřeba.

### Dva kánony a proč

Openpose se učil na **fotkách lidí**, takže osmihlavý kánon je to, co model zná a co
poslušně nakreslí. Jenže hra je chibi: avokádový mnich má hlavu přes půlku výšky.

První kouřová zkouška to ukázala hned — lidský kánon udělal z chibi ghoula lanky
človíčka, známka 7,4. Obchod jde na obě strany a nedá se z něj vyklouznout:

| kánon | model ho zná | výsledek je ve stylu hry |
|---|---|---|
| `human` | ano | ne |
| `chibi` | hůř | spíš ano |

Kánon na dvě hlavy (skutečné proporce hry) se **neosvědčil už při kreslení**: hlavové body
se odtrhnou od krku do široké tyčky vznášející se nad tělem, což model nepřečte jako
člověka, ale jako dva objekty. `chibi` je proto kompromis kolem tří hlav — nejchibiovatější
kánon, který ještě drží pohromadě.

---

## Kolik se toho vejde na kartu

Tohle zabralo víc času než všechno ostatní dohromady a je to nejpřenositelnější poznatek
z celé fáze 3.

Změřeno 18. 8. 2026 na 4070 SUPER. Karta má 12 282 MiB, ale **volných je jen 11 069** —
zbytek si drží Windows. To je první číslo, které se plete: počítat se dá s ~11 GB, ne s 12.

| co | VRAM |
|---|---|
| SDXL + LoRA | 6 887 MiB |
| + ControlNet openpose | ~2 440 MiB |
| + obrázkový enkodér ViT-bigG | ~1 850 MiB |
| **dohromady** | **~11 180 MiB — nevejde se** |

Při překročení **to nespadne a nic to nenahlásí**. Ovladač začne přelévat do systémové
paměti a jeden směr trvá **375 sekund** místo desítek. Poznat se to dá jedině na příkonu:
65 W z 220 W při 100 % vytížení znamená, že karta čeká na paměť, ne že počítá.

### Špičku nestačí uklidit, nesmí vzniknout

První pokus byl předpočítat podmiňování a enkodéry z karty odložit. Zabralo to jen zčásti
(375 → 225 s) a měření řeklo proč: `mem_get_info` hlásil po odložení pořád **`volno 0`**.

> Jakmile ovladač jednou začne přelévat, v témže procesu už z toho nevycouvá.

Viník byl **soubor enkodéru**: ViT-bigG je uložený v **fp32 a má 3,69 GB**. Načtení na
kartu proto nejdřív vyrobí fp32 kopii a teprve z ní fp16 (1,85 GB) — špička přes 5 GB na
kartu, kde už sedí SDXL a volno jsou 3,9 GB. A `pipe.load_ip_adapter()` si ho na kartu
stáhne sám, takže přesunout ho zpátky *potom* je pozdě.

Řešení: načíst enkodér rovnou na procesor (`image_encoder_folder=None` + vlastní
`CLIPVisionModelWithProjection` ve float32) a embeddingy spočítat tam. Na kartu jde jen
výsledek, což je pár kilobajtů místo 1,85 GB. Enkodér stejně běží **jednou za celý cyklus**,
takže na jeho rychlosti nezáleží.

Totéž pro **textové enkodéry**: `encode_prompt` se zavolá dopředu na všechny směry a modul
odejde z karty. Moduly jsou sdílené se všemi ostatními rourami, takže se v `finally`
vracejí; jinak by další generování v témže procesu spadlo na neshodě zařízení a vypadalo by
to jako vada někde úplně jinde.

### Druhá páka: rozlišení

Aktivace rostou s **plochou** latentu, takže render je nejlevnější škrtidlo:

| render | s/krok (identita 0,6) | s/krok (bez identity) |
|---|---|---|
| 1024 | 2,09 | 1,56 |
| **768** | **1,09** | 0,64 |
| 640 | 0,94 | 0,50 |

768 je zlom — polovina času proti 1024, kdežto 640 už skoro nic nepřidá. Na sprite 32–64 px
při 768 pořád zbyde 12 až 24 zdrojových pixelů na pixel spritu, tedy hluboko nad prahem 8,
pod kterým zmenšení začne zahazovat detail rychleji, než ho model stihne nakreslit.
Nesnižuje se tedy kvalita, jen se přestává platit za něco, z čeho na 32pixelovém spritu
stejně nic nezbyde. Odtud `POSE_RENDER = 768`.

### Výsledek

| | s na směr (28 kroků) | osm směrů |
|---|---|---|
| jak to začalo | 375 | ~50 minut |
| po předpočítání podmiňování | 225 | ~30 minut |
| **+ enkodér na procesoru, render 768** | **~30** | **~4 minuty** |

**Pozor na měření v jednom procesu.** Podmínky za sebou nejsou nezávislé — alokátor si
paměť drží, takže druhá a další podmínka startuje z horšího stavu než ta první. Čísla výš
platí pro čistý start; v jednom běhu je věrohodná hlavně ta první.

`gen.vram()` tuhle past hlídá: vypíše volno a upozorní, když spadne pod ~1,2 GB.

---

## Měření: mění se pohled?

*Tatáž předloha, tytéž metriky a tytéž směry jako ve fázi 2, aby se čísla dala položit vedle
sebe. Data v `build/gen/_cn_test/`.*

| podmínka | změna pohledu | symetrie |
|---|---|---|
| předloha | — | 0,89 |
| **fáze 2** (img2img, čtyři podmínky) | 0,003–0,036 | 0,87–0,92 |
| kontrola: stejná kostra všem směrům | 0,000–0,049 | 0,928–0,950 |
| **kostra podle směru** — jih | 0,000 | 0,928 |
| **kostra podle směru — východ** | **0,394** | **0,785** |
| kostra podle směru — sever | 0,143 | 0,919 |
| **kostra podle směru — západ** | **0,386** | **0,756** |

**Změna pohledu** = 1 − překryv siluety proti jihu · **symetrie** = překryv siluety s vlastním
zrcadlem; čelní pohled ≈ 0,93, profil musí spadnout výrazně níž.

### Co z toho plyne

**Profil funguje.** Východ a západ mají symetrii 0,76–0,79 proti čelním 0,93 a změnu pohledu
0,39 proti 0,003 z fáze 2 — o dva řády. Na kontaktním listu je to vidět bez měření: hlava
otočená do strany, jedno oko, chodidla do profilu.

**Kontrolní vzorek to potvrzuje.** Se stejnou kostrou pro všechny směry vyjdou čtyři
prakticky totožné čelní pohledy. Rozdíl tedy dělá **kostra**, ne text a ne náhoda.

To je odpověď na otázku, kvůli které celá fáze 3 vznikla: **ControlNet dokáže to, co
img2img prokazatelně nedokázal.**

### Sever zatím ne — a je jasné proč

Sever vyšel jako čelní pohled (změna 0,143, symetrie 0,919). Není to náhoda ani slabé
nastavení:

> Kostra otočená o 180° je **zrcadlově tatáž kostra** jako zepředu. Ramena, boky
> i končetiny sedí na týchž místech. Jediný rozdíl je, že zmizí nos a oči — a to model
> přebije svým sklonem kreslit obličeje.

Profil kostra říct **umí** (ramena splynou do jedné osy), záda **neumí**. Je to vlastnost
formátu, ne chyba v kódu — a stojí za to ji vědět dřív, než se začne ladit control scale
v domnění, že je to slabé.

Zkoušená oprava: **cílený negativní prompt pro záda** (`negative_for()`), který přidá
`face, eyes, mouth, looking at viewer`. Musí se přitom vejít do 77 tokenů, takže se
nejméně důležitý konec obecného negativu **vymění**, nepřidá — kdyby se přidal, useknutí
by zahodilo právě ty nové položky a nikdo by se to nedozvěděl. Přesně tak vznikl roj lebek
i šedá pozadí.

**Nezabralo.** Změna pohledu 0,143 → 0,171, symetrie 0,919 → 0,904 — při jednom seedu je to
šum, a na kontaktním listu má sever pořád obličej, jen tmavší oči. `back_negative` je proto
**výchozí vypnutý**: stojí dvě položky obecného negativu a nic za to nedává. Kód zůstává,
aby to za půl roku nikdo nezkoušel znovu.

Další nápad, zatím nezkoušený: **vyřešit sever inpaintem** — vzít čelní výsledek,
zamaskovat obličej a přemalovat na zátylek. `gen.inpaint()` už existuje, takže je to
skládání hotových dílů, ne nový výzkum.

### Jenže: na avokádovém mnichovi sever vyšel

Zkouška celé cesty z příkazové řádky na **humanoidovi** dopadla jinak než na ghoulovi:
východ je čistý profil **a sever je skutečný pohled zezadu** — kápě jako hladký zelený ovál
bez obličeje, ramena a hábit odzadu.

Rozdíl není v nastavení, ale v postavě:

> Sever selže tam, kde má postava **holou tvář**. Kde má kapuci, vlasy nebo plášť, model
> ví, jak vypadají záda, a nakreslí je.

Není to tedy tvrdá hranice ControlNetu, ale hranice toho, co model o té konkrétní postavě
ví. Praktický důsledek: **u postav s holou tváří počítej se severem jako s ruční prací**
(nebo s tím inpaintem výš), u zahalených ne.

Tatáž zkouška odhalila i to, že **`IP_SCALE = 0.4` je pro kostrovou cestu málo** — z avokáda
se stal obecný zelený mnich. Odtud samostatné `POSE_IP_SCALE = 0.6`.

---

## Sweep: co nastavit

*Šest podmínek, každá ve vlastním procesu. Předloha stejná, seed stejný.*

| podmínka | symetrie (J/V/S/Z) | známky |
|---|---|---|
| kontrola: stejná kostra | 0,93 · 0,94 · 0,95 · 0,95 | 7,7–7,9 |
| kostra 0,7 chibi | 0,93 · 0,79 · 0,92 · 0,76 | 7,6–8,0 |
| kostra 0,7 + zádový negativ | 0,93 · 0,79 · 0,90 · 0,76 | 7,5–8,4 |
| **kostra 0,9 chibi** | 0,85 · **0,82** · 0,90 · **0,52** | **7,7–8,5** |
| kostra 0,7 human | 0,94 · 0,95 · 0,86 · 0,92 | 7,2–7,7 |
| kostra 0,7 bez identity | 0,84 · 0,21 · 0,72 · 0,36 | 5,9–7,9 |

### Tři věci, které měření rozhodlo

**1. `chibi` porazil `human` — proti očekávání.** Čekal jsem, že model svůj vlastní kánon
poslechne líp. Nestalo se: u `human` má východ symetrii 0,95, tedy žádný profil, a známky
spadly na 7,2–7,7. Osmihlavá kostra navíc udělá z chibi postavičky hubeňoura.

**2. Síla 0,9 je lepší než 0,7.** Profily jsou čistší (západ 0,52) a známky o něco vyšší.
Cena je, že se výkrok kostry propíše i do čelního pohledu (jih 0,93 → 0,85). Vadí to míň,
než to zní: **jižní pohled je předloha, tedy ho už máš** — generuje se jen kvůli společné
paletě a dá se vynechat přes `--dirs`.

**3. Bez IP-Adapteru to čísla vyhrálo a obrázek prohrál — a rozhoduje obrázek.**
Metriky u „bez identity" vypadají skvěle (východ 0,21, západ 0,36, konečně se hnul
i sever). Na kontaktním listu je ale vidět, že to **nejsou otočené pohledy téže příšery,
ale jiné příšery**: z bílého ghoula se stalo fialové monstrum a západ je rozpadlý fragment.

> Symetrie neodliší „čistý profil" od „úplně jiného obrázku". Je to tatáž past, na kterou
> ve fázi 2 najela metrika identity, jen z druhé strany.

IP-Adapter tedy rotaci **skutečně brzdí** — reference je čelní pohled a model si ji drží —
ale vypnout ho nejde, protože pak to není tatáž postava. Správná cesta není mezi „0,6 nebo
0,0", ale najít nižší sílu, nebo držet identitu jinak (`lock_to_palette` už existuje).

**Nastaveno:** `CONTROL_SCALE = 0.9`, `ip_scale = 0.6`, kánon `chibi`.

---

## Licence

`xinsir/controlnet-openpose-sdxl-1.0` je **Apache 2.0**, ověřeno přes HF API 18. 8. 2026 —
tedy včetně komerčního užití, stejně jako IP-Adapter a na rozdíl od Pixelization
a Retro Diffusion. Totéž platí pro `scribble` a `union` od téhož autora. Alternativa
`diffusers/controlnet-canny-sdxl-1.0` je openrail++, což je licence samotného SDXL.

---

## Jak se to volá

```bash
python tools/gen.py "Overthinking Ghoul, hunched shadowy purple entity" \
    --from build/gen/.../cand_04.png --pose --dirs south,east,north,west

python tools/gen.py "..." --from ... --pose --canon human --control-scale 0.9
```

`--pose` a `--rotate` se navzájem vylučují — jsou to dvě různé cesty a slučovat je nemá
smysl:

| | co dělá |
|---|---|
| `--pose` | ControlNet + kostra; pohled se skutečně změní |
| `--rotate` | img2img; překreslí čelní pohled na variantu **téhož** pohledu |
