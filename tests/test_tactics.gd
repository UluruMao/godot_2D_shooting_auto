extends RefCounted

const EscapeAnalysis := preload("res://scripts/ai/escape_analysis.gd")
var checks := 0
var failures: Array[String] = []

class ClearLineController extends AutoController:
	func _clear_firing_line(_origin: Vector2, _target: Vector2) -> bool:
		return true

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func navigation() -> NavigationGrid:
	var grid := NavigationGrid.new()
	grid.blocked.resize(grid.width * grid.height)
	return grid

func world(position := Vector2(128, 128)) -> Dictionary:
	return {"position": position, "speed": 120.0, "radius": 6.0, "velocity": Vector2.ZERO,
		"enemies": [], "pickups": [], "effects": {}, "spawn_points": PackedVector2Array()}

func enemy(position: Vector2, id := 1, health := 3) -> Dictionary:
	return {"id": id, "health": health, "position": position, "velocity": Vector2.ZERO,
		"radius": 8.0, "bomber": false, "blast_radius": 0.0, "dying": false}

func test_collected_spawn_drop_cannot_leave_an_idle_spawn_goal() -> void:
	var grid := navigation()
	var snapshot := world(Vector2(20, 144))
	snapshot.spawn_points = PackedVector2Array([Vector2(8, 144)])
	var assessment := EscapeAnalysis.new().assess(snapshot, grid, AutoProfile.new())
	check(assessment.retreat and assessment.reason == "LEAVE_SPAWN_LANE", "an empty spawn lane is still a strategic hazard")
	snapshot.merge(assessment, true)
	var choice := GoalSelector.new().choose(snapshot, grid, {"position": snapshot.position, "kind": "HOLD", "id": 0, "base": 65.0})
	check(choice.goal.kind == "ESCAPE" and Vector2(choice.goal.position).distance_to(Vector2(8, 144)) >= 64.0, "holding on a collected drop is replaced by a destination outside the spawn lane including arrival tolerance")
	check(Vector2(choice.goal.position).distance_to(snapshot.position) > 15.0, "leaving a spawn lane produces real displacement")

func test_retreat_invalidates_a_valuable_pickup_and_previous_lock() -> void:
	var grid := navigation()
	var snapshot := world(Vector2(20, 144))
	snapshot.spawn_points = PackedVector2Array([Vector2(8, 144)])
	snapshot.pickups = [{"id": 42, "position": Vector2(25, 144), "category": 0, "remaining": 20.0}]
	snapshot.merge(EscapeAnalysis.new().assess(snapshot, grid, AutoProfile.new()), true)
	var choice := GoalSelector.new().choose(snapshot, grid, {"position": Vector2(25, 144), "kind": "COLLECT", "id": 42, "base": 160.0})
	check(choice.goal.kind == "ESCAPE", "pickup value and hysteresis cannot override strategic retreat")
	var explained := false
	for candidate: Dictionary in choice.candidates:
		if candidate.id == 42:
			explained = candidate.reason == "RETREAT_BEFORE_LOOT"
	check(explained, "the inspector receives the real pickup rejection reason")

func test_corner_pressure_prefers_roomier_connected_ground() -> void:
	var grid := navigation()
	var snapshot := world(Vector2(12, 12))
	snapshot.enemies = [enemy(Vector2(12, 75)), enemy(Vector2(75, 12), 2)]
	var assessment := EscapeAnalysis.new().assess(snapshot, grid, AutoProfile.new())
	check(assessment.retreat and assessment.reason == "LEAVE_CONFINED_SPACE", "a closing pincer at walls triggers retreat before contact")
	snapshot.merge(assessment, true)
	var choice := GoalSelector.new().choose(snapshot, grid, {})
	check(choice.goal.kind == "ESCAPE" and grid.room_at(choice.goal.position) > grid.room_at(snapshot.position), "corner escape seeks more open ground rather than retaining a firing corner")

func test_flood_fill_respects_walls_without_row_wrapping() -> void:
	var grid := navigation()
	for y in grid.height:
		grid.blocked[y * grid.width + 16] = 1
	var assessment := EscapeAnalysis.new().assess(world(Vector2(28, 28)), grid, AutoProfile.new())
	check(assessment.reachable_cells == 16 * grid.height, "flood fill stops at the separating wall and grid boundaries")
	check(assessment.reachable[4 * grid.width + 24] == 0, "nearby Euclidean distance does not imply a connected exit")

func test_connectivity_cache_invalidates_on_terrain_and_threat_changes() -> void:
	var grid := navigation()
	var analysis := EscapeAnalysis.new()
	var snapshot := world(Vector2(28, 28))
	var first := analysis.assess(snapshot, grid, AutoProfile.new())
	snapshot.position = Vector2(60, 28)
	var reused := analysis.assess(snapshot, grid, AutoProfile.new())
	check(not first.connectivity_reused and reused.connectivity_reused, "a moved start in the same unchanged component reuses connectivity")
	check(reused.reachable == first.reachable, "connectivity reuse preserves every reachable cell")
	for y in grid.height:
		grid.blocked[y * grid.width + 16] = 1
	var changed := analysis.assess(snapshot, grid, AutoProfile.new())
	check(not changed.connectivity_reused and changed.reachable_cells == 16 * grid.height, "terrain edits invalidate the cached component")
	snapshot.enemies = [enemy(Vector2(70, 28))]
	changed = analysis.assess(snapshot, grid, AutoProfile.new())
	check(not changed.connectivity_reused, "a changed enemy mask invalidates connectivity")
	check(changed.threats[grid.cell(Vector2(70, 28)).y * grid.width + grid.cell(Vector2(70, 28)).x] == 1, "invalidated results contain the new threat")

func test_connectivity_cache_does_not_reuse_a_threatened_start_exception() -> void:
	var grid := navigation()
	var analysis := EscapeAnalysis.new()
	var snapshot := world(Vector2(128, 128))
	snapshot.enemies = [enemy(Vector2(128, 128))]
	analysis.assess(snapshot, grid, AutoProfile.new())
	var repeated := analysis.assess(snapshot, grid, AutoProfile.new())
	check(not repeated.connectivity_reused, "the special permission to leave a threatened source is never reused as an ordinary free component")

func test_surrounding_enemies_trigger_escape_in_open_terrain() -> void:
	var grid := navigation()
	var snapshot := world()
	for i in 4:
		snapshot.enemies.append(enemy(snapshot.position + Vector2.from_angle(TAU * i / 4.0) * 75.0, i + 1))
	var assessment := EscapeAnalysis.new().assess(snapshot, grid, AutoProfile.new())
	check(assessment.retreat and assessment.reason == "ESCAPE_ENCIRCLEMENT", "opposing nearby threat bearings trigger an early escape even away from walls")

func test_threat_mask_routes_around_enemy_bodies() -> void:
	var grid := navigation()
	grid.native = ClassDB.instantiate("ShooterPathfinder")
	grid.ready = true
	var threats := PackedByteArray()
	threats.resize(grid.blocked.size())
	threats[2 * grid.width + 4] = 1
	var route := grid.route(Vector2(20, 20), Vector2(60, 20), PackedFloat64Array(), threats)
	check(route.status == "found", "native A* can route around a transient enemy obstacle")
	var crossed := false
	for point: Vector2 in route.path:
		crossed = crossed or threats[grid.cell(point).y * grid.width + grid.cell(point).x] != 0
	check(not crossed, "the native route does not use a cell excluded by the tactical threat map")
	check(grid.blocked[2 * grid.width + 4] == 0, "transient threats do not mutate cached terrain")

func test_retreat_does_not_accept_the_idle_hold_fast_path() -> void:
	var snapshot := world(Vector2.ZERO)
	snapshot.retreat = true
	var result := LocalSteering.new().choose(snapshot, Vector2.ZERO, Vector2.ZERO,
		func(_p: Vector2, _m: Vector2) -> float: return 1.0,
		func(point: Vector2) -> float: return minf(point.length() / 50.0, 1.0))
	check(result.rule == "ESCAPE_SEARCH" and not result.movement.is_zero_approx(), "retreat searches for a roomier move instead of accepting a zero-velocity hold")

func test_emergency_overlap_prefers_an_exit_to_standing_still() -> void:
	var snapshot := world(Vector2.ZERO)
	snapshot.retreat = true
	snapshot.enemies = [enemy(Vector2(-5, 0))]
	var result := LocalSteering.new().choose(snapshot, Vector2.RIGHT, Vector2.ZERO,
		func(_p: Vector2, motion: Vector2) -> float: return 0.0 if motion.x < 0.0 else 1.0)
	check(result.emergency, "an initial overlap is never labelled safe")
	check(result.movement.x > 0.5, "an unavoidable initial overlap does not freeze the controller against a corner")
	check(result.candidates[result.selected].ending_clearance > 0.0, "the selected emergency move ends outside the predicted contact zone")
	check(is_equal_approx(LocalSteering.contact_time(Vector2(50, 0), Vector2(-100, 0), 10.0, 1.0), 0.4), "contact-time ranking matches the relative-motion equation")
	check(is_inf(LocalSteering.contact_time(Vector2(50, 0), Vector2(100, 0), 10.0, 1.0)), "a separating trajectory has no predicted contact")

func test_breakout_fire_overrides_unrelated_target_lock() -> void:
	var controller := ClearLineController.new()
	controller._target_id = 2
	controller._target_lock = 1.0
	var snapshot := world(Vector2.ZERO)
	snapshot.escape_direction = Vector2.RIGHT
	snapshot.enemies = [enemy(Vector2(40, 0), 1, 1), enemy(Vector2(-20, 0), 2, 8)]
	var selected := controller._select_target(snapshot)
	check(selected.id == 1 and snapshot.breakout_target_id == 1, "retreat aims at the vulnerable exit blocker instead of retaining the closer rear target")

func test_reached_escape_goal_holds_without_threshold_oscillation() -> void:
	var snapshot := world(Vector2.ZERO)
	snapshot.retreat = true
	snapshot.escape_arrived = true
	var result := LocalSteering.new().choose(snapshot, Vector2.ZERO, Vector2.LEFT,
		func(_p: Vector2, _m: Vector2) -> float: return 1.0,
		func(_point: Vector2) -> float: return 1.0)
	check(result.holding and result.movement.is_zero_approx(), "a reached, safe escape goal can settle without alternating across its arrival radius")
	snapshot.enemies = [enemy(Vector2(22, 0))]
	snapshot.enemies[0].velocity = Vector2(-30, 0)
	result = LocalSteering.new().choose(snapshot, Vector2.ZERO, Vector2.ZERO, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	check(not result.holding and result.movement.x < 0.0, "arrival does not justify holding when a threat is about to arrive")

func test_route_forecast_stops_at_the_destination() -> void:
	var snapshot := world(Vector2.ZERO)
	snapshot.route_destination = Vector2(20, 0)
	snapshot.enemies = [enemy(Vector2(70, 0))]
	var result := LocalSteering.new().choose(snapshot, Vector2.RIGHT, Vector2.RIGHT, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	check(result.rule == "ROUTE_CHECK" and result.endpoint.is_equal_approx(Vector2(20, 0)), "arrival forecast does not invent a collision beyond the final waypoint")
	var grid := navigation()
	check(grid.cell(Vector2(-0.01, 20)).x == -1, "negative coordinates use floor rather than truncating into the arena")

func test_evasion_commitment_rechecks_safety_before_continuing() -> void:
	var snapshot := world(Vector2.ZERO)
	snapshot.keep_evasion = true
	var result := LocalSteering.new().choose(snapshot, Vector2.LEFT, Vector2.RIGHT, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	check(result.movement == Vector2.RIGHT and result.rule == "CONTINUE_EVASION", "a safe short evasion is not reversed immediately by route following")
	snapshot.enemies = [enemy(Vector2(40, 0))]
	snapshot.enemies[0].velocity = Vector2(-30, 0)
	result = LocalSteering.new().choose(snapshot, Vector2.LEFT, Vector2.RIGHT, func(_p: Vector2, _m: Vector2) -> float: return 1.0)
	check(result.rule != "CONTINUE_EVASION" and result.movement.x < 0.0, "a newly dangerous evasion is abandoned immediately despite its commitment time")

func test_runtime_last_spawn_drop_is_collected_then_vacated() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Game = load("res://scene/game.tscn").instantiate()
	scene.initial_pause = 60.0
	tree.root.add_child(scene)
	scene.player.position = Vector2(20, 144)
	var pickup: Pickup = load("res://scene/pickup.tscn").instantiate()
	pickup.config = load("res://resources/config/pickup_rapid.tres")
	pickup.position = scene.player.position
	scene.add_child(pickup)
	var collected := [0]
	scene.player.pickup_collected.connect(func(_category: int) -> void: collected[0] += 1)
	if not scene.auto_enabled:
		scene.toggle_auto()
	for i in 90:
		await tree.physics_frame
		await tree.process_frame
	check(collected[0] == 1, "the actual last spawn drop is collected normally")
	check(scene.player.position.distance_to(Vector2(8, 144)) >= 48.0, "the actual player vacates the spawn lane before another enemy appears")
	var actor: Enemy = load("res://scene/enemy.tscn").instantiate()
	actor.config = load("res://resources/config/enemy_shelled.tres")
	actor.position = Vector2(8, 144)
	actor.target = scene.player
	scene.enemy_container.add_child(actor)
	for i in 60:
		await tree.physics_frame
		await tree.process_frame
	check(scene.player.current_health == scene.player.max_health, "a later enemy spawn does not hit a player camping on the collected drop")
	scene.queue_free()
	await tree.process_frame
