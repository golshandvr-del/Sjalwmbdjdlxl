# political_cost_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Dynamic diplomacy "political cost" model (Phase MC10.5,
# requests 11/12/17).
#
# Instead of a HARD cap on how many alliances an owner may hold, alliances and
# betrayals carry a POLITICAL COST: each extra alliance you sign lowers how much
# the rest of the world trusts you, and every betrayal lowers it sharply. Trust
# is a 0..100 score per owner; low trust makes future proposals less likely to
# be accepted (the diplomatic AI reads it in a later phase). This pure helper
# owns the arithmetic so it is unit-testable and identical on every peer.
#
# Logic/Render Separation: nothing here touches WorldState or the scene tree.
# Determinism: pure integer/float arithmetic on the inputs only.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PoliticalCostUtil
extends RefCounted


# Trust runs on a 0..100 scale; everyone starts neutral.
const TRUST_MIN: float = 0.0
const TRUST_MAX: float = 100.0
const TRUST_DEFAULT: float = 50.0


# The FIRST alliance is "free" (no reputation hit); every alliance beyond this
# many active ones incurs the escalating cost below.
const FREE_ALLIANCES: int = 1


# Base trust hit for each alliance past the free allowance, and how sharply the
# hit grows with each further alliance (spreading yourself thin looks greedy).
const ALLIANCE_COST_BASE: float = 6.0
const ALLIANCE_COST_STEP: float = 4.0


# A betrayal is far more damaging than merely over-committing.
const BETRAYAL_COST: float = 35.0


# Clamp a raw trust value into the valid range.
static func clamp_trust(value: float) -> float:
	return clampf(value, TRUST_MIN, TRUST_MAX)


# The political cost (trust points spent) of signing ONE more alliance when the
# owner already holds `current_alliances`. The first FREE_ALLIANCES cost 0; each
# beyond that costs BASE + STEP * (over_index), so 2nd/3rd/... escalate.
static func alliance_cost(current_alliances: int) -> float:
	var already: int = max(0, current_alliances)
	if already < FREE_ALLIANCES:
		return 0.0
	var over_index: int = already - FREE_ALLIANCES
	return ALLIANCE_COST_BASE + ALLIANCE_COST_STEP * float(over_index)


# The political cost of committing a betrayal. Flat and heavy so that betrayal
# is always a meaningful, reputation-shredding choice.
static func betrayal_cost() -> float:
	return BETRAYAL_COST


# Apply a cost to a trust score, returning the new clamped score. Costs are
# subtracted; a negative "cost" (a reward, e.g. honouring a treaty) adds trust.
static func apply_cost(current_trust: float, cost: float) -> float:
	return clamp_trust(current_trust - cost)


# Convenience: new trust after this owner signs one more alliance.
static func trust_after_alliance(current_trust: float, current_alliances: int) -> float:
	return apply_cost(current_trust, alliance_cost(current_alliances))


# Convenience: new trust after this owner commits a betrayal.
static func trust_after_betrayal(current_trust: float) -> float:
	return apply_cost(current_trust, betrayal_cost())


# A normalised 0..1 "acceptance likelihood" derived from trust: the diplomatic
# AI multiplies its base willingness by this. Kept pure so the same score maps
# to the same likelihood on every peer.
static func acceptance_factor(trust: float) -> float:
	var t: float = clamp_trust(trust)
	return t / TRUST_MAX
