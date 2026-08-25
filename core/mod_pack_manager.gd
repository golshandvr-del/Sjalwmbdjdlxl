# mod_pack_manager.gd
# ----------------------------------------------------------------------------
# Project Nexus - Active-Mod Pack Manager (core component, Phase P4 / R5).
#
# R5 asks for exporting the WHOLE set of active content (units / buildings /
# objects / scenarios / tech) into a single portable `.nexpack`, and importing
# such a pack and activating it. This wraps the existing, fully-tested pack layer
# (PackWriter / PackReader / PackFormat / ModLoader) so the UI has one simple
# surface to call.
#
# Design notes:
#   - "Active content" = whatever the running DataLoader currently holds across
#     the standard catalogs. Exporting is a snapshot of the merged catalogs, so a
#     freshly-installed copy that imports the pack ends up with the same content
#     and therefore the same deterministic catalog hash (lockstep-safe, R7).
#   - Textures referenced by entries are pulled from the StorageService content
#     root (and res:// fallback) and embedded so the pack is self-contained.
#   - Import writes the pack into the content root and loads it through the same
#     ModLoader path used at startup, so there is exactly one code path for mods.
#
# Everything here is tooling: it reads catalogs and writes/reads files. It never
# touches WorldState or the deterministic hash directly.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name ModPackManager
extends RefCounted

# The standard catalogs an exported bundle carries.
const CATALOGS: Array = ["units", "buildings", "objects", "scenarios", "tech"]

var _nexus: Object = null


func setup(nexus: Object) -> void:
	_nexus = nexus


# Export the currently-loaded content into a single `.nexpack` at `out_path`.
# `pack_id` / `pack_name` identify the bundle in its manifest. Returns true on
# success. Empty catalogs are skipped.
func export_active(out_path: String, pack_id: String = "exported_content", pack_name: String = "Exported Content") -> bool:
	if _nexus == null:
		push_error("ModPackManager: not set up")
		return false
	var data_loader: Object = _nexus.data_loader
	if data_loader == null:
		push_error("ModPackManager: no data loader")
		return false

	var files: Dictionary = {}
	var provides: Dictionary = {}
	var texture_refs: Dictionary = {}   # relative texture path -> true (dedup)

	for catalog_name in CATALOGS:
		var catalog: Dictionary = data_loader.get_catalog(catalog_name)
		if catalog.is_empty():
			continue
		var entry_paths: Array = []
		var ids: Array = catalog.keys()
		ids.sort()  # deterministic archive
		for entry_id in ids:
			var entry: Variant = catalog[entry_id]
			if not (entry is Dictionary):
				continue
			var rel: String = "data/%s/%s.json" % [catalog_name, str(entry_id)]
			files[rel] = JSON.stringify(entry as Dictionary, "\t")
			entry_paths.append(rel)
			_collect_texture_refs(entry as Dictionary, texture_refs)
		if not entry_paths.is_empty():
			provides[catalog_name] = entry_paths

	if provides.is_empty():
		push_error("ModPackManager: nothing to export (no loaded content)")
		return false

	# Embed referenced textures (self-contained pack).
	for rel_tex in texture_refs.keys():
		var bytes: PackedByteArray = _read_texture_bytes(str(rel_tex))
		if bytes.size() > 0:
			files[str(rel_tex)] = bytes

	var manifest: Dictionary = {
		"id": pack_id,
		"name": pack_name,
		"version": "1.0.0",
		"author": "Project Nexus",
		"enabled": true,
		"load_after": [],
		"provides": provides,
	}
	return PackWriter.write_from_data(manifest, files, out_path)


# Import a `.nexpack` from `src_path`: copy it into the content root and load it
# into the running catalogs via the standard ModLoader path. Returns true on
# success.
func import_pack(src_path: String) -> bool:
	if _nexus == null:
		return false
	if not FileAccess.file_exists(src_path):
		push_error("ModPackManager: import source not found '%s'" % src_path)
		return false
	# Validate it is a readable pack with a valid manifest before accepting it.
	var reader: PackReader = PackReader.new()
	if not reader.open(src_path):
		push_error("ModPackManager: '%s' is not a readable pack" % src_path)
		return false
	var manifest: Variant = reader.read_manifest()
	reader.close()
	if not PackFormat.is_manifest_valid(manifest):
		push_error("ModPackManager: pack has an invalid manifest")
		return false

	var storage: Object = _resolve_storage()
	if storage == null:
		push_error("ModPackManager: no storage service")
		return false
	storage.ensure_content_root()
	var pack_id: String = str((manifest as Dictionary).get("id", "imported_pack"))
	var dest: String = storage.resolve(PackFormat.pack_file_name(pack_id))
	# Copy the bytes into the content root (atomic: a kill mid-import must not
	# leave a torn .nexpack that shadows a previously good one).
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src_path)
	if not SafeFileUtil.write_bytes(dest, bytes):
		push_error("ModPackManager: cannot write pack to content root '%s'" % dest)
		return false
	# Load all packs (including the new one) into the live catalogs.
	var texture_service: Object = _nexus.get("texture_service") if _nexus.has_method("get") else null
	ModLoader.load_packs(_nexus.data_loader, storage, texture_service)
	return true


# --- Internals --------------------------------------------------------------

# Build a StorageService pointed at the player's configured content root, exactly
# like GameBootstrap.load_packs does (there is no single storage autoload).
func _resolve_storage() -> Object:
	var settings: GameSettings = GameSettings.new(_nexus.world_state)
	settings.load_from_file()
	return StorageService.new(settings.get_content_path())

# Walk an entry's graphic/visual block(s) and collect any texture paths it
# references, so the exported pack is truly SELF-CONTAINED on another machine.
func _collect_texture_refs(entry: Dictionary, refs: Dictionary) -> void:
	var graphic: Variant = entry.get("graphic", null)
	if graphic is Dictionary:
		var parts: Variant = (graphic as Dictionary).get("parts", [])
		if parts is Array:
			for part in (parts as Array):
				if part is Dictionary and (part as Dictionary).has("texture"):
					refs[str((part as Dictionary)["texture"])] = true
	# The render layer's primary field: `visual.texture` (see TextureService and
	# the base data/units/*.json). Without this an exported pack silently drops
	# every texture referenced the standard way.
	var visual: Variant = entry.get("visual", null)
	if visual is Dictionary and (visual as Dictionary).has("texture"):
		var tex: String = str((visual as Dictionary)["texture"])
		if tex != "":
			refs[tex] = true
	# Legacy / simple single-texture field.
	if entry.has("texture"):
		refs[str(entry["texture"])] = true


# Read a texture's bytes from the content root first, then res:// as a fallback.
func _read_texture_bytes(rel_path: String) -> PackedByteArray:
	var candidates: Array = []
	var storage: Object = _resolve_storage()
	if storage != null:
		candidates.append(storage.resolve(rel_path))
	candidates.append("res://" + rel_path)
	candidates.append("res://mods/" + rel_path)
	for path in candidates:
		if FileAccess.file_exists(path):
			return FileAccess.get_file_as_bytes(path)
	return PackedByteArray()
