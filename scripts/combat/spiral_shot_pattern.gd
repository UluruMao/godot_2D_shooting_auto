class_name SpiralShotPattern
extends WeaponShotPattern

var phase := 0.0
var angular_step := 0.3

func _init() -> void:
	cooldown = 0.05
	automatic = true

func directions(_aim: Vector2) -> Array[Vector2]:
	phase = fposmod(phase + angular_step, TAU)
	return [Vector2.from_angle(phase)]

func reset() -> void:
	phase = 0.0
