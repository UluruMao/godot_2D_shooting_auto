class_name NormalShotPattern
extends WeaponShotPattern

func directions(aim: Vector2) -> Array[Vector2]:
	return [aim.normalized()] if not aim.is_zero_approx() else []
