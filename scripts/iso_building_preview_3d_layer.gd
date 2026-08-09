extends Node3D

const BuildingCatalog := preload("res://scripts/building_catalog.gd")
const Building3DLayer := preload("res://scripts/iso_building_3d_layer.gd")
const BUILDING_VISUAL_LAYER_MASK := 1 << 1

const PREVIEW_ALPHA_VALID := 0.52
const PREVIEW_ALPHA_INVALID := 0.34
const FOOTPRINT_HEIGHT := 0.055
const FOOTPRINT_WIDTH := 0.045
const FOOTPRINT_Y := 0.075
const FOOTPRINT_VALID_COLOR := Color(0.25, 1.0, 0.32, 0.82)
const FOOTPRINT_INVALID_COLOR := Color(1.0, 0.15, 0.12, 0.86)

var building_catalog = BuildingCatalog.new()
var mesh_by_type := {}
var material_by_key := {}
var preview_instance: MeshInstance3D
var footprint_root: Node3D
var footprint_material_by_valid := {}
var _current_key := ""
var _current_footprint_key := ""


func _ready() -> void:
	name = "BuildingPreview3DLayer"


func set_building_catalog(next_building_catalog) -> void:
	if next_building_catalog == null:
		return
	building_catalog = next_building_catalog
	mesh_by_type.clear()
	material_by_key.clear()
	clear_preview()


func clear_preview() -> void:
	_current_key = ""
	_current_footprint_key = ""
	if preview_instance != null:
		preview_instance.queue_free()
		preview_instance = null
	_clear_footprint()


func has_warm_model(building_type: String) -> bool:
	return mesh_by_type.has(building_type) and material_by_key.has("%s:true" % building_type) and material_by_key.has("%s:false" % building_type)


func warm_model(building_type: String) -> bool:
	if building_catalog == null:
		return false
	var model_config: Dictionary = building_catalog.get_model_config(building_type)
	if model_config.is_empty():
		return true
	if _mesh_for_building(building_type, model_config) == null:
		return false
	_preview_material_for_building(building_type, model_config, true)
	_preview_material_for_building(building_type, model_config, false)
	return true


func set_preview(building_type: String, origin: Vector2i, orientation: String, valid: bool, placement_feedback: Array[Dictionary] = []) -> void:
	if building_catalog == null or building_type.is_empty():
		clear_preview()
		return

	var model_config: Dictionary = building_catalog.get_model_config(building_type)
	if model_config.is_empty():
		clear_preview()
		return

	var footprint: Vector2i = building_catalog.get_footprint(building_type, orientation)
	var next_key := "%s:%s:%s:%s:%s" % [building_type, origin.x, origin.y, orientation, valid]
	if next_key == _current_key:
		return

	var mesh := _mesh_for_building(building_type, model_config)
	if mesh == null:
		clear_preview()
		return

	if preview_instance == null:
		preview_instance = MeshInstance3D.new()
		preview_instance.name = "BuildingPlacementPreview3D"
		preview_instance.layers = BUILDING_VISUAL_LAYER_MASK
		preview_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(preview_instance)

	_current_key = next_key
	preview_instance.mesh = mesh
	preview_instance.material_override = _preview_material_for_building(building_type, model_config, valid)
	preview_instance.transform = _building_transform(origin, footprint, orientation, model_config)
	_set_footprint(placement_feedback)


func _mesh_for_building(building_type: String, model_config: Dictionary) -> Mesh:
	if mesh_by_type.has(building_type):
		return mesh_by_type[building_type]
	var mesh_path: String = model_config.get("mesh_path", "")
	if mesh_path.is_empty() or not ResourceLoader.exists(mesh_path):
		return null
	var mesh := load(mesh_path) as Mesh
	if mesh == null:
		return null
	if String(model_config.get("normal_texture", "")).is_empty():
		mesh = Building3DLayer.smooth_mesh_normals(
			mesh,
			float(model_config.get("smooth_normal_angle_degrees", Building3DLayer.DEFAULT_SMOOTH_NORMAL_ANGLE_DEGREES))
		)
	mesh_by_type[building_type] = mesh
	return mesh


func _preview_material_for_building(building_type: String, model_config: Dictionary, valid: bool) -> StandardMaterial3D:
	var key := "%s:%s" % [building_type, valid]
	if material_by_key.has(key):
		return material_by_key[key]

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 1.0, 0.78, PREVIEW_ALPHA_VALID) if valid else Color(1.0, 0.35, 0.35, PREVIEW_ALPHA_INVALID)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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

	material_by_key[key] = material
	return material


func _building_transform(origin: Vector2i, footprint: Vector2i, orientation: String, model_config: Dictionary) -> Transform3D:
	var center := Vector3(
		float(origin.x) + (float(footprint.x) - 1.0) * 0.5,
		float(model_config.get("height_offset", 0.0)) + 0.015,
		float(origin.y) + (float(footprint.y) - 1.0) * 0.5
	)
	var rotation_y := float(model_config.get("rotation_y", 0.0))
	if orientation == BuildingCatalog.ORIENTATION_VERTICAL:
		rotation_y += PI * 0.5
	var scale: Vector3 = model_config.get("scale", Vector3.ONE)
	var basis := Basis(Vector3.UP, rotation_y).scaled(scale)
	return Transform3D(basis, center)


func _set_footprint(placement_feedback: Array[Dictionary]) -> void:
	var next_key := _footprint_key(placement_feedback)
	if next_key == _current_footprint_key:
		return
	_current_footprint_key = next_key
	_clear_footprint()
	if placement_feedback.is_empty():
		return

	footprint_root = Node3D.new()
	footprint_root.name = "BuildingPlacementFootprint3D"
	add_child(footprint_root)
	for feedback in placement_feedback:
		var tile: Vector2i = feedback.get("tile", Vector2i(-1, -1))
		_add_tile_outline(tile, bool(feedback.get("valid", false)))


func _clear_footprint() -> void:
	if footprint_root != null:
		footprint_root.queue_free()
		footprint_root = null


func _add_tile_outline(tile: Vector2i, valid: bool) -> void:
	var corners := [
		Vector3(float(tile.x) - 0.5, FOOTPRINT_Y, float(tile.y) - 0.5),
		Vector3(float(tile.x) + 0.5, FOOTPRINT_Y, float(tile.y) - 0.5),
		Vector3(float(tile.x) + 0.5, FOOTPRINT_Y, float(tile.y) + 0.5),
		Vector3(float(tile.x) - 0.5, FOOTPRINT_Y, float(tile.y) + 0.5),
	]
	for index in corners.size():
		_add_edge(corners[index], corners[(index + 1) % corners.size()], valid)


func _add_edge(start: Vector3, end: Vector3, valid: bool) -> void:
	if footprint_root == null:
		return
	var edge := MeshInstance3D.new()
	edge.name = "FootprintEdge"
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.mesh = _edge_mesh(start.distance_to(end))
	edge.material_override = _footprint_material(valid)
	var midpoint := (start + end) * 0.5
	var direction := end - start
	var yaw := atan2(direction.x, direction.z)
	edge.transform = Transform3D(Basis(Vector3.UP, yaw), midpoint)
	footprint_root.add_child(edge)


func _edge_mesh(length: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(FOOTPRINT_WIDTH, FOOTPRINT_HEIGHT, length + FOOTPRINT_WIDTH)
	return mesh


func _footprint_material(valid: bool) -> StandardMaterial3D:
	if footprint_material_by_valid.has(valid):
		return footprint_material_by_valid[valid]
	var material := StandardMaterial3D.new()
	material.albedo_color = FOOTPRINT_VALID_COLOR if valid else FOOTPRINT_INVALID_COLOR
	material.emission_enabled = true
	material.emission = FOOTPRINT_VALID_COLOR if valid else FOOTPRINT_INVALID_COLOR
	material.emission_energy_multiplier = 0.55
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	footprint_material_by_valid[valid] = material
	return material


func _footprint_key(placement_feedback: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for feedback in placement_feedback:
		var tile: Vector2i = feedback.get("tile", Vector2i(-1, -1))
		parts.append("%s,%s,%s" % [tile.x, tile.y, feedback.get("valid", false)])
	return "|".join(parts)
