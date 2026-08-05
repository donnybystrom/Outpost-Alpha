extends RefCounted

const BUILDING_LIVING_QUARTERS := "living_quarters"
const BUILDING_OXYGEN_EXTRACTOR := "oxygen_extractor"
const BUILDING_MACHINE_PARK := "machine_park"
const BUILDING_MILLING_PLANT := "milling_plant"

const BUILDING_TYPES := {
	BUILDING_LIVING_QUARTERS: {
		"name": "Living Quarters",
		"label": "LQ",
		"footprint": Vector2i(3, 2),
		"population_capacity": 8,
		"oxygen_capacity": 0,
		"digger_capacity": 0,
	},
	BUILDING_OXYGEN_EXTRACTOR: {
		"name": "Oxygen Extractor",
		"label": "O2",
		"footprint": Vector2i(2, 2),
		"population_capacity": 0,
		"oxygen_capacity": 5,
		"digger_capacity": 0,
	},
	BUILDING_MACHINE_PARK: {
		"name": "Machine Park",
		"label": "MP",
		"footprint": Vector2i(3, 2),
		"population_capacity": 0,
		"oxygen_capacity": 0,
		"digger_capacity": 2,
	},
	BUILDING_MILLING_PLANT: {
		"name": "Milling Plant",
		"label": "MILL",
		"footprint": Vector2i(4, 3),
		"population_capacity": 0,
		"oxygen_capacity": 0,
		"digger_capacity": 0,
	},
}

var buildings: Array[Dictionary] = []
var population: int = 5
var oxygen_days_remaining: int = 3
var digger_operators: int = 0
var infantry: int = 0
var resources := {
	"stone": 0,
	"ore": 0,
	"metal": 0,
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
		"metal": 0,
	}
	_next_building_id = 1


func can_place_building(building_type: String, origin: Vector2i, map_data: RefCounted) -> bool:
	if not BUILDING_TYPES.has(building_type) or map_data == null:
		return false

	for tile in footprint_tiles(building_type, origin):
		if not map_data.is_inside(tile):
			return false
		if map_data.has_road(tile):
			return false
		if map_data.get_terrain(tile) > 1:
			return false
		if is_occupied(tile):
			return false

	return true


func place_building(building_type: String, origin: Vector2i, map_data: RefCounted) -> bool:
	if not can_place_building(building_type, origin, map_data):
		return false

	var definition: Dictionary = BUILDING_TYPES[building_type]
	buildings.append({
		"id": _next_building_id,
		"type": building_type,
		"origin": origin,
		"footprint": definition["footprint"],
	})
	_next_building_id += 1
	_clamp_assignments()
	return true


func footprint_tiles(building_type: String, origin: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not BUILDING_TYPES.has(building_type):
		return tiles

	var footprint: Vector2i = BUILDING_TYPES[building_type]["footprint"]
	for y in footprint.y:
		for x in footprint.x:
			tiles.append(origin + Vector2i(x, y))
	return tiles


func is_occupied(tile: Vector2i) -> bool:
	for building in buildings:
		var origin: Vector2i = building["origin"]
		var footprint: Vector2i = building["footprint"]
		if tile.x >= origin.x and tile.y >= origin.y and tile.x < origin.x + footprint.x and tile.y < origin.y + footprint.y:
			return true
	return false


func get_population_capacity() -> int:
	var capacity := 0
	for building in buildings:
		var definition: Dictionary = BUILDING_TYPES[building["type"]]
		capacity += int(definition.get("population_capacity", 0))
	return capacity


func get_oxygen_capacity() -> int:
	var capacity := 0
	for building in buildings:
		var definition: Dictionary = BUILDING_TYPES[building["type"]]
		capacity += int(definition.get("oxygen_capacity", 0))
	return capacity


func has_oxygen_shortage() -> bool:
	return get_oxygen_capacity() < population


func get_digger_capacity() -> int:
	var capacity := 0
	for building in buildings:
		var definition: Dictionary = BUILDING_TYPES[building["type"]]
		capacity += int(definition.get("digger_capacity", 0))
	return capacity


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
		"Buildings: O2 %d  LQ %d  Machine Park %d  Milling %d" % [
			get_building_count(BUILDING_OXYGEN_EXTRACTOR),
			get_building_count(BUILDING_LIVING_QUARTERS),
			get_building_count(BUILDING_MACHINE_PARK),
			get_building_count(BUILDING_MILLING_PLANT),
		],
		"Resources: stone %d  ore %d  metal %d" % [
			resources["stone"],
			resources["ore"],
			resources["metal"],
		],
	]
