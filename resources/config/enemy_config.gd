extends Resource
class_name EnemyConfig

enum EnemyType {
	BASIC,
	SHELLED,
	FAST_SMALL,
	BOMBER,
}

@export_group("Basic Info")
@export var enemy_type: EnemyType = EnemyType.BASIC
@export var display_name: String = "Basic enemy"

@export_group("Stats")
@export_range(1, 999, 1, "or_greater") var max_health: int = 3
@export_range(0.0, 1000.0, 1.0, "or_greater") var move_speed: float = 60.0
## World-space radius; each enemy duplicates the mutable collision shape.
@export_range(1.0, 256.0, 0.5, "or_greater") var collision_radius: float = 8

@export_group("Animation")
@export var enemy_frames: SpriteFrames
@export var move_animation_name: StringName = &"move"
@export var death_animation_name: StringName = &"death"
@export var explosion_animation_name: StringName = &"explode"

@export_group("Death Effect")
@export var explode_on_death: bool = false
@export_range(0, 999, 1, "or_greater") var explosion_damage: int = 0
@export_range(0.0, 512.0, 1.0, "or_greater") var explosion_radius: float = 0


@export_group("Drops")
## Roll this probability first, then select among eligible pickup weights.
@export_range(0.0, 1.0, 0.01) var pickup_drop_chance: float = 0.3
@export var pickup_drop_configs: Array[PickUpConfig] = [
	preload("res://resources/config/pickup_speed.tres"),
	preload("res://resources/config/pickup_rapid.tres"),
	preload("res://resources/config/pickup_spiral.tres"),
]
