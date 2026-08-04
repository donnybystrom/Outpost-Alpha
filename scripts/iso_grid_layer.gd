extends Node2D

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)

var map_data: RefCounted
var cached_grid_texture: ImageTexture
var cached_grid_offset: Vector2 = Vector2.ZERO
var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_bake_usec: int = 0
var last_redraw_reason: String = ""


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	_bake_grid_texture()
	request_redraw("set_map_data")


func request_redraw(reason: String) -> void:
	redraw_requests += 1
	last_redraw_reason = reason
	queue_redraw()


func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	draw_calls += 1
	last_cells_processed = 0
	if cached_grid_texture == null:
		last_draw_usec = Time.get_ticks_usec() - started
		return

	draw_texture(cached_grid_texture, cached_grid_offset)
	last_draw_usec = Time.get_ticks_usec() - started


func _bake_grid_texture() -> void:
	var started: int = Time.get_ticks_usec()
	last_cells_processed = 0
	if map_data == null:
		cached_grid_texture = null
		last_bake_usec = Time.get_ticks_usec() - started
		return

	var bounds: Rect2i = _map_pixel_bounds()
	var image: Image = Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	cached_grid_offset = Vector2(bounds.position)

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile: Vector2i = Vector2i(x, y)
			last_cells_processed += 1
			var points: Array[Vector2i] = _tile_pixel_polygon(tile, cached_grid_offset)
			for i in points.size():
				_draw_line_on_image(image, points[i], points[(i + 1) % points.size()], Color8(16, 18, 17, 125))

	cached_grid_texture = ImageTexture.create_from_image(image)
	last_bake_usec = Time.get_ticks_usec() - started


func _tile_pixel_polygon(tile: Vector2i, offset: Vector2) -> Array[Vector2i]:
	var origin: Vector2 = map_to_screen(tile)
	return [
		Vector2i((origin + Vector2(0, -HALF_TILE.y) - offset).round()),
		Vector2i((origin + Vector2(HALF_TILE.x, 0) - offset).round()),
		Vector2i((origin + Vector2(0, HALF_TILE.y) - offset).round()),
		Vector2i((origin + Vector2(-HALF_TILE.x, 0) - offset).round()),
	]


func _draw_line_on_image(image: Image, start: Vector2i, end: Vector2i, color: Color) -> void:
	var delta: Vector2i = end - start
	var steps: int = maxi(abs(delta.x), abs(delta.y))
	for i in range(steps + 1):
		var t: float = 0.0 if steps == 0 else float(i) / float(steps)
		var point: Vector2 = Vector2(start).lerp(Vector2(end), t).round()
		_blend_pixel(image, Vector2i(int(point.x), int(point.y)), color)


func _blend_pixel(image: Image, point: Vector2i, color: Color) -> void:
	if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
		return

	var existing: Color = image.get_pixel(point.x, point.y)
	var alpha: float = color.a + existing.a * (1.0 - color.a)
	if alpha <= 0.0:
		return
	image.set_pixel(point.x, point.y, Color(
		(color.r * color.a + existing.r * existing.a * (1.0 - color.a)) / alpha,
		(color.g * color.a + existing.g * existing.a * (1.0 - color.a)) / alpha,
		(color.b * color.a + existing.b * existing.a * (1.0 - color.a)) / alpha,
		alpha
	))


func _map_pixel_bounds() -> Rect2i:
	var min_point: Vector2 = Vector2(1.0e20, 1.0e20)
	var max_point: Vector2 = Vector2(-1.0e20, -1.0e20)
	for tile in [
		Vector2i(0, 0),
		Vector2i(map_data.size.x - 1, 0),
		Vector2i(0, map_data.size.y - 1),
		Vector2i(map_data.size.x - 1, map_data.size.y - 1),
	]:
		var top_left: Vector2 = map_to_screen(tile) - HALF_TILE
		var bottom_right: Vector2 = top_left + Vector2(TILE_SIZE)
		min_point.x = minf(min_point.x, top_left.x)
		min_point.y = minf(min_point.y, top_left.y)
		max_point.x = maxf(max_point.x, bottom_right.x)
		max_point.y = maxf(max_point.y, bottom_right.y)
	return Rect2i(
		Vector2i(floori(min_point.x), floori(min_point.y)),
		Vector2i(ceili(max_point.x - min_point.x), ceili(max_point.y - min_point.y))
	)


func map_to_screen(tile: Vector2i) -> Vector2:
	return Vector2(
		float(tile.x - tile.y) * HALF_TILE.x,
		float(tile.x + tile.y) * HALF_TILE.y
	)


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": draw_calls,
		"redraw_requests": redraw_requests,
		"last_draw_usec": last_draw_usec,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_bake_usec,
		"last_reason": last_redraw_reason,
	}
