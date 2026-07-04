# CODE LANGUAGE POLICY (MANDATORY -- APPLIES TO THE ENTIRE PROJECT)

> **This is an absolute, non-negotiable rule for the whole project.**

**In the source code of the entire project, only English letters and characters must be used. No exceptions.**

This rule applies to **all** of the following:

- **Identifiers:** variable names, function names, class names, method names, signal names, node names, scene names, constant names, and enum names.
- **File and folder names:** all file names and directory names in the repository.
- **Keys and IDs in data files:** all JSON / `.tres` keys, module IDs, event names, resource keys, and configuration keys.
- **Code comments:** all in-code comments and docstrings.
- **Commit messages and branch names:** all Git history must be in English.
- **Log messages and error strings used internally** (technical / debug strings).
- **Asset identifiers:** internal names/handles of textures, sounds, and other assets referenced from code or data.

## Allowed Exceptions (exactly two)

**1. Localized display text.**
User-facing display text shown to the player (localized UI strings) MAY contain
non-English characters, **but only** when stored in dedicated localization files
(the `localization/` folder, e.g. `localization/en.json`, `localization/fa.json`).

Such display text must always be referenced from code through an **English
localization key** -- the key itself must be English (e.g. `ui.menu.start_game`).
Non-English characters must never leak into code identifiers, file names, data
keys, comments, or logic.

**2. Design documents under `docs/`.**
The design/planning documents in `docs/` (`STRUCTURE.md`, `CODE_MAP.md`,
`BUG_REPORT.md`, ...) are **intentionally written in Persian** for the project
owner and are NOT part of the shipping source code, so the ASCII-only rule does
not apply to their *contents*. Their **file names** must still be ASCII. The rule
of thumb is precise: **code = ASCII; `docs/*.md` = Persian allowed.** (The linter
was previously scanning these docs and reporting ~640 false violations, which
kept CI permanently red -- fixed as BUG-D3 by exempting `docs/`.)

## Rationale

This guarantees cross-platform encoding safety, prevents tooling/locale-related
bugs, keeps the codebase universally readable and contributable for the
open-source community, and avoids issues with engines, compilers, file systems,
and version control across different operating systems.

## Enforcement

A lightweight CI/lint check (`tools/check_code_policy.gd`, added in Phase 5
tooling) scans source files and rejects any non-ASCII character outside the two
allowed trees: `localization/` (display text) and `docs/` (Persian design docs).
It reports each violation as `file:line:col` and exits non-zero so CI fails fast.
Run it locally with:

```bash
godot --headless --path . --script res://tools/check_code_policy.gd
```

It runs automatically on every push / pull request via
`.github/workflows/ci.yml`, alongside the headless test suite.
