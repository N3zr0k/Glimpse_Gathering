# Changelog

## [Unreleased]

### Added
- GatheringDB: export and import of all data (`/gli gatheringdb export | import`, buttons in the options), compressed text, merge or replace, duplicate-import protection
- GatheringDB: imports of older data versions are migrated automatically, newer ones are refused
- GatheringDB: records where loot was found (zone + coordinates, clustered, option "Record locations"); API `GetSpots`, `GetItemSpots`, `GetMapName` (API_VERSION 2)
- GatheringDB: uses node locations from GatherMate2 when it is installed (option "Use locations from other addons"); API `GetNearestSpots`, `GetOwnSpots`, `GetProviders`, `RegisterProvider`, `GetSpots(..., includeExternal)` (API_VERSION 3)
- GatheringDB: crafting materials show their sources with locations in the debug tooltip; API `GetLocatedItemSources`
- GatheringTooltip: sources of a crafting material are ordered by area (your area, other areas, outside locations only, each the most likely first); option "List sources with outside locations separately" in the Crafting materials tab (off: outside locations count like your own)
- GatheringDB: locations from other addons keep the best location of every zone, so no zone is lost when another one is much denser
- GatheringDB: each source for outside locations (GatherMate2) has its own switch in the options, next to the general one
- GatheringDB: debug tooltip lists locations (own and from other addons) with map, coordinates, distance in yards (from the game's own map data, no other addon needed) and source; `/gli gatheringdb gm2` helps to find problems with the GatherMate2 data
- GatheringDB: loot in dungeons and raids is stored with the instance as its location (no coordinates); instances count as "here" in the source order and show in the debug tooltip; data version 3 (migrates automatically, export/import carries the instance names)
- GatheringDB: the debug chat output on looting shows the position (map and coordinates, or the instance) and the stored location
- GatheringDB: the debug chat output also shows the area (and the raw `IsInInstance` / `GetInstanceInfo` values) when entering a zone, instance or loading screen
- GatheringTooltip: each source of a crafting material gets an icon (bag for loot, profession icons for skinning, herbalism and mining, `?` for other nodes); option "Show source icons". Without icons the sources are grouped under headings for loot, skinning, herbalism, mining and gathering
- GatheringTooltip: the location of each source is shown in brackets in the same line, in its own colours (coordinates yellow like TomTom, zone and distance light blue): coordinates and distance of the nearest location in your area, the zone or instance elsewhere, the other addon's name for its locations; further locations only for different zones, each in its own line (also next to a location in your own zone); options for none, nearest or up to three zones, coordinates and distance
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
