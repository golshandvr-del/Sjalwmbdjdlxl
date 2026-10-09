# Project state (agent reference)
Update at the end of every approved task (Claude provides the text).

## Baseline (after T005)
- Version 0.6.0. Engine Godot 4.7 (verified with 4.7.2). Roadmap P0-P9 complete.
- Gates: G1 lint 246 files no violations; G2 tests Total 4544 / Passed 4544 /
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

## Resolved in T003
- KI-13 Malformed/newer save files were half-applied (world wiped, script errors) ->
  `SaveSnapshotUtil.validate` gate in SaveSystem.apply_snapshot + SaveManager.import_save.
- KI-14 Per-device `ui_prefs` (locale/style/zoom) were hashed -> false desync between
  peers with different settings -> `ui_prefs` added to `_LOCAL_SECTIONS`.
- KI-15 App backgrounded on Android kept the match running -> single-player auto-pause.
- KI-16 No guard that literal `t("...")` keys exist in both locales -> test added.

## Open known issues
- KI-5 First editor import on a fresh checkout logs Vazirmatn font/theme errors
  (second import clean). Cosmetic; CI imports twice.
- KI-7 (partly resolved T004) Pure HUD decisions now live in `ui/shared/hud_logic_util.gd`
  (HudLogicUtil): local HQ, next research node, controlled owners, owner count,
  speed cycle, style label key, match result key, chat history, mission proposal.
  Remaining duplication is node-building/UI code (tab builders, input handlers) -> T005. T005 moved treaty proposal and target-owner pickers too; remaining duplication = node-building code only.
- KI-11 `docs/STRUCTURE.md` history still describes `docs/BUG_REPORT.md` (historical
  text, intentionally kept).
- Device-only confirmations pending: see docs/PLAN_ANDROID_FIXES_V2.md (bottom).

## T006 "Frontier" (in review)
The `frontier` mod is enabled by default: 12 units, 12 buildings, a 10-node tech
tree, defensive watchtowers/cannon towers and walls, a second resource
(`resource_energy`), and three natural-map scenarios (`fr_river_valley`,
`fr_four_realms`, `fr_border_siege`). New general engine features: `PrereqUtil`,
production from any building, forest terrain + ASCII `map.rows`, scenario `hq_type`
and `rules { pop_cap, full_ai, faction_prefix }`, defensive buildings, and
`counts_for_survival: false`. `rules.full_ai` drives a full-tree strategic AI via
`FullTreeOrderUtil`. See DEC-017 / DEC-018 and `docs/mods/frontier.md`.
Objective judge `tests/acceptance/t006_acceptance.gd` reports, verbatim:
`T006_SUMMARY pass=148 fail=0`. Vanilla scenarios are unchanged (A1/A2 goldens).

## Task log
| ID | Title | Status | Branch | Result |
|---|---|---|---|---|
| T001 | AI workflow bootstrap | merged (PR #1) | oh/T001-ai-workflow-bootstrap | APPROVED |
| T002 | Hardening: determinism, export, CI, docs | merged (PR #2) | claude/T002-hardening | done by Claude |
| T003 | Hardening 2: save validation, ui_prefs hash, app pause, l10n guard | merged (PR #3) | claude/T003-hardening | done by Claude |
| T004 | HudLogicUtil (KI-7 part 1) + save/QA + long-run determinism tests | merged (PR #4) | claude/T004-reference | done by Claude |
| T005 | HUD dedup part 2 + scenario determinism matrix + docs | PR open (OpenHands) | oh/T005-hud-dedup-scenarios | awaiting Claude review |
| T006 | Frontier mod (tech tree, defenses, natural maps, full AI) | in review | oh/T006-frontier | T006_SUMMARY pass=148 fail=0 |

## Candidate next tasks (Claude decides)
- T007 Android device QA checklist (docs/ai/DEVICE_QA.md) — Claude decides.
