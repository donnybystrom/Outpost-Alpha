# Input Model

Outpost Alpha separates UI intent, viewport input, map projection, and game commands.

## Current Flow

1. UI buttons select placement intent, such as `Road`, `living_quarters`, or another buildable object.
2. `MapInputController` receives unhandled viewport input that was not consumed by UI controls.
3. The controller converts viewport coordinates to map coordinates. With the active 3D world camera it projects a ray from `Camera3D` through the pointer to the ground plane; otherwise it falls back to Godot's 2D canvas transform.
4. `IsoWorld.world_to_map()` converts world coordinates to map tile coordinates.
5. `IsoWorld` applies game commands such as hover, select, road paint, and line preview.
6. `MapData` stores terrain and road state.
7. Static render layers draw cached terrain, roads, and grid.
8. `IsoOverlayLayer` redraws hover, placement preview, road preview, and line preview without invalidating terrain, roads, or grid.

## Coordinate Spaces

| Space | Example Owner | Purpose |
| --- | --- | --- |
| Viewport | `InputEventMouseButton.position` | Raw pointer/touch position inside the game window. |
| World | `Camera2D` canvas transform | Camera-aware 2D scene coordinates after pan and zoom for legacy 2D overlays. |
| Ground plane | `Camera3D` ray against `y = 0` | Camera-aware 3D map position after pan, zoom, and view rotation. |
| Map tile | `Vector2i(x, y)` | Gameplay address used by terrain, roads, selection, and commands. |

The 3D viewport-to-map conversion is the default while the orthographic 3D camera is active:

```gdscript
ray_origin = camera_3d.project_ray_origin(viewport_position)
ray_direction = camera_3d.project_ray_normal(viewport_position)
point = ray_origin + ray_direction * (-ray_origin.y / ray_direction.y)
tile = Vector2i(roundi(point.x), roundi(point.z))
```

The legacy 2D viewport-to-world conversion is:

```gdscript
world.get_global_transform_with_canvas().affine_inverse() * viewport_position
```

The world-to-isometric-map conversion is:

```gdscript
map_x = (world_y / tile_height) + (world_x / tile_width)
map_y = (world_y / tile_height) - (world_x / tile_width)
tile = Vector2i(floori(map_x + 0.5), floori(map_y + 0.5))
```

This keeps camera zoom, window resize, and viewport expansion outside gameplay math. Single-touch input feeds the same viewport command path as the mouse, while two-touch gestures are reserved for pinch zoom. A touch press is deferred until it becomes a tap or drag so the first finger of a pinch cannot accidentally select or paint. Mouse wheel, trackpad magnification, mobile pinch, and gamepad trigger input all feed the same camera zoom command.

Camera actions are registered through `CameraControlMapping`. Keyboard and gamepad bindings resolve to named pan and zoom actions; pointer and gesture events adapt into the same public camera commands. This keeps device-specific events out of camera movement math and leaves room for remapping UI or a virtual controller cursor later.

Three concurrent mobile touches lock the active touch sequence to camera rotation and tilt, using the moving touch centroid as the drag delta. The lock remains until every finger is released so lifting one finger cannot turn a rotation into an accidental pinch. macOS trackpads expose aggregated pan gestures without a finger count, so `Alt` + trackpad pan is the desktop equivalent and shares the existing `Alt` + middle-mouse rotation path.

Selection rectangles are screen-space interactions. While the 3D camera is active, drag-selection stores the raw viewport rectangle and tests units against their current `Camera3D.unproject_position()` screen positions. That keeps Command & Conquer-style selection stable after camera rotation instead of treating the rectangle as a rotated ground-plane area.

Middle-mouse pan is also ground-plane aware in the 3D view. The camera compares the map position under the previous pointer location with the map position under the current pointer location, then moves the camera center by that map delta. This keeps “grab and drag the world” behavior consistent regardless of yaw.

## Placement Cancellation

Roads, buildings, walls, and future placeable objects use the same active placement pipeline even when their footprints and commit behavior differ. Right-click currently cancels the active placement tool and releases the matching toolbar button. Future controller and touch cancellation should call the same `IsoWorld.cancel_active_placement()` command.

## Unit Selection And Commands

When no placement tool is active, primary mouse drag starts a unit selection rectangle. Workers inside the rectangle become the active command group. Primary click selects a single unit if one is under the cursor, clears selection when clicking empty map space, or will later select/interact with buildings. Secondary click with selected workers issues a move command to the clicked map tile.

Group move commands use formation slots around the secondary-clicked tile. Each selected worker gets a nearby passable destination where possible, so multiple workers do not collapse into the exact same target point. Workers also carry small render offsets so overlapping paths remain visually readable while movement/collision is still tile-based.

## Placement Feedback

Active placement tools ask `IsoWorld` for per-tile feedback before rendering previews. The world validates each target tile against map bounds, terrain, roads, and colony footprints, then sends only `{ tile, valid }` feedback to `IsoOverlayLayer`. The overlay renders valid tiles green and invalid tiles red without owning gameplay rules.

## Redraw Invariants

- Hover changes must only request redraw from `IsoOverlayLayer`.
- Terrain redraws only on map regeneration or terrain edits.
- Road redraws only on map regeneration or road edits.
- A single road edit must only recompute the placed tile and its cardinal neighbors, since those are the only road autotile masks that can change.
- Road line placement and fast road dragging must produce cardinally connected tile paths. Diagonal tile jumps create disconnected road data and therefore cannot produce correct T-junction or corner masks.
- Grid redraws only on map regeneration; visibility toggles should not rebuild terrain or roads.
- Camera pan and zoom must only change `Camera2D` transform.
- HUD diagnostics live in a separate `CanvasLayer` and must not be a child of the map rendering tree.
