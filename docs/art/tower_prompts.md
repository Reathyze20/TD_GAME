# Prompty pro věže — ruční zadávání do PixelLabu

*Odvozeno z měření hotových nepřátel (`list_characters`) a ze dvou zpackaných kol
21. 8. 2026. Mechaniky jsou opsané z `data/habits/*.tres`, ne z jmen věží.*

## 1. Nastavení (stejné pro všechny)

Nástroj: **Create Image (Pixflux)** — jediný textový nástroj, který má `isometric`
i `color_image`, a stojí 1 generování místo 20–40 u `create_character`.

| parametr | hodnota |
|---|---|
| width × height | **64 × 64** |
| no_background | **true** |
| isometric | **false** |
| view | **low top-down** |
| outline | **single color black outline** |
| shading | **basic shading** |
| detail | **medium detail** |
| text_guidance_scale | 8.0 |
| color_image | **NEPOUŽÍVAT** |

**Podstavec musí být kruhový.** Věž se otáčí za nepřítelem a otáčí se s ní celý sprite,
takže cokoli s předkem (nožky, schůdek, hranatá deska) se tím otáčením zradí. Válec nebo
prstenec vypadá ze všech osmi směrů stejně. Podrobně v
[tower_concept_mj.md](tower_concept_mj.md) §6.

## 2. Společný ocas promptu

Připoj za každý popis níž doslova:

```
64x64 pixel art sprite of a small machine, front-facing low top-down RPG perspective
aligned straight to the square grid, zero isometric tilt. It is an object, not a
creature: no face, no eyes, no arms, no legs. It stands still and works by itself.
Gritty pixel dithering, high contrast, crisp dark outline, strong readable silhouette.
It stands on a round radially symmetric base with no front and no legs.
No text, no floor shadow, no baked ground shadow, clean transparent background.
```

## 3. Popisy jednotlivých věží

Každý je odvozený z toho, **co ta věž dělá**, ne z jejího jména.

### focus_timer — „Focus Timer"
> *`has_work_cycle`, práce 8 s, krátká pauza 3 s, dlouhá 6 s → doslova pomodoro.*
```
a chunky red tomato-shaped kitchen timer standing upright, a pale clock dial set into
its front with black hands, a small brass bell on top, a short green stem and leaf
```

### mindfulness — „Mindfulness"
> *Plošné poškození, zpomaluje a rozbíjí pancíř.*
```
a squat machine gun mounted on a low metal tripod, firing round soft meditation
cushions instead of bullets, a neat stack of pale lilac cushions loaded where the
ammunition box would be
```

### exercise — „Exercise"
> *Pomalé těžké jednotlivé zásahy, na tanky.*
```
a small chunky wooden catapult with wide planted feet, a black iron kettlebell sitting
in its throwing bucket, one thick taut rope, heavy timber frame
```

### real_hobby — „Deep Reading"
> *Střílí proud utržených stránek přes celou mapu, každá se zachytí a působí dál.*
```
a big open hardcover book resting on a sturdy wooden lectern, loose pale pages tearing
off the top edge and flying away, worn leather cover, carved wooden legs
```

### accountability — „Nutrition Guild"
> *Vysílá tři zeleninové obránce, kteří blokují cestu.*
```
a small wooden market crate stall packed with bright green broccoli and vegetables,
a little cloth awning over it, plank sides, standing on the ground
```

### anchor — „Anchor"
> *Rozšiřuje Routine o 260 px; návyky mimo ni se zastaví. Je to světlo.*
```
a warm desk lamp with a heavy round weighted base, a wide domed shade glowing warm
yellow, a simple bent metal neck
```

### zen_pulsar — „Zen Pulsar"
> *Nabíjí se v tichu, pak sklapne a zmrazí výseč.*
```
a bronze singing bowl resting on a round flat cushion, a wooden mallet leaning against
its rim, one faint ring of sound rippling around the edge
```

### focus_pillar — „Focus Pillar"
> *Zatím převzato ze Zen Pulsaru: zmrazí výseč. Přesýpací hodiny říkají „čas stojí".*
```
a large hourglass held in a heavy wooden frame, pale sand caught in mid-fall inside
the glass, thick turned wooden posts, wide flat base
```

## 4. Jak poznat, že to vyšlo

Změř výsledek proti těmhle číslům. Nepřátelé jsou cíl, protože ti už fungují.

| | cíl (nepřátelé) | vyhoď, když |
|---|---|---|
| obsah na plátně | 29–40 × 40–48 px | přesahuje 56 px na výšku |
| počet barev | **22–24** | pod 12 (bude to plochá rekvizita) |
| tmavý obrys | 70–84 % okrajových pixelů | pod 50 % |
| sytost | 0,33–0,86 | pod 0,25 |
| jas (součet RGB) | — | **nad 380** (terasa má 484, splyne s ní) |

Jas se dá spravit i potom: `python tools/tower_band.py` ztlumí **tělo** na 300 a nechá
akcent svítit (dělí podle sytosti). Počet barev ani obrys se potom spravit nedají.

## 5. Dvě chyby, které stály dvě kola

**1. kolo — vynucená paleta a izometrie.** `color_image` s osmi světly dal přesně
8 barev: jas sedl napoprvé, ale vyšly z toho mrtvé ploché rekvizity. A `isometric=true`
je špatná projekce — hotoví nepřátelé mají v promptu doslova *„front-facing low top-down
RPG perspective, zero isometric tilt"*. Byly to dvě projekce na jedné desce.

**2. kolo — přehnaná oprava.** Z „mrtvých rekvizit" jsem usoudil, že chybí život, a
zadal tvory s obličeji a nohama. Jenže **nepřátelé mají nohy, protože chodí.** Věže
stojí a pracují. Život na věži nedělá obličej, ale to, že je na ní vidět práce:
padající písek, letící stránky, napnuté lano, svítící stínítko.
