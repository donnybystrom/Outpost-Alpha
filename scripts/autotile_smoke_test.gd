extends SceneTree

const MapData := preload("res://scripts/map_data.gd")
const AutoTile := preload("res://scripts/auto_tile.gd")
const Road3DLayer := preload("res://scripts/iso_road_3d_layer.gd")


func _initialize() -> void:
	var map_data := MapData.new(Vector2i(8, 8))

	var center := Vector2i(3, 3)
	map_data.set_road(center)
	map_data.set_road(center + Vector2i(0, -1))
	map_data.set_road(center + Vector2i(1, 0))
	map_data.set_road(center + Vector2i(0, 1))
	map_data.set_road(center + Vector2i(-1, 0))
	_assert_mask(map_data, center, 15, "four-way road")

	var vertical := Vector2i(6, 3)
	map_data.set_road(vertical)
	map_data.set_road(vertical + Vector2i(0, -1))
	map_data.set_road(vertical + Vector2i(0, 1))
	_assert_mask(map_data, vertical, 5, "north-south road")

	var corner := Vector2i(1, 1)
	map_data.set_road(corner)
	map_data.set_road(corner + Vector2i(1, 0))
	map_data.set_road(corner + Vector2i(0, 1))
	_assert_mask(map_data, corner, 6, "east-south road corner")

	var tee := Vector2i(1, 5)
	map_data.set_road(tee)
	map_data.set_road(tee + Vector2i(0, -1))
	map_data.set_road(tee + Vector2i(1, 0))
	map_data.set_road(tee + Vector2i(-1, 0))
	_assert_mask(map_data, tee, 11, "north-east-west road tee")

	var diagonal_map := MapData.new(Vector2i(5, 5))
	var diagonal := Vector2i(2, 2)
	diagonal_map.set_road(diagonal)
	diagonal_map.set_road(diagonal + Vector2i(1, -1))
	diagonal_map.set_road(diagonal + Vector2i(-1, 1))
	_assert_mask(diagonal_map, diagonal, AutoTile.NORTH_EAST | AutoTile.SOUTH_WEST, "diagonal road")
	_assert_continuous_road_mesh(diagonal_map)
	_assert_closed_road_loop()
	_assert_local_chunk_rebuild()

	var mountain := Vector2i(4, 5)
	map_data.set_terrain(mountain, 5)
	map_data.set_terrain(mountain + Vector2i(0, -1), 5)
	map_data.set_terrain(mountain + Vector2i(-1, 0), 5)
	map_data.set_terrain(mountain + Vector2i(1, 0), 1)
	_assert_same_terrain_mask(map_data, mountain, 9, "mountain massif north-west connection")

	quit(0)


func _assert_mask(map_data: RefCounted, tile: Vector2i, expected: int, label: String) -> void:
	var actual := AutoTile.road_mask(map_data, tile)
	if actual != expected:
		push_error("%s expected mask %s but got %s" % [label, expected, actual])
		quit(1)


func _assert_same_terrain_mask(map_data: RefCounted, tile: Vector2i, expected: int, label: String) -> void:
	var actual := AutoTile.same_terrain_mask(map_data, tile)
	if actual != expected:
		push_error("%s expected mask %s but got %s" % [label, expected, actual])
		quit(1)


func _assert_continuous_road_mesh(map_data: RefCounted) -> void:
	var renderer := Road3DLayer.new()
	renderer.set_map_data(map_data)
	if renderer.active_chunk_coords.size() != 1:
		push_error("Three nearby road tiles should render inside one local road chunk.")
		quit(1)
		renderer.free()
		return
	if renderer.last_cap_count != 2:
		push_error("Only road endpoints should receive caps; internal tiles must not render repeated pads.")
		quit(1)
		renderer.free()
		return
	var mesh := renderer.road_mesh_instance.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() != 1:
		push_error("Continuous road renderer should produce one layered network mesh.")
		quit(1)
		renderer.free()
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if vertices.is_empty() or colors.is_empty():
		push_error("Continuous road mesh should contain lunar deck, shoulder and rut geometry.")
		quit(1)
		renderer.free()
		return
	renderer.free()


func _assert_closed_road_loop() -> void:
	var loop_map := MapData.new(Vector2i(5, 5))
	for tile in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2)]:
		loop_map.set_road(tile)
	var renderer := Road3DLayer.new()
	renderer.set_map_data(loop_map)
	if renderer.active_chunk_coords.size() != 1 or renderer.last_cap_count != 0:
		push_error("A closed road loop should become one continuous ribbon without tile caps.")
		quit(1)
	renderer.free()


func _assert_local_chunk_rebuild() -> void:
	var large_map := MapData.new(Vector2i(64, 64))
	var total_roads := 0
	for y in range(0, 64, 4):
		for x in range(64):
			large_map.set_road(Vector2i(x, y))
			total_roads += 1
	var renderer := Road3DLayer.new()
	renderer.set_map_data(large_map)
	var far_chunk_mesh: Mesh = (renderer.chunk_instance_by_coord[Vector2i(0, 0)] as MeshInstance3D).mesh
	var new_road := Vector2i(62, 62)
	large_map.set_road(new_road)
	renderer.notify_road_changed(new_road)
	if renderer.last_chunks_rebuilt > 4:
		push_error("One road edit should rebuild at most the neighboring road chunks.")
		quit(1)
		renderer.free()
		return
	if renderer.last_cells_processed >= total_roads / 4:
		push_error("Local road rebuild should not process the existing network on distant chunks.")
		quit(1)
		renderer.free()
		return
	if (renderer.chunk_instance_by_coord[Vector2i(0, 0)] as MeshInstance3D).mesh != far_chunk_mesh:
		push_error("A distant road chunk should keep its existing mesh after a local road edit.")
		quit(1)
	renderer.free()
