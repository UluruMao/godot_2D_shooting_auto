class_name ControlFrame
extends RefCounted
## A controller's intent. Applying movement and weapon rules belongs to Player.

var movement := Vector2.ZERO
var aim := Vector2.ZERO
var fire := false

func _init(move := Vector2.ZERO, look := Vector2.ZERO, shooting := false) -> void:
	movement = move.limit_length(1.0) if move.is_finite() else Vector2.ZERO
	aim = look.normalized() if look.is_finite() else Vector2.ZERO
	fire = shooting
