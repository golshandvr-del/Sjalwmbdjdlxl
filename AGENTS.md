# AGENTS.md — Permanent rules for AI agents (Project Nexus)

Roles: **Claude = Architect / Tech Lead / Reviewer. OpenHands = Implementer.**
You implement exactly the task prompt you receive. You never redesign.

## 0. Read first (every task)
1. This file. 2. `docs/ai/ARCHITECTURE.md`. 3. `docs/ai/PROJECT_STATE.md`.
4. `docs/ai/DECISIONS.md`. 5. `docs/CODE_POLICY.md`. Then the task prompt.
Deep reference only when needed: `docs/STRUCTURE.md`, `docs/CODE_MAP.md`
(CODE_MAP has known drift: AI utils live in `modules/ai_commander/`, not `core/`).

## 1. Git workflow
- Branch per task: `oh/<task-id>-<slug>` from latest `main`. Never push to `main`. Never merge.
- Commit + push after each logical step (anti-loss rule). English commit messages.
- Stage files by explicit path only. Never `git add -A` / `git add .`.
- `.uid` policy (DEC-007, since T002): every `*.gd.uid` is tracked. When you add a
  new script, commit its generated `.uid` together with it. Never commit `.godot/`.
- After the editor import the tree must be clean (gate G5). If Godot modifies files
  you did not intend to touch, revert them:
  `git ls-files -m -- '*.import' | xargs -r git checkout --`.
- Never write tokens/credentials into files, remotes, logs or reports.

## 2. Scope discipline (forbidden unless the task says so)
- Architecture changes, broad refactors, renames, "cleanup", reformatting.
- Touching files outside the task's ALLOWED FILES list.
- New dependencies, plugins, addons, autoloads.
- Changing internal APIs, event names, command types, WorldState section keys,
  save format (`SAVE_VERSION`), `.nexpack` format, data schemas.
- Editing `project.godot`, `export_presets.cfg`, `.gitignore`, `ci/`, `.github/`.
- Excluding `tools/*` from export: `tools/` holds RUNTIME classes (StatRegistry,
  AiProfile, GuiProject ...) used by core/, modules/, ui/ (KI-10).
- Editing or deleting existing tests to make them pass.
- Modifying unrelated assets/scenes.

## 3. Hard invariants (never break)
- Determinism: sim logic uses only ticks, seeds, sorted keys, integers/fixed-point
  (`SCALE=1000`). No `randi()/randf()/randomize()`, no `Time.*`, no frame `delta`
  inside simulation code.
- Module registration order in `core/game_bootstrap.gd::register_modules` = tick order. Do not reorder.
- Commands: local human sim commands go through `Nexus.player_command`; each command is
  delivered once via EventBus `command.<type>`. `select_units` stays local `issue_command`.
- Cross-module access follows the existing pattern `nexus.get_module("<id>")` (duck-typed).
  Never `preload`/instantiate another module's class. Do not "fix" this pattern.
- Cosmetic (render/skin/theme/minimap/zoom/locale) never affects `StateHasher` output.
- Tools/editors (`tools/`) never touch WorldState.
- Source code is ASCII-only. Display text only in `localization/en.json` AND `fa.json`
  (same key in both), read via `Localization.t(key)` — never `tr()` (past bugs).
- New WorldState data: new section + `_ensure_state` in the owning module.

## 4. Tests and verification
- Godot 4.7.x headless. Gates (repo root):
  - G1 `godot --headless --path . --script res://tools/check_code_policy.gd`
  - G2 `godot --headless --path . --script res://tests/test_runner.gd` -> `Failed: 0`, exit 0
  - G3 `godot --headless --path . res://tools/scene_smoke.tscn` -> `SCENE_SMOKE_DONE failures=0`
  - G4 `godot --headless --path . res://tools/game_smoke.tscn` -> `GAME_SMOKE_DONE failures=0`
  - Run `godot --headless --editor --quit --path .` (twice on a fresh checkout) before G1.
  - G5 `git status --porcelain` is empty after G0-G4 (no Godot side effects).
  - G6 exported pack boots: `godot --headless --path . --export-pack "Android" /tmp/nexus.pck`
    then (from an empty dir) `godot --headless --main-pack /tmp/nexus.pck --quit-after 300`
    must print no `SCRIPT ERROR` / `ERROR: Failed to load`.
  - The same gates run on GitHub Actions (`.github/workflows/ci.yml`) for `main`,
    `oh/**`, `claude/**` and PRs. A red CI run means the task is not done.
- Every new test function in `tests/test_runner.gd` MUST also be added to the call list
  in `_init()` (before `_print_summary()`), or it never runs. Use `_check(cond, label)`.
- Bug fixes come with a regression test that fails before the fix.
- If a test and code disagree: assume the code is right and the test stale, unless
  evidence says otherwise — and report it; do not silently edit tests.

## 4.1 Known Godot traps for this repo
See `docs/ai/GODOT_PITFALLS.md` before touching save/load, hashing, export,
SimClock, signals or localization.

## 5. Ambiguity policy
1. Look for the answer in repo code/docs/conventions. 2. If inferable, decide.
3. Several options -> smallest change, lowest regression risk, most consistent.
4. Requirement conflict or destructive/high-impact risk -> STOP and report.
5. Record every significant assumption in the final report.

## 6. Final report
Always use the FINAL REPORT FORMAT from the task prompt. Quote real command output.
Never claim a gate passed without its result line.
