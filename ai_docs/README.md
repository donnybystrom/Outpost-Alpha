# Outpost Alpha

Minimal Godot 4.7 / GDScript prototype for an isometric 2D RTS foundation.

## Current slice

- 32x16 pixel isometric tile projection.
- Procedural 96x96 alien sandbox start map.
- Draw-order based on tile rows.
- Pan and zoom camera.
- Resizable viewport using `canvas_items` + `expand`.
- RTS-style camera behavior: resize reveals more or less world without resetting zoom.
- Main menu with `Sandbox`, `Dev Mode`, and `Quit to OS`.
- Hidden in-game admin panel toggled with ` / §.
- FPS, frame-time, draw-call, input-conversion, and per-render-layer diagnostics in the debug HUD.
- Bottom construction menu with road painting.
- Hover and click tile selection.
- Procedural placeholder roads, structures, and vehicles in Dev Mode only.
- Procedural ore, crystal growth, geothermal vents, and alien forest.

## Controls

- `WASD` or arrow keys: pan camera.
- Middle mouse drag: pan camera.
- Mouse wheel: zoom.
- Left click: select tile.
- `G`: toggle grid overlay.
- ` / §: toggle the in-game admin panel.
- Map hover: always shows a quiet 10% opacity orange isometric outline.
- Construction menu `Road`: paint roads. Hovering a tile in road mode shows a translucent road preview and green isometric target outline; hold `Shift` while dragging to preview and commit a straight road line on mouse release.

## Notes

The engine slice is intentionally sprite-size driven even though the current art is drawn procedurally. The tile projection uses `TILE_SIZE = Vector2i(32, 16)` in `scripts/iso_world.gd`, so generated or imported sprites can be aligned to that baseline later.

The project uses `window/stretch/mode="canvas_items"` and `window/stretch/aspect="expand"` so wide or tall windows increase the visible play area instead of adding black bars or non-uniform distortion. Runtime code keeps camera zoom stable on resize and only relayouts HUD controls.

## Tile Rendering

Ground rendering is data-driven:

1. `ProceduralMapGenerator` creates `MapData`.
2. `IsoTileRenderer` reads terrain data and bakes the terrain layer into one cached map texture.
3. `IsoRoadRenderer` bakes roads into one transparent road texture. A road edit only updates the placed tile plus its four cardinal neighbors because those are the only autotile masks affected.
4. `IsoGridLayer` bakes the static grid into one transparent grid texture so hover changes do not redraw the full grid.
5. `IsoOverlayLayer` draws hover, road preview, and line preview as O(1) dynamic overlay work.
6. `IsoWorld` owns map commands and temporary Dev Mode demo objects above the static layers.

The debug HUD abbreviates render diagnostics per layer:

```text
T d:1 r:2 c:9216 us:4200 set_map_data
```

`d` is total `_draw()` calls, `r` is total redraw requests, `c` is cells processed by the last draw, and `us` is microseconds spent inside the last `_draw()`. `bake` is the most recent cached-texture rebuild or dirty-update time. During normal hover, `terrain`, `roads`, and `grid` should not increase their redraw counts; only `overlay` should. During a single road placement, `roads` should process at most five cells: the placed tile plus north/east/south/west neighbors.

The sandbox start map is generated with a random seed when `Sandbox` is selected. It creates a 96x96 map with a player clearing, a buildable radius between 25 and 40 tiles by default, sporadically open alien forest outside the clearing, resource pockets beyond the build area, and three carved clear paths from the player clearing to the map edge. Sandbox starts without prebuilt roads or demo objects.

The hidden admin panel has a `World` category for the current procedural controls: `Paths`, `Path width`, `Clear noise`, `Build min`, and `Build max`. `Clear noise` controls how far the start clearing may deviate from the guaranteed minimum radius toward the maximum radius: `0` is a near-perfect circle at `Build min`, while `100` uses the full `Build min` to `Build max` range for an irregular edge.

`Dev Mode` uses the same map renderer and generator, but enables demo roads/objects and extra terrain-paint tools for debugging atlas and autotile behavior.

Current atlas slots are 32x16 pixels:

| Atlas X | Terrain |
| --- | --- |
| 0 | Basalt plain |
| 1 | Alien scrub |
| 2 | Crystal growth |
| 3 | Ore ridge |
| 4 | Geothermal vent |
| 5 | Road placeholder |
| 6 | Utility/plate placeholder |
| 7 | Reserved/debug placeholder |

Regenerate the MVP sheet with:

```bash
godot --headless --path /Users/donnybystrom/code/outpost-alpha --script res://tools/generate_mvp_tiles.gd
```

Road autotiles use atlas row 1. Atlas X is the 4-bit cardinal neighbor mask:

| Bit | Direction | Offset |
| --- | --- | --- |
| 1 | North | `Vector2i(0, -1)` |
| 2 | East | `Vector2i(1, 0)` |
| 4 | South | `Vector2i(0, 1)` |
| 8 | West | `Vector2i(-1, 0)` |

Examples: `5` is north+south, `10` is east+west, `15` is a four-way crossing.

## Living Design Docs

Design and concept notes live under `ai_docs/gdd/`. Update those documents as gameplay direction changes, and add implementation/design behavior notes to `ai_docs/devlog/CHANGELOG.md` as the prototype evolves.
