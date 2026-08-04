# Input Model

Outpost Alpha separates UI intent, viewport input, map projection, and game commands.

## Current Flow

1. UI buttons select intent, such as `Road`.
2. `MapInputController` receives unhandled viewport input that was not consumed by UI controls.
3. The controller converts viewport coordinates to world coordinates with Godot's canvas transform.
4. `IsoWorld.world_to_map()` converts world coordinates to map tile coordinates.
5. `IsoWorld` applies game commands such as hover, select, road paint, and line preview.
6. `MapData` stores terrain and road state.
7. Static render layers draw cached terrain, roads, and grid.
8. `IsoOverlayLayer` redraws hover, selection, road preview, and line preview without invalidating terrain, roads, or grid.

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

## Redraw Invariants

- Hover changes must only request redraw from `IsoOverlayLayer`.
- Terrain redraws only on map regeneration or terrain edits.
- Road redraws only on map regeneration or road edits.
- A single road edit must only recompute the placed tile and its cardinal neighbors, since those are the only road autotile masks that can change.
- Grid redraws only on map regeneration; visibility toggles should not rebuild terrain or roads.
- Camera pan and zoom must only change `Camera2D` transform.
- HUD diagnostics live in a separate `CanvasLayer` and must not be a child of the map rendering tree.
