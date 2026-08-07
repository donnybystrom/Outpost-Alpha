class_name CameraControlMapping
extends RefCounted

const PAN_LEFT := &"camera_pan_left"
const PAN_RIGHT := &"camera_pan_right"
const PAN_UP := &"camera_pan_up"
const PAN_DOWN := &"camera_pan_down"
const ZOOM_IN := &"camera_zoom_in"
const ZOOM_OUT := &"camera_zoom_out"


static func ensure_defaults() -> void:
	_ensure_action(PAN_LEFT, 0.2, [_key(KEY_A), _key(KEY_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_ensure_action(PAN_RIGHT, 0.2, [_key(KEY_D), _key(KEY_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_ensure_action(PAN_UP, 0.2, [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_ensure_action(PAN_DOWN, 0.2, [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_ensure_action(ZOOM_IN, 0.15, [_joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_ensure_action(ZOOM_OUT, 0.15, [_joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])


static func pan_direction() -> Vector2:
	return Input.get_vector(PAN_LEFT, PAN_RIGHT, PAN_UP, PAN_DOWN)


static func zoom_axis() -> float:
	return Input.get_action_strength(ZOOM_IN) - Input.get_action_strength(ZOOM_OUT)


static func _ensure_action(action: StringName, deadzone: float, default_events: Array[InputEvent]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for event in default_events:
		InputMap.action_add_event(action, event)


static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


static func _joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
