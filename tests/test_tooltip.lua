-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Symbole, Fundorte und Tabelle im Tooltip eines Handwerksmaterials (GatheringTooltip/Tooltip/Sources.lua und Tooltip.lua)
local function setup(profile)
    local Glimpse = stub.newGlimpse()
    local GT = Glimpse:NewModule("GatheringTooltip")
    GT.L = Glimpse.L
    GT.db = { profile = { showLocations = true, showCoords = true, showDistance = true, showSourceIcons = true, showAttempts = true, minChance = 10 } }
    for key, value in pairs(profile or {}) do GT.db.profile[key] = value end
    GT.data = { GetMapName = function(_, map) return ({ [37] = "Elwynn", [14] = "Dunkelküste", [10] = "Düsterwald" })[map] end }
    stub.load("Glimpse_GatheringTooltip/Core/Tooltip/Sources.lua", "Glimpse_GatheringTooltip")
    stub.load("Glimpse_GatheringTooltip/Core/Tooltip/Waypoint.lua", "Glimpse_GatheringTooltip")
    GT.db.profile.waypointKey = GT.db.profile.waypointKey or "CTRL-G"
    GT.db.profile.showWaypointHint = GT.db.profile.showWaypointHint == true -- die Hinweiszeile zählt in anderen Tests nicht mit
    return GT
end

-- Orte, wie sie GetLocatedItemSources liefert
local function Here(x, y, yards, source)
    return { map = 37, x = x, y = y, count = 3, source = source or "own", tier = 1, mapDistance = 0.01, distance = yards }
end
local function Zone(map, yards, source) -- Stufe 2: andere Karte, gleicher Kontinent
    return { map = map, x = 0.5, y = 0.5, count = 3, source = source or "own", tier = 2, distance = yards }
end
local function Other(map, source) -- Stufe 3
    return { map = map, x = 0.5, y = 0.5, count = 3, source = source or "own", tier = 3 }
end
local function Source(tier, spot, extra)
    local source = { kind = "node", id = 1, name = "Silberblatt", category = "herb", chance = 0.9, average = 1, hits = 9, attempts = 10, tier = tier, spot = spot }
    for key, value in pairs(extra or {}) do source[key] = value end
    return source
end

test("Tooltip: Symbole für Beute, Berufe und übrige Knoten", function()
    local GT = setup()
    local P = "Interface\\Icons\\"
    eq(GT:SourceIcon({ kind = "npc", mode = "loot" }), P .. "INV_Misc_Bag_10", "Beutel")
    eq(GT:SourceIcon({ kind = "npc", mode = "skinning" }), P .. "INV_Misc_Pelt_Wolf_01", "Kürschnern")
    eq(GT:SourceIcon({ kind = "node", category = "herb" }), P .. "Trade_Herbalism", "Kräuter")
    eq(GT:SourceIcon({ kind = "node", category = "ore" }), P .. "Trade_Mining", "Bergbau")
    eq(GT:SourceIcon({ kind = "node", category = "gas" }), P .. "INV_Misc_QuestionMark", "andere Knoten")
    eq(GT:SourceIcon({ kind = "node" }), P .. "INV_Misc_QuestionMark", "ohne Kategorie")
end)

test("Tooltip: Stufe 1 zeigt Koordinaten und Entfernung des Ortes", function()
    local GT = setup()
    local list = GT:LocationList(Source(1, Here(0.412, 0.568, 120.4)))
    eq(#list, 1, "ein Eintrag")
    eq(list[1].coords, "41, 57", "Koordinaten")
    eq(list[1].distance, 120, "Entfernung")
    eq(list[1].zone, "Elwynn", "Zone des eigenen Ortes")
    eq(list[1].here, true, "hier")
    eq(list[1].tag, nil, "kein Anbieter")

    GT.db.profile.showDistance = false
    local one = GT:LocationList(Source(1, Here(0.412, 0.568, 120)))[1]
    eq(one.coords, "41, 57", "ohne Entfernung")
    eq(one.distance, nil, "Entfernung aus")

    GT.db.profile.showCoords = false
    local bare = GT:LocationList(Source(1, Here(0.412, 0.568, 120)))[1]
    eq(bare.coords, nil, "ohne Koordinaten")
    eq(bare.zone, "Elwynn", "die Zone bleibt")

    GT.db.profile.showDistance, GT.db.profile.showCoords = true, true
    local unknown = GT:LocationList(Source(1, Here(0.1, 0.2, nil)))[1]
    eq(unknown.coords, "10, 20", "nur Koordinaten")
    eq(unknown.distance, nil, "keine Entfernung")
end)

test("Tooltip: in der eigenen Instanz steht nur der Name mit Markierung", function()
    local GT = setup()
    local entry = GT:LocationList(Source(1, { instance = 36, name = "Todesminen", here = true, source = "own", tier = 1 }))[1]
    eq(entry.zone, "Todesminen", "Name der Instanz")
    eq(entry.here, true, "hier")
    eq(entry.coords, nil, "keine Koordinaten")
end)

test("Tooltip: Stufe 2 zeigt Zone und Entfernung", function()
    local GT = setup()
    local entry = GT:LocationList(Source(2, Zone(14, 2300.4)))[1]
    eq(entry.zone, "Dunkelküste", "Zone")
    eq(entry.distance, 2300, "Entfernung")
    eq(entry.coords, nil, "keine Koordinaten in anderen Zonen")

    eq(GT:LocationList(Source(2, Zone(14, nil)))[1].distance, nil, "Entfernung unbekannt")
    GT.db.profile.showDistance = false
    eq(GT:LocationList(Source(2, Zone(14, 2300)))[1].distance, nil, "Entfernung aus")
end)

test("Tooltip: Stufe 3 zeigt nur die Zone oder Instanz", function()
    local GT = setup()
    local zone = GT:LocationList(Source(3, Other(10)))[1]
    eq(zone.zone, "Düsterwald", "Zone")
    eq(zone.distance, nil, "ohne Entfernung")
    eq(GT:LocationList(Source(3, { instance = 36, name = "Todesminen", source = "own", tier = 3 }))[1].zone, "Todesminen", "Instanz")

    -- Name unbekannt
    eq(GT:LocationList(Source(3, Other(99)))[1].zone, "Map 99", "Karte ohne Namen")
    eq(GT:LocationList(Source(3, { instance = 7, source = "own", tier = 3 }))[1].zone, "Instance 7", "Instanz ohne Namen")
end)

test("Tooltip: Orte anderer Addons tragen deren Namen", function()
    local GT = setup()
    eq(GT:LocationList(Source(2, Zone(14, 900, "GatherMate2")))[1].tag, "GatherMate2", "Zone")
    eq(GT:LocationList(Source(1, Here(0.3, 0.4, 80, "GatherMate2")))[1].tag, "GatherMate2", "Koordinaten")
    eq(GT:LocationList(Source(1, Here(0.3, 0.4, 80)))[1].tag, nil, "eigene Orte ohne Zusatz")
end)

test("Tooltip: ohne Ort, Option aus oder Stufe 4 gibt es keinen Eintrag", function()
    local GT = setup()
    eq(#GT:LocationList(Source(4, nil)), 0, "Stufe 4")
    eq(#GT:LocationList(Source(2, nil)), 0, "ohne Ort")

    GT.db.profile.showLocations = false
    eq(#GT:LocationList(Source(2, Zone(14, 900))), 0, "Option aus")
end)

local BLUE, YELLOW, WHITE, GREY = "|cff66ccff", "|cffffff78", "|cffffffff", "|cff999999"
local SEP = GREY .. " - |r"
local HERE = "|TInterface\\AddOns\\Glimpse_GatheringTooltip\\Media\\Markers\\pinsolid_blue.tga:11|t "

test("Tooltip: Fundort wird mit Farben formatiert", function()
    local GT = setup()
    eq(GT:FormatCoords({ coords = "41, 57" }), YELLOW .. "(41, 57)|r", "Koordinaten gelb in Klammern")
    eq(GT:FormatCoords({ zone = "Elwynn" }), nil, "ohne Koordinaten")
    eq(GT:FormatPlace({ zone = "Dunkelküste", distance = 1200, tag = "GatherMate2" }),
        BLUE .. "(|r" .. BLUE .. "Dunkelküste|r" .. SEP .. WHITE .. "1200 yd|r" .. SEP .. GREY .. "GatherMate2|r" .. BLUE .. ")|r",
        "Zone blau, Entfernung weiß, Anbieter grau")
    eq(GT:FormatPlace({ zone = "Elwynn", here = true }):sub(1, #HERE), HERE, "eigener Ort mit Markierung")
end)

test("Tooltip: Gruppen für die Anzeige ohne Symbole", function()
    local GT = setup()
    local key, title = GT:SourceGroup({ kind = "node", category = "herb" })
    eq(key, "herb", "Schlüssel")
    eq(title, "Herbalism", "Überschrift")
    eq(select(2, GT:SourceGroup({ kind = "node", category = "ore" })), "Mining", "Bergbau")
    eq(select(2, GT:SourceGroup({ kind = "node", category = "gas" })), "Gathering", "übrige Knoten")
    eq(select(2, GT:SourceGroup({ kind = "npc", mode = "loot" })), "Loot", "Beute")
    eq(select(2, GT:SourceGroup({ kind = "npc", mode = "skinning" })), "Skinning", "Kürschnern")
end)

-- Zeilen des Material-Tooltips: Tooltip.lua mit abgefangenem Provider
local function itemRows(GT, sources, maxSources)
    _G.C_Item = {}
    _G.Enum.TooltipDataType = { Object = 1, Unit = 2, Item = 3 }
    local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
    function Glimpse:ModifiersHeld() return true end
    GT.IsLearned = function() return true end
    GT.db.profile.showItemSource, GT.db.profile.minAttempts = true, 1
    GT.db.profile.maxSources = maxSources or GT.db.profile.maxSources or 3
    GT.data.GetLocatedItemSources = function(_, _, attempts, separate, minChance)
        GT.lastCall = { attempts = attempts, separate = separate, minChance = minChance }
        return sources
    end

    local callbacks = {}
    function GT:RegisterTooltipLine(kind, func) callbacks[kind] = func end
    stub.load("Glimpse_GatheringTooltip/Core/Tooltip/Tooltip.lua", "Glimpse_GatheringTooltip")
    GT:RegisterTooltips()
    return callbacks[3](GT, { id = 100 }, {})
end

local function plain(text)
    -- ohne Farbcodes, und ein Zeichen zählt einmal (die Umlaute sind in UTF-8 zwei Bytes)
    return (text:gsub("|c" .. string.rep("%x", 8), ""):gsub("|r", ""):gsub("[\128-\191]", ""))
end

test("Tooltip: Quellzeile mit Symbol, Name und Fundort in einer Zeile", function()
    local GT = setup({ minChance = 15 })
    local rows = itemRows(GT, {
        Source(1, Here(0.412, 0.568, 120)),
        Source(2, Zone(14, 2300), { id = 2, kind = "npc", name = "Waldwolf", mode = "skinning", level = 12, chance = 0.42, category = nil }),
    })
    eq(#rows, 3, "Überschrift und zwei Quellen")
    eq(rows[1][1]:find("Places", 1, true) ~= nil, true, "Überschrift")
    eq(rows[2][1]:find("Silberblatt", 1, true) == 1, true, "Name zuerst")
    eq(rows[2][1]:find(GT:FormatCoords({ coords = "41, 57" }) .. " " .. GT:FormatPlace({ zone = "Elwynn", distance = 120, here = true }), 1, true) ~= nil, false, "Spalten statt eines Textes")
    eq(rows[2][1]:find(GT:FormatCoords({ coords = "41, 57" }), 1, true) ~= nil, true, "Koordinaten")
    eq(rows[2][1]:find(GT:FormatPlace({ zone = "Elwynn", distance = 120, here = true }), 1, true) ~= nil, true, "eigener Ort")
    eq(rows[2].icon, "Interface\\Icons\\Trade_Herbalism", "Symbol")
    eq(rows[2][2]:find("90 \x25\x25") ~= nil, true, "Chance")
    eq(rows[3][1]:find("Level 12", 1, true) ~= nil, true, "Kreatur mit Stufe")
    eq(rows[3][1]:find("Skinning", 1, true), nil, "Art steht im Symbol")
    eq(rows[3][1]:find(GT:FormatPlace({ zone = "Dunkelküste", distance = 2300 }), 1, true) ~= nil, true, "Zone und Entfernung")
    eq(rows[3].icon, "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", "Pelz")

    -- die Mindestchance und die Trennung gehen an GatheringDB (Prozent in Bruchteile)
    near(GT.lastCall.minChance, 0.15, "Mindestchance")
    eq(GT.lastCall.separate, nil, "Trennung (Standard des Profils)")
end)

test("Tooltip: Treffer und Versuche hinter der Chance", function()
    local GT = setup()
    local rows = itemRows(GT, { Source(1, Here(0.4, 0.5, 10), { chance = 13 / 14, hits = 13, attempts = 14 }) })
    eq(rows[2][2], "93 %  |cff999999(13/14)|r  |cff999999Avg. 1.0|r", "Chance, Treffer/Versuche, Menge")

    GT.db.profile.showAttempts = false
    rows = itemRows(GT, { Source(1, Here(0.4, 0.5, 10), { chance = 13 / 14, hits = 13, attempts = 14 }) })
    eq(rows[2][2], "93 %  |cff999999Avg. 1.0|r", "ohne Versuche")
end)

test("Tooltip: Orte nur aus anderen Addons zeigen keine Chance", function()
    local GT = setup()
    local rows = itemRows(GT, {
        Source(1, Here(0.4, 0.5, 10)),                                                     -- eigener Fund
        Source(2, Zone(14, 900, "GatherMate2")),                                           -- nur GatherMate2
        Source(2, Zone(14, 950, "GatherMate2"), { spots = { Zone(14, 950, "GatherMate2"), Zone(14, 960) } }), -- auch eigener Ort dabei
        Source(4, nil),                                                                    -- ohne Ort
    }, 4)
    eq(rows[2][2]:find("90 \x25\x25") ~= nil, true, "eigener Fund: Chance")
    eq(rows[3][2], "", "nur GatherMate2: keine Chance")
    eq(rows[4][2]:find("90 \x25\x25") ~= nil, true, "eigener Ort in der Zone: Chance")
    eq(rows[5][2]:find("90 \x25\x25") ~= nil, true, "ohne Ort: Chance")
end)

-- Tooltip eines Knotens oder einer Kreatur: gleiche Zeilen wie bei den Quellen eines Items
local function sourceRows(profile, kind, data)
    local GT = setup(profile)
    local Glimpse = LibStub():GetAddon()
    function Glimpse:ModifiersHeld() return true end
    GT.IsLearned = function() return true end
    GT.db.profile.showNodes, GT.db.profile.showLoot, GT.db.profile.showSkinning = true, true, true
    GT.db.profile.minAttempts, GT.db.profile.maxItems = 1, 5

    local drops = {
        { itemID = 100, hits = 22, attempts = 22, amount = 22, chance = 1, average = 1 },
        { itemID = 101, hits = 11, attempts = 22, amount = 17, chance = 0.5, average = 17 / 11 },
    }
    GT.data.GetNode = function() return { category = "ore" } end
    GT.data.FindNodeIDs = function() return {} end
    GT.data.GetNodeDrops = function() return drops, 22 end
    GT.data.GetNPCDrops = function() return drops, 22 end

    _G.C_Item = {
        GetItemNameByID = function(id) return "Item" .. id end,
        GetItemQualityByID = function() return 1 end,
        RequestLoadItemDataByID = function() end,
        GetItemInfoInstant = function() return 0, "", "", "", "icon" end,
    }
    _G.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } }
    _G.Enum.TooltipDataType = { Object = 1, Unit = 2, Item = 3 }

    local callbacks = {}
    function GT:RegisterTooltipLine(k, func) callbacks[k] = func end
    GT.NodeSkillRow, GT.UnitSkillRow = function() end, function() end -- die Skill-Zeilen testet test_skills.lua
    stub.load("Glimpse_GatheringTooltip/Core/Tooltip/Tooltip.lua", "Glimpse_GatheringTooltip")
    GT:RegisterTooltips()
    return callbacks[kind == "node" and 1 or 2](GT, data, {})
end

test("Tooltip: Knoten zeigt Treffer/Versuche wie die Quellen eines Items, ohne Zahl in der Überschrift", function()
    local rows = sourceRows({}, "node", { guid = "GameObject-0-1-2-3-1731-0000A5C2B1" })
    eq(plain(rows[1][1]), "Gathered", "Überschrift ohne Versuche")
    eq(rows[2][2], "100 %  |cff999999(22/22)|r  |cff999999Avg. 1.0|r", "Kupfererz")
    eq(rows[3][2], "50 %  |cff999999(11/22)|r  |cff999999Avg. 1.5|r", "Rauer Stein")
    eq(rows[2].icon, "icon", "Item-Symbol")
end)

test("Tooltip: Kreatur zeigt Treffer/Versuche je Zeile", function()
    local rows = sourceRows({}, "npc", { guid = "Creature-0-1-2-3-179891-0000A5C2B1" })
    eq(plain(rows[1][1]), "Loot", "Überschrift")
    eq(rows[3][2]:find("(11/22)", 1, true) ~= nil, true, "Treffer/Versuche")
end)

test("Tooltip: ohne Option Versuche anzeigen steht die Zahl in der Überschrift", function()
    local rows = sourceRows({ showAttempts = false }, "node", { guid = "GameObject-0-1-2-3-1731-0000A5C2B1" })
    eq(plain(rows[1][1]), "Gathered  22 attempts", "Versuche in der Überschrift")
    eq(rows[3][2], "50 %  |cff999999Avg. 1.5|r", "Zeile ohne Treffer/Versuche")
end)

test("Tooltip: nur so viele Orte wie eingestellt", function()
    local GT = setup()
    local sources = {}
    for id = 1, 5 do sources[id] = Source(1, Here(0.1 * id, 0.2, 10 * id), { id = id, name = "Q" .. id }) end
    eq(#itemRows(GT, sources, 2), 3, "Überschrift und zwei Zeilen")
    eq(#itemRows(GT, sources, 5), 6, "alle fünf")
    eq(#itemRows(GT, { sources[1] }, 3), 2, "eine Quelle: eine Zeile")
    eq(itemRows(GT, { sources[1] }, 3)[1][1]:find("Best place", 1, true) ~= nil, true, "Überschrift bei einem Ort")
end)

test("Tooltip: fehlende Koordinaten lassen die Spalte frei", function()
    local GT = setup()
    local rows = itemRows(GT, {
        Source(1, Here(0.412, 0.568, 120), { id = 1, name = "Silberblatt" }),
        Source(2, Zone(14, 2300), { id = 2, kind = "npc", name = "Waldwolf", mode = "skinning", level = 12, chance = 0.42 }),
    })
    eq(#rows, 3, "Überschrift und zwei Quellen")
    local silver, wolf = plain(rows[2][1]), plain(rows[3][1])

    -- Name, Abstand, Koordinaten, Abstand, (Markierung), Ort
    local coordStart = #"Waldwolf (Level 12)" + 8 + 1
    eq(silver:find("(41, 57)", 1, true), coordStart, "Koordinaten")
    eq(silver:find("(Elwynn", 1, true) ~= nil, true, "eigener Ort mit Namen")
    eq(wolf:find(plain("(Dunkelküste"), 1, true) > coordStart + #"(41, 57)", true, "Ort steht hinter der Koordinatenspalte")
    eq(wolf:sub(coordStart, coordStart + 7), string.rep(" ", 8), "Platzhalter statt Koordinaten")
end)

test("Tooltip: ohne Koordinaten gibt es keine Lücke vor den Zonen", function()
    local GT = setup()
    local rows = itemRows(GT, {
        Source(2, Zone(14, 2300), { id = 2, kind = "npc", name = "Waldwolf", mode = "skinning", chance = 0.8 }),
        Source(3, Other(10), { id = 3, kind = "npc", name = "Bär", mode = "loot", chance = 0.7 }),
    })
    local wolf, bear = plain(rows[2][1]), plain(rows[3][1])
    eq(wolf:find(plain("(Dunkelküste"), 1, true), #"Waldwolf" + 8 + 1, "Zone direkt hinter dem Namen")
    eq(bear:find(plain("(Düsterwald"), 1, true), #"Waldwolf" + 8 + 1, "gleiche Spalte")
end)

test("Tooltip: dieselbe Quelle in mehreren Zonen steht in mehreren Zeilen", function()
    local GT = setup()
    local rows = itemRows(GT, {
        Source(1, Here(0.412, 0.568, 120), { id = 1, name = "Silberblatt" }),
        Source(2, Zone(14, 2300), { id = 1, name = "Silberblatt" }),
        Source(2, Zone(10, 3100), { id = 1, name = "Silberblatt" }),
    })
    eq(#rows, 4, "Überschrift und drei Orte")
    eq(rows[2][1]:find("41, 57", 1, true) ~= nil, true, "eigene Zone")
    eq(rows[3][1]:find("Dunkelküste", 1, true) ~= nil, true, "zweite Zone")
    eq(rows[4][1]:find("Düsterwald", 1, true) ~= nil, true, "dritte Zone")
    for index = 2, 4 do eq(rows[index][1]:find("Silberblatt", 1, true) == 1, true, "jede Zeile nennt die Quelle") end
end)

test("Tooltip: Quellen ohne Ort haben keine Klammer", function()
    local GT = setup()
    local rows = itemRows(GT, { Source(4, nil, { name = "Unbekannt" }) })
    eq(rows[2][1], "Unbekannt", "nur der Name")
end)

test("Tooltip: ohne Symbole stehen die Quellen unter Überschriften für Beute und Berufe", function()
    local GT = setup({ showSourceIcons = false })
    local rows = itemRows(GT, {
        Source(1, Here(0.4, 0.5, 10), { id = 1, name = "Silberblatt", chance = 0.9 }),
        Source(1, Here(0.5, 0.5, 20), { id = 2, kind = "npc", name = "Waldwolf", mode = "skinning", chance = 0.8 }),
        Source(2, Zone(14, 900), { id = 5, name = "Friedensblume", chance = 0.7 }),
        Source(4, nil, { id = 3, kind = "npc", name = "Bär", mode = "loot", chance = 0.2 }),
    }, 4)
    eq(#rows, 8, "Titel, drei Überschriften, vier Quellen")
    eq(rows[2][1]:find("Herbalism", 1, true) ~= nil, true, "Kräuterkunde zuerst")
    eq(rows[3][1]:find("Silberblatt", 1, true) == 1, true, "Silberblatt")
    eq(rows[4][1]:find("Friedensblume", 1, true) == 1, true, "zweites Kraut in derselben Gruppe")
    eq(rows[5][1]:find("Skinning", 1, true) ~= nil, true, "Kürschnern")
    eq(rows[6][1]:find("Waldwolf", 1, true) == 1, true, "Waldwolf")
    eq(rows[7][1]:find("Loot", 1, true) ~= nil, true, "Beute")
    eq(rows[8][1], "Bär", "Bär")
    eq(rows[3].icon, nil, "kein Symbol")
end)

test("Tooltip: Tooltip.lua lässt sich laden", function()
    local GT = setup()
    GT.IsLearned = function() return true end
    _G.C_Item = {}
    stub.load("Glimpse_GatheringTooltip/Core/Tooltip/Tooltip.lua", "Glimpse_GatheringTooltip")
    eq(type(GT.RegisterTooltips), "function", "RegisterTooltips")
end)

test("Tooltip: Markierung des eigenen Ortes ist wählbar", function()
    local GT = setup()
    eq(GT:HereIcon():find("Markers\\pinsolid_blue.tga", 1, true) ~= nil, true, "Standard: blaue volle Nadel")
    GT.db.profile.hereIcon, GT.db.profile.hereColor = "arrow", "red"
    eq(GT:HereIcon():find("arrow_red.tga:10", 1, true) ~= nil, true, "roter Pfeil mit eigener Höhe")
    GT.db.profile.hereIcon, GT.db.profile.hereColor = "gibt es nicht", "gibt es nicht"
    eq(GT:HereIcon():find("pinsolid_blue.tga", 1, true) ~= nil, true, "unbekannte Werte fallen auf den Standard zurück")
    GT.db.profile.showHereIcon = false
    eq(GT:HereIcon(), "", "keine Markierung")
    eq(GT:FormatPlace({ zone = "Elwynn", here = true }):find("|T", 1, true), nil, "ohne Symbol im Text")
end)

test("Tooltip: zu jedem Symbol und jeder Farbe gibt es eine Datei", function()
    local GT = setup()
    eq(#GT.MarkerIcons <= 5, true, "höchstens fünf Symbole")
    for _, icon in ipairs(GT.MarkerIcons) do
        for _, color in ipairs(GT.MarkerColors) do
            local f = io.open("Glimpse_GatheringTooltip/Media/Markers/" .. icon.key .. "_" .. color .. ".tga", "rb")
            eq(f ~= nil, true, icon.key .. "_" .. color)
            if f then f:close() end
        end
    end
end)

test("Tooltip: Optionen für die Markierung lassen sich bauen", function()
    local GT = setup()
    local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
    local refreshed = 0
    function GT:RefreshTooltip() refreshed = refreshed + 1 end
    local realLibStub = _G.LibStub
    _G.LibStub = function(name)
        if name == "AceConfigRegistry-3.0" then return { NotifyChange = function() end } end
        return realLibStub(name)
    end
    stub.load("Glimpse_GatheringTooltip/Core/Options.lua", "Glimpse_GatheringTooltip")
    Glimpse.name = Glimpse.name or "Glimpse"
    local group = GT:BuildMarkerOptions()
    eq(group.inline, true, "Gruppe")

    local pin, arrow = group.args.icon_pinsolid, group.args.icon_arrow
    eq(pin.image():find("pinsolid_blue.tga", 1, true) ~= nil, true, "Symbol in der gewählten Farbe")
    eq(pin.name():find("|cffffd100", 1, true) ~= nil, true, "gewähltes Symbol hervorgehoben")
    eq(arrow.name():find("|cffffd100", 1, true), nil, "anderes nicht")

    arrow.func()
    eq(GT.db.profile.hereIcon, "arrow", "Klick wählt das Symbol")
    eq(refreshed, 1, "Tooltip aktualisiert")
    eq(group.args.color.values().red:find("arrow_red.tga", 1, true) ~= nil, true, "Farbauswahl zeigt das gewählte Symbol")
    group.args.color.set(nil, "green")
    eq(GT.db.profile.hereColor, "green", "Farbe")
    _G.LibStub = realLibStub
end)

test("Tooltip: Fundort-Optionen stehen in einer Gruppe mit zwei Haken je Reihe", function()
    local GT = setup()
    local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
    function GT:RefreshTooltip() end
    GT.data = {}
    function Glimpse:BuildModifierOptions() return {} end
    local realLibStub = _G.LibStub
    _G.LibStub = function(name)
        if name == "AceConfigRegistry-3.0" then return { NotifyChange = function() end } end
        return realLibStub(name)
    end
    Glimpse.name = Glimpse.name or "Glimpse"
    stub.load("Glimpse_GatheringTooltip/Core/Options.lua", "Glimpse_GatheringTooltip")
    local options = GT:BuildOptions()
    _G.LibStub = realLibStub

    local items = options.items.args
    eq(items.display.inline, true, "Gruppe Darstellung")
    for _, key in ipairs({ "showLocations", "showCoords", "showDistance", "showAttempts" }) do
        eq(items.display.args[key] ~= nil, true, key .. " in der Gruppe")
        eq(items.display.args[key].width, "relative", key .. " Anteil der Breite")
        eq(items.display.args[key].relWidth, 0.49, key .. " halbe Breite")
        eq(items[key], nil, key .. " nicht mehr einzeln")
    end
end)

test("Tooltip: Entfernung kommt aus dem Kern", function()
    local GT = setup()
    local Locations = LibStub("AceAddon-3.0"):GetAddon("Glimpse"):GetModule("Locations")
    eq(GT:FormatDistance(120), "120 yd", "Yards")
    eq(GT:FormatDistance(2300), "1.3 mi", "Einheit des Kerns")
    function Locations:FormatDistance(yards) return "[" .. yards .. "]" end
    eq(GT:FormatDistance(120), "[120]", "Format des Kerns")
    eq(GT:FormatPlace({ zone = "Elwynn", distance = 3690 }):find("[3690]", 1, true) ~= nil, true, "im Ort")
end)

test("Tooltip: Wegpunkt per Taste zum besten Fundort", function()
    local GT = setup({ showWaypointHint = true })
    local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
    local Locations = Glimpse:GetModule("Locations")
    local printed, set = {}, nil
    function Glimpse:Print(text) printed[#printed + 1] = text end
    function Locations:SetWaypoint(map, x, y, title) set = { map, x, y, title }; return true end

    eq(GT:SetWaypointTarget({ instance = 36 }, "Erz"), false, "Instanz hat keine Koordinaten")
    eq(GT:HasWaypointTarget(), false, "kein Ziel")
    eq(GT:WaypointHint(), nil, "ohne Ziel kein Hinweis")

    eq(GT:SetWaypointTarget({ map = 37, x = 0.4, y = 0.6 }, "Silberblatt"), true, "Ziel gesetzt")
    eq(GT:WaypointHint():find("Ctrl+G: set waypoint", 1, true) ~= nil, true, "Hinweis mit Taste")
    eq(GT:WaypointHint():find("TomTom", 1, true), nil, "ohne TomTom kein Zusatz")
    _G.TomTom = { AddWaypoint = function() end }
    eq(GT:WaypointHint():find("(TomTom)", 1, true) ~= nil, true, "mit TomTom: Zusatz im Hinweis")
    _G.TomTom = nil

    -- Taste: nur die gewählte Kombination löst aus
    local listener = stub.frames[#stub.frames]
    stub.keys.ctrl = true
    listener.onEvent(listener, "H")
    eq(set, nil, "andere Taste löst nichts aus")
    stub.keys.ctrl = false
    listener.onEvent(listener, "G")
    eq(set, nil, "ohne Strg nichts")
    stub.keys.ctrl = true
    listener.onEvent(listener, "G")
    eq(set[1], 37, "Karte") eq(set[4], "Silberblatt - Elwynn", "Titel mit Zone")
    eq(printed[1]:find("Elwynn", 1, true) ~= nil, true, "Meldung")

    GT.db.profile.waypointKey = "off"
    eq(GT:HasWaypointTarget(), false, "aus")
    eq(GT:WaypointHint(), nil, "aus: kein Hinweis")
    GT.db.profile.waypointKey = "CTRL-G"
    GT:SetWaypointTarget(nil)
    eq(GT:SetWaypoint(), false, "ohne Ziel nichts")

    function Locations:SetWaypoint() return false end
    GT:SetWaypointTarget({ map = 37, x = 0.4, y = 0.6 }, "Silberblatt")
    eq(GT:SetWaypoint(), false, "nicht möglich")
    eq(printed[#printed]:find("No waypoint possible", 1, true) ~= nil, true, "Meldung")
end)

test("Tooltip: Hinweiszeile am Ende des Materialtooltips", function()
    local GT = setup({ showWaypointHint = true })
    local rows = itemRows(GT, { Source(1, Here(0.4, 0.5, 10)) })
    eq(rows[#rows][1]:find("Ctrl+G: set waypoint", 1, true) ~= nil, true, "Hinweis")
    eq(GT:HasWaypointTarget(), true, "Ziel gesetzt")

    GT.db.profile.showWaypointHint = false
    rows = itemRows(GT, { Source(1, Here(0.4, 0.5, 10)) })
    eq(#rows, 2, "ohne Hinweis")

    itemRows(GT, { Source(1, { instance = 36, name = "Minen", count = 1, source = "own", tier = 1 }) })
    eq(GT:HasWaypointTarget(), false, "Instanz: kein Ziel")
end)

test("Tooltip: Wegpunkt-Taste einstellen und auf Belegung prüfen", function()
    local GT = setup()
    eq(GT:WaypointKeyName("CTRL-G"), "Ctrl+G", "Name")
    eq(GT:WaypointKeyName("ALT-CTRL-SHIFT-F5"), "Ctrl+Shift+Alt+F5", "alle drei Umschalter")
    eq(GT:WaypointKeyName("off"), "Off", "aus")

    -- Belegung des Spiels: Strg+W ist belegt
    _G.GetBindingAction = function(chord) return chord == "CTRL-W" and "MOVEFORWARD" or "" end
    _G.BINDING_NAME_MOVEFORWARD = "Move Forward"
    eq(GT:FindBindingConflict("CTRL-W"), "Move Forward", "belegt")
    eq(GT:FindBindingConflict("CTRL-G"), nil, "frei")

    local ok, conflict = GT:SetWaypointKey("CTRL-W")
    eq(ok, false, "belegte Kombination wird abgelehnt") eq(conflict, "Move Forward", "Name der Belegung")
    eq(GT.db.profile.waypointKey, "CTRL-G", "alte Taste bleibt")
    eq(GT:SetWaypointKey("ALT-CTRL-SHIFT-H"), true, "freie Kombination")
    eq(GT.db.profile.waypointKey, "ALT-CTRL-SHIFT-H", "gespeichert")
    eq(GT:SetWaypointKey("off"), true, "aus")
    _G.GetBindingAction, _G.BINDING_NAME_MOVEFORWARD = nil, nil
end)

test("Tooltip: Tastenabfrage nimmt die gedrückte Kombination auf", function()
    local GT = setup()
    local got = {}
    local function result(chord) got[#got + 1] = chord == nil and "abgebrochen" or chord end

    GT:CaptureKey(result)
    eq(GT:IsCapturingKey(), true, "wartet")
    local frame = stub.frames[#stub.frames]
    frame.onEvent(frame, "LSHIFT")
    eq(#got, 0, "ein Umschalter allein zählt nicht")
    stub.keys.ctrl, stub.keys.shift, stub.keys.alt = true, true, true
    frame.onEvent(frame, "K")
    eq(got[1], "ALT-CTRL-SHIFT-K", "Kombination in der Schreibweise des Spiels")
    eq(GT:IsCapturingKey(), false, "fertig")

    stub.keys.ctrl, stub.keys.shift, stub.keys.alt = false, false, false
    GT:CaptureKey(result) frame.onEvent(frame, "ESCAPE")
    eq(got[2], "abgebrochen", "Escape bricht ab")
    GT:CaptureKey(result) frame.onEvent(frame, "DELETE")
    eq(got[3], "off", "Entf schaltet aus")
end)

test("Tooltip: belegte Taste wird auch über die Liste aller Belegungen gefunden, Meldung als Fehlerfenster", function()
    local GT = setup()
    -- GetBindingAction kennt die Taste nicht (Sondertaste), die Liste der Belegungen schon
    _G.GetBindingAction = function() return "" end
    local bindings = { { "TOGGLESHEATH", "Misc", "Ü", nil }, { "JUMP", "Movement", "SPACE", "ALT-SPACE" } }
    _G.GetNumBindings = function() return #bindings end
    _G.GetBinding = function(i) return (table.unpack or unpack)(bindings[i], 1, 4) end
    _G.BINDING_NAME_TOGGLESHEATH = "Sheath"
    eq(GT:FindBindingConflict("Ü"), "Sheath", "Taste Ü belegt")
    eq(GT:FindBindingConflict("ALT-SPACE"), "Jump" == nil and "" or "JUMP", "zweite Belegung ohne Namen: Befehl")
    eq(GT:FindBindingConflict("CTRL-G"), nil, "frei")

    local shown
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, text) shown = { which, text } end
    local ok, conflict = GT:SetWaypointKey("Ü")
    eq(ok, false, "abgelehnt")
    GT:ShowKeyInUse("Ü", conflict)
    eq(shown[2]:find("Ü", 1, true) ~= nil and shown[2]:find("Sheath", 1, true) ~= nil, true, "Fehlerfenster nennt Taste und Belegung")
    eq(StaticPopupDialogs.GLIMPSE_GATHERINGTOOLTIP_KEY_IN_USE ~= nil, true, "Dialog angelegt")
    _G.GetBindingAction, _G.GetNumBindings, _G.GetBinding, _G.StaticPopupDialogs, _G.StaticPopup_Show = nil, nil, nil, nil, nil
end)

test("Tooltip: jedes Markierungs-Symbol hat einen Bildnachweis", function()
    local GT = setup()
    local credited = {}
    for _, credit in ipairs(GT.IconCredits) do
        eq(credit.author ~= nil and credit.url:find("^https://www.flaticon.com/") ~= nil, true, credit.key .. ": Autor und Link")
        credited[credit.key] = true
    end
    for _, icon in ipairs(GT.MarkerIcons) do eq(credited[icon.key], true, icon.key .. " hat einen Nachweis") end
end)

test("Tooltip: Bildnachweis für die Credits der Optionsseite", function()
    local GT = setup()
    stub.load("Glimpse_GatheringTooltip/Core/Options.lua", "Glimpse_GatheringTooltip")
    local credits = GT:BuildCredits()
    eq(#credits.images, #GT.IconCredits, "ein Eintrag je Symbol")
    eq(credits.images[1]:find("Karacis |cff66ccff(", 1, true) ~= nil, true, "Autor und Flaticon")
    eq(credits.images[1]:find("|cff66ccff(https://www.flaticon.com/", 1, true) ~= nil, true, "Link blau in Klammern")
    eq(credits.images[1]:sub(-3), ")|r", "Klammer und Farbe geschlossen")
end)

test("Waypoint: im Kampf wird die Tastaturabfrage nicht angefasst (geschützte Aufrufe)", function()
    local GT = setup()
    local calls = {}
    GT:SetWaypointTarget({ map = 37, x = 0.4, y = 0.6 }, "Silberblatt") -- legt die Abfrage an
    local listener = stub.frames[#stub.frames]
    function listener:EnableKeyboard(on) calls[#calls + 1] = "keyboard:" .. tostring(on) end
    function listener:SetPropagateKeyboardInput(on) calls[#calls + 1] = "propagate:" .. tostring(on) end

    _G.InCombatLockdown = function() return true end
    GT:SetWaypointTarget(nil)
    GT:SetWaypointTarget({ map = 37, x = 0.4, y = 0.6 }, "Silberblatt")
    eq(#calls, 0, "im Kampf keine Aufrufe")

    _G.InCombatLockdown = function() return false end
    GT:UpdateWaypointListener() -- PLAYER_REGEN_ENABLED
    eq(calls[1], "keyboard:true", "nach dem Kampf nachgestellt")
    _G.InCombatLockdown = nil
end)
