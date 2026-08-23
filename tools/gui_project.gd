# gui_project.gd
# ----------------------------------------------------------------------------
# Project Nexus - GUI authoring model (Phase MC7, request 8).
#
# `GuiProject` is the IN-MEMORY, data-driven model of a customizable GUI: a set
# of named PAGES (main / options / multiplayer / in-game / ...), each holding a
# list of WIDGETS. A widget is a positioned, named, icon-bearing control whose
# FUNCTION is fixed by its `logical_id` (e.g. "single", "host", "zoom_in") while
# its POSITION / SIZE / ICON / DISPLAY NAME are freely editable. This lets a user
# re-skin and re-arrange the interface without ever changing what a button does.
#
# Like ModProject / ScenarioProject this object holds ZERO UI: the editor scene
# (`ui/shared/gui_editor.gd`) is a thin view that drives it, while ALL authoring
# logic -- add / move / resize / set icon / rename / set background -- lives here
# so it is fully headless-testable.
#
# Serialised shape (a stable, deterministic JSON dictionary):
#
#   {
#     "id": "...",              # gui project id
#     "display_name_key": "..", # optional localization key for the whole GUI
#     "pages": {
#       "main": {
#         "background": { "kind": "color"|"image"|"video", "value": "..." },
#         "widgets": [
#           { "logical_id": "single", "rect": [x,y,w,h],
#             "icon_path": "", "display_name": "Single Player" },
#           ...
#         ]
#       },
#       ...
#     }
#   }
#
# Design rules (consistent with the rest of the project):
#   - PURE TOOLING: never touches WorldState or the deterministic sim hash. The
#     GUI is cosmetic; only the widget's logical_id (its function) matters to the
#     app, and that is validated against a catalog (MC7.3), never invented here.
#   - SAFE + VALIDATING: bad rects are clamped, blank/duplicate widgets rejected,
#     an unknown background kind falls back to a solid color. Saving an invalid
#     project is refused with a reason.
#   - DETERMINISTIC: pages and widgets serialise in a stable sorted order so the
#     same project always produces byte-identical JSON.
#   - English-only identifiers/comments (CODE_POLICY); author-facing text is a
#     plain display string the UI may pass through Localization if it is a key.
# ----------------------------------------------------------------------------
class_name GuiProject
extends RefCounted

# The file extension a standalone GUI project is exported under.
const GUI_EXTENSION: String = "nexgui"

# Background kinds a page may use. "color" is always safe; "image"/"video" carry
# a resource path the render layer resolves (with a fallback to color).
const BG_COLOR: String = "color"
const BG_IMAGE: String = "image"
const BG_VIDEO: String = "video"
const BG_KINDS: Array = [BG_COLOR, BG_IMAGE, BG_VIDEO]

# A safe default background (opaque dark) used when none is set or a bad kind is
# supplied. Stored as a hex string so JSON stays plain-text and deterministic.
const DEFAULT_BG_COLOR: String = "#101014"

# Video background limits (MC7.5): keep the asset small so it cannot stall a
# low-end device. The editor surfaces these; the model enforces them.
const MAX_VIDEO_SECONDS: int = 30
const MAX_VIDEO_MB: int = 16
const VIDEO_EXTENSION: String = "ogv"

# Rect clamping bounds. Widgets live in a virtual 1920x1080 design space; the
# render layer scales that to the real viewport. Keeping a fixed design space
# makes layouts deterministic and resolution-independent.
const DESIGN_WIDTH: int = 1920
const DESIGN_HEIGHT: int = 1080
const MIN_WIDGET_SIZE: int = 8

var _id: String = ""
var _display_name_key: String = ""
# pages: { page_name -> { "background": {...}, "widgets": [ {...}, ... ] } }
var _pages: Dictionary = {}


# --- Construction -----------------------------------------------------------

# Start a fresh, empty GUI project with the given id.
func init_new(id: String) -> void:
	_id = str(id).strip_edges()
	_display_name_key = ""
	_pages = {}


func get_id() -> String:
	return _id


func set_id(id: String) -> bool:
	var clean: String = str(id).strip_edges()
	if clean == "":
		return false
	_id = clean
	return true


func get_display_name_key() -> String:
	return _display_name_key


func set_display_name_key(key: String) -> void:
	_display_name_key = str(key).strip_edges()


# --- Pages ------------------------------------------------------------------

# Ensure a page exists (created empty with a default background if new). Returns
# false only for a blank page name.
func ensure_page(page: String) -> bool:
	var name: String = str(page).strip_edges()
	if name == "":
		return false
	if not _pages.has(name):
		_pages[name] = { "background": _default_background(), "widgets": [] }
	return true


func has_page(page: String) -> bool:
	return _pages.has(str(page).strip_edges())


# Stable, sorted list of page names (deterministic for UI + tests).
func page_names() -> Array:
	var names: Array = _pages.keys()
	names.sort()
	return names


# --- Widgets ----------------------------------------------------------------

# Add a widget to a page. `logical_id` must be non-blank and unique within the
# page (its function is fixed elsewhere by the widget catalog). The rect is
# clamped into the design space. Returns false if the page/id is bad or the id
# already exists on that page.
func add_widget(page: String, logical_id: String, rect: Array, icon_path: String = "", display_name: String = "") -> bool:
	var name: String = str(page).strip_edges()
	if not _pages.has(name):
		return false
	var lid: String = str(logical_id).strip_edges()
	if lid == "":
		return false
	var widgets: Array = _pages[name]["widgets"]
	for w in widgets:
		if str((w as Dictionary).get("logical_id", "")) == lid:
			return false  # duplicate function on the same page
	widgets.append({
		"logical_id": lid,
		"rect": clamp_rect(rect),
		"icon_path": str(icon_path).strip_edges(),
		"display_name": str(display_name),
	})
	return true


# Number of widgets on a page (0 for an unknown page).
func widget_count(page: String) -> int:
	var name: String = str(page).strip_edges()
	if not _pages.has(name):
		return 0
	return (_pages[name]["widgets"] as Array).size()


# Find a widget's index on a page by logical_id, or -1.
func _widget_index(page: String, logical_id: String) -> int:
	var name: String = str(page).strip_edges()
	if not _pages.has(name):
		return -1
	var widgets: Array = _pages[name]["widgets"]
	var lid: String = str(logical_id).strip_edges()
	for i in range(widgets.size()):
		if str((widgets[i] as Dictionary).get("logical_id", "")) == lid:
			return i
	return -1


# A defensive copy of one widget's dictionary, or {} if not found.
func get_widget(page: String, logical_id: String) -> Dictionary:
	var idx: int = _widget_index(page, logical_id)
	if idx < 0:
		return {}
	return (_pages[str(page).strip_edges()]["widgets"][idx] as Dictionary).duplicate(true)


# Move / resize a widget (the drag-to-move + resize editor operation). The rect
# is clamped into the design space. Returns false if the widget is not found.
func set_widget_rect(page: String, logical_id: String, rect: Array) -> bool:
	var idx: int = _widget_index(page, logical_id)
	if idx < 0:
		return false
	_pages[str(page).strip_edges()]["widgets"][idx]["rect"] = clamp_rect(rect)
	return true


# Set a widget's icon path (cosmetic). Blank clears it. Returns false if not found.
func set_widget_icon(page: String, logical_id: String, icon_path: String) -> bool:
	var idx: int = _widget_index(page, logical_id)
	if idx < 0:
		return false
	_pages[str(page).strip_edges()]["widgets"][idx]["icon_path"] = str(icon_path).strip_edges()
	return true


# Rename a widget's DISPLAY name only (never its logical_id / function). Returns
# false if not found.
func set_widget_display_name(page: String, logical_id: String, display_name: String) -> bool:
	var idx: int = _widget_index(page, logical_id)
	if idx < 0:
		return false
	_pages[str(page).strip_edges()]["widgets"][idx]["display_name"] = str(display_name)
	return true


# Remove a widget from a page. Returns false if not found.
func remove_widget(page: String, logical_id: String) -> bool:
	var idx: int = _widget_index(page, logical_id)
	if idx < 0:
		return false
	(_pages[str(page).strip_edges()]["widgets"] as Array).remove_at(idx)
	return true


# --- Background -------------------------------------------------------------

# Set a page's background. An unknown kind falls back to a solid color so the
# render layer always has something valid. For video the value is validated by
# validate_video_background (the editor calls that before this). Returns false
# for an unknown page.
func set_page_background(page: String, kind: String, value: String) -> bool:
	var name: String = str(page).strip_edges()
	if not _pages.has(name):
		return false
	var k: String = str(kind).strip_edges()
	if not BG_KINDS.has(k):
		_pages[name]["background"] = _default_background()
		return true
	_pages[name]["background"] = { "kind": k, "value": str(value).strip_edges() }
	return true


func get_page_background(page: String) -> Dictionary:
	var name: String = str(page).strip_edges()
	if not _pages.has(name):
		return {}
	return (_pages[name]["background"] as Dictionary).duplicate(true)


# --- Helpers ----------------------------------------------------------------

static func _default_background() -> Dictionary:
	return { "kind": BG_COLOR, "value": DEFAULT_BG_COLOR }


# Clamp an [x, y, w, h] rect into the design space with a minimum size. Bad /
# short input yields a safe default rect at the origin. Pure + deterministic.
static func clamp_rect(rect: Array) -> Array:
	if rect == null or rect.size() < 4:
		return [0, 0, MIN_WIDGET_SIZE, MIN_WIDGET_SIZE]
	var w: int = clampi(int(rect[2]), MIN_WIDGET_SIZE, DESIGN_WIDTH)
	var h: int = clampi(int(rect[3]), MIN_WIDGET_SIZE, DESIGN_HEIGHT)
	var x: int = clampi(int(rect[0]), 0, DESIGN_WIDTH - w)
	var y: int = clampi(int(rect[1]), 0, DESIGN_HEIGHT - h)
	return [x, y, w, h]


# Validate a proposed video background. Returns [ok: bool, reason_key: String].
# Enforces the .ogv extension and the size/duration budget (MC7.5). Duration is
# supplied by the caller (the editor probes the file); the model owns the rule.
static func validate_video_background(path: String, seconds: float, size_bytes: int) -> Array:
	var p: String = str(path).strip_edges()
	if p == "":
		return [false, "ui.guieditor.video_blank"]
	if not p.to_lower().ends_with("." + VIDEO_EXTENSION):
		return [false, "ui.guieditor.video_format"]
	if seconds > float(MAX_VIDEO_SECONDS):
		return [false, "ui.guieditor.video_too_long"]
	if size_bytes > MAX_VIDEO_MB * 1024 * 1024:
		return [false, "ui.guieditor.video_too_big"]
	return [true, ""]


# --- Serialisation ----------------------------------------------------------

# Whether the project is savable: a non-blank id and at least one page.
func is_valid() -> bool:
	return _id != "" and not _pages.is_empty()


# Produce the deterministic JSON dictionary (widgets sorted by logical_id,
# pages by name). Returns {} if the project is not valid.
func to_dict() -> Dictionary:
	if not is_valid():
		return {}
	var pages_out: Dictionary = {}
	for name in page_names():
		var page: Dictionary = _pages[name]
		var widgets_src: Array = (page["widgets"] as Array).duplicate(true)
		widgets_src.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["logical_id"]) < str(b["logical_id"]))
		pages_out[name] = {
			"background": (page["background"] as Dictionary).duplicate(true),
			"widgets": widgets_src,
		}
	return {
		"id": _id,
		"display_name_key": _display_name_key,
		"pages": pages_out,
	}


# Load from a dictionary produced by to_dict (or an external .nexgui file).
# Unknown / malformed entries are skipped rather than aborting so a partially
# corrupt file still opens with whatever is salvageable. Returns false only if
# there is no usable id.
func from_dict(data: Dictionary) -> bool:
	var id: String = str(data.get("id", "")).strip_edges()
	if id == "":
		return false
	init_new(id)
	_display_name_key = str(data.get("display_name_key", "")).strip_edges()
	var pages: Variant = data.get("pages", {})
	if pages is Dictionary:
		for name in (pages as Dictionary).keys():
			var page_name: String = str(name).strip_edges()
			if page_name == "" or not ((pages as Dictionary)[name] is Dictionary):
				continue
			ensure_page(page_name)
			var page: Dictionary = (pages as Dictionary)[name]
			var bg: Variant = page.get("background", null)
			if bg is Dictionary:
				set_page_background(page_name, str((bg as Dictionary).get("kind", BG_COLOR)), str((bg as Dictionary).get("value", DEFAULT_BG_COLOR)))
			var widgets: Variant = page.get("widgets", [])
			if widgets is Array:
				for w in (widgets as Array):
					if not (w is Dictionary):
						continue
					var wd: Dictionary = w
					add_widget(page_name, str(wd.get("logical_id", "")), wd.get("rect", []), str(wd.get("icon_path", "")), str(wd.get("display_name", "")))
	return true


# --- JSON round-trip (MC7.2) ------------------------------------------------
#
# `to_json` / `from_json` are the pure, headless-testable heart of save / export
# / import: a valid project serialises to a deterministic pretty-JSON STRING and
# reloads byte-for-byte identically. The file helpers below are thin IO wrappers
# so the round-trip logic stays testable without touching disk.

# Deterministic pretty JSON for this project, or "" if it is not valid. Because
# to_dict sorts pages + widgets, the same project always yields identical text.
func to_json() -> String:
	var data: Dictionary = to_dict()
	if data.is_empty():
		return ""
	return JSON.stringify(data, "\t")


# Rebuild this project from a JSON string produced by to_json (or an external
# .nexgui file). Returns false on malformed JSON or a missing id.
func from_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(str(text))
	if not (parsed is Dictionary):
		return false
	return from_dict(parsed as Dictionary)


# Save the project to `path` as pretty JSON. Refuses to write an invalid project
# (no id / no pages). Returns [ok: bool, reason_key: String].
func save_to_file(path: String) -> Array:
	if not is_valid():
		return [false, "ui.guieditor.save_invalid"]
	var text: String = to_json()
	if text == "":
		return [false, "ui.guieditor.save_invalid"]
	# Atomic write: never leave a half-written .nexgui replacing a good one.
	if not SafeFileUtil.write_text(str(path), text):
		return [false, "ui.guieditor.save_io"]
	return [true, ""]


# Load a project from a .nexgui file at `path`. Returns [ok: bool, reason_key].
func load_from_file(path: String) -> Array:
	var p: String = str(path)
	if not FileAccess.file_exists(p):
		return [false, "ui.guieditor.load_missing"]
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return [false, "ui.guieditor.load_io"]
	var text: String = f.get_as_text()
	f.close()
	if not from_json(text):
		return [false, "ui.guieditor.load_malformed"]
	return [true, ""]
