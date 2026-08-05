extends Node2D

const AutoTile := preload("res://scripts/auto_tile.gd")
const AutoTileAtlas := preload("res://scripts/autotile_atlas.gd")
const TERRAIN_ATLAS_TEXTURE: Texture2D = preload(
	"res://assets/tiles/terrain_32x16.png"
)

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)

const TERRAIN_MOUNTAIN := 5
const TERRAIN_ATLAS := {
	0: Vector2i(0, 0),
	1: Vector2i(1, 0),
	2: Vector2i(2, 0),
	3: Vector2i(3, 0),
	4: Vector2i(4, 0),
}
const ROAD_ATLAS_ROW := 1
const MOUNTAIN_ATLAS_ROW := 2

var map_data: RefCounted
var atlas: Texture2D
var atlas_image: Image
var cached_map_texture: ImageTexture
var cached_map_offset: Vector2 = Vector2.ZERO
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

	_bake_map_texture()
	request_redraw("ready")


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	_bake_map_texture()
	request_redraw("set_map_data")


func request_redraw(reason: String) -> void:
	redraw_requests += 1
	last_redraw_reason = reason
	queue_redraw()


func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	draw_calls += 1
	last_cells_processed = 0
	if cached_map_texture == null:
		last_draw_usec = Time.get_ticks_usec() - started
		return

	draw_texture(cached_map_texture, cached_map_offset)
	last_draw_usec = Time.get_ticks_usec() - started


func _bake_map_texture() -> void:
	var started: int = Time.get_ticks_usec()
	last_cells_processed = 0
	if map_data == null or atlas_image == null:
		cached_map_texture = null
		last_bake_usec = Time.get_ticks_usec() - started
		return

	var bounds: Rect2i = _map_pixel_bounds()
	var image: Image = Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	cached_map_offset = Vector2(bounds.position)

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile: Vector2i = Vector2i(x, y)
			var terrain_id: int = map_data.get_terrain(tile)
			var atlas_coords: Vector2i = _terrain_atlas_coords(tile, terrain_id)
			var source_rect: Rect2i = Rect2i(atlas_coords * TILE_SIZE, TILE_SIZE)
			var target: Vector2i = Vector2i((map_to_screen(tile) - HALF_TILE - cached_map_offset).round())
			image.blend_rect(atlas_image, source_rect, target)
			last_cells_processed += 1

	cached_map_texture = ImageTexture.create_from_image(image)
	last_bake_usec = Time.get_ticks_usec() - started


func _terrain_atlas_coords(tile: Vector2i, terrain_id: int) -> Vector2i:
	if terrain_id == TERRAIN_MOUNTAIN:
		return Vector2i(AutoTileAtlas.mountain_column(AutoTile.same_terrain_mask(map_data, tile)), MOUNTAIN_ATLAS_ROW)
	return TERRAIN_ATLAS.get(terrain_id, Vector2i.ZERO)


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
	return Rect2i(Vector2i(floori(min_point.x), floori(min_point.y)), Vector2i(ceili(max_point.x - min_point.x), ceili(max_point.y - min_point.y)))


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
