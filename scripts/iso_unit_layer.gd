extends Node2D

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
const UNIT_ATLAS_PATH := "res://assets/objects/units.png"
const ROLE_DRILLING_MACHINE := "drilling_machine"
const ROLE_HAULER := "hauler"
const FACING_SOUTH_EAST := "south_east"
const FACING_NORTH_EAST := "north_east"
const FACING_SOUTH_WEST := "south_west"
const FACING_NORTH_WEST := "north_west"

const SPRITE_HAULER_EMPTY_SOUTH_EAST := Rect2i(46, 8, 28, 24)
const SPRITE_HAULER_EMPTY_NORTH_EAST := Rect2i(80, 8, 29, 24)
const SPRITE_HAULER_FULL_SOUTH_EAST := Rect2i(113, 9, 28, 24)
const SPRITE_HAULER_FULL_NORTH_EAST := Rect2i(147, 7, 29, 25)
const SPRITE_DRILLING_MACHINE_SOUTH_EAST := Rect2i(183, 4, 34, 26)
const SPRITE_DRILLING_MACHINE_NORTH_EAST := Rect2i(222, 3, 41, 28)

var unit_state: RefCounted
var unit_atlas: Texture2D
var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_redraw_reason: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(UNIT_ATLAS_PATH):
		unit_atlas = load(UNIT_ATLAS_PATH) as Texture2D


func set_unit_state(next_unit_state: RefCounted) -> void:
	unit_state = next_unit_state
	request_redraw("set_unit_state")


func request_redraw(reason: String) -> void:
	redraw_requests += 1
	last_redraw_reason = reason
	queue_redraw()


func _draw() -> void:
	var started := Time.get_ticks_usec()
	draw_calls += 1
	last_cells_processed = 0
	if unit_state == null:
		last_draw_usec = Time.get_ticks_usec() - started
		return

	var workers: Array[Dictionary] = unit_state.workers.duplicate()
	workers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_pos: Vector2 = a["position"]
		var b_pos: Vector2 = b["position"]
		return a_pos.x + a_pos.y < b_pos.x + b_pos.y
	)
	for worker in workers:
		_draw_worker_path(worker)
	for worker in workers:
		_draw_worker(worker)

	last_draw_usec = Time.get_ticks_usec() - started


func _draw_worker(worker: Dictionary) -> void:
	var position: Vector2 = worker["position"]
	var origin := map_position_to_screen(position) + _worker_visual_offset(worker)
	var role: String = worker.get("role", "worker")
	if role == ROLE_HAULER or role == ROLE_DRILLING_MACHINE:
		_draw_vehicle_status(origin, worker)
		if unit_state != null and unit_state.is_selected(int(worker["id"])):
			_draw_unit_selection_box(_vehicle_selection_rect(origin, worker))
		last_cells_processed += 1
		return
	if role == ROLE_DRILLING_MACHINE or role == ROLE_HAULER:
		if not _draw_vehicle_sprite(origin, worker):
			_draw_vehicle_fallback(origin, worker)
		if unit_state != null and unit_state.is_selected(int(worker["id"])):
			_draw_unit_selection_box(_vehicle_selection_rect(origin, worker))
		last_cells_processed += 1
		return
	draw_circle(origin + Vector2(0, -5), 4.0, Color8(28, 32, 34))
	draw_circle(origin + Vector2(0, -7), 3.0, Color8(178, 188, 184))
	draw_line(origin + Vector2(-3, -4), origin + Vector2(3, -4), Color8(75, 205, 94), 1.0)
	draw_line(origin + Vector2(0, -3), origin + Vector2(0, 2), Color8(114, 122, 120), 2.0)
	if unit_state != null and unit_state.is_selected(int(worker["id"])):
		_draw_unit_selection_box(Rect2(origin + Vector2(-8, -14), Vector2(16, 19)))
	last_cells_processed += 1


func _draw_vehicle_sprite(origin: Vector2, worker: Dictionary) -> bool:
	if unit_atlas == null:
		return false
	var source_rect := _vehicle_source_rect(worker)
	if source_rect.size == Vector2i.ZERO:
		return false
	var anchor := _vehicle_anchor(source_rect)
	var target_rect := Rect2(origin - anchor, Vector2(source_rect.size))
	_draw_texture_region(unit_atlas, target_rect, Rect2(source_rect), Color.WHITE, _should_flip_vehicle_sprite(worker))
	_draw_vehicle_status(origin, worker)
	return true


func _draw_texture_region(texture: Texture2D, target_rect: Rect2, source_rect: Rect2, color: Color, flip_horizontal: bool) -> void:
	if not flip_horizontal:
		draw_texture_rect_region(texture, target_rect, source_rect, color)
		return

	draw_set_transform(target_rect.position + Vector2(target_rect.size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, target_rect.size), source_rect, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_vehicle_fallback(origin: Vector2, worker: Dictionary) -> void:
	var role: String = worker.get("role", "worker")
	var accent := Color8(226, 140, 34) if role == ROLE_DRILLING_MACHINE else Color8(92, 170, 220)
	var body := PackedVector2Array([
		origin + Vector2(0, -15),
		origin + Vector2(15, -7),
		origin + Vector2(15, 2),
		origin + Vector2(0, 9),
		origin + Vector2(-15, 2),
		origin + Vector2(-15, -7),
	])
	draw_colored_polygon(body, Color8(42, 47, 48))
	draw_polyline(body + PackedVector2Array([body[0]]), Color8(8, 9, 9), 1.0)
	draw_line(origin + Vector2(-8, -7), origin + Vector2(8, -7), accent, 2.0)
	if role == ROLE_DRILLING_MACHINE:
		draw_line(origin + Vector2(-16, 1), origin + Vector2(-24, 7), Color8(156, 110, 70), 2.0)
		draw_line(origin + Vector2(-20, 4), origin + Vector2(-15, 8), Color8(216, 160, 74), 1.0)
	else:
		draw_rect(Rect2(origin + Vector2(-8, -3), Vector2(16, 7)), Color8(64, 70, 69), true)
		draw_rect(Rect2(origin + Vector2(-8, -3), Vector2(16, 7)), accent, false, 1.0)
	_draw_vehicle_status(origin, worker)


func _draw_vehicle_status(origin: Vector2, worker: Dictionary) -> void:
	if worker.get("role", "") == ROLE_DRILLING_MACHINE and worker.get("order", "") == "mining":
		draw_circle(origin + Vector2(-23, 8), 3.0, Color8(245, 170, 38, 210))
	var cargo_capacity := int(worker.get("cargo_capacity", 0))
	var cargo := int(worker.get("cargo", 0))
	if cargo_capacity > 0 and cargo > 0:
		var fill_width := 18.0 * clampf(float(cargo) / float(cargo_capacity), 0.0, 1.0)
		draw_rect(Rect2(origin + Vector2(-9, 11), Vector2(18, 2)), Color8(18, 20, 20), true)
		draw_rect(Rect2(origin + Vector2(-9, 11), Vector2(fill_width, 2)), Color8(216, 145, 52), true)


func _vehicle_source_rect(worker: Dictionary) -> Rect2i:
	var role: String = worker.get("role", "")
	var facing: String = worker.get("facing", FACING_SOUTH_EAST)
	var north_facing := facing == FACING_NORTH_EAST or facing == FACING_NORTH_WEST
	var has_cargo := int(worker.get("cargo", 0)) > 0
	if role == ROLE_DRILLING_MACHINE:
		return SPRITE_DRILLING_MACHINE_NORTH_EAST if north_facing else SPRITE_DRILLING_MACHINE_SOUTH_EAST
	if role == ROLE_HAULER and has_cargo:
		return SPRITE_HAULER_FULL_NORTH_EAST if north_facing else SPRITE_HAULER_FULL_SOUTH_EAST
	if role == ROLE_HAULER:
		return SPRITE_HAULER_EMPTY_NORTH_EAST if north_facing else SPRITE_HAULER_EMPTY_SOUTH_EAST
	return Rect2i()


func _vehicle_anchor(source_rect: Rect2i) -> Vector2:
	return Vector2(float(source_rect.size.x) * 0.5, float(source_rect.size.y) - 3.0)


func _should_flip_vehicle_sprite(worker: Dictionary) -> bool:
	var facing: String = worker.get("facing", FACING_SOUTH_EAST)
	return facing == FACING_SOUTH_WEST or facing == FACING_NORTH_WEST


func _draw_worker_path(worker: Dictionary) -> void:
	var path: Array = worker["path"]
	var path_index: int = worker["path_index"]
	if path_index >= path.size():
		return

	var points := PackedVector2Array()
	var offset := _worker_visual_offset(worker)
	points.append(map_position_to_screen(worker["position"]) + offset)
	for index in range(path_index, path.size()):
		points.append(map_position_to_screen(Vector2(path[index])) + offset)
	if points.size() > 1:
		draw_polyline(points, Color(0.3, 0.9, 0.35, 0.24), 1.0)


func _vehicle_selection_rect(origin: Vector2, worker: Dictionary) -> Rect2:
	var source_rect := _vehicle_source_rect(worker)
	if source_rect.size == Vector2i.ZERO:
		return Rect2(origin + Vector2(-17, -17), Vector2(34, 28))
	var anchor := _vehicle_anchor(source_rect)
	return Rect2(origin - anchor, Vector2(source_rect.size)).grow(1.0)


func _draw_unit_selection_box(rect: Rect2) -> void:
	draw_rect(rect, Color(0.40, 1.0, 0.42, 0.80), false, 1.0)


func _worker_visual_offset(worker: Dictionary) -> Vector2:
	return worker.get("visual_offset", Vector2.ZERO)


func map_position_to_screen(map_position: Vector2) -> Vector2:
	return Vector2(
		(map_position.x - map_position.y) * HALF_TILE.x,
		(map_position.x + map_position.y) * HALF_TILE.y
	)


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": draw_calls,
		"redraw_requests": redraw_requests,
		"last_draw_usec": last_draw_usec,
		"last_cells": last_cells_processed,
		"last_reason": last_redraw_reason,
	}
