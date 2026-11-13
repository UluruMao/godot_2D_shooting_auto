extends RefCounted
## Command bindings live in InputMap; the inspector reads the same bindings.

const AUTO := &"game_toggle_auto"
const INSPECTOR := &"game_toggle_inspector"
const PLANNER := &"game_cycle_planner"
const PAUSE := &"game_toggle_pause"
const STEP := &"game_step"
const RESTART := &"game_restart"
const NEXT_SEED := &"game_next_seed"
const ACTIONS := [AUTO, INSPECTOR, PLANNER, PAUSE, STEP, RESTART, NEXT_SEED]

static func action_for(event: InputEvent) -> StringName:
	if not event is InputEventKey or not event.pressed or event.echo:
		return &""
	for action: StringName in ACTIONS:
		# Exact matching prevents Ctrl+R and other editor chords running commands.
		if event.is_action_pressed(action, false, true):
			return action
	return &""

static func hint(action: StringName) -> String:
	var labels: PackedStringArray = []
	for event: InputEvent in InputMap.action_get_events(action):
		labels.append(event.as_text())
	return " / ".join(labels) if not labels.is_empty() else "Unbound"
