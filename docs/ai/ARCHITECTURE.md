# Architecture (agent reference) — Project Nexus
Verified against commit 98a8866. Update only via a Claude-approved task.

## Boot
- `project.godot`: main scene `res://scenes/main_menu.tscn`; single autoload
  `Nexus="*res://core/nexus.gd"`; theme `res://assets/theme/nexus_theme.tres`;
  viewport 1280x720, stretch canvas_items/expand; renderer gl_compatibility.
- `Nexus._ready()`: `_build_core()` creates EventBus, WorldState, SimClock,
  CommandQueue, DataLoader, ModuleRegistry, SaveSystem; then deferred
  `_apply_ui_skin()` (UiSkinService + `data/ui_skin/skin.json`).

## Match setup — `core/game_bootstrap.gd`
- `setup_skirmish()` -> `register_modules()` (fixed order = tick order):
  difficulty, map, economy, logistics, buildings, tech_tree, units, hero_fusion,
  strategic_ai, ai_commander, diplomacy, combat, fog_of_war, victory, multiplayer.
- `load_catalogs()`: units, buildings, tech, difficulty, scenarios, stats
  (StatRegistry) -> `load_mods()`: folder mods `res://mods` then `.nexpack` packs
  from the content root (GameSettings/StorageService), last writer wins.
- Scenario: `modules/map/scenario_loader.gd`; match config via `match_config` section.

## Tick loop — `core/nexus.gd`
`_process(delta)` -> `sim_clock.advance(delta)` ticks ->
- single-player: `_run_single_tick()` N times;
- networked (multiplayer module active): `LockstepGateUtil.run_frame` (flush ->
  can_simulate gate -> inject -> simulate), emits lockstep stall/resume.
`_run_single_tick()`: `current_tick += 1`; due commands emitted ONCE as
`command.<type>`; `module_registry.tick_all(1)`; emit `core.tick`.

## App lifecycle
- `Nexus._notification(NOTIFICATION_APPLICATION_PAUSED)` -> `handle_app_backgrounded()`:
  pauses a running single-player match; never pauses a networked lockstep session.

## Commands
- HUD sim commands: `Nexus.player_command(type, data)` (lockstep-aware).
- Local presentation: `Nexus.issue_command("select_units", LOCAL_PLAYER, ...)`.
- Modules subscribe in `init()` via `nexus.subscribe("command.<type>", self, "_method")`.
- Ownership gate for selection: `Nexus.is_locally_controlled(owner)` (OwnershipUtil).

## Modules — `modules/*/*_module.gd` extend `IModule` (core/i_module.gd)
Contract: `module_id()`, `init(nexus)`, `on_tick(delta_tick)`, `handle_event`,
`serialize()`, `deserialize(data)`, `shutdown()`. State lives in WorldState sections.
De-facto cross-module access: `nexus.get_module("<id>")` returning a duck-typed Object
(e.g. buildings -> economy.try_spend). Pure helpers are `*_util.gd` (RefCounted,
static, deterministic, no SceneTree).

## State, hashing, saving
- `WorldState`: named Dictionary sections + `current_tick` + `random_seed`.
- `StateHasher.hash_world`: FNV-1a 64 over sorted keys; excludes LOCAL sections
  `lockstep`, `local_selection`, `ui_prefs` (`_LOCAL_SECTIONS`). Integral floats hash as ints.
- `SaveSystem.apply_snapshot` first runs `SaveSnapshotUtil.validate` (all-or-nothing;
  rejects malformed/newer saves without touching the live game). Same check in
  `SaveManager.import_save`.
- `SaveSystem` (SAVE_VERSION=1): world_state + modules.serialize_all + command_queue +
  sim_clock. `SaveManager`: user:// slots, export/import. `SafeFileUtil`: atomic writes.

## Presentation
- `render/render_adapter.gd` (Node2D under WorldLayer) + styles simple/detailed/sprite.
- HUDs: `ui/mobile/game_hud.gd` (`scenes/game_main.tscn`), `ui/desktop/desktop_hud.gd`
  (`scenes/game_desktop.tscn`); choice by `ui_mode` setting. Shared screens in `ui/shared/`.
  Shared pure HUD decisions: `ui/shared/hud_logic_util.gd` (HudLogicUtil, DEC-015).
- Text: `Localization.t(key)`; files `localization/en.json`, `localization/fa.json`.

## AI pipeline (modules/ai_commander/, fixed-point SCALE=1000)
raw stats -> capabilities (derived_metrics) -> roles -> personality weights + policy ->
context -> utility (unit/building) -> staged decision -> learning. Diplomacy AI in
`modules/diplomacy/`. Note: two classes `AiLearningUtil` (diplomacy) and
`AiRoleLearningUtil` (ai_commander) — different responsibilities.

## Tooling
Editors' headless models in `tools/` (mod_project, scenario_project, gui_project,
stat_registry, graphic_model ...). Linter `tools/check_code_policy.gd`. Smoke runners
`tools/scene_smoke.tscn`, `tools/game_smoke.tscn`. Release `tools/build_release.sh`.

## Tests
Single file `tests/test_runner.gd` (extends SceneTree). Tests are called manually from
`_init()`; helpers `_check`, `_check_or_skip`; exit 0/1.

## High-risk files (change only when the task names them)
core/nexus.gd, core/game_bootstrap.gd, core/state_hasher.gd, core/save_system.gd,
modules/multiplayer/*, ui/mobile/game_hud.gd (1603 lines), ui/shared/mod_editor.gd
(1605), ui/desktop/desktop_hud.gd (912), modules/ai_commander/strategic_ai_module.gd,
tests/test_runner.gd (append-only), project.godot, export_presets.cfg.
