# nav_service.gd
# ----------------------------------------------------------------------------
# Project Nexus - Back-navigation service (Phase MB3 / bug 6).
#
# The bug this fixes: on Android the hardware/gesture BACK button quits the whole
# app from every screen instead of returning to the previous menu. Godot delivers
# that press as NOTIFICATION_WM_GO_BACK_REQUEST (and, for keyboards / the ESC key,
# as the "ui_cancel" action). Left unhandled, the default is to quit.
#
# This helper is the SINGLE SOURCE OF TRUTH for "where does BACK go from screen
# X?". It is a pure, dependency-free static util (no SceneTree, no autoload) so it
# is fully unit-testable headless. Each scene keeps its own _on_back() (which
# already knows how to tear down its own session / editor state); this service
# only answers the routing question and provides a tiny helper that scenes call
# from _notification()/_unhandled_input() so the behaviour is identical
# everywhere.
#
# Design rules:
#   * The main menu is the ROOT: BACK there does NOT silently quit; it asks the
#     scene to confirm (the scene decides how -- a dialog, or quit on a second
#     press). back_target() returns "" for the root so callers know to confirm.
#   * In-game (the HUD scenes) BACK should open pause / return to menu WITH a
#     confirm, never an instant quit. is_in_game() flags those scenes.
#   * Every other scene maps to its logical parent (usually the main menu, but
#     e.g. the online lobby's parent is the main menu too). The map is data, so
#     adding a screen is a one-line change and a test guards completeness.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name NavService
extends RefCounted

# Canonical scene paths (kept in one place so callers and tests agree).
const MAIN_MENU: String = "res://scenes/main_menu.tscn"
const MATCH_SETUP: String = "res://scenes/match_setup.tscn"
const LOBBY: String = "res://scenes/lobby.tscn"
const OPTIONS: String = "res://scenes/options_menu.tscn"
const MOD_EDITOR: String = "res://scenes/mod_editor.tscn"
const MAP_EDITOR: String = "res://scenes/map_editor.tscn"
const CUSTOM_GAMES: String = "res://scenes/custom_games.tscn"
const SAVE_LOAD: String = "res://scenes/save_load_menu.tscn"
const GAME_MOBILE: String = "res://scenes/game_main.tscn"
const GAME_DESKTOP: String = "res://scenes/game_desktop.tscn"

# The in-game HUD scenes. BACK here must confirm (pause / leave), never quit.
const IN_GAME_SCENES: Array = [GAME_MOBILE, GAME_DESKTOP]

# Logical parent of every non-root scene. BACK from a key routes here. The main
# menu is intentionally ABSENT (it is the root: back_target() returns "").
const PARENTS: Dictionary = {
	MATCH_SETUP: MAIN_MENU,
	LOBBY: MAIN_MENU,
	OPTIONS: MAIN_MENU,
	MOD_EDITOR: MAIN_MENU,
	MAP_EDITOR: MAIN_MENU,
	CUSTOM_GAMES: MAIN_MENU,
	SAVE_LOAD: MAIN_MENU,
	# In-game scenes route to the menu but only AFTER a confirm (see is_in_game).
	GAME_MOBILE: MAIN_MENU,
	GAME_DESKTOP: MAIN_MENU,
}


# Return the scene BACK should navigate to from `scene`, or "" when `scene` is
# the root (main menu) and BACK should instead trigger a confirm-to-quit.
static func back_target(scene: String) -> String:
	return str(PARENTS.get(scene, ""))


# True when `scene` is the root of the navigation tree (BACK confirms, no parent).
static func is_root(scene: String) -> bool:
	return scene == MAIN_MENU or back_target(scene) == ""


# True when `scene` is an in-game HUD: BACK should open pause / confirm-leave
# rather than immediately changing scene.
static func is_in_game(scene: String) -> bool:
	return IN_GAME_SCENES.has(scene)


# Every scene BACK can meaningfully act from (root + all mapped children).
static func known_scenes() -> Array:
	var scenes: Array = [MAIN_MENU]
	for key in PARENTS.keys():
		if not scenes.has(key):
			scenes.append(key)
	scenes.sort()
	return scenes
