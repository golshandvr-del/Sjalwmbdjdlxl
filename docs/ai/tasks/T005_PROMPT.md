# T005 — HUD dedup part 2 + scenario determinism matrix + docs refresh

Executor: OpenHands. Author/reviewer: Claude. Base: `main` at `692b55b` (or newer).
Branch: `oh/T005-hud-dedup-scenarios`. Read `AGENTS.md` first; it overrides nothing here.

Claude already implemented and verified this exact change in a scratch branch:
G2 `Total: 4544   Passed: 4544   Failed: 0   Skipped: 0`, 610 `func test_` functions,
G1 no violations, G3/G4 failures=0. Your job is to reproduce it exactly, run every
gate, and refresh the documentation. If your numbers differ, STOP (S3) and report.

## SCOPE
In: WP1 (HUD logic), WP2+WP3 (tests), WP4 (docs). Out: everything else.

## ALLOWED FILES (nothing else may appear in `git diff --name-only main..HEAD`)
1. `ui/shared/hud_logic_util.gd` (append only)
2. `ui/mobile/game_hud.gd` (2 edits below only)
3. `ui/desktop/desktop_hud.gd` (2 edits below only)
4. `tests/test_runner.gd` (append tests + 6 call lines only)
5. `README.md` (3 number edits only)
6. `docs/CODE_MAP.md` (append rows only)
7. `docs/ai/PROJECT_STATE.md`, `docs/ai/DECISIONS.md` (text given below)

FORBIDDEN: every other path, especially `core/`, `modules/`, `project.godot`,
`export_presets.cfg`, `.github/`, `ci/`, `localization/`, scenes, assets.
Do not change behaviour: the refactor must be a pure move of logic.

---------------------------------------------------------------------------
## WP1 — move treaty proposal + target picker logic into HudLogicUtil

### WP1.1 Append to the END of `ui/shared/hud_logic_util.gd`
Add exactly two blank lines after the current last line, then this block verbatim:

```gdscript
# --- T005 WP1: treaty proposal + owner pickers -------------------------------

# Build a plain treaty proposal (no mission payload). Returns the treaty, or {}
# when invalid (self-target or TreatyUtil.is_valid() false).
static func build_treaty_proposal(type_id: String, sender: int, target: int,
		duration: int, tick: int) -> Dictionary:
	if target == sender:
		return {}
	var treaty: Dictionary = TreatyUtil.make_treaty(
		type_id, sender, target, {}, {}, duration, tick)
	if not TreatyUtil.is_valid(treaty):
		return {}
	return treaty


# Owner ids for treaty/mission target pickers: 0..owner_count-1 except `local_player`.
static func target_owner_choices(owner_count: int, local_player: int) -> Array:
	var out: Array = []
	for o in range(owner_count):
		if o != local_player:
			out.append(o)
	return out
```

### WP1.2 `_populate_owner_options` — SAME edit in BOTH HUD files
In `ui/mobile/game_hud.gd` and `ui/desktop/desktop_hud.gd`, inside
`func _populate_owner_options(opt: OptionButton) -> void:` replace

```gdscript
	for o in range(_owner_count()):
		if o == LOCAL_PLAYER:
			continue
		opt.add_item(_owner_label(o))
		opt.set_item_metadata(opt.item_count - 1, o)
```
with
```gdscript
	for o in HudLogicUtil.target_owner_choices(_owner_count(), LOCAL_PLAYER):
		opt.add_item(_owner_label(int(o)))
		opt.set_item_metadata(opt.item_count - 1, int(o))
```

### WP1.3 `_on_propose_treaty_pressed`
`ui/mobile/game_hud.gd` — replace
```gdscript
	if target == LOCAL_PLAYER:
		return
	var duration: int = int(_treaty_duration.value)
	var treaty: Dictionary = TreatyUtil.make_treaty(
		type_id, LOCAL_PLAYER, target, {}, {}, duration,
		int(Nexus.world_state.current_tick))
	if not TreatyUtil.is_valid(treaty):
		return
```
`ui/desktop/desktop_hud.gd` — replace
```gdscript
	if target == LOCAL_PLAYER:
		return
	var treaty: Dictionary = TreatyUtil.make_treaty(
		type_id, LOCAL_PLAYER, target, {}, {}, int(_treaty_duration.value),
		int(Nexus.world_state.current_tick))
	if not TreatyUtil.is_valid(treaty):
		return
```
In BOTH files the replacement is:
```gdscript
	var treaty: Dictionary = HudLogicUtil.build_treaty_proposal(
		type_id, LOCAL_PLAYER, target, int(_treaty_duration.value),
		int(Nexus.world_state.current_tick))
	if treaty.is_empty():
		return
```
Keep the following `diplomacy.issue_propose(...)` and `MessageLogUtil.append_message(...)`
lines untouched. Afterwards `grep -n "TreatyUtil.make_treaty(" ui/mobile/game_hud.gd
ui/desktop/desktop_hud.gd` must print nothing.

Commit: `refactor(hud): treaty proposal + target pickers via HudLogicUtil (T005 WP1, KI-7)`; push.

---------------------------------------------------------------------------
## WP2 + WP3 — tests

### Insert the test functions
In `tests/test_runner.gd` find the single line `class TickHarness extends RefCounted:`.
Insert the block below immediately BEFORE it, preceded by one blank line and
followed by two blank lines:

```gdscript
# --- T005 WP1: treaty proposal + target owner choices -----------------------
func test_t005_hud_logic_build_treaty_proposal() -> void:
	print("test_t005_hud_logic_build_treaty_proposal")
	var t: Dictionary = HudLogicUtil.build_treaty_proposal(str(TreatyUtil.TYPES[0]), 0, 1, 100, 7)
	_check(not t.is_empty(), "T005 valid treaty proposal built")
	_check(str(t.get("type", "")) == str(TreatyUtil.TYPES[0]), "T005 treaty carries the requested type")
	_check(HudLogicUtil.build_treaty_proposal(str(TreatyUtil.TYPES[0]), 0, 0, 100, 7).is_empty(), "T005 self-target treaty refused")
	_check(HudLogicUtil.build_treaty_proposal("not_a_treaty_type", 0, 1, 100, 7).is_empty(), "T005 unknown treaty type refused")


func test_t005_hud_logic_target_owner_choices() -> void:
	print("test_t005_hud_logic_target_owner_choices")
	_check(HudLogicUtil.target_owner_choices(4, 0) == [1, 2, 3], "T005 targets exclude the local player")
	_check(HudLogicUtil.target_owner_choices(4, 2) == [0, 1, 3], "T005 targets exclude a non-zero local player")
	_check(HudLogicUtil.target_owner_choices(1, 0) == [], "T005 single owner -> no targets")


func test_t005_huds_delegate_wp1_logic() -> void:
	print("test_t005_huds_delegate_wp1_logic")
	for path in ["res://ui/mobile/game_hud.gd", "res://ui/desktop/desktop_hud.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		_check(text.contains("HudLogicUtil.build_treaty_proposal("), "T005 %s calls build_treaty_proposal" % path.get_file())
		_check(text.contains("HudLogicUtil.target_owner_choices("), "T005 %s calls target_owner_choices" % path.get_file())
		_check(not text.contains("TreatyUtil.make_treaty("), "T005 %s builds no treaty itself" % path.get_file())


# --- T005 WP2: determinism matrix over every shipped scenario ---------------
func _t005_scenario_ids() -> Array:
	var probe: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(probe)
	GameBootstrap.load_catalogs(probe)
	var ids: Array = probe.data_loader.get_catalog("scenarios").keys()
	ids.sort()
	return ids


func _t005_harness_for(scenario_id: String) -> TickHarness:
	var nexus: TickHarness = TickHarness.new()
	GameBootstrap.register_modules(nexus)
	GameBootstrap.load_catalogs(nexus)
	var entry: Dictionary = nexus.data_loader.get_entry("scenarios", scenario_id)
	ScenarioLoader.apply_scenario(nexus, entry)
	return nexus


func test_t005_every_shipped_scenario_is_deterministic() -> void:
	print("test_t005_every_shipped_scenario_is_deterministic")
	var ids: Array = _t005_scenario_ids()
	_check(ids.size() >= 3, "T005 found the shipped scenarios (%d)" % ids.size())
	for sid in ids:
		var a: TickHarness = _t005_harness_for(str(sid))
		var b: TickHarness = _t005_harness_for(str(sid))
		a.run_ticks(300)
		b.run_ticks(300)
		_check(StateHasher.hash_world(a.world_state) == StateHasher.hash_world(b.world_state), "T005 scenario '%s': two fresh runs of 300 ticks hash equal" % str(sid))
		_check(a.world_state.current_tick == 300, "T005 scenario '%s' advanced 300 ticks" % str(sid))


func test_t005_every_shipped_scenario_survives_save_load() -> void:
	print("test_t005_every_shipped_scenario_survives_save_load")
	for sid in _t005_scenario_ids():
		var ref: TickHarness = _t005_harness_for(str(sid))
		ref.run_ticks(300)
		var expected: int = StateHasher.hash_world(ref.world_state)
		var a: TickHarness = _t005_harness_for(str(sid))
		a.run_ticks(150)
		var sa: SaveSystem = SaveSystem.new()
		sa.setup(a)
		var text: String = JSON.stringify(sa.build_snapshot())
		var b: TickHarness = _t005_harness_for(str(sid))
		var sb: SaveSystem = SaveSystem.new()
		sb.setup(b)
		_check(sb.apply_snapshot(JSON.parse_string(text)), "T005 scenario '%s' snapshot accepted" % str(sid))
		b.run_ticks(150)
		_check(StateHasher.hash_world(b.world_state) == expected, "T005 scenario '%s': save at 150 + load + 150 == 300 uninterrupted" % str(sid))


# --- T005 WP3: four-peer lockstep on the four-player shipped scenario --------
func test_t005_four_peer_lockstep_four_corners() -> void:
	print("test_t005_four_peer_lockstep_four_corners")
	var transport: LoopbackTransport = LoopbackTransport.new()
	var peers: Array = []
	for pid in [0, 1, 2, 3]:
		var nexus: TickHarness = _t005_harness_for("skirmish_four_corners")
		var lock: LockstepModule = nexus.get_module("multiplayer")
		lock.start_session([0, 1, 2, 3], pid, 3)
		transport.attach(pid, lock, nexus.event_bus)
		peers.append(nexus)
	var horizon: int = 150
	for nexus in peers:
		var lock: LockstepModule = nexus.get_module("multiplayer")
		for t in range(1, horizon + 1):
			lock.flush_empty_turn_for(t)
	for t in range(1, horizon + 1):
		for nexus in peers:
			var lock: LockstepModule = nexus.get_module("multiplayer")
			lock.inject_commands_for_tick(t)
			nexus.run_ticks(1)
	var h0: int = StateHasher.hash_world(peers[0].world_state)
	for i in range(peers.size()):
		var nexus: TickHarness = peers[i]
		_check(StateHasher.hash_world(nexus.world_state) == h0, "T005 four-peer: peer %d hash equals peer 0 after %d ticks" % [i, horizon])
		_check(not (nexus.get_module("multiplayer") as Object).has_desync(), "T005 four-peer: peer %d reports no desync" % i)
		_check(nexus.world_state.current_tick == horizon, "T005 four-peer: peer %d reached tick %d" % [i, horizon])
```

### Register the calls
In `_init()`, directly after the line `	test_t004_save_load_mid_battle_is_transparent()`
(and before `	_print_summary()`), insert these 6 lines (one tab indent):
```
	test_t005_hud_logic_build_treaty_proposal()
	test_t005_hud_logic_target_owner_choices()
	test_t005_huds_delegate_wp1_logic()
	test_t005_every_shipped_scenario_is_deterministic()
	test_t005_every_shipped_scenario_survives_save_load()
	test_t005_four_peer_lockstep_four_corners()
```
Verify: `grep -c "^func test_" tests/test_runner.gd` == 610 and every `test_t005_*`
defined is called exactly once in `_init()`.

### Red/green proof (mandatory, quote output in the report)
1. With WP1 committed and the tests inserted, run G2 -> expect
   `Total: 4544   Passed: 4544   Failed: 0   Skipped: 0`.
2. Temporarily restore the OLD mobile HUD: `git show main:ui/mobile/game_hud.gd > ui/mobile/game_hud.gd`.
   Run G2 -> expect exactly 3 `[FAIL] T005 game_hud.gd ...` lines (delegation checks).
3. Restore: `git checkout -- ui/mobile/game_hud.gd`. Run G2 again -> green (4544).

Commit: `test: T005 treaty/picker logic, scenario determinism matrix, four-peer lockstep`; push.

---------------------------------------------------------------------------
## WP4 — documentation refresh (numbers must equal YOUR G2 output = 4544 / 610)

### README.md (numbers only: `4366` occurs 5 times on lines 37, 152, 180; `584` once on line 153)
- Line with `**Tests:** \`Total: 4366 | Passed: 4366 | ...` -> replace both `4366` with `4544`.
- `Current suite: **4366` / `checks in 584 test functions**` -> `4544` and `610`.
- `tests (\`Total: 4366 | Passed: 4366 | Failed: 0\`)` -> `4544`.
Afterwards `grep -n "4366\|584 test" README.md` prints nothing.

### docs/CODE_MAP.md
Find the single line that starts with `| \`ui/shared/ui_scale.gd\``. Insert directly after
it these two lines verbatim (Persian is allowed in docs):
```
| `ui/shared/hud_logic_util.gd` | (T004/T005) منطقِ خالص و مشترکِ دو HUD (DEC-015) | HQ محلی، تحقیقِ بعدی، مالکانِ قابل‌کنترل، سرعت، برچسبِ سبک، نتیجه‌ی مسابقه، تاریخچه‌ی چت، پیشنهادِ مأموریت/پیمان، فهرستِ هدف‌ها |
| `core/save_snapshot_util.gd` | (T003) اعتبارسنجیِ کاملِ snapshot پیش از load/import (DEC-012) | `SaveSnapshotUtil.validate` — all-or-nothing |
```

### docs/ai/PROJECT_STATE.md
- `## Baseline (after T004)` -> `## Baseline (after T005)`.
- `Total 4506 / Passed 4506` -> `Total 4544 / Passed 4544`.
- In the KI-7 bullet append the sentence: ` T005 moved treaty proposal and target-owner
  pickers too; remaining duplication = node-building code only.`
- Task log row T005: replace `| assigned to OpenHands | oh/T005-hud-dedup-scenarios | - |`
  with `| PR open (OpenHands) | oh/T005-hud-dedup-scenarios | awaiting Claude review |`.
- In `## Candidate next tasks` replace the line
  `- T005 Android device QA checklist automation (what can be tested headless).` with
  `- T006 Android device QA checklist (docs/ai/DEVICE_QA.md) — Claude decides.`

### docs/ai/DECISIONS.md — append at the end
```
## DEC-016 Scenario determinism matrix (T005)
Every scenario in `data/scenarios/` must (a) produce identical hashes on two fresh
300-tick runs, (b) survive save@150 -> JSON -> load -> +150 bit-identically, and the
four-player scenario must stay in sync across four lockstep peers. New shipped
scenarios are covered automatically (the test enumerates the catalog).
```

Commit: `docs: T005 state, README counts, CODE_MAP rows, DEC-016`; push.

---------------------------------------------------------------------------
## GATES (run all, in order, after WP4; quote result lines)
G0 import twice; G1 lint; G2 tests (expect exactly `Total: 4544   Passed: 4544   Failed: 0   Skipped: 0`);
G3 scene smoke `failures=0`; G4 game smoke `failures=0`; G5 `git status --porcelain` empty;
G6 exported Android pack boots with 0 `SCRIPT ERROR`/`ERROR: Failed to load` (commands in AGENTS.md §4).
Then open a PR to `main` titled `T005: HUD dedup part 2 + scenario determinism matrix + docs`
with the FINAL REPORT as body, wait for GitHub Actions and quote its conclusion. Do NOT merge.

## ACCEPTANCE
A1 only ALLOWED FILES changed. A2 G1–G6 green locally and CI green on the PR.
A3 G2 totals exactly 4544/4544, 610 test functions. A4 red/green proof shown.
A5 no `TreatyUtil.make_treaty(` left in either HUD. A6 README has no `4366`/`584 test`.

## STOP CONDITIONS
S1 any old text block above not found exactly once -> do not improvise; report which.
S2 any gate red -> do not edit other files or existing tests; report last 40 log lines.
S3 G2 totals differ from 4544 -> report your numbers and the diff stat.
S4 push/auth failure -> keep local commits, report exact error (no tokens in output).

## FINAL REPORT FORMAT
## T005 REPORT
- Status: DONE | PARTIAL | STOPPED (Sx) ; Base SHA / Head SHA / Branch / PR URL / CI conclusion
## Files changed (git diff --stat main..HEAD)
## Commits (git log --oneline main..HEAD)
## Gates G0..G6 (exact result lines)
## Red/green proof (output)
## Deviations / Assumptions / Observations (not acted on)
