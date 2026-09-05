# texture_service.gd
# ----------------------------------------------------------------------------
# Project Nexus - Texture Service (Phase B, step B.2).
#
# A small, lazy, cached texture loader that backs the data-driven visual layer
# ("the play-dough idea"): a unit/building's `visual.texture` field names an
# image, and this service resolves it to a Texture2D the render style can draw.
#
# Design rules:
#   - PURE PRESENTATION: nothing here ever touches the simulation/WorldState.
#     Textures are cosmetic, so they must never affect the deterministic hash.
#   - LAZY + CACHED: a texture is loaded the first time it is requested and kept
#     in a `texture_id -> Texture2D` cache, so the render loop stays cheap.
#   - SAFE FALLBACK: a missing or unloadable texture resolves to a generated
#     1x1 placeholder so the renderer never crashes on bad mod data.
#   - MULTI-ROOT: search roots are tried in order. The base game ships textures
#     under `res://assets/textures/`; user mods / .nexpack content (Phase C) can
#     register extra roots (e.g. `user://content/<mod>/`), last-registered-wins
#     so a mod can override a base texture by id.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name TextureService
extends RefCounted

# Default search root for base-game textures (shipped inside the PCK on export).
#
# GUI audit (BUG-G7): catalog entries reference textures as "textures/<name>.png"
# (the same layout mod packs use: <pack_root>/textures/<name>). The root was
# "res://assets/textures/", so every base texture resolved to the non-existent
# "res://assets/textures/textures/x.png" -> has_texture() false everywhere and
# the magenta/black checker placeholder painted the whole sprite-style map.
# The root is the folder that CONTAINS "textures/", i.e. "res://assets/".
const DEFAULT_ROOT: String = "res://assets/"

# Ordered list of root directories to resolve relative texture paths against.
# Earlier entries are searched first; callers append mod roots at runtime.
var _roots: Array = [DEFAULT_ROOT]

# Cache: resolved texture key (String) -> Texture2D.
var _cache: Dictionary = {}

# A shared 4x4 magenta/black checker so a missing texture is obvious but never
# fatal. Built lazily on first miss.
var _placeholder: Texture2D = null


# Register an additional search root (e.g. an unpacked mod folder). Later roots
# take precedence so mods can override base textures by relative path.
func add_root(path: String) -> void:
	if path == "" or _roots.has(path):
		return
	# Insert at the front so the most-recently-added root wins.
	_roots.push_front(path)


# Reset the service to base-only roots and drop the cache (used on mod reload).
func clear() -> void:
	_roots = [DEFAULT_ROOT]
	_cache.clear()


# Resolve a relative texture path (e.g. "textures/soldier.png") to a Texture2D.
# Returns a placeholder on any failure. Results are cached by the input key.
func get_texture(relative_path: String) -> Texture2D:
	if relative_path == "":
		return _get_placeholder()
	if _cache.has(relative_path):
		return _cache[relative_path]
	var tex: Texture2D = _try_load(relative_path)
	if tex == null:
		tex = _get_placeholder()
	_cache[relative_path] = tex
	return tex


# Whether a given relative texture path resolves to a real file in any root.
func has_texture(relative_path: String) -> bool:
	for root in _roots:
		if ResourceLoader.exists(_join(root, relative_path)):
			return true
		if FileAccess.file_exists(_join(root, relative_path)):
			return true
	return false


# --- Internals --------------------------------------------------------------

func _try_load(relative_path: String) -> Texture2D:
	for root in _roots:
		var full: String = _join(root, relative_path)
		# Prefer Godot's resource loader (imported textures inside the PCK).
		if ResourceLoader.exists(full):
			var res: Resource = ResourceLoader.load(full)
			if res is Texture2D:
				return res as Texture2D
		# Fall back to loading a raw image from disk (user:// mod content).
		if FileAccess.file_exists(full):
			var img: Image = Image.new()
			if img.load(full) == OK:
				# MB9.2 (bug 28): user images may be a float format that the GL
				# Compatibility renderer would convert (with an RGBAFloat warning)
				# on upload. Normalize to RGBA8 first so the warning never fires.
				img = ImageFormatUtil.normalize_for_gl_compat(img)
				return ImageTexture.create_from_image(img)
	return null


func _join(root: String, rel: String) -> String:
	if root.ends_with("/"):
		return root + rel
	return root + "/" + rel


func _get_placeholder() -> Texture2D:
	if _placeholder != null:
		return _placeholder
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var magenta: Color = Color(0.9, 0.1, 0.9, 1.0)
	var dark: Color = Color(0.1, 0.1, 0.1, 1.0)
	for y in range(4):
		for x in range(4):
			img.set_pixel(x, y, magenta if (x + y) % 2 == 0 else dark)
	_placeholder = ImageTexture.create_from_image(img)
	return _placeholder
