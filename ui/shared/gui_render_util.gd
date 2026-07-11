# gui_render_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Data-driven GUI layout resolver (Phase MC7.6, request 8).
#
# The GUI editor stores a cosmetic layout in a `GuiProject` (pages -> widgets in
# a virtual 1920x1080 DESIGN space). At runtime a menu/HUD scene must turn that
# authored layout into CONCRETE pixel rectangles for the current viewport, and
# fall back to the app's built-in layout when a page/widget is not authored.
#
# THIS UTIL IS PURE MATH: given an authored page dict, a viewport size, and a
# default layout, it returns a resolved list of placements the scene can apply.
# It touches no Control nodes, no WorldState, no autoload -- so it is fully
# headless-testable and can never affect the deterministic sim hash (the GUI is
# 100% cosmetic).
#
# Resolution rules:
#   - Each authored widget's design-space rect is scaled to the viewport using a
#     UNIFORM scale (min of x/y ratios) so aspect ratio is preserved, then the
#     scaled layout is centered (letterboxed) in the viewport.
#   - A widget with an unknown/blank logical_id is dropped (the catalog guards
#     this upstream; we are defensive here too).
#   - If the page has NO authored widgets, the caller's `default_widgets` are
#     returned unchanged (already viewport-space) -> nothing breaks pre-skin.
#
# English-only identifiers/comments (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name GuiRenderUtil
extends RefCounted

const DESIGN_WIDTH: int = 1920
const DESIGN_HEIGHT: int = 1080


# Uniform scale + centering offset to map DESIGN space into `viewport`.
# Returns { "scale": float, "offset_x": float, "offset_y": float }.
static func fit_transform(viewport_w: float, viewport_h: float) -> Dictionary:
	if viewport_w <= 0.0 or viewport_h <= 0.0:
		return { "scale": 1.0, "offset_x": 0.0, "offset_y": 0.0 }
	var sx: float = viewport_w / float(DESIGN_WIDTH)
	var sy: float = viewport_h / float(DESIGN_HEIGHT)
	var s: float = min(sx, sy)
	var used_w: float = float(DESIGN_WIDTH) * s
	var used_h: float = float(DESIGN_HEIGHT) * s
	return {
		"scale": s,
		"offset_x": (viewport_w - used_w) * 0.5,
		"offset_y": (viewport_h - used_h) * 0.5,
	}


# Map a single design-space rect [x,y,w,h] into viewport pixels using a
# transform from fit_transform. Returns [x, y, w, h] as floats.
static func resolve_rect(design_rect: Array, transform: Dictionary) -> Array:
	if design_rect == null or design_rect.size() < 4:
		return [0.0, 0.0, 0.0, 0.0]
	var s: float = float(transform.get("scale", 1.0))
	var ox: float = float(transform.get("offset_x", 0.0))
	var oy: float = float(transform.get("offset_y", 0.0))
	return [
		float(design_rect[0]) * s + ox,
		float(design_rect[1]) * s + oy,
		float(design_rect[2]) * s,
		float(design_rect[3]) * s,
	]


# Resolve a full authored page into viewport-space placements.
#
# `page_dict`   : a GuiProject page dict { "background":..., "widgets":[...] }
#                 (or {} / null when the page is not authored).
# `viewport`    : { "w": float, "h": float }.
# `default_widgets` : Array of already-viewport-space placements the app ships
#                 with; returned as-is when nothing is authored.
#
# Returns an Array of { "logical_id", "rect":[x,y,w,h], "icon_path",
# "display_name" } sorted by logical_id (deterministic).
static func resolve_page(page_dict: Variant, viewport: Dictionary, default_widgets: Array = []) -> Array:
	var vw: float = float(viewport.get("w", 0.0))
	var vh: float = float(viewport.get("h", 0.0))
	var widgets: Variant = null
	if page_dict is Dictionary:
		widgets = (page_dict as Dictionary).get("widgets", null)
	if not (widgets is Array) or (widgets as Array).is_empty():
		return default_widgets.duplicate(true)
	var transform: Dictionary = fit_transform(vw, vh)
	var out: Array = []
	for w in (widgets as Array):
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w
		var lid: String = str(wd.get("logical_id", "")).strip_edges()
		if lid == "":
			continue
		out.append({
			"logical_id": lid,
			"rect": resolve_rect(wd.get("rect", []), transform),
			"icon_path": str(wd.get("icon_path", "")),
			"display_name": str(wd.get("display_name", "")),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["logical_id"]) < str(b["logical_id"]))
	return out
