local ADDON_NAME = ...

-- NewLocale liefert nil, wenn der Client nicht deDE ist. Dann bleibt alles auf Englisch.
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "deDE")
if not L then return end

-- Tooltip
L["Gathered"] = "Gesammelt"
L["Loot"] = "Beute"
L["Skinning"] = "Kürschnern"
L["%d attempts"] = "%d Versuche"
L["Best source"] = "Beste Quelle"
L["Node %d"] = "Knoten %d"
L["Creature %d"] = "Kreatur %d"
L["Avg. %.1f"] = "Ø %.1f"

-- Optionen
L["Show gathering nodes"] = "Sammelknoten anzeigen"
L["Show herb and ore nodes in their tooltips."] = "Zeigt Kräuter- und Erzknoten in ihren Tooltips."
L["Show creature loot"] = "Kreaturen-Beute anzeigen"
L["Show the loot of creatures in their tooltips."] = "Zeigt die Beute von Kreaturen in ihren Tooltips."
L["Show skinning loot"] = "Kürschner-Beute anzeigen"
L["Show the skinning loot of creatures in their tooltips."] = "Zeigt die Kürschner-Beute von Kreaturen in ihren Tooltips."
L["Items per list"] = "Items pro Liste"
L["Maximum number of items shown per list."] = "Höchstzahl der Items pro Liste."
L["Minimum attempts"] = "Mindestversuche"
L["Lists are only shown after this many recorded attempts."] = "Listen erscheinen erst nach so vielen erfassten Versuchen."
L["Level %s"] = "Stufe %s"
L["Crafting materials"] = "Handwerksmaterial"
L["Target"] = "Ziel"
L["General"] = "Allgemein"
L["Sources"] = "Quellen"
L["Show sources on items"] = "Quellen bei Items anzeigen"
L["Show where a crafting material comes from in its tooltip."] = "Zeigt im Tooltip eines Handwerksmaterials, woher es kommt."
L["Number of sources"] = "Anzahl der Quellen"
L["How many sources are shown: your area first, then other areas, each the most likely first."] = "Wie viele Quellen angezeigt werden: erst dein Gebiet, dann andere Gebiete, jeweils die wahrscheinlichste zuerst."
L["List sources with outside locations separately"] = "Quellen mit externen Fundorten getrennt aufführen"
L["On: sources that only have locations from other addons (GatherMate2) come after those with your own. Off: those locations count like your own when sorting."] = "An: Quellen, die nur Fundorte aus anderen Addons (GatherMate2) haben, stehen hinter denen mit eigenen. Aus: Diese Fundorte zählen beim Sortieren wie deine eigenen."
L["Only learned professions"] = "Nur gelernte Berufe"
L["Only show nodes, skinning loot and sources for professions you have learned."] = "Zeigt nur Knoten, Kürschner-Beute und Quellen zu Berufen, die du gelernt hast."

-- Symbole und Fundorte
L["Show source icons"] = "Symbole vor den Quellen"
L["Show a bag for loot and the profession icon for skinning, herbalism and mining in front of each source. Off: a heading for loot or the profession is shown above its sources."] = "Zeigt vor jeder Quelle einen Beutel für Beute und das Berufssymbol für Kürschnern, Kräuterkunde und Bergbau. Aus: Über den Quellen steht eine Überschrift für Beute oder den Beruf."
L["Locations per source"] = "Fundorte je Quelle"
L["Shows the location in brackets behind each source: coordinates and distance in your area, the zone or instance elsewhere."] = "Zeigt hinter dem Namen jeder Quelle den Fundort in Klammern: Koordinaten und Entfernung im eigenen Gebiet, sonst die Zone oder Instanz."
L["Off"] = "Aus"
L["Nearest location"] = "Nächster Fundort"
L["Up to three zones"] = "Bis zu drei Zonen"
L["Show coordinates"] = "Koordinaten anzeigen"
L["Show the coordinates of locations in your area."] = "Zeigt die Koordinaten von Fundorten im eigenen Gebiet."
L["Show distance"] = "Entfernung anzeigen"
L["Show the distance in yards to locations in your area."] = "Zeigt die Entfernung in Yards zu Fundorten im eigenen Gebiet."
L["%d yd"] = "%d yd"
L["Instance %d"] = "Instanz %d"
L["Map %d"] = "Karte %d"
L["Herbalism"] = "Kräuterkunde"
L["Mining"] = "Bergbau"
L["Gathering"] = "Sammeln"
