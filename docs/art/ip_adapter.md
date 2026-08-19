# IP-Adapter — identita z obrázku místo z textu

*Změřeno 17. 8. 2026. Tři seedy na podmínku, tentýž prompt (Overthinking Ghoul, ten, který
dřív dával skvrny), reference `phantom_buzz_frame_1.png`. Data v `build/gen/_ip_test/`
a `build/gen/_ip_neutral/`.*

---

## Závěr napřed

**První zásah, který se skutečně projevil.** Zmenšovač dal ±0,3 a nezměnil nic; IP-Adapter
dal +1 známku a šum na polovinu. A hlavně opravil to, co žádné čištění opravit nemohlo:
z chapadlových skvrn se staly postavy s hlavou, trupem a končetinami.

Nastaveno: `IP_SCALE = 0.4`, `IP_NEUTRAL = True`.

---

## Měření 1: síla identity

| podmínka | známky | průměr | osamocené pixely |
|---|---|---|---|
| bez reference | 7,8 · 7,0 · 8,2 | 7,7 | 0,25–0,28 |
| **0,4** | 9,0 · 8,6 · 8,4 | **8,7** | 0,125 |
| 0,6 | 9,1 · 8,8 · 7,8 | 8,6 | 0,11–0,18 |
| 0,8 | 8,6 · 8,5 · 7,9 | 8,3 | 0,10–0,15 |

Rozdíl mezi 0,4 a 0,6 je při třech vzorcích šum. Rozhodla barva, ne známka — viz níž.

---

## Měření 2: reference unesla paletu, odbarvení ji vrátilo

Reference je **azurová**, prompt chce **hlubokou fialovou a neonově žlutou**. Známka tenhle
problém neukáže vůbec: přebarvený sprite je pořád čistý sprite. Proto se měřil i podíl
sytých pixelů v barvách promptu proti barvě reference.

| podmínka | známka | barvy promptu | azurová |
|---|---|---|---|
| bez reference | 7,7 | 57 % | 2 % |
| barevná reference 0,4 | 8,7 | **10 %** | **56 %** |
| **odbarvená reference 0,4** | 8,7 | **88 %** | **0 %** |
| odbarvená reference 0,6 | 8,5 | 55 % | 4 % |

**Ten poslední řádek je proti intuici a je důležitý.** U barevné reference platilo „silněji =
víc její palety". U odbarvené platí „silněji = víc ŽÁDNÉ palety" — sprite se vybělí do
šedomodré. Odbarvení tedy nezruší přenos barvy, jen změní, co se přenáší.

Obě páky proto drží spolu: čím neutrálnější reference, tím níž musí být síla. Při 0,4 to
sedí; nad 0,5 se odbarvení začne propisovat do výsledku.

Odbarvení **nestálo nic na známce** a vrátilo promptu paletu úplně. Navíc je i lepší než
generování bez reference (88 % proti 57 %) — když má model tvar hotový z reference, drží
zadanou paletu líp, než když si musí vymyslet obojí.

Tvar z reference, barva z promptu. To jsou dvě nezávislé páky a teď to tak i funguje.

---

## Jak je to zapojené

`gen_ref.ref_identity()` odbarví **subjekt** a pozadí nechá magentové. To druhé je
podstatné: šedé pozadí v referenci by model naučilo kreslit šedé pozadí, a tím by se
rozbil `cut_background`, který na té ploše stojí.

```bash
python tools/gen.py "..." --ref assets/distractions/phantom_buzz_frame_1.png \
                         --ref-mode identita --ip-scale 0.4
python tools/gen.py "..." --ref ... --ref-mode identita --ip-color   # ber i barvu
```

`--ip-color` má smysl u varianty téže příšery, kde je barva součástí identity.

---

## Dvě pasti, na které se přišlo až za běhu

**Attention slicing se s IP-Adapterem tluče.** `build_pipe()` volá
`enable_attention_slicing()`; adapter si přepíše attention procesory a sliced varianta se
přitom postaví znovu bez `slice_size`:

```
TypeError: SlicedAttnProcessor.__init__() missing 1 required positional argument
```

Řeší se vypnutím slicingu před načtením adaptéru. Nic se tím neztrácí — je to pojistka
proti OOM při větším batchi a `generate()` jede po jednom obrázku.

**Obrázkový enkodér zůstane na CPU.** `load_ip_adapter()` přidá do roury nový modul, ale
to už je po `pipe.to("cuda")` v `build_pipe`. Bez dodatečného `.to("cuda")` to spadne na
neshodě zařízení.

---

## Nová vada, kterou odbarvení přineslo `VYŘEŠENO — byla to záměna příčin`

Na kontaktním listu mají **2 z 6** spritů s odbarvenou referencí kolem sebe šedý
obdélník — `cut_background` pozadí neodstranil.

Příčina je nejspíš přesně ta, které mělo zabránit ponechání magentového pozadí
v referenci: model občas šeď z odbarveného subjektu rozšíří i za něj a nakreslí šedé
pozadí místo plné magenty. Zaplava od okraje pak nemá čeho se chytit.

**Doměřeno 18. 8. 2026: příčina byla jinde.** Šest seedů s desetiprocentním okrajem
v předloze i bez něj dalo shodně **0/6 vad** — okraj plátna to nezpůsoboval.

Skutečný viník bylo skoro jistě **useknutí promptu na 77 tokenů**. Ta sada měla prompt
o 120 tokenech a odpadlo z něj i `solid magenta background`, takže model nevěděl, na co
má kreslit. S promptem, který se vejde, se vada neobjeví.

Je to už druhá vada, kterou to useknutí způsobilo — po roji lebek z chybějícího
`centered single creature`. Stojí za to to mít na paměti u každého dalšího „divného"
výsledku ze starých sad.

## Výhrada k těm číslům

Známka vyskočila zčásti proto, že sprity **zploštěly** — osamocené pixely spadly z 0,27 na
0,10. Studio samo varuje, že „nejvyšší známku mívá ten nejplošší sprite", takže část toho
skoku je metrika, ne kvalita.

Tady se ale čísla i oko shodují: těla proti skvrnám je vidět bez měření. Kdyby se
rozcházely, platí oko.

---

## Co z toho plyne pro ControlNet

Otázka „stačí IP-Adapter i na rotaci?" už má odpověď a je **ne** — viz
[rotace.md](rotace.md). Šestnáct vygenerovaných „směrů" byly všechno čelní pohledy, a to
i bez adaptéru a při síle 0,85. Změnu pohledu img2img nevyrobí.

IP-Adapter tedy zůstává tam, kde se osvědčil: **generování z nuly**, kde dodá tvar a drží
identitu. Na rotaci je dokonce na škodu — při vysoké síle sprite vybledne a ztratí žluté
oči (známky 8,2–8,4 proti 8,8–9,1 bez něj).

ControlNet je tím potvrzený jako nutný, ne volitelný.
