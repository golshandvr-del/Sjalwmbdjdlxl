# ui_scale.gd
# ----------------------------------------------------------------------------
# Project Nexus - GUI Scale applier (Phase G).
#
# A tiny, shared helper that turns the persisted GUI-scale preference
# (GameSettings.ui_scale / ui_scale_auto) into a live window
# `content_scale_factor`, so the *whole* interface -- main menu, options, the
# in-game HUD buttons, the editors -- grows or shrinks together.
#
# Why a window content_scale_factor (and not per-control font sizes)?
#   - It scales every Control uniformly in one place, including button minimum
#     sizes, fonts, and margins, with zero per-scene bookkeeping.
#   - It is purely a *presentation* knob: it changes how big the UI is drawn and
#     NEVER touches WorldState or the deterministic simulation hash (it sits in
#     the same "cosmetic-only" category as render style and locale).
#
# Usage (called from any UI scene's _ready, and on viewport resize):
#   UiScale.apply_from_settings(self)
#
# The helper resolves the active GameSettings (loading it from disk if needed),
# asks it for the scale to use given the current screen size, and writes that to
# the window. It degrades gracefully when run head-less or in isolation: if there
# is no window/tree it simply does nothing.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name UiScale
extends RefCounted


# Apply the persisted GUI scale to the window that owns `node`. Loads settings
# from disk so a fresh launch already honours the player's choice. Returns the
# scale factor that was applied (1.0 when no window is available).
static func apply_from_settings(node: Node, world: WorldState = null) -> float:
	var settings: GameSettings = GameSettings.new(world)
	settings.load_from_file()
	return apply_with_settings(node, settings)


# Apply using an already-constructed GameSettings (preferred when the caller
# already owns one, avoiding a second disk read). Reads the current screen size
# from the node's window and writes the resolved content_scale_factor.
static func apply_with_settings(node: Node, settings: GameSettings) -> float:
	if node == null or not node.is_inside_tree():
		return 1.0
	var window: Window = node.get_window()
	if window == null:
		return 1.0
	var screen_size: Vector2 = _screen_size_for(window)
	var scale: float = settings.resolve_ui_scale(screen_size)
	window.content_scale_factor = scale
	return scale


# Resolve the screen size we should scale against. On a real device/window the
# physical window size is the right reference; we fall back to the configured
# viewport size if the window has not been sized yet.
static func _screen_size_for(window: Window) -> Vector2:
	var size: Vector2 = Vector2(window.size)
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(window.content_scale_size)
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(GameSettings.REFERENCE_WIDTH, GameSettings.REFERENCE_HEIGHT)
	return size
