class_name NavigationGrid
extends RefCounted
## Static terrain is sampled from physical colliders, including transformed tiles.

var cell_size := 8.0
var bounds := Rect2(0, 0, 256, 256)
var width := 32
var height := 32
var blocked := PackedByteArray()
var native: RefCounted
var ready := false
var diagnostic := ""
var _room := PackedFloat32Array()
var _centers := PackedVector2Array()
const DIRECTIONS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

func build(space: PhysicsDirectSpaceState2D, radius := 6.5) -> bool:
	if not ClassDB.class_exists("ShooterPathfinder"):
		diagnostic = "Native pathfinder missing: run scripts/build_native.ps1 and reimport the project."
		return false
	native = ClassDB.instantiate("ShooterPathfinder")
	width = ceili(bounds.size.x / cell_size)
	height = ceili(bounds.size.y / cell_size)
	blocked.resize(width * height)
	_centers.resize(width * height)
	for y in height:
		for x in width:
			_centers[y * width + x] = bounds.position + (Vector2(x, y) + Vector2.ONE * 0.5) * cell_size
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	for y in height:
		for x in width:
			query.transform = Transform2D(0, center(Vector2i(x, y)))
			blocked[y * width + x] = int(not space.intersect_shape(query, 1).is_empty())
	_room.resize(width * height)
	for y in height:
		for x in width:
			_room[y * width + x] = _measure_room(Vector2i(x, y))
	ready = true
	diagnostic = "Native A* ready"
	return true

func cell(point: Vector2) -> Vector2i:
	var offset := (point - bounds.position) / cell_size
	return Vector2i(floori(offset.x), floori(offset.y))

func center(coordinate: Vector2i) -> Vector2:
	if _centers.size() == width * height and coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < width and coordinate.y < height:
		return _centers[coordinate.y * width + coordinate.x]
	return bounds.position + (Vector2(coordinate) + Vector2.ONE * 0.5) * cell_size

func is_blocked(coordinate: Vector2i) -> bool:
	return coordinate.x < 0 or coordinate.y < 0 or coordinate.x >= width or coordinate.y >= height or blocked[coordinate.y * width + coordinate.x] != 0

func room_at(point: Vector2) -> float:
	var coordinate := cell(point)
	if is_blocked(coordinate):
		return 0.0
	return _room[coordinate.y * width + coordinate.x] if _room.size() == blocked.size() else _measure_room(coordinate)

func _measure_room(coordinate: Vector2i) -> float:
	if is_blocked(coordinate):
		return 0.0
	var total := 0.0
	for direction: Vector2i in DIRECTIONS:
		var previous := coordinate
		for step in range(1, 6):
			var next := coordinate + direction * step
			if is_blocked(next) or (direction.x != 0 and direction.y != 0 and (is_blocked(previous + Vector2i(direction.x, 0)) or is_blocked(previous + Vector2i(0, direction.y)))):
				break
			total += 1.0
			previous = next
	return total / 40.0

func nearest_free(point: Vector2) -> Vector2i:
	var direct := cell(point)
	if not is_blocked(direct):
		return direct
	var nearest := Vector2i(-1, -1)
	var distance := INF
	for y in height:
		for x in width:
			var coordinate := Vector2i(x, y)
			if is_blocked(coordinate):
				continue
			var candidate := center(coordinate).distance_squared_to(point)
			if candidate < distance:
				distance = candidate
				nearest = coordinate
	return nearest

func risk_field(enemies: Array) -> PackedFloat64Array:
	var risk := PackedFloat64Array()
	risk.resize(width * height)
	var centers_cached := _centers.size() == blocked.size()
	for enemy: Dictionary in enemies:
		if enemy.dying and not enemy.bomber:
			continue
		var position: Vector2 = enemy.position
		var location := cell(position)
		for y in range(maxi(location.y - 7, 0), mini(location.y + 8, height)):
			for x in range(maxi(location.x - 7, 0), mini(location.x + 8, width)):
				var point := _centers[y * width + x] if centers_cached else center(Vector2i(x, y))
				var distance := point.distance_to(position)
				var reach: float = enemy.blast_radius + 10.0 if enemy.bomber else 26.0
				risk[y * width + x] += maxf(0.0, 1.0 - distance / (reach + 25.0)) * 5.0
	return risk

func route(origin: Vector2, destination: Vector2, risk: PackedFloat64Array, threats := PackedByteArray()) -> Dictionary:
	if not ready:
		return {"status": "native_unavailable", "path": PackedVector2Array(), "explored": PackedInt32Array(), "cost": 0.0}
	var source := nearest_free(origin)
	var goal := nearest_free(destination)
	var obstacles := blocked
	if threats.size() == blocked.size():
		obstacles = blocked.duplicate()
		for i in threats.size():
			if obstacles[i] == 0 and threats[i] != 0:
				obstacles[i] = threats[i]
		# A threatened start must still be able to leave; static walls stay blocked.
		if not is_blocked(source):
			obstacles[source.y * width + source.x] = 0
	var result: Dictionary = native.call("find_path", obstacles, width, height, source, goal, risk, 4096, true)
	var points := PackedVector2Array()
	for coordinate: Vector2 in result.path:
		points.append(center(Vector2i(coordinate)))
	result.path = points
	return result
