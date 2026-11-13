extends CharacterBody2D
class_name Enemy
## Per-instance combat state; EnemyConfig supplies shared, immutable tuning data.

const DEFAULT_BULLET_DAMAGE := 1
const BLINK_ENABLED_SHADER_PARAMETER := &"blink_enabled"
const PICKUP_SCENE := preload("res://scene/pickup.tscn")

var drop_rng := RandomNumberGenerator.new()

enum DeathSequenceStage {
	NONE,
	DEATH,
	EXPLOSION,
	DONE,
}

@export var config: EnemyConfig
@export var touch_damage: int = 1
@export var touch_damage_interval: float = 1.0
@export var hurt_blink_duration: float = 0.16

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var touch_damage_area: Area2D = $TouchDamageArea
@onready var touch_damage_shape: CollisionShape2D = $TouchDamageArea/CollisionShape
@onready var explosion_area: Area2D = $ExplosionArea
@onready var explosion_shape: CollisionShape2D = $ExplosionArea/CollisionShape2D
@onready var hit_sfx_player: AudioStreamPlayer = $AudioContainer/HitSfxplayer
@onready var die_sfx_player: AudioStreamPlayer = $AudioContainer/DieSfxPlayer
@onready var explode_sfx_player: AudioStreamPlayer = $AudioContainer/ExplodeSfxPlayer

var current_health: int = 0
var death_stage: DeathSequenceStage = DeathSequenceStage.NONE
var touch_damage_cooldown: float = 0.0
var hurt_blink_time_left: float = 0.0
var target: Node2D = null
var _stage_remaining := 0.0
var _explosion_pending := false


func _ready() -> void:
	add_to_group("enemies")
	# PackedScene instances otherwise share these mutable shape resources.
	collision_shape.shape = collision_shape.shape.duplicate()
	touch_damage_shape.shape = touch_damage_shape.shape.duplicate()
	explosion_shape.shape = explosion_shape.shape.duplicate()
	if config != null:
		current_health = config.max_health
		_apply_collision_radius(config.collision_radius)
		_apply_frames(config)
		explosion_shape.disabled = not config.explode_on_death
		if config.explode_on_death and config.explosion_radius > 0.0:
			var explosion_circle := explosion_shape.shape as CircleShape2D
			if explosion_circle != null:
				explosion_circle.radius = config.explosion_radius
		_play_animation(config.move_animation_name)
	else:
		current_health = 1

	touch_damage_area.body_entered.connect(_on_touch_body_entered)
	touch_damage_area.body_exited.connect(_on_touch_body_exited)
	explosion_area.monitoring = false
	_set_hurt_blink_enabled(false)


func _physics_process(delta: float) -> void:
	if death_stage != DeathSequenceStage.NONE:
		velocity = Vector2.ZERO
		if _explosion_pending:
			_deal_explosion_damage()
		_stage_remaining = maxf(0.0, _stage_remaining - delta)
		if _stage_remaining <= 0.0:
			if death_stage == DeathSequenceStage.DEATH:
				_on_death_timeout()
			elif death_stage == DeathSequenceStage.EXPLOSION:
				_on_explosion_timeout()
		return

	_update_touch_cooldown(delta)
	_update_hurt_blink(delta)

	if target != null and is_instance_valid(target):
		var to_target: Vector2 = target.global_position - global_position
		var distance := to_target.length()
		var speed := config.move_speed if config != null else 60.0
		if distance > 1.0:
			velocity = to_target.normalized() * speed
		else:
			velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func take_damage(amount: int) -> void:
	if death_stage != DeathSequenceStage.NONE:
		return
	if amount <= 0:
		return
	current_health = maxi(current_health - amount, 0)
	_start_hurt_blink()
	_play_sfx(hit_sfx_player)
	if current_health <= 0:
		_begin_death()


func _on_touch_body_entered(body: Node2D) -> void:
	_try_deal_touch_damage(body)


func _on_touch_body_exited(_body: Node2D) -> void:
	pass


func _try_deal_touch_damage(body: Node2D) -> void:
	if death_stage != DeathSequenceStage.NONE:
		return
	if touch_damage_cooldown > 0.0:
		return
	var player := body as Player
	if player == null:
		return
	if player.apply_damage(touch_damage):
		touch_damage_cooldown = touch_damage_interval


func _update_touch_cooldown(delta: float) -> void:
	if touch_damage_cooldown > 0.0:
		touch_damage_cooldown = maxf(touch_damage_cooldown - delta, 0.0)
	if touch_damage_cooldown <= 0.0:
		for body in touch_damage_area.get_overlapping_bodies():
			_try_deal_touch_damage(body)
			if touch_damage_cooldown > 0.0:
				break


func _begin_death() -> void:
	death_stage = DeathSequenceStage.DEATH
	velocity = Vector2.ZERO
	touch_damage_area.set_deferred("monitoring", false)
	_play_sfx(die_sfx_player)
	var anim_name := config.death_animation_name if config != null else &"death"
	_play_animation(anim_name)
	if not animated_sprite.animation_finished.is_connected(_on_death_animation_finished):
		animated_sprite.animation_finished.connect(_on_death_animation_finished)
	var death_duration := _get_animation_duration(anim_name)
	# Physics-owned fallback also completes missing or looping death animations.
	if death_duration <= 0.0:
		death_duration = 0.5
	_stage_remaining = death_duration


func _on_death_timeout() -> void:
	if death_stage == DeathSequenceStage.DEATH:
		if config != null and config.explode_on_death:
			_begin_explosion()
		else:
			_finish_death()


func _on_death_animation_finished() -> void:
	if death_stage == DeathSequenceStage.DEATH:
		if config != null and config.explode_on_death:
			_begin_explosion()
		else:
			_finish_death()


func _begin_explosion() -> void:
	death_stage = DeathSequenceStage.EXPLOSION
	velocity = Vector2.ZERO
	_play_sfx(explode_sfx_player)
	# Query once on the next physics tick. Enabling monitoring and immediately
	# reading overlaps would use the area's stale overlap cache.
	_explosion_pending = true
	var anim_name := config.explosion_animation_name if config != null else &"explode"
	_play_animation(anim_name)
	if not animated_sprite.animation_finished.is_connected(_on_explosion_animation_finished):
		animated_sprite.animation_finished.connect(_on_explosion_animation_finished)
	var explosion_duration := _get_animation_duration(anim_name)
	if explosion_duration <= 0.0:
		explosion_duration = 0.5
	_stage_remaining = explosion_duration

func _deal_explosion_damage() -> void:
	_explosion_pending = false
	if config == null or config.explosion_damage <= 0:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = explosion_shape.shape
	query.transform = explosion_shape.global_transform
	query.collision_mask = 2
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var player := hit.collider as Player
		if player != null:
			player.apply_damage(config.explosion_damage)


func _on_explosion_timeout() -> void:
	if death_stage == DeathSequenceStage.EXPLOSION:
		_finish_death()


func _on_explosion_animation_finished() -> void:
	if death_stage == DeathSequenceStage.EXPLOSION:
		_finish_death()


func _finish_death() -> void:
	# Animation completion and the fallback clock may resolve in the same tick.
	# This guard makes drops and disposal exactly-once operations.
	if death_stage == DeathSequenceStage.DONE:
		return
	death_stage = DeathSequenceStage.DONE
	_try_drop_pickup()
	queue_free()


func _try_drop_pickup() -> void:
	if config == null:
		return
	if config.pickup_drop_configs.is_empty():
		return
	if randf() > config.pickup_drop_chance:
		return
	var weights := PackedFloat64Array()
	for pickup_config in config.pickup_drop_configs:
		weights.append(pickup_config.drop_weight if pickup_config != null else 0.0)
	var idx := WeightedSampler.pick(weights, drop_rng)
	if idx < 0:
		return
	var pickup: Area2D = PICKUP_SCENE.instantiate()
	pickup.config = config.pickup_drop_configs[idx]
	pickup.global_position = global_position
	get_parent().add_child(pickup)


func _apply_collision_radius(radius: float) -> void:
	var body_circle := collision_shape.shape as CircleShape2D
	if body_circle != null:
		body_circle.radius = radius
	var touch_circle := touch_damage_shape.shape as CircleShape2D
	if touch_circle != null:
		touch_circle.radius = radius


func _apply_frames(cfg: EnemyConfig) -> void:
	if cfg.enemy_frames == null:
		return
	animated_sprite.sprite_frames = cfg.enemy_frames


func _play_animation(anim_name: StringName) -> void:
	if animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)


func _get_animation_duration(anim_name: StringName) -> float:
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim_name):
		return 0.0
	var frame_count := frames.get_frame_count(anim_name)
	var speed := frames.get_animation_speed(anim_name)
	if speed <= 0.0:
		return 0.0
	return float(frame_count) / speed


func _start_hurt_blink() -> void:
	hurt_blink_time_left = hurt_blink_duration
	_set_hurt_blink_enabled(true)


func _update_hurt_blink(delta: float) -> void:
	if hurt_blink_time_left <= 0.0:
		return
	hurt_blink_time_left = maxf(hurt_blink_time_left - delta, 0.0)
	if hurt_blink_time_left <= 0.0:
		_set_hurt_blink_enabled(false)


func _set_hurt_blink_enabled(enabled: bool) -> void:
	var sprite_material := animated_sprite.material as ShaderMaterial
	if sprite_material != null:
		sprite_material.set_shader_parameter(BLINK_ENABLED_SHADER_PARAMETER, enabled)


func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null:
		player.play()
