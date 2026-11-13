class_name WorldPerception
extends RefCounted
## Main-thread adapter: snapshots contain observed values, never live actor nodes.

static func capture(player: Player) -> Dictionary:
	var enemies: Array[Dictionary] = []
	for enemy: Enemy in player.get_tree().get_nodes_in_group("enemies"):
		if enemy.death_stage == Enemy.DeathSequenceStage.DONE:
			continue
		var config := enemy.config
		enemies.append({"id": enemy.get_instance_id(), "position": enemy.global_position,
			"velocity": enemy.velocity, "radius": config.collision_radius if config != null else 8.0,
			"bomber": config != null and config.explode_on_death,
			"blast_radius": config.explosion_radius if config != null else 0.0,
			"dying": enemy.death_stage != Enemy.DeathSequenceStage.NONE,
			"health": enemy.current_health})
	var pickups: Array[Dictionary] = []
	for item: Pickup in player.get_tree().get_nodes_in_group("pickups"):
		if item.config != null and not item.is_queued_for_deletion():
			pickups.append({"id": item.get_instance_id(), "position": item.global_position,
				"category": item.config.pickup_type, "remaining": item.lifetime_timer.time_left,
				"duration": item.config.duration})
	var effects := {}
	for category in [PickUpConfig.PickupType.SPEED, PickUpConfig.PickupType.RAPID, PickUpConfig.PickupType.SPIRAL]:
		effects[category] = player.buffs.remaining(category)
	# Visible spawn markers are terrain knowledge, not access to future spawns.
	var spawn_points := PackedVector2Array()
	for marker: Marker2D in player.get_tree().get_nodes_in_group("enemy_spawn_points"):
		spawn_points.append(marker.global_position)
	return {"enemies": enemies, "pickups": pickups, "effects": effects, "spawn_points": spawn_points,
		"speed": player.move_speed * player.buffs.move_multiplier(), "radius": 6.0,
		"tick": Engine.get_physics_frames(), "velocity": player.velocity}
