# game_settings.gd
# ----------------------------------------------------------------------------
# Project Nexus - Game Settings Service (Phase 6, step 6.1).
#
# A small, self-contained, *persisted* preferences store for player-facing
# options that must outlive a single match (and a single launch): UI locale,
# render style, default AI difficulty, camera zoom, and the sound toggles.
#
# Design notes (consistent with the rest of the project):
#   - Settings live in a single WorldState section ("ui_prefs") so they ride
#     along with the existing state model and are trivially inspectable. The
#     main menu already stashed "locale" there in Phase 5; this service formalises
#     that section, adds the rest of the knobs, and validates every write.
#   - Persistence is a *separate* JSON file from the game save (the SaveSystem
#     owns match state; settings are global), written to `user://` so it works on
#     every export platform without touching the project tree.
#   - Every setter validates against an allow-list / range and is idempotent, so
#     a corrupt or hand-edited settings file can never push the game into an
#     invalid state -- unknown values fall back to the documented default.
#   - No engine singletons are required: the service is constructed with (or
#     lazily finds) the WorldState, which keeps it unit-testable headlessly.
#
# This is intentionally UI-cosmetic / global-preference state only. It NEVER
# feeds the deterministic simulation hash (render style and locale are proven
# cosmetic in Phase 4/5); the "difficulty" stored here is only the *default*
# offered in the menu -- the authoritative in-match difficulty is still owned by
# the difficulty module.
extends RefCounted
class_name GameSettings

# The WorldState section that holds every persisted preference.
const SECTION: String = "ui_prefs"

# Default settings file path (overridable for tests).
const DEFAULT_PATH: String = "user://nexus_settings.json"

# Allowed values / ranges (the single source of truth for validation).
# P1.2 (v0.6.0): the texture-driven "sprite" style is now a first-class,
# selectable render style (and the new default -- see DEFAULTS below).
const RENDER_STYLES: Array = ["simple", "detailed", "sprite"]
const DIFFICULTIES: Array = ["easy", "normal", "hard"]
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 3.0

# GUI scale range (Phase G). This is the *manual* multiplier applied to the
# whole UI (menus + in-game HUD buttons) via the window content_scale_factor.
# It is purely cosmetic: it scales how big the interface is drawn and NEVER
# touches the deterministic simulation hash. When `ui_scale_auto` is true the
# manual value is ignored and the scale is computed from the device/screen size.
const UI_SCALE_MIN: float = 0.5
const UI_SCALE_MAX: float = 3.0

# The documented default content root, mirrored from StorageService so a missing
# settings file resolves to the same platform-portable location the storage
# layer would use. Kept as a literal (not a hard dependency) so the settings
# service stays loadable on its own in headless tests.
const DEFAULT_CONTENT_PATH: String = "user://content"

# Documented defaults applied when a key is missing or invalid.
const DEFAULTS: Dictionary = {
	"locale": "en",
	"render_style": "sprite",
	"difficulty": "normal",
	"camera_zoom": 1.0,
	"sfx_enabled": true,
	"music_enabled": true,
	"content_path": DEFAULT_CONTENT_PATH,
	# GUI scaling (Phase G). Auto is ON by default so the interface fits every
	# device out of the box; the manual multiplier is only consulted when auto
	# is turned off.
	"ui_scale": 1.0,
	"ui_scale_auto": true,
}

var _world: WorldState = null


# Construct against an explicit WorldState (preferred for tests). When null, the
# service resolves the live /root/Nexus.world_state on first use.
func _init(world: WorldState = null) -> void:
	_world = world


# Ensure the ui_prefs section exists and contains every key with a valid value,
# filling any gap with the documented default. Safe to call repeatedly.
func ensure_defaults() -> void:
	var section: Dictionary = _section()
	for key in DEFAULTS.keys():
		if not section.has(key) or not _is_valid(key, section[key]):
			section[key] = DEFAULTS[key]


# --- Typed getters (always return a valid, in-range value) ------------------

func get_locale() -> String:
	return str(_get_pref("locale"))


func get_render_style() -> String:
	return str(_get_pref("render_style"))


func get_difficulty() -> String:
	return str(_get_pref("difficulty"))


func get_camera_zoom() -> float:
	return float(_get_pref("camera_zoom"))


func is_sfx_enabled() -> bool:
	return bool(_get_pref("sfx_enabled"))


func is_music_enabled() -> bool:
	return bool(_get_pref("music_enabled"))


# The configurable content root used by the StorageService / pack pipeline
# (Phase C). Always returns a non-empty path (falls back to the default).
func get_content_path() -> String:
	return str(_get_pref("content_path"))


# The manual GUI scale multiplier (Phase G). Always in [UI_SCALE_MIN, UI_SCALE_MAX].
# Only used for drawing the interface when auto-scaling is OFF.
func get_ui_scale() -> float:
	return float(_get_pref("ui_scale"))


# When true (the default), the GUI scale is derived automatically from the
# device/screen size and the manual `ui_scale` value is ignored.
func is_ui_scale_auto() -> bool:
	return bool(_get_pref("ui_scale_auto"))


# --- Validated setters (return true when the value was accepted) ------------

func set_locale(value: String) -> bool:
	# Any non-empty locale id is accepted here; the Localization service decides
	# whether a matching file exists. This keeps settings decoupled from disk.
	if value.strip_edges().is_empty():
		return false
	_set_pref("locale", value)
	return true


func set_render_style(value: String) -> bool:
	if not RENDER_STYLES.has(value):
		return false
	_set_pref("render_style", value)
	return true


func set_difficulty(value: String) -> bool:
	if not DIFFICULTIES.has(value):
		return false
	_set_pref("difficulty", value)
	return true


func set_camera_zoom(value: float) -> bool:
	if value < ZOOM_MIN or value > ZOOM_MAX:
		return false
	_set_pref("camera_zoom", value)
	return true


func set_sfx_enabled(value: bool) -> void:
	_set_pref("sfx_enabled", value)


func set_music_enabled(value: bool) -> void:
	_set_pref("music_enabled", value)


# Set the content root for installed/authored packages. Any non-empty path is
# accepted (the StorageService normalises + creates it); an empty/whitespace
# value is rejected so the setting can never become unusable.
func set_content_path(value: String) -> bool:
	if value.strip_edges().is_empty():
		return false
	_set_pref("content_path", value.strip_edges())
	return true


# Set the manual GUI scale multiplier (Phase G). Rejected (state untouched) when
# outside the documented [UI_SCALE_MIN, UI_SCALE_MAX] range so a corrupt value
# can never make the interface unusable.
func set_ui_scale(value: float) -> bool:
	if value < UI_SCALE_MIN or value > UI_SCALE_MAX:
		return false
	_set_pref("ui_scale", value)
	return true


# Toggle automatic GUI scaling (Phase G). Always accepted.
func set_ui_scale_auto(value: bool) -> void:
	_set_pref("ui_scale_auto", value)


# --- GUI scale resolution (Phase G) -----------------------------------------
#
# The single source of truth for "how big should the interface be drawn". The
# UI was designed against a 1280x720 reference; on a device whose screen is
# larger (a tablet, a 4K monitor) the same pixel sizes look tiny, and on a small
# phone they overflow. `auto_scale_for` maps an actual screen size to a sensible
# content_scale_factor by comparing it to that reference, clamped to the allowed
# range. This is pure math (no engine singletons) so it is unit-testable.

# The design reference resolution the menus/HUD were laid out against.
const REFERENCE_WIDTH: float = 1280.0
const REFERENCE_HEIGHT: float = 720.0


# Compute the automatic GUI scale for a given screen size (in physical pixels).
# Uses the smaller of the width/height ratios so the whole interface always
# fits, rounds to a tidy step, and clamps into [UI_SCALE_MIN, UI_SCALE_MAX].
static func auto_scale_for(screen_size: Vector2) -> float:
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return 1.0
	var ratio_w: float = screen_size.x / REFERENCE_WIDTH
	var ratio_h: float = screen_size.y / REFERENCE_HEIGHT
	var ratio: float = min(ratio_w, ratio_h)
	# Round to the nearest 0.05 so the scale is stable across tiny size jitter.
	ratio = round(ratio / 0.05) * 0.05
	return clampf(ratio, UI_SCALE_MIN, UI_SCALE_MAX)


# The GUI scale that should actually be applied right now, honouring the
# auto/manual toggle: when auto is on, derive it from `screen_size`; otherwise
# use the stored manual multiplier. Always returns a valid, clamped value.
func resolve_ui_scale(screen_size: Vector2) -> float:
	if is_ui_scale_auto():
		return auto_scale_for(screen_size)
	return clampf(get_ui_scale(), UI_SCALE_MIN, UI_SCALE_MAX)


# Reset every preference back to its documented default.
func reset_to_defaults() -> void:
	for key in DEFAULTS.keys():
		_set_pref(key, DEFAULTS[key])


# --- Persistence (separate from the game save) ------------------------------

# Write the current preferences to a JSON file. Returns true on success.
func save_to_file(path: String = DEFAULT_PATH) -> bool:
	ensure_defaults()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameSettings: cannot open '%s' for writing" % path)
		return false
	file.store_string(JSON.stringify(_export_dict(), "\t"))
	file.close()
	return true


# Load preferences from a JSON file, validating every value. A missing file is
# NOT an error (first run): defaults are applied and true is returned.
func load_from_file(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		ensure_defaults()
		return true
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GameSettings: cannot open '%s' for reading" % path)
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("GameSettings: invalid settings file '%s' -- using defaults" % path)
		ensure_defaults()
		return false
	_import_dict(parsed as Dictionary)
	return true


# A plain copy of the current settings (defaults guaranteed). Useful for UIs.
func to_dict() -> Dictionary:
	return _export_dict()


# --- Internals --------------------------------------------------------------

func _export_dict() -> Dictionary:
	ensure_defaults()
	var out: Dictionary = {}
	for key in DEFAULTS.keys():
		out[key] = _section()[key]
	return out


func _import_dict(data: Dictionary) -> void:
	# Accept only known keys with valid values; everything else falls to default.
	var section: Dictionary = _section()
	for key in DEFAULTS.keys():
		if data.has(key) and _is_valid(key, data[key]):
			section[key] = _coerce(key, data[key])
		else:
			section[key] = DEFAULTS[key]


func _is_valid(key: String, value: Variant) -> bool:
	match key:
		"locale":
			return value is String and not (value as String).strip_edges().is_empty()
		"render_style":
			return value is String and RENDER_STYLES.has(value)
		"difficulty":
			return value is String and DIFFICULTIES.has(value)
		"camera_zoom":
			var n: float = float(value) if (value is float or value is int) else -1.0
			return n >= ZOOM_MIN and n <= ZOOM_MAX
		"sfx_enabled", "music_enabled", "ui_scale_auto":
			return value is bool
		"content_path":
			return value is String and not (value as String).strip_edges().is_empty()
		"ui_scale":
			var s: float = float(value) if (value is float or value is int) else -1.0
			return s >= UI_SCALE_MIN and s <= UI_SCALE_MAX
	return false


func _coerce(key: String, value: Variant) -> Variant:
	if key == "camera_zoom" or key == "ui_scale":
		return float(value)
	return value


func _get_pref(key: String) -> Variant:
	var section: Dictionary = _section()
	if not section.has(key) or not _is_valid(key, section[key]):
		section[key] = DEFAULTS[key]
	return section[key]


func _set_pref(key: String, value: Variant) -> void:
	_section()[key] = value


# Resolve (and lazily create) the ui_prefs section, using the injected
# WorldState when present, otherwise the live Nexus singleton.
func _section() -> Dictionary:
	var ws: WorldState = _resolve_world()
	if ws == null:
		# No world available (extreme edge case): return a throwaway dict so calls
		# never crash; persistence will still operate on real state once present.
		return {}
	return ws.get_section(SECTION)


func _resolve_world() -> WorldState:
	if _world != null:
		return _world
	var nexus: Node = Engine.get_main_loop().get_root().get_node_or_null("Nexus") if Engine.get_main_loop() is SceneTree else null
	if nexus != null and nexus.has_method("get") and nexus.get("world_state") != null:
		_world = nexus.world_state
	return _world
