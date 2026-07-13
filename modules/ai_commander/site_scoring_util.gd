# site_scoring_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Site Scoring for AI building placement (Phase MD9, expert
# item 8, step MD9.2). Given a candidate tile on the map grid, produce a
# FIXED-POINT QUALITY VECTOR describing how good that tile is as a build site,
# from several independent angles. BuildingUtilityUtil (MD9.1) then couples the
# building's value to a single site_quality scalar folded from this vector.
#
# The quality vector keys (closed, versioned) are:
#   site_security         - how safe the tile is (far from enemies / near HQ)
#   frontline_value       - how "on the front" the tile is (between us and enemy)
#   resource_access       - how close resource nodes are
#   path_blocking         - how much building here obstructs an enemy path
#   choke_point_control   - how narrow / pinch-like the surrounding terrain is
#   coverage              - how much friendly ground the tile overlooks
#   vulnerability         - how exposed the tile is (INVERSE of security-ish)
#   synergy_with_existing - how well the tile complements our existing buildings
#
# Every value is q-scaled (SCALE = 1000) integer math over a PLAIN grid snapshot
# (flat Array of ints, index = y*width + x, 0 = walkable; matches PathService /
# MapModule) plus plain coordinate lists. Nothing here touches the world model
# or the scene tree, so it is byte-identical on every peer and headlessly
# testable -- placement issues Commands that mutate the lockstep sim, so it MUST
# be deterministic.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (pure ASCII).
# ----------------------------------------------------------------------------
class_name SiteScoringUtil
extends RefCounted


# Fixed-point scale shared with the whole v4 backbone.
const SCALE: int = 1000

# Walkable grid value (matches PathService.GROUND).
const GROUND: int = 0

# The CLOSED, VERSIONED site-quality keys, in stable (sorted) order so callers
# can iterate deterministically and tests can assert the full set.
const QUALITY_KEYS: Array = [
	"choke_point_control",
	"coverage",
	"frontline_value",
	"path_blocking",
	"resource_access",
	"site_security",
	"synergy_with_existing",
	"vulnerability",
]

# How the eight axes fold into ONE site_quality scalar. Positive axes help a
# generic (defensive) site; vulnerability is a penalty. Weights sum-normalised
# by the fold, so the scalar stays in roughly [0..SCALE].
const FOLD_WEIGHTS: Dictionary = {
	"site_security":         200,
	"frontline_value":       150,
	"resource_access":       100,
	"path_blocking":         150,
	"choke_point_control":   200,
	"coverage":              100,
	"synergy_with_existing": 100,
	"vulnerability":        -200,
}


# --- Fixed-point / geometry helpers -----------------------------------------

static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	var num: int = a * b
	var half: int = c / 2
	if num >= 0:
		return (num + half) / c
	return -((-num + half) / c)


static func _clamp_q(v: int) -> int:
	if v < 0:
		return 0
	if v > SCALE:
		return SCALE
	return v


static func _manhattan(ax: int, ay: int, bx: int, by: int) -> int:
	return abs(ax - bx) + abs(ay - by)


# Nearest Manhattan distance from (x,y) to any point in `points` (Array of
# {"x","y"} dictionaries). Returns -1 when the list is empty.
static func _nearest_dist(x: int, y: int, points: Array) -> int:
	var best: int = -1
	# Iterate in a stable order (sorted by x then y) for determinism.
	var sorted: Array = points.duplicate(true)
	sorted.sort_custom(func(a, b):
		var ax: int = int((a as Dictionary).get("x", 0))
		var bx: int = int((b as Dictionary).get("x", 0))
		if ax != bx:
			return ax < bx
		return int((a as Dictionary).get("y", 0)) < int((b as Dictionary).get("y", 0)))
	for p in sorted:
		var d: int = _manhattan(x, y, int((p as Dictionary).get("x", 0)), int((p as Dictionary).get("y", 0)))
		if best < 0 or d < best:
			best = d
	return best


# Map a distance to a "closeness" q value: 0 distance -> SCALE, >= `span` -> 0,
# linear in between. `span` is the distance at which the factor decays to 0.
static func _closeness_q(dist: int, span: int) -> int:
	if dist < 0:
		return 0
	if span <= 0:
		return 0
	if dist >= span:
		return 0
	return _clamp_q(SCALE - _mul_div_round(dist, SCALE, span))


static func _in_bounds(width: int, height: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


static func _is_ground(width: int, height: int, tiles: Array, x: int, y: int) -> bool:
	if not _in_bounds(width, height, x, y):
		return false
	var idx: int = y * width + x
	if idx < 0 or idx >= tiles.size():
		return false
	return int(tiles[idx]) == GROUND


# --- Individual quality axes -------------------------------------------------

# site_security: closeness to our HQ (safe rear). span scales with map size.
static func _site_security(x: int, y: int, hq: Dictionary, span: int) -> int:
	if hq.is_empty():
		return SCALE / 2
	var d: int = _manhattan(x, y, int(hq.get("x", x)), int(hq.get("y", y)))
	return _closeness_q(d, span)


# frontline_value: highest when the tile sits BETWEEN our HQ and the nearest
# enemy (roughly on the midline), i.e. its distance to HQ approaches its
# distance to the enemy front.
static func _frontline_value(x: int, y: int, hq: Dictionary, enemies: Array, span: int) -> int:
	if hq.is_empty() or enemies.is_empty():
		return 0
	var d_hq: int = _manhattan(x, y, int(hq.get("x", x)), int(hq.get("y", y)))
	var d_en: int = _nearest_dist(x, y, enemies)
	if d_en < 0:
		return 0
	var total: int = d_hq + d_en
	if total <= 0:
		return 0
	# Symmetry factor: 1 at the exact midpoint (d_hq == d_en), 0 at either end.
	var diff: int = abs(d_hq - d_en)
	var sym: int = _clamp_q(SCALE - _mul_div_round(diff, SCALE, total))
	# Dampen sites that are absurdly far from both (span guard via HQ closeness).
	var reach: int = _closeness_q(d_hq, span * 2)
	return _mul_div_round(sym, reach, SCALE)


# resource_access: closeness to the nearest resource node.
static func _resource_access(x: int, y: int, resources: Array, span: int) -> int:
	if resources.is_empty():
		return 0
	return _closeness_q(_nearest_dist(x, y, resources), span)


# path_blocking + choke_point_control both read the local walkability around the
# tile. A tile whose 4-neighbourhood has few open ground cells sits in a pinch;
# building there blocks movement / controls a choke.
static func _open_neighbours(width: int, height: int, tiles: Array, x: int, y: int) -> int:
	var open: int = 0
	if _is_ground(width, height, tiles, x, y - 1):
		open += 1
	if _is_ground(width, height, tiles, x + 1, y):
		open += 1
	if _is_ground(width, height, tiles, x, y + 1):
		open += 1
	if _is_ground(width, height, tiles, x - 1, y):
		open += 1
	return open


# choke_point_control: 4 open neighbours -> open field -> 0; 2 open (a corridor)
# -> strong choke -> high; 0/1 -> dead-end, still pinch-like.
static func _choke_control(width: int, height: int, tiles: Array, x: int, y: int) -> int:
	if not _is_ground(width, height, tiles, x, y):
		return 0
	var open: int = _open_neighbours(width, height, tiles, x, y)
	# Map open-count (0..4) to a choke q: fewer openings == tighter choke.
	# 4 -> 0, 3 -> 250, 2 -> 750, 1 -> 500, 0 -> 250 (isolated, less useful).
	match open:
		4:
			return 0
		3:
			return 250
		2:
			return 750
		1:
			return 500
		_:
			return 250


# path_blocking: how much a wall here would obstruct traffic. Approximated by
# the choke tightness folded with whether both opposing sides are open (a real
# corridor to block).
static func _path_blocking(width: int, height: int, tiles: Array, x: int, y: int) -> int:
	if not _is_ground(width, height, tiles, x, y):
		return 0
	var up: bool = _is_ground(width, height, tiles, x, y - 1)
	var down: bool = _is_ground(width, height, tiles, x, y + 1)
	var left: bool = _is_ground(width, height, tiles, x - 1, y)
	var right: bool = _is_ground(width, height, tiles, x + 1, y)
	# A vertical corridor (up+down open, left+right blocked) or a horizontal one
	# is the ideal place to block a path.
	if (up and down and not left and not right) or (left and right and not up and not down):
		return SCALE
	# Partial corridor still blocks somewhat.
	var open: int = _open_neighbours(width, height, tiles, x, y)
	if open == 2:
		return SCALE / 2
	return 0


# coverage: how much friendly ground the tile overlooks -- approximated by the
# fraction of ground tiles within a small radius (a tile with open surroundings
# covers more area). Complementary to choke.
static func _coverage(width: int, height: int, tiles: Array, x: int, y: int, radius: int) -> int:
	if radius <= 0:
		return 0
	var ground: int = 0
	var total: int = 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			total += 1
			if _is_ground(width, height, tiles, x + dx, y + dy):
				ground += 1
	if total <= 0:
		return 0
	return _mul_div_round(ground, SCALE, total)


# vulnerability: how exposed the tile is to the enemy -- closeness to the
# nearest enemy (the inverse of the rear-safety idea).
static func _vulnerability(x: int, y: int, enemies: Array, span: int) -> int:
	if enemies.is_empty():
		return 0
	return _closeness_q(_nearest_dist(x, y, enemies), span)


# synergy_with_existing: a mild bonus for sitting NEAR (but not on top of) our
# existing buildings, so the base grows as a connected cluster rather than
# scattered. Peaks at distance 2, decays past `span`.
static func _synergy(x: int, y: int, existing: Array, span: int) -> int:
	if existing.is_empty():
		return 0
	var d: int = _nearest_dist(x, y, existing)
	if d <= 0:
		# On top of an existing building -> no synergy (and unbuildable anyway).
		return 0
	# Ideal spacing is small; use closeness but cap the on-top case above.
	return _closeness_q(d, span)


# --- Public API --------------------------------------------------------------

# Compute the full quality vector for tile (x,y). `world` bundles the plain map
# snapshot and coordinate lists:
#   { "width", "height", "tiles": Array[int],
#     "hq": {"x","y"} | {},
#     "enemies": Array[{"x","y"}], "resources": Array[{"x","y"}],
#     "existing": Array[{"x","y"}] }
# All missing keys degrade to safe defaults; the full closed key set is always
# returned. `span` scales distance-based axes (defaults to a map-derived span).
static func score_site(x: int, y: int, world: Dictionary, span: int = 0) -> Dictionary:
	var width: int = int(world.get("width", 0))
	var height: int = int(world.get("height", 0))
	var tiles: Array = (world.get("tiles", []) as Array)
	var hq: Dictionary = (world.get("hq", {}) as Dictionary)
	var enemies: Array = (world.get("enemies", []) as Array)
	var resources: Array = (world.get("resources", []) as Array)
	var existing: Array = (world.get("existing", []) as Array)
	if span <= 0:
		# Half the map diagonal (Manhattan) is a reasonable default reach.
		span = maxi(1, (width + height) / 2)

	var q: Dictionary = {
		"site_security":         _site_security(x, y, hq, span),
		"frontline_value":       _frontline_value(x, y, hq, enemies, span),
		"resource_access":       _resource_access(x, y, resources, span),
		"path_blocking":         _path_blocking(width, height, tiles, x, y),
		"choke_point_control":   _choke_control(width, height, tiles, x, y),
		"coverage":              _coverage(width, height, tiles, x, y, 2),
		"vulnerability":         _vulnerability(x, y, enemies, span),
		"synergy_with_existing": _synergy(x, y, existing, span),
	}
	return q


# Fold a quality vector into ONE site_quality scalar in [0..SCALE] using
# FOLD_WEIGHTS. Deterministic; clamps the result to the valid q range so a
# vulnerability-heavy tile never drives it negative.
static func fold_quality(quality: Dictionary) -> int:
	var num: int = 0
	var wsum: int = 0
	# Iterate the closed key set in sorted order for a stable fold.
	for key in QUALITY_KEYS:
		var w: int = int(FOLD_WEIGHTS.get(key, 0))
		var v: int = int(quality.get(key, 0))
		num += w * v
		wsum += abs(w)
	if wsum <= 0:
		return 0
	return _clamp_q(_mul_div_round(num, 1, wsum))
