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
	var input_controller = root.get_node("MapInputController")
	var game_hud_root := root.get_node("Ui/UiRoot/GameHud") as Control
	var hud_panel := root.get_node("Ui/UiRoot/GameHud/StatusPanel") as Control
	var initial_zoom := camera.zoom
	var initial_hud_scale := root.get_effective_hud_scale_for_tests()

	get_root().size = Vector2i(1920, 720)
	await process_frame
	var wide_viewport_size := get_root().get_visible_rect().size
	var wide_zoom := camera.zoom
	var wide_hud_scale := root.get_effective_hud_scale_for_tests()
	var wide_panel_position := hud_panel.position

	get_root().size = Vector2i(900, 900)
	await process_frame
	var square_viewport_size := get_root().get_visible_rect().size
	var square_zoom := camera.zoom
	var square_hud_scale := root.get_effective_hud_scale_for_tests()
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

	if not is_equal_approx(initial_hud_scale, root.gui_scale_factor) or not is_equal_approx(wide_hud_scale, root.gui_scale_factor) or not is_equal_approx(square_hud_scale, root.gui_scale_factor):
		push_error("HUD physical scale should remain equal to gui_scale_factor across viewport sizes.")
		quit(1)
		return

	var gesture_start_zoom: float = camera.zoom.x
	var magnify := InputEventMagnifyGesture.new()
	magnify.factor = 1.25
	magnify.position = square_viewport_size * 0.5
	camera._unhandled_input(magnify)
	if not is_equal_approx(camera.zoom.x, gesture_start_zoom * magnify.factor):
		push_error("Trackpad magnify gesture did not use the shared anchored zoom path.")
		quit(1)
		return

	var first_touch := InputEventScreenTouch.new()
	first_touch.index = 0
	first_touch.position = Vector2(100.0, 100.0)
	first_touch.pressed = true
	camera._unhandled_input(first_touch)
	var second_touch := InputEventScreenTouch.new()
	second_touch.index = 1
	second_touch.position = Vector2(200.0, 100.0)
	second_touch.pressed = true
	camera._unhandled_input(second_touch)
	var pinch_start_zoom: float = camera.zoom.x
	input_controller._unhandled_input(first_touch)
	input_controller._unhandled_input(second_touch)
	var pinch_drag := InputEventScreenDrag.new()
	pinch_drag.index = 1
	pinch_drag.position = Vector2(220.0, 100.0)
	camera._unhandled_input(pinch_drag)
	input_controller._unhandled_input(pinch_drag)
	if not is_equal_approx(camera.zoom.x, pinch_start_zoom * 1.2):
		push_error("Two-finger touch distance did not drive pinch zoom.")
		quit(1)
		return
	if input_controller.primary_button_down:
		push_error("A pinch gesture leaked into the map's primary pointer command.")
		quit(1)
		return
	first_touch.pressed = false
	second_touch.pressed = false
	camera._unhandled_input(first_touch)
	camera._unhandled_input(second_touch)
	input_controller._unhandled_input(first_touch)
	input_controller._unhandled_input(second_touch)

	first_touch.position = Vector2(100.0, 100.0)
	second_touch.position = Vector2(200.0, 100.0)
	first_touch.pressed = true
	second_touch.pressed = true
	var third_touch := InputEventScreenTouch.new()
	third_touch.index = 2
	third_touch.position = Vector2(150.0, 200.0)
	third_touch.pressed = true
	for touch in [first_touch, second_touch, third_touch]:
		camera._unhandled_input(touch)
		input_controller._unhandled_input(touch)
	var rotation_start_zoom: float = camera.zoom.x
	var rotation_start_yaw: float = root.camera_3d.yaw_radians
	var rotation_start_tilt: float = root.camera_3d.tilt_radians
	var rotation_drag := InputEventScreenDrag.new()
	rotation_drag.index = 2
	rotation_drag.position = Vector2(180.0, 230.0)
	camera._unhandled_input(rotation_drag)
	input_controller._unhandled_input(rotation_drag)
	if not is_equal_approx(camera.zoom.x, rotation_start_zoom):
		push_error("Three-finger camera rotation leaked into pinch zoom.")
		quit(1)
		return
	if is_equal_approx(root.camera_3d.yaw_radians, rotation_start_yaw) or is_equal_approx(root.camera_3d.tilt_radians, rotation_start_tilt):
		push_error("Three-finger touch drag did not rotate and tilt the 3D camera.")
		quit(1)
		return
	if input_controller.primary_button_down:
		push_error("Three-finger camera rotation leaked into the map's primary pointer command.")
		quit(1)
		return
	for touch in [first_touch, second_touch, third_touch]:
		touch.pressed = false
		camera._unhandled_input(touch)
		input_controller._unhandled_input(touch)

	var trackpad_start_yaw: float = root.camera_3d.yaw_radians
	var trackpad_start_tilt: float = root.camera_3d.tilt_radians
	var trackpad_pan := InputEventPanGesture.new()
	trackpad_pan.alt_pressed = true
	trackpad_pan.delta = Vector2(1.0, 1.0)
	camera._unhandled_input(trackpad_pan)
	if is_equal_approx(root.camera_3d.yaw_radians, trackpad_start_yaw) or is_equal_approx(root.camera_3d.tilt_radians, trackpad_start_tilt):
		push_error("Alt + trackpad pan did not use the shared camera rotation path.")
		quit(1)
		return

	var tap_position := square_viewport_size * 0.5
	var expected_tap_tile: Vector2i = input_controller.viewport_to_tile(tap_position)
	var tap := InputEventScreenTouch.new()
	tap.index = 0
	tap.position = tap_position
	tap.pressed = true
	input_controller._unhandled_input(tap)
	if input_controller.primary_button_down:
		push_error("Single touch should be deferred until it is identified as a tap or drag.")
		quit(1)
		return
	tap.pressed = false
	input_controller._unhandled_input(tap)
	if root.world.selected_tile != expected_tap_tile:
		push_error("Single-touch tap did not feed the shared map command path.")
		quit(1)
		return

	var wheel_start_zoom: float = camera.zoom.x
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = square_viewport_size * 0.5
	camera._unhandled_input(wheel)
	if not is_equal_approx(camera.zoom.x, wheel_start_zoom * camera.ZOOM_STEP):
		push_error("Mouse wheel zoom stopped using its existing zoom step.")
		quit(1)
		return

	for action in [&"camera_pan_left", &"camera_pan_right", &"camera_pan_up", &"camera_pan_down", &"camera_zoom_in", &"camera_zoom_out"]:
		if not InputMap.has_action(action):
			push_error("Missing centralized camera input action: %s" % action)
			quit(1)
			return

	root.camera_3d.yaw_radians = PI * 0.5
	root._sync_terrain_3d_camera()
	var keyboard_pan_delta := Vector2(camera.PAN_SPEED * 0.1, 0.0)
	var keyboard_pan_center := square_viewport_size * 0.5
	var expected_keyboard_map_delta: Vector2 = (
		input_controller.viewport_to_map_position(keyboard_pan_center + keyboard_pan_delta)
		- input_controller.viewport_to_map_position(keyboard_pan_center)
	)
	var keyboard_pan_start_map: Vector2 = root._iso_screen_to_map_position(camera.position)
	Input.action_press(&"camera_pan_right")
	camera._process(0.1)
	Input.action_release(&"camera_pan_right")
	var actual_keyboard_map_delta: Vector2 = root._iso_screen_to_map_position(camera.position) - keyboard_pan_start_map
	if not actual_keyboard_map_delta.is_equal_approx(expected_keyboard_map_delta):
		push_error("Keyboard camera pan did not follow viewport-right after camera rotation.")
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
