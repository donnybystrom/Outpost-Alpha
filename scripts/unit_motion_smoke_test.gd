extends SceneTree

const MapData := preload("res://scripts/map_data.gd")
const PathfindingGrid := preload("res://scripts/pathfinding_grid.gd")
const UnitState := preload("res://scripts/unit_state.gd")

var _failed := false


func _initialize() -> void:
	var map_data := MapData.new(Vector2i(24, 24))
	var pathfinding_grid := PathfindingGrid.new()
	pathfinding_grid.configure(map_data, null)

	_assert_path_smoothing(pathfinding_grid, map_data)
	if _failed:
		quit(1)
		return
	_assert_vehicle_turning(pathfinding_grid)
	if _failed:
		quit(1)
		return
	_assert_unit_avoidance(pathfinding_grid)
	if _failed:
		quit(1)
		return
	quit(0)


func _assert_path_smoothing(pathfinding_grid: RefCounted, map_data: RefCounted) -> void:
	var raw_path: Array[Vector2i] = pathfinding_grid.find_path(Vector2i(3, 3), Vector2i(10, 8))
	var path_without_start: Array[Vector2i] = raw_path.duplicate()
	path_without_start.remove_at(0)
	var smoothed: Array[Vector2] = pathfinding_grid.smooth_path(Vector2(3, 3), path_without_start, 0.32)
	if smoothed.size() >= path_without_start.size():
		_fail("Open terrain path should be reduced by smoothing.")
		return
	if not Vector2(smoothed[smoothed.size() - 1]).is_equal_approx(Vector2(10, 8)):
		_fail("Smoothed path should preserve its destination.")
		return
	for y in range(3, 9):
		map_data.set_road(Vector2i(3, y), true)
	for x in range(3, 11):
		map_data.set_road(Vector2i(x, 8), true)
	var road_path: Array[Vector2i] = pathfinding_grid.find_path(Vector2i(3, 3), Vector2i(10, 8))
	road_path.remove_at(0)
	var smoothed_road_path: Array[Vector2] = pathfinding_grid.smooth_path(Vector2(3, 3), road_path, 0.32)
	if smoothed_road_path.size() < 2:
		_fail("Smoothing should retain a preferred road bend instead of cutting across open terrain.")
		return
	for y in range(3, 9):
		map_data.set_road(Vector2i(3, y), false)
	for x in range(3, 11):
		map_data.set_road(Vector2i(x, 8), false)

	for offset in range(0, 7):
		map_data.set_road(Vector2i(3 + offset, 3 + offset), true)
	var diagonal_road_path: Array[Vector2i] = pathfinding_grid.find_path(Vector2i(3, 3), Vector2i(9, 9))
	if diagonal_road_path.size() != 7:
		_fail("Eight-direction pathfinding should follow a direct diagonal road; path=%s" % [diagonal_road_path])
		return
	for offset in range(0, 7):
		var sample := Vector2(3 + offset, 3 + offset).lerp(Vector2(4 + offset, 4 + offset), 0.5) if offset < 6 else Vector2(9, 9)
		if not pathfinding_grid.is_fast_position(sample):
			_fail("The widened road corridor should cover diagonal movement between road tiles.")
			return
	for offset in range(0, 7):
		map_data.set_road(Vector2i(3 + offset, 3 + offset), false)

	map_data.set_terrain(Vector2i(7, 6), 5)
	if pathfinding_grid.has_clear_path_segment(Vector2(3, 3), Vector2(10, 8), 0.38):
		_fail("Radius-aware smoothing should reject a segment through blocked terrain.")


func _assert_vehicle_turning(pathfinding_grid: RefCounted) -> void:
	var unit_state := UnitState.new()
	unit_state.reset(Vector2i(3, 3), 0)
	var vehicle := unit_state.add_vehicle("hauler", Vector2i(3, 3))
	unit_state.set_selected_worker_destination(Vector2i(10, 8), pathfinding_grid)
	var initial_heading := float(vehicle["heading"])
	for _step in 300:
		unit_state.advance(0.05, pathfinding_grid)
	var moved_vehicle: Dictionary = unit_state.get_unit_by_id(int(vehicle["id"]))
	if Vector2(moved_vehicle["position"]).distance_to(Vector2(10, 8)) > 0.12:
		_fail("Vehicle path follower should reach a smoothed-path destination; position=%s path_index=%s path=%s" % [moved_vehicle["position"], moved_vehicle["path_index"], moved_vehicle["path"]])
		return
	if is_equal_approx(float(moved_vehicle["heading"]), initial_heading):
		_fail("Vehicle should rotate continuously while changing direction.")


func _assert_unit_avoidance(pathfinding_grid: RefCounted) -> void:
	var unit_state := UnitState.new()
	unit_state.reset(Vector2i(4, 12), 0)
	var first := unit_state.add_vehicle("hauler", Vector2i(4, 12))
	var second := unit_state.add_vehicle("hauler", Vector2i(16, 12))
	unit_state.select_unit_by_id(int(first["id"]))
	unit_state.set_selected_worker_destination(Vector2i(16, 12), pathfinding_grid)
	unit_state.select_unit_by_id(int(second["id"]))
	unit_state.set_selected_worker_destination(Vector2i(4, 12), pathfinding_grid)
	var minimum_distance := INF
	for _step in 360:
		unit_state.advance(0.05, pathfinding_grid)
		var first_position: Vector2 = unit_state.get_unit_by_id(int(first["id"]))["position"]
		var second_position: Vector2 = unit_state.get_unit_by_id(int(second["id"]))["position"]
		minimum_distance = minf(minimum_distance, first_position.distance_to(second_position))
	if minimum_distance < 0.575:
		_fail("Local avoidance should limit overlap between two haulers; minimum distance=%s" % minimum_distance)


func _fail(message: String) -> void:
	push_error(message)
	_failed = true
