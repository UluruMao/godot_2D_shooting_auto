class_name AutoController
extends PlayerController
## Runtime coordinator; algorithms operate on snapshots and explicit query APIs.
enum Planner { BASELINE, ROUTE_ONLY, PREDICTIVE }
const EscapeAnalysis := preload("res://scripts/ai/escape_analysis.gd")

var planner := Planner.PREDICTIVE
var navigation := NavigationGrid.new()
var decision := AutoDecision.new()
var steering := LocalSteering.new()
var goal_selector := GoalSelector.new()
var profile := AutoProfile.new()
var _goal: Dictionary = {}
var _goal_candidates: Array[Dictionary] = []
var _route: Dictionary = {"status": "not_requested", "path": PackedVector2Array(), "explored": PackedInt32Array(), "cost": 0.0}
var _route_tick := 0
var _waypoint := 0
var _goal_due := 0.0
var _target_id := 0
var _target_lock := 0.0
var _previous := Vector2.ZERO
var _space: PhysicsDirectSpaceState2D
var _shape := CircleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()
var _warned := false
var _last_position := Vector2.ZERO
var _stuck_time := 0.0
var _avoid_goal := Vector2(INF, INF)
var _avoid_time := 0.0
var _tactical: Dictionary = {}
var _escape_left := 0.0
var _escape_analysis := EscapeAnalysis.new()
var _evasion_left := 0.0
var profiling_enabled := "--profile-ai" in OS.get_cmdline_user_args()

func _init() -> void:
	wants_world = true
	_shape.radius = 6.0
	_query.shape = _shape
	_query.collision_mask = 1
	configure(profile)

func configure(settings: AutoProfile) -> void:
	profile = settings if settings != null else AutoProfile.new()
	goal_selector.profile = profile
	steering.horizon = profile.prediction_horizon
	steering.direction_count = profile.sampled_directions
	steering.proactive_margin = profile.route_clearance_margin

func reset() -> void:
	_goal.clear()
	_goal_due = 0.0
	_target_id = 0
	_target_lock = 0.0
	_previous = Vector2.ZERO
	_stuck_time = 0.0
	_avoid_time = 0.0
	_tactical.clear()
	_escape_left = 0.0
	_evasion_left = 0.0
	decision = AutoDecision.new()

func sample(context: Dictionary, delta: float) -> ControlFrame:
	var started := Time.get_ticks_usec()
	var stage_started := started
	_space = context.space
	decision = AutoDecision.new()
	decision.tick = context.tick
	decision.origin = context.position
	decision.enemies = context.enemies
	decision.spawn_points = context.get("spawn_points", PackedVector2Array())
	decision.horizon = profile.prediction_horizon
	if _previous.length() > 0.1 and Vector2(context.position).distance_to(_last_position) < 0.1:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_position = context.position
	_avoid_time = maxf(0.0, _avoid_time - delta)
	if _stuck_time > 0.6:
		_avoid_goal = _goal.get("position", context.position)
		_avoid_time = 1.0
		_goal.clear()
		_goal_due = 0.0
		_stuck_time = 0.0
	if _avoid_time > 0.0:
		context.avoid_goal = _avoid_goal
	if profiling_enabled:
		decision.stage_usec.observation = int(context.get("observation_usec", 0))
		stage_started = _mark_stage("maintenance", stage_started)
	if planner != Planner.BASELINE and not navigation.ready and not navigation.build(_space):
		decision.reason = navigation.diagnostic
		if not _warned:
			push_warning(navigation.diagnostic)
			_warned = true
		return ControlFrame.new()
	if profiling_enabled:
		stage_started = _mark_stage("navigation_init", stage_started)
	_goal_due -= delta
	_evasion_left = maxf(0.0, _evasion_left - delta)
	_escape_left = maxf(0.0, _escape_left - delta)
	if planner == Planner.PREDICTIVE:
		if _goal_due <= 0.0 or _tactical.is_empty():
			_tactical = _escape_analysis.assess(context, navigation, profile)
			if _tactical.retreat:
				_escape_left = profile.escape_commit_time
		context.retreat = _escape_left > 0.0
		context.reachable = _tactical.reachable
		context.steering_horizon = profile.escape_horizon if context.retreat else profile.prediction_horizon
		decision.horizon = context.steering_horizon
		decision.tactical_reason = _tactical.reason
		decision.reachable_cells = _tactical.reachable_cells
		decision.escape_room = _tactical.room
	if profiling_enabled:
		stage_started = _mark_stage("tactical", stage_started)
	_target_lock = maxf(0.0, _target_lock - delta)
	var target := _select_target(context)
	if not target.is_empty():
		context.target_position = target.position
	if profiling_enabled:
		stage_started = _mark_stage("targeting", stage_started)
	var invalid_pickup: bool = not _goal.is_empty() and _goal.kind == "COLLECT"
	if invalid_pickup:
		for item: Dictionary in context.pickups:
			if item.id == _goal.id:
				invalid_pickup = false
	if planner == Planner.BASELINE:
		_goal = {"position": context.position if target.is_empty() else target.position, "kind": "BASELINE", "id": 0, "base": 0.0}
		_route = {"status": "not_used_by_baseline", "path": PackedVector2Array(), "explored": PackedInt32Array(), "cost": 0.0}
	elif _goal_due <= 0.0 or _goal.is_empty() or invalid_pickup:
		var choice := goal_selector.choose(context, navigation, _goal, _clear_firing_line)
		_goal = choice.goal
		_goal_candidates = choice.candidates
		if profiling_enabled:
			stage_started = _mark_stage("goal_selection", stage_started)
		var risk := navigation.risk_field(context.enemies) if planner == Planner.PREDICTIVE else PackedFloat64Array()
		var threats: PackedByteArray = _tactical.get("threats", PackedByteArray()) if planner == Planner.PREDICTIVE else PackedByteArray()
		_route = navigation.route(context.position, _goal.position, risk, threats)
		if _route.status != "found" and context.get("retreat", false) and _tactical.get("trapped", false):
			# A static route identifies the corridor to clear with fire. Steering
			# still checks every movement against the living enemies blocking it.
			_route = navigation.route(context.position, _goal.position, risk)
			_route["blocked_by_enemies"] = _route.status == "found"
		# Straight-line ETA is only a preliminary filter. Verify collection against
		# the actual routed travel distance before committing to it.
		if _goal.kind == "COLLECT" and _route.status == "found":
			var distance := 0.0
			var previous: Vector2 = context.position
			for point: Vector2 in _route.path:
				distance += previous.distance_to(point)
				previous = point
			for item: Dictionary in context.pickups:
				if item.id == _goal.id and distance / maxf(float(context.speed), 1.0) + 0.25 >= float(item.remaining):
					for candidate in _goal_candidates:
						if candidate.id == item.id:
							candidate.reason = "ROUTE_ARRIVES_TOO_LATE"
					_goal = {"position": context.position, "kind": "HOLD", "id": 0, "base": 0.0}
					_route = {"status": "pickup_too_late", "path": PackedVector2Array(), "explored": _route.explored, "cost": _route.cost}
		_route_tick = context.tick
		_waypoint = 0
		_goal_due = profile.goal_interval
	if profiling_enabled:
		stage_started = _mark_stage("routing", stage_started)
	var preferred := _preferred_direction(context.position)
	if not _route.path.is_empty():
		context.route_destination = _route.path[-1]
	context.escape_arrived = _route.status == "found" and Vector2(context.position).distance_to(_goal.position) < 12.0
	if context.get("retreat", false) and preferred.is_zero_approx() and Vector2(context.position).distance_to(_goal.position) > 12.0:
		preferred = Vector2(context.position).direction_to(_goal.position)
	if context.get("retreat", false):
		context.escape_direction = preferred
		target = _select_target(context, target)
	decision.objective = _goal.kind
	decision.goal = _goal.position
	decision.goal_candidates = _goal_candidates
	decision.reason = "Route toward a useful pickup" if _goal.kind == "COLLECT" else "Maintain firing distance and escape space"
	if context.get("retreat", false):
		decision.reason = "Retreat toward reachable open ground before collecting items"
	if _avoid_time > 0.0:
		decision.reason = "Stuck recovery: choose a different destination"
	decision.path = _route.path
	decision.path_status = _route.status
	decision.route_blockaded = _route.get("blocked_by_enemies", false)
	if decision.route_blockaded:
		decision.reason = "Shoot an opening along the blocked escape route"
	decision.path_cost = _route.cost
	decision.explored = _route.explored
	decision.route_tick = _route_tick
	if profiling_enabled:
		stage_started = _mark_stage("route_following", stage_started)
	var movement: Vector2
	if planner == Planner.PREDICTIVE:
		context.keep_evasion = _evasion_left > 0.0
		var result := steering.choose(context, preferred, _previous, _sweep, navigation.room_at)
		movement = result.movement
		if result.rule in ["LOCAL_SEARCH", "ESCAPE_SEARCH"] and not result.emergency and not movement.is_zero_approx() and movement.dot(preferred) < 0.5:
			_evasion_left = 0.2
		decision.endpoint = result.endpoint
		decision.candidates = result.candidates
		decision.selected = result.selected
		decision.emergency = result.emergency
		decision.selection_rule = result.rule
		if result.holding:
			decision.reason = "Hold a reached destination with clear escape space"
		if decision.emergency:
			decision.reason = "All sampled moves failed a check; use best evaluated emergency move"
	elif planner == Planner.BASELINE:
		movement = Vector2.ZERO
		if not target.is_empty():
			var offset: Vector2 = target.position - Vector2(context.position)
			movement = -offset.normalized() if offset.length() < 85.0 else offset.normalized()
		if _sweep(context.position, movement * float(context.speed) * delta) < 1.0:
			movement = Vector2.ZERO
		decision.reason = "Baseline: approach or retreat from the selected target"
		decision.endpoint = context.position + movement * float(context.speed) * 0.2
	else:
		movement = preferred if _sweep(context.position, preferred * float(context.speed) * delta) >= 1.0 else Vector2.ZERO
		decision.reason = "A* route following; predictive avoidance disabled"
		decision.endpoint = context.position + movement * float(context.speed) * 0.2
	var aim: Vector2 = context.aim
	if profiling_enabled:
		stage_started = _mark_stage("steering", stage_started)
	if not target.is_empty():
		decision.target_id = target.id
		var intercept := CombatAim.intercept(context.position, target.position, target.velocity)
		decision.aim_point = intercept.position
		aim = (decision.aim_point - Vector2(context.position)).normalized()
		# Check the full corridor, including the segment before the muzzle, so
		# an offset spawn cannot make a shot through a nearby wall look clear.
		var ray := PhysicsRayQueryParameters2D.create(context.position, decision.aim_point, 5)
		var hit := _space.intersect_ray(ray)
		decision.fire = hit.is_empty() or int(hit.collider_id) == int(target.id)
		decision.shot_reason = "PREDICTED_INTERCEPT" if intercept.predicted else "DIRECT_AIM_FALLBACK"
		if int(context.get("breakout_target_id", 0)) == int(target.id) and decision.fire:
			decision.shot_reason = "CLEAR_ESCAPE_CORRIDOR"
		if not decision.fire:
			decision.shot_reason = "FIRING_CORRIDOR_BLOCKED"
		if target.bomber and Vector2(context.position).distance_to(target.position) < float(target.blast_radius) + 12.0:
			decision.fire = false
			decision.shot_reason = "GAIN_DISTANCE_BEFORE_BOMBER_KILL"
	_previous = movement
	if profiling_enabled:
		_mark_stage("aiming", stage_started)
	decision.duration_usec = Time.get_ticks_usec() - started + int(context.get("observation_usec", 0))
	return ControlFrame.new(movement, aim, decision.fire)

func _mark_stage(name: String, started: int) -> int:
	var now := Time.get_ticks_usec()
	decision.stage_usec[name] = int(decision.stage_usec.get(name, 0)) + now - started
	return now

func _select_target(context: Dictionary, fallback: Dictionary = {}) -> Dictionary:
	context.erase("breakout_target_id")
	# While retreating, shoot a vulnerable enemy obstructing the intended exit
	# instead of preserving a lock on an unrelated enemy across the arena.
	var escape: Vector2 = context.get("escape_direction", Vector2.ZERO)
	var blocker: Dictionary = {}
	var blocker_score := INF
	if not escape.is_zero_approx():
		for enemy: Dictionary in context.enemies:
			var offset: Vector2 = enemy.position - Vector2(context.position)
			if enemy.dying or offset.length() > 110.0 or offset.normalized().dot(escape) < 0.55 or not _clear_firing_line(context.position, enemy.position):
				continue
			var score: float = float(enemy.health) * 12.0 + offset.length() * 0.15 + (35.0 if enemy.bomber else 0.0)
			if score < blocker_score:
				blocker_score = score
				blocker = enemy
	if not blocker.is_empty():
		context.breakout_target_id = int(blocker.id)
		_target_id = blocker.id
		_target_lock = 0.0
		return blocker
	if not fallback.is_empty():
		return fallback
	var nearest: Dictionary = {}
	var incumbent: Dictionary = {}
	var distance := INF
	var incumbent_score := INF
	var incumbent_clear := false
	for enemy: Dictionary in context.enemies:
		if enemy.dying:
			continue
		var clear := _clear_firing_line(context.position, enemy.position)
		var candidate: float = Vector2(context.position).distance_squared_to(enemy.position) + (0.0 if clear else 40000.0)
		if enemy.id == _target_id:
			incumbent = enemy
			incumbent_score = candidate
			incumbent_clear = clear
		if candidate < distance:
			distance = candidate
			nearest = enemy
	if not incumbent.is_empty() and ((_target_lock > 0.0 and incumbent_clear) or incumbent_score < distance * 1.3):
		return incumbent
	if not nearest.is_empty() and int(nearest.id) != _target_id:
		_target_id = nearest.id
		_target_lock = 0.25
	return nearest

func _clear_firing_line(origin: Vector2, target: Vector2) -> bool:
	return _space.intersect_ray(PhysicsRayQueryParameters2D.create(origin, target, 1)).is_empty()

func _preferred_direction(origin: Vector2) -> Vector2:
	var path: PackedVector2Array = _route.path
	if path.is_empty():
		return Vector2.ZERO
	while _waypoint < path.size() - 1 and origin.distance_to(path[_waypoint]) < 9.0:
		_waypoint += 1
	var lookahead := _waypoint
	for i in range(_waypoint + 1, mini(_waypoint + 4, path.size())):
		if _sweep(origin, path[i] - origin) >= 0.999:
			lookahead = i
	var arrival_radius := 6.0 if _goal.get("kind", "") == "COLLECT" else 9.0
	if origin.distance_to(path[lookahead]) < arrival_radius:
		return Vector2.ZERO
	return origin.direction_to(path[lookahead])

func _sweep(origin: Vector2, motion: Vector2) -> float:
	if motion.is_zero_approx():
		return 1.0
	_query.transform = Transform2D(0, origin)
	_query.motion = motion
	var result := _space.cast_motion(_query)
	return float(result[0])
