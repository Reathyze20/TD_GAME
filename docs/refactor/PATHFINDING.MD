# Pathfinding, multi-směr, segmenty, brainfog
Pořadí je podle poměru užitek/práce. NEMĚŇ ho.

VŠECHNY testy: scripts/_test_*.gd + scenes/_test_*.tscn podle "Verification pattern"
v docs/REFACTOR_PLAN.md. NEINSTALUJ GUT ani GdUnit4. Spouštění přes --main-scene.

## P0 — zdroj pravdy mapy: ASCII vs. bakování
Model: opus
Needs-me: yes
Status: blocked
Analýza do BLOCKED.md: může být ASCII autoritativní formát, ze kterého MapEditor
čte i zapisuje, a bakování do .tres být jen odvozený artefakt? Co z LevelData se
do ASCII nevejde? Rozsah zásahu do td_level_designer? Neimplementuj.

## P1 — flow field od cíle
Model: opus
Needs-me: yes
Status: todo
Jeden distance field BFS od cíle, gradient dává směr, všechny jednotky čtou totéž.
Hotovo: _test_flowfield ověří klesající gradient z každé volné buňky k cíli
a že nedosažitelné buňky nemají záznam. Bench: přepočet pod 5 ms na největší mapě.

## P2 — anti-block validace zdí
Model: opus
Needs-me: yes
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
