extends RefCounted

const TERRAIN_FOREST := 1
const TERRAIN_MOUNTAIN := 5
const ROAD_COST := 0.70
const DEFAULT_COST := 1.0

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
