# Glimpse: Gathering – CurseForge-Texte

Zum Kopieren in die Projektseite auf CurseForge. Projekt-ID 1730186 (steht in der TOC als `X-Curse-Project-ID` und in
`release.yml` als `-p`). Ab der Beta lädt das Release das ZIP selbst hoch, die Texte hier pflegt Sven von Hand.

## Projektname

```
Glimpse: Gathering
```

## Summary

```
Learns where crafting materials come from while you play: drop chances on nodes and creatures, and the best places to farm an item.
```

## Kategorie

```
Tooltip
```

## Logo

`docs/icon.png` (512 x 512)

## Beschreibung

Alles unter dieser Zeile in den Beschreibungs-Editor (Markdown) kopieren.

---

# Glimpse: Gathering

[![latest](https://img.shields.io/github/v/release/N3zr0k/Glimpse_Gathering?include_prereleases&amp;sort=date&amp;label=latest)](https://github.com/N3zr0k/Glimpse_Gathering/releases) [![last push](https://img.shields.io/github/last-commit/N3zr0k/Glimpse_Gathering/main?label=last%20push)](https://github.com/N3zr0k/Glimpse_Gathering/commits/main) [![CI](https://img.shields.io/github/actions/workflow/status/N3zr0k/Glimpse_Gathering/ci.yml?branch=main&amp;label=CI)](https://github.com/N3zr0k/Glimpse_Gathering/actions/workflows/ci.yml)

> ## ⚠ Requires the Glimpse core addon
> **Glimpse: Gathering only works together with [Glimpse](https://www.curseforge.com/wow/addons/glimpse).** Install Glimpse first (version 0.3.33 or newer, with Glimpse: Database), otherwise this addon does not load.
> 👉 https://www.curseforge.com/wow/addons/glimpse

**Glimpse: Gathering** watches your loot windows and learns which herbs, ores, skins and other crafting materials drop where. It shows the results right in your tooltips.

> Up to version 0.3.5 this project contained two addons, GatheringDB and GatheringTooltip. They are now one addon. If the folders `Glimpse_GatheringDB` and `Glimpse_GatheringTooltip` are still in your AddOns folder, delete them.

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
- Names of nodes and creatures are learned while you play; creature names also come from the game.
- Export, import and reset are in the Glimpse options (tab *Data*).
- Everything can be switched on or off in the options (Glimpse options, *Gathering*: General, Crafting materials, Target, Recording).
- German and English.

## Commands

`/gli probe gathering stats` shows what has been recorded so far. More checks: `skill`, `gm2`, `area`, `names`, `fishing`, `node <id>`, `npc <id>`, `item <id>`.

## Links

- Core addon: [Glimpse on CurseForge](https://www.curseforge.com/wow/addons/glimpse) · [GitHub](https://github.com/N3zr0k/Glimpse)
- Source and issues: [GitHub](https://github.com/N3zr0k/Glimpse_Gathering)
- MIT license
