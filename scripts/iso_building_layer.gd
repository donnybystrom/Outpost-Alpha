extends Node2D

const ColonyState := preload("res://scripts/colony_state.gd")
const BuildingCatalog := preload("res://scripts/building_catalog.gd")

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)

var colony_state: ColonyState
var building_catalog = BuildingCatalog.new()
var atlas: Texture2D
var hidden_building_types: Array[String] = []
var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_redraw_reason: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_atlas()


func set_building_catalog(next_building_catalog) -> void:
	if next_building_catalog == null:
		return
	building_catalog = next_building_catalog
	_load_atlas()
	request_redraw("building_catalog")


func set_colony_state(next_colony_state: ColonyState) -> void:
	colony_state = next_colony_state
	request_redraw("set_colony_state")


func set_hidden_building_types(next_hidden_building_types: Array[String]) -> void:
	hidden_building_types = next_hidden_building_types
	request_redraw("hidden_building_types")


func request_redraw(reason: String) -> void:
	redraw_requests += 1
	last_redraw_reason = reason
	queue_redraw()


func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	draw_calls += 1
	last_cells_processed = 0

	if colony_state != null:
		for building in colony_state.buildings:
			_draw_colony_building(building)

	last_draw_usec = Time.get_ticks_usec() - started


func _draw_colony_building(building: Dictionary) -> void:
	var tile: Vector2i = building["origin"]
	var footprint: Vector2i = building["footprint"]
	var building_type: String = building["type"]
	if hidden_building_types.has(building_type) or not building_catalog.get_model_config(building_type).is_empty():
		return
	var orientation: String = building.get("orientation", BuildingCatalog.ORIENTATION_HORIZONTAL)
	if _draw_building_sprite(tile, building_type, orientation):
		last_cells_processed += footprint.x * footprint.y
		return
	var colors: Array[Color] = _building_colors(building_type)
	var label: String = building_catalog.get_definition(building_type).get("label", building_type)
	_draw_building(tile, Vector2(footprint), colors[0], colors[1], label)
	last_cells_processed += footprint.x * footprint.y


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


func _draw_building_sprite(tile: Vector2i, building_type: String, orientation: String) -> bool:
	if atlas == null:
		return false
	var source_rect: Rect2i = building_catalog.get_sprite_source_rect(building_type, orientation)
	if source_rect.size == Vector2i.ZERO:
		return false

	var anchor: Vector2 = building_catalog.get_sprite_anchor(building_type, orientation)
	var screen_offset: Vector2 = building_catalog.get_sprite_screen_offset(building_type)
	var target_rect := Rect2(map_to_screen(tile) + screen_offset - anchor, Vector2(source_rect.size))
	_draw_texture_region(atlas, target_rect, Rect2(source_rect), Color.WHITE, building_catalog.should_flip_sprite_horizontal(building_type, orientation))
	return true


func _draw_texture_region(texture: Texture2D, target_rect: Rect2, source_rect: Rect2, color: Color, flip_horizontal: bool) -> void:
	if not flip_horizontal:
		draw_texture_rect_region(texture, target_rect, source_rect, color)
		return

	draw_set_transform(target_rect.position + Vector2(target_rect.size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, target_rect.size), source_rect, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _load_atlas() -> void:
	atlas = null
	if building_catalog != null and ResourceLoader.exists(building_catalog.atlas_path()):
		atlas = load(building_catalog.atlas_path()) as Texture2D


func _building_colors(building_type: String) -> Array[Color]:
	match building_type:
		ColonyState.BUILDING_LIVING_QUARTERS:
			return [Color8(63, 78, 84), Color8(85, 198, 220)]
		ColonyState.BUILDING_OXYGEN_EXTRACTOR:
			return [Color8(56, 82, 78), Color8(108, 226, 212)]
		ColonyState.BUILDING_MACHINE_PARK:
			return [Color8(77, 74, 64), Color8(230, 142, 38)]
		ColonyState.BUILDING_MILLING_PLANT:
			return [Color8(72, 72, 76), Color8(180, 187, 194)]
		_:
			return [Color8(70, 74, 72), Color8(128, 210, 98)]


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
		"last_reason": last_redraw_reason,
	}
