# World Generation

The sandbox start map is generated at runtime from a random seed.

## Current Controls

| Control | Purpose |
| --- | --- |
| Paths | Number of clear exit paths from the player clearing through the surrounding forest. |
| Path width | Preferred width of those carved paths in tiles. |
| Clear noise | How irregular the edge of the starting clearing should be. |
| Build min | Guaranteed circular build radius around the start tile. |
| Build max | Maximum radius that `Clear noise` can extend the clearing toward. |

## Current Algorithm

1. Generate base ground over a 96x96 map.
2. Bias alien forest to appear outside the player start zone.
3. Carve a start clearing around the center tile.
4. Place resources outside the guaranteed build area.
5. Carve configured clear paths from the start tile to map edges.
6. Place temporary demo roads near the start tile.

## Design Intent

The player should begin with an understandable, buildable central zone but feel visually surrounded by alien forest. The three-path default creates readable strategic exits without making the wilderness a solid wall.

Sandbox generation should not place prebuilt roads or demo structures. Those remain a Dev Mode concern so the real game start can grow from explicit player construction.
