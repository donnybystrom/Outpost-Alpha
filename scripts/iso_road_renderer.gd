extends Node2D

const AutoTile := preload("res://scripts/auto_tile.gd")
const AutoTileAtlas := preload("res://scripts/autotile_atlas.gd")

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
const TERRAIN_ATLAS_TEXTURE: Texture2D = preload(
	"res://assets/tiles/terrain_32x16.png"
)

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

	atlas = TERRAIN_ATLAS_TEXTURE
	atlas_image = atlas.get_image()

	if atlas_image == null or atlas_image.is_empty():
		push_error("Could not retrieve terrain atlas image")
		return

	if atlas_image.is_compressed():
		var error := atlas_image.decompress()
		if error != OK:
			push_error("Could not decompress terrain atlas: %s" % error)
			return

	if atlas_image.get_format() != Image.FORMAT_RGBA8:
		atlas_image.convert(Image.FORMAT_RGBA8)

	_bake_road_texture()
	request_redraw("ready")



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

	var clear_tiles: Array[Vector2i] = _valid_unique_tiles(tiles)
	var repaint_tiles: Array[Vector2i] = _road_tiles_overlapping_clear_tiles(clear_tiles)

	for tile in clear_tiles:
		if not map_data.is_inside(tile):
			continue
		_clear_road_tile(tile)
	for tile in repaint_tiles:
		if map_data.has_road(tile):
			_blit_road_tile(tile)
		last_cells_processed += 1

	cached_road_texture.update(cached_road_image)
	last_bake_usec = Time.get_ticks_usec() - started


func _clear_road_tile(tile: Vector2i) -> void:
	var target: Vector2i = _tile_target_position(tile)
	cached_road_image.fill_rect(Rect2i(target, TILE_SIZE), Color(0, 0, 0, 0))


func _blit_road_tile(tile: Vector2i) -> void:
	# The legacy 2D atlas only contains the 16 cardinal variants. The active 3D
	# renderer handles all eight road directions.
	var road_mask: int = AutoTile.road_mask(map_data, tile) & AutoTile.CARDINAL_MASK
	var source_rect: Rect2i = Rect2i(Vector2i(AutoTileAtlas.road_column(road_mask), ROAD_ATLAS_ROW) * TILE_SIZE, TILE_SIZE)
	cached_road_image.blend_rect(atlas_image, source_rect, _tile_target_position(tile))


func _tile_target_position(tile: Vector2i) -> Vector2i:
	return Vector2i((map_to_screen(tile) - HALF_TILE - cached_road_offset).round())


func _road_sprite_rect(tile: Vector2i) -> Rect2i:
	return Rect2i(_tile_target_position(tile), TILE_SIZE)


func _valid_unique_tiles(tiles: Array[Vector2i]) -> Array[Vector2i]:
	var unique_tiles: Array[Vector2i] = []
	for tile in tiles:
		if map_data != null and map_data.is_inside(tile) and not unique_tiles.has(tile):
			unique_tiles.append(tile)
	return unique_tiles


func _road_tiles_overlapping_clear_tiles(clear_tiles: Array[Vector2i]) -> Array[Vector2i]:
	var repaint_tiles: Array[Vector2i] = []
	for clear_tile in clear_tiles:
		var clear_rect: Rect2i = _road_sprite_rect(clear_tile)
		for y in range(clear_tile.y - 2, clear_tile.y + 3):
			for x in range(clear_tile.x - 2, clear_tile.x + 3):
				var candidate := Vector2i(x, y)
				if not map_data.is_inside(candidate):
					continue
				if not map_data.has_road(candidate):
					continue
				if repaint_tiles.has(candidate):
					continue
				if _road_sprite_rect(candidate).intersects(clear_rect):
					repaint_tiles.append(candidate)
	return repaint_tiles


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
