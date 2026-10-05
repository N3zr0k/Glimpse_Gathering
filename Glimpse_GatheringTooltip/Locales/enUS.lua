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
