# catalog_list_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pure helpers to turn a loaded DataLoader catalog (units,
# buildings, ...) into a stable, UI-ready list for the Map Editor's SEPARATE
# "Units" and "Buildings" sections (Phase MB7.4, bug 21b: the editor used one
# generic "unit" tool; the user asked for two distinct sections that list the
# actual unit/building types of the loaded mod so any of them can be placed).
#
# Pure + dependency-free (no Nexus autoload, no SceneTree): it takes a plain
# catalog Dictionary (id-string -> entry Dictionary) and returns a deterministic,
# id-sorted Array of small {id, name_key} dictionaries. Sorting by id keeps the
# UI stable and lockstep-irrelevant (editor tooling never touches the sim hash).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name CatalogListUtil
extends RefCounted


# Turn a catalog Dictionary (id -> entry) into a sorted Array of
# { "id": String, "name_key": String } entries. `name_key` falls back to the id
# when an entry carries no display_name_key. Ids are sorted ascending so the list
# is deterministic across machines / runs.
static func list_entries(catalog: Dictionary) -> Array:
	var ids: Array = catalog.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var entry: Variant = catalog[id]
		var name_key: String = ""
		if entry is Dictionary:
			name_key = str((entry as Dictionary).get("display_name_key", ""))
		if name_key == "":
			name_key = str(id)
		out.append({ "id": str(id), "name_key": name_key })
	return out


# Just the ids (sorted) -- handy when the caller only needs to know which types
# exist (e.g. to pick a sensible default place-tool type).
static func list_ids(catalog: Dictionary) -> Array:
	var out: Array = []
	for e in list_entries(catalog):
		out.append(str(e.get("id", "")))
	return out


# The first id in the sorted catalog, or `fallback` when the catalog is empty.
# Used to seat a valid default type for the Units / Buildings place tools.
static func first_id(catalog: Dictionary, fallback: String) -> String:
	var ids: Array = list_ids(catalog)
	if ids.is_empty():
		return fallback
	return str(ids[0])
