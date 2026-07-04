# Temporary scene instantiation smoke-check (removed after use).
# Loads and instantiates every main scene to surface runtime @onready/.tscn bugs
# that a pure file-exists test would miss. Run headless:
#   godot --headless --path . --script res://tests/_tmp_scene_check.gd
extends SceneTree

func _init() -> void:
	var scenes: Array = [
		"res://scenes/custom_games.tscn",
		"res://scenes/debug_main.tscn",
		"res://scenes/game_desktop.tscn",
		"res://scenes/game_main.tscn",
		"res://scenes/lobby.tscn",
		"res://scenes/main_menu.tscn",
		"res://scenes/map_editor.tscn",
		"res://scenes/match_setup.tscn",
		"res://scenes/mod_editor.tscn",
		"res://scenes/options_menu.tscn",
		"res://scenes/save_load_menu.tscn",
	]
	var ok: int = 0
	var bad: int = 0
	for path in scenes:
		var ps: PackedScene = load(path)
		if ps == null:
			print("[BAD]  load returned null: ", path)
			bad += 1
			continue
		var inst: Node = ps.instantiate()
		if inst == null:
			print("[BAD]  instantiate returned null: ", path)
			bad += 1
			continue
		print("[OK]   ", path, "  (", inst.get_class(), ", children=", inst.get_child_count(), ")")
		inst.free()
		ok += 1
	print("---- scene smoke-check: OK=", ok, " BAD=", bad, " ----")
	quit(0 if bad == 0 else 1)
