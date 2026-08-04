extends Node2D

const AutoTile := preload("res://scripts/auto_tile.gd")

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
const ATLAS_PATH := "res://assets/tiles/terrain_32x16.png"
const ROAD_ATLAS_ROW := 1

var map_data: RefCounted
var atlas: Texture2D
var atlas_image: Image
var cached_road_image: Image
var cached_road_texture: ImageTexture
var cached_road_offset: Vector2 = Vector2.ZERO
var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_bake_usec: int = 0
var last_redraw_reason: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	atlas_image = _load_atlas_image()
	if atlas_image != null:
		atlas = ImageTexture.create_from_image(atlas_image)
	_bake_road_texture()
	request_redraw("ready")


func _load_atlas_image() -> Image:
	var image: Image = Image.new()
	var error: Error = image.load(ProjectSettings.globalize_path(ATLAS_PATH))
	if error != OK:
		push_error("Could not load terrain atlas image: %s" % error)
		return null

	return image


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	_bake_road_texture()
	request_redraw("set_map_data")


func notify_road_changed(tile: Vector2i) -> void:
	_update_dirty_road_tiles(_affected_road_tiles(tile))
	request_redraw("road_edit")


func notify_roads_changed(tiles: Array[Vector2i]) -> void:
	var dirty_tiles: Array[Vector2i] = []
	for tile in tiles:
		for affected_tile in _affected_road_tiles(tile):
			if not dirty_tiles.has(affected_tile):
				dirty_tiles.append(affected_tile)
	_update_dirty_road_tiles(dirty_tiles)
	request_redraw("road_batch_edit")


func refresh_road_tiles(reason: String) -> void:
	_bake_road_texture()
	request_redraw(reason)


func request_redraw(reason: String) -> void:
	redraw_requests += 1
	last_redraw_reason = reason
	queue_redraw()


func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	draw_calls += 1
	last_cells_processed = 0
	if cached_road_texture == null:
		last_draw_usec = Time.get_ticks_usec() - started
		return

	draw_texture(cached_road_texture, cached_road_offset)
	last_draw_usec = Time.get_ticks_usec() - started


func _bake_road_texture() -> void:
	var started: int = Time.get_ticks_usec()
	last_cells_processed = 0
	if map_data == null or atlas_image == null:
		cached_road_image = null
		cached_road_texture = null
		last_bake_usec = Time.get_ticks_usec() - started
		return

	var bounds: Rect2i = _map_pixel_bounds()
	cached_road_image = Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	cached_road_image.fill(Color(0, 0, 0, 0))
	cached_road_offset = Vector2(bounds.position)

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile: Vector2i = Vector2i(x, y)
			if map_data.has_road(tile):
				_blit_road_tile(tile)
			last_cells_processed += 1

	cached_road_texture = ImageTexture.create_from_image(cached_road_image)
	last_bake_usec = Time.get_ticks_usec() - started


func _update_dirty_road_tiles(tiles: Array[Vector2i]) -> void:
	var started: int = Time.get_ticks_usec()
	last_cells_processed = 0
	if cached_road_image == null or cached_road_texture == null:
		_bake_road_texture()
		return

	for tile in tiles:
		if not map_data.is_inside(tile):
			continue
		_clear_road_tile(tile)
	for tile in tiles:
		if not map_data.is_inside(tile):
			continue
		if map_data.has_road(tile):
			_blit_road_tile(tile)
		last_cells_processed += 1

	cached_road_texture.update(cached_road_image)
	last_bake_usec = Time.get_ticks_usec() - started


func _clear_road_tile(tile: Vector2i) -> void:
	var target: Vector2i = _tile_target_position(tile)
	cached_road_image.fill_rect(Rect2i(target, TILE_SIZE), Color(0, 0, 0, 0))


func _blit_road_tile(tile: Vector2i) -> void:
	var road_mask: int = AutoTile.road_mask(map_data, tile)
	var source_rect: Rect2i = Rect2i(Vector2i(road_mask, ROAD_ATLAS_ROW) * TILE_SIZE, TILE_SIZE)
	cached_road_image.blend_rect(atlas_image, source_rect, _tile_target_position(tile))


func _tile_target_position(tile: Vector2i) -> Vector2i:
	return Vector2i((map_to_screen(tile) - HALF_TILE - cached_road_offset).round())


func _affected_road_tiles(tile: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [tile]
	for bit in AutoTile.CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = tile + AutoTile.CARDINAL_DIRECTIONS[bit]
		if map_data != null and map_data.is_inside(neighbor):
			tiles.append(neighbor)
	return tiles


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
