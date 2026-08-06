extends Node2D

const AutoTile := preload("res://scripts/auto_tile.gd")
const BuildingCatalog := preload("res://scripts/building_catalog.gd")

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
const PAINT_TOOL_NONE := "none"
const PAINT_TOOL_ROAD := "road"
const PAINT_TOOL_ROAD_DELETE := "road_delete"
const PAINT_TOOL_TERRAIN_PREFIX := "terrain:"
const PAINT_TOOL_BUILDING_PREFIX := "building:"

var map_data: RefCounted
var road_atlas: Texture2D
var building_atlas: Texture2D
var building_catalog = BuildingCatalog.new()
var hovered_tile := Vector2i(-1, -1)
var selected_tile := Vector2i(-1, -1)
var paint_tool := PAINT_TOOL_NONE
var building_orientation := BuildingCatalog.ORIENTATION_HORIZONTAL
var dev_mode: bool = false
var is_line_painting: bool = false
var line_preview_tiles: Array[Vector2i] = []
var placement_feedback: Array[Dictionary] = []
var selected_building_tiles: Array[Vector2i] = []
var selection_rect := Rect2()
var selection_rect_visible := false
var selection_rect_viewport_space := false
var map_position_projector := Callable()

var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_redraw_reason: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_building_atlas()


func set_building_catalog(next_building_catalog) -> void:
	if next_building_catalog == null:
		return
	building_catalog = next_building_catalog
	_load_building_atlas()
	request_redraw("building_catalog")


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	request_redraw("set_map_data")


func set_road_atlas(next_road_atlas: Texture2D) -> void:
	road_atlas = next_road_atlas
	request_redraw("set_road_atlas")


func set_map_position_projector(next_projector: Callable) -> void:
	map_position_projector = next_projector
	request_redraw("map_position_projector")


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


func set_building_orientation(next_orientation: String) -> void:
	if building_orientation == next_orientation:
		return
	building_orientation = next_orientation
	request_redraw("building_orientation")


func set_line_preview(next_line_preview_tiles: Array[Vector2i], next_is_line_painting: bool) -> void:
	line_preview_tiles = next_line_preview_tiles.duplicate()
	is_line_painting = next_is_line_painting
	request_redraw("line_preview")


func set_placement_feedback(next_placement_feedback: Array[Dictionary]) -> void:
	placement_feedback = next_placement_feedback.duplicate()
	request_redraw("placement_feedback")


func set_selected_building_tiles(next_selected_building_tiles: Array[Vector2i]) -> void:
	selected_building_tiles = next_selected_building_tiles.duplicate()
	request_redraw("selected_building")


func clear_line_preview() -> void:
	if line_preview_tiles.is_empty() and not is_line_painting:
		return
	line_preview_tiles.clear()
	is_line_painting = false
	placement_feedback.clear()
	request_redraw("clear_line_preview")


func set_selection_rect(rect: Rect2, visible: bool, viewport_space: bool = false) -> void:
	selection_rect = rect.abs()
	selection_rect_visible = visible
	selection_rect_viewport_space = viewport_space
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
	_draw_selected_building()
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
	elif paint_tool == PAINT_TOOL_ROAD_DELETE and _is_inside_map(hovered_tile):
		_draw_placement_feedback()
	elif paint_tool.begins_with(PAINT_TOOL_BUILDING_PREFIX) and _is_inside_map(hovered_tile):
		var building_type := paint_tool.trim_prefix(PAINT_TOOL_BUILDING_PREFIX)
		if building_catalog.get_model_config(building_type).is_empty():
			_draw_building_sprite_preview(hovered_tile, building_type)
			_draw_placement_feedback()
	elif paint_tool.begins_with(PAINT_TOOL_TERRAIN_PREFIX) and dev_mode and _is_inside_map(hovered_tile):
		_draw_placement_feedback()


func _draw_placement_feedback() -> void:
	for feedback in placement_feedback:
		_draw_feedback_outline(feedback)


func _draw_feedback_outline(feedback: Dictionary) -> void:
	var tile: Vector2i = feedback["tile"]
	var color: Color
	if paint_tool == PAINT_TOOL_ROAD_DELETE:
		color = Color8(238, 80, 62, 225) if bool(feedback["valid"]) else Color8(125, 70, 66, 180)
	else:
		color = Color8(72, 230, 84, 215) if bool(feedback["valid"]) else Color8(230, 56, 54, 220)
	_draw_selection(tile, color, 2.0)


func _draw_selection_rect() -> void:
	if not selection_rect_visible:
		return
	if selection_rect_viewport_space:
		var inverse_canvas := get_global_transform_with_canvas().affine_inverse()
		var top_left: Vector2 = inverse_canvas * selection_rect.position
		var top_right: Vector2 = inverse_canvas * (selection_rect.position + Vector2(selection_rect.size.x, 0.0))
		var bottom_right: Vector2 = inverse_canvas * (selection_rect.position + selection_rect.size)
		var bottom_left: Vector2 = inverse_canvas * (selection_rect.position + Vector2(0.0, selection_rect.size.y))
		var points := PackedVector2Array([top_left, top_right, bottom_right, bottom_left])
		draw_colored_polygon(points, Color(0.25, 0.85, 0.35, 0.10))
		draw_polyline(PackedVector2Array([top_left, top_right, bottom_right, bottom_left, top_left]), Color(0.40, 1.0, 0.42, 0.78), 1.0)
		return
	draw_rect(selection_rect, Color(0.25, 0.85, 0.35, 0.10), true)
	draw_rect(selection_rect, Color(0.40, 1.0, 0.42, 0.78), false, 1.0)


func _draw_selected_building() -> void:
	if selected_building_tiles.is_empty():
		return
	for tile in selected_building_tiles:
		_draw_selection(tile, Color(0.40, 1.0, 0.42, 0.80), 1.0)


func _draw_road_preview_tile(tile: Vector2i, road_mask: int) -> void:
	if not _is_inside_map(tile):
		return
	last_cells_processed += 1
	var center := map_to_screen(tile)
	if road_mask == 0:
		draw_circle(center, 7.0, Color(0.27, 0.28, 0.25, 0.52))
		draw_circle(center, 5.0, Color(0.38, 0.38, 0.33, 0.58))
		return
	for bit in AutoTile.ROAD_DIRECTIONS:
		if (road_mask & bit) == 0:
			continue
		var neighbor_center := map_to_screen(tile + AutoTile.ROAD_DIRECTIONS[bit])
		var end := center.lerp(neighbor_center, 0.5)
		var screen_normal := center.direction_to(end).orthogonal()
		draw_line(center, end, Color(0.27, 0.28, 0.25, 0.52), 10.0, true)
		draw_line(center, end, Color(0.38, 0.38, 0.33, 0.58), 7.0, true)
		draw_line(center + screen_normal * 2.0, end + screen_normal * 2.0, Color(0.19, 0.21, 0.19, 0.46), 1.2, true)
		draw_line(center - screen_normal * 2.0, end - screen_normal * 2.0, Color(0.19, 0.21, 0.19, 0.46), 1.2, true)


func _draw_building_sprite_preview(tile: Vector2i, building_type: String) -> void:
	if not building_catalog.get_model_config(building_type).is_empty():
		return
	if building_atlas == null:
		return
	var source_rect: Rect2i = building_catalog.get_sprite_source_rect(building_type, building_orientation)
	if source_rect.size == Vector2i.ZERO:
		return
	var anchor: Vector2 = building_catalog.get_sprite_anchor(building_type, building_orientation)
	var screen_offset: Vector2 = building_catalog.get_sprite_screen_offset(building_type)
	var target_rect := Rect2(map_to_screen(tile) + screen_offset - anchor, Vector2(source_rect.size))
	_draw_texture_region(
		building_atlas,
		target_rect,
		Rect2(source_rect),
		Color(1.0, 1.0, 1.0, 0.52),
		building_catalog.should_flip_sprite_horizontal(building_type, building_orientation)
	)


func _draw_texture_region(texture: Texture2D, target_rect: Rect2, source_rect: Rect2, color: Color, flip_horizontal: bool) -> void:
	if not flip_horizontal:
		draw_texture_rect_region(texture, target_rect, source_rect, color)
		return

	draw_set_transform(target_rect.position + Vector2(target_rect.size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, target_rect.size), source_rect, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _load_building_atlas() -> void:
	building_atlas = null
	if building_catalog != null and ResourceLoader.exists(building_catalog.atlas_path()):
		building_atlas = load(building_catalog.atlas_path()) as Texture2D


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

	for bit in AutoTile.ROAD_DIRECTIONS:
		var direction: Vector2i = AutoTile.ROAD_DIRECTIONS[bit]
		var neighbor: Vector2i = tile + direction
		if not map_data.has_road(neighbor) and not preview_tiles.has(neighbor):
			continue
		if direction.x != 0 and direction.y != 0:
			var bridge_x := tile + Vector2i(direction.x, 0)
			var bridge_y := tile + Vector2i(0, direction.y)
			if map_data.has_road(bridge_x) or preview_tiles.has(bridge_x):
				continue
			if map_data.has_road(bridge_y) or preview_tiles.has(bridge_y):
				continue
		mask |= bit
	return mask


func _tile_polygon(tile: Vector2i) -> PackedVector2Array:
	if map_position_projector.is_valid():
		var center := Vector2(tile)
		return PackedVector2Array([
			_map_position_to_draw(center + Vector2(-0.5, -0.5)),
			_map_position_to_draw(center + Vector2(0.5, -0.5)),
			_map_position_to_draw(center + Vector2(0.5, 0.5)),
			_map_position_to_draw(center + Vector2(-0.5, 0.5)),
		])
	var origin: Vector2 = map_to_screen(tile)
	return PackedVector2Array([
		origin + Vector2(0, -HALF_TILE.y),
		origin + Vector2(HALF_TILE.x, 0),
		origin + Vector2(0, HALF_TILE.y),
		origin + Vector2(-HALF_TILE.x, 0),
	])


func map_to_screen(tile: Vector2i) -> Vector2:
	if map_position_projector.is_valid():
		return _map_position_to_draw(Vector2(tile))
	return Vector2(
		float(tile.x - tile.y) * HALF_TILE.x,
		float(tile.x + tile.y) * HALF_TILE.y
	)


func _map_position_to_draw(map_position: Vector2) -> Vector2:
	var viewport_position: Vector2 = map_position_projector.call(map_position)
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


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
