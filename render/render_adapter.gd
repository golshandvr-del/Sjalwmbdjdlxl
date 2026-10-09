# render_adapter.gd
# ----------------------------------------------------------------------------
# Project Nexus - Render Adapter (Phase 1, step 1.9).
#
# THE ONE-WAY BRIDGE between simulation and presentation.
#
# Design Philosophy #5 (Logic/Render Separation): the render layer may READ the
# WorldState to draw the world, but it must NEVER write to it or drive the
# simulation. All player input becomes COMMANDS (handled by the UI layer), not
# direct render-side mutations.
#
# The RenderAdapter is a Node2D that, each frame, reads the authoritative
# "map", "buildings", and "units" sections from WorldState and asks a pluggable
# "style" to draw them. Swapping the style (style_simple now, style_detailed in
# Phase 6) changes the look WITHOUT touching any game logic.
#
# Coordinate model: tile (x, y) -> pixel (x * tile_size, y * tile_size), with a
# camera offset/zoom owned by the adapter. Helpers convert both ways so the UI
# can translate a screen tap into a tile for command issuing.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name RenderAdapter
extends Node2D

# Pixel size of a single grid tile.
@export var tile_size: int = 24

# The active drawing style. Must implement the methods called in _draw().
# Assigned in _ready() (StyleSimple by default).
var style: Object = null

# Phase 4.2: the swappable render-style registry. Both styles implement the
# IDENTICAL duck-typed interface (draw_tile / draw_building / draw_unit) so we
# can flip between them at runtime with ZERO changes to any game logic -- this
# is the whole point of the RenderAdapter (Logic/Render Separation). "simple" is
# the Mindustry-style flat renderer; "detailed" is the richer MOWAS-style one.
const STYLE_SIMPLE: String = "simple"
const STYLE_DETAILED: String = "detailed"

# Phase B.4: the texture-driven render style id.
const STYLE_SPRITE: String = "sprite"

# Currently active style id (one of the STYLE_* constants above).
var style_id: String = STYLE_SIMPLE

# Phase B.2/B.3: the shared texture cache used by the sprite style. Lazily
# created so headless tests that never draw don't pay for it.
var texture_service: TextureService = null

# Camera offset in pixels (pan) and zoom factor.
var camera_offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0

# BUG-4 (P3.1): interactive zoom limits (cosmetic only; never touches WorldState).
const ZOOM_MIN: float = 0.15
const ZOOM_MAX: float = 6.0

# Set of selected unit ids for the local player (for highlight drawing).
var selected_unit_ids: Array = []

# Fog of war (Phase 2.7): the local player whose visibility we render from.
# When >= 0, tiles and enemy entities outside this player's sight are dimmed
# (explored) or hidden. Set to -1 to disable fog rendering entirely.
var fog_viewer: int = -1

# Fog tile-state constants mirror FogOfWarModule (kept local to avoid a hard
# dependency on the module class from the render layer).
const FOG_HIDDEN: int = 0
const FOG_EXPLORED: int = 1
const FOG_VISIBLE: int = 2

# MC2 (request 2): cosmetic "last-image" memory. Each draw we let it observe the
# currently-VISIBLE tiles so EXPLORED tiles can be redrawn with the frozen image
# the viewer last saw (rather than leaking live enemy state). Purely a render
# aid -- never fed back into the simulation or the deterministic hash.
var _fog_snapshot: FogSnapshotUtil = FogSnapshotUtil.new()


# MC2.3 (request 2): expose the cosmetic last-image memory (read-only use) so
# the minimap can render the SAME frozen snapshot on EXPLORED tiles as the main
# view, instead of keeping a second diverging memory.
func fog_snapshot() -> FogSnapshotUtil:
	return _fog_snapshot


func _ready() -> void:
	if style == null:
		set_style(style_id)
	set_process(true)


# Phase 4.2: swap the active render style by id. Unknown ids fall back to the
# simple style. Returns the id that ended up active. This is the single entry
# point the UI uses to toggle the look at runtime -- no game logic is touched.
func set_style(id: String) -> String:
	match id:
		STYLE_DETAILED:
			style = StyleDetailed.new()
			style_id = STYLE_DETAILED
		STYLE_SPRITE:
			style = StyleSprite.new()
			style_id = STYLE_SPRITE
			_ensure_texture_service()
			style.texture_service = texture_service
		_:
			style = StyleSimple.new()
			style_id = STYLE_SIMPLE
	queue_redraw()
	return style_id


# Cycle through the available styles and return the now-active id. Handy for a
# single on-screen toggle button: simple -> detailed -> sprite -> simple.
func toggle_style() -> String:
	match style_id:
		STYLE_SIMPLE:
			return set_style(STYLE_DETAILED)
		STYLE_DETAILED:
			return set_style(STYLE_SPRITE)
		_:
			return set_style(STYLE_SIMPLE)


# Phase B.2: lazily build the texture cache (only the sprite style needs it).
func _ensure_texture_service() -> void:
	if texture_service == null:
		texture_service = TextureService.new()


func _process(_delta: float) -> void:
	# Redraw every frame from the latest world state (read-only).
	queue_redraw()


func _draw() -> void:
	if not Engine.has_singleton("Nexus") and not _has_nexus():
		return
	var world: Object = _world_state()
	if world == null:
		return
	# MC2 (request 2): refresh the last-image memory from what is currently
	# VISIBLE before drawing, so EXPLORED tiles can show a frozen snapshot.
	_observe_fog_snapshot(world)
	_draw_map(world)
	_draw_buildings(world)
	_draw_units(world)
	_draw_fog(world)


# MC2 (request 2): feed the current frame to the cosmetic snapshot memory.
func _observe_fog_snapshot(world: Object) -> void:
	if fog_viewer < 0:
		return
	var fog: Dictionary = world.get_section("fog")
	var buildings: Dictionary = world.get_section("buildings").get("list", {})
	var units: Dictionary = world.get_section("units").get("list", {})
	_fog_snapshot.observe(fog_viewer, fog, buildings, units)


# --- Drawing (delegated to the pluggable style) -----------------------------

func _draw_map(world: Object) -> void:
	var section: Dictionary = world.get_section("map")
	var w: int = int(section.get("width", 0))
	var h: int = int(section.get("height", 0))
	var tiles: Array = section.get("tiles", [])
	if w <= 0 or h <= 0:
		return
	for y in range(h):
		for x in range(w):
			var idx: int = y * w + x
			var terrain: int = int(tiles[idx]) if idx < tiles.size() else 0
			var rect: Rect2 = _tile_rect(x, y)
			style.draw_tile(self, rect, terrain, x, y)


func _draw_buildings(world: Object) -> void:
	var buildings: Dictionary = world.get_section("buildings").get("list", {})
	var keys: Array = buildings.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = buildings[key]
		# Fog: hide enemy buildings on tiles we have never explored.
		if _hidden_to_viewer(world, int(b.get("owner", -1)), int(b["x"]), int(b["y"])):
			continue
		var rect: Rect2 = _tile_rect(int(b["x"]), int(b["y"]))
		# Phase B.3: resolve the data-driven `visual` block and hand it to the
		# style. Read-only catalog lookup; the WorldState is never touched.
		var b_drawn: Dictionary = _with_visual(b, "buildings")
		style.draw_building(self, rect, b_drawn)


func _draw_units(world: Object) -> void:
	var units: Dictionary = world.get_section("units").get("list", {})
	var keys: Array = units.keys()
	keys.sort()
	for key in keys:
		var u: Dictionary = units[key]
		# Fog: enemy units are only visible on tiles we can currently SEE.
		if fog_viewer >= 0 and int(u.get("owner", -1)) != fog_viewer:
			if _fog_state(world, int(u["x"]), int(u["y"])) != FOG_VISIBLE:
				continue
		var rect: Rect2 = _tile_rect(int(u["x"]), int(u["y"]))
		var is_selected: bool = selected_unit_ids.has(int(u["id"]))
		# MB1.4 (bug 2b): draw a cosmetic destination MARKER (no line) for a
		# selected, moving unit so the player gets clear feedback the move
		# registered -- including while paused (move_goal persists in pause).
		if is_selected and u.has("move_goal"):
			_draw_move_goal(rect, u.get("move_goal", []))
		# Phase B.3: attach the data-driven `visual` block (read-only).
		var u_drawn: Dictionary = _with_visual(u, "units")
		style.draw_unit(self, rect, u_drawn, is_selected)


# --- Fog of war overlay (Phase 2.7) -----------------------------------------

# Draw a dimming overlay over explored tiles and a solid cover over hidden ones,
# from the local fog_viewer's perspective. No-op when fog is disabled.
func _draw_fog(world: Object) -> void:
	if fog_viewer < 0:
		return
	var fog: Dictionary = world.get_section("fog")
	var w: int = int(fog.get("width", 0))
	var h: int = int(fog.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var grid: Array = fog.get("visible", {}).get(str(fog_viewer), [])
	if grid.size() != w * h:
		return
	for y in range(h):
		for x in range(w):
			var state: int = int(grid[y * w + x])
			if state == FOG_VISIBLE:
				continue
			var rect: Rect2 = _tile_rect(x, y)
			if state == FOG_HIDDEN:
				# Never seen -> solid black cover.
				draw_rect(rect, Color(0, 0, 0, 0.85), true)
			else:  # EXPLORED
				# MC2 (request 2): draw the frozen "last image" of whatever the
				# viewer last saw on this tile (a dimmed owner-coloured marker),
				# THEN a semi-transparent dim over it so the memory reads as
				# "explored, not currently seen".
				_draw_remembered_tile(rect, x, y)
				draw_rect(rect, Color(0, 0, 0, 0.45), true)


# MC2 (request 2): render the remembered entity image (if any) on an EXPLORED
# tile. Cosmetic only; owner colours mirror the simple style's convention.
func _draw_remembered_tile(rect: Rect2, x: int, y: int) -> void:
	var mem: Dictionary = _fog_snapshot.remembered(x, y)
	if mem.is_empty():
		return
	var owner: int = int(mem.get("owner", -1))
	var col: Color = _remembered_owner_color(owner)
	if str(mem.get("kind", "")) == FogSnapshotUtil.KIND_BUILDING:
		# Buildings fill most of the tile.
		draw_rect(rect.grow(-rect.size.x * 0.15), col, true)
	else:
		# Units are a smaller centred blob.
		draw_circle(rect.get_center(), rect.size.x * 0.28, col)


func _remembered_owner_color(owner: int) -> Color:
	var palette: Array = [
		Color(0.30, 0.69, 0.95),  # 0 - blue
		Color(0.89, 0.33, 0.24),  # 1 - red
		Color(0.36, 0.75, 0.42),  # 2 - green
		Color(0.89, 0.71, 0.25),  # 3 - amber
	]
	if owner >= 0 and owner < palette.size():
		return palette[owner]
	return Color(0.7, 0.7, 0.7)


func _fog_state(world: Object, x: int, y: int) -> int:
	var fog: Dictionary = world.get_section("fog")
	var w: int = int(fog.get("width", 0))
	var h: int = int(fog.get("height", 0))
	if w <= 0 or x < 0 or y < 0 or x >= w or y >= h:
		return FOG_HIDDEN
	var grid: Array = fog.get("visible", {}).get(str(fog_viewer), [])
	var idx: int = y * w + x
	if idx < 0 or idx >= grid.size():
		return FOG_HIDDEN
	return int(grid[idx])


# MC2 (request 2): an enemy entity is only drawn LIVE on a tile we can currently
# SEE (VISIBLE). On HIDDEN tiles it is fully hidden; on EXPLORED tiles the live
# entity is suppressed too and the dimmed "last image" from the snapshot memory
# is drawn instead (see _draw_fog) -- this stops the map leaking the enemy's
# current state on tiles we no longer see.
func _hidden_to_viewer(world: Object, owner: int, x: int, y: int) -> bool:
	if fog_viewer < 0 or owner == fog_viewer:
		return false
	return _fog_state(world, x, y) != FOG_VISIBLE


# Phase B.3: return a SHALLOW COPY of `entity` with its catalog `visual` block
# attached (under the "visual" key). The original WorldState dict is never
# mutated -- visuals are cosmetic and must not affect the deterministic hash.
# `catalog_name` is "units" or "buildings"; the entity's "type" selects the row.
func _with_visual(entity: Dictionary, catalog_name: String) -> Dictionary:
	var type_id: String = str(entity.get("type", ""))
	if type_id == "":
		return entity
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus == null or nexus.data_loader == null:
		return entity
	var row: Variant = nexus.data_loader.get_entry(catalog_name, type_id)
	if not (row is Dictionary):
		return entity
	var visual: Variant = (row as Dictionary).get("visual", null)
	if not (visual is Dictionary):
		return entity
	var copy: Dictionary = entity.duplicate(false)
	copy["visual"] = visual
	return copy


# --- Coordinate conversion --------------------------------------------------

# MB1.4 (bug 2b): draw ONLY a small cosmetic destination marker at a selected
# unit's move target -- NO guide line. Per the user, the guide line looked bad in
# both normal and pause play, so it is removed; a faint dot/ring is kept so the
# player still gets clear feedback (also visible while paused, since `move_goal`
# is set on the unit regardless of pause state). Purely cosmetic: read from the
# unit's "move_goal" hint, never affects the deterministic hash.
func _draw_move_goal(_unit_rect: Rect2, goal: Array) -> void:
	if goal.size() < 2:
		return
	var goal_rect: Rect2 = _tile_rect(int(goal[0]), int(goal[1]))
	var to: Vector2 = goal_rect.position + goal_rect.size * 0.5
	var r: float = maxf(4.0, goal_rect.size.x * 0.22)
	# Faint filled dot + a slightly brighter thin ring so it reads on any terrain.
	draw_circle(to, r, Color(1.0, 1.0, 1.0, 0.30))
	draw_arc(to, r, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.55), 1.5)


func _tile_rect(x: int, y: int) -> Rect2:
	var px: float = (x * tile_size) * zoom + camera_offset.x
	var py: float = (y * tile_size) * zoom + camera_offset.y
	var size: float = tile_size * zoom
	return Rect2(px, py, size, size)


# BUG-5 fix (P0.5, THE root cause of "cannot move units" + "pinch zoom feels
# wrong"): map a raw INPUT position (the coordinate space Godot delivers to
# _input / _unhandled_input / _gui_input) into this adapter's CANVAS space.
#
# The game uses the "canvas_items" stretch mode and UiScale sets
# Window.content_scale_factor (e.g. 0.5 on small/HiDPI screens). In that mode the
# ENGINE scales the rendered canvas by content_scale_factor, but the input events
# it hands to our code are still in the *physical window* coordinate space --
# they are NOT pre-divided by that factor. Crucially,
# get_global_transform_with_canvas() returns IDENTITY here (it does not carry the
# stretch factor), so the old code mapped a physical tap straight through and
# landed on a tile near the corner (roughly tap*factor). Selecting a unit only
# "sometimes" worked by luck; issuing a MOVE to that wrong tile silently went
# nowhere the player intended -- exactly the reported bug.
#
# Correct, platform-independent conversion:
#     canvas = gtwc.affine_inverse() * (input_pos / content_scale_factor)
# When content_scale_factor == 1.0 (desktop, no scaling) this is identical to the
# previous behaviour, so nothing regresses.
func _viewport_to_canvas(pos: Vector2) -> Vector2:
	var scaled: Vector2 = pos
	if is_inside_tree():
		var win: Window = get_window()
		if win != null:
			var factor: float = win.content_scale_factor
			if factor > 0.0 and not is_equal_approx(factor, 1.0):
				scaled = pos / factor
		# Undo any parent (WorldLayer) offset via the real canvas transform.
		return get_global_transform_with_canvas().affine_inverse() * scaled
	# Headless / no tree: no stretch, no parent transform.
	return scaled


# Convert a screen-space pixel position into a tile coordinate.
#
# BUG-3 fix (P0.3): the adapter is a Node2D that may sit UNDER a transformed
# WorldLayer (offset/scale). A tap arrives in viewport space, so we first map it
# into THIS node's canvas space (accounting for the content-scale stretch factor
# and any parent offset), then undo the adapter's own camera pan/zoom. This makes
# taps land on the correct tile regardless of parent offset OR window scaling.
func screen_to_tile(pos: Vector2) -> Vector2i:
	var node_local: Vector2 = _viewport_to_canvas(pos)
	# node_local is now in the adapter's local pixel space; the camera pan/zoom
	# are applied inside _tile_rect on top of that, so undo them.
	var local: Vector2 = (node_local - camera_offset) / zoom
	return Vector2i(int(floor(local.x / tile_size)), int(floor(local.y / tile_size)))


func center_camera_on(tile: Vector2i, viewport_size: Vector2) -> void:
	camera_offset = viewport_size * 0.5 - Vector2(tile.x, tile.y) * tile_size * zoom


# --- BUG-4 (P3.1): interactive zoom + pan (pure presentation) ---------------
#
# All of these only mutate `zoom` / `camera_offset` and NEVER the WorldState, so
# they can never affect the deterministic hash. `focus` is the CANVAS-space point
# the zoom should keep stationary (e.g. the pinch midpoint or cursor), so zooming
# feels anchored under the fingers instead of jumping to a corner.
#
# NOTE: `focus` here is in the SAME space as camera_offset (canvas space). Input
# handlers get raw viewport/physical positions, so they must call zoom_at() below
# (which converts through the content-scale factor) rather than zoom_by()
# directly -- otherwise the anchor point drifts on scaled windows (BUG-5).
func zoom_by(factor: float, focus: Vector2) -> void:
	var old_zoom: float = zoom
	var new_zoom: float = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	# Keep the world point under `focus` fixed: solve for the offset so that the
	# same world coordinate maps to the same screen point after the zoom change.
	var world_point: Vector2 = (focus - camera_offset) / old_zoom
	zoom = new_zoom
	camera_offset = focus - world_point * new_zoom
	queue_redraw()


# Zoom anchored under a RAW input position (cursor / pinch midpoint in the
# viewport/physical space that Godot delivers to input callbacks). Converts the
# anchor into canvas space first so the point under the fingers stays fixed even
# when Window.content_scale_factor != 1 (BUG-5). All HUD input handlers should
# call this instead of zoom_by().
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	zoom_by(factor, _viewport_to_canvas(screen_pos))


# Zoom a fixed step in/out around the viewport centre (for the +/- buttons).
func zoom_step(zoom_in: bool, viewport_size: Vector2) -> void:
	var factor: float = 1.2 if zoom_in else (1.0 / 1.2)
	zoom_by(factor, viewport_size * 0.5)


# Pan by a CANVAS-space delta (camera_offset lives in canvas space).
func pan_by(delta: Vector2) -> void:
	camera_offset += delta
	queue_redraw()


# Pan by a RAW input-space delta (finger drag / mouse relative motion). Input
# deltas are in physical-window space, but camera_offset is canvas space, so on a
# scaled window (content_scale_factor != 1) the raw delta must be rescaled first
# or the map would drift faster/slower than the finger (BUG-5). A delta is a
# direction+length only, so we scale it (divide by factor) WITHOUT applying the
# canvas transform's translation.
func pan_by_screen(delta: Vector2) -> void:
	var scaled: Vector2 = delta
	if is_inside_tree():
		var win: Window = get_window()
		if win != null:
			var factor: float = win.content_scale_factor
			if factor > 0.0 and not is_equal_approx(factor, 1.0):
				scaled = delta / factor
	camera_offset += scaled
	queue_redraw()


# Clamp the camera so the map never scrolls completely off-screen. Keeps at
# least a margin of the map visible on every edge.
func clamp_camera(viewport_size: Vector2, margin_px: float = 64.0) -> void:
	var world: Object = _world_state()
	if world == null:
		return
	var section: Dictionary = world.get_section("map")
	var w: int = int(section.get("width", 0))
	var h: int = int(section.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var scaled_w: float = float(w * tile_size) * zoom
	var scaled_h: float = float(h * tile_size) * zoom
	# Allowed offset range: keep `margin_px` of the map on-screen at every edge.
	var min_x: float = viewport_size.x - scaled_w - margin_px
	var max_x: float = margin_px
	var min_y: float = viewport_size.y - scaled_h - margin_px
	var max_y: float = margin_px
	# If the map is smaller than the viewport, center it instead of clamping.
	if scaled_w <= viewport_size.x:
		camera_offset.x = (viewport_size.x - scaled_w) * 0.5
	else:
		camera_offset.x = clampf(camera_offset.x, min_x, max_x)
	if scaled_h <= viewport_size.y:
		camera_offset.y = (viewport_size.y - scaled_h) * 0.5
	else:
		camera_offset.y = clampf(camera_offset.y, min_y, max_y)
	queue_redraw()


# Phase A.1: fit the WHOLE map inside the viewport with a margin, then center it.
# This is the fix for the "tiny square in the corner" bug: the simulation's map
# is read from WorldState and the camera zoom + offset are computed so every tile
# is visible (instead of a fixed 24px tile_size that left huge maps off-screen).
# It is pure presentation (touches only zoom/camera_offset, never WorldState).
func fit_map_to_viewport(viewport_size: Vector2, margin_px: float = 24.0) -> void:
	var world: Object = _world_state()
	if world == null:
		return
	var section: Dictionary = world.get_section("map")
	var w: int = int(section.get("width", 0))
	var h: int = int(section.get("height", 0))
	if w <= 0 or h <= 0 or viewport_size.x <= 0 or viewport_size.y <= 0:
		return
	# Available drawing area after reserving a margin on every side (and room for
	# the top/bottom HUD bars, approximated by the margin).
	var avail_w: float = maxf(1.0, viewport_size.x - margin_px * 2.0)
	var avail_h: float = maxf(1.0, viewport_size.y - margin_px * 2.0 - 120.0)
	# World pixel size at zoom == 1.0.
	var world_w: float = float(w * tile_size)
	var world_h: float = float(h * tile_size)
	# Pick the zoom that makes the larger dimension fit (so nothing is cropped).
	var fit_zoom: float = minf(avail_w / world_w, avail_h / world_h)
	zoom = clampf(fit_zoom, 0.05, 8.0)
	# Center the scaled map inside the viewport.
	var scaled_w: float = world_w * zoom
	var scaled_h: float = world_h * zoom
	camera_offset = Vector2(
		(viewport_size.x - scaled_w) * 0.5,
		(viewport_size.y - scaled_h) * 0.5
	)
	queue_redraw()


# --- Read-only access to the simulation -------------------------------------

func _has_nexus() -> bool:
	return get_node_or_null("/root/Nexus") != null


func _world_state() -> Object:
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus == null:
		return null
	return nexus.world_state
