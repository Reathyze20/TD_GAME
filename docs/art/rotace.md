# Rotace do směrů — proč img2img nestačí

*Změřeno 18. 8. 2026. Předloha `build/gen/_ip_neutral/seda_04_2.png`, čtyři směry, stejný
seed. Data v `build/gen/_rotace_test/` a `build/gen/_sila_test/`.*

---

## Závěr napřed

**img2img neumí změnit pohled.** Ani s IP-Adapterem, ani bez něj, ani při síle 0,85.
Šestnáct vygenerovaných „směrů" jsou všechno čelní pohledy.

Není to otázka ladění. Výchozí obraz drží kompozici a textové vodítko („side view, facing
screen right, profile of the whole body") ji nepřepere. **ControlNet, nebo model
natrénovaný přímo na rotaci, je nevyhnutelný.**

> **Dopsáno později téhož dne: ControlNet to skutečně vyřešil** — profil se otočí, symetrie
> 0,76–0,79 proti 0,93 u čelního pohledu. Podrobnosti a to, co ještě nefunguje (pohled
> zezadu), jsou v [controlnet.md](controlnet.md). Závěr níž zůstává platný jako popis
> toho, co img2img umí a neumí.

---

## Měření

| podmínka | změna pohledu | symetrie | identita | známky |
|---|---|---|---|---|
| předloha | — | 0,89 | — | — |
| IP 0,50 | 0,003 | 0,87–0,88 | 0,045 | 9,1 |
| IP 0,70 | 0,004 | 0,91 | 0,047 | 9,0 |
| IP 0,85 | 0,026 | 0,91–0,92 | 0,062 | 8,2–8,4 |
| bez IP 0,85 | 0,036 | 0,89–0,91 | — | 8,8–9,1 |

**Změna pohledu** = 1 − překryv siluety proti jihu. Nula znamená, že všechny směry jsou
tentýž obraz.

**Symetrie** = překryv siluety s vlastním zrcadlem. Čelní pohled ≈ 0,89, profil by musel
spadnout výrazně níž. Nespadl ani jednou — a to je ta odpověď.

## Dvě hypotézy, které měření zabilo

**„Síla je moc nízká."** Zvýšení z 0,50 na 0,70 změnu pohledu nepřineslo (0,003 → 0,004)
a symetrie dokonce **stoupla**. Přitom se síla prokazatelně uplatňuje — čas na směr šel
ze 45 na 64 sekund, protože model odjede víc kroků. Pracuje víc, otáčí stejně.

**„IP-Adapter přehlušuje text."** Vypadalo to tak, dokud nedoběhl kontrolní vzorek:
**bez** adaptéru při síle 0,85 se pohled nezměnil taky (0,036). Adaptér za to nemůže.

Co IP-Adapter při vysoké síle udělá, je něco jiného: sprite ztratí žluté oči a vybledne
(známky 8,2–8,4 proti 8,8–9,1 bez něj). Pro rotaci je tedy **na škodu** — jeho místo je
u generování z nuly, kde drží identitu, ne u změny pohledu.

## Past, na kterou se přišlo až tady

Načtení IP-Adapteru přepíše UNetu config na `encoder_hid_dim_type='ip_image_proj'`, čímž
se `image_embeds` stane povinným argumentem. Kdo pak zavolá tutéž rouru bez reference:

```
ValueError: ... requires the keyword argument `image_embeds` in `added_cond_kwargs`
```

A protože UNet je sdílený mezi textovou i img2img rourou, **otráví to celý proces**. Ve
studiu stačilo jedno generování s referencí a následné doladění bez ní už spadlo.

Ošetřeno `gen.unload_ip_adapter()`, který se volá v `generate()` bez reference i v
`rotate()`. Příznak sedí na UNetu, ne na rouře — roury se staví a zahazují, UNet je jeden.

## Co dál `VYŘEŠENO — viz controlnet.md`

1. **ControlNet** — hotovo, `gen.rotate_pose()`. Profil se skutečně otočí: symetrie spadla
   z 0,93 na 0,76–0,79 a změna pohledu vyskočila z 0,003 na 0,39.
   **Pozor na past v původní formulaci:** stálo tu „lineart nebo depth **ze siluety**",
   což je špatně. Silueta základního spritu je čelní pohled, takže by se vnutila i severu
   a východu — ta samá vada, tentokrát vynucená konstrukcí. Tvar musí vznikat **z úhlu**,
   ne z předlohy; dělá to `tools/gen_pose.py`.
2. ~~Do té doby dělat směry v PixelLabu~~ — už není potřeba.
3. `rotate()` i `rotate_ip()` nechat, ale **nevydávat je za rotaci**. Dnes to jsou
   generátory variant téže příšery v čelním pohledu, což je jiná — a taky užitečná — věc.
   Ve studiu je proto rozbalovátko se třemi režimy a kostra je výchozí.

Vedlejší zjištění: hra osm směrů nepoužívá. `defender_unit.gd:415` bere jen
`walk_south`, `walk_north`, `walk_east` a západ si zrcadlí. Generovat osm je plýtvání.
