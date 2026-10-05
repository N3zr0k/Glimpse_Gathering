local ADDON_NAME = ...

-- NewLocale liefert nil, wenn der Client nicht deDE ist. Dann bleibt alles auf Englisch.
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "deDE")
if not L then return end

-- Optionen
L["Record gathering data"] = "Sammeldaten aufzeichnen"
L["Collects gathering nodes and creature loot while you play."] = "Sammelt Sammelknoten und Kreaturen-Beute beim Spielen."
L["Statistics"] = "Statistik"
L["Gathering nodes: %d"] = "Sammelknoten: %d"
L["Creatures: %d"] = "Kreaturen: %d"
L["Recorded loot windows: %d"] = "Erfasste Beutefenster: %d"
L["Reset data"] = "Daten zurücksetzen"
L["Deletes all collected gathering data."] = "Löscht alle gesammelten Daten."
L["Really delete all collected gathering data?"] = "Wirklich alle gesammelten Daten löschen?"

-- Slash-Befehl
L["Shows statistics or resets the gathering data (stats | reset)"] = "Zeigt die Statistik oder setzt die Daten zurück (stats | reset)"
L["Usage: /gli gatheringdb stats | reset"] = "Verwendung: /gli gatheringdb stats | reset"
L["Gathering data deleted."] = "Sammeldaten gelöscht."

-- Debug-Anzeige im Tooltip
L["ID"] = "ID"
L["Name"] = "Name"
L["Level"] = "Stufe"
L["Category"] = "Kategorie"
L["Loot"] = "Beute"
L["Skinning"] = "Kürschnern"
L["%d attempts"] = "%d Versuche"
L["%d hits, %d total"] = "%d Treffer, %d gesamt"
L["... %d more"] = "... %d weitere"
L["No data recorded yet"] = "Noch keine Daten erfasst"
L["No source ID in tooltip data"] = "Keine Quellen-ID in den Tooltip-Daten"
L["Fields"] = "Felder"
L["Secret fields"] = "Geschützte Felder"
L["no ID in tooltip"] = "keine ID im Tooltip"
L["The saved gathering data comes from a newer version. Recording is paused."] = "Die gespeicherten Sammeldaten stammen von einer neueren Version. Die Aufzeichnung ist pausiert."
L["Missing game functions, recording is off: %s"] = "Fehlende Spielfunktionen, die Aufzeichnung ist aus: %s"
L["Errors while recording: %d (last: %s)"] = "Fehler beim Aufzeichnen: %d (zuletzt: %s)"
