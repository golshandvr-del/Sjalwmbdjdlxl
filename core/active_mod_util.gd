# active_mod_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pure helpers for the "current mods" management screen (Phase
# MC6, request 7). The user wants to: (1) see the mods discovered on disk, (2)
# toggle which ones are ENABLED, (3) pick ONE "main" mod, and (4) have both
# selections PERSIST across sessions. This util owns only the deterministic
# list/selection LOGIC; GameSettings owns persistence (MC6.2) and the menu
# scene owns the widgets (MC6.3).
#
# Design (consistent with CatalogListUtil / OwnershipUtil):
#   - PURE + dependency-free: no Nexus autoload, no SceneTree, no file IO. It
#     takes the plain Array of manifest dictionaries that ModLoader.discover_mods
#     returns (each has at least an "id" String; optional "enabled", "_dir",
#     "name"/"display_name_key") plus the persisted selection, and returns
#     deterministic, id-sorted results.
#   - DETERMINISTIC: every list is sorted by id so the UI and any test are stable
#     across machines. This tooling never touches the simulation hash.
#   - FAIL-SAFE: a persisted selection that references a mod no longer on disk is
#     silently dropped (sanitise); an empty/foreign main id resolves to "".
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name ActiveModUtil
extends RefCounted


# Turn the ModLoader.discover_mods() output into a stable, UI-ready Array of
# small dictionaries: { "id", "name_key", "enabled", "is_main" }. `enabled`
# reflects the persisted active list (falling back to the manifest's own
# "enabled" default when the persisted list is empty/unknown), and `is_main`
# marks the single chosen main mod. Sorted by id for determinism.
static func list_mods(discovered: Array, active_ids: Array = [], main_id: String = "") -> Array:
	var active_set: Dictionary = _to_set(active_ids)
	var has_active: bool = not active_set.is_empty()
	var rows: Array = []
	for manifest in discovered:
		if not (manifest is Dictionary):
			continue
		var m: Dictionary = manifest as Dictionary
		var id: String = str(m.get("id", ""))
		if id == "":
			continue
		# When a persisted active list exists it is authoritative; otherwise fall
		# back to the manifest's own enabled flag (default true).
		var enabled: bool = active_set.has(id) if has_active else bool(m.get("enabled", true))
		rows.append({
			"id": id,
			"name_key": _name_key_for(m, id),
			"enabled": enabled,
			"is_main": id == main_id and main_id != "",
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return rows


# The sorted list of ids that exist on disk (deterministic). Handy for the menu
# and for sanitising a persisted selection.
static func discovered_ids(discovered: Array) -> Array:
	var ids: Array = []
	for manifest in discovered:
		if manifest is Dictionary:
			var id: String = str((manifest as Dictionary).get("id", ""))
			if id != "":
				ids.append(id)
	ids.sort()
	return ids


# Drop any id from `active_ids` that no longer exists on disk, de-duplicate, and
# return a sorted list. This keeps a persisted selection honest when a mod is
# deleted between sessions.
static func sanitise_active(active_ids: Array, discovered: Array) -> Array:
	var exists: Dictionary = _to_set(discovered_ids(discovered))
	var seen: Dictionary = {}
	var out: Array = []
	for raw in active_ids:
		var id: String = str(raw)
		if id != "" and exists.has(id) and not seen.has(id):
			seen[id] = true
			out.append(id)
	out.sort()
	return out


# Resolve the "main" mod id against what is actually enabled+present. Returns ""
# when the requested main id is empty, missing on disk, or not enabled. This is
# what the loader/UI should treat as the effective main mod.
static func resolve_main(main_id: String, active_ids: Array, discovered: Array) -> String:
	var id: String = main_id.strip_edges()
	if id == "":
		return ""
	var clean_active: Dictionary = _to_set(sanitise_active(active_ids, discovered))
	if clean_active.has(id):
		return id
	return ""


# Toggle a single mod id in an active list, returning the new sorted list.
# Adding an unknown-on-disk id is refused (returns the input unchanged) so the
# selection can never drift from reality.
static func toggle(active_ids: Array, id: String, discovered: Array) -> Array:
	var clean: String = id.strip_edges()
	if clean == "":
		return sanitise_active(active_ids, discovered)
	var exists: Dictionary = _to_set(discovered_ids(discovered))
	var current: Dictionary = _to_set(sanitise_active(active_ids, discovered))
	if current.has(clean):
		current.erase(clean)
	elif exists.has(clean):
		current[clean] = true
	var out: Array = current.keys()
	out.sort()
	return out


# Whether a given id is currently enabled in the (sanitised) active list.
static func is_active(active_ids: Array, id: String, discovered: Array) -> bool:
	return _to_set(sanitise_active(active_ids, discovered)).has(id.strip_edges())


# --- internals --------------------------------------------------------------

# A manifest's display name key falls back to the raw id when absent, matching
# CatalogListUtil so the menu can localise or show the id verbatim.
static func _name_key_for(manifest: Dictionary, id: String) -> String:
	var key: String = str(manifest.get("display_name_key", ""))
	if key == "":
		key = str(manifest.get("name", ""))
	if key == "":
		key = id
	return key


# Build a set (Dictionary with true values) from an Array of ids, ignoring
# blanks. Used for O(1) membership checks without disturbing order.
static func _to_set(ids: Array) -> Dictionary:
	var s: Dictionary = {}
	for raw in ids:
		var id: String = str(raw)
		if id != "":
			s[id] = true
	return s
