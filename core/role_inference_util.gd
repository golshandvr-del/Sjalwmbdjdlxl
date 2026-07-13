# role_inference_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Role Inference: Capability vector -> Role(s) (plan v4, MD4).
#
# This is the fourth link of the data-driven backbone described in
# docs/plan_android_fix_v4.md:
#
#   raw stats --(affects)--> Capability vector (DerivedMetricsUtil)
#       --(role signatures, HERE)--> one or more ROLES
#           (frontline_tank, glass_cannon, ranged_dps, siege_unit, scout,
#            support, anti_air, harasser, economy_unit, control_unit;
#            for buildings: defensive, production, economic, tech, frontline)
#
# The AI's decision logic (MD5+) reasons about ROLES and CAPABILITIES, never
# about a raw stat and never about a unit NAME. The JSON `category` field
# (infantry/armor/...) stays a purely cosmetic display label (plan MD4 note);
# the decision-making role is DERIVED here from the capability vector, so a
# brand-new modded unit gets a meaningful role with ZERO engine code.
#
# Design rules (Definition of Done, plan section 2 + "اصولِ ثابت"):
#   - PURE INFRASTRUCTURE: RefCounted, no SceneTree / WorldState / sim-hash
#     dependency. Headlessly unit-testable. Plain dictionaries in, plain
#     arrays/strings out.
#   - FIXED-POINT DETERMINISM (section 2.1 golden rule): every score is an int
#     in units of SCALE (1.0 == 1000). No float enters a score. Roles are
#     sorted by (score DESC, role_id ASC) so the ordering is byte-for-byte
#     identical on any CPU; primary_role ties break ALPHABETICALLY (stable).
#   - RESILIENCE (section 2.5): an empty/incomplete/all-default vector never
#     leaves without a role -- it yields the `generic` role with a base score.
#     No input can crash it and no input can produce an empty role list.
#   - COSMETIC vs SIMULATION (section 2.2): a role may feed a deterministic
#     Command decision (so it MUST be deterministic, which it is) but this util
#     never writes WorldState and never touches state_hasher.
#   - English-only identifiers/comments (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name RoleInferenceUtil
extends RefCounted

# Fixed-point scale (section 2.1). Mirrors CapabilityRegistry.SCALE. Capability
# q values arriving here are already in [0..SCALE]; role scores are too.
const SCALE: int = 1000

# The fallback role every entity is guaranteed to receive when no signature
# scores above the floor (empty / all-default / malformed vector). Section 2.5.
const GENERIC_ROLE: String = "generic"

# The base score the generic fallback carries so it is a real, comparable role
# (below any meaningfully-matched signature but above nothing).
const GENERIC_BASE_Q: int = 1

# --- Role signatures ---------------------------------------------------------
#
# A signature is a weighted profile over capability ids. Each entry is a
# fixed-point weight in units of SCALE:
#   positive weight -> this capability SHOULD be high for the role,
#   negative weight -> this capability SHOULD be low (a glass cannon is
#                      penalised for high survivability, etc).
# The role score is the weighted dot product of the capability vector with the
# signature, normalised by the sum of the POSITIVE weights so every role's raw
# score lands in a comparable [~0..SCALE] band regardless of how many terms it
# has. All integer math -> deterministic.
#
# Unit signatures (applies to entities whose vector carries unit capabilities).
const UNIT_SIGNATURES: Dictionary = {
	"frontline_tank": { "survivability": 1000, "holding_power": 700, "mobility": -200 },
	"glass_cannon":   { "damage_output": 1000, "survivability": -500 },
	"ranged_dps":     { "damage_output": 900, "anti_air_power": 200, "mobility": 200 },
	"siege_unit":     { "siege_power": 1000, "mobility": -200 },
	"scout":          { "scout_power": 1000, "mobility": 600, "survivability": -300 },
	"support":        { "support_power": 1000, "damage_output": -200 },
	"anti_air":       { "anti_air_power": 1000, "damage_output": 200 },
	"harasser":       { "mobility": 900, "damage_output": 500, "survivability": -300 },
	"economy_unit":   { "resource_pressure": 1000, "damage_output": -300 },
	"control_unit":   { "control_value": 1000, "support_power": 300 },
}

# Building signatures (applies to entities whose vector carries building
# capabilities). A building's category role set is separate from a unit's.
const BUILDING_SIGNATURES: Dictionary = {
	"defensive":  { "defense_value": 1000, "frontline_value": 300 },
	"production": { "production_value": 1000 },
	"economic":   { "economic_value": 1000, "resource_pressure": 400 },
	"tech":       { "tech_value": 1000 },
	"frontline":  { "frontline_value": 1000, "defense_value": 400 },
}

# A role must reach at least this normalised score to be reported as a real
# role (below it the entity is too weak in that dimension to count). The
# generic fallback fills in when NOTHING clears this floor.
const ROLE_FLOOR_Q: int = 100

# --- Public API -------------------------------------------------------------

# Infer the ranked role list from a capability vector.
#
# `capabilities` : { capability_id: q in [0..SCALE] } (from
#                  DerivedMetricsUtil.compute_capabilities). May be
#                  null/empty/partial.
# `target`       : "unit" | "building" | "auto" (default). "auto" picks the
#                  signature table by which capabilities carry signal, so a
#                  caller that does not know the entity kind still works.
#
# Returns an Array of { "role": String, "score_q": int } sorted by
# (score_q DESC, role ASC). NEVER empty: an entity with no clearing role gets
# [ { "role": "generic", "score_q": GENERIC_BASE_Q } ].
static func infer_roles(capabilities: Variant, target: String = "auto") -> Array:
	var caps: Dictionary = _caps_of(capabilities)
	var signatures: Dictionary = _signatures_for(caps, target)

	var scored: Array = []
	var role_ids: Array = signatures.keys()
	role_ids.sort()  # deterministic iteration
	for role_id in role_ids:
		var sig: Dictionary = signatures[role_id] as Dictionary
		var score: int = _score_signature(caps, sig)
		if score >= ROLE_FLOOR_Q:
			scored.append({ "role": str(role_id), "score_q": score })

	if scored.is_empty():
		# Resilience (section 2.5): no signature cleared the floor -> generic.
		return [ { "role": GENERIC_ROLE, "score_q": GENERIC_BASE_Q } ]

	# Sort by score DESC, then role id ASC (stable, deterministic tie-break).
	scored.sort_custom(Callable(RoleInferenceUtil, "_role_sort"))
	return scored


# The single PRIMARY role: the highest-scoring role, ties broken
# ALPHABETICALLY (plan MD4.2) so the choice is deterministic. Returns
# GENERIC_ROLE for an empty/incomplete vector. Never returns "".
static func primary_role(capabilities: Variant, target: String = "auto") -> String:
	var roles: Array = infer_roles(capabilities, target)
	# infer_roles already sorted by (score DESC, role ASC), so the first entry
	# is the highest score with the alphabetically-first role on a tie.
	return str((roles[0] as Dictionary).get("role", GENERIC_ROLE))


# --- Internals ---------------------------------------------------------------

# Comparator: score_q DESC, then role id ASC. Pure integer/string compare.
static func _role_sort(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = int(a.get("score_q", 0))
	var sb: int = int(b.get("score_q", 0))
	if sa != sb:
		return sa > sb
	return str(a.get("role", "")) < str(b.get("role", ""))


# The weighted, normalised score of one signature against the vector. Sum of
# (capability_q * weight) over the signature, divided by the sum of POSITIVE
# weights so the result is a comparable normalised band. Negative weights
# subtract (penalise) but do NOT inflate the normaliser. Clamped to [0..SCALE].
static func _score_signature(caps: Dictionary, sig: Dictionary) -> int:
	var acc: int = 0
	var pos_weight: int = 0
	var cap_ids: Array = sig.keys()
	cap_ids.sort()  # deterministic accumulation order
	for cap_id in cap_ids:
		var w: int = int(sig[cap_id])
		var q: int = int(caps.get(cap_id, 0))
		# term = q * w / SCALE  (both q and w are in SCALE units).
		acc += _mul_div_round(q, w, SCALE)
		if w > 0:
			pos_weight += w
	if pos_weight <= 0:
		return 0
	# Normalise by positive weight mass so a 3-term and a 1-term role compare.
	var score: int = _mul_div_round(acc, SCALE, pos_weight)
	return _clamp_q(score)


# Pick the signature table. "unit"/"building" force it; "auto" chooses by which
# capability family carries the most signal in the vector (falls back to unit).
static func _signatures_for(caps: Dictionary, target: String) -> Dictionary:
	if target == "unit":
		return UNIT_SIGNATURES
	if target == "building":
		return BUILDING_SIGNATURES
	# auto: sum the building-only capabilities vs the unit-only capabilities.
	var building_signal: int = 0
	for id in ["defense_value", "production_value", "tech_value", "economic_value", "frontline_value", "repair_value"]:
		building_signal += int(caps.get(id, 0))
	var unit_signal: int = 0
	for id in ["survivability", "damage_output", "mobility", "holding_power", "siege_power", "scout_power", "support_power", "anti_air_power"]:
		unit_signal += int(caps.get(id, 0))
	if building_signal > unit_signal:
		return BUILDING_SIGNATURES
	return UNIT_SIGNATURES


# Coerce the incoming capabilities argument to a Dictionary (empty if absent).
static func _caps_of(capabilities: Variant) -> Dictionary:
	if capabilities is Dictionary:
		return capabilities as Dictionary
	return {}


# Deterministic (a * b) / c with round-half-away-from-zero.
static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	var num: int = a * b
	var d: int = c if c > 0 else -c
	var half: int = d / 2
	if num >= 0:
		return (num + half) / d
	return -(((-num) + half) / d)


# Clamp a fixed-point value into [0..SCALE].
static func _clamp_q(q: int) -> int:
	if q < 0:
		return 0
	if q > SCALE:
		return SCALE
	return q
