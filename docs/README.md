# Outpost Alpha

Minimal Godot 4.7 / GDScript prototype for an isometric 2D RTS foundation.

## Current slice

- 32x16 pixel isometric tile projection.
- Procedural 42x42 alien terrain grid.
- Draw-order based on tile rows.
- Pan and zoom camera.
- Resizable viewport using `canvas_items` + `expand`.
- RTS-style camera behavior: resize reveals more or less world without resetting zoom.
- Responsive HUD root with controlled scale and anchored status panel.
- Hover and click tile selection.
- Procedural placeholder roads, structures, vehicles, ore, crystal growth and geothermal vents.

## Controls

- `WASD` or arrow keys: pan camera.
- Middle mouse drag: pan camera.
- Mouse wheel: zoom.
- Left click: select tile.
- `G`: toggle grid overlay.

## Notes

The engine slice is intentionally sprite-size driven even though the current art is drawn procedurally. The tile projection uses `TILE_SIZE = Vector2i(32, 16)` in `scripts/iso_world.gd`, so generated or imported sprites can be aligned to that baseline later.

The project uses `window/stretch/mode="canvas_items"` and `window/stretch/aspect="expand"` so wide or tall windows increase the visible play area instead of adding black bars or non-uniform distortion. Runtime code keeps camera zoom stable on resize and only relayouts HUD controls.
