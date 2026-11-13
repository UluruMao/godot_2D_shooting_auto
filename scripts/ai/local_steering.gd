class_name LocalSteering
extends RefCounted
## Check the route first; spend the full sampling budget only near a threat.

var horizon := 0.65
var direction_count := 16
var proactive_margin := 8.0
var _positions := PackedVector2Array()
var _velocities := PackedVector2Array()
var _end_positions := PackedVector2Array()
var _reaches := PackedFloat64Array()
var _directions: Array[Vector2] = []
var _cached_direction_count := 0

static func closest_distance(offset: Vector2, relative_velocity: Vector2, duration: float) -> float:
	var time := 0.0
	if relative_velocity.length_squared() > 0.000001:
		time = clampf(-offset.dot(relative_velocity) / relative_velocity.length_squared(), 0.0, duration)
	return (offset + relative_velocity * time).length()

static func contact_time(offset: Vector2, relative_velocity: Vector2, reach: float, duration: float) -> float:
	var c := offset.length_squared() - reach * reach
	if c <= 0.0:
		return 0.0
	var a := relative_velocity.length_squared()
	var b := 2.0 * offset.dot(relative_velocity)
	var discriminant := b * b - 4.0 * a * c
	if a < 0.000001 or discriminant < 0.0:
		return INF
	var time := (-b - sqrt(discriminant)) / (2.0 * a)
	return time if time >= 0.0 and time < duration else INF

func choose(snapshot: Dictionary, preferred: Vector2, previous: Vector2, sweep: Callable, room_query := Callable()) -> Dictionary:
	_prepare_threats(snapshot)
	if snapshot.get("keep_evasion", false) and not previous.is_zero_approx():
		var continued := _evaluate(snapshot, previous, preferred, previous, sweep, room_query)
		if continued.legal and float(continued.clearance) >= proactive_margin:
			var checked: Array[Dictionary] = [continued]
			return {"movement": previous, "endpoint": continued.endpoint, "candidates": checked,
				"selected": 0, "emergency": false, "holding": false, "rule": "CONTINUE_EVASION"}
	var first := _evaluate(snapshot, preferred, preferred, previous, sweep, room_query)
	var holding := preferred.is_zero_approx()
	var retreat: bool = snapshot.get("retreat", false)
	var arrived_safely: bool = snapshot.get("escape_arrived", false) and float(first.clearance) >= proactive_margin * 2.0
	if first.legal and ((holding and (not retreat or arrived_safely)) or (not holding and float(first.clearance) >= proactive_margin)):
		var checked: Array[Dictionary] = [first]
		return {"movement": first.movement, "endpoint": first.endpoint, "candidates": checked,
			"selected": 0, "emergency": false, "holding": holding, "rule": "HOLD_CHECK" if holding else "ROUTE_CHECK"}
	var choices: Array[Vector2] = [Vector2.ZERO]
	if not preferred.is_zero_approx():
		choices.append(preferred.normalized())
	if not previous.is_zero_approx():
		choices.append(previous)
	if _cached_direction_count != direction_count:
		_directions.clear()
		for i in direction_count:
			_directions.append(Vector2.from_angle(TAU * i / direction_count))
		_cached_direction_count = direction_count
	for direction: Vector2 in _directions:
		choices.append(direction)
		choices.append(direction * 0.5)
	var candidates: Array[Dictionary] = []
	var selected := -1
	for movement in choices:
		var candidate := _evaluate(snapshot, movement, preferred, previous, sweep, room_query)
		candidates.append(candidate)
		if selected < 0 or _better(candidate, candidates[selected]):
			selected = candidates.size() - 1
	if candidates[selected].legal:
		for i in candidates.size():
			var candidate := candidates[i]
			if candidate.legal and Vector2(candidate.movement).is_equal_approx(previous) and float(candidate.score) + (8.0 if retreat else 20.0) >= float(candidates[selected].score):
				selected = i
				break
	var winner := candidates[selected]
	return {"movement": winner.movement, "endpoint": winner.endpoint, "candidates": candidates,
		"selected": selected, "emergency": not winner.legal, "holding": false, "rule": "ESCAPE_SEARCH" if retreat else "LOCAL_SEARCH"}

func _prepare_threats(snapshot: Dictionary) -> void:
	# Values invariant across candidate movements are copied once per observation.
	# Packed arrays avoid repeated dictionary lookups inside the sampled loop.
	_positions.clear()
	_velocities.clear()
	_end_positions.clear()
	_reaches.clear()
	var duration: float = snapshot.get("steering_horizon", horizon)
	for enemy: Dictionary in snapshot.enemies:
		if enemy.dying and not enemy.bomber:
			continue
		var position: Vector2 = enemy.position
		var velocity: Vector2 = enemy.velocity
		var reach: float = float(snapshot.radius) + float(enemy.radius) + 5.0
		if enemy.bomber:
			reach = maxf(reach, float(snapshot.radius) + float(enemy.blast_radius) + 5.0)
		_positions.append(position)
		_velocities.append(velocity)
		_end_positions.append(position + velocity * duration)
		_reaches.append(reach)

func _evaluate(snapshot: Dictionary, movement: Vector2, preferred: Vector2, previous: Vector2, sweep: Callable, room_query: Callable) -> Dictionary:
	var origin: Vector2 = snapshot.position
	var velocity: Vector2 = movement * float(snapshot.speed)
	var duration: float = snapshot.get("steering_horizon", horizon)
	var fraction: float = clampf(sweep.call(origin, velocity * duration), 0.0, 1.0)
	var travel_time := duration * fraction
	if snapshot.has("route_destination") and not movement.is_zero_approx():
		var to_goal: Vector2 = snapshot.route_destination - origin
		if movement.normalized().dot(to_goal.normalized()) > 0.98:
			# Forecast arrival followed by stopping, rather than continuing at
			# full speed past the final waypoint into a wall or enemy.
			travel_time = minf(travel_time, to_goal.length() / velocity.length())
	var endpoint := origin + velocity * travel_time
	var clearance := 120.0
	var ending_clearance := 120.0
	var survival := duration
	for i in _positions.size():
		var enemy_position := _positions[i]
		var enemy_velocity := _velocities[i]
		var reach := _reaches[i]
		var closest := closest_distance(enemy_position - origin, enemy_velocity - velocity, travel_time)
		if closest < reach:
			survival = minf(survival, contact_time(enemy_position - origin, enemy_velocity - velocity, reach, travel_time))
		if travel_time < duration:
			var stopped_closest := closest_distance(enemy_position + enemy_velocity * travel_time - endpoint, enemy_velocity, duration - travel_time)
			closest = minf(closest, stopped_closest)
			if stopped_closest < reach:
				survival = minf(survival, travel_time + contact_time(enemy_position + enemy_velocity * travel_time - endpoint, enemy_velocity, reach, duration - travel_time))
		clearance = minf(clearance, closest - reach)
		ending_clearance = minf(ending_clearance, _end_positions[i].distance_to(endpoint) - reach)
	var blocked := not movement.is_zero_approx() and travel_time < 0.1
	var reason := "WALL_BLOCKED" if blocked else ("PREDICTED_CONTACT" if clearance < 0.0 else "")
	var progress := (endpoint - origin).dot(preferred)
	var score := progress * 2.0 + minf(clearance, 60.0) * 2.0 + minf(ending_clearance, 60.0) + movement.dot(previous) * 5.0
	if snapshot.get("retreat", false):
		score += progress + (float(room_query.call(endpoint)) * 45.0 if room_query.is_valid() else 0.0)
	# If every move fails, the common initial overlap should not make standing
	# still look as useful as reaching an opening after a brief exposure.
	var escape_score := ending_clearance * 3.0 + progress * 2.0 + (endpoint - origin).length() * 0.25
	return {"movement": movement, "endpoint": endpoint, "clearance": clearance,
		"score": score, "reason": reason, "legal": reason == "", "collision_time": survival,
		"ending_clearance": ending_clearance, "escape_score": escape_score}

func _better(candidate: Dictionary, incumbent: Dictionary) -> bool:
	if candidate.legal != incumbent.legal:
		return candidate.legal
	if candidate.reason == "WALL_BLOCKED" and incumbent.reason != "WALL_BLOCKED":
		return false
	if incumbent.reason == "WALL_BLOCKED" and candidate.reason != "WALL_BLOCKED":
		return true
	if not candidate.legal:
		if absf(float(candidate.collision_time) - float(incumbent.collision_time)) > 0.06:
			return float(candidate.collision_time) > float(incumbent.collision_time)
		return float(candidate.escape_score) > float(incumbent.escape_score) + 0.0001
	return float(candidate.score) > float(incumbent.score) + 0.0001
