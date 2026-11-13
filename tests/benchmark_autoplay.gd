extends SceneTree
## Run with --fixed-fps 60. Reports CPU wall time, not rendered/GPU frame rate.

func _initialize() -> void:
	call_deferred("_run")

func percentile(values: Array[float], quantile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(sorted.size() * quantile) - 1, 0, sorted.size() - 1)]

func _run() -> void:
	var results: Array[Dictionary] = []
	var modes := [AutoController.Planner.BASELINE, AutoController.Planner.ROUTE_ONLY, AutoController.Planner.PREDICTIVE]
	var seeds := [12345, 54321, 999]
	var repeats := 1
	if "--quick" in OS.get_cmdline_user_args():
		modes = [AutoController.Planner.PREDICTIVE]
		seeds = [12345]
	if "--predictive" in OS.get_cmdline_user_args():
		modes = [AutoController.Planner.PREDICTIVE]
		seeds = [12345, 54321, 999, 2026, 8675309]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seeds = [argument.trim_prefix("--seed=").to_int()]
		if argument.begins_with("--seeds="):
			seeds = []
			for value in argument.trim_prefix("--seeds=").split(","):
				seeds.append(value.to_int())
		if argument.begins_with("--repeats="):
			repeats = clampi(argument.trim_prefix("--repeats=").to_int(), 1, 10)
	var scheduled_seeds := seeds.duplicate()
	var repetitions := {}
	for repeat in range(1, repeats):
		seeds.append_array(scheduled_seeds)
	for mode in modes:
		for run_seed in seeds:
			var scene: Game = load("res://scene/game.tscn").instantiate()
			scene.run_seed = run_seed
			root.add_child(scene)
			scene.auto_controller.planner = mode
			if not scene.auto_enabled:
				scene.toggle_auto()
			if scene.inspector.expanded:
				scene.inspector.toggle()
			var damage := [0]
			var pickups := [0]
			scene.player.damaged.connect(func(amount: int) -> void: damage[0] += amount)
			scene.player.pickup_collected.connect(func(_category: int) -> void: pickups[0] += 1)
			var times: Array[float] = []
			var stages: Dictionary = {}
			var tick_times: Array[float] = []
			var ticks := 0
			var stuck := 0
			var reversals := 0
			var previous := Vector2.ZERO
			var position := scene.player.global_position
			while ticks < 5400 and not scene.game_ended:
				await physics_frame
				var tick_started := Time.get_ticks_usec()
				await process_frame
				ticks += 1
				var intent := scene.player.last_control.movement
				if ticks > 60:
					times.append(scene.auto_controller.decision.duration_usec / 1000.0)
					tick_times.append((Time.get_ticks_usec() - tick_started) / 1000.0)
					for stage: String in scene.auto_controller.decision.stage_usec:
						if not stages.has(stage):
							stages[stage] = []
						stages[stage].append(float(scene.auto_controller.decision.stage_usec[stage]) / 1000.0)
				if intent.length() > 0.1 and scene.player.global_position.distance_to(position) < 0.2:
					stuck += 1
				if intent.dot(previous) < -0.2:
					reversals += 1
					if "--trace" in OS.get_cmdline_user_args() and reversals <= 12:
						var d := scene.auto_controller.decision
						print("TRACE ", JSON.stringify({"tick": ticks, "position": position, "old": previous,
							"new": intent, "goal": d.goal, "objective": d.objective, "emergency": d.emergency,
							"tactical": d.tactical_reason, "rule": d.selection_rule, "reason": d.reason, "path_status": d.path_status,
							"selected": d.candidates[d.selected] if d.selected >= 0 else {}}))
				previous = intent
				position = scene.player.global_position
			var result := {"mode": mode, "seed": run_seed, "seconds": ticks / 60.0,
				"victory": scene.game_ended and not scene.player.is_dead,
				"wave": scene.current_wave, "health": scene.player.current_health,
				"damage": damage[0], "pickups": pickups[0], "stuck_ticks": stuck,
				"reversals": reversals, "ai_p50_ms": percentile(times, 0.5),
				"ai_p95_ms": percentile(times, 0.95), "ai_max_ms": percentile(times, 1.0),
				"projectiles": scene.player.projectile_spawner.metrics()}
			var run_key := "%d:%d" % [mode, run_seed]
			repetitions[run_key] = int(repetitions.get(run_key, 0)) + 1
			result.repetition = repetitions[run_key]
			result.tick_p95_ms = percentile(tick_times, 0.95)
			result.stages = {}
			for stage: String in stages:
				var values: Array[float] = []
				values.assign(stages[stage])
				var total := 0.0
				for value: float in values:
					total += value
				result.stages[stage] = {"total_ms": total, "mean_per_ai_tick_ms": total / maxf(times.size(), 1.0),
					"p95_when_recorded_ms": percentile(values, 0.95), "recorded_ticks": values.size()}
			results.append(result)
			var display := result.duplicate()
			if "--summary" in OS.get_cmdline_user_args():
				display.erase("stages")
			print(JSON.stringify(display))
			paused = false
			scene.queue_free()
			await process_frame
	DirAccess.make_dir_recursive_absolute("res://benchmark-results")
	var output := FileAccess.open("res://benchmark-results/autoplay.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	await create_timer(0.1, true).timeout
	OS.delay_msec(200) # Unmeasured cleanup: let the real-time audio mixer drain.
	quit()
