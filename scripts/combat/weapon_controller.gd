class_name WeaponController
extends RefCounted
## The spawner callable takes (world_origin, unit_direction) and returns success.
signal fired

var _patterns: Dictionary = {}
var _pattern: WeaponShotPattern
var _remaining := 0.0
var _spawn: Callable
var spawn_offset := 14.0

func _init(spawn_projectile: Callable = Callable()) -> void:
	_spawn = spawn_projectile
	register_pattern(PickUpConfig.ShotPattern.NORMAL, NormalShotPattern.new())
	register_pattern(PickUpConfig.ShotPattern.SPIRAL, SpiralShotPattern.new())
	select_pattern(PickUpConfig.ShotPattern.NORMAL)

func register_pattern(id: int, pattern: WeaponShotPattern) -> void:
	if pattern != null:
		_patterns[id] = pattern

func select_pattern(id: int) -> bool:
	if not _patterns.has(id):
		return false
	if _pattern != _patterns[id]:
		_pattern = _patterns[id]
		_remaining = 0.0
	return true

func step(delta: float, requested: bool, aim: Vector2, origin: Vector2, multiplier := 1.0) -> int:
	if not is_finite(delta) or delta < 0.0 or _pattern == null:
		return 0
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining > 0.000001 or not (requested or _pattern.automatic) or not _spawn.is_valid():
		return 0
	var count := 0
	for direction in _pattern.directions(aim):
		if not direction.is_finite() or direction.is_zero_approx():
			continue
		var unit := direction.normalized()
		if _spawn.call(origin + unit * spawn_offset, unit):
			count += 1
	if count > 0:
		var rate := multiplier if is_finite(multiplier) and multiplier > 0.0 else 1.0
		_remaining = maxf(_pattern.cooldown, 0.000001) / rate
		fired.emit()
	return count

func reset() -> void:
	_remaining = 0.0
	for pattern: WeaponShotPattern in _patterns.values():
		pattern.reset()
