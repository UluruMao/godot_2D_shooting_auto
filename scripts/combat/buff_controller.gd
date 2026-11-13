class_name BuffController
extends RefCounted
## One refreshable effect per category. Stats are derived, never divided on expiry.
signal changed

class Effect extends RefCounted:
	var remaining: float
	var move_multiplier: float
	var fire_multiplier: float
	var form: int
	var pattern: int

var _effects: Dictionary = {}

func apply(config: PickUpConfig) -> bool:
	if config == null or not is_finite(config.duration) or config.duration <= 0.0:
		return false
	if config.pickup_type not in [PickUpConfig.PickupType.SPEED, PickUpConfig.PickupType.RAPID, PickUpConfig.PickupType.SPIRAL]:
		return false
	if not is_finite(config.move_speed_multiplier) or config.move_speed_multiplier <= 0.0:
		return false
	if not is_finite(config.fire_rate_multiplier) or config.fire_rate_multiplier <= 0.0:
		return false
	var effect := Effect.new()
	effect.remaining = config.duration
	effect.move_multiplier = config.move_speed_multiplier
	effect.fire_multiplier = config.fire_rate_multiplier
	effect.form = config.player_form_mode
	effect.pattern = config.shot_pattern
	_effects[config.pickup_type] = effect
	changed.emit()
	return true

func step(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var expired := false
	for category: int in _effects.keys():
		var effect: Effect = _effects[category]
		effect.remaining = maxf(0.0, effect.remaining - delta)
		if effect.remaining <= 0.000001:
			_effects.erase(category)
			expired = true
	if expired:
		changed.emit()

func remaining(category: int) -> float:
	return _effects[category].remaining if _effects.has(category) else 0.0

func move_multiplier() -> float:
	return _effects[PickUpConfig.PickupType.SPEED].move_multiplier if _effects.has(PickUpConfig.PickupType.SPEED) else 1.0

func fire_multiplier() -> float:
	var category := PickUpConfig.PickupType.SPIRAL if pattern() == PickUpConfig.ShotPattern.SPIRAL else PickUpConfig.PickupType.RAPID
	return _effects[category].fire_multiplier if _effects.has(category) else 1.0

func pattern() -> int:
	return _effects[PickUpConfig.PickupType.SPIRAL].pattern if _effects.has(PickUpConfig.PickupType.SPIRAL) else PickUpConfig.ShotPattern.NORMAL

func form() -> int:
	return _effects[PickUpConfig.PickupType.SPIRAL].form if _effects.has(PickUpConfig.PickupType.SPIRAL) else PickUpConfig.PlayerFormMode.NORMAL

func clear() -> void:
	if not _effects.is_empty():
		_effects.clear()
		changed.emit()
