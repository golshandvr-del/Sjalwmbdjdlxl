# ma6_touch_probe.gd
# ----------------------------------------------------------------------------
# Project Nexus - MA6 scene-based touch-input probe.
#
# WHY THIS EXISTS (bug B7: "on mobile, units are not selected"):
# The pure unit tests in tests/test_runner.gd pin down TapSelectUtil's decision
# logic, and a static guard proves the HUD routes through it. But those run in
# --script mode, which has NO Nexus autoload and NO live input pipeline, so they
# cannot prove that a REAL InputEventScreenTouch actually reaches _handle_tap and
# selects a unit end-to-end.
#
# This probe closes that gap. It runs as a MAIN SCENE (not --script), so the
# Nexus autoload is present, instantiates the real mobile HUD, and injects a
# genuine press+release InputEventScreenTouch through the HUD's real input entry
# point (_unhandled_input -> _handle_touch -> _handle_tap). It then asserts:
#   1) tapping a friendly unit's tile selects that unit, and
#   2) tapping empty ground with a selection issues a move_unit command.
#
# Run headless (as a scene, so autoloads load):
#   godot --headless res://tests/ma6_touch_probe.tscn
# Exit code 0 = all probes passed, 1 = a probe failed.
extends Node

const LOCAL_PLAYER: int = 0

var _passed: int = 0
var _failed: int = 0

# Command types issued through Nexus.issue_command(), captured live via the
# EventBus "core.command" event. This is robust against tick timing (a command
# may be dispatched off the queue on the very next frame), because we record the
# emission itself rather than inspecting the pending queue.
var _issued_commands: Array = []


func _on_command(_event_name: String, payload: Dictionary) -> void:
	_issued_commands.append(str(payload.get("type", "")))


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] ", label)
	else:
		_failed += 1
		print("  [FAIL] ", label)


func _ready() -> void:
	# Defer to give the Nexus autoload a frame to finish its own _ready().
	call_deferred("_run")


func _run() -> void:
	print("===========================================")
	print("MA6 scene touch probe (real InputEventScreenTouch path)")
	print("-------------------------------------------")

	var nexus: Node = get_node_or_null("/root/Nexus")
	_check(nexus != null, "Nexus autoload is present (scene, not --script)")
	if nexus == null:
		_finish()
		return

	# Instantiate the REAL mobile game HUD (its scene root carries game_hud.gd).
	var scene: PackedScene = load("res://scenes/game_main.tscn")
	_check(scene != null, "game_main.tscn loads")
	if scene == null:
		_finish()
		return
	var hud: Node = scene.instantiate()
	add_child(hud)
	# Let the HUD's _ready() run (it sets up the skirmish + render adapter).
	await get_tree().process_frame
	await get_tree().process_frame

	var adapter: Object = hud.get_node_or_null("WorldLayer/RenderAdapter")
	_check(adapter != null, "HUD has a live RenderAdapter")
	if adapter == null:
		_finish()
		hud.free()
		return

	await _probe_select_and_move(nexus, hud, adapter)

	hud.free()
	_finish()


func _probe_select_and_move(nexus: Node, hud: Node, adapter: Object) -> void:
	var units_mod: Object = nexus.get_module("units")
	var map_mod: Object = nexus.get_module("map")
	_check(units_mod != null, "units module available")
	_check(map_mod != null, "map module available")
	if units_mod == null or map_mod == null:
		return

	# Spawn a friendly probe unit at a known interior tile.
	var tx: int = int(map_mod.width()) / 2
	var ty: int = int(map_mod.height()) / 2
	var uid: int = units_mod.spawn_unit("soldier", LOCAL_PLAYER, tx, ty)
	_check(uid > 0, "spawned a probe unit for the local player")

	# Freeze the sim and record every command the HUD issues via the EventBus.
	if nexus.sim_clock != null:
		nexus.sim_clock.pause()
	nexus.subscribe(nexus.EVENT_COMMAND, self, "_on_command")

	var vp: Vector2 = hud.get_viewport_rect().size
	adapter.center_camera_on(Vector2i(tx, ty), vp)
	var unit_px: Vector2 = _tile_centre_px(adapter, tx, ty)
	# Sanity: the pixel we will tap must map back to the unit's tile.
	_check(adapter.screen_to_tile(unit_px) == Vector2i(tx, ty),
		"tile-centre pixel maps back to the unit tile")

	# --- 1) Tap the unit's tile -> it must be selected. ---
	_issued_commands.clear()
	_tap(hud, unit_px)
	await get_tree().process_frame
	var selection: Array = hud.get("_selected_unit_ids")
	_check(selection.has(uid),
		"tapping a friendly unit selects it (real InputEventScreenTouch path)")
	_check(_issued_commands.has("select_units"), "tap issued a select_units command")

	# --- 2) Tap empty ground -> a move_unit command is issued for the selection. ---
	var ex: int = 0
	var ey: int = 0
	# The spawn tile is the map centre; a corner should be empty. If not, flip
	# to the opposite corner.
	if TapSelectUtil.unit_at_tile(_units_list(nexus), Vector2i(ex, ey), -1) != -1:
		ex = int(map_mod.width()) - 1
		ey = int(map_mod.height()) - 1
	adapter.center_camera_on(Vector2i(ex, ey), vp)
	var empty_px: Vector2 = _tile_centre_px(adapter, ex, ey)
	_check(adapter.screen_to_tile(empty_px) == Vector2i(ex, ey),
		"empty-tile centre pixel maps back to the empty tile")
	_issued_commands.clear()
	_tap(hud, empty_px)
	await get_tree().process_frame
	_check(_issued_commands.has("move_unit"),
		"tapping empty ground with a selection issues a move_unit command")


# The viewport pixel at the centre of tile (tx,ty): the exact inverse of the
# adapter's screen_to_tile, so the tap lands on the intended tile even though the
# adapter sits under a transformed parent (WorldLayer) and the window may carry a
# content_scale_factor. screen_to_tile computes:
#     local  = (viewport_to_canvas(px) - camera_offset) / zoom
#     tile   = floor(local / tile_size)
# with viewport_to_canvas(px) = global_canvas_xform.affine_inverse() * (px/factor).
# We invert it for the tile centre (local = (tile+0.5)*tile_size):
#     canvas = local*zoom + camera_offset
#     px     = factor * (global_canvas_xform * canvas)
func _tile_centre_px(adapter: Object, tx: int, ty: int) -> Vector2:
	var ts: int = int(adapter.get("tile_size"))
	var zoom: float = float(adapter.get("zoom"))
	var off: Vector2 = adapter.get("camera_offset")
	var local: Vector2 = Vector2((tx + 0.5) * ts, (ty + 0.5) * ts)
	var canvas: Vector2 = local * zoom + off
	var xform: Transform2D = (adapter as Node2D).get_global_transform_with_canvas()
	var px: Vector2 = xform * canvas
	var factor: float = 1.0
	var win: Window = (adapter as Node).get_window()
	if win != null and win.content_scale_factor > 0.0:
		factor = win.content_scale_factor
	return px * factor


# Inject a genuine (non-emulated) press+release touch through the HUD's real
# input entry point. device >= 0 so _is_emulated() does NOT drop it.
func _tap(hud: Node, pos: Vector2) -> void:
	var press: InputEventScreenTouch = InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = pos
	press.device = 0
	hud._unhandled_input(press)

	var release: InputEventScreenTouch = InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = pos
	release.device = 0
	hud._unhandled_input(release)


func _units_list(nexus: Node) -> Dictionary:
	return nexus.world_state.get_section("units").get("list", {})


func _finish() -> void:
	print("-------------------------------------------")
	print("MA6 PROBE  Total: %d   Passed: %d   Failed: %d" % [_passed + _failed, _passed, _failed])
	print("===========================================")
	get_tree().quit(0 if _failed == 0 else 1)
