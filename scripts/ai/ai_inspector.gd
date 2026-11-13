class_name AIInspector
extends CanvasLayer
## Presentation only: reads published decisions and never calls the planner.

const Shortcuts := preload("res://scripts/control/game_shortcuts.gd")

var game: Game
var expanded := true
var _status: Label
var _details: Label
var _panel: PanelContainer
var _drawing: Node2D
var _due := 0.0

class DecisionDrawing extends Node2D:
	var inspector: AIInspector
	func _draw() -> void:
		if not inspector.expanded or not inspector.game.auto_enabled:
			return
		var decision: AutoDecision = inspector.game.auto_controller.decision
		draw_set_transform_matrix(get_viewport().get_canvas_transform())
		for point: Vector2 in decision.spawn_points:
			draw_circle(point, inspector.game.ai_profile.spawn_safety_radius, Color(0.8, 0.35, 1.0, 0.35), false, 0.7)
		for enemy: Dictionary in decision.enemies:
			var reach: float = float(enemy.blast_radius) if enemy.bomber else float(enemy.radius) + 6.0
			draw_circle(enemy.position, reach, Color(1.0, 0.35, 0.2, 0.5), false, 0.6)
			draw_line(enemy.position, Vector2(enemy.position) + Vector2(enemy.velocity) * decision.horizon, Color(1, 0.5, 0.3, 0.6), 0.6)
		for index: int in decision.explored:
			var nav: NavigationGrid = inspector.game.auto_controller.navigation
			var center := nav.center(Vector2i(index % nav.width, index / nav.width))
			draw_rect(Rect2(center - Vector2.ONE * 2, Vector2.ONE * 4), Color(0.25, 0.6, 1, 0.10))
		if decision.path.size() > 1:
			draw_polyline(decision.path, Color(1, 0.85, 0.25, 0.8), 0.9, true)
		for candidate: Dictionary in decision.candidates:
			var tint := Color(0.3, 0.9, 0.7, 0.14) if candidate.legal else Color(1, 0.2, 0.3, 0.18)
			draw_line(decision.origin, candidate.endpoint, tint, 0.5)
		draw_line(decision.origin, decision.endpoint, Color(0.25, 1, 0.65), 1.5, true)
		draw_circle(decision.goal, 3.5, Color(1, 0.9, 0.2), false, 1.0)
		if decision.target_id != 0:
			draw_line(decision.origin, decision.aim_point, Color(0.25, 0.9, 1, 0.8), 0.8, true)
			draw_circle(decision.aim_point, 2.5, Color(0.25, 0.9, 1), false, 0.8)
		draw_set_transform_matrix(Transform2D.IDENTITY)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_font_size_override("font_size", 16)
	add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(16, 72)
	add_child(buttons)
	for item in [[Shortcuts.AUTO, "Auto", game.toggle_auto], [Shortcuts.INSPECTOR, "Inspector", toggle], [Shortcuts.PAUSE, "Pause", game.toggle_pause]]:
		var button := Button.new()
		button.text = "%s %s" % [Shortcuts.hint(item[0]), item[1]]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(item[2])
		buttons.add_child(button)
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 112)
	_panel.size = Vector2(292, 590)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.09, 0.96)
	style.border_color = Color(0.15, 0.35, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_details = Label.new()
	_details.custom_minimum_size = Vector2(264, 0)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_details.add_theme_font_size_override("font_size", 14)
	var scroll := ScrollContainer.new()
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.custom_minimum_size = Vector2(264, 550)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	scroll.add_child(_details)
	_drawing = DecisionDrawing.new()
	_drawing.inspector = self
	add_child(_drawing)
	move_child(_drawing, 0) # World annotations stay behind the readable HUD.

func toggle() -> void:
	expanded = not expanded
	_panel.visible = expanded

func _process(delta: float) -> void:
	_drawing.queue_redraw()
	_due -= delta
	if _due > 0.0:
		return
	_due = 0.1
	var mode := "AUTO" if game.auto_enabled else "MANUAL"
	if get_tree().paused:
		mode += " | PAUSED" if not game.game_ended else " | FINISHED"
	_status.text = "%s | Seed %d\nHP %d/%d   Wave %d/%d   %.1fs" % [mode, game.run_seed,
		game.player.current_health, game.player.max_health, maxi(game.current_wave, 1),
		game.max_waves, game.wave_time_left]
	if not expanded:
		return
	var pool: Dictionary = game.player.projectile_spawner.metrics()
	var text := "AI INSPECTOR\n\n"
	if not game.auto_enabled:
		text += "Manual control\nWASD move, mouse aim, click fire.\nPress %s to enable the autoplayer.\n\n%s cycles baseline, route-only,\nand predictive planning.\n\n" % [Shortcuts.hint(Shortcuts.AUTO), Shortcuts.hint(Shortcuts.PLANNER)]
	else:
		var bot: AutoController = game.auto_controller
		var d: AutoDecision = bot.decision
		text += ["BASELINE", "A* ROUTE ONLY", "PREDICTIVE"][bot.planner] + "\n"
		text += d.objective + "\n" + d.reason + "\n\n"
		if not d.tactical_reason.is_empty():
			text += "%s\n" % d.tactical_reason
		if bot.planner == AutoController.Planner.PREDICTIVE:
			text += "Reachable cells %d | room %.0f%%\n\n" % [d.reachable_cells, d.escape_room * 100.0]
		else:
			text += "Tactical retreat checks disabled\n\n"
		text += "Path: %s | expanded %d\nCost %.1f | age %d ticks\n" % [d.path_status, d.explored.size(), d.path_cost, maxi(0, d.tick - d.route_tick)]
		if d.route_blockaded:
			text += "Enemy blockade: clear with fire\n"
		text += "Target: %d\nFire: %s\n%s\n\n" % [d.target_id, "YES" if d.fire else "NO", d.shot_reason]
		var reasons := {}
		var legal := 0
		for candidate: Dictionary in d.candidates:
			if candidate.legal:
				legal += 1
			else:
				reasons[candidate.reason] = int(reasons.get(candidate.reason, 0)) + 1
		text += "Movement: %d / %d pass checks\n" % [legal, d.candidates.size()]
		for reason: String in reasons:
			text += "%s: %d\n" % [reason, reasons[reason]]
		if d.selected >= 0:
			var selected: Dictionary = d.candidates[d.selected]
			text += "Chosen score %.1f\nPredicted clearance %.1f px\n" % [selected.score, selected.clearance]
			if d.emergency:
				text += "Forecast contact in %.2fs\n" % selected.collision_time
		text += "%s\nAI %.2f ms | horizon %.2fs\n" % [d.selection_rule, d.duration_usec / 1000.0, d.horizon]
		if d.candidates.size() == 1:
			text += "Other directions not evaluated.\n"
		text += "EMERGENCY: no passing sample\n" if d.emergency else "Predictions are approximate.\n"
	text += "\nPROJECTILES\nActive %d | peak %d\nCreated %d | fired %d | misses %d\n" % [pool.active, pool.high_water, pool.created, pool.spawned, pool.misses]
	text += "\nYellow: A* route\nGreen: chosen short trajectory\nCyan: aim / intercept\nOrange: enemy reach / forecast\nPurple: spawn avoidance\nBlue cells: expanded search\n\n%s Auto | %s Inspector | %s Planner\n%s Pause | %s Step\n%s Same seed | %s Next seed" % [Shortcuts.hint(Shortcuts.AUTO), Shortcuts.hint(Shortcuts.INSPECTOR), Shortcuts.hint(Shortcuts.PLANNER), Shortcuts.hint(Shortcuts.PAUSE), Shortcuts.hint(Shortcuts.STEP), Shortcuts.hint(Shortcuts.RESTART), Shortcuts.hint(Shortcuts.NEXT_SEED)]
	_details.text = text
