extends SceneTree

const TILE_SIZE := Vector2i(32, 16)
const ATLAS_COLUMNS := 16
const ATLAS_ROWS := 3
const OUTPUT_PATH := "res://assets/tiles/terrain_32x16.png"

const ROAD_NORTH := 1
const ROAD_EAST := 2
const ROAD_SOUTH := 4
const ROAD_WEST := 8

const TILE_PALETTES := [
	{"base": Color8(48, 54, 45), "shade": Color8(34, 39, 34), "accent": Color8(74, 80, 68)},
	{"base": Color8(54, 75, 36), "shade": Color8(34, 49, 29), "accent": Color8(80, 108, 45)},
	{"base": Color8(59, 43, 76), "shade": Color8(40, 32, 54), "accent": Color8(174, 54, 194)},
	{"base": Color8(78, 65, 48), "shade": Color8(48, 42, 36), "accent": Color8(206, 111, 31)},
	{"base": Color8(35, 78, 82), "shade": Color8(24, 54, 58), "accent": Color8(72, 229, 238)},
	{"base": Color8(54, 58, 55), "shade": Color8(38, 41, 40), "accent": Color8(196, 126, 38)},
	{"base": Color8(55, 62, 57), "shade": Color8(38, 43, 40), "accent": Color8(142, 148, 138)},
	{"base": Color8(36, 41, 39), "shade": Color8(26, 30, 29), "accent": Color8(96, 210, 90)},
]


func _initialize() -> void:
	var image := Image.create(TILE_SIZE.x * ATLAS_COLUMNS, TILE_SIZE.y * ATLAS_ROWS, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for tile_index in TILE_PALETTES.size():
		_draw_terrain_tile(image, tile_index)

	for mask in range(16):
		_draw_road_tile(image, mask)
		_draw_mountain_tile(image, mask)

	var output_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Could not save MVP terrain tilesheet: %s" % error)
		quit(1)
		return

	print("Generated %s" % output_path)
	quit(0)


func _draw_terrain_tile(image: Image, tile_index: int) -> void:
	var palette: Dictionary = TILE_PALETTES[tile_index]
	var offset: Vector2i = Vector2i(tile_index * TILE_SIZE.x, 0)
	var center: Vector2 = Vector2(TILE_SIZE.x / 2.0 - 0.5, TILE_SIZE.y / 2.0 - 0.5)

	for y in TILE_SIZE.y:
		for x in TILE_SIZE.x:
			var local: Vector2 = Vector2(x, y)
			var diamond_distance: float = abs(local.x - center.x) / 16.0 + abs(local.y - center.y) / 8.0
			if diamond_distance <= 1.0:
				var color: Color = palette["base"]
				if y > TILE_SIZE.y / 2:
					color = color.darkened(0.13)
				if _hash_noise(x, y, tile_index) > 0.78:
					color = color.lightened(0.12)
				image.set_pixel(offset.x + x, offset.y + y, color)

	_draw_diamond_outline(image, offset, Color8(15, 18, 16, 210))
	_draw_tile_details(image, tile_index, offset, palette)


func _draw_road_tile(image: Image, mask: int) -> void:
	var offset: Vector2i = Vector2i(mask * TILE_SIZE.x, TILE_SIZE.y)
	var palette: Dictionary = {
		"base": Color8(46, 49, 47),
		"shade": Color8(32, 35, 34),
		"accent": Color8(198, 127, 38),
	}
	_fill_diamond(image, offset, palette["base"], palette["shade"], 24 + mask)
	_draw_diamond_outline(image, offset, Color8(13, 15, 14, 220))

	var center: Vector2i = Vector2i(16, 8)
	var road_color: Color = Color8(76, 78, 73)
	var road_edge: Color = Color8(28, 30, 29)
	var stripe: Color = palette["accent"]

	_draw_thick_line(image, offset, center, center, 5, road_color)
	if mask == 0:
		_draw_disc(image, offset, center, 4, road_color)
	else:
		if mask & ROAD_NORTH:
			_draw_thick_line(image, offset, center, Vector2i(24, 4), 4, road_color)
			_draw_line(image, offset, center, Vector2i(24, 4), stripe)
		if mask & ROAD_EAST:
			_draw_thick_line(image, offset, center, Vector2i(24, 12), 4, road_color)
			_draw_line(image, offset, center, Vector2i(24, 12), stripe)
		if mask & ROAD_SOUTH:
			_draw_thick_line(image, offset, center, Vector2i(8, 12), 4, road_color)
			_draw_line(image, offset, center, Vector2i(8, 12), stripe)
		if mask & ROAD_WEST:
			_draw_thick_line(image, offset, center, Vector2i(8, 4), 4, road_color)
			_draw_line(image, offset, center, Vector2i(8, 4), stripe)

	for point in [Vector2i(11, 8), Vector2i(21, 8), Vector2i(16, 5), Vector2i(16, 11)]:
		_set_pixel_safe(image, offset.x + point.x, offset.y + point.y, road_edge)


func _draw_mountain_tile(image: Image, mask: int) -> void:
	var offset: Vector2i = Vector2i(mask * TILE_SIZE.x, TILE_SIZE.y * 2)
	var palette: Dictionary = {
		"base": Color8(66, 66, 62),
		"shade": Color8(36, 38, 37),
		"accent": Color8(126, 132, 126),
	}
	_fill_diamond(image, offset, Color8(40, 44, 39), Color8(29, 32, 30), 80 + mask)
	_draw_diamond_outline(image, offset, Color8(12, 14, 13, 220))

	var north_open: bool = (mask & ROAD_NORTH) == 0
	var east_open: bool = (mask & ROAD_EAST) == 0
	var south_open: bool = (mask & ROAD_SOUTH) == 0
	var west_open: bool = (mask & ROAD_WEST) == 0
	var peak: Vector2i = Vector2i(16, 2)
	var left_base: Vector2i = Vector2i(6 if west_open else 1, 10)
	var right_base: Vector2i = Vector2i(26 if east_open else 31, 10)
	var lower_base: Vector2i = Vector2i(16, 15 if south_open else 13)

	_fill_triangle(image, offset, peak, left_base, lower_base, palette["shade"], 81 + mask)
	_fill_triangle(image, offset, peak, lower_base, right_base, palette["base"], 97 + mask)
	_draw_line(image, offset, peak, lower_base, palette["accent"])
	if north_open:
		_draw_line(image, offset, Vector2i(11, 5), Vector2i(21, 5), palette["accent"].lightened(0.18))
	if west_open:
		_draw_line(image, offset, peak, left_base, Color8(20, 22, 21))
	if east_open:
		_draw_line(image, offset, peak, right_base, Color8(20, 22, 21))

	for point in [Vector2i(12, 9), Vector2i(18, 7), Vector2i(21, 11), Vector2i(9, 11)]:
		if _hash_noise(point.x, point.y, mask) > 0.28:
			_draw_ore_dot(image, offset, point, Color8(184, 119, 46))


func _fill_diamond(image: Image, offset: Vector2i, base: Color, shade: Color, seed: int) -> void:
	var center: Vector2 = Vector2(TILE_SIZE.x / 2.0 - 0.5, TILE_SIZE.y / 2.0 - 0.5)
	for y in TILE_SIZE.y:
		for x in TILE_SIZE.x:
			var local: Vector2 = Vector2(x, y)
			var diamond_distance: float = abs(local.x - center.x) / 16.0 + abs(local.y - center.y) / 8.0
			if diamond_distance <= 1.0:
				var color: Color = base if y <= TILE_SIZE.y / 2 else shade
				if _hash_noise(x, y, seed) > 0.82:
					color = color.lightened(0.10)
				image.set_pixel(offset.x + x, offset.y + y, color)


func _draw_diamond_outline(image: Image, offset: Vector2i, color: Color) -> void:
	var points: Array[Vector2i] = [Vector2i(16, 0), Vector2i(31, 8), Vector2i(16, 15), Vector2i(0, 8)]
	for i in points.size():
		_draw_line(image, offset, points[i], points[(i + 1) % points.size()], color)


func _draw_tile_details(image: Image, tile_index: int, offset: Vector2i, palette: Dictionary) -> void:
	var accent: Color = palette["accent"]
	if tile_index == 1:
		for point in [Vector2i(10, 7), Vector2i(17, 5), Vector2i(22, 9)]:
			_set_pixel_safe(image, offset.x + point.x, offset.y + point.y, accent)
			_set_pixel_safe(image, offset.x + point.x, offset.y + point.y - 1, accent.lightened(0.2))
	elif tile_index == 2:
		for point in [Vector2i(11, 8), Vector2i(16, 5), Vector2i(21, 8), Vector2i(17, 10)]:
			_draw_crystal(image, offset, point, accent)
	elif tile_index == 3:
		for point in [Vector2i(9, 8), Vector2i(14, 6), Vector2i(18, 9), Vector2i(23, 7)]:
			_draw_ore_dot(image, offset, point, accent)
	elif tile_index == 4:
		_draw_disc(image, offset, Vector2i(16, 8), 4, Color8(15, 72, 80))
		_draw_disc(image, offset, Vector2i(16, 8), 2, accent)
	elif tile_index == 5:
		_draw_line(image, offset, Vector2i(4, 8), Vector2i(28, 8), accent)
		_draw_line(image, offset, Vector2i(8, 6), Vector2i(24, 6), Color8(74, 78, 75))
	elif tile_index == 6:
		_draw_line(image, offset, Vector2i(16, 1), Vector2i(16, 14), accent)
		_draw_line(image, offset, Vector2i(3, 8), Vector2i(29, 8), accent.darkened(0.25))
	elif tile_index == 7:
		for point in [Vector2i(12, 7), Vector2i(16, 6), Vector2i(20, 8)]:
			_set_pixel_safe(image, offset.x + point.x, offset.y + point.y, accent)


func _draw_crystal(image: Image, offset: Vector2i, origin: Vector2i, color: Color) -> void:
	_set_pixel_safe(image, offset.x + origin.x, offset.y + origin.y - 2, color.lightened(0.2))
	_set_pixel_safe(image, offset.x + origin.x, offset.y + origin.y - 1, color)
	_set_pixel_safe(image, offset.x + origin.x - 1, offset.y + origin.y, color.darkened(0.15))
	_set_pixel_safe(image, offset.x + origin.x, offset.y + origin.y, color)
	_set_pixel_safe(image, offset.x + origin.x + 1, offset.y + origin.y, color.lightened(0.1))


func _draw_ore_dot(image: Image, offset: Vector2i, origin: Vector2i, color: Color) -> void:
	_set_pixel_safe(image, offset.x + origin.x, offset.y + origin.y, color)
	_set_pixel_safe(image, offset.x + origin.x + 1, offset.y + origin.y, color.darkened(0.1))
	_set_pixel_safe(image, offset.x + origin.x, offset.y + origin.y + 1, color.darkened(0.25))


func _draw_disc(image: Image, offset: Vector2i, origin: Vector2i, radius: int, color: Color) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if Vector2(x, y).length() <= radius:
				_set_pixel_safe(image, offset.x + origin.x + x, offset.y + origin.y + y, color)


func _fill_triangle(image: Image, offset: Vector2i, a: Vector2i, b: Vector2i, c: Vector2i, color: Color, seed: int) -> void:
	var min_x: int = mini(a.x, mini(b.x, c.x))
	var max_x: int = maxi(a.x, maxi(b.x, c.x))
	var min_y: int = mini(a.y, mini(b.y, c.y))
	var max_y: int = maxi(a.y, maxi(b.y, c.y))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var point := Vector2i(x, y)
			if _point_in_triangle(point, a, b, c):
				var pixel_color: Color = color
				if _hash_noise(x, y, seed) > 0.78:
					pixel_color = color.lightened(0.12)
				_set_pixel_safe(image, offset.x + x, offset.y + y, pixel_color)


func _point_in_triangle(point: Vector2i, a: Vector2i, b: Vector2i, c: Vector2i) -> bool:
	var p := Vector2(point)
	var pa := Vector2(a)
	var pb := Vector2(b)
	var pc := Vector2(c)
	var d1: float = _triangle_sign(p, pa, pb)
	var d2: float = _triangle_sign(p, pb, pc)
	var d3: float = _triangle_sign(p, pc, pa)
	var has_negative: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_positive: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_negative and has_positive)


func _triangle_sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


func _draw_thick_line(image: Image, offset: Vector2i, start: Vector2i, end: Vector2i, radius: int, color: Color) -> void:
	var delta: Vector2i = end - start
	var steps: int = maxi(abs(delta.x), abs(delta.y))
	for i in range(steps + 1):
		var t: float = 0.0 if steps == 0 else float(i) / float(steps)
		var point: Vector2 = Vector2(start).lerp(Vector2(end), t).round()
		_draw_disc(image, offset, Vector2i(int(point.x), int(point.y)), radius / 2, color)


func _draw_line(image: Image, offset: Vector2i, start: Vector2i, end: Vector2i, color: Color) -> void:
	var delta: Vector2i = end - start
	var steps: int = maxi(abs(delta.x), abs(delta.y))
	for i in range(steps + 1):
		var t: float = 0.0 if steps == 0 else float(i) / float(steps)
		var point: Vector2 = Vector2(start).lerp(Vector2(end), t).round()
		_set_pixel_safe(image, offset.x + int(point.x), offset.y + int(point.y), color)


func _set_pixel_safe(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		if image.get_pixel(x, y).a > 0.0:
			image.set_pixel(x, y, color)


func _hash_noise(x: int, y: int, seed: int) -> float:
	var value: int = (x * 928371 + y * 364479 + seed * 15731) & 0xffff
	return float(value % 1000) / 1000.0
