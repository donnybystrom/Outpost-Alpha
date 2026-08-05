extends Node2D

const TILE_SIZE := Vector2i(32, 16)
const HALF_TILE := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)

var unit_state: RefCounted
var redraw_requests: int = 0
var draw_calls: int = 0
var last_draw_usec: int = 0
var last_cells_processed: int = 0
var last_redraw_reason: String = ""


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
	if unit_state != null and unit_state.is_selected(int(worker["id"])):
		_draw_selection_ring(origin)
	draw_circle(origin + Vector2(0, -5), 4.0, Color8(28, 32, 34))
	draw_circle(origin + Vector2(0, -7), 3.0, Color8(178, 188, 184))
	draw_line(origin + Vector2(-3, -4), origin + Vector2(3, -4), Color8(75, 205, 94), 1.0)
	draw_line(origin + Vector2(0, -3), origin + Vector2(0, 2), Color8(114, 122, 120), 2.0)
	last_cells_processed += 1


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


func _draw_selection_ring(origin: Vector2) -> void:
	var points := PackedVector2Array([
		origin + Vector2(0, -12),
		origin + Vector2(9, -7),
		origin + Vector2(0, -2),
		origin + Vector2(-9, -7),
		origin + Vector2(0, -12),
	])
	draw_polyline(points, Color8(92, 230, 82, 220), 1.5)


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
