# Pathfinding, multi-směr, segmenty, brainfog
Pořadí je podle poměru užitek/práce. NEMĚŇ ho.

VŠECHNY testy: scripts/_test_*.gd + scenes/_test_*.tscn podle "Verification pattern"
v docs/REFACTOR_PLAN.md. NEINSTALUJ GUT ani GdUnit4. Spouštění přes --main-scene.

## P0 — zdroj pravdy mapy: ASCII vs. bakování
Model: opus
Needs-me: yes
Status: done
ROZHODNUTO: varianta B (ASCII jako bezztrátový side-car, .tres zůstává
autoritativní). Viz P0b. Analýza je v BLOCKED.md.
Analýza do BLOCKED.md: může být ASCII autoritativní formát, ze kterého MapEditor
čte i zapisuje, a bakování do .tres být jen odvozený artefakt? Co z LevelData se
do ASCII nevejde? Rozsah zásahu do td_level_designer? Neimplementuj.

## P0b — ASCII side-car (varianta B)
Model: sonnet
Needs-me: no
Status: done

.tres zůstává autoritativní. ASCII je odvozený, bezztrátový side-car pro čtení
a git diffy. Nikdy se z něj nečte do hry.

Rozsah: vlastní právě to, co dnes vlastní _bake_to_level() — high_ground,
objective, path_cells. NIC jiného. decor a tile_overrides do ASCII nepatří
a nesmí se do něj pokoušet vejít.

1. tools/level_to_ascii.py — vygeneruje docs/levels/<id>.md pro každý level.
   14 řádků po 30 znacích + hlavička s ID a rozměry.
   path_cells jako SEZNAM, ne množina — duplicita (Vector2i(25,2) v level_98)
   se musí v side-caru objevit, ne tiše zmizet. Když ji ASCII mřížka vyjádřit
   neumí, vypiš ji do sekce pod mřížkou.

2. Round-trip test _test_ascii_sidecar: parse vygenerovaného ASCII zpět a porovnej
   s originálem po jednotlivých polích. Musí projít na VŠECH levelech včetně
   level_98. Nezarovnané spawn rekty (Rect2i(0,5,1,4), Rect2i(0,6,1,2)) NEODVOZUJ
   z bloků — pokud je čtečka neumí, patří do sekce pod mřížkou, ne do mřížky.

3. Hook: po _bake_to_level() se side-car přegeneruje. Pokud to znamená zásah
   do tools/map_editor.gd, udělej ho tam — addon je view a nesahej na něj.

4. Do verify.sh přidej kontrolu, že side-cary v docs/levels/ odpovídají
   aktuálním .tres (jako se dnes kontroluje ROSTER.md).

Hotovo když: round-trip projde na všech levelech, verify.sh chytí ručně
rozhozený side-car, a docs/levels/ je v gitu s čitelnými diffy.

NEDOTÝKEJ SE pěti dalších nástrojů, které zapisují geometrii
(build_placeholder_level.gd, refit_levels.py, regrid_levels.py,
build_level_first.py, build_level_iso.py). Side-car je jednosměrný,
takže je nemusí řešit — jen zkontroluj, že to tak opravdu je,
a když ne, zapiš do BLOCKED.md.

## P0c — duplicita v path_cells
Model: sonnet
Needs-me: no
Status: done

level_98.tres má Vector2i(25, 2) v path_cells dvakrát. Zjisti, jestli je to
záměr (ovlivňuje losování variant dlaždic) nebo chyba při bakování.
Pokud chyba: oprav bake tak, aby duplicity nevznikaly, a přidej validaci
do verify.sh přes všechny levely.
Pokud záměr: zdokumentuj do docs/EDITOR_GUIDE.md, proč tam je.
Nález zapiš do PROGRESS.md tak jako tak.

## P0d — úklid iso legacy
Model: sonnet
Needs-me: no
Status: done

scripts/_test_iso_math.gd a scripts/_test_game_iso_slice.gd nemají .tscn,
takže se nespouštějí. Iso projekce je pryč.
1. Smaž oba skripty včetně .gd.uid sidecarů.
2. Z CLAUDE.md odstraň výjimku o přejmenování na _test_legacy_iso_* — je splněná
   jinak, než zněla. Nahraď ji poznámkou, že iso fixtures byly odstraněny při
   migraci na top-down (datum, commit).
3. Klauzuli _test_legacy_* ve verify.sh NECH, ale připiš k ní komentář, že
   momentálně netrefuje nic a je připravená pro budoucí použití.
4. Přidej do verify.sh kontrolu: každý scripts/_test_*.gd musí mít odpovídající
   scenes/_test_*.tscn. Osiřelý skript = FAIL, ne ticho.

Hotovo: verify.sh chytí uměle vytvořený osiřelý _test_ skript.

## P0e — inventura known-broken
Model: sonnet
Needs-me: no
Status: todo

Pět testů padá. Vytvoř docs/KNOWN_BROKEN.md a u každého napiš, co přesně
selhává, od kdy (git blame / bisect na první červený commit), a do které
z těchto tří tříd patří:
  - očekávání artu (test čeká sprite, který po přechodu na plochý terén neexistuje)
  - chybějící textura
  - skutečná regrese v logice

Zajímá mě hlavně _test_shadow_occlusion: 'Cannot call method get_size on a null
value' znamená, že textura chybí nebo se přejmenovala. Najdi kterou a proč.

NEOPRAVUJ nic. Jen zjisti a zapiš.
Hotovo: dokument existuje, u každého testu je první červený commit.

## P0f — verify.sh rozlišuje known-broken
Model: sonnet
Needs-me: no
Status: todo

verify.sh dnes vrací PASS s pěti padajícími testy. To je nebezpečné — nová
regrese v nich zapadne.
Zaveď seznam known-broken (soubor nebo hlavička v testu) a chovej se takto:
  - known-broken test padá → KNOWN FAIL, nezvyšuje exit kód
  - known-broken test PROJDE → FAIL s hláškou "oprav se sám, vyřaď ze seznamu"
  - test mimo seznam padá → FAIL

POZNÁMKA K SOUČASNÉMU STAVU (zjištěno při zadávání, ověř si to sám):
verify.sh už dnes má pole KNOWN_BROKEN_TESTS a první i třetí pravidlo splňuje.
Chybí JEN druhé: když known-broken test projde, verify.sh vypíše
"PASS <name> (was KNOWN-BROKEN — remove it from verify.sh's list)" a započítá
ho do pass, tedy neselže. Pozor na _test_phase3, který je v tom poli veden jako
flaky, ne rozbitý — na něm by nové pravidlo padalo obden. Rozhodni, jestli
flaky potřebuje vlastní kategorii, a když ano, zapiš to do BLOCKED.md.

## P1 — flow field od cíle
Model: opus
Needs-me: no
Status: todo
Jeden distance field BFS od cíle, gradient dává směr, všechny jednotky čtou totéž.
Hotovo: _test_flowfield ověří klesající gradient z každé volné buňky k cíli
a že nedosažitelné buňky nemají záznam. Bench: přepočet pod 5 ms na největší mapě.

## P2 — anti-block validace zdí
Model: opus
Needs-me: no
Status: todo
Zeď nesmí odříznout žádný aktivní spawn. Union-find nebo lokální re-BFS.
Hotovo: _test_antiblock projede každou legální pozici a ověří obojí směr.
Bench: kontrola jedné zdi pod 1 ms.

## P3 — dirty-region přepočet
Model: sonnet
Needs-me: no
Status: todo
Hotovo: výsledek je bit-identický s full rebuildem (to je ten test) a je rychlejší.

## P4 — jednotky na flow fieldu
Model: sonnet
Needs-me: no
Status: todo
Pozice je Vector2 na mřížce, NE vzdálenost podél cesty (dřívější zadání platilo
jen pro jednu cestu). Zaměřování = rozsahový dotaz nad prostorovým hashem.
Hotovo: regresní testy ekonomiky zelené, bench zopakován do docs/PERF.md.

## P5 — MultiMeshInstance2D
Model: sonnet
Needs-me: no
Status: todo
Hotovo: bench N=500 aspoň 3x rychlejší než baseline.

## P6 — SpawnPointData a více spawnů
Model: sonnet
Needs-me: no
Status: todo
cell, direction_id, active_from_wave, requires_segment, telegraph_lead_time.
Field se NEMĚNÍ. Hotovo: _test_multispawn ověří cestu z každého spawnu v každé wave.

## P7 — telegraf směru
Model: sonnet
Needs-me: no
Status: todo
TVRDÉ PRAVIDLO: telegraf musí být pravdivý. Ohlášený směr = skutečný směr.
Hotovo: _test_telegraph ověří aktivaci právě po telegraph_lead_time a právě
na ohlášené pozici.

## P8 — MapSegmentData a skládání levelů
Model: opus
Needs-me: yes
Status: todo
ČEKÁ NA P0. Level N+1 = LevelData N + segment, odkazem ne kopií.
Hotovo: _test_segments ověří, že KAŽDÁ kombinace odemčených segmentů dá validní
dokončitelnou mapu a že skládání je deterministické.

## P8b — fog_bandwidth před P9
Model: opus
Needs-me: no
Status: todo

_test_fog_bandwidth hlásí, že arc nemá vliv na osvětlenou plochu (36 → 36 buněk
při arc 15 → 120) a že otočení habitu světlem nehne. Podle P0e zjisti, jestli je
mrtvý parametr, nebo se osvětlení počítá jinak než z kužele.
Oprav to, ať už je příčina jakákoli. P9 staví na tomhle a nechci stavět na systému,
o kterém nevím, jestli funguje.
Hotovo: test zelený, vyřazený z known-broken, a v PROGRESS.md je popsaná příčina.

## P9 — brainfog jako vizuál
Model: sonnet
Needs-me: no
Status: todo
Dva SubViewporty sdílející World2D, maska přes ViewportTexture. Herní logika beze změny.
Hotovo: screenshoty do .dev/screenshots/ včetně rozostřené a odbarvené. NEPOSUZUJ.

## P10 — brainfog jako pravidlo
Model: sonnet
Needs-me: yes
Status: todo
Až potvrdím po zahrání P9. visible grid + explored grid, věž cílí jen visible.
Hotovo: _test_fog ověří, že věž nikdy nestřílí do ne-visible a explored se nezmenší.

## P11 — Quick Hit a Tolerance na mlhu
Model: sonnet
Needs-me: no
Status: todo
Quick Hit prosvětlí, Tolerance zmenšuje poloměr. Obojí přes ModifierManager.
Hotovo: _test_fog_modifiers na hraničních hodnotách Tolerance 0 a 100.

## P12 — minimapa
Model: sonnet
Needs-me: no
Status: todo
Ukazuje explored terén, ne jednotky.
Hotovo: test, že minimapa nikdy neukáže víc než explored.
