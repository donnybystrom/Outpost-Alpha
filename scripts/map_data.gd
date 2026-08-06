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


func _init(map_size := Vector2i.ZERO) -> void:
	if map_size != Vector2i.ZERO:
		resize(map_size)


func resize(map_size: Vector2i) -> void:
	size = map_size
	terrain.clear()
	roads.clear()
	for y in size.y:
		var terrain_row: Array[int] = []
		var road_row: Array[bool] = []
		for x in size.x:
			terrain_row.append(0)
			road_row.append(false)
		terrain.append(terrain_row)
		roads.append(road_row)


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
