extends RefCounted

const TERRAIN_COLORS := {
	0: Color8(47, 56, 50),
	1: Color8(44, 74, 31),
	2: Color8(99, 42, 126),
	3: Color8(132, 76, 31),
	4: Color8(28, 127, 139),
	5: Color8(77, 76, 71),
}

const TERRAIN_NAMES := {
	0: "Basalt plain",
	1: "Alien scrub",
	2: "Crystal growth",
	3: "Ore ridge",
	4: "Geothermal vent",
	5: "Mountain massif",
}


static func terrain_color(terrain_id: int) -> Color:
	return TERRAIN_COLORS.get(terrain_id, TERRAIN_COLORS[0])


static func terrain_name(terrain_id: int) -> String:
	return TERRAIN_NAMES.get(terrain_id, "Unknown terrain")
