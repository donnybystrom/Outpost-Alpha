extends Camera2D

const CameraControlMapping := preload("res://scripts/camera_control_mapping.gd")

signal view_rotation_dragged(relative_pixels: Vector2)
signal pan_dragged(relative_pixels: Vector2, previous_position: Vector2, current_position: Vector2)

const PAN_SPEED := 520.0
const DRAG_SPEED := 1.0
const ZOOM_STEP := 1.12
const CONTINUOUS_ZOOM_SPEED := 1.8
const TRACKPAD_ROTATION_PIXELS_PER_DELTA := 12.0
const MIN_ZOOM := 0.65
const MAX_ZOOM := 16.0

enum TouchGestureMode {
	NONE,
	PINCH,
	ROTATE,
}

var _dragging := false
var _rotating := false
var _last_mouse_position := Vector2.ZERO
var _touch_positions: Dictionary[int, Vector2] = {}
var _touch_gesture_mode := TouchGestureMode.NONE
var external_pan_enabled := false


func _ready() -> void:
	CameraControlMapping.ensure_defaults()
	make_current()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var direction := CameraControlMapping.pan_direction()

	if direction != Vector2.ZERO:
		position += direction * PAN_SPEED * delta / zoom.x

	var zoom_axis := CameraControlMapping.zoom_axis()
	if not is_zero_approx(zoom_axis):
		var viewport_center := get_viewport_rect().size * 0.5
		zoom_by_factor(pow(CONTINUOUS_ZOOM_SPEED, zoom_axis * delta), viewport_center)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mouse_button.pressed and mouse_button.alt_pressed
			_dragging = mouse_button.pressed and not _rotating
			_last_mouse_position = mouse_button.position
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by_steps(1.0, mouse_button.position)
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by_steps(-1.0, mouse_button.position)

	if event is InputEventMouseMotion and (_dragging or _rotating):
		var mouse_motion := event as InputEventMouseMotion
		if _rotating or mouse_motion.alt_pressed:
			_dragging = false
			_rotating = true
			view_rotation_dragged.emit(mouse_motion.relative)
		elif external_pan_enabled:
			pan_dragged.emit(mouse_motion.relative, _last_mouse_position, mouse_motion.position)
		else:
			position -= mouse_motion.relative * DRAG_SPEED / zoom.x
		_last_mouse_position = mouse_motion.position

	if event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		zoom_by_factor(magnify.factor, magnify.position)
		get_viewport().set_input_as_handled()

	if event is InputEventPanGesture:
		var pan_gesture := event as InputEventPanGesture
		if pan_gesture.alt_pressed:
			view_rotation_dragged.emit(pan_gesture.delta * TRACKPAD_ROTATION_PIXELS_PER_DELTA)
			get_viewport().set_input_as_handled()

	if event is InputEventScreenTouch:
		_track_touch(event as InputEventScreenTouch)

	if event is InputEventScreenDrag:
		_update_touch_and_zoom(event as InputEventScreenDrag)


func _set_zoom(next_zoom: float, screen_anchor: Vector2) -> void:
	var canvas_transform := get_viewport().get_canvas_transform()
	var before := canvas_transform.affine_inverse() * screen_anchor
	next_zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(next_zoom, next_zoom)
	force_update_scroll()
	var after := get_viewport().get_canvas_transform().affine_inverse() * screen_anchor
	position += before - after
	force_update_scroll()


func zoom_by_steps(steps: float, screen_anchor: Vector2) -> void:
	zoom_by_factor(pow(ZOOM_STEP, steps), screen_anchor)


func zoom_by_factor(factor: float, screen_anchor: Vector2) -> void:
	if factor <= 0.0 or is_equal_approx(factor, 1.0):
		return
	_set_zoom(zoom.x * factor, screen_anchor)


func set_zoom_level(next_zoom: float) -> void:
	next_zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(next_zoom, next_zoom)


func set_external_pan_enabled(enabled: bool) -> void:
	external_pan_enabled = enabled


func _track_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_positions[event.index] = event.position
		if _touch_positions.size() >= 3:
			_touch_gesture_mode = TouchGestureMode.ROTATE
		elif _touch_positions.size() == 2 and _touch_gesture_mode == TouchGestureMode.NONE:
			_touch_gesture_mode = TouchGestureMode.PINCH
	else:
		_touch_positions.erase(event.index)
		if _touch_positions.is_empty():
			_touch_gesture_mode = TouchGestureMode.NONE


func _update_touch_and_zoom(event: InputEventScreenDrag) -> void:
	if not _touch_positions.has(event.index):
		_touch_positions[event.index] = event.position
		return

	var previous_positions := _touch_positions.duplicate()
	_touch_positions[event.index] = event.position
	if _touch_gesture_mode == TouchGestureMode.ROTATE:
		if _touch_positions.size() < 3:
			return
		var previous_centroid := _touch_centroid(previous_positions)
		var current_centroid := _touch_centroid(_touch_positions)
		var relative := current_centroid - previous_centroid
		if relative != Vector2.ZERO:
			view_rotation_dragged.emit(relative)
		return

	if _touch_gesture_mode != TouchGestureMode.PINCH or _touch_positions.size() < 2:
		return

	var touch_ids: Array = _touch_positions.keys()
	var first_id: int = touch_ids[0]
	var second_id: int = touch_ids[1]
	var previous_first: Vector2 = previous_positions.get(first_id, _touch_positions[first_id])
	var previous_second: Vector2 = previous_positions.get(second_id, _touch_positions[second_id])
	var previous_distance := previous_first.distance_to(previous_second)
	if previous_distance <= 0.001:
		return

	var current_first: Vector2 = _touch_positions[first_id]
	var current_second: Vector2 = _touch_positions[second_id]
	var current_distance := current_first.distance_to(current_second)
	var midpoint := (current_first + current_second) * 0.5
	zoom_by_factor(current_distance / previous_distance, midpoint)


func _touch_centroid(positions: Dictionary[int, Vector2]) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var centroid := Vector2.ZERO
	for touch_position in positions.values():
		centroid += touch_position
	return centroid / float(positions.size())
