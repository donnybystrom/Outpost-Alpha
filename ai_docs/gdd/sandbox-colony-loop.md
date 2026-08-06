# Sandbox Colony Loop

Sandbox mode is the first real play mode. It should start empty apart from procedurally generated terrain and let the player establish a functional outpost by placing structures on top of the terrain layer.

On planetfall, Sharon from mission control contacts the player. The first pressure is oxygen: reserve oxygen lasts only a few days, so the player must build an `oxygen_extractor` before expanding.

The player starts with one preplaced `hq` centered on the map and 225 metal stored in that HQ. Construction and vehicle production spend from HQ metal. Roads are free.

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
- `hq`: central colony delivery point for processed metal. Sandbox starts with one HQ already placed in the middle of the map.

Buildings occupy map footprints but do not rewrite terrain data. Placement currently requires map bounds, low/clear terrain, no roads, no existing building footprint overlap, and enough HQ metal for the building cost.

Building object metadata is documented in [Building Object Config](building-object-config.md). The MVP supports active building orientation with `R`, sprite source rects from `assets/objects/buildings.png`, per-building anchor offsets, and vehicle entry/approach tiles for future logistics.

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

## First Resource Chain

The first production chain is anchored by `milling_plant` and `machine_park`:

- Build a `milling_plant` near mountain terrain.
- Build a `machine_park`.
- Use the Machine Park HUD to build a `drilling_machine` for 50 metal or a `hauler` for 35 metal.
- Select a `drilling_machine` and right-click mountain terrain.
- The drilling machine travels to the nearest passable tile beside the mountain, mines for 5.5 seconds, returns raw material to the nearest `milling_plant`, spends 2 seconds dumping, then repeats the same mining route.
- The milling plant processes raw material into metal over time.
- Select a `hauler` and right-click a `milling_plant`.
- The hauler travels to the Milling Plant, waits there if no metal is available, spends 2 seconds loading 20 metal, switches to its full-cargo sprite, delivers that load to the nearest HQ, spends 2 seconds unloading, then repeats the route.

Vehicles currently use the shared unit selection and pathfinding pipeline. The global metal resource still updates when a Milling Plant processes raw material; spendable metal is the amount stored in HQ.

## Unit Sprites

Vehicle sprites are loaded from `assets/objects/units.png`.

The MVP atlas order is:

- placeholder tile
- empty hauler facing south-east
- empty hauler facing north-east
- full hauler facing south-east
- full hauler facing north-east
- drilling machine facing south-east
- drilling machine facing north-east

The renderer reuses those source sprites for all four isometric directions. South-west mirrors the south-east sprite horizontally, and north-west mirrors the north-east sprite horizontally. Unit facing is derived from the current tile-space movement delta.
