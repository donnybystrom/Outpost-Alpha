# Sandbox Colony Loop

Sandbox mode is the first real play mode. It should start empty apart from procedurally generated terrain and let the player establish a functional outpost by placing structures on top of the terrain layer.

On planetfall, Sharon from mission control contacts the player. The first pressure is oxygen: reserve oxygen lasts only a few days, so the player must build an `oxygen_extractor` before expanding.

## Layer Model

The map is split into data layers. The authoritative layer model is documented in [Rendering and Simulation Layer Model](rendering-layer-model.md).

- Ground: generated base terrain and roads. This is static unless explicitly changed by game code.
- Buildings: colony objects placed above terrain with footprints and gameplay effects.
- Environment objects: trees, large rocks, wreckage, alien growths, and other blockers/occluders.
- Units: future dynamic entities rendered above the built environment and sorted against nearby occluders.
- Overlay: hover, selection, placement preview, and debug/admin affordances.

Moving units or changing roles must not invalidate terrain. A layer is redrawn only when its own data changes.

## Current Buildings

- `oxygen_extractor`: first objective building. One module supports up to 5 colonists.
- `living_quarters`: houses people. MVP starts with 5 people; quarters establish the housing concept.
- `machine_park`: provides digger vehicle/operator slots. Current MVP grants 2 digger operator slots.
- `milling_plant`: receives future digger yields and processes them into usable resources.

Buildings occupy map footprints but do not rewrite terrain data. Placement currently requires map bounds, low/clear terrain, no roads, and no existing building footprint overlap.

## Current People Roles

People are an abstract colony resource for now. Reassignment is immediate:

- Idle: unassigned people.
- Digger operators: crew future drilling/digging vehicles from the machine park.
- Infantry: standalone field personnel for future defense and exploration.

The MVP does not simulate walking between roles yet. Reassignment changes state directly and updates the HUD.

## Current Workers

Sandbox currently spawns one visible worker unit per starting colonist. Workers are the first concrete unit type and can be commanded by clicking the map when no construction tool is active.

Workers use cardinal tile pathfinding. Forest and mountain tiles block movement, and building footprints block movement. Roads have 70% movement cost, so workers move 30% faster on them and choose road routes when the travel cost is better.

Worker control follows the initial RTS-style command model:

- Drag-select workers when no build tool is active.
- Left-click a worker to select it.
- Left-click empty map space to clear the current worker selection.
- Right-click a destination to move the selected workers.

Group movement assigns passable formation slots around the clicked tile, similar to the classic RTS approach where a group fans out around its destination instead of stacking in one point. The current MVP also applies a tiny render offset per worker so overlapping paths remain readable while true local avoidance is still future work.
