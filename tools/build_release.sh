#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Project Nexus - Release build driver (Phase 6, step 6.6).
#
# A thin, reproducible wrapper around Godot's headless exporter that turns the
# committed export_presets.cfg into shippable builds for every target platform
# (Android first, then Linux, Windows, macOS). It runs the CODE_POLICY linter
# and the full headless test suite FIRST, so a release can only be produced from
# a green tree -- the same gates CI enforces.
#
# It does NOT bundle Godot or the export templates (those are large binaries and
# platform/SDK specific); instead it expects a Godot 4.x binary on PATH (or via
# the GODOT env var) with the matching export templates installed, exactly as a
# normal Godot release pipeline does. See docs/RELEASE.md for the full setup.
#
# Usage:
#   tools/build_release.sh [preset-name ...]
# With no arguments it builds every preset below. Examples:
#   tools/build_release.sh
#   tools/build_release.sh "Linux/X11" "Windows Desktop"
#
# CODE LANGUAGE POLICY: English-only.
# ----------------------------------------------------------------------------
set -euo pipefail

# Resolve the project root (this script lives in tools/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

GODOT_BIN="${GODOT:-godot}"
if ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
  echo "ERROR: Godot binary '${GODOT_BIN}' not found on PATH."
  echo "       Install Godot 4.x and/or set GODOT=/path/to/godot."
  exit 1
fi

# Every preset name from export_presets.cfg.
DEFAULT_PRESETS=("Android" "Linux/X11" "Windows Desktop" "macOS")
if [[ "$#" -gt 0 ]]; then
  PRESETS=("$@")
else
  PRESETS=("${DEFAULT_PRESETS[@]}")
fi

echo "==== Project Nexus :: Release Build ===="
echo "Godot:   $(${GODOT_BIN} --version 2>/dev/null || echo unknown)"
echo "Project: ${PROJECT_DIR}"

# 1) Warm the global class cache so the linter / tests / exporter resolve every
#    `class_name`-registered script on a fresh checkout.
echo "--> Importing project (warming class cache)"
"${GODOT_BIN}" --headless --editor --quit --path . >/dev/null 2>&1 || true

# 2) Gate: English-only CODE_POLICY.
echo "--> CODE_POLICY lint"
"${GODOT_BIN}" --headless --path . --script res://tools/check_code_policy.gd

# 3) Gate: full headless test suite.
echo "--> Headless test suite"
"${GODOT_BIN}" --headless --path . --script res://tests/test_runner.gd

# 3b) Gate: MA6 scene-based touch probe. Runs as a MAIN SCENE (not --script) so
# the Nexus autoload + live input pipeline exist, proving a real
# InputEventScreenTouch selects a unit and moves it end-to-end. It quits with a
# non-zero exit code on failure, so set -e stops the build here.
echo "--> MA6 scene touch probe"
"${GODOT_BIN}" --headless --path . res://tests/ma6_touch_probe.tscn

# 4) Export each requested preset.
for preset in "${PRESETS[@]}"; do
  echo "--> Exporting preset: ${preset}"
  # --export-release writes to the export_path declared in export_presets.cfg.
  if ! "${GODOT_BIN}" --headless --path . --export-release "${preset}"; then
    echo "WARNING: export of '${preset}' failed (missing export templates or"
    echo "         platform SDK?). See docs/RELEASE.md. Continuing."
  fi
done

echo "==== Done. Artifacts (if any) are under build/ ===="
ls -R build 2>/dev/null || echo "(no build/ artifacts produced in this environment)"
