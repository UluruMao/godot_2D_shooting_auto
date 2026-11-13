extends RefCounted

var checks := 0
var failures: Array[String] = []

class FixedController extends PlayerController:
	func sample(_context: Dictionary, _delta: float) -> ControlFrame:
		return ControlFrame.new(Vector2.RIGHT, Vector2.UP, true)

class InputProbeGame extends Game:
	var requested_restarts: Array[bool] = []
	func _restart(advance_seed: bool) -> void:
		# Observe restart dispatch without replacing the test runner's scene.
		requested_restarts.append(advance_seed)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func test_game_control_switch_pause_step_and_death() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Game = load("res://scene/game.tscn").instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	await tree.physics_frame
	await tree.process_frame
	var player := scene.player
	check(player.projectile_spawner.is_inside_tree(), "game owns a live projectile backend")
	var effect := PickUpConfig.new()
	effect.pickup_type = PickUpConfig.PickupType.RAPID
	effect.fire_rate_multiplier = 2.0
	effect.duration = 5.0
	player.apply_pickup(effect)
	player.weapon.reset()
	check(player.weapon.step(0.0, true, Vector2.UP, player.global_position) == 1, "real projectile spawn succeeds")
	var remaining := player.buffs.remaining(PickUpConfig.PickupType.RAPID)
	player.set_controller(FixedController.new())
	check(player.weapon.step(0.0, true, Vector2.UP, player.global_position) == 0, "switching controller cannot reset fire cooldown")
	check(player.buffs.remaining(PickUpConfig.PickupType.RAPID) == remaining, "switching controller preserves active effects")
	scene.toggle_auto()
	check(player.controller == scene.auto_controller, "auto mode uses the shared controller interface")
	scene.toggle_pause()
	var frozen := player.buffs.remaining(PickUpConfig.PickupType.RAPID)
	var position := player.global_position
	for i in 3:
		await tree.process_frame
	check(player.buffs.remaining(PickUpConfig.PickupType.RAPID) == frozen and player.global_position == position, "pause freezes gameplay and effect time")
	var key := InputEventKey.new()
	key.keycode = KEY_N
	key.pressed = true
	scene._unhandled_key_input(key)
	await tree.physics_frame
	await tree.process_frame
	check(tree.paused, "single step restores pause")
	var elapsed := frozen - player.buffs.remaining(PickUpConfig.PickupType.RAPID)
	check(elapsed > 0.0 and elapsed < 0.02, "single step advances one physics tick of buff time")
	tree.paused = false
	check(player.apply_damage(999), "lethal damage applies through normal mechanics")
	check(player.is_dead and not player.controls_enabled and player.buffs.fire_multiplier() == 1.0, "death clears controls and effects")
	scene.queue_free()
	await tree.process_frame
	tree.paused = false

func test_bomber_explosion_uses_actual_radius_once() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var holder := Node2D.new()
	tree.root.add_child(holder)
	var player: Player = load("res://scene/player.tscn").instantiate()
	player.position = Vector2(100, 100)
	holder.add_child(player)
	var bomber: Enemy = load("res://scene/enemy.tscn").instantiate()
	bomber.config = load("res://resources/config/enemy_bomber.tres")
	bomber.position = Vector2(130, 100)
	holder.add_child(bomber)
	bomber._begin_explosion()
	await tree.physics_frame
	await tree.process_frame
	check(player.current_health == 3, "bomber radius applies configured damage beyond contact range")
	player.invincibility_time_left = 0.0
	await tree.physics_frame
	await tree.process_frame
	check(player.current_health == 3, "explosion damage is applied once")
	holder.queue_free()
	await tree.process_frame

func test_ai_stage_profiling_is_optional_and_accounts_for_total_time() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Game = load("res://scene/game.tscn").instantiate()
	tree.root.add_child(scene)
	scene.auto_controller.profiling_enabled = true
	if not scene.auto_enabled:
		scene.toggle_auto()
	await tree.physics_frame
	await tree.process_frame
	var decision := scene.auto_controller.decision
	var sum := 0
	for stage: String in decision.stage_usec:
		sum += int(decision.stage_usec[stage])
	check(decision.stage_usec.has("observation") and decision.stage_usec.has("steering"), "profiling reports actual AI stages")
	check(sum <= decision.duration_usec, "stage timings fit within total measured AI time")
	scene.auto_controller.profiling_enabled = false
	await tree.physics_frame
	await tree.process_frame
	check(scene.auto_controller.decision.stage_usec.is_empty(), "profiling can be disabled without changing the controller interface")
	scene.queue_free()
	await tree.process_frame

func _press(keycode: Key, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await (Engine.get_main_loop() as SceneTree).process_frame

func test_shortcuts_through_runtime_input_and_hud_focus() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Game = load("res://scene/game.tscn").instantiate()
	scene.set_script(InputProbeGame)
	var probe := scene as InputProbeGame
	tree.root.add_child(probe)
	await tree.process_frame
	await tree.process_frame
	var initial_auto := probe.auto_enabled
	await _press(KEY_T, true)
	check(probe.auto_enabled == initial_auto, "Ctrl+T cannot toggle automatic control")
	await _press(KEY_T)
	check(probe.auto_enabled != initial_auto, "T toggles automatic control through runtime input")
	await _press(KEY_T)
	check(probe.auto_enabled == initial_auto, "a second T returns to the original control mode")
	var was_expanded := probe.inspector.expanded
	await _press(KEY_I)
	check(probe.inspector.expanded != was_expanded, "I toggles inspector through runtime input")
	var planner := int(probe.auto_controller.planner)
	await _press(KEY_C)
	check(int(probe.auto_controller.planner) == (planner + 1) % 3, "C cycles the planner through runtime input")
	await _press(KEY_R, true)
	check(probe.requested_restarts.is_empty(), "Ctrl+R cannot restart the run")
	await _press(KEY_R)
	await _press(KEY_Y)
	check(probe.requested_restarts == [false, true], "R and Y dispatch same-seed and next-seed restarts")
	await _press(KEY_ESCAPE)
	check(not tree.paused, "Escape is left to UI rather than toggling gameplay pause")
	await _press(KEY_P)
	check(tree.paused, "P pauses through runtime input")
	var frozen := probe.wave_pause_time_left
	await _press(KEY_N)
	await tree.physics_frame
	await tree.process_frame
	var elapsed := frozen - probe.wave_pause_time_left
	check(tree.paused and elapsed > 0.0 and elapsed < 0.02, "N advances exactly one paused simulation tick through runtime input")
	await _press(KEY_P)
	check(not tree.paused, "P resumes while the gameplay subtree is paused")
	for control: Node in probe.inspector.find_children("*", "Control", true, false):
		check((control as Control).focus_mode == Control.FOCUS_NONE, "inspector controls cannot steal arrow/Space input")
	probe.queue_free()
	await tree.process_frame
