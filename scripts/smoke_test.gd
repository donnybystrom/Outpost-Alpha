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

	var building_layer := world.get_node_or_null("BuildingLayer")
	if building_layer == null:
		push_error("IsoWorld did not create BuildingLayer.")
		quit(1)
		return

	var unit_layer := world.get_node_or_null("UnitLayer")
	if unit_layer == null:
		push_error("IsoWorld did not create UnitLayer.")
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

	if world.unit_state == null or world.unit_state.workers.size() != world.colony_state.population:
		push_error("Sandbox should spawn one worker unit per starting colonist.")
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
	if world.pathfinding_grid.movement_cost(road_tile) >= world.pathfinding_grid.movement_cost(world.map_data.start_tile):
		push_error("Worker pathfinding should give roads a lower movement cost than normal ground.")
		quit(1)
		return

	var oxygen_tile: Vector2i = _find_buildable_tile(world, "oxygen_extractor")
	root._select_build_tool("building:oxygen_extractor")
	world.paint_tile(oxygen_tile)
	if world.colony_state.get_building_count("oxygen_extractor") != 1:
		push_error("Oxygen extractor construction did not create a colony building.")
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
	root._select_build_tool("building:machine_park")
	world.paint_tile(machine_tile)
	if world.colony_state.get_digger_capacity() != 2:
		push_error("Machine park should add two digger operator slots.")
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

	var milling_tile: Vector2i = _find_buildable_tile(world, "milling_plant")
	root._select_build_tool("building:milling_plant")
	world.paint_tile(milling_tile)
	if world.colony_state.get_building_count("milling_plant") != 1:
		push_error("Milling plant construction did not create a colony building.")
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
	var selection_rect: Rect2 = _worker_selection_rect(world)
	world.primary_press_world(selection_rect.position, world.world_to_map(selection_rect.position), false)
	world.primary_drag_world(selection_rect.position + selection_rect.size, world.world_to_map(selection_rect.position + selection_rect.size))
	world.primary_release_world(selection_rect.position + selection_rect.size, world.world_to_map(selection_rect.position + selection_rect.size))
	if not world.unit_state.has_selection():
		push_error("Dragging without a build tool should select worker units.")
		quit(1)
		return
	var worker_target: Vector2i = _find_passable_worker_target(world)
	var revisions_before_move: int = world.unit_state.path_revisions
	world.secondary_press_world(world.map_to_screen(worker_target), worker_target)
	if world.unit_state.path_revisions <= revisions_before_move:
		push_error("Right-clicking the map with selected workers should issue a move command.")
		quit(1)
		return
	if not _selected_workers_have_unique_targets(world):
		push_error("Selected worker move command should spread workers into unique formation targets.")
		quit(1)
		return
	var empty_click_tile: Vector2i = _find_empty_worker_click_tile(world)
	world.primary_press_world(world.map_to_screen(empty_click_tile), empty_click_tile, false)
	world.primary_release_world(world.map_to_screen(empty_click_tile), empty_click_tile)
	if world.unit_state.has_selection():
		push_error("Left-clicking empty map space should clear worker selection.")
		quit(1)
		return

	var road_line: Array[Vector2i] = _find_road_line(world)
	var line_start: Vector2i = road_line[0]
	var line_end: Vector2i = road_line[1]
	_assert_cardinal_path(world._line_tiles(world.map_data.start_tile + Vector2i(-4, -4), world.map_data.start_tile + Vector2i(-1, -1)))
	var line_start_viewport_position: Vector2 = world.get_global_transform_with_canvas() * world.map_to_screen(line_start)
	var line_end_viewport_position: Vector2 = world.get_global_transform_with_canvas() * world.map_to_screen(line_end)
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


func _selected_workers_have_unique_targets(world: Node) -> bool:
	var targets := {}
	var selected_count := 0
	for worker in world.unit_state.workers:
		if world.unit_state.is_selected(int(worker["id"])):
			selected_count += 1
			targets[worker["target_tile"]] = true
	return selected_count > 1 and targets.size() > 1


func _assert_cardinal_path(tiles: Array[Vector2i]) -> void:
	for index in range(1, tiles.size()):
		var delta: Vector2i = tiles[index] - tiles[index - 1]
		if absi(delta.x) + absi(delta.y) != 1:
			push_error("Road line path contains a diagonal gap between %s and %s." % [tiles[index - 1], tiles[index]])
			quit(1)
			return


func _feedback_marks_tile_invalid(feedback: Array[Dictionary], tile: Vector2i) -> bool:
	for item in feedback:
		if item["tile"] == tile and not bool(item["valid"]):
			return true
	return false
