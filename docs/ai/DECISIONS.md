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
