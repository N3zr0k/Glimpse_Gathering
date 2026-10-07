local ADDON_NAME = ...

-- Default-Locale, der englische Text ist gleichzeitig der Key (siehe Glimpse/Locales).
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "enUS", true, true)

-- Tooltip
L["Gathered"] = true
L["Loot"] = true
L["Skinning"] = true
L["%d attempts"] = true
L["Best place"] = true
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
L["Places"] = true
L["Show sources on items"] = true
L["Show where a crafting material comes from in its tooltip."] = true
L["Number of places"] = true
L["List sources with outside locations separately"] = true
L["Only learned professions"] = true
L["Only show nodes, skinning loot and sources for professions you have learned."] = true

-- Symbole und Fundorte
L["Show source icons"] = true
L["Show a bag for loot and the profession icon for skinning, herbalism and mining in front of each source. Off: a heading for loot or the profession is shown above its sources."] = true
L["Show coordinates"] = true
L["Show the coordinates of locations in your area."] = true
L["Show distance"] = true
L["Instance %d"] = true
L["Map %d"] = true
L["Herbalism"] = true
L["Mining"] = true
L["Gathering"] = true
L["How many places are shown (a source in two zones counts twice). Order: your area first, then other zones on your continent by distance, then everything else."] = true
L["Minimum chance for other zones"] = true
L["Sources in other zones of your continent are only shown from this chance (in percent). 0 shows all."] = true
L["On: within each step, sources with locations you found yourself come before those with locations from other addons only (GatherMate2). Off: both count the same."] = true
L["Show locations"] = true
L["Shows the location in brackets behind each source: coordinates and distance in your area, the zone and distance elsewhere."] = true
L["Show the distance to the location."] = true
L["Show attempts"] = true
L["Show hits and attempts behind the chance, e.g. (13/14), to see how reliable the chance is."] = true
L["Symbol in front of the location where you are."] = true
L["Marker for your place"] = true
L["Symbol in front of the location where you are."] = true
L["Pin"] = true
L["Arrow"] = true
L["Blue"] = true
L["White"] = true
L["Yellow"] = true
L["Green"] = true
L["Red"] = true
L["Color"] = true
L["Show marker"] = true
L["Click to use this symbol."] = true
L["Solid pin"] = true
L["Outline pin"] = true
L["Position"] = true
L["Display"] = true
L["Ctrl"] = true
L["Shift"] = true
L["Alt"] = true
L["Waypoint set: %s (%s)"] = true
L["No waypoint possible here: %s (%s)"] = true
L["%s: set waypoint"] = true
L["Waypoint"] = true
L["Key"] = true
L["Off"] = true
L["Show hint"] = true
L["Shows the key as a line at the end of the tooltip."] = true
L["Press a key ..."] = true
L["While the tooltip of a crafting material is shown, this key sets a waypoint to its best place: TomTom if installed, otherwise the game marker. Click, then press the new combination (Ctrl, Shift and Alt can be combined). Escape cancels, Delete turns the key off. Keys that are already used in the game are refused."] = true
L["TomTom detected: waypoints are set through TomTom."] = true
L["TomTom not found: waypoints are set with the game marker."] = true
L["The key %s is already used in the game: %s"] = true
L["Error"] = true

-- Benötigter Skill
L["Skill: %s - requires %s %d"] = true
L["Skill: %s - possibly requires %s %d"] = true
L["not learned - requires %s %d"] = true
L["Requires %s %d"] = true
L["Show required skill on nodes"] = true
L["Show the skill a herb or ore node needs, your own skill and the colour in its tooltip."] = true
L["Show required skill on creatures"] = true
L["Show the skinning skill a creature needs. Creatures with recorded skinning loot are shown for sure, beasts and dragonkin as a guess."] = true
L["Skill only for learned professions"] = true
L["Only show the required skill if you have the profession."] = true
L["Hide gray nodes"] = true
L["Do not show the skill for nodes and creatures that no longer raise your skill."] = true

-- Angeln
L["Fishing"] = true
L["%s %d/%d"] = true
L["%s - not learned"] = true
