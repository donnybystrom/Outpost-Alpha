extends RefCounted

const BuildingCatalog := preload("res://scripts/building_catalog.gd")

const BUILDING_LIVING_QUARTERS := BuildingCatalog.BUILDING_LIVING_QUARTERS
const BUILDING_OXYGEN_EXTRACTOR := BuildingCatalog.BUILDING_OXYGEN_EXTRACTOR
const BUILDING_MACHINE_PARK := BuildingCatalog.BUILDING_MACHINE_PARK
const BUILDING_MILLING_PLANT := BuildingCatalog.BUILDING_MILLING_PLANT
const BUILDING_HQ := BuildingCatalog.BUILDING_HQ
const BUILDING_PLANET_LANDER_MODULE := BuildingCatalog.BUILDING_PLANET_LANDER_MODULE
const BUILDING_TYPES := BuildingCatalog.BUILDING_TYPES
const STARTING_LANDER_METAL := 950
const STARTING_HQ_METAL := STARTING_LANDER_METAL

var building_catalog = BuildingCatalog.new()
var buildings: Array[Dictionary] = []
var population: int = 5
var oxygen_days_remaining: int = 3
var digger_operators: int = 0
var infantry: int = 0
var resources := {
	"stone": 0,
	"ore": 0,
	"metal": STARTING_HQ_METAL,
}
var _next_building_id: int = 1


func reset() -> void:
	buildings.clear()
	population = 5
	oxygen_days_remaining = 3
	digger_operators = 0
	infantry = 0
	resources = {
		"stone": 0,
		"ore": 0,
		"metal": STARTING_HQ_METAL,
	}
	_next_building_id = 1


func set_building_catalog(next_building_catalog) -> void:
	if next_building_catalog == null:
		return
	building_catalog = next_building_catalog
	refresh_building_metadata()
	_clamp_assignments()


func refresh_building_metadata() -> void:
	for building in buildings:
		var building_type: String = building["type"]
		var origin: Vector2i = building["origin"]
		var orientation: String = building.get("orientation", BuildingCatalog.ORIENTATION_HORIZONTAL)
		var max_health: int = int(building_catalog.get_definition(building_type).get("max_health", 100))
		building["footprint"] = building_catalog.get_footprint(building_type, orientation)
		building["vehicle_entry_tile"] = origin + building_catalog.get_vehicle_entry_offset(building_type, orientation)
		building["vehicle_approach_tile"] = origin + building_catalog.get_vehicle_approach_offset(building_type, orientation)
		building["max_health"] = max_health
		building["health"] = mini(int(building.get("health", max_health)), max_health)
		building["power_usage"] = int(building_catalog.get_definition(building_type).get("power_usage", 0))
		building["stored_raw"] = int(building.get("stored_raw", 0))
		building["stored_metal"] = int(building.get("stored_metal", 0))
		building["processing_progress"] = float(building.get("processing_progress", 0.0))


func can_place_building(building_type: String, origin: Vector2i, map_data: RefCounted, orientation := BuildingCatalog.ORIENTATION_HORIZONTAL) -> bool:
	if not building_catalog.has(building_type) or map_data == null:
		return false

	for tile in footprint_tiles(building_type, origin, orientation):
		if not map_data.is_inside(tile):
			return false
		if map_data.has_road(tile):
			return false
		if map_data.get_terrain(tile) > 1:
			return false
		if is_occupied(tile):
			return false

	return true


func can_afford_building(building_type: String) -> bool:
	return get_hq_stored_metal() >= get_building_metal_cost(building_type)


func get_building_metal_cost(building_type: String) -> int:
	return int(building_catalog.get_definition(building_type).get("metal_cost", 0))


func place_building(building_type: String, origin: Vector2i, map_data: RefCounted, orientation := BuildingCatalog.ORIENTATION_HORIZONTAL) -> bool:
	if not can_place_building(building_type, origin, map_data, orientation):
		return false
	if not spend_hq_metal(get_building_metal_cost(building_type)):
		return false

	_add_building(building_type, origin, orientation)
	_clamp_assignments()
	return true


func place_starting_hq(origin: Vector2i) -> bool:
	_add_building(BUILDING_HQ, origin, BuildingCatalog.ORIENTATION_HORIZONTAL, STARTING_HQ_METAL)
	return true


func place_starting_lander(origin: Vector2i) -> bool:
	_add_building(BUILDING_PLANET_LANDER_MODULE, origin, BuildingCatalog.ORIENTATION_HORIZONTAL, 0)
	var index := buildings.size() - 1
	buildings[index]["operational"] = false
	buildings[index]["landing_state"] = "descending"
	return true


func complete_starting_lander_landing() -> bool:
	for index in buildings.size():
		if buildings[index].get("type", "") != BUILDING_PLANET_LANDER_MODULE:
			continue
		var building := buildings[index]
		building["operational"] = true
		building["landing_state"] = "landed"
		building["stored_metal"] = STARTING_LANDER_METAL
		buildings[index] = building
		return true
	return false


func _add_building(building_type: String, origin: Vector2i, orientation := BuildingCatalog.ORIENTATION_HORIZONTAL, stored_metal := 0) -> void:
	buildings.append({
		"id": _next_building_id,
		"type": building_type,
		"origin": origin,
		"orientation": orientation,
		"footprint": building_catalog.get_footprint(building_type, orientation),
		"health": int(building_catalog.get_definition(building_type).get("max_health", 100)),
		"max_health": int(building_catalog.get_definition(building_type).get("max_health", 100)),
		"power_usage": int(building_catalog.get_definition(building_type).get("power_usage", 0)),
		"stored_raw": 0,
		"stored_metal": stored_metal,
		"vehicle_entry_tile": origin + building_catalog.get_vehicle_entry_offset(building_type, orientation),
		"vehicle_approach_tile": origin + building_catalog.get_vehicle_approach_offset(building_type, orientation),
	})
	_next_building_id += 1


func footprint_tiles(building_type: String, origin: Vector2i, orientation := BuildingCatalog.ORIENTATION_HORIZONTAL) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not building_catalog.has(building_type):
		return tiles

	var footprint: Vector2i = building_catalog.get_footprint(building_type, orientation)
	for y in footprint.y:
		for x in footprint.x:
			tiles.append(origin + Vector2i(x, y))
	return tiles


func is_occupied(tile: Vector2i) -> bool:
	return get_building_at_tile(tile).size() > 0


func get_building_at_tile(tile: Vector2i) -> Dictionary:
	for building in buildings:
		var origin: Vector2i = building["origin"]
		var footprint: Vector2i = building["footprint"]
		if tile.x >= origin.x and tile.y >= origin.y and tile.x < origin.x + footprint.x and tile.y < origin.y + footprint.y:
			return building
	return {}


func get_building_by_id(building_id: int) -> Dictionary:
	for building in buildings:
		if int(building["id"]) == building_id:
			return building
	return {}


func get_building_definition(building: Dictionary) -> Dictionary:
	return building_catalog.get_definition(building.get("type", ""))


func get_nearest_building_of_type(building_type: String, tile: Vector2i) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for building in buildings:
		if building.get("type", "") != building_type:
			continue
		var approach_tile: Vector2i = building.get("vehicle_approach_tile", building.get("origin", Vector2i.ZERO))
		var distance: float = absf(float(approach_tile.x - tile.x)) + absf(float(approach_tile.y - tile.y))
		if distance < nearest_distance:
			nearest = building
			nearest_distance = distance
	return nearest


func deposit_raw_to_building(building_id: int, amount: int) -> bool:
	if amount <= 0:
		return false
	for index in buildings.size():
		if int(buildings[index]["id"]) != building_id:
			continue
		var building := buildings[index]
		building["stored_raw"] = int(building.get("stored_raw", 0)) + amount
		buildings[index] = building
		return true
	return false


func get_building_stored_metal(building_id: int) -> int:
	for building in buildings:
		if int(building["id"]) == building_id:
			return int(building.get("stored_metal", 0))
	return 0


func get_hq_stored_metal() -> int:
	var total := 0
	for building in buildings:
		if building.get("type", "") == BUILDING_PLANET_LANDER_MODULE and building.get("operational", false):
			total += int(building.get("stored_metal", 0))
	return total


func spend_hq_metal(amount: int) -> bool:
	if amount <= 0:
		return true
	if get_hq_stored_metal() < amount:
		return false

	var remaining := amount
	for index in buildings.size():
		if buildings[index].get("type", "") != BUILDING_PLANET_LANDER_MODULE or not buildings[index].get("operational", false):
			continue
		var building := buildings[index]
		var stored_metal := int(building.get("stored_metal", 0))
		var spent := mini(stored_metal, remaining)
		if spent <= 0:
			continue
		building["stored_metal"] = stored_metal - spent
		buildings[index] = building
		remaining -= spent
		if remaining <= 0:
			return true
	return false


func load_metal_from_building(building_id: int, amount: int) -> int:
	if amount <= 0:
		return 0
	for index in buildings.size():
		if int(buildings[index]["id"]) != building_id:
			continue
		var building := buildings[index]
		var loaded_amount: int = mini(amount, int(building.get("stored_metal", 0)))
		if loaded_amount <= 0:
			return 0
		building["stored_metal"] = int(building.get("stored_metal", 0)) - loaded_amount
		buildings[index] = building
		return loaded_amount
	return 0


func deliver_metal_to_building(building_id: int, amount: int) -> bool:
	if amount <= 0:
		return false
	for index in buildings.size():
		if int(buildings[index]["id"]) != building_id:
			continue
		var building := buildings[index]
		if not building.get("operational", true):
			return false
		building["stored_metal"] = int(building.get("stored_metal", 0)) + amount
		buildings[index] = building
		return true
	return false


func advance(delta: float) -> bool:
	var changed := false
	for index in buildings.size():
		var building := buildings[index]
		if building.get("type", "") != BUILDING_MILLING_PLANT:
			continue
		var stored_raw := int(building.get("stored_raw", 0))
		if stored_raw <= 0:
			continue

		var definition: Dictionary = get_building_definition(building)
		var output_rate := float(definition.get("metal_output_rate", 1.0))
		var progress := float(building.get("processing_progress", 0.0)) + output_rate * delta
		var process_amount := mini(floori(progress), stored_raw)
		if process_amount > 0:
			building["stored_raw"] = stored_raw - process_amount
			building["stored_metal"] = int(building.get("stored_metal", 0)) + process_amount
			resources["metal"] = int(resources.get("metal", 0)) + process_amount
			progress -= float(process_amount)
			changed = true
		building["processing_progress"] = progress
		buildings[index] = building
	return changed


func get_population_capacity() -> int:
	var capacity := 0
	for building in buildings:
		var definition: Dictionary = building_catalog.get_definition(building["type"])
		capacity += int(definition.get("population_capacity", 0))
	return capacity


func get_oxygen_capacity() -> int:
	var capacity := 0
	for building in buildings:
		var definition: Dictionary = building_catalog.get_definition(building["type"])
		capacity += int(definition.get("oxygen_capacity", 0))
	return capacity


func has_oxygen_shortage() -> bool:
	return get_oxygen_capacity() < population


func get_digger_capacity() -> int:
	var capacity := 0
	for building in buildings:
		var definition: Dictionary = building_catalog.get_definition(building["type"])
		capacity += int(definition.get("digger_capacity", 0))
	return capacity


func get_power_usage() -> int:
	var usage := 0
	for building in buildings:
		usage += int(building.get("power_usage", 0))
	return usage


func get_vehicle_build_options(building: Dictionary) -> Dictionary:
	return get_building_definition(building).get("vehicle_build_options", {})


func can_afford_vehicle(building: Dictionary, unit_type: String) -> bool:
	var options := get_vehicle_build_options(building)
	if not options.has(unit_type):
		return false
	return get_hq_stored_metal() >= int(options[unit_type].get("metal_cost", 0))


func spend_vehicle_cost(building: Dictionary, unit_type: String) -> bool:
	if not can_afford_vehicle(building, unit_type):
		return false
	var options := get_vehicle_build_options(building)
	return spend_hq_metal(int(options[unit_type].get("metal_cost", 0)))


func get_idle_population() -> int:
	return population - digger_operators - infantry


func change_digger_operators(delta: int) -> void:
	if delta > 0:
		var assignable: int = mini(delta, mini(get_idle_population(), get_digger_capacity() - digger_operators))
		digger_operators += maxi(assignable, 0)
	elif delta < 0:
		digger_operators = maxi(0, digger_operators + delta)


func change_infantry(delta: int) -> void:
	if delta > 0:
		var assignable: int = mini(delta, get_idle_population())
		infantry += maxi(assignable, 0)
	elif delta < 0:
		infantry = maxi(0, infantry + delta)


func _clamp_assignments() -> void:
	digger_operators = mini(digger_operators, get_digger_capacity())
	if digger_operators + infantry > population:
		infantry = maxi(0, population - digger_operators)


func get_building_count(building_type: String) -> int:
	var count := 0
	for building in buildings:
		if building["type"] == building_type:
			count += 1
	return count


func get_primary_objective() -> String:
	if get_hq_stored_metal() <= 0 and get_building_count(BUILDING_PLANET_LANDER_MODULE) > 0:
		return "Await the Planet Lander's touchdown."
	if has_oxygen_shortage():
		return "Build an Oxygen Extractor before reserve oxygen runs out."
	return "Oxygen support online. Expand the colony."


func get_summary_lines() -> Array[String]:
	return [
		"People: %d  Idle: %d  Diggers: %d/%d  Infantry: %d" % [
			population,
			get_idle_population(),
			digger_operators,
			get_digger_capacity(),
			infantry,
		],
		"Oxygen: %d/%d colonists supported  Reserve: %d days" % [
			get_oxygen_capacity(),
			population,
			oxygen_days_remaining,
		],
		"Buildings: O2 %d  LQ %d  Machine Park %d  Milling %d  Lander %d" % [
			get_building_count(BUILDING_OXYGEN_EXTRACTOR),
			get_building_count(BUILDING_LIVING_QUARTERS),
			get_building_count(BUILDING_MACHINE_PARK),
			get_building_count(BUILDING_MILLING_PLANT),
			get_building_count(BUILDING_PLANET_LANDER_MODULE),
		],
		"Resources: stone %d  ore %d  metal %d" % [
			resources["stone"],
			resources["ore"],
			resources["metal"],
		],
		"Power draw: %d" % get_power_usage(),
	]
