# Migrace izometrie → top-down

## T1 — Ověřovací síť
Nainstaluj GUT pro Godot 4 do addons/. Založ tests/. Ověř, že ./verify.sh vrací 0
u čistého stavu a nenulový kód u úmyslně rozbitého .tres (zkus a vrať zpět).
Přidej .github/workflows/ci.yml, který pouští ./verify.sh.
Hotovo když: ./verify.sh projde a v CI je zelený běh.

## T2 — Regresní testy stávajícího chování
Najdi implementaci Tolerance, Quick Hit a ekonomiky dopaminu. Napiš testy, které
zafixují SOUČASNÉ chování včetně hranic 0 a 100. Tyto testy jsou smlouva —
při migraci se nesmí měnit, jen musí zůstat zelené.
Hotovo když: aspoň 15 testů, všechny zelené.

## T3 — Inventura perspektivy (READ-ONLY, nic neměň)
Model: opus
Napiš docs/MIGRATION_AUDIT.md: každé místo v kódu, které převádí souřadnice
mapy na obrazovku a zpět; jestli jsou bakované levely v data/ závislé na
perspektivě; jestli je Y-sorting nebo elevace herní mechanika, nebo jen vizuál;
jestli má výška („High ground") vliv na dosah nebo jen název.
Hotovo když: dokument existuje a vyjmenovává konkrétní soubory a řádky.

## T4 — Souřadnicová abstrakce
Model: opus
Zaveď jednu vrstvu (scripts/GridProjection.gd), přes kterou tečou VŠECHNY převody
mřížka↔obrazovka. Zatím se chová izometricky — chování se nemění.
Hotovo když: T2 testy zelené a v kódu není žádný jiný převod souřadnic.

## T5 — Top-down projekce
Přidej do GridProjection čtvercovou variantu a přepni na ni. Nastav project.godot:
base resolution 480x270, integer scaling, Nearest filter.
Hotovo když: T2 testy zelené, hra se spustí, ./verify.sh projde.

## T6 — Migrace bakovaných levelů
Napiš tools/migrate_levels.py, který převede levely v data/ na novou mřížku.
Zachovej topologii cesty. Přidej test, který u každého migrovaného levelu ověří,
že cesta je souvislá a vede od spawnu k Focusu.
Hotovo když: všechny levely projdou validátorem, ROSTER.md přegenerovaný.

## T7 — Testy čitelnosti (bez posuzování)
Rozšiř dev screenshot skript o tři varianty: rozostřenou, odbarvenou, siluetovou.
Vygeneruj sadu pro každý level do .dev/screenshots/ a commitni.
Hotovo když: obrázky existují. NEPOSUZUJ je — to udělám já.

## T8 — STOP
Zapiš do PROGRESS.md souhrn a skonči. addons/td_level_designer/ se NEDOTÝKEJ.

## T9 — Vlastnosti cesty jako testovatelný modul
Vytáhni logiku cesty do samostatného modulu: délka, souvislost, vzdálenost podél
cesty, dotaz „která pozice je ve vzdálenosti X". Nezávisí na renderu.
Hotovo když: 20+ testů, včetně degenerovaných případů (cesta délky 1, cesta
vedoucí zpět přes sebe, slepá odbočka).

## T10 — Detekce nevalidních bludišť
Napiš validátor, který u každého levelu ověří, že hráč nemůže cestu úplně
zazdít, a že po každém legálním umístění zdi existuje cesta ze spawnu k Focusu.
Přidej test pro každý level v data/.
Hotovo když: validátor běží ve verify.sh a všechny levely projdou.

## T11 — Bench pro hordy
Benchmark scéna: N nepřátel na cestě, měř průměrný frametime pro N = 50, 100,
200, 500, 1000. Zapiš výsledky do docs/PERF.md jako tabulku.
Hotovo když: dokument existuje s naměřenými čísly. NEOPTIMALIZUJ.