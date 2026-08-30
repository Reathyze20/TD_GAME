## S1 — Charakterizační testy ekonomiky
Zmapuj, jak se počítá dopamine, jak ho ovlivňuje Tolerance a Streak, jak Quick Hit
zasahuje do obojího. Napiš testy, které zafixují SOUČASNÉ chování včetně hranic.
Hotovo když: 20+ testů, všechny zelené. Chování neměň.

## S2 — Deterministický simulátor levelu
Model: opus
Headless simulátor, který odehraje level bez renderu podle skriptu rozhodnutí
(kam postavit co, kdy zmáčknout Quick Hit) a vrátí výsledek: přežil/padl,
zbývající Focus, konečná Tolerance, celkový dopamine. Seedovaný, deterministický.
Hotovo když: dvakrát spuštěný stejný seed dá bit-identický výsledek.

## S3 — Report o balanci
Pomocí S2 projeď každý level třemi strategiemi (nic nestavět / stavět levné věže
rovnoměrně / spamovat Quick Hit) a zapiš výsledky do docs/BALANCE.md.
Hotovo když: tabulka level × strategie × výsledek. Nedělej závěry, jen data.

## S4 — Palette-swap shader
Shader v shaders/, který mapuje master paletu na alternativní sadu. Použitelný
na sprity distractions. Přidej testovací scénu se třemi variantami stejného spritu.
Hotovo když: scéna existuje, screenshot ukazuje tři barevné varianty.

## S5 — Datová vrstva pro hordy
Přepiš stav nepřátel z uzlů na pole struktur: pozice = vzdálenost podél cesty,
pole seřazené, zaměřování jako rozsahový dotaz. Vykreslování zatím neřeš.
Hotovo když: S1 testy zelené, bench z T11 zopakovaný a zapsaný do PERF.md.

## S6 — Vykreslování hordy přes MultiMeshInstance2D
Model: opus
Nahraď jeden-uzel-na-nepřítele jedním MultiMeshInstance2D na hordu.
Hotovo když: bench pro N=500 aspoň 3× rychlejší než baseline, testy zelené.

## S7 — Tvar spawnu ve waves
Model: opus
Přidej do wave resource pole pro tvar spawnu (souvislý proud / shluky / náhlá
vlna) a počty v desítkách až stovkách. Zachovej validaci, přegeneruj ROSTER.md.
Hotovo když: validátor projde, S2 simulátor odehraje všechny levely bez chyby.

## S8 — Save/load round-trip
Testy, které ověří, že uložený a načtený stav hry je identický: rozestavěné věže,
Tolerance, dopamine, postup vlnou, MetaProgression.
Hotovo když: property-based test s náhodnými stavy, 100 iterací, žádný rozdíl.

## S9 — Úklid podle vlastních pravidel
Projdi scripts/ proti pravidlům v CLAUDE.md. Vypiš do docs/DEBT.md každé porušení:
chybějící typové hinty, hardcoded hodnoty místo @export, přímé $Node cesty místo
signálů, Godot 3 idiomy. Oprav ta, která jsou mechanická a testy zůstanou zelené;
ostatní jen vypiš.
Hotovo když: DEBT.md existuje, verify.sh projde.