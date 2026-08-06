extends Node3D

const AutoTile := preload("res://scripts/auto_tile.gd")

const ROAD_Y := 0.035
const EDGE_Y := 0.032
const STRIPE_Y := 0.038
const HALF_TILE := 0.48
const EDGE_WIDTH := 0.30
const DECK_WIDTH := 0.22
const STRIPE_WIDTH := 0.035

const ROAD_ENDPOINTS := {
	AutoTile.NORTH: Vector2(0.0, -HALF_TILE),
	AutoTile.EAST: Vector2(HALF_TILE, 0.0),
	AutoTile.SOUTH: Vector2(0.0, HALF_TILE),
	AutoTile.WEST: Vector2(-HALF_TILE, 0.0),
}

var map_data: RefCounted
var material: StandardMaterial3D
var mesh_by_mask := {}
var road_tiles_by_mask := {}
var tile_mask_by_tile := {}
var multimesh_by_mask := {}
var instance_by_mask := {}
var rebuild_requests: int = 0
var last_cells_processed: int = 0
var last_rebuild_usec: int = 0
var last_reason := ""


func _ready() -> void:
	name = "Road3DLayer"
	_ensure_initialized()


func set_map_data(next_map_data: RefCounted) -> void:
	_ensure_initialized()
	map_data = next_map_data
	_rescan_roads()
	_rebuild_all_multimeshes("set_map_data")


func notify_road_changed(tile: Vector2i) -> void:
	notify_roads_changed([tile])


func notify_roads_changed(tiles: Array) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = "road_edit"
	last_cells_processed = 0
	if map_data == null:
		last_rebuild_usec = Time.get_ticks_usec() - started
		return

	var dirty_tiles: Array[Vector2i] = []
	for tile in tiles:
		for affected_tile in _affected_road_tiles(tile):
			if map_data.is_inside(affected_tile) and not dirty_tiles.has(affected_tile):
				dirty_tiles.append(affected_tile)

	var dirty_masks := {}
	for tile in dirty_tiles:
		_update_tracked_tile(tile, dirty_masks)
		last_cells_processed += 1

	for mask in dirty_masks.keys():
		_rebuild_mask_multimesh(int(mask))

	last_rebuild_usec = Time.get_ticks_usec() - started


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": 0,
		"redraw_requests": rebuild_requests,
		"last_draw_usec": 0,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_rebuild_usec,
		"last_reason": last_reason,
	}


func _build_material() -> void:
	material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _ensure_initialized() -> void:
	if material == null:
		_build_material()
	if mesh_by_mask.is_empty():
		_build_mask_meshes()


func _build_mask_meshes() -> void:
	for mask in range(16):
		mesh_by_mask[mask] = _build_road_mesh(mask)
		road_tiles_by_mask[mask] = []


func _rescan_roads() -> void:
	tile_mask_by_tile.clear()
	for mask in range(16):
		road_tiles_by_mask[mask] = []
	if map_data == null:
		return

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if not map_data.has_road(tile):
				continue
			var mask := AutoTile.road_mask(map_data, tile)
			tile_mask_by_tile[tile] = mask
			road_tiles_by_mask[mask].append(tile)


func _rebuild_all_multimeshes(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = tile_mask_by_tile.size()
	for mask in range(16):
		_rebuild_mask_multimesh(mask)
	last_rebuild_usec = Time.get_ticks_usec() - started


func _rebuild_mask_multimesh(mask: int) -> void:
	_ensure_mask_instance(mask)
	var tiles: Array = road_tiles_by_mask.get(mask, [])
	var multimesh: MultiMesh = multimesh_by_mask[mask]
	multimesh.instance_count = tiles.size()
	for index in tiles.size():
		var tile: Vector2i = tiles[index]
		multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(float(tile.x), 0.0, float(tile.y))))


func _ensure_mask_instance(mask: int) -> void:
	if instance_by_mask.has(mask):
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh_by_mask[mask]
	multimesh.instance_count = 0
	multimesh_by_mask[mask] = multimesh

	var instance := MultiMeshInstance3D.new()
	instance.name = "RoadMask_%02d" % mask
	instance.multimesh = multimesh
	instance.material_override = material
	instance_by_mask[mask] = instance
	add_child(instance)


func _update_tracked_tile(tile: Vector2i, dirty_masks: Dictionary) -> void:
	if tile_mask_by_tile.has(tile):
		var previous_mask: int = tile_mask_by_tile[tile]
		var previous_bucket: Array = road_tiles_by_mask[previous_mask]
		previous_bucket.erase(tile)
		dirty_masks[previous_mask] = true
		tile_mask_by_tile.erase(tile)

	if not map_data.has_road(tile):
		return

	var next_mask := AutoTile.road_mask(map_data, tile)
	tile_mask_by_tile[tile] = next_mask
	road_tiles_by_mask[next_mask].append(tile)
	dirty_masks[next_mask] = true


func _affected_road_tiles(tile: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [tile]
	for bit in AutoTile.CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = tile + AutoTile.CARDINAL_DIRECTIONS[bit]
		if map_data != null and map_data.is_inside(neighbor):
			tiles.append(neighbor)
	return tiles


func _build_road_mesh(mask: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	if mask == 0:
		_add_center_pad(vertices, normals, colors)
	else:
		for bit in ROAD_ENDPOINTS.keys():
			if mask & int(bit):
				_add_segment(vertices, normals, colors, ROAD_ENDPOINTS[bit], int(bit), mask)
		_add_junction(vertices, normals, colors, mask)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_segment(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, end: Vector2, bit: int, mask: int) -> void:
	var start := Vector2.ZERO
	_add_strip(vertices, normals, colors, start, end, EDGE_WIDTH, EDGE_Y, Color8(15, 18, 17, 245))
	_add_strip(vertices, normals, colors, start, end, DECK_WIDTH, ROAD_Y, Color8(66, 70, 66, 245))

	var stripe_offset := Vector2(0.0, 0.05)
	if bit == AutoTile.NORTH or bit == AutoTile.SOUTH:
		stripe_offset = Vector2(0.05, 0.0)
	var stripe_start := start.lerp(end, 0.30) + stripe_offset
	var stripe_end := start.lerp(end, 0.82) + stripe_offset
	_add_strip(vertices, normals, colors, stripe_start, stripe_end, STRIPE_WIDTH, STRIPE_Y, Color8(214, 133, 35, 235))

	if mask != bit and _hash_noise(mask, bit, 11) > 0.45:
		var panel_start := start.lerp(end, 0.48) - stripe_offset
		var panel_end := start.lerp(end, 0.90) - stripe_offset
		_add_strip(vertices, normals, colors, panel_start, panel_end, STRIPE_WIDTH, STRIPE_Y, Color8(101, 104, 96, 190))


func _add_center_pad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	_add_diamond(vertices, normals, colors, Vector2.ZERO, Vector2(0.22, 0.16), EDGE_Y, Color8(16, 19, 18, 235))
	_add_diamond(vertices, normals, colors, Vector2.ZERO, Vector2(0.16, 0.11), ROAD_Y, Color8(73, 76, 71, 240))
	_add_strip(vertices, normals, colors, Vector2(-0.11, 0.02), Vector2(0.11, -0.02), STRIPE_WIDTH, STRIPE_Y, Color8(214, 133, 35, 230))


func _add_junction(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, mask: int) -> void:
	var connection_count := _bit_count(mask)
	if connection_count >= 3:
		_add_diamond(vertices, normals, colors, Vector2.ZERO, Vector2(0.20, 0.20), EDGE_Y, Color8(15, 18, 17, 245))
		_add_diamond(vertices, normals, colors, Vector2.ZERO, Vector2(0.15, 0.15), ROAD_Y, Color8(75, 79, 74, 245))
		_add_strip(vertices, normals, colors, Vector2(-0.13, 0.0), Vector2(0.13, 0.0), STRIPE_WIDTH, STRIPE_Y, Color8(222, 141, 38, 235))
	elif connection_count == 2:
		_add_diamond(vertices, normals, colors, Vector2.ZERO, Vector2(0.12, 0.12), ROAD_Y, Color8(75, 79, 74, 235))
	else:
		_add_diamond(vertices, normals, colors, Vector2.ZERO, Vector2(0.09, 0.09), ROAD_Y, Color8(75, 79, 74, 220))


func _add_strip(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, start: Vector2, end: Vector2, width: float, y: float, color: Color) -> void:
	var direction := end - start
	if direction.length_squared() <= 0.0001:
		return
	var normal := Vector2(-direction.y, direction.x).normalized() * width * 0.5
	_add_quad(
		vertices,
		normals,
		colors,
		Vector3(start.x + normal.x, y, start.y + normal.y),
		Vector3(end.x + normal.x, y, end.y + normal.y),
		Vector3(end.x - normal.x, y, end.y - normal.y),
		Vector3(start.x - normal.x, y, start.y - normal.y),
		color
	)


func _add_diamond(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, center: Vector2, radius: Vector2, y: float, color: Color) -> void:
	_add_quad(
		vertices,
		normals,
		colors,
		Vector3(center.x, y, center.y - radius.y),
		Vector3(center.x + radius.x, y, center.y),
		Vector3(center.x, y, center.y + radius.y),
		Vector3(center.x - radius.x, y, center.y),
		color
	)


func _add_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	vertices.append_array(PackedVector3Array([a, b, c, a, c, d]))
	for i in range(6):
		normals.append(Vector3.UP)
	for i in range(6):
		colors.append(color)


func _bit_count(mask: int) -> int:
	var count := 0
	for bit in [AutoTile.NORTH, AutoTile.EAST, AutoTile.SOUTH, AutoTile.WEST]:
		if mask & bit:
			count += 1
	return count


func _hash_noise(x: int, y: int, seed: int) -> float:
	var value := int(x * 374761393 + y * 668265263 + seed * 2246822519)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xffff) / 65535.0
