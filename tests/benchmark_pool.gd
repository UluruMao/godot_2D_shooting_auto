extends SceneTree
## Same schedule and lifetime for both backends; do not compare dropped work.

func _initialize() -> void:
	call_deferred("_run")

func percentile(values: Array[float], quantile: float) -> float:
	values.sort()
	return values[clampi(ceili(values.size() * quantile) - 1, 0, values.size() - 1)]

func _run() -> void:
	var results: Array[Dictionary] = []
	for workload in [{"name": "normal", "interval": 12, "batch": 1, "capacity": 32},
		{"name": "spiral", "interval": 3, "batch": 1, "capacity": 128},
		{"name": "stress", "interval": 1, "batch": 8, "capacity": 1600}]:
		for repetition in 3:
			# Alternate ordering to reduce a consistent cold-start advantage.
			for pooled in ([false, true] if repetition % 2 == 0 else [true, false]):
				var backend: SceneProjectileSpawner = PooledProjectileSpawner.new() if pooled else SceneProjectileSpawner.new()
				if pooled:
					backend.prewarm_count = workload.capacity
					backend.max_capacity = workload.capacity
				var startup := Time.get_ticks_usec()
				root.add_child(backend)
				var startup_ms := (Time.get_ticks_usec() - startup) / 1000.0
				var times: Array[float] = []
				var previous := Time.get_ticks_usec()
				for tick in 360:
					if tick % int(workload.interval) == 0:
						for i in int(workload.batch):
							backend.spawn(Vector2(10000, 10000 + i * 16), Vector2.RIGHT)
					await physics_frame
					await process_frame
					var now := Time.get_ticks_usec()
					if tick >= 180:
						times.append((now - previous) / 1000.0)
					previous = now
				var result := {"workload": workload.name, "pooled": pooled, "run": repetition,
					"prewarm_ms": startup_ms, "tick_p50_ms": percentile(times.duplicate(), 0.5),
					"tick_p95_ms": percentile(times.duplicate(), 0.95),
					"tick_max_ms": percentile(times.duplicate(), 1.0), "metrics": backend.metrics()}
				results.append(result)
				print(JSON.stringify(result))
				if backend.misses != 0:
					printerr("Unequal workload: acquisitions failed")
					quit(1)
					return
				backend.queue_free()
				await process_frame
	DirAccess.make_dir_recursive_absolute("res://benchmark-results")
	var output := FileAccess.open("res://benchmark-results/pool.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	quit()
