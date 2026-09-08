# scene_smoke.gd
# ----------------------------------------------------------------------------
# Project Nexus - Headless SCENE SMOKE runner (GUI audit tool).
#
# Instantiates every menu / editor scene inside a real SceneTree (with the
# Nexus autoload present, because it runs as the project's main scene via
# `godot --headless res://tools/scene_smoke.tscn`), lets it run a few frames,
# then presses every visible Button that does NOT navigate away, and reports
# any scene that failed to load or instantiate. Runtime script errors surface
# in the engine log; the process exit code is non-zero if any scene failed.
#
# Purely a development tool: never referenced by gameplay code.
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
extends Node

const SCENES: Array = [
	"res://scenes/main_menu.tscn",
	"res://scenes/options_menu.tscn",
	"res://scenes/match_setup.tscn",
	"res://scenes/custom_games.tscn",
	"res://scenes/save_load_menu.tscn",
	"res://scenes/editor_hub.tscn",
	"res://scenes/editor_defaults.tscn",
	"res://scenes/map_editor.tscn",
	"res://scenes/mod_editor.tscn",
	"res://scenes/gui_editor.tscn",
	"res://scenes/ai_builder.tscn",
	"res://scenes/lobby.tscn",
]

var _failures: int = 0
# Buttons whose handler swapped the current scene (informational).
var _navigations: int = 0


func _ready() -> void:
	if has_meta("is_runner"):
		return
	# This node is the CURRENT SCENE, so any button that calls
	# change_scene_to_file() would free it mid-sweep. Hand the work to a runner
	# parked directly under the root (survives scene swaps).
	var runner: Node = Node.new()
	runner.name = "SceneSmokeRunner"
	runner.set_script(get_script())
	runner.set_meta("is_runner", true)
	get_tree().root.add_child.call_deferred(runner)


func _enter_tree() -> void:
	if has_meta("is_runner"):
		_run.call_deferred()


func _run() -> void:
	for path in SCENES:
		await _smoke_scene(str(path))
	print("SCENE_SMOKE_DONE failures=%d navigations=%d" % [_failures, _navigations])
	get_tree().quit(1 if _failures > 0 else 0)


func _smoke_scene(path: String) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		print("SCENE_SMOKE_FAIL load %s" % path)
		_failures += 1
		return
	var node: Node = ps.instantiate()
	if node == null:
		print("SCENE_SMOKE_FAIL instantiate %s" % path)
		_failures += 1
		return
	add_child(node)
	for i in range(3):
		await get_tree().process_frame
	var buttons: Array = node.find_children("*", "BaseButton", true, false)
	var pressed: int = 0
	for b in buttons:
		if not is_instance_valid(b):
			# A previous press navigated away and freed this scene; the rest
			# of its buttons are gone too.
			break
		var button: BaseButton = b
		if not button.is_visible_in_tree() or button.disabled:
			continue
		if button.toggle_mode:
			continue
		# Navigation buttons would swap the current scene under us; skip the
		# obvious ones by name so the sweep stays within this scene.
		var lname: String = button.name.to_lower()
		if lname.contains("back") or lname.contains("quit") or lname.contains("start") \
				or lname.contains("host") or lname.contains("join") or lname.contains("play") \
				or lname.contains("load") or lname.contains("restart") or lname.contains("editor") \
				or lname.contains("games") or lname.contains("save") or lname.contains("single") \
				or lname.contains("mobile") or lname.contains("desktop") or lname.contains("offline") \
				or lname.contains("online") or lname.contains("multiplayer") or lname.contains("gear") \
				or lname.contains("options") or lname.contains("defaults") or lname.contains("builder"):
			continue
		if not is_instance_valid(button) or not button.is_inside_tree():
			continue
		var scene_before: Node = get_tree().current_scene
		button.emit_signal("pressed")
		pressed += 1
		await get_tree().process_frame
		if get_tree().current_scene != scene_before:
			_navigations += 1
			print("SCENE_SMOKE_NAV %s -> button changed scene" % path)
			if not is_instance_valid(node):
				break
	print("SCENE_SMOKE_OK %s buttons=%d pressed=%d" % [path, buttons.size(), pressed])
	if is_instance_valid(node):
		node.queue_free()
	await get_tree().process_frame
