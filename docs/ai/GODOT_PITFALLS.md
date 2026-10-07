# Godot 4 pitfalls checklist (agent reference) — Project Nexus
Each item: the trap, whether THIS repo was affected (evidence), and the rule.
Verified with Godot 4.7.2 headless. Update only via a Claude-approved task.

## P1 Export filters silently drop runtime scripts  [AFFECTED -> fixed T002, KI-10]
- Trap: `exclude_filter` removes files from the exported .pck. Scripts referenced by
  `class_name` then fail ONLY in the exported build ("Identifier X not declared").
  The editor and headless tests never notice.
- Evidence: presets excluded `tools/*`; `core/game_bootstrap.gd` uses `StatRegistry`
  (`tools/stat_registry.gd`). Exported pack boot printed 5 SCRIPT ERRORs, main menu
  failed to compile. Introduced in 4a8264d (MD1.5); undetected until T002.
- Rule: never exclude `tools/*`. Gate G6 boots the exported pack in CI.
  Test `test_t002_export_filter_keeps_runtime_tool_classes`.

## P2 JSON turns every int into float  [AFFECTED -> fixed T002, KI-8]
- Trap: `JSON.parse_string` returns all numbers as float. `int` vs `float` values
  differ in `typeof`, in hashing, in `==` on Arrays, and as Dictionary keys.
- Evidence: StateHasher hashed 1 and 1.0 differently, so the world hash changed after
  a save/load round-trip (simulation behaviour itself stayed identical).
- Rule: StateHasher hashes integral floats as ints. Code reading JSON must cast with
  `int(...)` before using a value as an index, key, or in `match`.

## P3 Local presentation state inside hashed state  [AFFECTED -> fixed T002, KI-6]
- Trap: lockstep checksums cover everything in WorldState; per-peer UI state there
  causes false desyncs.
- Evidence: `select_units` wrote `units.selected`; a 2-peer loopback where only peer 0
  selected a unit reported `has_desync() == true`.
- Rule: per-peer state goes in a section listed in `StateHasher._LOCAL_SECTIONS`
  (`lockstep`, `local_selection`).

## P4 Huge frame delta after resume  [AFFECTED -> fixed T002, KI-9]
- Trap: after Android background/resume, a debugger break or a long load, `_process`
  receives a delta of many seconds. A fixed-step accumulator then runs hundreds of
  ticks in one frame (freeze / "spiral of death").
- Evidence: `SimClock.advance(30.0)` returned 600 ticks (2400 at 4x speed).
- Rule: `SimClock.MAX_FRAME_DELTA = 0.5` clamps real time per call.

## P5 Unseeded RNG / wall clock in simulation  [NOT affected; guarded T002]
- Rule: no `randi/randf/randomize/randi_range/randf_range`, `Time.get_*`,
  `OS.get_ticks*` in core/ or modules/ except the allowlist
  (`core/save_manager.gd` slot timestamps, `modules/multiplayer/lan_discovery.gd`
  beacon id). Test `test_t002_sim_sources_have_no_wallclock_or_unseeded_rng`.

## P6 Dictionary / directory iteration order  [OK, keep it so]
- Trap: `DirAccess` listing order is platform-dependent; iterating unsorted keys from
  data merged in different orders differs across peers.
- Evidence: DataLoader, ModLoader (Kahn + id ties), StorageService.list_packs and
  ModPackManager all sort. 28 `for k in d.keys()` loops exist in modules/ — any NEW
  loop whose order affects the simulation must iterate `keys()` after `.sort()`.

## P7 `.uid` files (Godot 4.4+)  [AFFECTED -> policy T002, KI-3, DEC-007]
- Trap: Godot generates `<script>.gd.uid`; scenes reference `uid://`. Untracked uids
  get regenerated with different ids on each machine -> broken/changed references.
- Rule: commit every `*.gd.uid` (official recommendation). New script => commit its
  `.uid` in the same commit. `.godot/` is never committed. Gate G5.

## P8 `.import` rewrites by newer engine  [AFFECTED -> committed T002]
- Trap: opening the project in a newer Godot rewrites `*.import` (new keys).
- Rule: the 4.7.2 form is committed; the tree must stay clean after import (G5).

## P9 `tr()` vs project Localization  [OK, keep it so]
- Rule: always `Localization.t(key)`; keys must exist in BOTH `localization/en.json`
  and `fa.json` under `strings`. Existing tests `test_*_localized_in_all_locales`.

## P10 Listeners of freed nodes  [AFFECTED -> fixed T002, KI-12]
- Trap: a freed node that stays registered on a shared bus/signal is a dead listener.
- Evidence: opening a match HUD 3 times left 3 `victory.match_over` listeners on
  Nexus.event_bus (game_hud.gd, desktop_hud.gd, main_menu.gd never unsubscribed;
  lobby.gd already did).
- Rule: every ui/ or render/ file that calls `Nexus.subscribe(` must call
  `Nexus.event_bus.unsubscribe_all(self)` in `_exit_tree`. Test
  `test_t002_ui_bus_subscribers_unsubscribe_on_exit`. 49 `.connect(func ...)` lambdas
  in ui/ are WATCH: connect lambdas only to signals of the node itself or children.

## P11 `@onready` / `$Path` vs .tscn drift  [WATCH; covered by G3]
- Fact: 72 `$Node` references in ui/. Renaming a node in a .tscn breaks them only at
  runtime. G3 scene smoke instantiates every navigable scene; keep it green.

## P12 First import on a fresh checkout  [KNOWN, KI-5]
- The first `--editor --quit` may log Vazirmatn font/theme errors because the class
  cache and imports do not exist yet. Always run the import twice; only the second
  run counts.

## Sources
- awesome-godot (https://github.com/godotengine/awesome-godot): GUT, GdUnit4,
  godot-gdscript-toolkit (gdlint/gdformat), godot-ci, Netfox were reviewed. DEC-010:
  none adopted now — the in-repo runner + linter + smoke tools already cover the need
  and the project has a zero-dependency rule.
- Godot docs: "Exporting projects" (filters), "UID" (4.4 .uid files), JSON class.
