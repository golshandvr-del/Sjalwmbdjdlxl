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

## DEC-004 Godot side effects are not committed
Modified `*.import` and newly generated `*.uid` are reverted/removed before commit,
until a dedicated task decides a `.uid` policy (KI-3).

## DEC-005 Verification gates
G1 lint, G2 tests (Failed: 0), G3 scene smoke, G4 game smoke, Godot 4.7.x headless.
A task is not acceptable unless all four pass and the exact result lines are reported.

## DEC-006 Tests
New tests are appended to `tests/test_runner.gd` and registered in `_init()`.
Existing tests are not edited/deleted without explicit task permission.
