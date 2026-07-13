# unit_candidate_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI unit-production candidate assembly (Phase MD8.5, expert
# item 7). The GLUE between the data-driven catalog and the pure utility scorer
# (UnitUtilityUtil, MD8): given a plain map of unit definitions it builds the
# list of scoring candidates -- each {"id", "caps", "primary_role"} -- that
# UnitUtilityUtil.select_best consumes.
#
# Why a separate pure util (not inline in the module): the module reads the live
# DataLoader catalog, but the transformation "unit def -> capability card ->
# primary role -> candidate" is pure and deterministic, so it belongs in a
# headless-testable RefCounted helper. The module only fetches the catalog map
# and hands it here.
#
# Determinism: candidates are emitted in id-sorted order and every capability
# card is the fixed-point DerivedMetricsUtil output, so the list is byte-stable
# on every peer/replay. Backward compatible: a catalog with only "soldier"
# yields exactly one candidate, so select_best returns "soldier" unchanged.
#
# Resilience (section 2.5): a malformed / statless def still produces a
# candidate with the capability defaults and the GENERIC role, never a crash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name UnitCandidateUtil
extends RefCounted


# Build the sorted candidate list from a catalog map (unit_id -> unit_def).
# `stat_registry` / `affects` are passed straight through to DerivedMetricsUtil
# (null uses the engine builtins). `allowed_ids` (optional) restricts the set to
# currently buildable units (tech unlock / cost gate handled by the caller); an
# empty allow list means "every unit in the catalog is a candidate".
static func build_candidates(
		catalog: Dictionary,
		stat_registry: Object = null,
		affects: Variant = null,
		allowed_ids: Array = []) -> Array:
	var out: Array = []
	var ids: Array = catalog.keys()
	ids.sort_custom(func(a, b): return str(a) < str(b))
	for raw_id in ids:
		var id: String = str(raw_id)
		if not allowed_ids.is_empty() and not allowed_ids.has(id):
			continue
		var entity_def: Variant = catalog[raw_id]
		var caps: Dictionary = DerivedMetricsUtil.compute_capabilities(entity_def, stat_registry, affects)
		var role: String = RoleInferenceUtil.primary_role(caps, "unit")
		out.append({
			"id": id,
			"caps": caps,
			"primary_role": role,
		})
	return out


# Convenience wrapper: assemble candidates and delegate to the utility scorer,
# returning the chosen unit id. Returns `fallback_id` when there are no
# candidates so the AI always has something to build (backward compatibility
# with the previous always-"soldier" behaviour).
static func choose_unit(
		catalog: Dictionary,
		profile_weights: Dictionary,
		context: Dictionary,
		match_seed: int,
		tick: int,
		owner: int,
		noise_strength_q: int,
		stat_registry: Object = null,
		affects: Variant = null,
		allowed_ids: Array = [],
		fallback_id: String = "soldier") -> String:
	var candidates: Array = build_candidates(catalog, stat_registry, affects, allowed_ids)
	if candidates.is_empty():
		return fallback_id
	var chosen: String = UnitUtilityUtil.select_best(
		candidates, profile_weights, context, match_seed, tick, owner, noise_strength_q)
	if chosen == "":
		return fallback_id
	return chosen
