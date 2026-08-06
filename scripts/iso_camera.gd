extends Camera2D

signal view_rotation_dragged(relative_pixels: Vector2)
signal pan_dragged(relative_pixels: Vector2, previous_position: Vector2, current_position: Vector2)

const PAN_SPEED := 520.0
const DRAG_SPEED := 1.0
const ZOOM_STEP := 1.12
const MIN_ZOOM := 0.65
const MAX_ZOOM := 16.0

var _dragging := false
var _rotating := false
var _last_mouse_position := Vector2.ZERO
var external_pan_enabled := false


func _ready() -> void:
	make_current()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0

	if direction != Vector2.ZERO:
		position += direction.normalized() * PAN_SPEED * delta / zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = mouse_button.pressed and mouse_button.alt_pressed
			_dragging = mouse_button.pressed and not _rotating
			_last_mouse_position = mouse_button.position
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x * ZOOM_STEP, mouse_button.position)
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x / ZOOM_STEP, mouse_button.position)

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


func _set_zoom(next_zoom: float, screen_anchor: Vector2) -> void:
	var before := get_global_mouse_position()
	next_zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(next_zoom, next_zoom)
	var after := get_global_mouse_position()
	position += before - after


func set_zoom_level(next_zoom: float) -> void:
	next_zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(next_zoom, next_zoom)


func set_external_pan_enabled(enabled: bool) -> void:
	external_pan_enabled = enabled
