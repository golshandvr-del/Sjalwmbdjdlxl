# full_tree_order_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - "Full tree" AI ordering (T006 WP4).
#
# When a scenario opts in with `rules.full_ai`, the strategic AI should play the
# WHOLE data-driven tree instead of only the vanilla outpost/HQ loop: research
# every reachable tech, build every reachable building (economy first, then
# production, then defense), and produce a mix of units from all of its
# production buildings.
#
# This helper is PURE and deterministic: it only reads plain catalog/snapshot
# dictionaries, emits id-sorted arrays, and breaks every tie by (depth, cost,
# id). No world-model access, no RNG, no wall clock -- safe to unit test headless
# and to run identically on every lockstep peer.
#
# It is deliberately generic: it works for ANY catalog and ANY id prefix, so a
# mod that ships its own `xx_` buildings/techs gets the same behaviour without
# touching engine code. The prefix is what keeps a vanilla AI from ever picking
# mod content (A2 lock).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name FullTreeOrderUtil
extends RefCounted


# Sorted ids of buildings `owner` could START building right now: id has the
# prefix, is not the HQ, is buildable, is not already completed, and every
# prerequisite is met. Ordered by (prerequisite depth, total cost, id) so the
# cheapest foundational buildings come first. Affordability is NOT applied here
# (the caller decides whether to wait for income).
static func building_order(
                catalog: Dictionary,
                prefix: String,
                completed: Array,
                researched: Array) -> Array:
        var depth: Dictionary = {}
        var eligible: Array = []
        var ids: Array = catalog.keys()
        ids.sort_custom(func(a, b): return str(a) < str(b))
        for raw_id in ids:
                var id: String = str(raw_id)
                if prefix != "" and not id.begins_with(prefix):
                        continue
                var entry: Variant = catalog[raw_id]
                if not (entry is Dictionary):
                        continue
                var e: Dictionary = entry
                if not bool(e.get("buildable", true)):
                        continue
                if completed.has(id):
                        continue
                if not PrereqUtil.missing(e.get("requires", {}), completed, researched).is_empty():
                        continue
                eligible.append({
                        "id": id,
                        "depth": _building_depth(id, catalog, depth, 0),
                        "cost": total_cost(e),
                })
        eligible.sort_custom(func(a, b):
                if int(a["depth"]) != int(b["depth"]):
                        return int(a["depth"]) < int(b["depth"])
                if int(a["cost"]) != int(b["cost"]):
                        return int(a["cost"]) < int(b["cost"])
                return str(a["id"]) < str(b["id"]))
        var out: Array = []
        for rec in eligible:
                out.append(str(rec["id"]))
        return out


# Sorted ids of tech nodes `owner` could START researching right now: not
# researched, not in progress, every tech prerequisite researched, every
# building prerequisite completed. Ordered by (depth, cost, id).
static func tech_order(
                nodes: Dictionary,
                completed_buildings: Array,
                researched: Array,
                in_progress: Array) -> Array:
        var depth: Dictionary = {}
        var eligible: Array = []
        var ids: Array = nodes.keys()
        ids.sort_custom(func(a, b): return str(a) < str(b))
        for raw_id in ids:
                var id: String = str(raw_id)
                if researched.has(id) or in_progress.has(id):
                        continue
                var node: Dictionary = nodes[raw_id]
                var ready: bool = true
                for req in node.get("requires", []):
                        if not researched.has(str(req)):
                                ready = false
                                break
                if ready:
                        for rb in node.get("requires_buildings", []):
                                if not completed_buildings.has(str(rb)):
                                        ready = false
                                        break
                if not ready:
                        continue
                eligible.append({
                        "id": id,
                        "depth": _tech_depth(id, nodes, depth, 0),
                        "cost": total_cost(node),
                })
        eligible.sort_custom(func(a, b):
                if int(a["depth"]) != int(b["depth"]):
                        return int(a["depth"]) < int(b["depth"])
                if int(a["cost"]) != int(b["cost"]):
                        return int(a["cost"]) < int(b["cost"])
                return str(a["id"]) < str(b["id"]))
        var out: Array = []
        for rec in eligible:
                out.append(str(rec["id"]))
        return out


# Summed numeric cost of an entry's `cost` block (0 when absent).
static func total_cost(entry: Dictionary) -> int:
        var cost: Variant = entry.get("cost", {})
        if not (cost is Dictionary):
                return 0
        var total: int = 0
        for key in (cost as Dictionary).keys():
                total += int((cost as Dictionary)[key])
        return total


# True when every resource in `cost` is covered by `wallet`.
static func can_afford(cost: Variant, wallet: Dictionary) -> bool:
        if not (cost is Dictionary):
                return true
        for resource_id in (cost as Dictionary).keys():
                if int(wallet.get(str(resource_id), 0)) < int((cost as Dictionary)[resource_id]):
                        return false
        return true


# Longest building-prerequisite chain ending at `id` (0 = no building prereqs).
static func _building_depth(id: String, catalog: Dictionary, memo: Dictionary, guard: int) -> int:
        if memo.has(id):
                return int(memo[id])
        if guard > 64:
                return 99
        var entry: Variant = catalog.get(id, {})
        var maxd: int = 0
        if entry is Dictionary:
                var requires: Variant = (entry as Dictionary).get("requires", {})
                if requires is Dictionary:
                        for r in (requires as Dictionary).get("buildings", []):
                                maxd = max(maxd, _building_depth(str(r), catalog, memo, guard + 1) + 1)
        memo[id] = maxd
        return maxd


# Longest tech-prerequisite chain ending at `id` (0 = no tech prereqs).
static func _tech_depth(id: String, nodes: Dictionary, memo: Dictionary, guard: int) -> int:
        if memo.has(id):
                return int(memo[id])
        if guard > 64:
                return 99
        var node: Variant = nodes.get(id, {})
        var maxd: int = 0
        if node is Dictionary:
                for r in (node as Dictionary).get("requires", []):
                        maxd = max(maxd, _tech_depth(str(r), nodes, memo, guard + 1) + 1)
        memo[id] = maxd
        return maxd
