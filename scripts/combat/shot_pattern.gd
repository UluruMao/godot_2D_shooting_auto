class_name WeaponShotPattern
extends RefCounted
## Polymorphic direction generation; no input, scene allocation, or presentation.

var cooldown := 0.2
var automatic := false

func directions(_aim: Vector2) -> Array[Vector2]:
	return []

func reset() -> void:
	pass
