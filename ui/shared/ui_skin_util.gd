# ui_skin_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - UI Skin util (GUI overhaul, data-driven look).
#
# PURE, dependency-free logic for the moddable UI skin. A skin is a plain
# Dictionary (loaded from JSON) describing:
#
#   {
#     "schema": "nexus_ui_skin_v1",
#     "id": "base",
#     "palette":     { "bg": "#0e1219", "accent": "#3d6fb4", ... },
#     "button":      { "corner_radius": 6, "border_width": 1, "min_height": 44 },
#     "panel":       { "corner_radius": 10, "border_width": 1 },
#     "logo":        "textures/ui/logo.png",
#     "backgrounds": {
#        "default":   { "top": "#141a26", "bottom": "#090c12",
#                       "image": "textures/ui/bg_default.png",
#                       "overlay": "textures/ui/grid_overlay.png",
#                       "vignette": 0.55, "grid": 48 },
#        "main_menu": { ... per-screen override, merged over "default" ... }
#     }
#   }
#
# Screens are identified by their scene file stem ("main_menu", "options_menu",
# "game_main", ...). Mods ship `<mod>/ui_skin/skin.json` which is DEEP-MERGED
# over the base skin (later mods win), and any image path is resolved through
# TextureService roots so a mod can also override just the art.
#
# Everything here is deterministic and headless-testable; the engine-facing
# half (building a Theme / background node) is UiSkinService.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name UiSkinUtil
extends RefCounted

const SCHEMA: String = "nexus_ui_skin_v1"

# The built-in skin. It is the LAST fallback: a project ships data/ui_skin/
# skin.json (which normally mirrors this), and mods override on top.
const DEFAULT_SKIN: Dictionary = {
	"schema": SCHEMA,
	"id": "builtin",
	"palette": {
		"bg": "#0e1219",
		"panel": "#161c27",
		"panel_border": "#2a3446",
		"accent": "#3d6fb4",
		"accent_hover": "#4d84d4",
		"accent_pressed": "#2c5290",
		"accent_disabled": "#2a3140",
		"text": "#e0e8f2",
		"text_dim": "#9aa7ba",
		"title": "#e1be57",
		"danger": "#c95a4a",
		"success": "#5fb86a",
		"field": "#0b0f16",
	},
	"button": { "corner_radius": 6, "border_width": 1, "min_height": 44, "font_size": 16 },
	"panel": { "corner_radius": 10, "border_width": 1 },
	"logo": "textures/ui/logo.png",
	"backgrounds": {
		"default": {
			"top": "#141a26",
			"bottom": "#090c12",
			"image": "textures/ui/bg_default.png",
			"overlay": "",
			"vignette": 0.55,
			"grid": 48,
			"grid_alpha": 0.06,
		},
		"main_menu": { "image": "textures/ui/bg_main_menu.png", "vignette": 0.65 },
		"match_setup": { "image": "textures/ui/bg_match_setup.png" },
		"options_menu": { "image": "textures/ui/bg_options.png" },
		"lobby": { "image": "textures/ui/bg_lobby.png" },
		"editor_hub": { "image": "textures/ui/bg_editor.png" },
		"editor_defaults": { "image": "textures/ui/bg_editor.png" },
		"map_editor": { "image": "textures/ui/bg_editor.png", "vignette": 0.3 },
		"mod_editor": { "image": "textures/ui/bg_editor.png", "vignette": 0.3 },
		"gui_editor": { "image": "textures/ui/bg_editor.png", "vignette": 0.3 },
		"ai_builder": { "image": "textures/ui/bg_editor.png", "vignette": 0.3 },
		"custom_games": { "image": "textures/ui/bg_match_setup.png" },
		"save_load_menu": { "image": "textures/ui/bg_options.png" },
		"game_main": { "image": "", "top": "#0b0e14", "bottom": "#05070a", "vignette": 0.0, "grid": 0 },
		"game_desktop": { "image": "", "top": "#0b0e14", "bottom": "#05070a", "vignette": 0.0, "grid": 0 },
	},
}


# True when `raw` looks like a skin document (schema tag + dictionary).
static func is_valid(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var d: Dictionary = raw
	return str(d.get("schema", "")) == SCHEMA


# Deep-merge `over` onto a COPY of `base`: nested dictionaries merge key by
# key, every other value is replaced. Neither input is mutated. Deterministic.
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	var keys: Array = over.keys()
	keys.sort()
	for key in keys:
		var value: Variant = over[key]
		if value is Dictionary and out.get(key) is Dictionary:
			out[key] = merge(out[key], value)
		else:
			out[key] = value.duplicate(true) if (value is Dictionary or value is Array) else value
	return out


# Merge an ordered list of skin layers over DEFAULT_SKIN. Invalid layers are
# skipped (never crash on a broken mod file).
static func resolve(layers: Array) -> Dictionary:
	var skin: Dictionary = DEFAULT_SKIN.duplicate(true)
	for layer in layers:
		if is_valid(layer):
			skin = merge(skin, layer)
	return skin


# Parse a "#rrggbb" / "#rrggbbaa" string; `fallback` on anything invalid.
static func color(raw: Variant, fallback: Color) -> Color:
	var text: String = str(raw).strip_edges()
	if text == "":
		return fallback
	# Only hex forms are accepted ("#rgb", "#rrggbb", "#rrggbbaa"); named
	# colours are rejected up-front so Color.html never logs an engine error
	# for an arbitrary mod string.
	if not text.begins_with("#"):
		return fallback
	if Color.html_is_valid(text):
		return Color.html(text)
	return fallback


# A palette colour by name (falls back to the built-in palette, then `fallback`).
static func palette_color(skin: Dictionary, name: String, fallback: Color = Color.MAGENTA) -> Color:
	var palette: Dictionary = skin.get("palette", {})
	var builtin: Dictionary = DEFAULT_SKIN["palette"]
	return color(palette.get(name, builtin.get(name, "")), fallback)


# The fully-resolved background spec for one screen: the "default" entry with
# the per-screen entry merged over it. Unknown screens get "default".
static func background_for(skin: Dictionary, screen_id: String) -> Dictionary:
	var all: Dictionary = skin.get("backgrounds", {})
	var base: Dictionary = DEFAULT_SKIN["backgrounds"]["default"].duplicate(true)
	if all.get("default") is Dictionary:
		base = merge(base, all["default"])
	if screen_id != "" and all.get(screen_id) is Dictionary:
		base = merge(base, all[screen_id])
	return base


# Screen id for a scene path: "res://scenes/main_menu.tscn" -> "main_menu".
static func screen_id_for(scene_path: String) -> String:
	return scene_path.get_file().get_basename()


# Integer / float readers with clamping so a broken mod value can never yield
# a negative radius or a NaN vignette.
static func int_of(section: Dictionary, key: String, fallback: int, lo: int = 0, hi: int = 4096) -> int:
	var v: Variant = section.get(key, fallback)
	if v is int or v is float:
		return clampi(int(v), lo, hi)
	return fallback


static func float_of(section: Dictionary, key: String, fallback: float, lo: float = 0.0, hi: float = 1.0) -> float:
	var v: Variant = section.get(key, fallback)
	if v is int or v is float:
		var f: float = float(v)
		if is_nan(f):
			return fallback
		return clampf(f, lo, hi)
	return fallback
