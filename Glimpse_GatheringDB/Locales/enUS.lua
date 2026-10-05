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
L["Reset data"] = true
L["Deletes all collected gathering data."] = true
L["Really delete all collected gathering data?"] = true

-- Slash-Befehl
L["Shows statistics or resets the gathering data (stats | reset)"] = true
L["Usage: /gli gatheringdb stats | reset"] = true
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
L["No data recorded yet"] = true
L["No source ID in tooltip data"] = true
L["Fields"] = true
L["Secret fields"] = true
L["no ID in tooltip"] = true
L["The saved gathering data comes from a newer version. Recording is paused."] = true
L["Missing game functions, recording is off: %s"] = true
L["Errors while recording: %d (last: %s)"] = true
