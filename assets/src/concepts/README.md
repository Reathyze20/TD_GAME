# Koncepty high ground atlasu

Šest hotových směrů. Každý je **kompletní atlas 192×192** — správné rozložení 16 slotů,
správné fazety, povrch v paletě hry. Kterýkoliv z nich můžeš hned vyexportovat a hrát si
s ním, aniž bys nakreslil jedinou čáru.

Náhledy: [_nahled_v_mape.png](_nahled_v_mape.png) (skutečná velikost ve hře, tohle rozhoduje)
a [_nahled_atlasy.png](_nahled_atlasy.png) (zvětšené atlasy, tady je vidět detail).

| # | Soubor | Charakter |
|---|---|---|
| 1 | `atlas_1_veins.svg` | Organické dendrity a synaptické uzly. Nejvíc „živý mozek". |
| 2 | `atlas_2_circuit.svg` | Vyryté ortogonální kanály s kontaktními pady. Navazuje na stávající `background.jpg`. |
| 3 | `atlas_3_ridges.svg` | Husté vodorovné pruhování. Nejčitelnější v malé velikosti. |
| 4 | `atlas_4_plating.svg` | Mřížka zaoblených destiček. Nejvíc „postavené", nejméně organické. |
| 5 | `atlas_5_minimal.svg` | Jen fazeta a vsazený panel. Nechává vyniknout věžím. |
| 6 | `atlas_6_fracture.svg` | Úhlaté trhliny. Čte se jako poškozený, přetížený mozek. |

### Mozková tkáň

Tyhle tři nesou vlastní paletu — teplý základ, protože na modrošedém podkladu se tkáň
prostě přečíst nedá. Podlaha zůstává tmavě modrá, plošina je růžová, a ten kontrast je
funkční: hráč hned vidí, kam se dá stavět.

| # | Soubor | Charakter |
|---|---|---|
| 7 | `atlas_7_cortex.svg` | Růžová kůra, azurový rim light. Nejsilnější „mozek". |
| 8 | `atlas_8_cortex_muted.svg` | Tlumená mauve verze s ocelovou hranou. Blíž paletě UI. |
| 9 | `atlas_9_cortex_inflamed.svg` | Zanícená, oranžovo-červená. Na level 2 nebo bosse. |

Vzor `gyri` je kreslený jako tlustý tah (tělo závitu) plus tenčí světlý tah posunutý
o pixel doleva nahoru (osvětlený hřbet). Ten posun dělá tu oblost — když budeš vzor
upravovat, drž oba tahy pohromadě.

## Jak je upravovat

Struktura vrstev je u všech stejná:

- **1 podklad** — 16 plných čtverců, základní barva plošiny
- **2 povrch** — 16 **klonů** jednoho vzoru
- **3 hrany tmavé** / **4 hrany světlé** — fazety, ty needituj

Vzor je definovaný **jednou** a do všech šestnácti buněk vložený jako klon. Označ
libovolný klon a dej `Shift+D` (Edit → Klon → Vybrat originál). Změna originálu se
promítne do všech šestnácti naráz.

Vzor je uvnitř zabalený devětkrát s posunem o ±48 px a oříznutý na buňku. Díky tomu
cokoliv, co vyjede z jedné hrany, se vrátí na protilehlé — proto povrch navazuje i mezi
různými dlaždicemi. Když budeš přidávat vlastní prvky, přidej je do stejné skupiny,
jinak ti navazování přestane fungovat.

## Co na tom není dokonalé

Všech šestnáct dlaždic sdílí **jeden a týž** vzor, takže se povrch opakuje přesně po
48 px. V ploše 3×3 to není poznat, u velké souvislé plošiny ano. Až budeš chtít
rozbít pravidelnost, odklonuj dvě tři dlaždice (`Shift+Alt+D` = Odpojit klon) a jen
jim vzor pootoč nebo posuň.

## Export

`Esc` (zrušit výběr) → `Ctrl+Shift+E` → **Page** → ověř **192 × 192** → PNG →
`assets/terrain/high_ground_atlas.png`, přepsat.

Postup a ověření v Godotu je v [../../../docs/ART_INKSCAPE.md](../../../docs/ART_INKSCAPE.md).
