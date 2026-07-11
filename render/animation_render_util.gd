# animation_render_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Cosmetic animation RENDER math util (Phase MC4, request 5,
# step MC4.3).
#
# AnimationEventUtil (MC4.1) decides WHAT to animate and for HOW LONG. This util
# decides HOW to DRAW a single animation event at a given moment: where the
# projectile is along its flight, which explosion frame is showing, and the fade
# alpha. It is the headless-testable "interface" the render layer (a thin
# Node2D) calls each _draw().
#
# When a mod supplies real sprite art (GraphicModel animation block) the render
# layer blits that texture; when it does not, this util drives a simple
# PROGRAMMATIC fallback (a moving dot for the projectile, an expanding fading
# ring for the explosion) so animation exists even with zero authored assets.
#
# COSMETIC / DETERMINISM: all math here is pure presentation. It reads only the
# animation event (already outside the hash) + elapsed time; it never feeds back
# into the simulation and never touches the deterministic state hash.
#
# Pure RefCounted, no SceneTree/autoload dependency -> unit-testable.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name AnimationRenderUtil
extends RefCounted


# Progress of an event in [0, 1], where 0 = just spawned and 1 = about to end.
# `remaining` counts DOWN from `total`, so progress = 1 - remaining/total.
static func progress(event: Dictionary, total_seconds: float) -> float:
	var total: float = max(0.0001, float(total_seconds))
	var rem: float = clampf(float(event.get("remaining", 0.0)), 0.0, total)
	return clampf(1.0 - rem / total, 0.0, 1.0)


# Interpolated projectile TILE position (as Vector2, sub-tile precision) at the
# given progress. Linear flight from `from` to `to`.
static func projectile_point(event: Dictionary, p: float) -> Vector2:
	var from_t: Vector2i = _as_tile(event.get("from", Vector2i.ZERO))
	var to_t: Vector2i = _as_tile(event.get("to", Vector2i.ZERO))
	var t: float = clampf(p, 0.0, 1.0)
	return Vector2(from_t).lerp(Vector2(to_t), t)


# Which frame of an explosion spritesheet to show at progress `p`. `frames` is
# the strip length (>=1). Result is clamped to [0, frames-1].
static func explosion_frame(p: float, frames: int) -> int:
	var n: int = maxi(1, frames)
	var idx: int = int(floor(clampf(p, 0.0, 1.0) * float(n)))
	return clampi(idx, 0, n - 1)


# Fade alpha for the programmatic fallback: full at the start, fading to 0 as the
# event ends (explosions and spent projectiles dissolve out).
static func fade_alpha(p: float) -> float:
	return clampf(1.0 - clampf(p, 0.0, 1.0), 0.0, 1.0)


# Programmatic explosion ring radius (in tile units) that expands with progress.
# Used only when no explosion spritesheet is authored.
static func explosion_radius(p: float, max_radius_tiles: float = 0.6) -> float:
	return clampf(p, 0.0, 1.0) * max(0.0, max_radius_tiles)


# Build a compact "draw plan" for one event: everything the thin Node2D needs to
# render it this frame, chosen by kind. Returns a Dictionary; the render layer
# switches on draw_plan.kind.
static func draw_plan(event: Dictionary, total_seconds: float, frames: int = 8) -> Dictionary:
	var kind: String = str(event.get("kind", ""))
	var p: float = progress(event, total_seconds)
	if kind == "projectile":
		return {
			"kind": "projectile",
			"point": projectile_point(event, p),
			"alpha": 1.0,
			"progress": p,
		}
	if kind == "explosion":
		return {
			"kind": "explosion",
			"point": Vector2(_as_tile(event.get("from", Vector2i.ZERO))),
			"frame": explosion_frame(p, frames),
			"radius": explosion_radius(p),
			"alpha": fade_alpha(p),
			"progress": p,
		}
	return { "kind": kind, "progress": p }


static func _as_tile(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i.ZERO
