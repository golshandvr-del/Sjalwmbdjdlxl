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


# GUI audit (BUG-G10): the left-edge TOOL STACK. The Move-mode toggle, its
# Confirm/Cancel pair and the Messages toggle were added in later phases with
# hard-coded BOTTOM_LEFT offsets and were never part of the responsive flow, so
# they landed ON TOP of the control-group panel / Select button (overlapping,
# unreadable, sometimes off-screen after rotation). This helper stacks any
# number of widgets upward from an anchor rect (the Select button), sharing its
# left edge, each clamped into the safe area. `sizes` is ordered bottom-to-top;
# the returned Array holds one position per entry in the same order.
static func stack_above(viewport: Vector2, anchor_pos: Vector2, sizes: Array, gap: float = 8.0) -> Array:
	var out: Array = []
	var next_bottom: float = anchor_pos.y - gap
	for raw in sizes:
		var widget_size: Vector2 = raw
		var desired: Vector2 = Vector2(anchor_pos.x, next_bottom - widget_size.y)
		var placed: Vector2 = clamp_into_safe_area(desired, widget_size, viewport)
		out.append(placed)
		next_bottom = placed.y - gap
	return out


# Widgets placed in a horizontal ROW to the right of `left_pos` (same top edge),
# each clamped into the safe area. Used for the Confirm / Cancel pair that sits
# beside the Move-mode toggle. `sizes` ordered left-to-right.
static func row_right_of(viewport: Vector2, left_pos: Vector2, left_size: Vector2, sizes: Array, gap: float = 8.0) -> Array:
	var out: Array = []
	var next_left: float = left_pos.x + left_size.x + gap
	for raw in sizes:
		var widget_size: Vector2 = raw
		var placed: Vector2 = clamp_into_safe_area(Vector2(next_left, left_pos.y), widget_size, viewport)
		out.append(placed)
		next_left = placed.x + widget_size.x + gap
	return out


# --- MB4.5: multi-column action-button flow (bug 16) ------------------------
#
# In PORTRAIT the action bar is a single horizontal row (wide + short screen,
# lots of horizontal room). In LANDSCAPE the usable width is spent on the world
# view, so a long single row of buttons overflows and needs scrolling; instead
# we let the buttons WRAP into a compact grid of several columns/rows that fits
# the shorter landscape height without pushing anything off-screen.
#
# These helpers are pure: given the orientation, the number of buttons and the
# per-button size they return how many COLUMNS the grid should use. The HUD (or
# any menu) then feeds that into a GridContainer / flow layout. Keeping the math
# here makes the "never overflow" rule unit-testable without a SceneTree.

# Smallest column count is 1; we never return 0 (avoids div-by-zero in callers).
const MIN_COLUMNS: int = 1

# How many action buttons can sit side by side within `available_width` given a
# per-button width plus a uniform `gap`. Always at least MIN_COLUMNS. This is the
# geometric cap; callers combine it with a desired count.
static func columns_that_fit(available_width: float, button_width: float, gap: float) -> int:
	if button_width <= 0.0:
		return MIN_COLUMNS
	# n buttons occupy n*button_width + (n-1)*gap. Solve for the largest n.
	var span: float = button_width + gap
	var n: int = int(floor((available_width + gap) / span))
	return maxi(MIN_COLUMNS, n)


# The number of columns the action grid should use for `count` buttons on this
# viewport. PORTRAIT keeps everything in a single row (one wide flow). LANDSCAPE
# wraps: it prefers the geometric fit but caps at ceil(count/rows) so the grid
# stays reasonably square rather than one very long row that scrolls. The bottom
# bar's usable width is the viewport minus the outer margins.
static func action_columns(viewport: Vector2, count: int, button_width: float, gap: float = 8.0) -> int:
	if count <= 0:
		return MIN_COLUMNS
	if not is_landscape(viewport):
		# Portrait: a single horizontal row (existing behaviour).
		return count
	var usable_w: float = maxf(0.0, viewport.x - 2.0 * MARGIN)
	var fit: int = columns_that_fit(usable_w, button_width, gap)
	# Never ask for more columns than buttons.
	return clampi(fit, MIN_COLUMNS, count)


# Given the chosen column count, how many ROWS the grid needs for `count` items.
static func grid_rows(count: int, columns: int) -> int:
	if columns <= 0 or count <= 0:
		return 0
	return int(ceil(float(count) / float(columns)))
