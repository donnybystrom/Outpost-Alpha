extends Node3D

const TERRAIN_MOUNTAIN := 5
const HALF_TILE := 0.5
const SUBDIVISIONS := 4
const MAX_HEIGHT := 1.55
const BASE_Y := 0.045

var map_data: RefCounted
var material: StandardMaterial3D
var mountain_noise: FastNoiseLite
var ridge_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var rebuild_requests: int = 0
var last_cells_processed: int = 0
var last_rebuild_usec: int = 0
var last_reason := ""


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


func _rebuild(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = 0

	for child in get_children():
		child.queue_free()

	if map_data == null:
		last_rebuild_usec = Time.get_ticks_usec() - started
		return

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


func _height_at(tile: Vector2i, local: Vector2, world_point: Vector2) -> float:
	var base := (mountain_noise.get_noise_2d(world_point.x, world_point.y) + 1.0) * 0.5
	var ridge := 1.0 - absf(ridge_noise.get_noise_2d(world_point.x, world_point.y))
	var detail := (detail_noise.get_noise_2d(world_point.x, world_point.y) + 1.0) * 0.5
	var combined: float = clampf(base * 0.35 + ridge * 0.72 + detail * 0.10, 0.0, 1.0)
	var remapped := pow(combined, 2.35)
	return remapped * MAX_HEIGHT * _edge_falloff(tile, local)


func _edge_falloff(tile: Vector2i, local: Vector2) -> float:
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
