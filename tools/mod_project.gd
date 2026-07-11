# mod_project.gd
# ----------------------------------------------------------------------------
# Project Nexus - Mod Editor data model + save engine (Phase D, steps D.2-D.7).
#
# `ModProject` is the IN-MEMORY model of a mod being authored in the graphical
# Mod Editor (Phase D). It deliberately holds ZERO UI: the editor scene
# (`ui/shared/mod_editor.gd`) is a thin view that drives this object, while ALL
# of the authoring logic -- create / open / edit units + buildings / validate /
# save -- lives here so it can be exercised fully headless by the test runner.
#
# What it owns:
#   - a `manifest` Dictionary (id / name / version / author / enabled / provides)
#   - a `units`     Dictionary: unit_id     -> unit definition Dictionary
#   - a `buildings` Dictionary: building_id -> building definition Dictionary
#   - a `textures`  Dictionary: "textures/<name>.png" -> PackedByteArray
#
# How it maps to a `.nexpack` (Phase C format, the SINGLE source of truth):
#   - each unit/building becomes `data/units/<id>.json` / `data/buildings/<id>.json`
#   - `manifest.provides` is rebuilt deterministically from those entries
#   - textures are bundled verbatim
#   - PackWriter.write_from_data() does the actual ZIP write (validated first)
# Opening reverses this through PackReader, so a project round-trips losslessly.
#
# Design rules (consistent with the rest of the project):
#   - PURE INFRASTRUCTURE / TOOLING: never touches WorldState or the sim hash.
#   - SAFE + VALIDATING: ids are normalised; bad input is rejected with a reason
#     rather than corrupting the model; saving refuses an invalid manifest.
#   - DETERMINISTIC: entries are emitted in sorted order so the same project
#     always produces the same pack (friendly to diffing / caching).
#   - English-only identifiers/comments (CODE_POLICY); any author-facing text the
#     UI shows is resolved through Localization, not stored here.
# ----------------------------------------------------------------------------
class_name ModProject
extends RefCounted

# The two catalogs the editor can author in Phase D. Map editor / scenario
# authoring (other catalogs) arrives in Phase E; the model already stores them
# generically via `provides`, so extending it later needs no format change.
const UNITS_CATALOG: String = "units"
const BUILDINGS_CATALOG: String = "buildings"
# Phase E adds two more catalogs to the SAME pack so a single .nexpack can ship a
# whole playable "custom game" (units + buildings + scenarios + a simple tech
# tree). The pack format already supported arbitrary catalogs (PackFormat C.3),
# so this needs no format change -- only that ModProject now author them too.
const SCENARIOS_CATALOG: String = "scenarios"
const TECH_CATALOG: String = "tech"
# Phase E5 adds a brand-new `objects` catalog (map decorations / extractable
# resource nodes). The pack format already accepts arbitrary catalogs, so this is
# purely a ModProject addition.
const OBJECTS_CATALOG: String = "objects"

# Virtual tree roots (Phase E2.1). These are NEVER stored in JSON; they exist
# only so the editor can hang real nodes under a stable parent. A node whose
# `editor.parent_id` is one of these is a top-level node in its catalog's tree.
const ROOT_UNIT: String = "root_unit"
const ROOT_BUILDING: String = "root_building"
const ROOT_OBJECT: String = "root_object"

# Hard balance cap: an upgrade may grow a base layer by at most +15% (plan 2.4).
const UPGRADE_SIZE_CAP: float = 0.15

# A new, empty project's manifest defaults.
const DEFAULT_VERSION: String = "0.1.0"

var manifest: Dictionary = {}
var units: Dictionary = {}      # id -> Dictionary
var buildings: Dictionary = {}  # id -> Dictionary
var scenarios: Dictionary = {}  # id -> scenario Dictionary (Phase E)
var tech: Dictionary = {}       # id -> tech definition Dictionary (Phase E)
var objects: Dictionary = {}    # id -> map-object definition Dictionary (Phase E5)
var textures: Dictionary = {}   # "textures/<name>.png" -> PackedByteArray


func _init() -> void:
	new_project("new_mod", "New Mod")


# --- Project lifecycle (D.2) ------------------------------------------------

# Reset to a fresh, empty project with the given id + display name. An invalid id
# falls back to a safe default so the model is never left unusable.
func new_project(mod_id: String, display_name: String = "") -> void:
	var clean_id: String = normalise_id(mod_id)
	if clean_id == "":
		clean_id = "new_mod"
	manifest = {
		"id": clean_id,
		"name": display_name.strip_edges() if display_name.strip_edges() != "" else clean_id,
		"version": DEFAULT_VERSION,
		"author": "",
		"enabled": true,
		"load_after": [],
		"provides": {},
	}
	units = {}
	buildings = {}
	scenarios = {}
	tech = {}
	objects = {}
	textures = {}


# Open an existing `.nexpack` into this project (replacing current content).
# Returns true on success; on any failure the project is left UNCHANGED so a bad
# file never destroys in-progress work.
func open_pack(path: String) -> bool:
	var reader: PackReader = PackReader.new()
	if not reader.open(path):
		return false
	var read_manifest: Variant = reader.read_manifest()
	if read_manifest == null:
		reader.close()
		return false

	# Build the new state into locals first; only commit if nothing failed.
	var new_units: Dictionary = {}
	var new_buildings: Dictionary = {}
	var new_scenarios: Dictionary = {}
	var new_tech: Dictionary = {}
	var new_objects: Dictionary = {}
	var new_textures: Dictionary = {}

	var catalogs: Dictionary = reader.read_catalogs()
	for entry in (catalogs.get(UNITS_CATALOG, {}) as Dictionary).values():
		if entry is Dictionary:
			new_units[str((entry as Dictionary).get("id", ""))] = (entry as Dictionary).duplicate(true)
	for entry in (catalogs.get(BUILDINGS_CATALOG, {}) as Dictionary).values():
		if entry is Dictionary:
			new_buildings[str((entry as Dictionary).get("id", ""))] = (entry as Dictionary).duplicate(true)
	# Phase E catalogs (scenarios + tech) round-trip the same generic way.
	for entry in (catalogs.get(SCENARIOS_CATALOG, {}) as Dictionary).values():
		if entry is Dictionary:
			new_scenarios[str((entry as Dictionary).get("id", ""))] = (entry as Dictionary).duplicate(true)
	for entry in (catalogs.get(TECH_CATALOG, {}) as Dictionary).values():
		if entry is Dictionary:
			new_tech[str((entry as Dictionary).get("id", ""))] = (entry as Dictionary).duplicate(true)
	# Phase E5: map objects round-trip the same generic way.
	for entry in (catalogs.get(OBJECTS_CATALOG, {}) as Dictionary).values():
		if entry is Dictionary:
			new_objects[str((entry as Dictionary).get("id", ""))] = (entry as Dictionary).duplicate(true)

	# Pull in any bundled textures verbatim (binary-safe).
	var prefix: String = PackFormat.TEXTURES_DIR + "/"
	for entry_path in reader.list_entries():
		if str(entry_path).begins_with(prefix):
			new_textures[str(entry_path)] = reader.read_bytes(str(entry_path))
	reader.close()

	# Commit. Drop the loader-only "_pack" marker the reader adds.
	var m: Dictionary = (read_manifest as Dictionary).duplicate(true)
	m.erase("_pack")
	manifest = m
	units = new_units
	buildings = new_buildings
	scenarios = new_scenarios
	tech = new_tech
	objects = new_objects
	textures = new_textures
	return true


# --- Full-project snapshot (MC5.3, request 6) -------------------------------
#
# A deep, self-contained copy of the ENTIRE in-memory project (manifest + every
# catalog + bundled textures). Used by the editor's undo/redo history so a single
# stored entry captures the whole authoring state. Deep-duplicated so a stored
# snapshot is fully isolated from later edits. Textures (PackedByteArray) survive
# the duplicate(true) intact.
func to_snapshot() -> Dictionary:
	return {
		"manifest": manifest.duplicate(true),
		"units": units.duplicate(true),
		"buildings": buildings.duplicate(true),
		"scenarios": scenarios.duplicate(true),
		"tech": tech.duplicate(true),
		"objects": objects.duplicate(true),
		"textures": textures.duplicate(true),
	}


# Replace the whole project from a snapshot produced by to_snapshot(). Missing
# sections fall back to empty so a partial/legacy snapshot cannot corrupt the
# model. Returns true when the snapshot looked usable (had a manifest).
func from_snapshot(snapshot: Dictionary) -> bool:
	if not (snapshot.get("manifest") is Dictionary):
		return false
	manifest = (snapshot.get("manifest") as Dictionary).duplicate(true)
	units = _snapshot_section(snapshot, "units")
	buildings = _snapshot_section(snapshot, "buildings")
	scenarios = _snapshot_section(snapshot, "scenarios")
	tech = _snapshot_section(snapshot, "tech")
	objects = _snapshot_section(snapshot, "objects")
	textures = _snapshot_section(snapshot, "textures")
	return true


# Deep-copy one section of a snapshot, defaulting to an empty Dictionary.
func _snapshot_section(snapshot: Dictionary, key: String) -> Dictionary:
	var value: Variant = snapshot.get(key, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


# --- Unit editing (D.3) -----------------------------------------------------

# Add or replace a unit definition. `definition` may omit "id"; the passed `id`
# is authoritative and written back into the stored copy. Returns true on
# success, false (model unchanged) when the id is invalid.
func set_unit(id: String, definition: Dictionary) -> bool:
	var clean: String = normalise_id(id)
	if clean == "":
		return false
	var copy: Dictionary = definition.duplicate(true)
	copy["id"] = clean
	units[clean] = copy
	return true


func remove_unit(id: String) -> bool:
	var clean: String = normalise_id(id)
	if units.has(clean):
		units.erase(clean)
		return true
	return false


func get_unit(id: String) -> Dictionary:
	var clean: String = normalise_id(id)
	if units.has(clean):
		return units[clean]
	return {}


# Convenience for the UI: build a sensible default unit so a freshly-added unit
# is already valid + visible (round body, given colour). Phase E3 adds the tree
# metadata + single-part `graphic` block; `visual` is kept for backward
# compatibility with the Phase B renderer.
static func default_unit(id: String) -> Dictionary:
	return {
		"id": id,
		"category": "infantry",
		"stats": {
			"health": 100, "move_speed": 2, "attack_damage": 10,
			"attack_range": 1, "vision_range": 5,
		},
		"cost": { "resource_basic": 50 },
		"build_time_ticks": 60,
		"visual": { "shape": "circle", "color": "#4CB0F2", "size_scale": 1.0, "outline": true },
		"graphic": GraphicModel.default_graphic(),
		"editor": { "parent_id": ROOT_UNIT, "tree_order": 0 },
	}


# Build a MULTI-PART unit skeleton with `n` cosmetic layers (1..3). Each part has
# its own stats dictionary so the compatibility matrix (StatRegistry) applies.
# Only multi-part entities may be marked `fusable` (plan 1.1 / E3.4).
static func default_multipart_unit(id: String, parts: int = 3) -> Dictionary:
	var n: int = clampi(parts, 2, GraphicModel.MAX_PARTS)
	var graphic_parts: Array = []
	var size: int = 64
	for i in n:
		graphic_parts.append(GraphicModel.default_part(i + 1, size, size))
		size = maxi(GraphicModel.MIN_PX, size - 16)
	# Distribute default stat groups across parts so they are compatible.
	var part_stats: Array = []
	part_stats.append({ "health": 120, "armor": 2 })          # body / defense
	if n >= 2:
		part_stats.append({ "attack_damage": 14, "attack_range": 2 })  # weapon / combat
	if n >= 3:
		part_stats.append({ "move_speed": 3 })                # engine / mobility
	return {
		"id": id,
		"category": "infantry",
		"stats": { "health": 120, "vision_range": 5 },
		"cost": { "resource_basic": 70 },
		"build_time_ticks": 80,
		"visual": { "shape": "circle", "color": "#4CB0F2", "size_scale": 1.0, "outline": true },
		"graphic": {
			"mode": GraphicModel.MODE_MULTI,
			"logical_size": { "w": 1, "h": 1 },
			"parts": graphic_parts,
		},
		"part_stats": part_stats,
		"fusable": true,
		"editor": { "parent_id": ROOT_UNIT, "tree_order": 0 },
	}


# A unit upgrade definition (E3.5). `visual_change.px` is capped at +15% of the
# base layer-1 size by validate_unit().
static func default_unit_upgrade(trigger_type: String = "kill_count", value: int = 50) -> Dictionary:
	return {
		"trigger": { "type": trigger_type, "value": value, "ref": "" },
		"effects": { "stat_add": {}, "stat_mul": {} },
		"visual_change": {},
	}


# A "trained from" / buildable descriptor (E3.6). Both `from_building` and
# `required_tech` are id references the editor offers as dropdowns.
static func default_buildable(from_building: String = "barracks") -> Dictionary:
	return {
		"from_building": from_building,
		"cost": { "resource_basic": 50 },
		"materials": [],
		"required_tech": "",
	}


# --- Building editing (D.4 -- the play-dough realisation) -------------------

func set_building(id: String, definition: Dictionary) -> bool:
	var clean: String = normalise_id(id)
	if clean == "":
		return false
	var copy: Dictionary = definition.duplicate(true)
	copy["id"] = clean
	buildings[clean] = copy
	return true


func remove_building(id: String) -> bool:
	var clean: String = normalise_id(id)
	if buildings.has(clean):
		buildings.erase(clean)
		return true
	return false


func get_building(id: String) -> Dictionary:
	var clean: String = normalise_id(id)
	if buildings.has(clean):
		return buildings[clean]
	return {}


static func default_building(id: String) -> Dictionary:
	return {
		"id": id,
		"category": "production",
		"stats": { "health": 500, "vision_range": 5 },
		"cost": { "resource_basic": 150 },
		"build_time_ticks": 100,
		"visual": { "shape": "square", "color": "#8A6FB0", "size_scale": 1.0, "outline": true },
		"graphic": GraphicModel.default_graphic(),
		"editor": { "parent_id": ROOT_BUILDING, "tree_order": 0 },
	}


# MULTI-PART building (E4.3). Every part is INDEPENDENTLY destructible and MUST
# carry hp+armor (enforced in validate_building) -- this is what makes a building
# losing one wing while another keeps fighting possible.
static func default_multipart_building(id: String, parts: int = 3) -> Dictionary:
	var n: int = clampi(parts, 2, GraphicModel.MAX_PARTS)
	var graphic_parts: Array = []
	var size: int = 96
	var part_stats: Array = []
	for i in n:
		graphic_parts.append(GraphicModel.default_part(i + 1, size, size))
		size = maxi(GraphicModel.MIN_PX, size - 24)
		# Every building part is required to have hp + armor.
		part_stats.append({ "health": 250, "armor": 3 })
	return {
		"id": id,
		"category": "production",
		"stats": { "health": 500, "vision_range": 5 },
		"cost": { "resource_basic": 200 },
		"build_time_ticks": 140,
		"visual": { "shape": "square", "color": "#8A6FB0", "size_scale": 1.0, "outline": true },
		"graphic": {
			"mode": GraphicModel.MODE_MULTI,
			"logical_size": { "w": 2, "h": 2 },
			"parts": graphic_parts,
		},
		"part_stats": part_stats,
		"part_destructible": true,
		"editor": { "parent_id": ROOT_BUILDING, "tree_order": 0 },
	}


# --- Scenario authoring (E.6 -- bundling a whole "custom game") -------------
# A scenario is stored verbatim as a `data/scenarios/<id>.json` entry. The Map
# Editor (Phase E) produces these from a `ScenarioProject.to_scenario()`; the
# game loads them through the SAME ModLoader pipeline, so an authored scenario in
# a pack is immediately listed + playable (see E.7).

func set_scenario(id: String, definition: Dictionary) -> bool:
	var clean: String = normalise_id(id)
	if clean == "":
		return false
	var copy: Dictionary = definition.duplicate(true)
	copy["id"] = clean
	scenarios[clean] = copy
	return true


func remove_scenario(id: String) -> bool:
	var clean: String = normalise_id(id)
	if scenarios.has(clean):
		scenarios.erase(clean)
		return true
	return false


func get_scenario(id: String) -> Dictionary:
	var clean: String = normalise_id(id)
	if scenarios.has(clean):
		return scenarios[clean]
	return {}


# --- Tech authoring (E.5 -- the simple tech tree) ---------------------------

func set_tech(id: String, definition: Dictionary) -> bool:
	var clean: String = normalise_id(id)
	if clean == "":
		return false
	var copy: Dictionary = definition.duplicate(true)
	copy["id"] = clean
	tech[clean] = copy
	return true


func remove_tech(id: String) -> bool:
	var clean: String = normalise_id(id)
	if tech.has(clean):
		tech.erase(clean)
		return true
	return false


func get_tech(id: String) -> Dictionary:
	var clean: String = normalise_id(id)
	if tech.has(clean):
		return tech[clean]
	return {}


# --- Map object authoring (E5 -- the Object Editor) -------------------------
# A map object is a decoration or an extractable resource node placed on the map.
# It is stored verbatim as `data/objects/<id>.json` and round-trips the same way
# every other catalog does.

func set_object(id: String, definition: Dictionary) -> bool:
	var clean: String = normalise_id(id)
	if clean == "":
		return false
	var copy: Dictionary = definition.duplicate(true)
	copy["id"] = clean
	objects[clean] = copy
	return true


func remove_object(id: String) -> bool:
	var clean: String = normalise_id(id)
	if objects.has(clean):
		objects.erase(clean)
		return true
	return false


func get_object(id: String) -> Dictionary:
	var clean: String = normalise_id(id)
	if objects.has(clean):
		return objects[clean]
	return {}


# A sensible default map object: a decorative rock on land. Set `extractable`
# true + a `yields` block to turn it into a resource node (E5.3).
static func default_object(id: String) -> Dictionary:
	return {
		"id": id,
		"graphic": GraphicModel.default_graphic(),
		"logical_size": { "w": 1, "h": 1 },
		"placement": "land",          # "land" | "sea" | "both"
		"extractable": false,
		"yields": {},                 # { "material": "iron", "rate": 2 } when extractable
		"editor": { "parent_id": ROOT_OBJECT, "tree_order": 0 },
	}


# --- Tree model (E2.1) ------------------------------------------------------
# Editor-only metadata lives in `definition.editor = { parent_id, tree_order }`.
# The game engine ignores it entirely. These helpers operate on whichever catalog
# the editor is currently showing.

# Return the catalog dictionary for a name, or an empty dict for unknown names.
func _catalog(catalog: String) -> Dictionary:
	match catalog:
		UNITS_CATALOG: return units
		BUILDINGS_CATALOG: return buildings
		OBJECTS_CATALOG: return objects
		_: return {}


func root_for(catalog: String) -> String:
	match catalog:
		UNITS_CATALOG: return ROOT_UNIT
		BUILDINGS_CATALOG: return ROOT_BUILDING
		OBJECTS_CATALOG: return ROOT_OBJECT
		_: return ""


# Set the tree parent of a node (editor metadata only). Returns false if the node
# does not exist in the catalog.
func set_parent(catalog: String, node_id: String, parent_id: String) -> bool:
	var cat: Dictionary = _catalog(catalog)
	var clean: String = normalise_id(node_id)
	if not cat.has(clean):
		return false
	var def: Dictionary = cat[clean] as Dictionary
	var editor: Dictionary = def.get("editor", {}) as Dictionary
	editor["parent_id"] = parent_id if parent_id != "" else root_for(catalog)
	def["editor"] = editor
	return true


# "Add subgroup": create a child node under `parent_id`. Returns the new node id
# (already stored) or "" on failure. The factory is chosen by catalog.
func add_child(catalog: String, parent_id: String, new_id: String) -> String:
	var clean: String = normalise_id(new_id)
	if clean == "":
		return ""
	var def: Dictionary = _make_default(catalog, clean)
	if def.is_empty():
		return ""
	var editor: Dictionary = def.get("editor", {}) as Dictionary
	editor["parent_id"] = parent_id if parent_id != "" else root_for(catalog)
	editor["tree_order"] = _next_order(catalog, str(editor["parent_id"]))
	def["editor"] = editor
	_store(catalog, clean, def)
	return clean


# "Add sibling": create a node sharing the parent of `node_id`.
func add_sibling(catalog: String, node_id: String, new_id: String) -> String:
	var cat: Dictionary = _catalog(catalog)
	var clean_sel: String = normalise_id(node_id)
	var parent: String = root_for(catalog)
	if cat.has(clean_sel):
		parent = str((cat[clean_sel].get("editor", {}) as Dictionary).get("parent_id", root_for(catalog)))
	return add_child(catalog, parent, new_id)


# Rename a node id, preserving its definition + tree position. Children that
# point at the old id are re-parented to the new id. Returns the new id or "".
func rename_node(catalog: String, old_id: String, new_id: String) -> String:
	var cat: Dictionary = _catalog(catalog)
	var clean_old: String = normalise_id(old_id)
	var clean_new: String = normalise_id(new_id)
	if clean_new == "" or not cat.has(clean_old) or cat.has(clean_new):
		return ""
	var def: Dictionary = (cat[clean_old] as Dictionary).duplicate(true)
	def["id"] = clean_new
	cat.erase(clean_old)
	cat[clean_new] = def
	# Re-parent any children that referenced the old id.
	for k in cat.keys():
		var ed: Dictionary = cat[k].get("editor", {}) as Dictionary
		if str(ed.get("parent_id", "")) == clean_old:
			ed["parent_id"] = clean_new
			cat[k]["editor"] = ed
	return clean_new


# Build a nested tree structure for the UI:
#   { "id": <root>, "children": [ { "id": .., "children": [...] }, ... ] }
# Nodes are ordered by `tree_order` then id (deterministic).
func build_tree(catalog: String) -> Dictionary:
	var cat: Dictionary = _catalog(catalog)
	var root: String = root_for(catalog)
	# Group children by parent.
	var by_parent: Dictionary = {}
	for id in cat.keys():
		var ed: Dictionary = cat[id].get("editor", {}) as Dictionary
		var p: String = str(ed.get("parent_id", root))
		if not by_parent.has(p):
			by_parent[p] = []
		(by_parent[p] as Array).append(str(id))
	return { "id": root, "children": _build_children(root, by_parent, cat) }


func _build_children(parent: String, by_parent: Dictionary, cat: Dictionary) -> Array:
	var ids: Array = (by_parent.get(parent, []) as Array).duplicate()
	ids.sort_custom(func(a, b):
		var oa: int = int((cat[a].get("editor", {}) as Dictionary).get("tree_order", 0))
		var ob: int = int((cat[b].get("editor", {}) as Dictionary).get("tree_order", 0))
		if oa != ob:
			return oa < ob
		return str(a) < str(b))
	var out: Array = []
	for id in ids:
		out.append({ "id": id, "children": _build_children(str(id), by_parent, cat) })
	return out


func _next_order(catalog: String, parent: String) -> int:
	var cat: Dictionary = _catalog(catalog)
	var maxo: int = -1
	for id in cat.keys():
		var ed: Dictionary = cat[id].get("editor", {}) as Dictionary
		if str(ed.get("parent_id", "")) == parent:
			maxo = maxi(maxo, int(ed.get("tree_order", 0)))
	return maxo + 1


func _make_default(catalog: String, id: String) -> Dictionary:
	match catalog:
		UNITS_CATALOG: return default_unit(id)
		BUILDINGS_CATALOG: return default_building(id)
		OBJECTS_CATALOG: return default_object(id)
		_: return {}


func _store(catalog: String, id: String, def: Dictionary) -> void:
	match catalog:
		UNITS_CATALOG: set_unit(id, def)
		BUILDINGS_CATALOG: set_building(id, def)
		OBJECTS_CATALOG: set_object(id, def)


# --- Texture management (D.5) -----------------------------------------------

# Register a texture by bare name (e.g. "wall_block.png" or "wall_block"). It is
# stored under the canonical `textures/<name>.png` entry path used by the pack
# format + TextureService. Returns the stored entry path.
func add_texture(name: String, bytes: PackedByteArray) -> String:
	var entry: String = texture_entry_path(name)
	textures[entry] = bytes
	return entry


func remove_texture(name: String) -> bool:
	var entry: String = texture_entry_path(name)
	if textures.has(entry):
		textures.erase(entry)
		return true
	return false


func has_texture(name: String) -> bool:
	return textures.has(texture_entry_path(name))


# E2.4 -- Add a texture only after validating the PNG bytes (format + size).
# Returns the stored entry path on success, or "" with the project unchanged when
# the image is invalid (golden rule #3: validate before save). Problems are
# reported back through `out_problems` if supplied.
func add_texture_validated(name: String, bytes: PackedByteArray, out_problems: Array = []) -> String:
	var problems: Array = GraphicModel.validate_image(bytes)
	if not problems.is_empty():
		out_problems.append_array(problems)
		return ""
	return add_texture(name, bytes)


# E2.4 -- Make a texture name that does not collide with an existing one by
# appending _2, _3, ... before the extension.
func unique_texture_name(base: String) -> String:
	var stem: String = base.strip_edges()
	if stem.to_lower().ends_with(".png"):
		stem = stem.substr(0, stem.length() - 4)
	if not has_texture(stem):
		return stem
	var n: int = 2
	while has_texture("%s_%d" % [stem, n]):
		n += 1
	return "%s_%d" % [stem, n]


static func texture_entry_path(name: String) -> String:
	var n: String = name.strip_edges()
	if n.begins_with(PackFormat.TEXTURES_DIR + "/"):
		return n
	if not n.to_lower().ends_with(".png"):
		n += ".png"
	return PackFormat.TEXTURES_DIR + "/" + n


# --- Manifest convenience ---------------------------------------------------

func set_manifest_field(field: String, value: Variant) -> void:
	manifest[field] = value


func get_id() -> String:
	return str(manifest.get("id", ""))


# --- Validation + serialisation (D.7) ---------------------------------------

# A composed manifest with `provides` rebuilt from the current units/buildings,
# in deterministic (sorted) order. This is exactly what gets written to disk.
func build_manifest() -> Dictionary:
	var m: Dictionary = manifest.duplicate(true)
	var provides: Dictionary = {}
	var unit_ids: Array = units.keys()
	unit_ids.sort()
	if not unit_ids.is_empty():
		var unit_paths: Array = []
		for id in unit_ids:
			unit_paths.append("%s/%s/%s.json" % [PackFormat.DATA_DIR, UNITS_CATALOG, str(id)])
		provides[UNITS_CATALOG] = unit_paths
	var building_ids: Array = buildings.keys()
	building_ids.sort()
	if not building_ids.is_empty():
		var b_paths: Array = []
		for id in building_ids:
			b_paths.append("%s/%s/%s.json" % [PackFormat.DATA_DIR, BUILDINGS_CATALOG, str(id)])
		provides[BUILDINGS_CATALOG] = b_paths
	# Phase E catalogs.
	var scenario_ids: Array = scenarios.keys()
	scenario_ids.sort()
	if not scenario_ids.is_empty():
		var s_paths: Array = []
		for id in scenario_ids:
			s_paths.append("%s/%s/%s.json" % [PackFormat.DATA_DIR, SCENARIOS_CATALOG, str(id)])
		provides[SCENARIOS_CATALOG] = s_paths
	var tech_ids: Array = tech.keys()
	tech_ids.sort()
	if not tech_ids.is_empty():
		var t_paths: Array = []
		for id in tech_ids:
			t_paths.append("%s/%s/%s.json" % [PackFormat.DATA_DIR, TECH_CATALOG, str(id)])
		provides[TECH_CATALOG] = t_paths
	# Phase E5 objects catalog.
	var object_ids: Array = objects.keys()
	object_ids.sort()
	if not object_ids.is_empty():
		var o_paths: Array = []
		for id in object_ids:
			o_paths.append("%s/%s/%s.json" % [PackFormat.DATA_DIR, OBJECTS_CATALOG, str(id)])
		provides[OBJECTS_CATALOG] = o_paths
	m["provides"] = provides
	return m


# The complete {entry path -> String|PackedByteArray} map for PackWriter, minus
# the manifest (which PackWriter owns). Entry order is deterministic.
func build_files() -> Dictionary:
	var files: Dictionary = {}
	for id in units.keys():
		files["%s/%s/%s.json" % [PackFormat.DATA_DIR, UNITS_CATALOG, str(id)]] = JSON.stringify(units[id], "\t")
	for id in buildings.keys():
		files["%s/%s/%s.json" % [PackFormat.DATA_DIR, BUILDINGS_CATALOG, str(id)]] = JSON.stringify(buildings[id], "\t")
	for id in scenarios.keys():
		files["%s/%s/%s.json" % [PackFormat.DATA_DIR, SCENARIOS_CATALOG, str(id)]] = JSON.stringify(scenarios[id], "\t")
	for id in tech.keys():
		files["%s/%s/%s.json" % [PackFormat.DATA_DIR, TECH_CATALOG, str(id)]] = JSON.stringify(tech[id], "\t")
	for id in objects.keys():
		files["%s/%s/%s.json" % [PackFormat.DATA_DIR, OBJECTS_CATALOG, str(id)]] = JSON.stringify(objects[id], "\t")
	for entry_path in textures.keys():
		files[str(entry_path)] = textures[entry_path]
	return files


# Human-readable validation of the WHOLE project (not just the manifest). Returns
# an Array of problem strings; empty means "ready to save / play-test".
func validate() -> Array:
	var problems: Array = []
	problems.append_array(PackFormat.validate_manifest(build_manifest()))
	if units.is_empty() and buildings.is_empty() and scenarios.is_empty() and tech.is_empty() and objects.is_empty():
		problems.append("project is empty: add at least one unit, building, scenario, object or tech")
	for id in units.keys():
		problems.append_array(validate_unit(str(id)))
	for id in buildings.keys():
		problems.append_array(validate_building(str(id)))
	for id in objects.keys():
		problems.append_array(validate_object(str(id)))
	# A bundled scenario must carry a map block so the ScenarioLoader can build it.
	for id in scenarios.keys():
		if not (scenarios[id] is Dictionary) or not (scenarios[id] as Dictionary).has("map"):
			problems.append("scenario '%s' has no map block" % str(id))
	return problems


# --- Per-entity validation (E3 / E4 / E5) -----------------------------------

# Validate a single unit: stats present, graphic valid, multi-part stat
# compatibility, upgrade size cap, fusable only when multi-part.
func validate_unit(id: String) -> Array:
	var problems: Array = []
	var def: Variant = units.get(id, null)
	if not (def is Dictionary):
		return ["unit '%s' is malformed" % id]
	var u: Dictionary = def as Dictionary
	if not u.has("stats"):
		problems.append("unit '%s' has no stats block" % id)
	problems.append_array(_validate_graphic_block(u, "unit '%s'" % id))
	problems.append_array(_validate_multipart(u, "unit '%s'" % id, false))
	if bool(u.get("fusable", false)) and not _is_multi(u):
		problems.append("unit '%s' is marked fusable but is single-part" % id)
	problems.append_array(_validate_upgrade(u, "unit '%s'" % id))
	return problems


# Validate a single building: like a unit, but EVERY part of a multi-part
# building MUST carry hp + armor (E4.3).
func validate_building(id: String) -> Array:
	var problems: Array = []
	var def: Variant = buildings.get(id, null)
	if not (def is Dictionary):
		return ["building '%s' is malformed" % id]
	var b: Dictionary = def as Dictionary
	if not b.has("stats"):
		problems.append("building '%s' has no stats block" % id)
	problems.append_array(_validate_graphic_block(b, "building '%s'" % id))
	problems.append_array(_validate_multipart(b, "building '%s'" % id, true))
	problems.append_array(_validate_upgrade(b, "building '%s'" % id))
	return problems


# Validate a single map object: graphic valid; extractable objects need a yields
# block with a material + positive rate; placement is one of land/sea/both.
func validate_object(id: String) -> Array:
	var problems: Array = []
	var def: Variant = objects.get(id, null)
	if not (def is Dictionary):
		return ["object '%s' is malformed" % id]
	var o: Dictionary = def as Dictionary
	problems.append_array(_validate_graphic_block(o, "object '%s'" % id))
	var placement: String = str(o.get("placement", "land"))
	if placement != "land" and placement != "sea" and placement != "both":
		problems.append("object '%s' has invalid placement '%s'" % [id, placement])
	if bool(o.get("extractable", false)):
		var yields: Variant = o.get("yields", {})
		if not (yields is Dictionary) or str((yields as Dictionary).get("material", "")) == "" or int((yields as Dictionary).get("rate", 0)) <= 0:
			problems.append("object '%s' is extractable but has no valid yields (material + positive rate)" % id)
	return problems


func _is_multi(def: Dictionary) -> bool:
	var g: Variant = def.get("graphic", {})
	return g is Dictionary and str((g as Dictionary).get("mode", "")) == GraphicModel.MODE_MULTI


func _validate_graphic_block(def: Dictionary, label: String) -> Array:
	if not def.has("graphic"):
		return []  # graphic is optional; the Phase B `visual` block still works
	var problems: Array = []
	for p in GraphicModel.validate(def["graphic"]):
		problems.append("%s graphic: %s" % [label, str(p)])
	return problems


# Validate per-part stats of a multi-part entity. `require_hp_armor` enforces the
# building rule. Adjacent parts must be group-compatible (StatRegistry).
func _validate_multipart(def: Dictionary, label: String, require_hp_armor: bool) -> Array:
	if not _is_multi(def):
		return []
	var problems: Array = []
	var part_stats: Variant = def.get("part_stats", [])
	if not (part_stats is Array) or (part_stats as Array).is_empty():
		problems.append("%s is multi-part but has no part_stats" % label)
		return problems
	var ps: Array = part_stats as Array
	for i in ps.size():
		if not (ps[i] is Dictionary):
			problems.append("%s part %d stats malformed" % [label, i])
			continue
		if require_hp_armor:
			var sd: Dictionary = ps[i] as Dictionary
			if not sd.has("health") or not sd.has("armor"):
				problems.append("%s part %d must have health + armor" % [label, i])
	# Pairwise compatibility (defense may be shared on buildings).
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			if ps[i] is Dictionary and ps[j] is Dictionary:
				if not StatRegistry.compatible(ps[i], ps[j], require_hp_armor):
					var c: Array = StatRegistry.conflicts(ps[i], ps[j], require_hp_armor)
					problems.append("%s parts %d and %d conflict on group(s) %s" % [label, i, j, str(c)])
	return problems


# Validate an optional `upgrade` block: visual_change.px must not exceed the base
# layer-1 size by more than +15% (plan 2.4, E3.5/E4.4).
func _validate_upgrade(def: Dictionary, label: String) -> Array:
	if not def.has("upgrade"):
		return []
	var up: Variant = def["upgrade"]
	if not (up is Dictionary):
		return ["%s upgrade block malformed" % label]
	var vc: Variant = (up as Dictionary).get("visual_change", {})
	if not (vc is Dictionary) or not (vc as Dictionary).has("px"):
		return []  # no visual growth to check
	var base_px: int = _base_layer_px_area(def)
	if base_px <= 0:
		return []
	var new_px_d: Dictionary = (vc as Dictionary).get("px", {}) as Dictionary
	var new_area: int = int(new_px_d.get("w", 0)) * int(new_px_d.get("h", 0))
	if float(new_area) > float(base_px) * (1.0 + UPGRADE_SIZE_CAP):
		return ["%s upgrade grows the base layer beyond +%d%%" % [label, int(UPGRADE_SIZE_CAP * 100)]]
	return []


func _base_layer_px_area(def: Dictionary) -> int:
	var g: Variant = def.get("graphic", {})
	if not (g is Dictionary):
		return 0
	for part in (g as Dictionary).get("parts", []):
		if part is Dictionary and int((part as Dictionary).get("layer", 0)) == 1:
			var px: Dictionary = (part as Dictionary).get("px", {}) as Dictionary
			return int(px.get("w", 0)) * int(px.get("h", 0))
	return 0


func is_valid() -> bool:
	return validate().is_empty()


# Save the project to a `.nexpack` at `out_path`. Refuses to save an invalid
# project (returns false) so a broken pack is never produced. The manifest is
# rebuilt from the live content first.
func save_pack(out_path: String) -> bool:
	if not is_valid():
		push_error("ModProject: refusing to save an invalid project: %s" % str(validate()))
		return false
	return PackWriter.write_from_data(build_manifest(), build_files(), out_path)


# --- Helpers ----------------------------------------------------------------

# Normalise a content id to a safe, deterministic token: lower-case, spaces and
# stray characters collapsed to underscores, leading/trailing underscores
# trimmed. An id that reduces to nothing returns "".
static func normalise_id(raw: String) -> String:
	var s: String = raw.strip_edges().to_lower()
	var out: String = ""
	for i in s.length():
		var c: String = s[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
		elif c == " " or c == "-" or c == ".":
			out += "_"
		# any other character is dropped
	while out.begins_with("_"):
		out = out.substr(1)
	while out.ends_with("_"):
		out = out.substr(0, out.length() - 1)
	return out
