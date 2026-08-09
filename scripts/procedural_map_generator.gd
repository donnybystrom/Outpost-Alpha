extends RefCounted

const MapData := preload("res://scripts/map_data.gd")

const TERRAIN_CLEAR := 0
const TERRAIN_FOREST := 1
const TERRAIN_CRYSTAL := 2
const TERRAIN_ORE := 3
const TERRAIN_VENT := 4
const TERRAIN_MOUNTAIN := 5
const DEFAULT_MOUNTAIN_PERCENT := 67
const MOUNTAIN_CLOSING_PASSES := 1
const MOUNTAIN_CLOSING_NEIGHBORS := 5
const MAX_MOUNTAIN_HOLE_TILES := 24
const MOUNTAIN_EDGE_RADIUS := 3.5


static func generate(map_size: Vector2i, seed: int = 0, min_build_radius: int = 25, max_build_radius: int = 40, path_count: int = 3, path_width: int = 8, clearing_noise: int = 45, mountain_percent: int = DEFAULT_MOUNTAIN_PERCENT, include_demo_roads: bool = false) -> RefCounted:
	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
		seed = rng.randi_range(1, 2147483647)
		rng.seed = seed
	else:
		rng.seed = seed

	min_build_radius = clampi(min_build_radius, 4, maxi(map_size.x, map_size.y) / 2 - 4)
	max_build_radius = clampi(max_build_radius, min_build_radius, maxi(map_size.x, map_size.y) / 2 - 2)
	path_count = clampi(path_count, 1, 12)
	path_width = clampi(path_width, 1, 16)
	clearing_noise = clampi(clearing_noise, 0, 100)
	mountain_percent = clampi(mountain_percent, 0, 100)

	var map_data := MapData.new(map_size)
	map_data.seed = seed
	map_data.start_tile = map_size / 2
	map_data.build_radius = min_build_radius
	map_data.clearing_noise = clearing_noise
	map_data.path_width = path_width
	map_data.mountain_percent = mountain_percent

	_generate_ground(map_data, seed)
	_place_mountain_massifs(map_data, seed + 541, mountain_percent)
	_carve_player_clearing(map_data, seed, min_build_radius, max_build_radius, clearing_noise)
	_place_resources(map_data, seed + 991)
	_carve_exit_paths(map_data, rng, path_count, path_width)
	if include_demo_roads:
		_place_demo_roads(map_data)
	_generate_surface_fields(map_data, seed + 2027)
	return map_data


static func _generate_surface_fields(map_data: RefCounted, seed: int) -> void:
	var moisture_noise := FastNoiseLite.new()
	moisture_noise.seed = seed
	moisture_noise.frequency = 0.032
	moisture_noise.fractal_octaves = 4
	moisture_noise.fractal_lacunarity = 2.0
	moisture_noise.fractal_gain = 0.52

	var radiation_noise := FastNoiseLite.new()
	radiation_noise.seed = seed + 103
	radiation_noise.frequency = 0.021
	radiation_noise.fractal_octaves = 3
	radiation_noise.fractal_gain = 0.48

	var mineral_noise := FastNoiseLite.new()
	mineral_noise.seed = seed + 251
	mineral_noise.frequency = 0.047
	mineral_noise.fractal_octaves = 4
	mineral_noise.fractal_gain = 0.56

	var dust_noise := FastNoiseLite.new()
	dust_noise.seed = seed + 397
	dust_noise.frequency = 0.026
	dust_noise.fractal_octaves = 3
	dust_noise.fractal_gain = 0.5

	var age_noise := FastNoiseLite.new()
	age_noise.seed = seed + 461
	age_noise.frequency = 0.014
	age_noise.fractal_octaves = 3
	age_noise.fractal_gain = 0.54

	var rock_noise := FastNoiseLite.new()
	rock_noise.seed = seed + 557
	rock_noise.frequency = 0.082
	rock_noise.fractal_octaves = 3
	rock_noise.fractal_gain = 0.48

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var terrain_id: int = map_data.get_terrain(tile)
			var moisture_value := _noise_to_unit(moisture_noise.get_noise_2d(float(x), float(y)))
			var radiation_value := _noise_to_unit(radiation_noise.get_noise_2d(float(x), float(y)))
			var mineral_value := _noise_to_unit(mineral_noise.get_noise_2d(float(x), float(y)))
			var dust_value := _noise_to_unit(dust_noise.get_noise_2d(float(x), float(y)))
			var age_value := _noise_to_unit(age_noise.get_noise_2d(float(x), float(y)))
			var rock_value := _noise_to_unit(rock_noise.get_noise_2d(float(x), float(y)))

			# The logical terrain influences ecology, but does not replace these continuous fields.
			if terrain_id == TERRAIN_FOREST:
				moisture_value = minf(1.0, moisture_value + 0.24)
				radiation_value *= 0.72
			elif terrain_id == TERRAIN_CRYSTAL:
				mineral_value = minf(1.0, mineral_value + 0.34)
			elif terrain_id == TERRAIN_ORE:
				mineral_value = minf(1.0, mineral_value + 0.46)
			elif terrain_id == TERRAIN_VENT:
				moisture_value *= 0.42
				mineral_value = minf(1.0, mineral_value + 0.22)
				radiation_value = minf(1.0, radiation_value + 0.16)
			elif terrain_id == TERRAIN_MOUNTAIN:
				moisture_value *= 0.58
				mineral_value = minf(1.0, mineral_value + 0.18)
				rock_value = minf(1.0, rock_value + 0.35)
				dust_value *= 0.55

			map_data.set_surface_parameters(tile, moisture_value, radiation_value, mineral_value)
			map_data.set_geology_parameters(tile, dust_value, age_value, rock_value)

	_generate_mountain_edge_weights(map_data)


static func refresh_visual_fields(map_data: RefCounted) -> void:
	if map_data != null:
		_generate_surface_fields(map_data, int(map_data.seed) + 2027)


static func _generate_mountain_edge_weights(map_data: RefCounted) -> void:
	var scan_radius := ceili(MOUNTAIN_EDGE_RADIUS)
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if map_data.get_terrain(tile) == TERRAIN_MOUNTAIN:
				map_data.set_mountain_edge_weight(tile, 1.0)
				continue
			var nearest_distance := MOUNTAIN_EDGE_RADIUS + 1.0
			for offset_y in range(-scan_radius, scan_radius + 1):
				for offset_x in range(-scan_radius, scan_radius + 1):
					var neighbor := tile + Vector2i(offset_x, offset_y)
					if not map_data.is_inside(neighbor) or map_data.get_terrain(neighbor) != TERRAIN_MOUNTAIN:
						continue
					nearest_distance = minf(nearest_distance, Vector2(offset_x, offset_y).length())
			var edge_weight := 1.0 - smoothstep(0.55, MOUNTAIN_EDGE_RADIUS, nearest_distance)
			map_data.set_mountain_edge_weight(tile, edge_weight)


static func _noise_to_unit(value: float) -> float:
	return clampf(value * 0.5 + 0.5, 0.0, 1.0)


static func _generate_ground(map_data: RefCounted, seed: int) -> void:
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = seed
	forest_noise.frequency = 0.055
	forest_noise.fractal_octaves = 4

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = seed + 337
	detail_noise.frequency = 0.16
	detail_noise.fractal_octaves = 2

	var max_distance: float = Vector2(map_data.size).length() * 0.5
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var distance: float = Vector2(tile - map_data.start_tile).length()
			var forest_bias: float = smoothstep(float(map_data.build_radius) * 0.75, max_distance * 0.82, distance)
			var forest_value: float = forest_noise.get_noise_2d(float(x), float(y)) + forest_bias
			var detail_value: float = detail_noise.get_noise_2d(float(x), float(y))
			var terrain_id := TERRAIN_CLEAR

			if forest_value > 0.32:
				terrain_id = TERRAIN_FOREST
			if terrain_id == TERRAIN_FOREST and detail_value > 0.42:
				terrain_id = TERRAIN_CRYSTAL
			elif terrain_id == TERRAIN_FOREST and detail_value < -0.48:
				terrain_id = TERRAIN_CLEAR

			map_data.set_terrain(Vector2i(x, y), terrain_id)


static func _place_mountain_massifs(map_data: RefCounted, seed: int, mountain_percent: int) -> void:
	if mountain_percent <= 0:
		return

	var mountain_noise := FastNoiseLite.new()
	mountain_noise.seed = seed
	mountain_noise.frequency = 0.052
	mountain_noise.fractal_octaves = 4

	var ridge_noise := FastNoiseLite.new()
	ridge_noise.seed = seed + 229
	ridge_noise.frequency = 0.12
	ridge_noise.fractal_octaves = 2

	var candidates: Array[Dictionary] = []
	var max_distance: float = Vector2(map_data.size).length() * 0.5
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var terrain_id: int = map_data.get_terrain(tile)
			if terrain_id != TERRAIN_FOREST and terrain_id != TERRAIN_CRYSTAL:
				continue
			var distance: float = Vector2(tile - map_data.start_tile).length()
			var wilderness_bias: float = smoothstep(float(map_data.build_radius) * 0.9, max_distance * 0.72, distance)
			var mountain_value: float = mountain_noise.get_noise_2d(float(x), float(y)) + wilderness_bias * 0.36
			var ridge_value: float = ridge_noise.get_noise_2d(float(x), float(y))
			candidates.append({
				"tile": tile,
				"score": mountain_value + ridge_value * 0.28,
			})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var mountain_count := roundi(float(candidates.size()) * float(mountain_percent) / 100.0)
	for index in range(mountain_count):
		map_data.set_terrain(candidates[index]["tile"], TERRAIN_MOUNTAIN)

	_close_mountain_mask(map_data)
	_fill_small_mountain_holes(map_data)


static func _close_mountain_mask(map_data: RefCounted) -> void:
	var neighbor_offsets := [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	for pass_index in range(MOUNTAIN_CLOSING_PASSES):
		var tiles_to_fill: Array[Vector2i] = []
		for y in map_data.size.y:
			for x in map_data.size.x:
				var tile := Vector2i(x, y)
				if map_data.get_terrain(tile) == TERRAIN_MOUNTAIN:
					continue
				var mountain_neighbors := 0
				for offset: Vector2i in neighbor_offsets:
					var neighbor := tile + offset
					if map_data.is_inside(neighbor) and map_data.get_terrain(neighbor) == TERRAIN_MOUNTAIN:
						mountain_neighbors += 1
				if mountain_neighbors >= MOUNTAIN_CLOSING_NEIGHBORS:
					tiles_to_fill.append(tile)
		for tile in tiles_to_fill:
			map_data.set_terrain(tile, TERRAIN_MOUNTAIN)


static func _fill_small_mountain_holes(map_data: RefCounted) -> void:
	var visited := {}
	var cardinal_offsets := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for y in map_data.size.y:
		for x in map_data.size.x:
			var start := Vector2i(x, y)
			if visited.has(start) or map_data.get_terrain(start) == TERRAIN_MOUNTAIN:
				continue
			var component: Array[Vector2i] = []
			var pending: Array[Vector2i] = [start]
			visited[start] = true
			var touches_map_edge := false
			var contains_colony_start := false
			while not pending.is_empty():
				var tile: Vector2i = pending.pop_back()
				component.append(tile)
				if tile.x == 0 or tile.y == 0 or tile.x == map_data.size.x - 1 or tile.y == map_data.size.y - 1:
					touches_map_edge = true
				if tile == map_data.start_tile:
					contains_colony_start = true
				for offset: Vector2i in cardinal_offsets:
					var neighbor := tile + offset
					if not map_data.is_inside(neighbor) or visited.has(neighbor):
						continue
					if map_data.get_terrain(neighbor) == TERRAIN_MOUNTAIN:
						continue
					visited[neighbor] = true
					pending.append(neighbor)
			if not touches_map_edge and not contains_colony_start and component.size() <= MAX_MOUNTAIN_HOLE_TILES:
				for tile in component:
					map_data.set_terrain(tile, TERRAIN_MOUNTAIN)


static func _carve_player_clearing(map_data: RefCounted, seed: int, min_build_radius: int, max_build_radius: int, clearing_noise: int) -> void:
	var clearing_shape_noise := FastNoiseLite.new()
	clearing_shape_noise.seed = seed + 711
	clearing_shape_noise.frequency = 0.12
	clearing_shape_noise.fractal_octaves = 2

	var noise_factor: float = float(clearing_noise) / 100.0
	var radius_span: float = float(max_build_radius - min_build_radius)

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var distance: float = Vector2(tile - map_data.start_tile).length()
			var edge_noise: float = (clearing_shape_noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var local_radius: float = float(min_build_radius) + radius_span * edge_noise * noise_factor
			if distance <= local_radius:
				map_data.set_terrain(tile, TERRAIN_CLEAR)


static func _carve_exit_paths(map_data: RefCounted, rng: RandomNumberGenerator, path_count: int, path_width: int) -> void:
	var base_angle: float = rng.randf_range(0.0, TAU)
	var base_radius: int = _path_width_to_radius(path_width)
	for path_index in range(path_count):
		var angle: float = base_angle + TAU * float(path_index) / float(path_count) + rng.randf_range(-0.28, 0.28)
		var endpoint: Vector2i = _edge_tile_for_angle(map_data, angle)
		map_data.path_endpoints.append(endpoint)
		var radius_variation := rng.randi_range(-1, 1) if path_width > 3 else 0
		_carve_path(map_data, map_data.start_tile, endpoint, maxi(0, base_radius + radius_variation), rng)


static func _path_width_to_radius(path_width: int) -> int:
	if path_width <= 1:
		return 0
	return ceili(float(path_width - 1) * 0.5)


static func _edge_tile_for_angle(map_data: RefCounted, angle: float) -> Vector2i:
	var direction: Vector2 = Vector2(cos(angle), sin(angle))
	var center: Vector2 = Vector2(map_data.start_tile)
	var max_steps: int = maxi(map_data.size.x, map_data.size.y)
	var last_inside: Vector2i = map_data.start_tile

	for step in range(max_steps):
		var point: Vector2 = center + direction * float(step)
		var tile: Vector2i = Vector2i(roundi(point.x), roundi(point.y))
		if not map_data.is_inside(tile):
			return last_inside
		last_inside = tile

	return last_inside


static func _carve_path(map_data: RefCounted, start: Vector2i, end: Vector2i, radius: int, rng: RandomNumberGenerator) -> void:
	var delta: Vector2i = end - start
	var steps: int = maxi(abs(delta.x), abs(delta.y))
	var normal: Vector2 = Vector2(-delta.y, delta.x).normalized()
	var wobble_noise := FastNoiseLite.new()
	wobble_noise.seed = map_data.seed + end.x * 13 + end.y * 29
	wobble_noise.frequency = 0.075
	wobble_noise.fractal_octaves = 2

	for i in range(steps + 1):
		var t: float = 0.0 if steps == 0 else float(i) / float(steps)
		var center: Vector2 = Vector2(start).lerp(Vector2(end), t)
		var wobble: float = wobble_noise.get_noise_1d(float(i)) * 4.0
		var tile_center: Vector2i = Vector2i(roundi(center.x + normal.x * wobble), roundi(center.y + normal.y * wobble))
		_carve_disc(map_data, tile_center, radius + int(abs(wobble) * 0.25))


static func _carve_disc(map_data: RefCounted, center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var tile := Vector2i(x, y)
			if map_data.is_inside(tile) and Vector2(tile - center).length() <= float(radius):
				map_data.set_terrain(tile, TERRAIN_CLEAR)


static func _place_resources(map_data: RefCounted, seed: int) -> void:
	var resource_noise := FastNoiseLite.new()
	resource_noise.seed = seed
	resource_noise.frequency = 0.11
	resource_noise.fractal_octaves = 3

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var distance: float = Vector2(tile - map_data.start_tile).length()
			if distance < float(map_data.build_radius + 4):
				continue
			var n: float = resource_noise.get_noise_2d(float(x), float(y))
			if n > 0.54 and map_data.get_terrain(tile) != TERRAIN_MOUNTAIN:
				map_data.set_terrain(tile, TERRAIN_ORE)
			elif n < -0.58 and map_data.get_terrain(tile) != TERRAIN_MOUNTAIN:
				map_data.set_terrain(tile, TERRAIN_VENT)


static func _place_demo_roads(map_data: RefCounted) -> void:
	var center: Vector2i = map_data.start_tile
	for x in range(center.x - 8, center.x + 9):
		map_data.set_road(Vector2i(x, center.y))
	for y in range(center.y - 6, center.y + 7):
		map_data.set_road(Vector2i(center.x, y))
	for x in range(center.x, center.x + 10):
		map_data.set_road(Vector2i(x, center.y + 5))
