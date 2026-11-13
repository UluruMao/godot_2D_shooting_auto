class_name PlayerController
extends RefCounted
## Controllers return intent, never mutate health, position, or weapon cooldowns.

var wants_world := false

func sample(_context: Dictionary, _delta: float) -> ControlFrame:
	return ControlFrame.new()

func reset() -> void:
	pass
