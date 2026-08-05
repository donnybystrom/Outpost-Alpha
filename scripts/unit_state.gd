extends RefCounted

const WORKER_ROLE := "worker"
const WORKER_SPEED_TILES_PER_SECOND := 3.0
const ROAD_SPEED_MULTIPLIER := 1.3

var workers: Array[Dictionary] = []
var selected_unit_ids := {}
var path_revisions: int = 0
var _next_unit_id: int = 1


func reset(start_tile: Vector2i, worker_count: int) -> void:
	workers.clear()
	selected_unit_ids.clear()
	_next_unit_id = 1
	path_revisions = 0
	_spawn_workers(start_tile, worker_count)


func set_worker_destination(target: Vector2i, pathfinding_grid: RefCounted) -> void:
	_set_worker_group_destination(_worker_indices(), target, pathfinding_grid)


func set_selected_worker_destination(target: Vector2i, pathfinding_grid: RefCounted) -> void:
	_set_worker_group_destination(_selected_worker_indices(), target, pathfinding_grid)


func _set_worker_group_destination(worker_indices: Array[int], target: Vector2i, pathfinding_grid: RefCounted) -> void:
	if pathfinding_grid == null or not pathfinding_grid.is_tile_passable(target):
		return
	if worker_indices.is_empty():
		return

	var formation_targets := _formation_targets(target, worker_indices.size(), pathfinding_grid)
	for assignment_index in worker_indices.size():
		var unit_index: int = worker_indices[assignment_index]
		var unit_target: Vector2i = formation_targets[mini(assignment_index, formation_targets.size() - 1)]
		_set_unit_path(unit_index, unit_target, pathfinding_grid)
	path_revisions += 1


func recalculate_paths(pathfinding_grid: RefCounted) -> void:
	if pathfinding_grid == null:
		return
	for index in workers.size():
		var target: Vector2i = workers[index]["target_tile"]
		_set_unit_path(index, target, pathfinding_grid)
	path_revisions += 1


func advance(delta: float, pathfinding_grid: RefCounted) -> bool:
	var moved := false
	for index in workers.size():
		var worker := workers[index]
		var path: Array = worker["path"]
		var path_index: int = worker["path_index"]
		if path_index >= path.size():
			continue

		var remaining_distance: float = WORKER_SPEED_TILES_PER_SECOND * delta
		while remaining_distance > 0.0 and path_index < path.size():
			var position: Vector2 = worker["position"]
			var next_tile: Vector2i = path[path_index]
			var next_position := Vector2(next_tile)
			var distance_to_next := position.distance_to(next_position)
			var speed_multiplier := ROAD_SPEED_MULTIPLIER if pathfinding_grid != null and pathfinding_grid.is_fast_tile(next_tile) else 1.0
			var step_distance := remaining_distance * speed_multiplier

			if distance_to_next <= step_distance or distance_to_next <= 0.001:
				worker["position"] = next_position
				worker["tile"] = next_tile
				path_index += 1
				worker["path_index"] = path_index
				remaining_distance -= distance_to_next / speed_multiplier
			else:
				worker["position"] = position.lerp(next_position, step_distance / distance_to_next)
				worker["tile"] = Vector2i(roundi(worker["position"].x), roundi(worker["position"].y))
				remaining_distance = 0.0
			moved = true

		workers[index] = worker
	return moved


func select_workers_in_rect(world_rect: Rect2, world_to_screen: Callable) -> int:
	selected_unit_ids.clear()
	for worker in workers:
		var position: Vector2 = worker["position"]
		var screen_position: Vector2 = world_to_screen.call(position)
		if world_rect.has_point(screen_position):
			selected_unit_ids[int(worker["id"])] = true
	return selected_unit_ids.size()


func select_worker_near(screen_position: Vector2, world_to_screen: Callable, radius: float = 10.0) -> bool:
	var closest_id := -1
	var closest_distance := radius
	for worker in workers:
		var worker_screen_position: Vector2 = world_to_screen.call(worker["position"])
		var distance := worker_screen_position.distance_to(screen_position)
		if distance <= closest_distance:
			closest_id = int(worker["id"])
			closest_distance = distance
	selected_unit_ids.clear()
	if closest_id >= 0:
		selected_unit_ids[closest_id] = true
		return true
	return false


func clear_selection() -> void:
	selected_unit_ids.clear()


func has_selection() -> bool:
	return not selected_unit_ids.is_empty()


func is_selected(unit_id: int) -> bool:
	return selected_unit_ids.has(unit_id)


func _spawn_workers(start_tile: Vector2i, worker_count: int) -> void:
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
	]
	for index in worker_count:
		var tile := start_tile + offsets[index % offsets.size()]
		workers.append({
			"id": _next_unit_id,
			"role": WORKER_ROLE,
			"position": Vector2(tile),
			"tile": tile,
			"target_tile": tile,
			"path": [],
			"path_index": 0,
			"visual_offset": _visual_offset_for_index(index),
		})
		_next_unit_id += 1


func _set_unit_path(index: int, target: Vector2i, pathfinding_grid: RefCounted) -> void:
	var worker := workers[index]
	var start_tile: Vector2i = worker["tile"]
	var path: Array[Vector2i] = pathfinding_grid.find_path(start_tile, target)
	if path.size() > 1:
		path.remove_at(0)
	elif path.size() == 1:
		path.clear()
	worker["target_tile"] = target if not path.is_empty() or start_tile == target else start_tile
	worker["path"] = path
	worker["path_index"] = 0
	workers[index] = worker


func _worker_indices() -> Array[int]:
	var indices: Array[int] = []
	for index in workers.size():
		indices.append(index)
	return indices


func _selected_worker_indices() -> Array[int]:
	var indices: Array[int] = []
	for index in workers.size():
		if selected_unit_ids.has(int(workers[index]["id"])):
			indices.append(index)
	return indices


func _formation_targets(anchor: Vector2i, count: int, pathfinding_grid: RefCounted) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	var max_radius := 10
	for radius in range(0, max_radius + 1):
		for offset in _formation_offsets_for_radius(radius):
			var tile := anchor + offset
			if targets.has(tile):
				continue
			if pathfinding_grid.is_tile_passable(tile):
				targets.append(tile)
				if targets.size() >= count:
					return targets
	return targets


func _formation_offsets_for_radius(radius: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if radius == 0:
		offsets.append(Vector2i.ZERO)
		return offsets

	offsets.append(Vector2i(0, -radius))
	offsets.append(Vector2i(radius, 0))
	offsets.append(Vector2i(0, radius))
	offsets.append(Vector2i(-radius, 0))
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if maxi(absi(x), absi(y)) == radius:
				var offset := Vector2i(x, y)
				if not offsets.has(offset):
					offsets.append(offset)
	return offsets


func _visual_offset_for_index(index: int) -> Vector2:
	var offsets: Array[Vector2] = [
		Vector2(0, -2),
		Vector2(3, -1),
		Vector2(-3, -1),
		Vector2(2, 2),
		Vector2(-2, 2),
		Vector2(4, 1),
		Vector2(-4, 1),
		Vector2(1, -4),
		Vector2(-1, -4),
	]
	return offsets[index % offsets.size()]
