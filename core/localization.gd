# localization.gd
# ----------------------------------------------------------------------------
# Project Nexus - Localization Service (Phase 5, step 5.2).
#
# The single, data-driven gateway between English localization KEYS used in code
# and the localized DISPLAY TEXT shown to the player. This is the mechanism the
# CODE_POLICY mandates: code always references an English key (e.g.
# "ui.menu.start_game"); the only place non-English text exists is the
# localization/ JSON files this service loads.
#
# Usage:
#   var loc := Localization.new()
#   loc.load_all("res://localization")   # discovers en.json, fa.json, ...
#   loc.set_locale("fa")
#   label.text = loc.t("ui.menu.start_game")   # -> Persian string
#
# It is a plain RefCounted helper (no autoload required), so scenes and tests can
# each own one. Lookup falls back gracefully: requested locale -> default locale
# -> the key itself (so a missing translation is visible, never a crash).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments. The translated values
# live exclusively in localization/*.json (the one allowed exception).
# ----------------------------------------------------------------------------
class_name Localization
extends RefCounted

# The locale used when a key is missing in the active locale (always English).
const DEFAULT_LOCALE: String = "en"

# locale id -> { key: value } string tables.
var _tables: Dictionary = {}

# The currently active locale id.
var _active: String = DEFAULT_LOCALE


# Discover and load every "*.json" locale file under `dir`. Each file's locale id
# is taken from its "locale" field (falling back to the file basename). Returns
# the list of locale ids that loaded successfully.
func load_all(dir_path: String = "res://localization") -> Array:
	var loaded: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return loaded
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() == "json":
			var locale_id: String = _load_file(dir_path.path_join(name))
			if locale_id != "":
				loaded.append(locale_id)
		name = dir.get_next()
	dir.list_dir_end()
	loaded.sort()
	return loaded


# Load a single locale JSON file. Returns the locale id, or "" on failure.
func _load_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return ""
	var data: Dictionary = parsed
	var locale_id: String = str(data.get("locale", path.get_file().get_basename()))
	var strings: Dictionary = data.get("strings", {})
	var table: Dictionary = {}
	for key in strings.keys():
		table[str(key)] = str(strings[key])
	_tables[locale_id] = table
	return locale_id


# Make `locale_id` active for subsequent t() calls. Returns true if the locale is
# loaded; false (and no change) if it is unknown.
func set_locale(locale_id: String) -> bool:
	if not _tables.has(locale_id):
		return false
	_active = locale_id
	return true


func active_locale() -> String:
	return _active


# All loaded locale ids (sorted, deterministic).
func available_locales() -> Array:
	var ids: Array = _tables.keys()
	ids.sort()
	return ids


# Translate an English key into the active locale's display text. Falls back to
# the default locale, then to the key itself so missing strings are obvious.
func t(key: String) -> String:
	var active_table: Dictionary = _tables.get(_active, {})
	if active_table.has(key):
		return str(active_table[key])
	var default_table: Dictionary = _tables.get(DEFAULT_LOCALE, {})
	if default_table.has(key):
		return str(default_table[key])
	return key


# True when the active locale actually defines this key (no fallback used).
func has_key(key: String) -> bool:
	return (_tables.get(_active, {}) as Dictionary).has(key)


# Cycle to the next available locale (handy for a single on-screen toggle).
# Returns the now-active locale id.
func cycle_locale() -> String:
	var ids: Array = available_locales()
	if ids.is_empty():
		return _active
	var idx: int = ids.find(_active)
	var next_idx: int = (idx + 1) % ids.size()
	_active = str(ids[next_idx])
	return _active
