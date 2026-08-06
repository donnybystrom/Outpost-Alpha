extends Camera3D

const ISO_PIXELS_PER_WORLD_UNIT := 22.627416997
const CAMERA_DISTANCE := 180.0
const MIN_ORTHO_SIZE := 4.0
const MAX_ORTHO_SIZE := 220.0

const RIGHT_AXIS := Vector3(0.707106781, 0.0, -0.707106781)
const UP_AXIS := Vector3(-0.353553391, 0.866025404, -0.353553391)
const BACK_AXIS := Vector3(0.612372436, 0.5, 0.612372436)
const ROTATION_RADIANS_PER_PIXEL := 0.006

var yaw_radians := 0.0

func _ready() -> void:
	name = "IsoCamera3D"
	projection = Camera3D.PROJECTION_ORTHOGONAL
	near = 0.05
	far = 500.0
	current = true


func sync_from_iso_camera(camera_2d: Camera2D, viewport_size: Vector2) -> void:
	if camera_2d == null or viewport_size.y <= 0.0:
		return

	var map_center := _iso_screen_to_map(camera_2d.position)
	var target := Vector3(map_center.x, 0.0, map_center.y)
	var yaw_basis := Basis(Vector3.UP, yaw_radians)
	var right_axis := yaw_basis * RIGHT_AXIS
	var up_axis := yaw_basis * UP_AXIS
	var back_axis := yaw_basis * BACK_AXIS
	size = clampf(viewport_size.y / (ISO_PIXELS_PER_WORLD_UNIT * camera_2d.zoom.x), MIN_ORTHO_SIZE, MAX_ORTHO_SIZE)
	global_transform = Transform3D(
		Basis(right_axis, up_axis, back_axis).orthonormalized(),
		target + back_axis * CAMERA_DISTANCE
	)


func rotate_view(relative_pixels: float) -> void:
	yaw_radians = wrapf(yaw_radians + relative_pixels * ROTATION_RADIANS_PER_PIXEL, -PI, PI)


func _iso_screen_to_map(screen_position: Vector2) -> Vector2:
	var x := (screen_position.y / 8.0 + screen_position.x / 16.0) * 0.5
	var y := (screen_position.y / 8.0 - screen_position.x / 16.0) * 0.5
	return Vector2(x, y)
