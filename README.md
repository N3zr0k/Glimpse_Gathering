# Glimpse: Gathering

<p align="center"><img src="docs/icon_gatheringdb.png" width="128" alt="GatheringDB icon"> <img src="docs/icon_gatheringtooltip.png" width="128" alt="GatheringTooltip icon"></p>

Two addons for [Glimpse](https://github.com/N3zr0k/Glimpse) (0.1.0 or newer) that learn where crafting
materials come from while you play.

| Addon | Role |
| --- | --- |
| **Glimpse: GatheringDB** | Records gathering nodes and creature loot (crafting materials and gems, every attempt counts) account-wide and offers the data to other addons through a small API. Shows nothing by itself, except raw numbers in debug mode. |
| **Glimpse: GatheringTooltip** | Shows drop chances and average amounts in the tooltips of nodes, creatures and crafting materials, including the best source of an item. Requires GatheringDB. |

GatheringDB also remembers **where** you looted (zone and coordinates, clustered, optional) and can **export / import**
its data (`/gli gatheringdb export`, `/gli gatheringdb import`, or the buttons in its options). Imports of
older data versions are migrated automatically; data from a newer version is refused.

If [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) is installed, its node locations are used as well
(after your own, never saved or exported; can be switched off in the GatheringDB options).

Not recorded: chests, fishing (no loot source), anything that is not a crafting material.

## Options (GatheringTooltip)

* General: only learned professions, minimum number of attempts, only while Shift/Ctrl/Alt is held
* Crafting materials: show sources on items, number of sources (your area first, then other areas, each the most likely first), list sources with outside locations (GatherMate2) separately or count them like your own
* Target: nodes, creature loot, skinning loot, items per list

## Installation

Install Glimpse first. Unpack this ZIP into `Interface/AddOns`; it contains both folders
`Glimpse_GatheringDB` and `Glimpse_GatheringTooltip`. The data starts empty and grows while you play.

Commands: `/gli gatheringdb stats` and `/gli gatheringdb reset`.

## Development

The repository contains the two addon folders at its top level. To work on it directly, clone it anywhere and link
both folders into the AddOns folder (see [DEVELOPER.md](DEVELOPER.md)). Checks:

```
lua tests/run.lua
luacheck .
python3 tools/check.py
```

## License

MIT, see [LICENSE](LICENSE).
