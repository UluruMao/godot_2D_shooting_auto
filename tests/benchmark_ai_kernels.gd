extends SceneTree
## Snapshot-only comparison: identical inputs isolate algorithm work from physics.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71353
	var steering := LocalSteering.new()
	var selector := GoalSelector.new()
	var navigation := NavigationGrid.new()
	navigation.blocked.resize(navigation.width * navigation.height)
	var clear := func(_origin: Vector2, _motion: Vector2) -> float: return 1.0
	var wall := func(origin: Vector2, motion: Vector2) -> float:
		var fraction := 1.0
		if motion.x < 0.0:
			fraction = minf(fraction, -origin.x / motion.x)
		if motion.y < 0.0:
			fraction = minf(fraction, -origin.y / motion.y)
		return clampf(fraction, 0.0, 1.0)
	var records := PackedStringArray()
	var samples: Array[float] = []
	var goal_records := PackedStringArray()
	for i in 2048:
		var origin := Vector2(rng.randf_range(5, 200), rng.randf_range(5, 200))
		var enemies: Array[Dictionary] = []
		for j in i % 20:
			enemies.append({"id": j + 1, "position": Vector2(rng.randf_range(0, 256), rng.randf_range(0, 256)),
				"velocity": Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0, 45),
				"radius": 6.0 + j % 5, "bomber": j % 7 == 0, "blast_radius": 30.0,
				"dying": j % 11 == 0, "health": 2})
		var snapshot := {"position": origin, "speed": 120.0, "radius": 6.0, "enemies": enemies,
			"retreat": i % 2 == 0, "keep_evasion": i % 5 == 0, "escape_arrived": i % 13 == 0}
		if i % 3 == 0:
			snapshot.route_destination = origin + Vector2(20, 0)
		var preferred := Vector2.from_angle(rng.randf_range(-PI, PI)) if i % 4 else Vector2.ZERO
		var previous := Vector2.from_angle(rng.randf_range(-PI, PI))
		var started := Time.get_ticks_usec()
		var result := steering.choose(snapshot, preferred, previous, wall if i % 3 else clear)
		samples.append((Time.get_ticks_usec() - started) / 1000.0)
		var candidates := []
		for candidate: Dictionary in result.candidates:
			candidates.append([candidate.movement, candidate.endpoint, candidate.legal, candidate.reason,
				candidate.clearance, candidate.score, candidate.collision_time, candidate.ending_clearance])
		records.append(JSON.stringify([result.movement, result.selected, result.rule, result.emergency, candidates]))
		if i < 256:
			snapshot.effects = {}
			snapshot.pickups = [{"id": 42, "position": Vector2(64, 64), "remaining": 5.0, "category": 0}]
			snapshot.spawn_points = PackedVector2Array([Vector2(8, 144), Vector2(248, 144)])
			snapshot.velocity = previous * 120.0
			var goals := selector.choose(snapshot, navigation, {})
			goal_records.append(JSON.stringify(goals))
	samples.sort()
	var report := {"samples": records.size(), "decision_sha256": "\n".join(records).sha256_text(),
		"goal_samples": goal_records.size(), "goals_sha256": "\n".join(goal_records).sha256_text(),
		"p50_ms": samples[samples.size() / 2], "p95_ms": samples[ceili(samples.size() * 0.95) - 1]}
	DirAccess.make_dir_recursive_absolute("res://benchmark-results")
	var file := FileAccess.open("res://benchmark-results/kernels.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify(report))
	quit()
