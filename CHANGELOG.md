# Changelog

## [0.2.10] - 2026-10-08

### Changed
- WoW Forever only (interface 16001)

## [0.2.8] - 2026-10-07

### Removed
- GatheringTooltip: fishing skill on fishing poles and the bobber (now in Glimpse: Professions)

## [0.2.5] - 2026-10-06

### Changed
- GatheringDB: kills without loot are detected via `PARTY_KILL`; kill counts are no longer stored

## [0.2.3] - 2026-10-06

### Added
- GatheringDB: fishing per zone (casts and catches)
- GatheringTooltip: where a fish was caught, with chance and amount
- GatheringTooltip: required gathering skill on nodes and skinnable creatures

## [0.2.2] - 2026-10-06

### Added
- GatheringDB: records where loot was found (zone and coordinates)
- GatheringDB: uses node locations from GatherMate2 if installed
- GatheringDB: export and import of all data
- GatheringTooltip: best places of a crafting material, ordered by distance
- GatheringTooltip: waypoint key (default Ctrl+G) to the best place
- GatheringTooltip: hits and attempts behind the chance

### Fixed
- GatheringDB: data version was lost at logout, migrations never ran
- GatheringDB: respawned and repeatedly mined nodes are recorded again
- GatheringTooltip: no "Interface action failed" from the waypoint key in combat

## [0.1.0] - 2026-10-05

### Added
- First release: GatheringDB records nodes and creature loot account-wide
- GatheringTooltip: chances and averages for nodes, creatures, skinning and crafting materials
