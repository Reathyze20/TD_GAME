# Zmenšování renderu na cílový rastr

*Změřeno 17. 8. 2026 na sedmi existujících 1024px renderech v `build/gen`. Skript nic
negeneroval, takže rozdíl ve výsledku je JEN tou metodou zmenšování.*

---

## Závěr napřed

**Zmenšovač vybírá barvy, ne strukturu.** Vyměnit ho za chytřejší nezlepší sprity, které
jsou rozbité tvarem. Default zůstává `median`; `kcentroid` je v `gen.py` jako změřená
volba (`--downscale kcentroid`), ne jako doporučení.

Když je sprite kaše, hledej příčinu v 1024px renderu, ne tady.

---

## Co se měřilo

Median (původní) proti k-centroidu. K-centroid shlukuje celé RGB bloku na `k` barev a
vrátí střed nejpočetnějšího shluku; median řeší každý kanál zvlášť, a může proto vrátit
barvu, která v bloku vůbec nebyla.

Celá `to_sprite()` oběma metodami, známky ze stejného `score()`, kterým se měří zbytek hry:

| render | median | k-centroid |
|---|---|---|
| _detail | 8,6 | 8,3 |
| _lora 0.0 | 8,9 | 8,8 |
| _lora 0.45 | 8,7 | 8,4 |
| _lora 0.7 | 8,1 | 8,3 |
| _lora 1.0 | 8,6 | 8,3 |
| _smoke_1 | 9,3 | 9,3 |
| _smoke_2 | 9,1 | 9,1 |

Okem k nerozeznání (kontaktní list `build/gen/_downscale_cmp/_sheet.png`).

## „Žádný rozdíl" bývá chyba v měření. Tady nebyla

- pixely se liší na **73–100 % plochy**
- ale **medián** toho rozdílu je **0–4 z 255**, tedy nic
- jen horních 5 % pixelů se liší výrazně (43–77 z 255) — a to jsou přesně ty nejednoznačné
  bloky na hranách, kde má k-centroid teoreticky pravdu
- metrika `okraj` vyšla u všech sedmi na tři desetinná místa **identicky**

## Proč to tak musí být

Ten identický okraj vysvětluje všechno ostatní. Siluetu neurčuje pravidlo pro výběr barvy,
ale pravidlo pro alfu („blok je neprůhledný, jen když je neprůhledná jeho většina") a mřížka
bloků. Obojí mají obě metody stejné, takže **silueta vyjde bit po bitu táž**.

Zmenšovač tedy z principu nemůže změnit tvar. Může změnit jen to, jakou barvu tvar dostane.

## Co se tím vyloučilo

- Reimplementovat Pixelization (SIGGRAPH Asia 2022) — hodně práce za páku naměřenou na nule.
  Navíc má v README zákaz komerčního užití, takže by se stejně musela psát znovu z článku.
- Obecně: honit lepší downscaler, dokud je rozbitá struktura renderu.

Zbývající podezřelý je **struktura 1024px renderu** — tedy conditioning modelu, ne
postprocess. Tam vede další práce.
