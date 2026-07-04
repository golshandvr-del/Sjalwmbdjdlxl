# check_code_policy.gd
# ----------------------------------------------------------------------------
# Project Nexus - CODE LANGUAGE POLICY linter (Phase 5, step 5.1).
#
# A zero-dependency CI/lint check that enforces docs/CODE_POLICY.md: the entire
# codebase must be ASCII/English-only. The ONLY place non-English (non-ASCII)
# characters are allowed is the localization/ folder (display strings keyed by
# English ids).
#
# It walks the repository, opens every scanned source file, and rejects any
# character with a code point > 127 that lives outside the allowed
# localization/ tree. It also flags non-ASCII file/folder NAMES anywhere.
#
# Run it headless from the project root:
#   godot --headless --path . --script res://tools/check_code_policy.gd
# Exit code 0 = clean (policy satisfied), 1 = at least one violation found.
# This is exactly what the CI workflow invokes (see .github/workflows/ci.yml).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
extends SceneTree

# File extensions that are part of "the source code of the entire project" and
# must therefore be pure ASCII. (Binary/asset files are skipped.)
const SCANNED_EXTENSIONS: Array = [
	"gd", "tscn", "tres", "godot", "import", "cfg", "json",
	"md", "yml", "yaml", "txt", "csv", "gdextension", "cs",
]

# Directories that are never scanned at all (engine/vendor/VCS noise).
const SKIPPED_DIRS: Array = [".git", ".godot", ".import", "addons", "android"]

# The single allowed exception: files UNDER this folder may contain non-ASCII
# display text (localized UI strings). Their KEYS must still be English, but we
# intentionally do not parse JSON here -- the contract is "non-English text is
# only permitted inside localization/ files".
const LOCALIZATION_DIR: String = "localization"

# Design documents under docs/ are INTENTIONALLY written in Persian (see
# docs/CODE_POLICY.md: "code = ASCII; docs/*.md = Persian allowed"). They are not
# part of the shipping source code, so the ASCII-only rule does not apply to
# them. Their file NAMES are still checked for ASCII above. This closes BUG-D3
# (the linter used to flag ~640 intentional Persian characters in these docs,
# keeping the CI gate permanently red and hiding the single real violation).
const DOCS_DIR: String = "docs"

var _violations: Array = []
var _files_scanned: int = 0


func _init() -> void:
	print("==== Project Nexus :: CODE_POLICY Linter ====")
	var root: String = "res://"
	_scan_dir(root)
	_report()
	quit(0 if _violations.is_empty() else 1)


# Recursively walk a directory, scanning eligible files and recursing into
# subfolders. Also enforces ASCII file/folder NAMES (policy item: file names).
func _scan_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full: String = path.path_join(name)
		# File/folder NAME must itself be ASCII (policy: file and folder names).
		if not _is_ascii(name):
			_violations.append("%s :: non-ASCII characters in the name itself" % full)
		if dir.current_is_dir():
			if not SKIPPED_DIRS.has(name):
				_scan_dir(full)
		else:
			_maybe_scan_file(full)
		name = dir.get_next()
	dir.list_dir_end()


func _maybe_scan_file(full: String) -> void:
	var ext: String = full.get_extension().to_lower()
	if not SCANNED_EXTENSIONS.has(ext):
		return
	# Allowed exceptions: anything under localization/ may hold non-ASCII display
	# text, and design documents under docs/*.md are intentionally in Persian.
	# (We still scanned their NAMES above for ASCII safety.)
	if _is_in_localization(full):
		return
	if _is_in_docs(full):
		return
	_files_scanned += 1
	var file: FileAccess = FileAccess.open(full, FileAccess.READ)
	if file == null:
		return
	var line_number: int = 0
	while not file.eof_reached():
		line_number += 1
		var line: String = file.get_line()
		var col: int = _first_non_ascii_column(line)
		if col >= 0:
			_violations.append("%s:%d:%d :: non-ASCII character (policy: source must be English-only)" % [
				full, line_number, col + 1,
			])
	file.close()


# Return the 0-based column of the first non-ASCII character, or -1 if the whole
# line is ASCII.
func _first_non_ascii_column(line: String) -> int:
	for i in range(line.length()):
		if line.unicode_at(i) > 127:
			return i
	return -1


func _is_ascii(text: String) -> bool:
	for i in range(text.length()):
		if text.unicode_at(i) > 127:
			return false
	return true


# True when the path lives under the allowed localization/ tree.
func _is_in_localization(full: String) -> bool:
	var normalized: String = full.trim_prefix("res://")
	return normalized == LOCALIZATION_DIR or normalized.begins_with(LOCALIZATION_DIR + "/")


# True when the path is a design document under docs/ (Persian allowed).
func _is_in_docs(full: String) -> bool:
	var normalized: String = full.trim_prefix("res://")
	return normalized == DOCS_DIR or normalized.begins_with(DOCS_DIR + "/")


func _report() -> void:
	print("-------------------------------------------")
	print("Files scanned: %d" % _files_scanned)
	if _violations.is_empty():
		print("[PASS] No CODE_POLICY violations found.")
	else:
		print("[FAIL] %d CODE_POLICY violation(s):" % _violations.size())
		for v in _violations:
			print("  - %s" % v)
	print("===========================================")
