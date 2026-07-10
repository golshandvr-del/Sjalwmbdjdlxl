# loading_stages.gd
# ----------------------------------------------------------------------------
# Project Nexus - Loading / progress stage descriptors (Phase MB10 / bug 29).
#
# The bug this supports: the game showed no loading indicator, so any wait
# (starting a match, syncing mods, saving/loading a map, scanning the LAN) made
# the app look frozen. ProgressOverlay (MB10.1) is the visual widget; THIS file
# is the pure, dependency-free brain that answers "what stages does operation X
# have, and what ratio/label is each stage?" so every caller drives the overlay
# consistently and the sequence is unit-testable headless (no SceneTree).
#
# A "plan" is an ordered Array of stage dictionaries:
#     { "ratio": float (0.0..1.0), "key": String (localization key) }
# Determinate operations list their real milestones; unknown-length operations
# expose is_indeterminate()==true and a single label key instead.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII). The "key"
# fields are localization keys the caller resolves through Localization.
# ----------------------------------------------------------------------------
class_name LoadingStages
extends RefCounted

# Canonical operation identifiers. Callers pass one of these to plan_for().
const OP_START_MATCH: String = "start_match"
const OP_ONLINE_CONNECT: String = "online_connect"
const OP_SAVE_MAP: String = "save_map"
const OP_LOAD_MAP: String = "load_map"
const OP_SAVE_MOD: String = "save_mod"
const OP_VALIDATE_IMAGE: String = "validate_image"
const OP_SCAN_NETWORK: String = "scan_network"

# Operations whose total length is unknown up front: the overlay animates in
# indeterminate mode rather than showing a misleading percentage.
const INDETERMINATE_OPS: Array = [OP_SCAN_NETWORK, OP_VALIDATE_IMAGE]

# The determinate stage plans. Each entry's ratios are non-decreasing and end at
# 1.0 so the bar always fills. Kept as data so adding a milestone is one line and
# a test guards the invariants.
const PLANS: Dictionary = {
	OP_START_MATCH: [
		{ "ratio": 0.0, "key": "ui.loading.building_match" },
		{ "ratio": 0.6, "key": "ui.loading.loading_catalogs" },
		{ "ratio": 1.0, "key": "ui.loading.entering_game" },
	],
	OP_ONLINE_CONNECT: [
		{ "ratio": 0.0, "key": "ui.loading.checking_mods" },
		{ "ratio": 0.5, "key": "ui.loading.syncing_mods" },
		{ "ratio": 1.0, "key": "ui.loading.connected" },
	],
	OP_SAVE_MAP: [
		{ "ratio": 0.0, "key": "ui.loading.saving" },
		{ "ratio": 1.0, "key": "ui.loading.saved" },
	],
	OP_LOAD_MAP: [
		{ "ratio": 0.0, "key": "ui.loading.loading" },
		{ "ratio": 1.0, "key": "ui.loading.loaded" },
	],
	OP_SAVE_MOD: [
		{ "ratio": 0.0, "key": "ui.loading.saving" },
		{ "ratio": 1.0, "key": "ui.loading.saved" },
	],
}

# Label key for indeterminate operations (no percentage, just "busy...").
const INDETERMINATE_KEYS: Dictionary = {
	OP_SCAN_NETWORK: "ui.loading.scanning_network",
	OP_VALIDATE_IMAGE: "ui.loading.validating_image",
}

# Title key shown at the top of the overlay for each operation.
const TITLE_KEYS: Dictionary = {
	OP_START_MATCH: "ui.loading.title.start_match",
	OP_ONLINE_CONNECT: "ui.loading.title.online_connect",
	OP_SAVE_MAP: "ui.loading.title.save_map",
	OP_LOAD_MAP: "ui.loading.title.load_map",
	OP_SAVE_MOD: "ui.loading.title.save_mod",
	OP_VALIDATE_IMAGE: "ui.loading.title.validate_image",
	OP_SCAN_NETWORK: "ui.loading.title.scan_network",
}


# True when `op` has no known total length and the overlay should animate in
# indeterminate mode instead of showing a percentage.
static func is_indeterminate(op: String) -> bool:
	return INDETERMINATE_OPS.has(op)


# The ordered stage plan for a determinate operation, or [] for an unknown /
# indeterminate one.
static func plan_for(op: String) -> Array:
	if is_indeterminate(op):
		return []
	return PLANS.get(op, [])


# The localization key of the title for `op` (or "" if unknown).
static func title_key(op: String) -> String:
	return str(TITLE_KEYS.get(op, ""))


# The single status-label key for an indeterminate operation (or "" otherwise).
static func indeterminate_key(op: String) -> String:
	return str(INDETERMINATE_KEYS.get(op, ""))


# The ratio of stage `index` in a determinate plan, clamped to the plan bounds.
# Safe for any index so callers can loop without bounds checks.
static func stage_ratio(op: String, index: int) -> float:
	var plan: Array = plan_for(op)
	if plan.is_empty():
		return 0.0
	var i: int = clampi(index, 0, plan.size() - 1)
	return float(plan[i].get("ratio", 0.0))


# The label key of stage `index` in a determinate plan (or "" if none).
static func stage_key(op: String, index: int) -> String:
	var plan: Array = plan_for(op)
	if plan.is_empty():
		return ""
	var i: int = clampi(index, 0, plan.size() - 1)
	return str(plan[i].get("key", ""))


# Number of milestones in a determinate operation's plan (0 for indeterminate).
static func stage_count(op: String) -> int:
	return plan_for(op).size()


# Every operation identifier this util knows about (sorted, deterministic).
static func known_ops() -> Array:
	var ops: Array = TITLE_KEYS.keys()
	ops.sort()
	return ops
