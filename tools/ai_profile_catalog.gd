# ai_profile_catalog.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI profile catalog (Phase MC12, step 12.2, request 13).
#
# A thin, PURE helper that knows about the built-in ("default") AI personality
# profiles shipped in `res://data/ai_profiles/*.json` and turns them into
# `AiProfile` objects. It exists so match setup / the AI builder (MC14) can list
# and load the nine historical generals without duplicating file paths, and so
# the set is unit-testable headlessly.
#
# The nine defaults (from docs/plan_android_fix_v3.md MC12.2), in a STABLE
# alphabetical order (deterministic listing):
#   alaric, alexander, bismarck, caesar, cyrus, fabius, genghis, hannibal,
#   talleyrand.
#
# Design rules:
#   - PURE: no WorldState / SceneTree state. It only reads JSON via a supplied
#     DataLoader-like reader (dependency injection) so tests can feed a stub and
#     avoid real file IO, while production passes a real DataLoader.
#   - DETERMINISTIC: ids() returns a fixed sorted list; load_all() iterates it in
#     order. Same inputs -> same outputs.
#   - SAFE: a missing / malformed file yields the neutral default_profile() for
#     that id rather than crashing, so the game always has a usable roster.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiProfileCatalog
extends RefCounted

# Directory the built-in profiles live in.
const PROFILE_DIR: String = "res://data/ai_profiles"

# The canonical, stable-ordered list of built-in profile ids.
const DEFAULT_IDS: Array = [
	"alaric",
	"alexander",
	"bismarck",
	"caesar",
	"cyrus",
	"fabius",
	"genghis",
	"hannibal",
	"talleyrand",
]


# The stable list of built-in profile ids.
static func ids() -> Array:
	return DEFAULT_IDS.duplicate()


# The res:// path of a built-in profile's JSON file.
static func path_for(id: String) -> String:
	return "%s/%s.json" % [PROFILE_DIR, str(id).strip_edges()]


# Build an AiProfile for one id, reading its JSON through `reader`. `reader` is
# any object exposing `load_json_file(path) -> Variant` (a DataLoader or a test
# stub). A missing / non-Dictionary payload falls back to a neutral profile that
# still carries the requested id, so callers never get null.
static func load_profile(id: String, reader: Object) -> AiProfile:
	var clean_id: String = str(id).strip_edges()
	var payload: Variant = null
	if reader != null and reader.has_method("load_json_file"):
		payload = reader.load_json_file(path_for(clean_id))
	if payload is Dictionary and not (payload as Dictionary).is_empty():
		var data: Dictionary = (payload as Dictionary).duplicate(true)
		# Trust the file's own id if present, else stamp the requested one.
		if not data.has("id") or str(data["id"]).strip_edges().is_empty():
			data["id"] = clean_id
		var p: AiProfile = AiProfile.from_dict(data)
		if p.is_valid():
			return p
	# Fallback: a neutral profile stamped with this id.
	var fallback: AiProfile = AiProfile.default_profile()
	fallback.load({"id": clean_id, "archetype": "balanced"})
	return fallback


# Load every built-in profile, in DEFAULT_IDS order, as an Array[AiProfile].
static func load_all(reader: Object) -> Array:
	var out: Array = []
	for id in DEFAULT_IDS:
		out.append(load_profile(id, reader))
	return out
