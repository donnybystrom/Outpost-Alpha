extends SceneTree

const BuildingCatalog := preload("res://scripts/building_catalog.gd")
const Building3DLayer := preload("res://scripts/iso_building_3d_layer.gd")
const PlanetLanderLandingSequence3D := preload("res://scripts/planet_lander_landing_sequence_3d.gd")


func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	main._build_world_lighting()

	if main.building_light == null:
		_fail("Main should create a dedicated building light.")
		return
	if main.building_light.shadow_enabled:
		_fail("Building light must remain shadowless.")
		return
	if main.building_light.light_cull_mask != Building3DLayer.BUILDING_VISUAL_LAYER_MASK:
		_fail("Building light should affect only the building visual layer.")
		return
	if not main.sun_light.shadow_enabled:
		_fail("World sun should remain responsible for cast shadows.")
		return
	if (main.sun_light.light_cull_mask & Building3DLayer.BUILDING_VISUAL_LAYER_MASK) == 0:
		_fail("World sun should still illuminate the building visual layer.")
		return

	var building_layer := Building3DLayer.new()
	root.add_child(building_layer)
	var building := {
		"id": 1,
		"type": BuildingCatalog.BUILDING_LIVING_QUARTERS,
		"origin": Vector2i.ZERO,
		"footprint": Vector2i(2, 3),
		"orientation": BuildingCatalog.ORIENTATION_HORIZONTAL,
		"landing_state": "landed",
	}
	if not building_layer._add_model_instance(building):
		_fail("Lighting test could not create a building model.")
		return
	var instance := building_layer.get_child(0) as MeshInstance3D
	if instance == null or instance.layers != Building3DLayer.BUILDING_VISUAL_LAYER_MASK:
		_fail("Building meshes should use the dedicated building visual layer.")
		return
	if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		_fail("Building meshes should still cast world-sun shadows.")
		return
	var material := instance.material_override as StandardMaterial3D
	if material == null or not material.disable_receive_shadows:
		_fail("Building materials should not receive self-shadow artifacts.")
		return

	var landing_sequence := PlanetLanderLandingSequence3D.new()
	root.add_child(landing_sequence)
	landing_sequence.prepare_landing(Vector2.ZERO)
	var flying_model := landing_sequence.get_node_or_null("PlanetLanderFlyingModel") as MeshInstance3D
	if flying_model == null or flying_model.layers != Building3DLayer.BUILDING_VISUAL_LAYER_MASK:
		_fail("Flying Planet Lander should use the building visual layer.")
		return
	var flying_material := flying_model.material_override as StandardMaterial3D
	if flying_material == null or not flying_material.disable_receive_shadows:
		_fail("Flying Planet Lander should use softened building surface shading.")
		return
	if flying_model.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		_fail("Flying Planet Lander should still cast a world-sun shadow.")
		return
	if not flying_model.position.is_equal_approx(landing_sequence.model_visual_offset):
		_fail("Flying Planet Lander should apply the configurable touchdown visual offset.")
		return

	var hot_reload_config_path := "user://planet_lander_tuning_smoke.cfg"
	if not _save_lander_tuning(hot_reload_config_path, 0.77, 0.12, -0.08):
		_fail("Could not create the Planet Lander hot-reload test config.")
		return
	landing_sequence.runtime_config_path = hot_reload_config_path
	landing_sequence.prepare_landing(Vector2.ZERO)
	if not is_equal_approx(landing_sequence.model_uniform_scale, 0.77):
		_fail("Planet Lander should load tuning when landing is prepared.")
		return

	if not _save_lander_tuning(hot_reload_config_path, 0.71, 0.2, 0.1):
		_fail("Could not update the Planet Lander hot-reload test config.")
		return
	landing_sequence.prepare_landing(Vector2.ZERO)
	var reloaded_model := landing_sequence.get_node_or_null("PlanetLanderFlyingModel") as MeshInstance3D
	var expected_offset := Vector3.UP * 0.2 \
		+ PlanetLanderLandingSequence3D.DEFAULT_SCREEN_RIGHT_AXIS * 0.1
	if not is_equal_approx(landing_sequence.model_uniform_scale, 0.71):
		_fail("Planet Lander should reload scale on the same node without restarting.")
		return
	if reloaded_model == null or not reloaded_model.position.is_equal_approx(expected_offset):
		_fail("Planet Lander should reload offsets on the same node without restarting.")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(hot_reload_config_path))

	print("building_light_energy=%.2f layer_mask=%d flying_layer_mask=%d hot_reloaded_scale=%.2f casts_shadows=%s" % [
		main.building_light.light_energy,
		instance.layers,
		flying_model.layers,
		reloaded_model.scale.x,
		main.sun_light.shadow_enabled,
	])
	quit(0)


func _save_lander_tuning(path: String, scale_value: float, offset_up: float, offset_right: float) -> bool:
	var config := ConfigFile.new()
	config.set_value("planet_lander_tuning", "flying_model_scale", scale_value)
	config.set_value("planet_lander_tuning", "flying_offset_up", offset_up)
	config.set_value("planet_lander_tuning", "flying_offset_screen_right", offset_right)
	return config.save(path) == OK


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
