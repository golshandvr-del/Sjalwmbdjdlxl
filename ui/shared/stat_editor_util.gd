# stat_editor_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Data-driven Stat editor helper (plan v4, phase MD12.1).
#
# The Mod Editor's stat picker must be built DYNAMICALLY from the data-driven
# StatRegistry (section MD1/MD2), not from a hand-coded list of three fields.
# This PURE, headless-testable util produces the *plan* the UI renders:
#
#   catalog ("unit"/"building"/"object")
#       --StatRegistry.ids_for + per-stat metadata-->
#   a list of stat descriptors, GROUPED BY `category`, and PAGINATED so a phone
#   screen never has to show more than a fixed cap of controls at once.
#
# Design rules (Definition of Done, plan section 2 constant principles):
#   - PURE INFRASTRUCTURE: RefCounted, no SceneTree / WorldState / sim-hash
#     dependency. It only DESCRIBES what the editor should draw. The editor
#     (ui/shared/mod_editor.gd, MD12.2) turns each descriptor into a widget.
#   - DETERMINISTIC: ids are emitted in a stable order (stat ids sorted inside
#     each group; groups sorted by category id) so the same query always yields
#     byte-for-byte the same layout -- friendly to UI diffing and to tests.
#   - COSMETIC (section 2.2): the descriptors carry no simulation state and this
#     util never touches state_hasher. It reads metadata only.
#   - RESILIENCE (section 2.5): an unknown catalog / a stat missing metadata
#     never crashes -- it degrades to sensible defaults (int, category "misc").
#   - English-only identifiers/comments (CODE_POLICY); any author-facing label
#     the UI shows is resolved by the caller through Localization
#     (key `stat.<id>.name`, MD12.5) with the raw id as the fallback.
# ----------------------------------------------------------------------------
class_name StatEditorUtil
extends RefCounted

# Category id used when a stat declares no category (resilient fallback).
const MISC_CATEGORY: String = "misc"

# Default per-page cap tuned for a phone screen. The editor may pass its own cap
# (e.g. a larger one on tablets) but this is the safe mobile default.
const DEFAULT_PAGE_SIZE: int = 8


# A single stat descriptor the editor turns into one control. Everything the UI
# needs is here so the view stays thin (MD12.2). `registry` is StatRegistry (or a
# stub exposing the same static getters); may be null -> pure fallbacks apply.
static func describe_stat(id: String, registry: Object = null) -> Dictionary:
	var sid: String = str(id)
	var out: Dictionary = {
		"id": sid,
		"name_key": "stat.%s.name" % sid,
		"value_type": "int",
		"category": MISC_CATEGORY,
		"min": 0.0,
		"max": 0.0,
		"default": 0,
		"needs_value": true,
		"core": false,
	}
	if registry == null:
		return out
	if registry.has_method("value_type"):
		out["value_type"] = str(registry.call("value_type", sid))
	if registry.has_method("category"):
		var cat: String = str(registry.call("category", sid))
		out["category"] = cat if cat != "" else MISC_CATEGORY
	if registry.has_method("min_of"):
		out["min"] = float(registry.call("min_of", sid))
	if registry.has_method("max_of"):
		out["max"] = float(registry.call("max_of", sid))
	if registry.has_method("default_value"):
		out["default"] = registry.call("default_value", sid)
	if registry.has_method("needs_value"):
		out["needs_value"] = bool(registry.call("needs_value", sid))
	if registry.has_method("is_core"):
		out["core"] = bool(registry.call("is_core", sid))
	return out


# The sorted list of stat ids valid for a catalog ("unit"/"building"/"object").
# Delegates the applies_to filtering to the registry so there is one source of
# truth. Returns [] for a null registry or an unknown catalog. Deterministic.
static func stat_ids_for(catalog: String, registry: Object = null) -> Array:
	if registry == null or not registry.has_method("ids_for"):
		return []
	var ids: Array = registry.call("ids_for", str(catalog))
	if not (ids is Array):
		return []
	var out: Array = []
	for id in ids:
		out.append(str(id))
	out.sort()
	return out


# The full descriptor list for a catalog, stat ids sorted (deterministic).
static func descriptors_for(catalog: String, registry: Object = null) -> Array:
	var out: Array = []
	for id in stat_ids_for(catalog, registry):
		out.append(describe_stat(id, registry))
	return out


# Group a catalog's stats by `category`. Returns an Array of groups, each
#   { "category": String, "stats": Array<descriptor> }
# sorted by category id ASC; within each group the stats keep their sorted-id
# order. This is what the editor renders as collapsible sections. Deterministic.
static func groups_for(catalog: String, registry: Object = null) -> Array:
	var by_cat: Dictionary = {}   # category -> Array<descriptor>
	for desc in descriptors_for(catalog, registry):
		var cat: String = str((desc as Dictionary).get("category", MISC_CATEGORY))
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(desc)
	var cats: Array = by_cat.keys()
	cats.sort()
	var out: Array = []
	for cat in cats:
		out.append({ "category": str(cat), "stats": by_cat[cat] })
	return out


# The sorted list of distinct category ids present in a catalog. Deterministic.
static func categories_for(catalog: String, registry: Object = null) -> Array:
	var out: Array = []
	for group in groups_for(catalog, registry):
		out.append(str((group as Dictionary).get("category", MISC_CATEGORY)))
	return out


# Paginate a flat descriptor list for a mobile screen. `page` is 0-based; a page
# out of range yields an empty page (never crashes). `page_size` clamps to >= 1.
# Returns { "page": int, "page_count": int, "page_size": int, "total": int,
#           "stats": Array<descriptor> } so the editor can draw prev/next + a
# "page X of N" label with no extra math. Deterministic.
static func paginate(descriptors: Array, page: int, page_size: int = DEFAULT_PAGE_SIZE) -> Dictionary:
	var size: int = page_size if page_size >= 1 else 1
	var total: int = descriptors.size()
	var page_count: int = int((total + size - 1) / size) if total > 0 else 1
	var p: int = page
	if p < 0:
		p = 0
	if p >= page_count:
		p = page_count - 1
	var start: int = p * size
	var stats: Array = []
	var i: int = start
	while i < start + size and i < total:
		stats.append(descriptors[i])
		i += 1
	return {
		"page": p,
		"page_count": page_count,
		"page_size": size,
		"total": total,
		"stats": stats,
	}


# Convenience: paginate a whole catalog's flat descriptor list in one call.
static func paginate_catalog(catalog: String, registry: Object, page: int, page_size: int = DEFAULT_PAGE_SIZE) -> Dictionary:
	return paginate(descriptors_for(catalog, registry), page, page_size)
