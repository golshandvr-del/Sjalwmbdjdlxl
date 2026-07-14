# ai_decision_pipeline_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Staged AI decision pipeline (plan v4, MD10, expert item 9).
#
# The final decision link of the data-driven AI backbone
# (docs/plan_android_fix_v4.md). It fuses every earlier layer into ONE explicit,
# four-stage decision so the strategic brain stops hard-coding "if X then build
# soldier" and instead reasons: what is my situation, what should I prioritise,
# which category of action serves that priority, and finally which exact unit /
# building / target realises it.
#
#   Stage 1 STATE:     classify the situation from the MD7 Context vector.
#   Stage 2 PRIORITY:  pick ONE macro priority (defense / economy / research /
#                      attack / diplomacy / expansion) from policy + weights.
#   Stage 3 CATEGORY:  map the priority to an action category (defensive
#                      building, holding unit, economic building, ...).
#   Stage 4 PICK:      choose the exact unit/building via the MD8/MD9 utility
#                      scorers over the supplied candidates.
#
# The public entry point is:
#   decide(context, policy, weights, candidates, params) -> action Dictionary
# where `action` is a structured decision:
#   { "state", "priority", "category", "kind", "target_id", "score", "detail" }
#
# Design rules (Definition of Done, plan section 2 constant principles):
#   - PURE INFRASTRUCTURE: RefCounted, no scene tree / world model / RNG /
#     sim-hash dependency. Same (context, policy, weights, candidates) in ->
#     byte-identical action out. NO persistent internal state (plan note at
#     MD10 line 551): the pipeline is a pure function of its deterministic
#     inputs.
#   - FIXED-POINT DETERMINISM (section 2.1 golden rule): every comparison and
#     every score is pure integer q-math on the shared SCALE = 1000. No float
#     ever enters the decision. Priority ranking ties break on a fixed,
#     documented order; candidate ties break on id (delegated to MD8/MD9).
#   - STABLE ORDER (section 2.1): the priority table and category table are
#     fixed, sorted, closed lists; the pick delegates to select_best (id-sorted).
#   - RESILIENCE (section 2.5): missing context keys, an empty policy, an empty
#     candidate list, and unknown weights all yield a documented SAFE action,
#     never a crash. decide ALWAYS returns the full action key set.
#   - COSMETIC vs SIMULATION (section 2.2): the action drives a deterministic
#     Command in the module, so it MUST be deterministic (it is); this util
#     never writes the world model and never touches the sim hasher.
#   - BACKWARD COMPATIBLE (MD10.5): the module keeps issuing the exact same
#     Commands; the pipeline only decides WHAT, the module still decides the raw
#     Command shape and falls back to legacy logic on an empty pick.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiDecisionPipelineUtil
extends RefCounted

# Fixed-point scale (section 2.1), mirroring the whole v4 backbone.
const SCALE: int = 1000

# --- Stage 1: situation states (closed, sorted) -----------------------------
# A coarse classification of the battlefield, derived purely from the MD7
# context vector. One and only one state is chosen deterministically.
const STATE_CRISIS: String = "crisis"           # base under direct threat / losing
const STATE_PRESSURED: String = "pressured"     # contested frontline, not yet crisis
const STATE_DEVELOPING: String = "developing"   # safe, still growing economy/army
const STATE_DOMINANT: String = "dominant"       # safe and ahead -> can press / tech

const STATES: Array = [
	STATE_CRISIS,
	STATE_DEVELOPING,
	STATE_DOMINANT,
	STATE_PRESSURED,
]

# --- Stage 2: macro priorities (closed, sorted) -----------------------------
# The expert's six macro priorities (plan MD10.2). Exactly one is selected.
const PRIORITY_ATTACK: String = "attack"
const PRIORITY_DEFENSE: String = "defense"
const PRIORITY_DIPLOMACY: String = "diplomacy"
const PRIORITY_ECONOMY: String = "economy"
const PRIORITY_EXPANSION: String = "expansion"
const PRIORITY_RESEARCH: String = "research"

const PRIORITIES: Array = [
	PRIORITY_ATTACK,
	PRIORITY_DEFENSE,
	PRIORITY_DIPLOMACY,
	PRIORITY_ECONOMY,
	PRIORITY_EXPANSION,
	PRIORITY_RESEARCH,
]

# Deterministic tie-break order for equal-scoring priorities: defense first
# (survival dominates), then economy, research, expansion, attack, diplomacy.
# This mirrors a conservative "keep the base alive first" doctrine and is fixed
# so every peer resolves a tie identically.
const PRIORITY_TIE_ORDER: Array = [
	PRIORITY_DEFENSE,
	PRIORITY_ECONOMY,
	PRIORITY_RESEARCH,
	PRIORITY_EXPANSION,
	PRIORITY_ATTACK,
	PRIORITY_DIPLOMACY,
]

# --- Stage 3: action categories (closed, sorted) ----------------------------
# The category tells the module which kind of Command to build and which
# candidate pool (units vs buildings) Stage 4 should score.
const CATEGORY_DEFENSIVE_BUILDING: String = "defensive_building"
const CATEGORY_ECONOMIC_BUILDING: String = "economic_building"
const CATEGORY_TECH_BUILDING: String = "tech_building"
const CATEGORY_HOLDING_UNIT: String = "holding_unit"
const CATEGORY_STRIKE_UNIT: String = "strike_unit"
const CATEGORY_EXPANSION_BUILDING: String = "expansion_building"
const CATEGORY_DIPLOMACY_ACTION: String = "diplomacy_action"
const CATEGORY_NONE: String = "none"

const CATEGORIES: Array = [
	CATEGORY_DEFENSIVE_BUILDING,
	CATEGORY_DIPLOMACY_ACTION,
	CATEGORY_ECONOMIC_BUILDING,
	CATEGORY_EXPANSION_BUILDING,
	CATEGORY_HOLDING_UNIT,
	CATEGORY_NONE,
	CATEGORY_STRIKE_UNIT,
	CATEGORY_TECH_BUILDING,
]

# Which candidate pool a category draws from: "unit", "building", or "" (none).
const CATEGORY_POOL: Dictionary = {
	"defensive_building": "building",
	"diplomacy_action": "",
	"economic_building": "building",
	"expansion_building": "building",
	"holding_unit": "unit",
	"none": "",
	"strike_unit": "unit",
	"tech_building": "building",
}

# The closed action key set, always present in a returned decision.
const ACTION_KEYS: Array = [
	"category",
	"detail",
	"kind",
	"priority",
	"score",
	"state",
	"target_id",
]


# --- Public API -------------------------------------------------------------

# Run the full four-stage pipeline and return a structured decision.
#
# `context`    : the MD7 fixed-point context vector (Dictionary of q ints).
# `policy`     : the MD6 policy rule list (Array); empty -> baseline flags.
# `weights`    : the MD5 derived weights { "roles":{...}, "capabilities":{...} }.
# `candidates` : { "unit": Array, "building": Array } candidate pools, each a
#   list of { "id", "caps", "primary_role", ...(building extras) } dictionaries.
#   Missing pools are treated as empty (resilience).
# `params`     : optional deterministic knobs for Stage 4 scoring:
#   { "match_seed":int, "tick":int, "owner":int, "noise_strength_q":int,
#     "site_quality":int, "placement_fit":int }. All default to 0.
#
# Returns the full ACTION_KEYS set. Deterministic and resilient.
static func decide(
		context: Variant,
		policy: Variant,
		weights: Variant,
		candidates: Variant,
		params: Variant = {}) -> Dictionary:
	var ctx: Dictionary = context as Dictionary if context is Dictionary else {}
	var w: Dictionary = weights as Dictionary if weights is Dictionary else {}
	var pools: Dictionary = candidates as Dictionary if candidates is Dictionary else {}
	var p: Dictionary = params as Dictionary if params is Dictionary else {}

	# Stage 1 + Stage 2 + Stage 3.
	var flags: Dictionary = AiPolicyUtil.evaluate(policy, ctx)
	var state: String = classify_state(ctx)
	var priority: String = choose_priority(ctx, flags, w)
	var category: String = choose_category(priority, ctx, flags)

	# Stage 4: exact pick over the matching candidate pool.
	var pick: Dictionary = pick_action(category, ctx, w, pools, p)

	return {
		"state": state,
		"priority": priority,
		"category": category,
		"kind": str(pick.get("kind", "")),
		"target_id": str(pick.get("target_id", "")),
		"score": int(pick.get("score", 0)),
		"detail": pick.get("detail", {}),
	}


# The closed situation-state set (sorted copy).
static func states() -> Array:
	return STATES.duplicate()


# The closed macro-priority set (sorted copy).
static func priorities() -> Array:
	return PRIORITIES.duplicate()


# The closed action-category set (sorted copy).
static func categories() -> Array:
	return CATEGORIES.duplicate()


# The closed action key set (sorted copy).
static func action_keys() -> Array:
	return ACTION_KEYS.duplicate()


# A resilient, safe default decision (as if nothing is known). Handy for a
# module that must return something before any world data exists.
static func safe_default_action() -> Dictionary:
	return decide({}, [], {}, {}, {})


# --- Stage 1: STATE ---------------------------------------------------------
#
# Classify the battlefield from the context vector. Thresholds are fixed
# q-values; comparisons are pure integer. Priority of tests (highest-severity
# first) makes the result deterministic:
#   CRISIS    if under_threat OR base_security very low OR army badly losing.
#   PRESSURED if there is meaningful frontline pressure or a near enemy.
#   DOMINANT  if safe AND clearly ahead on army/economy.
#   DEVELOPING otherwise (the safe, growing default).
static func classify_state(context: Variant) -> String:
	var ctx: Dictionary = context as Dictionary if context is Dictionary else {}
	var under_threat: int = int(ctx.get("under_threat", 0))
	var base_security: int = int(ctx.get("base_security", SCALE))
	var army_ratio: int = int(ctx.get("army_ratio", SCALE / 2))
	var frontline: int = int(ctx.get("frontline_pressure", 0))
	var economy_gap: int = int(ctx.get("economy_gap", SCALE / 2))

	# CRISIS: an active threat at the base, a badly exposed base, or a collapsing
	# army. Any one of these is a survival emergency.
	if under_threat >= 1 or base_security < 300 or army_ratio < 250:
		return STATE_CRISIS
	# PRESSURED: contested frontline or a moderately exposed base.
	if frontline >= 400 or base_security < 600:
		return STATE_PRESSURED
	# DOMINANT: safe and clearly ahead on BOTH army and economy.
	if base_security >= 700 and army_ratio >= 650 and economy_gap >= 550:
		return STATE_DOMINANT
	# DEVELOPING: the safe, still-growing default.
	return STATE_DEVELOPING


# --- Stage 2: PRIORITY ------------------------------------------------------
#
# Score each macro priority as a fixed-point integer from the context vector,
# policy flags (MD6), and derived weights (MD5), then pick the argmax with a
# fixed tie-break (PRIORITY_TIE_ORDER). Pure integer throughout.
static func choose_priority(context: Variant, flags: Variant, weights: Variant) -> String:
	var scores: Dictionary = priority_scores(context, flags, weights)
	return _argmax_priority(scores)


# The per-priority q-score table. Exposed for testing; the values are the raw
# fixed-point urgencies (higher = more urgent) BEFORE the tie-break.
static func priority_scores(context: Variant, flags: Variant, weights: Variant) -> Dictionary:
	var ctx: Dictionary = context as Dictionary if context is Dictionary else {}
	var f: Dictionary = flags as Dictionary if flags is Dictionary else {}
	var w: Dictionary = weights as Dictionary if weights is Dictionary else {}
	var role_w: Dictionary = (w.get("roles", {}) as Dictionary) if (w.get("roles", {}) is Dictionary) else {}

	var under_threat: int = int(ctx.get("under_threat", 0))
	var base_security: int = int(ctx.get("base_security", SCALE))
	var army_ratio: int = int(ctx.get("army_ratio", SCALE / 2))
	var frontline: int = int(ctx.get("frontline_pressure", 0))
	var economy_gap: int = int(ctx.get("economy_gap", SCALE / 2))
	var enemy_distance: int = int(ctx.get("enemy_distance", SCALE))
	var has_ally: int = int(ctx.get("has_ally", 0))
	var in_active_war: int = int(ctx.get("in_active_war", 0))

	# DEFENSE urgency: rises as the base becomes insecure or pressured, spikes
	# under an active threat. Policy prefer_static_defense / prefer_tank add.
	var defense: int = (SCALE - base_security)
	defense += _avg2(frontline, under_threat * SCALE)
	if bool(f.get("prefer_static_defense", false)):
		defense += SCALE / 2
	if bool(f.get("prefer_tank_when_pressured", false)) and frontline >= 500:
		defense += SCALE / 4

	# ECONOMY urgency: rises as we fall behind economically, tempered when the
	# base is unsafe (can't farm under fire). Policy prefer_economy adds.
	var economy: int = (SCALE - economy_gap)
	economy = _mul_div_round(economy, base_security, SCALE)
	if bool(f.get("prefer_economy", false)):
		economy += SCALE / 2

	# RESEARCH urgency: a "when comfortable" priority - scales with how safe and
	# how far ahead on army we are (we tech up from strength). Tech role weight
	# biases it up for tech-loving profiles.
	var research: int = _avg2(base_security, army_ratio)
	research = _mul_div_round(research, int(role_w.get("tech", SCALE)), SCALE)

	# ATTACK urgency: rises with our army advantage and an exposed enemy, gated
	# by the allow_attack flag (a defensive policy can zero it out). Harass flag
	# adds when the enemy is exposed.
	var attack: int = 0
	if bool(f.get("allow_attack", true)):
		attack = _avg2(army_ratio, SCALE - enemy_distance)
		if bool(f.get("prefer_harass_when_exposed", false)) and enemy_distance <= 600:
			attack += SCALE / 4
	# A collapsing army must never prioritise attacking.
	if army_ratio < 300:
		attack = 0

	# EXPANSION urgency: grow the map when safe and reasonably even; economy
	# role weight biases it. Suppressed under threat.
	var expansion: int = 0
	if under_threat == 0 and base_security >= 500:
		expansion = _mul_div_round(_avg2(base_security, economy_gap), int(role_w.get("economic", SCALE)), SCALE)

	# DIPLOMACY urgency: only meaningful when we have an ally or an active war;
	# otherwise near zero so it never wins by accident.
	var diplomacy: int = 0
	if has_ally >= 1 or in_active_war >= 1:
		diplomacy = _avg2(has_ally * SCALE, in_active_war * SCALE) / 4

	return {
		PRIORITY_ATTACK: _clamp_nonneg(attack),
		PRIORITY_DEFENSE: _clamp_nonneg(defense),
		PRIORITY_DIPLOMACY: _clamp_nonneg(diplomacy),
		PRIORITY_ECONOMY: _clamp_nonneg(economy),
		PRIORITY_EXPANSION: _clamp_nonneg(expansion),
		PRIORITY_RESEARCH: _clamp_nonneg(research),
	}


# --- Stage 3: CATEGORY ------------------------------------------------------
#
# Map the chosen macro priority to a concrete action category, refined by the
# state and policy. Deterministic table lookup with small, fixed refinements.
static func choose_category(priority: String, context: Variant, flags: Variant) -> String:
	var ctx: Dictionary = context as Dictionary if context is Dictionary else {}
	var f: Dictionary = flags as Dictionary if flags is Dictionary else {}
	var frontline: int = int(ctx.get("frontline_pressure", 0))
	match priority:
		PRIORITY_DEFENSE:
			# Static defense policy or heavy pressure -> build a wall/tower;
			# otherwise train a durable holding unit to plug the line.
			if bool(f.get("prefer_static_defense", false)) or frontline >= 600:
				return CATEGORY_DEFENSIVE_BUILDING
			return CATEGORY_HOLDING_UNIT
		PRIORITY_ECONOMY:
			return CATEGORY_ECONOMIC_BUILDING
		PRIORITY_RESEARCH:
			return CATEGORY_TECH_BUILDING
		PRIORITY_ATTACK:
			return CATEGORY_STRIKE_UNIT
		PRIORITY_EXPANSION:
			return CATEGORY_EXPANSION_BUILDING
		PRIORITY_DIPLOMACY:
			return CATEGORY_DIPLOMACY_ACTION
		_:
			return CATEGORY_NONE


# The candidate pool key ("unit"/"building"/"") a category draws from.
static func category_pool(category: String) -> String:
	return str(CATEGORY_POOL.get(category, ""))


# --- Stage 4: PICK ----------------------------------------------------------
#
# Choose the exact unit/building for the category by delegating to the MD8/MD9
# utility scorers over the matching candidate pool. Returns a pick dictionary
#   { "kind", "target_id", "score", "detail" }
# where kind is the pool ("unit"/"building"/"") and target_id is the chosen
# candidate id ("" when the pool is empty or the category needs no candidate).
static func pick_action(
		category: String,
		context: Variant,
		weights: Variant,
		candidates: Variant,
		params: Variant = {}) -> Dictionary:
	var ctx: Dictionary = context as Dictionary if context is Dictionary else {}
	var w: Dictionary = weights as Dictionary if weights is Dictionary else {}
	var pools: Dictionary = candidates as Dictionary if candidates is Dictionary else {}
	var p: Dictionary = params as Dictionary if params is Dictionary else {}
	var pool_key: String = category_pool(category)

	if pool_key == "unit":
		return _pick_unit(category, pools, w, ctx, p)
	if pool_key == "building":
		return _pick_building(category, pools, ctx, p)
	# Diplomacy / none: no candidate needed; the module handles the raw action.
	return { "kind": "", "target_id": "", "score": 0, "detail": {} }


# Pick the best unit via UnitUtilityUtil.select_best (id-stable tie-break).
# The chosen CATEGORY (Stage 3) biases the capability weights so the exact pick
# reflects the category's intent (a STRIKE order favours the damage dealer, a
# HOLDING order the durable unit) -- this is the "category then exact pick"
# design. The bias is a deterministic integer overlay on the profile weights;
# the shared MD8 scorer is left untouched.
static func _pick_unit(category: String, pools: Dictionary, weights: Dictionary, ctx: Dictionary, p: Dictionary) -> Dictionary:
	var list: Array = pools.get("unit", []) as Array if (pools.get("unit", []) is Array) else []
	if list.is_empty():
		return { "kind": "unit", "target_id": "", "score": 0, "detail": {} }
	var biased: Dictionary = _category_biased_weights(category, weights)
	var match_seed: int = int(p.get("match_seed", 0))
	var tick: int = int(p.get("tick", 0))
	var owner: int = int(p.get("owner", 0))
	var noise: int = int(p.get("noise_strength_q", 0))
	var best_id: String = UnitUtilityUtil.select_best(list, biased, ctx, match_seed, tick, owner, noise)
	# Recompute the winning score for the detail (deterministic, same inputs).
	var score: int = 0
	for raw in list:
		if not (raw is Dictionary):
			continue
		var cand: Dictionary = raw as Dictionary
		if str(cand.get("id", "")) != best_id:
			continue
		var salt: int = abs(best_id.hash())
		score = UnitUtilityUtil.score_unit(
			(cand.get("caps", {}) as Dictionary),
			str(cand.get("primary_role", "generic")),
			biased, ctx, match_seed, tick, owner, salt, noise)
		break
	return { "kind": "unit", "target_id": best_id, "score": score, "detail": {} }


# Deterministic category-bias overlay on the profile's capability weights. For a
# unit category we DOUBLE the weight of the capabilities that category is about
# (strike -> damage_output; holding -> survivability + holding_power) so Stage 4
# picks the candidate that best serves the Stage 3 category. Returns a NEW dict
# (never mutates the caller's weights); a non-unit or unknown category returns
# the weights unchanged. Pure integer math -> lockstep safe.
static func _category_biased_weights(category: String, weights: Dictionary) -> Dictionary:
	var boost: Array = []
	match category:
		CATEGORY_STRIKE_UNIT:
			boost = ["damage_output"]
		CATEGORY_HOLDING_UNIT:
			boost = ["survivability", "holding_power"]
		_:
			return weights
	var out: Dictionary = weights.duplicate(true)
	var caps: Dictionary = (out.get("capabilities", {}) as Dictionary) if (out.get("capabilities", {}) is Dictionary) else {}
	for cap_id in boost:
		var w_q: int = int(caps.get(cap_id, SCALE))
		caps[cap_id] = w_q * 2
	out["capabilities"] = caps
	return out


# Pick the best building by scoring each candidate with BuildingUtilityUtil
# and taking the argmax, with a STABLE tie-break on id (lexicographic). Each
# building candidate may carry its own "site_quality" and "placement_fit"; the
# params provide defaults.
static func _pick_building(category: String, pools: Dictionary, ctx: Dictionary, p: Dictionary) -> Dictionary:
	var list: Array = pools.get("building", []) as Array if (pools.get("building", []) is Array) else []
	if list.is_empty():
		return { "kind": "building", "target_id": "", "score": 0, "detail": {} }
	var def_site: int = int(p.get("site_quality", 0))
	var def_fit: int = int(p.get("placement_fit", 0))
	# Iterate in id-sorted order for a deterministic scan.
	var sorted: Array = []
	for e in list:
		if e is Dictionary:
			sorted.append(e)
	sorted.sort_custom(func(a, b): return str((a as Dictionary).get("id", "")) < str((b as Dictionary).get("id", "")))
	var best_id: String = ""
	var best_score: int = -2147483648
	for raw in sorted:
		var cand: Dictionary = raw as Dictionary
		var id: String = str(cand.get("id", ""))
		if id == "":
			continue
		var site_q: int = int(cand.get("site_quality", def_site))
		var fit_q: int = int(cand.get("placement_fit", def_fit))
		var s: int = BuildingUtilityUtil.score_building((cand.get("caps", {}) as Dictionary), ctx, site_q, fit_q)
		if s > best_score:
			best_score = s
			best_id = id
	return { "kind": "building", "target_id": best_id, "score": best_score, "detail": { "category": category } }


# --- Internals: deterministic priority argmax + integer helpers -------------

# Argmax over a priority-score dictionary with a fixed tie-break order. Returns
# the priority with the highest q-score; ties resolve by PRIORITY_TIE_ORDER.
static func _argmax_priority(scores: Dictionary) -> String:
	var best: String = PRIORITY_TIE_ORDER[0]
	var best_score: int = int(scores.get(best, 0))
	for prio in PRIORITY_TIE_ORDER:
		var s: int = int(scores.get(prio, 0))
		if s > best_score:
			best_score = s
			best = prio
	return best


# The integer mean of two q-values, round-half-away-from-zero.
static func _avg2(a: int, b: int) -> int:
	return _div_round(a + b, 2)


# Deterministic (a * b) / c with round-half-away-from-zero. c must be > 0.
static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	return _div_round(a * b, c)


# Deterministic integer division with round-half-away-from-zero.
static func _div_round(num: int, den: int) -> int:
	if den == 0:
		return 0
	var d: int = den if den > 0 else -den
	var half: int = d / 2
	if num >= 0:
		return (num + half) / d
	return -(((-num) + half) / d)


# Clamp a value to be non-negative (urgencies never go below zero).
static func _clamp_nonneg(v: int) -> int:
	return v if v > 0 else 0
