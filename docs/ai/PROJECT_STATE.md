# Project state (agent reference)
Update at the end of every approved task (Claude provides the text).

## Baseline (after T002)
- Version 0.6.0. Engine Godot 4.7 (verified with 4.7.2). Roadmap P0-P9 complete.
- Gates: G1 lint 246 files no violations; G2 tests Total 4366 / Passed 4366 /
  Failed 0 / Skipped 0; G3 scene smoke failures=0 navigations=11; G4 game smoke
  failures=0; G5 clean tree after import; G6 exported Android pack boots with 0
  script errors. GitHub Actions CI runs G1-G6.

## Resolved in T002
- KI-1 CI inactive -> `.github/workflows/ci.yml` committed, Godot 4.7.2 (DEC-009).
- KI-2 Doc drift (CODE_MAP paths, BUG_REPORT refs, README counts, AGENT_RULES).
- KI-3 `.uid` inconsistency -> all tracked (DEC-007).
- KI-4 `tests/_tmp_scene_check.gd` removed.
- KI-6 local selection caused false desync -> `local_selection` section (DEC-008).
- KI-8 JSON save round-trip changed world hash -> integral floats hash as ints.
- KI-9 huge resume delta burst -> `SimClock.MAX_FRAME_DELTA = 0.5`.
- KI-10 exported builds broken (tools/* excluded, StatRegistry missing) -> filter fixed.
- KI-12 HUD/main menu left dead EventBus listeners -> `_exit_tree` unsubscribe_all.

## Open known issues
- KI-5 First editor import on a fresh checkout logs Vazirmatn font/theme errors
  (second import clean). Cosmetic; CI imports twice.
- KI-7 Mobile/desktop HUD logic partly duplicated (`ui/mobile/game_hud.gd`,
  `ui/desktop/desktop_hud.gd`). Refactor only via a dedicated task.
- KI-11 `docs/STRUCTURE.md` history still describes `docs/BUG_REPORT.md` (historical
  text, intentionally kept).
- Device-only confirmations pending: see docs/PLAN_ANDROID_FIXES_V2.md (bottom).

## Task log
| ID | Title | Status | Branch | Result |
|---|---|---|---|---|
| T001 | AI workflow bootstrap | merged (PR #1) | oh/T001-ai-workflow-bootstrap | APPROVED |
| T002 | Hardening: determinism, export, CI, docs | in progress | oh/T002-hardening | - |

## Candidate next tasks (Claude decides)
- T004 Android device QA checklist automation (what can be tested headless).
- T005 HUD duplication (KI-7) analysis document only.
