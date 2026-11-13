extends Node2D
class_name Game
## Coordinates run progression; player mechanics and AI have separate owners.

static var remembered_auto := false
static var remembered_planner := 2
static var remembered_seed := -1

const ENEMY_SCENE_PATH := "res://scene/enemy.tscn"
const Shortcuts := preload("res://scripts/control/game_shortcuts.gd")

@export var max_waves: int = 4
@export var wave_duration: float = 20.0
@export var wave_pause: float = 5.0
@export var spawn_interval_start: float = 0.4
@export var spawn_interval_end: float = 0.15
@export var initial_pause: float = 1.0

@export var enemy_configs: Array[EnemyConfig] = [
	preload("res://resources/config/enemy_basic.tres"),
	preload("res://resources/config/enemy_shelled.tres"),
	preload("res://resources/config/enemy_fast.tres"),
	preload("res://resources/config/enemy_bomber.tres"),
]

@onready var player: Player = $Player
@onready var enemy_container: Node2D = $EnemyContainer
@onready var spawn_points: Node2D = $EnemySpawnPoints
@onready var spawn_timer: Timer = $EnemySpawnTimer
@onready var life_count_label: Label = $HUDLayer/LifeCountLabel
@onready var wave_label: Label = $HUDLayer/WaveLabel
@onready var time_bar: Sprite2D = $HUDLayer/TimeBar
@onready var game_over_dialog: AcceptDialog = $AcceptDialog
@onready var bgm_player: AudioStreamPlayer = $AudioContainer/BGMPlayer
@onready var spiral_bgm_player: AudioStreamPlayer = $AudioContainer/SpiralBgmPlayer
@onready var result_win_sfx_player: AudioStreamPlayer = $AudioContainer/ResultWinSfxPlayer
@onready var result_lose_sfx_player: AudioStreamPlayer = $AudioContainer/ResultLoseSfxPlayer

var _time_bar_full_scale_x: float = 3.625
var _time_bar_texture_width: float = 48.0
var _time_bar_left_edge_x: float = 0.0

var current_wave: int = 0
var wave_time_left: float = 0.0
var wave_pause_time_left: float = 0.0
var is_pausing_between_waves: bool = false
var current_spawn_interval: float = 0.4
var game_ended: bool = false
var auto_enabled := false
var auto_controller := AutoController.new()
var inspector: AIInspector
var _step_requested := false
@export var run_seed := 12345
@export var ai_profile := AutoProfile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Resolve after actors so single-step pauses at the end of one complete tick.
	process_physics_priority = 10000
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			run_seed = argument.trim_prefix("--seed=").to_int()
	if remembered_seed >= 0:
		run_seed = remembered_seed
	seed(run_seed)
	for marker in spawn_points.get_children():
		if marker is Marker2D:
			marker.add_to_group("enemy_spawn_points")
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
	game_over_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	# Outcome sounds stay audible after the gameplay subtree is paused.
	result_win_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	result_lose_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	inspector = AIInspector.new()
	inspector.game = self
	add_child(inspector)
	auto_controller.planner = remembered_planner as AutoController.Planner
	auto_controller.configure(ai_profile)
	if remembered_auto or "--auto" in OS.get_cmdline_user_args():
		toggle_auto()
	if "--baseline" in OS.get_cmdline_user_args():
		auto_controller.planner = AutoController.Planner.BASELINE
	if "--route-only" in OS.get_cmdline_user_args():
		auto_controller.planner = AutoController.Planner.ROUTE_ONLY
	_setup_hud()
	$HUDLayer.visible = false # Screen-space inspector HUD replaces the world-space HUD.
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	game_over_dialog.confirmed.connect(_on_dialog_confirmed)
	game_over_dialog.canceled.connect(_on_dialog_canceled)
	game_over_dialog.dialog_hide_on_ok = true
	player.spiral_state_changed.connect(_on_spiral_state_changed)
	wave_pause_time_left = initial_pause
	is_pausing_between_waves = true
	_start_bgm()
	_update_hud()
	if "--verify-runtime" in OS.get_cmdline_user_args():
		_verify_runtime.call_deferred()

func _verify_runtime() -> void:
	# The release template does not run external source test scripts. Exercise
	# the packaged main scene through an explicit non-interactive launch option.
	if not auto_enabled:
		toggle_auto()
	for tick in 32:
		await get_tree().physics_frame
		await get_tree().process_frame
	var valid: bool = ClassDB.class_exists("ShooterPathfinder") and auto_controller.navigation.ready
	valid = valid and auto_controller.decision.path_status == "found" and player.current_health > 0
	valid = valid and not get_tree().root.has_node("_mcp_game_helper")
	print("RELEASE_CHECK_PASSED: native pathfinding and gameplay loaded" if valid else "RELEASE_CHECK_FAILED: packaged gameplay did not initialise")
	for node in find_children("*", "AudioStreamPlayer", true, false):
		node.stop()
	await get_tree().create_timer(0.1, true).timeout
	OS.delay_msec(200)
	get_tree().quit(0 if valid else 1)


func _setup_hud() -> void:
	wave_time_left = maxf(wave_duration, 0.0)

	if time_bar == null:
		return

	_time_bar_full_scale_x = time_bar.scale.x
	if time_bar.texture != null:
		_time_bar_texture_width = time_bar.texture.get_width()
		if time_bar.region_enabled:
			_time_bar_texture_width = time_bar.region_rect.size.x
	if time_bar.centered:
		_time_bar_left_edge_x = time_bar.position.x - (_time_bar_texture_width * _time_bar_full_scale_x * 0.5)
	else:
		_time_bar_left_edge_x = time_bar.position.x

	_update_hud()


func _update_time_bar() -> void:
	if time_bar == null:
		return

	var fill_ratio := 0.0
	if wave_duration > 0.0:
		fill_ratio = clampf(wave_time_left / wave_duration, 0.0, 1.0)

	time_bar.scale.x = _time_bar_full_scale_x * fill_ratio

	if not time_bar.centered:
		time_bar.position.x = _time_bar_left_edge_x
		return

	var current_width := _time_bar_texture_width * time_bar.scale.x
	time_bar.position.x = _time_bar_left_edge_x + (current_width * 0.5)


func _on_spiral_state_changed(active: bool) -> void:
	if game_ended or player.is_dead:
		return
	if active:
		if bgm_player != null:
			bgm_player.stop()
		if spiral_bgm_player != null and spiral_bgm_player.stream != null:
			_set_stream_loop(spiral_bgm_player.stream, true)
			spiral_bgm_player.play()
	else:
		if spiral_bgm_player != null:
			spiral_bgm_player.stop()
		if bgm_player != null and not bgm_player.playing:
			_start_bgm()


func _start_bgm() -> void:
	if bgm_player != null and bgm_player.stream != null:
		_set_stream_loop(bgm_player.stream, true)
		bgm_player.play()


func _set_stream_loop(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamMP3:
		stream.loop = enabled
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if enabled else AudioStreamWAV.LOOP_DISABLED


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_advance_wave(delta)
	if _step_requested:
		get_tree().paused = true
		_step_requested = false

func _advance_wave(delta: float) -> void:
	if get_tree().paused:
		return
	if game_ended:
		return

	_update_hud()

	if player.is_dead:
		_end_game(false)
		return

	if is_pausing_between_waves:
		wave_pause_time_left = maxf(wave_pause_time_left - delta, 0.0)
		if wave_pause_time_left <= 0.0:
			is_pausing_between_waves = false
			_start_next_wave()
		return

	if current_wave > 0:
		wave_time_left = maxf(wave_time_left - delta, 0.0)
		if wave_time_left <= 0.0:
			_end_wave()


func _start_next_wave() -> void:
	current_wave += 1
	if current_wave > max_waves:
		_end_game(true)
		return
	wave_time_left = wave_duration
	current_spawn_interval = _get_spawn_interval(current_wave)
	_on_spawn_timer_timeout()


func _get_spawn_interval(wave: int) -> float:
	if max_waves <= 1:
		return spawn_interval_start
	var progress: float = clampf(float(wave - 1) / float(max_waves - 1), 0.0, 1.0)
	return lerpf(spawn_interval_start, spawn_interval_end, progress)


func _on_spawn_timer_timeout() -> void:
	if game_ended or is_pausing_between_waves:
		return
	if current_wave <= 0 or wave_time_left <= 0.0:
		return
	_spawn_one_enemy()
	spawn_timer.wait_time = current_spawn_interval
	spawn_timer.start()


func _end_wave() -> void:
	_kill_all_enemies()
	if current_wave >= max_waves:
		_end_game(true)
		return
	wave_pause_time_left = wave_pause
	is_pausing_between_waves = true


func _kill_all_enemies() -> void:
	# Wave expiry uses normal death handling, including bomber effects and drops.
	for child in enemy_container.get_children():
		var enemy := child as Enemy
		if enemy != null:
			enemy.take_damage(999)


func _spawn_one_enemy() -> void:
	var enemy: CharacterBody2D = load(ENEMY_SCENE_PATH).instantiate()
	var cfg := _pick_enemy_config(current_wave)
	if cfg != null:
		enemy.config = cfg
	enemy.target = player
	enemy.drop_rng.seed = randi()
	enemy.global_position = _pick_spawn_position()
	enemy_container.add_child(enemy)


func _pick_spawn_position() -> Vector2:
	var markers: Array[Node] = []
	for child in spawn_points.get_children():
		if child is Marker2D:
			markers.append(child)
	if markers.is_empty():
		return Vector2(128, 128)
	var marker: Marker2D = markers[randi() % markers.size()]
	return marker.global_position


func _pick_enemy_config(wave: int) -> EnemyConfig:
	# Later waves shift pressure from basic enemies toward armor and explosions.
	if enemy_configs.is_empty():
		return null
	var progress: float = clampf(float(wave - 1) / float(maxi(max_waves - 1, 1)), 0.0, 1.0)

	var w_basic := lerpf(6.0, 1.0, progress)
	var w_shelled := lerpf(1.0, 4.0, progress)
	var w_fast := 3.0
	var w_bomber := lerpf(0.5, 3.5, progress)

	var weights: Array[float] = []
	var configs: Array[EnemyConfig] = []
	_collect_weighted(enemy_configs, EnemyConfig.EnemyType.BASIC, w_basic, weights, configs)
	_collect_weighted(enemy_configs, EnemyConfig.EnemyType.SHELLED, w_shelled, weights, configs)
	_collect_weighted(enemy_configs, EnemyConfig.EnemyType.FAST_SMALL, w_fast, weights, configs)
	_collect_weighted(enemy_configs, EnemyConfig.EnemyType.BOMBER, w_bomber, weights, configs)

	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0 or configs.is_empty():
		return enemy_configs[0]

	var roll := randf() * total
	var accumulated := 0.0
	for i in weights.size():
		accumulated += weights[i]
		if roll <= accumulated:
			return configs[i]
	return configs.back()


func _collect_weighted(all: Array[EnemyConfig], type: EnemyConfig.EnemyType, weight: float, out_weights: Array[float], out_configs: Array[EnemyConfig]) -> void:
	for cfg in all:
		if cfg.enemy_type == type:
			out_weights.append(weight)
			out_configs.append(cfg)


func _update_hud() -> void:
	if life_count_label != null and is_instance_valid(player):
		life_count_label.text = "x%d" % player.get_current_health()

	if wave_label != null:
		var display_wave: int = current_wave if current_wave > 0 else 1
		wave_label.text = "Wave %d / %d" % [display_wave, max_waves]

	if time_bar != null:
		if is_pausing_between_waves or current_wave <= 0:
			time_bar.visible = false
		else:
			time_bar.visible = true
			_update_time_bar()


func _end_game(is_victory: bool) -> void:
	if game_ended:
		return
	game_ended = true
	player.controls_enabled = false
	get_tree().paused = true
	spawn_timer.stop()
	if bgm_player != null:
		bgm_player.stop()
	if spiral_bgm_player != null:
		spiral_bgm_player.stop()
	if is_victory:
		game_over_dialog.title = "Victory"
		game_over_dialog.dialog_text = "All waves cleared!"
		if result_win_sfx_player != null:
			result_win_sfx_player.play()
	else:
		game_over_dialog.title = "Game Over"
		game_over_dialog.dialog_text = "You died on wave %d." % current_wave
		if result_lose_sfx_player != null:
			result_lose_sfx_player.play()
	game_over_dialog.popup_centered()


func _on_dialog_confirmed() -> void:
	print("[Game] confirmed: reloading scene")
	_restart(false)


func _on_dialog_canceled() -> void:
	print("[Game] canceled: quitting")
	get_tree().quit()

func toggle_auto() -> void:
	if game_ended:
		return
	auto_enabled = not auto_enabled
	player.set_controller(auto_controller if auto_enabled else HumanController.new())

func toggle_pause() -> void:
	if not game_ended:
		get_tree().paused = not get_tree().paused

func _unhandled_key_input(event: InputEvent) -> void:
	var action := Shortcuts.action_for(event)
	if action.is_empty():
		return
	# GUI controls get first refusal; consume each recognized command only once.
	get_viewport().set_input_as_handled()
	match action:
		Shortcuts.AUTO:
			toggle_auto()
		Shortcuts.INSPECTOR:
			inspector.toggle()
		Shortcuts.PLANNER:
			auto_controller.planner = ((int(auto_controller.planner) + 1) % 3) as AutoController.Planner
			auto_controller.reset()
		Shortcuts.PAUSE:
			toggle_pause()
		Shortcuts.RESTART:
			_restart(false)
		Shortcuts.NEXT_SEED:
			_restart(true)
		Shortcuts.STEP:
			if get_tree().paused and not game_ended and not _step_requested:
				_step_requested = true
				_step_once()

func _step_once() -> void:
	get_tree().paused = false

func _restart(advance_seed: bool) -> void:
	remembered_auto = auto_enabled
	remembered_planner = auto_controller.planner
	remembered_seed = run_seed + int(advance_seed)
	get_tree().paused = false
	get_tree().reload_current_scene()
