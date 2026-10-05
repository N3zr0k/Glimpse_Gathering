# Changelog

## [Unreleased]

### Added
- GatheringDB: export and import of all data (`/gli gatheringdb export | import`, buttons in the options), compressed text, merge or replace, duplicate-import protection
- GatheringDB: imports of older data versions are migrated automatically, newer ones are refused
- GatheringDB: records where loot was found (zone + coordinates, clustered, option "Record locations"); API `GetSpots`, `GetItemSpots`, `GetMapName` (API_VERSION 2)
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
