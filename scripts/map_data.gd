extends RefCounted

var size := Vector2i.ZERO
var seed := 0
var start_tile := Vector2i.ZERO
var build_radius := 0
var clearing_noise := 45
var path_width := 8
var mountain_percent := 67
var path_endpoints: Array[Vector2i] = []
var terrain: Array[Array] = []
var roads: Array[Array] = []
var moisture: Array[Array] = []
var radiation: Array[Array] = []
var mineral_content: Array[Array] = []
var mountain_edge_weight: Array[Array] = []
var dustiness: Array[Array] = []
var surface_age: Array[Array] = []
var rockiness: Array[Array] = []


func _init(map_size := Vector2i.ZERO) -> void:
	if map_size != Vector2i.ZERO:
		resize(map_size)


func resize(map_size: Vector2i) -> void:
	size = map_size
	terrain.clear()
	roads.clear()
	moisture.clear()
	radiation.clear()
	mineral_content.clear()
	mountain_edge_weight.clear()
	dustiness.clear()
	surface_age.clear()
	rockiness.clear()
	for y in size.y:
		var terrain_row: Array[int] = []
		var road_row: Array[bool] = []
		var moisture_row: Array[float] = []
		var radiation_row: Array[float] = []
		var mineral_row: Array[float] = []
		var mountain_edge_row: Array[float] = []
		var dustiness_row: Array[float] = []
		var surface_age_row: Array[float] = []
		var rockiness_row: Array[float] = []
		for x in size.x:
			terrain_row.append(0)
			road_row.append(false)
			moisture_row.append(0.0)
			radiation_row.append(0.0)
			mineral_row.append(0.0)
			mountain_edge_row.append(0.0)
			dustiness_row.append(0.0)
			surface_age_row.append(0.0)
			rockiness_row.append(0.0)
		terrain.append(terrain_row)
		roads.append(road_row)
		moisture.append(moisture_row)
		radiation.append(radiation_row)
		mineral_content.append(mineral_row)
		mountain_edge_weight.append(mountain_edge_row)
		dustiness.append(dustiness_row)
		surface_age.append(surface_age_row)
		rockiness.append(rockiness_row)


func is_inside(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y


func set_terrain(tile: Vector2i, terrain_id: int) -> void:
	if is_inside(tile):
		terrain[tile.y][tile.x] = terrain_id


func get_terrain(tile: Vector2i) -> int:
	if not is_inside(tile):
		return 0
	return terrain[tile.y][tile.x]


func set_road(tile: Vector2i, enabled := true) -> void:
	if is_inside(tile):
		roads[tile.y][tile.x] = enabled


func has_road(tile: Vector2i) -> bool:
	return is_inside(tile) and roads[tile.y][tile.x]


func set_surface_parameters(tile: Vector2i, next_moisture: float, next_radiation: float, next_mineral_content: float) -> void:
	if not is_inside(tile):
		return
	moisture[tile.y][tile.x] = clampf(next_moisture, 0.0, 1.0)
	radiation[tile.y][tile.x] = clampf(next_radiation, 0.0, 1.0)
	mineral_content[tile.y][tile.x] = clampf(next_mineral_content, 0.0, 1.0)


func get_moisture(tile: Vector2i) -> float:
	return float(moisture[tile.y][tile.x]) if is_inside(tile) else 0.0


func get_radiation(tile: Vector2i) -> float:
	return float(radiation[tile.y][tile.x]) if is_inside(tile) else 0.0


func get_mineral_content(tile: Vector2i) -> float:
	return float(mineral_content[tile.y][tile.x]) if is_inside(tile) else 0.0


func set_geology_parameters(tile: Vector2i, next_dustiness: float, next_surface_age: float, next_rockiness: float) -> void:
	if not is_inside(tile):
		return
	dustiness[tile.y][tile.x] = clampf(next_dustiness, 0.0, 1.0)
	surface_age[tile.y][tile.x] = clampf(next_surface_age, 0.0, 1.0)
	rockiness[tile.y][tile.x] = clampf(next_rockiness, 0.0, 1.0)


func set_mountain_edge_weight(tile: Vector2i, weight: float) -> void:
	if is_inside(tile):
		mountain_edge_weight[tile.y][tile.x] = clampf(weight, 0.0, 1.0)


func get_mountain_edge_weight(tile: Vector2i) -> float:
	return float(mountain_edge_weight[tile.y][tile.x]) if is_inside(tile) else 0.0


func get_dustiness(tile: Vector2i) -> float:
	return float(dustiness[tile.y][tile.x]) if is_inside(tile) else 0.0


func get_surface_age(tile: Vector2i) -> float:
	return float(surface_age[tile.y][tile.x]) if is_inside(tile) else 0.0


func get_rockiness(tile: Vector2i) -> float:
	return float(rockiness[tile.y][tile.x]) if is_inside(tile) else 0.0
