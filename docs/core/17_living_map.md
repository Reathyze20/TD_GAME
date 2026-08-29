# 17 — Živá mapa: trody, které se otevřou v čase

*Rozhodnuto a zavedeno 21. 8. 2026. Kód: `scripts/resources/trod_data.gd`,
`game.gd` sekce „living map: trods". Test: `scenes/_test_trod.tscn`.*

## 1. Proč to existuje

Tahle hra je o únosu pozornosti a na tom tématu **není nic, co by se dalo vyřešit
jednou provždy**. Zablokuješ jeden kanál, vrátí se to jiným. Statická mapa tuhle lekci
naučit neumí: hráč postaví bludiště, ono funguje, a level je od té chvíle jen čekání.

Trod, který se otevře uprostřed levelu, je ta lekce udělaná mechanikou. Jméno je
folklorní termín, který pruhy už používají (`docs/design/fae_theme.md` §5) — trod je
cesta, kterou chodí Fae, a **skutečné trody se posouvají**.

## 2. Co to je a co to NENÍ

`TrodData` = seznam buněk + číslo vlny, ve které se přidají do pruhu.

**Nemění terén.** Otevřít trod znamená jen zlevnit ze `path_off_lane_cost` na 1.0
buňky, přes které horda vždycky mohla přejít. Z objížďky se stane preferovaná cesta.
Dva důsledky, kvůli kterým to takhle je:

- Pod ničím, co hráč postavil, se nemůže objevit ani zmizet zem.
- Trod nemůže udělat level neřešitelným, protože **žádnou cestu neodebírá**.

Terén, který se za běhu opravdu mění, je jiná mechanika a existuje zvlášť — spike
„sinking walls" hned pod trody v `game.gd`.

## 3. Dvě pravidla, bez kterých je to podraz

### 3a. Nová cesta se musí SLÉVAT se starou

Když nový trod vede od spawnu k jádru, aniž by se staré trasy dotkl, hráčova práce za
celý level je k ničemu a level čte jako podvod. Sdílený koncový úsek znamená, že věže
u jádra platí dál a hráč **přesouvá**, místo aby stavěl znovu.

Měří se to **dosahem věže, ne shodou buněk.** První verze testu porovnávala buňky a
spadla na tom, že obě trasy jdou týmž třípolovým koridorem, jen jinými sloupci — vada
byla v měřidle, ne v mapě. Správná otázka zní „dosáhne tam věž, kterou už mám".
Práh je 260 px, nejkratší útočný dosah ve hře (mindfulness): co pokryje ta nejslabší
věž, pokryjí všechny.

Na levelu 98 vychází **12 z 31 buněk** nové trasy v dosahu staré obrany.

### 3b. Telegraf o celou vlnu dřív

`pending_trod()` vrací trod, který se otevře **příští** vlnu, a `_draw_static_field()`
ho kreslí slabě v barvě pruhu. Bez toho je nová cesta hod mincí; s tím je to nejlepší
napětí, jaké TD umí — vidíš, co přijde, a nestíháš.

*Stav: funguje, ale čte se jako plošný nádech, ne jako cesta. Chce to spíš obrys nebo
pulz než výplň — viz `build/_trod_seq.png`, prostřední snímek.*

## 4. Pořadí operací při otevření

Totéž pořadí a z týchž důvodů jako `_set_sunk()`:

1. `_apply_path_weights()` — váhy rozhodují o trasách
2. `_build_path_layer()` — art musí novou cestu ukázat
3. `_compute_path_previews()`
4. `assign_path(d)` pro každou živou distrakci

Krok 4 je past, ne detail: nepřítel drží buněčnou trasu přidělenou při spawnu. Bez
přepočtu by vlna, která už je na desce, celou tu změnu prochodila po staré cestě.

Otevírá se **před** stavbou fronty ve `_start_wave()`, aby tatáž vlna už šla novou
cestou.

## 5. Proč `lane_cells` a ne `level.path_cells`

`level` je hluboká kopie, zapisovat do ní by bylo bezpečné. Oddělené jsou proto, že
odpovídají na dvě různé otázky: `level.path_cells` = „co designér namaloval",
`lane_cells` = „kudy horda právě teď chce chodit". `_build_field()` druhé staví
z prvního, takže restart levelu začne se zavřenými trody.

`_apply_path_weights()` proto nastavuje váhu **každé** buňce, ne jen mimopruhovým.
Dřív lané buňky přeskakovala s tichým předpokladem, že jsou na výchozí 1.0 — pravda,
dokud běžela jednou při startu; nepravda ve chvíli, kdy ji otevření trodu spustí
podruhé.

## 6. Co zbývá

- **Editor**: trody se dnes píšou ručně do `.tres`. Patří do `td_level_designer` jako
  další blokové vrstvy s přepínačem „otevře se ve vlně N" — je to tentýž kus práce jako
  odložené „chunky".
- **Telegraf** čte jako plocha, ne jako cesta (§3b).
- **Zavírání trodu** zatím není. Otevřít i zavřít by byla „cesta se přesunula" místo
  „přibyla", což je jiný pocit a možná lepší.
- **Vyvyšování terénu hráčem** jako odpověď na hrozbu je odložené záměrně: nejdřív ať
  existuje hrozba, pak se pozná, jestli je tohle ta správná odpověď.
