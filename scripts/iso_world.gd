extends Node2D

signal tile_changed(tile: Vector2i, terrain_name: String)

const IsoTileRenderer := preload("res://scripts/iso_tile_renderer.gd")
const IsoRoadRenderer := preload("res://scripts/iso_road_renderer.gd")
const IsoGridLayer := preload("res://scripts/iso_grid_layer.gd")
const IsoOverlayLayer := preload("res://scripts/iso_overlay_layer.gd")
const ProceduralMapGenerator := preload("res://scripts/procedural_map_generator.gd")

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
const MAP_SIZE := Vector2i(96, 96)

const TERRAIN_NAMES := {
	0: "Basalt plain",
	1: "Alien scrub",
	2: "Crystal growth",
	3: "Ore ridge",
	4: "Geothermal vent",
}
const PAINT_TOOL_NONE := "none"
const PAINT_TOOL_ROAD := "road"
const PAINT_TOOL_TERRAIN_PREFIX := "terrain:"

var map_data: RefCounted
var terrain_layer: IsoTileRenderer
var road_layer: IsoRoadRenderer
var grid_layer: IsoGridLayer
var overlay_layer: IsoOverlayLayer
var hovered_tile := Vector2i(-1, -1)
var selected_tile := Vector2i(-1, -1)
var show_grid := true
var dev_mode := false
var show_demo_content := false
var paint_tool := PAINT_TOOL_NONE
var path_count := 3
var path_width := 8
var clearing_noise := 45
var min_build_radius := 25
var max_build_radius := 40
var _is_line_painting := false
var _line_start_tile := Vector2i(-1, -1)
var _line_preview_tiles: Array[Vector2i] = []
var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_redraw_reason: String = ""


func _ready() -> void:
	position = Vector2.ZERO
	_generate_world()
	_build_render_layers()
	request_redraw("ready")


func configure_mode(next_dev_mode: bool, next_show_demo_content: bool) -> void:
	dev_mode = next_dev_mode
	show_demo_content = next_show_demo_content
	if not dev_mode and paint_tool.begins_with(PAINT_TOOL_TERRAIN_PREFIX):
		set_paint_tool(PAINT_TOOL_NONE)
	request_redraw("configure_mode")


func regenerate(next_path_count: int, next_min_build_radius: int, next_max_build_radius: int, next_path_width: int, next_clearing_noise: int, include_demo_roads := false) -> void:
	path_count = clampi(next_path_count, 1, 12)
	min_build_radius = clampi(next_min_build_radius, 4, 46)
	max_build_radius = clampi(next_max_build_radius, min_build_radius, 47)
	path_width = clampi(next_path_width, 1, 16)
	clearing_noise = clampi(next_clearing_noise, 0, 100)
	show_demo_content = include_demo_roads
	_generate_world()
	if terrain_layer != null:
		terrain_layer.set_map_data(map_data)
	if road_layer != null:
		road_layer.set_map_data(map_data)
	if grid_layer != null:
		grid_layer.set_map_data(map_data)
	if overlay_layer != null:
		overlay_layer.set_map_data(map_data)
	hovered_tile = Vector2i(-1, -1)
	_clear_line_preview()
	request_redraw("regenerate")
	tile_changed.emit(selected_tile, _terrain_name(selected_tile))


func _generate_world() -> void:
	map_data = ProceduralMapGenerator.generate(
		MAP_SIZE,
		0,
		min_build_radius,
		max_build_radius,
		path_count,
		path_width,
		clearing_noise,
		show_demo_content
	)
	selected_tile = map_data.start_tile


func _build_render_layers() -> void:
	terrain_layer = IsoTileRenderer.new()
	terrain_layer.name = "TerrainTileLayer"
	terrain_layer.z_index = -10
	add_child(terrain_layer)
	terrain_layer.set_map_data(map_data)

	road_layer = IsoRoadRenderer.new()
	road_layer.name = "RoadTileLayer"
	road_layer.z_index = -5
	add_child(road_layer)
	road_layer.set_map_data(map_data)

	grid_layer = IsoGridLayer.new()
	grid_layer.name = "GridLayer"
	grid_layer.z_index = 5
	grid_layer.visible = show_grid
	add_child(grid_layer)
	grid_layer.set_map_data(map_data)

	overlay_layer = IsoOverlayLayer.new()
	overlay_layer.name = "OverlayLayer"
	overlay_layer.z_index = 20
	add_child(overlay_layer)
	overlay_layer.set_map_data(map_data)
	overlay_layer.set_road_atlas(road_layer.atlas)
	overlay_layer.set_selected_tile(selected_tile)
	overlay_layer.set_paint_tool(paint_tool, dev_mode)


func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	draw_calls += 1
	last_cells_processed = 0

	if show_demo_content:
		_draw_demo_objects()

	last_draw_usec = Time.get_ticks_usec() - started


func set_paint_tool(next_tool: String) -> void:
	if next_tool.begins_with(PAINT_TOOL_TERRAIN_PREFIX) and not dev_mode:
		paint_tool = PAINT_TOOL_NONE
	else:
		paint_tool = next_tool
	_clear_line_preview()
	if overlay_layer != null:
		overlay_layer.set_paint_tool(paint_tool, dev_mode)


func paint_tile(tile: Vector2i) -> void:
	if not _is_inside_map(tile):
		return

	_apply_paint_tool(tile, true)
	_request_overlay_redraw("paint_tile")
	tile_changed.emit(tile, _terrain_name(tile))


func hover_tile(tile: Vector2i) -> void:
	if tile == hovered_tile:
		return

	hovered_tile = tile
	if _is_inside_map(hovered_tile):
		tile_changed.emit(hovered_tile, _terrain_name(hovered_tile))
	if _is_line_painting:
		_update_line_preview(hovered_tile)
	if overlay_layer != null:
		overlay_layer.set_hovered_tile(hovered_tile)


func primary_press_tile(tile: Vector2i, line_mode: bool) -> void:
	if not _is_inside_map(tile):
		return

	selected_tile = tile
	tile_changed.emit(selected_tile, _terrain_name(selected_tile))
	if overlay_layer != null:
		overlay_layer.set_selected_tile(selected_tile)
	if paint_tool != PAINT_TOOL_NONE:
		if line_mode:
			_begin_line_preview(tile)
		else:
			paint_tile(tile)
	else:
		_request_overlay_redraw("select")


func primary_drag_tile(tile: Vector2i) -> void:
	if not _is_inside_map(tile):
		return

	hover_tile(tile)
	if _is_line_painting:
		_update_line_preview(tile)
	elif paint_tool != PAINT_TOOL_NONE:
		paint_tile(tile)


func primary_release_tile(tile: Vector2i) -> void:
	if _is_line_painting:
		if _is_inside_map(tile):
			_update_line_preview(tile)
		_commit_line_preview()


func toggle_grid() -> void:
	show_grid = not show_grid
	if grid_layer != null:
		grid_layer.visible = show_grid
	_request_overlay_redraw("grid_toggle")


func request_redraw(reason: String) -> void:
	redraw_requests += 1
	last_redraw_reason = reason
	queue_redraw()


func _draw_demo_objects() -> void:
	if map_data == null:
		return

	var center: Vector2i = map_data.start_tile
	_draw_building(center + Vector2i(-3, 1), Vector2(2, 2), Color8(82, 88, 84), Color8(255, 150, 28), "GEN")
	_draw_building(center + Vector2i(5, -2), Vector2(3, 2), Color8(72, 78, 83), Color8(234, 136, 31), "ORE")
	_draw_building(center + Vector2i(0, 7), Vector2(3, 2), Color8(52, 82, 62), Color8(92, 210, 84), "FOOD")
	_draw_vehicle(center + Vector2i(-6, 2), Color8(205, 129, 34))
	_draw_vehicle(center + Vector2i(7, 3), Color8(205, 129, 34))
	_draw_beacon(center + Vector2i(-10, -4), Color8(45, 216, 230))


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


func _draw_beacon(tile: Vector2i, color: Color) -> void:
	var origin := map_to_screen(tile)
	draw_circle(origin + Vector2(0, -18), 5.0, Color(color.r, color.g, color.b, 0.24))
	draw_line(origin + Vector2(0, -8), origin + Vector2(0, -34), Color(color.r, color.g, color.b, 0.55), 2.0)


func _begin_line_preview(tile: Vector2i) -> void:
	_is_line_painting = true
	_line_start_tile = tile
	_update_line_preview(tile)


func _update_line_preview(tile: Vector2i) -> void:
	if not _is_line_painting or not _is_inside_map(tile):
		return

	_line_preview_tiles = _line_tiles(_line_start_tile, tile)
	if overlay_layer != null:
		overlay_layer.set_line_preview(_line_preview_tiles, true)


func _commit_line_preview() -> void:
	var changed_tiles: Array[Vector2i] = _line_preview_tiles.duplicate()
	for tile in _line_preview_tiles:
		_apply_paint_tool(tile, false)
	_clear_line_preview()
	_refresh_static_layer_for_tiles(changed_tiles)
	_request_overlay_redraw("commit_line_preview")


func _clear_line_preview() -> void:
	_is_line_painting = false
	_line_start_tile = Vector2i(-1, -1)
	_line_preview_tiles.clear()
	if overlay_layer != null:
		overlay_layer.clear_line_preview()


func _request_overlay_redraw(reason: String) -> void:
	if overlay_layer != null:
		overlay_layer.request_redraw(reason)


func _apply_paint_tool(tile: Vector2i, redraw_static_layer: bool) -> void:
	if paint_tool == PAINT_TOOL_ROAD:
		map_data.set_road(tile, true)
		if redraw_static_layer:
			_refresh_road_tile(tile)
	elif paint_tool.begins_with(PAINT_TOOL_TERRAIN_PREFIX) and dev_mode:
		var terrain_id := paint_tool.trim_prefix(PAINT_TOOL_TERRAIN_PREFIX).to_int()
		map_data.set_terrain(tile, terrain_id)
		if redraw_static_layer:
			_refresh_terrain_layer()


func _refresh_static_layer_for_tiles(changed_tiles: Array[Vector2i]) -> void:
	if paint_tool == PAINT_TOOL_ROAD:
		_refresh_road_tiles(changed_tiles)
	elif paint_tool.begins_with(PAINT_TOOL_TERRAIN_PREFIX):
		_refresh_terrain_layer()


func _refresh_terrain_layer() -> void:
	if terrain_layer != null:
		terrain_layer.request_redraw("terrain_edit")


func _refresh_road_tiles(changed_tiles: Array[Vector2i]) -> void:
	if road_layer != null:
		road_layer.notify_roads_changed(changed_tiles)


func _refresh_road_tile(tile: Vector2i) -> void:
	if road_layer != null:
		road_layer.notify_road_changed(tile)


func _line_tiles(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var x0 := start.x
	var y0 := start.y
	var x1 := end.x
	var y1 := end.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var error := dx + dy

	while true:
		var tile := Vector2i(x0, y0)
		if _is_inside_map(tile):
			tiles.append(tile)
		if x0 == x1 and y0 == y1:
			break
		var doubled_error := 2 * error
		if doubled_error >= dy:
			error += dy
			x0 += sx
		if doubled_error <= dx:
			error += dx
			y0 += sy

	return tiles


func _tile_polygon(tile: Vector2i) -> PackedVector2Array:
	var origin := map_to_screen(tile)
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


func get_map_bounds() -> Rect2:
	var map_size: Vector2i = MAP_SIZE if map_data == null else map_data.size
	var points: Array[Vector2] = [
		map_to_screen(Vector2i(0, 0)) + Vector2(0, -HALF_TILE.y),
		map_to_screen(Vector2i(map_size.x - 1, 0)) + Vector2(HALF_TILE.x, 0),
		map_to_screen(Vector2i(0, map_size.y - 1)) + Vector2(-HALF_TILE.x, 0),
		map_to_screen(Vector2i(map_size.x - 1, map_size.y - 1)) + Vector2(0, HALF_TILE.y),
	]
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)


func world_to_map(world_position: Vector2) -> Vector2i:
	var map_x := (world_position.y / TILE_SIZE.y) + (world_position.x / TILE_SIZE.x)
	var map_y := (world_position.y / TILE_SIZE.y) - (world_position.x / TILE_SIZE.x)
	return Vector2i(floori(map_x + 0.5), floori(map_y + 0.5))


func screen_to_map(screen_position: Vector2) -> Vector2i:
	return world_to_map(screen_position)


func _is_inside_map(tile: Vector2i) -> bool:
	return map_data != null and map_data.is_inside(tile)


func _terrain_name(tile: Vector2i) -> String:
	if not _is_inside_map(tile):
		return "Outside map"
	return TERRAIN_NAMES[map_data.get_terrain(tile)]


func get_generation_summary() -> String:
	if map_data == null:
		return ""
	return "Seed: %s  Build radius: %s-%s  Clearing noise: %s  Paths: %s  Path width: %s" % [
		map_data.seed,
		min_build_radius,
		max_build_radius,
		map_data.clearing_noise,
		map_data.path_endpoints.size(),
		map_data.path_width,
	]


func get_render_diagnostics() -> Dictionary:
	return {
		"world": _diagnostics_for(self),
		"terrain": _diagnostics_for(terrain_layer),
		"roads": _diagnostics_for(road_layer),
		"grid": _diagnostics_for(grid_layer),
		"overlay": _diagnostics_for(overlay_layer),
	}


func _diagnostics_for(layer: Object) -> Dictionary:
	if layer == null or not layer.has_method("get_diagnostics"):
		return {}
	return layer.get_diagnostics()


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": draw_calls,
		"redraw_requests": redraw_requests,
		"last_draw_usec": last_draw_usec,
		"last_cells": last_cells_processed,
		"last_reason": last_redraw_reason,
	}
