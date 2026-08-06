extends Node3D

const AutoTile := preload("res://scripts/auto_tile.gd")

const CHUNK_SIZE := 8
const SHOULDER_Y := 0.026
const DECK_Y := 0.032
const RUT_Y := 0.038
const SHOULDER_WIDTH := 0.92
const DECK_WIDTH := 0.68
const RUT_WIDTH := 0.085
const RUT_OFFSET := 0.19
const SHOULDER_IRREGULARITY := 0.10
const DECK_IRREGULARITY := 0.035
const CURVE_STEPS := 8
const CAP_SEGMENTS := 16

const SHOULDER_COLOR := Color8(68, 70, 62, 255)
const DECK_COLOR := Color8(91, 91, 79, 255)
const RUT_COLOR := Color8(52, 55, 50, 255)

const ROAD_ENDPOINTS := {
	AutoTile.NORTH: Vector2(0.0, -0.5),
	AutoTile.NORTH_EAST: Vector2(0.5, -0.5),
	AutoTile.EAST: Vector2(0.5, 0.0),
	AutoTile.SOUTH_EAST: Vector2(0.5, 0.5),
	AutoTile.SOUTH: Vector2(0.0, 0.5),
	AutoTile.SOUTH_WEST: Vector2(-0.5, 0.5),
	AutoTile.WEST: Vector2(-0.5, 0.0),
	AutoTile.NORTH_WEST: Vector2(-0.5, -0.5),
}

var map_data: RefCounted
var material: StandardMaterial3D
var road_mesh_instance: MeshInstance3D
var mesh_by_mask := {}
var tile_mask_by_tile := {}
var chunk_instance_by_coord := {}
var active_chunk_coords := {}
var rebuild_requests: int = 0
var last_cells_processed: int = 0
var last_rebuild_usec: int = 0
var last_reason := ""
var last_chunks_rebuilt: int = 0
var last_junction_count: int = 0
var last_cap_count: int = 0


func _ready() -> void:
	name = "Road3DLayer"
	_ensure_initialized()


func set_map_data(next_map_data: RefCounted) -> void:
	_ensure_initialized()
	map_data = next_map_data
	_rescan_masks()
	_rebuild_all_chunks("set_map_data")


func notify_road_changed(tile: Vector2i) -> void:
	notify_roads_changed([tile])


func notify_roads_changed(tiles: Array) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = "road_edit"
	last_cells_processed = 0
	last_chunks_rebuilt = 0
	last_junction_count = 0
	last_cap_count = 0
	if map_data == null:
		last_rebuild_usec = Time.get_ticks_usec() - started
		return

	var affected_tiles := _affected_tiles(tiles)
	var dirty_chunks := {}
	for tile in affected_tiles:
		_update_tile_mask(tile)
		dirty_chunks[_chunk_coord(tile)] = true
	for chunk_coord in dirty_chunks.keys():
		_rebuild_chunk(chunk_coord)
	_refresh_diagnostic_mesh_reference()
	last_rebuild_usec = Time.get_ticks_usec() - started


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": active_chunk_coords.size(),
		"redraw_requests": rebuild_requests,
		"last_draw_usec": 0,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_rebuild_usec,
		"last_reason": last_reason,
		"chunks": active_chunk_coords.size(),
		"chunks_rebuilt": last_chunks_rebuilt,
		"junctions": last_junction_count,
		"caps": last_cap_count,
	}


func _ensure_initialized() -> void:
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = Color.WHITE
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not mesh_by_mask.has(0):
		mesh_by_mask[0] = ArrayMesh.new()


func _rescan_masks() -> void:
	tile_mask_by_tile.clear()
	if map_data == null:
		return
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if map_data.has_road(tile):
				tile_mask_by_tile[tile] = AutoTile.road_mask(map_data, tile)


func _rebuild_all_chunks(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = 0
	last_chunks_rebuilt = 0
	last_junction_count = 0
	last_cap_count = 0
	for instance in chunk_instance_by_coord.values():
		(instance as MeshInstance3D).visible = false
	active_chunk_coords.clear()
	var chunks := {}
	for tile in tile_mask_by_tile.keys():
		chunks[_chunk_coord(tile)] = true
	for chunk_coord in chunks.keys():
		_rebuild_chunk(chunk_coord)
	_refresh_diagnostic_mesh_reference()
	last_rebuild_usec = Time.get_ticks_usec() - started


func _affected_tiles(changed_tiles: Array) -> Array[Vector2i]:
	var affected: Array[Vector2i] = []
	for changed_tile in changed_tiles:
		for direction in [Vector2i.ZERO] + AutoTile.ROAD_DIRECTIONS.values():
			var tile: Vector2i = changed_tile + direction
			if map_data.is_inside(tile) and not affected.has(tile):
				affected.append(tile)
	return affected


func _update_tile_mask(tile: Vector2i) -> void:
	if map_data.has_road(tile):
		tile_mask_by_tile[tile] = AutoTile.road_mask(map_data, tile)
	else:
		tile_mask_by_tile.erase(tile)


func _chunk_coord(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / float(CHUNK_SIZE)), floori(float(tile.y) / float(CHUNK_SIZE)))


func _rebuild_chunk(chunk_coord: Vector2i) -> void:
	last_chunks_rebuilt += 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var start := chunk_coord * CHUNK_SIZE
	var end := Vector2i(
		mini(start.x + CHUNK_SIZE, map_data.size.x),
		mini(start.y + CHUNK_SIZE, map_data.size.y)
	)
	for y in range(start.y, end.y):
		for x in range(start.x, end.x):
			var tile := Vector2i(x, y)
			if not tile_mask_by_tile.has(tile):
				continue
			last_cells_processed += 1
			_add_road_tile_geometry(vertices, normals, colors, tile, int(tile_mask_by_tile[tile]))

	var instance := _chunk_instance(chunk_coord)
	if vertices.is_empty():
		instance.visible = false
		instance.mesh = null
		active_chunk_coords.erase(chunk_coord)
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh
	instance.visible = true
	active_chunk_coords[chunk_coord] = true


func _chunk_instance(chunk_coord: Vector2i) -> MeshInstance3D:
	if chunk_instance_by_coord.has(chunk_coord):
		return chunk_instance_by_coord[chunk_coord]
	var instance := MeshInstance3D.new()
	instance.name = "RoadChunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	instance.material_override = material
	chunk_instance_by_coord[chunk_coord] = instance
	add_child(instance)
	return instance


func _refresh_diagnostic_mesh_reference() -> void:
	road_mesh_instance = null
	for chunk_coord in active_chunk_coords.keys():
		road_mesh_instance = chunk_instance_by_coord[chunk_coord]
		break
	mesh_by_mask[0] = road_mesh_instance.mesh if road_mesh_instance != null else ArrayMesh.new()


func _add_road_tile_geometry(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, tile: Vector2i, mask: int) -> void:
	var bits := _connected_bits(mask)
	var center := Vector2(tile)
	if bits.is_empty():
		_add_network_cap(vertices, normals, colors, center, 0)
		return
	if bits.size() <= 2:
		var centerline := _centerline_for_connections(bits)
		for index in centerline.size():
			centerline[index] += center
		_add_road_layers(vertices, normals, colors, centerline)
		if bits.size() == 1:
			_add_network_cap(vertices, normals, colors, center, 1)
		return

	for bit in bits:
		var centerline := PackedVector2Array([center, center + Vector2(ROAD_ENDPOINTS[bit])])
		_add_road_layers(vertices, normals, colors, centerline)
	_add_network_cap(vertices, normals, colors, center, bits.size())


func _connected_bits(mask: int) -> Array[int]:
	var bits: Array[int] = []
	for bit in ROAD_ENDPOINTS:
		if (mask & int(bit)) != 0:
			bits.append(int(bit))
	return bits


func _centerline_for_connections(bits: Array[int]) -> PackedVector2Array:
	if bits.size() == 1:
		return PackedVector2Array([Vector2.ZERO, ROAD_ENDPOINTS[bits[0]]])
	var start: Vector2 = ROAD_ENDPOINTS[bits[0]]
	var end: Vector2 = ROAD_ENDPOINTS[bits[1]]
	if start.is_equal_approx(-end):
		return PackedVector2Array([start, end])
	var points := PackedVector2Array()
	for step in range(CURVE_STEPS + 1):
		var weight := float(step) / float(CURVE_STEPS)
		var inverse := 1.0 - weight
		points.append(start * inverse * inverse + end * weight * weight)
	return points


func _add_road_layers(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, centerline: PackedVector2Array) -> void:
	_add_ribbon(vertices, normals, colors, centerline, SHOULDER_WIDTH, 0.0, SHOULDER_IRREGULARITY, SHOULDER_Y, SHOULDER_COLOR, 0.08, 17.0)
	_add_ribbon(vertices, normals, colors, centerline, DECK_WIDTH, 0.0, DECK_IRREGULARITY, DECK_Y, DECK_COLOR, 0.055, 41.0)
	_add_ribbon(vertices, normals, colors, centerline, RUT_WIDTH, -RUT_OFFSET, 0.018, RUT_Y, RUT_COLOR, 0.08, 73.0)
	_add_ribbon(vertices, normals, colors, centerline, RUT_WIDTH, RUT_OFFSET, 0.018, RUT_Y, RUT_COLOR, 0.08, 109.0)


func _add_ribbon(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, points: PackedVector2Array, width: float, lateral_offset: float, irregularity: float, y: float, base_color: Color, color_variation: float, seed: float) -> void:
	if points.size() < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in points.size():
		var normal := _polyline_normal(points, index)
		var center := points[index] + normal * lateral_offset
		var point_width := maxf(0.02, width + _noise_signed(points[index], seed) * irregularity)
		left.append(center + normal * point_width * 0.5)
		right.append(center - normal * point_width * 0.5)
	for index in range(points.size() - 1):
		var midpoint := points[index].lerp(points[index + 1], 0.5)
		var color := _vary_color(base_color, midpoint, color_variation, seed + 29.0)
		_add_quad(
			vertices,
			normals,
			colors,
			Vector3(left[index].x, y, left[index].y),
			Vector3(left[index + 1].x, y, left[index + 1].y),
			Vector3(right[index + 1].x, y, right[index + 1].y),
			Vector3(right[index].x, y, right[index].y),
			color
		)


func _polyline_normal(points: PackedVector2Array, index: int) -> Vector2:
	var previous := points[maxi(0, index - 1)]
	var following := points[mini(points.size() - 1, index + 1)]
	var tangent := previous.direction_to(following)
	if tangent.is_zero_approx():
		tangent = Vector2.RIGHT
	return tangent.orthogonal()


func _add_network_cap(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, center: Vector2, connection_count: int) -> void:
	last_cap_count += 1
	if connection_count >= 3:
		last_junction_count += 1
	var scale := 1.12 if connection_count >= 3 else 1.0
	_add_disc(vertices, normals, colors, center, SHOULDER_WIDTH * 0.5 * scale, SHOULDER_Y, SHOULDER_COLOR)
	_add_disc(vertices, normals, colors, center, DECK_WIDTH * 0.5 * scale, DECK_Y, DECK_COLOR)
	if connection_count == 0:
		for offset in [-RUT_OFFSET, RUT_OFFSET]:
			_add_simple_strip(vertices, normals, colors, center + Vector2(-0.22, offset), center + Vector2(0.22, offset), RUT_WIDTH, RUT_Y, RUT_COLOR)


func _add_disc(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, center: Vector2, radius: float, y: float, color: Color) -> void:
	for index in range(CAP_SEGMENTS):
		var angle_a := TAU * float(index) / float(CAP_SEGMENTS)
		var angle_b := TAU * float(index + 1) / float(CAP_SEGMENTS)
		_add_triangle(vertices, normals, colors, Vector3(center.x, y, center.y), Vector3(center.x + cos(angle_a) * radius, y, center.y + sin(angle_a) * radius), Vector3(center.x + cos(angle_b) * radius, y, center.y + sin(angle_b) * radius), color)


func _add_simple_strip(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, start: Vector2, end: Vector2, width: float, y: float, color: Color) -> void:
	var normal := start.direction_to(end).orthogonal() * width * 0.5
	_add_quad(vertices, normals, colors, Vector3(start.x + normal.x, y, start.y + normal.y), Vector3(end.x + normal.x, y, end.y + normal.y), Vector3(end.x - normal.x, y, end.y - normal.y), Vector3(start.x - normal.x, y, start.y - normal.y), color)


func _noise_signed(position: Vector2, seed: float) -> float:
	return fposmod(sin(position.dot(Vector2(12.9898, 78.233)) + seed) * 43758.5453, 1.0) * 2.0 - 1.0


func _vary_color(base_color: Color, position: Vector2, amount: float, seed: float) -> Color:
	var scale := 1.0 + _noise_signed(position, seed) * amount
	return Color(clampf(base_color.r * scale, 0.0, 1.0), clampf(base_color.g * scale, 0.0, 1.0), clampf(base_color.b * scale, 0.0, 1.0), base_color.a)


func _add_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_add_triangle(vertices, normals, colors, a, b, c, color)
	_add_triangle(vertices, normals, colors, a, c, d, color)


func _add_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	vertices.append_array(PackedVector3Array([a, b, c]))
	for _index in range(3):
		normals.append(Vector3.UP)
		colors.append(color)
