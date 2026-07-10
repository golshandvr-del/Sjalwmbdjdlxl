# image_format_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - GL-Compatibility-safe image format helpers (MB9.2 / bug 28).
#
# The bug this fixes (bug 28): on the Android device (GL Compatibility renderer)
# Godot prints "RGBAFloat not supported, converting to RGBAHalf" whenever a
# floating-point image reaches the GPU. Base-game textures are fixed at import
# time, but user-supplied content (mod textures, map-editor background images
# loaded via Image.load() at runtime) can still arrive in a float format
# (FORMAT_RF / RGF / RGBF / RGBAF / their half variants) and spam that warning.
#
# This is a pure, dependency-free static util (no SceneTree, no autoload) so the
# decision logic is fully unit-testable headless. TextureService and the map
# editor call normalize_for_gl_compat() on every runtime-loaded Image so the
# pixels reach the GPU as plain RGBA8, silencing the warning at the source.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name ImageFormatUtil
extends RefCounted

# The floating-point Image formats GL Compatibility cannot upload directly and
# therefore converts (with a warning) at load time. Includes both full-float and
# half-float variants; normalizing any of them to RGBA8 avoids the conversion.
const FLOAT_FORMATS: Array = [
	Image.FORMAT_RF, Image.FORMAT_RGF, Image.FORMAT_RGBF, Image.FORMAT_RGBAF,
	Image.FORMAT_RH, Image.FORMAT_RGH, Image.FORMAT_RGBH, Image.FORMAT_RGBAH,
	Image.FORMAT_RGBE9995,
]


# True when `format` is a floating-point format GL Compatibility must convert.
static func is_float_format(format: int) -> bool:
	return FLOAT_FORMATS.has(format)


# True when an image in `format` needs normalizing before it is safe to upload
# on the GL Compatibility renderer without triggering the RGBAFloat warning.
static func needs_normalize(format: int) -> bool:
	return is_float_format(format)


# Return a GL-Compatibility-safe Image: if `img` is a float format it is
# converted to RGBA8 (in place is avoided -- we work on the passed image which is
# already a fresh runtime load), otherwise it is returned unchanged. Null-safe.
static func normalize_for_gl_compat(img: Image) -> Image:
	if img == null:
		return null
	if needs_normalize(img.get_format()):
		img.convert(Image.FORMAT_RGBA8)
	return img
