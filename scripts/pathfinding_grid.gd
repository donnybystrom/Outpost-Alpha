extends RefCounted

const TERRAIN_FOREST := 1
const TERRAIN_MOUNTAIN := 5
const ROAD_COST := 0.70
const DEFAULT_COST := 1.0
const PATH_SAMPLE_SPACING := 0.10
const SMOOTHING_COST_TOLERANCE := 1.03
const SMOOTHING_ROAD_FRACTION_TOLERANCE := 0.15

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

var map_data: RefCounted
var colony_state: RefCounted


func configure(next_map_data: RefCounted, next_colony_state: RefCounted) -> void:
	map_data = next_map_data
	colony_state = next_colony_state


func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if map_data == null or not map_data.is_inside(start) or not is_tile_passable(goal):
		return empty_path
	if start == goal:
		return [start]

	var open_set: Array[Vector2i] = [start]
	var came_from := {}
	var g_score := {start: 0.0}
	var f_score := {start: _heuristic(start, goal)}
	var closed := {}

	while not open_set.is_empty():
		var current := _lowest_score_tile(open_set, f_score)
		if current == goal:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)
		closed[current] = true

		for neighbor in _passable_neighbors(current):
			if closed.has(neighbor):
				continue
			var tentative_g_score: float = float(g_score[current]) + movement_cost(neighbor)
			if not g_score.has(neighbor) or tentative_g_score < float(g_score[neighbor]):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g_score
				f_score[neighbor] = tentative_g_score + _heuristic(neighbor, goal)
				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return empty_path


func is_tile_passable(tile: Vector2i) -> bool:
	if map_data == null or not map_data.is_inside(tile):
		return false
	var terrain_id: int = map_data.get_terrain(tile)
	if terrain_id == TERRAIN_FOREST or terrain_id == TERRAIN_MOUNTAIN:
		return false
	if colony_state != null and colony_state.has_method("is_occupied") and colony_state.is_occupied(tile):
		return false
	return true


func movement_cost(tile: Vector2i) -> float:
	if map_data != null and map_data.has_road(tile):
		return ROAD_COST
	return DEFAULT_COST


func is_fast_tile(tile: Vector2i) -> bool:
	return map_data != null and map_data.has_road(tile)


func smooth_path(start_position: Vector2, raw_path: Array[Vector2i], agent_radius: float) -> Array[Vector2]:
	var smoothed: Array[Vector2] = []
	if raw_path.is_empty():
		return smoothed

	var points: Array[Vector2] = [start_position]
	for tile in raw_path:
		points.append(Vector2(tile))

	var source_index := 0
	while source_index < points.size() - 1:
		var destination_index := points.size() - 1
		while destination_index > source_index + 1:
			if _can_smooth_between(points, source_index, destination_index, agent_radius):
				break
			destination_index -= 1
		smoothed.append(points[destination_index])
		source_index = destination_index
	return smoothed


func has_clear_path_segment(start_position: Vector2, end_position: Vector2, agent_radius: float) -> bool:
	var distance := start_position.distance_to(end_position)
	var sample_count := maxi(1, ceili(distance / PATH_SAMPLE_SPACING))
	for sample_index in range(sample_count + 1):
		var weight := float(sample_index) / float(sample_count)
		if not is_position_passable(start_position.lerp(end_position, weight), agent_radius):
			return false
	return true


func is_position_passable(position: Vector2, agent_radius: float = 0.0) -> bool:
	var center_tile := _tile_for_position(position)
	if agent_radius <= 0.001:
		return is_tile_passable(center_tile)

	var search_radius := ceili(agent_radius + 0.5)
	for y in range(center_tile.y - search_radius, center_tile.y + search_radius + 1):
		for x in range(center_tile.x - search_radius, center_tile.x + search_radius + 1):
			var tile := Vector2i(x, y)
			if is_tile_passable(tile):
				continue
			var closest_point := Vector2(
				clampf(position.x, float(x) - 0.5, float(x) + 0.5),
				clampf(position.y, float(y) - 0.5, float(y) + 0.5)
			)
			if position.distance_squared_to(closest_point) < agent_radius * agent_radius:
				return false
	return true


func _passable_neighbors(tile: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for direction in CARDINAL_DIRECTIONS:
		var neighbor := tile + direction
		if is_tile_passable(neighbor):
			neighbors.append(neighbor)
	return neighbors


func _lowest_score_tile(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best := open_set[0]
	var best_score := float(f_score.get(best, INF))
	for tile in open_set:
		var score := float(f_score.get(tile, INF))
		if score < best_score:
			best = tile
			best_score = score
	return best


func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y)) * ROAD_COST


func _can_smooth_between(points: Array[Vector2], source_index: int, destination_index: int, agent_radius: float) -> bool:
	var start_position := points[source_index]
	var end_position := points[destination_index]
	if not has_clear_path_segment(start_position, end_position, agent_radius):
		return false

	var original_cost := 0.0
	var original_distance := 0.0
	var original_road_distance := 0.0
	for index in range(source_index + 1, destination_index + 1):
		var segment_distance := points[index - 1].distance_to(points[index])
		original_distance += segment_distance
		var tile := _tile_for_position(points[index])
		original_cost += segment_distance * movement_cost(tile)
		if is_fast_tile(tile):
			original_road_distance += segment_distance
	if original_distance > 0.001:
		var original_road_fraction := original_road_distance / original_distance
		if _segment_road_fraction(start_position, end_position) + SMOOTHING_ROAD_FRACTION_TOLERANCE < original_road_fraction:
			return false
	var direct_cost := _segment_movement_cost(start_position, end_position)
	return direct_cost <= original_cost * SMOOTHING_COST_TOLERANCE


func _segment_movement_cost(start_position: Vector2, end_position: Vector2) -> float:
	var distance := start_position.distance_to(end_position)
	if distance <= 0.001:
		return 0.0
	var sample_count := maxi(1, ceili(distance / 0.25))
	var cost := 0.0
	for sample_index in range(sample_count):
		var weight := (float(sample_index) + 0.5) / float(sample_count)
		cost += movement_cost(_tile_for_position(start_position.lerp(end_position, weight)))
	return distance * cost / float(sample_count)


func _segment_road_fraction(start_position: Vector2, end_position: Vector2) -> float:
	var distance := start_position.distance_to(end_position)
	if distance <= 0.001:
		return 1.0 if is_fast_tile(_tile_for_position(start_position)) else 0.0
	var sample_count := maxi(1, ceili(distance / 0.25))
	var road_samples := 0
	for sample_index in range(sample_count):
		var weight := (float(sample_index) + 0.5) / float(sample_count)
		if is_fast_tile(_tile_for_position(start_position.lerp(end_position, weight))):
			road_samples += 1
	return float(road_samples) / float(sample_count)


func _tile_for_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x + 0.5), floori(position.y + 0.5))
