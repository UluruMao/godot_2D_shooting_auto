extends SceneTree
## Fixed adversarial fixtures complement the random full-game evaluation.

func _initialize() -> void:
	call_deferred("_run")

func _enemy(scene: Game, position: Vector2, health: int, kind := "shelled") -> Enemy:
	var actor: Enemy = load("res://scene/enemy.tscn").instantiate()
	actor.config = load("res://resources/config/enemy_%s.tres" % kind).duplicate()
	actor.config.max_health = health
	actor.config.move_speed = 22.0
	actor.config.pickup_drop_chance = 0.0
	actor.position = position
	actor.target = scene.player
	scene.enemy_container.add_child(actor)
	return actor

func _wall(scene: Game, position: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.position = position
	body.add_child(shape)
	scene.add_child(body)

func _run() -> void:
	var results: Array[Dictionary] = []
	for scenario in ["spawn_pickup", "corner_pincer", "closed_ring", "bomber_pincer", "buff_expiry_retreat", "narrow_exit"]:
		var scene: Game = load("res://scene/game.tscn").instantiate()
		scene.initial_pause = 60.0
		root.add_child(scene)
		scene.player.position = Vector2(20, 144) if scenario == "spawn_pickup" else (Vector2(26, 26) if scenario in ["corner_pincer", "buff_expiry_retreat"] else Vector2(112, 112))
		var origin := scene.player.position
		var damage := [0]
		var collected := [0]
		scene.player.damaged.connect(func(amount: int) -> void: damage[0] += amount)
		scene.player.pickup_collected.connect(func(_category: int) -> void: collected[0] += 1)
		if scenario == "spawn_pickup":
			var pickup: Pickup = load("res://scene/pickup.tscn").instantiate()
			pickup.config = load("res://resources/config/pickup_rapid.tres")
			pickup.position = origin
			scene.add_child(pickup)
		elif scenario in ["corner_pincer", "buff_expiry_retreat"]:
			if scenario == "buff_expiry_retreat":
				var effect := PickUpConfig.new()
				effect.pickup_type = PickUpConfig.PickupType.SPEED
				effect.move_speed_multiplier = 1.5
				effect.duration = 0.6
				scene.player.apply_pickup(effect)
			for position: Vector2 in [Vector2(26, 95), Vector2(95, 26), Vector2(85, 85)]:
				_enemy(scene, position, 8)
		elif scenario == "closed_ring":
			for i in 8:
				_enemy(scene, origin + Vector2.from_angle(TAU * i / 8.0) * 38.0, 1 if i == 0 else 8)
		elif scenario == "bomber_pincer":
			for i in 5:
				_enemy(scene, origin + Vector2.from_angle(TAU * i / 5.0) * 65.0, 2, "bomber")
		elif scenario == "narrow_exit":
			scene.player.position = Vector2(112, 80)
			origin = scene.player.position
			_wall(scene, Vector2(112, 64), Vector2(64, 8))
			_wall(scene, Vector2(112, 96), Vector2(64, 8))
			_enemy(scene, Vector2(88, 80), 8)
			_enemy(scene, Vector2(160, 80), 1)
		if not scene.auto_enabled:
			scene.toggle_auto()
		if scene.inspector.expanded:
			scene.inspector.toggle()
		var lane_ticks := 0
		var stalled := 0
		var displacement_at_3s := 0.0
		var times: Array[float] = []
		var objectives := {}
		var ticks := 0
		var breakout_fire_ticks := 0
		while ticks < 480 and not scene.game_ended:
			await physics_frame
			await process_frame
			ticks += 1
			var position := scene.player.position
			if scenario == "spawn_pickup" and position.distance_to(Vector2(8, 144)) < 48.0:
				lane_ticks += 1
			if scene.player.last_control.movement.length() < 0.1 and not scene.enemy_container.get_children().is_empty():
				stalled += 1
			var d := scene.auto_controller.decision
			if d.fire and d.shot_reason == "CLEAR_ESCAPE_CORRIDOR":
				breakout_fire_ticks += 1
			objectives[d.objective] = int(objectives.get(d.objective, 0)) + 1
			times.append(d.duration_usec / 1000.0)
			if ticks == 180:
				displacement_at_3s = position.distance_to(origin)
				if scenario == "spawn_pickup":
					_enemy(scene, Vector2(8, 144), 8)
					_enemy(scene, Vector2(248, 144), 8)
		var result := {"scenario": scenario, "ticks": ticks, "damage": damage[0], "pickups": collected[0],
			"alive": not scene.player.is_dead, "displacement_at_3s": displacement_at_3s,
			"final_displacement": scene.player.position.distance_to(origin), "spawn_lane_ticks": lane_ticks,
			"stationary_threat_ticks": stalled, "objectives": objectives}
		result.breakout_fire_ticks = breakout_fire_ticks
		if scenario == "buff_expiry_retreat":
			result.buff_expired = scene.player.buffs.remaining(PickUpConfig.PickupType.SPEED) <= 0.0
		times.sort()
		result.ai_p95_ms = times[clampi(ceili(times.size() * 0.95) - 1, 0, times.size() - 1)]
		results.append(result)
		print(JSON.stringify(result))
		paused = false
		scene.queue_free()
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://benchmark-results")
	var output := FileAccess.open("res://benchmark-results/tactics.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	await create_timer(0.1, true).timeout
	OS.delay_msec(200) # Let the real-time audio mixer release stopped playbacks.
	quit()
