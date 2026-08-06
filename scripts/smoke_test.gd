extends SceneTree


func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Could not load main scene.")
		quit(1)
		return

	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame

	if root.app_state != root.AppState.MAIN_MENU:
		push_error("Main scene did not start on main menu.")
		quit(1)
		return

	if not root.main_menu_root.visible or root.sandbox_root.visible or root.game_hud_root.visible:
		push_error("Initial UI visibility is not main-menu-only.")
		quit(1)
		return
	if root.main_menu_background == null or root.main_menu_background.texture == null:
		push_error("Main menu should use assets/start_screen_background.png as a rendered background texture.")
		quit(1)
		return
	if root.main_menu_background.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		push_error("Main menu background should cover the viewport without distorting aspect ratio.")
		quit(1)
		return
	if root.music_player == null:
		push_error("Main scene should create a music player for the music system.")
		quit(1)
		return
	if root.music_enabled:
		if root.music_player.stream == null:
			push_error("Main scene should load the intro music stream when music is enabled.")
			quit(1)
			return
		if root.music_player.stream.resource_path != root.INTRO_MUSIC_PATH:
			push_error("Main menu should play intro_dystopian_nightmare.mp3.")
			quit(1)
			return
		if root.music_player.stream is AudioStreamMP3 and not (root.music_player.stream as AudioStreamMP3).loop:
			push_error("Intro music MP3 should be configured to loop.")
			quit(1)
			return
		if not root.music_player.playing:
			push_error("Start music should begin playing on the main menu when enabled.")
			quit(1)
			return
	else:
		if root.music_player.playing:
			push_error("Start music should not play when runtime config disables music.")
			quit(1)
			return

	root.paths_spin_box.value = 5
	root.path_width_spin_box.value = 2
	root.clearing_noise_spin_box.value = 80
	root.min_build_spin_box.value = 12
	root.max_build_spin_box.value = 14
	root._start_sandbox(false)
	await process_frame
	await process_frame

	var world := root.get_node_or_null("IsoWorld")
	var camera := root.get_node_or_null("IsoCamera")
	var input_controller = root.get_node_or_null("MapInputController")
	if world == null or camera == null or input_controller == null:
		push_error("Sandbox start did not create the expected world, camera and input nodes.")
		quit(1)
		return
	if root.music_enabled:
		if not root.music_player.playing or root.music_player.stream.resource_path != root.GAME_MUSIC_PATH:
			push_error("Sandbox should switch to the looping empty_orbit_signal.mp3 track.")
			quit(1)
			return
		if root.music_player.stream is AudioStreamMP3 and not (root.music_player.stream as AudioStreamMP3).loop:
			push_error("Sandbox music MP3 should be configured to loop.")
			quit(1)
			return
		if not root.music_fade_player.playing or root._music_tween == null or not root._music_tween.is_running():
			push_error("Entering Sandbox should crossfade from intro music instead of cutting it off.")
			quit(1)
			return

	var terrain_layer := world.get_node_or_null("TerrainTileLayer")
	if terrain_layer == null:
		push_error("IsoWorld did not create TerrainTileLayer.")
		quit(1)
		return
	if terrain_layer.visible:
		push_error("2D terrain layer should be hidden while the 3D terrain renderer is active.")
		quit(1)
		return
	var terrain_3d_layer := root.get_node_or_null("Terrain3DLayer")
	if terrain_3d_layer == null:
		push_error("Main scene should create Terrain3DLayer for the 3D ground renderer.")
		quit(1)
		return
	var forest_3d_layer := root.get_node_or_null("Forest3DLayer")
	if forest_3d_layer == null:
		push_error("Main scene should create Forest3DLayer for 3D tree placement.")
		quit(1)
		return
	var mountain_3d_layer := root.get_node_or_null("Mountain3DLayer")
	if mountain_3d_layer == null:
		push_error("Main scene should create Mountain3DLayer for procedural 3D mountain massifs.")
		quit(1)
		return
	var road_3d_layer := root.get_node_or_null("Road3DLayer")
	if road_3d_layer == null:
		push_error("Main scene should create Road3DLayer for the 3D road renderer.")
		quit(1)
		return
	if road_3d_layer.material == null or road_3d_layer.material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		push_error("3D road material should receive lighting instead of being unshaded.")
		quit(1)
		return
	var road_mesh := road_3d_layer.mesh_by_mask[0] as ArrayMesh
	var road_arrays: Array = road_mesh.surface_get_arrays(0)
	var road_normals: PackedVector3Array = road_arrays[Mesh.ARRAY_NORMAL]
	if road_normals.is_empty():
		push_error("Road3DLayer should generate normals so sunlight can shade road meshes.")
		quit(1)
		return
	if road_3d_layer.DECK_WIDTH < 0.60:
		push_error("3D roads should provide a visibly wider driving deck.")
		quit(1)
		return
	var corner_connections: Array[int] = [1, 2]
	var curved_centerline: PackedVector2Array = road_3d_layer._centerline_for_connections(corner_connections)
	if curved_centerline.size() <= 2:
		push_error("3D road corners should generate a smooth curved centerline.")
		quit(1)
		return
	var building_3d_layer := root.get_node_or_null("Building3DLayer")
	if building_3d_layer == null:
		push_error("Main scene should create Building3DLayer for 3D building models.")
		quit(1)
		return
	var building_preview_3d_layer := root.get_node_or_null("BuildingPreview3DLayer")
	if building_preview_3d_layer == null:
		push_error("Main scene should create BuildingPreview3DLayer for 3D placement previews.")
		quit(1)
		return
	if root.camera_3d == null:
		push_error("Main scene should create an orthographic Camera3D for the 3D ground renderer.")
		quit(1)
		return
	var camera_3d_size_before_rotation: float = root.camera_3d.size
	var camera_3d_yaw_before_rotation: float = root.camera_3d.yaw_radians
	root._on_camera_view_rotation_dragged(80.0)
	if is_equal_approx(root.camera_3d.yaw_radians, camera_3d_yaw_before_rotation):
		push_error("Alt-middle mouse drag should rotate the 3D world view yaw.")
		quit(1)
		return
	if not is_equal_approx(root.camera_3d.size, camera_3d_size_before_rotation):
		push_error("3D world view rotation should keep the same orthographic projection size.")
		quit(1)
		return
	var sun_light := root.get_node_or_null("SunLight") as DirectionalLight3D
	if sun_light == null or not sun_light.visible:
		push_error("Main scene should create a visible DirectionalLight3D sun for 3D world lighting.")
		quit(1)
		return
	if sun_light.shadow_enabled:
		push_error("MVP sun shadows should be disabled by default until shadow quality controls exist.")
		quit(1)
		return
	var world_environment := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		push_error("Main scene should create a WorldEnvironment with ambient lighting.")
		quit(1)
		return
	if terrain_3d_layer.get_child_count() > 0:
		var terrain_instance := terrain_3d_layer.get_child(0) as MultiMeshInstance3D
		var terrain_material := terrain_instance.material_override as StandardMaterial3D
		if terrain_material == null or terrain_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			push_error("3D terrain material should receive lighting instead of being unshaded.")
			quit(1)
			return

	var road_layer := world.get_node_or_null("RoadTileLayer")
	if road_layer == null:
		push_error("IsoWorld did not create RoadTileLayer.")
		quit(1)
		return
	if road_layer.visible:
		push_error("2D road layer should be hidden while the 3D road renderer is active.")
		quit(1)
		return

	var grid_layer := world.get_node_or_null("GridLayer")
	if grid_layer == null:
		push_error("IsoWorld did not create GridLayer.")
		quit(1)
		return
	if grid_layer.visible:
		push_error("2D grid layer should be hidden while the 3D terrain renderer is active.")
		quit(1)
		return

	var overlay_layer := world.get_node_or_null("OverlayLayer")
	if overlay_layer == null:
		push_error("IsoWorld did not create OverlayLayer.")
		quit(1)
		return

	var building_layer := world.get_node_or_null("BuildingLayer")
	if building_layer == null:
		push_error("IsoWorld did not create BuildingLayer.")
		quit(1)
		return
	if not building_layer.hidden_building_types.has("hq"):
		push_error("2D BuildingLayer should hide HQ while the 3D HQ model renderer is active.")
		quit(1)
		return
	if building_layer.atlas == null:
		push_error("BuildingLayer should load the buildings object atlas.")
		quit(1)
		return
	if not world.reload_building_catalog():
		push_error("Building catalog reload should keep a valid runtime catalog.")
		quit(1)
		return
	if world.colony_state.building_catalog != world.building_catalog:
		push_error("Reloaded building catalog should propagate to colony state.")
		quit(1)
		return
	if world.building_catalog.get_footprint("milling_plant", "horizontal") != Vector2i(2, 3):
		push_error("Milling Plant should use the configured 2x3 horizontal footprint.")
		quit(1)
		return
	if world.building_catalog.get_footprint("milling_plant", "vertical") != Vector2i(3, 2):
		push_error("Milling Plant should transpose to a 3x2 vertical footprint.")
		quit(1)
		return
	if not world.building_catalog.should_flip_sprite_horizontal("milling_plant", "vertical"):
		push_error("Single-source building sprites should mirror horizontally for vertical orientation.")
		quit(1)
		return
	if world.building_catalog.get_vehicle_approach_offset("milling_plant", "vertical") != Vector2i(3, 1):
		push_error("Milling Plant vertical vehicle approach should transpose with the flipped isometric sprite.")
		quit(1)
		return
	var milling_source: Rect2i = world.building_catalog.get_sprite_source_rect("milling_plant", "vertical")
	var milling_anchor_horizontal: Vector2 = world.building_catalog.get_sprite_anchor("milling_plant", "horizontal")
	var milling_anchor_vertical: Vector2 = world.building_catalog.get_sprite_anchor("milling_plant", "vertical")
	if not is_equal_approx(milling_anchor_horizontal.x + milling_anchor_vertical.x, float(milling_source.size.x)):
		push_error("Milling Plant vertical sprite anchor should mirror horizontally inside the source rect.")
		quit(1)
		return
	var machine_park_footprint: Vector2i = world.building_catalog.get_footprint("machine_park", "horizontal")
	if machine_park_footprint.x < 1 or machine_park_footprint.y < 1:
		push_error("Machine Park should use a non-empty configured horizontal footprint.")
		quit(1)
		return
	if world.building_catalog.get_model_config("oxygen_extractor").get("mesh_path", "") != "res://assets/3D/buildings/oxygen_extractor/base.obj":
		push_error("Oxygen Extractor should be configured with its 3D OBJ model asset.")
		quit(1)
		return
	if world.building_catalog.get_model_config("machine_park").get("mesh_path", "") != "res://assets/3D/buildings/machine_park/base.obj":
		push_error("Machine Park should be configured with its 3D OBJ model asset.")
		quit(1)
		return
	if world.building_catalog.get_model_config("milling_plant").get("mesh_path", "") != "res://assets/3D/buildings/milling_plant/base.obj":
		push_error("Milling Plant should be configured with its 3D OBJ model asset.")
		quit(1)
		return
	if world.building_catalog.get_sprite_source_rect("machine_park", "horizontal").size == Vector2i.ZERO:
		push_error("Machine Park should have an atlas sprite source rect.")
		quit(1)
		return
	if not world.building_catalog.should_flip_sprite_horizontal("machine_park", "vertical"):
		push_error("Machine Park should mirror its single-source sprite for vertical orientation.")
		quit(1)
		return
	if world.building_catalog.get_footprint("hq", "horizontal") != Vector2i(3, 3):
		push_error("HQ should use the configured 3x3 footprint.")
		quit(1)
		return
	if world.building_catalog.get_sprite_source_rect("hq", "horizontal").size == Vector2i.ZERO:
		push_error("HQ should have an atlas sprite source rect.")
		quit(1)
		return
	if world.building_catalog.get_model_config("hq").get("mesh_path", "") != "res://assets/3D/buildings/hq/base.obj":
		push_error("HQ should be configured with the 3D OBJ model asset.")
		quit(1)
		return

	var unit_layer := world.get_node_or_null("UnitLayer")
	if unit_layer == null:
		push_error("IsoWorld did not create UnitLayer.")
		quit(1)
		return
	var unit_3d_layer := root.get_node_or_null("Unit3DLayer")
	if unit_3d_layer == null:
		push_error("Main scene should create Unit3DLayer for model-backed units.")
		quit(1)
		return
	if unit_layer.unit_atlas == null:
		push_error("UnitLayer should load the units object atlas.")
		quit(1)
		return

	if terrain_layer.atlas == null:
		push_error("TerrainTileLayer did not load the terrain atlas.")
		quit(1)
		return

	if terrain_layer.atlas_image == null or terrain_layer.atlas_image.get_height() < 48:
		push_error("Terrain atlas should include terrain, road, and mountain rows.")
		quit(1)
		return
	var road_row_y := 16
	if terrain_layer.atlas_image.get_pixel(0, road_row_y).a > 0.0:
		push_error("Road atlas row should be transparent outside the road overlay art.")
		quit(1)
		return
	if terrain_layer.atlas_image.get_pixel(16, road_row_y + 8).a <= 0.0:
		push_error("Standalone road pad should render visible overlay pixels at tile center.")
		quit(1)
		return
	if terrain_layer.atlas_image.get_pixel(32 + 24, road_row_y + 4).a <= 0.0:
		push_error("North-connected road tile should render visible overlay pixels at its north endpoint.")
		quit(1)
		return

	if terrain_layer.cached_map_texture == null:
		push_error("TerrainTileLayer did not bake a cached map texture.")
		quit(1)
		return

	if road_layer.cached_road_texture == null:
		push_error("RoadTileLayer did not bake a cached road texture.")
		quit(1)
		return

	if grid_layer.cached_grid_texture == null:
		push_error("GridLayer did not bake a cached grid texture.")
		quit(1)
		return

	if world.map_data.path_endpoints.size() != 5:
		push_error("Sandbox start did not apply path count.")
		quit(1)
		return

	if world.map_data.build_radius < 12 or world.map_data.build_radius > 14:
		push_error("Sandbox start did not apply build radius range.")
		quit(1)
		return

	if world.map_data.path_width != 2:
		push_error("Sandbox start did not apply path width.")
		quit(1)
		return

	if world.map_data.clearing_noise != 80:
		push_error("Sandbox start did not apply clearing noise.")
		quit(1)
		return
	var mountain_count := _count_terrain(world.map_data, 5)
	if mountain_3d_layer.last_cells_processed != mountain_count:
		push_error("Mountain3DLayer should process exactly the current mountain terrain tiles.")
		quit(1)
		return
	if mountain_count > 0 and mountain_3d_layer.get_child_count() <= 0:
		push_error("Mountain3DLayer should create a mesh instance when mountain terrain exists.")
		quit(1)
		return
	if mountain_count > 0:
		var mountain_instance := mountain_3d_layer.get_child(0) as MeshInstance3D
		var mountain_arrays: Array = mountain_instance.mesh.surface_get_arrays(0)
		var mountain_normals: PackedVector3Array = mountain_arrays[Mesh.ARRAY_NORMAL]
		if mountain_normals.is_empty():
			push_error("Mountain3DLayer should generate normals so sunlight can shade procedural massifs.")
			quit(1)
			return
	var forest_count := _count_terrain(world.map_data, 1)
	if forest_3d_layer.tree_meshes.size() <= 1:
		push_error("Forest3DLayer should split the tree collection OBJ into multiple tree mesh variants.")
		quit(1)
		return
	var tree_arrays: Array = forest_3d_layer.tree_meshes[0].surface_get_arrays(0)
	var tree_normals: PackedVector3Array = tree_arrays[Mesh.ARRAY_NORMAL]
	if tree_normals.is_empty():
		push_error("Forest3DLayer tree meshes should keep or generate normals for lighting.")
		quit(1)
		return
	if forest_3d_layer.last_cells_processed != forest_count:
		push_error("Forest3DLayer should process exactly the current forest terrain tiles.")
		quit(1)
		return
	if forest_count > 0 and forest_3d_layer.target_density > 0.0 and forest_3d_layer.get_child_count() <= 0:
		push_error("Forest3DLayer should create tree multimesh instances when forest terrain exists.")
		quit(1)
		return
	root.tree_density_spin_box.value = 25
	root.tree_size_spin_box.value = 75
	root._apply_forest_visual_settings()
	if not is_equal_approx(forest_3d_layer.target_density, 0.25):
		push_error("Sandbox Admin tree density control should update Forest3DLayer target density.")
		quit(1)
		return
	if not is_equal_approx(forest_3d_layer.global_tree_scale, 0.75):
		push_error("Sandbox Admin tree size control should update Forest3DLayer global scale.")
		quit(1)
		return
	if forest_count > 0 and forest_3d_layer.get_child_count() <= 0:
		push_error("Forest3DLayer should create tree multimesh instances when tree density is above zero.")
		quit(1)
		return
	if root.game_hud_root.scale != Vector2.ONE:
		push_error("Game HUD should keep stable 1.0 UI scale so font size is viewport-independent.")
		quit(1)
		return
	if root.ui_root.theme.get_font_size("font_size", "Label") != 18:
		push_error("UI theme should keep Label font size at 18px.")
		quit(1)
		return

	if root.sharon_panel == null or not root.sharon_panel.visible:
		push_error("Sandbox start should show Sharon's opening briefing.")
		quit(1)
		return

	if root.hud_panel.visible:
		push_error("Sandbox debug HUD should be hidden until the admin/debug toggle is opened.")
		quit(1)
		return

	if world.colony_state == null:
		push_error("Sandbox start did not create colony state.")
		quit(1)
		return

	if world.colony_state.population != 5:
		push_error("Initial sandbox colony should start with five people.")
		quit(1)
		return

	if world.unit_state == null or not world.unit_state.workers.is_empty():
		push_error("Sandbox should not spawn the retired placeholder worker units.")
		quit(1)
		return

	if world.pathfinding_grid == null:
		push_error("Sandbox should create a pathfinding grid for units.")
		quit(1)
		return

	if world.colony_state.get_oxygen_capacity() != 0 or not world.colony_state.has_oxygen_shortage():
		push_error("Initial sandbox colony should start with an oxygen shortage.")
		quit(1)
		return

	if not root.objective_label.text.contains("Oxygen Extractor"):
		push_error("Initial sandbox objective should ask for an Oxygen Extractor.")
		quit(1)
		return

	if root.game_hud_root.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("Game HUD root should ignore mouse events so map clicks reach IsoWorld.")
		quit(1)
		return
	if root.resource_bar_panel == null or root.hq_metal_value_label == null:
		push_error("Game HUD should include a top-center HQ metal resource bar.")
		quit(1)
		return
	if root.hq_metal_value_label.text != "225":
		push_error("HQ metal HUD should start with the initial HQ metal reserve.")
		quit(1)
		return
	if world.colony_state.get_building_count("hq") != 1:
		push_error("Sandbox should start with one preplaced HQ.")
		quit(1)
		return
	var hq_models: Array[MeshInstance3D] = []
	for child in building_3d_layer.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Building3D_hq_"):
			hq_models.append(child)
	if hq_models.size() != 1:
		push_error("Starting HQ should be rendered as one 3D building model instance; found %d." % hq_models.size())
		quit(1)
		return
	var hq_model := hq_models[0]
	if hq_model == null or hq_model.mesh == null:
		push_error("3D HQ model instance should have a loaded mesh.")
		quit(1)
		return
	if hq_model.material_override == null:
		push_error("3D HQ model instance should have a texture material override.")
		quit(1)
		return
	var hq_material := hq_model.material_override as StandardMaterial3D
	if hq_material == null or not hq_material.normal_enabled or hq_material.normal_texture == null:
		push_error("3D HQ material should use the configured normal texture so sunlight creates surface detail.")
		quit(1)
		return
	if hq_material.roughness_texture == null or hq_material.metallic_texture == null:
		push_error("3D HQ material should use configured roughness and metallic textures.")
		quit(1)
		return
	var starting_hq: Dictionary = world.colony_state.get_nearest_building_of_type("hq", world.map_data.start_tile)
	if starting_hq.get("origin", Vector2i.ZERO) != world.map_data.start_tile - Vector2i(1, 1):
		push_error("Starting HQ should be centered on the middle of the map.")
		quit(1)
		return
	if world.pathfinding_grid.is_tile_passable(world.map_data.start_tile):
		push_error("Starting HQ footprint should block pathfinding at the map center.")
		quit(1)
		return

	var background_fill := root.get_node("Background/ViewportFill") as Control
	if background_fill.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("Background fill should ignore mouse events so map clicks reach IsoWorld.")
		quit(1)
		return
	if root.background.visible:
		push_error("Background canvas should be hidden in-game so it does not cover the 3D terrain renderer.")
		quit(1)
		return

	if not input_controller.active:
		push_error("Map input controller should be active in sandbox.")
		quit(1)
		return

	if root.performance_label == null:
		push_error("HUD should include performance label.")
		quit(1)
		return

	if _count_roads(world.map_data) != 1:
		push_error("Sandbox start should only include the HQ vehicle approach road, not demo roads.")
		quit(1)
		return

	root._toggle_admin_panel()
	await process_frame
	if not root.sandbox_root.visible:
		push_error("Admin panel did not open from toggle.")
		quit(1)
		return
	if not root.hud_panel.visible:
		push_error("Debug HUD should become visible with the admin/debug toggle.")
		quit(1)
		return
	root._toggle_admin_panel()
	await process_frame
	if root.sandbox_root.visible:
		push_error("Admin panel did not close from toggle.")
		quit(1)
		return
	if root.hud_panel.visible:
		push_error("Debug HUD should hide again when the admin/debug toggle closes.")
		quit(1)
		return

	var road_tile: Vector2i = world.map_data.start_tile + Vector2i(2, 2)
	root._select_build_tool("road")
	var road_viewport_position: Vector2 = _tile_to_viewport(root, road_tile)
	if input_controller.viewport_to_tile(road_viewport_position) != road_tile:
		push_error("Viewport-to-tile conversion did not round-trip through the 3D camera transform.")
		quit(1)
		return
	camera.position += Vector2(123, -57)
	camera.set_zoom_level(3.0)
	root._sync_terrain_3d_camera()
	await process_frame
	road_viewport_position = _tile_to_viewport(root, road_tile)
	if input_controller.viewport_to_tile(road_viewport_position) != road_tile:
		push_error("Viewport-to-tile conversion failed after camera pan/zoom.")
		quit(1)
		return
	root._on_camera_view_rotation_dragged(90.0)
	road_viewport_position = _tile_to_viewport(root, road_tile)
	if input_controller.viewport_to_tile(road_viewport_position) != road_tile:
		push_error("Viewport-to-tile conversion failed after 3D camera rotation.")
		quit(1)
		return

	var terrain_redraws_before_hover: int = terrain_layer.redraw_requests
	var road_redraws_before_hover: int = road_layer.redraw_requests
	var grid_redraws_before_hover: int = grid_layer.redraw_requests
	input_controller.hover_at_viewport(road_viewport_position)
	world.hovered_tile = road_tile
	if terrain_layer.redraw_requests != terrain_redraws_before_hover:
		push_error("Hover should not request terrain redraw.")
		quit(1)
		return
	if road_layer.redraw_requests != road_redraws_before_hover:
		push_error("Hover should not request road redraw.")
		quit(1)
		return
	if grid_layer.redraw_requests != grid_redraws_before_hover:
		push_error("Hover should not request grid redraw.")
		quit(1)
		return
	var single_preview_tiles: Array[Vector2i] = [road_tile]
	var preview_mask: int = overlay_layer._road_preview_mask(road_tile, single_preview_tiles)
	if preview_mask != 0:
		push_error("Single road hover preview should not report connected neighbors on an empty map.")
		quit(1)
		return
	var diagonal_preview_tiles: Array[Vector2i] = [road_tile, road_tile + Vector2i(1, 1)]
	var diagonal_preview_mask: int = overlay_layer._road_preview_mask(road_tile, diagonal_preview_tiles)
	if (diagonal_preview_mask & 32) == 0:
		push_error("Road placement preview should retain diagonal drag connections.")
		quit(1)
		return
	var road_feedback: Array[Dictionary] = world._get_placement_feedback()
	if road_feedback.size() != 1 or not bool(road_feedback[0]["valid"]):
		push_error("Road placement feedback should mark a clear hovered tile as valid.")
		quit(1)
		return
	input_controller.primary_press_at_viewport(road_viewport_position, false)
	if not world.map_data.has_road(road_tile):
		push_error("Road construction tool did not paint a road.")
		quit(1)
		return
	if not road_3d_layer.tile_mask_by_tile.has(road_tile):
		push_error("3D road layer did not track the newly placed road tile.")
		quit(1)
		return
	if road_3d_layer.last_chunks_rebuilt > 4 or road_3d_layer.last_cells_processed > road_3d_layer.CHUNK_SIZE * road_3d_layer.CHUNK_SIZE * road_3d_layer.last_chunks_rebuilt:
		push_error("Road edits should rebuild only the local chunks around the changed tile.")
		quit(1)
		return
	if road_layer.last_cells_processed > 25:
		push_error("Single road edit should repaint only a small local overlap area.")
		quit(1)
		return
	var distant_overlap_tile: Vector2i = road_tile + Vector2i(0, -2)
	world.map_data.set_road(distant_overlap_tile, true)
	var overlap_repaint_tiles: Array[Vector2i] = road_layer._road_tiles_overlapping_clear_tiles(road_layer._affected_road_tiles(road_tile))
	if not overlap_repaint_tiles.has(distant_overlap_tile):
		push_error("Road dirty repaint should include neighboring sprites overlapped by cleared isometric rects.")
		quit(1)
		return
	var blocked_road_tile: Vector2i = world.map_data.start_tile + Vector2i(4, 4)
	world.map_data.set_terrain(blocked_road_tile, 5)
	if world.pathfinding_grid.is_tile_passable(blocked_road_tile):
		push_error("Worker pathfinding should treat mountain terrain as impassable.")
		quit(1)
		return
	world.hover_tile(blocked_road_tile)
	road_feedback = world._get_placement_feedback()
	if road_feedback.size() != 1 or bool(road_feedback[0]["valid"]):
		push_error("Road placement feedback should mark blocked terrain as invalid.")
		quit(1)
		return
	world.paint_tile(blocked_road_tile)
	if world.map_data.has_road(blocked_road_tile):
		push_error("Road placement should not commit on blocked terrain.")
		quit(1)
		return
	var forest_tile: Vector2i = world.map_data.start_tile + Vector2i(5, 4)
	world.map_data.set_terrain(forest_tile, 1)
	if world.pathfinding_grid.is_tile_passable(forest_tile):
		push_error("Worker pathfinding should treat forest terrain as impassable.")
		quit(1)
		return
	world.hover_tile(forest_tile)
	road_feedback = world._get_placement_feedback()
	if road_feedback.size() != 1 or bool(road_feedback[0]["valid"]):
		push_error("Road placement feedback should mark forest terrain as invalid.")
		quit(1)
		return
	world.paint_tile(forest_tile)
	if world.map_data.has_road(forest_tile):
		push_error("Road placement should not commit on forest terrain.")
		quit(1)
		return
	if world.pathfinding_grid.movement_cost(road_tile) >= world.pathfinding_grid.movement_cost(world.map_data.start_tile):
		push_error("Worker pathfinding should give roads a lower movement cost than normal ground.")
		quit(1)
		return

	var oxygen_tile: Vector2i = _find_buildable_tile(world, "oxygen_extractor")
	var hq_metal_before_oxygen: int = world.colony_state.get_hq_stored_metal()
	root._select_build_tool("building:oxygen_extractor")
	world.rotate_active_building()
	if world.building_orientation != "vertical":
		push_error("R/building rotation should toggle active building orientation.")
		quit(1)
		return
	world.hover_tile(oxygen_tile)
	root._sync_building_3d_preview()
	if building_preview_3d_layer.preview_instance == null:
		push_error("Modeled building placement should show a 3D ghost preview.")
		quit(1)
		return
	if building_preview_3d_layer.preview_instance.mesh == null:
		push_error("3D building placement preview should use the active building model mesh.")
		quit(1)
		return
	if building_preview_3d_layer.footprint_root == null:
		push_error("Modeled building placement should render a 3D footprint outline.")
		quit(1)
		return
	if building_preview_3d_layer.footprint_root.get_child_count() != 16:
		push_error("2x2 modeled building footprint should render four 3D tile outlines.")
		quit(1)
		return
	world.paint_tile(oxygen_tile)
	if world.colony_state.get_building_count("oxygen_extractor") != 1:
		push_error("Oxygen extractor construction did not create a colony building.")
		quit(1)
		return
	var oxygen_models: Array[MeshInstance3D] = []
	for child in building_3d_layer.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Building3D_oxygen_extractor_"):
			oxygen_models.append(child)
	if oxygen_models.size() != 1:
		push_error("Placed Oxygen Extractor should render as one 3D model instance; found %d." % oxygen_models.size())
		quit(1)
		return
	if world.colony_state.get_hq_stored_metal() != hq_metal_before_oxygen - 40:
		push_error("Oxygen Extractor should spend 40 HQ metal.")
		quit(1)
		return
	var oxygen_building: Dictionary = world.colony_state.buildings[world.colony_state.buildings.size() - 1]
	if oxygen_building["orientation"] != "vertical":
		push_error("Placed Oxygen Extractor should store the active orientation.")
		quit(1)
		return
	if not oxygen_building.has("vehicle_entry_tile") or not oxygen_building.has("vehicle_approach_tile"):
		push_error("Placed buildings should store vehicle entry and approach tiles.")
		quit(1)
		return
	if not world.map_data.has_road(oxygen_building["vehicle_approach_tile"]):
		push_error("Placed buildings should auto-connect a road at the vehicle approach tile when passable.")
		quit(1)
		return
	if world.colony_state.get_oxygen_capacity() != 5:
		push_error("Oxygen extractor should support five colonists.")
		quit(1)
		return
	if world.colony_state.has_oxygen_shortage():
		push_error("One Oxygen Extractor should stabilize oxygen for the initial five colonists.")
		quit(1)
		return
	if not root.objective_label.text.contains("Oxygen support online"):
		push_error("Oxygen objective should update after the first extractor is built.")
		quit(1)
		return
	if world.pathfinding_grid.is_tile_passable(oxygen_tile):
		push_error("Worker pathfinding should treat placed buildings as impassable.")
		quit(1)
		return

	var living_tile: Vector2i = _find_buildable_tile(world, "living_quarters")
	root._select_build_tool("building:living_quarters")
	world.paint_tile(living_tile)
	if world.colony_state.get_building_count("living_quarters") != 1:
		push_error("Living quarters construction did not create a colony building.")
		quit(1)
		return
	if world.map_data.get_terrain(living_tile) > 1:
		push_error("Building placement should not rewrite the terrain layer.")
		quit(1)
		return

	var machine_tile: Vector2i = _find_buildable_tile(world, "machine_park")
	var hq_metal_before_machine: int = world.colony_state.get_hq_stored_metal()
	root._select_build_tool("building:machine_park")
	world.paint_tile(machine_tile)
	if world.colony_state.get_digger_capacity() != 2:
		push_error("Machine park should add two digger operator slots.")
		quit(1)
		return
	if world.colony_state.get_hq_stored_metal() != hq_metal_before_machine - 60:
		push_error("Machine Park should spend 60 HQ metal.")
		quit(1)
		return
	var machine_models: Array[MeshInstance3D] = []
	for child in building_3d_layer.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Building3D_machine_park_"):
			machine_models.append(child)
	if machine_models.size() != 1:
		push_error("Placed Machine Park should render as one 3D model instance; found %d." % machine_models.size())
		quit(1)
		return

	var milling_tile: Vector2i = _find_buildable_tile(world, "milling_plant")
	var hq_metal_before_milling: int = world.colony_state.get_hq_stored_metal()
	root._select_build_tool("building:milling_plant")
	world.paint_tile(milling_tile)
	if world.colony_state.get_building_count("milling_plant") != 1:
		push_error("Milling plant construction did not create a colony building.")
		quit(1)
		return
	if world.colony_state.get_hq_stored_metal() != hq_metal_before_milling - 40:
		push_error("Milling Plant should spend 40 HQ metal.")
		quit(1)
		return
	var milling_building: Dictionary = world.colony_state.buildings[world.colony_state.buildings.size() - 1]
	if milling_building.get("footprint", Vector2i.ZERO) != Vector2i(2, 3):
		push_error("Placed Milling Plant should use the configured 2x3 footprint.")
		quit(1)
		return
	var milling_models: Array[MeshInstance3D] = []
	for child in building_3d_layer.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Building3D_milling_plant_"):
			milling_models.append(child)
	if milling_models.size() != 1:
		push_error("Placed Milling Plant should render as one 3D model instance; found %d." % milling_models.size())
		quit(1)
		return

	world.cancel_active_placement()
	world.primary_press_world(world.map_to_screen(machine_tile), machine_tile, false)
	world.primary_release_world(world.map_to_screen(machine_tile), machine_tile)
	if world.get_selected_building().get("type", "") != "machine_park":
		push_error("Left-clicking a building footprint should select that building.")
		quit(1)
		return
	var selected_machine_park_footprint: Vector2i = world.get_selected_building().get("footprint", Vector2i.ZERO)
	if overlay_layer.selected_building_tiles.size() != selected_machine_park_footprint.x * selected_machine_park_footprint.y:
		push_error("Selected Machine Park should draw selection outlines for each footprint tile.")
		quit(1)
		return
	if not root.selected_building_panel.visible or not root.selected_building_title_label.text.contains("MACHINE PARK"):
		push_error("Selecting Machine Park should open its building HUD.")
		quit(1)
		return
	if root.build_drilling_machine_button.disabled:
		push_error("Machine Park should enable Drilling Machine production when metal is available.")
		quit(1)
		return
	var hq_metal_before_vehicle: int = world.colony_state.get_hq_stored_metal()
	var units_before_vehicle: int = world.unit_state.workers.size()
	root.build_drilling_machine_button.pressed.emit()
	if world.unit_state.workers.size() != units_before_vehicle + 1:
		push_error("Machine Park production should create a vehicle unit.")
		quit(1)
		return
	if world.unit_state.workers[world.unit_state.workers.size() - 1].get("role", "") != "drilling_machine":
		push_error("Machine Park Drilling Machine button should create a drilling_machine unit.")
		quit(1)
		return
	var drilling_machine_id: int = int(world.unit_state.workers[world.unit_state.workers.size() - 1]["id"])
	root._sync_unit_3d_layer()
	if not unit_3d_layer.instance_by_unit_id.has(drilling_machine_id):
		push_error("Drilling Machine should render through Unit3DLayer after production.")
		quit(1)
		return
	if unit_3d_layer.variant_by_unit_id.get(drilling_machine_id, "") != "drilling_machine_empty":
		push_error("Empty Drilling Machine should use the drilling_machine_empty 3D model variant.")
		quit(1)
		return
	if world.colony_state.get_hq_stored_metal() != hq_metal_before_vehicle - 50:
		push_error("Building a Drilling Machine should spend 50 HQ metal.")
		quit(1)
		return
	var hq_metal_before_hauler: int = world.colony_state.get_hq_stored_metal()
	var units_before_hauler: int = world.unit_state.workers.size()
	root.build_hauler_button.pressed.emit()
	if world.unit_state.workers.size() != units_before_hauler + 1:
		push_error("Machine Park production should create a hauler unit.")
		quit(1)
		return
	var hauler_unit: Dictionary = world.unit_state.workers[world.unit_state.workers.size() - 1]
	if hauler_unit.get("role", "") != "hauler" or unit_layer._vehicle_source_rect(hauler_unit).size == Vector2i.ZERO:
		push_error("Hauler should resolve to a sprite rect in units.png.")
		quit(1)
		return
	root._sync_unit_3d_layer()
	if not unit_3d_layer.instance_by_unit_id.has(int(hauler_unit["id"])):
		push_error("Hauler should render through Unit3DLayer after production.")
		quit(1)
		return
	if unit_3d_layer.variant_by_unit_id.get(int(hauler_unit["id"]), "") != "hauler_empty":
		push_error("Empty Hauler should use the hauler_empty 3D model variant.")
		quit(1)
		return
	if world.colony_state.get_hq_stored_metal() != hq_metal_before_hauler - 35:
		push_error("Building a Hauler should spend 35 HQ metal.")
		quit(1)
		return
	if world.colony_state.get_hq_stored_metal() != 0:
		push_error("Initial HQ metal should be fully spent after the first MVP production chain.")
		quit(1)
		return
	if not root.oxygen_extractor_button.disabled:
		push_error("Building buttons should disable when HQ metal cannot cover their cost.")
		quit(1)
		return
	if not root.build_drilling_machine_button.disabled:
		push_error("Vehicle production buttons should disable when HQ metal cannot cover their cost.")
		quit(1)
		return
	var oxygen_count_before_unaffordable_build: int = world.colony_state.get_building_count("oxygen_extractor")
	var unaffordable_oxygen_tile: Vector2i = _find_buildable_tile(world, "oxygen_extractor")
	root._select_build_tool("building:oxygen_extractor")
	world.paint_tile(unaffordable_oxygen_tile)
	if world.colony_state.get_building_count("oxygen_extractor") != oxygen_count_before_unaffordable_build:
		push_error("Building placement should fail when HQ metal cannot cover the building cost.")
		quit(1)
		return
	root._select_build_tool("none")
	var hauler_id: int = int(hauler_unit["id"])
	var empty_hauler_sprite_rect: Rect2i = unit_layer._vehicle_source_rect(hauler_unit)
	hauler_unit["cargo"] = hauler_unit["cargo_capacity"]
	if unit_layer._vehicle_source_rect(hauler_unit) == empty_hauler_sprite_rect:
		push_error("Loaded Hauler should use a different full-cargo sprite rect.")
		quit(1)
		return
	world.unit_state.workers[world.unit_state.workers.size() - 1] = hauler_unit
	root._sync_unit_3d_layer()
	if unit_3d_layer.variant_by_unit_id.get(hauler_id, "") != "hauler_filled":
		push_error("Loaded Hauler should switch to the hauler_filled 3D model variant.")
		quit(1)
		return
	var drilling_machine_unit: Dictionary = world.unit_state.get_unit_by_id(drilling_machine_id)
	drilling_machine_unit["cargo"] = drilling_machine_unit["cargo_capacity"]
	_set_unit_by_id(world.unit_state, drilling_machine_id, drilling_machine_unit)
	root._sync_unit_3d_layer()
	if unit_3d_layer.variant_by_unit_id.get(drilling_machine_id, "") != "drilling_machine_full":
		push_error("Loaded Drilling Machine should switch to the drilling_machine_full 3D model variant.")
		quit(1)
		return
	world.change_digger_operators(3)
	if world.colony_state.digger_operators != 2:
		push_error("Digger operators should be capped by machine park capacity.")
		quit(1)
		return
	world.change_infantry(2)
	if world.colony_state.infantry != 2 or world.colony_state.get_idle_population() != 1:
		push_error("Infantry assignment should consume idle population without map movement.")
		quit(1)
		return

	var hq_building: Dictionary = world.colony_state.get_nearest_building_of_type("hq", world.map_data.start_tile)
	if not world.unit_state.select_unit_by_id(hauler_id):
		push_error("The produced Hauler should remain selectable by id.")
		quit(1)
		return
	world.secondary_press_world(world.map_to_screen(milling_tile), milling_tile)
	hauler_unit = world.unit_state.get_unit_by_id(hauler_id)
	if not ["travel_to_load_metal", "waiting_for_metal"].has(hauler_unit.get("order", "")):
		push_error("Right-clicking an empty Milling Plant with a Hauler selected should assign a waitable metal transport order.")
		quit(1)
		return

	if not world.unit_state.select_unit_by_id(drilling_machine_id):
		push_error("The produced Drilling Machine should remain selectable by id.")
		quit(1)
		return
	var metal_before_mining: int = int(world.colony_state.resources["metal"])
	world.secondary_press_world(world.map_to_screen(blocked_road_tile), blocked_road_tile)
	var drilling_machine: Dictionary = world.unit_state.get_unit_by_id(drilling_machine_id)
	if drilling_machine.get("order", "") != "travel_to_mine":
		push_error("Right-clicking mountain terrain with a Drilling Machine selected should assign a mining order.")
		quit(1)
		return
	for step in 900:
		world._process(0.10)
		hq_building = world.colony_state.get_building_by_id(int(hq_building["id"]))
		if int(hq_building.get("stored_metal", 0)) >= 20:
			break
	drilling_machine = world.unit_state.get_unit_by_id(drilling_machine_id)
	if drilling_machine.get("order", "") == "idle":
		push_error("Drilling Machine should keep repeating its assigned mine and dump loop.")
		quit(1)
		return
	milling_building = world.colony_state.get_building_by_id(int(milling_building["id"]))
	if int(world.colony_state.resources["metal"]) <= metal_before_mining:
		push_error("Milling Plant should process deposited raw material into metal over time.")
		quit(1)
		return
	hq_building = world.colony_state.get_building_by_id(int(hq_building["id"]))
	if int(hq_building.get("stored_metal", 0)) < 20:
		push_error("Hauler should wait for metal, load 20 metal, deliver it to HQ, and continue its route.")
		quit(1)
		return
	if int(root.hq_metal_value_label.text) < 20:
		push_error("Top-center HQ metal HUD should update after a Hauler delivery.")
		quit(1)
		return
	hauler_unit = world.unit_state.get_unit_by_id(hauler_id)
	if hauler_unit.get("order", "") == "idle":
		push_error("Hauler should keep repeating the Milling Plant to HQ transport route after unloading.")
		quit(1)
		return
	if overlay_layer._should_draw_selected_marker():
		push_error("Building placement tool should hide the yellow selected-tile marker.")
		quit(1)
		return
	input_controller.secondary_press_at_viewport(road_viewport_position)
	if world.paint_tool != "none":
		push_error("Right-click should cancel active building placement.")
		quit(1)
		return
	if root.milling_plant_button.button_pressed:
		push_error("Right-click cancel should release the active building toolbar button.")
		quit(1)
		return
	root._select_build_tool("road")
	input_controller.secondary_press_at_viewport(road_viewport_position)
	if world.paint_tool != "none":
		push_error("Right-click should cancel active road placement.")
		quit(1)
		return
	if root.road_tool_button.button_pressed:
		push_error("Right-click cancel should release the active road toolbar button.")
		quit(1)
		return
	root._select_build_tool("building:oxygen_extractor")
	world.hover_tile(road_tile)
	var building_feedback: Array[Dictionary] = world._get_placement_feedback()
	if not _feedback_marks_tile_invalid(building_feedback, road_tile):
		push_error("Building placement feedback should mark footprint tiles on roads as invalid.")
		quit(1)
		return
	root._select_build_tool("none")
	if not _unit_layer_uses_camera_projection(root, world):
		push_error("Unit overlays should use the active Camera3D projection after viewport rotation.")
		quit(1)
		return
	var click_unit: Dictionary = world.unit_state.workers[0]
	var click_unit_viewport_position: Vector2 = input_controller.map_position_to_viewport(click_unit["position"])
	input_controller.primary_press_at_viewport(click_unit_viewport_position, false)
	input_controller.primary_release_at_viewport(click_unit_viewport_position)
	if not world.unit_state.is_selected(int(click_unit["id"])):
		push_error("Clicking a projected 3D unit should select it after viewport rotation.")
		quit(1)
		return
	var selection_rect: Rect2 = _worker_selection_viewport_rect(root, world)
	input_controller.primary_press_at_viewport(selection_rect.position, false)
	input_controller.primary_drag_at_viewport(selection_rect.position + selection_rect.size)
	input_controller.primary_release_at_viewport(selection_rect.position + selection_rect.size)
	if not world.unit_state.has_selection():
		push_error("Dragging without a build tool should select worker units after 3D camera rotation.")
		quit(1)
		return
	var worker_target: Vector2i = _find_passable_worker_target(world)
	var revisions_before_move: int = world.unit_state.path_revisions
	input_controller.secondary_press_at_viewport(_tile_to_viewport(root, worker_target))
	if world.unit_state.path_revisions <= revisions_before_move:
		push_error("Right-clicking the map with selected workers should issue a move command.")
		quit(1)
		return
	if not _selected_workers_have_unique_targets(world):
		push_error("Selected worker move command should spread workers into unique formation targets.")
		quit(1)
		return
	if not _selected_worker_targets_are_anchored_at(world, worker_target):
		push_error("Rotated-view move command should remain anchored at the clicked map tile.")
		quit(1)
		return
	var empty_click_tile: Vector2i = _find_empty_worker_click_tile(world)
	var empty_click_viewport_position := _tile_to_viewport(root, empty_click_tile)
	input_controller.primary_press_at_viewport(empty_click_viewport_position, false)
	input_controller.primary_release_at_viewport(empty_click_viewport_position)
	if world.unit_state.has_selection():
		push_error("Left-clicking empty map space should clear worker selection.")
		quit(1)
		return

	var road_line: Array[Vector2i] = _find_road_line(world)
	var line_start: Vector2i = road_line[0]
	var line_end: Vector2i = road_line[1]
	_assert_eight_direction_path(world._line_tiles(world.map_data.start_tile + Vector2i(-4, -4), world.map_data.start_tile + Vector2i(-1, -1)))
	var line_start_viewport_position: Vector2 = _tile_to_viewport(root, line_start)
	var line_end_viewport_position: Vector2 = _tile_to_viewport(root, line_end)
	root._select_build_tool("road")
	input_controller.primary_press_at_viewport(line_start_viewport_position, true)
	input_controller.primary_drag_at_viewport(line_end_viewport_position)
	if world._line_preview_tiles.size() < 2:
		push_error("Road line preview did not collect target tiles.")
		quit(1)
		return
	input_controller.primary_release_at_viewport(line_end_viewport_position)
	if not world.map_data.has_road(line_start) or not world.map_data.has_road(line_end):
		push_error("Road line preview did not commit painted roads.")
		quit(1)
		return

	var terrain_tile: Vector2i = world.map_data.start_tile + Vector2i(3, 2)
	var previous_terrain: int = world.map_data.get_terrain(terrain_tile)
	root._select_build_tool("terrain:2")
	world.paint_tile(terrain_tile)
	if world.map_data.get_terrain(terrain_tile) != previous_terrain:
		push_error("Sandbox mode allowed dev terrain painting.")
		quit(1)
		return

	root._show_main_menu()
	await process_frame
	root._start_sandbox(true)
	await process_frame
	await process_frame
	world = root.get_node_or_null("IsoWorld")
	if world == null:
		push_error("Dev mode did not keep a world node.")
		quit(1)
		return

	if not world.dev_mode:
		push_error("Dev mode did not configure IsoWorld dev flag.")
		quit(1)
		return

	if not root.hud_panel.visible:
		push_error("Dev mode should show the debug HUD by default.")
		quit(1)
		return

	if _count_roads(world.map_data) == 0:
		push_error("Dev mode did not include demo roads.")
		quit(1)
		return

	root._select_build_tool("terrain:2")
	world.paint_tile(terrain_tile)
	if world.map_data.get_terrain(terrain_tile) != 2:
		push_error("Dev mode terrain painting did not apply.")
		quit(1)
		return

	quit(0)


func _count_roads(map_data: RefCounted) -> int:
	var roads := 0
	for y in map_data.size.y:
		for x in map_data.size.x:
			if map_data.has_road(Vector2i(x, y)):
				roads += 1
	return roads


func _count_terrain(map_data: RefCounted, terrain_id: int) -> int:
	var count := 0
	for y in map_data.size.y:
		for x in map_data.size.x:
			if map_data.get_terrain(Vector2i(x, y)) == terrain_id:
				count += 1
	return count


func _find_buildable_tile(world: Node, building_type: String) -> Vector2i:
	var start_tile: Vector2i = world.map_data.start_tile
	for radius in range(0, 18):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var tile: Vector2i = start_tile + Vector2i(x, y)
				if world.colony_state.can_place_building(building_type, tile, world.map_data):
					return tile
	push_error("Could not find buildable tile for %s." % building_type)
	return Vector2i(-1, -1)


func _find_road_line(world: Node) -> Array[Vector2i]:
	var start_tile: Vector2i = world.map_data.start_tile
	for radius in range(2, 24):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var start: Vector2i = start_tile + Vector2i(x, y)
				var end: Vector2i = start + Vector2i(3, 0)
				if not world.map_data.is_inside(start) or not world.map_data.is_inside(end):
					continue
				if world.colony_state.is_occupied(start) or world.colony_state.is_occupied(end):
					continue
				return [start, end]
	push_error("Could not find empty road line.")
	return [Vector2i(-1, -1), Vector2i(-1, -1)]


func _find_passable_worker_target(world: Node) -> Vector2i:
	var start_tile: Vector2i = world.map_data.start_tile
	for radius in range(3, 20):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var tile: Vector2i = start_tile + Vector2i(x, y)
				if world.pathfinding_grid.is_tile_passable(tile):
					return tile
	push_error("Could not find passable worker target.")
	return Vector2i(-1, -1)


func _find_empty_worker_click_tile(world: Node) -> Vector2i:
	var start_tile: Vector2i = world.map_data.start_tile
	for radius in range(8, 24):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var tile: Vector2i = start_tile + Vector2i(x, y)
				if not world.pathfinding_grid.is_tile_passable(tile):
					continue
				var screen_position: Vector2 = world.map_to_screen(tile)
				if not _is_near_any_worker(world, screen_position, 18.0):
					return tile
	push_error("Could not find empty worker click tile.")
	return Vector2i(-1, -1)


func _is_near_any_worker(world: Node, screen_position: Vector2, radius: float) -> bool:
	for worker in world.unit_state.workers:
		var worker_screen_position: Vector2 = world.map_position_to_screen(worker["position"])
		if worker_screen_position.distance_to(screen_position) <= radius:
			return true
	return false


func _worker_selection_rect(world: Node) -> Rect2:
	var min_point := Vector2(1.0e20, 1.0e20)
	var max_point := Vector2(-1.0e20, -1.0e20)
	for worker in world.unit_state.workers:
		var point: Vector2 = world.map_position_to_screen(worker["position"])
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	min_point -= Vector2(18, 18)
	max_point += Vector2(18, 18)
	return Rect2(min_point, max_point - min_point)


func _worker_selection_viewport_rect(root: Node, world: Node) -> Rect2:
	var min_point := Vector2(1.0e20, 1.0e20)
	var max_point := Vector2(-1.0e20, -1.0e20)
	for worker in world.unit_state.workers:
		var position: Vector2 = worker["position"]
		var point: Vector2 = root.camera_3d.unproject_position(Vector3(position.x, 0.0, position.y))
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	min_point -= Vector2(18, 18)
	max_point += Vector2(18, 18)
	return Rect2(min_point, max_point - min_point)


func _selected_workers_have_unique_targets(world: Node) -> bool:
	var targets := {}
	var selected_count := 0
	for worker in world.unit_state.workers:
		if world.unit_state.is_selected(int(worker["id"])):
			selected_count += 1
			targets[worker["target_tile"]] = true
	return selected_count > 1 and targets.size() > 1


func _selected_worker_targets_are_anchored_at(world: Node, anchor: Vector2i) -> bool:
	var found_anchor := false
	for worker in world.unit_state.workers:
		if not world.unit_state.is_selected(int(worker["id"])):
			continue
		var target: Vector2i = worker["target_tile"]
		if target == anchor:
			found_anchor = true
		if maxi(absi(target.x - anchor.x), absi(target.y - anchor.y)) > 1:
			return false
	return found_anchor


func _unit_layer_uses_camera_projection(root: Node, world: Node) -> bool:
	for worker in world.unit_state.workers:
		var local_position: Vector2 = world.unit_layer.map_position_to_screen(worker["position"])
		var rendered_viewport_position: Vector2 = world.unit_layer.get_global_transform_with_canvas() * local_position
		var expected_viewport_position: Vector2 = root.camera_3d.unproject_position(
			Vector3(worker["position"].x, 0.0, worker["position"].y)
		)
		if rendered_viewport_position.distance_to(expected_viewport_position) > 0.5:
			return false
	return not world.unit_state.workers.is_empty()


func _set_unit_by_id(unit_state: RefCounted, unit_id: int, next_unit: Dictionary) -> void:
	for index in unit_state.workers.size():
		if int(unit_state.workers[index]["id"]) == unit_id:
			unit_state.workers[index] = next_unit
			return


func _tile_to_viewport(root: Node, tile: Vector2i) -> Vector2:
	return root.camera_3d.unproject_position(Vector3(float(tile.x), 0.0, float(tile.y)))


func _assert_eight_direction_path(tiles: Array[Vector2i]) -> void:
	var found_diagonal := false
	for index in range(1, tiles.size()):
		var delta: Vector2i = tiles[index] - tiles[index - 1]
		if maxi(absi(delta.x), absi(delta.y)) != 1:
			push_error("Road line path contains a disconnected gap between %s and %s." % [tiles[index - 1], tiles[index]])
			quit(1)
			return
		if absi(delta.x) == 1 and absi(delta.y) == 1:
			found_diagonal = true
	if not found_diagonal:
		push_error("Diagonal road drag should retain diagonal connections instead of becoming a cardinal staircase.")
		quit(1)


func _feedback_marks_tile_invalid(feedback: Array[Dictionary], tile: Vector2i) -> bool:
	for item in feedback:
		if item["tile"] == tile and not bool(item["valid"]):
			return true
	return false
