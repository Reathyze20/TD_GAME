# Retro Diffusion Lite jako generátor

*Placená Aseprite extension, kterou umíme řídit bez Aseprite. Vlastní fork SD 1.5
vycvičený na pixel art, běží lokálně, zaplacený jednou.
Klient: `tools/retrodiffusion.py`. Ve studiu: hlavička → **zdroj → Retro Diffusion**.*

---

## Licence a povolení k automatizaci

`EULA.txt` uvnitř `models/RetroDiffusionLite1.5.0/RetroDiffusionLite.aseprite-extension`
zakazuje mimo jiné Software „combined with or incorporated in any other software",
reverse engineering a užití Software „for any commercial purpose". O vlastnictví
**vygenerovaných výstupů nemluví vůbec** — mlčí, což není totéž co dovoluje.

Míří to přesně na to, co dělá `tools/retrodiffusion.py`: řídí jejich server vlastním
klientem a odkazuje na `image_server.py` po číslech řádků. Používání RD rukama v Aseprite
se to netýká — to je přesně ta věc, která se prodává.

**Astropulse na dotaz odpověděli ano.** Doplň sem jejich přesné znění, ne parafrázi:

> _(sem vlož citaci odpovědi)_
>
> — Astropulse, _(datum)_, kanál: _(mail / Discord / …)_

Na co přesně souhlas platí — zaškrtni jen to, co opravdu odpověděli:

- [ ] komerční užití vygenerovaných výstupů
- [ ] řízení serveru vlastním nástrojem místo Aseprite
- [ ] něco dalšího: …

Dokud tam ta citace není, je tohle jen něčí vzpomínka. Datum je součást věci: EULA se
může změnit a souhlas platí ke znění, které platilo tehdy.

---

## Proč vedle lokálního SDXL

| | Retro Diffusion | lokální SDXL (`gen.py`) |
|---|---|---|
| 4 sprity 32×32 | **17 s** | ~160 s |
| plátno | 512×512, `pixel_size` 16 | 1024×1024 |
| na cílový rastr | k-centroid **na serveru** | náš `downscale_median` |
| pozadí | rembg segmentace (CPU) | `cut_background` chroma-key |
| styl | 10 hotových LoR | jedna pixel-art LoRA se sílou |

Ten rozdíl v čase není kosmetický. Při čtyřiceti sekundách na sprite je zkoušení
promptů drahé a člověk se spokojí s prvním, co vyjde. Při čtyřech je to konečně
smyčka, ve které se dá iterovat.

Klíčové je ale to druhé: **RD kreslí rovnou v cílovém rastru.** SDXL dělá obrázek,
který vypadá jako pixel art, a my z něj pixel art teprve vyrábíme. RD ho vyrábí sám,
a přesně tím dělením, které naše pravidlo rastru vyžaduje:

```
16×16 dlaždice   → plátno 256×256, pixel_size 16
32×32 příšera    → plátno 512×512, pixel_size 16
64×64 boss       → plátno 512×512, pixel_size 8
```

Proto se po RD **nepouští** naše zmenšování — zmenšovalo by se už zmenšené.

---

## Co jsme naměřili

### Paletu si musíme dodělat sami

Sprite 32×32 přímo od serveru: **263 barev na 288 neprůhledných pixelech.** Skoro
každý pixel vlastní odstín. Není to chyba RD — k-centroid při zmenšování barvy míchá —
ale do hry, kde je rozpočet palety měřítko kvality, to takhle nesmí.

Dvě cesty a obě fungují:

- `--palettize` (jejich, na serveru): 260 barev → **7**, a na oko je rozdíl proti
  originálu sotva vidět. Skoro zadarmo.
- `gen.clean(a, colors)` (naše, používá to i studio): srovná na zadaný rozpočet, výchozí 16.

Studio jede přes `gen.clean`, protože je to tatáž funkce, která čistí SDXL i PixelLab —
jedna paleta na celý svět je víc než o pár barev míň.

### LoRA je jiná páka, než se čeká

Prompt „broccoli knight with a shield", 32×32, stejný seed:

| nastavení | co vyšlo |
|---|---|
| bez LoRA | **nejvíc struktury** — růžičky brokolice jsou vidět |
| `topdown` 50 | nejhorší — vyhladí texturu na lesklou kuličku |
| `gamecharacters` 100 | hrbolatý povrch, čte se jako hlava, ale bez postavy |
| `topdown` 100 | ze všeho udělá **tvar štítu** |

Poučení: LoRA tady není „víc kvality", je to **silueta**. `topdown` na plné síle vnutí
tvar; na poloviční jen ubere detail a nic nedá. Když jde o strukturu povrchu, vyplatí se
začít **bez ní**.

### Rozhoduje velikost, ne délka promptu

První kolo testů použilo krátký prompt na 32 px a vyšly z toho zelené kuličky. To bylo
nefér srovnání: naše nejlepší SDXL výsledky mají čtyřicetislovný prompt na 64 px.
Tentýž dlouhý prompt („sturdy Broccoli Knight defender, stocky vegetable stalk body
wearing dark iron cuirass with rivets, dense green broccoli crown helmet, holding wooden
shield and mallet, low top-down RPG perspective"), stejný seed, obě velikosti:

| | výsledek |
|---|---|
| **64×64** | těla s **nohama a botama**, jedno i s pažemi. Postavy, ne skvrny. |
| **32×32** | kaše. Jeden z pokusů má **dvě barvy** a je to černý flek. |

Prompt byl v obou případech tentýž. **Na 32 px SD 1.5 postavu prostě neumístí** —
není kam. To není chyba promptu ani LoRA a nespraví to ani jedno.

### Kde tedy RD stojí proti našemu SDXL

Ani na 64 px nedá RD rekvizity: vyjde zelená silueta bez štítu, bez kyrysu, bez palice.
Naše SDXL sada `64x64_pixel_art_character_sprite__sturdy` s týmž zadáním má rytíře se
štítem i kyrysem a známky 9,1 až 9,7.

Takže rozdělení práce:

- **Retro Diffusion** — rychlost a nativní rastr. Iterování promptů (za 17 s víš, jestli
  má směr smysl), dlaždice a terén (má na to `tiling16`, `tiling32`, `topdown`),
  dekorace, hrubý tvar k dalšímu doladění.

**Terénní prompty ať rovnou žádají barevný stín, ne jen tmavý.** `style_audit.py` na
684 shipped souborech (18. 8. 2026) naměřil terén na 2–11° posunu odstínu proti cíli
20°+ — nejhůř dopadla právě podlaha (`path/`, 2–4°), kterou RD umí za 17 s přegenerovat
a rovnou ověřit. Přidej do promptu `shadow shifts cool blue/violet, not a flat black
falloff`, jinak i rychlá iterace skončí v šedé (stejná past jako u lokálního SDXL).
- **lokální SDXL** — postavy s rekvizitami. Pomalejší, ale jako jediné to umí.
- **32px postavy** — mimo obojí. Ty v hře vznikly v PixelLabu.

### Kvalita = počet kroků, ale jen do šesti

`steps = round(3,4 + kvalita² / 2)` (jejich vzorec, `image_server.py:2085`).
Kvalita 4 → 11 kroků, 6 → 21. Rozdíl mezi 4 a 6 je vidět; nad 6 už model jen počítá dýl,
protože je LCM-destilovaný. Posuvník ve studiu proto končí na 8 a popisek to říká.

---

## Past v protokolu, na kterou se přijde až nakonec

Generátor na serveru yielduje dvojici `[titulek, obrázky]` a v **posledním** kroku je
první položka prázdný řetězec (`image_server.py:2285`). Obě položky posílá zvlášť, takže
po drátě přijde holý JSON `""` — ne objekt.

Aseprite klient si toho nevšimne: v Lue je čtení klíče z něčeho jiného než tabulky tiše
`nil`. V Pythonu je to `AttributeError` — a padá to **až na poslední zprávě**, kdy jsou
obrázky spočítané a zahodí se.

Projeví se to **jen** při `send_progress=True`, což je přesně to nastavení, které chceš,
když má UI ukazovat průběh. Ošetřeno v `_call()`.

---

## Jak to pustit

```bash
python tools/retrodiffusion.py check      # instalace, modely, LoRA, stav portu
python tools/retrodiffusion.py start      # jednou za sezení, pak nechat běžet
python tools/retrodiffusion.py gen "prompt" --size 32 --n 4 --quality 6 --palettize
python tools/retrodiffusion.py stop       # korektně uvolní VRAM
```

Server startuje **minuty** (import knihoven, načtení modelu, při prvním spuštění navíc
stáhne ~1,7 GB). Startuje se jednou a nechá se běžet — nikdy ne na každý prompt.
Má vlastní okno konzole a je to jediné místo, kde je vidět jeho progress bar a případný
traceback: k nám se chyba vrátí jen jako `{"action":"error"}` bez detailu.

Ve studiu se o start postará samo první generování; tlačítko **spustit server** je tam
proto, aby se to čekání dalo odbýt dopředu.

---

## Co RD Lite neumí

Neural Resize, Neural Detail a Pixelate jsou podle jejich vlastní tabulky funkcí
**jen ve Full verzi**, ne v Lite. Škálování spritů mezi rastry tedy zůstává na nás
(`tools/tiles.py`, `sprite_cleanup.py`).
