extends Node3D

const TileVisualCatalog := preload("res://scripts/tile_visual_catalog.gd")

const TILE_PLANE_SIZE := 0.96

var map_data: RefCounted
var material_by_terrain := {}


func _ready() -> void:
	name = "Terrain3DLayer"


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	if map_data == null:
		return

	var buckets := {}
	for y in map_data.size.y:
		for x in map_data.size.x:
			var terrain_id: int = map_data.get_terrain(Vector2i(x, y))
			if not buckets.has(terrain_id):
				buckets[terrain_id] = []
			buckets[terrain_id].append(Vector2i(x, y))

	var plane := PlaneMesh.new()
	plane.size = Vector2(TILE_PLANE_SIZE, TILE_PLANE_SIZE)

	for terrain_id in buckets.keys():
		var tiles: Array = buckets[terrain_id]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = plane
		multimesh.instance_count = tiles.size()

		for index in tiles.size():
			var tile: Vector2i = tiles[index]
			var transform := Transform3D(Basis(), Vector3(float(tile.x), 0.0, float(tile.y)))
			multimesh.set_instance_transform(index, transform)

		var instance := MultiMeshInstance3D.new()
		instance.name = "Terrain_%s" % terrain_id
		instance.multimesh = multimesh
		instance.material_override = _material_for_terrain(int(terrain_id))
		add_child(instance)


func _material_for_terrain(terrain_id: int) -> StandardMaterial3D:
	if material_by_terrain.has(terrain_id):
		return material_by_terrain[terrain_id]

	var material := StandardMaterial3D.new()
	material.albedo_color = TileVisualCatalog.terrain_color(terrain_id)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_by_terrain[terrain_id] = material
	return material
