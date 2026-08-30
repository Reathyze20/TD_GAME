# Migrace izometrie → top-down

## T1 — Ověřovací síť
Model: sonnet
Needs-me: yes
Status: blocked
BLOCKED.md:302 — GUT/`tests/` odmítnuto (koliduje s CLAUDE.md „Testy jsou smlouva"),
`.github/workflows/ci.yml` přidán. Zbývá jen potvrdit zelený běh v CI, což vyžaduje
push, který si session sama zakazuje — proto čeká na tebe.
Nainstaluj GUT pro Godot 4 do addons/. Založ tests/. Ověř, že ./verify.sh vrací 0
u čistého stavu a nenulový kód u úmyslně rozbitého .tres (zkus a vrať zpět).
Přidej .github/workflows/ci.yml, který pouští ./verify.sh.
Hotovo když: ./verify.sh projde a v CI je zelený běh.

## T2 — Regresní testy stávajícího chování
Model: sonnet
Needs-me: no
Status: done
`scripts/_test_economy_characterization.gd`, commit `4d3f3c7`.
Najdi implementaci Tolerance, Quick Hit a ekonomiky dopaminu. Napiš testy, které
zafixují SOUČASNÉ chování včetně hranic 0 a 100. Tyto testy jsou smlouva —
při migraci se nesmí měnit, jen musí zůstat zelené.
Hotovo když: aspoň 15 testů, všechny zelené.

## T3 — Inventura perspektivy (READ-ONLY, nic neměň)
Model: opus
Needs-me: no
Status: done
`docs/MIGRATION_AUDIT.md` existuje.
Napiš docs/MIGRATION_AUDIT.md: každé místo v kódu, které převádí souřadnice
mapy na obrazovku a zpět; jestli jsou bakované levely v data/ závislé na
perspektivě; jestli je Y-sorting nebo elevace herní mechanika, nebo jen vizuál;
jestli má výška („High ground") vliv na dosah nebo jen název.
Hotovo když: dokument existuje a vyjmenovává konkrétní soubory a řádky.

## T4 — Souřadnicová abstrakce
Model: opus
Needs-me: no
Status: done
`scripts/grid_projection.gd` existuje a je jediný převodník mřížka↔obrazovka v repu.
Zaveď jednu vrstvu (scripts/GridProjection.gd), přes kterou tečou VŠECHNY převody
mřížka↔obrazovka. Zatím se chová izometricky — chování se nemění.
Hotovo když: T2 testy zelené a v kódu není žádný jiný převod souřadnic.

## T5 — Top-down projekce
Model: sonnet
Needs-me: yes
Status: done
BLOCKED.md:339 — zastaveno na vizuálním posouzení (rozlišení, HUD, styl terénu),
vyřešeno přímým pokynem uživatele: `26814f9` aktivoval MODE_SQUARE, smazal
pre-migrační levely a nastavil project.godot na 480x270/integer scale/Nearest
(ověřeno v project.godot). ./verify.sh prochází, hra běží.
Přidej do GridProjection čtvercovou variantu a přepni na ni. Nastav project.godot:
base resolution 480x270, integer scaling, Nearest filter.
Hotovo když: T2 testy zelené, hra se spustí, ./verify.sh projde.

## T6 — Migrace bakovaných levelů
Model: sonnet
Needs-me: yes
Status: obsolete
BLOCKED.md:259 — uživatel se rozhodl (v rámci T5) pre-migrační levely smazat, ne
migrovat. Migrovat tedy není co; validátor (T10) a ROSTER.md už jsou nezávisle
splněné pro oba levely, které dnes existují.
Napiš tools/migrate_levels.py, který převede levely v data/ na novou mřížku.
Zachovej topologii cesty. Přidej test, který u každého migrovaného levelu ověří,
že cesta je souvislá a vede od spawnu k Focusu.
Hotovo když: všechny levely projdou validátorem, ROSTER.md přegenerovaný.

## T7 — Testy čitelnosti (bez posuzování)
Model: sonnet
Needs-me: yes
Status: done
BLOCKED.md:202 — potřeboval uživatelovo svolení k výjimce z `.gitignore` pro
`.dev/screenshots/`. Implementováno jako `scripts/_shot_readability.gd`, commit
`d717061`.
Rozšiř dev screenshot skript o tři varianty: rozostřenou, odbarvenou, siluetovou.
Vygeneruj sadu pro každý level do .dev/screenshots/ a commitni.
Hotovo když: obrázky existují. NEPOSUZUJ je — to udělám já.

## T8 — STOP
Model: sonnet
Needs-me: no
Status: done
BLOCKED.md:202 — session přeběhla tenhle checkpoint bez zastavení; souhrn dopsán
zpětně tamtéž. `addons/td_level_designer/` nebyl dotčen po celou dobu.
Zapiš do PROGRESS.md souhrn a skonči. addons/td_level_designer/ se NEDOTÝKEJ.

## T9 — Vlastnosti cesty jako testovatelný modul
Model: sonnet
Needs-me: no
Status: done
`scripts/path_metrics.gd` + `_test_path_metrics.gd` existují.
Vytáhni logiku cesty do samostatného modulu: délka, souvislost, vzdálenost podél
cesty, dotaz „která pozice je ve vzdálenosti X". Nezávisí na renderu.
Hotovo když: 20+ testů, včetně degenerovaných případů (cesta délky 1, cesta
vedoucí zpět přes sebe, slepá odbočka).

## T10 — Detekce nevalidních bludišť
Model: sonnet
Needs-me: no
Status: done
`scripts/level_validator.gd` + `_test_maze_validity.gd`, běží ve verify.sh.
Napiš validátor, který u každého levelu ověří, že hráč nemůže cestu úplně
zazdít, a že po každém legálním umístění zdi existuje cesta ze spawnu k Focusu.
Přidej test pro každý level v data/.
Hotovo když: validátor běží ve verify.sh a všechny levely projdou.

## T11 — Bench pro hordy
Model: sonnet
Needs-me: no
Status: done
`docs/PERF.md` existuje s naměřenými čísly (1000 distrakcí = 88ms/11 FPS baseline,
citováno v S5/S6 BLOCKED.md entry).
Benchmark scéna: N nepřátel na cestě, měř průměrný frametime pro N = 50, 100,
200, 500, 1000. Zapiš výsledky do docs/PERF.md jako tabulku.
Hotovo když: dokument existuje s naměřenými čísly. NEOPTIMALIZUJ.
