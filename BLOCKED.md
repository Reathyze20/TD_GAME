# Blocked

Design decisions found ambiguous or contradictory during autonomous runs.
Not fixed by guessing — recorded here with options, then moved past.

## T1 (docs/refactor/MIGRATION.MD) — "Nainstaluj GUT pro Godot 4 do addons/. Založ tests/."

Conflicts with CLAUDE.md's "Testy jsou smlouva" section, which is explicit and detailed
about this project deliberately NOT using GUT: "v repu není `tests/` adresář ani GUT
(`addons/gut` neexistuje, nikde v repu není zmínka o něm)." It documents an established
alternative instead — `scripts/_test_*.gd` + `scenes/_test_*.tscn` pairs, run via
`--main-scene`, with a `completed := false` sentinel + `Timer` watchdog — with a whole
list of existing fixtures already built on it and a hard rule not to rename/disturb them
without reason.

verify.sh (T0, this session) was built to drive exactly that existing pattern, per
CLAUDE.md's own instructions on what to read for testing work
(docs/REFACTOR_PLAN.md "Verification pattern"). Installing GUT and founding `tests/`
alongside it would mean two parallel, disconnected test frameworks in the same repo,
with `verify.sh` blind to whichever one it doesn't drive.

**Options:**
1. Skip the GUT/`tests/` part of T1 entirely; keep the existing `_test_*` harness
   pattern as the only test framework, and treat T1 as satisfied by verify.sh's CI
   wiring alone. Lowest-risk, no new dependencies, consistent with CLAUDE.md as
   written today.
2. Install GUT for future tasks (T2, S1, etc. all say "napiš testy" without specifying
   a framework) while leaving existing `_test_*` fixtures untouched, and update
   verify.sh to run both. Doubles the testing surface and contradicts CLAUDE.md's
   explicit "v repu není GUT" unless that section is rewritten to reflect the change.
3. Migrate everything to GUT, retiring the `_test_*.gd`/`_test_*.tscn` pattern. Highest
   effort, touches 20 existing fixtures explicitly protected by CLAUDE.md
   ("neruš, nepřejmenovávej bez důvodu"), and reverses a documented architectural
   decision without being asked to.

**What I did:** proceeded with option 1 for now (no GUT installed, no `tests/` founded).
New tests for T2 onward will use the existing `_test_*.gd`/`_test_*.tscn` pattern that
verify.sh already drives. Added `.github/workflows/ci.yml` running `verify.sh` as T1's
other half. A live "zelený běh v CI" per T1's own done-criterion can't be confirmed from
here without pushing, which the branch rules in CLAUDE.md forbid — flagging that gap
rather than silently marking T1 complete.
