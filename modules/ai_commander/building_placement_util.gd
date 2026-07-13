# building_placement_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Building placement SELECTOR (Phase MD9, expert item 8, step
# MD9.4). The capstone that composes the three MD9 layers into ONE decision:
#
#   candidates (SiteTopologyUtil.candidate_tiles, MD9.3)
#     -> per-tile quality vector (SiteScoringUtil.score_site, MD9.2)
#        -> folded to a site_quality scalar (SiteScoringUtil.fold_quality)
#     -> building value x site quality (BuildingUtilityUtil.score_building, MD9.1)
#   argmax over the limited candidate set, STABLE tie-break by (x, y).
#
# The AI thus places a building at the tile that maximises
# (value-of-this-building-given-need) coupled to (quality-of-this-site), rather
# than the legacy "first empty tile near HQ". Backward compatibility (MD9.5) is
# preserved by the caller: if only the trivial candidate exists, that tile wins.
#
# Everything is q-scaled (SCALE = 1000) integer math over PLAIN dictionaries and
# a grid snapshot; nothing here touches the world model or the scene tree, so it
# is byte-identical on every peer -- placement issues Commands that mutate the
# lockstep sim, so it MUST be deterministic.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (pure ASCII).
# ----------------------------------------------------------------------------
class_name BuildingPlacementUtil
extends RefCounted


const SCALE: int = 1000

# When a building does not declare its own placement_fit, how strongly it cares
# about site quality by default (q). A neutral middle value.
const DEFAULT_PLACEMENT_FIT: int = 500


# Score a SINGLE (building, tile) pairing: fold the tile's quality vector, then
# feed it into BuildingUtilityUtil.score_building. Returns the integer utility.
#   caps           : building capability card (q), from DerivedMetricsUtil.
#   context        : MD7 context vector (q).
#   world          : plain map snapshot for SiteScoringUtil.score_site.
#   placement_fit  : how much this building weights site quality (q).
static func score_placement(
		caps: Dictionary,
		context: Dictionary,
		world: Dictionary,
		x: int,
		y: int,
		placement_fit: int) -> int:
	var quality: Dictionary = SiteScoringUtil.score_site(x, y, world, 0)
	var site_quality: int = SiteScoringUtil.fold_quality(quality)
	return BuildingUtilityUtil.score_building(caps, context, site_quality, placement_fit)


# Choose the best tile for a building over a LIMITED candidate list.
# `candidates` is an Array of Vector2i (e.g. SiteTopologyUtil.candidate_tiles).
# Returns { "x", "y", "score", "found" }; `found` is false (and x/y = -1) when
# there are no candidates, so the caller can fall back to legacy placement.
# Ties break by (x, y) ascending so every peer picks the identical tile.
static func select_site(
		caps: Dictionary,
		context: Dictionary,
		world: Dictionary,
		candidates: Array,
		placement_fit: int = DEFAULT_PLACEMENT_FIT) -> Dictionary:
	if candidates.is_empty():
		return { "x": -1, "y": -1, "score": 0, "found": false }
	# Iterate in a stable (x, y)-sorted order so the tie-break is deterministic.
	var sorted: Array = candidates.duplicate()
	sorted.sort_custom(func(a, b):
		var av: Vector2i = a as Vector2i
		var bv: Vector2i = b as Vector2i
		if av.x != bv.x:
			return av.x < bv.x
		return av.y < bv.y)
	var best_x: int = -1
	var best_y: int = -1
	var best_score: int = -2147483648
	for raw in sorted:
		var cell: Vector2i = raw as Vector2i
		var s: int = score_placement(caps, context, world, cell.x, cell.y, placement_fit)
		# Strictly-greater keeps the FIRST (lowest x,y) on a tie -> stable.
		if s > best_score:
			best_score = s
			best_x = cell.x
			best_y = cell.y
	return { "x": best_x, "y": best_y, "score": best_score, "found": true }


# Convenience: enumerate candidates from the world (MD9.3) and select in one
# call. `world` must carry the topology keys (width/height/tiles/hq/enemies/
# occupied) AND the scoring keys (resources/existing) -- SiteScoringUtil reads
# `enemies`/`existing`; SiteTopologyUtil reads `enemies`/`occupied`. The caller
# builds one merged snapshot. Returns the same shape as select_site.
static func plan_placement(
		caps: Dictionary,
		context: Dictionary,
		world: Dictionary,
		max_radius: int = 4,
		placement_fit: int = DEFAULT_PLACEMENT_FIT) -> Dictionary:
	var candidates: Array = SiteTopologyUtil.candidate_tiles(world, max_radius)
	return select_site(caps, context, world, candidates, placement_fit)
