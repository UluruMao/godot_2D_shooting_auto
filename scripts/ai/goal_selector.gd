class_name GoalSelector
extends RefCounted

var profile := AutoProfile.new()
var _enemy_positions := PackedVector2Array()
var _enemy_reaches := PackedFloat64Array()
var _origin := Vector2.ZERO
var _heading := Vector2.ZERO

func choose(snapshot: Dictionary, navigation: NavigationGrid, previous: Dictionary, firing_check := Callable()) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var origin: Vector2 = snapshot.position
	_origin = origin
	_heading = Vector2(snapshot.get("velocity", Vector2.ZERO)).normalized()
	_enemy_positions.clear()
	_enemy_reaches.clear()
	for enemy: Dictionary in snapshot.enemies:
		if not enemy.dying or enemy.bomber:
			_enemy_positions.append(enemy.position)
			_enemy_reaches.append(float(enemy.blast_radius) + 12.0 if enemy.bomber else float(enemy.radius) + 18.0)
	var nearest: Dictionary = {}
	var distance := INF
	var retreat: bool = snapshot.get("retreat", false)
	for enemy: Dictionary in snapshot.enemies:
		if enemy.dying:
			continue
		var next := origin.distance_to(enemy.position)
		if next < distance:
			distance = next
			nearest = enemy
	if not nearest.is_empty():
		for i in 16:
			var anchor: Vector2 = nearest.position + Vector2.from_angle(TAU * i / 16.0) * profile.preferred_firing_range
			candidates.append(_candidate(snapshot, navigation, anchor, "ESCAPE" if retreat else "KITE", 0, 65.0, firing_check))
	# Distributed anchors can lead out of a corner even when every firing ring
	# around the nearest enemy is blocked. Only connected destinations qualify.
	for y in range(3, navigation.height, 4):
		for x in range(3, navigation.width, 4):
			var point := navigation.center(Vector2i(x, y))
			if navigation.is_blocked(Vector2i(x, y)):
				continue
			candidates.append(_candidate(snapshot, navigation, point, "ESCAPE" if retreat else "REPOSITION", 0, 65.0 if retreat else 40.0, firing_check))
	if not retreat:
		candidates.append(_candidate(snapshot, navigation, origin, "HOLD", 0, 65.0, firing_check))
	for item: Dictionary in snapshot.pickups:
		if retreat:
			candidates.append({"position": item.position, "kind": "COLLECT", "id": item.id,
				"base": 0.0, "utility": -INF, "reason": "RETREAT_BEFORE_LOOT", "room": 0.0, "firing": false})
			continue
		var travel := origin.distance_to(item.position) / maxf(float(snapshot.speed), 1.0)
		var value := profile.fresh_pickup_value if float(snapshot.effects.get(item.category, 0.0)) < 1.0 else profile.refresh_pickup_value
		var candidate := _candidate(snapshot, navigation, item.position, "COLLECT", item.id, value, firing_check)
		if travel + 0.25 >= float(item.remaining):
			candidate.reason = "PICKUP_TOO_LATE"
		candidates.append(candidate)
	var selected: Dictionary = {}
	for candidate in candidates:
		if candidate.reason != "":
			continue
		if selected.is_empty() or float(candidate.utility) > float(selected.utility):
			selected = candidate
	# Keep a still-valid goal unless the new choice improves utility materially.
	if not previous.is_empty() and not selected.is_empty():
		var old: Dictionary = {}
		if previous.kind == "COLLECT":
			for candidate in candidates:
				if candidate.kind == "COLLECT" and candidate.id == previous.id:
					old = candidate
		elif (not retreat and previous.kind != "ESCAPE") or (retreat and previous.kind == "ESCAPE"):
			old = _candidate(snapshot, navigation, previous.position, previous.kind, previous.id, float(previous.base), firing_check)
		var threshold := 4.0 if previous.kind == "KITE" else 12.0
		if not old.is_empty() and old.reason == "" and float(old.utility) + threshold >= float(selected.utility):
			selected = old
	if selected.is_empty():
		# A closed enemy ring may have no traversable route yet. Keep the
		# strategic destination so movement and fire can open that corridor.
		if retreat:
			for candidate in candidates:
				if candidate.kind == "ESCAPE" and candidate.reason == "NO_CONNECTED_ROUTE" and (selected.is_empty() or candidate.utility > selected.utility):
					selected = candidate
		if selected.is_empty():
			selected = {"position": origin, "kind": "HOLD", "id": 0, "base": 0.0,
				"utility": 0.0, "reason": "No acceptable destination; evaluate local escape"}
	return {"goal": selected, "candidates": candidates}

func _candidate(snapshot: Dictionary, navigation: NavigationGrid, point: Vector2, kind: String, id: int, base: float, firing_check := Callable()) -> Dictionary:
	var reason := ""
	var coordinate := navigation.cell(point)
	if navigation.is_blocked(coordinate):
		reason = "WALL_BLOCKED"
	if snapshot.has("avoid_goal") and point.distance_to(snapshot.avoid_goal) < 20.0:
		reason = "STUCK_DESTINATION"
	var room := navigation.room_at(point)
	var spawn_distance := INF
	for spawn: Vector2 in snapshot.get("spawn_points", PackedVector2Array()):
		spawn_distance = minf(spawn_distance, point.distance_to(spawn))
	var spawn_penalty := maxf(0.0, 1.0 - spawn_distance / profile.spawn_safety_radius) * 70.0
	# Destination clearance includes the arrival tolerance: stopping several
	# pixels before a waypoint must still leave the actual spawn danger zone.
	if kind != "COLLECT" and spawn_distance < profile.spawn_safety_radius + 16.0:
		reason = "SPAWN_LANE"
	if kind == "HOLD" and room < 0.45:
		reason = "LIMITED_ESCAPE_SPACE"
	var clearance := 100.0
	for i in _enemy_positions.size():
		clearance = minf(clearance, point.distance_to(_enemy_positions[i]) - _enemy_reaches[i])
	if clearance < 0.0:
		reason = "ENEMY_AT_DESTINATION"
	var reachable: PackedByteArray = snapshot.get("reachable", PackedByteArray())
	if reason.is_empty() and reachable.size() == navigation.blocked.size() and reachable[coordinate.y * navigation.width + coordinate.x] == 0:
		reason = "NO_CONNECTED_ROUTE"
	var origin := _origin
	var distance_weight := 0.15 if kind == "KITE" or kind == "ESCAPE" else 0.45
	var clearance_weight := 1.0 if kind != "COLLECT" else 0.25
	var continuity := _heading.dot(origin.direction_to(point)) * 8.0 if kind == "KITE" else 0.0
	var firing := firing_check.is_valid() and snapshot.has("target_position") and bool(firing_check.call(point, snapshot.target_position))
	return {"position": point, "kind": kind, "id": id, "base": base, "reason": reason, "room": room,
		"firing": firing, "utility": base - origin.distance_to(point) * distance_weight
			+ minf(clearance, 60.0) * clearance_weight + room * (80.0 if kind == "ESCAPE" else 35.0)
			- spawn_penalty + continuity + (35.0 if firing else 0.0)}
