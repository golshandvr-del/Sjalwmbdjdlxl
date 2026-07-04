# Release & Packaging Guide (Phase 6.6)

Project Nexus is a real Godot 4.x project. Producing shippable builds is a
standard Godot **headless export**, driven from the committed
[`export_presets.cfg`](../export_presets.cfg) by the helper script
[`tools/build_release.sh`](../tools/build_release.sh).

The sandbox that authored this repository does not ship the Godot export
templates or the platform SDKs (Android SDK/NDK, signing keys, macOS toolchain),
so the **binary artifacts are produced on a developer/CI machine** that has them
installed. Everything needed to do that reproducibly is committed here
(`export_presets.cfg` is deliberately **not** git-ignored).

## Automated Android build (CI)

`.github/workflows/build-android.yml` builds an installable APK on GitHub
Actions. It installs Godot 4.x + the export templates + the Android SDK, runs the
same green-tree gates as `ci.yml` (CODE_POLICY lint + headless tests), generates
a throwaway debug keystore, exports the **Android** preset (`arm64-v8a`), and
uploads `project-nexus.apk` as a workflow artifact. It runs on demand
(*workflow_dispatch*) and on any `v*` tag, so ordinary pushes stay fast.

## Content bundling (why `include_filter` matters)

The engine loads its content at runtime with raw `FileAccess`/`DirAccess` over
`res://data`, `res://localization`, `res://mods` and the PNG textures under
`res://assets/textures`. Those raw `.json`/`.png` files are **not** Godot-imported
resources, so Godot would strip them from the exported `.pck` unless they are
listed in each preset's `include_filter`. Every preset in `export_presets.cfg`
therefore ships the same `include_filter` covering `data`, `localization`, `mods`
and the texture/font assets. If you add a new base-data folder, extend that
filter or the shipped build will silently miss it.

## Target platforms (priority order)

| Preset name        | Platform        | Arch          | Output (`export_path`)                  |
|--------------------|-----------------|---------------|-----------------------------------------|
| `Android`          | Android         | `arm64-v8a`   | `build/android/project-nexus.apk`       |
| `Linux/X11`        | Linux desktop   | `x86_64`      | `build/linux/project-nexus.x86_64`      |
| `Windows Desktop`  | Windows desktop | `x86_64`      | `build/windows/project-nexus.exe`       |
| `macOS`            | macOS           | `universal`   | `build/macos/project-nexus.zip`         |

> Android targets `arm64-v8a` (the modern 64-bit ABI required by Google Play).
> The 32-bit `armeabi-v7a` slice is left off by default to keep the APK small; if
> you must support very old devices, flip `architectures/armeabi-v7a=true` in
> `export_presets.cfg`.

## Prerequisites

1. **Godot 4.x** on `PATH` (or set `GODOT=/path/to/godot`).
2. **Export templates** for that exact Godot version
   (`godot --headless --export-release ...` needs them):
   install via the editor (*Editor -> Manage Export Templates*) or
   `godot --headless --install-export-templates`.
3. **Android only:** an Android SDK + NDK configured in the editor's Android
   settings, plus a debug/release **keystore** for signing.
4. **macOS only:** build on macOS (and, for distribution, code-sign/notarize).

## One-command build

```bash
# Build every preset (after running the lint + test gates):
tools/build_release.sh

# Or just specific presets:
tools/build_release.sh "Linux/X11" "Windows Desktop"
```

The script:

1. warms Godot's global class cache (`--editor --quit`) so a fresh checkout
   resolves every `class_name` script;
2. runs the **CODE_POLICY** linter (`tools/check_code_policy.gd`) -- English-only
   gate;
3. runs the **full headless test suite** (`tests/test_runner.gd`);
4. exports each requested preset with `--export-release`, writing to the
   `export_path` in `export_presets.cfg`.

A release can therefore only be cut from a **green** tree, mirroring CI.

## Manual export (single platform)

```bash
godot --headless --path . --export-release "Linux/X11" build/linux/project-nexus.x86_64
```

## Troubleshooting

- **"No export template found"** -> install the templates matching your Godot
  version (step 2 above).
- **`Could not find base class "IModule"`** -> open the project in the editor
  once (or `godot --headless --editor --quit`) to write
  `.godot/global_script_class_cache.cfg`, then re-run.
- **Android export fails** -> confirm the SDK/NDK paths and a keystore are set in
  the editor's Android export settings; the CLI reuses that configuration.
