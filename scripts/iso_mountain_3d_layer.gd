extends Node3D

const TERRAIN_MOUNTAIN := 5
const HALF_TILE := 0.5
const SUBDIVISIONS := 4
const BASE_MAX_HEIGHT := 1.55
const MAX_HEIGHT := 2.35
const BASE_Y := 0.045
const HEIGHT_SMOOTHING_PASSES := 2
const HEIGHT_SMOOTHING_BLEND := 0.42
const MAX_HEIGHT_STEP := 0.24
const INTERIOR_BOOST_START_TILES := 1.0
const INTERIOR_BOOST_FULL_TILES := 3.0
const INTERIOR_UPLIFT_MIN := 0.52
const INTERIOR_UPLIFT_MAX := 1.12
const INTERIOR_FINE_DETAIL_SCALE := 0.76

var map_data: RefCounted
var material: StandardMaterial3D
var mountain_noise: FastNoiseLite
var ridge_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var massif_noise: FastNoiseLite
var height_cache := {}
var rebuild_requests: int = 0
var last_cells_processed: int = 0
var last_rebuild_usec: int = 0
var last_reason := ""
var last_interior_boosted_points := 0
var last_max_generated_height := 0.0


func _ready() -> void:
	name = "Mountain3DLayer"
	_ensure_initialized()


func set_map_data(next_map_data: RefCounted) -> void:
	_ensure_initialized()
	map_data = next_map_data
	_configure_noise()
	_rebuild("set_map_data")


func refresh_mountains(reason: String) -> void:
	_rebuild(reason)


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": 0,
		"redraw_requests": rebuild_requests,
		"last_draw_usec": 0,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_rebuild_usec,
		"last_reason": last_reason,
		"interior_boosted_points": last_interior_boosted_points,
		"max_generated_height": last_max_generated_height,
	}


func _ensure_initialized() -> void:
	if material != null:
		return
	material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _configure_noise() -> void:
	var seed := 1
	if map_data != null:
		seed = maxi(1, int(map_data.seed))

	mountain_noise = FastNoiseLite.new()
	mountain_noise.seed = seed + 1701
	mountain_noise.frequency = 0.095
	mountain_noise.fractal_octaves = 4
	mountain_noise.fractal_lacunarity = 2.1
	mountain_noise.fractal_gain = 0.52

	ridge_noise = FastNoiseLite.new()
	ridge_noise.seed = seed + 1723
	ridge_noise.frequency = 0.18
	ridge_noise.fractal_octaves = 5
	ridge_noise.fractal_lacunarity = 2.0
	ridge_noise.fractal_gain = 0.48

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = seed + 1789
	detail_noise.frequency = 0.42
	detail_noise.fractal_octaves = 2
	detail_noise.fractal_gain = 0.45

	massif_noise = FastNoiseLite.new()
	massif_noise.seed = seed + 1811
	massif_noise.frequency = 0.024
	massif_noise.fractal_octaves = 3
	massif_noise.fractal_lacunarity = 2.0
	massif_noise.fractal_gain = 0.5


func _rebuild(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = 0
	last_interior_boosted_points = 0
	last_max_generated_height = 0.0
	height_cache.clear()

	for child in get_children():
		child.queue_free()

	if map_data == null:
		last_rebuild_usec = Time.get_ticks_usec() - started
		return
	_build_height_cache()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if map_data.get_terrain(tile) != TERRAIN_MOUNTAIN:
				continue
			_add_mountain_tile(vertices, normals, colors, tile)
			last_cells_processed += 1

	if vertices.is_empty():
		last_rebuild_usec = Time.get_ticks_usec() - started
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var instance := MeshInstance3D.new()
	instance.name = "ProceduralMountainMassifs"
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)

	last_rebuild_usec = Time.get_ticks_usec() - started


func _add_mountain_tile(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, tile: Vector2i) -> void:
	var points: Array[Array] = []
	for sy in range(SUBDIVISIONS + 1):
		var row: Array[Dictionary] = []
		for sx in range(SUBDIVISIONS + 1):
			var local := Vector2(
				lerpf(-HALF_TILE, HALF_TILE, float(sx) / float(SUBDIVISIONS)),
				lerpf(-HALF_TILE, HALF_TILE, float(sy) / float(SUBDIVISIONS))
			)
			var world_point := Vector2(float(tile.x) + local.x, float(tile.y) + local.y)
			var height := _height_at(tile, local, world_point)
			row.append({
				"position": Vector3(world_point.x, BASE_Y + height, world_point.y),
				"color": _color_for_height(height),
			})
		points.append(row)

	for sy in range(SUBDIVISIONS):
		for sx in range(SUBDIVISIONS):
			var a: Dictionary = points[sy][sx]
			var b: Dictionary = points[sy][sx + 1]
			var c: Dictionary = points[sy + 1][sx + 1]
			var d: Dictionary = points[sy + 1][sx]
			_add_triangle(vertices, normals, colors, a, b, c)
			_add_triangle(vertices, normals, colors, a, c, d)


func _build_height_cache() -> void:
	var boundary_points := {}
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if not _is_mountain(tile):
				continue
			for sy in range(SUBDIVISIONS + 1):
				for sx in range(SUBDIVISIONS + 1):
					var local := Vector2(
						lerpf(-HALF_TILE, HALF_TILE, float(sx) / float(SUBDIVISIONS)),
						lerpf(-HALF_TILE, HALF_TILE, float(sy) / float(SUBDIVISIONS))
					)
					var world_point := Vector2(float(tile.x) + local.x, float(tile.y) + local.y)
					var grid_point := _height_grid_point(world_point)
					if height_cache.has(grid_point):
						continue
					var sample_point := Vector2(grid_point) / float(SUBDIVISIONS)
					var edge_falloff := _shared_edge_falloff(tile, local, sample_point)
					height_cache[grid_point] = _raw_noise_height(sample_point) * edge_falloff
					if edge_falloff <= 0.0001:
						boundary_points[grid_point] = true

	_apply_interior_height_boost(boundary_points)
	_smooth_height_cache(boundary_points)
	_limit_height_slopes(boundary_points)
	for height in height_cache.values():
		last_max_generated_height = maxf(last_max_generated_height, float(height))


func _apply_interior_height_boost(boundary_points: Dictionary) -> void:
	if boundary_points.is_empty():
		return
	var distance_by_point := {}
	var pending: Array[Vector2i] = []
	for grid_point: Vector2i in boundary_points:
		distance_by_point[grid_point] = 0
		pending.append(grid_point)
	var cardinal_neighbors := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var pending_index := 0
	while pending_index < pending.size():
		var grid_point: Vector2i = pending[pending_index]
		pending_index += 1
		var next_distance: int = int(distance_by_point[grid_point]) + 1
		for offset: Vector2i in cardinal_neighbors:
			var neighbor := grid_point + offset
			if not height_cache.has(neighbor) or distance_by_point.has(neighbor):
				continue
			distance_by_point[neighbor] = next_distance
			pending.append(neighbor)

	var boost_start := INTERIOR_BOOST_START_TILES * float(SUBDIVISIONS)
	var boost_full := INTERIOR_BOOST_FULL_TILES * float(SUBDIVISIONS)
	for grid_point: Vector2i in height_cache:
		if not distance_by_point.has(grid_point):
			continue
		var distance: float = float(distance_by_point[grid_point])
		var interior_weight := smoothstep(boost_start, boost_full, distance)
		if interior_weight <= 0.0:
			continue
		var sample_point := Vector2(grid_point) / float(SUBDIVISIONS)
		var macro_value := (massif_noise.get_noise_2d(sample_point.x, sample_point.y) + 1.0) * 0.5
		var macro_uplift := lerpf(INTERIOR_UPLIFT_MIN, INTERIOR_UPLIFT_MAX, macro_value)
		var fine_detail_scale := lerpf(1.0, INTERIOR_FINE_DETAIL_SCALE, interior_weight)
		var raised_height := float(height_cache[grid_point]) * fine_detail_scale + macro_uplift * interior_weight
		height_cache[grid_point] = minf(raised_height, MAX_HEIGHT)
		last_interior_boosted_points += 1


func _smooth_height_cache(boundary_points: Dictionary) -> void:
	var cardinal_neighbors := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for pass_index in range(HEIGHT_SMOOTHING_PASSES):
		var next_heights := height_cache.duplicate()
		for grid_point: Vector2i in height_cache:
			if boundary_points.has(grid_point):
				next_heights[grid_point] = 0.0
				continue
			var neighbor_total := 0.0
			var neighbor_count := 0
			for offset: Vector2i in cardinal_neighbors:
				var neighbor := grid_point + offset
				if not height_cache.has(neighbor):
					continue
				neighbor_total += float(height_cache[neighbor])
				neighbor_count += 1
			if neighbor_count > 0:
				var neighbor_average := neighbor_total / float(neighbor_count)
				next_heights[grid_point] = lerpf(float(height_cache[grid_point]), neighbor_average, HEIGHT_SMOOTHING_BLEND)
		height_cache = next_heights


func _limit_height_slopes(boundary_points: Dictionary) -> void:
	var cardinal_neighbors := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var relaxation_passes := ceili(MAX_HEIGHT / MAX_HEIGHT_STEP) + 1
	for pass_index in range(relaxation_passes):
		var next_heights := height_cache.duplicate()
		for grid_point: Vector2i in height_cache:
			if boundary_points.has(grid_point):
				next_heights[grid_point] = 0.0
				continue
			var limited_height := float(height_cache[grid_point])
			for offset: Vector2i in cardinal_neighbors:
				var neighbor := grid_point + offset
				if height_cache.has(neighbor):
					limited_height = minf(limited_height, float(height_cache[neighbor]) + MAX_HEIGHT_STEP)
			next_heights[grid_point] = limited_height
		height_cache = next_heights


func _height_at(tile: Vector2i, local: Vector2, world_point: Vector2) -> float:
	var grid_point := _height_grid_point(world_point)
	if height_cache.has(grid_point):
		return float(height_cache[grid_point])
	var sample_point := Vector2(grid_point) / float(SUBDIVISIONS)
	return _raw_noise_height(sample_point) * _shared_edge_falloff(tile, local, sample_point)


func _height_grid_point(world_point: Vector2) -> Vector2i:
	return Vector2i(roundi(world_point.x * SUBDIVISIONS), roundi(world_point.y * SUBDIVISIONS))


func _raw_noise_height(sample_point: Vector2) -> float:
	var base := (mountain_noise.get_noise_2d(sample_point.x, sample_point.y) + 1.0) * 0.5
	var ridge := 1.0 - absf(ridge_noise.get_noise_2d(sample_point.x, sample_point.y))
	var detail := (detail_noise.get_noise_2d(sample_point.x, sample_point.y) + 1.0) * 0.5
	var combined: float = clampf(base * 0.35 + ridge * 0.72 + detail * 0.10, 0.0, 1.0)
	var remapped := pow(combined, 2.35)
	return remapped * BASE_MAX_HEIGHT


func _shared_edge_falloff(tile: Vector2i, local: Vector2, world_point: Vector2) -> float:
	var candidates: Array[Vector2i] = [tile]
	var edge_x := 0
	var edge_y := 0
	if is_equal_approx(absf(local.x), HALF_TILE):
		edge_x = 1 if local.x > 0.0 else -1
		candidates.append(tile + Vector2i(edge_x, 0))
	if is_equal_approx(absf(local.y), HALF_TILE):
		edge_y = 1 if local.y > 0.0 else -1
		candidates.append(tile + Vector2i(0, edge_y))
	if edge_x != 0 and edge_y != 0:
		candidates.append(tile + Vector2i(edge_x, edge_y))
	var shared_falloff := 0.0
	for candidate in candidates:
		if not _is_mountain(candidate):
			continue
		shared_falloff = maxf(shared_falloff, _edge_falloff_for_tile(candidate, world_point - Vector2(candidate)))
	return shared_falloff


func _edge_falloff_for_tile(tile: Vector2i, local: Vector2) -> float:
	var edge := 1.0
	if not _is_mountain(tile + Vector2i(-1, 0)):
		edge = minf(edge, smoothstep(-HALF_TILE, -0.12, local.x))
	if not _is_mountain(tile + Vector2i(1, 0)):
		edge = minf(edge, 1.0 - smoothstep(0.12, HALF_TILE, local.x))
	if not _is_mountain(tile + Vector2i(0, -1)):
		edge = minf(edge, smoothstep(-HALF_TILE, -0.12, local.y))
	if not _is_mountain(tile + Vector2i(0, 1)):
		edge = minf(edge, 1.0 - smoothstep(0.12, HALF_TILE, local.y))
	return clampf(edge, 0.0, 1.0)


func _is_mountain(tile: Vector2i) -> bool:
	return map_data != null and map_data.is_inside(tile) and map_data.get_terrain(tile) == TERRAIN_MOUNTAIN


func _color_for_height(height: float) -> Color:
	var t: float = clampf(height / MAX_HEIGHT, 0.0, 1.0)
	var low := Color8(55, 54, 50)
	var mid := Color8(94, 92, 86)
	var high := Color8(154, 151, 139)
	if t < 0.58:
		return low.lerp(mid, t / 0.58)
	return mid.lerp(high, (t - 0.58) / 0.42)


func _add_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var point_a: Vector3 = a["position"]
	var point_b: Vector3 = b["position"]
	var point_c: Vector3 = c["position"]
	var normal := (point_b - point_a).cross(point_c - point_a).normalized()
	if normal.y < 0.0:
		normal = -normal

	vertices.append(point_a)
	vertices.append(point_b)
	vertices.append(point_c)
	for i in range(3):
		normals.append(normal)
	colors.append(a["color"])
	colors.append(b["color"])
	colors.append(c["color"])
