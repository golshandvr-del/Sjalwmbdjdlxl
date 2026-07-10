# net_address_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Network Address Utilities (Phase MB6, bug 12).
#
# A PURE, dependency-free helper that turns the raw list returned by
# IP.get_local_addresses() into the single, human-facing "connect to this host
# at ..." address the lobby should show. It owns no engine state: the lobby
# passes in the address list (so tests can inject a fixed list) and this util
# decides which address is the best LAN IPv4 to display.
#
# WHY A SEPARATE UTIL: IP.get_local_addresses() returns a noisy mix (loopback,
# IPv6, link-local, sometimes multiple NICs). Picking the "right" one to show a
# joining player is fiddly and easy to get wrong, so the selection rules live
# here where they can be unit-tested headlessly without a real network.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name NetAddressUtil
extends RefCounted


# Loopback addresses we never want to advertise as a "connect here" IP.
const LOOPBACK_V4: String = "127.0.0.1"


# True if `addr` is a dotted IPv4 string (four 0-255 octets). Rejects IPv6 and
# malformed text. Pure.
static func is_ipv4(addr: String) -> bool:
	var parts: PackedStringArray = addr.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part == "" or not part.is_valid_int():
			return false
		var value: int = int(part)
		if value < 0 or value > 255:
			return false
		# Reject leading zeros like "01" which are not canonical dotted-quad.
		if part.length() > 1 and part.begins_with("0"):
			return false
	return true


# True for loopback (127.x) IPv4.
static func is_loopback_v4(addr: String) -> bool:
	return is_ipv4(addr) and addr.begins_with("127.")


# True for IPv4 link-local (169.254.x.x) which is not routable on a real LAN.
static func is_link_local_v4(addr: String) -> bool:
	return is_ipv4(addr) and addr.begins_with("169.254.")


# True for the RFC1918 private ranges most home/LAN routers hand out
# (10.x, 172.16-31.x, 192.168.x). These are the addresses a joining player on
# the same Wi-Fi actually needs, so we prefer them over any other IPv4.
static func is_private_lan_v4(addr: String) -> bool:
	if not is_ipv4(addr):
		return false
	if addr.begins_with("10."):
		return true
	if addr.begins_with("192.168."):
		return true
	if addr.begins_with("172."):
		var second: int = int(addr.split(".")[1])
		return second >= 16 and second <= 31
	return false


# From a raw address list (as IP.get_local_addresses() returns), pick the single
# best address to show as the host's LAN address, or "" if none is usable.
#
# Preference order:
#   1. A private LAN IPv4 (10/172.16-31/192.168) -- what a peer on the same
#      network connects to.
#   2. Any other non-loopback, non-link-local IPv4.
#   3. "" (nothing usable) -- caller shows a "no LAN detected" hint.
#
# Deterministic: among equal-priority candidates the FIRST in list order wins,
# so the result is stable for a given input.
static func best_lan_ipv4(addresses: Array) -> String:
	var fallback: String = ""
	for entry in addresses:
		var addr: String = str(entry)
		if not is_ipv4(addr):
			continue
		if is_loopback_v4(addr) or is_link_local_v4(addr):
			continue
		if is_private_lan_v4(addr):
			return addr
		if fallback == "":
			fallback = addr
	return fallback
