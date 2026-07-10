# scenario_project.gd
# ----------------------------------------------------------------------------
# Project Nexus - Scenario / Map authoring model (Phase E, steps E.1-E.5).
#
# `ScenarioProject` is the IN-MEMORY model of a single scenario (a playable map +
# its entity placements + match rules + an optional simple tech tree) being
# authored in the graphical Map/Scenario Editor (Phase E). Like `ModProject`
# (Phase D) it holds ZERO UI: the editor scene (`ui/shared/map_editor.gd`) is a
# thin view that drives this object, while ALL authoring logic -- resize / brush /
# fill / place entity / edit rules / build a tech node -- lives here so it can be
# exercised fully headless by the test runner.
#
# It serialises to EXACTLY the scenario JSON shape `ScenarioLoader.apply_scenario`
# already consumes (`modules/map/scenario_loader.gd`):
#
#   {
#     "id": "...", "display_name_key": "...", "random_seed": int,
#     "difficulty": "normal",
#     "map": { "width": w, "height": h, "walls": [[x,y], ...] },
#     "players":   [ { "owner": int, "is_human": bool, ... }, ... ],
#     "buildings": [ { "type": "hq", "owner": int, "x": int, "y": int }, ... ],
#     "units":     [ { "type": "soldier", "owner": int, "x": int, "y": int }, ... ]
#   }
#
# An optional simple tech tree (E.5) is authored alongside and emitted as a
# parallel `tech` catalog map (id -> tech definition) so the same `.nexpack`
# pipeline (Phase C) carries it without any format change.
#
# Design rules (consistent with the rest of the project):
#   - PURE INFRASTRUCTURE / TOOLING: never touches WorldState or the sim hash.
#     It only PRODUCES data the deterministic ScenarioLoader will later read.
#   - SAFE + VALIDATING: out-of-bounds edits are clamped/ignored; bad input is
#     rejected with a reason rather than corrupting the model; saving an invalid
#     scenario is refused.
#   - DETERMINISTIC: walls + entity lists are emitted in a stable sorted order so
#     the same project always produces byte-identical scenario JSON.
#   - English-only identifiers/comments (CODE_POLICY); any author-facing text the
#     UI shows is resolved through Localization, not stored here.
# ----------------------------------------------------------------------------
class_name ScenarioProject
extends RefCounted

# The catalog name a scenario is stored under inside a .nexpack / mod folder.
const SCENARIOS_CATALOG: String = "scenarios"
const TECH_CATALOG: String = "tech"

# Terrain tokens the map editor paints with. Only "wall" is currently a real
# obstacle (matches MapModule.TERRAIN_WALL); "ground" is the eraser. Extra
# tokens are reserved for Phase F art without changing the save format.
const TERRAIN_GROUND: String = "ground"
const TERRAIN_WALL: String = "wall"
# Phase E6.1 -- "sea" is a paintable LOGICAL token (land vs sea). A coastline is
# NOT stored; it is computed render-only by CoastAutotile (golden rule #1).
const TERRAIN_SEA: String = "sea"
const PAINTABLE_TERRAINS: Array = [TERRAIN_GROUND, TERRAIN_WALL, TERRAIN_SEA]

# Sensible authoring bounds so a slider/brush can never create a degenerate or
# absurd map. The deterministic core itself imposes no upper bound; these are
# purely editor ergonomics.
const MIN_DIM: int = 4
const MAX_DIM: int = 128
const DEFAULT_WIDTH: int = 20
const DEFAULT_HEIGHT: int = 14
const DEFAULT_SEED: int = 20240601

# --- State ------------------------------------------------------------------
var scenario_id: String = "new_scenario"
var display_name: String = "New Scenario"
var random_seed: int = DEFAULT_SEED
var difficulty: String = "normal"
var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT

# Phase P7 (R1.5 / R10.2): match-wide rules authored in the Map Editor.
var game_mode: String = "ffa"          # "ffa" | "team" | "ctf"
var team_layout: String = "clustered"  # "clustered" | "random"

# Walls stored as a Set-like Dictionary keyed by "x,y" -> true for O(1)
# paint/erase and deterministic emission. Never stores out-of-bounds cells.
var _walls: Dictionary = {}

# Phase E6.1 -- sea cells, same Set-like "x,y" -> true representation as walls.
var _sea: Dictionary = {}

# Entity placements. Each is a small Dictionary; we keep them in plain Arrays and
# sort on emit for determinism.
var players: Array = []     # { owner, is_human, difficulty, smart, personality, start_resources }
var buildings: Array = []   # { type, owner, x, y }
var units: Array = []       # { type, owner, x, y }
# Phase E6.4 -- placed map objects: { object, x, y }.
var map_objects: Array = []

# Phase P7 (R10.5) -- placed CTF/HQ flags: { index, x, y, team }.
var flags: Array = []

# Optional simple tech tree (E.5): id -> tech definition Dictionary.
var tech: Dictionary = {}

# MB7.2 (bug 20): optional background image drawn UNDER the grid (cosmetic map
# art). Stored as a path string (empty = none). The image itself lives under the
# writable content root (user://); only the reference is serialised so the
# scenario JSON stays small and portable. Render-only -> never affects the sim
# hash (golden rule #1 / #3).
var background_image: String = ""


func _init() -> void:
	new_scenario("new_scenario", "New Scenario")


# --- Lifecycle --------------------------------------------------------------

# Reset to a fresh scenario with a default 2-player layout so a brand-new project
# is already playable (a human vs. one normal AI on an empty map with two HQs).
func new_scenario(id: String, name: String = "") -> void:
	var clean: String = ModProject.normalise_id(id)
	if clean == "":
		clean = "new_scenario"
	scenario_id = clean
	display_name = name.strip_edges() if name.strip_edges() != "" else clean
	random_seed = DEFAULT_SEED
	difficulty = "normal"
	width = DEFAULT_WIDTH
	height = DEFAULT_HEIGHT
	_walls = {}
	_sea = {}
	map_objects = []
	players = [
		{ "owner": 0, "is_human": true, "start_resources": { "resource_basic": 150 } },
		{ "owner": 1, "is_human": false, "difficulty": "normal", "start_resources": { "resource_basic": 150 } },
	]
	buildings = [
		{ "type": "hq", "owner": 0, "x": 2, "y": int(height / 2) },
		{ "type": "hq", "owner": 1, "x": width - 3, "y": int(height / 2) },
	]
	units = [
		{ "type": "soldier", "owner": 0, "x": 3, "y": int(height / 2) - 1 },
		{ "type": "soldier", "owner": 1, "x": width - 4, "y": int(height / 2) - 1 },
	]
	map_objects = []
	flags = []
	game_mode = "ffa"
	team_layout = "clustered"
	tech = {}
	background_image = ""


# MB7.1 (bug 22): start a fresh scenario with an author-chosen NAME and explicit
# grid DIMENSIONS (the editor now shows a "new map" dialog before editing instead
# of dumping the user into a fixed default grid). Dimensions are clamped to the
# safe [MIN_DIM, MAX_DIM] authoring bounds so a bad dialog value can never create
# a degenerate map. Building on the default 2-player layout, the two HQs/units are
# then re-clamped into the requested grid so a small map stays playable.
func new_scenario_sized(id: String, name: String, w: int, h: int) -> void:
	new_scenario(id, name)
	resize(w, h)
	# Re-seat the default HQs/units for the (possibly) new size so nothing is left
	# stranded off-map or stacked after a shrink.
	var mid_y: int = int(height / 2)
	buildings = [
		{ "type": "hq", "owner": 0, "x": clampi(2, 0, width - 1), "y": mid_y },
		{ "type": "hq", "owner": 1, "x": clampi(width - 3, 0, width - 1), "y": mid_y },
	]
	units = [
		{ "type": "soldier", "owner": 0, "x": clampi(3, 0, width - 1), "y": clampi(mid_y - 1, 0, height - 1) },
		{ "type": "soldier", "owner": 1, "x": clampi(width - 4, 0, width - 1), "y": clampi(mid_y - 1, 0, height - 1) },
	]


# MB7.1 (bug 22): validate the "new map" dialog inputs (name + width + height)
# BEFORE a project is created, so the editor can show a precise reason instead of
# silently clamping. Returns an Array of problem strings; empty means valid.
# Static + pure so the dialog can call it headlessly without a live project.
static func validate_new_map(name: String, w: int, h: int) -> Array:
	var problems: Array = []
	if ModProject.normalise_id(name) == "":
		problems.append("name is empty or has no usable ASCII characters")
	if w < MIN_DIM or h < MIN_DIM:
		problems.append("map is too small (min %dx%d)" % [MIN_DIM, MIN_DIM])
	if w > MAX_DIM or h > MAX_DIM:
		problems.append("map is too large (max %dx%d)" % [MAX_DIM, MAX_DIM])
	return problems


# Load an existing scenario Dictionary (as produced by `to_scenario()` or read
# from a pack/file). On any structural problem the project is left UNCHANGED so a
# bad file never destroys in-progress work. Returns true on success.
func from_scenario(scenario: Variant) -> bool:
	if not (scenario is Dictionary):
		return false
	var s: Dictionary = scenario as Dictionary
	# A scenario MUST carry a map block; a missing or non-Dictionary map is
	# rejected so a malformed payload never silently produces an empty map.
	if not s.has("map") or not (s["map"] is Dictionary):
		return false
	var map_data: Variant = s["map"]

	# Build into locals first; only commit when nothing failed.
	var new_w: int = clampi(int((map_data as Dictionary).get("width", DEFAULT_WIDTH)), MIN_DIM, MAX_DIM)
	var new_h: int = clampi(int((map_data as Dictionary).get("height", DEFAULT_HEIGHT)), MIN_DIM, MAX_DIM)
	var new_walls: Dictionary = {}
	for wall in (map_data as Dictionary).get("walls", []):
		if wall is Array and (wall as Array).size() >= 2:
			var wx: int = int(wall[0])
			var wy: int = int(wall[1])
			if wx >= 0 and wy >= 0 and wx < new_w and wy < new_h:
				new_walls["%d,%d" % [wx, wy]] = true

	# Phase E6.1 -- sea cells (optional; older scenarios simply have none).
	var new_sea: Dictionary = {}
	for cell in (map_data as Dictionary).get("sea", []):
		if cell is Array and (cell as Array).size() >= 2:
			var sx: int = int(cell[0])
			var sy: int = int(cell[1])
			if sx >= 0 and sy >= 0 and sx < new_w and sy < new_h:
				new_sea["%d,%d" % [sx, sy]] = true

	# Phase E6.4 -- placed map objects (optional).
	var new_objects: Array = []
	for o in s.get("objects", []):
		if o is Dictionary:
			var ox: int = int((o as Dictionary).get("x", -1))
			var oy: int = int((o as Dictionary).get("y", -1))
			if ox >= 0 and oy >= 0 and ox < new_w and oy < new_h:
				new_objects.append((o as Dictionary).duplicate(true))

	# Phase P7 (R10.5) -- placed flags (optional; older scenarios have none).
	var new_flags: Array = []
	for f in s.get("flags", []):
		if f is Dictionary:
			var fx: int = int((f as Dictionary).get("x", -1))
			var fy: int = int((f as Dictionary).get("y", -1))
			if fx >= 0 and fy >= 0 and fx < new_w and fy < new_h:
				new_flags.append((f as Dictionary).duplicate(true))

	var new_players: Array = []
	for p in s.get("players", []):
		if p is Dictionary:
			new_players.append((p as Dictionary).duplicate(true))
	var new_buildings: Array = []
	for b in s.get("buildings", []):
		if b is Dictionary:
			new_buildings.append((b as Dictionary).duplicate(true))
	var new_units: Array = []
	for u in s.get("units", []):
		if u is Dictionary:
			new_units.append((u as Dictionary).duplicate(true))

	# Commit.
	scenario_id = ModProject.normalise_id(str(s.get("id", "new_scenario")))
	if scenario_id == "":
		scenario_id = "new_scenario"
	display_name = str(s.get("display_name", s.get("display_name_key", scenario_id)))
	random_seed = int(s.get("random_seed", DEFAULT_SEED))
	difficulty = str(s.get("difficulty", "normal"))
	width = new_w
	height = new_h
	_walls = new_walls
	_sea = new_sea
	players = new_players
	buildings = new_buildings
	units = new_units
	map_objects = new_objects
	flags = new_flags
	game_mode = str(s.get("game_mode", "ffa"))
	team_layout = str(s.get("team_layout", "clustered"))
	background_image = str(s.get("background_image", ""))
	return true


# --- Map editing (E.1 / E.2 / E.3) ------------------------------------------

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


# E.2 -- Resize. Growing keeps everything; shrinking DROPS any wall/entity that
# would fall outside the new grid (so the model never holds out-of-bounds data).
func resize(new_width: int, new_height: int) -> void:
	width = clampi(new_width, MIN_DIM, MAX_DIM)
	height = clampi(new_height, MIN_DIM, MAX_DIM)
	# Prune walls now outside the grid.
	var kept: Dictionary = {}
	for key in _walls.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 2:
			var wx: int = int(parts[0])
			var wy: int = int(parts[1])
			if in_bounds(wx, wy):
				kept[key] = true
	_walls = kept
	# Prune sea cells now outside the grid.
	var kept_sea: Dictionary = {}
	for key in _sea.keys():
		var sp: PackedStringArray = str(key).split(",")
		if sp.size() == 2 and in_bounds(int(sp[0]), int(sp[1])):
			kept_sea[key] = true
	_sea = kept_sea
	# Prune off-map entities.
	players = players  # players carry no coords; untouched
	buildings = _prune_entities(buildings)
	units = _prune_entities(units)
	map_objects = _prune_entities(map_objects)
	flags = _prune_entities(flags)  # P7 (R10.5): flags share the {x, y} shape


func _prune_entities(list: Array) -> Array:
	var kept: Array = []
	for e in list:
		if e is Dictionary and in_bounds(int((e as Dictionary).get("x", -1)), int((e as Dictionary).get("y", -1))):
			kept.append(e)
	return kept


# E.2 -- Brush: paint a single cell with a terrain token. "ground" erases a wall.
func paint_cell(x: int, y: int, terrain: String) -> bool:
	if not in_bounds(x, y):
		return false
	var key: String = "%d,%d" % [x, y]
	if terrain == TERRAIN_WALL:
		_sea.erase(key)       # a cell is one token at a time
		_walls[key] = true
		return true
	if terrain == TERRAIN_SEA:
		_walls.erase(key)
		_sea[key] = true
		return true
	if terrain == TERRAIN_GROUND:
		_walls.erase(key)
		_sea.erase(key)
		return true
	return false  # unknown terrain token ignored


func is_wall(x: int, y: int) -> bool:
	return _walls.has("%d,%d" % [x, y])


func is_sea(x: int, y: int) -> bool:
	return _sea.has("%d,%d" % [x, y])


func wall_count() -> int:
	return _walls.size()


func sea_count() -> int:
	return _sea.size()


# E.2 -- Fill: paint a rectangular region (inclusive). Coordinates are sorted +
# clamped, so any corner order / partly-off-map rect is handled safely.
func fill_rect(x0: int, y0: int, x1: int, y1: int, terrain: String) -> int:
	var lo_x: int = clampi(mini(x0, x1), 0, width - 1)
	var hi_x: int = clampi(maxi(x0, x1), 0, width - 1)
	var lo_y: int = clampi(mini(y0, y1), 0, height - 1)
	var hi_y: int = clampi(maxi(y0, y1), 0, height - 1)
	var painted: int = 0
	for yy in range(lo_y, hi_y + 1):
		for xx in range(lo_x, hi_x + 1):
			if paint_cell(xx, yy, terrain):
				painted += 1
	return painted


func clear_walls() -> void:
	_walls = {}


# E.2 -- Border: paint a wall ring around the whole map (a common starting point).
func paint_border() -> void:
	for xx in range(width):
		paint_cell(xx, 0, TERRAIN_WALL)
		paint_cell(xx, height - 1, TERRAIN_WALL)
	for yy in range(height):
		paint_cell(0, yy, TERRAIN_WALL)
		paint_cell(width - 1, yy, TERRAIN_WALL)


# --- Entity placement (E.3) -------------------------------------------------

# Place a building. A cell is exclusive: any existing building OR unit at (x,y)
# is replaced/removed first, and a wall is cleared, so placement is unambiguous.
func place_building(type_id: String, owner: int, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	_clear_cell(x, y)
	buildings.append({ "type": str(type_id), "owner": int(owner), "x": int(x), "y": int(y) })
	return true


func place_unit(type_id: String, owner: int, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	_clear_cell(x, y)
	units.append({ "type": str(type_id), "owner": int(owner), "x": int(x), "y": int(y) })
	return true


# E6.4 -- Place a map object (decoration / resource node). A cell is exclusive,
# so any existing entity/object at (x,y) is cleared first and a wall is removed.
func place_object(object_id: String, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	_clear_cell(x, y)
	map_objects.append({ "object": str(object_id), "x": int(x), "y": int(y) })
	return true


func object_count() -> int:
	return map_objects.size()


# Remove any entity (building or unit) sitting on a cell. Returns true if one was
# removed. Also used by the editor's "erase entity" tool.
func remove_entity_at(x: int, y: int) -> bool:
	var before: int = buildings.size() + units.size() + map_objects.size() + flags.size()
	buildings = _without_cell(buildings, x, y)
	units = _without_cell(units, x, y)
	map_objects = _without_cell(map_objects, x, y)
	flags = _without_cell(flags, x, y)  # P7 (R10.5): the eraser also removes flags
	return (buildings.size() + units.size() + map_objects.size() + flags.size()) < before


func entity_at(x: int, y: int) -> Dictionary:
	for b in buildings:
		if int(b.get("x", -1)) == x and int(b.get("y", -1)) == y:
			var hit_b: Dictionary = (b as Dictionary).duplicate(true)
			hit_b["kind"] = "building"
			return hit_b
	for u in units:
		if int(u.get("x", -1)) == x and int(u.get("y", -1)) == y:
			var hit_u: Dictionary = (u as Dictionary).duplicate(true)
			hit_u["kind"] = "unit"
			return hit_u
	return {}


# MB7.5 (bug 21c): MOVE the entity (building / unit / map object / flag) sitting
# on (from_x, from_y) to (to_x, to_y). This is the model side of the editor's
# select-then-move (or drag) tool. The moved entity keeps its type/owner; the
# destination cell is cleared first so a move is unambiguous (same rule as a
# fresh place). Returns true if an entity was found and moved. A no-op move
# (same cell) still succeeds. Nothing happens if the destination is off-map.
func move_entity(from_x: int, from_y: int, to_x: int, to_y: int) -> bool:
	if not in_bounds(to_x, to_y):
		return false
	if from_x == to_x and from_y == to_y:
		return not entity_at(from_x, from_y).is_empty() or not flag_at(from_x, from_y).is_empty()
	# Flags carry an index/team, so move them via their own dedicated path.
	var flag: Dictionary = flag_at(from_x, from_y)
	if not flag.is_empty():
		return place_flag(int(flag.get("index", next_flag_index())), to_x, to_y, int(flag.get("team", 0)))
	var hit: Dictionary = entity_at(from_x, from_y)
	if not hit.is_empty():
		var kind: String = str(hit.get("kind", ""))
		var type_id: String = str(hit.get("type", ""))
		var owner: int = int(hit.get("owner", 0))
		remove_entity_at(from_x, from_y)
		if kind == "building":
			return place_building(type_id, owner, to_x, to_y)
		if kind == "unit":
			return place_unit(type_id, owner, to_x, to_y)
		return false
	# Map object (decoration / resource node): move by object id.
	for o in map_objects:
		if int(o.get("x", -1)) == from_x and int(o.get("y", -1)) == from_y:
			var object_id: String = str(o.get("object", ""))
			remove_entity_at(from_x, from_y)
			return place_object(object_id, to_x, to_y)
	return false


func _clear_cell(x: int, y: int) -> void:
	paint_cell(x, y, TERRAIN_GROUND)  # never place on a wall
	remove_entity_at(x, y)


func _without_cell(list: Array, x: int, y: int) -> Array:
	var kept: Array = []
	for e in list:
		if not (int(e.get("x", -1)) == x and int(e.get("y", -1)) == y):
			kept.append(e)
	return kept


# --- Players + rules (E.4) --------------------------------------------------

func set_player(owner: int, fields: Dictionary) -> void:
	for p in players:
		if int(p.get("owner", -1)) == owner:
			for k in fields.keys():
				p[k] = fields[k]
			return
	# New player.
	var entry: Dictionary = { "owner": int(owner), "is_human": false }
	for k in fields.keys():
		entry[k] = fields[k]
	players.append(entry)


func remove_player(owner: int) -> bool:
	var before: int = players.size()
	var kept: Array = []
	for p in players:
		if int(p.get("owner", -1)) != owner:
			kept.append(p)
	players = kept
	return players.size() < before


func get_player(owner: int) -> Dictionary:
	for p in players:
		if int(p.get("owner", -1)) == owner:
			return p
	return {}


func human_player_count() -> int:
	var n: int = 0
	for p in players:
		if bool(p.get("is_human", false)):
			n += 1
	return n


# E.4 -- Match rules. Stored on the scenario top-level so ScenarioLoader picks
# them up. We keep them in dedicated fields rather than a free-form blob so
# validation can be meaningful.
func set_seed(value: int) -> void:
	random_seed = int(value)


func set_difficulty(preset: String) -> void:
	var p: String = preset.strip_edges()
	if p != "":
		difficulty = p


# --- Background image (MB7.2 / bug 20) --------------------------------------

# Set the cosmetic background image path (empty clears it). Only the reference is
# stored; the editor is responsible for having copied the source image into the
# writable content root first. Pure/side-effect-free so it is headless testable.
func set_background_image(path: String) -> void:
	background_image = path.strip_edges()


func clear_background_image() -> void:
	background_image = ""


func has_background_image() -> bool:
	return background_image.strip_edges() != ""


# --- Simple tech tree (E.5) -------------------------------------------------

# Author one tech node. Prerequisites reference other tech ids; effects are a
# free-form Dictionary the TechTree module already understands. Stored under the
# `tech` catalog so it ships in the same pack as units/buildings/scenarios.
func set_tech(id: String, definition: Dictionary) -> bool:
	var clean: String = ModProject.normalise_id(id)
	if clean == "":
		return false
	var copy: Dictionary = definition.duplicate(true)
	copy["id"] = clean
	tech[clean] = copy
	return true


func remove_tech(id: String) -> bool:
	var clean: String = ModProject.normalise_id(id)
	if tech.has(clean):
		tech.erase(clean)
		return true
	return false


# Reader symmetric with set_tech/remove_tech (fixes BUG-D1: the getter used by
# the scenario editor and by cross-project copy was missing, causing a runtime
# SCRIPT ERROR). Returns a defensive copy of the stored tech definition, or an
# empty Dictionary when the id is unknown (never indexes a missing key).
func get_tech(id: String) -> Dictionary:
	var clean: String = ModProject.normalise_id(id)
	if not tech.has(clean):
		return {}
	return (tech[clean] as Dictionary).duplicate(true)


static func default_tech(id: String) -> Dictionary:
	return {
		"id": id,
		"name_key": "tech.%s.name" % id,
		"cost": { "resource_basic": 100 },
		"research_ticks": 120,
		"prerequisites": [],
		"effects": {},
	}


# --- Serialisation ----------------------------------------------------------

# Walls in a deterministic order: sorted by (y, x). This makes the emitted JSON
# byte-stable for diffing / caching (same project -> same file).
func sorted_walls() -> Array:
	return _sorted_cells(_walls)


func sorted_sea() -> Array:
	return _sorted_cells(_sea)


func _sorted_cells(cells: Dictionary) -> Array:
	var coords: Array = []
	for key in cells.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 2:
			coords.append(Vector2i(int(parts[0]), int(parts[1])))
	coords.sort_custom(func(a, b): return (a.y < b.y) or (a.y == b.y and a.x < b.x))
	var out: Array = []
	for c in coords:
		out.append([c.x, c.y])
	return out


# E6.5 -- Coastline bitmask for a cell, computed RENDER-ONLY from the sea map.
# Returns 0 for non-coast cells. Treats the map edge as sea by default so the
# shore wraps the border. This never touches stored data (golden rule #1).
func coast_mask(x: int, y: int, edge_is_sea: bool = true) -> int:
	return CoastAutotile.mask4(x, y, func(cx, cy): return is_sea(cx, cy), edge_is_sea, width, height)


# Sorted placed objects for deterministic emission.
func _sorted_objects() -> Array:
	var copy: Array = map_objects.duplicate(true)
	copy.sort_custom(func(a, b):
		var ay: int = int(a.get("y", 0))
		var by: int = int(b.get("y", 0))
		if ay != by:
			return ay < by
		if int(a.get("x", 0)) != int(b.get("x", 0)):
			return int(a.get("x", 0)) < int(b.get("x", 0))
		return str(a.get("object", "")) < str(b.get("object", "")))
	return copy


func _sorted_entities(list: Array) -> Array:
	var copy: Array = list.duplicate(true)
	copy.sort_custom(func(a, b):
		var ao: int = int(a.get("owner", 0))
		var bo: int = int(b.get("owner", 0))
		if ao != bo:
			return ao < bo
		var ay: int = int(a.get("y", 0))
		var by: int = int(b.get("y", 0))
		if ay != by:
			return ay < by
		return int(a.get("x", 0)) < int(b.get("x", 0)))
	return copy


# Build the scenario JSON Dictionary exactly as ScenarioLoader.apply_scenario
# consumes it. Deterministic order throughout.
func to_scenario() -> Dictionary:
	var sorted_players: Array = players.duplicate(true)
	sorted_players.sort_custom(func(a, b): return int(a.get("owner", 0)) < int(b.get("owner", 0)))
	return {
		"id": scenario_id,
		"display_name_key": "scenario.%s.name" % scenario_id,
		"display_name": display_name,
		"random_seed": random_seed,
		"difficulty": difficulty,
		"game_mode": game_mode,
		"team_layout": team_layout,
		"map": {
			"width": width,
			"height": height,
			"walls": sorted_walls(),
			"sea": sorted_sea(),
		},
		"players": sorted_players,
		"buildings": _sorted_entities(buildings),
		"units": _sorted_entities(units),
		"objects": _sorted_objects(),
		"flags": _sorted_flags(),
		"background_image": background_image,
	}


# --- Flag placement (R10.5) -------------------------------------------------

# Place (or move) a flag at cell (x, y). A given `index` is unique: re-placing
# the same index moves it. A cell may hold at most one flag (placing on an
# occupied cell moves whichever flag was there? No -- we keep it explicit:
# placing a NEW index on an occupied cell is rejected). Returns true on success.
func place_flag(index: int, x: int, y: int, team: int) -> bool:
	if not in_bounds(x, y):
		return false
	# A cell already holding a DIFFERENT flag index is rejected (unambiguous map).
	for f in flags:
		if int(f.get("x", -1)) == x and int(f.get("y", -1)) == y and int(f.get("index", -1)) != index:
			return false
	for f in flags:
		if int(f.get("index", -1)) == index:
			f["x"] = x
			f["y"] = y
			f["team"] = team
			return true
	flags.append({ "index": int(index), "x": int(x), "y": int(y), "team": int(team) })
	return true


# Remove any flag at cell (x, y). Returns true if one was removed.
func remove_flag_at(x: int, y: int) -> bool:
	var before: int = flags.size()
	var kept: Array = []
	for f in flags:
		if not (int(f.get("x", -1)) == x and int(f.get("y", -1)) == y):
			kept.append(f)
	flags = kept
	return flags.size() < before


# The flag at (x, y) or an empty Dictionary if none.
func flag_at(x: int, y: int) -> Dictionary:
	for f in flags:
		if int(f.get("x", -1)) == x and int(f.get("y", -1)) == y:
			return f
	return {}


# Next unused flag index (deterministic: lowest free non-negative int).
func next_flag_index() -> int:
	var used: Dictionary = {}
	for f in flags:
		used[int(f.get("index", -1))] = true
	var i: int = 0
	while used.has(i):
		i += 1
	return i


func _sorted_flags() -> Array:
	var copy: Array = flags.duplicate(true)
	copy.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
	return copy


# --- Validation -------------------------------------------------------------

# Human-readable validation of the WHOLE scenario. Returns an Array of problem
# strings; empty means "ready to save / play-test".
func validate() -> Array:
	var problems: Array = []
	if ModProject.normalise_id(scenario_id) == "":
		problems.append("scenario id is empty/invalid")
	if width < MIN_DIM or height < MIN_DIM:
		problems.append("map is too small (min %dx%d)" % [MIN_DIM, MIN_DIM])
	if players.size() < 2:
		problems.append("a scenario needs at least 2 players")
	# Every player must own at least one HQ-like building so victory can resolve.
	var hq_owners: Dictionary = {}
	for b in buildings:
		hq_owners[int(b.get("owner", -1))] = true
	for p in players:
		if not hq_owners.has(int(p.get("owner", -1))):
			problems.append("player %d has no starting building (cannot be eliminated)" % int(p.get("owner", -1)))
	# Tech prerequisites must reference real tech ids.
	for tid in tech.keys():
		for pre in (tech[tid] as Dictionary).get("prerequisites", []):
			if not tech.has(ModProject.normalise_id(str(pre))):
				problems.append("tech '%s' requires unknown tech '%s'" % [str(tid), str(pre)])
	return problems


func is_valid() -> bool:
	return validate().is_empty()
