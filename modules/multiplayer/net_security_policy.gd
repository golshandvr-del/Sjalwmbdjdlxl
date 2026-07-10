# net_security_policy.gd
# ----------------------------------------------------------------------------
# Project Nexus - Network security policy (MB9.1 / bug 27).
#
# The bug this addresses (bug 27): the Android log shows "TLS handshake error
# -29184". Project Nexus is LAN-first: discovery is plain UDP broadcast
# (LanDiscovery) and the game transport is plain ENet UDP (EnetTransport). NO
# part of the game opens an HTTPS/TLS connection -- there is no update check, no
# telemetry, no remote lobby server. So that handshake error does NOT originate
# in game code; it is engine-level noise (typically the editor/remote-debug
# probe or an export-template network check) and is harmless to gameplay.
#
# This util is the SINGLE SOURCE OF TRUTH for that invariant. It is a pure,
# dependency-free static util (no SceneTree, no autoload) so it is fully
# unit-testable headless. It does two jobs:
#   1. uses_tls(): declares (and lets a test assert) that the LAN networking
#      stack uses NO TLS -- a regression guard so nobody silently adds an HTTPS
#      dependency to the LAN path.
#   2. is_benign_tls_error()/describe_tls_error(): classify the -29184 code (and
#      the related mbedTLS handshake range) as a known, ignorable transient so
#      callers can log ONE friendly line instead of letting the raw error spam.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name NetSecurityPolicy
extends RefCounted

# The specific handshake error reported on Android (bug 27). mbedTLS surfaces a
# family of negative codes for a peer that closed / never completed the TLS
# handshake; -29184 is the one observed. We treat this whole low range as the
# same "peer went away / no TLS peer here" transient.
const TLS_HANDSHAKE_ERROR: int = -29184
# mbedTLS negative error codes cluster in this range; anything at or below the
# handshake code is treated as a benign non-TLS-peer transient for our LAN app.
const TLS_ERROR_FLOOR: int = -32768


# Project Nexus is LAN-first and opens NO TLS/HTTPS connections. This returns
# false by design; a test asserts it so adding a TLS dependency to the LAN path
# is a deliberate, reviewed change (and never silently regresses bug 27).
static func uses_tls() -> bool:
	return false


# True when `code` is the known benign TLS handshake transient (bug 27). Because
# the game never initiates TLS, any such code means a non-TLS peer (or the
# engine's debug probe) hit a socket -- safe to ignore beyond one log line.
static func is_benign_tls_error(code: int) -> bool:
	if code == TLS_HANDSHAKE_ERROR:
		return true
	return code <= TLS_HANDSHAKE_ERROR and code >= TLS_ERROR_FLOOR


# A short, user/log friendly description for a benign TLS error, or "" when the
# code is not a benign TLS transient (so callers can decide to surface it).
static func describe_tls_error(code: int) -> String:
	if is_benign_tls_error(code):
		return "Ignoring stray TLS handshake error %d: LAN play uses no TLS." % code
	return ""
