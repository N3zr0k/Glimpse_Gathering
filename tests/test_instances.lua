-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Instanzen als Fundort: Zone -instanceID in Glimpse: Database, Name in der Namensablage
local function setup()
    _G.GetTime = function() return stub.now end
    stub.now = 1000
    local DB, Glimpse = stub.newGatheringDB({ api = { GetItemInfoInstant = function(id) return id, "", "", "", "", 7, 7 end } })

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

    eq(DB:GetNode(1).attempts, 4, "Versuche")
    eq(GlimpseDB:Get("gathering"):GetZones("node", 1)[-36], 2, "Zone -instanceID")

    local spots = DB:GetOwnSpots("node", 1)
    eq(#spots, 3, "drei Orte")
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

test("Instanzen: ungültige Angaben", function()
    local DB = setup()
    for _, bad in ipairs({ { instance = 0 }, { instance = -3 }, { instance = 1.5 }, { instance = "x" }, { instance = 1e9 } }) do
        DB:RecordNode(1, nil, { [100] = 1 }, bad)
    end
    eq(#DB:GetOwnSpots("node", 1), 0, "nichts gespeichert")
    eq(next(DB.names.instances), nil, "keine Namen")

    DB:RecordNode(1, nil, { [100] = 1 }, { instance = 5, name = ("x"):rep(300) })
    eq(#DB:GetInstanceName(5), 100, "Name gekürzt")
end)

test("Instanzen: Auswertung hier, woanders und Debug-Anzeige", function()
    local DB = setup()
    DB:RecordNode(10, { name = "Erz" }, { [100] = 1 }, MINES)                                -- 100 %
    DB:RecordNode(11, { name = "Kraut" }, { [100] = 1 }, { map = 37, x = 0.5, y = 0.5 })      -- 100 %
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

test("Instanzen: Kreatur nur mit Zone ist im eigenen Gebiet ohne Entfernung, hinter Orten mit Koordinaten", function()
    local DB = setup()
    DB:RecordNPC(5, "loot", { name = "Wolf" }, { [100] = 1 }, { map = 37, x = 0.2, y = 0.2 })
    DB:RecordNode(11, { name = "Kraut" }, { [100] = 1 }, { map = 37, x = 0.5, y = 0.5 })

    DB.area = { map = 37, x = 0.4, y = 0.4 }
    local near = DB:GetNearestSpots("npc", 5)
    eq(#near, 1, "eine Zone")
    eq(near[1].tier, 1, "eigenes Gebiet")
    eq(near[1].distance, nil, "keine Entfernung")
    eq(near[1].mapDistance, nil, "kein Anteil der Karte")

    local list = DB:GetLocatedItemSources(100)
    eq(#list, 2, "zwei Quellen")
    eq(list[1].area, "here", "hier")
    eq(list[2].area, "here", "hier")

    -- Debug-Zeile ohne Koordinaten
    eq(DB:DebugSpotLines("npc", { 5 })[3][1], "  37", "nur die Karte")
end)
