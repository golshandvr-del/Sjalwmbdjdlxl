# state_hasher.gd
# ----------------------------------------------------------------------------
# Project Nexus - State Hasher (core component, Phase 3).
#
# Produces a STABLE, ORDER-INDEPENDENT-OF-DICTIONARY-INSERTION checksum of the
# WorldState. This is the cornerstone of lockstep multiplayer: each peer runs
# the exact same deterministic simulation, so after every tick (or every Nth
# tick) their world hashes MUST match. If two peers ever disagree, that is a
# "desync" and the netcode can detect it immediately instead of silently
# drifting.
#
# Why a dedicated hasher rather than JSON.stringify?
#   - Godot Dictionaries do not guarantee key order across runs/platforms, so a
#     naive stringify is NOT a reliable cross-machine checksum. Here we walk the
#     structure and SORT keys at every level, so the same logical state always
#     hashes identically regardless of insertion order.
#   - It is cheap and allocation-light compared to building a giant string.
#
# Determinism notes:
#   - Dictionary keys are sorted (as strings) before hashing.
#   - Arrays preserve order (order is meaningful in game data, e.g. paths).
#   - Floats are quantized to a fixed number of decimals before hashing so that
#     platform float printing differences cannot cause false desyncs. (The sim
#     is integer-based, but this guards any incidental float that creeps in.)
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name StateHasher
extends RefCounted

# FNV-1a 64-bit constants (a fast, well-distributed, fully deterministic hash).
const _FNV_OFFSET: int = -3750763034362895579  # 0xcbf29ce484222325 as signed 64-bit
const _FNV_PRIME: int = 1099511628211           # 0x100000001b3

# Decimals to quantize floats to before hashing.
const _FLOAT_DECIMALS: int = 6

# Sections that are LOCAL / per-peer metadata rather than shared simulation
# state. They legitimately differ between peers (e.g. each machine stores its
# OWN local_peer id and turn bookkeeping in "lockstep") so they MUST be excluded
# from the lockstep sync checksum -- otherwise two perfectly-synced peers would
# falsely report a desync. Gameplay state (units, buildings, economy, tech, map,
# ...) is fully shared and so is always hashed.
const _LOCAL_SECTIONS: Array = ["lockstep", "local_selection"]


# Hash an entire WorldState into a stable 64-bit integer.
#
# By default LOCAL/per-peer sections (see _LOCAL_SECTIONS) are EXCLUDED so the
# result is a true cross-peer "simulation checksum". Pass include_local = true
# to hash absolutely everything (useful for single-machine save/replay checks).
static func hash_world(world: WorldState, include_local: bool = false) -> int:
	var h: int = _FNV_OFFSET
	h = _mix_int(h, world.current_tick)
	h = _mix_int(h, world.random_seed)
	# Hash sections in sorted name order so section insertion order is irrelevant.
	var names: Array = world.get_all_section_names()
	names.sort()
	for name in names:
		if not include_local and _LOCAL_SECTIONS.has(str(name)):
			continue
		h = _mix_string(h, str(name))
		h = _hash_value(h, world.get_section(str(name)))
	return h


# Convenience: a short hex-ish string form of the world hash (for logs / events).
static func hash_world_string(world: WorldState, include_local: bool = false) -> String:
	return _to_hex(hash_world(world, include_local))


# Hash ANY serializable Variant (Dictionary / Array / scalar) into a stable
# 64-bit integer using the same order-independent recursive rules as the world
# hash. This is the public entry point used by P5 mod-sync (R7): both host and
# join compute a hash of their ACTIVE MOD CATALOG (the sorted set of catalog
# entry ids + definitions); if the two hashes differ, the host ships its
# `.nexpack` to the join before the match starts, keeping the deterministic core
# lockstep-safe (identical catalogs on every machine).
static func hash_variant(value: Variant) -> int:
	return _hash_value(_FNV_OFFSET, value)


# Short hex-ish string form of hash_variant (for the lobby's "mod fingerprint").
static func hash_variant_string(value: Variant) -> String:
	return _to_hex(hash_variant(value))


# --- Recursive structural hashing -------------------------------------------

static func _hash_value(h: int, value: Variant) -> int:
	if value is Dictionary:
		var d: Dictionary = value
		var keys: Array = d.keys()
		# Sort keys by their string form for insertion-order independence.
		keys.sort_custom(func(a, b): return str(a) < str(b))
		h = _mix_string(h, "{")
		for k in keys:
			h = _mix_string(h, str(k))
			h = _mix_string(h, ":")
			h = _hash_value(h, d[k])
		h = _mix_string(h, "}")
		return h
	elif value is Array:
		var arr: Array = value
		h = _mix_string(h, "[")
		for item in arr:
			h = _hash_value(h, item)
			h = _mix_string(h, ",")
		h = _mix_string(h, "]")
		return h
	elif value is bool:
		return _mix_int(h, 1 if value else 0)
	elif value is int:
		return _mix_int(h, int(value))
	elif value is float:
		# An integral float (e.g. 3.0) hashes exactly like the int 3, because a JSON
		# save round-trip turns every int into a float (JSON has one number type).
		var f: float = float(value)
		if f == floorf(f) and absf(f) < 9007199254740992.0:
			return _mix_int(h, int(f))
		# Quantize to fixed decimals, then hash the integer representation.
		var scaled: int = int(round(float(value) * pow(10.0, _FLOAT_DECIMALS)))
		return _mix_int(h, scaled)
	elif value is String:
		return _mix_string(h, str(value))
	elif value is Vector2i:
		h = _mix_int(h, (value as Vector2i).x)
		return _mix_int(h, (value as Vector2i).y)
	elif value == null:
		return _mix_string(h, "null")
	# Fallback: stringify anything exotic deterministically.
	return _mix_string(h, str(value))


# --- FNV-1a mixing primitives -----------------------------------------------

static func _mix_int(h: int, v: int) -> int:
	# Fold the 64-bit integer in 8 bytes, FNV-1a style.
	var x: int = v
	for _i in range(8):
		var byte: int = x & 0xff
		h = (h ^ byte) * _FNV_PRIME
		# Keep it inside 64 bits (GDScript ints are 64-bit; the multiply wraps).
		x = x >> 8
	return h


static func _mix_string(h: int, s: String) -> int:
	var bytes: PackedByteArray = s.to_utf8_buffer()
	for b in bytes:
		h = (h ^ int(b)) * _FNV_PRIME
	return h


# Render a (possibly negative, 64-bit) hash as a fixed-width hex string.
static func _to_hex(value: int) -> String:
	# Mask to 16 hex nibbles by formatting the two 32-bit halves.
	var high: int = (value >> 32) & 0xffffffff
	var low: int = value & 0xffffffff
	return "%08x%08x" % [high, low]
