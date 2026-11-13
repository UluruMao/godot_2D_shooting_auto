extends SceneTree
## Uncapped rendered frames at fixed simulation delta, not headless timing.

func _initialize() -> void:
	call_deferred("_run")

func percentile(values: Array[float], quantile: float) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * quantile) - 1, 0, ordered.size() - 1)]

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var reports := []
	for expanded in [false, true]:
		var scene: Game = load("res://scene/game.tscn").instantiate()
		root.add_child(scene)
		if not scene.auto_enabled:
			scene.toggle_auto()
		if scene.inspector.expanded != expanded:
			scene.inspector.toggle()
		var frames: Array[float] = []
		var ai: Array[float] = []
		var previous := Time.get_ticks_usec()
		for tick in 1200:
			await process_frame
			var now := Time.get_ticks_usec()
			if tick >= 120:
				frames.append((now - previous) / 1000.0)
				ai.append(scene.auto_controller.decision.duration_usec / 1000.0)
			previous = now
		var report := {"inspector_expanded": expanded, "seed": scene.run_seed, "simulated_seconds": 20.0,
			"warmup_frames": 120, "measured_frames": frames.size(), "vsync": false,
			"resolution": "1280x720", "renderer": RenderingServer.get_current_rendering_method(),
			"frame_p50_ms": percentile(frames, 0.5), "frame_p95_ms": percentile(frames, 0.95),
			"frame_max_ms": percentile(frames, 1.0), "ai_p95_ms": percentile(ai, 0.95),
			"health": scene.player.current_health}
		reports.append(report)
		print(JSON.stringify(report))
		scene.queue_free()
		await process_frame
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://benchmark-results")
	var file := FileAccess.open("res://benchmark-results/rendered.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	file.close()
	await create_timer(0.1, true).timeout
	OS.delay_msec(200)
	quit()
