extends RefCounted

const PlanetSurfacePalette := preload("res://scripts/planet_surface_palette.gd")

const TERRAIN_COLORS := {
	0: PlanetSurfacePalette.WEATHERED_DUST,
	1: PlanetSurfacePalette.FUNGAL_CRUST_DARK,
	2: PlanetSurfacePalette.CRYSTAL,
	3: PlanetSurfacePalette.MINERAL_WARM,
	4: PlanetSurfacePalette.VENT_MINERAL,
	5: PlanetSurfacePalette.BEDROCK_MID,
}

const TERRAIN_NAMES := {
	0: "Basalt plain",
	1: "Fungal crust",
	2: "Crystal growth",
	3: "Ore ridge",
	4: "Geothermal vent",
	5: "Mountain massif",
}


static func terrain_color(terrain_id: int) -> Color:
	return TERRAIN_COLORS.get(terrain_id, TERRAIN_COLORS[0])


static func terrain_name(terrain_id: int) -> String:
	return TERRAIN_NAMES.get(terrain_id, "Unknown terrain")
