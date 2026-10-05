-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Symbole und Ortszeilen im Tooltip eines Handwerksmaterials (GatheringTooltip/Tooltip/Sources.lua)
local function setup(profile)
    local Glimpse = stub.newGlimpse()
    local GT = Glimpse:NewModule("GatheringTooltip")
    GT.L = Glimpse.L
    GT.db = { profile = { locationLines = "nearest", showCoords = true, showDistance = true, showSourceIcons = true } }
    for key, value in pairs(profile or {}) do GT.db.profile[key] = value end
    GT.data = { GetMapName = function(_, map) return ({ [37] = "Elwynn", [14] = "Dunkelküste", [10] = "Düsterwald" })[map] end }
    stub.load("Glimpse_GatheringTooltip/Tooltip/Sources.lua", "Glimpse_GatheringTooltip")
    return GT
end

local function Near(map, x, y, yards, source)
    return { map = map, x = x, y = y, count = 3, source = source or "own", mapDistance = 0.01, distance = yards }
end
local function Far(map, source)
    return { map = map, x = 0.5, y = 0.5, count = 3, source = source or "own" }
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

local BLUE, YELLOW = "|cff66ccff", "|cffffff78"

test("Tooltip: eigenes Gebiet zeigt den nächsten Ort mit Koordinaten und Entfernung", function()
    local GT = setup()
    local list = GT:LocationList({ area = "here", spots = { Near(37, 0.412, 0.568, 120.4), Near(37, 0.7, 0.2, 400) } })
    eq(#list, 1, "nur der nächste Ort, es ist ja dieselbe Zone")
    eq(list[1].coords, "41, 57", "Koordinaten")
    eq(list[1].distance, 120, "Entfernung")
    eq(list[1].zone, nil, "keine Zone")
    eq(list[1].more, nil, "keine weiteren Zonen")

    GT.db.profile.locationLines = "several"
    eq(#GT:LocationList({ area = "here", spots = { Near(37, 0.412, 0.568, 120), Near(37, 0.7, 0.2, 400) } }), 1, "gleiche Zone: auch bei mehreren nur einer")
    GT.db.profile.locationLines = "nearest"

    GT.db.profile.showDistance = false
    local one = GT:LocationList({ area = "here", spots = { Near(37, 0.412, 0.568, 120) } })[1]
    eq(one.coords, "41, 57", "ohne Entfernung")
    eq(one.distance, nil, "Entfernung aus")
    GT.db.profile.showCoords = false
    eq(#GT:LocationList({ area = "here", spots = { Near(37, 0.412, 0.568, 120) } }), 0, "ohne beides kein Eintrag")

    -- Entfernung unbekannt
    GT.db.profile.showDistance, GT.db.profile.showCoords = true, true
    local unknown = GT:LocationList({ area = "here", spots = { Near(37, 0.1, 0.2, nil) } })[1]
    eq(unknown.coords, "10, 20", "nur Koordinaten")
    eq(unknown.distance, nil, "keine Entfernung")
end)

test("Tooltip: in der eigenen Instanz entfällt der Fundort", function()
    local GT = setup()
    eq(#GT:LocationList({ area = "here", spots = { { instance = 36, name = "Todesminen", here = true, source = "own" } } }), 0, "kein Eintrag")
end)

test("Tooltip: mehrere Orte nur bei verschiedenen Zonen", function()
    local GT = setup()
    local source = { area = "elsewhere", spots = { Far(14), Far(14), Far(10), { instance = 36, name = "Todesminen", source = "own" } } }
    local list = GT:LocationList(source)
    eq(#list, 1, "nächster Ort")
    eq(list[1].zone, "Dunkelküste", "erste Zone")
    eq(list[1].more, 2, "zwei weitere Zonen (die doppelte zählt nicht)")

    GT.db.profile.locationLines = "several"
    list = GT:LocationList(source)
    eq(#list, 3, "drei verschiedene Zonen")
    eq(list[1].zone, "Dunkelküste", "Zone")
    eq(list[2].zone, "Düsterwald", "zweite Zone")
    eq(list[3].zone, "Todesminen", "Instanz")
    eq(list[1].more, nil, "ohne +N")

    source.spots[5], source.spots[6] = Far(11), Far(12)
    eq(#GT:LocationList(source), 3, "höchstens drei")

    -- nur eine Zone: eine Zeile, auch bei mehreren Orten darin
    eq(#GT:LocationList({ area = "elsewhere", spots = { Far(14), Far(14), Far(14) } }), 1, "eine Zone")

    -- Name unbekannt
    GT.db.profile.locationLines = "nearest"
    eq(GT:LocationList({ area = "elsewhere", spots = { Far(99) } })[1].zone, "Map 99", "Karte ohne Namen")
    eq(GT:LocationList({ area = "elsewhere", spots = { { instance = 7, source = "own" } } })[1].zone, "Instance 7", "Instanz ohne Namen")
end)

test("Tooltip: eigenes Gebiet und weitere Zonen zusammen", function()
    local GT = setup()
    local spots = { Near(37, 0.412, 0.568, 120), Near(37, 0.7, 0.2, 400), Far(14), Far(14), Far(10), Far(11) }

    -- nearest: nur der Ort im eigenen Gebiet, mit der Zahl weiterer Zonen
    local list = GT:LocationList({ area = "here", spots = spots })
    eq(#list, 1, "ein Eintrag")
    eq(list[1].coords, "41, 57", "Ort im eigenen Gebiet")
    eq(list[1].more, 3, "drei weitere Zonen")

    -- several: erst das eigene Gebiet, dann andere Zonen, höchstens drei Einträge
    GT.db.profile.locationLines = "several"
    list = GT:LocationList({ area = "here", spots = spots })
    eq(#list, 3, "drei Einträge")
    eq(list[1].coords, "41, 57", "eigenes Gebiet zuerst")
    eq(list[2].zone, "Dunkelküste", "zweiter Eintrag")
    eq(list[3].zone, "Düsterwald", "dritter Eintrag")

    -- Quelle nur mit Orten anderer Addons: gleiches Verhalten
    local external = { area = "external", spots = { Near(37, 0.3, 0.4, 80, "GatherMate2"), Far(14, "GatherMate2") } }
    list = GT:LocationList(external)
    eq(#list, 2, "eigenes Gebiet und eine Zone")
    eq(list[2].zone, "Dunkelküste", "Zone")
    eq(list[2].tag, "GatherMate2", "Anbieter")

    -- in der eigenen Instanz: bei nearest nichts, bei several die anderen Zonen
    local inst = { area = "here", spots = { { instance = 36, name = "Todesminen", here = true, source = "own" }, Far(14) } }
    eq(#GT:LocationList(inst), 1, "several: andere Zone")
    GT.db.profile.locationLines = "nearest"
    eq(#GT:LocationList(inst), 0, "nearest: nichts")
end)

test("Tooltip: Orte anderer Addons tragen deren Namen", function()
    local GT = setup()
    local far = GT:LocationList({ area = "external", spots = { Far(14, "GatherMate2") } })[1]
    eq(far.zone, "Dunkelküste", "andere Zone")
    eq(far.tag, "GatherMate2", "Anbieter")

    local near = GT:LocationList({ area = "external", spots = { Far(14, "GatherMate2"), Near(37, 0.3, 0.4, 80, "GatherMate2") } })[1]
    eq(near.coords, "30, 40", "im eigenen Gebiet vor anderen Gebieten")
    eq(near.distance, 80, "Entfernung")
    eq(near.tag, "GatherMate2", "Anbieter")
end)

test("Tooltip: Fundort wird mit Klammern und Farben formatiert", function()
    local GT = setup()
    eq(GT:FormatLocation({ coords = "41, 57", distance = 120 }),
        BLUE .. "(|r" .. YELLOW .. "41, 57|r" .. BLUE .. " · |r" .. BLUE .. "120 yd|r" .. BLUE .. ")|r", "Koordinaten gelb, Rest blau")
    eq(GT:FormatLocation({ zone = "Dunkelküste", tag = "GatherMate2", more = 2 }),
        BLUE .. "(|r" .. BLUE .. "Dunkelküste|r" .. BLUE .. " · |r" .. BLUE .. "GatherMate2|r" .. BLUE .. "  +2|r" .. BLUE .. ")|r", "Zone mit Anbieter und weiteren Zonen")
end)

test("Tooltip: ohne Orte, aus oder ohne Gebiet gibt es keinen Eintrag", function()
    local GT = setup()
    eq(#GT:LocationList({ area = "none", spots = {} }), 0, "keine Orte")
    eq(#GT:LocationList({ area = "none" }), 0, "ohne spots")
    eq(#GT:LocationList({ area = "none", spots = { Far(14) } }), 0, "Gruppe none")

    GT.db.profile.locationLines = "off"
    eq(#GT:LocationList({ area = "elsewhere", spots = { Far(14) } }), 0, "Option aus")
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

test("Tooltip: Tooltip.lua lässt sich laden", function()
    local GT = setup()
    GT.IsLearned = function() return true end
    _G.C_Item = {}
    stub.load("Glimpse_GatheringTooltip/Tooltip/Tooltip.lua", "Glimpse_GatheringTooltip")
    eq(type(GT.RegisterTooltips), "function", "RegisterTooltips")
end)

-- Zeilen des Material-Tooltips: Tooltip.lua mit abgefangenem Provider
local function itemRows(GT, sources)
    _G.C_Item = {}
    _G.Enum.TooltipDataType = { Object = 1, Unit = 2, Item = 3 }
    local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
    function Glimpse:ModifiersHeld() return true end
    GT.IsLearned = function() return true end
    GT.db.profile.showItemSource, GT.db.profile.minAttempts = true, 1
    GT.db.profile.maxSources = GT.db.profile.maxSources or 2
    GT.data.GetLocatedItemSources = function() return sources end

    local callbacks = {}
    function GT:RegisterTooltipLine(kind, func) callbacks[kind] = func end
    stub.load("Glimpse_GatheringTooltip/Tooltip/Tooltip.lua", "Glimpse_GatheringTooltip")
    GT:RegisterTooltips()
    return callbacks[3](GT, { id = 100 }, {})
end

test("Tooltip: Quellzeile mit Symbol, Name und Fundort in einer Zeile", function()
    local GT = setup()
    local rows = itemRows(GT, {
        { kind = "node", id = 1, name = "Silberblatt", category = "herb", chance = 0.93, average = 1.4, area = "here",
            spots = { Near(37, 0.412, 0.568, 120) } },
        { kind = "npc", id = 2, name = "Waldwolf", mode = "skinning", level = 12, chance = 0.42, average = 1.4, area = "elsewhere",
            spots = { Far(14) } },
    })
    eq(#rows, 3, "Überschrift und zwei Quellen")
    eq(rows[1][1]:find("Sources", 1, true) ~= nil, true, "Überschrift")
    eq(rows[2][1], "Silberblatt " .. GT:FormatLocation({ coords = "41, 57", distance = 120 }), "Name, Fundort")
    eq(rows[2].icon, "Interface\\Icons\\Trade_Herbalism", "Symbol")
    eq(rows[2][2]:find("93 %%") ~= nil, true, "Chance")
    eq(rows[3][1]:find("Waldwolf", 1, true) ~= nil and rows[3][1]:find("Level 12", 1, true) ~= nil, true, "Kreatur mit Stufe")
    eq(rows[3][1]:find("Skinning", 1, true), nil, "Art steht im Symbol")
    eq(rows[3][1]:find(GT:FormatLocation({ zone = "Dunkelküste" }), 1, true) ~= nil, true, "Zone nach der Stufe")
    eq(rows[3].icon, "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", "Pelz")
end)

test("Tooltip: mehrere Zonen stehen in Folgezeilen, die nicht als Quelle zählen", function()
    local GT = setup({ locationLines = "several" })
    local rows = itemRows(GT, {
        { kind = "npc", id = 2, name = "Waldwolf", mode = "loot", chance = 0.42, average = 1, area = "elsewhere",
            spots = { Far(14), Far(10) } },
        { kind = "npc", id = 3, name = "Bär", mode = "loot", chance = 0.2, average = 1, area = "none", spots = {} },
        { kind = "npc", id = 4, name = "Eber", mode = "loot", chance = 0.1, average = 1, area = "none", spots = {} },
    })
    eq(#rows, 4, "Überschrift, Wolf, zweite Zone, Bär (maxSources = 2)")
    eq(rows[2][1]:find("Dunkelküste", 1, true) ~= nil, true, "erste Zone in der Quellzeile")
    eq(rows[3][1]:find("Düsterwald", 1, true) ~= nil, true, "zweite Zone darunter")
    eq(rows[3][2], nil, "ohne Chance")
    eq(rows[4][1]:find("Bär", 1, true) ~= nil, true, "zweite Quelle")
end)

test("Tooltip: ohne Symbole stehen die Quellen unter Überschriften für Beute und Berufe", function()
    local GT = setup({ showSourceIcons = false, maxSources = 4 })
    local rows = itemRows(GT, {
        { kind = "node", id = 1, name = "Silberblatt", category = "herb", chance = 0.9, average = 1, area = "here", spots = {} },
        { kind = "npc", id = 2, name = "Waldwolf", mode = "skinning", chance = 0.8, average = 1, area = "here", spots = {} },
        { kind = "node", id = 5, name = "Friedensblume", category = "herb", chance = 0.7, average = 1, area = "elsewhere", spots = {} },
        { kind = "npc", id = 3, name = "Bär", mode = "loot", chance = 0.2, average = 1, area = "none", spots = {} },
    })
    eq(#rows, 8, "Titel, drei Überschriften, vier Quellen")
    eq(rows[2][1]:find("Herbalism", 1, true) ~= nil, true, "Kräuterkunde zuerst")
    eq(rows[3][1], "Silberblatt", "Silberblatt")
    eq(rows[4][1], "Friedensblume", "zweites Kraut in derselben Gruppe")
    eq(rows[5][1]:find("Skinning", 1, true) ~= nil, true, "Kürschnern")
    eq(rows[6][1], "Waldwolf", "ohne Art hinter dem Namen")
    eq(rows[7][1]:find("Loot", 1, true) ~= nil, true, "Beute")
    eq(rows[8][1], "Bär", "Bär")
    eq(rows[3].icon, nil, "kein Symbol")
end)
