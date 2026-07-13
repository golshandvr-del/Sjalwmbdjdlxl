# building_utility_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Utility scoring for AI BUILDING placement (Phase MD9, expert
# item 8). The building analog of UnitUtilityUtil (MD8): instead of dropping a
# structure on "the first empty tile near HQ", the AI scores every buildable
# structure by how well its CAPABILITY card matches the current battlefield
# NEED, then multiplies by the QUALITY of the candidate SITE.
#
# score_building = defense_need   x defense_value
#                + economy_need   x economic_value
#                + tech_need      x tech_value
#                + frontline_need x frontline_value
#                + site_quality   x placement_fit
#
# The first four terms are the "value" of the building given what the AI needs
# right now (needs derived from the MD7 Context vector). The last term couples
# the building to WHERE it would sit: a defensive tower wants a choke, an
# economic building wants a safe, resource-rich site (site_quality comes from
# MD9.2 site_scoring; placement_fit says how much THIS building cares about
# site quality).
#
# Everything is q-scaled (SCALE = 1000) integer math so it is byte-identical on
# every peer/replay -- building placement issues Commands that mutate the
# lockstep simulation, so it MUST be deterministic.
#
# Logic/Render Separation: nothing here touches the world model or the scene
# tree; it consumes plain Dictionaries (caps / context / site) built elsewhere.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (pure ASCII).
# ----------------------------------------------------------------------------
class_name BuildingUtilityUtil
extends RefCounted


# Fixed-point scale shared with the capability / weight / context layers.
const SCALE: int = 1000

# The building capability dimensions that feed placement utility. Each is read
# from the capability card (q 0..SCALE). Kept as an explicit, sorted list so the
# scoring is deterministic and easy to test. Mirrors CapabilityRegistry's
# building capabilities.
const SCORED_CAPS: Array = [
	"control_value",
	"defense_value",
	"economic_value",
	"frontline_value",
	"production_value",
	"repair_value",
	"tech_value",
]


# --- Fixed-point helpers -----------------------------------------------------

# Round-half-away-from-zero (a * b) / c. Deterministic on every CPU.
static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	var num: int = a * b
	var half: int = c / 2
	if num >= 0:
		return (num + half) / c
	return -((-num + half) / c)


# --- Need derivation from the MD7 Context vector -----------------------------
#
# The AI's current NEED for each building "value" axis, derived from the shared
# context vector (all context values are q in [0..SCALE]). Returned as a closed
# dictionary { defense_need, economy_need, tech_need, frontline_need } of q
# values. This is the deterministic bridge between "situation" and "what should
# I build".
static func derive_needs(context: Dictionary) -> Dictionary:
	# base_security 1000 = totally safe -> low defense need; invert it.
	var base_security: int = int(context.get("base_security", SCALE))
	var under_threat: int = int(context.get("under_threat", 0))
	var frontline: int = int(context.get("frontline_pressure", 0))
	# economy_gap 1000 = we are far ahead -> low economy need; invert it.
	var economy_gap: int = int(context.get("economy_gap", SCALE))
	# army_ratio 1000 = we dominate -> a comfortable army frees us to tech up.
	var army_ratio: int = int(context.get("army_ratio", SCALE))

	var defense_need: int = SCALE - base_security
	# Threat sharpens the defense need (weighted average with the threat flag).
	defense_need = _mul_div_round(defense_need + under_threat * SCALE / SCALE, SCALE, SCALE * 2)
	if defense_need < 0:
		defense_need = 0
	if defense_need > SCALE:
		defense_need = SCALE

	var economy_need: int = SCALE - economy_gap
	if economy_need < 0:
		economy_need = 0
	if economy_need > SCALE:
		economy_need = SCALE

	# We invest in tech when we are NOT desperate on defense/economy and the
	# army is holding: tech_need scales with how safe + how ahead we are.
	var tech_need: int = _mul_div_round(base_security + army_ratio, 1, 2)
	if tech_need < 0:
		tech_need = 0
	if tech_need > SCALE:
		tech_need = SCALE

	var frontline_need: int = frontline
	if frontline_need < 0:
		frontline_need = 0
	if frontline_need > SCALE:
		frontline_need = SCALE

	return {
		"defense_need": defense_need,
		"economy_need": economy_need,
		"tech_need": tech_need,
		"frontline_need": frontline_need,
	}


# --- Core scoring ------------------------------------------------------------

# The "value" of a building given the current needs, independent of WHERE it
# goes: the dot product of needs with the matching capability values. Needs is
# the dictionary produced by derive_needs; caps is the building's capability
# card (q). Folds back to q by dividing one SCALE out.
static func value_component(caps: Dictionary, needs: Dictionary) -> int:
	var total: int = 0
	total += _mul_div_round(int(needs.get("defense_need", 0)), int(caps.get("defense_value", 0)), SCALE)
	total += _mul_div_round(int(needs.get("economy_need", 0)), int(caps.get("economic_value", 0)), SCALE)
	total += _mul_div_round(int(needs.get("tech_need", 0)), int(caps.get("tech_value", 0)), SCALE)
	total += _mul_div_round(int(needs.get("frontline_need", 0)), int(caps.get("frontline_value", 0)), SCALE)
	return total


# The site-coupling component: site_quality (q, from MD9.2) times placement_fit
# (q; how much THIS building cares about site quality). A building with fit 0
# ignores where it lands; fit SCALE fully weights the site quality.
static func site_component(site_quality: int, placement_fit: int) -> int:
	return _mul_div_round(site_quality, placement_fit, SCALE)


# The full utility of placing `caps` at a site of quality `site_quality`, given
# the current `context` (MD7). `placement_fit` is a per-building constant (q).
# Deterministic: pure integer math over q inputs.
static func score_building(
		caps: Dictionary,
		context: Dictionary,
		site_quality: int,
		placement_fit: int) -> int:
	var needs: Dictionary = derive_needs(context)
	var score: int = 0
	score += value_component(caps, needs)
	score += site_component(site_quality, placement_fit)
	return score
