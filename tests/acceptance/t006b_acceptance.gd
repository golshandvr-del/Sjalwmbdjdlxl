# t006b_acceptance.gd
# ----------------------------------------------------------------------------
# Project Nexus - T006b review fix-up acceptance checker (author: Claude, Tech Lead).
# READ-ONLY FOR THE EXECUTOR. t006_acceptance.gd must ALSO stay at fail=0.
# Targets the review findings on PR #7: stamped maps, cloned scenario,
# identical AIs, short games without late-tree content, hidden SCRIPT ERRORs.
#
# Run: godot --headless --path . --script res://tests/acceptance/t006b_acceptance.gd
# Output: "T006B_CHECK PASS|FAIL <id> <msg>", final "T006B_SUMMARY pass=<n> fail=<m>".
# ----------------------------------------------------------------------------
extends SceneTree

const TR = preload("res://tests/test_runner.gd")
const HQ_TYPE: String = "fr_citadel"
const MAPS: Array = ["fr_river_valley", "fr_four_realms", "fr_border_siege"]
const LATE_BUILDINGS: Array = ["fr_sanctum", "fr_dragon_roost", "fr_cannon_tower"]
const LATE_UNITS: Array = ["fr_paladin", "fr_wyvern"]

var _pass: int = 0
var _fail: int = 0
var _only: String = ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--only="):
			_only = str(a).substr(7)
	if _only == "" or _only.contains("M"):
		_maps()
	if _only == "" or _only.contains("P"):
		_personality()
	if _only == "" or _only.contains("L"):
		_late_game()
	if _only == "" or _only.contains("Q"):
		_quality()
	print("T006B_SUMMARY pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, id: String, msg: String) -> void:
	if cond:
		_pass += 1
		print("T006B_CHECK PASS %s %s" % [id, msg])
	else:
		_fail += 1
		print("T006B_CHECK FAIL %s %s" % [id, msg])


func _full() -> Object:
	var n: Object = TR.TickHarness.new()
	GameBootstrap.register_modules(n)
	GameBootstrap.load_catalogs(n)
	return n


func _rows(n: Object, sid: String) -> Array:
	var sc: Variant = n.data_loader.get_entry("scenarios", sid)
	if not (sc is Dictionary):
		return []
	return ((sc as Dictionary).get("map", {}) as Dictionary).get("rows", [])


func _grid(rows: Array) -> Dictionary:
	var h: int = rows.size()
	var w: int = str(rows[0]).length() if h > 0 else 0
	var tiles: Array = []
	for r in rows:
		var s: String = str(r)
		for x in range(w):
			var c: String = s.substr(x, 1)
			tiles.append(0 if c == "." else (1 if c == "#" else (2 if c == "~" else (3 if c == "T" else 0))))
	return { "w": w, "h": h, "tiles": tiles }


# Components of one terrain as arrays of Vector2i (4-connected).
func _components(g: Dictionary, terrain: int) -> Array:
	var w: int = g["w"]
	var h: int = g["h"]
	var tiles: Array = g["tiles"]
	var seen: Dictionary = {}
	var out: Array = []
	for i in range(tiles.size()):
		if int(tiles[i]) != terrain or seen.has(i):
			continue
		var comp: Array = []
		var stack: Array = [i]
		seen[i] = true
		while not stack.is_empty():
			var c: int = int(stack.pop_back())
			comp.append(Vector2i(c % w, c / w))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var xx: int = c % w + d.x
				var yy: int = c / w + d.y
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var ni: int = yy * w + xx
				if not seen.has(ni) and int(tiles[ni]) == terrain:
					seen[ni] = true
					stack.append(ni)
		out.append(comp)
	return out


# Translation-normalised shape signature (rotation/mirror NOT normalised on
# purpose: rotated copies of one stamp still count as distinct only if they differ).
func _shape_sig(comp: Array) -> String:
	var minx: int = 1 << 30
	var miny: int = 1 << 30
	for p in comp:
		minx = min(minx, p.x)
		miny = min(miny, p.y)
	var pts: Array = []
	for p in comp:
		pts.append("%d,%d" % [p.x - minx, p.y - miny])
	pts.sort()
	return ";".join(pts)


func _is_symmetric(comp: Array) -> bool:
	# True when the component is identical under BOTH horizontal and vertical mirror.
	var minx: int = 1 << 30
	var maxx: int = -1
	var miny: int = 1 << 30
	var maxy: int = -1
	var set: Dictionary = {}
	for p in comp:
		minx = min(minx, p.x)
		maxx = max(maxx, p.x)
		miny = min(miny, p.y)
		maxy = max(maxy, p.y)
		set[p] = true
	for p in comp:
		if not set.has(Vector2i(minx + maxx - p.x, p.y)) or not set.has(Vector2i(p.x, miny + maxy - p.y)):
			return false
	return true


# =============================================================================
# M. Maps look natural and are distinct
# =============================================================================
func _maps() -> void:
	var n: Object = _full()
	var grids: Dictionary = {}
	for sid in MAPS:
		var rows: Array = _rows(n, sid)
		_ok(not rows.is_empty(), "M00." + sid, "scenario %s has map.rows" % sid)
		if rows.is_empty():
			continue
		var g: Dictionary = _grid(rows)
		grids[sid] = g
		var tiles: Array = g["tiles"]
		var total: float = float(tiles.size())
		var cnt: Array = [0, 0, 0, 0]
		for t in tiles:
			cnt[int(t)] += 1
		_ok(cnt[3] / total >= 0.11 and cnt[3] / total <= 0.28, "M01." + sid, "forest 11..28%% (%.1f%%)" % (100.0 * cnt[3] / total))
		for terrain in [3, 1]:
			var tname: String = "forest" if terrain == 3 else "rock"
			var comps: Array = []
			for c in _components(g, terrain):
				if (c as Array).size() >= 3:
					comps.append(c)
			var sigs: Dictionary = {}
			var sym: int = 0
			var sizes: Array = []
			for c in comps:
				sigs[_shape_sig(c)] = true
				if _is_symmetric(c):
					sym += 1
				sizes.append((c as Array).size())
			var distinct: float = float(sigs.size()) / float(max(1, comps.size()))
			_ok(comps.size() >= 5 and distinct >= 0.9, "M02.%s.%s" % [sid, tname],
				"%s clusters are not stamped copies: %d distinct shapes of %d clusters" % [tname, sigs.size(), comps.size()])
			_ok(comps.size() > 0 and float(sym) / float(comps.size()) <= 0.2, "M03.%s.%s" % [sid, tname],
				"%s clusters are irregular: %d of %d are mirror-symmetric on both axes" % [tname, sym, comps.size()])
			if terrain == 3:
				sizes.sort()
				var big: int = int(sizes[sizes.size() - 1]) if not sizes.is_empty() else 0
				var small: int = int(sizes[0]) if not sizes.is_empty() else 0
				_ok(big >= 4 * max(1, small) and big >= 25, "M04." + sid,
					"forest cluster sizes vary (smallest %d, largest %d)" % [small, big])
		# Room around citadels: comfortably above the T006 floor.
		var applied: Object = _full()
		ScenarioLoader.apply_scenario(applied, applied.data_loader.get_entry("scenarios", sid))
		var placed: Dictionary = applied.world_state.get_section("buildings").get("list", {})
		var w: int = g["w"]
		var h: int = g["h"]
		var room: Array = []
		for bk in placed.keys():
			var b: Dictionary = placed[bk]
			if str(b.get("type", "")) != HQ_TYPE:
				continue
			var gr: int = 0
			for y in range(max(0, int(b["y"]) - 6), min(h, int(b["y"]) + 7)):
				for x in range(max(0, int(b["x"]) - 6), min(w, int(b["x"]) + 7)):
					if abs(x - int(b["x"])) + abs(y - int(b["y"])) <= 6 and int(tiles[y * w + x]) == 0:
						gr += 1
			room.append(gr)
		var rmin: int = 1 << 30
		for r in room:
			rmin = min(rmin, int(r))
		_ok(not room.is_empty() and rmin >= 66, "M05." + sid, "build room around every citadel >= 66 %s" % str(room))
	# River in fr_river_valley: one water body crossing the map, winding.
	if grids.has("fr_river_valley"):
		var g2: Dictionary = grids["fr_river_valley"]
		# The river = union of every water body with >= 10 tiles (fords split it).
		var best: Array = []
		for c in _components(g2, 2):
			if (c as Array).size() >= 10:
				best.append_array(c)
		var miny: int = 1 << 30
		var maxy: int = -1
		var minx: int = 1 << 30
		var maxx: int = -1
		for p in best:
			miny = min(miny, p.y)
			maxy = max(maxy, p.y)
			minx = min(minx, p.x)
			maxx = max(maxx, p.x)
		var span_v: float = float(maxy - miny + 1) / float(g2["h"])
		var span_h: float = float(maxx - minx + 1) / float(g2["w"])
		var vertical: bool = span_v >= span_h
		_ok(max(span_v, span_h) >= 0.9, "M06", "river: water bodies together span >= 90%% of the map (v %.0f%%, h %.0f%%)" % [span_v * 100.0, span_h * 100.0])
		# Winding: the centreline wanders and the river stays narrow.
		var centres: Array = []
		var widths: Array = []
		var lines: int = int(g2["h"]) if vertical else int(g2["w"])
		for i in range(lines):
			var lo: int = 1 << 30
			var hi: int = -1
			var cntw: int = 0
			for p in best:
				var along: int = p.y if vertical else p.x
				var across: int = p.x if vertical else p.y
				if along == i:
					lo = min(lo, across)
					hi = max(hi, across)
					cntw += 1
			if hi >= 0:
				centres.append(float(lo + hi) / 2.0)
				widths.append(cntw)
		var cmin: float = 1e9
		var cmax: float = -1e9
		var wsum: int = 0
		for c in centres:
			cmin = min(cmin, c)
			cmax = max(cmax, c)
		for x in widths:
			wsum += int(x)
		var avgw: float = float(wsum) / float(max(1, widths.size()))
		_ok(cmax - cmin >= 6.0, "M07", "river winds: centreline sways %.1f tiles (>= 6)" % (cmax - cmin))
		_ok(avgw >= 2.0 and avgw <= 6.0, "M08", "river is a river, not a lake: mean width %.1f (2..6)" % avgw)
		# Crossings: ground fords/bridges break the river so armies can cross.
		_ok(_has_ford(g2, best, vertical), "M09", "river has at least 2 land crossings (fords/bridges)")
	# Distinct scenarios.
	var keys: Array = grids.keys()
	keys.sort()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Dictionary = grids[keys[i]]
			var b2: Dictionary = grids[keys[j]]
			var diff: float = 1.0
			if a["w"] == b2["w"] and a["h"] == b2["h"]:
				var d: int = 0
				for k in range((a["tiles"] as Array).size()):
					if int(a["tiles"][k]) != int(b2["tiles"][k]):
						d += 1
				diff = float(d) / float((a["tiles"] as Array).size())
			_ok(diff >= 0.25, "M10.%s~%s" % [keys[i], keys[j]], "maps are different (%.0f%% of tiles differ, >= 25%%)" % (diff * 100.0))


func _has_ford(g: Dictionary, river: Array, vertical: bool) -> bool:
	# Count lines (along the river) where the river is absent between its first and last line.
	var present: Dictionary = {}
	for p in river:
		present[p.y if vertical else p.x] = true
	var ks: Array = present.keys()
	ks.sort()
	if ks.is_empty():
		return false
	var gaps: int = 0
	var inside: bool = false
	for i in range(int(ks[0]), int(ks[ks.size() - 1]) + 1):
		if not present.has(i):
			if not inside:
				gaps += 1
			inside = true
		else:
			inside = false
	return gaps >= 2


# =============================================================================
# P. AI personalities differ in a full_ai scenario
# =============================================================================
class OrderRec extends RefCounted:
	var order: Dictionary = {}      # owner(str) -> Array of building types in placement order
	var units: Dictionary = {}      # owner(str) -> { type: count }
	var first_attack: Dictionary = {}  # owner(str) -> tick
	var tick_ref: Object = null
	func on_ev(event_name: String, payload: Dictionary) -> void:
		var o: String = str(int(payload.get("owner", -1)))
		if event_name == "buildings.placed":
			if not order.has(o):
				order[o] = []
			(order[o] as Array).append(str(payload.get("type", "")))
		elif event_name == "units.spawned":
			if not units.has(o):
				units[o] = {}
			var t: String = str(payload.get("type", ""))
			units[o][t] = int(units[o].get(t, 0)) + 1


func _personality() -> void:
	var n: Object = _full()
	var sc: Variant = n.data_loader.get_entry("scenarios", "fr_four_realms")
	if not (sc is Dictionary):
		_ok(false, "P01", "fr_four_realms missing")
		return
	var s: Dictionary = (sc as Dictionary).duplicate(true)
	for p in s.get("players", []):
		p["is_human"] = false
		p["smart"] = true
		if int(p.get("owner", -1)) == 0:
			p["personality"] = "defensive"
	ScenarioLoader.apply_scenario(n, s)
	var rec: OrderRec = OrderRec.new()
	n.subscribe("buildings.placed", rec, "on_ev")
	n.subscribe("units.spawned", rec, "on_ev")
	n.run_ticks(6000)
	var seqs: Dictionary = {}
	var report: Array = []
	for o in range(4):
		var seq: Array = (rec.order.get(str(o), []) as Array)
		var first8: Array = []
		for t in seq:
			if t == HQ_TYPE:
				continue
			first8.append(t)
			if first8.size() >= 8:
				break
		seqs[",".join(first8)] = true
		report.append("%d:%s" % [o, ",".join(first8)])
	_ok(seqs.size() >= 3, "P01", ">= 3 distinct first-8 build orders among 4 personalities %s" % str(report))
	# Army composition: share of the most common unit type differs between personalities.
	var mixes: Dictionary = {}
	var mreport: Array = []
	for o in range(4):
		var u: Dictionary = rec.units.get(str(o), {})
		var keys: Array = u.keys()
		keys.sort_custom(func(a, b): return int(u[a]) > int(u[b]) or (int(u[a]) == int(u[b]) and str(a) < str(b)))
		var top3: Array = keys.slice(0, 3)
		mixes[",".join(top3)] = true
		mreport.append("%d:%s" % [o, str(u)])
	_ok(mixes.size() >= 3, "P02", ">= 3 distinct top-3 unit mixes among 4 personalities %s" % str(mreport))
	var defensive_towers: int = 0
	var aggressive_towers: int = 0
	for t in rec.order.get("0", []):
		if t in ["fr_watchtower", "fr_cannon_tower", "fr_wall"]:
			defensive_towers += 1
	for t in rec.order.get("2", []):
		if t in ["fr_watchtower", "fr_cannon_tower", "fr_wall"]:
			aggressive_towers += 1
	_ok(defensive_towers > aggressive_towers, "P03", "defensive AI builds more towers/walls than aggressive AI (%d > %d)" % [defensive_towers, aggressive_towers])


# =============================================================================
# L. Duel reaches the late tree
# =============================================================================
func _late_game() -> void:
	var n: Object = _full()
	var sc: Variant = n.data_loader.get_entry("scenarios", "fr_river_valley")
	if not (sc is Dictionary):
		_ok(false, "L01", "fr_river_valley missing")
		return
	var s: Dictionary = (sc as Dictionary).duplicate(true)
	for p in s.get("players", []):
		p["is_human"] = false
		p["smart"] = true
	ScenarioLoader.apply_scenario(n, s)
	var rec: OrderRec = OrderRec.new()
	n.subscribe("units.spawned", rec, "on_ev")
	var done: Dictionary = {}
	var vic: Object = n.get_module("victory")
	var t0: int = Time.get_ticks_msec()
	while n.world_state.current_tick < 20000 and not vic.is_over():
		n.run_ticks(100)
		var list: Dictionary = n.world_state.get_section("buildings").get("list", {})
		for k in list.keys():
			var b: Dictionary = list[k]
			if int(b.get("construction_remaining", 0)) <= 0 and int(b.get("health", 0)) > 0:
				done[str(b.get("type", ""))] = true
	var ms: int = Time.get_ticks_msec() - t0
	print("T006B_INFO duel ticks=%d ms=%d over=%s winner=%d" % [n.world_state.current_tick, ms, str(vic.is_over()), vic.winner()])
	_ok(vic.is_over() and vic.winner() >= 0, "L01", "duel still ends with a winner before tick 20000 (tick %d)" % n.world_state.current_tick)
	_ok(n.world_state.current_tick >= 6000, "L02", "duel lasts >= 6000 ticks so the tree matters (tick %d)" % n.world_state.current_tick)
	var miss_b: Array = []
	for b in LATE_BUILDINGS:
		if not done.has(b):
			miss_b.append(b)
	_ok(miss_b.is_empty(), "L03", "late buildings completed by some AI in the duel; missing %s" % str(miss_b))
	var seen_u: Dictionary = {}
	for o in rec.units.keys():
		for t in (rec.units[o] as Dictionary).keys():
			seen_u[t] = true
	var miss_u: Array = []
	for u in LATE_UNITS:
		if not seen_u.has(u):
			miss_u.append(u)
	_ok(miss_u.is_empty(), "L04", "late units fielded in the duel; missing %s" % str(miss_u))
	_ok(ms <= 300000, "L05", "duel simulation <= 300 s (%d ms)" % ms)


# =============================================================================
# Q. Quality gates
# =============================================================================
func _quality() -> void:
	var ci: String = FileAccess.get_file_as_string("res://.github/workflows/ci.yml")
	_ok(ci.contains("tests/acceptance/t006b_acceptance.gd"), "Q01", "CI runs t006b acceptance")
	var rx: RegEx = RegEx.new()
	rx.compile("SCRIPT ERROR[^\\n]*/tmp/test\\.log|/tmp/test\\.log[^\\n]*SCRIPT ERROR")
	_ok(rx.search(ci) != null, "Q02", "CI G2 fails when tests/test_runner.gd output contains SCRIPT ERROR")
	var runner: String = FileAccess.get_file_as_string("res://tests/test_runner.gd")
	_ok(not runner.contains("var rec: Dictionary = n.get_module(\"buildings\").place_building("), "Q03",
		"test_t006_defensive_building_attack_fields no longer assigns place_building()'s int id to a Dictionary")
	var dec: String = FileAccess.get_file_as_string("res://docs/ai/DECISIONS.md")
	_ok(dec.contains("DEC-019"), "Q04", "DECISIONS.md has DEC-019 (personality-driven full-tree AI)")
	var state: String = FileAccess.get_file_as_string("res://docs/ai/PROJECT_STATE.md")
	_ok(state.contains("T006B_SUMMARY pass="), "Q05", "PROJECT_STATE.md quotes the final T006B_SUMMARY line")
