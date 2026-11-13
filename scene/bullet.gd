class_name Projectile
extends Area2D
## Release is immediate logically; the owner reuses/frees only after physics flush.
signal released(projectile: Projectile, activation: int)
signal enemy_hit

const SPEED := 320.0
const LIFETIME := 3.0
var direction := Vector2.ZERO
var active := false
var activation := 0
var remaining := 0.0
var damage := 1

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	visible = false
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)

func activate(origin: Vector2, heading: Vector2) -> bool:
	if active or not origin.is_finite() or not heading.is_finite() or heading.is_zero_approx():
		return false
	activation += 1
	global_position = origin
	direction = heading.normalized()
	damage = 1
	remaining = LIFETIME
	active = true
	visible = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	set_deferred("collision_layer", 16)
	set_deferred("collision_mask", 5)
	set_physics_process(true)
	return true

func release(expected_activation := -1) -> void:
	if not active or (expected_activation >= 0 and expected_activation != activation):
		return
	active = false
	visible = false
	direction = Vector2.ZERO
	remaining = 0.0
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	released.emit(self, activation)

func _physics_process(delta: float) -> void:
	if not active:
		return
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		release()
		return
	global_position += direction * SPEED * delta

func _on_body_entered(body: Node) -> void:
	if not active:
		return
	# Mark inactive before damage, which may trigger other collision/death effects.
	var dealt := damage
	release()
	if body is Enemy and body.death_stage == Enemy.DeathSequenceStage.NONE:
		enemy_hit.emit()
		body.take_damage(dealt)
