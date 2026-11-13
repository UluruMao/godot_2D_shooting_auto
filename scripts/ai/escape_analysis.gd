extends RefCounted
## Bounded flood fill distinguishes nearby safe destinations from reachable ones.

var _cached_threats := PackedByteArray()
var _cached_terrain := PackedByteArray()
var _cached_reachable := PackedByteArray()
var _cached_start := -1
var _cached_width := 0
var _cached_count := 0

func assess(snapshot: Dictionary, navigation: NavigationGrid, profile: AutoProfile) -> Dictionary:
	var origin: Vector2 = snapshot.position
	var near_spawn := false
	for point: Vector2 in snapshot.get("spawn_points", PackedVector2Array()):
		near_spawn = near_spawn or origin.distance_to(point) < profile.spawn_safety_radius
	var clearance := INF
	var bearings: Array[float] = []
	var threats := PackedByteArray()
	threats.resize(navigation.width * navigation.height)
	for enemy: Dictionary in snapshot.enemies:
		if enemy.dying and not enemy.bomber:
			continue
		var reach: float = float(snapshot.radius) + float(enemy.radius) + 4.0
		if enemy.bomber:
			reach = maxf(reach, float(enemy.blast_radius) + float(snapshot.radius) + 4.0)
		var offset: Vector2 = enemy.position - origin
		clearance = minf(clearance, offset.length() - reach)
		if offset.length() - reach < profile.escape_trigger_distance:
			bearings.append(fposmod(offset.angle(), TAU))
		var forecast: Vector2 = enemy.velocity * 0.4
		var radius := reach + forecast.length()
		var location := navigation.cell(enemy.position)
		var cells := ceili(radius / navigation.cell_size) + 1
		for y in range(maxi(0, location.y - cells), mini(navigation.height, location.y + cells + 1)):
			for x in range(maxi(0, location.x - cells), mini(navigation.width, location.x + cells + 1)):
				var point := navigation.center(Vector2i(x, y))
				var closest := Geometry2D.get_closest_point_to_segment(point, enemy.position, enemy.position + forecast)
				if point.distance_to(closest) < reach:
					threats[y * navigation.width + x] = 1
	var room := navigation.room_at(origin)
	bearings.sort()
	var largest_gap := TAU
	if bearings.size() >= 2:
		largest_gap = bearings[0] + TAU - bearings[-1]
		for i in range(1, bearings.size()):
			largest_gap = maxf(largest_gap, bearings[i] - bearings[i - 1])
	var closing_ring := bearings.size() >= 3 and largest_gap < PI * 1.25
	var corner_pressure: bool = clearance < profile.escape_trigger_distance and room < 0.65
	var reason := "LEAVE_SPAWN_LANE" if near_spawn else ("ESCAPE_ENCIRCLEMENT" if closing_ring else ("LEAVE_CONFINED_SPACE" if corner_pressure else ""))
	var start := navigation.nearest_free(origin)
	var start_index := start.y * navigation.width + start.x
	var can_reuse: bool = _cached_width == navigation.width and threats == _cached_threats and navigation.blocked == _cached_terrain
	can_reuse = can_reuse and _cached_start >= 0 and not navigation.is_blocked(start) and _cached_threats[_cached_start] == 0
	can_reuse = can_reuse and _cached_reachable[start_index] != 0 and threats[start_index] == 0
	if can_reuse:
		var trapped: bool = _cached_count < 24 and clearance < profile.escape_trigger_distance
		return {"retreat": not reason.is_empty() or trapped, "reason": "BREAK_ENEMY_BLOCKADE" if trapped else reason,
			"room": room, "clearance": clearance, "reachable": _cached_reachable.duplicate(), "threats": threats,
			"reachable_cells": _cached_count, "trapped": trapped, "connectivity_reused": true}
	var reachable := PackedByteArray()
	reachable.resize(threats.size())
	var queue := PackedInt32Array()
	queue.resize(threats.size())
	var tail := 0
	if not navigation.is_blocked(start):
		reachable[start.y * navigation.width + start.x] = 1
		queue[tail] = start.y * navigation.width + start.x
		tail += 1
	var head := 0
	var offsets := PackedInt32Array([-1, 1, -navigation.width, navigation.width])
	while head < tail:
		var index := queue[head]
		head += 1
		for offset: int in offsets:
			var next := index + offset
			if next < 0 or next >= threats.size() or (offset == -1 and index % navigation.width == 0) or (offset == 1 and next % navigation.width == 0):
				continue
			if reachable[next] or navigation.blocked[next] or threats[next]:
				continue
			# Four-neighbour connectivity equals legal eight-neighbour connectivity
			# when diagonals require both adjacent orthogonal cells to be free.
			reachable[next] = 1
			queue[tail] = next
			tail += 1
	var trapped: bool = tail < 24 and clearance < profile.escape_trigger_distance
	# Freeze the cache keys: packed arrays can be mutated through another owner.
	_cached_threats = threats.duplicate()
	_cached_terrain = navigation.blocked.duplicate()
	_cached_reachable = reachable.duplicate()
	_cached_width = navigation.width
	_cached_start = start_index if tail > 0 else -1
	_cached_count = tail
	return {"retreat": not reason.is_empty() or trapped, "reason": "BREAK_ENEMY_BLOCKADE" if trapped else reason,
		"room": room, "clearance": clearance, "reachable": reachable, "threats": threats,
		"reachable_cells": tail, "trapped": trapped, "connectivity_reused": false}
