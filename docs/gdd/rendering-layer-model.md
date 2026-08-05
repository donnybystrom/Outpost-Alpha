# Rendering and Simulation Layer Model

Outpost Alpha uses explicit map layers. The purpose is to keep static map drawing, buildable objects, environmental blockers, and active units separated in both data and rendering.

## Layer 1: Ground

Ground is the static base layer. It is always at the bottom of z-ordering and must never render in front of buildings, environment objects, or units.

Ground can contain static sublayers such as:

- Terrain: basalt, scrub, forest floor, mountain massifs, ore ridges, crystal growth, vents, water or other future base terrain.
- Roads: player-built ground infrastructure with autotile variants.

Ground does not run per-frame gameplay logic. If a ground tile changes, it is because game code made an explicit request. Neighbor-dependent ground features, such as roads and mountain massifs, recalculate only the changed tile and the relevant nearby tiles.

## Layer 2: Buildings

Buildings are placed above ground and have footprints, ownership, state, production, storage, crew requirements, and other gameplay logic.

Buildings are z-ordered against other buildings by their map position and footprint. This should be local where possible: changing one building should not require comparing or rebuilding the entire scene graph.

Buildings can affect navigation, line of sight, production, resources, jobs, and unit behavior, but they do not rewrite ground data unless a specific game rule explicitly requests it.

## Layer 3: Environment Objects

Environment objects include trees, large rocks, wreckage, alien growths, cliffs, and similar objects that are not player buildings but still occupy space.

They can have collision, blockers, cover values, harvestable resources, damage state, or z-ordering. They must not live in the building layer because they follow different ownership, placement, and lifecycle rules.

## Layer 4: Units

Units are the most dynamic simulation layer. They move, pathfind, shoot, acquire targets, execute jobs, carry resources, and interact with buildings and environment objects.

Units can read ground passability, road bonuses, building entrances, and environment blockers, but their movement must not invalidate static ground rendering. Unit rendering should be dynamic and independently sorted against nearby occluders.

Current MVP workers use a shared pathfinding grid built from `MapData` and `ColonyState`. Forest and mountain terrain are impassable. Placed building footprints are impassable. Roads reduce movement cost to 70% of normal ground, which means workers move 30% faster on roads and the pathfinder proportionally prefers routes that use them.

When roads, buildings, or dev terrain edits change navigation data, all worker paths are recalculated. This is acceptable for the current small worker count. Later optimization should invalidate only units whose current or planned paths overlap the changed navigation region.

## Non-Gameplay Overlay Layers

Debug and interaction visuals are separate from gameplay layers:

- Grid.
- Hover marker.
- Selection marker.
- Placement preview.
- Admin/debug panels.

These overlays can redraw frequently without mutating map data.
