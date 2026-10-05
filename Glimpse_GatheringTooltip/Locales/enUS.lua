local ADDON_NAME = ...

-- Default-Locale, der englische Text ist gleichzeitig der Key (siehe Glimpse/Locales).
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "enUS", true, true)

-- Tooltip
L["Gathered"] = true
L["Loot"] = true
L["Skinning"] = true
L["%d attempts"] = true
L["Best source"] = true
L["Node %d"] = true
L["Creature %d"] = true
L["Avg. %.1f"] = true

-- Optionen
L["Show gathering nodes"] = true
L["Show herb and ore nodes in their tooltips."] = true
L["Show creature loot"] = true
L["Show the loot of creatures in their tooltips."] = true
L["Show skinning loot"] = true
L["Show the skinning loot of creatures in their tooltips."] = true
L["Items per list"] = true
L["Maximum number of items shown per list."] = true
L["Minimum attempts"] = true
L["Lists are only shown after this many recorded attempts."] = true
L["Level %s"] = true
L["Crafting materials"] = true
L["Target"] = true
L["General"] = true
L["Sources"] = true
L["Show sources on items"] = true
L["Show where a crafting material comes from in its tooltip."] = true
L["Number of sources"] = true
L["How many sources are shown: your area first, then other areas, each the most likely first."] = true
L["List sources with outside locations separately"] = true
L["On: sources that only have locations from other addons (GatherMate2) come after those with your own. Off: those locations count like your own when sorting."] = true
L["Only learned professions"] = true
L["Only show nodes, skinning loot and sources for professions you have learned."] = true

-- Symbole und Fundorte
L["Show source icons"] = true
L["Show a bag for loot and the profession icon for skinning, herbalism and mining in front of each source. Off: a heading for loot or the profession is shown above its sources."] = true
L["Locations per source"] = true
L["Shows the location in brackets behind each source: coordinates and distance in your area, the zone or instance elsewhere."] = true
L["Off"] = true
L["Nearest location"] = true
L["Up to three zones"] = true
L["Show coordinates"] = true
L["Show the coordinates of locations in your area."] = true
L["Show distance"] = true
L["Show the distance in yards to locations in your area."] = true
L["%d yd"] = true
L["Instance %d"] = true
L["Map %d"] = true
L["Herbalism"] = true
L["Mining"] = true
L["Gathering"] = true
