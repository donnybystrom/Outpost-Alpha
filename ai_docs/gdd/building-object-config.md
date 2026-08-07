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

The Planet Lander uses two model sets under `assets/3D/buildings/`: `planet_lander_module_flying` during its opening descent and `planet_lander_module_landed` after touchdown. `PlanetLanderLandingSequence3D` owns the transient flying model, six procedural particle jets, spatial engine synthesis, pneumatic touchdown sound, and touchdown handoff. The engine generator blends low jet harmonics, turbine resonance, and filtered combustion noise with intensity tied to descent progress. The landed mesh, textures, and materials are warmed during the sandbox loading screen; `IsoBuilding3DLayer` renders them from the normal building catalog only after the same colony building record becomes operational. The flight-only mesh, jet geometry, particles, and light are released at touchdown.

Other model-backed buildings use a hybrid warmup policy rather than loading the entire catalog at startup. Hovering or focusing a construction button requests its mesh and texture resources through Godot's threaded resource loader. If the player clicks first, build-tool activation waits for that same request and then fills the runtime and preview material caches before placement begins.

### 3D texture import policy

All texture maps added for 3D buildings, units, and comparable environment models must be imported as 3D assets rather than with Godot's 2D-oriented defaults:

- Use `VRAM Compressed` (`compress/mode=2`) for diffuse/albedo, emissive, normal, roughness, metallic, and packed PBR maps.
- Generate mipmaps (`mipmaps/generate=true`).
- Explicitly enable normal-map import (`compress/normal_map=1`) for files named `texture_normal.*`; do not enable it for other map types.
- Commit the source image and its generated `.import` metadata. Do not commit `.godot/imported/`.
- Keep source PNGs for normal and data maps. Diffuse maps may use a high-quality JPEG/WebP source when alpha is unnecessary, but source-file compression does not replace VRAM compression.
- Choose the lowest source resolution that survives the intended camera distance. Start at 1024x1024 for prominent buildings and 512x512-1024x1024 for smaller buildings and units, then verify visually. Resolution changes are an art decision and are not performed automatically by the importer.

The project importer explicitly generates both S3TC/BPTC desktop and ETC2/ASTC mobile variants, and the Web export includes both sets so GitHub Pages builds can serve laptop and mobile browsers. Apply this policy whenever a new model folder is added under `assets/3D/`; otherwise its first import will fall back to high-memory lossless textures without mipmaps.

`IsoBuilding3DLayer` instantiates model-backed buildings from the same `ColonyState` building records used by the 2D layer. It centers the model on the building footprint, applies model config from `building_catalog.gd`, and does not own placement, selection, pathfinding blockers, vehicle entry, storage, health, or HUD state. Those remain in the gameplay data.

While rendering migration is mixed, model-backed buildings should be hidden in `IsoBuildingLayer` to avoid double-rendering an old sprite and a 3D model. Buildings with `landing_state != "landed"` are also skipped by `IsoBuilding3DLayer` so a transition layer can own their temporary visual state.

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
