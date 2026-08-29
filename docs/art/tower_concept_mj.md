# Midjourney: koncept art pro věže

*Napsáno 21. 8. 2026, po dvou zpackaných kolech přímého generování v PixelLabu.
Prompty pro pixel art jsou v [tower_prompts.md](tower_prompts.md) — tenhle dokument je
krok PŘED nimi.*

## 1. K čemu ten koncept art je

Není to jen na dívání. V tomhle projektu vede z Midjourney rovná cesta do hry:

```
MJ koncept.png
  → python tools/mj_to_sprite.py koncept.png predloha_64.png --chroma --test
  → python tools/pl_tower.py rotobj <klic> predloha_64.png
        (create_8_direction_object, ~8 minut)
  → python tools/pl_iso.py poll obj_<klic> ; pull obj_<klic>
  → python tools/check_turntable.py build/iso_art/obj_<klic>      # brana 1
  → python tools/install_tower_art.py --dirs <klic> [--rotate N]
  → python tools/check_turntable.py sheet <klic>                  # brana 2
```

### Dvě brány, a ani jedna nestačí sama

**Brána 1 — jsou snímky různé?** Rotace se občas nepovede a čtyři z osmi vyjdou skoro
stejné. Měří se to párovou vzdáleností mezi snímky, ne úhlem hlavně: úhel se měřit
nedá, protože mosaz na spritu není jen hlaveň, ale i prstenec, a ten je v každém snímku
jinde. Dvě různá „chytrá" měřidla na tomtéž problému daly 307° a 0°.

**Brána 2 — míří tam, kam slibuje jméno?** Různost je nutná, ne postačující. Štítky
z PixelLabu se k obsahu vážou nespolehlivě — sada 1 měla jména správně, sada 4 byla celá
otočená o 180°, takže její `east` mířil doleva. Posun se předá instalátoru přes
`--rotate N`; jak ho poznat, je v hlavičce `install_tower_art.py`.

A i po správném posunu může sada mít **díru**: jedna měla `south-east` i `south-west`
hlavní nahoru, protože generátor ji v té sadě nikdy neklopil k divákovi. Šest z osmi
byl její strop a žádné přejmenování to nespraví — jde se znovu.

**Ne `create_character`.** Zkoušeno 21. 8. 2026 a změřeno: `mode="v3"` vyrobil osm
hezkých pohledů, ale hlaveň v nich nerotovala — úhly vyšly −9, +3, +1, −33, −104, −137,
−177, +34 stupňů, tři různé „směry" měly hlaveň na témže místě a rozestupy nebyly 45°.
Důvod: v3 bere vstup jako **postavu** a za její obličej vzal ciferník. Hlaveň je pro něj
boční přívěsek, který nechal víceméně stát. `create_8_direction_object` je od **propů**
(vlastní popis: *„works well for props (barrels, chests)"*) a otáčí těleso.

`mj_to_sprite.py` obrázek **vyřízne z pozadí, posadí na 64 px, zkvantuje na 24 barev
a přikreslí 1px tmavý obrys** — přesně to, čím drží tvar brokolicoví rytíři. Pak to
projde branami:

| brána | limit |
|---|---|
| barev | ≤ 32 |
| kontrast obrysu | ≥ 15 |
| souvislých částí | **= 1** |
| tenkých segmentů (< 2 px) | ≤ 2 |
| výška na 32 px | ≥ 26 |

**Z toho plyne pět tvrdých pravidel pro Midjourney.** Nejsou to preference, jsou to
věci, které skript neumí doplnit:

1. **Jeden objekt, nic jiného v obraze.** Brána „souvislých částí = 1" spadne na
   každém uletěném kousku. MJ rád dělá sady a listy s variantami — musí se zakázat.
2. **Ploché jednolité pozadí.** `cutout()` vylévá barvu z rohů; na scéně, přechodu nebo
   textuře nemá kde začít.
3. **Žádný stín na zemi, žádná podlaha, žádný sokl.** Skript to sice umí odstranit
   (`strip_shadow`, `cut_floor`), ale je to oprava, ne funkce — a ukrajuje z objektu.
4. **Žádný rámeček, karta, popisek ani text.** `strip_panel` je zase jen záchrana.
5. **Silueta musí být čitelná v černé.** Po zmenšení na 64 a kvantizaci na 24 barev
   zbyde z jemných detailů kaše. Tvar musí nést informaci sám.
6. **Podstavec ano, ale KRUHOVÝ.** Věž se otáčí za nepřítelem, takže se otáčí i všechno,
   co je nakreslené v jejím spritu. Cokoli, co má *předek* — nožky, schůdek, cedulka,
   čtvercová deska — se tím otáčením zradí: osm pohledů na tytéž nožky je osm různých
   chodidel na témže místě a oko to čte jako poskakování, ne jako míření. Válec, buben
   nebo kruhový prstenec vypadá ze všech osmi směrů stejně, takže se smí zapéct rovnou
   do spritu. **Radiální symetrie je to jediné kritérium**, jinak si podstavec vymýšlej,
   jak chceš. Hlaveň nebo rameno ho klidně přesahuje; hlaveň z lafety trčí.

## 2. Parametry

```
--ar 1:1 --style raw
--no text, letters, watermark, grid, sheet, multiple views, turnaround,
    background scenery, floor, ground, shadow, frame, border, label
```

**Nejsilnější páka je `--sref`.** Vygeneruj **jednu** věž pořádně, tu si ulož, a všechny
ostatní dělej s `--sref <URL té první> --sw 100`. Rodina z jednoho kořene je rodina;
osm samostatných promptů je osm cizinců. Tohle je táž rada jako v
[map_sketch_prompt.md](../design/map_sketch_prompt.md) a platí i tady.

Doporučené pořadí: začni **pomodorem** (`focus_timer`). Má nejjasnější tvar, takže se
na něm nejlíp pozná, jestli styl sedí.

## 3. Společný stylový základ

Připoj za každý popis níž:

```
a single small hand-built contraption, one object only, centred, filling the frame,
chunky toy-like proportions, worn and used but cared for, bold simple shapes, thick
readable silhouette, high contrast, limited palette of about eight colours, soft even
studio light from the upper left, no shadow on the ground, isolated on a plain flat
neutral grey background, game asset concept art
```

### Proč zrovna tahle slova

- **„hand-built contraption … worn and used but cared for"** — tohle je celý emoční
  rejstřík hry. Věže jsou návyky: pomůcky, které si člověk sám postavil proti
  rozptýlení. Nejsou to zbraně z armádního skladu a nejsou nové.
- **„chunky toy-like proportions"** — sesazuje je k nepřátelům, kteří jsou zavalití
  a hračkovití (popcorn s nohama, hrací automat s rukama).
- **„limited palette of about eight colours"** — kvantizace na 24 barev proběhne tak
  jako tak. Když je malba postavená na osmi, přežije to; když na padesáti, vyjde
  z toho rozmazaná fotka mezi pixel-artovými sousedy (změřeno na clickbaitu: 57 barev).
- **„soft even studio light from the upper left"** — světlo zleva je v bibli
  (`iso_bible.md` kap. 2), a terasa i její stín ho už dodržují.
- **„isolated on a plain flat neutral grey background"** — pro `cutout()`.

## 4. Popisy jednotlivých věží

Každý je odvozený z toho, **co ta věž dělá** (`data/habits/*.tres`), ne z jejího jména.

### focus_timer — „Focus Timer" · ZAČNI TÍMHLE
> Práce 8 s, krátká pauza 3 s, dlouhá 6 s. Je to doslova pomodoro: technika pojmenovaná
> po kuchyňské minutce ve tvaru rajčete.
```
a chunky red tomato-shaped kitchen timer standing upright, a pale clock dial set into
its front with black hands, a small brass bell on top, a short green stem and leaf,
the paint slightly chipped from years of use
```

### mindfulness — „Mindfulness"
> Plošné poškození, zpomaluje distrakce a rozbíjí jim pancíř.
```
a squat machine gun on a low metal tripod that fires round soft meditation cushions
instead of bullets, a neat stack of pale lilac cushions loaded where the ammunition box
would be, absurdly gentle for a weapon
```

### exercise — „Exercise"
> Pomalé těžké jednotlivé zásahy, stavěné na otužilé distrakce.
```
a small chunky wooden catapult with wide planted feet, a black iron kettlebell sitting
in its throwing bucket, one thick taut rope, heavy scarred timber frame
```

### real_hobby — „Deep Reading"
> Střílí proud utržených stránek přes celou mapu; každá se zachytí a působí dál.
```
a big open hardcover book resting on a sturdy wooden lectern, loose pale pages tearing
off the top edge and flying up, worn leather cover, carved wooden legs, dog-eared and
much re-read
```

### accountability — „Nutrition Guild"
> Vysílá tři zeleninové obránce, kteří blokují cestu.
```
a small wooden market crate stall packed with bright green broccoli and vegetables, a
little striped cloth awning over it, plank sides, a hand-painted price board with no
writing on it
```

### anchor — „Anchor"
> Rozšiřuje Routine o 260 px; návyky mimo ni se zastaví. Je to světlonoš.
```
a warm desk lamp with a heavy round weighted base, a wide domed shade glowing warm
yellow from inside, a simple bent metal neck, the shade dented on one side
```

### zen_pulsar — „Zen Pulsar"
> Nabíjí se v tichu, pak sklapne a zmrazí výseč.
```
a bronze singing bowl resting on a round flat cushion, a wooden mallet leaning against
its rim, one faint ring of sound rippling around the edge, the bronze darkened with age
```

### focus_pillar — „Focus Pillar"
> Zatím převzato ze Zen Pulsaru: zmrazí výseč. Přesýpací hodiny říkají „čas stojí".
```
a large hourglass held in a heavy wooden frame, pale sand caught in mid-fall inside the
glass, thick turned wooden posts, wide flat base, brass fittings gone green
```

## 5. Když je koncept hotový

```
python tools/mj_to_sprite.py <koncept.png> build/predloha_<vez>_64.png --test
```

`--test` vypíše naměřená čísla a **seznam porušených bran**. Prázdný seznam znamená, že
předloha ve hře obstojí. Nejčastější dvě selhání a co s nimi:

- **„částí > 1"** — v obraze zůstal uletěný kousek. Buď to v MJ přegeneruj, nebo ten
  kousek smaž ručně; `tools/install_tower_art.py` malé úlomky zahazuje sám, ale
  spolehni se na to až jako na pojistku.
- **„barev > 32"** — malba je moc bohatá. Přidej do promptu důraz na plochý stín
  (`flat blocked shading, no gradients`) a méně materiálů v jednom objektu.

### Stín se soudí NA PŘEDLOZE, ne až na výsledku

`--no cast shadow` Midjourney **neuhlídá** — vržený stín tam byl v každé várce, kterou
jsme viděli. Někdy ho výřez odstraní a někdy ne, a pozná se to jedině měřením:

```
    varianta A   studených pixelů 433   → skvrna vlevo dole, zapečená
    varianta B   studených pixelů   0   → čisté
```

(„studený" = `G ≥ R` a sytost > 0,08 na 64px předloze.)

Proč to musí padnout tady a ne později: **z hotových osmi směrů se stín odečíst nedá.**
Zkoušeno 22. 8. — skvrna měla medián (99, 119, 111), stopka rajčete (116, 123, 102).
Jsou to tytéž hodnoty, takže by maska sežrala stopku. Ze dvou konceptů, které se líbily
stejně, proto rozhodlo tohle jediné číslo.

## 6. Co NEDĚLAT — chyby, které stály kolo za kolem

**Vynucená paleta.** `color_image` s osmi světly dá přesně 8 barev. Jas sedne napoprvé,
ale vyjde z toho mrtvá plochá rekvizita. Nepřátelé mají 22–24 barev a dithering. Jas se
sesazuje **až potom**, `tools/tower_band.py` (ztlumí tělo, nechá akcent svítit).

**Izometrie.** Hotoví nepřátelé mají v promptu doslova *„front-facing low top-down RPG
perspective, zero isometric tilt"*. Věže kreslené izometricky a nepřátelé zepředu jsou
dvě projekce na jedné desce.

**Nožky.** První osmisměrná rodina (rajče, 22. 8. 2026) měla dole dřevěné nožky, protože
je měl koncept. Dvě věci na tom nesedly a obě měly tutéž příčinu — **pod tělem není nic,
co by drželo tvar napříč směry**:

* Ve třech směrech (`south-east`, `south`, `south-west`) nevyšly nožky dřevěné, ale jako
  **šedivá hmota**. Změřeno: sytost spodních řádků 0,26–0,29 proti 0,57–0,60 u zbylých
  pěti. V jižních pohledech je pod tělem nejvíc místa, tak si tam model vymyslel vlastní
  podstavec — pokaždé jiný.
* A hlavně: nožky mají předek, takže se **otáčely s věží**.

Odříznout je a podložit věž soklem kresleným enginem **nefunguje** — zkoušeno a zahozeno
téhož dne. Plochý kosočtverec pod pixelartovým tělem čte jako podložka pod hrnec, protože
nemá tutéž ruku. Podstavec patří do spritu; musí být jen kruhový (pravidlo 6 výš).

**A jedna, kterou tenhle dokument dělá jinak než druhé kolo:** věže **nejsou tvorové.**
Nepřátelé mají nohy, protože chodí. Věž stojí a pracuje. Život na věži nedělá obličej,
ale to, že je na ní vidět práce — padající písek, letící stránky, napnuté lano, svítící
stínítko.
