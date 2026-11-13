extends CharacterBody2D
class_name Player

signal spiral_state_changed(active: bool)
signal damaged(amount: int)
signal pickup_collected(category: int)

const BLINK_ENABLED_SHADER_PARAMETER := &"blink_enabled"

@export var move_speed := 120.0
@export var max_health := 5
@export var invincibility_duration := 0.5
@export var use_projectile_pool := true

var current_health := 0
var invincibility_time_left := 0.0
var is_dead := false
var controls_enabled := true
var aim := Vector2.RIGHT
var facing_suffix := "right"
var controller: PlayerController = HumanController.new()
var buffs := BuffController.new()
var weapon: WeaponController
var projectile_spawner: SceneProjectileSpawner
var last_control := ControlFrame.new()
var _spiral_active := false

@onready var sprite: AnimatedSprite2D = $BodySprite
@onready var armed_effect: AnimatedSprite2D = $ArmedEffectSprite
@onready var shoot_sfx_player: AudioStreamPlayer = $AudioContainer/ShootSfxPlayer
@onready var move_sfx_player: AudioStreamPlayer = $AudioContainer/MoveSfxPlayer
@onready var pickup_sfx_player: AudioStreamPlayer = $AudioContainer/PickupSfxPlayer

func _ready() -> void:
	current_health = maxi(max_health, 1)
	use_projectile_pool = use_projectile_pool and "--unpooled" not in OS.get_cmdline_user_args()
	projectile_spawner = PooledProjectileSpawner.new() if use_projectile_pool else SceneProjectileSpawner.new()
	projectile_spawner.name = "Projectiles"
	projectile_spawner.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_parent().add_child.call_deferred(projectile_spawner)
	weapon = WeaponController.new(projectile_spawner.spawn)
	weapon.fired.connect(_play_shoot_sfx)
	buffs.changed.connect(_on_buffs_changed)
	_set_hurt_blink_enabled(false)
	_update_animation()
	_update_armed_effect()

func _exit_tree() -> void:
	shoot_sfx_player.stop()
	move_sfx_player.stop()
	pickup_sfx_player.stop()

func set_controller(next: PlayerController) -> void:
	if next == null:
		return
	controller.reset()
	controller = next
	controller.reset()
	last_control = ControlFrame.new()
	# Switching input source preserves cooldowns and legitimately active buffs.

func _physics_process(delta: float) -> void:
	_update_invincibility(delta)
	if is_dead or not controls_enabled:
		velocity = Vector2.ZERO
		_update_move_sfx(Vector2.ZERO)
		last_control = ControlFrame.new()
		return
	buffs.step(delta)
	var context := {"position": global_position, "mouse_position": get_global_mouse_position(), "aim": aim}
	if controller.wants_world:
		var observation_started := Time.get_ticks_usec()
		context.merge(WorldPerception.capture(self))
		context.space = get_world_2d().direct_space_state
		context.observation_usec = Time.get_ticks_usec() - observation_started
	last_control = controller.sample(context, delta)
	if not last_control.aim.is_zero_approx():
		aim = last_control.aim
	velocity = last_control.movement * move_speed * buffs.move_multiplier()
	move_and_slide()
	_update_move_sfx(last_control.movement)
	weapon.step(delta, last_control.fire, aim, global_position, buffs.fire_multiplier())
	_update_facing(last_control.movement, aim)

func _on_buffs_changed() -> void:
	weapon.select_pattern(buffs.pattern())
	var active := buffs.pattern() == PickUpConfig.ShotPattern.SPIRAL
	if active != _spiral_active:
		_spiral_active = active
		spiral_state_changed.emit(active)
	_update_animation()
	_update_armed_effect()

func _update_move_sfx(movement: Vector2) -> void:
	if movement != Vector2.ZERO:
		if not move_sfx_player.playing:
			_set_stream_loop(move_sfx_player.stream, true)
			move_sfx_player.play()
	else:
		move_sfx_player.stop()

func _set_stream_loop(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamMP3:
		stream.loop = enabled
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if enabled else AudioStreamWAV.LOOP_DISABLED

func _play_shoot_sfx() -> void:
	shoot_sfx_player.play()

func _update_facing(movement: Vector2, look: Vector2) -> void:
	if buffs.pattern() == PickUpConfig.ShotPattern.SPIRAL:
		if not movement.is_zero_approx():
			facing_suffix = _vector_to_facing_suffix(movement)
	elif not look.is_zero_approx():
		facing_suffix = _vector_to_facing_suffix(look)
	_update_animation()
	_update_armed_effect()

func _update_animation() -> void:
	var prefix := "armed" if buffs.form() == PickUpConfig.PlayerFormMode.ARMED else "normal"
	var animation := "death" if is_dead else "%s_%s" % [prefix, facing_suffix]
	if sprite.animation != animation or not sprite.is_playing():
		sprite.play(animation)

func _update_armed_effect() -> void:
	armed_effect.visible = not is_dead and buffs.form() == PickUpConfig.PlayerFormMode.ARMED

func apply_damage(amount: int) -> bool:
	if is_dead or not controls_enabled or amount <= 0 or invincibility_time_left > 0.0:
		return false
	current_health = maxi(current_health - amount, 0)
	damaged.emit(amount)
	if current_health == 0:
		_die()
	else:
		invincibility_time_left = maxf(invincibility_duration, 0.0)
		_set_hurt_blink_enabled(invincibility_time_left > 0.0)
	return true

func get_current_health() -> int:
	return current_health

func _update_invincibility(delta: float) -> void:
	if invincibility_time_left > 0.0:
		invincibility_time_left = maxf(invincibility_time_left - delta, 0.0)
		if invincibility_time_left <= 0.0:
			_set_hurt_blink_enabled(false)

func _set_hurt_blink_enabled(enabled: bool) -> void:
	var material := sprite.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(BLINK_ENABLED_SHADER_PARAMETER, enabled)

func _die() -> void:
	is_dead = true
	controls_enabled = false
	velocity = Vector2.ZERO
	last_control = ControlFrame.new()
	controller.reset()
	buffs.clear()
	invincibility_time_left = 0.0
	_set_hurt_blink_enabled(false)
	move_sfx_player.stop()
	armed_effect.visible = false
	armed_effect.stop()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"death"):
		if not sprite.animation_finished.is_connected(_on_death_animation_finished):
			sprite.animation_finished.connect(_on_death_animation_finished)
		sprite.play("death")
	else:
		sprite.visible = false

func _on_death_animation_finished() -> void:
	if is_dead:
		sprite.visible = false
		sprite.animation_finished.disconnect(_on_death_animation_finished)

func _vector_to_facing_suffix(direction: Vector2) -> String:
	if absf(direction.x) >= absf(direction.y):
		return "left" if direction.x < 0.0 else "right"
	return "up" if direction.y < 0.0 else "down"

func apply_pickup(config: PickUpConfig) -> bool:
	if is_dead or not controls_enabled or not buffs.apply(config):
		return false
	pickup_sfx_player.play()
	pickup_collected.emit(config.pickup_type)
	return true
