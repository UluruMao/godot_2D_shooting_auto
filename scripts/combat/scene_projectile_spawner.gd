class_name SceneProjectileSpawner
extends Node
## Reference instantiate/free spawner, and common activation/metrics contract.

var requested := 0
var created := 0
var spawned := 0
var released_count := 0
var misses := 0
var high_water := 0
var hits := 0
var _active: Dictionary = {}
var _pending: Dictionary = {}
var _scene: PackedScene

func spawn(origin: Vector2, direction: Vector2) -> bool:
	requested += 1
	if not is_inside_tree() or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		misses += 1
		return false
	return _activate(_create(), origin, direction)

func _create() -> Projectile:
	if _scene == null:
		_scene = load("res://scene/bullet.tscn")
	var bullet := _scene.instantiate() as Projectile
	add_child(bullet)
	bullet.released.connect(_on_released)
	bullet.enemy_hit.connect(func() -> void: hits += 1)
	created += 1
	return bullet

func _activate(bullet: Projectile, origin: Vector2, direction: Vector2) -> bool:
	if not bullet.activate(origin, direction):
		misses += 1
		return false
	_active[bullet.get_instance_id()] = bullet.activation
	spawned += 1
	high_water = maxi(high_water, _active.size())
	return true

func _on_released(bullet: Projectile, generation: int) -> void:
	var id := bullet.get_instance_id()
	if not _active.has(id) or int(_active[id]) != generation or _pending.has(id):
		return
	_active.erase(id)
	_pending[id] = generation
	released_count += 1
	_finish_release.call_deferred(bullet, generation)

func _finish_release(bullet: Projectile, generation: int) -> void:
	if not is_instance_valid(bullet):
		return
	var id := bullet.get_instance_id()
	if bullet.active or bullet.activation != generation or not _pending.has(id):
		return
	_pending.erase(id)
	bullet.queue_free()

func metrics() -> Dictionary:
	return {"requested": requested, "created": created, "spawned": spawned,
		"released": released_count, "active": _active.size(), "pending": _pending.size(),
		"high_water": high_water, "misses": misses, "hits": hits}
