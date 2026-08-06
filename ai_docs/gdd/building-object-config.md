# Building Object Config

Buildings use shared metadata for placement, rendering, navigation, and future logistics. The current MVP config lives in `scripts/building_catalog.gd`.

## Atlas

Building sprites are loaded from `assets/objects/buildings.png` through Godot's normal resource import pipeline. Keep the `.png` and its `.import` metadata committed so web exports include the atlas.

The normal MVP sprite contract is one atlas `source` rect per building. When a building is placed in `vertical` orientation, the renderer mirrors that same source horizontally instead of requiring a second authored sprite.

The current Oxygen Extractor footprint is `2x2`, so rotation is mostly visual. Other buildings, such as `living_quarters`, can use asymmetric footprints like `2x3`, where rotation changes both the footprint and the rendered sprite choice.

## Building Metadata

Each building definition should describe:

- `footprint`: footprint in map tiles before orientation rotation.
- `sprite.source`: atlas source rect for the building sprite. Prefer a single `Rect2i`; legacy per-orientation dictionaries are still accepted while the schema settles.
- `sprite.flip_horizontal_on_vertical`: whether `vertical` orientation should mirror the single source rect horizontally. Defaults to `true` for single-source sprites.
- `sprite.anchor`: pixel point inside the unflipped sprite that lands on the building's map origin. When the sprite is mirrored for `vertical`, the renderer mirrors this anchor across the source rect width.
- `sprite.screen_offset`: final screen-space pixel nudge after anchoring. Use this for art-specific visual adjustment, not for rotation logic.
- `model.mesh_path`: optional 3D mesh resource for buildings that have migrated from sprite rendering.
- `model.diffuse_texture`, `model.emissive_texture`, `model.normal_texture`, `model.roughness_texture`, and `model.metallic_texture`: optional texture resources for the 3D model.
- `model.scale`, `model.height_offset`, and `model.rotation_y`: visual placement controls for fitting the model to its tile footprint.
- `vehicle_entry`: tile inside the footprint that represents the vehicle/logistics entry.
- `vehicle_approach`: tile outside or at the edge of the building where roads and vehicle pathfinding should connect.

`vehicle_entry` and `vehicle_approach` are authored in the base horizontal orientation. For single-source sprites, `vertical` orientation is a horizontal screen mirror of the isometric art, so local footprint and entry coordinates transpose from `(x, y)` to `(y, x)`.

## 3D Building Models

HQ is the first building rendered from a 3D asset. The model lives in `assets/3D/buildings/hq/base.obj`, with texture files beside it. The unzipped files are the runtime source assets; `hq.zip` can remain as the original package/reference.

`IsoBuilding3DLayer` instantiates model-backed buildings from the same `ColonyState` building records used by the 2D layer. It centers the model on the building footprint, applies model config from `building_catalog.gd`, and does not own placement, selection, pathfinding blockers, vehicle entry, storage, health, or HUD state. Those remain in the gameplay data.

While rendering migration is mixed, model-backed buildings should be hidden in `IsoBuildingLayer` to avoid double-rendering the old sprite and the new 3D model.

## Placement Flow

When a building tool is active:

- `R` toggles the active building orientation.
- `F5` manually reloads `scripts/building_catalog.gd` during local development.
- Placement preview uses the configured sprite when one exists.
- Per-tile footprint feedback still comes from `IsoWorld`, so the overlay only renders validity.
- Placed buildings store `orientation`, `footprint`, `vehicle_entry_tile`, and `vehicle_approach_tile`.
- The MVP auto-connects a road at `vehicle_approach_tile` when that tile is passable.

## Building HUD

Buildings are selectable from their occupied footprint tiles when no placement tool is active. Selection opens a HUD panel with shared building state:

- `health` / `max_health`
- `power_usage`
- footprint and origin
- stored raw and stored metal placeholders

`machine_park` exposes MVP production actions for:

- `drilling_machine`: costs 50 metal
- `hauler`: costs 35 metal

Produced vehicles spawn at the building's `vehicle_approach_tile` when passable and use the shared unit selection/pathfinding pipeline.

## Runtime Reload

`IsoWorld` keeps a runtime `building_catalog` instance and shares it with `ColonyState`, `IsoBuildingLayer`, and `IsoOverlayLayer`. During local non-web runs it polls the modified time of `scripts/building_catalog.gd` every 0.5 seconds. When the file changes, the script is reloaded with `ResourceLoader.CACHE_MODE_REPLACE`, a fresh catalog instance is created, and all building consumers are reconnected.

This means changes to footprint, sprite source rects, anchors, screen offsets, capacity values, and vehicle entry/approach metadata should appear in the running sandbox after saving the file. Existing placed buildings keep their type, origin, and orientation, but their derived footprint and vehicle entry/approach tiles are recalculated from the new catalog.

Future production objects should move this data into a Godot `Resource` or external structured config once the schema stabilizes.
