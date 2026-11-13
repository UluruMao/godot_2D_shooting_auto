class_name PooledProjectileSpawner
extends SceneProjectileSpawner
## The free stack gives O(1) acquire/release once capacity is available.

@export var prewarm_count := 64
@export var max_capacity := 256
var _free: Array[Projectile] = []

func _ready() -> void:
	for i in clampi(prewarm_count, 0, max_capacity):
		_free.append(_create())

func spawn(origin: Vector2, direction: Vector2) -> bool:
	requested += 1
	if not is_inside_tree() or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		misses += 1
		return false
	if _free.is_empty():
		if created >= max_capacity:
			misses += 1
			return false
		_free.append(_create())
	return _activate(_free.pop_back(), origin, direction)

func _finish_release(bullet: Projectile, generation: int) -> void:
	if not is_instance_valid(bullet):
		return
	var id := bullet.get_instance_id()
	if bullet.active or bullet.activation != generation or not _pending.has(id):
		return
	_pending.erase(id)
	_free.append(bullet)
