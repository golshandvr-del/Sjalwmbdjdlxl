# prereq_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Prerequisite Util (T006 WP1).
#
# Pure, static, deterministic helpers for the data-driven prerequisite engine
# that buildings, units and tech nodes all share. A `requires` block is a small
# dictionary of the shape:
#
#   { "buildings": ["barracks", ...], "tech": ["improved_weapons", ...] }
#
# Either key may be omitted; `null` / `{}` mean "no prerequisites". `missing`
# returns the sorted list of unmet items as strings ("building:<id>" /
# "tech:<id>") so callers can both reject an order and show the player exactly
# what is missing. It is robust to malformed input (null, non-Array values,
# non-Dictionary `requires`) and never touches the world model, so it is fully
# headless-testable and lockstep-safe.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PrereqUtil
extends RefCounted

const BUILDING_PREFIX: String = "building:"
const TECH_PREFIX: String = "tech:"


# Sorted Array of unmet prerequisite ids for `requires`, each tagged with its
# kind ("building:<id>" / "tech:<id>"). `completed_building_types` is the set of
# building types the owner has finished; `researched` is the set of tech node
# ids the owner has completed. Both may be empty. Returns [] when `requires` is
# null / {} / malformed.
static func missing(requires: Variant, completed_building_types: Array, researched: Array) -> Array:
        var out: Array = []
        if not (requires is Dictionary):
                return out
        var req: Dictionary = requires as Dictionary
        for building_id in _as_string_array(req.get("buildings", [])):
                if not completed_building_types.has(building_id):
                        out.append(BUILDING_PREFIX + building_id)
        for tech_id in _as_string_array(req.get("tech", [])):
                if not researched.has(tech_id):
                        out.append(TECH_PREFIX + tech_id)
        out.sort()
        return out


# Sorted, unique list of building TYPES owned by `owner` that are alive and fully
# constructed. `building_list` is the WorldState "buildings" -> "list" map.
static func owner_completed_building_types(building_list: Dictionary, owner: int) -> Array:
        var out: Array = []
        for key in building_list.keys():
                var b: Variant = building_list[key]
                if not (b is Dictionary):
                        continue
                var rec: Dictionary = b as Dictionary
                if int(rec.get("owner", -1)) != owner:
                        continue
                if int(rec.get("health", 0)) <= 0:
                        continue
                if int(rec.get("construction_remaining", 0)) > 0:
                        continue
                var type_id: String = str(rec.get("type", ""))
                if type_id != "" and not out.has(type_id):
                        out.append(type_id)
        out.sort()
        return out


# Coerce a `requires` sub-value into a String Array, ignoring non-Array values
# (and skipping blank entries) so a malformed block can never crash the caller.
static func _as_string_array(value: Variant) -> Array:
        var out: Array = []
        if not (value is Array):
                return out
        for raw in value as Array:
                var s: String = str(raw)
                if s != "":
                        out.append(s)
        return out
