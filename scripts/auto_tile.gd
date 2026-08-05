extends RefCounted

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8

# These are map-space cardinal neighbors. With the current isometric projection
# they appear on screen as NE, SE, SW, and NW respectively.
const CARDINAL_DIRECTIONS := {
	NORTH: Vector2i(0, -1),
	EAST: Vector2i(1, 0),
	SOUTH: Vector2i(0, 1),
	WEST: Vector2i(-1, 0),
}


static func road_mask(map_data: RefCounted, tile: Vector2i) -> int:
	var mask := 0
	for bit in CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = tile + CARDINAL_DIRECTIONS[bit]
		if map_data.has_road(neighbor):
			mask |= bit
	return mask


static func same_terrain_mask(map_data: RefCounted, tile: Vector2i) -> int:
	var terrain_id: int = map_data.get_terrain(tile)
	var mask := 0
	for bit in CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = tile + CARDINAL_DIRECTIONS[bit]
		if map_data.is_inside(neighbor) and map_data.get_terrain(neighbor) == terrain_id:
			mask |= bit
	return mask
