extends RefCounted

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8
const NORTH_EAST := 16
const SOUTH_EAST := 32
const SOUTH_WEST := 64
const NORTH_WEST := 128
const CARDINAL_MASK := NORTH | EAST | SOUTH | WEST

# These are map-space cardinal neighbors. With the current isometric projection
# they appear on screen as NE, SE, SW, and NW respectively.
const CARDINAL_DIRECTIONS := {
	NORTH: Vector2i(0, -1),
	EAST: Vector2i(1, 0),
	SOUTH: Vector2i(0, 1),
	WEST: Vector2i(-1, 0),
}

const ROAD_DIRECTIONS := {
	NORTH: Vector2i(0, -1),
	NORTH_EAST: Vector2i(1, -1),
	EAST: Vector2i(1, 0),
	SOUTH_EAST: Vector2i(1, 1),
	SOUTH: Vector2i(0, 1),
	SOUTH_WEST: Vector2i(-1, 1),
	WEST: Vector2i(-1, 0),
	NORTH_WEST: Vector2i(-1, -1),
}


static func road_mask(map_data: RefCounted, tile: Vector2i) -> int:
	var mask := 0
	for bit in ROAD_DIRECTIONS:
		if roads_connect(map_data, tile, ROAD_DIRECTIONS[bit]):
			mask |= bit
	return mask


static func roads_connect(map_data: RefCounted, tile: Vector2i, direction: Vector2i) -> bool:
	if map_data == null or not map_data.has_road(tile + direction):
		return false
	if direction.x == 0 or direction.y == 0:
		return true
	# A diagonal is an intentional connection only when it is not merely the
	# opposite corners of an existing cardinal bend.
	return (
		not map_data.has_road(tile + Vector2i(direction.x, 0))
		and not map_data.has_road(tile + Vector2i(0, direction.y))
	)


static func same_terrain_mask(map_data: RefCounted, tile: Vector2i) -> int:
	var terrain_id: int = map_data.get_terrain(tile)
	var mask := 0
	for bit in CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = tile + CARDINAL_DIRECTIONS[bit]
		if map_data.is_inside(neighbor) and map_data.get_terrain(neighbor) == terrain_id:
			mask |= bit
	return mask
