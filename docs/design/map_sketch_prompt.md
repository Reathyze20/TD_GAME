# Midjourney: skicák s koncepty map

Doplněk k [map_ideation_prompt.md](map_ideation_prompt.md). Tam textová AI vymyslí
nápady, tady z nich vznikne stránka skicáku, která se dá ukázat.

## Past, kterou je potřeba znát předem

**Midjourney neumí čitelný text.** Na tvojí referenci je přitom polovina hodnoty právě
v popiscích — „Good LoS", „Dead Zone", „Cone of Fire", šipky k vysvětlivkám. Midjourney
vygeneruje **klikyháky, které vypadají jako rukopis**, ale nepřečteš je. Nadpis o dvou
třech slovech v uvozovkách někdy vyjde, odstavec poznámek nikdy.

Z toho plyne, k čemu to použít:

- **Ano:** nálada, pitch, obálka designového dokumentu, inspirace při vymýšlení tvarů,
  obrázek do prezentace.
- **Ne:** podklad, ze kterého se bude stavět mapa. Na to potřebuješ diagram s reálnými
  popisky, ne obrázek.

Když budeš chtít obojí — ruční vzhled **i** čitelné popisky — jde to udělat jako
vektorový diagram stylizovaný do „nakresleno rukou" (knihovna rough.js dělá přesně
tenhle efekt). Řekni si a udělám to; není to Midjourney, ale je to čitelné a dá se to
generovat přímo z dat levelu.

## Nejsilnější páka: `--sref`

Prompt nastaví obsah, ale **styl trefíš referencí, ne slovy**. Nahraj tu svoji
fotku skicáku (v Discordu ji přetáhni do chatu a zkopíruj adresu obrázku, ve webové
aplikaci ji dej do pole style reference) a přidej na konec promptu:

```
--sref <adresa tvojí fotky> --sw 150
```

`--sw` je síla stylu, výchozí 100, rozsah 0–1000. Přes ~400 začne styl přebíjet obsah.

Až vygeneruješ stránku, která se ti líbí, použij **ji** jako `--sref` pro další —
tím dostaneš celou sérii, která vypadá jako jeden a ten samý sešit.

## Prompt A — celá stránka skicáku (jako tvoje reference)

```
pencil sketchbook page of isometric tower defense level concepts, three hand-drawn
axonometric terrain slabs on graph paper, winding enemy paths carved between raised
plateaus, small square markers for tower platforms, cross-hatched graphite shading on
the cliff faces, hand-lettered underlined headings, callout arrows pointing to short
margin notes, tiny inset diagrams of turrets and firing cones along the bottom edge,
squared grid paper, warm off-white page, monochrome graphite, flat overhead photo of an
open notebook, soft shadow along the spine
--ar 16:9 --style raw --stylize 100 --v 7
```

## Prompt B — jeden level do detailu

```
single isometric tower defense level layout, pencil on graph paper, diamond-shaped
terrain slab with thick extruded sides, a spiral path cut into the surface leading to a
central base, raised terrace blocks marked as build platforms, hatched shading on the
vertical faces, a few leader arrows with short handwritten labels, technical design
sketch, monochrome graphite, faint blue grid
--ar 4:3 --style raw --stylize 80 --v 7
```

Tvar cesty vyměň podle nápadu: `a spiral path` → `an S-curve path`, `a forking path that
splits and rejoins`, `a long switchback path along the edges`, `a figure-eight path
crossing itself in the middle`.

## Prompt C — list studií do okraje

Malé ikonky a schémata, která se dají použít jako výplň stránky nebo jako legenda:

```
sketchbook margin study sheet, pencil on graph paper, small isometric diagrams of tower
defense elements: firing cones, choke points, elevated platforms, path junctions, dead
zones, each with a short hand-lettered caption underneath, cross-hatching, monochrome
graphite
--ar 3:4 --style raw --v 7
```

## Parametry a co dělají

| parametr | k čemu |
|---|---|
| `--ar 16:9` | poměr stran. Tvoje reference je zhruba 16:9, jeden level snese 4:3 nebo 3:2. |
| `--style raw` | vypne „hezčení". U technické kresby ho chceš skoro vždycky. |
| `--stylize 50–150` | jak moc si Midjourney přidává vlastní vkus. Nízko = drží se promptu. |
| `--chaos 0` | drží čtyři návrhy blízko u sebe. Nahoru jdi, jen když chceš rozstřel. |
| `--seed <číslo>` | stejný seed + stejný styl = série, která drží pohromadě. |
| `--no color` | vynutí grafit. Zkus, až když ti do kresby leze barva. |
| `--no text` | ubere klikyháky. **Ale ubere i vzhled popisků**, který na referenci chceš. |

## Ladicí slovník

Přidej, když chceš **víc ručního**:
`loose gesture lines, visible construction lines, smudged graphite, eraser marks,
slightly wobbly freehand lines`

Přidej, když chceš **víc technického**:
`fine liner pen, ruled straight edges, precise isometric grid, drafting style`

Přidej, když chceš **barevný akcent** (a rovnou v paletě hry — zlatá cesta, fialová tkáň):
`amber and violet colored pencil accents, otherwise monochrome`

Přidej, když chceš, aby to **vypadalo jako fotka sešitu**:
`spiral binding along the left edge, dog-eared corner, slight page curl, desk lamp
shadow`

## Postup, který dává smysl

1. Textovou AI (prompt v [map_ideation_prompt.md](map_ideation_prompt.md)) nech vymyslet
   nápady. Vrátí ti mimo jiné nákres 8 × 8 bloků.
2. Z nákresu si vytáhni **tvar cesty** jednou větou — spirála, dvojitá klička, vidlice.
3. Vlož ho do promptu B a vygeneruj.
4. To, co se povede, použij jako `--sref` pro zbytek série.

Tvar tedy vymýšlí ta chytrá AI a Midjourney ho jen kreslí. Naopak to nefunguje —
Midjourney nezná mřížku 8 × 8 ani pravidlo, že terasa je zeď i parcela, takže mapa
z jeho hlavy bude hezká a nehratelná.
