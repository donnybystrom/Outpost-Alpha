extends Node

const IsoWorld := preload("res://scripts/iso_world.gd")

var world: IsoWorld
var camera: Camera2D
var active: bool = false
var primary_button_down: bool = false
var conversion_calls: int = 0
var last_conversion_usec: int = 0


func _ready() -> void:
	set_process_unhandled_input(true)
	set_active(active)


func configure(target_world: IsoWorld, target_camera: Camera2D) -> void:
	world = target_world
	camera = target_camera


func set_active(next_active: bool) -> void:
	active = next_active
	primary_button_down = false
	set_process_unhandled_input(active)
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func viewport_to_world(viewport_position: Vector2) -> Vector2:
	if world == null:
		return Vector2.ZERO
	return world.get_global_transform_with_canvas().affine_inverse() * viewport_position


func viewport_to_tile(viewport_position: Vector2) -> Vector2i:
	var started: int = Time.get_ticks_usec()
	if world == null:
		last_conversion_usec = Time.get_ticks_usec() - started
		return Vector2i(-1, -1)
	var tile: Vector2i = world.world_to_map(viewport_to_world(viewport_position))
	last_conversion_usec = Time.get_ticks_usec() - started
	conversion_calls += 1
	return tile


func hover_at_viewport(viewport_position: Vector2) -> void:
	if not active or world == null:
		return
	world.hover_tile(viewport_to_tile(viewport_position))


func primary_press_at_viewport(viewport_position: Vector2, line_mode: bool) -> void:
	if not active or world == null:
		return
	primary_button_down = true
	world.primary_press_tile(viewport_to_tile(viewport_position), line_mode)


func primary_drag_at_viewport(viewport_position: Vector2) -> void:
	if not active or world == null or not primary_button_down:
		return
	world.primary_drag_tile(viewport_to_tile(viewport_position))


func primary_release_at_viewport(viewport_position: Vector2) -> void:
	if not active or world == null:
		return
	primary_button_down = false
	world.primary_release_tile(viewport_to_tile(viewport_position))


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

	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_G:
			world.toggle_grid()
