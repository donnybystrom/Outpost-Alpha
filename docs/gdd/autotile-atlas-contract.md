# Autotile Atlas Contract

Outpost Alpha stores map data in orthogonal tile coordinates and renders it with an isometric projection. That means the logical cardinal neighbors do not use the same labels an artist may use when looking at the diamond on screen.

## Map-Space Directions

The engine uses this 4-bit mask:

| Bit | Engine name | Map delta | Screen direction |
| --- | --- | --- | --- |
| 1 | `NORTH` | `(0, -1)` | up-right / NE |
| 2 | `EAST` | `(1, 0)` | down-right / SE |
| 4 | `SOUTH` | `(0, 1)` | down-left / SW |
| 8 | `WEST` | `(-1, 0)` | up-left / NW |

Mask values are additive. A tile connected to map north and map west has mask `1 + 8 = 9`, which appears visually as NE + NW.

## Current Atlas Layout

`assets/tiles/terrain_32x16.png` is 16 columns by 3 rows.

| Row | Contents |
| --- | --- |
| 0 | fixed terrain sprites |
| 1 | road autotile sprites |
| 2 | mountain autotile sprites |

Roads and mountains currently use one sprite per 4-bit mask. The mask-to-column mapping is defined in `scripts/autotile_atlas.gd`. It is currently identity mapped, so mask `11` is column `11`, but production art does not have to keep that order.

## Required Road/Mountain Sprite Set

The autotile set needs these 16 logical sprites:

| Mask | Connections in engine terms | Visual connections |
| --- | --- | --- |
| 0 | none | isolated |
| 1 | N | NE |
| 2 | E | SE |
| 3 | N + E | NE + SE |
| 4 | S | SW |
| 5 | N + S | NE + SW |
| 6 | E + S | SE + SW |
| 7 | N + E + S | NE + SE + SW |
| 8 | W | NW |
| 9 | N + W | NE + NW |
| 10 | E + W | SE + NW |
| 11 | N + E + W | NE + SE + NW |
| 12 | S + W | SW + NW |
| 13 | N + S + W | NE + SW + NW |
| 14 | E + S + W | SE + SW + NW |
| 15 | N + E + S + W | all four |

If a generated sheet uses labels like `NW`, `NE`, `SW`, and `SE`, map them through the "Visual connections" column instead of assuming they match `N`, `E`, `S`, and `W` in code.
