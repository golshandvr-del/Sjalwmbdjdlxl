# T006 — "Frontier": a complete, playable mod (real tech tree, defenses, natural maps, full AI)

Executor: OpenHands. Author/reviewer: Claude (Tech Lead). Base: `main` (this commit or newer).
Branch: `oh/T006-frontier`. Read `AGENTS.md` first.

## 0. HOW THIS TASK IS JUDGED (read twice)

There is ONE objective judge:

    godot --headless --path . --script res://tests/acceptance/t006_acceptance.gd

It prints `T006_CHECK PASS|FAIL <id> ...` lines and ends with
`T006_SUMMARY pass=<n> fail=<m>`. **The task is DONE only when it prints `fail=0`**
AND all existing gates G0–G6 are green AND the full suite still passes.

Rules about the judge:
- `tests/acceptance/t006_acceptance.gd` is READ-ONLY. Do not edit, move, rename or
  wrap it. `git diff main..HEAD -- tests/acceptance/` must be empty. Its sha256 at
  hand-off is recorded in section 9; the reviewer will compare.
- Do NOT stop, open the PR, or write the final report while any check FAILS.
  "Mostly passing" is not done. If you are blocked on a check, keep working on the
  others, then come back; report as STOPPED only under the stop conditions in §8.
- Use `-- --only=BC` (letters) to run sections quickly while iterating. Sections D and F
  are slow (full playthrough / AI matches): run them at least once per work package.
- Never make a check pass by special-casing the checker (e.g. detecting the test
  scenario id `t006_flat`, reading `OS.get_cmdline_user_args`, checking the call stack).
  The reviewer greps for this. Every behaviour must be a real, general engine feature.

Current state on `main`: `T006_SUMMARY pass=8 fail=80` (88 lines, because sections B and E
stop early while content is missing). With all content present the checker emits exactly
148 checks: A 9, B 29, C 23, D 5, E 34, F 10, G 38. **Target: `T006_SUMMARY pass=148 fail=0`.**

## 1. GOAL

Today the engine only lets you build an `outpost`, units come only from the HQ, there are
no prerequisites, terrain is only floor/wall, buildings cannot shoot, the HUD shows only
`resource_basic`, and the AI only builds outposts. T006 delivers:

1. **Engine features** (general and data-driven, usable by any mod): building/unit/tech
   prerequisites, production from any building, defensive buildings that attack, forest
   terrain, ASCII map rows, scenario `hq_type`, scenario `rules` (`pop_cap`, `full_ai`,
   `faction_prefix`), non-survival buildings (walls), a second resource on the HUD.
2. **The `frontier` mod** (`mods/frontier/`), enabled by default: ≥10 units, ≥10
   buildings, ≥10 techs, a real tech tree (building depth ≥4), two energy types of
   spending, two handmade-quality natural maps (1v1 and 4-player FFA).
3. **An AI that actually plays the tree** in `full_ai` scenarios: builds diverse
   buildings, researches, produces many unit types, defends, and wins decisively.
4. **HUD + rendering**: build menu, production menu, research menu, resource lines,
   natural varied terrain art (ground variants, forest, water, rock) in all 3 styles.
5. **Vanilla stays identical**: base scenarios produce the post-WP0 golden hashes,
   and enabling `frontier` changes NOTHING in them (check A2).

## 2. WORK PACKAGES (do them in order; commit after each)

### WP0 — Pathing performance + belief-grid bug (exact patch provided)
Apply `docs/ai/tasks/T006_WP0_reference.patch` exactly (`git apply`). It changes only
`core/path_service.gd` (binary-heap open set, identical pop order) and
`core/belief_grid_util.gd` (a viewer that owns no fog grid has full knowledge).
Why: AI players are never fog viewers, so they planned through walls and replanned
every tick; A* was ~4 ms × 1 call/tick. Measured by Claude after the patch:
- full suite `Total: 4544   Passed: 4544   Failed: 0   Skipped: 0` (unchanged),
- vanilla 600-tick hashes become `skirmish_basic 853235305436049241`,
  `skirmish_duel -4480766952479341591`, `skirmish_four_corners -1523216689346447094`
  (these are the A1 goldens in the checker),
- 3000 AI ticks on `skirmish_four_corners`: ~4.8 s → ~0.7 s.
Then delete `docs/ai/tasks/T006_WP0_reference.patch` in the same commit.
Commit: `perf: T006 WP0 heap A* + full-knowledge belief for fog-less viewers (DEC-017)`.

### WP1 — Engine contracts (sections A, C)
All of these are generic engine features. Exact contracts:

**1a. PrereqUtil** — new `core/prereq_util.gd`, `class_name PrereqUtil`, pure static:
- `static func missing(requires: Variant, completed_building_types: Array, researched: Array) -> Array`
  `requires` is `{ "buildings": [ids], "tech": [ids] }` (either key optional) or `null`/`{}`.
  Returns a **sorted** Array of strings `"building:<id>"` / `"tech:<id>"` for every unmet
  item. Robust to `null`, missing keys, non-Array values.
- `static func owner_completed_building_types(building_list: Dictionary, owner: int) -> Array`
  Sorted unique `type`s of buildings with that owner, `health > 0` and
  `construction_remaining <= 0`.

**1b. Prerequisite enforcement** (checked BEFORE spending; a rejection spends nothing,
places nothing, queues nothing):
- Building archetype `"requires": {"buildings": [...], "tech": [...]}` →
  `build_building` rejects with event `buildings.build_rejected`
  `{owner, reason: "missing_prerequisite", type, missing: [...]}`.
- Unit archetype `"requires"` (same shape) → `build_unit` rejects with
  `economy.build_rejected` `{owner, reason: "missing_prerequisite", unit_type, missing}`.
- Tech node `"requires_buildings": [ids]` (in addition to the existing `"requires"` tech
  list) → `research_tech` rejects with `tech.research_rejected` reason
  `"missing_prerequisite"`.
- `buildable_units` of ANY building (not just the HQ) is honoured by `build_unit`
  (production from barracks, stables, ...). Upgrade `effects.buildable_units_add` keeps working.

**1c. Terrain + maps**
- `MapModule.TERRAIN_FOREST: int = 3`. Forest is NOT walkable and NOT buildable (like rock).
  Every walkability call site must treat 1,2,3 as blocked; keep ground = 0 only walkable.
- Scenario `"map": { "rows": ["..#~T", ...] }` — ASCII: `.`=0 ground, `#`=1 rock/wall,
  `~`=2 water, `T`=3 forest. Width = row length (all rows equal), height = row count.
  Existing `width/height/tiles` maps keep working unchanged.

**1d. Scenario fields**
- `"hq_type": "<building id>"` — auto-placed HQs (players without an explicit HQ) use this
  type instead of `"hq"`. Explicit `buildings` entries are placed as written. Every code
  path that "finds the HQ" (AI, HUD, victory, placement) must work for a custom HQ type:
  treat a building as an HQ if its type is `"hq"` OR equals the scenario's `hq_type`
  (store `hq_type` in the `scenario` world-state section via `store_meta`).
- `"rules": {...}` copied into a NEW world-state section `"rules"` **only if the scenario
  has a non-empty `rules`** (vanilla scenarios must not get the section — check C23 and A1).
  Keys: `pop_cap` (int), `full_ai` (bool), `faction_prefix` (string, e.g. `"fr_"`).
- `pop_cap`: `build_unit` rejects with `economy.build_rejected` reason `"pop_cap"` when
  (alive units of owner + items in that owner's build queues) >= `pop_cap`.

**1e. Defensive buildings**
- A building archetype with `stats.attack_damage > 0` (plus `attack_range`,
  optional `attack_cooldown_ticks`, default 10) attacks the nearest enemy unit in range
  (Manhattan or Chebyshev — document which; deterministic tie-break by unit id) via the
  combat module, emitting `combat.attack` `{attacker: <building id>, target: <unit id>,
  damage, attacker_kind: "building"}` and applying damage/death exactly like unit attacks.
- Building records only get the extra attack fields when the archetype has
  `attack_damage > 0`; all other building records keep exactly today's 13 keys (C18, C19).
- Respect diplomacy/teams exactly as unit combat does (no friendly fire, allies are safe).

**1f. Survival**: building archetype `"counts_for_survival": false` (walls) is ignored by
the victory module's "player still alive" test.

**1g. Resources**: `resource_energy` is a real second resource (start wallet, building
`produces`, costs). `EconomyModule.try_spend` must check ALL cost keys atomically.

**1h. Determinism**: all new state lives in `world_state` (never only in module vars),
iterates sorted keys, uses no wall-clock/random APIs except the seeded sim RNG, and
survives save/load (F09, F10).

Commit(s): `feat: T006 WP1 prerequisite engine, forest/ascii maps, hq_type, rules, defensive buildings`.

### WP2 — The `frontier` mod content (section B, D)
`mods/frontier/mod.json`: `id "frontier"`, `enabled true`, `provides` units, buildings,
tech, scenarios (and localization if the mod loader supports it; otherwise add strings to
`localization/en.json` + `fa.json`). Every id starts with `fr_`.

Target design (you set the numbers; the checker enforces balance B24/B25 and depth):

| Tier | Building | Requires | Role / produces |
|---|---|---|---|
| 0 | `fr_citadel` | — | HQ (`buildable: false`), small gold income, trains `fr_militia`, `fr_scout` |
| 1 | `fr_barracks` | citadel | `fr_militia`, `fr_spearman`, `fr_archer` |
| 1 | `fr_lumber_mill` | citadel | gold income |
| 1 | `fr_watchtower` | citadel | defensive (attack_damage) |
| 1 | `fr_wall` | citadel | cheap, tough, `counts_for_survival: false` |
| 2 | `fr_power_well` | lumber_mill | produces `resource_energy` |
| 2 | `fr_stable` | barracks | `fr_rider`, `fr_lancer` |
| 3 | `fr_academy` | barracks + power_well | `fr_mage`, `fr_priest` |
| 4 | `fr_workshop` | academy | `fr_catapult`, `fr_ballista` |
| 4 | `fr_sanctum` | academy + stable | `fr_paladin` |
| 5 | `fr_cannon_tower` | workshop + watchtower | strong defensive |
| 5 | `fr_dragon_roost` | sanctum + workshop | `fr_wyvern` |

Units span ≥4 categories (infantry, ranged, cavalry, siege, magic, air). ≥3 units cost
`resource_energy` (mage, catapult, wyvern...). ≥2 units have `requires.tech`
(e.g. `fr_lancer` ← `fr_tech_lancer_training`, `fr_paladin` ← `fr_tech_holy_order`,
`fr_wyvern` ← `fr_tech_dragon_taming`).

Techs: one tech tree document (e.g. `data/tech/frontier_tree.json` in the mod) with ≥10
`fr_tech_*` nodes, tech depth ≥3 levels, ≥5 nodes with `requires_buildings`, each with
cost, `research_time_ticks`, at least one real effect (use the effect types the tech
module already implements — read `modules/tech_tree/tech_tree_module.gd`; add a new
effect type only if needed and test it).

Every unit needs: cost (gold > 0), `build_time_ticks`, stats `health, attack_damage,
attack_range, vision_range, move_speed` all > 0, `visual {shape, color}`, `category`,
`display_name_key`. Every building: `stats.health`, `display_name_key`, `visual.color`,
cost + `build_time_ticks` (except the citadel). Names translated in en AND fa (fa must
differ from en), plus `resource.resource_basic.name` / `resource.resource_energy.name`.

Write `docs/mods/frontier.md`: design intent, the tech tree (text diagram), and a
balance table (cost, hp, dmg, range, speed, value-per-cost) for every unit.

Commit: `feat: T006 WP2 frontier mod content + docs/mods/frontier.md`.

### WP3 — Natural, fair maps (section E)
Two scenarios in the mod:
- `fr_river_valley`: 2 players, ≥48×32, owner 0 human, owner 1 AI (`smart: true`).
- `fr_four_realms`: 4 players FFA, ≥64×48, owner 0 human, 1–3 AI (`smart: true`).
Both: `hq_type "fr_citadel"`, ASCII `map.rows`, `rules { full_ai: true, pop_cap 20..60,
faction_prefix "fr_" }`, a `display_name_key`, starting `resource_basic` and
`resource_energy`.

Quality bars (checked): water 5–25 % forming a real body (river/lake), forest 8–30 %
in clusters, rock 2–15 %, ground ≥85 % one connected landmass, every citadel reaches every
other by land, nearest-enemy path lengths within 15 % of each other, citadels far apart,
equal build room around each citadel. Make it look natural: a winding river with 2–3
fords/bridges (ground tiles), groves of forest, rocky outcrops — not noise, not stripes.
Recommended: write a deterministic generator `tools/frontier_map_gen.gd` (seeded, pure)
with mirror/rotational symmetry for fairness, run it once and commit the produced rows.

Commit: `feat: T006 WP3 fr_river_valley + fr_four_realms maps (+ generator)`.

### WP4 — AI plays the whole tree (section F)
When `rules.full_ai` is true, the strategic AI (smart players) must:
- follow the prerequisite tree (use `PrereqUtil`; never issue orders whose prereqs are
  unmet — F07 caps rejections at 400 per duel), place buildings on valid ground near its
  citadel (forest/water/rock are blocked), build economy (lumber mill, power well),
  towers and walls, production buildings, research techs, and produce a MIX of units from
  ALL its production buildings (not only the HQ), spending both resources,
- attack in waves, and win: an AI-vs-AI duel on `fr_river_valley` must end with a winner
  between tick 3000 and 18000 (F01/F05), within 300 s wall-clock on the checker's run
  (F06; measure, profile, and optimise if needed — WP0 is the big win),
- winner of the duel: ≥7 building types, ≥6 unit types, ≥4 techs; in `fr_four_realms`
  by tick 9000, ≥3 of 4 AIs reach 6 building types / 5 unit types / 3 techs.
When `full_ai` is absent (all vanilla scenarios) the AI must behave EXACTLY as before —
A1 and A2 lock this with hashes. In particular the AI must not pick `fr_` units or
techs in vanilla scenarios.

Commit: `feat: T006 WP4 full-tree strategic AI for full_ai scenarios`.

### WP5 — HUD + rendering (section G)
`ui/shared/hud_logic_util.gd` (pure, static, sorted outputs):
- `building_menu(catalog: Dictionary, completed_types: Array, researched: Array, wallet: Dictionary) -> Array`
  one entry per catalog entry with `buildable != false`, sorted by id:
  `{ "id", "affordable": bool (wallet >= every cost key), "missing": PrereqUtil.missing(...) }`.
- `production_menu(building: Dictionary, unit_catalog: Dictionary, completed_types: Array, researched: Array, wallet: Dictionary) -> Array`
  one entry per id in `building.buildable_units` (sorted by id), same entry shape.
- `resource_lines(wallet: Dictionary) -> Array` of `{ "id", "amount" }`:
  `resource_basic` first (if present), then the other ids sorted.
Both HUDs (`ui/desktop/desktop_hud.gd`, `ui/mobile/game_hud.gd`) must use all three,
show every resource, offer a build menu (only the scenario's `faction_prefix` buildings
when that rule exists; vanilla keeps today's outpost-only behaviour), a production menu
for the selected building, and a research menu; actions are issued as player commands
`"build_building"`, `"build_unit"`, `"research_tech"`. Disabled entries show what is missing.

Rendering: `draw_tile(canvas, rect, terrain_id, x, y)` in `style_simple`, `style_sprite`
and `style_detailed`; `render/render_adapter.gd` passes the tile coordinates
(`style.draw_tile(self, rect, terrain, x, y)`). Ground gets ≥3 subtle natural colour
variants chosen by a hash of (x, y) (pure function — no RNG state); forest draws
distinct tree art (≥3 draw calls); water and rock get their own look. Minimap shows forest.
`tools/game_smoke.gd` also smokes `fr_river_valley`. Add a CI step
`G7 T006 acceptance` running the checker (and failing the job on `fail>0`).

Commit: `feat: T006 WP5 build/production/research menus, resource lines, natural terrain art`.

### WP6 — Tests + docs
- ≥25 new `func test_t006_*` in `tests/test_runner.gd`, each called from the run list,
  each asserting real behaviour (no `_check(true`). Cover PrereqUtil, each rejection
  path, ascii rows, hq_type, rules/pop_cap, tower attack, walls & survival, energy spend,
  HUD menus, AI uses non-HQ production, determinism + save/load of a frontier match.
- Update `README.md` test counts, `docs/CODE_MAP.md` rows for new files,
  `docs/ai/DECISIONS.md`: `DEC-017` (WP0 pathing/belief fix and new vanilla goldens) and
  `DEC-018` (prerequisite/rules/terrain/defensive-building contracts and the frontier mod),
  `docs/ai/PROJECT_STATE.md`: a T006 section mentioning `frontier` and quoting the final
  `T006_SUMMARY pass=148 fail=0` line verbatim.

## 3. ALLOWED / FORBIDDEN
Allowed: `core/`, `modules/`, `render/`, `ui/`, `tools/`, `mods/frontier/`,
`localization/en.json`, `localization/fa.json`, `tests/test_runner.gd`,
`.github/workflows/ci.yml` (add G7 only), `README.md`, `docs/`.
Forbidden: `tests/acceptance/**`, `data/scenarios/*` (vanilla), `data/units/*`,
`data/buildings/*`, `data/tech/*` (vanilla content must stay byte-identical),
`project.godot`, `export_presets.cfg`, `android/`, `mods/example_mod/`, `mods/playdough_demo/`.
Do not weaken or delete any existing test. Do not change existing golden values except as
WP0 dictates.

## 4. ENGINE FACTS YOU WILL NEED (verified by Claude on main)
- Commands enter via `nexus.issue_command(type, owner, data, delay)` → bus event
  `command.<type>`; buildings module handles `build_building`, economy handles `build_unit`,
  tech handles `research_tech`. Existing rejection events: `buildings.build_rejected`,
  `economy.build_rejected`, `tech.research_rejected` (payload has `reason`).
- `units.spawned` payload has `owner`, `type`; `tech.research_completed` has `owner`, `node_id`.
- `StateHasher._LOCAL_SECTIONS = ["lockstep", "local_selection", "ui_prefs"]`; every other
  section is hashed — so a new `rules` section is part of the hash (that is why it must
  not appear in vanilla).
- Smart AI = `ai_commander` + `strategic_ai` (`modules/ai_commander/strategic_ai_module.gd`);
  today it only plans outposts and HQ upgrades; unit choice is `UnitCandidateUtil.choose_unit`
  restricted to the HQ's `buildable_units`.
- Profiling baseline: before WP0, `units.on_tick` was >85 % of tick time, all of it A*.
- Known Godot traps (AGENTS.md §4.1) apply: typed arrays from JSON, `int()` every JSON
  number, never iterate unsorted Dictionary keys in sim code.

## 5. GATES (run all, in order, at the end; quote result lines)
G0 import twice; G1 lint `[PASS] No CODE_POLICY violations found.`; G2 full suite
`Failed: 0` (Total = 4544 + your new checks); G3 scene smoke `failures=0`; G4 game smoke
`failures=0` (now including `fr_river_valley`); G5 `git status --porcelain` empty;
G6 exported pack boots with 0 `SCRIPT ERROR`; **G7 acceptance `T006_SUMMARY pass=148 fail=0`**.
Then open a PR to `main` titled `T006: Frontier mod (tech tree, defenses, natural maps, full AI)`
with the FINAL REPORT as body, wait for GitHub Actions and quote its conclusion. Do NOT merge.

## 6. WORKING METHOD (required)
1. After every WP run `-- --only=<letters>` for the sections it affects and paste the
   PASS/FAIL counts in the commit message body.
2. Keep a running log in the PR body: which checks flipped to PASS in which commit.
3. If a check seems impossible, re-read its source in the checker — it is short and
   exact — before concluding. The intended solution is always a general feature.
4. Prefer many small commits over one giant one.

## 7. ACCEPTANCE
A1 `T006_SUMMARY pass=148 fail=0` locally and in CI (G7). A2 G0–G6 green, CI green.
A3 `git diff main..HEAD -- tests/acceptance/ data/ mods/example_mod mods/playdough_demo` empty.
A4 ≥25 `test_t006_*`, all called, none vacuous. A5 no checker special-casing.
A6 docs updated as in WP6.

## 8. STOP CONDITIONS (the ONLY reasons to stop before fail=0)
S1 `git apply` of the WP0 patch fails → report the error, do not hand-edit.
S2 after WP0 the full suite is not 4544/4544 or A1 goldens differ → report numbers.
S3 an existing test must change for a feature to work → stop and explain which and why.
S4 push/auth failure → keep local commits, report the exact error (no tokens).
S5 a check is provably contradictory with another check → quote both and your proof.
Anything else ("it's slow", "the AI is hard", "the map is hard") is NOT a stop condition.

## 9. HAND-OFF FACTS
- Checker sha256: `04752708a160431c0f8877cdd56d6460dcb5ecb57c8109c4eee275f634b3a928`
- Checker on `main` at hand-off: `T006_SUMMARY pass=8 fail=80`.

## FINAL REPORT FORMAT
## T006 REPORT
- Status: DONE | STOPPED (Sx) ; Base SHA / Head SHA / Branch / PR URL / CI conclusion
## Acceptance (paste the full `T006_CHECK` list and the SUMMARY line)
## Files changed (git diff --stat main..HEAD)
## Commits (git log --oneline main..HEAD)
## Gates G0..G7 (exact result lines)
## Performance (duel ticks + ms, four-player ms, from the checker's T006_INFO lines)
## Deviations / Assumptions / Observations
