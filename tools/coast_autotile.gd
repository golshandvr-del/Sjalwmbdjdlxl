# coast_autotile.gd
# ----------------------------------------------------------------------------
# Project Nexus - Coastline auto-tiling (Phase E6, step E6.5).
#
# RENDER-ONLY helper. The map's LOGICAL data only ever knows three tokens:
# `land`, `sea`, `wall`. There is NO stored "beach"/"coast" tile -- a coast is a
# purely cosmetic edge drawn where land meets sea. This module computes a 4-bit
# (or 8-bit) bitmask from a cell's neighbours so a renderer can pick the right
# coast sprite, WITHOUT touching the deterministic simulation (golden rule #1,
# risk R5 of docs/Nexus_ModEditor_Plan_fa.md).
#
# Because it is render-only, nothing here is allowed to feed back into
# WorldState or the sim hash; it is a pure function of the terrain query.
#
# Design rules: PURE, deterministic, English-only (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name CoastAutotile
extends RefCounted

# 4-direction bit weights (orthogonal neighbours that are sea).
const BIT_N: int = 1
const BIT_E: int = 2
const BIT_S: int = 4
const BIT_W: int = 8

# Diagonal bits (used only by the 8-bit variant for inner corners).
const BIT_NE: int = 16
const BIT_SE: int = 32
const BIT_SW: int = 64
const BIT_NW: int = 128


# `is_sea` is a Callable taking (x, y) -> bool. For a LAND cell, returns the
# 4-bit mask of orthogonal directions that face the sea. A land cell fully
# surrounded by land returns 0 (no coast drawn). Out-of-bounds neighbours are
# treated as sea by default so the map edge gets a shoreline; pass
# `edge_is_sea=false` to treat the border as land instead.
static func mask4(x: int, y: int, is_sea: Callable, edge_is_sea: bool = true, width: int = -1, height: int = -1) -> int:
	# A sea (or out-of-range-as-sea) cell itself is not a coast tile.
	if _sea_at(x, y, is_sea, edge_is_sea, width, height):
		return 0
	var m: int = 0
	if _sea_at(x, y - 1, is_sea, edge_is_sea, width, height):
		m |= BIT_N
	if _sea_at(x + 1, y, is_sea, edge_is_sea, width, height):
		m |= BIT_E
	if _sea_at(x, y + 1, is_sea, edge_is_sea, width, height):
		m |= BIT_S
	if _sea_at(x - 1, y, is_sea, edge_is_sea, width, height):
		m |= BIT_W
	return m


# Full 8-bit mask (orthogonal + diagonal). Diagonals are only set when BOTH of
# their flanking orthogonals are land (a true inner corner), which is the usual
# blob-autotile convention.
static func mask8(x: int, y: int, is_sea: Callable, edge_is_sea: bool = true, width: int = -1, height: int = -1) -> int:
	var m: int = mask4(x, y, is_sea, edge_is_sea, width, height)
	if m == 0 and _sea_at(x, y, is_sea, edge_is_sea, width, height):
		return 0
	var north_land: bool = (m & BIT_N) == 0
	var east_land: bool = (m & BIT_E) == 0
	var south_land: bool = (m & BIT_S) == 0
	var west_land: bool = (m & BIT_W) == 0
	if north_land and east_land and _sea_at(x + 1, y - 1, is_sea, edge_is_sea, width, height):
		m |= BIT_NE
	if south_land and east_land and _sea_at(x + 1, y + 1, is_sea, edge_is_sea, width, height):
		m |= BIT_SE
	if south_land and west_land and _sea_at(x - 1, y + 1, is_sea, edge_is_sea, width, height):
		m |= BIT_SW
	if north_land and west_land and _sea_at(x - 1, y - 1, is_sea, edge_is_sea, width, height):
		m |= BIT_NW
	return m


# True if a land cell touches the sea on any orthogonal side (i.e. it is a coast).
static func is_coast(x: int, y: int, is_sea: Callable, edge_is_sea: bool = true, width: int = -1, height: int = -1) -> bool:
	return mask4(x, y, is_sea, edge_is_sea, width, height) != 0


static func _sea_at(x: int, y: int, is_sea: Callable, edge_is_sea: bool, width: int, height: int) -> bool:
	if width >= 0 and height >= 0:
		if x < 0 or y < 0 or x >= width or y >= height:
			return edge_is_sea
	return bool(is_sea.call(x, y))
