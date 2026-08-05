# Outpost Alpha Game Design Notes

This folder is the living design record for Outpost Alpha. Keep it updated as mechanics, tone, UI flows, and technical constraints become clearer.

## Current Concept

Outpost Alpha is an isometric survival/economic RTS about establishing a colony on a hostile alien planet. The current playable direction starts with a sandbox mode: generate a world, inspect the starting terrain, and iterate on procedural parameters before layering in economy, logistics, raids, loot, research, and base defense.

## Current UX Flow

1. Main menu with a visual colony/alien-world backdrop.
2. `Sandbox` starts the actual game sandbox directly, with no prebuilt demo roads.
3. `Dev Mode` starts the same renderer with demo roads/objects and extra tile painting tools.
4. The in-game admin panel is hidden by default and toggled with ` / §.
5. Generated world with tile selection, pan/zoom, debug status HUD, and a bottom construction menu.

## Current Build Interaction

Sandbox currently exposes road construction and four colony buildings: `oxygen_extractor`, `living_quarters`, `machine_park`, and `milling_plant`. Selecting `Road` in the bottom construction menu lets the player paint roads tile by tile. Road mode shows a translucent road preview and green isometric outline over the tile under the cursor. Holding `Shift` while dragging creates a green isometric preview line; the road tiles are committed when the mouse button is released.

Buildings are a separate layer above terrain. They use footprints, can block road painting, and update colony state without rewriting terrain.

## Documentation Practice

When gameplay direction changes, add or update a document in `docs/gdd/`. When implementation changes affect design assumptions or player-facing behavior, add a short note in `docs/devlog/CHANGELOG.md`.

## Topic Notes

- [World generation](world-generation.md)
- [Input model](input-model.md)
- [Sandbox colony loop](sandbox-colony-loop.md)
- [Rendering and simulation layer model](rendering-layer-model.md)
- [Tileset workflow](tileset-workflow.md)
