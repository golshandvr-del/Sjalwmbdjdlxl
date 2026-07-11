# gui_widget_catalog.gd
# ----------------------------------------------------------------------------
# Project Nexus - GUI widget catalog (Phase MC7.3, request 8).
#
# THE CONTRACT THIS ENFORCES:
# The GUI editor lets a user move / resize / re-icon / RENAME every button, but
# the user must NEVER be able to change what a button DOES or invent a control
# that the app cannot wire up. A widget's FUNCTION is its `logical_id`; its
# display name is pure cosmetics. This catalog is the single source of truth for
# WHICH logical_ids are valid on WHICH page, so `GuiProject` / the editor can:
#   - offer only real, wireable functions when adding a widget,
#   - reject an imported .nexgui that references an unknown function,
#   - guarantee "rename is cosmetic; function stays fixed".
#
# It is a PURE, stateless registry (no UI, no WorldState, no autoload) so it is
# fully headless-testable and can be shared by the editor, the importer, and the
# data-driven render layer (MC7.6). The logical_ids mirror the real actions in
# the current menus (main_menu.gd) and in-game HUD so the render layer can bind
# each widget to an existing handler by id.
#
# English-only identifiers/comments (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name GuiWidgetCatalog
extends RefCounted

# Canonical page names an authored GUI may target. Mirrors the app's real
# surfaces (menu panels + in-game HUD). Kept as constants so callers/tests agree.
const PAGE_MAIN: String = "main"
const PAGE_OPTIONS: String = "options"
const PAGE_MULTIPLAYER: String = "multiplayer"
const PAGE_ONLINE: String = "online"
const PAGE_IN_GAME: String = "in_game"

# The allowed logical_ids per page. Each id maps to a REAL, existing action so
# the render layer can bind it. Order here is not significant (allowed_ids
# returns them sorted for determinism).
const CATALOG: Dictionary = {
	PAGE_MAIN: [
		"single", "multiplayer", "custom_games", "mod_editor", "map_editor",
		"gui_editor", "save_load", "options", "language", "quit",
	],
	PAGE_OPTIONS: [
		"audio", "video", "controls", "language", "back",
	],
	PAGE_MULTIPLAYER: [
		"offline", "online", "back",
	],
	PAGE_ONLINE: [
		"host", "join", "back",
	],
	PAGE_IN_GAME: [
		"pause", "resume", "select", "move", "attack", "stop", "assign_group",
		"zoom_in", "zoom_out", "minimap", "build", "menu",
	],
}


# All known page names, sorted (deterministic for UI + tests).
static func page_names() -> Array:
	var names: Array = CATALOG.keys()
	names.sort()
	return names


func is_known_page(page: String) -> bool:
	return CATALOG.has(str(page).strip_edges())


# Sorted list of allowed logical_ids for a page, or [] for an unknown page.
static func allowed_ids(page: String) -> Array:
	var name: String = str(page).strip_edges()
	if not CATALOG.has(name):
		return []
	var ids: Array = (CATALOG[name] as Array).duplicate()
	ids.sort()
	return ids


# Whether `logical_id` is a valid function on `page`.
static func is_allowed(page: String, logical_id: String) -> bool:
	var name: String = str(page).strip_edges()
	if not CATALOG.has(name):
		return false
	var lid: String = str(logical_id).strip_edges()
	return (CATALOG[name] as Array).has(lid)


# Validate an authored GuiProject dictionary (to_dict shape) against the
# catalog. Returns [ok: bool, reason_key: String, bad: String] where `bad` names
# the first offending "page/logical_id" (or page) for the editor to surface.
# An unknown PAGE is allowed to pass through (custom surfaces may exist) but any
# widget with an unknown logical_id ON A KNOWN PAGE is rejected, because that is
# a function the app cannot bind.
static func validate_project_dict(data: Dictionary) -> Array:
	var pages: Variant = data.get("pages", {})
	if not (pages is Dictionary):
		return [false, "ui.guieditor.catalog_no_pages", ""]
	var page_keys: Array = (pages as Dictionary).keys()
	page_keys.sort()
	for name in page_keys:
		if not CATALOG.has(str(name)):
			continue  # unknown page: not our contract to police here
		var page: Variant = (pages as Dictionary)[name]
		if not (page is Dictionary):
			continue
		var widgets: Variant = (page as Dictionary).get("widgets", [])
		if not (widgets is Array):
			continue
		for w in (widgets as Array):
			if not (w is Dictionary):
				continue
			var lid: String = str((w as Dictionary).get("logical_id", "")).strip_edges()
			if not is_allowed(str(name), lid):
				return [false, "ui.guieditor.catalog_bad_id", "%s/%s" % [str(name), lid]]
	return [true, "", ""]
