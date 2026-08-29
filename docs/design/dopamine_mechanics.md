# Zážitek a mechaniky — designový rozbor

> **Status:** návrh je **implementovaný** — viz [kapitola 13](#13-stav-kódu) pro
> přesný stav, co je v kódu a co ještě potřebuje obsah (mapy levelů 3–7).
>
> **Jazyk:** tělo dokumentu je česky. **Všechny názvy mechanik, identifikátory a
> texty pro hráče jsou anglicky**, aby se daly zvednout přímo do implementace
> (viz `Data.TERM` v `docs/core/00_overview.md`).

---

## Obsah

1. [Jádro: dopamin není hladina, je to derivace](#1-jádro)
2. [Rámování: Tolerance je zdroj, ne trest](#2-rámování)
3. [Přehlednost: jeden systém = jeden smysl](#3-přehlednost)
4. [Tři vrstvy informace](#4-tři-vrstvy)
5. [Mechaniky — detailně](#5-mechaniky)
6. [Reklamy](#6-reklamy)
7. [Telemetrie: jeden log](#7-telemetrie)
8. [Účtenka po levelu](#8-účtenka)
9. [Etika a pravidla pro texty](#9-etika)
10. [Plán po levelech](#10-plán)
11. [Rizika](#11-rizika)
12. [Co škrtnout](#12-co-škrtnout)
13. [Stav implementace](#13-stav-kódu)

---

<a name="1-jádro"></a>
## 1. Jádro: dopamin není hladina, je to derivace

Současný design zachází s dopaminem jako s **hladinou**. Tolerance je číslo 0–100,
odměna je `base_reward * (1.0 - 0.6 * ratio)`. Je to čisté a funguje to.

Ale dopamin hladina není. Je to **derivace**.

**Schultz (1997), reward prediction error:** dopaminové neurony nekódují odměnu.
Kódují **rozdíl mezi očekáváním a skutečností**.

| Situace | Dopaminová odezva |
|---|---|
| Odměna, kterou jsi čekal | **nula** |
| Odměna, kterou jsi nečekal | salva |
| Odměna, kterou jsi čekal a nepřišla | **propad pod klidovou hladinu** |

Z toho plyne věc, kterou současná Tolerance neumí říct:

> **Není to o množství. Je to o překvapení.**

Proto tě nudí hra, kterou máš vyřešenou, i když v ní vyhráváš. Proto přepínáš
appky, i když ta první funguje. Proto je desátý Quick Hit prázdný — ne kvůli
receptorům, ale protože ho mozek už čekal.

**Tolerance = stmívač. RPE = motor.** Přidat motor odemkne většinu mechanik níž.

### Druhý pilíř vědy: wanting ≠ liking

**Berridge:** chtění a líbení jsou **dva různé systémy**. Dopamin řídí chtění
(incentive salience). Opioidy řídí líbení. Můžeš zoufale chtít něco, co ti nedělá
radost — **a to je závislost**, ne "chtít moc příjemných věcí".

Jedna Tolerance dělá obě práce najednou, a proto to nemůže ukázat. Viz [5.4](#54).

### Třetí pilíř: knowing ≠ helping

Nejdůležitější a nejvíc přehlížený fakt pro celý projekt:

> **Každý už to ví.** Každý teenager ví, že TikTok je navržený, aby ho udržel.
> Scrolluje dál. Kdyby stačila informace, problém by neexistoval.

Hra, která doručí fakta, **selže**, protože fakta nejsou ta chybějící součástka.
Hra musí demonstrovat, že **vědět nestačí** — a udělat to na hráči, ne o něm.

Nejčistší nástroj na tohle jsou parodické reklamy ([kapitola 6](#6-reklamy)):
hráč se jim směje, vidí skrz ně, a stejně klikne.

---

<a name="2-rámování"></a>
## 2. Rámování: Tolerance je zdroj, ne trest

**Toto je nejdůležitější rozhodnutí v celém dokumentu**, protože sladí dva cíle,
které vypadají, že se perou: *hra musí být sranda a relax* × *hra musí mít
message*.

### Problém současného rámování

Text hry čte Toleranci jako **trest**: hraješ špatně → hra se zhorší. Trest není
relax. A hlavně: **je to nepřesná lekce.** Mozek není jednosměrný. Receptory se
vrací.

### Oprava

> **Tolerance není trest. Je to zdroj, který utrácíš.**

**Quick Hit musí být někdy správný tah.** Vlna se láme, potřebuješ 30 Dopaminu
teď hned, sáhneš po něm, zachráníš level. To je dovedná hra a hra tě za ni má
odměnit. Co to stálo, je juice — a ten se vrátí, když pár vln zahraješ čistě.

Loop se tím mění ze **sestupu** na **rytmus**:

```
push  →  uklidnění  →  push  →  uklidnění
```

Rytmus je relax. Sestup je domácí úkol.

### Proč je to i lepší věda a lepší message

"Internet ti zničil mozek" vyvolá obranu a zavře uši. **"Existuje rychlost, a
takhle se cítí být nad ní a pod ní"** je něco, s čím se dá pracovat. Pro mladé
lidi je hodnější zpráva ta, která doopravdy dopadne.

### Rozpočet čísel

| Tolerance | Kdy tam hráč je | Jak to vypadá |
|---|---|---|
| **0–30** | Normální hra. **80 % času.** | Plný juice. Nic nechybí. |
| **30–60** | "Zrovna tlačím." Vědomá volba. | Znatelné, pořád dobré. Napětí, ne ošklivost. |
| **60+** | Vzácné. Musíš to chtít. | Šedá díra. |

**Klíč:** hráč, který hraje normálně, šedou nikdy neuvidí. Uvidí ji jen ten, kdo
si o ni řekne — **a to je přesně ten, kdo tu lekci potřebuje.**

> Lekce je **opt-in** a chytne správné lidi.

### Strop juice musí přes kampaň RŮST

Level 6 při nízké Toleranci musí být krásnější, než byl level 1 kdy. Aby vzpomínka
na hru byla **"zlepšilo se to"**, a temný úsek byl **údolí uprostřed, ne cíl**.

### Poměr 80/20

Rozdělte mechaniky na dvě hromádky:

**Běží pořád** (musí být neviditelné): Tolerance→juice, novelty tax, decay.
Je to **stmívač na věcech, co už existují**. Nula nových obrazovek, nula čísel.

**Stane se jednou** (trvá 10 sekund): prázdná bonus vlna, odhalení cue, fake
notifikace, půstový level, "pusť myš", každá reklama.

Jednorázovky **nestojí nic** na průběžné složitosti. 95 % hraní je čistá klidná
TD hra. Zbylých 5 % jsou momenty, které se zaryjou.

> **Pravidlo: maximálně jeden "moment" na level.** Zbytek je jen dobrá TD.

---

<a name="3-přehlednost"></a>
## 3. Přehlednost: jeden systém = jeden smysl

Hra se rozmaže ve chvíli, kdy **dva systémy hýbou stejným výstupem** — pak hráč
netuší, co způsobilo co. Přiřaď každému systému **přesně jeden kanál** a nikdy
ho nesdílej.

| Systém | Vlastní kanál | Nikdy nesahá na |
|---|---|---|
| **Tolerance** (cena za braní) | **barva / saturace** | zvuk, kameru, hudbu |
| **Novelty** (překvapení) | **zvuk zabití** | barvu, kameru |
| **Burnout** (cena za protečení) | **kamera** — třes, rozostření | barvu, zvuk |
| **Craving** (chtění) | **tempo UI** — pulzace, Quick Hit glow | všechno ostatní |
| **Satisfaction** (líbení) | **hudba** — vrstvy nastupují a mizí | všechno ostatní |

Pět systémů, pět kanálů, **nula nových prvků na HUDu**.

Hráč se za dva levely naučí jazyk:

- *šedne to* → beru moc levného
- *zvuk umřel* → tohle už mě nepřekvapuje
- *třese se to* → protéká mi to
- *hudba zmizela* → vyhrávám, ale nebaví mě to

To je **směrodatnost v nejdoslovnějším smyslu: 1:1 mapování mezi příčinou a
pocitem.** Hráč nikdy nemusí hádat.

> **Hudba jako kanál pro Satisfaction je nejsilnější a je úplně volný.** Nic tak
> neřekne "vyhráváš a je ti to jedno" jako ticho pod vítěznou vlnou.

### Změřeno: jak se Tolerance kreslí (20. 8. 2026)

Harness [`_shot_flat.gd`](../../scripts/_shot_flat.gd) vyfotí iso pole při Toleranci
0 / 50 / 95 a změří jas a kontrast. Tři varianty téhož kanálu:

| Varianta | Kontrast 0→95 | Jas 0→95 | Verdikt |
|---|---|---|---|
| šedý `ColorRect` | −9,5 % | **+20 %** | ✗ míchání do šedi tmavou scénu **zesvětluje** — čte se jako mlha |
| energie `Light2D` | **−3,1 %** | −2,0 % | ✗ nic. Lampy jsou aditivní záře nad plně nasvíceným artem |
| `shaders/flatten.gdshader` | **−25,2 %** | +2,4 % | ✓ |

**Proč světla neuspěla.** `game.gd` to má u `SHADOW_LIGHT_ENERGY` napsané: *"nothing in
this project uses CanvasModulate, so the base art already renders at full authored
brightness with zero lights present."* Lampy nic neosvětlují, jen přidávají teplou
kaluž. **Není z čeho scénu zhasínat.** Zhasnutí *všech* světel hne obrazem o 3 %.

Nápad „zhasnout světla = vzít hloubku" je pro isometrii pořád ten správný, ale potřebuje
nejdřív **CanvasModulate základní tmu pod celým polem** — což je reálné renderovací
rozhodnutí s dopadem na všechen autorovaný art, ne přílepek. Háček `depth_channel`
v `game.gd` je pro to připravený a je **vypnutý**, dokud to nepřijde.

**Co dělá shader:** nesčítá šeď, ale (1) stáhne saturaci k luminanci a (2) **sesype
rozsah k vlastnímu střednímu tónu scény**. Tím se stěna a podlaha vedle ní přestanou
oddělovat. To je ta věta — *„všechno vypadalo stejně, nic nevystupovalo"* — a ne
*„všechno bylo vybledlé"*.

**A vedlejší nález:** `_update_glitch` už Toleranci řídil celoobrazovkový glitch shader.
Tolerance tím ovládala **tři vizuální slovesa naráz** a obraz při 95 četl jako
*rozbitý*, ne *plochý*. Glitch přešel na **Burnout**, kam patří — Burnout už vlastní
kameru (třes) a *třes + glitch* je jedna věta („obraz je nestabilní"), zatímco
*vyblednutí + zplacatění* je druhá.

---

<a name="4-tři-vrstvy"></a>
## 4. Tři vrstvy informace

| Vrstva | Co tam patří | Test |
|---|---|---|
| **Číslo na HUDu** | Focus, Dopamine | *Můžu na to reagovat do 3 s?* Když ne, dolů. |
| **Metr** | Tolerance. **Jeden.** | *Řídím to aktivně?* |
| **Smysly** | Novelty, Craving, Satisfaction, Burnout | žádné UI |
| **Po levelu** | veškerý tracking, cue, křivky | žádné UI během hry |

**Progresivní odhalování.** Burnout, Bandwidth, Rush, Insight mají být **skryté,
dokud nezačnou být relevantní**. Burnout se objeví teprve když překročí 40. Do té
doby ho hráč jen *cítí* v kameře.

**Split Craving/Satisfaction nepřidává prvek.** Kreslí se **dovnitř existujícího
Tolerance baru**:

- Level 1–4: jedna čára, jak ji hráč zná.
- Level 5: v tom samém rámečku se vynoří **druhá čára, která tam byla celou dobu**.

Odhalení je, že to byly vždycky dvě. HUD nevyrostl ani o pixel a je to nejsilnější
obrázek v celé hře.

---

<a name="5-mechaniky"></a>
## 5. Mechaniky — detailně

Každá položka má stejnou strukturu: **Věda → Mechanika → Co hráč cítí → Kanál →
Cena → Insight.**

---

### 5.1 Novelty tax — juice škáluje na překvapení

**Věda.** Reward prediction error. Plně předvídaná odměna nevyvolá dopaminovou
odezvu. Novost ji obnoví. Tohle je motor za "přepínáním appek".

**Mechanika.** Vedle Tolerance zavést druhou proměnnou: **predikci**. Každý typ
věže / typ zabití si drží, jak často se to už stalo. Juice škáluje na
`surprise`, ne jen na `1 - tolerance`.

- Dvacáté zabití stejnou věží zní tlumeně.
- **První** zabití **novou** věží zní jako v levelu 1 — plný ding, na ten jeden moment.

**A teď to podstatné:** **upgrade musí být strategicky lepší než šířka.**
Tall > wide, matematicky, jasně.

**Co hráč cítí.** Bude stavět **nové** věže místo aby upgradoval tu, co funguje.
Tím vznikne konflikt, který je celá teze hry, jako **hratelné rozhodnutí**:

> **Co ti dělá dobře a co ti prospívá jsou dvě různá tlačítka. A ty to při hraní víš.**

Žádná insight karta to neřekne líp než ruka, která sáhne po nové věži, protože ta
stará "už nic nedělá" — i když dělá nejvíc DPS na mapě.

**Kanál.** Zvuk zabití. (Barvu si drží Tolerance.)

**Cena.** Nízká. Je to násobitel navíc tam, kde už Tolerance násobí — plus
per-type counter.

**Insight (po levelu):**
> *"That tower worked. It just stopped surprising you. Your brain doesn't
> distinguish 'this isn't working' from 'I've seen this' — which is why you
> downloaded another app when the first one was fine."*

---

### 5.2 Negativní RPE — prázdná bonus vlna

**Věda.** Očekávaná odměna, která nepřijde, sráží dopamin **pod** klidovou
hladinu. Není to neutrální. Je to mínus.

**Mechanika.** **Jednou, maximálně dvakrát za kampaň.** Hra ohlásí
`BONUS WAVE — DOUBLE DOPAMINE`. Hráč to odehraje. Bonus **nepřijde**. Ne "selže" —
prostě tam není.

Na tři sekundy: obraz klesne **pod** normální saturaci. Hudba vypadne. Ticho.
Pak se to vrátí, bez komentáře.

**Co hráč cítí.** Fyzickou plochost. Přesně to, co refresh feedu, kde nic není.
Nebo odeslaná zpráva, na kterou nikdo neodpoví.

**Kanál.** Barva + hudba, obojí **pod** baseline. Jediné místo v celé hře, kde
smějí jít pod nulu.

**Cena.** Velmi nízká — jeden příznak na vlně, jeden tween.

**Riziko.** Musí být vzácné. Dvakrát a je to trik. Třikrát a je to buzerace.

---

### 5.3 Steady Payout — poctivý A/B test na hráči

**Věda.** Variabilní poměr posílení (Skinner). Nepředvídatelná odměna je
kompulzivnější než předvídatelná, i když je **matematicky horší**.

**Mechanika.**

1. Změnit odměnu za zabití na **variabilní** (např. 1–15, průměr 5). Stejná
   matematika jako dnes, úplně jiný pocit.
2. Později v draftu nabídnout kartu:

```
STEADY PAYOUT
Every defeat pays exactly 6 Dopamine.
```

Je **striktně lepší** (+20 %). Většina hráčů ji odmítne, nebo vezme a bude jim
chybět ten pocit.

**Co hráč cítí.** Že jistota je nuda. Bez toho, aby mu to někdo řekl.

**Kanál.** Žádný nový — jen čísla ve floating textu.

**Cena.** Nízká. Jeden `randi_range` v `_on_distraction_defeated`, jedna karta.

**Insight:**
> *"Steady Payout: +20% Dopamine. Declined. Randomness pays worse than certainty.
> You kept the randomness."*

**Poznámka:** tenhle je zajímavý tím, že hra **nic nepředstírá**. Je to reálný
experiment s reálným výsledkem. Přesně o tom stojí kasina.

---

<a name="54"></a>
### 5.4 Craving / Satisfaction split

**Věda.** Berridge — wanting a liking jsou oddělené systémy a **rozcházejí se**.
Tolerance na příjemnost, senzitizace na chtění. Jdou opačným směrem.

**Mechanika.** Rozdělit to, co dnes dělá jedna Tolerance:

| | Roste z | Klesá z |
|---|---|---|
| **Craving** (wanting) | Quick Hit, rychlé klikání, near-miss, reklama | čistě odehrané vlny |
| **Satisfaction** (liking) | dokončený návyk, čistá vlna, plán který vyšel | Quick Hit, protečení |

**Craving MUSÍ být užitečný.** Vysoký Craving = věže střílí rychleji, stavíš
rychleji, urgency. Je to reálná výhoda. Jen každé zabití platí míň Satisfaction.

**Co hráč cítí.** Run se postupně stává **mechanicky silnějším a emocionálně
prázdnějším zároveň**. Hráč je nezastavitelný a necítí nic.

A výsledková obrazovka:

```
LEVEL CLEARED
Focus kept:    20/20
Satisfaction:  12%
```

**Vítězství, které nechutná. To je teze hry ve výsledkové tabulce.**

**Kanál.** Craving = tempo UI (pulzace). Satisfaction = **hudba** (vrstvy).

**Prezentace.** Viz [kapitola 4](#4-tři-vrstvy) — **žádný nový prvek na HUDu**,
druhá čára se vynoří uvnitř existujícího Tolerance baru v levelu 5.

**Cena.** Střední — dotýká se ekonomiky. Ale ta obrazovka se dvěma rozcházejícími
se čárami je obrázek, který si člověk pamatuje roky.

---

### 5.5 Tři TD slovesa, která už existují a jsou zadarmo

**Nejvyšší poměr dopadu k práci v celém dokumentu.** Nevyžaduje novou mechaniku —
jen měřit to, co v TD **už je**.

#### a) Tlačítko zrychlení = netrpělivost

Každá TD má 2×. Zrychlení = víc vln za minutu = víc dopaminu za minutu, výměnou
za horší rozhodnutí. **Nic víc není potřeba.** Jen to sledovat.

> *"Level 1: 12% of the time at 2x. Level 4: 78%. Nothing got harder. You got
> less patient."*

Reálná paralela: videa na 1,5×, přeskakování intr, swipe dál. **Komprese času je
symptom** — a v TD už na to je tlačítko.

#### b) Přípravná fáze = nesnesitelnost nudy

TD má přirozený downtime. Použít ho.

| Craving | Jak downtime vypadá |
|---|---|
| nízký | **odpočinek** — hudba, klid, hezký obraz |
| vysoký | **nesnesitelný** — obraz zplacatí, tenký vysoký tón, Quick Hit pulzuje |

Hráč začne přípravu odklikávat, jen aby ten pocit skončil.

> *"Average time in the prep phase: level 1 = 22s. Level 4 = 3s. You stopped
> planning. You just wanted the next wave."*

**Neschopnost snést nudu je nejlepší jednotlivý prediktor kompulzivního
scrollování** a nikdo z toho neudělal mechaniku. Místo pro ni už v TD je.

#### c) Delay discounting jako opakovaná volba

Každou vlnu nabídnout:

```
Take 20 Dopamine now    —or—    60 at the end of the wave.
```

**Odložená varianta je vždycky lepší**, takže racionální hráč vždycky čeká.
Sledovat, jak se křivka láme s rostoucím Cravingem.

Po kampani ukázat **hráčovu vlastní diskontní křivku**, level 1 vs. level 5, dva
grafy vedle sebe. Bez komentáře:

> *"Your patience, measured."*

**Cena všech tří: skoro nula.** Dvě z nich jsou čistě telemetrie
([kapitola 7](#7-telemetrie)), třetí je jedno tlačítko.

---

<a name="56"></a>
### 5.6 Cue — podmiňování přes tři levely

**Věda.** Pavlov + Schultz: dopaminová odezva se časem **přesune dozadu**, z
odměny na **signál, který ji předpovídá**. Proto tě nechytá obsah — chytá tě
**ikona**. Vibrace v kapse. Modrá tečka.

**Mechanika — oblouk přes tři levely:**

| Fáze | Level | Co se děje |
|---|---|---|
| **Trénink** | 1–2 | Každá velká odměna má **konzistentní předehru**: specifický zvuk + malý modrý záblesk v rohu. **Vždycky.** Hráč se podmíní a neví o tom. |
| **Vyprázdnění** | 3–4 | Záblesk se objevuje **bez odměny**. Cca 11×. |
| **Odhalení** | po levelu | Účtenka. |

**Jak to změřit bez eye-trackingu:**

- pohyb myši směrem k rohu po záblesku
- **pauza v akci** — když hráči po záblesku klesne APM na ~400 ms, chytil se

Obojí je poctivě měřitelné z telemetrie.

**Insight:**
> *"That blue flash meant a reward in levels 1–3. In level 4 it meant nothing —
> 11 times. You reacted 9 times. Your eyes learned the cue, not the reward.
> That's what an app icon is."*

**KRITICKÉ — načasování.** Podmiňování **se nedá udělat zpětně**. Ten modrý
záblesk musí být v levelu 1 **od začátku**. Je to nejlevnější věc na celém
seznamu (jedna částice) a jediná, která **musí být hotová brzo, jinak se ztratí**.

#### Oprava fake notifikace

Fake notification badge nesmí být **vždycky** falešný. Ať je asi ve **30 %**
skutečný. Variabilní poměr.

Pokud je vždycky falešný, hráč se to za jeden level odnaučí — **a tím se lekce
rozpadne.** Pointa je, že se to odnaučit **nejde**.

> *"If it were always fake, you'd stop reacting. That's why it's never always
> fake. That is the entire design of notifications."*

#### Cue přežije zotavení

I když je Tolerance zpátky na nule, když se objeví ten starý modrý záblesk,
**Craving na okamžik vyskočí**. Napořád, do konce kampaně.

> *"Receptors recover. The cue memory doesn't."*

Je to pravda, je to brutální a v kódu je to pět řádků.

---

### 5.7 Algoritmus

**Věda.** Personalizace a adaptivní servírování obsahu. Systém tě neposuzuje —
jen zjišťuje, co u tebe funguje, a dává toho víc.

**Mechanika A — adaptace (jádro).**

- Mačkáš Quick Hit → častěji se nabízejí karty s `tolerance_cost`
- Stavíš jednu věž víc než ostatní → distrakce `comparison` se klonuje podle ní
- Ignoruješ pravou stranu mapy → tam se hromadí Brain Fog a spawnují extra nepřátelé
- Klikáš rychle bez rozmyslu → na pár sekund ztlumená efektivita věží
  ("mindless clicking doesn't help")

**Musí být jemné.** Hráč nesmí mít během hraní pocit, že hra cheatuje. Odhaluje se
**až po levelu, s účtenkou.** Pak se pocit zpětně změní z "nefér" na "chytré".

**Mechanika B — profil v jazyce ad-targetingu** *(pozdě v kampani)*:

```
SEGMENT          Completionist / loss-averse
PREDICTED        responds to streak threats > streak rewards
DELIVERED        14 near-miss events, 3 streak-loss warnings
ENGAGEMENT LIFT  +34%
```

Je to mrazivé a **je to pravda** — hra to fakt udělala. Nic si nevymýšlí.

**Mechanika C — boss, který kopíruje tvou nejlepší věž.**

Pokud ses opíral o Focus Timer, boss spawnuje **Productivity Porn** — distrakci ve
tvaru tvé vlastní věže. Tvoje obrana je útočná plocha.

Tematicky: **tvůj způsob, jak se bránit, se stane tou závislostí.** Čtení o
soustředění místo soustředění. Optimalizování systému místo práce. Je to extrémně
reálné a nikdo z toho neudělal bosse.

**Mechanika D — personalizační dialog** *(kandidát na škrt, viz [12](#12-co-škrtnout))*:

```
Enable personalization?
Levels will be tuned to how you play.
        [ Yes ]        [ No ]
```

**Ano** = hra je znatelně **lepší** — líp odsýpá, líp sedí tempo, víc karet, které
chceš. Není to lež. A Craving roste rychleji.
**Ne** = plošší, kostrbatější, ale stabilní.

Skoro každý řekne ano. **A o to jde.** Neudělal jsi chybu — udělal jsi směnu, ta
směna byla reálná a udělal bys ji znovu. To je attention economy v jednom dialogu,
a nikdo tě přitom neobvinil. O dva levely dál to jde vypnout a hra se **fakt**
zhorší — to je odvykání od personalizovaného feedu.

**Cena.** A–C nízká až střední. **D vysoká** (potřebuje za sebou reálnou
adaptivní obtížnost, jinak je to lež).

---

### 5.8 Zotavení — část, kterou všichni vynechají

Každá hra o závislosti miluje sestup. Skoro žádná neudělá poctivě návrat. Fakta
jsou přitom dramatická sama o sobě:

- **Zpočátku je to horší, ne lepší.** Anhedonie je nejsilnější v prvních dnech.
- **Relapsuje tě prostředí, ne slabá vůle.** Cue, ne charakter.
- **Není to lineární** a relaps je **normální událost**, ne selhání.

#### Level půstu

Jeden level, kde **Quick Hit není** a Tolerance klesá. `lean_waves` už tuhle
kostru máte ([level_data.gd:74](../../scripts/resources/level_data.gd#L74)).

Ten level je **záměrně první dvě třetiny nejméně zábavný v celé hře.** Barvy mdlé,
zvuky ploché, všechno stojí úsilí.

A pak, kolem osmé vlny, se barvy začnou vracet. **Ne najednou — postupně.** A
první čistý *ding* po šesti minutách hladu je **nejuspokojivější zvuk v celé
hře**, protože hráč byl o něj šest minut připraven.

> **Tohle nejde naučit textem. Jde to jen udělat** — nechat člověka projít tou
> plochou a pak doručit.

**Insight:**
> *"That took six minutes. In a brain it takes about two weeks. The shape is the same."*

#### Relaps není fail state

Když hráč během půstu sáhne po Quick Hitu, metr se **nevynuluje**. Jen povyskočí
a pokračuje. Copy je neutrální:

```
Tolerance +18. Continuing.
```

**Žádný stud.** Protože stud je to, co spirálu ve skutečnosti roztáčí — a hra,
která hráče zahanbí, reprodukuje přesně ten mechanismus, před kterým varuje.

**Riziko.** Level půstu může lidi vyhnat. Musí být **krátký**, výplata musí přijít
**okamžitě** a musí být **zpětně pojmenovaná** jako záměr.

---

### 5.9 Distrakce jako taxonomie útoků na pozornost

Každý nepřítel má mít mechaniku, která **je** tou psychologií:

| Distrakce | Mechanika = lekce | Stav |
|---|---|---|
| **FOMO** | Rychlá, viditelná pár sekund. **Když ji ignoruješ, neudělá nulové poškození.** Ale ty ji neignoruješ. Její škoda je tvoje pozornost, ne Focus. | ✅ archetyp `fleeting` |
| **Just One More** | Umře a spawne o něco menší kopii. Šestkrát. Každá vypadá jako poslední. | ✅ archetyp `splitter` |
| **Autoplay** | Když ji nezabiješ do N sekund, **další vlna začne sama**. Ukradne ti přípravnou fázi. | ✅ archetyp `autoplay` |
| **Comparison** | Kopíruje staty tvé nejsilnější věže. | ✅ archetyp `adaptive` |
| **Notification** | Spawne návnadu na HUDu (viz [5.6](#56)). | ✅ `cue_phase` |
| **Doomscroll** | 200 slabých nepřátel v řadě. Každý umře na jednu ránu. Vlna nikdy neskončí — jen **přestane stát za dívání**. | ⬜ nepotřebuje kód, jen `WaveCurveEntryData` (`base_count` vysoký, `spacing` malý). Stávající `doomscroll.tres` je vybalancovaný do levelů 1–2 a nepředěláváme ho. |
| **Multitasking, Nostalgia** *(nice-to-have)* | — | ❌ škrtnuto, [kapitola 12](#12-co-škrtnout) |

#### Jak jsou archetypy postavené

Stejný vzor jako `overdrive` / `energiser` / `disruptor`: **pole na `DistractionData`,
vypnuté nulou.** Žádná dědičnost, žádný `match` na id. Existující distrakce se tím
nehnuly (hlídá to `_test_taxonomy.gd`), a nová se autoruje `.tres` souborem.

| Archetyp | Pole | Kde žije |
|---|---|---|
| `fleeting` | `lifetime_seconds` | `Distraction._expire()` |
| `splitter` | `split_count`, `split_generations`, `split_scale` | `Distraction._split()` → `Game.spawn_split()` |
| `autoplay` | `autoplay_seconds`, `autoplay_grace` | `Distraction._arm_autoplay()` → `Game.arm_autoplay()` |
| `adaptive` | `adapts_to_player`, `adapt_ratio` | `Distraction._adapt_to_player()` → `Game.player_damage_profile()` |

**Čtyři pravidla, která z toho dělají lekci místo obtížnosti:**

1. **Odpočty běží jen ve WAVE čase.** Limitovaná nabídka, která vyprší, zatímco hráč
   přemýšlí v build fázi, neučí nic — a ukradená příprava, která nikdy nezačala, je
   trest, ne hrozba. Stejné gatování jako `disruptor` a `energiser`.
2. **Každý odpočet je vidět.** Oba deadline archetypy kreslí ubývající prstenec po zemi
   (`PixelDraw.arc` je 2:1, takže v isometrii leží na podlaze). Comparison kreslí
   **plný** prstenec v barvě kanálu, protože to není odpočet — je to fakt, který platil
   už při příchodu.
3. **Splitter stojí ČAS, ne obtížnost.** Zdraví klesá `split_scale^generation`, takže
   ocas řetězu se čistí triviálně. A děti pokračují **odtamtud, kde rodič padl** —
   restart u vchodu by z attrition mechaniky udělal odměnu za zabití rodiče.
4. **Comparison tvrdne jen v JEDNOM kanálu** a měří se podle **nejlepšího jednoho
   návyku**, ne podle součtu desky. Kdyby se sčítalo, stavět víc by nepřítele posilovalo —
   a to je jediná věc, kterou tower defence nesmí udělat. Odpověď proto nikdy není „ještě
   jedna stejná věž", ale **druhý kanál**.

**Co to zapisuje do účtenky** ([kapitola 7](#7-účtenka)): `bait_kills` je nejostřejší
číslo na celé obrazovce, protože škoda, kterou by ty nabídky udělaly, není odhad — je
**nula z definice**. Hra to nemusí tvrdit, jen vytiskne obě čísla.

**Testy:** `scripts/_test_taxonomy.gd`, 47 kontrol (`scenes/_test_taxonomy.tscn`).

---

### 5.10 Finále: The Feed

**Boss: The Feed.** Nekonečná dráha. **Nejde vyčistit.** Nezabiješ ho.

Vítězná podmínka není zabít. Je **postavit dost, abys od toho mohl odejít**:
dostat systém do stavu, kdy **30 sekund drží linii bez tvého vstupu**.

Hra tě doslova požádá, abys pustil myš a díval se:

```
Take your hands off the mouse.
Your habits will hold.

00:30
```

**A tohle řeší celou tenzi mezi "sranda/relax" a "message".**

Co dělá TD relaxní? **Dívat se, jak to, co jsi postavil, funguje samo.**
Compounding. Systém, který tě nepotřebuje.

A to je zároveň **teze téhle hry**.

> **Nejrelaxnější stav, jaký ta hra umí vyrobit, je zároveň její nejsilnější
> lekce.** Nejsou to dva cíle, které se perou. Je to jeden cíl.

Odměna za dobrou hru není, že se vyhneš trestu. Odměna je, že **hra ztichne a ty
se můžeš dívat.**

A message: **cílem není bojovat s feedem víc. Cílem je postavit život, který na to
tebe nepotřebuje.**

---

### 5.11 Klesající zdi — co Tolerance stojí (SPIKE)

**Rozdělení.** Shader je, **jak Tolerance vypadá**. Klesající zdi jsou, **co Tolerance
stojí**. Smysl vs. důsledek — stejný předěl, jaký dokument dělá mezi juice a ekonomikou.
Nekolidují, protože to nejsou dva senzorické kanály.

**Věda/téma.** `00_overview.md` mapuje bludiště na *„Structure & boundaries"*. Poctivý
důsledek utrácení levného dopaminu tedy je, že **eroduje struktura** a distrakce se
dostanou k samotným návykům.

**Mechanika.** Nad prahem Tolerance přestane nejvzdálenější **zastavěný** blok být zdí:
distrakce jím projdou a návyk na něm může být přerušen. Pod prahem se zeď **vrátí**.

**Proč je to záměrně malé.** Plynulá eroze podle čísla Tolerance je smyčka smrti —
rozpadlé bludiště → víc průsaků → víc Burnoutu → hůř. Přesně ten jednosměrný sestup,
který [kapitola 2](#2-rámování) odmítá. Tři pojistky:

1. **Jeden blok**, ne všechny. Bludiště se třepí na okraji.
2. **Práh s hysterezí** (60 / 45), ne gradient. Čára je viditelná, vyhnutelná, a pod ní
   zeď **vyroste zpátky** — zotavení, na které se dá dívat.
3. **Odkrytý návyk se `disrupt()`, nikdy nezničí.** „Když ti eroduje struktura, návyky
   se nezničí — **přeruší se**." Pravdivější, a nedá se z toho udělat spirála.

**Iso-nativní.** Výška **je** ta projekce, takže blok klesající na úroveň cesty je v
isometrii čitelný a v top-downu neviditelný. **První mechanika, kterou plochá verze mít
nemůže** — a tím i argument pro iso slice.

**Stav spiku** (`scripts/_test_sink.gd`, 17 kontrol):

| Otázka | Odpověď |
|---|---|
| Zvládne to A*? | ✅ cesta existuje před, během i po; živé distrakce se přepočítají; žádný krok nevede zdí |
| Vrátí se stav? | ✅ délka cesty se vrací na původní, 9/9 buněk zase blokuje |
| Přeruší, nezničí? | ✅ návyk přežije, `disrupted_left = 1.6s` |

**Co spike odhalil a co ještě chybí:**

- ⚠️ **Blok mizí, neklesá.** Animace snížení je další krok, ne tenhle.
- ⚠️ **Původní pravidlo výběru („nejdál od jádra") bylo špatné** — vybralo izolovaný blok
  uprostřed volné podlahy, takže se délka cesty nezměnila (25 → 25). Opraveno na
  **nejvzdálenější zastavěný blok**, protože smyslem je odkrýt návyk, ne zkrátit cestu.
- ⚠️ Distrakce stojící na buňkách při návratu zdi se jen přepočítá ven.
- Vypnuté všude (`LevelData.sinking_walls = false`).

---

<a name="6-reklamy"></a>
### 5.12 Cue přežije zotavení — proč relaps není selhání charakteru

**Věda.** *Cue-induced reinstatement.* Po vyhasnutí podmíněné reakce stačí jediné
znovuspárování a reakce se vrátí skoro na původní sílu — mnohem rychleji, než se
budovala. Asociace se nemaže, jen se překrývá.

**Mechanika.** `GameState.conditioning` (0..1) roste s každým poctivým spárováním
a řídí, jak moc záblesk **táhne** — je větší, drží déle, je hlasitější. Tři pravidla,
a každé je záměrné odmítnutí něčeho pohodlnějšího:

| Pravidlo | Proč |
|---|---|
| **Není v `reset_for_level()`** | dohrát level neznamená odnaučit se to. Jediný kus run-state, který schválně přežije hranici levelu |
| **Tolerance na to nesahá** | hráč může Toleranci srazit na nulu, barvy se vrátí, je viditelně „vyléčený" — a záblesk táhne úplně stejně. Ta mezera **je** ta lekce |
| **Vyhasínání pomalé, reinstatement okamžitý** | 17 prázdných záblesků ubourá to, co 6 poctivých postavilo. Jedno skutečné vyplacení vrátí 90 % starého vrcholu **jedním krokem**. Symetrická čísla by učila opak toho, co platí |

**Nemá žádný vliv na boj**, a to je správně. Jeho zuby jsou v tom, že se hráč podívá —
a dívání ho stojí vlnu, kterou zrovna sledoval. To Mirror počítá.

**Na účtence.** Řádek „What the flash means" stojí ve stejném sloupci jako „Time in the
build phase: 22s → 3s". Nikdo nemusí kreslit čáru mezi nimi.

**Testy:** `_test_attention.gd`, sekce *cue conditioning*.

---

### 5.13 Effort discounting — bariéra z kolečka myši

**Věda.** Salamone: dopamin není chemie slasti, je to chemie **ochoty**. Krysy
s vyčerpaným dopaminem v nucleus accumbens přestanou přelézat překážku pro oblíbené
jídlo a vezmou si volně dostupné granule — a jejich chuť na to oblíbené jídlo je
**úplně nezměněná**. Nepřestaly ho chtít. Přestaly být ochotné lézt.

Tohle je věc, kterou skoro každý článek o dopaminu na internetu plete, a hra ji umí
neříct, ale **předvést**.

**Bariéra.** Mířením se v téhle hře platí: vejít do aim módu, přečíst koridor, doladit
kužel kolečkem. Nad `EFFORT_STRAIN = 45` Tolerance se krok kolečka zmenšuje z 10° na 4°,
takže stejné doladění stojí **2,5× tolik kliknutí** — přesně ve chvíli, kdy na to má
hráč nejmíň trpělivosti.

> Nic se nestalo těžším na **vyhrání**. Stalo se otravnějším na **dělání**. To je jiná
> osa a je to ta správná.

**A pak hra nabídne granule.** `A` a návyky se míří samy.

**Cena té snadné volby není vymyšlená.** Auto-aim vrátí kužel na **domácí úhel habitu**,
kde jsou z konstrukce všechny násobiče `ArcProfile` přesně 1.0. Hráč ztrácí *výhradně*
to doladění, které sám dělal:

- kdo s kolečkem nikdy nehnul, odevzdá **přesně 1.000** — a účtenka o mířeni mlčí,
  protože vymýšlet nález je totéž co lhát
- kdo měl úzký kužel na koridor, odevzdá celý rozdíl (v testu 2.16× → 1.0)

**Vzít si míření zpátky vrátí i původní nastavení.** Cena je za odehrané vlny, ne trvalá
daň — trvalá daň by naučila jen to, že se to tlačítko nemá mačkat, a lekce, kterou nikdo
nezmáčkne, není lekce.

**Kanál:** *pocit z ovládání*. Byl volný — barva patří Toleranci, zvuk Novelty, kamera
Burnoutu, tempo UI Cravingu, hudba Satisfaction, světlo Routine.

**Na účtence.** Headline: *„28 % — extra damage your own aiming was worth. You handed it
back when it got tedious."* Hráč se díval, jak dobrovolně mění poškození za míň kliknutí,
s čísly na očích celou dobu.

**Testy:** `scripts/_test_effort.gd`, 27 kontrol (`scenes/_test_effort.tscn`).

---

### 5.14 Série — přepnutí ze zisku na ztrátu

**Věda/design.** Prospect theory (Kahneman & Tversky, 1979): ztráta váží zhruba dvakrát
tolik co stejně velký zisk. Série toho využívá tím, že **změní rámec** — po dvou třech
vlnách už nevyděláváš bonus, ale **chráníš** ho.

**Mechanika.** Vlny za sebou bez jediného průsaku, `+0.15` k výplatě za každou, strop
`x1.60`. Jeden průsak → nula.

**Bonus je skutečný a má být příjemný.** Není to past a nezadržuje se žádná správná
odpověď — hrát opatrně kvůli sérii je opravdu správná hra. Kdyby to bylo tajně špatně,
lekce by zněla „hra mi lhala", což neučí nic o ničem mimo hru. Co dělá, je tohle:

- nutí hrát **bezpečně** — přestavět, přestat experimentovat, vzít nudnou linii
- nutí hrát **ještě jednu vlnu**

Ani jedno není trest, který hra uvalí. Obojí si hráč udělá sám, kvůli číslu, které měl
celou dobu na očích.

**Láme se v OKAMŽIKU průsaku**, ne v souhrnu po vlně. Ztráta musí být *moment* — série,
která se tiše nezvýšila v mezivlnovém přehledu, je účetnictví, a účetnictví nebolí.

**Strop je záměrně nízko** (dosáhne se na vlně 4). Nad ním **číslo dál roste, ale výplata
ne** — takže se od čtvrté vlny chrání už jenom číslo. To je ten rámec vypreparovaný do
čisté podoby.

**Kanál:** *číslo ekonomiky*. Zlom dostane plovoucí text u jádra, **ne zvuk** — zvuk
patří Novelty a kamera Burnoutu.

**Na účtence.** Headline jen u série ≥ 4, protože pod tím se rámec ještě nestihl vytvořit
a tisknout ho by znamenalo vymyslet hráči pocit, který neměl: *„7 — waves in a row you
had going when it broke. What you lost was a bonus you had not been paid yet."*

**Testy:** `scripts/_test_streak.gd`, 22 kontrol (`scenes/_test_streak.tscn`).

---

## 6. Reklamy

### Proč to není jen gag

Reklamy **zalepují jedinou opravdovou díru v tezi hry** ([1.3](#1-jádro)):

> Hráč se parodické reklamě **směje**, vidí skrz ni, ví přesně, co to je — a
> **stejně na to tlačítko klikne.**

To je nejčistší možný důkaz, že **vědět nestačí**. A hra u toho nemusí říct ani
slovo.

---

### Vrstva 1 — vtip

**Reklamy musí být vizuálně mimo styl.** Jiné rozlišení, ošklivé gradienty, emoji,
hvězdičky, tučný sans. Ten střet je půlka vtipu — a pro art pipeline je to
**úleva**, protože tyhle assety **nemusí projít style bible**. Čím jankovější,
tím autentičtější.

| Reklama | Vtip |
|---|---|
| **DOPAMINE CLICKER** 💎 "NUMBER GO UP" | Jen číslo, které roste, konfety. Vtip je, že to vypadá **fakt lákavě**. ⭐4.8 |
| **BRAIN BLAST** 🧠 "99% CAN'T SOLVE THIS!" | Otázka `2 + 2 = ?`. Falešná ruka zaváhá nad `4`… a klikne na `7`. **WRONG!** Učebnicový rage bait. |
| **PULL THE PIN — SAVE YOUR FOCUS!** | Používá **vaši vlastní ikonu Focusu**. Ruka vytáhne špatný špendlík, Focus se vylije. "OH NO!" Nejlepší z nich, protože si půjčuje ikonografii hry. |
| **SCROLLR** "10,000 hours of video. Never be bored again." | ⭐4.9 (2 300 411). Hrůza je, že to **není nadsázka**. |
| **MONK MODE PRO** "DELETE DOPAMINE FOREVER" | Předplatné $89/rok na appku, co ti maže appky. Tematicky nejostřejší — je to past "optimalizuju si zotavení místo abych se zotavil". |
| **ATTENTION SPAN+** "TRAIN YOUR FOCUS IN 60 SECONDS A DAY!" | A ta reklama je dlouhá 45 sekund. |
| **Reklama na automat** *(pozdě, jednou)* | **Bez parodie.** Úplně obyčejná, realistická reklama na slot machine. Přesně tohle hra celou dobu popisovala a nepotřebuje komentář. |
| **GO OUTSIDE** "It's free. No download." *(pozdě, jednou)* | Obří pohodlný X. Whiplash z reklamy, která po tobě nic nechce, řekne víc než insight karta. |

---

### Vrstva 2 — troll

> **ŽELEZNÉ PRAVIDLO: trollíte formát, ne hráče.**
> Každý troll musí mít pointu, která dopadne **do tří sekund.** Jinak je to jen
> špatné UI.

- **X má 6 pixelů** a je v rohu, kde nebývá.
- **X jednou uhne.** Jednou. Ne pořád — to už je krutost.
- **"Skip in 5… 4… 3… 3… 3…"** a pak se to na trojce zavře samo. Lež nic
  nestála, ale všiml sis jí.
- **X zavře reklamu a pod ní je druhá.** Jednou za kampaň.
- **Falešný X vpravo nahoře, skutečný je šedý "no thanks" 8px dole.** Jednou.

#### Teplý troll — správný register

```
WATCH AD FOR 2x DOPAMINE
```

→ 30sekundové odpočítávání, které počítá **poctivě**.

| čas | text |
|---|---|
| 0:10 | *"you're actually watching this."* |
| 0:03 | *"you waited 30 seconds for pretend currency in a game about not doing that."* |
| 0:00 | **a ty 2× ti to dá.** |

**Hra tě chytí — a pak ti to stejně zaplatí.** Nikdy tě netrestá za to, že ses
chytil. To je tón, který drží celou hru pohromadě: **hra stojí na tvojí straně a
směje se s tebou, ne na tebe.**

---

### Vrstva 3 — háček

#### A) Nabídka je skutečná

Reklama je očividná parodie. Tlačítko říká:

```
TAP FOR 50 FREE DOPAMINE 💎💎💎
```

A když na něj klikneš, **dostaneš 50 Dopaminu**. Doopravdy. A **+15 Tolerance**.

Hráč je v pasti, ze které není rozumné východisko: ví, co to je. Směje se tomu. Je
to *literálně reklama v parodii na reklamy ve hře o manipulaci*. A 50 Dopaminu je
50 Dopaminu.

**Účtenka po levelu, jedna věta, bez komentáře:**

> **You took the ad's offer 3 times. You knew exactly what it was.**

Neobviňuje. Jen konstatuje, že **znalost nebyla ta chybějící součástka.**

#### B) Hra se nezastaví

Reklama vyskočí **během vlny**. Zatímco hledáš X a směješ se, dvě distrakce
projdou. Attention economy v jedné interakci.

**Ale cena musí být směšně malá.** 1–2 Focus, **nikdy ne level**. A hra to hned
pojmenuje:

> *"Ad on screen: 4.2s. Focus lost: 2. Funny though."*

---

### Křivka důvěry

**Jediná věc, kterou když zkazíte, celé to vyhoří.**

| Kdy | Co | Cena |
|---|---|---|
| **Level 1** | **nic.** Nejdřív si zasloužit důvěru. | — |
| Po levelu 1 | první reklama, na **výsledkové obrazovce** | nula, čistá komedie |
| Level 3 | první reklama **během vlny** | 1–2 Focus |
| Level 4 | reklama s **funkční nabídkou** | Dopamine ↔ Tolerance |
| Level 5+ | reklamy se **začnou trefovat** — "STILL BUILDING FOCUS TIMERS? 😴" | — |

**Kdyby první reklama stála Focus, hráč přečte hru jako nepřátelskou a už ji
nepustí.** Nejdřív vtipné, teprve pak s cenou.

> **Jedna reklama na level. Maximum.**

---

### Jak to postavit levně

Zapadá to do toho, co už v projektu je. Je to **jedna scéna + jeden `.tres` na
vtip.**

- `_hud_layer` je `CanvasLayer` ([game.gd:110](../../scripts/game.gd#L110))
- `_hud_root.process_mode = PROCESS_MODE_ALWAYS`
  ([game.gd:4293](../../scripts/game.gd#L4293))

→ overlay, který běží, **zatímco hra neběží na pauze**, umíte už teď. Přesně to
potřebujete.

**Nový `scripts/resources/ad_data.gd`**, stejný vzor jako
[card_data.gd](../../scripts/resources/card_data.gd):

```gdscript
@export var headline: String
@export var subline: String
@export var art: Texture2D
@export var stars: String            # "4.9 (2,300,411)"
@export var cta_text: String

@export var payload_dopamine: int    # co to fakt dá
@export var payload_tolerance: float # co to fakt stojí

@export var x_size_px: int           # 6 = troll, 48 = poctivé
@export var x_delay: float
@export var x_dodges: bool           # uhne jednou
@export var countdown_lies: bool     # 5..4..3..3..3..
@export var hand_path: Array[Vector2]  # dráha falešné ruky
```

**Scéna se napíše jednou:** pozadí, headline, falešná ruka (jeden `Sprite2D` +
tween po `hand_path`), CTA, X, countdown.

A pak je **každý vtip jeden `.tres` soubor.** Deset reklam = deset resources =
**žádný nový kód.** Přesně jako karty a distrakce.

> **Falešná ruka je 90 % komedie za 20 řádků**, protože je to jediná animovaná věc
> v reálných reklamách. Neanimujte "gameplay" — statický obrázek plus tween.
> **Levné = autentické.**

---

### Finále: reklama na tuhle hru

Poslední reklama v kampani. Se všemi triky, které hra právě naučila:

```
        🧠  BRAIN DEFENSE  💎
  100+ LEVELS!  ⭐  FREE DOPAMINE!  ⭐  NO ADS!
         ⭐⭐⭐⭐⭐  4.9 (1,204,882)
```

Hra má sedm levelů, žádný dopamin zadarmo a hráč právě odklikal osm reklam.

A pak, malým písmem, poctivě:

> *That's how we'd have to sell it. Thanks for playing it instead.*

**Je to jediný marketing, který tuhle hru nedělá pokrytcem.**

---

<a name="7-telemetrie"></a>
## 7. Telemetrie: jeden append-only log

Všechen tracking vypadá jako práce na týden. Je to **jeden autoload a ~100
řádků.**

`GameState` už vysílá všechny potřebné signály
([game_state.gd:5–23](../../scripts/game_state.gd#L5)):

```
dopamine_changed   focus_changed      wave_changed
tolerance_changed  burnout_changed    kills_changed
defeat_reward_granted   run_insight_changed   bandwidth_changed
```

**Telemetrie se na ně jen připojí** a zapisuje do jednoho pole. Do existujícího
kódu se skoro nesahá.

```gdscript
# autoload Telemetry
var log: Array[Dictionary] = []   # {t: float, ev: StringName, data: Variant}

func mark(ev: StringName, data = null) -> void:
    log.append({"t": _level_time, "ev": ev, "data": data})
```

Události k zaznamenání:

```
wave_start  wave_cleared  speed_changed  click  build  upgrade
quick_hit   cue_flash     ad_shown       ad_tapped   ad_closed
offer_now   offer_later   leak           kill
```

**A pak je každá statistika jen dotaz nad tím polem:**

| Statistika | Dotaz |
|---|---|
| reakce na cue | první `click` po `cue_flash` |
| délka přípravné fáze | mezera mezi `wave_cleared` a `wave_start` |
| % času na 2× | součet intervalů mezi `speed_changed` |
| diskontní křivka | poměr `offer_now` : `offer_later` v čase |
| doba reklamy na obrazovce | `ad_closed.t - ad_shown.t` |

> **Jednou to napíšete a máte všechny post-level statistiky navždy** — včetně těch,
> které vás ještě nenapadly. **Nejlepší poměr dopad/práce z celého dokumentu.**

**Ochrana soukromí:** všechno zůstává lokálně. A **napište to** — ta věta je
poslední lekce. Viz [kapitola 9](#9-etika).

---

<a name="8-účtenka"></a>
## 8. Účtenka po levelu

Aby to bylo přehledné a **ne otravné**:

1. **Tři čísla. Ne deset.** Zbytek do sbalitelného `detail`.
2. **Každé číslo vždycky jako pár: level 1 → teď.**
   `Prep phase: 3s` neznamená nic.
   `Prep phase: 22s → 3s` je rána do břicha.
   **Hráč je svoje vlastní kontrolní skupina — a to je ta směrodatnost.**
3. **Nikdy během hraní.** Žádný popup uprostřed vlny. To je rozdíl mezi
   **zrcadlem a rejpáním**.
4. **Jedno nejostřejší číslo nahoře, velké.** Zbytek malý.
5. **Navrhnout to jako sdílitelný obrázek** — čitelné v malém, bez brandingu přes
   půl plochy. Co se pak šíří, není referral link, ale **něčí vlastní
   sebepoznání**.

### Příklad

```
                LEVEL 4

  Fake notification → reaction:      0.3s
  Real threat       → reaction:      1.8s

  ─────────────────────────────────────────

  Quick Hits             0  →  0
  Prep phase          22s  →  3s
  Time at 2x speed    12%  →  78%

                                   [ detail ]
```

Žádné "good job". Žádné "you should". **Jen čísla.**

---

<a name="9-etika"></a>
## 9. Etika a pravidla pro texty

### Hra nesmí být pokrytec

Tohle je **konkurenční výhoda**, kterou si žádný jiný produkt v tom prostoru
nemůže dovolit.

- **Na konci sezení žádné tlačítko "další level".** Musíš zpátky do menu.
  Záměrné tření na straně hry. Stojí to retention a je to **nejdůvěryhodnější
  věc, kterou ta hra může udělat** — protože každý jiný produkt dělá opak a hráč
  si toho **všimne**.
- **Jednou, uprostřed dlouhého sezení:** *"You've been playing 47 minutes.
  Continue?"* — kde `Continue` je velké a svítí, `Stop` je malé a šedé. A na
  konci: *"Notice which button was bigger?"* **Jednou.** Kouzelnický trik se
  neopakuje.
- **Žádný žebříček.** A ještě líp: ukázat místo, kde by byl, a napsat
  *"We almost showed you where you rank. We decided not to. Ranking is the
  mechanic this whole game is about."*
- **Všechna data lokálně — a napsat to.** *"None of this left your computer.
  Guess how often that was true today."*

### Pravidla pro copy

| ❌ Nikdy | ✅ Vždycky |
|---|---|
| "You used Quick Hit too many times! Try using it less." | "Quick Hits used: 9. Average reward per hit: 3.2 (started at 15)." |
| "You should pay more attention." | "Fake notification: 0.3s. Real threat: 1.8s." |
| "Good job!" / "You failed" | (nic) |

- **Nikdy slovo "should".** Nikdy "too much". Nikdy známka.
- **Insight karty musí být ověřitelné.** Jména, roky, konkrétní zjištění —
  Schultz, Berridge, Volkow, Solomon & Corbit. Mladý člověk, co si jednu
  vygoogluje a zjistí, že je pravdivá, uvěří všemu ostatnímu. Ten, co najde
  popsciovou kaši, **zahodí celou hru**.
- **NEJDŮLEŽITĚJŠÍ: hra nikdy neřekne hráči, že je závislý.** Ukazuje chování,
  závěr si udělá on. V okamžiku, kdy hra diagnostikuje, **jdou nahoru obrany a
  učení končí.**

### Délka

**5–8 levelů, ~90 minut.** Hra, která tohle učí a přitom si vezme 30 hodin, si
sama odporuje.

---

<a name="10-plán"></a>
## 10. Plán po levelech

**Kampaň JE tutoriál.** Nic není na obrazovce dřív, než se to učí.
**Jeden nový signál na level.**

| Level | Co přibude | Nový kanál | Reklama |
|---|---|---|---|
| **1** | nic. Jen dobrá TD. *(potichu: modrý cue záblesk)* | — | ne |
| **2** | Tolerance + Quick Hit *(hotové)* | **barva** | po levelu, zdarma |
| **3** | Novelty tax + upgrade > šířka | **zvuk** | během vlny, 1–2 Focus |
| **4** | Cue se vyprázdní → první účtenka | **po levelu** | s funkční nabídkou |
| **5** | Craving/Satisfaction split | **hudba** | targetovaná |
| **6** | Půst | vše odteče a vrátí se | ne |
| **7** | The Feed → "pusť myš" | — | finále: reklama na tuhle hru |

> **L1–L3 je odeslatelná, soudržná hra.** Nic pozdějšího není potřeba, aby to
> dávalo smysl.

### Pořadí práce

1. **Cue záblesk v levelu 1** — nejlevnější (jedna částice) a **jediná věc, která
   se nedá dodělat zpětně.** Když se neudělá teď, ztratí se.
2. **Telemetrie** (kapitola 7) — jeden log, odemkne všechny účtenky navždy.
3. **Novelty tax** (5.1) — největší nový mechanický prostor za nejmíň práce.
4. **Reklamy** (kapitola 6) — jedna scéna + `.tres` na vtip, roste samo.
5. **Craving/Satisfaction split** (5.4) — nejvíc práce, nejsilnější obrázek.
6. **Půst** (5.8) a **The Feed** (5.10) — poslední, ale **zapsat si je jako
   severku hned teď**. Když víte, že hra končí "pusť myš", začne to tvarovat
   každý level před ním.

---

<a name="11-rizika"></a>
## 11. Rizika

| # | Riziko | Pojistka |
|---|---|---|
| 1 | **Degradace juice se čte prostě jako "hra se zhoršila".** | Tolerance **musí klesat** a hráč nad tím musí mít páky. Jednosměrný metr = trest. Obousměrný = systém. Viz [kapitola 2](#2-rámování). |
| 2 | **Záměrná frustrace je břitva.** Půst může lidi vyhnat. | Krátký, okamžitá výplata, **zpětně pojmenovaný** jako záměr. |
| 3 | **Každý trik má jedno použití.** | Rozpočtovat jako munici. **Max jeden "moment" na level.** |
| 4 | **Adaptivní obtížnost odhalená během hraní = cheat.** | Odhaluje se **až po** levelu, s účtenkou. Pak se pocit zpětně změní z "nefér" na "chytré". |
| 5 | **Tracking hráče je sám o sobě creepy.** | Lokálně, **napsat to** — a ta věta je poslední lekce. |
| 6 | **Reklama, která doopravdy štve, je jen otravná reklama.** | Křivka důvěry: **nejdřív vtipné, pak s cenou.** Cena max 1–2 Focus. Pointa do 3 s. |
| 7 | **Příliš mnoho metrů = nečitelná hra.** | [Kapitola 3](#3-přehlednost) a [4](#4-tři-vrstvy): jeden systém = jeden smysl, HUD neroste. |

---

<a name="12-co-škrtnout"></a>
## 12. Co škrtnout

Ať to nenaroste:

| Věc | Proč pryč |
|---|---|
| **Personalizační dialog** (5.7 D) | Chce za sebou reálnou adaptivní obtížnost, jinak je to lež. Drahé. **v2.** |
| **Hláška o 47 minutách** | Meta vtip, potřebuje hotovou hru okolo. **v2.** |
| **Multitasking, Nostalgia** (5.9) | Hezké, ale nic nenesou. |
| **Plný ad-targeting profil** (5.7 B) | **v2.** |

### Páteř, která zůstane — sedm věcí

1. **barva ← Tolerance** *(hotové)*
2. **zvuk ← novelty**
3. **jeden telemetrický log + účtenka**
4. **cue od levelu 1**
5. **split uvnitř téhož baru**
6. **půst**
7. **The Feed / pusť myš**

Plus **reklamy** jako průběžná linka přes celou kampaň.

---

<a name="13-stav-kódu"></a>
## 13. Stav implementace

> Aktualizováno po implementaci. Testy: `scenes/_test_attention.tscn` (39 kontrol).

### Hotové — systémy

| Věc | Kde | Pozn. |
|---|---|---|
| **Novelty / RPE** — `surprise_of()`, per-habit familiarita | [game_state.gd](../../scripts/game_state.gd) | `killer_key` se zapisuje v [enemy.gd](../../scripts/enemy.gd) |
| **Rozpojení kanálů** — Tolerance→barva, novelty→zvuk, Burnout→kamera | [game.gd](../../scripts/game.gd) `_on_distraction_defeated`, [sfx.gd](../../scripts/sfx.gd) `play_defeat` | základní shake u zabití je konstantní |
| **Celoobrazovkový wash** (kanál Tolerance) | [game.gd](../../scripts/game.gd) `_setup_attention` | CanvasLayer 6 — **pod HUDem**, takže mapa bledne a Quick Hit ne |
| **Craving / Satisfaction** | [game_state.gd](../../scripts/game_state.gd) | Craving = reálný buff (−25 % cooldown v [tower.gd](../../scripts/tower.gd)) |
| **Hudba jako kanál Satisfaction** | [music.gd](../../scripts/music.gd) | 3 procedurální vrstvy, odcházejí po jedné |
| **Split uvnitř Tolerance baru** | [ui_meter.gd](../../scripts/ui_meter.gd) `split_value` | žádný nový prvek na HUDu |
| **Variabilní odměna + Steady Payout** | [game_state.gd](../../scripts/game_state.gd) `_payout_multiplier` | střední hodnota **přesně 1.0** (ověřeno testem na 40 000 vzorcích) |
| **Cue** — podmiňování, vyprázdnění, měření přitažení | [game.gd](../../scripts/game.gd) `_fire_cue`, `_update_cue` | 30 % cue zůstává pravdivých |
| **Prep-phase span + nesnesitelnost** | [game.gd](../../scripts/game.gd) `_update_downtime` | |
| **Delay discounting** | [game.gd](../../scripts/game.gd) `_show_delay_offer` | odložená varianta je vždy lepší |
| **Prázdná bonus vlna** | [game.gd](../../scripts/game.gd) `_announce_bait_wave` | obraz jde **pod** baseline, hudba na 3 s vypadne |
| **Reklamy** — resource + overlay + 10 vtipů | [ad_data.gd](../../scripts/resources/ad_data.gd), [ad_overlay.gd](../../scripts/ad_overlay.gd), [data/ads/](../../data/ads/) | nabídka je **skutečná**; hra se za nimi nezastaví |
| **Telemetrie** — jeden append-only log | [mirror.gd](../../scripts/mirror.gd) | připojeno na existující signály; `user://mirror.json` |
| **Účtenka** — 3 řádky, vždy v páru, řazené podle změny | [receipt.gd](../../scripts/receipt.gd) | na level 1 se řádky **nezobrazí** (není s čím párovat) |
| **Půst** — Quick Hit pryč, rychlejší decay, start v šedi | [game.gd](../../scripts/game.gd) `_setup_attention`, `_update_tolerance` | relaps bez zahanbení |
| **Hands-off finále** | [game.gd](../../scripts/game.gd) `_update_hands_off` | 30 s bez vstupu = vítězství |
| **Klesající zdi (SPIKE)** | [game.gd](../../scripts/game.gd) `_update_sinking` | vypnuté; test `_test_sink.gd`, viz [5.11](#511-klesající-zdi--co-tolerance-stojí-spike) |
| **Slider hudby + smazání dat** | [settings_panel.gd](../../scripts/settings_panel.gd) | slib o soukromí musí jít vykonat |
| **Taxonomie distrakcí** (4 archetypy) | [distraction_data.gd](../../scripts/resources/distraction_data.gd) · [enemy.gd](../../scripts/enemy.gd) | `fomo` · `just_one_more` · `autoplay` · `comparison`; test `_test_taxonomy.gd`, viz [5.9](#59-distrakce-jako-taxonomie-útoků-na-pozornost) |
| **Cue přežije zotavení** | [game_state.gd](../../scripts/game_state.gd) `condition_cue` | Tolerance ani nový level to nemažou; viz [5.12](#512-cue-přežije-zotavení--proč-relaps-není-selhání-charakteru) |
| **Effort discounting** | [game.gd](../../scripts/game.gd) `aim_step` · [tower.gd](../../scripts/tower.gd) `set_auto_aim` | bariéra + auto-aim (klávesa `A`); test `_test_effort.gd`, viz [5.13](#513-effort-discounting--bariéra-z-kolečka-myši) |
| **Série** | [game_state.gd](../../scripts/game_state.gd) `note_wave_cleared` | HUD chip + plovoucí text; test `_test_streak.gd`, viz [5.14](#514-série--přepnutí-ze-zisku-na-ztrátu) |
| **Přepínače prezentace na levelu** | [level_data.gd](../../scripts/resources/level_data.gd) `fog` · `shadows` · `routine_gates` | nahradily natvrdo psané `if level.id == 99` v game.gd, kvůli kterému běžel level 98 potmě |

### Datové přepínače na levelu

Vše je zapnutelné per-level v [level_data.gd](../../scripts/resources/level_data.gd):

`cue_phase` · `variable_rewards` · `delay_offers` · `split_meter` · `bait_waves` ·
`fasting` · `hands_off_finale` · `ads`

**Aktuální nasazení** (kompromis — kampaň má zatím jen 2 levely):

| Level | Zapnuto |
|---|---|
| **1** | `cue_phase 1` + reklama po levelu (zdarma). Jinak čistá TD. |
| **2** | `cue_phase 2`, `variable_rewards`, `delay_offers`, `split_meter`, `bait_waves [10]`, 3 reklamy ve vlnách 4 / 8 / 14 |
| **98** (iso, „Morning Routine") | `cue_phase 1` + jedna reklama po levelu (`brain_defense`, payload 0). Jinak **čistá TD** — přesně to, co kapitola 10 chce po prvním levelu. 8 stavebních míst, serpentina 18 bloků, notification + doomscroll. |
| **99** (iso slice) | `quick_hit`, **`cue_phase 2`**, `variable_rewards`, `delay_offers`, `split_meter`, `bait_waves [3]`, 2 reklamy — plus všechny 4 archetypy ve `wave_curve` (FOMO w2, Just One More / Comparison w3, Autoplay w4). |

> **Proč to potřebuje dva levely.** `cue_phase 1` nechá záblesk vézt vždycky skutečnou
> odměnu — buduje význam. `cue_phase 2` ho pak pouští naprázdno — ten význam utrácí.
> Přes jeden level se ta lekce zahrát nedá, protože nemá co utratit. Totéž platí pro
> účtenku: `Mirror.baseline_row()` nemá s jediným levelem co vrátit a `Receipt._rows()`
> je pak **navždy prázdná**. Půlka výukové vrstvy byla do levelu 98 nedosažitelná.

> ⚠️ **Level 2 je hustší, než design chce.** [Kapitola 10](#10-plán) rozpočítává jeden
> moment na level. Až budou levely 3–7, přepínače se rozestoupí:
> `cue_phase 2`→L4 · `variable_rewards`/`delay_offers`→L3 · `split_meter`→L5 ·
> `bait_waves`→L4 · reklamy podle křivky důvěry v [kapitole 6](#6-reklamy).

### Zbývá — potřebuje obsah, ne kód

| Věc | Co chybí |
|---|---|
| **Levely 3–7** | mapy. Mechaniky čekají za přepínači výše. |
| **Půstový level** | `fasting = true` + mapa. Systém hotový. |
| **The Feed** | `hands_off_finale = true` + boss `infinite_feed` + mapa. Systém hotový. |
| **Insight karty pro budoucí levely** | existují `level_1`, `level_2`, `level_98` (The Cue / Schultz 1997), `level_99` (Wanting Is Not Liking / Berridge 1998). Všechny čtyři mají `citation`. |
| **Reklamy 4–10** | resources hotové, čekají na levely (`monk_mode`, `scrollr`, `reward_video`, `jackpot_real`, `brain_defense`) |
| **Algoritmus** (5.7) | neimplementováno — [kapitola 12](#12-co-škrtnout) ho odkládá. Adaptivní archetyp z [5.9](#59) je jeho zárodek: čte desku, ne historii. |
| **Doomscroll jako roj** (5.9) | jen autorská práce ve `wave_curve` — potřebuje level, ne kód |

### Známé předexistující chyby (nesouvisí s tímto)

Ověřeno spuštěním na čistém `HEAD` — chovají se identicky:

- `level_1.tres` má `objective = Vector2i(109, 34)` proti mřížce **24×24** →
  `Can't get id path` při startu. Pozůstatek migrace mřížky (viz `.bak_grid48` soubory).
- `_test_phase4` (cone math), `_test_los`, `_test_suppression`,
  `_test_fog_bandwidth`, `_test_shadow_occlusion` — padají i bez těchto změn.
