# Decisions log (ADR-lite). Append-only. Only Claude adds entries.

## DEC-001 Two-agent workflow
Claude designs, scopes, reviews; OpenHands implements exactly one task prompt per run.
Every task has ALLOWED/FORBIDDEN files, gates and acceptance criteria.

## DEC-002 Keep existing architecture
Nexus core + EventBus + WorldState + IModule + `nexus.get_module()` duck-typed access
is the accepted architecture. No redesign without a new DEC entry.

## DEC-003 Branch-per-task, immediate commits
Agents commit+push after each logical step to `oh/<task-id>-<slug>`; never to main.
Claude reviews the diff; the owner merges. Remote is `origin`. AGENT_RULES.md rule 3
(`project-nexus/` folder) is obsolete.

## DEC-004 Godot side effects are not committed  (SUPERSEDED by DEC-007)
Modified `*.import` and newly generated `*.uid` are reverted/removed before commit,
until a dedicated task decides a `.uid` policy (KI-3).

## DEC-005 Verification gates
G1 lint, G2 tests (Failed: 0), G3 scene smoke, G4 game smoke, Godot 4.7.x headless.
A task is not acceptable unless all four pass and the exact result lines are reported.

## DEC-006 Tests
New tests are appended to `tests/test_runner.gd` and registered in `_init()`.
Existing tests are not edited/deleted without explicit task permission.

## DEC-007 Track all .uid files (T002)
Every `*.gd.uid` is committed; `*.import` are committed in their Godot 4.7.2 form.
After an editor import the working tree must be clean (gate G5). `.godot/` stays
ignored.

## DEC-008 Local presentation state is outside the sim hash (T002)
Per-peer data (selection, camera, UI prefs ...) lives in a section listed in
`StateHasher._LOCAL_SECTIONS`. Unit selection moved from `units.selected` to section
`local_selection`. Integral floats hash as ints (JSON round-trip safety).

## DEC-009 GitHub Actions CI is active (T002)
`.github/workflows/ci.yml` is committed (no longer gitignored); `ci/ci.yml` is a
byte-identical mirror. Gates G1-G6 on Godot 4.7.2 run for main, `oh/**`, `claude/**`
and PRs. Godot version bumps change `GODOT_VERSION` in both files together.

## DEC-010 No third-party test/lint addons for now (T002)
awesome-godot tools (GUT, GdUnit4, gdtoolkit) were evaluated and not adopted: the
zero-dependency in-repo runner/linter/smoke tools cover current needs.

## DEC-011 Bigger tasks per run (T002)
The owner can only message every ~12h, so each OpenHands run carries several work
packages (WP) in strict order, each with its own commit(s) and gates. A failed WP
stops the run; completed WPs stay committed.

## DEC-012 Saves are validated before apply (T003)
`SaveSnapshotUtil.validate(snapshot, SAVE_VERSION)` returns "" or a reason. Any
reason => apply_snapshot/import_save refuse and the live game is untouched. Newer
`save_version` is refused; older is loaded best-effort.

## DEC-013 ui_prefs is local (T003)
`ui_prefs` is per-device preference state and is excluded from the sim hash.
Gameplay must never read `ui_prefs` inside simulation code (difficulty in ui_prefs
is only the menu default; the difficulty module owns the match value).

## DEC-014 App background pause (T003)
Single-player matches pause on NOTIFICATION_APPLICATION_PAUSED and stay paused on
resume. Networked sessions never pause locally.

## DEC-015 Shared HUD logic lives in HudLogicUtil (T004)
`ui/shared/hud_logic_util.gd` holds static, pure, headless-testable HUD decisions.
Both HUDs delegate to it; they keep only node/Localization code. New HUD logic that
both HUDs need goes there first, with a unit test, never duplicated into both HUDs.

## DEC-016 Scenario determinism matrix (T005)
Every scenario in `data/scenarios/` must (a) produce identical hashes on two fresh
300-tick runs, (b) survive save@150 -> JSON -> load -> +150 bit-identically, and the
four-player scenario must stay in sync across four lockstep peers. New shipped
scenarios are covered automatically (the test enumerates the catalog).

## DEC-017 T006 WP0 pathing performance + fog-less viewer belief (vanilla goldens)
`core/path_service.gd` uses a binary-heap open set with an identical pop order, and
`core/belief_grid_util.gd` treats a viewer that owns no fog grid as having full
knowledge. Together these cut A* cost and stop AI players (never fog viewers) from
planning through walls and replanning every tick. The vanilla 600-tick hashes after
WP0 are the A1 goldens: `skirmish_basic 853235305436049241`,
`skirmish_duel -4480766952479341591`, `skirmish_four_corners -1523216689346447094`.

## DEC-018 T006 prerequisite/rules/terrain/defensive-building contracts + frontier mod
General, data-driven engine features (no mod special-casing):
- `core/prereq_util.gd` (`PrereqUtil`) is the single prerequisite checker. Buildings
  and units carry `requires { buildings, tech }`; tech nodes carry
  `requires_buildings`. Every rejection happens BEFORE spending/placing/queueing and
  emits the owning module's `*_rejected` event with `reason: "missing_prerequisite"`.
- `build_unit` honours the producing building's `buildable_units`, not only the HQ.
- `MapModule.TERRAIN_FOREST = 3` (blocked like rock); scenario `map.rows` accepts
  ASCII `. # ~ T`; scenario `hq_type` and `rules { pop_cap, full_ai, faction_prefix }`
  are opt-in and stored in the `scenario` / `rules` world-state sections. Vanilla
  scenarios never get a `rules` section, so their hash is unchanged.
- Defensive buildings (`stats.attack_damage > 0`) fire via the combat module with
  `combat.attack.attacker_kind = "building"`, respecting diplomacy/teams. Only such
  archetypes add the extra attack fields to their record; other buildings keep the
  13-key shape.
- `counts_for_survival: false` (walls) is ignored by the victory "still alive" test.
- `mods/frontier/` is the first total-conversion mod: 12 units, 12 buildings, a
  10-node tech tree, defensive towers/walls, a second resource (`resource_energy`)
  and three natural-map scenarios. The `rules.full_ai` strategic AI plays the whole
  tree through the pure `FullTreeOrderUtil`; without `full_ai` the AI is unchanged.
- Objective judge: `tests/acceptance/t006_acceptance.gd` (read-only, 148 checks),
  wired into CI as gate G7.


## DEC-019 Personality-driven full-tree AI (T006B WP2)
When `rules.full_ai` is set, each AI personality drives its own full-tree plan
from a single data table, `FullTreeOrderUtil.PERSONALITY_PLAN`: a building-priority
list (`build_bias`), a build-avoid list (`build_avoid`), a unit-mix preference
(`unit_bias`) and an attack-army threshold (`full_tree_army_size`). A 4th
personality, `"defensive"`, fortifies first (watchtower/wall/cannon tower) and
masses the largest army; `"aggressive"` skips static defenses and pushes earliest;
`"economic"` favours economy buildings and late units. The table is data, not
branching code, and stays deterministic (no RNG). Full-tree AIs also hold their
all-in until `FULL_TREE_MIN_ATTACK_TICK` so the tree is actually played before the
duel resolves (T006B WP3). Vanilla behaviour is untouched: every change is gated
by `rules.full_ai`.

