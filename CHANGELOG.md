# Changelog

## [Unreleased]

### Changed
- Maps, player position, distances, coordinates and units now come from the Glimpse core module `Locations` (Glimpse 0.2.0 or newer is required, `X-Glimpse-MinVersion`); GatheringDB API_VERSION 5 (`GetMapSize`, `GetMapDistance`, `GetContinent`, `GetWorldPosition`, `GetPlayerArea` moved to the core, `GetMapName` stays)

### Added
- GatheringTooltip: credits for the marker icons (Flaticon: Karacis, Magnific, kawalanicon) in the README, in `Media/Markers/CREDITS.md` and in the "Credits" section of the options page
- GatheringTooltip: a key (default Ctrl+G; any combination of Ctrl, Shift, Alt and a key, set in the options and checked against the game key bindings) sets a waypoint to the best place while the tooltip of a crafting material is shown: TomTom if installed, otherwise the game marker; optional hint line in the tooltip (mentions TomTom when it is detected; the options page says which one is used)
- GatheringDB: export and import of all data (`/gli gatheringdb export | import`, buttons in the options), compressed text, merge or replace, duplicate-import protection
- GatheringDB: imports of older data versions are migrated automatically, newer ones are refused
- GatheringDB: records where loot was found (zone + coordinates, clustered, option "Record locations"); API `GetSpots`, `GetItemSpots`, `GetMapName` (API_VERSION 2)
- GatheringDB: uses node locations from GatherMate2 when it is installed (option "Use locations from other addons"); API `GetNearestSpots`, `GetOwnSpots`, `GetProviders`, `RegisterProvider`, `GetSpots(..., includeExternal)` (API_VERSION 3)
- GatheringDB: crafting materials show their sources with locations in the debug tooltip; API `GetLocatedItemSources(itemID, minAttempts, externalSeparate, minChance)` (one entry per source and zone) with the steps own zone, same continent (by distance in yards), elsewhere, none; `GetNearestSpots` gives every location a `tier` and distances to other zones of the continent; API_VERSION 4
- GatheringTooltip: the places to get a crafting material are ordered by where you can farm it best: first your own zone or instance, then other zones of your continent by distance (from a minimum chance), then everything else (other continents, instances), then sources without a location; within each step finds you confirmed yourself come before locations from other addons; one entry per source and zone, option "Number of places" (1 to 10, default 3), "Minimum chance for other zones" and "List sources with outside locations separately"
- GatheringDB: locations from other addons keep the best location of every zone, so no zone is lost when another one is much denser
- GatheringDB: each source for outside locations (GatherMate2) has its own switch in the options, next to the general one
- GatheringDB: debug tooltip lists locations (own and from other addons) with map, coordinates, distance in yards (from the game's own map data, no other addon needed) and source; `/gli gatheringdb gm2` helps to find problems with the GatherMate2 data
- GatheringDB: loot in dungeons and raids is stored with the instance as its location (no coordinates); instances count as "here" in the source order and show in the debug tooltip; data version 3 (migrates automatically, export/import carries the instance names)
- GatheringDB: the debug chat output on looting shows the position (map and coordinates, or the instance) and the stored location
- GatheringDB: the debug chat output also shows the area (and the raw `IsInInstance` / `GetInstanceInfo` values) when entering a zone, instance or loading screen
- GatheringTooltip: hits and attempts are shown behind the chance of a place, e.g. `93 %  (13/14)`; option "Show attempts"
- GatheringTooltip: each source of a crafting material gets an icon (bag for loot, profession icons for skinning, herbalism and mining, `?` for other nodes); option "Show source icons". Without icons the sources are grouped under headings for loot, skinning, herbalism, mining and gathering
- GatheringTooltip: distances use the unit set in the Glimpse options (automatic by client language, yards or metres; needs a Glimpse with `FormatDistance`)
- GatheringTooltip: the best location of each source is shown in brackets in the same line, in its own colours (coordinates in yellow brackets like TomTom, then the place `(Loch Modan - 2288 yd - GatherMate2)` with light blue zone, white distance and grey addon name; your own place shows its zone name too, with a small marker: five symbols to click in the options, shown side by side, in five colours picked from a list that previews the symbol in each colour, or switched off): coordinates and distance in your zone, zone and distance (yards, straight line) in other zones of your continent, the zone elsewhere; the other addon's name for its locations; options for showing locations, coordinates and distance; names and locations of all sources are aligned in two columns, coordinates and place (measured and padded with spaces; missing coordinates leave the column empty)
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
