## Q2 — Quick Hit analýza (PRVNÍ)
Model: opus
Needs-me: yes
Status: todo
Přes S2 simulátor odehraj první tři levely čtyřmi strategiemi (nic / habity /
spam Quick Hit / kombinace). Vypiš pro každou přežil/Focus/Tolerance/dopamine.
Odpověz: je spam Quick Hitu objektivně nejlepší tah? Když ne, o kolik zaostává.
Navrhni změnu čísel v data/, ale NIC NEMĚŇ. Analýza do BLOCKED.md.

## P2 — anti-block validace zdí
Model: opus
Needs-me: no
Status: todo
Union-find nebo re-BFS. Zeď nesmí odříznout žádný aktivní spawn.
Hotovo: _test_antiblock projede každou legální pozici obojím směrem.
Bench: kontrola zdi pod 1 ms. Změř přepočty/s při rychlém stavění → PERF.md.

## P4 — jednotky na flow fieldu
Model: sonnet
Needs-me: no
Status: todo
Pozice = Vector2 na mřížce (NE vzdálenost podél cesty). Zaměřování = rozsahový
dotaz nad prostorovým hashem. Vyřeš i _test_suppression z KNOWN_BROKEN.
Hotovo: testy ekonomiky zelené, _test_suppression zelený, bench do PERF.md.

## P5 — MultiMeshInstance2D
Model: sonnet
Needs-me: no
Status: todo
Hotovo: bench N=500 aspoň 3x rychlejší než baseline.

## Q1 — time control
Model: sonnet
Needs-me: no
Status: todo
Rychlosti 0.25/1/2/4x, pauza s příkazy, skip vlny, staty na hover.
Hotovo: _test_timecontrol — 4x dá bit-identický výsledek jako 1x.

## _test_shadow_occlusion — oprava testu
Model: sonnet
Needs-me: no
Status: todo
Test selhává, protože CORE_ROOTLINE_RADIUS se zmenšil. Regrese v testu,
ne v systému. Oprav referenční hodnoty, vyřaď z REQUIRES_DISPLAY/known-broken.