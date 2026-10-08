-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

local function setup()
    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    DB.data = { version = 1, nodes = {}, npcs = {} }
    DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"
    stub.load("Glimpse_GatheringDB/Core/Data/Spots.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Store.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Names.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Migrate.lua", "Glimpse_GatheringDB")
    return DB
end

test("Store: Chance und Durchschnitt eines Knotens", function()
    local DB = setup()
    DB:RecordNode(100, { name = "Silberblatt", category = "herb" }, { [1] = 2 })
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
    eq(DB:GetNode(100).category, "herb", "Kategorie")
end)

test("Store: leeres Beutefenster zählt als Versuch", function()
    local DB = setup()
    DB:RecordNPC(5, "loot", { name = "Wolf", level = 10 }, {})
    DB:RecordNPC(5, "loot", nil, { [9] = 1 })

    local drops, attempts = DB:GetNPCDrops(5, "loot")
    eq(attempts, 2, "Versuche")
    near(drops[1].chance, 0.5, "Chance")
    eq(DB:GetNPC(5).level, 10, "Stufe")
end)

test("Store: Name und Kategorie werden nur ergänzt, nicht überschrieben", function()
    local DB = setup()
    DB:RecordNode(1, { name = "A", category = "other" }, { [1] = 1 })
    DB:RecordNode(1, { name = "B", category = "ore" }, { [1] = 1 })
    eq(DB:GetNode(1).name, "A", "Name bleibt")
    eq(DB:GetNode(1).category, "ore", "other wird zu ore")
    DB:RecordNode(1, { category = "herb" }, { [1] = 1 })
    eq(DB:GetNode(1).category, "ore", "ore bleibt")
end)

test("Store: Quellen eines Items, wahrscheinlichste zuerst", function()
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
    eq(sources[3].mode, "loot", "schlechteste zuletzt")

    eq(#DB:GetItemSources(50, 2), 2, "minAttempts blendet aus")
    eq(#DB:GetItemSources(999), 0, "unbekanntes Item")
    eq(#DB:GetItemSources(nil), 0, "ungültige ID")
end)

test("Store: Index wird nach neuer Beute neu aufgebaut", function()
    local DB = setup()
    DB:RecordNode(1, { name = "Erz" }, { [50] = 1 })
    eq(#DB:GetItemSources(50), 1, "vorher")
    DB:RecordNode(2, { name = "Erz2" }, { [50] = 1 })
    eq(#DB:GetItemSources(50), 2, "nachher")
end)

test("Store: Knoten über den Namen, Farbcodes werden ignoriert", function()
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

test("Store: Statistik und Zurücksetzen", function()
    local DB = setup()
    DB:RecordNode(1, nil, { [1] = 1 })
    DB:RecordNPC(2, "loot", nil, {})
    DB:RecordNPC(2, "skinning", nil, {})
    local nodes, npcs, attempts = DB:GetStats()
    eq(nodes, 1, "Knoten"); eq(npcs, 1, "Kreaturen"); eq(attempts, 3, "Fenster")

    local before = DB.data.nodes
    DB:ResetData()
    eq(DB.data.nodes, before, "Tabelle bleibt dieselbe")
    eq(next(DB.data.nodes), nil, "leer")
    nodes = DB:GetStats()
    eq(nodes, 0, "nach Reset")
end)

test("Store: ungültige IDs werden ignoriert", function()
    local DB = setup()
    DB:RecordNode("abc", nil, {})
    DB:RecordNPC(nil, "loot", nil, {})
    eq(next(DB.data.nodes), nil, "keine Knoten")
    eq(next(DB.data.npcs), nil, "keine Kreaturen")
end)

test("Migrate: Daten einer neueren Version bleiben unangetastet", function()
    local DB = setup()
    DB.data.version = 2
    DB.data.nodes[1] = "kaputt"
    eq(DB:PrepareData(1), false, "Ergebnis")
    eq(DB.data.nodes[1], "kaputt", "unverändert")
end)

test("Migrate: defekte Einträge fallen weg, gute bleiben", function()
    local DB = setup()
    DB.data.nodes[1] = { attempts = 3, items = { [7] = { hits = 2, amount = 4 } } }
    DB.data.nodes[2] = "kaputt"
    DB.data.nodes["x"] = { attempts = 1, items = {} }
    DB.data.nodes[3] = { attempts = 1, items = { [7] = { hits = 5, amount = 1 } } } -- mehr Treffer als Versuche
    DB.data.npcs[4] = { loot = { attempts = -1, items = {} } }
    DB.data.npcs[5] = { skinning = { attempts = 2, items = { [9] = { hits = 1, amount = 1 } } } }

    eq(DB:PrepareData(1), true, "Ergebnis")
    eq(DB.data.nodes[1].items[7].hits, 2, "guter Knoten")
    eq(DB.data.nodes[2], nil, "kein Eintrag")
    eq(DB.data.nodes["x"], nil, "falscher Schlüssel")
    eq(next(DB.data.nodes[3].items), nil, "unmögliches Item entfernt")
    eq(DB.data.npcs[4], nil, "negative Versuche")
    eq(DB.data.npcs[5].skinning.attempts, 2, "gute Kreatur")
end)

test("Migrate: Obergrenze entfernt die Einträge mit den wenigsten Versuchen", function()
    local DB = setup()
    DB.MAX_NPCS = 100
    for id = 1, 150 do
        DB.data.npcs[id] = { loot = { attempts = id, items = { [5] = { hits = 1, amount = 1 } } } }
    end
    DB:PrepareData(1)

    local count = 0
    for _ in pairs(DB.data.npcs) do count = count + 1 end
    eq(count, 90, "90 % der Grenze bleiben")
    eq(DB.data.npcs[150] ~= nil, true, "meiste Versuche bleibt")
    eq(DB.data.npcs[1], nil, "wenigste Versuche fällt weg")
end)

test("Migrate: ein alter Kill-Zähler wird entfernt, eine Kreatur nur mit Kills fällt weg", function()
    local DB = setup()
    DB.data.npcs[6] = { kills = 5 }
    DB.data.npcs[8] = { kills = 2, skinning = { attempts = 1, items = {} } }
    DB.data.npcs[9] = { kills = "viele", loot = { attempts = 3, items = {} } }

    eq(DB:PrepareData(1), true, "Ergebnis")
    eq(DB.data.npcs[6], nil, "nur Kills: weg")
    eq(DB.data.npcs[8].kills, nil, "Zähler entfernt")
    eq(DB.data.npcs[8].skinning.attempts, 1, "Versuche bleiben")
    eq(DB.data.npcs[9].kills, nil, "auch ohne Zahlenwert")
    eq(DB.data.npcs[9].loot.attempts, 3, "Versuche bleiben")
    eq(DB.GetNPCKills, nil, "keine Abfrage mehr")
    eq(DB.RecordKill, nil, "kein Zählen mehr")
end)

test("Migrate: ohne gespeicherte Version laufen alle Schritte (AceDB speichert keine Default-Werte)", function()
    local DB = setup()
    DB.data.version = nil -- so kommen die Daten an, wenn die Version einmal dem Default entsprach
    DB.data.npcs[113] = { loot = { attempts = 7, items = {} } }
    eq(DB:PrepareData(5), true, "Ergebnis")
    eq(DB.data.version, 5, "Version steht fest")
    eq(DB.data.imports ~= nil and DB.data.instances ~= nil, true, "Schritte 1 und 2 sind harmlos")
end)

test("Core: die Datenversion steht nicht in den AceDB-Defaults", function()
    local file = io.open("Glimpse_GatheringDB/Core/GatheringDB.lua", "r")
    local text = file:read("*a")
    file:close()
    local defaults = text:match("local dataDefaults = (%b{})")
    eq(defaults ~= nil, true, "Defaults gefunden")
    eq(defaults:find("version", 1, true), nil, "kein version-Default (AceDB würde ihn beim Speichern entfernen)")
end)
