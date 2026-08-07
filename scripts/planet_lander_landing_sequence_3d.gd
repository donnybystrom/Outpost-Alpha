extends Node3D

signal landed

const FLYING_MESH_PATH := "res://assets/3D/buildings/planet_lander_module_flying/base.obj"
const FLYING_DIFFUSE_PATH := "res://assets/3D/buildings/planet_lander_module_flying/texture_diffuse.png"
const FLYING_NORMAL_PATH := "res://assets/3D/buildings/planet_lander_module_flying/texture_normal.png"
const FLYING_ROUGHNESS_PATH := "res://assets/3D/buildings/planet_lander_module_flying/texture_roughness.png"
const FLYING_METALLIC_PATH := "res://assets/3D/buildings/planet_lander_module_flying/texture_metallic.png"

const LANDING_DURATION := 6.0
const START_HEIGHT := 14.0
const TOUCHDOWN_HEIGHT := 0.04
const MODEL_SCALE := Vector3(1.55, 1.55, 1.55)
const ENGINE_OFFSETS: Array[Vector3] = [
	Vector3(-0.52, 0.06, -1.08),
	Vector3(0.52, 0.06, -1.08),
	Vector3(-0.52, 0.06, 0.0),
	Vector3(0.52, 0.06, 0.0),
	Vector3(-0.52, 0.06, 1.08),
	Vector3(0.52, 0.06, 1.08),
]

var _landing_center := Vector3.ZERO
var _elapsed := 0.0
var _active := false
var _flying_model: MeshInstance3D
var _engine_particles: Array[GPUParticles3D] = []
var _engine_flames: Array[MeshInstance3D] = []
var _engine_light: OmniLight3D


func _ready() -> void:
	name = "PlanetLanderLandingSequence3D"
	visible = false
	set_process(false)


func prepare_landing(map_center: Vector2) -> void:
	_active = false
	_elapsed = 0.0
	_landing_center = Vector3(map_center.x, TOUCHDOWN_HEIGHT, map_center.y)
	_clear_visuals()
	_build_flying_model()
	_build_engine_effects()
	position = _landing_center + Vector3(0.0, START_HEIGHT, 0.0)
	visible = false
	set_process(false)


func start_landing() -> bool:
	if _flying_model == null or _flying_model.mesh == null:
		push_warning("Planet Lander landing could not start because the flying model is unavailable.")
		return false
	_elapsed = 0.0
	_active = true
	visible = true
	set_process(true)
	for particles in _engine_particles:
		particles.emitting = true
		particles.restart()
	return true


func finish_landing_immediately() -> void:
	if _active:
		_complete_landing()


func is_landing() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed = minf(_elapsed + delta, LANDING_DURATION)
	var progress := _elapsed / LANDING_DURATION
	var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
	var remaining := 1.0 - progress
	var lateral_drift := Vector3(
		sin(_elapsed * 1.35) * 0.13 * remaining,
		0.0,
		cos(_elapsed * 1.1) * 0.1 * remaining
	)
	position = _landing_center + lateral_drift + Vector3.UP * lerpf(START_HEIGHT, 0.0, eased_progress)
	rotation.y = sin(_elapsed * 0.55) * 0.025 * remaining
	_update_engine_effect(progress)
	if _elapsed >= LANDING_DURATION:
		_complete_landing()


func _build_flying_model() -> void:
	if not ResourceLoader.exists(FLYING_MESH_PATH):
		push_warning("Missing Planet Lander flying mesh: %s" % FLYING_MESH_PATH)
		return
	var mesh := load(FLYING_MESH_PATH) as Mesh
	if mesh == null:
		push_warning("Could not load Planet Lander flying mesh: %s" % FLYING_MESH_PATH)
		return
	_flying_model = MeshInstance3D.new()
	_flying_model.name = "PlanetLanderFlyingModel"
	_flying_model.mesh = mesh
	_flying_model.material_override = _build_flying_material()
	_flying_model.scale = MODEL_SCALE
	add_child(_flying_model)


func _build_flying_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(FLYING_DIFFUSE_PATH):
		material.albedo_texture = load(FLYING_DIFFUSE_PATH) as Texture2D
	if ResourceLoader.exists(FLYING_NORMAL_PATH):
		material.normal_enabled = true
		material.normal_texture = load(FLYING_NORMAL_PATH) as Texture2D
	if ResourceLoader.exists(FLYING_ROUGHNESS_PATH):
		material.roughness_texture = load(FLYING_ROUGHNESS_PATH) as Texture2D
	if ResourceLoader.exists(FLYING_METALLIC_PATH):
		material.metallic_texture = load(FLYING_METALLIC_PATH) as Texture2D
	return material


func _build_engine_effects() -> void:
	var outer_flame_mesh := CylinderMesh.new()
	outer_flame_mesh.top_radius = 0.13
	outer_flame_mesh.bottom_radius = 0.018
	outer_flame_mesh.height = 1.75
	outer_flame_mesh.radial_segments = 8
	outer_flame_mesh.material = _build_flame_material(Color(1.0, 0.18, 0.015, 0.82), Color(1.0, 0.12, 0.01), 4.8)
	var inner_flame_mesh := CylinderMesh.new()
	inner_flame_mesh.top_radius = 0.072
	inner_flame_mesh.bottom_radius = 0.008
	inner_flame_mesh.height = 1.18
	inner_flame_mesh.radial_segments = 8
	inner_flame_mesh.material = _build_flame_material(Color(1.0, 0.9, 0.42, 0.94), Color(1.0, 0.52, 0.08), 7.0)

	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.065, 0.14)
	var flame_material := StandardMaterial3D.new()
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_material.vertex_color_use_as_albedo = true
	flame_material.albedo_color = Color(1.0, 0.62, 0.12, 0.9)
	flame_material.emission_enabled = true
	flame_material.emission = Color(1.0, 0.24, 0.025)
	flame_material.emission_energy_multiplier = 5.0
	flame_mesh.material = flame_material

	var flame_gradient := Gradient.new()
	flame_gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.72, 1.0])
	flame_gradient.colors = PackedColorArray([
		Color(1.0, 0.97, 0.72, 1.0),
		Color(1.0, 0.55, 0.08, 0.95),
		Color(0.95, 0.12, 0.015, 0.58),
		Color(0.18, 0.025, 0.01, 0.0),
	])
	var flame_ramp := GradientTexture1D.new()
	flame_ramp.gradient = flame_gradient

	for engine_index in ENGINE_OFFSETS.size():
		var outer_flame := MeshInstance3D.new()
		outer_flame.name = "LandingFlameOuter%d" % (engine_index + 1)
		outer_flame.mesh = outer_flame_mesh
		outer_flame.position = ENGINE_OFFSETS[engine_index] + Vector3(0.0, -0.82, 0.0)
		add_child(outer_flame)
		_engine_flames.append(outer_flame)

		var inner_flame := MeshInstance3D.new()
		inner_flame.name = "LandingFlameInner%d" % (engine_index + 1)
		inner_flame.mesh = inner_flame_mesh
		inner_flame.position = ENGINE_OFFSETS[engine_index] + Vector3(0.0, -0.52, 0.0)
		add_child(inner_flame)
		_engine_flames.append(inner_flame)

		var process_material := ParticleProcessMaterial.new()
		process_material.direction = Vector3.DOWN
		process_material.spread = 12.0
		process_material.initial_velocity_min = 3.5
		process_material.initial_velocity_max = 7.0
		process_material.gravity = Vector3(0.0, -4.0, 0.0)
		process_material.scale_min = 0.4
		process_material.scale_max = 1.0
		process_material.color_ramp = flame_ramp

		var particles := GPUParticles3D.new()
		particles.name = "LandingJet%d" % (engine_index + 1)
		particles.position = ENGINE_OFFSETS[engine_index]
		particles.amount = 48
		particles.lifetime = 0.62
		particles.randomness = 0.35
		particles.fixed_fps = 30
		particles.local_coords = false
		particles.visibility_aabb = AABB(Vector3(-1.5, -9.0, -1.5), Vector3(3.0, 10.0, 3.0))
		particles.process_material = process_material
		particles.draw_pass_1 = flame_mesh
		particles.emitting = false
		add_child(particles)
		_engine_particles.append(particles)

	_engine_light = OmniLight3D.new()
	_engine_light.name = "LandingJetLight"
	_engine_light.position = Vector3(0.0, -0.4, 0.0)
	_engine_light.light_color = Color(1.0, 0.36, 0.08)
	_engine_light.light_energy = 4.0
	_engine_light.omni_range = 7.0
	_engine_light.shadow_enabled = false
	add_child(_engine_light)


func _build_flame_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material


func _update_engine_effect(progress: float) -> void:
	var touchdown_fade := clampf((1.0 - progress) / 0.08, 0.0, 1.0)
	var pulse := 0.88 + sin(_elapsed * 24.0) * 0.12
	for flame_index in _engine_flames.size():
		var staggered_pulse := 0.9 + sin(_elapsed * 22.0 + float(flame_index) * 0.73) * 0.1
		_engine_flames[flame_index].scale = Vector3(1.0, staggered_pulse * touchdown_fade, 1.0)
	for particles in _engine_particles:
		particles.speed_scale = pulse
		particles.amount_ratio = touchdown_fade
	if _engine_light != null:
		_engine_light.light_energy = 4.0 * pulse * touchdown_fade


func _complete_landing() -> void:
	_active = false
	set_process(false)
	for particles in _engine_particles:
		particles.emitting = false
	visible = false
	position = _landing_center
	rotation = Vector3.ZERO
	landed.emit()


func _clear_visuals() -> void:
	_flying_model = null
	_engine_particles.clear()
	_engine_flames.clear()
	_engine_light = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
