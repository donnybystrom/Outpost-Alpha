extends SceneTree

const TILE_SIZE := Vector2i(32, 16)
const ATLAS_COLUMNS := 16
const TERRAIN_ATLAS_PATH := "res://assets/tiles/terrain_32x16.png"
const ROAD_ROW := 1

const ROAD_NORTH := 1
const ROAD_EAST := 2
const ROAD_SOUTH := 4
const ROAD_WEST := 8

const CENTER := Vector2i(16, 8)
const ROAD_ENDPOINTS := {
	ROAD_NORTH: Vector2i(24, 4),
	ROAD_EAST: Vector2i(24, 12),
	ROAD_SOUTH: Vector2i(8, 12),
	ROAD_WEST: Vector2i(8, 4),
}


func _initialize() -> void:
	var image := Image.new()
	var input_path := ProjectSettings.globalize_path(TERRAIN_ATLAS_PATH)
	var error := image.load(input_path)
	if error != OK:
		push_error("Could not load terrain atlas: %s" % error)
		quit(1)
		return

	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	_clear_road_row(image)
	for mask in range(ATLAS_COLUMNS):
		_draw_road_overlay_tile(image, mask)

	error = image.save_png(input_path)
	if error != OK:
		push_error("Could not save terrain atlas: %s" % error)
		quit(1)
		return

	print("Updated road overlay row in %s" % input_path)
	quit(0)


func _clear_road_row(image: Image) -> void:
	var row_y := ROAD_ROW * TILE_SIZE.y
	image.fill_rect(Rect2i(0, row_y, TILE_SIZE.x * ATLAS_COLUMNS, TILE_SIZE.y), Color(0, 0, 0, 0))


func _draw_road_overlay_tile(image: Image, mask: int) -> void:
	var offset := Vector2i(mask * TILE_SIZE.x, ROAD_ROW * TILE_SIZE.y)
	var connected := mask != 0

	if not connected:
		_draw_pad(image, offset)
		return

	for bit in ROAD_ENDPOINTS.keys():
		if mask & int(bit):
			_draw_temporary_segment(image, offset, ROAD_ENDPOINTS[bit], int(bit), mask)
	_draw_junction_cap(image, offset, mask)


func _draw_pad(image: Image, offset: Vector2i) -> void:
	var dark := Color8(14, 17, 16, 170)
	var deck := Color8(66, 69, 65, 230)
	var edge := Color8(169, 103, 31, 215)
	_draw_polyline(image, offset, [
		Vector2i(11, 6),
		Vector2i(16, 4),
		Vector2i(21, 6),
		Vector2i(21, 10),
		Vector2i(16, 12),
		Vector2i(11, 10),
		Vector2i(11, 6),
	], dark, 2)
	_draw_disc(image, offset, CENTER, 4, deck)
	_draw_line(image, offset, Vector2i(12, 7), Vector2i(20, 9), edge)


func _draw_temporary_segment(image: Image, offset: Vector2i, endpoint: Vector2i, bit: int, mask: int) -> void:
	var shadow := Color8(7, 9, 8, 150)
	var road_edge := Color8(25, 29, 27, 230)
	var deck := Color8(72, 75, 70, 238)
	var panel := Color8(95, 98, 91, 220)
	var stripe := Color8(208, 130, 38, 230)

	_draw_thick_line(image, offset, CENTER, endpoint, 5, shadow)
	_draw_thick_line(image, offset, CENTER, endpoint, 4, road_edge)
	_draw_thick_line(image, offset, CENTER, endpoint, 3, deck)

	var accent_points := _offset_stripe_points(CENTER, endpoint, bit)
	_draw_line(image, offset, accent_points[0], accent_points[1], stripe)
	if mask != bit and _hash_noise(mask, bit, 13) > 0.35:
		_draw_line(image, offset, accent_points[2], accent_points[3], panel)


func _draw_junction_cap(image: Image, offset: Vector2i, mask: int) -> void:
	var deck := Color8(77, 80, 75, 242)
	var dark := Color8(18, 21, 20, 230)
	var stripe := Color8(218, 138, 40, 235)
	var connection_count := _bit_count(mask)
	if connection_count >= 3:
		_draw_disc(image, offset, CENTER, 4, dark)
		_draw_disc(image, offset, CENTER, 3, deck)
		_draw_line(image, offset, Vector2i(12, 8), Vector2i(20, 8), stripe)
	elif connection_count == 2:
		_draw_disc(image, offset, CENTER, 3, deck)
	else:
		_draw_disc(image, offset, CENTER, 2, deck)


func _offset_stripe_points(start: Vector2i, end: Vector2i, bit: int) -> Array[Vector2i]:
	var perpendicular := Vector2i(0, 1)
	if bit == ROAD_NORTH or bit == ROAD_SOUTH:
		perpendicular = Vector2i(1, 0)
	var near_start := _lerp_point(start, end, 0.28)
	var near_end := _lerp_point(start, end, 0.78)
	var secondary_start := _lerp_point(start, end, 0.52)
	var secondary_end := _lerp_point(start, end, 0.95)
	return [
		near_start + perpendicular,
		near_end + perpendicular,
		secondary_start - perpendicular,
		secondary_end - perpendicular,
	]


func _lerp_point(start: Vector2i, end: Vector2i, weight: float) -> Vector2i:
	var point := Vector2(start).lerp(Vector2(end), weight).round()
	return Vector2i(int(point.x), int(point.y))


func _bit_count(mask: int) -> int:
	var count := 0
	for bit in [ROAD_NORTH, ROAD_EAST, ROAD_SOUTH, ROAD_WEST]:
		if mask & bit:
			count += 1
	return count


func _draw_disc(image: Image, offset: Vector2i, origin: Vector2i, radius: int, color: Color) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if Vector2(x, y).length() <= float(radius):
				_blend_pixel_safe(image, offset + origin + Vector2i(x, y), color)


func _draw_thick_line(image: Image, offset: Vector2i, start: Vector2i, end: Vector2i, radius: int, color: Color) -> void:
	var delta := end - start
	var steps: int = maxi(abs(delta.x), abs(delta.y))
	for i in range(steps + 1):
		var t: float = 0.0 if steps == 0 else float(i) / float(steps)
		var point := Vector2(start).lerp(Vector2(end), t).round()
		_draw_disc(image, offset, Vector2i(int(point.x), int(point.y)), radius / 2, color)


func _draw_polyline(image: Image, offset: Vector2i, points: Array[Vector2i], color: Color, width: int) -> void:
	for index in range(1, points.size()):
		_draw_thick_line(image, offset, points[index - 1], points[index], width, color)


func _draw_line(image: Image, offset: Vector2i, start: Vector2i, end: Vector2i, color: Color) -> void:
	var delta := end - start
	var steps: int = maxi(abs(delta.x), abs(delta.y))
	for i in range(steps + 1):
		var t: float = 0.0 if steps == 0 else float(i) / float(steps)
		var point := Vector2(start).lerp(Vector2(end), t).round()
		_blend_pixel_safe(image, offset + Vector2i(int(point.x), int(point.y)), color)


func _blend_pixel_safe(image: Image, point: Vector2i, color: Color) -> void:
	if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
		return
	var previous := image.get_pixel(point.x, point.y)
	var mixed := previous.blend(color)
	image.set_pixel(point.x, point.y, mixed)


func _hash_noise(x: int, y: int, seed: int) -> float:
	var value := int(x * 374761393 + y * 668265263 + seed * 2246822519)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xffff) / 65535.0
