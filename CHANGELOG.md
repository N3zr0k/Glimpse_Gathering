# Changelog

## [0.2.2] - 2026-10-06

### Added
- GatheringDB: separate kill counter per creature (`GetNPCKills`, shown in the debug tooltip and `/gli gatheringdb stats`)
- GatheringDB: kills without a loot window count as an attempt after 2 minutes, only as a fallback
- GatheringDB: records where loot was found (zone and coordinates, or the instance); option "Record locations"
- GatheringDB: uses node locations from GatherMate2 if installed; one switch per outside source in the options
- GatheringDB: export and import of all data (`/gli gatheringdb export | import`), merge or replace
- GatheringDB: `GetLocatedItemSources` orders the sources of an item by where you can farm it best
- GatheringDB: `/gli gatheringdb gm2` helps to find problems with the GatherMate2 data
- GatheringTooltip: the places of a crafting material are ordered by distance, with options for number and minimum chance
- GatheringTooltip: the best place of each source is shown in brackets (coordinates, zone, distance, addon name)
- GatheringTooltip: marker for your own place (five symbols, five colours), credits for the icons
- GatheringTooltip: a key (default Ctrl+G) sets a waypoint (TomTom or game marker) to the best place
- GatheringTooltip: source icons or headings per kind, hits and attempts behind the chance (option "Show attempts")

### Changed
- GatheringTooltip: nodes and creatures show their drops like the sources of an item (chance, hits/attempts, average)
- GatheringTooltip: places that only come from another addon show no chance and average
- GatheringTooltip: distances use the unit of the Glimpse options
- GatheringDB: nodes count once per gathering cast, creatures again after 10 minutes
- GatheringDB: drop lists carry an `attempts` field; data version 5, API_VERSION 6
- Maps, position and distances moved to the Glimpse module `Locations` (needs Glimpse 0.2.2)

### Fixed
- GatheringDB: GatherMate2 matching by node name also finds copper veins and nodes with another spelling or category
- GatheringDB: the data version was lost at logout, so migrations never ran
- GatheringDB: kills without loot are detected more reliably (target health, corpse, end of combat)
- GatheringDB: respawned nodes and repeated mining of one node are recorded again
- GatheringDB: a gathering cast without a success event no longer hides the node
- GatheringTooltip: the distance option no longer says "yards" (the unit is selectable); `gm2` is listed in the command help
- GatheringTooltip: the waypoint key listener is not touched during combat (no "Interface action failed" message)

## [0.1.0] - 2026-10-05

### Added
- GatheringDB: records nodes and creature loot (crafting materials and gems), account-wide, with a public API
- GatheringDB: data version, cleanup of damaged entries and a size limit (2000 nodes, 6000 creatures)
- GatheringDB: debug mode shows the raw recorded numbers in the tooltip
- GatheringTooltip: chances and averages for nodes, creatures (loot and skinning) and crafting materials
- GatheringTooltip: best source(s) in item tooltips, creature level, only-learned-professions filter
- GatheringTooltip: options in tabs, optional Shift/Ctrl/Alt requirement
- GatheringDB, GatheringTooltip: addon icons (`Media/Icon.tga`) shown in the addon list
