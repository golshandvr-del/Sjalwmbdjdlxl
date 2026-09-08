# game_smoke.gd
# ----------------------------------------------------------------------------
# Project Nexus - Headless IN-GAME smoke runner (GUI audit tool).
#
# Boots a real skirmish through the actual game HUD scenes (mobile + desktop),
# lets the simulation run, presses every visible HUD button, then issues a
# spawn + move order and verifies units actually travel. Runtime script errors
# surface in the engine log. With `--write-png` (via OS.get_cmdline_user_args)
# it also captures the rendered frame (needs a non-headless run) for review.
#
# Run: godot --headless res://tools/game_smoke.tscn
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
extends Node

const SCENES: Array = ["res://scenes/game_main.tscn", "res://scenes/game_desktop.tscn"]

var _failures: int = 0


func _ready() -> void:
	if has_meta("is_runner"):
		return
	var runner: Node = Node.new()
	runner.name = "GameSmokeRunner"
	runner.set_script(get_script())
	runner.set_meta("is_runner", true)
	get_tree().root.add_child.call_deferred(runner)


func _enter_tree() -> void:
	if has_meta("is_runner"):
		_run.call_deferred()


func _run() -> void:
	var write_png: bool = OS.get_cmdline_user_args().has("--write-png")
	for path in SCENES:
		await _smoke_game(str(path), write_png)
	print("GAME_SMOKE_DONE failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _smoke_game(path: String, write_png: bool) -> void:
	var nexus: Object = get_tree().root.get_node("Nexus")
	var config: Dictionary = nexus.world_state.get_section("match_config")
	config["scenario_id"] = "skirmish_basic"
	config["difficulty"] = "normal"
	config["human_players"] = 1
	config["ai_players"] = 1
	config["game_mode"] = "annihilation"
	var ps: PackedScene = load(path)
	if ps == null:
		print("GAME_SMOKE_FAIL load %s" % path)
		_failures += 1
		return
	var node: Node = ps.instantiate()
	get_tree().root.add_child(node)
	get_tree().current_scene = node
	for i in range(5):
		await get_tree().process_frame
	# Simulation must be running and populated.
	var units: Dictionary = nexus.world_state.get_section("units").get("list", {})
	var buildings: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	print("GAME_SMOKE %s units=%d buildings=%d tick=%d" % [path, units.size(), buildings.size(), int(nexus.world_state.current_tick)])
	if buildings.is_empty():
		print("GAME_SMOKE_FAIL %s: no buildings after setup" % path)
		_failures += 1
	# Let time pass (production, AI, fog).
	await get_tree().create_timer(2.0).timeout
	if write_png:
		await _capture("user://smoke_%s_clean.png" % path.get_file().get_basename())
	var tick_after: int = int(nexus.world_state.current_tick)
	if tick_after <= 0:
		print("GAME_SMOKE_FAIL %s: simulation did not advance" % path)
		_failures += 1
	# Press every visible, non-toggle HUD button once.
	var pressed: int = 0
	for b in node.find_children("*", "BaseButton", true, false):
		if not is_instance_valid(b) or not is_instance_valid(node):
			break
		var button: BaseButton = b
		if not button.is_visible_in_tree() or button.disabled or button.toggle_mode:
			continue
		var lname: String = button.name.to_lower()
		# Pause would freeze the sim for the movement probe below; menu/quit
		# would navigate away.
		if lname.contains("restart") or lname.contains("menu") or lname.contains("quit") \
				or lname.contains("back") or lname.contains("pause"):
			continue
		button.emit_signal("pressed")
		pressed += 1
		await get_tree().process_frame
	print("GAME_SMOKE %s pressed=%d buttons" % [path, pressed])
	# Spawn a unit and order it across the map: it MUST move.
	var units_mod: Object = nexus.module_registry.get_module("units")
	var uid: int = units_mod.spawn_unit("soldier", 0, 3, 3)
	var before: Dictionary = units_mod.get_unit(uid).duplicate()
	nexus.issue_command("move_unit", 0, { "unit_ids": [uid], "x": 12, "y": 8 }, 1)
	# Sample the position every frame: the unit may legitimately DIE in combat
	# on the way (the AI is live), so "moved" means it left its spawn tile at
	# any point before the probe ended, not that it survived.
	var moved: bool = false
	var last: Dictionary = before
	var deadline: float = Time.get_ticks_msec() / 1000.0 + 2.0
	while Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().process_frame
		var now: Dictionary = units_mod.get_unit(uid)
		if now.is_empty():
			break
		last = now.duplicate()
		if int(now["x"]) != int(before["x"]) or int(now["y"]) != int(before["y"]):
			moved = true
	print("GAME_SMOKE %s unit moved=%s (%d,%d)->(%d,%d) alive=%s" % [path, str(moved),
		int(before["x"]), int(before["y"]), int(last["x"]), int(last["y"]),
		str(not units_mod.get_unit(uid).is_empty())])
	if not moved:
		print("GAME_SMOKE_FAIL %s: spawned unit did not move" % path)
		_failures += 1
	if write_png:
		await _capture("user://smoke_%s.png" % path.get_file().get_basename())
	# Tear the match down the same way the HUD's Restart/Menu path does so the
	# next scene starts from a clean WorldState.
	nexus.shutdown_simulation()
	if is_instance_valid(node):
		node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(out: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out)
	print("GAME_SMOKE wrote %s" % ProjectSettings.globalize_path(out))
