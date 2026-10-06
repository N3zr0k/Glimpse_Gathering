-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

local function setup(compress)
    stub.libs.LibDeflate = nil
    if compress then stub.useLibDeflate() end
    _G.GatherMate2 = nil
    _G.GetTime = function() return stub.now end
    stub.now = 1000

    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    DB.L = setmetatable({}, { __index = function(_, key) return key end })
    DB.DATA_VERSION = 3
    DB.data = { version = 3, nodes = {}, npcs = {}, imports = {}, instances = {} }
    DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"
    DB.api = {}
    for _, file in ipairs({ "Data/Store.lua", "Data/Migrate.lua", "Data/Transfer.lua", "Data/Providers.lua",
        "Data/Sources.lua", "Debug/Debug.lua" }) do
        stub.load("Glimpse_GatheringDB/" .. file, "Glimpse_GatheringDB")
    end

    -- Wo der Spieler gerade ist: area = { instance, name } oder { map, x, y }
    DB.area = nil
    local Locations = Glimpse:GetModule("Locations")
    Locations.GetPlayerInstance = function() return DB.area and DB.area.instance and DB.area or nil end
    Locations.GetPlayerPosition = function() return DB.area and DB.area.map and DB.area or nil end
    return DB
end

local MINES = { instance = 36, name = "Die Todesminen" }
local CORE = { instance = 409, name = "Geschmolzener Kern" }

test("Instanzen: Fundort speichern, Namen merken, zusammenzählen", function()
    local DB = setup()
    DB:RecordNode(1, { name = "Erz" }, { [100] = 1 }, MINES)
    DB:RecordNode(1, nil, { [100] = 1 }, MINES)
    DB:RecordNode(1, nil, { [100] = 1 }, CORE)
    DB:RecordNode(1, nil, { [100] = 1 }, { map = 37, x = 0.5, y = 0.5 })

    local node = DB:GetNode(1)
    eq(node.attempts, 4, "Versuche")
    eq(#node.spots, 3, "drei Orte")

    local spots = DB:GetOwnSpots("node", 1)
    eq(spots[1].instance, 36, "häufigster Ort zuerst")
    eq(spots[1].count, 2, "zwei Funde")
    eq(spots[1].name, "Die Todesminen", "Name")
    eq(spots[1].map, nil, "keine Karte")
    eq(DB:GetInstanceName(409), "Geschmolzener Kern", "Name nachschlagbar")

    -- der Name wird aktualisiert, die Zahl bleibt
    DB:RecordNode(1, nil, { [100] = 1 }, { instance = 36, name = "Deadmines" })
    eq(DB:GetInstanceName(36), "Deadmines", "neuer Name")
    eq(DB:GetOwnSpots("node", 1)[1].count, 3, "weiter dieselbe Instanz")
end)

test("Instanzen: ungültige Angaben und Obergrenze", function()
    local DB = setup()
    for _, bad in ipairs({ { instance = 0 }, { instance = -3 }, { instance = 1.5 }, { instance = "x" }, { instance = 1e9 } }) do
        DB:RecordNode(1, nil, { [100] = 1 }, bad)
    end
    eq(DB:GetNode(1).spots, nil, "nichts gespeichert")
    eq(next(DB.data.instances), nil, "keine Namen")

    DB:RecordNode(1, nil, { [100] = 1 }, { instance = 5, name = ("x"):rep(300) })
    eq(#DB.data.instances[5], 100, "Name gekürzt")

    for id = 100, 100 + DB.MAX_SPOTS_NPC + 5 do DB:RecordNPC(7, "loot", nil, { [100] = 1 }, { instance = id, name = "I" .. id }) end
    eq(#DB:GetNPC(7).spots <= DB.MAX_SPOTS_NPC, true, "Obergrenze")
    DB:PruneData()
    local names = 0
    for _ in pairs(DB.data.instances) do names = names + 1 end
    eq(names <= DB.MAX_SPOTS_NPC + 1, true, "Namen ohne Fundort fallen weg")
end)

test("Instanzen: Zurücksetzen löscht auch die Namen", function()
    local DB = setup()
    DB:RecordNode(1, nil, { [100] = 1 }, MINES)
    DB:ResetData()
    eq(next(DB.data.instances), nil, "Namen weg")
end)

test("Instanzen: Migration von Version 2 und Bereinigen", function()
    local DB = setup()
    local data = { version = 2, nodes = {
        [1] = { attempts = 2, items = { [100] = { hits = 1, amount = 1 } }, spots = {
            { map = 37, x = 100, y = 100, n = 1 },
            { inst = 36, n = 2 },
            { inst = "x", n = 1 }, { inst = -1, n = 1 }, { inst = 36.5, n = 1 }, { inst = 5, n = 0 },
        } },
    }, npcs = {}, imports = {} }
    eq(DB:UpgradeData(data, 3), true, "migriert")
    eq(data.version, 3, "Version")
    eq(type(data.instances), "table", "instances ergänzt")

    data.instances = { [36] = "Todesminen", ["a"] = "x", [7] = 5, [8] = "" }
    DB:SanitizeData(data)
    eq(#data.nodes[1].spots, 2, "nur gültige Orte")
    eq(data.instances[36], "Todesminen", "gültiger Name bleibt")
    eq(data.instances.a, nil, "falscher Schlüssel")
    eq(data.instances[7], nil, "kein Text")
    eq(data.instances[8], nil, "leerer Text")
end)

for _, compress in ipairs({ true, false }) do
    test("Instanzen: Export und Import (" .. (compress and "komprimiert" or "unkomprimiert") .. ")", function()
        local a = setup(compress)
        a:RecordNode(1, { name = "Erz" }, { [100] = 1 }, MINES)
        a:RecordNode(1, nil, { [100] = 1 }, MINES)
        a:RecordNPC(7, "loot", { name = "Wolf" }, { [100] = 1 }, CORE)
        local text = a:ExportData()

        local b = setup(compress)
        b:RecordNode(1, nil, { [100] = 1 }, { instance = 36, name = "Eigener Name" })
        eq((b:ImportData(text)), true, "Import")
        eq(b:GetOwnSpots("node", 1)[1].count, 3, "Funde addiert")
        eq(b:GetInstanceName(36), "Eigener Name", "vorhandener Name bleibt")
        eq(b:GetInstanceName(409), "Geschmolzener Kern", "neuer Name kommt dazu")
        eq(b:GetOwnSpots("npc", 7)[1].instance, 409, "Kreatur")

        local c = setup(compress)
        c:RecordNode(99, nil, { [1] = 1 }, { instance = 5, name = "Alt" })
        eq((c:ImportData(text, "replace")), true, "Ersetzen")
        eq(c:GetInstanceName(5), nil, "alter Name weg")
        eq(c:GetInstanceName(36), "Die Todesminen", "neuer Name da")
    end)
end

test("Instanzen: Export einer älteren Version (ohne Instanzen) wird migriert", function()
    local b = setup(false)
    local payload = b.Serialize({
        format = 1, version = 2, id = "v2",
        nodes = { [10] = { name = "Kupfer", attempts = 3, items = { [101] = { hits = 2, amount = 4 } },
            spots = { { map = 37, x = 100, y = 200, n = 3 } } } },
        npcs = {},
    })
    local ok, res = b:ImportData("GGDB1:R:" .. payload)
    eq(ok, true, "Import")
    eq(res.migrated, true, "migriert")
    eq(#b:GetOwnSpots("node", 10), 1, "Ort übernommen")
end)

test("Instanzen: Auswertung hier, woanders und Debug-Anzeige", function()
    local DB = setup()
    DB:RecordNode(10, { name = "Erz", category = "ore" }, { [100] = 1 }, MINES)             -- 100 %
    DB:RecordNode(11, { name = "Kraut", category = "herb" }, { [100] = 1 }, { map = 37, x = 0.5, y = 0.5 }) -- 100 %
    DB:RecordNode(12, { name = "Kern" }, { [100] = 1 }, CORE)
    DB:RecordNode(12, nil, {}, CORE) -- 50 %

    -- in den Todesminen: Erz ist "hier", die anderen "woanders"
    DB.area = MINES
    local list = DB:GetLocatedItemSources(100)
    eq(list[1].id, 10, "Quelle in dieser Instanz zuerst")
    eq(list[1].area, "here", "hier")
    eq(list[2].area, "nearby", "Karte: der Kontinent ist in einer Instanz unbekannt, also Stufe 2")
    eq(list[3].area, "elsewhere", "andere Instanz")
    eq(list[1].spots[1].here, true, "Ort als hier markiert")

    -- im Geschmolzenen Kern: Kern ist "hier", obwohl nur 50 %
    DB.area = CORE
    list = DB:GetLocatedItemSources(100)
    eq(list[1].id, 12, "andere Instanz")
    eq(list[1].area, "here", "hier")

    -- in der offenen Welt: das Kraut
    DB.area = { map = 37, x = 0.4, y = 0.4 }
    list = DB:GetLocatedItemSources(100)
    eq(list[1].id, 11, "Karte")
    eq(list[2].area, "elsewhere", "Instanzen sind woanders")

    -- Debug-Anzeige
    DB.area = MINES
    local lines = DB:DebugSpotLines("node", { 10 })
    eq(lines[2][1], "Position: Instance: Die Todesminen (36)", "Position ohne Koordinaten")
    eq(lines[3][1], "  Instance: Die Todesminen (36)", "Ort")
    eq(lines[3][2]:find("here", 1, true) ~= nil and lines[3][2]:find("[own]", 1, true) ~= nil, true, "hier und Quelle")

    DB.area = nil
    eq(DB:DebugSpotLines("node", { 10 })[2][1], "Position: unknown", "ohne Ort")

    -- nächste Orte: die eigene Instanz zuerst, ohne Entfernung
    DB:RecordNode(10, nil, { [100] = 1 }, { map = 37, x = 0.6, y = 0.6 })
    DB.area = MINES
    local near = DB:GetNearestSpots("node", 10)
    eq(near[1].instance, 36, "Instanz zuerst")
    eq(near[1].distance, nil, "keine Entfernung")
    eq(near[2].map, 37, "Karte danach")
    eq(#DB:GetNearestSpots("node", 10, nil, true), 1, "nur aktuelles Gebiet")

    -- in der offenen Welt kommt die Instanz hinter den Orten der Karte
    DB.area = { map = 37, x = 0.5, y = 0.5 }
    near = DB:GetNearestSpots("node", 10)
    eq(near[1].map, 37, "Karte zuerst")
    eq(near[2].instance, 36, "Instanz danach")
    eq(near[2].here, nil, "nicht hier")
end)
