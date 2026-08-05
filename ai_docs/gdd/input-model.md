# Input Model

Outpost Alpha separates UI intent, viewport input, map projection, and game commands.

## Current Flow

1. UI buttons select placement intent, such as `Road`, `living_quarters`, or another buildable object.
2. `MapInputController` receives unhandled viewport input that was not consumed by UI controls.
3. The controller converts viewport coordinates to world coordinates with Godot's canvas transform.
4. `IsoWorld.world_to_map()` converts world coordinates to map tile coordinates.
5. `IsoWorld` applies game commands such as hover, select, road paint, and line preview.
6. `MapData` stores terrain and road state.
7. Static render layers draw cached terrain, roads, and grid.
8. `IsoOverlayLayer` redraws hover, placement preview, road preview, and line preview without invalidating terrain, roads, or grid.

## Coordinate Spaces

| Space | Example Owner | Purpose |
| --- | --- | --- |
| Viewport | `InputEventMouseButton.position` | Raw pointer/touch position inside the game window. |
| World | `Camera2D` canvas transform | Camera-aware 2D scene coordinates after pan and zoom. |
| Map tile | `Vector2i(x, y)` | Gameplay address used by terrain, roads, selection, and commands. |

The viewport-to-world conversion is:

```gdscript
world.get_global_transform_with_canvas().affine_inverse() * viewport_position
```

The world-to-isometric-map conversion is:

```gdscript
map_x = (world_y / tile_height) + (world_x / tile_width)
map_y = (world_y / tile_height) - (world_x / tile_width)
tile = Vector2i(floori(map_x + 0.5), floori(map_y + 0.5))
```

This keeps camera zoom, window resize, and viewport expansion outside gameplay math. Future mobile and controller input should feed the same controller/command path, either by passing viewport positions from touch or by moving a virtual cursor/focused tile and calling the same world command methods.

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
