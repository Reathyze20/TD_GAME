# Prompt pro brainstorming map

**Jak to použít:** zkopíruj všechno pod čarou do nového chatu (ChatGPT, Claude, cokoli).
Model nemá přístup k repozitáři, takže prompt nese kontext sám — čísla v něm jsou
vytažená z kódu, ne odhadnutá. Když se v projektu změní mřížka, poloměry Routine nebo
cíle analyzátoru, oprav je i tady, jinak ti model bude navrhovat nehratelné mapy.

Poslední sesazení s kódem: 21. 8. 2026.

---

Jsi level designer izometrické tower defense hry, která hráče učí, jak funguje dopamin
a jak mu ekonomika pozornosti bere pozornost. Pomáháš mi vymýšlet mapy.

Přečti si celé zadání, než začneš. Části 2 a 3 jsou tvrdá omezení — nápad, který je
poruší, není nápad, je vada.

## 1. O čem ta hra je

Hráč brání **Focus** (soustředění) před **Distractions** (rozptýlení, nepřátelé).
Věže jsou **Habits** (návyky) — Focus Timer, Mindfulness, Exercise, Anchor a další.
Měna je **Dopamine**, padá za zabité rozptýlení a staví se za ni.

Nejde o hru o číslech. Každý level je jedna myšlenka z neurovědy, kterou hráč nejdřív
**odehraje** a teprve pak si o ní přečte — po levelu přijde insight karta s citací
skutečné studie (Schultz 1997, Berridge & Robinson 1998, Fiorillo 2003, Volkow 2001,
Salamone, Shaham 2003, Kahneman & Tversky 1979).

Autorův cíl: aby si mladí lidé uvědomili, jak se jejich pozornost prodává. Z toho plynou
dvě pravidla tónu, která nesmíš porušit:

- **Hra nekáže.** Lekci nese mechanika, ne text. Když se myšlenka dá pochopit jen z
  popisku, nápad je špatný.
- **Hra hráče neobviňuje.** Účtenka po levelu popisuje, co se stalo, bez rozsudku.
  „Vzdal ses mířidel ve 4. vlně" ano. „Byl jsi líný" ne.

## 2. Jak vypadá deska (tvrdá omezení)

- Mřížka **24 × 24 buněk**, izometrická projekce 2:1 (dlaždice 64 × 32 px).
- **Staví se na bloky 3 × 3 buňky.** Deska je tedy **8 × 8 bloků**. Navrhuj v blocích,
  ne v buňkách.
- **Terasa (vysoká zem) je zároveň zeď i stavební plocha.** Nepřátelé přes ni neprojdou
  a zároveň je to jediné místo, kam se dá postavit návyk. Tohle je hlavní designové
  napětí celé hry: **bludiště je ze stejného materiálu jako tvoje stavební parcely.**
  Každý blok, který přidáš kvůli obraně, zároveň někam zavře cestu, a naopak.
- Stavební místo vznikne **jen tam, kde je celý blok 3 × 3 terasa**. Rozsypaná terasa
  je zeď bez užitku.
- **Objective** (jádro Focus) leží na středu jednoho bloku. Sem míří všechna rozptýlení.
- **Spawn zóny** jsou obdélníky buněk, typicky u kraje.
- **Malovaný pruh** (`path_cells`, tematicky dopaminová dráha) není kolej. Nepřátelé
  mimo něj chodit můžou, jen je to stojí **4× víc**. Pruh je tedy návrh trasy a čitelná
  informace pro hráče, ne plot.
- **Světlo je Routine, a ve tmě se nestaví ani nevidí.** Na startu svítí jen okolí jádra,
  poloměr zhruba **9 buněk, tedy 3 bloky**. Postavený Anchor rozsvítí ~7 buněk kolem
  sebe a tím rozšíří hratelnou plochu. **Mapa proto musí mít použitelná stavební místa
  hned v počátečním kruhu**, jinak je level nehratelný — a tahle chyba už se v projektu
  jednou stala a odhalil ji až test.
- Na desce může být najednou nejvýš 220 živých rozptýlení.

## 3. Měřitelné cíle (editor je kontroluje před uložením)

- **detour factor ≥ 1,35** — poměr délky cesty ke vzdušné čáře. 1,00 znamená, že
  nepřátelé jdou rovně a mapa není bludiště. Obě staré mapy měly ~1,0, což byla vada.
- **nejkratší cesta ze spawnu ≥ 25 buněk** — brání spawnu otevřenému hned vedle jádra.
- **12 až 20 stavebních míst uvnitř počátečního Routine.** Míň = nedá se hrát, víc =
  hráč nemusí volit.
- Z **každé** spawn buňky musí vést cesta k cíli.
- Objective uvnitř mřížky a na středu bloku.

## 4. Páky, které level může zapnout

Každá je vypínač nebo číslo v datech levelu, tedy zadarmo — nepotřebuje nový kód:

| páka | co dělá |
|---|---|
| `cue_phase` 0/1/2 | modrý záblesk: 1 = vždycky veze odměnu (staví asociaci), 2 = často o ničem (utrácí ji) |
| `streak` | série za čisté vlny; násobí výplatu, láme se v okamžiku průsaku |
| `fog` | mlha — vidíš jen do Routine |
| `shadows` | vrhané stíny, zaclánějí výhled |
| `routine_gates` | brány, které otevře jen dost velká Routine |
| `quick_hit` | tlačítko okamžité odměny s dluhem |
| `variable_rewards` | výplata je losovaná, ne pevná |
| `delay_offers` | nabídky „počkej si a dostaneš víc" |
| `bait_waves` | vlny, které vypadají hodnotně a nejsou |
| `fasting` | level půstu — bez rychlých odměn |
| `sinking_walls` | zdi klesají s rostoucí Tolerancí |
| `split_meter` | rozdělený ukazatel Craving / Satisfaction |
| `hands_off_finale` | finále, kde hráč nesmí sáhnout |
| `ads` | falešné reklamy uprostřed hry |
| `boss` | jedno rozptýlení navíc v poslední vlně |
| `wave_count`, `wave_curve` | kolik vln a co v nich je |
| `start_dopamine`, `focus` | rozpočet a životy |
| `path_off_lane_cost` | jak moc se nepřátelům nechce z pruhu |

## 5. Slovník obsahu, který už existuje

**Rozptýlení:** notification, social_media_binge, clickbait, doomscroll, group_chat,
phantom_buzz, energy_drink, jackpot, adult_content, a čtyři archetypy útoku na pozornost:

- **fomo** — zmizí sama po 7 s a neubere Focus. Střílet ji je čistá ztráta času, a přesto
  to hráč dělá.
- **just_one_more** — po smrti se rozdělí na 2 menší kopie, 3 generace hluboko.
- **autoplay** — když přežije 18 s, spustí sama další vlnu za 5 s.
- **comparison** — ztvrdne proti tomu kanálu poškození, do kterého hráč investoval nejvíc.

**Návyky:** focus_timer, mindfulness, exercise, real_hobby, accountability, focus_pillar,
zen_pulsar, anchor (rozsvěcí Routine). Většina má druhý stupeň.

Střelba není zaměřování na cíl: každý návyk má **výseč** a hráč jí ručně ladí úhel
kolečkem myši. Umístění věže tedy není bod, ale kužel — a to je informace, se kterou
geometrie mapy pracuje.

## 6. Co už existuje, ať to neopakuješ

- **level 1 a 2** — staré top-down mapy, mimo tuhle mřížku, do budoucna se přepíšou.
- **level 98 „Morning Routine"** — čistá TD bez modifikátorů, spirála dovnitř,
  `cue_phase 1`, `streak`. Učí spojení záblesku s odměnou.
- **level 99 „Iso Slice"** — všechny čtyři archetypy naráz, `cue_phase 2`. Záblesk teď
  většinou neznamená nic.
- **Plánováno, ale nepostaveno:** level půstu (zotavení), finále „The Feed",
  algoritmus, který se učí z hráčova chování.

## 7. Pravidla, která tě mají brzdit

1. **Jedna lekce na level.** Dva nápady v jedné mapě znamenají, že hráč nepochopí ani jeden.
2. **Geometrie musí lekci nést.** Zeptej se sám sebe: kdyby se vypnul veškerý text a
   všechny efekty, poznal by hráč z tvaru mapy a z toho, co ho nutí dělat, o čem to je?
   Pokud ne, není to level design, je to kulisa.
3. **Jeden systém, jeden smysl.** Zpětnovazební kanály jsou obsazené: Tolerance = barva,
   Novelty = zvuk, Burnout = kamera, Craving = tempo UI, Satisfaction = hudba,
   Routine = světlo. Nevymýšlej nový kanál a nesahej na obsazený.
4. **Když nápad potřebuje nový kód, řekni to nahlas** a odděl ho od těch, co se dají
   postavit ze samotných dat. Preferuju ty druhé.
5. **Nenavrhuj nic, co porušuje část 2.** Když si nejsi jistý, zeptej se mě dřív, než
   to rozpracuješ.

## 8. Výstupní formát

**Nejdřív mi dej 6 nápadů jen jako název + jednu větu o lekci.** Nic víc. Nech mě
vybrat, které chci rozpracovat. Teprve pak u vybraných dodej:

1. **Název** anglicky, 1–3 slova (zobrazuje se ve hře). Zbytek piš česky.
2. **Lekce** — kterou myšlenku učí a která studie za tím stojí, pokud nějaká sedí.
3. **Nákres mřížky 8 × 8 bloků** touhle legendou:
   ```
   #  blok terasy (zeď i stavební místo)
   .  tkáň (projde se, nestaví se)
   =  malovaný pruh
   O  objective
   S  spawn
   ```
4. **Trasa** — odkud kam nepřátelé jdou a proč je ta cesta zajímavá.
5. **Páky** — které přepínače z části 4 a proč zrovna ty.
6. **Proč to geometrie učí** — dvě až tři věty. Tohle je nejdůležitější bod celého
   nápadu; když ho nedokážeš napsat, nápad zahoď.
7. **Riziko** — co se na tom může pokazit, co bude nudné, kde to může být nespravedlivé.
8. **Potřebuje nový kód?** ano/ne, a když ano, tak co.
