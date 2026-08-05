extends SceneTree

const MapData := preload("res://scripts/map_data.gd")
const AutoTile := preload("res://scripts/auto_tile.gd")


func _initialize() -> void:
	var map_data := MapData.new(Vector2i(8, 8))

	var center := Vector2i(3, 3)
	map_data.set_road(center)
	map_data.set_road(center + Vector2i(0, -1))
	map_data.set_road(center + Vector2i(1, 0))
	map_data.set_road(center + Vector2i(0, 1))
	map_data.set_road(center + Vector2i(-1, 0))
	_assert_mask(map_data, center, 15, "four-way road")

	var vertical := Vector2i(6, 3)
	map_data.set_road(vertical)
	map_data.set_road(vertical + Vector2i(0, -1))
	map_data.set_road(vertical + Vector2i(0, 1))
	_assert_mask(map_data, vertical, 5, "north-south road")

	var corner := Vector2i(1, 1)
	map_data.set_road(corner)
	map_data.set_road(corner + Vector2i(1, 0))
	map_data.set_road(corner + Vector2i(0, 1))
	_assert_mask(map_data, corner, 6, "east-south road corner")

	var tee := Vector2i(1, 5)
	map_data.set_road(tee)
	map_data.set_road(tee + Vector2i(0, -1))
	map_data.set_road(tee + Vector2i(1, 0))
	map_data.set_road(tee + Vector2i(-1, 0))
	_assert_mask(map_data, tee, 11, "north-east-west road tee")

	var mountain := Vector2i(4, 5)
	map_data.set_terrain(mountain, 5)
	map_data.set_terrain(mountain + Vector2i(0, -1), 5)
	map_data.set_terrain(mountain + Vector2i(-1, 0), 5)
	map_data.set_terrain(mountain + Vector2i(1, 0), 1)
	_assert_same_terrain_mask(map_data, mountain, 9, "mountain massif north-west connection")

	quit(0)


func _assert_mask(map_data: RefCounted, tile: Vector2i, expected: int, label: String) -> void:
	var actual := AutoTile.road_mask(map_data, tile)
	if actual != expected:
		push_error("%s expected mask %s but got %s" % [label, expected, actual])
		quit(1)


func _assert_same_terrain_mask(map_data: RefCounted, tile: Vector2i, expected: int, label: String) -> void:
	var actual := AutoTile.same_terrain_mask(map_data, tile)
	if actual != expected:
		push_error("%s expected mask %s but got %s" % [label, expected, actual])
		quit(1)
