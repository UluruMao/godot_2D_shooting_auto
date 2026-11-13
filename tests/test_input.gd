extends RefCounted

const Shortcuts := preload("res://scripts/control/game_shortcuts.gd")
const GAMEPLAY_ACTIONS := [&"move_up", &"move_down", &"move_left", &"move_right", &"shoot", &"shoot_left", &"shoot_right", &"shoot_up", &"shoot_down"]

var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func test_project_bindings_have_no_duplicate_or_reserved_commands() -> void:
	var bindings: Array[Dictionary] = []
	var reserved_ui: Array[InputEvent] = []
	for action: StringName in [&"ui_accept", &"ui_cancel", &"ui_focus_next", &"ui_focus_prev", &"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		reserved_ui.append_array(InputMap.action_get_events(action))
	var actions: Array = GAMEPLAY_ACTIONS.duplicate()
	actions.append_array(Shortcuts.ACTIONS)
	for action: StringName in actions:
		var events := InputMap.action_get_events(action)
		check(not events.is_empty(), "%s has a configured binding" % action)
		for event: InputEvent in events:
			for previous: Dictionary in bindings:
				check(not event.is_match(previous.event), "%s and %s must not share a binding" % [action, previous.action])
			bindings.append({"action": action, "event": event})
			if action not in Shortcuts.ACTIONS:
				continue
			check(event is InputEventKey, "%s uses a keyboard command" % action)
			if event is InputEventKey:
				var keycode: Key = event.physical_keycode if event.physical_keycode else event.keycode
				check(keycode < KEY_F1 or keycode > KEY_F35, "%s leaves function keys to Godot" % action)
				for ui_event: InputEvent in reserved_ui:
					check(not event.is_match(ui_event), "%s avoids built-in UI commands" % action)
	check(not InputMap.has_action("toggle_enhanced") and not InputMap.has_action("toggle_accelerated"), "unused buff bindings are removed")

func test_commands_require_exact_nonrepeating_key_presses() -> void:
	for action: StringName in Shortcuts.ACTIONS:
		var event := InputMap.action_get_events(action)[0].duplicate() as InputEventKey
		event.pressed = true
		check(Shortcuts.action_for(event) == action, "%s resolves its configured key" % action)
		event.echo = true
		check(Shortcuts.action_for(event).is_empty(), "%s ignores held-key repeats" % action)
		event.echo = false
		event.pressed = false
		check(Shortcuts.action_for(event).is_empty(), "%s ignores releases" % action)
		event.pressed = true
		for modifier: String in ["ctrl_pressed", "alt_pressed", "meta_pressed", "shift_pressed"]:
			event.set(modifier, true)
			check(Shortcuts.action_for(event).is_empty(), "%s ignores %s chords" % [action, modifier])
			event.set(modifier, false)
	for keycode: Key in [KEY_F1, KEY_F2, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_ESCAPE, KEY_TAB, KEY_SPACE, KEY_UP]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = true
		check(Shortcuts.action_for(event).is_empty(), "%s cannot execute a game command" % event.as_text())
