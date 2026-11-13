extends RefCounted

var failures: Array[String] = []
var checks := 0

class FanPattern extends WeaponShotPattern:
	func directions(aim: Vector2) -> Array[Vector2]:
		return [aim.rotated(-0.2), aim.rotated(0.2)]

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func pickup(category: int, duration: float, multiplier: float) -> PickUpConfig:
	var config := PickUpConfig.new()
	config.pickup_type = category as PickUpConfig.PickupType
	config.duration = duration
	config.move_speed_multiplier = multiplier
	config.fire_rate_multiplier = multiplier
	return config

func test_independent_buffs_and_refresh() -> void:
	var buffs := BuffController.new()
	var speed := pickup(PickUpConfig.PickupType.SPEED, 2.0, 1.5)
	var rapid := pickup(PickUpConfig.PickupType.RAPID, 4.0, 2.0)
	check(buffs.apply(speed) and buffs.apply(rapid), "valid pickups apply")
	buffs.step(1.5)
	buffs.apply(speed)
	speed.move_speed_multiplier = 9.0
	check(is_equal_approx(buffs.move_multiplier(), 1.5), "active effect owns copied values")
	buffs.step(2.0)
	check(buffs.move_multiplier() == 1.0, "refreshed speed expires at its new deadline")
	check(buffs.fire_multiplier() == 2.0, "speed expiry does not reset rapid fire")
	check(is_equal_approx(buffs.remaining(PickUpConfig.PickupType.RAPID), 0.5), "remaining duration is queryable")
	buffs.step(0.5)
	check(buffs.fire_multiplier() == 1.0, "final expiry restores base rate")

func test_spiral_has_separate_rate_and_restores_rapid() -> void:
	var buffs := BuffController.new()
	buffs.apply(pickup(PickUpConfig.PickupType.RAPID, 5.0, 2.0))
	var spiral := pickup(PickUpConfig.PickupType.SPIRAL, 1.0, 3.0)
	spiral.shot_pattern = PickUpConfig.ShotPattern.SPIRAL
	spiral.player_form_mode = PickUpConfig.PlayerFormMode.ARMED
	buffs.apply(spiral)
	check(buffs.fire_multiplier() == 3.0 and buffs.form() == PickUpConfig.PlayerFormMode.ARMED, "spiral uses form rate")
	buffs.step(1.0)
	check(buffs.pattern() == PickUpConfig.ShotPattern.NORMAL and buffs.fire_multiplier() == 2.0, "spiral expiry reveals still-active rapid buff")
	buffs.clear()
	check(buffs.form() == PickUpConfig.PlayerFormMode.NORMAL and buffs.fire_multiplier() == 1.0, "clear restores derived defaults")

func test_invalid_effects_and_paused_time() -> void:
	var buffs := BuffController.new()
	check(not buffs.apply(null), "missing pickup rejected")
	check(not buffs.apply(pickup(0, 0.0, 2.0)), "zero duration rejected")
	check(not buffs.apply(pickup(0, 1.0, NAN)), "invalid multiplier rejected")
	buffs.apply(pickup(0, 2.0, 1.5))
	buffs.step(0.0)
	buffs.step(-1.0)
	check(buffs.remaining(0) == 2.0, "paused/invalid delta never consumes lifetime")

func test_cooldown_and_open_pattern_interface() -> void:
	var shots: Array[Vector2] = []
	var spawn := func(_origin: Vector2, direction: Vector2) -> bool:
		shots.append(direction)
		return true
	var weapon := WeaponController.new(spawn)
	check(weapon.step(0.0, true, Vector2.RIGHT, Vector2.ZERO) == 1, "normal fire starts immediately")
	check(weapon.step(0.1, true, Vector2.RIGHT, Vector2.ZERO) == 0, "cooldown blocks early shot")
	check(weapon.step(0.1, true, Vector2.RIGHT, Vector2.ZERO) == 1, "normal cooldown permits next shot")
	weapon.register_pattern(99, FanPattern.new())
	check(weapon.select_pattern(99), "third pattern registers without changing Player")
	check(weapon.step(0.0, true, Vector2.RIGHT, Vector2.ZERO) == 2, "weapon handles custom multi-shot polymorphically")
	check(shots[-1] != shots[-2], "custom pattern's distinct directions reach spawner")
	check(not weapon.select_pattern(999), "unknown pattern is rejected")

func test_spiral_auto_fire_and_spawn_failure() -> void:
	var weapon := WeaponController.new(func(_p: Vector2, _d: Vector2) -> bool: return true)
	weapon.select_pattern(PickUpConfig.ShotPattern.SPIRAL)
	check(weapon.step(0.0, false, Vector2.ZERO, Vector2.ZERO) == 1, "spiral fires without human fire input")
	check(weapon.step(0.025, false, Vector2.ZERO, Vector2.ZERO, 2.0) == 0, "existing cooldown is not skipped by rate change")
	check(weapon.step(0.025, false, Vector2.ZERO, Vector2.ZERO, 2.0) == 1, "spiral fires at next deadline")
	check(weapon.step(0.025, false, Vector2.ZERO, Vector2.ZERO, 2.0) == 1, "form multiplier affects subsequent interval")
	var failing := WeaponController.new(func(_p: Vector2, _d: Vector2) -> bool: return false)
	check(failing.step(0.0, true, Vector2.RIGHT, Vector2.ZERO) == 0, "failed acquisition never counts as fired")

func test_weighted_selection_boundaries() -> void:
	check(WeightedSampler.index_at([0.0, 1.0, 3.0], 0.0) == 1, "disabled weight cannot win at zero roll")
	check(WeightedSampler.index_at([0.0, 1.0, 3.0], 0.25) == 2, "boundary belongs to following interval")
	check(WeightedSampler.index_at([0.0, -2.0, NAN, INF], 0.5) == -1, "no valid weights yields no drop")
	check(WeightedSampler.index_at([], 0.5) == -1, "empty table yields no drop")
	check(WeightedSampler.index_at([1.0], 1.0) == -1, "invalid quantile rejected")
	check(WeightedSampler.index_at([1e308, 1e308], 0.75) == 1, "large finite weights do not overflow")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var counts := [0, 0]
	for i in 10000:
		counts[WeightedSampler.pick([1.0, 3.0], rng)] += 1
	check(abs(counts[0] - 2500) < 200, "fixed-seed sample respects configured proportions")

func test_control_frame_normalizes_intent() -> void:
	var frame := ControlFrame.new(Vector2(5, 5), Vector2(30, 0), true)
	check(is_equal_approx(frame.movement.length(), 1.0), "controller cannot exceed unit movement")
	check(frame.aim == Vector2.RIGHT and frame.fire, "aim and firing are independent of movement")
	check(ControlFrame.new(Vector2(NAN, 0), Vector2(INF, 0)).movement == Vector2.ZERO, "nonfinite movement is neutral")
