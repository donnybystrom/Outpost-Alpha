extends RefCounted

const WORKER_ROLE := "worker"
const DRILLING_MACHINE_ROLE := "drilling_machine"
const HAULER_ROLE := "hauler"
const WORKER_SPEED_TILES_PER_SECOND := 3.0
const VEHICLE_SPEED_TILES_PER_SECOND := 2.4
const ROAD_SPEED_MULTIPLIER := 1.3
const WORKER_ACCELERATION := 12.0
const VEHICLE_ACCELERATION := 4.5
const VEHICLE_BRAKING := 7.0
const WORKER_LOOKAHEAD_DISTANCE := 0.45
const VEHICLE_LOOKAHEAD_DISTANCE := 0.90
const WAYPOINT_REACHED_DISTANCE := 0.16
const FINAL_REACHED_DISTANCE := 0.08
const ARRIVAL_SLOW_DISTANCE := 0.80
const AVOIDANCE_NEIGHBOR_DISTANCE := 1.75
const AVOIDANCE_MARGIN := 0.12
const AVOIDANCE_TIME_HORIZON := 0.70
const MAX_ALLOWED_OVERLAP := 0.06
const STUCK_REPATH_SECONDS := 1.25
const WORKER_COLLISION_RADIUS := 0.20
const HAULER_COLLISION_RADIUS := 0.32
const DRILLING_MACHINE_COLLISION_RADIUS := 0.38
const ORDER_IDLE := "idle"
const ORDER_MOVE := "move"
const ORDER_TRAVEL_TO_MINE := "travel_to_mine"
const ORDER_MINING := "mining"
const ORDER_RETURN_TO_MILL := "return_to_mill"
const ORDER_DUMPING_RAW := "dumping_raw"
const ORDER_TRAVEL_TO_LOAD_METAL := "travel_to_load_metal"
const ORDER_WAITING_FOR_METAL := "waiting_for_metal"
const ORDER_LOADING_METAL := "loading_metal"
const ORDER_RETURN_TO_HQ := "return_to_hq"
const ORDER_UNLOADING_METAL := "unloading_metal"
const MINE_SECONDS := 5.5
const DRILLING_DUMP_SECONDS := 2.0
const HAULER_METAL_LOAD_SIZE := 20
const HAULER_LOAD_SECONDS := 2.0
const HAULER_UNLOAD_SECONDS := 2.0
const FACING_SOUTH_EAST := "south_east"
const FACING_NORTH_EAST := "north_east"
const FACING_SOUTH_WEST := "south_west"
const FACING_NORTH_WEST := "north_west"

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


func selected_drilling_machine_count() -> int:
	return _selected_unit_indices_by_role(DRILLING_MACHINE_ROLE).size()


func selected_hauler_count() -> int:
	return _selected_unit_indices_by_role(HAULER_ROLE).size()


func select_unit_by_id(unit_id: int) -> bool:
	if get_unit_by_id(unit_id).is_empty():
		return false
	selected_unit_ids.clear()
	selected_unit_ids[unit_id] = true
	return true


func get_unit_by_id(unit_id: int) -> Dictionary:
	for unit in workers:
		if int(unit["id"]) == unit_id:
			return unit
	return {}


func add_vehicle(vehicle_type: String, tile: Vector2i) -> Dictionary:
	var unit := {
		"id": _next_unit_id,
		"role": vehicle_type,
		"position": Vector2(tile),
		"tile": tile,
		"target_tile": tile,
		"path": [],
		"path_index": 0,
		"path_origin": Vector2(tile),
		"visual_offset": Vector2.ZERO,
		"heading": 0.0,
		"speed": 0.0,
		"velocity": Vector2.ZERO,
		"collision_radius": _collision_radius_for_role(vehicle_type),
		"stuck_time": 0.0,
		"health": _max_health_for_role(vehicle_type),
		"max_health": _max_health_for_role(vehicle_type),
		"cargo": 0,
		"cargo_capacity": _cargo_capacity_for_role(vehicle_type),
		"order": ORDER_IDLE,
		"order_target_tile": tile,
		"mine_timer": 0.0,
		"work_timer": 0.0,
		"facing": FACING_SOUTH_EAST,
	}
	workers.append(unit)
	_next_unit_id += 1
	selected_unit_ids.clear()
	selected_unit_ids[int(unit["id"])] = true
	return unit


func command_selected_drilling_machines_to_mine(
	mountain_tile: Vector2i,
	work_tiles: Array[Vector2i],
	return_tile: Vector2i,
	milling_building_id: int,
	pathfinding_grid: RefCounted
) -> bool:
	var drilling_indices := _selected_unit_indices_by_role(DRILLING_MACHINE_ROLE)
	if drilling_indices.is_empty() or work_tiles.is_empty() or pathfinding_grid == null:
		return false

	var assigned := false
	for assignment_index in drilling_indices.size():
		var unit_index: int = drilling_indices[assignment_index]
		var work_tile: Vector2i = work_tiles[mini(assignment_index, work_tiles.size() - 1)]
		if not _set_unit_path(unit_index, work_tile, pathfinding_grid, ORDER_TRAVEL_TO_MINE):
			continue
		var unit := workers[unit_index]
		unit["order"] = ORDER_TRAVEL_TO_MINE
		unit["order_target_tile"] = mountain_tile
		unit["mine_work_tile"] = work_tile
		unit["return_tile"] = return_tile
		unit["target_building_id"] = milling_building_id
		unit["mine_timer"] = MINE_SECONDS
		unit["work_timer"] = 0.0
		workers[unit_index] = unit
		assigned = true
	if assigned:
		path_revisions += 1
	return assigned


func command_selected_haulers_to_transport_metal(
	source_tile: Vector2i,
	source_building_id: int,
	hq_tile: Vector2i,
	hq_building_id: int,
	pathfinding_grid: RefCounted
) -> bool:
	var hauler_indices := _selected_unit_indices_by_role(HAULER_ROLE)
	if hauler_indices.is_empty() or pathfinding_grid == null:
		return false

	var assigned := false
	for unit_index in hauler_indices:
		if not _set_unit_path(unit_index, source_tile, pathfinding_grid, ORDER_TRAVEL_TO_LOAD_METAL):
			continue
		var unit := workers[unit_index]
		unit["order"] = ORDER_TRAVEL_TO_LOAD_METAL
		unit["order_target_tile"] = source_tile
		unit["source_building_id"] = source_building_id
		unit["target_building_id"] = hq_building_id
		unit["return_tile"] = hq_tile
		unit["requested_cargo"] = HAULER_METAL_LOAD_SIZE
		unit["cargo"] = 0
		unit["work_timer"] = 0.0
		workers[unit_index] = unit
		assigned = true
	if assigned:
		path_revisions += 1
	return assigned


func _set_worker_group_destination(worker_indices: Array[int], target: Vector2i, pathfinding_grid: RefCounted) -> void:
	if pathfinding_grid == null or not pathfinding_grid.is_tile_passable(target):
		return
	if worker_indices.is_empty():
		return

	var available_targets := _formation_targets(target, worker_indices.size(), pathfinding_grid)
	for unit_index in worker_indices:
		if available_targets.is_empty():
			break
		var unit_target := _nearest_formation_target(Vector2(workers[unit_index]["position"]), available_targets)
		available_targets.erase(unit_target)
		if _set_unit_path(unit_index, unit_target, pathfinding_grid, ORDER_MOVE):
			var unit := workers[unit_index]
			unit["order_target_tile"] = unit_target
			workers[unit_index] = unit
	if not worker_indices.is_empty():
		path_revisions += 1


func recalculate_paths(pathfinding_grid: RefCounted) -> void:
	if pathfinding_grid == null:
		return
	for index in workers.size():
		var order: String = workers[index].get("order", ORDER_IDLE)
		if order == ORDER_MINING:
			continue
		var target: Vector2i = workers[index]["target_tile"]
		_set_unit_path(index, target, pathfinding_grid, order)
	path_revisions += 1


func advance(delta: float, pathfinding_grid: RefCounted, colony_state: RefCounted = null) -> bool:
	if delta <= 0.0:
		return false
	var changed := false
	for index in workers.size():
		var worker := workers[index]
		_ensure_motion_fields(worker)
		_update_path_progress(worker)
		workers[index] = worker

	var snapshot: Array[Dictionary] = workers.duplicate(true)
	var desired_velocities: Array[Vector2] = []
	for worker in snapshot:
		desired_velocities.append(_desired_velocity(worker, pathfinding_grid))
	var safe_velocities := _avoidance_velocities(snapshot, desired_velocities)

	for index in workers.size():
		var worker := workers[index]
		var previous_position: Vector2 = worker["position"]
		var displacement := _motion_displacement(worker, safe_velocities[index], delta)
		var radius := float(worker.get("collision_radius", _collision_radius_for_role(worker.get("role", WORKER_ROLE))))
		var next_position := _move_with_static_collision(previous_position, displacement, radius, pathfinding_grid)
		worker["position"] = next_position
		worker["tile"] = _tile_for_position(next_position)
		var actual_velocity := (next_position - previous_position) / delta
		worker["velocity"] = actual_velocity
		if actual_velocity.length_squared() > 0.0001:
			worker["facing"] = _facing_for_delta(actual_velocity, worker.get("facing", FACING_SOUTH_EAST))
		_update_path_progress(worker)
		_update_stuck_state(worker, previous_position, delta)
		workers[index] = worker
		if not next_position.is_equal_approx(previous_position):
			changed = true

	if _resolve_unit_overlaps(pathfinding_grid):
		changed = true
	for index in workers.size():
		var worker := workers[index]
		if float(worker.get("stuck_time", 0.0)) >= STUCK_REPATH_SECONDS and not _path_complete(worker):
			worker["stuck_time"] = 0.0
			workers[index] = worker
			_set_unit_path(index, worker.get("target_tile", worker["tile"]), pathfinding_grid, worker.get("order", ORDER_MOVE))

	for index in workers.size():
		if _advance_drilling_order(index, delta, pathfinding_grid, colony_state):
			changed = true
		if _advance_hauler_order(index, delta, pathfinding_grid, colony_state):
			changed = true
	return changed


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
			"path_origin": Vector2(tile),
			"visual_offset": _visual_offset_for_index(index),
			"heading": 0.0,
			"speed": 0.0,
			"velocity": Vector2.ZERO,
			"collision_radius": WORKER_COLLISION_RADIUS,
			"stuck_time": 0.0,
			"order": ORDER_IDLE,
			"order_target_tile": tile,
			"work_timer": 0.0,
			"facing": FACING_SOUTH_EAST,
		})
		_next_unit_id += 1


func _speed_for_role(role: String) -> float:
	if role == DRILLING_MACHINE_ROLE or role == HAULER_ROLE:
		return VEHICLE_SPEED_TILES_PER_SECOND
	return WORKER_SPEED_TILES_PER_SECOND


func _max_health_for_role(role: String) -> int:
	if role == DRILLING_MACHINE_ROLE:
		return 160
	if role == HAULER_ROLE:
		return 130
	return 100


func _cargo_capacity_for_role(role: String) -> int:
	if role == DRILLING_MACHINE_ROLE:
		return 40
	if role == HAULER_ROLE:
		return 80
	return 0


func _ensure_motion_fields(unit: Dictionary) -> void:
	var role: String = unit.get("role", WORKER_ROLE)
	if not unit.has("heading"):
		unit["heading"] = _heading_for_facing(unit.get("facing", FACING_SOUTH_EAST))
	if not unit.has("speed"):
		unit["speed"] = 0.0
	if not unit.has("velocity"):
		unit["velocity"] = Vector2.ZERO
	if not unit.has("collision_radius"):
		unit["collision_radius"] = _collision_radius_for_role(role)
	if not unit.has("stuck_time"):
		unit["stuck_time"] = 0.0
	if not unit.has("path_origin"):
		unit["path_origin"] = Vector2(unit.get("position", Vector2.ZERO))


func _desired_velocity(unit: Dictionary, pathfinding_grid: RefCounted) -> Vector2:
	var path: Array = unit.get("path", [])
	var path_index := int(unit.get("path_index", 0))
	if path_index >= path.size():
		return Vector2.ZERO
	var position: Vector2 = unit["position"]
	var role: String = unit.get("role", WORKER_ROLE)
	var lookahead_distance := VEHICLE_LOOKAHEAD_DISTANCE if _is_vehicle_role(role) else WORKER_LOOKAHEAD_DISTANCE
	var lookahead := _path_lookahead(position, path, path_index, lookahead_distance)
	var direction := position.direction_to(lookahead)
	if direction.is_zero_approx():
		return Vector2.ZERO

	var max_speed := _speed_for_role(role)
	if pathfinding_grid != null and pathfinding_grid.is_fast_tile(_tile_for_position(position)):
		max_speed *= ROAD_SPEED_MULTIPLIER
	var final_position := Vector2(path[path.size() - 1])
	var arrival_scale := clampf(position.distance_to(final_position) / ARRIVAL_SLOW_DISTANCE, 0.12, 1.0)
	return direction * max_speed * arrival_scale


func _path_lookahead(position: Vector2, path: Array, path_index: int, lookahead_distance: float) -> Vector2:
	var cursor := position
	var remaining := lookahead_distance
	for index in range(path_index, path.size()):
		var point := Vector2(path[index])
		var segment_length := cursor.distance_to(point)
		if segment_length >= remaining and segment_length > 0.001:
			return cursor.lerp(point, remaining / segment_length)
		remaining -= segment_length
		cursor = point
	return Vector2(path[path.size() - 1])


func _avoidance_velocities(snapshot: Array[Dictionary], desired_velocities: Array[Vector2]) -> Array[Vector2]:
	var safe_velocities: Array[Vector2] = []
	for index in snapshot.size():
		var unit := snapshot[index]
		var desired := desired_velocities[index]
		var correction := Vector2.ZERO
		var position: Vector2 = unit["position"]
		var radius := float(unit.get("collision_radius", WORKER_COLLISION_RADIUS))
		for other_index in snapshot.size():
			if other_index == index:
				continue
			var other := snapshot[other_index]
			var offset: Vector2 = Vector2(other["position"]) - position
			var distance := offset.length()
			if distance > AVOIDANCE_NEIGHBOR_DISTANCE:
				continue
			var other_radius := float(other.get("collision_radius", WORKER_COLLISION_RADIUS))
			var comfort_distance := radius + other_radius + AVOIDANCE_MARGIN
			var away := _separation_direction(unit, other, offset)
			if distance < comfort_distance:
				var separation_strength := clampf((comfort_distance - distance) / comfort_distance, 0.0, 1.0)
				correction += away * _speed_for_role(unit.get("role", WORKER_ROLE)) * separation_strength

			var relative_velocity := desired_velocities[other_index] - desired
			if offset.dot(relative_velocity) >= 0.0:
				continue
			var future_offset := offset + relative_velocity * AVOIDANCE_TIME_HORIZON
			if future_offset.length() >= comfort_distance:
				continue
			var travel_direction := desired.normalized()
			if travel_direction.is_zero_approx():
				correction += away * 0.35 * _speed_for_role(unit.get("role", WORKER_ROLE))
				continue
			var side := travel_direction.orthogonal()
			var future_away := -future_offset.normalized()
			if not future_away.is_zero_approx() and side.dot(future_away) < 0.0:
				side = -side
			var prediction_strength := 1.0 - clampf(future_offset.length() / comfort_distance, 0.0, 1.0)
			correction += side * _speed_for_role(unit.get("role", WORKER_ROLE)) * prediction_strength * 0.75

		var max_speed := _speed_for_role(unit.get("role", WORKER_ROLE)) * ROAD_SPEED_MULTIPLIER
		safe_velocities.append((desired + correction).limit_length(max_speed))
	return safe_velocities


func _separation_direction(unit: Dictionary, other: Dictionary, offset: Vector2) -> Vector2:
	if offset.length_squared() > 0.000001:
		return -offset.normalized()
	return Vector2.RIGHT.rotated(float((int(unit["id"]) + int(other["id"])) % 8) * PI * 0.25)


func _motion_displacement(unit: Dictionary, safe_velocity: Vector2, delta: float) -> Vector2:
	if _path_complete(unit):
		unit["speed"] = 0.0
		unit["velocity"] = Vector2.ZERO
		return Vector2.ZERO
	var role: String = unit.get("role", WORKER_ROLE)
	if not _is_vehicle_role(role):
		var current_velocity: Vector2 = unit.get("velocity", Vector2.ZERO)
		var velocity := current_velocity.move_toward(safe_velocity, WORKER_ACCELERATION * delta)
		unit["velocity"] = velocity
		unit["speed"] = velocity.length()
		if not velocity.is_zero_approx():
			unit["heading"] = velocity.angle()
		return velocity * delta

	var heading := float(unit.get("heading", 0.0))
	var desired_heading := heading if safe_velocity.is_zero_approx() else safe_velocity.angle()
	var heading_error := wrapf(desired_heading - heading, -PI, PI)
	var turn_rate := 2.35 if role == DRILLING_MACHINE_ROLE else 2.85
	heading = rotate_toward(heading, desired_heading, turn_rate * delta)
	unit["heading"] = heading
	var alignment := clampf(1.0 - absf(heading_error) / (PI * 0.62), 0.0, 1.0)
	var target_speed := safe_velocity.length() * alignment
	var current_speed := float(unit.get("speed", 0.0))
	var acceleration := VEHICLE_ACCELERATION if target_speed >= current_speed else VEHICLE_BRAKING
	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	unit["speed"] = current_speed
	return Vector2.from_angle(heading) * current_speed * delta


func _move_with_static_collision(position: Vector2, displacement: Vector2, radius: float, pathfinding_grid: RefCounted) -> Vector2:
	if displacement.is_zero_approx() or pathfinding_grid == null:
		return position + displacement
	var step_count := maxi(1, ceili(displacement.length() / 0.08))
	var step := displacement / float(step_count)
	var result := position
	for _step_index in step_count:
		var candidate := result + step
		if pathfinding_grid.is_position_passable(candidate, radius):
			result = candidate
			continue
		var candidate_x := result + Vector2(step.x, 0.0)
		var candidate_y := result + Vector2(0.0, step.y)
		if absf(step.x) >= absf(step.y) and pathfinding_grid.is_position_passable(candidate_x, radius):
			result = candidate_x
		elif pathfinding_grid.is_position_passable(candidate_y, radius):
			result = candidate_y
		elif pathfinding_grid.is_position_passable(candidate_x, radius):
			result = candidate_x
	return result


func _resolve_unit_overlaps(pathfinding_grid: RefCounted) -> bool:
	var changed := false
	for index in workers.size():
		for other_index in range(index + 1, workers.size()):
			var unit := workers[index]
			var other := workers[other_index]
			var position: Vector2 = unit["position"]
			var other_position: Vector2 = other["position"]
			var offset := other_position - position
			var distance := offset.length()
			var minimum_distance := float(unit.get("collision_radius", WORKER_COLLISION_RADIUS)) + float(other.get("collision_radius", WORKER_COLLISION_RADIUS)) - MAX_ALLOWED_OVERLAP
			if distance >= minimum_distance:
				continue
			var normal := offset / distance if distance > 0.0001 else _separation_direction(other, unit, Vector2.ZERO)
			var correction := normal * (minimum_distance - distance)
			var unit_candidate := position - correction * 0.5
			var other_candidate := other_position + correction * 0.5
			var unit_can_move: bool = pathfinding_grid == null or pathfinding_grid.is_position_passable(unit_candidate, float(unit["collision_radius"]))
			var other_can_move: bool = pathfinding_grid == null or pathfinding_grid.is_position_passable(other_candidate, float(other["collision_radius"]))
			if unit_can_move and other_can_move:
				unit["position"] = unit_candidate
				other["position"] = other_candidate
			elif unit_can_move:
				unit["position"] = position - correction
			elif other_can_move:
				other["position"] = other_position + correction
			else:
				continue
			unit["tile"] = _tile_for_position(unit["position"])
			other["tile"] = _tile_for_position(other["position"])
			workers[index] = unit
			workers[other_index] = other
			changed = true
	return changed


func _update_path_progress(unit: Dictionary) -> void:
	var path: Array = unit.get("path", [])
	var path_index := int(unit.get("path_index", 0))
	var position: Vector2 = unit["position"]
	while path_index < path.size():
		var reached_distance := FINAL_REACHED_DISTANCE if path_index == path.size() - 1 else WAYPOINT_REACHED_DISTANCE
		var point := Vector2(path[path_index])
		var previous_point := Vector2(unit.get("path_origin", position)) if path_index == 0 else Vector2(path[path_index - 1])
		var incoming := point - previous_point
		var passed_waypoint := not incoming.is_zero_approx() and (position - point).dot(incoming) >= 0.0
		if position.distance_to(point) > reached_distance and not passed_waypoint:
			break
		if path_index == path.size() - 1:
			unit["position"] = point
			unit["tile"] = _tile_for_position(unit["position"])
		path_index += 1
	unit["path_index"] = path_index


func _update_stuck_state(unit: Dictionary, previous_position: Vector2, delta: float) -> void:
	if _path_complete(unit) or Vector2(unit["position"]).distance_to(previous_position) > 0.004:
		unit["stuck_time"] = 0.0
	else:
		unit["stuck_time"] = float(unit.get("stuck_time", 0.0)) + delta


func _collision_radius_for_role(role: String) -> float:
	if role == DRILLING_MACHINE_ROLE:
		return DRILLING_MACHINE_COLLISION_RADIUS
	if role == HAULER_ROLE:
		return HAULER_COLLISION_RADIUS
	return WORKER_COLLISION_RADIUS


func _is_vehicle_role(role: String) -> bool:
	return role == DRILLING_MACHINE_ROLE or role == HAULER_ROLE


func _tile_for_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x + 0.5), floori(position.y + 0.5))


func _set_unit_path(index: int, target: Vector2i, pathfinding_grid: RefCounted, order := ORDER_MOVE) -> bool:
	var worker := workers[index]
	var start_tile: Vector2i = worker["tile"]
	var raw_path: Array[Vector2i] = pathfinding_grid.find_path(start_tile, target)
	if raw_path.size() > 1:
		raw_path.remove_at(0)
	elif raw_path.size() == 1:
		raw_path.clear()
	elif start_tile != target:
		return false
	var radius := float(worker.get("collision_radius", _collision_radius_for_role(worker.get("role", WORKER_ROLE))))
	var path: Array[Vector2] = pathfinding_grid.smooth_path(Vector2(worker["position"]), raw_path, radius)
	worker["target_tile"] = target if not path.is_empty() or start_tile == target else start_tile
	worker["path"] = path
	worker["path_index"] = 0
	worker["path_origin"] = Vector2(worker["position"])
	worker["stuck_time"] = 0.0
	worker["order"] = order if start_tile != target or order != ORDER_MOVE else ORDER_IDLE
	if not path.is_empty():
		worker["facing"] = _facing_for_delta(path[0] - Vector2(worker["position"]), worker.get("facing", FACING_SOUTH_EAST))
	workers[index] = worker
	return true


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


func _selected_unit_indices_by_role(role: String) -> Array[int]:
	var indices: Array[int] = []
	for index in workers.size():
		if selected_unit_ids.has(int(workers[index]["id"])) and workers[index].get("role", WORKER_ROLE) == role:
			indices.append(index)
	return indices


func _advance_drilling_order(index: int, delta: float, pathfinding_grid: RefCounted, colony_state: RefCounted) -> bool:
	var unit := workers[index]
	if unit.get("role", WORKER_ROLE) != DRILLING_MACHINE_ROLE:
		return false

	var order: String = unit.get("order", ORDER_IDLE)
	if order == ORDER_TRAVEL_TO_MINE and _path_complete(unit):
		unit["order"] = ORDER_MINING
		unit["mine_timer"] = MINE_SECONDS
		workers[index] = unit
		return true

	if order == ORDER_MINING:
		var mine_timer := maxf(0.0, float(unit.get("mine_timer", MINE_SECONDS)) - delta)
		unit["mine_timer"] = mine_timer
		if mine_timer > 0.0:
			workers[index] = unit
			return true

		unit["cargo"] = int(unit.get("cargo_capacity", 0))
		workers[index] = unit
		if _set_unit_path(index, unit.get("return_tile", unit.get("tile", Vector2i.ZERO)), pathfinding_grid, ORDER_RETURN_TO_MILL):
			var returning_unit := workers[index]
			returning_unit["order"] = ORDER_RETURN_TO_MILL
			workers[index] = returning_unit
		return true

	if order == ORDER_RETURN_TO_MILL and _path_complete(unit):
		unit["order"] = ORDER_DUMPING_RAW
		unit["work_timer"] = DRILLING_DUMP_SECONDS
		workers[index] = unit
		return true

	if order == ORDER_DUMPING_RAW:
		var dump_timer := maxf(0.0, float(unit.get("work_timer", DRILLING_DUMP_SECONDS)) - delta)
		unit["work_timer"] = dump_timer
		if dump_timer > 0.0:
			workers[index] = unit
			return true

		var cargo_amount := int(unit.get("cargo", 0))
		if colony_state != null and colony_state.has_method("deposit_raw_to_building"):
			colony_state.deposit_raw_to_building(int(unit.get("target_building_id", -1)), cargo_amount)
		unit["cargo"] = 0
		workers[index] = unit
		if _set_unit_path(index, unit.get("mine_work_tile", unit.get("tile", Vector2i.ZERO)), pathfinding_grid, ORDER_TRAVEL_TO_MINE):
			var mining_unit := workers[index]
			mining_unit["order"] = ORDER_TRAVEL_TO_MINE
			mining_unit["mine_timer"] = MINE_SECONDS
			mining_unit["work_timer"] = 0.0
			workers[index] = mining_unit
		else:
			unit = workers[index]
			unit["order"] = ORDER_IDLE
			unit["mine_timer"] = 0.0
			unit["work_timer"] = 0.0
			workers[index] = unit
		return true

	return false


func _advance_hauler_order(index: int, delta: float, pathfinding_grid: RefCounted, colony_state: RefCounted) -> bool:
	var unit := workers[index]
	if unit.get("role", WORKER_ROLE) != HAULER_ROLE:
		return false

	var order: String = unit.get("order", ORDER_IDLE)
	if order == ORDER_TRAVEL_TO_LOAD_METAL and _path_complete(unit):
		if _source_has_requested_metal(unit, colony_state):
			unit["order"] = ORDER_LOADING_METAL
			unit["work_timer"] = HAULER_LOAD_SECONDS
		else:
			unit["order"] = ORDER_WAITING_FOR_METAL
			unit["work_timer"] = 0.0
		workers[index] = unit
		return true

	if order == ORDER_WAITING_FOR_METAL:
		if not _source_has_requested_metal(unit, colony_state):
			return false
		unit["order"] = ORDER_LOADING_METAL
		unit["work_timer"] = HAULER_LOAD_SECONDS
		workers[index] = unit
		return true

	if order == ORDER_LOADING_METAL:
		var load_timer := maxf(0.0, float(unit.get("work_timer", HAULER_LOAD_SECONDS)) - delta)
		unit["work_timer"] = load_timer
		if load_timer > 0.0:
			workers[index] = unit
			return true

		var loaded_amount := 0
		if colony_state != null and colony_state.has_method("load_metal_from_building"):
			loaded_amount = colony_state.load_metal_from_building(
				int(unit.get("source_building_id", -1)),
				int(unit.get("requested_cargo", HAULER_METAL_LOAD_SIZE))
			)
		if loaded_amount <= 0:
			unit["cargo"] = 0
			unit["order"] = ORDER_WAITING_FOR_METAL
			unit["work_timer"] = 0.0
			workers[index] = unit
			return true

		unit["cargo"] = loaded_amount
		unit["work_timer"] = 0.0
		workers[index] = unit
		if _set_unit_path(index, unit.get("return_tile", unit.get("tile", Vector2i.ZERO)), pathfinding_grid, ORDER_RETURN_TO_HQ):
			var returning_unit := workers[index]
			returning_unit["order"] = ORDER_RETURN_TO_HQ
			workers[index] = returning_unit
		return true

	if order == ORDER_RETURN_TO_HQ and _path_complete(unit):
		unit["order"] = ORDER_UNLOADING_METAL
		unit["work_timer"] = HAULER_UNLOAD_SECONDS
		workers[index] = unit
		return true

	if order == ORDER_UNLOADING_METAL:
		var unload_timer := maxf(0.0, float(unit.get("work_timer", HAULER_UNLOAD_SECONDS)) - delta)
		unit["work_timer"] = unload_timer
		if unload_timer > 0.0:
			workers[index] = unit
			return true

		var cargo_amount := int(unit.get("cargo", 0))
		if colony_state != null and colony_state.has_method("deliver_metal_to_building"):
			colony_state.deliver_metal_to_building(int(unit.get("target_building_id", -1)), cargo_amount)
		unit["cargo"] = 0
		unit["work_timer"] = 0.0
		workers[index] = unit
		if _set_unit_path(index, unit.get("order_target_tile", unit.get("tile", Vector2i.ZERO)), pathfinding_grid, ORDER_TRAVEL_TO_LOAD_METAL):
			var returning_unit := workers[index]
			returning_unit["order"] = ORDER_TRAVEL_TO_LOAD_METAL
			workers[index] = returning_unit
		else:
			unit = workers[index]
			unit["order"] = ORDER_IDLE
			workers[index] = unit
		return true

	return false


func _source_has_requested_metal(unit: Dictionary, colony_state: RefCounted) -> bool:
	if colony_state == null or not colony_state.has_method("get_building_stored_metal"):
		return false
	var stored_metal: int = colony_state.get_building_stored_metal(int(unit.get("source_building_id", -1)))
	return stored_metal >= int(unit.get("requested_cargo", HAULER_METAL_LOAD_SIZE))


func _path_complete(unit: Dictionary) -> bool:
	var path: Array = unit.get("path", [])
	return int(unit.get("path_index", 0)) >= path.size()


func _facing_for_delta(delta: Vector2, fallback: String) -> String:
	if absf(delta.x) >= absf(delta.y) and absf(delta.x) > 0.001:
		return FACING_SOUTH_EAST if delta.x > 0.0 else FACING_NORTH_WEST
	if absf(delta.y) > 0.001:
		return FACING_SOUTH_WEST if delta.y > 0.0 else FACING_NORTH_EAST
	return fallback


func _heading_for_facing(facing: String) -> float:
	match facing:
		FACING_SOUTH_EAST:
			return 0.0
		FACING_SOUTH_WEST:
			return PI * 0.5
		FACING_NORTH_WEST:
			return PI
		FACING_NORTH_EAST:
			return -PI * 0.5
		_:
			return 0.0


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


func _nearest_formation_target(position: Vector2, targets: Array[Vector2i]) -> Vector2i:
	var nearest := targets[0]
	var nearest_distance := position.distance_squared_to(Vector2(nearest))
	for target in targets:
		var distance := position.distance_squared_to(Vector2(target))
		if distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	return nearest


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
