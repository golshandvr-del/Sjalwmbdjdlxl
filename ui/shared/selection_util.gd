# selection_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared selection helpers (Phase MA2).
#
# Pure, dependency-free helpers for pointer-based unit selection that are shared
# between the mobile and desktop HUDs. Keeping this logic OUT of the HUD scripts
# (which depend on the `Nexus` autoload) means it can be unit-tested headlessly
# without a running scene tree.
#
# Logic/Render Separation: nothing here mutates WorldState. Callers take the
# returned id list and push it through the authoritative `select_units` command.
# ----------------------------------------------------------------------------
class_name SelectionUtil
extends RefCounted


# Return the ids of every unit owned by `owner_filter` whose tile lies inside the
# screen-space rectangle defined by the two corner points `p1`/`p2` (any order).
#
# `adapter` must expose `screen_to_tile(Vector2) -> Vector2i` (RenderAdapter).
# `units` is the WorldState units list dictionary: id-string -> {id,x,y,owner}.
# Ids are returned sorted ascending so the resulting selection is deterministic
# (identical on every lockstep peer).
static func units_in_screen_rect(adapter: Object, units: Dictionary, p1: Vector2, p2: Vector2, owner_filter: int) -> Array:
	var out: Array = []
	if adapter == null:
		return out
	var tl: Vector2i = adapter.screen_to_tile(Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y)))
	var br: Vector2i = adapter.screen_to_tile(Vector2(maxf(p1.x, p2.x), maxf(p1.y, p2.y)))
	var min_x: int = mini(tl.x, br.x)
	var max_x: int = maxi(tl.x, br.x)
	var min_y: int = mini(tl.y, br.y)
	var max_y: int = maxi(tl.y, br.y)
	var keys: Array = units.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var u: Dictionary = units[key]
		if int(u.get("owner", -1)) != owner_filter:
			continue
		var ux: int = int(u["x"])
		var uy: int = int(u["y"])
		if ux >= min_x and ux <= max_x and uy >= min_y and uy <= max_y:
			out.append(int(u["id"]))
	return out
