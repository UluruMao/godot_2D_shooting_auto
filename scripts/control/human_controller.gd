class_name HumanController
extends PlayerController

func sample(context: Dictionary, _delta: float) -> ControlFrame:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var look := Input.get_vector("shoot_left", "shoot_right", "shoot_up", "shoot_down")
	if look == Vector2.ZERO:
		var offset: Vector2 = context.mouse_position - context.position
		if offset.length_squared() > 1.0:
			look = offset
	return ControlFrame.new(movement, look, Input.is_action_pressed("shoot"))
