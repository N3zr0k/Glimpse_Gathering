-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Zusammenspiel mit Glimpse: Database: Anmeldung, geschriebene Arten, Namen (GlimpseGatheringNames), Meldungen
-- und Probes. Alte Daten (GlimpseGatheringDB) liest Gathering nicht.
-- Items: 2770 = Erz, 2447 = Kraut, 2318 = Leder, 300 = Fisch.
local ITEMS = { [2770] = 7, [2447] = 9, [2318] = 6, [300] = 8 }
local api = {
    GetItemInfoInstant = function(id) return id, "", "", "", "", 7, ITEMS[id] or 0 end,
}

-- Eigene Funde wie beim Spielen: ein Knoten mit Ort und Instanz, eine Kreatur mit Beute und Kürschnerbeute
local function Seed(DB)
    DB:RecordNode(1731, { name = "Kupferader" }, { [2770] = 2 }, { map = 1429, x = 0.4, y = 0.5 })
    DB:RecordNode(1731, nil, { [2770] = 1 }, { instance = 36, name = "Die Todesminen" })
    DB:RecordNPC(100, "loot", { name = "Wolf", level = 10 }, { [2318] = 1 }, { map = 1429, x = 0.1, y = 0.1 })
    DB:RecordNPC(100, "skinning", { name = "Wolf", level = 10 }, { [2318] = 2 }, { map = 1429, x = 0.1, y = 0.1 })
end

test("Database: Anmeldung als Schreiber von gathering", function()
    local DB = stub.newGatheringDB({ api = api })
    assert(DB.ns, "Schreiber")
    eq(DB.ns.name, "gathering", "Namespace")
    eq(DB.ns.area, "Gathering", "Bereich")
    eq(DB.ns.zones, true, "Zonen")
    for _, kind in ipairs({ "node", "nodeloot", "nodedrop", "npc", "npcloot", "npcdrop", "skinned", "skinloot", "skindrop" }) do
        eq(DB.ns.world[kind], true, "Weltwissen " .. kind)
    end
    eq(DB.ns.world.herb, nil, "Sammelzähler sind persönlich")
    eq(DB.registerError, nil, "kein Fehler")
    for _, text in ipairs(stub.printed) do assert(not text:find("Database", 1, true), "keine Meldung zu Database") end
end)

test("Database: geschriebene Arten für Knoten, Kreaturen und Kürschnern", function()
    local DB = stub.newGatheringDB({ api = api })
    local reader = GlimpseDB:Get("gathering")
    DB:RecordNode(1731, { name = "Kupferader" }, { [2770] = 2 }, { map = 1429, x = 0.4, y = 0.5 })
    DB:RecordNode(1617, { name = "Silberblatt" }, { [2447] = 1 }, { map = 1429, x = 0.2, y = 0.2 })
    DB:RecordNPC(100, "loot", { name = "Wolf", level = 10 }, {}, { map = 1429, x = 0.1, y = 0.1 })
    DB:RecordNPC(100, "skinning", nil, { [2318] = 3 }, { map = 1429, x = 0.1, y = 0.1 })

    eq(reader:GetCount("node", 1731), 1, "node")
    eq(reader:GetCount("nodeloot:1731", 2770), 2, "nodeloot = Menge")
    eq(reader:GetCount("nodedrop:1731", 2770), 1, "nodedrop = Fenster")
    eq(reader:GetCount("ore", 1731), 1, "ore")
    eq(reader:GetCount("herb", 1617), 1, "herb")
    eq(reader:GetZones("node", 1731)[1429], 1, "Zone des Knotens")
    eq(#reader:GetLocations(1429, 1731), 1, "Ort des Knotens")

    eq(reader:GetCount("npc", 100), 1, "npc, auch leer")
    eq(reader:GetCount("skinned", 100), 1, "skinned")
    eq(reader:GetCount("skinloot:100", 2318), 3, "skinloot")
    eq(reader:GetCount("skindrop:100", 2318), 1, "skindrop")
    eq(reader:GetCount("skin", 100), 1, "eigener Kürschnerzähler")
    eq(#reader:GetLocations(1429, 100), 0, "Kreaturen ohne Ort")
end)

test("Database: eigene Funde lesen, mit Namen und Orten", function()
    local DB = stub.newGatheringDB({ api = api })
    Seed(DB)

    local node = DB:GetNode(1731)
    assert(node, "Knoten")
    eq(node.name, "Kupferader", "Name")
    eq(node.attempts, 2, "Versuche")
    eq(node.items[2770].hits, 2, "Funde")
    eq(node.items[2770].amount, 3, "Menge")
    eq(node.category, "ore", "Kategorie aus der Beute")

    local npc = DB:GetNPC(100)
    eq(npc.name, "Wolf", "NPC-Name"); eq(npc.level, 10, "Stufe")
    eq(npc.loot.attempts, 1, "Beute"); eq(npc.skinning.items[2318].amount, 2, "Kürschnerbeute")
    eq(DB:GetInstanceName(36), "Die Todesminen", "Instanzname")

    local spots = DB:GetOwnSpots("node", 1731)
    eq(#spots, 2, "Ort und Instanz")
    eq(spots[1].map, 1429, "Karte"); near(spots[1].x, 0.4, "x")
    eq(spots[2].instance, 36, "Instanz"); eq(spots[2].name, "Die Todesminen", "mit Name")
    eq(#DB:GetOwnSpots("npc", 100), 1, "Kreatur: eine Zone")

    DB:RecordNode(1731, nil, { [2770] = 1 }, { map = 1429, x = 0.4, y = 0.5 })
    eq(DB:GetNode(1731).attempts, 3, "neuer Fund dazu")
    eq(#DB:GetOwnSpots("node", 1731), 2, "naher Ort nicht doppelt")
end)

test("Database: alte Daten von GatheringDB werden nicht gelesen", function()
    local DB = stub.newGatheringDB({ api = api, saved = { GlimpseGatheringDB = { global = { version = 6,
        nodes = { [1731] = { name = "Kupferader", attempts = 4, items = { [2770] = { hits = 4, amount = 6 } } } } } } } })
    eq(DB:GetNodeName(1731), nil, "kein Name")

    DB:SetNodeName(1731, "Kupferader")
    eq(GlimpseGatheringNames.nodes[1731], "Kupferader", "neu gelernt")
    eq(#DB:FindNodeIDs("Kupferader"), 1, "über den Namen auffindbar")
end)

test("Database: neuere Daten pausieren die Aufzeichnung", function()
    local DB = stub.newGatheringDB({ api = api, saved = { GlimpseDB_Gathering = { gathering = { version = 9 } } } })
    eq(DB.ns, nil, "kein Schreiber")
    eq(DB.registerError, "NEWER_DATA", "Grund")
    eq(stub.printed[1], "The saved gathering data comes from a newer version. Recording is paused.", "Meldung")
    DB:RecordNode(1731, nil, { [2770] = 1 })
    eq(DB:GetNode(1731), nil, "nichts geschrieben")
end)

test("Database: ohne Glimpse: Database keine Aufzeichnung, aber kein Fehler", function()
    local DB = stub.newGatheringDB({ api = api, noDatabase = true })
    eq(DB.ns, nil, "kein Schreiber")
    eq(stub.printed[1], "Glimpse: Database is not available, recording is off (MISSING).", "Meldung")
    DB:RecordNode(1731, nil, { [2770] = 1 })
    eq(DB:GetNode(1731), nil, "nichts lesbar")
    eq(#DB:GetItemSources(2770), 0, "keine Quellen")
    eq(#DB:GetOwnSpots("node", 1731), 0, "keine Fundorte")
end)

test("Database: Probes der Gruppe gathering", function()
    local DB, Glimpse = stub.newGatheringDB({ api = api })
    Seed(DB)
    for _, name in ipairs({ "stats", "gm2", "skill", "area", "names", "fishing", "node", "npc", "item" }) do
        assert(Glimpse.probes["gathering " .. name], "Probe " .. name)
    end
    local node = table.concat(Glimpse.probes["gathering node"]("1731"), "\n")
    assert(node:find("Kupferader", 1, true), "Knoten-Probe nennt den Namen")
    eq(Glimpse.probes["gathering node"]("")[1], "ID expected", "ohne ID")
    local item = table.concat(Glimpse.probes["gathering item"]("2318"), "\n")
    assert(item:find("Wolf", 1, true), "Item-Probe nennt die Quelle")
end)

test("Database: Datenquellen für /gli probe db sources", function()
    local _, Glimpse = stub.newGatheringDB({ api = api })
    local lines = table.concat(Glimpse.dataSources.Glimpse_Gathering(), "\n")
    assert(lines:find("records: namespace gathering (writer)", 1, true), "Schreiber")
    assert(lines:find("fishing: read from namespace fishing", 1, true), "Angeln")
    assert(lines:find("names in GlimpseGatheringNames: Names:", 1, true), "Namen")
    assert(lines:find("locations from GatherMate2:", 1, true), "GatherMate2")
end)
