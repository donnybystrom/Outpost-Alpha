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

	var terrain_layer := world.get_node_or_null("TerrainTileLayer")
	if terrain_layer == null:
		push_error("IsoWorld did not create TerrainTileLayer.")
		quit(1)
		return

	var road_layer := world.get_node_or_null("RoadTileLayer")
	if road_layer == null:
		push_error("IsoWorld did not create RoadTileLayer.")
		quit(1)
		return

	var grid_layer := world.get_node_or_null("GridLayer")
	if grid_layer == null:
		push_error("IsoWorld did not create GridLayer.")
		quit(1)
		return

	var overlay_layer := world.get_node_or_null("OverlayLayer")
	if overlay_layer == null:
		push_error("IsoWorld did not create OverlayLayer.")
		quit(1)
		return

	if terrain_layer.atlas == null:
		push_error("TerrainTileLayer did not load the terrain atlas.")
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

	if root.game_hud_root.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("Game HUD root should ignore mouse events so map clicks reach IsoWorld.")
		quit(1)
		return

	var background_fill := root.get_node("Background/ViewportFill") as Control
	if background_fill.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("Background fill should ignore mouse events so map clicks reach IsoWorld.")
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

	if _count_roads(world.map_data) != 0:
		push_error("Sandbox start should not include demo roads.")
		quit(1)
		return

	root._toggle_admin_panel()
	await process_frame
	if not root.sandbox_root.visible:
		push_error("Admin panel did not open from toggle.")
		quit(1)
		return
	root._toggle_admin_panel()
	await process_frame
	if root.sandbox_root.visible:
		push_error("Admin panel did not close from toggle.")
		quit(1)
		return

	var road_tile: Vector2i = world.map_data.start_tile + Vector2i(2, 2)
	root._select_build_tool("road")
	var road_viewport_position: Vector2 = world.get_global_transform_with_canvas() * world.map_to_screen(road_tile)
	if input_controller.viewport_to_tile(road_viewport_position) != road_tile:
		push_error("Viewport-to-tile conversion did not round-trip through camera transform.")
		quit(1)
		return
	camera.position += Vector2(123, -57)
	camera.set_zoom_level(3.0)
	await process_frame
	road_viewport_position = world.get_global_transform_with_canvas() * world.map_to_screen(road_tile)
	if input_controller.viewport_to_tile(road_viewport_position) != road_tile:
		push_error("Viewport-to-tile conversion failed after camera pan/zoom.")
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
	input_controller.primary_press_at_viewport(road_viewport_position, false)
	if not world.map_data.has_road(road_tile):
		push_error("Road construction tool did not paint a road.")
		quit(1)
		return
	if road_layer.last_cells_processed > 5:
		push_error("Single road edit should update at most the placed tile plus four cardinal neighbors.")
		quit(1)
		return

	var line_start: Vector2i = world.map_data.start_tile + Vector2i(-4, -4)
	var line_end: Vector2i = world.map_data.start_tile + Vector2i(-1, -1)
	var line_start_viewport_position: Vector2 = world.get_global_transform_with_canvas() * world.map_to_screen(line_start)
	var line_end_viewport_position: Vector2 = world.get_global_transform_with_canvas() * world.map_to_screen(line_end)
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
