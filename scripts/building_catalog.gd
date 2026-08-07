extends RefCounted

const ORIENTATION_HORIZONTAL := "horizontal"
const ORIENTATION_VERTICAL := "vertical"

const BUILDING_LIVING_QUARTERS := "living_quarters"
const BUILDING_OXYGEN_EXTRACTOR := "oxygen_extractor"
const BUILDING_MACHINE_PARK := "machine_park"
const BUILDING_MILLING_PLANT := "milling_plant"
const BUILDING_HQ := "hq"
const BUILDING_PLANET_LANDER_MODULE := "planet_lander_module"
const UNIT_DRILLING_MACHINE := "drilling_machine"
const UNIT_HAULER := "hauler"

const CATALOG_PATH := "res://scripts/building_catalog.gd"
const BUILDINGS_ATLAS_PATH := "res://assets/objects/buildings.png"
const HQ_MODEL_MESH_PATH := "res://assets/3D/buildings/hq/base.obj"
const HQ_MODEL_DIFFUSE_TEXTURE_PATH := "res://assets/3D/buildings/hq/texture_diffuse.png"
const HQ_MODEL_EMISSIVE_TEXTURE_PATH := "res://assets/3D/buildings/hq/texture_emissive.png"
const HQ_MODEL_NORMAL_TEXTURE_PATH := "res://assets/3D/buildings/hq/texture_normal.png"
const HQ_MODEL_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/buildings/hq/texture_roughness.png"
const HQ_MODEL_METALLIC_TEXTURE_PATH := "res://assets/3D/buildings/hq/texture_metallic.png"
const PLANET_LANDER_MODEL_MESH_PATH := "res://assets/3D/buildings/planet_lander_module_landed/base.obj"
const PLANET_LANDER_MODEL_DIFFUSE_TEXTURE_PATH := "res://assets/3D/buildings/planet_lander_module_landed/texture_diffuse.png"
const PLANET_LANDER_MODEL_NORMAL_TEXTURE_PATH := "res://assets/3D/buildings/planet_lander_module_landed/texture_normal.png"
const PLANET_LANDER_MODEL_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/buildings/planet_lander_module_landed/texture_roughness.png"
const PLANET_LANDER_MODEL_METALLIC_TEXTURE_PATH := "res://assets/3D/buildings/planet_lander_module_landed/texture_metallic.png"
const OXYGEN_EXTRACTOR_MODEL_MESH_PATH := "res://assets/3D/buildings/oxygen_extractor/base.obj"
const OXYGEN_EXTRACTOR_MODEL_DIFFUSE_TEXTURE_PATH := "res://assets/3D/buildings/oxygen_extractor/texture_diffuse.png"
const OXYGEN_EXTRACTOR_MODEL_EMISSIVE_TEXTURE_PATH := "res://assets/3D/buildings/oxygen_extractor/texture_emissive.png"
const OXYGEN_EXTRACTOR_MODEL_NORMAL_TEXTURE_PATH := "res://assets/3D/buildings/oxygen_extractor/texture_normal.png"
const OXYGEN_EXTRACTOR_MODEL_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/buildings/oxygen_extractor/texture_roughness.png"
const OXYGEN_EXTRACTOR_MODEL_METALLIC_TEXTURE_PATH := "res://assets/3D/buildings/oxygen_extractor/texture_metallic.png"
const MACHINE_PARK_MODEL_MESH_PATH := "res://assets/3D/buildings/machine_park/base.obj"
const MACHINE_PARK_MODEL_DIFFUSE_TEXTURE_PATH := "res://assets/3D/buildings/machine_park/texture_diffuse.png"
const MACHINE_PARK_MODEL_EMISSIVE_TEXTURE_PATH := "res://assets/3D/buildings/machine_park/texture_emissive.png"
const MACHINE_PARK_MODEL_NORMAL_TEXTURE_PATH := "res://assets/3D/buildings/machine_park/texture_normal.png"
const MACHINE_PARK_MODEL_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/buildings/machine_park/texture_roughness.png"
const MACHINE_PARK_MODEL_METALLIC_TEXTURE_PATH := "res://assets/3D/buildings/machine_park/texture_metallic.png"
const MILLING_PLANT_MODEL_MESH_PATH := "res://assets/3D/buildings/milling_plant/base.obj"
const MILLING_PLANT_MODEL_DIFFUSE_TEXTURE_PATH := "res://assets/3D/buildings/milling_plant/texture_diffuse.png"
const MILLING_PLANT_MODEL_EMISSIVE_TEXTURE_PATH := "res://assets/3D/buildings/milling_plant/texture_emissive.png"
const MILLING_PLANT_MODEL_NORMAL_TEXTURE_PATH := "res://assets/3D/buildings/milling_plant/texture_normal.png"
const MILLING_PLANT_MODEL_ROUGHNESS_TEXTURE_PATH := "res://assets/3D/buildings/milling_plant/texture_roughness.png"
const MILLING_PLANT_MODEL_METALLIC_TEXTURE_PATH := "res://assets/3D/buildings/milling_plant/texture_metallic.png"

const BUILDING_TYPES := {
	BUILDING_LIVING_QUARTERS: {
		"name": "Living Quarters",
		"label": "LQ",
		"footprint": Vector2i(2, 3),
		"population_capacity": 8,
		"oxygen_capacity": 0,
		"digger_capacity": 0,
		"max_health": 180,
		"power_usage": 8,
		"metal_cost": 0,
		"vehicle_entry": Vector2i(1, 2),
		"vehicle_approach": Vector2i(1, 3),
	},
	BUILDING_OXYGEN_EXTRACTOR: {
		"name": "Oxygen Extractor",
		"label": "O2",
		"footprint": Vector2i(2, 2),
		"population_capacity": 0,
		"oxygen_capacity": 5,
		"digger_capacity": 0,
		"max_health": 140,
		"power_usage": 14,
		"metal_cost": 40,
		"vehicle_entry": Vector2i(1, 1),
		"vehicle_approach": Vector2i(1, 2),
		"sprite": {
			"atlas_path": BUILDINGS_ATLAS_PATH,
			"source": Rect2i(178, 18, 54, 55),
			"flip_horizontal_on_vertical": true,
			"anchor": Vector2(28, 45),
			"screen_offset": Vector2(0, 24),
		},
		"model": {
			"mesh_path": OXYGEN_EXTRACTOR_MODEL_MESH_PATH,
			"diffuse_texture": OXYGEN_EXTRACTOR_MODEL_DIFFUSE_TEXTURE_PATH,
			"emissive_texture": OXYGEN_EXTRACTOR_MODEL_EMISSIVE_TEXTURE_PATH,
			"normal_texture": OXYGEN_EXTRACTOR_MODEL_NORMAL_TEXTURE_PATH,
			"roughness_texture": OXYGEN_EXTRACTOR_MODEL_ROUGHNESS_TEXTURE_PATH,
			"metallic_texture": OXYGEN_EXTRACTOR_MODEL_METALLIC_TEXTURE_PATH,
			"scale": Vector3(1.05, 1.05, 1.05),
			"height_offset": 0.04,
			"rotation_y": 0.0,
		},
	},
	BUILDING_MACHINE_PARK: {
		"name": "Machine Park",
		"label": "MP",
		"footprint": Vector2i(4, 2),
		"population_capacity": 0,
		"oxygen_capacity": 0,
		"digger_capacity": 2,
		"max_health": 220,
		"power_usage": 18,
		"metal_cost": 60,
		"vehicle_entry": Vector2i(1, 1),
		"vehicle_approach": Vector2i(1, 2),
		"vehicle_build_options": {
			UNIT_DRILLING_MACHINE: {
				"name": "Drilling Machine",
				"metal_cost": 50,
			},
			UNIT_HAULER: {
				"name": "Hauler",
				"metal_cost": 35,
			},
		},
		"sprite": {
			"atlas_path": BUILDINGS_ATLAS_PATH,
			"source": Rect2i(380, 10, 64, 46),
			"flip_horizontal_on_vertical": true,
			"anchor": Vector2(20, 40),
			"screen_offset": Vector2(0, 24),
		},
		"model": {
			"mesh_path": MACHINE_PARK_MODEL_MESH_PATH,
			"diffuse_texture": MACHINE_PARK_MODEL_DIFFUSE_TEXTURE_PATH,
			"emissive_texture": MACHINE_PARK_MODEL_EMISSIVE_TEXTURE_PATH,
			"normal_texture": MACHINE_PARK_MODEL_NORMAL_TEXTURE_PATH,
			"roughness_texture": MACHINE_PARK_MODEL_ROUGHNESS_TEXTURE_PATH,
			"metallic_texture": MACHINE_PARK_MODEL_METALLIC_TEXTURE_PATH,
			"scale": Vector3(2.2,2.2,2.2),
			"height_offset": 0,
			"rotation_y": PI * 0.5,
		},
	},
	BUILDING_MILLING_PLANT: {
		"name": "Milling Plant",
		"label": "MILL",
		"footprint": Vector2i(2, 3),
		"population_capacity": 0,
		"oxygen_capacity": 0,
		"digger_capacity": 0,
		"max_health": 260,
		"power_usage": 22,
		"metal_cost": 40,
		"raw_capacity": 100,
		"metal_output_rate": 6,
		"vehicle_entry": Vector2i(1, 2),
		"vehicle_approach": Vector2i(1, 3),
		"sprite": {
			"atlas_path": BUILDINGS_ATLAS_PATH,
			"source": Rect2i(290, 7, 73, 45),
			"flip_horizontal_on_vertical": true,
			"anchor": Vector2(27, 44),
			"screen_offset": Vector2(0, 24),
		},
		"model": {
			"mesh_path": MILLING_PLANT_MODEL_MESH_PATH,
			"diffuse_texture": MILLING_PLANT_MODEL_DIFFUSE_TEXTURE_PATH,
			"emissive_texture": MILLING_PLANT_MODEL_EMISSIVE_TEXTURE_PATH,
			"normal_texture": MILLING_PLANT_MODEL_NORMAL_TEXTURE_PATH,
			"roughness_texture": MILLING_PLANT_MODEL_ROUGHNESS_TEXTURE_PATH,
			"metallic_texture": MILLING_PLANT_MODEL_METALLIC_TEXTURE_PATH,
			"scale": Vector3(1.5, 1.5, 1.5),
			"height_offset": 0.03,
			"rotation_y": 0.0,
		},
	},
	BUILDING_HQ: {
		"name": "HQ",
		"label": "HQ",
		"footprint": Vector2i(3, 3),
		"population_capacity": 0,
		"oxygen_capacity": 0,
		"digger_capacity": 0,
		"max_health": 420,
		"power_usage": 30,
		"metal_cost": 0,
		"vehicle_entry": Vector2i(1, 2),
		"vehicle_approach": Vector2i(1, 3),
		"sprite": {
			"atlas_path": BUILDINGS_ATLAS_PATH,
			"source": Rect2i(452, 7, 84, 53),
			"flip_horizontal_on_vertical": true,
			"anchor": Vector2(42, 40),
			"screen_offset": Vector2(0, 24),
		},
		"model": {
			"mesh_path": HQ_MODEL_MESH_PATH,
			"diffuse_texture": HQ_MODEL_DIFFUSE_TEXTURE_PATH,
			"emissive_texture": HQ_MODEL_EMISSIVE_TEXTURE_PATH,
			"normal_texture": HQ_MODEL_NORMAL_TEXTURE_PATH,
			"roughness_texture": HQ_MODEL_ROUGHNESS_TEXTURE_PATH,
			"metallic_texture": HQ_MODEL_METALLIC_TEXTURE_PATH,
			"scale": Vector3(1.35, 1.35, 1.35),
			"height_offset": 0.04,
			"rotation_y": 0.0,
		},
	},
	BUILDING_PLANET_LANDER_MODULE: {
		"name": "Planet Lander",
		"label": "LANDER",
		"footprint": Vector2i(3, 3),
		"population_capacity": 0,
		"oxygen_capacity": 0,
		"digger_capacity": 0,
		"max_health": 480,
		"power_usage": 30,
		"metal_cost": 0,
		"placeable": false,
		"vehicle_entry": Vector2i(1, 2),
		"vehicle_approach": Vector2i(1, 3),
		"model": {
			"mesh_path": PLANET_LANDER_MODEL_MESH_PATH,
			"diffuse_texture": PLANET_LANDER_MODEL_DIFFUSE_TEXTURE_PATH,
			"normal_texture": PLANET_LANDER_MODEL_NORMAL_TEXTURE_PATH,
			"roughness_texture": PLANET_LANDER_MODEL_ROUGHNESS_TEXTURE_PATH,
			"metallic_texture": PLANET_LANDER_MODEL_METALLIC_TEXTURE_PATH,
			"scale": Vector3(1.55, 1.55, 1.55),
			"height_offset": 0.04,
			"rotation_y": 0.0,
		},
	},
}


static func has_building(building_type: String) -> bool:
	return BUILDING_TYPES.has(building_type)


static func definition(building_type: String) -> Dictionary:
	return BUILDING_TYPES.get(building_type, {})


static func footprint(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	var base: Vector2i = definition(building_type).get("footprint", Vector2i.ONE)
	if orientation == ORIENTATION_VERTICAL:
		return Vector2i(base.y, base.x)
	return base


static func oriented_offset(building_type: String, offset: Vector2i, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	if orientation == ORIENTATION_VERTICAL:
		return Vector2i(offset.y, offset.x)
	return offset


static func vehicle_entry_offset(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	var offset: Vector2i = definition(building_type).get("vehicle_entry", Vector2i.ZERO)
	return oriented_offset(building_type, offset, orientation)


static func vehicle_approach_offset(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	var offset: Vector2i = definition(building_type).get("vehicle_approach", Vector2i.ZERO)
	return oriented_offset(building_type, offset, orientation)


static func sprite_config(building_type: String) -> Dictionary:
	return definition(building_type).get("sprite", {})


static func sprite_source_rect(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Rect2i:
	var sprite: Dictionary = sprite_config(building_type)
	var source = sprite.get("source", Rect2i())
	if source is Rect2i:
		return source
	if source is Dictionary:
		return source.get(orientation, source.get(ORIENTATION_HORIZONTAL, Rect2i()))
	return Rect2i()


static func sprite_flip_horizontal(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> bool:
	var sprite: Dictionary = sprite_config(building_type)
	var source = sprite.get("source", Rect2i())
	var default_flip: bool = not (source is Dictionary and source.has(orientation))
	return orientation == ORIENTATION_VERTICAL and bool(sprite.get("flip_horizontal_on_vertical", default_flip))


static func sprite_anchor(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2:
	var sprite: Dictionary = sprite_config(building_type)
	var configured_anchor = sprite.get("anchor", Vector2.ZERO)
	var anchor := Vector2.ZERO
	if configured_anchor is Dictionary:
		anchor = configured_anchor.get(orientation, configured_anchor.get(ORIENTATION_HORIZONTAL, Vector2.ZERO))
	else:
		anchor = configured_anchor
	if sprite_flip_horizontal(building_type, orientation):
		var source_rect := sprite_source_rect(building_type, orientation)
		anchor.x = float(source_rect.size.x) - anchor.x
	return anchor


static func sprite_screen_offset(building_type: String) -> Vector2:
	return sprite_config(building_type).get("screen_offset", Vector2.ZERO)


static func model_config(building_type: String) -> Dictionary:
	return definition(building_type).get("model", {})


static func toggle_orientation(orientation: String) -> String:
	return ORIENTATION_VERTICAL if orientation == ORIENTATION_HORIZONTAL else ORIENTATION_HORIZONTAL


func atlas_path() -> String:
	return BUILDINGS_ATLAS_PATH


func has(building_type: String) -> bool:
	return has_building(building_type)


func get_definition(building_type: String) -> Dictionary:
	return definition(building_type)


func get_footprint(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	return footprint(building_type, orientation)


func get_oriented_offset(building_type: String, offset: Vector2i, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	return oriented_offset(building_type, offset, orientation)


func get_vehicle_entry_offset(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	return vehicle_entry_offset(building_type, orientation)


func get_vehicle_approach_offset(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2i:
	return vehicle_approach_offset(building_type, orientation)


func get_sprite_config(building_type: String) -> Dictionary:
	return sprite_config(building_type)


func get_sprite_source_rect(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Rect2i:
	return sprite_source_rect(building_type, orientation)


func should_flip_sprite_horizontal(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> bool:
	return sprite_flip_horizontal(building_type, orientation)


func get_sprite_anchor(building_type: String, orientation := ORIENTATION_HORIZONTAL) -> Vector2:
	return sprite_anchor(building_type, orientation)


func get_sprite_screen_offset(building_type: String) -> Vector2:
	return sprite_screen_offset(building_type)


func get_model_config(building_type: String) -> Dictionary:
	return model_config(building_type)


func get_toggled_orientation(orientation: String) -> String:
	return toggle_orientation(orientation)
