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

-- Debug-Anzeige im Tooltip
L["ID"] = "ID"
L["Name"] = "Name"
L["Level"] = "Stufe"
L["Category"] = "Kategorie"
L["Loot"] = "Beute"
L["Skinning"] = "Kürschnern"
L["Mining"] = "Bergbau"
L["Herbalism"] = "Kräuterkunde"
L["%s: skill %d, bonus %d, maximum %d (%s)"] = "%s: Skill %d, Bonus %d, Maximum %d (%s)"
L["%s: not learned"] = "%s: nicht gelernt"
L["Target: creature type %s, level %s, skinning skill %s"] = "Ziel: Kreaturentyp %s, Stufe %s, Kürschnerei-Skill %s"
L["%d attempts"] = "%d Versuche"
L["%d hits, %d total"] = "%d Treffer, %d gesamt"
L["... %d more"] = "... %d weitere"
L["Locations: %d own, %d from other addons"] = "Fundorte: %d eigene, %d aus anderen Addons"
L["Instance"] = "Instanz"
L["Position"] = "Position"
L["unknown"] = "unbekannt"
L["%d finds"] = "%d Funde"
L["%d points"] = "%d Punkte"
L["%d yards away"] = "%d Yards entfernt"
L["%s%% of the map away"] = "%s%% der Karte entfernt"
L["Places"] = "Orte"
L["here"] = "hier"
L["elsewhere"] = "woanders"
L["same continent"] = "gleicher Kontinent"
L["confirmed"] = "bestätigt"
L["outside"] = "extern"
L["no location"] = "kein Ort"
L["outside separate"] = "externe getrennt"
L["outside combined"] = "externe zusammengefasst"
L["No data recorded yet"] = "Noch keine Daten erfasst"
L["No source ID in tooltip data"] = "Keine Quellen-ID in den Tooltip-Daten"
L["Fields"] = "Felder"
L["Secret fields"] = "Geschützte Felder"
L["no ID in tooltip"] = "keine ID im Tooltip"
L["The saved gathering data comes from a newer version. Recording is paused."] = "Die gespeicherten Sammeldaten stammen von einer neueren Version. Die Aufzeichnung ist pausiert."
L["Missing game functions, recording is off: %s"] = "Fehlende Spielfunktionen, die Aufzeichnung ist aus: %s"
L["Errors while recording: %d (last: %s)"] = "Fehler beim Aufzeichnen: %d (zuletzt: %s)"

-- Fundorte
L["Record locations"] = "Fundorte aufzeichnen"
L["Also stores the zone and the coordinates where you looted. Needed to find where something drops."] = "Speichert zusätzlich Zone und Koordinaten, wo du gelootet hast. Nötig, um zu finden, wo etwas herkommt."
L["Locations: %d"] = "Fundorte: %d"
L["Use locations from other addons"] = "Fundorte aus anderen Addons verwenden"
L["Also lists locations from other addons (GatherMate2) after your own. They are not saved or exported."] = "Zeigt zusätzlich Fundorte aus anderen Addons (GatherMate2) hinter deinen eigenen. Sie werden weder gespeichert noch exportiert."
L["No supported addon found. Install GatherMate2 to use its locations."] = "Kein unterstütztes Addon gefunden. Installiere GatherMate2, um dessen Fundorte zu nutzen."
L["Sources for locations"] = "Quellen für Fundorte"
L["Choose which addons the locations are read from."] = "Wähle, aus welchen Addons Fundorte gelesen werden."
L["Reads the node locations saved by %s. They are not copied or exported."] = "Liest die von %s gespeicherten Knoten-Fundorte. Sie werden weder kopiert noch exportiert."
L["%s was not found or is not loaded."] = "%s wurde nicht gefunden oder ist nicht geladen."
L["%s: %d locations"] = "%s: %d Fundorte"

-- Angeln
L["Fishing"] = "Angeln"
L["Zone"] = "Zone"
L["No zone known"] = "Zone unbekannt"

-- Glimpse: Database
L["Fishing: %d zones, %d loot windows"] = "Angeln: %d Zonen, %d Beutefenster"
L["Glimpse: Database is not available, recording is off (%s)."] = "Glimpse: Database ist nicht verfügbar, die Aufzeichnung ist aus (%s)."
L["The data is stored in Glimpse: Database. Export, import and reset are in the Glimpse options, tab Data."] = "Die Daten liegen in Glimpse: Database. Export, Import und Zurücksetzen stehen in den Glimpse-Optionen, Tab Daten."
