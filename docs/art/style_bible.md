# Stylová bible — TD Project

*Odvozeno měřením 734 shipped PNG, ne od stolu. Přeměř kdykoli:*
`python tools/style_audit.py`

---

## Pravidla

| | |
|---|---|
| **Rozlišení** | 32×32 příšery a obránci · 24×24 hlavy věží · 16×16 dekorace a dlaždice · 64×64 boss |
| **Logický pixel** | ×1 v PNG (žádné zdvojování); zvětšuje až engine |
| **Paleta** | `docs/art/palette_32.hex` — 32 barev, celý projekt |
| **Barev na sprite** | ≤ 24, všechny z master palety |
| **Obrys** | 1px tmavší odstín **téže** barvy, ne černá. Postavy a věže ano, terén ne |
| **Stínování** | 3 tóny. Stín posunutý v odstínu ≥ 20° do chladna. Bez ditheringu |
| **Počty snímků** | chůze 6 · útok 5 · smrt 8 · idle 2 |
| **Časování** | základ 10 FPS. Nárazový snímek držet 3×, nápřah 1× |
| **Proporce** | příšera 26–30 px vysoká ve 32px plátně · obránce 29 px · boss ≤ 1,8× |
| **Pozadí při generování** | magenta `#FF00FF` — v těle nesmí zůstat ani stopa |

---

## Proč zrovna tahle čísla

**32 barev, ne 48.** Odchylka průměrného pixelu od master palety:

```
16 barev → 0.0507 Oklab
32 barev → 0.0369      ← koleno
48 barev → 0.0342      +0.003 za padesát procent barev navíc
```

Nad 32 se už neplatí za věrnost, platí se za rozpad konzistence.

**Obrys jako tmavší odstín, ne černá.** Postavy ho už mají a je silný — medián rozdílu
jasu vnitřek↔okraj je +0,23 (distrakce), +0,18 (obránci). Pravidlo jen zapisuje, co
ruka už dělá. Černá by ten posun odstínu, který je jinde přes celý art, na okraji zabila.

**Hue shift ≥ 20°.** Naměřeno: distrakce 58°, věže 86°, obránci 29°, dekorace 48°.
Práh je nízko schválně — je to podlaha, ne cíl.

**Počty snímků dolů.** Viz níže; je to největší jediná změna v celé bibli.

---

## Kde se art od bible dnes liší

### 1. Věže mají tři rozlišení

```
24×24  55 souborů
32×32  19
40×40  10
```

Nejde o styl, ale o mřížku — tři velikosti hlavy znamenají tři různé vztahy k dlaždici.
**24×24 vyhrává většinou.** Zbytek se převede.

Věže jsou i jediná kategorie s rozkolísaným obrysem: 64 % tmavý, 27 % žádný, **8 % má
světlý lem** — to není styl, to je zbytek po zmenšování.

### 2. Terén je plochý a je to změřitelné

```
distrakce   58,3°  posun odstínu    hue shift u 85 % spritů
obránci     29,2°                            83 %
věže        86,4°                            96 %
terén        4,2°                            10 %   ← ztmavování do černé u 76 %
```

Tohle je **měřená odpověď na „mapa působí plochá"**. Postavy žijí v hue-shiftovaném
světě, terén pod nimi v šedém. Rozdíl není v rozlišení ani v detailu, je v tom, že
terén nemá barevný stín.

### 3. Palety jsou nad rozpočtem a nesdílené

Medián barev na sprite: distrakce 34, obránci 30, věže 21, dekorace 6.
Cíl je 24. Hlavní problém ale není počet — je to, že **žádná společná paleta neexistuje**;
každý tvor si přivezl vlastní.

### 4. Animace: moc snímků, nulové časování

```
útok    16 snímků  ×5 tvorů      (shipped hry: 3–6)
smrt    11 snímků  ×10
chůze    8–9 snímků             (shipped hry: 4–6)
obránci  6 snímků  ×18           ← tady je to správně
```

`data/anim_tuning.tres` **nemá jediné FPS** → všechno běží na výchozích 12 a každý
snímek drží stejně dlouho.

Dvojnásobný počet snímků oproti běžné praxi a k tomu ploché časování je nejhorší možná
kombinace. A u AI artu to bolí dvakrát: **každý snímek navíc je další příležitost, aby
model ujel.** Šestnáctisnímkový útok má šestnáct šancí na drift, pětisnímkový pět.

Zkrácení tedy není ústupek. Je to zároveň bližší tomu, co dělají vydané hry, **a** přímá
oprava toho, proč animace z generátoru působí rozsypaně.

### 5. Drobnost

`assets/distractions/phantom_buzz_spritesheet.png` je 1024×1024 zdrojový list ležící
mezi shipped sprity. Patří do `assets/src/`.

---

## Co bible **není**

Neříká, jak velký je sprite na obrazovce. To je jiná osa (engine kreslí 32px sprite na
~96px) a řeší se v render vrstvě, ne v PNG.

Měření posunu odstínu neumí odlišit **hue-shiftované stínování** od **pestrého spritu**.
Zelený obránce s červenou přilbou vykáže velký posun, i kdyby stínoval do černé. Čísla
výše proto berte jako podlahu, ne jako důkaz techniky.
