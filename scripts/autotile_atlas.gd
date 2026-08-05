extends RefCounted

const ROAD_MASK_TO_COLUMN := {
	0: 0,
	1: 1,
	2: 2,
	3: 3,
	4: 4,
	5: 5,
	6: 6,
	7: 7,
	8: 8,
	9: 9,
	10: 10,
	11: 11,
	12: 12,
	13: 13,
	14: 14,
	15: 15,
}

const MOUNTAIN_MASK_TO_COLUMN := {
	0: 0,
	1: 1,
	2: 2,
	3: 3,
	4: 4,
	5: 5,
	6: 6,
	7: 7,
	8: 8,
	9: 9,
	10: 10,
	11: 11,
	12: 12,
	13: 13,
	14: 14,
	15: 15,
}


static func road_column(mask: int) -> int:
	return int(ROAD_MASK_TO_COLUMN.get(mask, 0))


static func mountain_column(mask: int) -> int:
	return int(MOUNTAIN_MASK_TO_COLUMN.get(mask, 0))
