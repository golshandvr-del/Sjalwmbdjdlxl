# ai_diplomacy_brain.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI diplomacy decision brain (Phase MC13, step 13.1,
# requests 14/15).
#
# The PURE cost/benefit engine that decides what a diplomatic AI does: whether
# to propose peace / an alliance, accept or reject an incoming treaty, declare
# war, betray an ally, or send aid. It is the "brain" behind the diplomacy
# module (MC10) and the personality vector (MC12).
#
# It answers the "seven-and-a-half questions" from the plan (section 1.c / MC13):
#   1. How am I doing?          (my_strength vs their_strength)
#   2. What do I want?          (profile ambition / greed / strategy)
#   3. What do I fear?          (threat pressure, being ganged up on)
#   4. Benefit of alliance?     (shared enemy, weakness, sociability)
#   5. Benefit of hostility?    (weak target, opportunism, greed)
#   6. Can I trust them?        (relationship trust + cross-match reputation)
#   7. Is now the right time?   (tempo, current war load)
#   7.5 Does my personality allow it? (loyalty / deceit gate on betrayal)
#
# DESIGN RULES (project constitution):
#   - PURE + DETERMINISTIC: a plain function of its inputs. NO WorldState, NO
#     SceneTree, NO RNG. Same context -> same action. This is what keeps the AI
#     lockstep-safe when the diplomacy module calls it (MC13.5).
#   - The "unforced error" / difficulty jitter lives in a SEPARATE seeded util
#     (MC13.4); this brain is the clean, best-effort evaluation. The consumer
#     may perturb the score deterministically before acting.
#   - INPUTS are plain dictionaries / an AiProfile-like object (get_value), so
#     tests feed hand-built scenarios with no engine dependencies.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
#
# ACTIONS it can return (stable string tokens):
#   "none", "propose_peace", "propose_alliance", "accept", "reject",
#   "declare_war", "betray", "send_aid".
# ----------------------------------------------------------------------------
class_name AiDiplomacyBrain
extends RefCounted

# The complete set of actions the brain may recommend, in a stable order.
const ACTION_NONE: String = "none"
const ACTION_PROPOSE_PEACE: String = "propose_peace"
const ACTION_PROPOSE_ALLIANCE: String = "propose_alliance"
const ACTION_ACCEPT: String = "accept"
const ACTION_REJECT: String = "reject"
const ACTION_DECLARE_WAR: String = "declare_war"
const ACTION_BETRAY: String = "betray"
const ACTION_SEND_AID: String = "send_aid"

const ACTIONS: Array = [
	ACTION_NONE, ACTION_PROPOSE_PEACE, ACTION_PROPOSE_ALLIANCE, ACTION_ACCEPT,
	ACTION_REJECT, ACTION_DECLARE_WAR, ACTION_BETRAY, ACTION_SEND_AID,
]

# Score threshold a proactive action must clear to be taken (else "none"). Keeps
# a shy / balanced AI from constantly spamming proposals.
const ACT_THRESHOLD: float = 0.55

# Trust (0..100) below which we will NOT accept an offer from a party, and above
# which we lean toward accepting.
const TRUST_ACCEPT_FLOOR: float = 25.0


# --- Public API -------------------------------------------------------------

# Decide the action toward ONE other player, given the situation. `context` is a
# plain dictionary describing the current view of that relationship:
#
#   {
#     "profile": <AiProfile-like or null>,   # our fixed personality
#     "relationship": "neutral"|"ally"|...,  # current RelationshipUtil state
#     "trust": float 0..100,                 # how much WE trust them
#     "reputation": float -1..1,             # cross-match memory (MC13.3), + good
#     "my_strength": float >= 0,             # our army/economy index
#     "their_strength": float >= 0,          # their index
#     "threat": float 0..1,                  # pressure we are under right now
#     "shared_enemy": bool,                  # we both fight a common foe
#     "current_allies": int,                 # how many allies we already have
#     "at_war_count": int,                   # how many wars we are already in
#     "incoming_offer": ""|<treaty type>,    # a pending proposal to respond to
#   }
#
# Returns { "action": <token>, "score": float, "reasons": Dictionary }.
static func decide(context: Dictionary) -> Dictionary:
	var profile = context.get("profile", null)
	var relationship: String = str(context.get("relationship", "neutral"))
	var trust: float = _num(context.get("trust", 50.0))
	var reputation: float = clampf(_num(context.get("reputation", 0.0)), -1.0, 1.0)
	var my_strength: float = maxf(0.0, _num(context.get("my_strength", 1.0)))
	var their_strength: float = maxf(0.0, _num(context.get("their_strength", 1.0)))
	var threat: float = clampf(_num(context.get("threat", 0.0)), 0.0, 1.0)
	var shared_enemy: bool = bool(context.get("shared_enemy", false))
	var current_allies: int = int(context.get("current_allies", 0))
	var incoming: String = str(context.get("incoming_offer", ""))

	# --- The evaluation knobs (question 1..7.5) ---
	# Q1: relative strength. > 1 means we are stronger; < 1 weaker.
	var ratio: float = my_strength / maxf(0.001, their_strength)
	var stronger: float = clampf((ratio - 1.0), -1.0, 1.0)   # -1 weaker .. +1 stronger

	# Personality knobs (neutral 0.5 when no profile).
	var aggression: float = _p(profile, "personality", "aggression")
	var ambition: float = _p(profile, "personality", "ambition")
	var greed: float = _p(profile, "personality", "greed")
	var loyalty: float = _p(profile, "personality", "loyalty")
	var sociability: float = _p(profile, "diplomacy_bias", "sociability")
	var trust_bias: float = _p(profile, "diplomacy_bias", "trust")
	var vengeance: float = _p(profile, "diplomacy_bias", "vengeance")
	var deceit: float = _p(profile, "diplomacy_bias", "deceit")
	var generosity: float = _p(profile, "diplomacy_bias", "generosity")
	var opportunism: float = _p(profile, "diplomacy_bias", "opportunism")

	# A blended "do I trust them" figure in 0..1 (relationship trust + reputation
	# + our own trusting nature).
	var trust_unit: float = clampf(trust / 100.0, 0.0, 1.0)
	var trust_blend: float = clampf(
		0.5 * trust_unit + 0.25 * (reputation * 0.5 + 0.5) + 0.25 * trust_bias, 0.0, 1.0)

	var reasons: Dictionary = {
		"ratio": ratio, "stronger": stronger, "threat": threat,
		"trust_blend": trust_blend, "shared_enemy": shared_enemy,
		"relationship": relationship,
	}

	# --- Responding to an incoming offer takes priority over acting. ---
	if not incoming.is_empty():
		var resp: Dictionary = _respond(incoming, trust_blend, threat, stronger,
			shared_enemy, sociability, opportunism, greed)
		resp["reasons"] = reasons
		return resp

	# --- Proactive actions, scored; the best above threshold wins. ---
	var best_action: String = ACTION_NONE
	var best_score: float = 0.0

	# BETRAY: only from an ally, gated hard by personality (loyalty vs deceit),
	# and only when it clearly pays (we are stronger, they are weak, opportunistic).
	if relationship == "ally":
		var betray_gate: float = clampf(deceit + opportunism - loyalty, 0.0, 1.0)
		var betray_gain: float = clampf(0.5 * maxf(0.0, stronger) + 0.5 * greed, 0.0, 1.0)
		var betray_score: float = betray_gate * betray_gain
		if betray_score > best_score:
			best_score = betray_score
			best_action = ACTION_BETRAY

	# DECLARE WAR: on a weaker, distrusted, non-ally target; aggression/greed push
	# it, being already at war or under threat pulls it back.
	if relationship != "ally" and relationship != "vassal":
		var weak_target: float = clampf(maxf(0.0, stronger), 0.0, 1.0)
		var war_score: float = clampf(
			0.4 * weak_target + 0.3 * aggression + 0.2 * ambition + 0.1 * (1.0 - trust_blend)
			- 0.4 * threat, 0.0, 1.0)
		# Vengeance: a distrusted rival/enemy we hold a grudge against.
		if relationship == "rival" or relationship == "enemy":
			war_score = clampf(war_score + 0.2 * vengeance, 0.0, 1.0)
		if war_score > best_score:
			best_score = war_score
			best_action = ACTION_DECLARE_WAR

	# PROPOSE ALLIANCE: with a not-yet-ally when there is a shared enemy or we are
	# under threat and they are strong; sociability + trust drive it.
	if relationship != "ally" and relationship != "enemy":
		var need: float = 0.0
		if shared_enemy:
			need += 0.4
		if threat > 0.4:
			need += 0.3 * threat
		if stronger < 0.0:
			need += 0.2 * (-stronger)   # we are weaker -> want a protector
		var ally_score: float = clampf(
			0.5 * clampf(need, 0.0, 1.0) + 0.3 * sociability + 0.2 * trust_blend, 0.0, 1.0)
		# Political cost: each existing alliance makes another less attractive.
		ally_score = clampf(ally_score - 0.08 * float(max(0, current_allies)), 0.0, 1.0)
		if ally_score > best_score:
			best_score = ally_score
			best_action = ACTION_PROPOSE_ALLIANCE

	# PROPOSE PEACE: when hostile but losing / over-extended, sue for peace.
	if relationship == "enemy" or relationship == "rival":
		var peace_score: float = clampf(
			0.5 * threat + 0.3 * maxf(0.0, -stronger) + 0.2 * (1.0 - aggression), 0.0, 1.0)
		if peace_score > best_score:
			best_score = peace_score
			best_action = ACTION_PROPOSE_PEACE

	# SEND AID: to an ally under threat, gated by generosity.
	if relationship == "ally" and shared_enemy:
		var aid_score: float = clampf(0.5 * generosity + 0.3 * loyalty + 0.2 * threat, 0.0, 1.0)
		if aid_score > best_score:
			best_score = aid_score
			best_action = ACTION_SEND_AID

	if best_score < ACT_THRESHOLD:
		return { "action": ACTION_NONE, "score": best_score, "reasons": reasons }
	return { "action": best_action, "score": best_score, "reasons": reasons }


# --- Response to an incoming offer ------------------------------------------

static func _respond(incoming: String, trust_blend: float, threat: float,
		stronger: float, shared_enemy: bool, sociability: float,
		opportunism: float, greed: float) -> Dictionary:
	# Hostile "offers" (declare_war / betrayal) are not accepted -- they are just
	# notifications; treat as reject so callers get a clean binary.
	if incoming == "declare_war" or incoming == "betrayal":
		return { "action": ACTION_REJECT, "score": 1.0 }

	# Peace / ceasefire / non-aggression: accept readily when we are pressured or
	# fairly trusting; reject when we are strong and distrustful (want to press on).
	if incoming == "ceasefire" or incoming == "non_aggression":
		var accept_peace: float = clampf(
			0.5 * threat + 0.3 * trust_blend + 0.2 * maxf(0.0, -stronger), 0.0, 1.0)
		return _binary(accept_peace, 0.4)

	# Alliance: accept when trusted and there is mutual benefit (shared enemy /
	# pressure), reject a low-trust partner.
	if incoming == "alliance_temp" or incoming == "alliance_full":
		if trust_blend * 100.0 < TRUST_ACCEPT_FLOOR:
			return { "action": ACTION_REJECT, "score": 1.0 - trust_blend }
		var accept_ally: float = clampf(
			0.4 * trust_blend + 0.3 * sociability + (0.3 if shared_enemy else 0.0)
			+ 0.2 * threat, 0.0, 1.0)
		return _binary(accept_ally, 0.5)

	# Trade / tribute / resource: opportunists and the greedy take free value.
	if incoming == "trade_resource" or incoming == "tribute":
		var accept_trade: float = clampf(0.4 + 0.3 * opportunism + 0.3 * greed, 0.0, 1.0)
		return _binary(accept_trade, 0.5)

	# Anything else: lean on trust.
	return _binary(trust_blend, 0.5)


# Turn an acceptance score + threshold into an accept/reject decision.
static func _binary(score: float, threshold: float) -> Dictionary:
	if score >= threshold:
		return { "action": ACTION_ACCEPT, "score": score }
	return { "action": ACTION_REJECT, "score": 1.0 - score }


# --- Helpers ----------------------------------------------------------------

static func _p(profile, category: String, knob: String) -> float:
	if profile != null and profile.has_method("get_value"):
		return float(profile.get_value(category, knob))
	return 0.5


static func _num(value) -> float:
	if value is float or value is int:
		return float(value)
	if value is String and (value as String).is_valid_float():
		return (value as String).to_float()
	return 0.0
