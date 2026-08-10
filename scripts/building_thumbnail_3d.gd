extends SubViewportContainer

const BuildingCatalog := preload("res://scripts/building_catalog.gd")
const Building3DLayer := preload("res://scripts/iso_building_3d_layer.gd")

const THUMBNAIL_SIZE := Vector2i(256, 144)
const MODEL_LAYER_MASK := 1

static var _mesh_cache: Dictionary = {}
static var _material_cache: Dictionary = {}

var building_catalog = BuildingCatalog.new()
var building_type := ""
var viewport: SubViewport
var camera: Camera3D
var model_root: Node3D


func setup(next_building_type: String, render_size := THUMBNAIL_SIZE) -> void:
	building_type = next_building_type
	custom_minimum_size = Vector2(render_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	# Headless smoke tests do not own a usable 3D render target on macOS.
	# Keep the layout node present, but only create the projection stage when a
	# display-backed renderer is available.
	if DisplayServer.get_name() == "headless":
		return

	viewport = SubViewport.new()
	viewport.name = "BuildingThumbnailViewport"
	viewport.size = render_size
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	_build_stage()
	set_building_type(building_type)


func set_building_type(next_building_type: String) -> void:
	building_type = next_building_type
	if viewport == null or model_root == null:
		return

	for child in model_root.get_children():
		child.queue_free()

	var model_config: Dictionary = building_catalog.get_model_config(building_type)
	if model_config.is_empty():
		return

	var mesh := _mesh_for_building(building_type, model_config)
	if mesh == null:
		return

	var instance := MeshInstance3D.new()
	instance.name = "Thumbnail_%s" % building_type
	instance.mesh = mesh
	instance.material_override = _material_for_building(building_type, model_config)
	instance.layers = MODEL_LAYER_MASK
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var scale: Vector3 = model_config.get("scale", Vector3.ONE)
	var rotation_y := float(model_config.get("rotation_y", 0.0))
	var basis := Basis(Vector3.UP, rotation_y).scaled(scale)
	var source_bounds := mesh.get_aabb()
	var centered_origin := -(basis * source_bounds.get_center())
	instance.transform = Transform3D(basis, centered_origin)
	model_root.add_child(instance)

	_frame_camera(_transformed_size(source_bounds, basis))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_stage() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.025, 0.03, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color8(93, 118, 126)
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	viewport.add_child(environment_node)

	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	viewport.add_child(model_root)

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color8(255, 226, 188)
	key_light.light_energy = 1.35
	key_light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key_light.shadow_enabled = false
	key_light.light_cull_mask = MODEL_LAYER_MASK
	viewport.add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color8(90, 218, 232)
	rim_light.light_energy = 0.42
	rim_light.rotation_degrees = Vector3(-28.0, 145.0, 0.0)
	rim_light.shadow_enabled = false
	rim_light.light_cull_mask = MODEL_LAYER_MASK
	viewport.add_child(rim_light)

	camera = Camera3D.new()
	camera.name = "ThumbnailCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.cull_mask = MODEL_LAYER_MASK
	camera.current = true
	viewport.add_child(camera)


func _frame_camera(model_size: Vector3) -> void:
	if camera == null or viewport == null:
		return

	var aspect := float(viewport.size.x) / maxf(float(viewport.size.y), 1.0)
	var projected_width := (model_size.x + model_size.z) * 0.72
	var projected_height := model_size.y + (model_size.x + model_size.z) * 0.28
	camera.size = maxf(projected_height, projected_width / aspect) * 1.16
	camera.look_at_from_position(Vector3(8.0, 6.4, 8.0), Vector3.ZERO, Vector3.UP)


func _transformed_size(bounds: AABB, basis: Basis) -> Vector3:
	var center := bounds.get_center()
	var min_corner := Vector3(INF, INF, INF)
	var max_corner := Vector3(-INF, -INF, -INF)
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				var transformed := basis * (Vector3(x, y, z) - center)
				min_corner = min_corner.min(transformed)
				max_corner = max_corner.max(transformed)
	return max_corner - min_corner


func _mesh_for_building(type: String, model_config: Dictionary) -> Mesh:
	if _mesh_cache.has(type):
		return _mesh_cache[type]
	var mesh_path: String = model_config.get("mesh_path", "")
	if mesh_path.is_empty() or not ResourceLoader.exists(mesh_path):
		push_warning("Missing thumbnail mesh for building '%s': %s" % [type, mesh_path])
		return null
	var mesh := load(mesh_path) as Mesh
	if mesh == null:
		return null
	if String(model_config.get("normal_texture", "")).is_empty():
		mesh = Building3DLayer.smooth_mesh_normals(
			mesh,
			float(model_config.get("smooth_normal_angle_degrees", Building3DLayer.DEFAULT_SMOOTH_NORMAL_ANGLE_DEGREES))
		)
	_mesh_cache[type] = mesh
	return mesh


func _material_for_building(type: String, model_config: Dictionary) -> StandardMaterial3D:
	if _material_cache.has(type):
		return _material_cache[type]

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true

	var diffuse_path: String = model_config.get("diffuse_texture", "")
	if not diffuse_path.is_empty() and ResourceLoader.exists(diffuse_path):
		material.albedo_texture = load(diffuse_path) as Texture2D

	var normal_path: String = model_config.get("normal_texture", "")
	if not normal_path.is_empty() and ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path) as Texture2D

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

	_material_cache[type] = material
	return material
