extends Node3D

signal landed

const Building3DLayer := preload("res://scripts/iso_building_3d_layer.gd")

const FLYING_MESH_PATH := "res://assets/3D/buildings/planet_lander_module_flying_2/base.obj"
const FLYING_DIFFUSE_PATH := "res://assets/3D/buildings/planet_lander_module_flying_2/texture_diffuse.png"

const LANDING_DURATION := 6.0
const START_HEIGHT := 14.0
const TOUCHDOWN_HEIGHT := 0.04
const RUNTIME_CONFIG_PATH := "res://config/runtime.cfg"
const RUNTIME_CONFIG_SECTION := "planet_lander_tuning"
const DEFAULT_MODEL_UNIFORM_SCALE := 0.862989
const DEFAULT_MODEL_OFFSET_UP := 0.44
const DEFAULT_MODEL_OFFSET_SCREEN_RIGHT := 0.14
# Used only to keep the engine effects proportional to the flying model.
const ENGINE_REFERENCE_MODEL_SCALE := 1.55
const DEFAULT_SCREEN_RIGHT_AXIS := Vector3(0.707106781, 0.0, -0.707106781)
const AUDIO_MIX_RATE := 22050.0
const TOUCHDOWN_AUDIO_DURATION := 2.25
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
var _engine_audio_player: AudioStreamPlayer3D
var _engine_audio_playback: AudioStreamGeneratorPlayback
var _touchdown_audio_player: AudioStreamPlayer3D
var _engine_audio_phase_low := 0.0
var _engine_audio_phase_mid := 0.0
var _engine_audio_phase_turbine := 0.0
var _engine_filtered_noise := 0.0
var _engine_audio_rng := RandomNumberGenerator.new()

# Public for focused smoke tests and runtime diagnostics. These values are
# refreshed from runtime.cfg on every prepare_landing() call.
var runtime_config_path := RUNTIME_CONFIG_PATH
var model_uniform_scale := DEFAULT_MODEL_UNIFORM_SCALE
var model_offset_up := DEFAULT_MODEL_OFFSET_UP
var model_offset_screen_right := DEFAULT_MODEL_OFFSET_SCREEN_RIGHT
var model_visual_offset := Vector3.UP * DEFAULT_MODEL_OFFSET_UP \
	+ DEFAULT_SCREEN_RIGHT_AXIS * DEFAULT_MODEL_OFFSET_SCREEN_RIGHT
var engine_effect_scale := DEFAULT_MODEL_UNIFORM_SCALE / ENGINE_REFERENCE_MODEL_SCALE


func _ready() -> void:
	name = "PlanetLanderLandingSequence3D"
	visible = false
	set_process(false)


func prepare_landing(map_center: Vector2) -> void:
	_active = false
	_elapsed = 0.0
	_landing_center = Vector3(map_center.x, TOUCHDOWN_HEIGHT, map_center.y)
	_reload_runtime_tuning()
	_clear_visuals()
	_build_flying_model()
	_build_engine_effects()
	_build_landing_audio()
	position = _landing_center + Vector3(0.0, START_HEIGHT, 0.0)
	visible = false
	set_process(false)


func _reload_runtime_tuning() -> void:
	model_uniform_scale = DEFAULT_MODEL_UNIFORM_SCALE
	model_offset_up = DEFAULT_MODEL_OFFSET_UP
	model_offset_screen_right = DEFAULT_MODEL_OFFSET_SCREEN_RIGHT

	var config := ConfigFile.new()
	var load_error := config.load(runtime_config_path)
	if load_error == OK:
		model_uniform_scale = clampf(float(config.get_value(
			RUNTIME_CONFIG_SECTION,
			"flying_model_scale",
			DEFAULT_MODEL_UNIFORM_SCALE
		)), 0.1, 4.0)
		model_offset_up = clampf(float(config.get_value(
			RUNTIME_CONFIG_SECTION,
			"flying_offset_up",
			DEFAULT_MODEL_OFFSET_UP
		)), -5.0, 5.0)
		model_offset_screen_right = clampf(float(config.get_value(
			RUNTIME_CONFIG_SECTION,
			"flying_offset_screen_right",
			DEFAULT_MODEL_OFFSET_SCREEN_RIGHT
		)), -5.0, 5.0)
	else:
		push_warning("Could not reload Planet Lander tuning from %s (error %d); using defaults." % [
			runtime_config_path,
			load_error,
		])

	model_visual_offset = Vector3.UP * model_offset_up \
		+ DEFAULT_SCREEN_RIGHT_AXIS * model_offset_screen_right
	engine_effect_scale = model_uniform_scale / ENGINE_REFERENCE_MODEL_SCALE
	print("Planet Lander tuning reloaded: scale=%.6f up=%.3f right=%.3f" % [
		model_uniform_scale,
		model_offset_up,
		model_offset_screen_right,
	])


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
	_start_engine_audio()
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
	_fill_engine_audio(progress)
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
	mesh = Building3DLayer.smooth_mesh_normals(
		mesh,
		Building3DLayer.DEFAULT_SMOOTH_NORMAL_ANGLE_DEGREES
	)
	_flying_model = MeshInstance3D.new()
	_flying_model.name = "PlanetLanderFlyingModel"
	_flying_model.layers = Building3DLayer.BUILDING_VISUAL_LAYER_MASK
	_flying_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_flying_model.mesh = mesh
	_flying_model.material_override = _build_flying_material()
	_flying_model.scale = Vector3.ONE * model_uniform_scale
	_flying_model.position = model_visual_offset
	add_child(_flying_model)


func _build_flying_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	if ResourceLoader.exists(FLYING_DIFFUSE_PATH):
		material.albedo_texture = load(FLYING_DIFFUSE_PATH) as Texture2D
	return material


func _build_engine_effects() -> void:
	var outer_flame_mesh := CylinderMesh.new()
	outer_flame_mesh.top_radius = 0.13 * engine_effect_scale
	outer_flame_mesh.bottom_radius = 0.018 * engine_effect_scale
	outer_flame_mesh.height = 1.75 * engine_effect_scale
	outer_flame_mesh.radial_segments = 8
	outer_flame_mesh.material = _build_flame_material(Color(1.0, 0.18, 0.015, 0.82), Color(1.0, 0.12, 0.01), 4.8)
	var inner_flame_mesh := CylinderMesh.new()
	inner_flame_mesh.top_radius = 0.072 * engine_effect_scale
	inner_flame_mesh.bottom_radius = 0.008 * engine_effect_scale
	inner_flame_mesh.height = 1.18 * engine_effect_scale
	inner_flame_mesh.radial_segments = 8
	inner_flame_mesh.material = _build_flame_material(Color(1.0, 0.9, 0.42, 0.94), Color(1.0, 0.52, 0.08), 7.0)

	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.065, 0.14) * engine_effect_scale
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
		var engine_offset := ENGINE_OFFSETS[engine_index] * engine_effect_scale + model_visual_offset
		var outer_flame := MeshInstance3D.new()
		outer_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outer_flame.name = "LandingFlameOuter%d" % (engine_index + 1)
		outer_flame.mesh = outer_flame_mesh
		outer_flame.position = engine_offset + Vector3(0.0, -0.82 * engine_effect_scale, 0.0)
		add_child(outer_flame)
		_engine_flames.append(outer_flame)

		var inner_flame := MeshInstance3D.new()
		inner_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inner_flame.name = "LandingFlameInner%d" % (engine_index + 1)
		inner_flame.mesh = inner_flame_mesh
		inner_flame.position = engine_offset + Vector3(0.0, -0.52 * engine_effect_scale, 0.0)
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
		particles.position = engine_offset
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
	_engine_light.position = model_visual_offset + Vector3(0.0, -0.4 * engine_effect_scale, 0.0)
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


func _build_landing_audio() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = AUDIO_MIX_RATE
	generator.buffer_length = 0.4
	_engine_audio_player = AudioStreamPlayer3D.new()
	_engine_audio_player.name = "LandingEngineAudio"
	_engine_audio_player.stream = generator
	# The orthographic camera orbits roughly 180 world units from its target, so
	# landing audio needs a broad 3D falloff while retaining directional panning.
	_engine_audio_player.unit_size = 90.0
	_engine_audio_player.max_distance = 400.0
	_engine_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_engine_audio_player.panning_strength = 0.72
	add_child(_engine_audio_player)

	_touchdown_audio_player = AudioStreamPlayer3D.new()
	_touchdown_audio_player.name = "LandingTouchdownAudio"
	_touchdown_audio_player.stream = _build_touchdown_audio_stream()
	_touchdown_audio_player.unit_size = 110.0
	_touchdown_audio_player.max_distance = 400.0
	_touchdown_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_touchdown_audio_player.panning_strength = 0.65
	add_child(_touchdown_audio_player)


func _start_engine_audio() -> void:
	if _engine_audio_player == null:
		return
	_engine_audio_phase_low = 0.0
	_engine_audio_phase_mid = 0.0
	_engine_audio_phase_turbine = 0.0
	_engine_filtered_noise = 0.0
	_engine_audio_rng.seed = 0x1A4D3E
	_engine_audio_player.play()
	_engine_audio_playback = _engine_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_fill_engine_audio(0.0)


func _fill_engine_audio(progress: float) -> void:
	if _engine_audio_playback == null:
		return
	var frames_available := _engine_audio_playback.get_frames_available()
	if frames_available <= 0:
		return
	var frames := PackedVector2Array()
	frames.resize(frames_available)
	var proximity := smoothstep(0.0, 1.0, progress)
	var gain := lerpf(0.11, 0.34, proximity)
	var low_frequency := lerpf(36.0, 49.0, proximity)
	var mid_frequency := lerpf(67.0, 83.0, proximity)
	var turbine_frequency := lerpf(138.0, 186.0, proximity)
	for frame_index in frames_available:
		_engine_audio_phase_low = fmod(_engine_audio_phase_low + TAU * low_frequency / AUDIO_MIX_RATE, TAU)
		_engine_audio_phase_mid = fmod(_engine_audio_phase_mid + TAU * mid_frequency / AUDIO_MIX_RATE, TAU)
		_engine_audio_phase_turbine = fmod(_engine_audio_phase_turbine + TAU * turbine_frequency / AUDIO_MIX_RATE, TAU)
		var raw_noise := _engine_audio_rng.randf_range(-1.0, 1.0)
		_engine_filtered_noise = lerpf(_engine_filtered_noise, raw_noise, 0.055)
		var combustion := raw_noise * 0.075 + _engine_filtered_noise * 0.32
		var rumble := sin(_engine_audio_phase_low) * 0.52 + sin(_engine_audio_phase_mid) * 0.24
		var turbine := sin(_engine_audio_phase_turbine) * (0.08 + proximity * 0.06)
		var pulse := 0.93 + sin(_engine_audio_phase_low * 0.23) * 0.07
		var sample := clampf((rumble + turbine + combustion) * gain * pulse, -0.92, 0.92)
		frames[frame_index] = Vector2(sample, sample)
	_engine_audio_playback.push_buffer(frames)


func _build_touchdown_audio_stream() -> AudioStreamWAV:
	var frame_count := ceili(AUDIO_MIX_RATE * TOUCHDOWN_AUDIO_DURATION)
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x70AC4D0
	var thud_phase := 0.0
	var hiss_filter_left := 0.0
	var hiss_filter_right := 0.0
	for frame_index in frame_count:
		var time := float(frame_index) / AUDIO_MIX_RATE
		var impact_progress := clampf(time / 0.5, 0.0, 1.0)
		var impact_frequency := lerpf(61.0, 31.0, impact_progress)
		thud_phase += TAU * impact_frequency / AUDIO_MIX_RATE
		var impact_envelope := exp(-time * 7.8)
		var thud := sin(thud_phase) * impact_envelope * 0.72
		var body_resonance := (
			sin(TAU * 174.0 * time) * 0.22
			+ sin(TAU * 286.0 * time) * 0.11
		) * exp(-time * 11.5)
		var vent_time := maxf(0.0, time - 0.075)
		var vent_attack := smoothstep(0.0, 0.045, vent_time)
		var vent_envelope := vent_attack * exp(-vent_time * 2.15)
		var noise_left := rng.randf_range(-1.0, 1.0)
		var noise_right := rng.randf_range(-1.0, 1.0)
		hiss_filter_left = lerpf(hiss_filter_left, noise_left, 0.065)
		hiss_filter_right = lerpf(hiss_filter_right, noise_right, 0.065)
		var hiss_pulse := 0.82 + sin(TAU * 7.5 * vent_time) * 0.18
		var hiss_left := (noise_left - hiss_filter_left * 0.7) * vent_envelope * hiss_pulse * 0.32
		var hiss_right := (noise_right - hiss_filter_right * 0.7) * vent_envelope * hiss_pulse * 0.32
		var pressure_release := sin(TAU * 24.0 * vent_time) * vent_envelope * 0.11
		var left_sample := clampf(thud + body_resonance + pressure_release + hiss_left, -0.98, 0.98)
		var right_sample := clampf(thud + body_resonance + pressure_release + hiss_right, -0.98, 0.98)
		pcm.encode_s16(frame_index * 4, roundi(left_sample * 32767.0))
		pcm.encode_s16(frame_index * 4 + 2, roundi(right_sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(AUDIO_MIX_RATE)
	stream.stereo = true
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


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
	if _engine_audio_player != null:
		_engine_audio_player.stop()
	_engine_audio_playback = null
	if _touchdown_audio_player != null:
		_touchdown_audio_player.play()
	visible = false
	_release_flight_visuals()
	position = _landing_center
	rotation = Vector3.ZERO
	landed.emit()


func _release_flight_visuals() -> void:
	if _flying_model != null:
		_flying_model.queue_free()
		_flying_model = null
	for particles in _engine_particles:
		particles.queue_free()
	_engine_particles.clear()
	for flame in _engine_flames:
		flame.queue_free()
	_engine_flames.clear()
	if _engine_light != null:
		_engine_light.queue_free()
		_engine_light = null


func _clear_visuals() -> void:
	_flying_model = null
	_engine_particles.clear()
	_engine_flames.clear()
	_engine_light = null
	_engine_audio_player = null
	_engine_audio_playback = null
	_touchdown_audio_player = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
