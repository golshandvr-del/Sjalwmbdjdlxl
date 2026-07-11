# icon_service.gd
# ----------------------------------------------------------------------------
# Project Nexus - UI Icon Service (Phase MC3, req 3).
#
# The engine-facing half of the data-driven icon system. It loads the icon
# manifest (data/ui_icons/manifest.json) via the pure IconManifestUtil, then
# resolves a LOGICAL icon name (e.g. "settings_gear") to a Texture2D:
#
#   1. If the manifest maps the name to a file that EXISTS, load and return it.
#   2. Otherwise return a procedurally-drawn RGBA8 fallback glyph so the UI is
#      never blank and an exported build never breaks on a missing art file.
#
# The fallback glyphs are simple (a colored shape per name) and drawn in an
# RGBA8 image -- GL-Compatibility friendly, so they never trigger the
# "RGBAFloat not supported" warning (bug 28). Real art (per
# docs/ASSET_PROMPTS_fa.md) can replace the files later with zero code change.
#
# Logic/Render Separation: cosmetic only. Icons never touch WorldState or the
# deterministic hash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name IconService
extends RefCounted

const DEFAULT_MANIFEST_PATH: String = "res://data/ui_icons/manifest.json"

# The fallback glyph size (px). Small: it is only a placeholder until real art
# lands, and buttons scale it with expand_icon.
const FALLBACK_SIZE: int = 48

var _manifest: Dictionary = {}
# Cache resolved textures by logical name so repeated lookups are cheap and the
# same fallback image is reused.
var _cache: Dictionary = {}


# Load the manifest from `path` (defaults to the bundled manifest). Safe to call
# with a missing/invalid file: the service then serves only fallback glyphs.
func load_manifest(path: String = DEFAULT_MANIFEST_PATH) -> void:
	_manifest = {}
	_cache.clear()
	if not FileAccess.file_exists(path):
		return
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_manifest = parsed


# The parsed manifest (may be empty if not loaded / invalid).
func manifest() -> Dictionary:
	return _manifest


# True if the manifest declares logical icon `name`.
func has_icon(name: String) -> bool:
	return IconManifestUtil.has_icon(_manifest, name)


# True if `name` resolves to a REAL art file on disk (not a fallback glyph).
func has_real_art(name: String) -> bool:
	var path: String = IconManifestUtil.path_for(_manifest, name)
	return path != "" and FileAccess.file_exists(path)


# Resolve logical icon `name` to a Texture2D. Returns the manifest art file if it
# exists, otherwise a drawn fallback glyph. Never returns null.
func icon_texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var tex: Texture2D = null
	var path: String = IconManifestUtil.path_for(_manifest, name)
	if path != "" and FileAccess.file_exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			tex = loaded
	if tex == null:
		tex = _build_fallback(name)
	_cache[name] = tex
	return tex


# Apply logical icon `name` to `button` (icon-only). Clears the button text so
# the icon stands alone and enables expand so it scales to the button.
func apply_to_button(button: Button, name: String) -> void:
	if button == null:
		return
	button.icon = icon_texture(name)
	button.expand_icon = true


# --- Fallback glyphs --------------------------------------------------------

# A deterministic per-name color so different logical icons get visually
# distinct fallback glyphs (hash of the name -> hue-ish RGB). Pure.
func _fallback_color(name: String) -> Color:
	var h: int = abs(name.hash())
	var r: float = float((h >> 0) & 0xFF) / 255.0
	var g: float = float((h >> 8) & 0xFF) / 255.0
	var b: float = float((h >> 16) & 0xFF) / 255.0
	# Keep it reasonably bright so it reads on a dark HUD.
	return Color(0.35 + 0.5 * r, 0.35 + 0.5 * g, 0.35 + 0.5 * b, 1.0)


# Draw a simple filled rounded square glyph in an RGBA8 image as the fallback.
func _build_fallback(name: String) -> Texture2D:
	var size: int = FALLBACK_SIZE
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var color: Color = _fallback_color(name)
	var margin: int = int(float(size) * 0.15)
	var radius: float = float(size) * 0.18
	for y in range(size):
		for x in range(size):
			if x < margin or y < margin or x >= size - margin or y >= size - margin:
				continue
			# Round the corners so the placeholder looks intentional.
			var cx: float = clamp(float(x), float(margin) + radius, float(size - margin) - radius)
			var cy: float = clamp(float(y), float(margin) + radius, float(size - margin) - radius)
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			if dx * dx + dy * dy <= radius * radius or (dx == 0.0 and dy == 0.0):
				img.set_pixel(x, y, color)
			elif abs(dx) < 0.5 or abs(dy) < 0.5:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
