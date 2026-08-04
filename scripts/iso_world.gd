extends Node2D

signal tile_changed(tile: Vector2i, terrain_name: String)

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
const MAP_SIZE := Vector2i(42, 42)

const TERRAIN_NAMES := {
	0: "Basalt plain",
	1: "Alien scrub",
	2: "Crystal growth",
	3: "Ore ridge",
	4: "Geothermal vent",
}

const TERRAIN_COLORS := {
	0: Color8(48, 54, 45),
	1: Color8(55, 75, 36),
	2: Color8(58, 42, 74),
	3: Color8(78, 67, 48),
	4: Color8(38, 78, 82),
}

var tiles: Array[Array] = []
var hovered_tile := Vector2i(-1, -1)
var selected_tile := Vector2i(10, 10)
var show_grid := true


func _ready() -> void:
	position = Vector2.ZERO
	_generate_map()
	set_process_unhandled_input(true)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next_hover := screen_to_map(get_global_mouse_position())
		if next_hover != hovered_tile:
			hovered_tile = next_hover
			if _is_inside_map(hovered_tile):
				tile_changed.emit(hovered_tile, _terrain_name(hovered_tile))
			queue_redraw()

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
			var clicked := screen_to_map(get_global_mouse_position())
			if _is_inside_map(clicked):
				selected_tile = clicked
				tile_changed.emit(selected_tile, _terrain_name(selected_tile))
				queue_redraw()

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_G:
			show_grid = not show_grid
			queue_redraw()


func _draw() -> void:
	for y in MAP_SIZE.y:
		for x in MAP_SIZE.x:
			var tile := Vector2i(x, y)
			_draw_tile(tile, tiles[y][x])

	_draw_demo_objects()
	_draw_selection(hovered_tile, Color8(130, 210, 76, 130))
	_draw_selection(selected_tile, Color8(245, 164, 45, 180), 2.0)


func _generate_map() -> void:
	tiles.clear()
	var noise := FastNoiseLite.new()
	noise.seed = 1701
	noise.frequency = 0.095
	noise.fractal_octaves = 3

	for y in MAP_SIZE.y:
		var row: Array[int] = []
		for x in MAP_SIZE.x:
			var n := noise.get_noise_2d(float(x), float(y))
			var terrain := 0
			if n > 0.38:
				terrain = 2
			elif n > 0.12:
				terrain = 1
			elif n < -0.48:
				terrain = 3
			row.append(terrain)
		tiles.append(row)

	for vent in [Vector2i(8, 15), Vector2i(28, 11), Vector2i(20, 30)]:
		tiles[vent.y][vent.x] = 4


func _draw_tile(tile: Vector2i, terrain: int) -> void:
	var origin := map_to_screen(tile)
	var points := PackedVector2Array([
		origin + Vector2(0, -HALF_TILE.y),
		origin + Vector2(HALF_TILE.x, 0),
		origin + Vector2(0, HALF_TILE.y),
		origin + Vector2(-HALF_TILE.x, 0),
	])
	var color: Color = TERRAIN_COLORS[terrain]
	var shade := 1.0 - float(tile.y) / float(MAP_SIZE.y) * 0.18
	color = color.darkened(1.0 - shade)

	draw_colored_polygon(points, color)
	if show_grid:
		draw_polyline(points + PackedVector2Array([points[0]]), Color8(16, 18, 17, 120), 1.0)

	if terrain == 2:
		_draw_growth(origin, Color8(160, 52, 170), Color8(42, 214, 218))
	elif terrain == 3:
		_draw_ore(origin)
	elif terrain == 4:
		_draw_vent(origin)


func _draw_demo_objects() -> void:
	_draw_road(Vector2i(12, 16), 10, false)
	_draw_road(Vector2i(12, 16), 9, true)
	_draw_building(Vector2i(16, 18), Vector2(2, 2), Color8(82, 88, 84), Color8(255, 150, 28), "GEN")
	_draw_building(Vector2i(22, 16), Vector2(3, 2), Color8(72, 78, 83), Color8(234, 136, 31), "ORE")
	_draw_building(Vector2i(18, 24), Vector2(3, 2), Color8(52, 82, 62), Color8(92, 210, 84), "FOOD")
	_draw_vehicle(Vector2i(14, 20), Color8(205, 129, 34))
	_draw_vehicle(Vector2i(24, 19), Color8(205, 129, 34))
	_draw_beacon(Vector2i(8, 15), Color8(45, 216, 230))


func _draw_road(start: Vector2i, length: int, vertical: bool) -> void:
	for i in length:
		var tile := start + (Vector2i(0, i) if vertical else Vector2i(i, 0))
		var origin := map_to_screen(tile)
		var points := PackedVector2Array([
			origin + Vector2(0, -5),
			origin + Vector2(10, 0),
			origin + Vector2(0, 5),
			origin + Vector2(-10, 0),
		])
		draw_colored_polygon(points, Color8(54, 58, 55))
		draw_polyline(points + PackedVector2Array([points[0]]), Color8(196, 126, 38, 150), 1.0)


func _draw_building(tile: Vector2i, footprint: Vector2, base_color: Color, accent: Color, label: String) -> void:
	var origin := map_to_screen(tile)
	var width := TILE_SIZE.x * footprint.x * 0.52
	var height := TILE_SIZE.y * footprint.y * 0.78
	var base := PackedVector2Array([
		origin + Vector2(0, -height * 0.55),
		origin + Vector2(width * 0.5, -height * 0.18),
		origin + Vector2(width * 0.5, height * 0.34),
		origin + Vector2(0, height * 0.70),
		origin + Vector2(-width * 0.5, height * 0.34),
		origin + Vector2(-width * 0.5, -height * 0.18),
	])
	draw_colored_polygon(base, base_color)
	draw_polyline(base + PackedVector2Array([base[0]]), Color8(22, 22, 20), 1.0)
	draw_line(origin + Vector2(-width * 0.35, -height * 0.05), origin + Vector2(width * 0.35, -height * 0.05), accent, 2.0)
	draw_circle(origin + Vector2(width * 0.22, -height * 0.20), 3.0, accent)


func _draw_vehicle(tile: Vector2i, accent: Color) -> void:
	var origin := map_to_screen(tile) + Vector2(0, -5)
	var body := Rect2(origin - Vector2(10, 5), Vector2(20, 10))
	draw_rect(body, Color8(42, 46, 47), true)
	draw_rect(body, Color8(9, 10, 10), false, 1.0)
	draw_line(origin + Vector2(-5, -3), origin + Vector2(7, -3), accent, 2.0)
	draw_circle(origin + Vector2(-6, 5), 2.0, Color8(16, 16, 15))
	draw_circle(origin + Vector2(7, 5), 2.0, Color8(16, 16, 15))


func _draw_growth(origin: Vector2, primary: Color, secondary: Color) -> void:
	draw_circle(origin + Vector2(-4, 0), 2.5, primary)
	draw_circle(origin + Vector2(3, -2), 2.0, primary.lightened(0.2))
	draw_line(origin + Vector2(1, 2), origin + Vector2(2, -7), secondary, 1.0)


func _draw_ore(origin: Vector2) -> void:
	draw_circle(origin + Vector2(-4, 1), 2.5, Color8(166, 91, 26))
	draw_circle(origin + Vector2(3, -1), 2.0, Color8(215, 119, 32))
	draw_circle(origin + Vector2(0, 3), 1.8, Color8(108, 71, 48))


func _draw_vent(origin: Vector2) -> void:
	draw_circle(origin, 4.0, Color8(20, 86, 90))
	draw_circle(origin, 2.0, Color8(71, 229, 238))
	draw_line(origin + Vector2(0, -4), origin + Vector2(0, -17), Color8(78, 215, 232, 150), 1.0)


func _draw_beacon(tile: Vector2i, color: Color) -> void:
	var origin := map_to_screen(tile)
	draw_circle(origin + Vector2(0, -18), 5.0, Color(color.r, color.g, color.b, 0.24))
	draw_line(origin + Vector2(0, -8), origin + Vector2(0, -34), Color(color.r, color.g, color.b, 0.55), 2.0)


func _draw_selection(tile: Vector2i, color: Color, width: float = 1.0) -> void:
	if not _is_inside_map(tile):
		return

	var origin := map_to_screen(tile)
	var points := PackedVector2Array([
		origin + Vector2(0, -HALF_TILE.y),
		origin + Vector2(HALF_TILE.x, 0),
		origin + Vector2(0, HALF_TILE.y),
		origin + Vector2(-HALF_TILE.x, 0),
	])
	draw_polyline(points + PackedVector2Array([points[0]]), color, width)


func map_to_screen(tile: Vector2i) -> Vector2:
	return Vector2(
		float(tile.x - tile.y) * HALF_TILE.x,
		float(tile.x + tile.y) * HALF_TILE.y
	)


func get_map_bounds() -> Rect2:
	var points: Array[Vector2] = [
		map_to_screen(Vector2i(0, 0)) + Vector2(0, -HALF_TILE.y),
		map_to_screen(Vector2i(MAP_SIZE.x - 1, 0)) + Vector2(HALF_TILE.x, 0),
		map_to_screen(Vector2i(0, MAP_SIZE.y - 1)) + Vector2(-HALF_TILE.x, 0),
		map_to_screen(Vector2i(MAP_SIZE.x - 1, MAP_SIZE.y - 1)) + Vector2(0, HALF_TILE.y),
	]
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)


func screen_to_map(screen_position: Vector2) -> Vector2i:
	var map_x := (screen_position.y / TILE_SIZE.y) + (screen_position.x / TILE_SIZE.x)
	var map_y := (screen_position.y / TILE_SIZE.y) - (screen_position.x / TILE_SIZE.x)
	return Vector2i(floori(map_x + 0.5), floori(map_y + 0.5))


func _is_inside_map(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < MAP_SIZE.x and tile.y < MAP_SIZE.y


func _terrain_name(tile: Vector2i) -> String:
	return TERRAIN_NAMES[tiles[tile.y][tile.x]]
