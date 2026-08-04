# Development Changelog

## Unreleased

- Added main menu with visual Outpost Alpha backdrop and `Sandbox` / `Quit to OS` actions.
- Added `Dev Mode` main-menu entry for demo roads, demo objects, and dev-only terrain painting.
- Changed `Sandbox` to start a clean generated world with no prebuilt demo roads.
- Added bottom construction menu with road painting in both Sandbox and Dev Mode.
- Fixed full-screen HUD input capture so map clicks reach the isometric world while in build mode.
- Fixed background viewport fill input capture so it cannot block map hover/click events.
- Added `MapInputController` to separate viewport input, camera-aware coordinate conversion, and world commands.
- Added faint black default hover outline for map cells when no build tool is active.
- Added Road hover preview with translucent road art and green isometric target outline.
- Added Shift-drag road-line preview with green isometric tile outlines and commit-on-release behavior.
- Added FPS/frame-time display to the debug HUD.
- Split terrain, roads, and grid into separate render layers to avoid full-grid redraws on hover and full-terrain redraws on road edits.
- Added `IsoOverlayLayer` so hover, selection, road preview, and line preview redraw separately from static map layers.
- Added render diagnostics for draw count, redraw requests, last draw time, and cells processed per layer.
- Added input conversion timing to the debug HUD.
- Baked terrain and grid into cached textures to avoid thousands of per-frame tile draw calls.
- Changed road rendering to a cached transparent road texture with dirty updates limited to the edited road tile and its four cardinal neighbors.
- Made the world-generation admin panel hidden by default and toggleable with ` / §.
- Added sandbox admin/settings panel with World, Raids, and Loot categories.
- Moved world generation controls into the admin panel's World tab.
- Added living GDD documentation structure under `docs/gdd/`.
- Documented current world generation parameters and design intent.
