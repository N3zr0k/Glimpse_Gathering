local ADDON_NAME = ...

-- Default-Locale, der englische Text ist gleichzeitig der Key (siehe Glimpse/Locales).
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "enUS", true, true)

-- Optionen
L["Record gathering data"] = true
L["Collects gathering nodes and creature loot while you play."] = true
L["Statistics"] = true
L["Gathering nodes: %d"] = true
L["Creatures: %d"] = true
L["Recorded loot windows: %d"] = true

-- Debug-Anzeige im Tooltip
L["ID"] = true
L["Name"] = true
L["Level"] = true
L["Category"] = true
L["Loot"] = true
L["Skinning"] = true
L["Mining"] = true
L["Herbalism"] = true
L["%s: skill %d, bonus %d, maximum %d (%s)"] = true
L["%s: not learned"] = true
L["Target: creature type %s, level %s, skinning skill %s"] = true
L["%d attempts"] = true
L["%d hits, %d total"] = true
L["... %d more"] = true
L["Locations: %d own, %d from other addons"] = true
L["Instance"] = true
L["Position"] = true
L["unknown"] = true
L["%d finds"] = true
L["%d points"] = true
L["%d yards away"] = true
L["%s%% of the map away"] = true
L["Places"] = true
L["here"] = true
L["elsewhere"] = true
L["same continent"] = true
L["confirmed"] = true
L["outside"] = true
L["no location"] = true
L["outside separate"] = true
L["outside combined"] = true
L["No data recorded yet"] = true
L["No source ID in tooltip data"] = true
L["Fields"] = true
L["Secret fields"] = true
L["no ID in tooltip"] = true
L["The saved gathering data comes from a newer version. Recording is paused."] = true
L["Missing game functions, recording is off: %s"] = true
L["Errors while recording: %d (last: %s)"] = true

-- Fundorte
L["Record locations"] = true
L["Also stores the zone and the coordinates where you looted. Needed to find where something drops."] = true
L["Locations: %d"] = true
L["Use locations from other addons"] = true
L["Also lists locations from other addons (GatherMate2) after your own. They are not saved or exported."] = true
L["No supported addon found. Install GatherMate2 to use its locations."] = true
L["Sources for locations"] = true
L["Choose which addons the locations are read from."] = true
L["Reads the node locations saved by %s. They are not copied or exported."] = true
L["%s was not found or is not loaded."] = true
L["%s: %d locations"] = true

-- Angeln
L["Fishing"] = true
L["Zone"] = true
L["No zone known"] = true

-- Glimpse: Database
L["Fishing: %d zones, %d loot windows"] = true
L["Glimpse: Database is not available, recording is off (%s)."] = true
L["The data is stored in Glimpse: Database. Export, import and reset are in the Glimpse options, tab Data."] = true
