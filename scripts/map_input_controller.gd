extends Node

const IsoWorld := preload("res://scripts/iso_world.gd")

var world: IsoWorld
var camera: Camera2D
var camera_3d: Camera3D
var active: bool = false
var primary_button_down: bool = false
var primary_uses_viewport_selection := false
var primary_press_viewport_position := Vector2.ZERO
var conversion_calls: int = 0
var last_conversion_usec: int = 0
var touch_drag_threshold := 6.0
var _touch_positions: Dictionary[int, Vector2] = {}
var _touch_primary_index := -1
var _touch_press_position := Vector2.ZERO
var _touch_primary_started := false
var _touch_gesture_consumed := false


func _ready() -> void:
	set_process_unhandled_input(true)
	set_active(active)


func configure(target_world: IsoWorld, target_camera: Camera2D, target_camera_3d: Camera3D = null) -> void:
	world = target_world
	camera = target_camera
	camera_3d = target_camera_3d


func set_active(next_active: bool) -> void:
	active = next_active
	primary_button_down = false
	primary_uses_viewport_selection = false
	_reset_touch_state()
	set_process_unhandled_input(active)
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func viewport_to_world(viewport_position: Vector2) -> Vector2:
	if world == null:
		return Vector2.ZERO
	if _can_project_from_3d_camera():
		return world.map_position_to_screen(viewport_to_map_position(viewport_position))
	return world.get_global_transform_with_canvas().affine_inverse() * viewport_position


func viewport_to_map_position(viewport_position: Vector2) -> Vector2:
	if not _can_project_from_3d_camera():
		if world == null:
			return Vector2.ZERO
		var world_position := world.get_global_transform_with_canvas().affine_inverse() * viewport_position
		var tile := world.world_to_map(world_position)
		return Vector2(tile)

	var ray_origin := camera_3d.project_ray_origin(viewport_position)
	var ray_direction := camera_3d.project_ray_normal(viewport_position)
	if absf(ray_direction.y) <= 0.0001:
		return Vector2.ZERO
	var distance := -ray_origin.y / ray_direction.y
	var point := ray_origin + ray_direction * distance
	return Vector2(point.x, point.z)


func viewport_to_tile(viewport_position: Vector2) -> Vector2i:
	var started: int = Time.get_ticks_usec()
	if world == null:
		last_conversion_usec = Time.get_ticks_usec() - started
		return Vector2i(-1, -1)
	var tile: Vector2i
	if _can_project_from_3d_camera():
		var map_position := viewport_to_map_position(viewport_position)
		tile = Vector2i(roundi(map_position.x), roundi(map_position.y))
	else:
		tile = world.world_to_map(viewport_to_world(viewport_position))
	last_conversion_usec = Time.get_ticks_usec() - started
	conversion_calls += 1
	return tile


func map_position_to_viewport(map_position: Vector2) -> Vector2:
	if _can_project_from_3d_camera():
		return camera_3d.unproject_position(Vector3(map_position.x, 0.0, map_position.y))
	if world == null:
		return Vector2.ZERO
	return world.get_global_transform_with_canvas() * world.map_position_to_screen(map_position)


func _can_project_from_3d_camera() -> bool:
	return camera_3d != null and camera_3d.current and camera_3d.visible


func hover_at_viewport(viewport_position: Vector2) -> void:
	if not active or world == null:
		return
	world.hover_tile(viewport_to_tile(viewport_position))


func primary_press_at_viewport(viewport_position: Vector2, line_mode: bool) -> void:
	if not active or world == null:
		return
	primary_button_down = true
	primary_uses_viewport_selection = _should_use_viewport_selection()
	primary_press_viewport_position = viewport_position
	if primary_uses_viewport_selection:
		world.primary_press_viewport(viewport_position, viewport_to_tile(viewport_position), line_mode, Callable(self, "map_position_to_viewport"))
	else:
		world.primary_press_world(viewport_to_world(viewport_position), viewport_to_tile(viewport_position), line_mode)


func primary_drag_at_viewport(viewport_position: Vector2) -> void:
	if not active or world == null or not primary_button_down:
		return
	if primary_uses_viewport_selection:
		world.primary_drag_viewport(viewport_position, viewport_to_tile(viewport_position))
	else:
		world.primary_drag_world(viewport_to_world(viewport_position), viewport_to_tile(viewport_position))


func primary_release_at_viewport(viewport_position: Vector2) -> void:
	if not active or world == null:
		return
	primary_button_down = false
	if primary_uses_viewport_selection:
		world.primary_release_viewport(viewport_position, viewport_to_tile(viewport_position))
	else:
		world.primary_release_world(viewport_to_world(viewport_position), viewport_to_tile(viewport_position))
	primary_uses_viewport_selection = false


func secondary_press_at_viewport(viewport_position: Vector2) -> void:
	if not active or world == null:
		return
	primary_button_down = false
	primary_uses_viewport_selection = false
	world.secondary_press_world(viewport_to_world(viewport_position), viewport_to_tile(viewport_position))


func _should_use_viewport_selection() -> bool:
	return _can_project_from_3d_camera() and world != null and world.paint_tool == "none"


func _unhandled_input(event: InputEvent) -> void:
	if not active or world == null:
		return

	if event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		hover_at_viewport(mouse_motion.position)
		primary_drag_at_viewport(mouse_motion.position)

	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				primary_press_at_viewport(mouse_button.position, mouse_button.shift_pressed)
			else:
				primary_release_at_viewport(mouse_button.position)
		elif mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			secondary_press_at_viewport(mouse_button.position)
			get_viewport().set_input_as_handled()

	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)

	if event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)

	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_G:
			world.toggle_grid()
		elif key.pressed and not key.echo and key.keycode == KEY_R:
			world.rotate_active_building()
		elif key.pressed and not key.echo and key.keycode == KEY_F5:
			world.reload_building_catalog()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_positions[event.index] = event.position
		if _touch_positions.size() == 1:
			_touch_primary_index = event.index
			_touch_press_position = event.position
			_touch_primary_started = false
			_touch_gesture_consumed = false
		else:
			_touch_gesture_consumed = true
			_cancel_touch_primary()
		return

	var was_primary := event.index == _touch_primary_index
	_touch_positions.erase(event.index)
	if was_primary and not _touch_gesture_consumed:
		if not _touch_primary_started:
			primary_press_at_viewport(event.position, false)
		primary_release_at_viewport(event.position)
	if _touch_positions.is_empty():
		_reset_touch_state()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touch_positions.has(event.index):
		return
	_touch_positions[event.index] = event.position
	if _touch_gesture_consumed or _touch_positions.size() != 1 or event.index != _touch_primary_index:
		return

	hover_at_viewport(event.position)
	if not _touch_primary_started and event.position.distance_to(_touch_press_position) >= touch_drag_threshold:
		primary_press_at_viewport(_touch_press_position, false)
		_touch_primary_started = true
	if _touch_primary_started:
		primary_drag_at_viewport(event.position)


func _cancel_touch_primary() -> void:
	primary_button_down = false
	primary_uses_viewport_selection = false
	_touch_primary_started = false
	if world != null:
		world.cancel_primary_interaction()


func _reset_touch_state() -> void:
	_touch_positions.clear()
	_touch_primary_index = -1
	_touch_press_position = Vector2.ZERO
	_touch_primary_started = false
	_touch_gesture_consumed = false
