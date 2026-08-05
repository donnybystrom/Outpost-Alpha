extends SceneTree

const TILE_SIZE := Vector2i(32, 16)
const ATLAS_COLUMNS := 16
const MOUNTAIN_ATLAS_ROW := 2
const TARGET_ATLAS_PATH := "res://assets/tiles/terrain_32x16.png"

const DEFAULT_SCAN_TOP_RATIO := 0.56
const DEFAULT_SCAN_BOTTOM_RATIO := 0.76
const FOREGROUND_THRESHOLD := 24
const GROUP_GAP_TOLERANCE := 14
const MIN_GROUP_WIDTH := 30


func _initialize() -> void:
	var source_path := _argument_value("--source")
	if source_path.is_empty():
		push_error("Missing --source=/absolute/path/to/source.png")
		quit(1)
		return

	var source := Image.new()
	var source_error := source.load(source_path)
	if source_error != OK:
		push_error("Could not load source image: %s" % source_error)
		quit(1)
		return

	var atlas_path := ProjectSettings.globalize_path(TARGET_ATLAS_PATH)
	var atlas := Image.new()
	var atlas_error := atlas.load(atlas_path)
	if atlas_error != OK:
		push_error("Could not load target atlas: %s" % atlas_error)
		quit(1)
		return

	var source_regions := _find_bottom_sprite_regions(source)
	if source_regions.size() < ATLAS_COLUMNS:
		push_error("Expected at least %d mountain sprites, found %d." % [ATLAS_COLUMNS, source_regions.size()])
		quit(1)
		return

	for mask in range(ATLAS_COLUMNS):
		var sprite := _extract_sprite(source, source_regions[mask])
		var tile := _fit_sprite_to_tile(sprite, mask)
		var target := Vector2i(mask * TILE_SIZE.x, MOUNTAIN_ATLAS_ROW * TILE_SIZE.y)
		atlas.blit_rect(tile, Rect2i(Vector2i.ZERO, TILE_SIZE), target)

	var save_error := atlas.save_png(atlas_path)
	if save_error != OK:
		push_error("Could not save target atlas: %s" % save_error)
		quit(1)
		return

	print("Imported %d mountain sprites into %s" % [ATLAS_COLUMNS, atlas_path])
	quit(0)


func _argument_value(name: String) -> String:
	for argument in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if argument.begins_with(name + "="):
			return argument.substr(name.length() + 1)
	return ""


func _find_bottom_sprite_regions(image: Image) -> Array[Rect2i]:
	var scan_top := int(float(image.get_height()) * DEFAULT_SCAN_TOP_RATIO)
	var scan_bottom := int(float(image.get_height()) * DEFAULT_SCAN_BOTTOM_RATIO)
	var active_columns: Array[int] = []

	for x in image.get_width():
		var has_foreground := false
		for y in range(scan_top, scan_bottom):
			if _is_foreground(image.get_pixel(x, y)):
				has_foreground = true
				break
		if has_foreground:
			active_columns.append(x)

	var x_ranges := _group_columns(active_columns)
	var regions: Array[Rect2i] = []
	for x_range in x_ranges:
		var region := _region_for_range(image, x_range.x, x_range.y, scan_top, scan_bottom)
		if region.size.x >= MIN_GROUP_WIDTH:
			regions.append(region)

	regions.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
	if regions.size() < ATLAS_COLUMNS and not active_columns.is_empty():
		regions = _slot_regions_from_bounds(image, active_columns[0], active_columns[active_columns.size() - 1], scan_top, scan_bottom)
	return regions


func _slot_regions_from_bounds(image: Image, x_start: int, x_end: int, y_start: int, y_end: int) -> Array[Rect2i]:
	var regions: Array[Rect2i] = []
	var total_width := x_end - x_start + 1
	var slot_width := float(total_width) / float(ATLAS_COLUMNS)

	for index in range(ATLAS_COLUMNS):
		var slot_start := x_start + int(floor(slot_width * float(index)))
		var slot_end := x_start + int(ceil(slot_width * float(index + 1))) - 1
		var region := _region_for_range(image, slot_start, slot_end, y_start, y_end)
		if region.size.x <= 1 or region.size.y <= 1:
			region = Rect2i(Vector2i(slot_start, y_start), Vector2i(maxi(1, slot_end - slot_start + 1), y_end - y_start))
		regions.append(region)

	return regions


func _group_columns(columns: Array[int]) -> Array[Vector2i]:
	var ranges: Array[Vector2i] = []
	if columns.is_empty():
		return ranges

	var start := columns[0]
	var previous := columns[0]
	for index in range(1, columns.size()):
		var column := columns[index]
		if column - previous > GROUP_GAP_TOLERANCE:
			ranges.append(Vector2i(start, previous))
			start = column
		previous = column
	ranges.append(Vector2i(start, previous))
	return ranges


func _region_for_range(image: Image, x_start: int, x_end: int, y_start: int, y_end: int) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := 0
	var max_y := 0

	for y in range(y_start, y_end):
		for x in range(x_start, x_end + 1):
			if _is_foreground(image.get_pixel(x, y)):
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)

	var padding := 3
	min_x = maxi(0, min_x - padding)
	min_y = maxi(0, min_y - padding)
	max_x = mini(image.get_width() - 1, max_x + padding)
	max_y = mini(image.get_height() - 1, max_y + padding)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))


func _extract_sprite(image: Image, region: Rect2i) -> Image:
	var sprite := Image.create(region.size.x, region.size.y, false, Image.FORMAT_RGBA8)
	sprite.fill(Color(0, 0, 0, 0))

	for y in region.size.y:
		for x in region.size.x:
			var color := image.get_pixel(region.position.x + x, region.position.y + y)
			if _is_foreground(color):
				color.a = _alpha_for_source_pixel(color)
				sprite.set_pixel(x, y, color)

	return sprite


func _fit_sprite_to_tile(sprite: Image, mask: int) -> Image:
	var tile := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	tile.fill(Color(0, 0, 0, 0))

	var normalized := sprite.duplicate()
	var scale := minf(float(TILE_SIZE.x - 2) / float(sprite.get_width()), float(TILE_SIZE.y - 1) / float(sprite.get_height()))
	var scaled_size := Vector2i(
		maxi(1, int(round(sprite.get_width() * scale))),
		maxi(1, int(round(sprite.get_height() * scale)))
	)
	normalized.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_LANCZOS)

	var target := Vector2i(
		int((TILE_SIZE.x - scaled_size.x) / 2.0),
		TILE_SIZE.y - scaled_size.y
	)
	tile.blend_rect(normalized, Rect2i(Vector2i.ZERO, scaled_size), target)
	_draw_mountain_mask_hint(tile, mask)
	return tile


func _draw_mountain_mask_hint(tile: Image, mask: int) -> void:
	var rock_edge := Color8(112, 118, 111, 190)
	var shadow := Color8(18, 21, 20, 190)
	_draw_line(tile, Vector2i(16, 0), Vector2i(31, 8), shadow)
	_draw_line(tile, Vector2i(31, 8), Vector2i(16, 15), shadow)
	_draw_line(tile, Vector2i(16, 15), Vector2i(0, 8), shadow)
	_draw_line(tile, Vector2i(0, 8), Vector2i(16, 0), shadow)

	if mask & 1:
		_draw_line(tile, Vector2i(16, 3), Vector2i(24, 6), rock_edge)
	if mask & 2:
		_draw_line(tile, Vector2i(22, 8), Vector2i(28, 9), rock_edge)
	if mask & 4:
		_draw_line(tile, Vector2i(16, 12), Vector2i(8, 10), rock_edge)
	if mask & 8:
		_draw_line(tile, Vector2i(10, 8), Vector2i(4, 7), rock_edge)


func _draw_line(image: Image, start: Vector2i, end: Vector2i, color: Color) -> void:
	var delta := end - start
	var steps := maxi(abs(delta.x), abs(delta.y))
	for i in range(steps + 1):
		var t := 0.0 if steps == 0 else float(i) / float(steps)
		var point := Vector2(start).lerp(Vector2(end), t).round()
		_set_pixel_safe(image, int(point.x), int(point.y), color)


func _set_pixel_safe(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		var existing := image.get_pixel(x, y)
		image.set_pixel(x, y, existing.blend(color))


func _is_foreground(color: Color) -> bool:
	return color.a > 0.0 and maxf(color.r, maxf(color.g, color.b)) > float(FOREGROUND_THRESHOLD) / 255.0


func _alpha_for_source_pixel(color: Color) -> float:
	var brightness := maxf(color.r, maxf(color.g, color.b))
	return clampf((brightness - 0.04) / 0.18, 0.0, 1.0)
