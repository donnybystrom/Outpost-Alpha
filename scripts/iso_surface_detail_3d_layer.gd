extends Node3D

const PlanetSurfacePalette := preload("res://scripts/planet_surface_palette.gd")

const CHUNK_SIZE := 16
const TERRAIN_CLEAR := 0
const TERRAIN_FOREST := 1
const TERRAIN_CRYSTAL := 2
const TERRAIN_ORE := 3
const TERRAIN_VENT := 4
const TERRAIN_MOUNTAIN := 5

const DETAIL_ROCK := 0
const DETAIL_CRYSTAL := 1
const DETAIL_FUNGUS := 2
const DETAIL_VENT := 3

var map_data: RefCounted
var meshes: Array[Mesh] = []
var materials: Array[StandardMaterial3D] = []
var rebuild_requests := 0
var last_cells_processed := 0
var last_rebuild_usec := 0
var last_reason := ""
var last_placement_count := 0
var last_scree_placement_count := 0


func _ready() -> void:
	name = "SurfaceDetail3DLayer"
	_ensure_assets()


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	_rebuild("set_map_data")


func refresh_details(reason: String) -> void:
	_rebuild(reason)


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": get_child_count(),
		"redraw_requests": rebuild_requests,
		"last_draw_usec": 0,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_rebuild_usec,
		"last_reason": last_reason,
		"chunks": _active_chunk_count(),
		"placements": last_placement_count,
		"scree_placements": last_scree_placement_count,
	}


func _rebuild(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = 0
	last_placement_count = 0
	last_scree_placement_count = 0
	for child in get_children():
		child.queue_free()

	if map_data == null:
		last_rebuild_usec = Time.get_ticks_usec() - started
		return
	_ensure_assets()

	var placements_by_chunk := {}
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var terrain_id: int = map_data.get_terrain(tile)
			if terrain_id == TERRAIN_MOUNTAIN or map_data.has_road(tile):
				continue
			last_cells_processed += 1
			_place_tile_details(placements_by_chunk, tile, terrain_id)

	for chunk_coord: Vector2i in placements_by_chunk:
		var placements_by_type: Dictionary = placements_by_chunk[chunk_coord]
		for detail_type: int in placements_by_type:
			var placements: Array = placements_by_type[detail_type]
			if not placements.is_empty():
				_add_instances(chunk_coord, detail_type, placements)

	last_rebuild_usec = Time.get_ticks_usec() - started


func _place_tile_details(placements_by_chunk: Dictionary, tile: Vector2i, terrain_id: int) -> void:
	var moisture: float = map_data.get_moisture(tile)
	var radiation: float = map_data.get_radiation(tile)
	var minerals: float = map_data.get_mineral_content(tile)
	var mountain_edge: float = map_data.get_mountain_edge_weight(tile)
	var distance_from_colony := Vector2(tile - map_data.start_tile).length()
	var wilderness := smoothstep(float(map_data.build_radius) * 0.72, float(map_data.build_radius) + 12.0, distance_from_colony)

	# Eroded mountain material collects outside the geometric talus skirt. This is deliberately
	# deterministic and sparse enough that the transition reads at RTS scale without becoming gravel soup.
	if mountain_edge > 0.04 and _unit_noise(tile, 107) < 0.10 + mountain_edge * 0.48:
		_append_placement(placements_by_chunk, tile, DETAIL_ROCK, _detail_transform(tile, 109, lerpf(0.48, 0.86, mountain_edge), 0.055))
		last_scree_placement_count += 1
	if mountain_edge > 0.55 and _unit_noise(tile, 113) < (mountain_edge - 0.45) * 0.38:
		_append_placement(placements_by_chunk, tile, DETAIL_ROCK, _detail_transform(tile, 127, lerpf(0.38, 0.64, mountain_edge), 0.050))
		last_scree_placement_count += 1

	match terrain_id:
		TERRAIN_CLEAR:
			if _unit_noise(tile, 11) < wilderness * (0.035 + minerals * 0.055):
				_append_placement(placements_by_chunk, tile, DETAIL_ROCK, _detail_transform(tile, 17, 0.55, 0.06))
			if wilderness > 0.3 and _unit_noise(tile, 23) < moisture * (1.0 - radiation) * 0.075:
				_append_placement(placements_by_chunk, tile, DETAIL_FUNGUS, _detail_transform(tile, 29, 0.62, 0.025))
		TERRAIN_FOREST:
			if _unit_noise(tile, 31) < 0.18 + moisture * 0.28:
				_append_placement(placements_by_chunk, tile, DETAIL_FUNGUS, _detail_transform(tile, 37, 0.82, 0.025))
			if _unit_noise(tile, 41) < minerals * 0.07:
				_append_placement(placements_by_chunk, tile, DETAIL_ROCK, _detail_transform(tile, 43, 0.65, 0.06))
		TERRAIN_CRYSTAL:
			if _unit_noise(tile, 47) < 0.58 + minerals * 0.34:
				_append_placement(placements_by_chunk, tile, DETAIL_CRYSTAL, _detail_transform(tile, 53, 0.78, 0.20))
			if _unit_noise(tile, 59) < 0.16:
				_append_placement(placements_by_chunk, tile, DETAIL_ROCK, _detail_transform(tile, 61, 0.58, 0.06))
		TERRAIN_ORE:
			if _unit_noise(tile, 67) < 0.38 + minerals * 0.34:
				_append_placement(placements_by_chunk, tile, DETAIL_ROCK, _detail_transform(tile, 71, 0.88, 0.07))
			if _unit_noise(tile, 73) < minerals * 0.22:
				_append_placement(placements_by_chunk, tile, DETAIL_CRYSTAL, _detail_transform(tile, 79, 0.54, 0.15))
		TERRAIN_VENT:
			if _unit_noise(tile, 83) < 0.62:
				_append_placement(placements_by_chunk, tile, DETAIL_VENT, _detail_transform(tile, 89, 0.92, 0.17))
			if _unit_noise(tile, 97) < 0.24:
				_append_placement(placements_by_chunk, tile, DETAIL_ROCK, _detail_transform(tile, 101, 0.60, 0.06))


func _append_placement(placements_by_chunk: Dictionary, tile: Vector2i, detail_type: int, transform: Transform3D) -> void:
	var chunk_coord := Vector2i(
		floori(float(tile.x) / float(CHUNK_SIZE)),
		floori(float(tile.y) / float(CHUNK_SIZE))
	)
	if not placements_by_chunk.has(chunk_coord):
		placements_by_chunk[chunk_coord] = {}
	var placements_by_type: Dictionary = placements_by_chunk[chunk_coord]
	if not placements_by_type.has(detail_type):
		placements_by_type[detail_type] = []
	(placements_by_type[detail_type] as Array).append(transform)
	last_placement_count += 1


func _add_instances(chunk_coord: Vector2i, detail_type: int, placements: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = meshes[detail_type]
	multimesh.instance_count = placements.size()
	for index in placements.size():
		multimesh.set_instance_transform(index, placements[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = "%s_%d_%d" % [_detail_name(detail_type), chunk_coord.x, chunk_coord.y]
	instance.multimesh = multimesh
	instance.material_override = materials[detail_type]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _detail_transform(tile: Vector2i, salt: int, base_scale: float, y: float) -> Transform3D:
	var rotation := _unit_noise(tile, salt) * TAU
	var uniform_scale := base_scale * lerpf(0.72, 1.28, _unit_noise(tile, salt + 2))
	var stretch := lerpf(0.82, 1.22, _unit_noise(tile, salt + 4))
	var offset := Vector2(
		(_unit_noise(tile, salt + 6) - 0.5) * 0.62,
		(_unit_noise(tile, salt + 8) - 0.5) * 0.62
	)
	var basis := Basis(Vector3.UP, rotation).scaled(Vector3(uniform_scale * stretch, uniform_scale, uniform_scale / stretch))
	return Transform3D(basis, Vector3(float(tile.x) + offset.x, y, float(tile.y) + offset.y))


func _unit_noise(tile: Vector2i, salt: int) -> float:
	var seed := maxi(1, int(map_data.seed)) if map_data != null else 1
	var value := int(tile.x * 374761393 + tile.y * 668265263 + seed * 2246822519 + salt * 3266489917)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xffff) / 65535.0


func _ensure_assets() -> void:
	if not meshes.is_empty():
		return
	meshes = [_rock_mesh(), _crystal_mesh(), _fungus_mesh(), _vent_mesh()]
	materials = [
		_material(PlanetSurfacePalette.BEDROCK_MID, 0.98, 0.0),
		_material(PlanetSurfacePalette.CRYSTAL, 0.62, 0.08),
		_material(PlanetSurfacePalette.FUNGUS_BODY, 0.94, 0.0),
		_material(PlanetSurfacePalette.VENT_MINERAL, 0.82, 0.03),
	]


func _rock_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.20
	mesh.radial_segments = 7
	mesh.rings = 3
	return mesh


func _crystal_mesh() -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.12
	mesh.height = 0.48
	mesh.radial_segments = 5
	mesh.rings = 1
	return mesh


func _fungus_mesh() -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_fungus_stalk(surface, Vector2(-0.085, 0.02), 0.34, 0.038, 0.13)
	_add_fungus_stalk(surface, Vector2(0.075, 0.055), 0.25, 0.032, 0.105)
	_add_fungus_stalk(surface, Vector2(0.025, -0.075), 0.19, 0.025, 0.082)
	return surface.commit()


func _add_fungus_stalk(surface: SurfaceTool, offset: Vector2, height: float, stem_radius: float, cap_radius: float) -> void:
	const SEGMENTS := 7
	var stem_top := height * 0.64
	var cap_ring_y := height * 0.76
	var cap_top := Vector3(offset.x, height, offset.y)
	var cap_bottom := Vector3(offset.x, stem_top, offset.y)
	for segment in SEGMENTS:
		var next_segment := (segment + 1) % SEGMENTS
		var angle_a := TAU * float(segment) / float(SEGMENTS)
		var angle_b := TAU * float(next_segment) / float(SEGMENTS)
		var direction_a := Vector2(cos(angle_a), sin(angle_a))
		var direction_b := Vector2(cos(angle_b), sin(angle_b))
		var base_a := Vector3(offset.x + direction_a.x * stem_radius, 0.0, offset.y + direction_a.y * stem_radius)
		var base_b := Vector3(offset.x + direction_b.x * stem_radius, 0.0, offset.y + direction_b.y * stem_radius)
		var top_a := Vector3(offset.x + direction_a.x * stem_radius * 0.72, stem_top, offset.y + direction_a.y * stem_radius * 0.72)
		var top_b := Vector3(offset.x + direction_b.x * stem_radius * 0.72, stem_top, offset.y + direction_b.y * stem_radius * 0.72)
		_add_surface_triangle(surface, base_a, base_b, top_b)
		_add_surface_triangle(surface, base_a, top_b, top_a)

		var ring_a := Vector3(offset.x + direction_a.x * cap_radius, cap_ring_y, offset.y + direction_a.y * cap_radius)
		var ring_b := Vector3(offset.x + direction_b.x * cap_radius, cap_ring_y, offset.y + direction_b.y * cap_radius)
		_add_surface_triangle(surface, cap_bottom, ring_b, ring_a)
		_add_surface_triangle(surface, ring_a, ring_b, cap_top)


func _add_surface_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < -0.2:
		normal = -normal
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(point)


func _vent_mesh() -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.055
	mesh.bottom_radius = 0.145
	mesh.height = 0.38
	mesh.radial_segments = 7
	mesh.rings = 2
	return mesh


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var next_material := StandardMaterial3D.new()
	next_material.albedo_color = color
	next_material.roughness = roughness
	next_material.metallic = metallic
	next_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return next_material


func _detail_name(detail_type: int) -> String:
	return ["Rocks", "Crystals", "Fungus", "Vents"][detail_type]


func _active_chunk_count() -> int:
	var chunks := {}
	for child in get_children():
		var parts := child.name.split("_")
		if parts.size() >= 3:
			chunks["%s_%s" % [parts[-2], parts[-1]]] = true
	return chunks.size()
