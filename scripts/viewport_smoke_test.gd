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
	root._start_sandbox(false)
	await root.sandbox_loading_finished
	await process_frame

	var camera := root.get_node("IsoCamera") as Camera2D
	var game_hud_root := root.get_node("Ui/UiRoot/GameHud") as Control
	var hud_panel := root.get_node("Ui/UiRoot/GameHud/StatusPanel") as Control
	var initial_zoom := camera.zoom
	var initial_hud_scale := game_hud_root.scale

	get_root().size = Vector2i(1920, 720)
	await process_frame
	var wide_viewport_size := get_root().get_visible_rect().size
	var wide_zoom := camera.zoom
	var wide_hud_scale := game_hud_root.scale
	var wide_panel_position := hud_panel.position

	get_root().size = Vector2i(900, 900)
	await process_frame
	var square_viewport_size := get_root().get_visible_rect().size
	var square_zoom := camera.zoom
	var square_hud_scale := game_hud_root.scale
	var square_panel_position := hud_panel.position

	if not initial_zoom.is_equal_approx(wide_zoom) or not initial_zoom.is_equal_approx(square_zoom):
		push_error("Window resize changed camera zoom.")
		quit(1)
		return

	if wide_viewport_size.x <= square_viewport_size.x:
		push_error("Wider viewport did not expose a wider visible area.")
		quit(1)
		return

	if wide_panel_position != square_panel_position:
		push_error("HUD panel lost its anchored margin across resize.")
		quit(1)
		return

	if initial_hud_scale != Vector2.ONE or wide_hud_scale != Vector2.ONE or square_hud_scale != Vector2.ONE:
		push_error("HUD root should not scale with viewport size; layout should remain responsive instead.")
		quit(1)
		return

	camera.set_zoom_level(999.0)
	root._sync_terrain_3d_camera()
	if not is_equal_approx(camera.zoom.x, camera.MAX_ZOOM) or camera.MAX_ZOOM < 16.0:
		push_error("Camera should allow a 16x close-up zoom level.")
		quit(1)
		return
	var expected_closeup_size: float = clampf(
		square_viewport_size.y / (root.camera_3d.ISO_PIXELS_PER_WORLD_UNIT * camera.MAX_ZOOM),
		root.camera_3d.MIN_ORTHO_SIZE,
		root.camera_3d.MAX_ORTHO_SIZE
	)
	if not is_equal_approx(root.camera_3d.size, expected_closeup_size) or root.camera_3d.size >= 4.0:
		push_error("Camera3D orthographic size should follow the extended close-up zoom range.")
		quit(1)
		return

	print("initial_zoom=", initial_zoom, " wide=", wide_viewport_size, " square=", square_viewport_size)
	quit(0)
