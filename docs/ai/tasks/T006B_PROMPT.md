# T006B — Frontier review fix-up (maps that look natural, AIs that differ, a real late game)

Executor: OpenHands. Author/reviewer: Claude (Tech Lead). Read `AGENTS.md` first.
Branch: keep working on **`oh/T006-frontier`** (PR #7). This commit added the judge
`tests/acceptance/t006b_acceptance.gd` (**read-only for you**) and this file.

## Review verdict on PR #7: CHANGES REQUESTED
What passed: T006 judge 148/148, tests 4627/4627, code policy, smoke. Good engine work
(PrereqUtil, rows maps, hq_type, rules, defensive buildings, heap A*).

What fails the *goal* (a mod that looks natural and plays well) even though the checks pass:
1. **Stamped maps.** Every forest is one of 3–4 identical diamond stamps and every rock is
   one of 2 plus-shaped stamps, all mirror-symmetric. The "river valley" has no river: it is
   one round lake in the middle.
2. **`fr_border_siege` is a byte-for-byte copy of `fr_river_valley`'s terrain** (0 of 2048 tiles differ).
3. **All AIs play the same game.** Owners 1, 2 and 3 have different personalities but the
   same first 8 buildings and nearly the same army.
4. **The late tree is never used.** The duel ends at tick 3600. Nobody builds
   fr_sanctum, fr_dragon_roost or fr_cannon_tower, and nobody fields fr_paladin or fr_wyvern.
5. **Hidden SCRIPT ERROR.** `test_t006_defensive_building_attack_fields` assigns the
   `int` returned by `place_building()` to a `Dictionary`, so it crashes mid-test. CI did not catch it.

Current judge output on this commit: `T006B_SUMMARY pass=10 fail=34`.

## Definition of done (no exceptions)
All four must hold on the final commit, each quoted verbatim in your final report:
- `godot --headless --path . --script res://tests/acceptance/t006b_acceptance.gd` → `T006B_SUMMARY pass=<n> fail=0`
- `godot --headless --path . --script res://tests/acceptance/t006_acceptance.gd` → `T006_SUMMARY pass=148 fail=0` (or more passes, never a FAIL)
- `tests/test_runner.gd` → `Failed: 0` **and** `grep -c "SCRIPT ERROR" ` of its log = 0
- `tools/check_code_policy.gd` → PASS; `tools/game_smoke.tscn` → `failures=0`

Do not stop while any of these is red. Do not edit either acceptance file. Do not weaken checks
by changing what a check reads (for example, adding fake clusters that are not visible on the map).

## WP1 — Natural maps (judge section M)
Rewrite the three `map.rows` grids. Write a generator script at `tools/mapgen/frontier_mapgen.py`
(Python 3, stdlib only), commit it, and commit its output into the scenario JSONs. Requirements:
- **Deterministic, seeded value noise or cellular automata** for forest and rock. No stamps.
  Clusters must have irregular outlines and varied sizes: the largest forest is ≥ 4× the smallest
  and ≥ 25 tiles. Forest is 11–28% of each map.
- **`fr_river_valley` (64×32 or larger): a real winding river** that crosses the whole map
  (≥ 90% span), mean width 2–6, centreline sways ≥ 6 tiles, broken by **≥ 2 fords** (ground gaps)
  so armies can cross. Citadels sit on opposite banks.
- **`fr_border_siege`:** a different layout (≥ 25% of tiles differ from every other map).
  Suggested: a central rock ridge with 3 passes, plus forest flanks.
- **`fr_four_realms`:** keep it 4-fold fair, but make the clusters organic. Build fairness by
  generating one quadrant organically and mirroring it. M03 counts a *cluster* as symmetric only
  when it mirrors onto itself on both axes, so mirroring a quadrant is fine.
- ≥ 66 ground tiles within Manhattan radius 6 of every citadel, while all T006 E-checks still
  pass (fairness, connectivity, distances, percentages).
- Re-render each map to PNG locally to eyeball it (not committed).

## WP2 — Personality-driven full-tree AI (judge section P)
In `strategic_ai_module.gd` and `full_tree_order_util.gd`:
- Add a 4th personality **`"defensive"`** to `PERSONALITY` (high attack_army_size, low expansion).
- Give each personality a data table that changes (a) the **building priority**, for example
  economic → lumber_mill/power_well first, aggressive → barracks/stable early,
  defensive → watchtower/wall early with cannon_tower as soon as allowed; (b) the **unit mix
  weights**; (c) the **attack timing**.
- The table must be data, not branching code spread around. A `const` Dictionary in
  `full_tree_order_util.gd` is fine. Everything stays deterministic: no `randi()`; use
  `world_state.random_seed` only.
- Judge: ≥ 3 distinct first-8 build orders and ≥ 3 distinct top-3 unit mixes among the 4 AIs on
  `fr_four_realms`, with owner 0 forced to "defensive". The defensive AI places more towers and
  walls than the aggressive one.

## WP3 — A real late game (judge section L)
The AI-vs-AI duel on `fr_river_valley` must last **≥ 6000 ticks**, still produce a winner before
20000, and some AI must complete fr_sanctum, fr_dragon_roost and fr_cannon_tower and field
fr_paladin and fr_wyvern. Levers, in this order: the AI's attack threshold and timing per
personality; citadel/tower health; early-unit cost; late-unit cost and time. If you change unit
stats, B24/B25 (no dominance, value band) must still pass, and docs/mods/frontier.md's balance
table must be updated.

## WP4 — Quality gates (judge section Q)
- Fix `test_t006_defensive_building_attack_fields`: `place_building` returns an `int` id.
- CI step G2 must fail when the test log contains `SCRIPT ERROR`. Use the same style as the pack
  step: `if grep -E "SCRIPT ERROR" /tmp/test.log; then exit 1; fi`.
- Add a CI step `G8 T006B acceptance` that runs the new judge and greps `fail=0`.
- Add ≥ 6 new `test_t006b_*` tests to `tests/test_runner.gd`, all called and non-vacuous:
  mapgen determinism, personality table lookup, the defensive personality, and the fixed tower test.
- Docs: DEC-019 (personality-driven full-tree AI) in DECISIONS.md; PROJECT_STATE.md quotes the
  final `T006B_SUMMARY` line; docs/mods/frontier.md gets map descriptions and the updated balance table.

## Commits (in order, push after each)
`feat: T006B WP1 organic mapgen + river/siege/realms maps` ·
`feat: T006B WP2 personality tables + defensive AI` ·
`balance: T006B WP3 late game reachable` ·
`test: T006B WP4 SCRIPT ERROR gate, tests, docs (DEC-019)`.
Then comment on PR #7 with the final report.

## FINAL REPORT FORMAT
```
T006B FINAL REPORT
branch: oh/T006-frontier @ <sha>
T006B judge: <verbatim T006B_SUMMARY line>  (+ T006B_INFO duel line)
T006 judge:  <verbatim T006_SUMMARY line>
tests:       <verbatim Total: line>   SCRIPT ERROR count: <n>
policy:      <verbatim PASS line>     smoke: <verbatim GAME_SMOKE_DONE line>
maps: <one line per map: size, forest%, water%, rock%, #forest clusters>
personalities: <first 4 buildings per owner on fr_four_realms>
balance changes: <list>
deviations from this prompt: <none | list with reason>
```
