-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Lese-API über Glimpse: Database (Core/Data/Drops.lua, Names.lua): Chancen, Quellen eines Items, Namen.
-- Items: 1 = Kraut, 2 = Erz, sonst Edelstein (Kategorie "other").
local function setup()
    return stub.newGatheringDB({ api = {
        GetItemInfoInstant = function(id)
            if id == 1 then return id, "", "", "", "", 7, 9 end
            if id == 2 then return id, "", "", "", "", 7, 7 end
            return id, "", "", "", "", 3, 0
        end,
    } })
end

test("Drops: Chance und Durchschnitt eines Knotens", function()
    local DB = setup()
    DB:RecordNode(100, { name = "Silberblatt" }, { [1] = 2 })
    DB:RecordNode(100, nil, { [1] = 1, [2] = 1 })
    DB:RecordNode(100, nil, { [2] = 3 })

    local drops, attempts = DB:GetNodeDrops(100)
    eq(attempts, 3, "Versuche")
    eq(#drops, 2, "Items")
    -- Item 1: 2 Treffer, Menge 3; Item 2: 2 Treffer, Menge 4. Gleich viele Treffer: kleinere ID zuerst.
    eq(drops[1].itemID, 1, "Reihenfolge")
    near(drops[1].chance, 2 / 3, "Chance")
    near(drops[1].average, 1.5, "Durchschnitt Item 1")
    near(drops[2].average, 2.0, "Durchschnitt Item 2")
    eq(DB:GetNode(100).name, "Silberblatt", "Name")
    eq(DB:GetNode(100).category, "herb", "Kategorie aus der Beute")
end)

test("Drops: leeres Beutefenster zählt als Versuch", function()
    local DB = setup()
    DB:RecordNPC(5, "loot", { name = "Wolf", level = 10 }, {})
    DB:RecordNPC(5, "loot", nil, { [9] = 1 })

    local drops, attempts = DB:GetNPCDrops(5, "loot")
    eq(attempts, 2, "Versuche")
    near(drops[1].chance, 0.5, "Chance")
    eq(DB:GetNPC(5).level, 10, "Stufe")
    eq(DB:GetNPC(5).name, "Wolf", "Name")
end)

test("Drops: Knotenname wird nur ergänzt, die Kategorie folgt der Beute", function()
    local DB = setup()
    DB:RecordNode(1, { name = "A" }, { [9] = 1 })
    eq(DB:GetNode(1).category, "other", "Edelstein: other")
    DB:RecordNode(1, { name = "B" }, { [2] = 1 })
    eq(DB:GetNode(1).name, "A", "Name bleibt")
    eq(DB:GetNode(1).category, "ore", "mit Erz: ore")
end)

test("Drops: Quellen eines Items, wahrscheinlichste zuerst", function()
    local DB = setup()
    DB:RecordNode(1, { name = "Kupfer" }, { [50] = 1 })          -- 1/1
    DB:RecordNPC(7, "loot", { name = "Wolf" }, { [50] = 1 })
    DB:RecordNPC(7, "loot", nil, {})                              -- 1/2
    DB:RecordNPC(8, "skinning", { name = "Bär" }, { [50] = 1 })
    DB:RecordNPC(8, "skinning", nil, { [50] = 1 })                -- 2/2

    local sources = DB:GetItemSources(50)
    eq(#sources, 3, "Quellen")
    eq(sources[1].chance, 1, "beste Chance")
    eq(sources[1].attempts, 2, "bei Gleichstand mehr Versuche zuerst")
    eq(sources[1].mode, "skinning", "Modus")
    eq(sources[1].name, "Bär", "Name aus der Namensablage")
    eq(sources[2].category, "other", "Kategorie des Knotens")
    eq(sources[3].mode, "loot", "schlechteste zuletzt")

    eq(#DB:GetItemSources(50, 2), 2, "minAttempts blendet aus")
    eq(#DB:GetItemSources(999), 0, "unbekanntes Item")
    eq(#DB:GetItemSources(nil), 0, "ungültige ID")
end)

test("Drops: Index und Zwischenspeicher folgen den Änderungen in Database", function()
    local DB = setup()
    DB:RecordNode(1, { name = "Erz" }, { [50] = 1 })
    eq(#DB:GetItemSources(50), 1, "vorher")
    eq(DB:GetNode(1).attempts, 1, "Knoten vorher")
    DB:RecordNode(2, { name = "Erz2" }, { [50] = 1 })
    DB:RecordNode(1, nil, {})
    eq(#DB:GetItemSources(50), 2, "nachher")
    eq(DB:GetNode(1).attempts, 2, "Knoten nachher")

    -- Zurücksetzen im Tab Daten von Glimpse (ganzer Bereich)
    GlimpseDB:ResetArea("Gathering")
    eq(#DB:GetItemSources(50), 0, "nach dem Zurücksetzen")
    eq(DB:GetNode(1), nil, "Knoten weg")
end)

test("Drops: Knoten über den Namen, Farbcodes werden ignoriert", function()
    local DB = setup()
    DB:RecordNode(1, { name = "Kupfervorkommen" }, { [1] = 1 })
    DB:RecordNode(2, { name = "  Kupfervorkommen " }, { [1] = 1 })

    local ids = DB:FindNodeIDs("|cffffffffKupfervorkommen|r")
    eq(#ids, 2, "IDs")
    eq(ids[1], 1, "sortiert")
    local drops, attempts = DB:GetNodeDropsByName("Kupfervorkommen")
    eq(attempts, 2, "zusammengerechnet")
    near(drops[1].chance, 1, "Chance")
    eq(#DB:FindNodeIDs("Unbekannt"), 0, "unbekannter Name")
    eq(#DB:FindNodeIDs(nil), 0, "kein Name")
end)

test("Drops: Statistik", function()
    local DB = setup()
    DB:RecordNode(1, nil, { [1] = 1 }, { map = 37, x = 0.5, y = 0.5 })
    DB:RecordNPC(2, "loot", nil, {})
    DB:RecordNPC(2, "skinning", nil, {})
    local nodes, npcs, attempts, spots = DB:GetStats()
    eq(nodes, 1, "Knoten"); eq(npcs, 1, "Kreaturen"); eq(attempts, 3, "Fenster"); eq(spots, 1, "Orte")
end)

test("Drops: ungültige IDs werden ignoriert", function()
    local DB = setup()
    DB:RecordNode("abc", nil, {})
    DB:RecordNPC(nil, "loot", nil, {})
    local nodes, npcs = DB:GetStats()
    eq(nodes, 0, "keine Knoten")
    eq(npcs, 0, "keine Kreaturen")
    eq(DB:GetNode(nil), nil, "GetNode(nil)")
    eq(DB:GetNPC("x"), nil, "GetNPC ungültig")
end)

test("Drops: mehr Funde als Versuche (zusammengeführte Importe) ergeben höchstens 100 %", function()
    local DB = setup()
    DB:RecordNode(1, nil, { [1] = 1 })
    DB.ns:Count("nodedrop:1", 1, nil, 5)
    local drops = DB:GetNodeDrops(1)
    eq(drops[1].hits, 1, "auf die Versuche begrenzt")
    eq(drops[1].chance, 1, "Chance")
end)
