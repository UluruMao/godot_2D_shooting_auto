extends RefCounted

var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func test_pool_lifecycle_and_exhaustion() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var pool := PooledProjectileSpawner.new()
	pool.prewarm_count = 1
	pool.max_capacity = 1
	tree.root.add_child(pool)
	check(pool.created == 1 and pool.metrics().active == 0, "prewarm creates inactive capacity")
	check(not (pool.get_child(0) as Projectile).monitorable, "inactive projectile is invisible to area queries")
	check(pool.spawn(Vector2(1000, 1000), Vector2.RIGHT), "acquire available projectile")
	var bullet := pool.get_child(0) as Projectile
	var old := bullet.activation
	check(not pool.spawn(Vector2.ZERO, Vector2.UP), "exhaustion is explicit")
	bullet.release()
	bullet.release()
	check(pool.released_count == 1 and pool.metrics().active == 0, "double release has no duplicate effect")
	check(not pool.spawn(Vector2.ZERO, Vector2.UP), "pending physics release cannot be reused immediately")
	await tree.process_frame
	check(pool.spawn(Vector2(1200, 1200), Vector2.DOWN), "released object becomes reusable after flush")
	check(pool.created == 1 and bullet.direction == Vector2.DOWN and bullet.damage == 1, "reuse resets state without allocating")
	check(bullet.remaining == Projectile.LIFETIME and bullet.visible, "reuse resets lifetime and visibility")
	bullet.release(old)
	check(bullet.active, "obsolete activation cannot release a reused projectile")
	bullet._physics_process(Projectile.LIFETIME)
	check(not bullet.active, "expiry releases projectile")
	await tree.process_frame
	check(pool.metrics().pending == 0 and pool.get_child_count() == 1, "inactive pooled node remains owned and settled")
	pool.queue_free()
	await tree.process_frame

func test_reference_and_pool_have_equal_activation_results() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for spawner: SceneProjectileSpawner in [SceneProjectileSpawner.new(), PooledProjectileSpawner.new()]:
		tree.root.add_child(spawner)
		for i in 5:
			check(spawner.spawn(Vector2(1000, 1000), Vector2.LEFT), "both spawners accept equivalent work")
		check(spawner.metrics().spawned == 5 and spawner.metrics().misses == 0, "same shot count without hidden misses")
		for bullet: Projectile in spawner.get_children():
			if bullet.active:
				var wall := Node.new()
				bullet._on_body_entered(wall)
				wall.free()
				# A second contact from the same physics flush must be harmless.
				bullet.release()
		check(spawner.released_count == 5, "one release per shot across both backends")
		await tree.process_frame
		spawner.queue_free()
		await tree.process_frame
