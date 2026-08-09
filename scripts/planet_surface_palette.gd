extends RefCounted

# One restrained mineral palette shared by flat ground, mountain massifs and props.
# Keeping these colors together prevents the terrain layers from reading as separate worlds.
const BEDROCK_LOW := Color8(55, 54, 50)
const BEDROCK_MID := Color8(94, 92, 86)
const BEDROCK_HIGH := Color8(154, 151, 139)
const WEATHERED_DUST := Color8(76, 73, 66)
const PALE_REGOLITH := Color8(112, 104, 91)
const ROCKY_SCREE := Color8(72, 70, 65)
const VOLCANIC_CRUST := Color8(45, 46, 43)
const COMPACT_BEDROCK := Color8(78, 78, 72)
const ERODED_STONE := Color8(108, 106, 96)
const PRESSURE_DUST := Color8(128, 120, 102)
const MINERAL_WARM := Color8(111, 83, 55)
const FUNGAL_CRUST_DARK := Color8(68, 68, 49)
const FUNGAL_CRUST_LIGHT := Color8(108, 102, 67)
const FUNGUS_BODY := Color8(126, 111, 78)
const CRYSTAL := Color8(137, 82, 153)
const VENT_MINERAL := Color8(61, 105, 103)
