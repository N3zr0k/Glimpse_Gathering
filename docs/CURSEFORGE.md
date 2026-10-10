# CurseForge texts: Glimpse: Gathering

One CurseForge project (ID 1730186) for both addons, GatheringDB and GatheringTooltip.

## Project name

Glimpse: Gathering

## Logo

`docs/icon.png` (512 x 512)

## Summary

Learns where crafting materials come from while you play: drop chances on nodes and creatures, and the best places to farm an item.

## Description

> ## ⚠ Requires the Glimpse core addon
> **Glimpse: Gathering only works together with [Glimpse](https://www.curseforge.com/wow/addons/glimpse).** Install Glimpse first (version 0.3.14 or newer, with Glimpse: Database), otherwise this addon does not load.
> 👉 https://www.curseforge.com/wow/addons/glimpse

**Glimpse: Gathering** watches your loot windows and learns which herbs, ores, skins and other crafting materials drop where. It then shows it right in your tooltips.

The package contains two addons:

- **Glimpse: GatheringDB** records nodes, creature loot and skinning.
- **Glimpse: GatheringTooltip** shows the results in tooltips.

## Tooltips of nodes and creatures

- Every recorded drop with its chance, hits and attempts, and the average amount per find
- Creatures show normal loot and skinning loot separately
- The required gathering skill, your own skill in colour

## Tooltips of crafting materials

- The best places to get the item: your own zone first, then nearby zones by distance, then everything else
- Coordinates, zone and distance, fishing spots included
- A small marker shows where you are standing
- Press a key (Ctrl+G by default) to set a waypoint to the best place, with TomTom or the game marker

## Good to know

- Only crafting materials and gems are recorded, every attempt counts, so the chances stay honest.
- Locations from [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) are used as well if installed (read live, never saved).
- Export, import and reset are in the Glimpse options (tab *Data*).
- Everything can be switched on or off in the options (Glimpse options, *Gathering*).
- German and English.

## Commands

`/gli probe gathering stats` shows what has been recorded so far. More checks: `skill`, `gm2`, `area`, `names`, `fishing`, `node <id>`, `npc <id>`, `item <id>`.

## Links

- Core addon: [Glimpse on CurseForge](https://www.curseforge.com/wow/addons/glimpse) · [GitHub](https://github.com/N3zr0k/Glimpse)
- Source and issues: [GitHub](https://github.com/N3zr0k/Glimpse_Gathering)
- MIT license
