extends SceneTree

const ProceduralMapGenerator := preload("res://scripts/procedural_map_generator.gd")


func _initialize() -> void:
	var map_data := ProceduralMapGenerator.generate(Vector2i(96, 96), 123456)
	var custom_map_data := ProceduralMapGenerator.generate(Vector2i(96, 96), 123456, 12, 14, 5, 2, 80)
	var circular_clearing := ProceduralMapGenerator.generate(Vector2i(96, 96), 24680, 18, 30, 3, 1, 0)
	var noisy_clearing := ProceduralMapGenerator.generate(Vector2i(96, 96), 24680, 18, 30, 3, 1, 100)
	var narrow_paths := ProceduralMapGenerator.generate(Vector2i(96, 96), 98765, 20, 20, 3, 1, 45)
	var wide_paths := ProceduralMapGenerator.generate(Vector2i(96, 96), 98765, 20, 20, 3, 10, 45)

	if map_data.seed != 123456:
		push_error("Fixed seed was not preserved on generated map data.")
		quit(1)
		return

	if map_data.build_radius != 25:
		push_error("Guaranteed build radius should be default min radius: %s" % map_data.build_radius)
		quit(1)
		return

	if map_data.path_endpoints.size() != 3:
		push_error("Expected exactly three forest exit paths.")
		quit(1)
		return

	if custom_map_data.build_radius < 12 or custom_map_data.build_radius > 14:
		push_error("Custom build radius range was not respected: %s" % custom_map_data.build_radius)
		quit(1)
		return

	if custom_map_data.path_endpoints.size() != 5:
		push_error("Custom path count was not respected: %s" % custom_map_data.path_endpoints.size())
		quit(1)
		return

	if custom_map_data.path_width != 2:
		push_error("Custom path width was not respected: %s" % custom_map_data.path_width)
		quit(1)
		return

	if custom_map_data.clearing_noise != 80:
		push_error("Custom clearing noise was not respected: %s" % custom_map_data.clearing_noise)
		quit(1)
		return

	if _count_clear_tiles(noisy_clearing) <= _count_clear_tiles(circular_clearing):
		push_error("Noisy clearing did not carve more outer build area than circular clearing.")
		quit(1)
		return

	if _count_clear_tiles(wide_paths) <= _count_clear_tiles(narrow_paths):
		push_error("Wide paths did not carve more clear terrain than narrow paths.")
		quit(1)
		return

	for endpoint in map_data.path_endpoints:
		if not map_data.is_inside(endpoint):
			push_error("Path endpoint is outside map bounds: %s" % endpoint)
			quit(1)
			return
		if map_data.get_terrain(endpoint) != 0:
			push_error("Path endpoint was not carved clear: %s" % endpoint)
			quit(1)
			return

	_assert_inner_build_area_is_clear(map_data)
	_assert_outer_forest_exists(map_data)
	_assert_outer_mountains_exist(map_data)
	quit(0)


func _assert_inner_build_area_is_clear(map_data: RefCounted) -> void:
	var safe_radius: int = maxi(map_data.build_radius - 5, 1)
	for y in range(map_data.start_tile.y - safe_radius, map_data.start_tile.y + safe_radius + 1):
		for x in range(map_data.start_tile.x - safe_radius, map_data.start_tile.x + safe_radius + 1):
			var tile := Vector2i(x, y)
			if map_data.is_inside(tile) and Vector2(tile - map_data.start_tile).length() <= float(safe_radius):
				if map_data.get_terrain(tile) != 0:
					push_error("Inner build area contains blocked terrain at %s." % tile)
					quit(1)
					return


func _assert_outer_forest_exists(map_data: RefCounted) -> void:
	var forest_count := 0
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var distance: float = Vector2(tile - map_data.start_tile).length()
			if distance > float(map_data.build_radius + 6):
				var terrain_id: int = map_data.get_terrain(tile)
				if terrain_id == 1 or terrain_id == 2:
					forest_count += 1

	if forest_count < 800:
		push_error("Generated map does not contain enough outer forest: %s tiles." % forest_count)
		quit(1)


func _assert_outer_mountains_exist(map_data: RefCounted) -> void:
	var forest_count := 0
	var mountain_count := 0
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var distance: float = Vector2(tile - map_data.start_tile).length()
			if distance > float(map_data.build_radius + 6):
				var terrain_id: int = map_data.get_terrain(tile)
				if terrain_id == 1 or terrain_id == 2:
					forest_count += 1
				elif terrain_id == 5:
					mountain_count += 1

	if mountain_count < 250:
		push_error("Generated map does not contain enough outer mountain massif: %s tiles." % mountain_count)
		quit(1)
	if mountain_count < int(float(forest_count) * 0.25) or mountain_count > int(float(forest_count) * 0.85):
		push_error("Mountain massifs should be roughly half as common as forest. Forest=%s mountain=%s." % [forest_count, mountain_count])
		quit(1)


func _count_clear_tiles(map_data: RefCounted) -> int:
	var clear_count := 0
	for y in map_data.size.y:
		for x in map_data.size.x:
			if map_data.get_terrain(Vector2i(x, y)) == 0:
				clear_count += 1
	return clear_count
