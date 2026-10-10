-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Fundorte aus Glimpse: Database (Core/Data/Spots.lua, Core/Loot/NodeDB.lua): Orte der Knoten, Zonen der Kreaturen
local function setup()
    return stub.newGatheringDB({ api = { GetItemInfoInstant = function(id) return id, "", "", "", "", 7, 7 end } })
end

test("Spots: ein Fundort wird als Ort in Database gespeichert", function()
    local DB = setup()
    DB:RecordNode(10, { name = "Kupfer" }, { [1] = 1 }, { map = 37, x = 0.4123, y = 0.5678 })

    local spots = DB:GetSpots("node", 10)
    eq(#spots, 1, "Orte")
    eq(spots[1].map, 37, "Karte")
    near(spots[1].x, 0.4123, "x")
    near(spots[1].y, 0.5678, "y")
    eq(spots[1].count, 1, "Funde in der Zone")
    eq(spots[1].source, "own", "Quelle")

    local places = GlimpseDB:Get("gathering"):GetLocations(37, 10)
    eq(#places, 1, "Ort im Namespace gathering")
    eq(GlimpseDB:Get("gathering"):GetZones("node", 10)[37], 1, "Zone des Knotens")
end)

test("Spots: nahe Orte gibt es nur einmal, ferne und andere Karten bleiben getrennt", function()
    local DB = setup()
    DB:RecordNode(10, nil, { [1] = 1 }, { map = 37, x = 0.40, y = 0.50 })
    DB:RecordNode(10, nil, { [1] = 1 }, { map = 37, x = 0.405, y = 0.50 }) -- 0,5 % daneben
    DB:RecordNode(10, nil, { [1] = 1 }, { map = 37, x = 0.60, y = 0.50 })  -- weit weg
    DB:RecordNode(10, nil, { [1] = 1 }, { map = 38, x = 0.40, y = 0.50 })  -- andere Karte

    local spots = DB:GetSpots("node", 10)
    eq(#spots, 3, "drei Orte")
    eq(spots[1].map, 37, "Zone mit den meisten Funden zuerst")
    eq(spots[1].count, 3, "Funde der Zone")
    near(spots[1].x, 0.40, "erster Ort bleibt")
    eq(spots[3].map, 38, "andere Karte")
    eq(DB:GetNode(10).attempts, 4, "Versuche zählen unabhängig vom Ort")
end)

test("Spots: ungültige Orte werden ignoriert, die Zone zählt trotzdem", function()
    local DB = setup()
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 37, x = 0, y = 0.5 })       -- (0, ...) heißt unbekannt
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 37, x = 1.5, y = 0.5 })
    DB:RecordNode(1, nil, { [1] = 1 }, { map = "x", x = 0.5, y = 0.5 })
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 0, x = 0.5, y = 0.5 })
    DB:RecordNode(1, nil, { [1] = 1 }, "ort")
    DB:RecordNode(1, nil, { [1] = 1 })

    local spots = DB:GetSpots("node", 1)
    eq(#spots, 1, "nur die Zone 37")
    eq(spots[1].map, 37, "Zone")
    eq(spots[1].x, nil, "ohne Koordinaten")
    eq(spots[1].count, 2, "zwei Funde in der Zone")
    eq(DB:GetNode(1).attempts, 6, "Versuche zählen trotzdem")
    eq(#DB:GetSpots("npc", 99), 0, "unbekannte Quelle")
    eq(#DB:GetSpots("node", nil), 0, "ohne ID")
end)

test("Spots: Kreaturen haben nur Zonen, gemeinsam für Beute und Kürschnern", function()
    local DB = setup()
    DB:RecordNPC(5, "loot", { name = "Wolf" }, {}, { map = 10, x = 0.3, y = 0.3 })
    DB:RecordNPC(5, "skinning", nil, { [9] = 1 }, { map = 10, x = 0.3, y = 0.3 })
    local spots = DB:GetSpots("npc", 5)
    eq(#spots, 1, "eine Zone")
    eq(spots[1].map, 10, "Karte")
    eq(spots[1].x, nil, "keine Koordinaten")
    eq(spots[1].count, 2, "zwei Funde")
    eq(#GlimpseDB:Get("gathering"):GetLocations(10), 0, "keine Orte für Kreaturen")
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
    eq(spots[2].map, 2, "Zone der Kreatur")
    eq(#DB:GetItemSpots(50, 1, 1), 1, "limit")
    eq(#DB:GetItemSpots(999), 0, "unbekanntes Item")
end)

test("Spots: Option aus speichert weder Ort noch Zone", function()
    local DB = setup()
    DB.ns:Count("node", 0) -- Charakter anlegen
    local before = #GlimpseDB:Get("gathering"):GetLocations()
    DB.db.profile.trackLocations = false
    DB:RecordNode(1, nil, { [1] = 1 }, nil)
    eq(#DB:GetSpots("node", 1), 0, "keine Fundorte")
    eq(#GlimpseDB:Get("gathering"):GetLocations(), before, "keine Orte")
end)
