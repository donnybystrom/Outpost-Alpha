extends Node2D

const IsoTileRenderer := preload("res://scripts/iso_tile_renderer.gd")
const AutoTile := preload("res://scripts/auto_tile.gd")
const AutoTileAtlas := preload("res://scripts/autotile_atlas.gd")

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
const PAINT_TOOL_NONE := "none"
const PAINT_TOOL_ROAD := "road"
const PAINT_TOOL_TERRAIN_PREFIX := "terrain:"
const PAINT_TOOL_BUILDING_PREFIX := "building:"

var map_data: RefCounted
var road_atlas: Texture2D
var hovered_tile := Vector2i(-1, -1)
var selected_tile := Vector2i(-1, -1)
var paint_tool := PAINT_TOOL_NONE
var dev_mode: bool = false
var is_line_painting: bool = false
var line_preview_tiles: Array[Vector2i] = []
var placement_feedback: Array[Dictionary] = []
var selection_rect := Rect2()
var selection_rect_visible := false

var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_redraw_reason: String = ""


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	request_redraw("set_map_data")


func set_road_atlas(next_road_atlas: Texture2D) -> void:
	road_atlas = next_road_atlas
	request_redraw("set_road_atlas")


func set_hovered_tile(tile: Vector2i) -> void:
	if hovered_tile == tile:
		return
	hovered_tile = tile
	request_redraw("hover")


func set_selected_tile(tile: Vector2i) -> void:
	if selected_tile == tile:
		return
	selected_tile = tile
	request_redraw("select")


func set_paint_tool(next_tool: String, next_dev_mode: bool) -> void:
	if paint_tool == next_tool and dev_mode == next_dev_mode:
		return
	paint_tool = next_tool
	dev_mode = next_dev_mode
	request_redraw("paint_tool")


func set_line_preview(next_line_preview_tiles: Array[Vector2i], next_is_line_painting: bool) -> void:
	line_preview_tiles = next_line_preview_tiles.duplicate()
	is_line_painting = next_is_line_painting
	request_redraw("line_preview")


func set_placement_feedback(next_placement_feedback: Array[Dictionary]) -> void:
	placement_feedback = next_placement_feedback.duplicate()
	request_redraw("placement_feedback")


func clear_line_preview() -> void:
	if line_preview_tiles.is_empty() and not is_line_painting:
		return
	line_preview_tiles.clear()
	is_line_painting = false
	placement_feedback.clear()
	request_redraw("clear_line_preview")


func set_selection_rect(rect: Rect2, visible: bool) -> void:
	selection_rect = rect.abs()
	selection_rect_visible = visible
	request_redraw("selection_rect")


func request_redraw(reason: String) -> void:
	redraw_requests += 1
	last_redraw_reason = reason
	queue_redraw()


func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	draw_calls += 1
	last_cells_processed = 0

	_draw_hover_marker()
	_draw_build_preview()
	_draw_line_preview()
	_draw_selection_rect()

	last_draw_usec = Time.get_ticks_usec() - started


func _draw_hover_marker() -> void:
	if not _is_inside_map(hovered_tile):
		return

	_draw_selection(hovered_tile, Color(1.0, 0.55, 0.05, 0.10), 2.0)


func _should_draw_selected_marker() -> bool:
	return false


func _draw_line_preview() -> void:
	if not is_line_painting or placement_feedback.is_empty():
		return

	for feedback in placement_feedback:
		_draw_feedback_outline(feedback)


func _draw_build_preview() -> void:
	if paint_tool == PAINT_TOOL_ROAD:
		if is_line_painting:
			for feedback in placement_feedback:
				var tile: Vector2i = feedback["tile"]
				if bool(feedback["valid"]):
					_draw_road_preview_tile(tile, _road_preview_mask(tile, line_preview_tiles))
		elif _is_inside_map(hovered_tile):
			if placement_feedback.is_empty() or bool(placement_feedback[0]["valid"]):
				var preview_tiles: Array[Vector2i] = [hovered_tile]
				_draw_road_preview_tile(hovered_tile, _road_preview_mask(hovered_tile, preview_tiles))
			_draw_placement_feedback()
	elif (paint_tool.begins_with(PAINT_TOOL_BUILDING_PREFIX) or (paint_tool.begins_with(PAINT_TOOL_TERRAIN_PREFIX) and dev_mode)) and _is_inside_map(hovered_tile):
		_draw_placement_feedback()


func _draw_placement_feedback() -> void:
	for feedback in placement_feedback:
		_draw_feedback_outline(feedback)


func _draw_feedback_outline(feedback: Dictionary) -> void:
	var tile: Vector2i = feedback["tile"]
	var color: Color = Color8(72, 230, 84, 215) if bool(feedback["valid"]) else Color8(230, 56, 54, 220)
	_draw_selection(tile, color, 2.0)


func _draw_selection_rect() -> void:
	if not selection_rect_visible:
		return
	draw_rect(selection_rect, Color(0.25, 0.85, 0.35, 0.10), true)
	draw_rect(selection_rect, Color(0.40, 1.0, 0.42, 0.78), false, 1.0)


func _draw_road_preview_tile(tile: Vector2i, road_mask: int) -> void:
	if not _is_inside_map(tile):
		return
	last_cells_processed += 1

	if road_atlas == null:
		var points: PackedVector2Array = _tile_polygon(tile)
		draw_colored_polygon(points, Color8(80, 84, 80, 125))
		return

	var source_rect: Rect2 = Rect2(Vector2(Vector2i(AutoTileAtlas.road_column(road_mask), IsoTileRenderer.ROAD_ATLAS_ROW) * TILE_SIZE), Vector2(TILE_SIZE))
	var target_rect: Rect2 = Rect2(map_to_screen(tile) - HALF_TILE, Vector2(TILE_SIZE))
	draw_texture_rect_region(road_atlas, target_rect, source_rect, Color(1.0, 1.0, 1.0, 0.46))


func _draw_selection(tile: Vector2i, color: Color, width: float = 1.0) -> void:
	if not _is_inside_map(tile):
		return

	last_cells_processed += 1
	var points: PackedVector2Array = _tile_polygon(tile)
	draw_polyline(points + PackedVector2Array([points[0]]), color, width)


func _road_preview_mask(tile: Vector2i, preview_tiles: Array[Vector2i]) -> int:
	var mask: int = 0
	if map_data == null:
		return mask

	for bit in AutoTile.CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = tile + AutoTile.CARDINAL_DIRECTIONS[bit]
		if map_data.has_road(neighbor) or preview_tiles.has(neighbor):
			mask |= bit
	return mask


func _tile_polygon(tile: Vector2i) -> PackedVector2Array:
	var origin: Vector2 = map_to_screen(tile)
	return PackedVector2Array([
		origin + Vector2(0, -HALF_TILE.y),
		origin + Vector2(HALF_TILE.x, 0),
		origin + Vector2(0, HALF_TILE.y),
		origin + Vector2(-HALF_TILE.x, 0),
	])


func map_to_screen(tile: Vector2i) -> Vector2:
	return Vector2(
		float(tile.x - tile.y) * HALF_TILE.x,
		float(tile.x + tile.y) * HALF_TILE.y
	)


func _is_inside_map(tile: Vector2i) -> bool:
	return map_data != null and map_data.is_inside(tile)


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": draw_calls,
		"redraw_requests": redraw_requests,
		"last_draw_usec": last_draw_usec,
		"last_cells": last_cells_processed,
		"last_reason": last_redraw_reason,
	}
