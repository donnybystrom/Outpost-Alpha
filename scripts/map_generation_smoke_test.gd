extends SceneTree

const ProceduralMapGenerator := preload("res://scripts/procedural_map_generator.gd")
const MapData := preload("res://scripts/map_data.gd")


func _initialize() -> void:
	_assert_mountain_mask_cleanup()
	var map_data := ProceduralMapGenerator.generate(Vector2i(96, 96), 123456)
	var custom_map_data := ProceduralMapGenerator.generate(Vector2i(96, 96), 123456, 12, 14, 5, 2, 80)
	var circular_clearing := ProceduralMapGenerator.generate(Vector2i(96, 96), 24680, 18, 30, 3, 1, 0)
	var noisy_clearing := ProceduralMapGenerator.generate(Vector2i(96, 96), 24680, 18, 30, 3, 1, 100)
	var narrow_paths := ProceduralMapGenerator.generate(Vector2i(96, 96), 98765, 20, 20, 3, 1, 45)
	var wide_paths := ProceduralMapGenerator.generate(Vector2i(96, 96), 98765, 20, 20, 3, 10, 45)
	var no_mountains := ProceduralMapGenerator.generate(Vector2i(96, 96), 123456, 25, 40, 3, 8, 45, 0)
	var all_mountains := ProceduralMapGenerator.generate(Vector2i(96, 96), 123456, 25, 40, 3, 8, 45, 100)

	if map_data.seed != 123456:
		push_error("Fixed seed was not preserved on generated map data.")
		quit(1)
		return

	_assert_surface_fields(map_data)

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

	if map_data.mountain_percent != ProceduralMapGenerator.DEFAULT_MOUNTAIN_PERCENT:
		push_error("Default generation should use the increased mountain wilderness percentage.")
		quit(1)
		return

	if _count_terrain(no_mountains, 5) != 0:
		push_error("Mountain wilderness 0 should generate no mountain tiles.")
		quit(1)
		return

	if _count_terrain(all_mountains, 1) != 0 or _count_terrain(all_mountains, 2) != 0:
		push_error("Mountain wilderness 100 should replace every forest and crystal wilderness tile.")
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


func _assert_mountain_mask_cleanup() -> void:
	var notched_map := MapData.new(Vector2i(7, 7))
	notched_map.start_tile = Vector2i(1, 1)
	for y in notched_map.size.y:
		for x in notched_map.size.x:
			notched_map.set_terrain(Vector2i(x, y), 5)
	for tile in [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2)]:
		notched_map.set_terrain(tile, 0)
	ProceduralMapGenerator._close_mountain_mask(notched_map)
	for tile in [Vector2i(3, 1), Vector2i(3, 2)]:
		if notched_map.get_terrain(tile) != 5:
			push_error("Mountain mask closing should remove narrow notches in a massif.")
			quit(1)
			return

	var pocket_map := MapData.new(Vector2i(10, 10))
	pocket_map.start_tile = Vector2i(1, 1)
	for y in pocket_map.size.y:
		for x in pocket_map.size.x:
			pocket_map.set_terrain(Vector2i(x, y), 5)
	for y in range(3, 7):
		for x in range(3, 7):
			pocket_map.set_terrain(Vector2i(x, y), 1)
	ProceduralMapGenerator._fill_small_mountain_holes(pocket_map)
	for y in range(3, 7):
		for x in range(3, 7):
			if pocket_map.get_terrain(Vector2i(x, y)) != 5:
				push_error("Mountain mask cleanup should fill small enclosed wilderness pockets.")
				quit(1)
				return


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
	if mountain_count < int(float(forest_count) * 1.4) or mountain_count > int(float(forest_count) * 3.0):
		push_error("Default mountain massifs should be roughly four times more common relative to forest than before. Forest=%s mountain=%s." % [forest_count, mountain_count])
		quit(1)


func _count_clear_tiles(map_data: RefCounted) -> int:
	var clear_count := 0
	for y in map_data.size.y:
		for x in map_data.size.x:
			if map_data.get_terrain(Vector2i(x, y)) == 0:
				clear_count += 1
	return clear_count


func _count_terrain(map_data: RefCounted, terrain_id: int) -> int:
	var count := 0
	for y in map_data.size.y:
		for x in map_data.size.x:
			if map_data.get_terrain(Vector2i(x, y)) == terrain_id:
				count += 1
	return count


func _assert_surface_fields(map_data: RefCounted) -> void:
	var distinct_samples := {}
	var distinct_geology_samples := {}
	var found_mountain_transition := false
	for y in range(0, map_data.size.y, 8):
		for x in range(0, map_data.size.x, 8):
			var tile := Vector2i(x, y)
			var values := Vector3(
				map_data.get_moisture(tile),
				map_data.get_radiation(tile),
				map_data.get_mineral_content(tile)
			)
			if values.x < 0.0 or values.x > 1.0 or values.y < 0.0 or values.y > 1.0 or values.z < 0.0 or values.z > 1.0:
				push_error("Ecology surface parameters should remain normalized: %s" % values)
				quit(1)
				return
			distinct_samples[Vector3i(roundi(values.x * 16.0), roundi(values.y * 16.0), roundi(values.z * 16.0))] = true
			var geology := Vector4(
				map_data.get_mountain_edge_weight(tile),
				map_data.get_dustiness(tile),
				map_data.get_surface_age(tile),
				map_data.get_rockiness(tile)
			)
			if geology.x < 0.0 or geology.x > 1.0 or geology.y < 0.0 or geology.y > 1.0 or geology.z < 0.0 or geology.z > 1.0 or geology.w < 0.0 or geology.w > 1.0:
				push_error("Geology surface parameters should remain normalized: %s" % geology)
				quit(1)
				return
			distinct_geology_samples[Vector3i(roundi(geology.y * 16.0), roundi(geology.z * 16.0), roundi(geology.w * 16.0))] = true
	if distinct_samples.size() < 8:
		push_error("Ecology fields should contain coherent variation instead of one constant value.")
		quit(1)
		return
	if distinct_geology_samples.size() < 8:
		push_error("Geology fields should contain macro variation instead of one constant ground tone.")
		quit(1)
		return

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if map_data.get_terrain(tile) == 5:
				continue
			if map_data.get_mountain_edge_weight(tile) > 0.75:
				found_mountain_transition = true
				break
		if found_mountain_transition:
			break
	if not found_mountain_transition:
		push_error("Mountain massifs should generate a graded scree field on adjacent ground.")
		quit(1)
