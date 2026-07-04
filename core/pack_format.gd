# pack_format.gd
# ----------------------------------------------------------------------------
# Project Nexus - .nexpack Package Format definition (Phase C, step C.3).
#
# A `.nexpack` is the project's PORTABLE CONTENT PACKAGE: a single ZIP file that
# bundles a whole mod / custom game (its manifest, data JSON, and textures) into
# one file the player can copy, share, or install without unzipping. The Mod
# Editor (Phase D) writes these; the PackReader (Phase C.4) loads them directly
# with Godot's `ZIPReader`, no full extraction required.
#
# This file is the SINGLE SOURCE OF TRUTH for the on-disk layout so the writer
# (C.6) and reader (C.4) can never drift apart. It contains only constants and
# tiny pure helpers -- no I/O, no engine singletons, no simulation state.
#
# ---------------------------------------------------------------------------
# On-disk layout INSIDE the ZIP (all paths forward-slash, relative to the root):
#
#   manifest.json                 # REQUIRED. The same schema as a mods/<id>/mod.json
#                                 #   manifest (id, name, version, author, enabled,
#                                 #   load_after, provides). `provides` maps a
#                                 #   catalog name -> [relative data paths], e.g.
#                                 #   { "buildings": ["data/buildings/raw_wall.json"] }.
#   data/units/<id>.json          # OPTIONAL. Added/overridden unit definitions.
#   data/buildings/<id>.json      # OPTIONAL. Added/overridden building definitions.
#   data/<catalog>/<id>.json      # OPTIONAL. Any other catalog (tech, scenarios...).
#   textures/<name>.png           # OPTIONAL. Art referenced by a visual.texture.
#
# The format is intentionally identical to an UNPACKED mod folder (the existing
# `mods/<id>/` layout), so:
#   - the same `ModLoader.apply_mod()` merge logic works on a pack's manifest;
#   - a pack can be unzipped into `mods/` and still load, and vice-versa;
#   - the TextureService resolves `textures/...` against a pack root exactly as
#     it already does for a base/mod root.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PackFormat
extends RefCounted

# Canonical extension (without the dot) and the manifest entry name in the ZIP.
const EXTENSION: String = "nexpack"
const MANIFEST_NAME: String = "manifest.json"

# Top-level folders inside the package.
const DATA_DIR: String = "data"
const TEXTURES_DIR: String = "textures"

# Required + optional manifest fields (mirrors the ModLoader manifest schema).
const REQUIRED_MANIFEST_FIELDS: Array = ["id"]
const KNOWN_MANIFEST_FIELDS: Array = [
	"id", "name", "version", "author", "enabled", "load_after", "provides",
]


# True when `file_name` looks like a package file (case-insensitive extension).
static func is_pack_file(file_name: String) -> bool:
	return file_name.strip_edges().to_lower().ends_with("." + EXTENSION)


# Build a canonical pack file name from a bare mod id ("my_mod" -> "my_mod.nexpack").
# An id that already carries the extension is returned unchanged.
static func pack_file_name(mod_id: String) -> String:
	var id: String = mod_id.strip_edges()
	if is_pack_file(id):
		return id
	return id + "." + EXTENSION


# Validate a manifest Dictionary against the format. Returns an Array of human
# readable problem strings; an empty Array means the manifest is well-formed.
# This is shared by the writer (refuse to save garbage) and reader (skip bad
# packs with a clear reason) so both agree on what "valid" means.
static func validate_manifest(manifest: Variant) -> Array:
	var problems: Array = []
	if not (manifest is Dictionary):
		problems.append("manifest is not a JSON object")
		return problems
	var m: Dictionary = manifest as Dictionary
	for field in REQUIRED_MANIFEST_FIELDS:
		if not m.has(field) or str(m[field]).strip_edges().is_empty():
			problems.append("missing required field '%s'" % field)
	# `provides`, when present, must map catalog name -> Array of relative paths.
	if m.has("provides"):
		if not (m["provides"] is Dictionary):
			problems.append("'provides' must be an object (catalog -> [paths])")
		else:
			for catalog_name in (m["provides"] as Dictionary).keys():
				if not (m["provides"][catalog_name] is Array):
					problems.append("'provides.%s' must be an array of paths" % str(catalog_name))
	# `load_after`, when present, must be an Array.
	if m.has("load_after") and not (m["load_after"] is Array):
		problems.append("'load_after' must be an array of mod ids")
	return problems


# Convenience: a manifest is valid when validate_manifest returns no problems.
static func is_manifest_valid(manifest: Variant) -> bool:
	return validate_manifest(manifest).is_empty()


# Collect every relative data path declared in a manifest's `provides` map, in a
# deterministic order (catalogs sorted by name, paths in declared order). Used by
# the writer to know which files to pull into the ZIP.
static func provided_data_paths(manifest: Dictionary) -> Array:
	var paths: Array = []
	var provides: Variant = manifest.get("provides", {})
	if not (provides is Dictionary):
		return paths
	var catalog_names: Array = (provides as Dictionary).keys()
	catalog_names.sort()
	for catalog_name in catalog_names:
		var entry: Variant = (provides as Dictionary)[catalog_name]
		if entry is Array:
			for rel_path in (entry as Array):
				paths.append(str(rel_path))
	return paths
