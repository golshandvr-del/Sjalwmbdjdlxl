# ai_reputation_store.gd
# ----------------------------------------------------------------------------
# Project Nexus - Level-2 (cross-match, persistent) AI reputation (Phase
# MC13.3, request 15).
#
# The SLOW, remembered layer of AI adaptation. It survives between matches and
# is kept strictly SEPARATE from the AI personality (MC12), which never changes,
# and from the in-match learning scratch-pad (MC13.2), which is wiped every
# game. This store answers "historically, how has this player treated me / each
# other across the games we have played?".
#
# For every ORDERED pair of owners we tally:
#   * betrayals : how many times the SECOND owner betrayed the FIRST.
#   * helps     : how many times the SECOND owner honoured a treaty / sent aid.
# The derived REPUTATION is a single number in [-1, +1]:
#   +1 = a proven reliable partner, -1 = a serial backstabber, 0 = unknown.
#
# DESIGN RULES (project constitution):
#   * The reputation MATH is pure + deterministic (same tallies -> same score),
#     so the AI diplomacy brain (MC13.1) can consume it in lockstep. Reputation
#     is read at match start and is CONSTANT during a match, so it never breaks
#     determinism mid-game.
#   * File IO is isolated to save_to_file / load_from_file. The core logic works
#     on an in-memory Dictionary that tests inject directly (import_dict) -- NO
#     real disk access is required to test the store.
#   * memory_weight from the profile scales HOW MUCH reputation matters to a
#     given AI, but that scaling is applied by the consumer; the store itself
#     just reports the raw reputation.
#   * English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiReputationStore
extends RefCounted

# Default on-disk location (user-writable, per platform).
const DEFAULT_PATH: String = "user://ai_reputation.json"

# The schema version stored in the file, so future migrations are possible.
const SCHEMA_VERSION: int = 1

# How many total interactions it takes for reputation to reach full confidence.
# Below this the score is damped toward 0 (a single data point is not proof).
const CONFIDENCE_SPAN: float = 5.0

# owner_key(from) -> owner_key(to) -> { "betrayals": int, "helps": int }
var _pairs: Dictionary = {}


# --- Ordered pair key -------------------------------------------------------
# Reputation is DIRECTIONAL (A's view of B differs from B's view of A), so
# unlike RelationshipUtil.pair_key this keeps the order.
static func directed_key(from_owner: int, to_owner: int) -> String:
	return str(from_owner) + ">" + str(to_owner)


# --- Recording --------------------------------------------------------------

func _entry(from_owner: int, to_owner: int) -> Dictionary:
	var key: String = directed_key(from_owner, to_owner)
	if not _pairs.has(key):
		_pairs[key] = {"betrayals": 0, "helps": 0}
	return _pairs[key]


# Record that `to_owner` betrayed `from_owner` (broke a treaty / backstabbed).
func record_betrayal(from_owner: int, to_owner: int) -> void:
	var e: Dictionary = _entry(from_owner, to_owner)
	e["betrayals"] = int(e.get("betrayals", 0)) + 1


# Record that `to_owner` behaved well toward `from_owner` (kept a treaty / aided).
func record_help(from_owner: int, to_owner: int) -> void:
	var e: Dictionary = _entry(from_owner, to_owner)
	e["helps"] = int(e.get("helps", 0)) + 1


# --- Query ------------------------------------------------------------------

func betrayals(from_owner: int, to_owner: int) -> int:
	var key: String = directed_key(from_owner, to_owner)
	if not _pairs.has(key):
		return 0
	return int(_pairs[key].get("betrayals", 0))


func helps(from_owner: int, to_owner: int) -> int:
	var key: String = directed_key(from_owner, to_owner)
	if not _pairs.has(key):
		return 0
	return int(_pairs[key].get("helps", 0))


# The reputation of `to_owner` in the eyes of `from_owner`, in [-1, +1]. It is
# (helps - betrayals) / total, damped by a confidence factor so a handful of
# interactions cannot slam the score to the extremes.
func reputation(from_owner: int, to_owner: int) -> float:
	var b: int = betrayals(from_owner, to_owner)
	var h: int = helps(from_owner, to_owner)
	var total: int = b + h
	if total <= 0:
		return 0.0
	var raw: float = float(h - b) / float(total)
	var confidence: float = clampf(float(total) / CONFIDENCE_SPAN, 0.0, 1.0)
	return clampf(raw * confidence, -1.0, 1.0)


# --- Serialisation (pure, no IO) --------------------------------------------

# A plain, JSON-safe snapshot of the whole store.
func export_dict() -> Dictionary:
	var pairs_copy: Dictionary = {}
	for key in _pairs.keys():
		var e: Dictionary = _pairs[key]
		pairs_copy[key] = {
			"betrayals": int(e.get("betrayals", 0)),
			"helps": int(e.get("helps", 0)),
		}
	return {"version": SCHEMA_VERSION, "pairs": pairs_copy}


# Replace the store contents from a dictionary (as produced by export_dict or
# parsed from disk). Unknown / malformed entries are skipped, never crash.
func import_dict(data: Dictionary) -> void:
	_pairs = {}
	var pairs: Variant = data.get("pairs", {})
	if not (pairs is Dictionary):
		return
	for key in (pairs as Dictionary).keys():
		var e: Variant = (pairs as Dictionary)[key]
		if not (e is Dictionary):
			continue
		var b: int = int((e as Dictionary).get("betrayals", 0))
		var h: int = int((e as Dictionary).get("helps", 0))
		_pairs[str(key)] = {"betrayals": max(0, b), "helps": max(0, h)}


# Wipe everything (e.g. a "forget history" option). Personality is untouched --
# it lives elsewhere.
func clear() -> void:
	_pairs = {}


# --- File IO (thin wrappers over the pure core) -----------------------------

func save_to_file(path: String = DEFAULT_PATH) -> bool:
	# Atomic write: reputation history persists across matches; a torn file
	# would silently erase every AI relationship the player has built.
	if not SafeFileUtil.write_text(path, JSON.stringify(export_dict(), "\t")):
		push_error("AiReputationStore: cannot open '%s' for writing" % path)
		return false
	return true


# A missing file is NOT an error (first run): the store stays empty.
func load_from_file(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		clear()
		return true
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("AiReputationStore: cannot open '%s' for reading" % path)
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("AiReputationStore: invalid file '%s' -- ignoring" % path)
		clear()
		return false
	import_dict(parsed as Dictionary)
	return true
