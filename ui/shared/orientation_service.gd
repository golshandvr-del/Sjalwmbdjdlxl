# orientation_service.gd
# ----------------------------------------------------------------------------
# Project Nexus - Screen orientation applier (Phase MB4, bugs 7/17/18).
#
# A tiny shared helper that turns the persisted screen-orientation preference
# (GameSettings.screen_orientation: "auto"/"portrait"/"landscape") into a live
# DisplayServer orientation lock. Callers apply it from a UI scene's _ready so
# the app respects the player's choice on every screen, and re-apply it when the
# setting changes in the options panel.
#
# Why a helper (and not inline DisplayServer calls)?
#   - It centralises the "setting -> DisplayServer constant" mapping (which lives,
#     tested, in GameSettings.orientation_to_display_constant) and the platform
#     guard, so every scene applies orientation identically.
#   - It is purely a *presentation* knob: it changes how the window is oriented
#     and NEVER touches WorldState or the deterministic simulation hash (same
#     cosmetic-only category as GUI scale and locale).
#
# It degrades gracefully: on desktop/headless where orientation locking is a
# no-op (or unsupported) it simply does nothing and reports the resolved value.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name OrientationService
extends RefCounted


# Apply the persisted orientation. Loads settings from disk so a fresh launch
# already honours the player's choice. Returns the DisplayServer constant that
# was resolved (even when the platform ignores it), so callers/tests can assert.
static func apply_from_settings(world: WorldState = null) -> int:
	var settings: GameSettings = GameSettings.new(world)
	settings.load_from_file()
	return apply_with_settings(settings)


# Apply using an already-constructed GameSettings (preferred when the caller
# already owns one). Maps the stored orientation to a DisplayServer constant and
# requests it. On platforms/headless where the call is unavailable this is a safe
# no-op; the resolved constant is still returned.
static func apply_with_settings(settings: GameSettings) -> int:
	var constant: int = GameSettings.orientation_to_display_constant(settings.get_screen_orientation())
	if DisplayServer.has_method("screen_set_orientation"):
		# Guard the call so a headless/CI run (which has a DisplayServer stub that
		# may reject orientation changes) never aborts the scene.
		DisplayServer.screen_set_orientation(constant)
	return constant
