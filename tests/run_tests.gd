extends SceneTree
## Standalone headless runner; no editor addon or test framework required.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var count := 0
	var checks := 0
	var failures: Array[String] = []
	var cases: Array[Dictionary] = []
	var paths := DirAccess.get_files_at("res://tests")
	for filename in paths:
		if not filename.begins_with("test_") or not filename.ends_with(".gd"):
			continue
		var script: GDScript = load("res://tests/" + filename)
		if script == null or not script.can_instantiate():
			failures.append("Cannot load suite " + filename)
			continue
		var suite: RefCounted = script.new()
		for method in suite.get_method_list():
			if String(method.name).begins_with("test_"):
				count += 1
				var started := Time.get_ticks_usec()
				var before := int(suite.get("checks"))
				var failures_before: int = suite.get("failures").size()
				await suite.call(method.name)
				cases.append({"suite": filename, "test": method.name,
					"duration_ms": (Time.get_ticks_usec() - started) / 1000.0,
					"checks": int(suite.get("checks")) - before,
					"passed": suite.get("failures").size() == failures_before})
		checks += int(suite.get("checks"))
		for failure: String in suite.get("failures"):
			failures.append(filename + ": " + failure)
	# Let AudioServer consume deferred stop/free commands from scene smoke tests.
	await create_timer(0.1, true).timeout
	if count == 0:
		failures.append("No tests discovered")
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: " + failure)
	print("Tests: %d; checks: %d; failures: %d" % [count, checks, failures.size()])
	DirAccess.make_dir_recursive_absolute("res://benchmark-results")
	var report := FileAccess.open("res://benchmark-results/tests.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"tests": count, "checks": checks, "failures": failures, "cases": cases}, "\t"))
	report.close()
	quit(0 if failures.is_empty() else 1)
