# Project state (agent reference)
Update at the end of every approved task (Claude provides the text).

## Baseline
- Commit: 98a8866 (main). Version 0.6.0. Engine Godot 4.7 (verified with 4.7.2).
- G1 lint: 246 files, no violations. G2 tests: Total 4334 / Passed 4334 / Failed 0 /
  Skipped 0. G3 scene smoke failures=0 navigations=11. G4 game smoke failures=0.

## Known issues / debt (not yet tasked)
- KI-1 GitHub CI inactive: `.github/workflows/` is gitignored; mirror `ci/ci.yml`
  pins Godot 4.2.2 while project targets 4.7.
- KI-2 Doc drift: CODE_MAP lists ai_* utils under core/ (actually
  modules/ai_commander/); `docs/BUG_REPORT.md` deleted but still referenced; README
  test counts outdated.
- KI-3 `.uid` inconsistency: 71 tracked, ~88 generated untracked by Godot 4.7.
- KI-4 `tests/_tmp_scene_check.gd` says "removed after use" but still present.
- KI-5 First editor import on fresh checkout logs Vazirmatn font/theme errors
  (second import clean).
- KI-6 SUSPECTED (unverified at runtime): local `select_units` writes
  `world_state.units.selected`, which StateHasher includes -> possible false desync
  in networked sessions.
- KI-7 Mobile/desktop HUD logic partly duplicated.
- Device-only confirmations pending: see docs/PLAN_ANDROID_FIXES_V2.md (bottom).

## Task log
| ID | Title | Status | Branch | Result |
|---|---|---|---|---|
| T001 | AI workflow bootstrap | in progress | oh/T001-ai-workflow-bootstrap | - |

## Candidate next tasks (Claude decides)
- T002 Investigate KI-6 with a two-peer loopback regression test (test only, no fix).
- T003 Fix doc drift KI-2.
