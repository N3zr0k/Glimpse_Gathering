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
L["Kills: %d"] = true
L["Kills"] = true
L["Reset data"] = true
L["Deletes all collected gathering data."] = true
L["Really delete all collected gathering data?"] = true

-- Slash-Befehl
L["Shows statistics, exports, imports or resets the gathering data (stats | export | import | reset)"] = true
L["Usage: /gli gatheringdb stats | export | import | reset"] = true
L["Gathering data deleted."] = true

-- Debug-Anzeige im Tooltip
L["ID"] = true
L["Name"] = true
L["Level"] = true
L["Category"] = true
L["Loot"] = true
L["Skinning"] = true
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
L["Sources"] = true
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

-- Export und Import
L["Export and import"] = true
L["Export"] = true
L["Import"] = true
L["Shows all collected data as text to copy, for a backup or another account."] = true
L["Paste exported data to merge it with yours or to replace it."] = true
L["Export gathering data"] = true
L["Import gathering data"] = true
L["%d gathering nodes, %d creatures, %d characters"] = true
L["Select the text (Ctrl+A), copy it (Ctrl+C) and paste it into the import window on the other account or computer."] = true
L["Paste the exported text here. Merge adds the numbers to your data, Replace deletes your data first. Older data is converted automatically."] = true
L["Merge"] = true
L["Replace"] = true
L["Replace ALL gathering data with the imported data? This cannot be undone."] = true
L["Imported: %d gathering nodes, %d creatures."] = true
L["Data converted from version %d."] = true
L["Removed entries: %d."] = true
L["Nothing to import. Paste the exported text first."] = true
L["The text is too long."] = true
L["This is not an export of Glimpse: GatheringDB."] = true
L["The export was made by a newer version of the addon. Please update the addon."] = true
L["The export is compressed, but the compression library is missing."] = true
L["The text is damaged or incomplete. Was it copied completely?"] = true
L["The data comes from a newer version of the addon. Please update the addon."] = true
L["This export has already been imported."] = true
