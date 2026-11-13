extends RefCounted

var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func snapshot(enemies: Array) -> Dictionary:
	return {"position": Vector2.ZERO, "speed": 100.0, "radius": 6.0, "enemies": enemies}

func enemy(position: Vector2, velocity: Vector2) -> Dictionary:
	return {"id": 1, "position": position, "velocity": velocity, "radius": 8.0,
		"bomber": false, "blast_radius": 0.0, "dying": false, "health": 2}

func test_crossing_enemy_rejects_straight_route() -> void:
	var steering := LocalSteering.new()
	var world := snapshot([enemy(Vector2(50, -30), Vector2(0, 60))])
	var result := steering.choose(world, Vector2.RIGHT, Vector2.RIGHT, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	var crossing_rejected := false
	for candidate: Dictionary in result.candidates:
		if candidate.movement == Vector2.RIGHT:
			crossing_rejected = crossing_rejected or candidate.reason == "PREDICTED_CONTACT"
	check(crossing_rejected, "a future crossing is rejected even when the route is clear now")
	check(not result.emergency and result.movement != Vector2.RIGHT, "a passing alternative takes priority over route progress")

func test_wall_and_emergency_choices_are_explicit() -> void:
	var steering := LocalSteering.new()
	var blocked := func(_p: Vector2, motion: Vector2) -> float: return 0.0 if motion.x > 0.0 else 1.0
	var result := steering.choose(snapshot([]), Vector2.RIGHT, Vector2.RIGHT, blocked)
	check(result.movement.x <= 0.0 and not result.emergency, "wall-blocked progress cannot outrank legal stopping")
	var threat := enemy(Vector2.ZERO, Vector2.ZERO)
	threat.radius = 1000.0
	result = steering.choose(snapshot([threat]), Vector2.RIGHT, Vector2.ZERO, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	check(result.emergency, "no passing sample is reported as an emergency, not claimed safe")

func test_reached_goal_does_not_create_clearance_roaming() -> void:
	var steering := LocalSteering.new()
	var world := snapshot([enemy(Vector2(60, 0), Vector2.ZERO)])
	var result := steering.choose(world, Vector2.ZERO, Vector2.LEFT, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	check(result.holding and result.movement == Vector2.ZERO, "a reached goal with passing checks holds position instead of oscillating")

func test_calm_route_is_preserved_without_searching_alternatives() -> void:
	var steering := LocalSteering.new()
	var result := steering.choose(snapshot([]), Vector2.RIGHT, Vector2.RIGHT, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	check(result.movement == Vector2.RIGHT and result.rule == "ROUTE_CHECK", "a clear route retains its intended movement")
	check(result.candidates.size() == 1, "unevaluated alternatives are not presented as rejected candidates")

func test_intercept_matches_projectile_equation() -> void:
	var target := Vector2(200, 50)
	var velocity := Vector2(20, 30)
	var result := CombatAim.intercept(Vector2.ZERO, target, velocity)
	var predicted: Vector2 = result.position
	check(result.predicted and float(result.time) > 0.0, "reachable moving target has a future intercept")
	var projectile := predicted.normalized() * (14.0 + 320.0 * float(result.time))
	check(projectile.distance_to(target + velocity * float(result.time)) < 0.001, "intercept includes muzzle offset and projectile travel")
	result = CombatAim.intercept(Vector2.ZERO, Vector2(100, 0), Vector2(500, 0))
	check(not result.predicted and result.position == Vector2(100, 0), "unreachable target uses labelled direct-aim fallback")

func test_expiring_pickup_cannot_survive_goal_hysteresis() -> void:
	var navigation := NavigationGrid.new()
	navigation.blocked.resize(32 * 32)
	var world := snapshot([enemy(Vector2(180, 180), Vector2.ZERO)])
	world.position = Vector2(30, 30)
	world.effects = {}
	world.pickups = [{"id": 42, "position": Vector2(35, 35), "category": 0, "remaining": 0.01, "duration": 5.0}]
	var old := {"kind": "COLLECT", "id": 42, "position": Vector2(35, 35), "base": 120.0}
	var choice := GoalSelector.new().choose(world, navigation, old)
	check(choice.goal.id != 42, "hysteresis cannot preserve a pickup that expires before arrival")
	var explanation := false
	for candidate: Dictionary in choice.candidates:
		if candidate.id == 42:
			explanation = candidate.reason == "PICKUP_TOO_LATE"
	check(explanation, "rejected pickup exposes its actual expiry check")

func test_destination_prefers_a_clear_firing_opportunity() -> void:
	var navigation := NavigationGrid.new()
	navigation.blocked.resize(32 * 32)
	var world := snapshot([enemy(Vector2(128, 128), Vector2.ZERO)])
	world.position = Vector2(20, 20)
	world.effects = {}
	world.pickups = []
	world.target_position = Vector2(128, 128)
	var check_line := func(origin: Vector2, _target: Vector2) -> bool: return origin.x > 128.0
	var choice := GoalSelector.new().choose(world, navigation, {}, check_line)
	check(choice.goal.firing and Vector2(choice.goal.position).x > 128.0, "a firing position can outrank a closer blocked position")

func test_native_adapter_and_input_validation() -> void:
	check(ClassDB.class_exists("ShooterPathfinder"), "native extension is loaded")
	if not ClassDB.class_exists("ShooterPathfinder"):
		return
	var pathfinder: RefCounted = ClassDB.instantiate("ShooterPathfinder")
	var cells := PackedByteArray()
	cells.resize(9)
	var result: Dictionary = pathfinder.call("find_path", cells, 3, 3, Vector2i.ZERO, Vector2i(2, 2), PackedFloat64Array(), 4096, true)
	check(result.status == "found" and is_equal_approx(result.cost, 2.0 * sqrt(2.0)), "Godot adapter returns native diagonal shortest path")
	check(result.path[0] == Vector2.ZERO and result.path[-1] == Vector2(2, 2), "adapter preserves coordinates")
	result = pathfinder.call("find_path", cells, 3, 3, Vector2i.ZERO, Vector2i(2, 2), PackedFloat64Array(), 0, true)
	check(result.status == "budget_exceeded", "adapter preserves bounded-work status")
	result = pathfinder.call("find_path", PackedByteArray(), 3, 3, Vector2i.ZERO, Vector2i(2, 2), PackedFloat64Array(), 4096, true)
	check(result.status == "invalid_input", "malformed packed grid is rejected")
