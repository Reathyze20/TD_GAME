# Průvodce editorem map (MapEditor)

Průvodce je česky, protože je pro tebe — obsah hry zůstává anglicky.
Otevři scénu `scenes/MapEditor.tscn`, klikni na kořenový uzel **MapEditor** a všechno
ovládáš z Inspectoru vpravo. Vše, co vidíš na plátně, se překreslí samo ~1 s po každé
úpravě (přepínač `Live Analyze`).

---

## 1. Co je co na plátně

| Prvek | Význam |
|---|---|
| **Šedé dlaždice** | High ground — zdi. Blokují cestu nepřátel **a zároveň** jsou to jediná místa, kam jde stavět Habity. Maluješ jimi bludiště i stavební plochy najednou. |
| **Žluté→červené podbarvení** | Heatmapa provozu: kolik tras nepřátel vede přes buňku. Červená = tudy teče celá horda (killzóna — sem míří věže), bledě žlutá = jen pár tras. |
| **Červené čáry se šipkami** | Ukázkové trasy nepřátel (3 na zónu). Tečka = start ve spawn zóně, šipky = směr k jádru. |
| **Červený rámeček** | Spawn zóna. Nepřátelé se rodí na náhodných volných buňkách uvnitř. Přetažením posouváš, za roh měníš velikost — vše se přichytává na mřížku. Štítek říká „Zone 0 — šířka×výška" v buňkách. |
| **Zelený čtverec** | Objective — jádro Focusu, cíl všech nepřátel. Přesouváš přetažením. |
| **Velký zelený kruh** | Core Routine — JEDINÁ oblast, kde jde stavět bez Anchorů. Kolik šedých dlaždic je uvnitř, tolik máš míst na první věže. |
| **Menší tyrkysový kruh** | Dosah Routine jednoho Anchoru — o tolik si hráč rozšíří stavební oblast každým Anchorem (řetězí se od jádra ven). |
| **Modrý obdélník** | Hranice hrací plochy (40×19 buněk). Co je namalované venku, je BLOCKER. |

## 2. Panel metrik (vlevo dole)

Barvy řádků: **zelená = cíl splněn · červená = oprav · šedá = informace.**

| Řádek | Co znamená | Cíl | Jak opravit |
|---|---|---|---|
| `validation` | Součet chyb mapy + nastavení. Každý BLOCKER je vypsaný červeně hned pod tím. | OK | Podle textu chyby (viz §6). |
| `detour factor` | O kolik delší je skutečná cesta oproti vzdušné čáře. 1.00 = nepřátelé jdou rovně, žádné bludiště. | **≥ 1.35** | Přidej zdi, které nutí trasu klikatit (S-oblouky, slepé kapsy). Sleduj, jak se červené čáry ohýbají. |
| `shortest spawn path` | Nejkratší cesta ze spawnu k jádru v buňkách. Krátká = hráč nestihne reagovat. | **≥ 25** | Odsuň zónu dál, nebo prodluž trasu zdmi. |
| `build spots` | Kolik šedých dlaždic (stavebních míst) mapa má celkem. | > 0 | — |
| `spots in core Routine` | Stavební místa uvnitř zeleného kruhu — co si hráč může dovolit před prvním Anchorem. | **12–20** | Přimaluj/ubuď šedé dlaždice poblíž jádra. |
| `reachable by Anchor chain` | Kolik míst je vůbec dosažitelných řetězem Anchorů. Nedosažitelné místo nejde nikdy použít. | 100 % | Doplň „mosty" z dlaždic, aby řetěz dosáhl všude. |
| `Anchor cost to cover` | Kolik Anchorů (a Dopaminu) stojí pokrýt celou mapu. | informace | Hodně = mapa je rozlehlá/drahá. |
| `waves: …` | Souhrn vln: počet, celkové spawny, špička, lean vlny, boss, drafty. | informace | Klikni na **Target Level** v Inspectoru a uprav. |
| `economy: …` | Startovní Dopamin, Focus, Quick Hit. | informace | Tamtéž. |
| `curve: …` | Jeden řádek za každý záznam křivky hordy: kdo, od které vlny, kolik, +růst/vlnu, rozestup. | informace | Tamtéž. |

## 3. Graf obtížnosti (uprostřed dole)

Sloupec = počet nepřátel v té vlně. **Oranžová** = běžná vlna, **modrá** = lean vlna
(zabití neplatí Dopamin), **červený rámeček** = finále s bossem. Tvar, který chceš:
plynulá rampa, občas propad na nádech, výrazná špička na konci.

## 4. Tlačítka (Inspector → Actions)

| Tlačítko | Co dělá | Kdy |
|---|---|---|
| **Load From Level** | Nahraje level ze souboru na plátno. | Vždy jako první krok. |
| **Analyze** | Ruční přepočet (Live Analyze to dělá samo). | Když vypneš živou analýzu. |
| **Bake To Level** | Zapíše geometrii (zdi, zóny, objective, dlaždice) do `.tres`. Nejdřív validace, pak záloha `.bak`, pak zápis. Chyby = odmítne a nic nezapíše. | Když je mapa hotová/za milník. |
| **Playtest** | Bake + spuštění hry rovnou v tomhle levelu. | Kdykoli chceš mapu cítit pod rukama. |
| **Playtest Designer Mode** | Cheaty pro playtest: **F1** +500 ◆, **F2** +10 Insight, **F3** turbo 5×, **F4** smete vlnu. Bez telemetrie. | Zapnuté nech pro tvarování mapy; vypni pro poctivý test obtížnosti. |
| **Save Level Settings** | Uloží JEN nastavení (vlny, ekonomiku, bosse) — geometrie se nedotkne. | Když ladíš čísla v Target Level a nechceš péct mapu. |
| **Create New Level** | Založí `level_N.tres` jako kopii aktuálního levelu s dalším volným id a rovnou ho nastaví jako cíl. Hra ho po restartu vidí sama. | Nový level do kampaně. |
| **Add Spawn Zone** | Přidá další spawn zónu (rámeček vlevo nahoře, přetáhni na místo). | Víc směrů útoku. |

## 5. Jak se vlastně kreslí

1. Ve stromě scény vyber uzel **HighGroundTiles** → dole se otevře panel **TileMap**.
2. Kresli štětcem; obdélník a kbelík jsou v liště panelu TileMap. Vzory (patterns) si
   ulož výběr dlaždic pro opakované motivy (rovinka, roh, komín).
3. Zóny a Objective přesouváš normálním nástrojem výběru ve 2D pohledu — přichytávání
   na mřížku je automatické.
4. Nastavení levelu: klikni v Inspectoru na **Target Level** — rozbalí se **všechna**
   pole (vlny, křivka hordy, lean, boss, ekonomika…). Každé pole má tooltip. Ulož přes
   **Save Level Settings** (nebo Bake, ten ukládá vše).

## 6. Nejčastější BLOCKERy a co s nimi

| Hláška | Příčina | Oprava |
|---|---|---|
| `…cells are outside the grid` | Namalováno mimo modrý rámeček. | Smaž dlaždice venku (guma = pravé tlačítko štětce). |
| `Spawn zone … extends past the grid` | Zóna přečuhuje z plochy (např. „Zone 0 — 1×22" na mřížce 19 řádků). | Zmenši/posuň rámeček dovnitř. |
| `Objective sits on high ground` | Jádro stojí na zdi. | Přesuň zelený čtverec na volnou buňku. |
| `spawn cells have no path` | Zeď úplně odřízla spawn od jádra. | Prokopej průchod — červené čáry se hned objeví. |
| `curve entry has no distraction` | Řádek křivky bez přiřazeného nepřítele. | V Target Level → Wave Curve doplň resource z `data/distractions/`. |
| `wave 1 has no spawns` | Žádný záznam nezačíná na vlně 1. | Dej aspoň jednomu záznamu `from_wave = 1`. |

## 7. Zálohy

Před **každým** zápisem (Bake i Save Level Settings) vznikne `level_X.tres.bak` vedle
souboru. Obnova = zkopíruj `.bak` zpět přes `.tres` (a v editoru dej Load). Editor
odmítne zapisovat, pokud se záloha nepovede — bez verzování je soubor jediná kopie.

## 8. Doporučený postup pro novou mapu

1. **Create New Level** → **Load From Level**.
2. Rozmísti Objective a zóny (daleko od sebe; `shortest spawn path` ať svítí zeleně).
3. Hrubě vyzdi hlavní trasu — sleduj `detour factor`, dokud nesvítí zeleně (≥ 1.35).
4. Dolaď stavební místa u jádra (`spots in core Routine` 12–20) a mosty pro Anchor řetěz.
5. Klikni na Target Level a nastav vlny/ekonomiku — grafem zkontroluj tvar rampy.
6. **Playtest** (s cheaty) → tvaruj; pak vypni Designer Mode a odehraj poctivě.
7. **Bake** za každým milníkem — záloha se postará o zbytek.
