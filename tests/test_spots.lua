-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

local function setup()
    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    DB.DATA_VERSION = 2
    DB.data = { version = 2, nodes = {}, npcs = {}, imports = {} }
    DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"
    stub.load("Glimpse_GatheringDB/Core/Data/Spots.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Store.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Names.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Migrate.lua", "Glimpse_GatheringDB")
    return DB
end

test("Spots: ein Fundort wird mit Karte und Koordinaten gespeichert", function()
    local DB = setup()
    DB:RecordNode(10, { name = "Kupfer" }, { [1] = 1 }, { map = 37, x = 0.4123, y = 0.5678 })

    local spots = DB:GetSpots("node", 10)
    eq(#spots, 1, "Orte")
    eq(spots[1].map, 37, "Karte")
    near(spots[1].x, 0.4123, "x")
    near(spots[1].y, 0.5678, "y")
    eq(spots[1].count, 1, "Anzahl")
    eq(DB:GetNode(10).spots[1].x, 4123, "gespeichert als ganze Zahl")
end)

test("Spots: nahe Orte werden zusammengefasst, ferne und andere Karten bleiben getrennt", function()
    local DB = setup()
    local base = { map = 37, x = 0.40, y = 0.50 }
    DB:RecordNode(10, nil, { [1] = 1 }, base)
    DB:RecordNode(10, nil, { [1] = 1 }, { map = 37, x = 0.405, y = 0.50 }) -- 0,5 % daneben
    DB:RecordNode(10, nil, { [1] = 1 }, { map = 37, x = 0.60, y = 0.50 })  -- weit weg
    DB:RecordNode(10, nil, { [1] = 1 }, { map = 38, x = 0.40, y = 0.50 })  -- andere Karte

    local spots = DB:GetSpots("node", 10)
    eq(#spots, 3, "drei Orte")
    eq(spots[1].count, 2, "der Haufen zuerst")
    near(spots[1].x, 0.4025, "gewichtete Mitte")
    eq(DB:GetNode(10).attempts, 4, "Versuche zählen unabhängig vom Ort")
end)

test("Spots: Obergrenze, die häufigsten Orte bleiben", function()
    local DB = setup()
    -- ein Ort mit vielen Funden
    for _ = 1, 20 do DB:RecordNode(1, nil, { [1] = 1 }, { map = 37, x = 0.01, y = 0.01 }) end
    -- mehr einzelne Orte als erlaubt, jeweils weit auseinander
    for index = 1, 60 do
        DB:RecordNode(1, nil, { [1] = 1 }, { map = 37, x = 0.05 + (index % 30) * 0.03, y = 0.05 + math.floor(index / 30) * 0.4 })
    end

    local spots = DB:GetSpots("node", 1)
    eq(#spots <= DB.MAX_SPOTS_NODE, true, "höchstens MAX_SPOTS_NODE")
    eq(spots[1].count >= 20, true, "stärkster Ort bleibt vorn")
end)

test("Spots: ungültige Orte werden ignoriert", function()
    local DB = setup()
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 37, x = 0, y = 0.5 })       -- (0, ...) heißt unbekannt
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 37, x = 1.5, y = 0.5 })
    DB:RecordNode(1, nil, { [1] = 1 }, { map = "x", x = 0.5, y = 0.5 })
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 0, x = 0.5, y = 0.5 })
    DB:RecordNode(1, nil, { [1] = 1 }, "ort")
    DB:RecordNode(1, nil, { [1] = 1 })
    eq(#DB:GetSpots("node", 1), 0, "keine Orte")
    eq(DB:GetNode(1).attempts, 6, "Versuche zählen trotzdem")
    eq(#DB:GetSpots("npc", 99), 0, "unbekannte Quelle")
    eq(#DB:GetSpots("sonst", 1), 0, "unbekannte Art")
end)

test("Spots: Kreaturen haben einen gemeinsamen Ort für Beute und Kürschnern", function()
    local DB = setup()
    DB:RecordNPC(5, "loot", { name = "Wolf" }, {}, { map = 10, x = 0.3, y = 0.3 })
    DB:RecordNPC(5, "skinning", nil, { [9] = 1 }, { map = 10, x = 0.3, y = 0.3 })
    local spots = DB:GetSpots("npc", 5)
    eq(#spots, 1, "ein Ort")
    eq(spots[1].count, 2, "zwei Funde")
end)

test("Spots: Orte eines Items, wahrscheinlichste Quelle zuerst", function()
    local DB = setup()
    DB:RecordNode(1, { name = "Silber" }, { [50] = 1 }, { map = 1, x = 0.1, y = 0.1 })      -- 1/1
    DB:RecordNPC(7, "loot", { name = "Wolf" }, { [50] = 1 }, { map = 2, x = 0.2, y = 0.2 })
    DB:RecordNPC(7, "loot", nil, {}, { map = 2, x = 0.2, y = 0.2 })                           -- 1/2

    local spots = DB:GetItemSpots(50)
    eq(#spots, 2, "Orte")
    eq(spots[1].kind, "node", "Knoten zuerst")
    eq(spots[1].name, "Silber", "Name")
    eq(spots[2].kind, "npc", "Kreatur danach")
    eq(#DB:GetItemSpots(50, 1, 1), 1, "limit")
    eq(#DB:GetItemSpots(999), 0, "unbekanntes Item")
end)

test("Spots: Statistik zählt die Fundorte", function()
    local DB = setup()
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 1, x = 0.1, y = 0.1 })
    DB:RecordNPC(2, "loot", nil, {}, { map = 1, x = 0.9, y = 0.9 })
    local _, _, _, spots = DB:GetStats()
    eq(spots, 2, "Fundorte")
end)

test("Migrate: Daten der Version 1 werden auf 2 gehoben, Beute bleibt", function()
    local DB = setup()
    DB.data.version = 1
    DB.data.imports = nil
    DB.data.nodes[1] = { name = "Alt", attempts = 3, items = { [7] = { hits = 2, amount = 4 } } }

    eq(DB:PrepareData(2), true, "Ergebnis")
    eq(DB.data.version, 2, "Version")
    eq(type(DB.data.imports), "table", "Importliste")
    eq(DB.data.nodes[1].attempts, 3, "Beute bleibt")
    eq(DB.data.nodes[1].spots, nil, "keine erfundenen Orte")
end)

test("Migrate: ungültige Fundorte fallen weg, gültige bleiben", function()
    local DB = setup()
    DB.data.nodes[1] = {
        attempts = 5, items = { [7] = { hits = 1, amount = 1 } },
        spots = {
            { map = 37, x = 100, y = 200, n = 3 },
            { map = 37, x = 0, y = 200, n = 3 },       -- x unbekannt
            { map = 37, x = 100, y = 20000, n = 3 },   -- außerhalb
            { map = "a", x = 100, y = 200, n = 3 },
            { map = 37, x = 100, y = 200, n = 0 },     -- keine Funde
            "kaputt",
        },
    }
    DB.data.nodes[2] = { attempts = 1, items = {}, spots = "kaputt" }

    eq(DB:PrepareData(2), true, "Ergebnis")
    eq(#DB.data.nodes[1].spots, 1, "ein gültiger Ort")
    eq(DB.data.nodes[1].spots[1].n, 3, "Anzahl")
    eq(DB.data.nodes[2].spots, nil, "kaputte Liste entfernt")
end)

test("Migrate: Daten einer neueren Version als 2 bleiben unangetastet", function()
    local DB = setup()
    DB.data.version = 3
    DB.data.nodes[1] = "kaputt"
    eq(DB:PrepareData(2), false, "Ergebnis")
    eq(DB.data.nodes[1], "kaputt", "unverändert")
end)
