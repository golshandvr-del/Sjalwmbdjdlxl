# ai_learning_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI learning layer (Phase MD11, expert item 12). Learning acts
# ONLY on ROLE weights, SITE preferences and TARGET preferences -- never on raw
# stats (the expert's explicit instruction). It is split into two strictly
# separated levels, exactly mirroring the determinism discipline of MC13:
#
#   LEVEL 1 (in-match, DETERMINISTIC, inside the sim hash):
#     Reinforce roles/sites/targets that succeeded, weaken those that failed.
#     Its ONLY inputs are deterministic battle-outcome summaries derived from
#     worldstate/tick, and its output is stored back in the worldstate snapshot
#     (like posture), so every peer computes the identical adjustment. All math
#     is fixed-point q-scaled (SCALE = 1000); no float ever enters this path.
#
#   LEVEL 2 (cross-match, OUTSIDE the sim hash):
#     "Which role / tactic worked on this mod / map." Persisted in user:// via
#     the reputation-store pattern (AiReputationStore, MC13.3). It only seeds
#     the STARTING weights of a match (identical for every peer from the same
#     file, or distributed by the host in the seed) -- it NEVER nudges a live
#     in-match decision non-deterministically.
#
# MD11.4: the learning RATE comes from the AiProfile learning_bias knobs
# (in_match_rate, exploration, memory_weight, ...).
# MD11.5: an anti-exploit guard caps the per-match change of any single weight
# and softly pulls every weight back toward its baseline, so learning can never
# lock the AI into a degenerate strategy.
#
# PURE INFRASTRUCTURE: RefCounted, no scene tree / world model / RNG / live
# sim-hash dependency. Same inputs -> byte-identical outputs. Callers build the
# deterministic summaries from worldstate and feed them in.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments, pure ASCII.
# ----------------------------------------------------------------------------
class_name AiLearningUtil
extends RefCounted


# Fixed-point scale shared with the whole v4 backbone (section 2.1).
const SCALE: int = 1000

# The neutral / baseline weight every role and preference starts at. Learning
# nudges around this and (MD11.5) is softly pulled back toward it.
const BASELINE_Q: int = SCALE

# Hard bounds on any learned weight, so no role can be driven to zero or blow up.
const MIN_WEIGHT_Q: int = 250      # 0.25x
const MAX_WEIGHT_Q: int = 3000     # 3.0x

# MD11.5 anti-exploit: the maximum absolute change any single weight may take in
# ONE match, and the fraction (q) by which every weight decays toward baseline
# each learning step (soft return). Both keep learning bounded and reversible.
const MAX_MATCH_DELTA_Q: int = 800         # never move more than 0.8x per match
const BASELINE_DECAY_Q: int = 60           # 6% pull toward baseline each step

# The default in-match learning rate (q) used when no profile is supplied. A
# rate of 200 means a full-success event moves a weight by up to 0.2x*strength.
const DEFAULT_RATE_Q: int = 200

# The learning-bias knob that scales the in-match rate (MD11.4).
const RATE_KNOB: String = "in_match_rate"
# The learning-bias knob that scales how much cross-match memory is trusted.
const MEMORY_KNOB: String = "memory_weight"

# Cross-match store schema version (level 2).
const MEMORY_SCHEMA_VERSION: int = 1


# --- Fixed-point helpers -----------------------------------------------------

static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	var num: int = a * b
	var half: int = c / 2
	if num >= 0:
		return (num + half) / c
	return -((-num + half) / c)


static func _clamp_q(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


# --- MD11.4: learning rate from the AiProfile -------------------------------

# Derive the in-match learning rate (q) from a profile's learning_bias. A null
# profile yields the neutral DEFAULT_RATE_Q so behaviour is unchanged when
# learning is not configured. The knob is a 0..1 float on disk; it is converted
# to fixed-point ONCE here (the single deterministic float->q boundary allowed
# by section 2.1). Higher in_match_rate -> larger, faster adaptation.
static func in_match_rate_q(profile) -> int:
	if profile == null:
		return DEFAULT_RATE_Q
	var knob: float = float(profile.learning(RATE_KNOB))
	# Map the 0..1 knob onto [0.5x .. 2.0x] of the default rate so even a low
	# learner still adapts a little and a high learner never runs away.
	var factor_q: int = 500 + int(round(knob * 1500.0))
	return _mul_div_round(DEFAULT_RATE_Q, factor_q, SCALE)


# Derive how strongly cross-match memory seeds the starting weights (q). Neutral
# (null profile) trusts memory at 1.0x.
static func memory_trust_q(profile) -> int:
	if profile == null:
		return SCALE
	var knob: float = float(profile.learning(MEMORY_KNOB))
	# 0..1 knob -> [0.0x .. 1.5x].
	return int(round(knob * 1500.0))


# --- MD11.1: Level-1 in-match reinforcement (deterministic) -----------------

# One outcome event summarising a deterministic battle result for a role.
# `role_id`  : the role that acted (RoleInferenceUtil id).
# `success_q`: 0..SCALE, how well it did (kills/value gained, from worldstate).
# `loss_q`   : 0..SCALE, how much it cost (losses taken, from worldstate).
# A single fixed-point delta is derived: reinforce on net success, weaken on
# net loss, scaled by the learning rate. Everything is integer q-math.
static func role_delta(success_q: int, loss_q: int, rate_q: int) -> int:
	var net: int = _clamp_q(success_q - loss_q, -SCALE, SCALE)
	return _mul_div_round(net, rate_q, SCALE)


# Apply a single role event to a role_weights map (role_id -> weight_q), in
# place-safe (returns a NEW dictionary; never mutates the input). Missing roles
# start at BASELINE_Q. The result is clamped to the hard weight bounds.
static func apply_role_event(role_weights: Dictionary, role_id: String, success_q: int, loss_q: int, rate_q: int) -> Dictionary:
	var out: Dictionary = role_weights.duplicate(true)
	var current: int = int(out.get(role_id, BASELINE_Q))
	var delta: int = role_delta(success_q, loss_q, rate_q)
	out[role_id] = _clamp_q(current + delta, MIN_WEIGHT_Q, MAX_WEIGHT_Q)
	return out


# Apply a list of role events, then a single soft baseline decay + per-match cap
# pass (MD11.5). `events` is an Array of {role_id, success_q, loss_q}. Iterating
# in a stable, id-sorted order keeps the fold deterministic. `base_weights` is
# the weights at match start (for the per-match delta cap). Returns the updated
# weights map.
static func apply_role_events(base_weights: Dictionary, role_weights: Dictionary, events: Array, rate_q: int) -> Dictionary:
	var out: Dictionary = role_weights.duplicate(true)
	# Deterministic order: sort events by role id, then by a stable index.
	var sorted: Array = events.duplicate()
	sorted.sort_custom(func(a, b): return str((a as Dictionary).get("role_id", "")) < str((b as Dictionary).get("role_id", "")))
	for raw in sorted:
		var ev: Dictionary = raw as Dictionary
		var role_id: String = str(ev.get("role_id", ""))
		if role_id == "":
			continue
		out = apply_role_event(out, role_id,
			int(ev.get("success_q", 0)), int(ev.get("loss_q", 0)), rate_q)
	# MD11.5: soft return to baseline + per-match delta cap on every touched key.
	out = decay_toward_baseline(out)
	out = cap_match_delta(base_weights, out)
	return out


# --- MD11.1: site / target preference reinforcement -------------------------

# Site and target preferences share the same reinforcement shape as roles: a
# stable-keyed map of key -> weight_q, nudged by a deterministic success/loss
# event. `key` is a site id (e.g. "x,y" or a region id) or a target owner id.
static func apply_pref_event(prefs: Dictionary, key: String, success_q: int, loss_q: int, rate_q: int) -> Dictionary:
	var out: Dictionary = prefs.duplicate(true)
	var current: int = int(out.get(key, BASELINE_Q))
	var delta: int = role_delta(success_q, loss_q, rate_q)
	out[key] = _clamp_q(current + delta, MIN_WEIGHT_Q, MAX_WEIGHT_Q)
	return out


static func apply_pref_events(base_prefs: Dictionary, prefs: Dictionary, events: Array, rate_q: int) -> Dictionary:
	var out: Dictionary = prefs.duplicate(true)
	var sorted: Array = events.duplicate()
	sorted.sort_custom(func(a, b): return str((a as Dictionary).get("key", "")) < str((b as Dictionary).get("key", "")))
	for raw in sorted:
		var ev: Dictionary = raw as Dictionary
		var key: String = str(ev.get("key", ""))
		if key == "":
			continue
		out = apply_pref_event(out, key,
			int(ev.get("success_q", 0)), int(ev.get("loss_q", 0)), rate_q)
	out = decay_toward_baseline(out)
	out = cap_match_delta(base_prefs, out)
	return out


# --- MD11.5: anti-exploit safeguards ----------------------------------------

# Soft return: pull every weight a fixed fraction toward BASELINE_Q. This means
# a role that stops paying off drifts back to neutral instead of staying locked
# high, and prevents any single good streak from dominating forever. Keys are
# iterated in sorted order for determinism (result order is irrelevant for a
# Dictionary, but the arithmetic is order-independent anyway).
static func decay_toward_baseline(weights: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = weights.keys()
	keys.sort()
	for k in keys:
		var w: int = int(weights[k])
		var toward: int = BASELINE_Q - w
		var step: int = _mul_div_round(toward, BASELINE_DECAY_Q, SCALE)
		out[k] = _clamp_q(w + step, MIN_WEIGHT_Q, MAX_WEIGHT_Q)
	return out


# Per-match delta cap: no weight may end a match more than MAX_MATCH_DELTA_Q away
# from where it started this match (`base_weights`). Keys absent from the base
# are measured against BASELINE_Q. Guarantees bounded, reversible learning.
static func cap_match_delta(base_weights: Dictionary, weights: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = weights.keys()
	keys.sort()
	for k in keys:
		var w: int = int(weights[k])
		var base: int = int(base_weights.get(k, BASELINE_Q))
		var lo: int = base - MAX_MATCH_DELTA_Q
		var hi: int = base + MAX_MATCH_DELTA_Q
		out[k] = _clamp_q(_clamp_q(w, lo, hi), MIN_WEIGHT_Q, MAX_WEIGHT_Q)
	return out


# --- MD11.2: worldstate round-trip (deterministic snapshot) -----------------

# Serialise the learned in-match state into a plain, sorted-key Dictionary
# suitable for the deterministic worldstate snapshot (like posture). Sorting the
# keys keeps the serialised form byte-stable for the state hasher.
static func export_state(role_weights: Dictionary, site_prefs: Dictionary, target_prefs: Dictionary) -> Dictionary:
	return {
		"roles": _sorted_copy(role_weights),
		"sites": _sorted_copy(site_prefs),
		"targets": _sorted_copy(target_prefs),
	}


# Read a snapshot back. Missing sections yield empty maps (resilience). Returns
# {roles, sites, targets}.
static func import_state(data: Dictionary) -> Dictionary:
	return {
		"roles": _sorted_copy((data.get("roles", {}) as Dictionary)),
		"sites": _sorted_copy((data.get("sites", {}) as Dictionary)),
		"targets": _sorted_copy((data.get("targets", {}) as Dictionary)),
	}


static func _sorted_copy(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = src.keys()
	keys.sort()
	for k in keys:
		out[k] = int(src[k])
	return out


# --- MD11.3: Level-2 cross-match memory (outside the sim hash) ---------------

# Build a fresh, empty cross-match memory document. Kept as a plain Dictionary
# so the caller can hand it to AiReputationStore-style JSON persistence in
# user://. It records, per (mod_id, map_id, role_id), an accumulated q-score of
# "did this role/tactic pay off here". This NEVER feeds a live decision; it only
# seeds match-start weights (identical for every peer from the same file).
static func new_memory() -> Dictionary:
	return { "version": MEMORY_SCHEMA_VERSION, "entries": {} }


static func _memory_key(mod_id: String, map_id: String, role_id: String) -> String:
	return "%s|%s|%s" % [mod_id, map_id, role_id]


# Record a cross-match outcome for a role on a mod/map. `outcome_q` is a signed
# q value (>0 the tactic helped win, <0 it lost). Returns a NEW memory document;
# never mutates the input. The stored score is clamped so a single map can never
# dominate the cross-match memory.
static func record_memory(memory: Dictionary, mod_id: String, map_id: String, role_id: String, outcome_q: int) -> Dictionary:
	var out: Dictionary = memory.duplicate(true)
	if not out.has("entries"):
		out["entries"] = {}
	var entries: Dictionary = out["entries"]
	var key: String = _memory_key(mod_id, map_id, role_id)
	var prev: int = int(entries.get(key, 0))
	entries[key] = _clamp_q(prev + outcome_q, -MAX_MATCH_DELTA_Q * 4, MAX_MATCH_DELTA_Q * 4)
	out["entries"] = entries
	return out


# MD11.3 + MD11.4: seed a match's STARTING role weights from cross-match memory.
# For each role that has memory on this mod/map, nudge its baseline by the
# remembered outcome, scaled by the profile's memory trust (memory_weight knob).
# The result is deterministic given (memory, mod_id, map_id, profile) so every
# peer that loads the same memory file computes the identical seed. Returns a
# role_id -> weight_q map ready to be the match-start baseline.
static func seed_weights_from_memory(memory: Dictionary, mod_id: String, map_id: String, role_ids: Array, memory_trust: int) -> Dictionary:
	var out: Dictionary = {}
	var entries: Dictionary = (memory.get("entries", {}) as Dictionary)
	# Stable, sorted iteration over the caller-supplied role universe.
	var sorted_roles: Array = role_ids.duplicate()
	sorted_roles.sort()
	for raw in sorted_roles:
		var role_id: String = str(raw)
		var key: String = _memory_key(mod_id, map_id, role_id)
		var remembered: int = int(entries.get(key, 0))
		var nudge: int = _mul_div_round(remembered, memory_trust, SCALE)
		out[role_id] = _clamp_q(BASELINE_Q + nudge, MIN_WEIGHT_Q, MAX_WEIGHT_Q)
	return out
