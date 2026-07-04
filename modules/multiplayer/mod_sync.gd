# mod_sync.gd
# ----------------------------------------------------------------------------
# Project Nexus - Automatic Mod Synchronisation (Phase P5, step P5.4 / R7).
#
# R7: when a match starts, if a joined player does NOT have the host's mods, the
# game must DETECT this automatically, UPLOAD the required content from the host,
# DOWNLOAD + APPLY it on the join, all BEFORE the match starts, showing a
# progress bar (R2.2). The whole point is lockstep safety: every peer must build
# the SAME catalogs from the SAME seed, or the deterministic simulation desyncs.
#
# THE STRATEGY (hash-compare, then transfer only if needed):
#   1. Both host and join compute a MOD FINGERPRINT = a stable hash of their
#      active catalog set (all catalog entries, sorted, hashed with StateHasher).
#      This is cheap and needs no transfer.
#   2. The host broadcasts its fingerprint. Each join compares it to its own.
#        - equal   -> nothing to do; proceed straight to the match.
#        - differ  -> the join is missing/older; the host serialises its ENTIRE
#                     active content into ONE in-memory `.nexpack` (ModPackManager
#                     already does exactly this) and ships the bytes to the join.
#   3. The join writes those bytes to its content root and imports the pack via
#      the standard ModLoader path, then recomputes its fingerprint to confirm it
#      now matches the host's. Only then is it allowed to start.
#
# This class is TRANSPORT-AGNOSTIC and headless-testable: it exposes the three
# primitive operations (fingerprint / pack-active-to-bytes / apply-bytes) plus a
# small progress signal. The actual byte transfer is done by whatever transport
# the lobby uses (ENet reliable channel); this class only produces/consumes the
# payload. It never touches WorldState or the deterministic hash directly -- it
# only reads catalogs and writes content files, exactly like the pack layer.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name ModSync
extends RefCounted

# The catalogs that make up a mod fingerprint (must match ModPackManager.CATALOGS
# so the fingerprint covers exactly what gets packed/transferred).
const CATALOGS: Array = ["units", "buildings", "objects", "scenarios", "tech"]

# A temporary pack id used when serialising active content for transfer.
const TRANSFER_PACK_ID: String = "synced_content"
const TRANSFER_PACK_NAME: String = "Synced Content"

var _nexus: Object = null


func setup(nexus: Object) -> void:
	_nexus = nexus


# --- Fingerprint ------------------------------------------------------------

# Compute a stable, order-independent hash of the ACTIVE catalog set. Two peers
# with identical content produce the same value; any add/remove/edit changes it.
# Returns 0 if there is no data loader (nothing to compare).
func fingerprint() -> int:
	if _nexus == null or _nexus.data_loader == null:
		return 0
	# Build a single canonical dictionary { catalog -> { id -> entry } } and hash
	# it. StateHasher.hash_variant sorts keys, so insertion order is irrelevant.
	var snapshot: Dictionary = {}
	for catalog_name in CATALOGS:
		var catalog: Dictionary = _nexus.data_loader.get_catalog(catalog_name)
		if not catalog.is_empty():
			snapshot[catalog_name] = catalog
	return StateHasher.hash_variant(snapshot)


# Short hex string form of the fingerprint (shown in the lobby as a "mod tag").
func fingerprint_string() -> String:
	return StateHasher.hash_variant_string(fingerprint())


# Do two fingerprints match? (Convenience for the lobby.)
func matches(remote_fingerprint: int) -> bool:
	return fingerprint() == remote_fingerprint


# --- Host side: serialise active content for transfer -----------------------

# Pack ALL currently-active content into a single in-memory `.nexpack` and return
# its raw bytes, ready to ship to a join over the transport. Returns an empty
# PackedByteArray on failure (nothing to export / write error).
func pack_active_bytes() -> PackedByteArray:
	if _nexus == null:
		return PackedByteArray()
	# Reuse the fully-tested ModPackManager to build the pack on a temp file, then
	# read the bytes back. (A .nexpack is a ZIP; ModPackManager writes to a path,
	# so we round-trip through a user:// temp file rather than duplicate its logic.)
	var manager: ModPackManager = ModPackManager.new()
	manager.setup(_nexus)
	var tmp_path: String = "user://.modsync_transfer.nexpack"
	if not manager.export_active(tmp_path, TRANSFER_PACK_ID, TRANSFER_PACK_NAME):
		return PackedByteArray()
	if not FileAccess.file_exists(tmp_path):
		return PackedByteArray()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(tmp_path)
	# Clean up the temp file; the bytes are what matters.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	return bytes


# --- Join side: apply received content --------------------------------------

# Write received `.nexpack` bytes to a temp file and import them via the standard
# ModPackManager path, so the join's catalogs match the host's. Returns true on
# success. `progress_cb` (optional) is called as Callable(fraction: float) so the
# UI can drive a progress bar (R2.2): 0.0 -> writing, 0.5 -> importing, 1.0 done.
func apply_pack_bytes(bytes: PackedByteArray, progress_cb: Callable = Callable()) -> bool:
	if _nexus == null or bytes.is_empty():
		return false
	if progress_cb.is_valid():
		progress_cb.call(0.0)
	var tmp_path: String = "user://.modsync_incoming.nexpack"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	if progress_cb.is_valid():
		progress_cb.call(0.5)
	var manager: ModPackManager = ModPackManager.new()
	manager.setup(_nexus)
	var ok: bool = manager.import_pack(tmp_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	if progress_cb.is_valid():
		progress_cb.call(1.0)
	return ok


# --- Orchestration helper (used by the lobby) -------------------------------

# Decide what a join must do given the host's fingerprint. Returns a plain
# Dictionary the lobby can act on without re-implementing the compare:
#   { "needs_sync": bool, "local": int, "remote": int }
func plan_for_join(host_fingerprint: int) -> Dictionary:
	var local: int = fingerprint()
	return {
		"needs_sync": local != host_fingerprint,
		"local": local,
		"remote": host_fingerprint,
	}
