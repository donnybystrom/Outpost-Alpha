extends Node3D

const BuildingCatalog := preload("res://scripts/building_catalog.gd")
const ColonyState := preload("res://scripts/colony_state.gd")

# Keep rendered buildings on their own visual layer so a cheap, shadowless
# fill light can soften their imported normals without touching terrain,
# mountains, units, or the world's shadow pass.
const BUILDING_VISUAL_LAYER_MASK := 1 << 1
const DEFAULT_SMOOTH_NORMAL_ANGLE_DEGREES := 52.0
const NORMAL_POSITION_QUANTIZATION := 10000.0

var colony_state: ColonyState
var building_catalog = BuildingCatalog.new()
var mesh_by_type := {}
var material_by_type := {}
var rebuild_requests: int = 0
var last_cells_processed: int = 0
var last_rebuild_usec: int = 0
var last_reason := ""


func _ready() -> void:
	name = "Building3DLayer"


func set_building_catalog(next_building_catalog) -> void:
	if next_building_catalog == null:
		return
	building_catalog = next_building_catalog
	mesh_by_type.clear()
	material_by_type.clear()
	_rebuild("building_catalog")


func set_colony_state(next_colony_state: ColonyState) -> void:
	colony_state = next_colony_state
	_rebuild("set_colony_state")


func refresh_buildings(reason: String) -> void:
	_rebuild(reason)


func has_warm_model(building_type: String) -> bool:
	return mesh_by_type.has(building_type) and material_by_type.has(building_type)


func warm_model(building_type: String) -> bool:
	if building_catalog == null:
		return false
	var model_config: Dictionary = building_catalog.get_model_config(building_type)
	if model_config.is_empty():
		return true
	return _mesh_for_building(building_type, model_config) != null and _material_for_building(building_type, model_config) != null


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": 0,
		"redraw_requests": rebuild_requests,
		"last_draw_usec": 0,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_rebuild_usec,
		"last_reason": last_reason,
	}


func _rebuild(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = 0

	for child in get_children():
		child.queue_free()

	if colony_state == null or building_catalog == null:
		last_rebuild_usec = Time.get_ticks_usec() - started
		return

	for building in colony_state.buildings:
		if _add_model_instance(building):
			var footprint: Vector2i = building.get("footprint", Vector2i.ONE)
			last_cells_processed += footprint.x * footprint.y

	last_rebuild_usec = Time.get_ticks_usec() - started


func _add_model_instance(building: Dictionary) -> bool:
	if building.get("landing_state", "landed") != "landed":
		return false
	var building_type: String = building.get("type", "")
	var model_config: Dictionary = building_catalog.get_model_config(building_type)
	if model_config.is_empty():
		return false

	var mesh := _mesh_for_building(building_type, model_config)
	if mesh == null:
		return false

	var instance := MeshInstance3D.new()
	instance.name = "Building3D_%s_%s" % [building_type, int(building.get("id", 0))]
	instance.mesh = mesh
	instance.material_override = _material_for_building(building_type, model_config)
	instance.layers = BUILDING_VISUAL_LAYER_MASK
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.transform = _building_transform(building, model_config)
	add_child(instance)
	return true


func _mesh_for_building(building_type: String, model_config: Dictionary) -> Mesh:
	if mesh_by_type.has(building_type):
		return mesh_by_type[building_type]
	var mesh_path: String = model_config.get("mesh_path", "")
	if mesh_path.is_empty() or not ResourceLoader.exists(mesh_path):
		push_warning("Missing 3D mesh for building '%s': %s" % [building_type, mesh_path])
		return null
	var mesh := load(mesh_path) as Mesh
	if mesh == null:
		push_warning("Could not load 3D mesh for building '%s': %s" % [building_type, mesh_path])
		return null
	# The generated OBJ assets contain many split per-triangle normals. Rebuild
	# only the normal arrays with an angle threshold, once per cached model, to
	# keep panel edges hard while removing triangulation from continuous shells.
	if String(model_config.get("normal_texture", "")).is_empty():
		mesh = smooth_mesh_normals(
			mesh,
			float(model_config.get("smooth_normal_angle_degrees", DEFAULT_SMOOTH_NORMAL_ANGLE_DEGREES))
		)
	mesh_by_type[building_type] = mesh
	return mesh


static func smooth_mesh_normals(source_mesh: Mesh, angle_degrees: float) -> Mesh:
	if source_mesh == null or source_mesh.get_blend_shape_count() > 0:
		return source_mesh
	var smoothed_mesh := ArrayMesh.new()
	var cosine_threshold := cos(deg_to_rad(clampf(angle_degrees, 0.0, 180.0)))

	for surface_index in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(surface_index)
		if arrays.size() != Mesh.ARRAY_MAX:
			return source_mesh
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		if vertices.is_empty() or normals.size() != vertices.size():
			return source_mesh

		var indices_by_position := {}
		for vertex_index in vertices.size():
			var vertex := vertices[vertex_index]
			var position_key := Vector3i(
				roundi(vertex.x * NORMAL_POSITION_QUANTIZATION),
				roundi(vertex.y * NORMAL_POSITION_QUANTIZATION),
				roundi(vertex.z * NORMAL_POSITION_QUANTIZATION)
			)
			var matching_indices: Array = indices_by_position.get(position_key, [])
			matching_indices.append(vertex_index)
			indices_by_position[position_key] = matching_indices

		var rebuilt_normals := normals.duplicate()
		for matching_indices: Array in indices_by_position.values():
			if matching_indices.size() < 2:
				continue
			for vertex_index: int in matching_indices:
				var reference_normal := normals[vertex_index].normalized()
				var normal_sum := Vector3.ZERO
				for matching_index: int in matching_indices:
					var candidate_normal := normals[matching_index].normalized()
					if reference_normal.dot(candidate_normal) >= cosine_threshold:
						normal_sum += candidate_normal
				if not normal_sum.is_zero_approx():
					rebuilt_normals[vertex_index] = normal_sum.normalized()
		arrays[Mesh.ARRAY_NORMAL] = rebuilt_normals

		var next_surface_index := smoothed_mesh.get_surface_count()
		smoothed_mesh.add_surface_from_arrays(
			source_mesh.surface_get_primitive_type(surface_index),
			arrays
		)
		smoothed_mesh.surface_set_material(next_surface_index, source_mesh.surface_get_material(surface_index))
		smoothed_mesh.surface_set_name(next_surface_index, source_mesh.surface_get_name(surface_index))

	smoothed_mesh.resource_name = "%s_SmoothByAngle" % source_mesh.resource_name
	return smoothed_mesh


func _material_for_building(building_type: String, model_config: Dictionary) -> StandardMaterial3D:
	if material_by_type.has(building_type):
		return material_by_type[building_type]

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true

	var diffuse_path: String = model_config.get("diffuse_texture", "")
	if not diffuse_path.is_empty() and ResourceLoader.exists(diffuse_path):
		material.albedo_texture = load(diffuse_path) as Texture2D

	var normal_path: String = model_config.get("normal_texture", "")
	if not normal_path.is_empty() and ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path) as Texture2D
		material.normal_scale = 1.0

	var roughness_path: String = model_config.get("roughness_texture", "")
	if not roughness_path.is_empty() and ResourceLoader.exists(roughness_path):
		material.roughness_texture = load(roughness_path) as Texture2D

	var metallic_path: String = model_config.get("metallic_texture", "")
	if not metallic_path.is_empty() and ResourceLoader.exists(metallic_path):
		material.metallic_texture = load(metallic_path) as Texture2D

	var emissive_path: String = model_config.get("emissive_texture", "")
	if not emissive_path.is_empty() and ResourceLoader.exists(emissive_path):
		material.emission_enabled = true
		material.emission_texture = load(emissive_path) as Texture2D
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 0.12

	material_by_type[building_type] = material
	return material


func _building_transform(building: Dictionary, model_config: Dictionary) -> Transform3D:
	var origin: Vector2i = building.get("origin", Vector2i.ZERO)
	var footprint: Vector2i = building.get("footprint", Vector2i.ONE)
	var orientation: String = building.get("orientation", BuildingCatalog.ORIENTATION_HORIZONTAL)
	var center := Vector3(
		float(origin.x) + (float(footprint.x) - 1.0) * 0.5,
		float(model_config.get("height_offset", 0.0)),
		float(origin.y) + (float(footprint.y) - 1.0) * 0.5
	)
	var rotation_y := float(model_config.get("rotation_y", 0.0))
	if orientation == BuildingCatalog.ORIENTATION_VERTICAL:
		rotation_y += PI * 0.5
	var scale: Vector3 = model_config.get("scale", Vector3.ONE)
	var basis := Basis(Vector3.UP, rotation_y).scaled(scale)
	return Transform3D(basis, center)
