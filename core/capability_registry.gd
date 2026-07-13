# capability_registry.gd
# ----------------------------------------------------------------------------
# Project Nexus - Capability registry (plan v4, phase MD2.1).
#
# The Capability layer is the FIXED, VERSIONED engine contract that sits
# between raw stats and the AI. Section 2.3 of docs/plan_android_fix_v4.md:
#
#   raw stats (health, armor, ...) --(engine formulas OR mod `affects`)-->
#       a CLOSED set of engine-known Capabilities
#
# The AI works ONLY with Capability + Role, never with a raw stat and never
# with a unit name. Mods change Capability VALUES (via stat / affects), never
# the LIST of capabilities. That closed list lives here.
#
# Design rules (consistent with the rest of the project):
#   - PURE INFRASTRUCTURE: RefCounted, no SceneTree / WorldState / sim-hash
#     dependency. It only DESCRIBES the contract. Headlessly unit-testable.
#   - FIXED-POINT DETERMINISM (section 2.1): every "normalised [0.0..1.0]"
#     quantity is stored/computed as a scaled integer in [0..SCALE]. `default_q`
#     is the safe fallback value (section 2.5) a capability yields when its
#     source stat is absent -- an int in [0..SCALE], never a float.
#   - DETERMINISTIC: `all_ids()` returns a stably SORTED array so the same
#     query always yields byte-for-byte the same list.
#   - English-only identifiers/comments (CODE_POLICY); any author-facing label
#     the UI shows is resolved through Localization (key `capability.<id>.name`).
# ----------------------------------------------------------------------------
class_name CapabilityRegistry
extends RefCounted

# Contract version. Bump ONLY when the closed list of capabilities changes
# (adding/removing a capability id). Mods must never change this; they only
# change capability VALUES. Consumers may assert on this to stay in sync.
const VERSION: int = 1

# Fixed-point scale (section 2.1 golden rule). A normalised [0.0..1.0] value is
# represented as an integer in [0..SCALE]. Mirrors the project-wide convention.
const SCALE: int = 1000

# Who a capability applies to.
const APPLIES_UNIT: String = "unit"
const APPLIES_BUILDING: String = "building"
const APPLIES_BOTH: String = "both"

# The single source of truth for the CLOSED, VERSIONED capability set
# (section 2.3). id -> record:
#   applies_to : "unit" | "building" | "both"
#   default_q  : fixed-point [0..SCALE] safe fallback when no stat feeds it
#   name_key   : i18n display key (cosmetic only; never touches the sim hash)
#
# Unit capabilities: survivability, damage_output, mobility, holding_power,
#   siege_power, scout_power, support_power, cost_efficiency, anti_air_power,
#   resource_pressure.
# Building capabilities: defense_value, production_value, tech_value,
#   economic_value, frontline_value, repair_value, control_value.
const CAPABILITIES: Dictionary = {
	# --- Unit capabilities -------------------------------------------------
	"survivability":     { "applies_to": "unit",     "default_q": 0, "name_key": "capability.survivability.name" },
	"damage_output":     { "applies_to": "unit",     "default_q": 0, "name_key": "capability.damage_output.name" },
	"mobility":          { "applies_to": "unit",     "default_q": 0, "name_key": "capability.mobility.name" },
	"holding_power":     { "applies_to": "unit",     "default_q": 0, "name_key": "capability.holding_power.name" },
	"siege_power":       { "applies_to": "unit",     "default_q": 0, "name_key": "capability.siege_power.name" },
	"scout_power":       { "applies_to": "unit",     "default_q": 0, "name_key": "capability.scout_power.name" },
	"support_power":     { "applies_to": "unit",     "default_q": 0, "name_key": "capability.support_power.name" },
	"cost_efficiency":   { "applies_to": "unit",     "default_q": 0, "name_key": "capability.cost_efficiency.name" },
	"anti_air_power":    { "applies_to": "unit",     "default_q": 0, "name_key": "capability.anti_air_power.name" },
	"resource_pressure": { "applies_to": "both",     "default_q": 0, "name_key": "capability.resource_pressure.name" },
	# --- Building capabilities ---------------------------------------------
	"defense_value":     { "applies_to": "building", "default_q": 0, "name_key": "capability.defense_value.name" },
	"production_value":  { "applies_to": "building", "default_q": 0, "name_key": "capability.production_value.name" },
	"tech_value":        { "applies_to": "building", "default_q": 0, "name_key": "capability.tech_value.name" },
	"economic_value":    { "applies_to": "building", "default_q": 0, "name_key": "capability.economic_value.name" },
	"frontline_value":   { "applies_to": "building", "default_q": 0, "name_key": "capability.frontline_value.name" },
	"repair_value":      { "applies_to": "building", "default_q": 0, "name_key": "capability.repair_value.name" },
	"control_value":     { "applies_to": "both",     "default_q": 0, "name_key": "capability.control_value.name" },
}


# All capability ids, stably SORTED (deterministic).
static func all_ids() -> Array:
	var ids: Array = CAPABILITIES.keys()
	ids.sort()
	return ids


# True if `id` is a known engine capability.
static func has_capability(id: String) -> bool:
	return CAPABILITIES.has(id)


# The full record for `id`, or an empty Dictionary when unknown.
static func record(id: String) -> Dictionary:
	if not CAPABILITIES.has(id):
		return {}
	return (CAPABILITIES[id] as Dictionary).duplicate(true)


# Who this capability applies to ("unit" | "building" | "both"); "" if unknown.
static func applies_to(id: String) -> String:
	if not CAPABILITIES.has(id):
		return ""
	return str((CAPABILITIES[id] as Dictionary).get("applies_to", APPLIES_BOTH))


# The fixed-point [0..SCALE] safe fallback for `id` (section 2.5); 0 if unknown.
static func default_q(id: String) -> int:
	if not CAPABILITIES.has(id):
		return 0
	return int((CAPABILITIES[id] as Dictionary).get("default_q", 0))


# The i18n display key for `id` (cosmetic); "" if unknown.
static func name_key(id: String) -> String:
	if not CAPABILITIES.has(id):
		return ""
	return str((CAPABILITIES[id] as Dictionary).get("name_key", ""))


# Sorted ids that apply to the given target ("unit" | "building"). A capability
# with applies_to == "both" is included for either target.
static func ids_for(target: String) -> Array:
	var out: Array = []
	for id in all_ids():
		var a: String = applies_to(id)
		if a == APPLIES_BOTH or a == target:
			out.append(id)
	return out
