# icon_manifest_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - UI Icon Manifest Utilities (Phase MC3, req 3).
#
# A PURE, dependency-free helper for the UI icon manifest (data/ui_icons/
# manifest.json). It owns no engine state: it takes the already-parsed manifest
# Dictionary and answers "what is the file path / intended size for logical
# icon N", validating shape and applying sensible fallbacks. This keeps the
# manifest rules (which the IconService relies on) unit-testable headlessly
# without loading real textures.
#
# WHY DATA-DRIVEN ICONS: today every HUD/menu button is a raw Godot button with
# no art. The manifest maps a stable LOGICAL name (e.g. "settings_gear") to an
# art file, so art can be dropped in later (per docs/ASSET_PROMPTS_fa.md) without
# touching code, and a missing file degrades to a drawn glyph instead of
# crashing.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name IconManifestUtil
extends RefCounted

# The default square size (px) used when a manifest entry omits "size" or the
# top-level "base_size" is absent.
const DEFAULT_BASE_SIZE: int = 128


# True if `manifest` is a well-formed icon manifest (has an "icons" dictionary).
# Pure.
static func is_valid(manifest: Dictionary) -> bool:
	return manifest.has("icons") and (manifest["icons"] is Dictionary)


# The top-level base size, or DEFAULT_BASE_SIZE if missing/invalid. Pure.
static func base_size(manifest: Dictionary) -> int:
	var value: int = int(manifest.get("base_size", DEFAULT_BASE_SIZE))
	return value if value > 0 else DEFAULT_BASE_SIZE


# Every logical icon name declared in the manifest, sorted for a stable order.
# Pure.
static func icon_names(manifest: Dictionary) -> Array:
	if not is_valid(manifest):
		return []
	var names: Array = (manifest["icons"] as Dictionary).keys()
	names.sort()
	return names


# True if `name` is declared in the manifest. Pure.
static func has_icon(manifest: Dictionary, name: String) -> bool:
	return is_valid(manifest) and (manifest["icons"] as Dictionary).has(name)


# The file path for logical icon `name`, or "" if the icon/entry is missing or
# malformed. Pure (does not check the file exists on disk -- that is the engine
# half's job).
static func path_for(manifest: Dictionary, name: String) -> String:
	if not has_icon(manifest, name):
		return ""
	var entry: Variant = (manifest["icons"] as Dictionary)[name]
	if not (entry is Dictionary):
		return ""
	return str((entry as Dictionary).get("path", ""))


# The intended square size (px) for logical icon `name`. Falls back to the
# manifest base size, then DEFAULT_BASE_SIZE. Pure.
static func size_for(manifest: Dictionary, name: String) -> int:
	var fallback: int = base_size(manifest)
	if not has_icon(manifest, name):
		return fallback
	var entry: Variant = (manifest["icons"] as Dictionary)[name]
	if not (entry is Dictionary):
		return fallback
	var value: int = int((entry as Dictionary).get("size", fallback))
	return value if value > 0 else fallback
