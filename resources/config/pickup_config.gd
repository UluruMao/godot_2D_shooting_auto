class_name PickUpConfig
extends Resource

enum PickupType {
	SPEED,
	RAPID,
	SPIRAL
}

enum PlayerFormMode {
	NORMAL,
	ARMED
}

enum ShotPattern {
	NORMAL,
	SPIRAL
}

@export_group("Basic Info")
@export var pickup_type: PickupType = PickupType.SPEED
@export var display_name: String = "Speed boost"
## Relative weight within an enemy's drop table; zero disables this entry.
@export_range(0.0, 1000.0, 0.1, "or_greater") var drop_weight: float = 1.0

@export_group("Presentation")
@export var icon_texture: Texture2D

@export_group("Buff Effect")
## Seconds of simulation time. Recollection refreshes the same effect category.
@export_range(0.0, 120.0, 0.1, "or_greater") var duration: float = 5.0
@export_range(0.1, 5.0, 0.05, "or_greater") var move_speed_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05, "or_greater") var fire_rate_multiplier: float = 1.0

@export_group("Form and Shot Pattern")
@export var player_form_mode: PlayerFormMode = PlayerFormMode.NORMAL
@export var shot_pattern: ShotPattern = ShotPattern.NORMAL
