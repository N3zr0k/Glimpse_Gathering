# Changelog

## [Unreleased]

### Added
- GatheringDB: export and import of all data (`/gli gatheringdb export | import`, buttons in the options), compressed text, merge or replace, duplicate-import protection
- GatheringDB: imports of older data versions are migrated automatically, newer ones are refused
- GatheringDB: records where loot was found (zone + coordinates, clustered, option "Record locations"); API `GetSpots`, `GetItemSpots`, `GetMapName` (API_VERSION 2)
- GatheringDB: uses node locations from GatherMate2 when it is installed (option "Use locations from other addons"); API `GetNearestSpots`, `GetOwnSpots`, `GetProviders`, `RegisterProvider`, `GetSpots(..., includeExternal)` (API_VERSION 3)
- GatheringDB: each source for outside locations (GatherMate2) has its own switch in the options, next to the general one
- GatheringDB: debug tooltip lists locations (own and from other addons) with map, coordinates, distance in yards (from the game's own map data, no other addon needed) and source; `/gli gatheringdb gm2` helps to find problems with the GatherMate2 data
- GatheringDB: data version 2 (adds `spots` and `imports`), bundled LibDeflate

## [0.1.0] - 2026-10-05

### Added
- GatheringDB: records nodes and creature loot (crafting materials and gems), account-wide, with a public API
- GatheringDB: data version, cleanup of damaged entries and a size limit (2000 nodes, 6000 creatures)
- GatheringDB: debug mode shows the raw recorded numbers in the tooltip
- GatheringTooltip: chances and averages for nodes, creatures (loot and skinning) and crafting materials
- GatheringTooltip: best source(s) in item tooltips, creature level, only-learned-professions filter
- GatheringTooltip: options in tabs, optional Shift/Ctrl/Alt requirement
- GatheringDB, GatheringTooltip: addon icons (`Media/Icon.tga`) shown in the addon list
