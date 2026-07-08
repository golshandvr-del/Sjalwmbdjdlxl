# fog_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared fog-of-war query helpers (Phase MB1).
#
# Pure, dependency-free helpers that read a WorldState "fog" section and answer
# "is tile (x,y) currently VISIBLE / EXPLORED / HIDDEN to player P". Extracted so
# the minimap (and any other read-only overlay) can apply the SAME fog rule the
# main RenderAdapter uses, and so the rule can be unit-tested headlessly without
# a running scene tree.
#
# Logic/Render Separation: read-only. Never mutates WorldState.
# ----------------------------------------------------------------------------
class_name FogUtil
extends RefCounted

# Fog cell states (kept identical to RenderAdapter.FOG_*).
const FOG_HIDDEN: int = 0
const FOG_EXPLORED: int = 1
const FOG_VISIBLE: int = 2


# Return the fog state (FOG_HIDDEN / FOG_EXPLORED / FOG_VISIBLE) of tile (x,y)
# for `viewer`, reading the given fog section dictionary (WorldState "fog").
# Out-of-range or missing data is treated as HIDDEN.
static func fog_state(fog: Dictionary, viewer: int, x: int, y: int) -> int:
	var w: int = int(fog.get("width", 0))
	var h: int = int(fog.get("height", 0))
	if w <= 0 or x < 0 or y < 0 or x >= w or y >= h:
		return FOG_HIDDEN
	var grid: Array = fog.get("visible", {}).get(str(viewer), [])
	var idx: int = y * w + x
	if idx < 0 or idx >= grid.size():
		return FOG_HIDDEN
	return int(grid[idx])


# Should an object owned by `owner` sitting on tile (x,y) be DRAWN for `viewer`?
#
#   - viewer < 0            -> fog disabled, draw everything (true).
#   - owner == viewer       -> always draw our own things (true).
#   - otherwise (an enemy/other player) -> only draw when the tile is currently
#     VISIBLE to the viewer (not merely explored, and never when hidden).
#
# This matches RenderAdapter's rule for enemy units/buildings so the minimap can
# no longer leak enemy positions through the fog (bug 3).
static func should_draw(fog: Dictionary, viewer: int, owner: int, x: int, y: int) -> bool:
	if viewer < 0:
		return true
	if owner == viewer:
		return true
	return fog_state(fog, viewer, x, y) == FOG_VISIBLE
