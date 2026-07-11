# animation_event_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Cosmetic animation event util (Phase MC4, request 5).
#
# The user asked for animation: a projectile flying when an object fires, and
# an explosion/smoke puff when a unit or building is destroyed.
#
# This util is the pure bridge between the DETERMINISTIC simulation events
# (combat.attack -> a shot was fired; units.died / buildings.destroyed -> an
# entity was destroyed) and the COSMETIC animation layer that draws them.
#
# COSMETIC / DETERMINISM: animation events are a pure RENDER concern. They are
# DERIVED from sim events but are NEVER fed back into the simulation and NEVER
# touch the deterministic state hash. Two peers may play different animations
# (they see different things through fog) without breaking lockstep, because
# these events only affect what is DRAWN, not what is simulated. This util
# therefore lives in render/, not modules/.
#
# It is a plain RefCounted with no SceneTree/autoload dependency so the mapping
# (sim event -> animation event) and lifetime bookkeeping are unit-testable
# headlessly. The render layer (MC4.3) owns the actual drawing; this util owns
# WHAT to draw and FOR HOW LONG.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name AnimationEventUtil
extends RefCounted

# Animation kinds produced by this util.
const ANIM_PROJECTILE: String = "projectile"
const ANIM_EXPLOSION: String = "explosion"

# Default cosmetic lifetimes (in seconds). The render layer may override these
# per-mod; they never affect the simulation.
const DEFAULT_PROJECTILE_SECONDS: float = 0.25
const DEFAULT_EXPLOSION_SECONDS: float = 0.5

# Sim event names this util understands (must match combat_module.gd).
const SIM_EVENT_ATTACK: String = "combat.attack"
const SIM_EVENT_UNIT_DIED: String = "units.died"
const SIM_EVENT_BUILDING_DESTROYED: String = "buildings.destroyed"

# Active animation events, each a Dictionary:
#   { kind, from (Vector2i or null), to (Vector2i or null), owner, remaining }
# from/to are TILE coordinates; the render layer maps them to pixels.
var _active: Array = []

# Monotonic id so the render layer can track individual animations if needed.
var _next_id: int = 0


# Build a projectile animation event from an attack. from_tile/to_tile are the
# attacker and target tile positions (looked up by the caller, which has the
# world state). Returns the created event Dictionary (also enqueued).
func spawn_projectile(from_tile: Vector2i, to_tile: Vector2i, owner: int, seconds: float = DEFAULT_PROJECTILE_SECONDS) -> Dictionary:
	var ev: Dictionary = {
		"id": _next_id,
		"kind": ANIM_PROJECTILE,
		"from": from_tile,
		"to": to_tile,
		"owner": int(owner),
		"remaining": max(0.0, float(seconds)),
	}
	_next_id += 1
	_active.append(ev)
	return ev


# Build an explosion/smoke animation event at a tile (unit or building death).
func spawn_explosion(at_tile: Vector2i, owner: int, seconds: float = DEFAULT_EXPLOSION_SECONDS) -> Dictionary:
	var ev: Dictionary = {
		"id": _next_id,
		"kind": ANIM_EXPLOSION,
		"from": at_tile,
		"to": at_tile,
		"owner": int(owner),
		"remaining": max(0.0, float(seconds)),
	}
	_next_id += 1
	_active.append(ev)
	return ev


# Translate a single sim event into an animation event, if applicable.
# tile_lookup is a Callable(int id) -> Vector2i that resolves an entity id to
# its current tile; it may be an invalid Callable if positions are supplied
# directly in the payload. Returns the created animation event, or an empty
# Dictionary if the sim event does not map to any animation.
func on_sim_event(event_name: String, payload: Dictionary, tile_lookup: Callable = Callable()) -> Dictionary:
	match event_name:
		SIM_EVENT_ATTACK:
			var from_t: Vector2i = _resolve_tile(payload, "attacker", "from", tile_lookup)
			var to_t: Vector2i = _resolve_tile(payload, "target", "to", tile_lookup)
			return spawn_projectile(from_t, to_t, int(payload.get("owner", 0)))
		SIM_EVENT_UNIT_DIED, SIM_EVENT_BUILDING_DESTROYED:
			var at_t: Vector2i = _resolve_tile(payload, "id", "at", tile_lookup)
			return spawn_explosion(at_t, int(payload.get("owner", 0)))
		_:
			return {}


# Advance all active animations by delta seconds and drop finished ones. Returns
# the number of animations that ended this step (purely informational).
func advance(delta: float) -> int:
	var d: float = max(0.0, float(delta))
	var ended: int = 0
	var kept: Array = []
	for ev in _active:
		var rem: float = float(ev.get("remaining", 0.0)) - d
		if rem <= 0.0:
			ended += 1
		else:
			ev["remaining"] = rem
			kept.append(ev)
	_active = kept
	return ended


# Snapshot of currently-active animation events (copies, safe to iterate/draw).
func active_events() -> Array:
	var out: Array = []
	for ev in _active:
		out.append(ev.duplicate(true))
	return out


func active_count() -> int:
	return _active.size()


func clear() -> void:
	_active.clear()


# Resolve a tile from the payload: prefer an explicit tile key ("from"/"to"/
# "at"), else resolve an id key ("attacker"/"target"/"id") via tile_lookup.
func _resolve_tile(payload: Dictionary, id_key: String, tile_key: String, tile_lookup: Callable) -> Vector2i:
	if payload.has(tile_key):
		var v = payload[tile_key]
		if v is Vector2i:
			return v
		if v is Vector2:
			return Vector2i(int(v.x), int(v.y))
		if v is Array and v.size() >= 2:
			return Vector2i(int(v[0]), int(v[1]))
	if payload.has(id_key) and tile_lookup.is_valid():
		var t = tile_lookup.call(int(payload[id_key]))
		if t is Vector2i:
			return t
		if t is Vector2:
			return Vector2i(int(t.x), int(t.y))
	return Vector2i.ZERO
