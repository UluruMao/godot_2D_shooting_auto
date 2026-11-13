class_name CombatAim
extends RefCounted

static func intercept(origin: Vector2, target: Vector2, velocity: Vector2, speed := 320.0, muzzle_offset := 14.0, lifetime := 3.0) -> Dictionary:
	var relative := target - origin
	var a := velocity.length_squared() - speed * speed
	var b := 2.0 * (relative.dot(velocity) - speed * muzzle_offset)
	var c := relative.length_squared() - muzzle_offset * muzzle_offset
	var time := INF
	if absf(a) < 0.000001:
		if absf(b) > 0.000001:
			var root := -c / b
			if root >= 0.0:
				time = root
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			for root in [(-b - sqrt(discriminant)) / (2.0 * a), (-b + sqrt(discriminant)) / (2.0 * a)]:
				if root >= 0.0:
					time = minf(time, root)
	var predicted := time <= lifetime
	return {"position": target + velocity * time if predicted else target,
		"time": time if predicted else 0.0, "predicted": predicted}
