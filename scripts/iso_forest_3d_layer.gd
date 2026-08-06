extends Node3D

const TreeCollectionLoader := preload("res://scripts/tree_collection_loader.gd")

const TERRAIN_FOREST := 1
const TREE_COLLECTION_OBJ_PATH := "res://assets/3D/trees/LowPoly_Tree_Collection_01_obj.obj"
const TREE_TEXTURE_PATH := "res://assets/3D/trees/textures/color_1024x1024.jpg"
const MAX_TREE_VARIANTS := 32
const DEFAULT_TREE_DENSITY := 1.0
const TREE_MIN_SCALE := 0.105
const TREE_MAX_SCALE := 0.165

var map_data: RefCounted
var tree_meshes: Array[ArrayMesh] = []
var material: StandardMaterial3D
var target_density: float = DEFAULT_TREE_DENSITY
var global_tree_scale: float = 1.4
var rebuild_requests: int = 0
var last_cells_processed: int = 0
var last_rebuild_usec: int = 0
var last_reason := ""


func _ready() -> void:
	name = "Forest3DLayer"
	_ensure_initialized()


func set_map_data(next_map_data: RefCounted) -> void:
	_ensure_initialized()
	map_data = next_map_data
	_rebuild("set_map_data")


func refresh_forest(reason: String) -> void:
	_rebuild(reason)


func set_visual_tuning(next_global_tree_scale: float, next_target_density: float) -> void:
	global_tree_scale = clampf(next_global_tree_scale, 0.2, 3.0)
	target_density = clampf(next_target_density, 0.0, 1.0)
	_rebuild("visual_tuning")


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": 0,
		"redraw_requests": rebuild_requests,
		"last_draw_usec": 0,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_rebuild_usec,
		"last_reason": last_reason,
	}


func _ensure_initialized() -> void:
	if material == null:
		_build_material()
	if tree_meshes.is_empty():
		var loader := TreeCollectionLoader.new()
		tree_meshes = loader.load_tree_meshes(TREE_COLLECTION_OBJ_PATH, MAX_TREE_VARIANTS)


func _build_material() -> void:
	material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(TREE_TEXTURE_PATH):
		material.albedo_texture = load(TREE_TEXTURE_PATH) as Texture2D


func _rebuild(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = 0

	for child in get_children():
		child.queue_free()

	if map_data == null or tree_meshes.is_empty():
		last_rebuild_usec = Time.get_ticks_usec() - started
		return

	var placements_by_variant := {}
	for index in tree_meshes.size():
		placements_by_variant[index] = []
	var fallback_tile := Vector2i(-1, -1)

	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if map_data.get_terrain(tile) != TERRAIN_FOREST:
				continue
			last_cells_processed += 1
			if fallback_tile == Vector2i(-1, -1):
				fallback_tile = tile
			if _unit_noise(tile, 3) > target_density:
				continue
			var variant := int(floor(_unit_noise(tile, 17) * float(tree_meshes.size()))) % tree_meshes.size()
			placements_by_variant[variant].append(_tree_transform(tile))

	if target_density > 0.0 and fallback_tile != Vector2i(-1, -1) and _placement_count(placements_by_variant) == 0:
		var fallback_variant := int(floor(_unit_noise(fallback_tile, 17) * float(tree_meshes.size()))) % tree_meshes.size()
		placements_by_variant[fallback_variant].append(_tree_transform(fallback_tile))

	for variant in placements_by_variant.keys():
		var placements: Array = placements_by_variant[variant]
		if placements.is_empty():
			continue
		_add_variant_instances(int(variant), placements)

	last_rebuild_usec = Time.get_ticks_usec() - started


func _placement_count(placements_by_variant: Dictionary) -> int:
	var count := 0
	for placements in placements_by_variant.values():
		count += (placements as Array).size()
	return count


func _add_variant_instances(variant: int, placements: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tree_meshes[variant]
	multimesh.instance_count = placements.size()

	for index in placements.size():
		multimesh.set_instance_transform(index, placements[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = "TreeVariant_%02d" % variant
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


func _tree_transform(tile: Vector2i) -> Transform3D:
	var rotation := _unit_noise(tile, 29) * TAU
	var scale := lerpf(TREE_MIN_SCALE, TREE_MAX_SCALE, _unit_noise(tile, 41)) * global_tree_scale
	var offset := Vector2(
		(_unit_noise(tile, 53) - 0.5) * 0.42,
		(_unit_noise(tile, 67) - 0.5) * 0.42
	)
	var origin := Vector3(float(tile.x) + offset.x, 0.055, float(tile.y) + offset.y)
	var basis := Basis(Vector3.UP, rotation).scaled(Vector3.ONE * scale)
	return Transform3D(basis, origin)


func _unit_noise(tile: Vector2i, salt: int) -> float:
	var seed := 1
	if map_data != null:
		seed = maxi(1, int(map_data.seed))
	var value := int(tile.x * 374761393 + tile.y * 668265263 + seed * 2246822519 + salt * 3266489917)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xffff) / 65535.0
