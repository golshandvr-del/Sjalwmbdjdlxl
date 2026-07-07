# responsive_layout_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared responsive-HUD layout helper (Phase MA5).
#
# Pure, dependency-free geometry for placing the mobile HUD's floating overlay
# widgets (minimap, zoom column, control-group panel, select-mode button) so
# that the game is comfortably playable in BOTH portrait and landscape and no
# widget ever leaves the screen or overlaps the top / bottom action bars.
#
# Keeping this logic OUT of the HUD script (which depends on the `Nexus`
# autoload and a live SceneTree) lets it be unit-tested headlessly: the tests
# feed a viewport size + a widget size and assert the returned rectangle stays
# inside the safe area for every orientation and screen size.
#
# COORDINATE MODEL
#   Everything works in ABSOLUTE viewport pixels (top-left origin). The HUD
#   applies the returned top-left position directly (PRESET_TOP_LEFT anchor) so
#   there is a single, testable source of truth instead of a mix of anchor
#   presets + signed offsets that were easy to push off-screen (the MA5 bug).
#
# SAFE AREA
#   A rectangle inset from the viewport edges by MARGIN on all sides, and
#   additionally by the top-bar height at the top and the bottom-bar height at
#   the bottom, so floating widgets never sit under the resource/status bar or
#   the scrolling action bar.
#
# Logic/Render Separation: nothing here touches WorldState; it only computes
# cosmetic positions. Determinism is irrelevant (camera/scale/orientation are
# explicitly cosmetic per the MA plan) but the math is still pure + stable.
# ----------------------------------------------------------------------------
class_name ResponsiveLayoutUtil
extends RefCounted


# Uniform gap kept between any widget and the screen edge / a HUD bar.
const MARGIN: float = 16.0

# Conservative heights (in viewport px) reserved for the top and bottom bars so
# floating widgets are never placed under them. These are upper bounds of the
# scene's PanelContainers at 1.0 GUI scale; being generous keeps widgets clear
# even when the bars grow slightly with a larger GUI scale.
const TOP_BAR_H: float = 56.0
const BOTTOM_BAR_H: float = 96.0


# True when the viewport is at least as wide as it is tall.
static func is_landscape(viewport: Vector2) -> bool:
	return viewport.x >= viewport.y


# The usable rectangle (Rect2, absolute px) that excludes the outer margin and
# the top / bottom bars. All widget placements are clamped into this area.
static func safe_area(viewport: Vector2) -> Rect2:
	var left: float = MARGIN
	var top: float = TOP_BAR_H + MARGIN
	var right: float = viewport.x - MARGIN
	var bottom: float = viewport.y - BOTTOM_BAR_H - MARGIN
	# Degenerate guard: on a tiny/uninitialised viewport keep a non-negative box.
	if right < left:
		right = left
	if bottom < top:
		bottom = top
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


# Clamp a widget of `widget_size` so its whole rectangle fits inside the safe
# area. If the widget is larger than the safe area it is pinned to the top-left
# of the safe area (never pushed off-screen). Returns the top-left position.
static func clamp_into_safe_area(pos: Vector2, widget_size: Vector2, viewport: Vector2) -> Vector2:
	var area: Rect2 = safe_area(viewport)
	var max_x: float = area.position.x + maxf(0.0, area.size.x - widget_size.x)
	var max_y: float = area.position.y + maxf(0.0, area.size.y - widget_size.y)
	var x: float = clampf(pos.x, area.position.x, max_x)
	var y: float = clampf(pos.y, area.position.y, max_y)
	return Vector2(x, y)


# --- Per-widget target positions (top-left, absolute px) --------------------
#
# Each helper returns the DESIRED position for one widget given the viewport and
# that widget's measured size, already clamped into the safe area so the result
# is guaranteed on-screen. The HUD passes each widget's real size in so the math
# adapts to localisation / GUI-scale changes.

# Minimap: always hugs the top-right corner of the safe area (both orientations
# keep it out of the thumbs' way while staying glanceable).
static func minimap_pos(viewport: Vector2, widget_size: Vector2) -> Vector2:
	var area: Rect2 = safe_area(viewport)
	var desired: Vector2 = Vector2(area.position.x + area.size.x - widget_size.x, area.position.y)
	return clamp_into_safe_area(desired, widget_size, viewport)


# Zoom column: landscape -> right edge, vertically centred (right thumb).
# Portrait -> right edge, docked to the bottom of the safe area so it sits just
# above the bottom action bar.
static func zoom_col_pos(viewport: Vector2, widget_size: Vector2) -> Vector2:
	var area: Rect2 = safe_area(viewport)
	var x: float = area.position.x + area.size.x - widget_size.x
	var y: float
	if is_landscape(viewport):
		y = area.position.y + (area.size.y - widget_size.y) * 0.5
	else:
		y = area.position.y + area.size.y - widget_size.y
	return clamp_into_safe_area(Vector2(x, y), widget_size, viewport)


# Control-group panel: landscape -> left edge, vertically centred (left thumb).
# Portrait -> bottom-left of the safe area (above the bottom bar).
static func control_group_pos(viewport: Vector2, widget_size: Vector2) -> Vector2:
	var area: Rect2 = safe_area(viewport)
	var x: float = area.position.x
	var y: float
	if is_landscape(viewport):
		y = area.position.y + (area.size.y - widget_size.y) * 0.5
	else:
		y = area.position.y + area.size.y - widget_size.y
	return clamp_into_safe_area(Vector2(x, y), widget_size, viewport)


# Select-mode toggle: sits just ABOVE the control-group panel, sharing its left
# edge, in both orientations so it is always thumb-reachable. `group_pos` and
# `group_size` are the placed control-group panel's rect so the button tucks in
# directly above it; the result is still clamped into the safe area.
static func select_button_pos(viewport: Vector2, widget_size: Vector2, group_pos: Vector2, group_size: Vector2) -> Vector2:
	var gap: float = 8.0
	var x: float = group_pos.x
	var y: float = group_pos.y - widget_size.y - gap
	return clamp_into_safe_area(Vector2(x, y), widget_size, viewport)
