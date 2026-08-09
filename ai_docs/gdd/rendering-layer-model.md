# Rendering and Simulation Layer Model

Outpost Alpha uses explicit map layers. The purpose is to keep static map drawing, buildable objects, environmental blockers, and active units separated in both data and rendering.

## Layer 1: Ground

Ground is the static base layer. It is always at the bottom of z-ordering and must never render in front of buildings, environment objects, or units.

Ground can contain static sublayers such as:

- Terrain: basalt, scrub, forest floor, mountain massifs, ore ridges, crystal growth, vents, water or other future base terrain.
- Roads: player-built ground infrastructure with autotile variants.

Ground does not run per-frame gameplay logic. If a ground tile changes, it is because game code made an explicit request. Neighbor-dependent ground features, such as roads and mountain massifs, recalculate only the changed tile and the relevant nearby tiles.

The current renderer migration renders base terrain through a 3D ground layer made from flat tile planes and an orthographic `Camera3D` synced to the existing isometric camera. Terrain colors come from `tile_visual_catalog.gd`. Forest terrain feeds a 3D forest layer that extracts individual tree variants from a collection OBJ and places seeded tree instances over forest tiles. Mountain terrain also feeds a procedural 3D massif layer that creates seeded heightfield meshes above mountain tiles. Roads render through a separate 3D road layer made from generated flat meshes and multimesh buckets keyed by the existing autotile masks. Planet Lander, Oxygen Extractor, Living Quarters, Machine Park, and Milling Plant are rendered through 3D OBJ assets while legacy-only buildings, workers, and some interaction overlays still use the existing 2D layers during the migration. The Planet Lander additionally uses a transient 3D landing layer until it hands rendering to the regular building layer at touchdown.

The MVP 3D scene uses an angled `DirectionalLight3D` as a sun plus low ambient world lighting. Terrain, road, mountain, forest, and model-backed building materials are lit rather than unshaded. Procedural road meshes use upward normals, procedural mountains generate face normals, and extracted tree OBJ meshes retain OBJ normals when present.

The sun uses one realtime directional shadow map with four PSSM splits, a bounded 48-world-unit range, hard filtering, and 90% opacity. The project caps the directional shadow texture at 2048 px for both desktop and mobile/Compatibility exports. Model-backed buildings, vehicles, animated Space Marines, the descending Planet Lander, and optionally the procedural mountain mesh cast shadows dynamically onto the terrain. Terrain, roads, building-placement previews, jet flames, and forest multimeshes are receiver-only or excluded from the shadow pass; in particular, excluding thousands of tree instances keeps the Web cost predictable. Runtime sun orientation, optional debug orbit, shadow blur, PSSM split count, range, opacity, bias, fade, split blending, and mountain shadow casting are configured under `[lighting]` in `config/runtime.cfg`. The orbit is disabled by default because continuously rotating a hard-shadow projection exposes shadow-map texel shimmer. Mountain casting is an experimental quality option because the current large combined mountain mesh can be submitted once per intersecting PSSM split; chunking that mesh spatially is the likely optimization if profiling shows excessive Web cost. A later low-end tier can disable realtime shadows and use blob/contact decals for units if profiling on target hardware requires it.

The 3D camera supports experimental view yaw rotation with Alt + middle mouse drag. The projection remains orthographic and the camera keeps the same tilt and zoom size while orbiting around world-up. During the renderer migration this only rotates the 3D scene layers; 2D overlays, unit sprites, and legacy object sprites still use the fixed isometric projection and should be migrated or explicitly projected through `Camera3D` before view rotation becomes a default gameplay feature.

## Layer 2: Buildings

Buildings are placed above ground and have footprints, ownership, state, production, storage, crew requirements, and other gameplay logic.

Buildings are z-ordered against other buildings by their map position and footprint. This should be local where possible: changing one building should not require comparing or rebuilding the entire scene graph.

Buildings can affect navigation, line of sight, production, resources, jobs, and unit behavior, but they do not rewrite ground data unless a specific game rule explicitly requests it.

Rendered building sprites come from an object atlas when available. Model-backed buildings come from optional `model` metadata in the same catalog. Placement and rendering share the same building catalog metadata: footprint, orientation, sprite/model source, anchor or transform offsets, and vehicle entry/approach tiles. If a building has `model` metadata, the 2D building layer skips its sprite and the 3D building layer owns its final rendering. The 3D placement preview layer also uses that model metadata to show a translucent model ghost and ground-plane footprint validation outlines for active building placement.

## Layer 3: Environment Objects

Environment objects include trees, large rocks, wreckage, alien growths, cliffs, and similar objects that are not player buildings but still occupy space.

They can have collision, blockers, cover values, harvestable resources, damage state, or z-ordering. They must not live in the building layer because they follow different ownership, placement, and lifecycle rules.

The MVP forest renderer treats terrain id `1` as the tree placement mask. The terrain tile remains the gameplay blocker, while rendered tree instances are visual environment objects generated deterministically from the map seed. Sandbox Admin exposes visual tuning for target tree density and global tree size; those controls rebuild only the forest render layer and do not mutate map terrain data.

## Layer 4: Units

Units are the most dynamic simulation layer. They move, pathfind, shoot, acquire targets, execute jobs, carry resources, and interact with buildings and environment objects.

Units can read ground passability, road bonuses, building entrances, and environment blockers, but their movement must not invalidate static ground rendering. Unit rendering should be dynamic and independently sorted against nearby occluders.

Current MVP workers use a shared pathfinding grid built from `MapData` and `ColonyState`. Forest and mountain terrain are impassable. Placed building footprints are impassable. Roads reduce movement cost to 70% of normal ground, which means workers move 30% faster on roads and the pathfinder proportionally prefers routes that use them.

When roads, buildings, or dev terrain edits change navigation data, all worker paths are recalculated. This is acceptable for the current small worker count. Later optimization should invalidate only units whose current or planned paths overlap the changed navigation region.

Unit simulation remains 2D grid data even when visual rendering migrates to 3D. The MVP 3D unit layer reads `UnitState` and renders model-backed haulers and drilling machines from their current interpolated map position, facing, and cargo state. Empty haulers use `assets/3D/units/hauler_empty/base.obj`; loaded haulers use `assets/3D/units/hauler_filled/base.obj`. Empty drilling machines use `assets/3D/units/drilling_machine_empty/base.obj`; loaded drilling machines use `assets/3D/units/drilling_machine_full/base.obj`. Workers, selection helpers, and path overlays remain in the existing 2D unit/overlay layers until they are migrated.

## Non-Gameplay Overlay Layers

Debug and interaction visuals are separate from gameplay layers:

- Grid.
- Hover marker.
- Selection marker.
- Placement preview.
- Admin/debug panels.

These overlays can redraw frequently without mutating map data.
