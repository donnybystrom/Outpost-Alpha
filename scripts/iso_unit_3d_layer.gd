extends Node3D

const ROLE_DRILLING_MACHINE := "drilling_machine"
const ROLE_HAULER := "hauler"
const FACING_SOUTH_EAST := "south_east"
const FACING_NORTH_EAST := "north_east"
const FACING_SOUTH_WEST := "south_west"
const FACING_NORTH_WEST := "north_west"

const HAULER_EMPTY := "hauler_empty"
const HAULER_FILLED := "hauler_filled"
const DRILLING_MACHINE_EMPTY := "drilling_machine_empty"
const DRILLING_MACHINE_FULL := "drilling_machine_full"
const HAULER_EMPTY_MESH_PATH := "res://assets/3D/units/hauler_empty/base.obj"
const HAULER_EMPTY_DIFFUSE_TEXTURE_PATH := "res://assets/3D/units/hauler_empty/texture_diffuse.png"
const HAULER_EMPTY_NORMAL_TEXTURE_PATH := "res://assets/3D/units/hauler_empty/texture_normal.png"
const HAULER_EMPTY_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/units/hauler_empty/texture_roughness.png"
const HAULER_EMPTY_METALLIC_TEXTURE_PATH := "res://assets/3D/units/hauler_empty/texture_metallic.png"
const HAULER_FILLED_MESH_PATH := "res://assets/3D/units/hauler_filled/base.obj"
const HAULER_FILLED_DIFFUSE_TEXTURE_PATH := "res://assets/3D/units/hauler_filled/texture_diffuse.png"
const HAULER_FILLED_NORMAL_TEXTURE_PATH := "res://assets/3D/units/hauler_filled/texture_normal.png"
const HAULER_FILLED_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/units/hauler_filled/texture_roughness.png"
const HAULER_FILLED_METALLIC_TEXTURE_PATH := "res://assets/3D/units/hauler_filled/texture_metallic.png"
const DRILLING_MACHINE_EMPTY_MESH_PATH := "res://assets/3D/units/drilling_machine_empty/base.obj"
const DRILLING_MACHINE_EMPTY_DIFFUSE_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_empty/texture_diffuse.png"
const DRILLING_MACHINE_EMPTY_NORMAL_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_empty/texture_normal.png"
const DRILLING_MACHINE_EMPTY_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_empty/texture_roughness.png"
const DRILLING_MACHINE_EMPTY_METALLIC_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_empty/texture_metallic.png"
const DRILLING_MACHINE_FULL_MESH_PATH := "res://assets/3D/units/drilling_machine_full/base.obj"
const DRILLING_MACHINE_FULL_DIFFUSE_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_full/texture_diffuse.jpeg"
const DRILLING_MACHINE_FULL_NORMAL_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_full/texture_normal.png"
const DRILLING_MACHINE_FULL_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_full/texture_roughness.png"
const DRILLING_MACHINE_FULL_METALLIC_TEXTURE_PATH := "res://assets/3D/units/drilling_machine_full/texture_metallic.png"

const HAULER_SCALE := Vector3(0.56, 0.56, 0.56)
const DRILLING_MACHINE_SCALE := Vector3(0.58, 0.58, 0.58)
const HAULER_HEIGHT_OFFSET := 0.07
const DRILLING_MACHINE_HEIGHT_OFFSET := 0.07

var unit_state: RefCounted
var mesh_by_variant := {}
var material_by_variant := {}
var instance_by_unit_id := {}
var variant_by_unit_id := {}
var sync_requests: int = 0
var last_units_processed: int = 0
var last_sync_usec: int = 0


func _ready() -> void:
	name = "Unit3DLayer"


func set_unit_state(next_unit_state: RefCounted) -> void:
	unit_state = next_unit_state
	sync_units("set_unit_state")


func sync_units(reason := "sync") -> void:
	var started := Time.get_ticks_usec()
	sync_requests += 1
	last_units_processed = 0

	if unit_state == null:
		_clear_all_instances()
		last_sync_usec = Time.get_ticks_usec() - started
		return

	var live_ids := {}
	for unit in unit_state.workers:
		if not _is_model_backed_unit(unit):
			continue
		last_units_processed += 1
		var unit_id := int(unit["id"])
		live_ids[unit_id] = true
		_sync_model_unit(unit)

	for unit_id in instance_by_unit_id.keys():
		if not live_ids.has(int(unit_id)):
			_remove_instance(int(unit_id))

	last_sync_usec = Time.get_ticks_usec() - started


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": 0,
		"redraw_requests": sync_requests,
		"last_draw_usec": 0,
		"last_cells": last_units_processed,
		"last_bake_usec": last_sync_usec,
		"last_reason": "unit_3d_sync",
	}


func _sync_model_unit(unit: Dictionary) -> void:
	var unit_id := int(unit["id"])
	var variant := _variant_for_unit(unit)
	var instance := _instance_for_unit(unit_id, variant)
	if instance == null:
		return
	instance.transform = _transform_for_unit(unit)


func _instance_for_unit(unit_id: int, variant: String) -> MeshInstance3D:
	if instance_by_unit_id.has(unit_id) and variant_by_unit_id.get(unit_id, "") == variant:
		return instance_by_unit_id[unit_id]

	_remove_instance(unit_id)
	var mesh := _mesh_for_variant(variant)
	if mesh == null:
		return null

	var instance := MeshInstance3D.new()
	instance.name = "Unit3D_%s_%s" % [variant, unit_id]
	instance.mesh = mesh
	instance.material_override = _material_for_variant(variant)
	add_child(instance)
	instance_by_unit_id[unit_id] = instance
	variant_by_unit_id[unit_id] = variant
	return instance


func _remove_instance(unit_id: int) -> void:
	if instance_by_unit_id.has(unit_id):
		var instance := instance_by_unit_id[unit_id] as MeshInstance3D
		if instance != null:
			instance.queue_free()
	instance_by_unit_id.erase(unit_id)
	variant_by_unit_id.erase(unit_id)


func _clear_all_instances() -> void:
	for unit_id in instance_by_unit_id.keys():
		_remove_instance(int(unit_id))


func _variant_for_unit(unit: Dictionary) -> String:
	var has_cargo := int(unit.get("cargo", 0)) > 0
	match unit.get("role", ""):
		ROLE_HAULER:
			return HAULER_FILLED if has_cargo else HAULER_EMPTY
		ROLE_DRILLING_MACHINE:
			return DRILLING_MACHINE_FULL if has_cargo else DRILLING_MACHINE_EMPTY
		_:
			return ""


func _is_model_backed_unit(unit: Dictionary) -> bool:
	var role: String = unit.get("role", "")
	return role == ROLE_HAULER or role == ROLE_DRILLING_MACHINE


func _mesh_for_variant(variant: String) -> Mesh:
	if mesh_by_variant.has(variant):
		return mesh_by_variant[variant]
	var mesh_path := _mesh_path_for_variant(variant)
	if mesh_path.is_empty():
		return null
	if not ResourceLoader.exists(mesh_path):
		push_warning("Missing 3D unit mesh: %s" % mesh_path)
		return null
	var mesh := load(mesh_path) as Mesh
	if mesh == null:
		push_warning("Could not load 3D unit mesh: %s" % mesh_path)
		return null
	mesh_by_variant[variant] = mesh
	return mesh


func _material_for_variant(variant: String) -> StandardMaterial3D:
	if material_by_variant.has(variant):
		return material_by_variant[variant]

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var paths := _texture_paths_for_variant(variant)
	var diffuse_path: String = paths["diffuse"]
	if ResourceLoader.exists(diffuse_path):
		material.albedo_texture = load(diffuse_path) as Texture2D

	var normal_path: String = paths["normal"]
	if ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path) as Texture2D
		material.normal_scale = 1.0

	var roughness_path: String = paths["roughness"]
	if ResourceLoader.exists(roughness_path):
		material.roughness_texture = load(roughness_path) as Texture2D

	var metallic_path: String = paths["metallic"]
	if ResourceLoader.exists(metallic_path):
		material.metallic_texture = load(metallic_path) as Texture2D

	material_by_variant[variant] = material
	return material


func _texture_paths_for_variant(variant: String) -> Dictionary:
	if variant == HAULER_FILLED:
		return {
			"diffuse": HAULER_FILLED_DIFFUSE_TEXTURE_PATH,
			"normal": HAULER_FILLED_NORMAL_TEXTURE_PATH,
			"roughness": HAULER_FILLED_ROUGHNESS_TEXTURE_PATH,
			"metallic": HAULER_FILLED_METALLIC_TEXTURE_PATH,
		}
	if variant == DRILLING_MACHINE_EMPTY:
		return {
			"diffuse": DRILLING_MACHINE_EMPTY_DIFFUSE_TEXTURE_PATH,
			"normal": DRILLING_MACHINE_EMPTY_NORMAL_TEXTURE_PATH,
			"roughness": DRILLING_MACHINE_EMPTY_ROUGHNESS_TEXTURE_PATH,
			"metallic": DRILLING_MACHINE_EMPTY_METALLIC_TEXTURE_PATH,
		}
	if variant == DRILLING_MACHINE_FULL:
		return {
			"diffuse": DRILLING_MACHINE_FULL_DIFFUSE_TEXTURE_PATH,
			"normal": DRILLING_MACHINE_FULL_NORMAL_TEXTURE_PATH,
			"roughness": DRILLING_MACHINE_FULL_ROUGHNESS_TEXTURE_PATH,
			"metallic": DRILLING_MACHINE_FULL_METALLIC_TEXTURE_PATH,
		}
	return {
		"diffuse": HAULER_EMPTY_DIFFUSE_TEXTURE_PATH,
		"normal": HAULER_EMPTY_NORMAL_TEXTURE_PATH,
		"roughness": HAULER_EMPTY_ROUGHNESS_TEXTURE_PATH,
		"metallic": HAULER_EMPTY_METALLIC_TEXTURE_PATH,
	}


func _mesh_path_for_variant(variant: String) -> String:
	match variant:
		HAULER_EMPTY:
			return HAULER_EMPTY_MESH_PATH
		HAULER_FILLED:
			return HAULER_FILLED_MESH_PATH
		DRILLING_MACHINE_EMPTY:
			return DRILLING_MACHINE_EMPTY_MESH_PATH
		DRILLING_MACHINE_FULL:
			return DRILLING_MACHINE_FULL_MESH_PATH
		_:
			return ""


func _transform_for_unit(unit: Dictionary) -> Transform3D:
	var position: Vector2 = unit.get("position", Vector2.ZERO)
	position += _screen_offset_to_map_offset(unit.get("visual_offset", Vector2.ZERO))
	var role: String = unit.get("role", "")
	var height_offset := DRILLING_MACHINE_HEIGHT_OFFSET if role == ROLE_DRILLING_MACHINE else HAULER_HEIGHT_OFFSET
	var scale := DRILLING_MACHINE_SCALE if role == ROLE_DRILLING_MACHINE else HAULER_SCALE
	var origin := Vector3(position.x, height_offset, position.y)
	var yaw := _yaw_for_heading(float(unit["heading"])) if unit.has("heading") else _yaw_for_facing(unit.get("facing", FACING_SOUTH_EAST))
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	return Transform3D(basis, origin)


func _screen_offset_to_map_offset(screen_offset: Vector2) -> Vector2:
	return Vector2(
		screen_offset.y / 16.0 + screen_offset.x / 32.0,
		screen_offset.y / 16.0 - screen_offset.x / 32.0
	)


func _yaw_for_facing(facing: String) -> float:
	match facing:
		FACING_SOUTH_EAST:
			return PI * 0.5
		FACING_NORTH_EAST:
			return PI
		FACING_NORTH_WEST:
			return -PI * 0.5
		FACING_SOUTH_WEST:
			return 0.0
		_:
			return PI * 0.5


func _yaw_for_heading(heading: float) -> float:
	return PI * 0.5 - heading
