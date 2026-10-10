# Changelog

## [0.3.7] - 2026-10-10

### Fixed
- Creature names come from the game cache, node and creature names are learned on mouseover

## [0.3.6] - 2026-10-10

### Changed
- GatheringDB and GatheringTooltip are now one addon, Glimpse: Gathering (delete the old folders)
- One options page with the new tab Recording
- Names of nodes and creatures are learned again
- Requires Glimpse 0.3.33

## [0.3.5] - 2026-10-10

### Changed
- Addon icon optimized for the game (64 x 64)

## [0.3.4] - 2026-10-10

### Changed
- New addon icon

## [0.3.3] - 2026-10-09

### Changed
- Requires Glimpse 0.3.14

## [0.3.2] - 2026-10-09

### Changed
- GatheringTooltip: credits are shown only once, in the Glimpse overview

## [0.3.1] - 2026-10-08

### Added
- Data sources shown in `/gli probe db sources`

## [0.3.0] - 2026-10-08

### Changed
- Data is now stored in Glimpse: Database; old data is taken over on first start
- Requires Glimpse 0.3 and Glimpse: Database
- GatheringDB: fishing is no longer recorded here, it is read from Glimpse: Professions
- GatheringDB: creature locations are kept per zone, without coordinates
- GatheringDB: debug output uses the Glimpse debugger and probes (`/gli probe gathering`)

### Removed
- GatheringDB: own export, import and reset (now in the Glimpse options, tab Data)
- GatheringDB: command `/gli gatheringdb`

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
