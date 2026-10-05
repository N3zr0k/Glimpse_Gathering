-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Nachbau der Schnittstelle von GatherMate2 (Aufbau wie im Quelltext: coord = x * 1e6 + y * 100 in 1/10000)
local NODE_IDS = {
    ["Herb Gathering"] = { Silberblatt = 1 },
    ["Mining"] = { Kupfervorkommen = 2 },
    ["Treasure"] = { Truhe = 3 },
    ["Extract Gas"] = {},
    ["Logging"] = {},
}

local function Encode(x, y)
    return math.floor(x * 10000 + 0.5) * 1000000 + math.floor(y * 10000 + 0.5) * 100
end

-- points[typ][map] = { { x, y, nodeID }, ... }
local function FakeGatherMate(points, withHBD)
    local gm = { gmdbs = {}, calls = 0 }
    local data = {}
    for typ, maps in pairs(points) do
        data[typ] = {}
        for map, list in pairs(maps) do
            data[typ][map] = {}
            for _, point in ipairs(list) do data[typ][map][Encode(point[1], point[2])] = point[3] end
        end
    end
    for typ in pairs(NODE_IDS) do
        gm.gmdbs[typ] = { __gm2_base_storage = data[typ] or {}, __gm2_storage_map = {} }
    end

    function gm:GetNodesForZone(zone, typ)
        gm.calls = gm.calls + 1
        if gm.broken then error("kaputt") end
        return pairs((data[typ] or {})[zone] or {})
    end
    function gm:DecodeLoc(id) return math.floor(id / 1000000) / 10000, math.floor(id % 1000000 / 100) / 10000 end
    function gm:GetIDForNode(typ, name) return NODE_IDS[typ] and NODE_IDS[typ][name] end
    if withHBD ~= false then
        gm.HBD = { GetAllMapIDs = function() return { 37, 38, 1000 } end }
    end
    return gm
end

local function setup(points, withHBD)
    stub.libs.LibDeflate = nil
    _G.GatherMate2 = points and FakeGatherMate(points, withHBD) or nil
    _G.GetTime = function() return stub.now end
    stub.now = 1000

    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    DB.L = setmetatable({}, { __index = function(_, key) return key end })
    DB.DATA_VERSION = 2
    DB.data = { version = 2, nodes = {}, npcs = {}, imports = {} }
    DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"
    DB.RegisterMessage = function(self, message, func) self.registered = self.registered or {}; self.registered[message] = func end
    stub.load("Glimpse_GatheringDB/Data/Store.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Data/Migrate.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Data/Providers.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Data/GatherMate2.lua", "Glimpse_GatheringDB")
    DB:RecordNode(10, { name = "Silberblatt", category = "herb" }, { [100] = 1 }, { map = 37, x = 0.40, y = 0.50 })
    return DB
end

local function teardown() _G.GatherMate2 = nil end

local HERBS = { ["Herb Gathering"] = { [37] = {
    { 0.4005, 0.5005, 1 },   -- direkt neben unserem eigenen Ort: fällt weg
    { 0.70, 0.30, 1 }, { 0.702, 0.304, 1 }, { 0.704, 0.302, 1 }, -- ein Haufen
    { 0.20, 0.80, 1 },
    { 0.55, 0.55, 99 },      -- anderer Knoten
} } }

test("GatherMate2: ohne das Addon nur eigene Orte, kein Fehler", function()
    local DB = setup(nil)
    local spots = DB:GetSpots("node", 10)
    eq(#spots, 1, "nur eigener Ort")
    eq(spots[1].source, "own", "Quelle")
    eq(DB:HasAvailableProvider(), false, "nicht verfügbar")
    eq(DB:ProviderStatistics(), "", "keine Statistik")
    eq(DB:GetProviders()[1].available, false, "Anbieter gemeldet, aber nicht verfügbar")
    teardown()
end)

test("GatherMate2: fremde Orte stehen hinter den eigenen, Haufen und Dubletten sind erledigt", function()
    local DB = setup(HERBS)
    local spots = DB:GetSpots("node", 10)

    eq(#spots, 3, "eigener + 2 fremde (Dublette weg, Haufen zusammen)")
    eq(spots[1].source, "own", "eigener zuerst")
    eq(spots[2].source, "GatherMate2", "Quelle")
    eq(spots[2].count, 0, "count 0")
    eq(spots[2].density, 3, "dichtester Haufen zuerst")
    near(spots[2].x, 0.702, "Mitte x")
    near(spots[2].y, 0.302, "Mitte y")
    eq(spots[2].map, 37, "Karte")
    eq(spots[3].density, 1, "Einzelpunkt")
    eq(DB:HasAvailableProvider(), true, "verfügbar")
    teardown()
end)

test("GatherMate2: Kategorie bestimmt den Typ, Name den Knoten", function()
    local points = {
        ["Herb Gathering"] = { [37] = { { 0.1, 0.1, 1 } } },
        ["Mining"] = { [37] = { { 0.2, 0.2, 2 } } },
        ["Treasure"] = { [38] = { { 0.3, 0.3, 3 } } },
    }
    local DB = setup(points)
    DB:RecordNode(11, { name = "Kupfervorkommen", category = "ore" }, { [101] = 1 })
    DB:RecordNode(12, { name = "Truhe", category = "other" }, { [102] = 1 })
    DB:RecordNode(13, { name = "Silberblatt", category = "ore" }, { [100] = 1 }) -- Kräutername, aber Kategorie Erz

    local ore = DB:GetSpots("node", 11)
    eq(#ore, 1, "Erz")
    near(ore[1].x, 0.2, "Erzposition")

    local other = DB:GetSpots("node", 12)
    eq(#other, 1, "Truhe")
    eq(other[1].map, 38, "andere Karte")

    eq(#DB:GetSpots("node", 13), 0, "falscher Typ findet nichts")
    teardown()
end)

test("GatherMate2: Kreaturen und unbekannte Quellen bekommen nichts", function()
    local DB = setup(HERBS)
    DB:RecordNPC(77, "loot", { name = "Wolf" }, { [102] = 1 }, { map = 10, x = 0.5, y = 0.5 })
    eq(#DB:GetSpots("npc", 77), 1, "nur eigener Ort")
    eq(#DB:GetSpots("node", 4711), 0, "unbekannter Knoten")
    teardown()
end)

test("GatherMate2: Option aus oder includeExternal=false liefert nur eigene", function()
    local DB = setup(HERBS)
    eq(#DB:GetSpots("node", 10, false), 1, "ausdrücklich ohne")
    eq(#DB:GetOwnSpots("node", 10), 1, "GetOwnSpots")

    DB.db = { profile = { useExternalSpots = false } }
    eq(#DB:GetSpots("node", 10), 1, "Option aus")
    eq(DB:ProviderStatistics(), "", "Statistik leer bei ausgeschalteter Option")

    DB.db.profile.useExternalSpots = true
    eq(#DB:GetSpots("node", 10), 3, "Option an")
    teardown()
end)

test("GatherMate2: Fehler im Anbieter werden gemeldet, eigene Orte bleiben", function()
    local DB = setup(HERBS)
    _G.GatherMate2.broken = true
    local reported
    DB.ReportError = function(_, where, err) reported = where .. ": " .. tostring(err) end

    local spots = DB:GetSpots("node", 10)
    eq(#spots, 1, "nur eigene")
    eq(reported ~= nil and reported:find("GatherMate2", 1, true) ~= nil, true, "Fehler gemeldet")
    teardown()
end)

test("GatherMate2: unvollständige Schnittstelle gilt als nicht verfügbar", function()
    local DB = setup(HERBS)
    _G.GatherMate2.DecodeLoc = nil
    eq(DB:HasAvailableProvider(), false, "ohne DecodeLoc")
    eq(#DB:GetSpots("node", 10), 1, "nur eigene")
    teardown()
end)

test("GatherMate2: Obergrenze für fremde Orte", function()
    local list = {}
    for index = 1, 200 do list[index] = { 0.05 + (index % 20) * 0.045, 0.05 + math.floor(index / 20) * 0.09, 1 } end
    local DB = setup({ ["Herb Gathering"] = { [37] = list } })
    local spots = DB:GetSpots("node", 10)
    eq(#spots <= 1 + DB.EXTERNAL_LIMIT, true, "höchstens EXTERNAL_LIMIT fremde Orte")
    eq(#spots > 20, true, "trotzdem viele")
    teardown()
end)

test("GatherMate2: ohne HereBeDragons werden die Speicher gelesen", function()
    local DB = setup(HERBS, false)
    eq(#DB:GetSpots("node", 10), 3, "gleiches Ergebnis")
    teardown()
end)

test("GatherMate2: Index bleibt zwischengespeichert, Änderungen wirken nach der Wartezeit", function()
    local DB = setup(HERBS)
    DB:GetSpots("node", 10)
    local calls = _G.GatherMate2.calls
    DB:GetSpots("node", 10)
    eq(_G.GatherMate2.calls, calls, "zweiter Aufruf ohne neues Lesen")

    DB:WatchGatherMate2()
    eq(type(DB.registered.GatherMate2NodeAdded), "function", "Nachricht angemeldet")
    DB.registered.GatherMate2NodeAdded()
    DB:GetSpots("node", 10)
    eq(_G.GatherMate2.calls, calls, "kurz nach der Änderung noch alter Index")

    stub.now = stub.now + 31
    DB:GetSpots("node", 10)
    eq(_G.GatherMate2.calls > calls, true, "später neu gelesen")
    teardown()
end)

test("GatherMate2: GetItemSpots enthält fremde Orte, ebenso die Statistik", function()
    local DB = setup(HERBS)
    local spots = DB:GetItemSpots(100, 1)
    eq(#spots, 3, "alle Orte der Quelle")
    eq(spots[2].source, "GatherMate2", "Quelle")
    eq(spots[2].name, "Silberblatt", "Name der Quelle")
    eq(#DB:GetItemSpots(100, 1, nil, false), 1, "ohne fremde")

    local text = DB:ProviderStatistics()
    eq(text, "GatherMate2: 6 locations", "Zeile vorhanden")
    eq(DB:GetProviderInfo()[1].points, 6, "Punkte (alle Knoten dieses Typs)")
    teardown()
end)

test("GatherMate2: eigener Anbieter lässt sich anmelden und ersetzen", function()
    local DB = setup(nil)
    local calls = 0
    DB:RegisterProvider("Test", {
        IsAvailable = function() return true end,
        GetSpots = function() calls = calls + 1; return { { map = 5, x = 0.9, y = 0.9, density = 2 }, { map = 5, x = 2, y = 0.1 } } end,
    })
    local spots = DB:GetSpots("node", 10)
    eq(#spots, 2, "ungültiger Ort verworfen")
    eq(spots[2].source, "Test", "Name")

    DB:RegisterProvider("Test", { IsAvailable = function() return false end, GetSpots = function() end })
    eq(#DB:GetSpots("node", 10), 1, "ersetzt")
    eq(calls, 1, "alter Anbieter nicht mehr gefragt")
end)

test("GatherMate2: nächste Fundorte nach Entfernung", function()
    local DB = setup(HERBS)
    DB.GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end

    local spots = DB:GetNearestSpots("node", 10)
    eq(spots[1].density, 3, "Haufen in der Nähe zuerst")
    eq(spots[1].mapDistance < 0.05, true, "Entfernung")
    eq(#spots, 3, "alle")
    eq(#DB:GetNearestSpots("node", 10, 1), 1, "limit")

    DB.GetPlayerPosition = function() return { map = 99, x = 0.5, y = 0.5 } end
    eq(#DB:GetNearestSpots("node", 10, nil, true), 0, "andere Karte, nur aktuelle")
    eq(#DB:GetNearestSpots("node", 10), 3, "andere Karte, alle")
    eq(DB:GetNearestSpots("node", 10)[1].source, "own", "Reihenfolge wie GetSpots")

    DB.GetPlayerPosition = function() return nil end
    eq(#DB:GetNearestSpots("node", 10), 3, "ohne Position")
    eq(#DB:GetNearestSpots("node", 10, nil, true), 0, "ohne Position, nur aktuelle")
    teardown()
end)

test("GatherMate2: Karten, die HereBeDragons nicht kennt, werden trotzdem gelesen", function()
    local DB = setup({ ["Herb Gathering"] = { [5555] = { { 0.3, 0.3, 1 } } } })
    local spots = DB:GetSpots("node", 10)
    eq(#spots, 2, "eigener + Ort auf unbekannter Karte")
    eq(spots[2].map, 5555, "Karte aus dem Speicher")
    teardown()
end)

test("GatherMate2: leerer Index wird nach der Wartezeit erneut gelesen", function()
    local DB = setup({ ["Herb Gathering"] = {} })
    eq(#DB:GetSpots("node", 10), 1, "noch keine Daten")
    local gm = _G.GatherMate2
    gm.gmdbs["Herb Gathering"].__gm2_base_storage[37] = { [Encode(0.2, 0.2)] = 1 }
    eq(#DB:GetSpots("node", 10), 1, "gleich danach noch der alte Stand")
    stub.now = stub.now + 31
    eq(#DB:GetSpots("node", 10), 2, "später gefunden")
    teardown()
end)

test("GatherMate2: Prüfausgabe nennt Punkte und Treffer", function()
    local DB = setup(HERBS)
    local text = table.concat(DB:DiagnoseGatherMate2(), "\n")
    eq(text:find("Herb Gathering: 6 points on 1 maps in storage, 6 points of 2 node kinds read", 1, true) ~= nil, true, "Punkte")
    eq(text:find("Own nodes with a match in GatherMate2: 1 of 1", 1, true) ~= nil, true, "Treffer")
    teardown()

    eq(DB:DiagnoseGatherMate2()[1], "GatherMate2 is not loaded.", "ohne Addon")
end)

test("Debug: Fundort-Zeilen zeigen Karte, Koordinaten, Quelle und Entfernung", function()
    local DB = setup(HERBS)
    DB.api = { GetMapInfo = function(map) return map == 37 and { name = "Elwynn" } or nil end }
    stub.load("Glimpse_GatheringDB/Debug/Debug.lua", "Glimpse_GatheringDB")

    DB.GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end
    local lines = DB:DebugSpotLines("node", { 10 })
    eq(lines[1][1], "Locations: 1 own, 2 from other addons", "Zahlen")
    eq(lines[2][1], "Position: Elwynn (37)", "Position")
    eq(lines[2][2], "68.0 / 30.0", "Koordinaten des Spielers in Prozent")
    eq(lines[3][1], "  Elwynn (37)  70.2 / 30.2", "nächster Ort zuerst")
    eq(lines[3][2]:find("3 points", 1, true) ~= nil and lines[3][2]:find("[GatherMate2]", 1, true) ~= nil, true, "Punkte und Quelle")
    eq(lines[3][2]:find("away", 1, true) ~= nil, true, "Entfernung")
    eq(lines[4][1], "  Elwynn (37)  40.0 / 50.0", "eigener Ort")
    eq(lines[4][2]:find("1 finds", 1, true) ~= nil, true, "Funde")
    eq(#lines, 5, "alle Orte")

    DB.GetPlayerPosition = function() return nil end
    lines = DB:DebugSpotLines("node", { 10 })
    eq(lines[2][1], "Position: unknown", "ohne Position")
    eq(lines[3][2]:find("[own]", 1, true) ~= nil, true, "eigener Ort zuerst")

    eq(DB:DebugSpotLines("node", { 4711 })[1][1], "Locations: 0 own, 0 from other addons", "unbekannte Quelle")
    teardown()
end)

test("Quellen: einzelne Anbieter lassen sich ausschalten", function()
    local DB = setup(HERBS)
    DB:RegisterProvider("Zweit", {
        IsAvailable = function() return true end,
        GetSpots = function() return { { map = 5, x = 0.9, y = 0.9, density = 1 } } end,
    })
    DB.db = { profile = { useExternalSpots = true, externalSources = {} } }
    eq(#DB:GetSpots("node", 10), 4, "beide Anbieter")

    DB.db.profile.externalSources.GatherMate2 = false
    local spots = DB:GetSpots("node", 10)
    eq(#spots, 2, "nur noch der zweite")
    eq(spots[2].source, "Zweit", "Quelle")

    local info = DB:GetProviders()
    eq(info[1].name, "GatherMate2", "Name")
    eq(info[1].enabled, false, "ausgeschaltet gemeldet")
    eq(info[1].available, true, "trotzdem vorhanden")
    eq(DB:ProviderStatistics():find("GatherMate2", 1, true), nil, "nicht in der Statistik")

    DB.db.profile.externalSources.GatherMate2 = true
    eq(#DB:GetSpots("node", 10), 4, "wieder an")
    teardown()
end)

test("Quellen: Optionen haben je Anbieter einen Schalter", function()
    local DB = setup(HERBS)
    DB.db = { profile = { useExternalSpots = true, externalSources = {} } }
    stub.load("Glimpse_GatheringDB/Core/Options.lua", "Glimpse_GatheringDB")

    local group = DB:BuildSourceOptions()
    local toggle = group.args.GatherMate2
    eq(toggle ~= nil, true, "Schalter vorhanden")
    eq(toggle.get(), true, "Standard an")
    eq(toggle.disabled(), false, "bedienbar")

    toggle.set(nil, false)
    eq(DB.db.profile.externalSources.GatherMate2, false, "gespeichert")
    eq(toggle.get(), false, "gelesen")

    DB.db.profile.useExternalSpots = false
    eq(toggle.disabled(), true, "bei ausgeschaltetem Hauptschalter nicht bedienbar")
    DB.db.profile.useExternalSpots = true
    teardown()

    eq(toggle.disabled(), true, "ohne das Addon nicht bedienbar")
    eq(toggle.desc():find("not found", 1, true) ~= nil, true, "Hinweis")
end)

local function Vector(x, y) return { GetXY = function() return x, y end } end

test("Entfernung: Yards aus der Kartengröße der Spielfunktion", function()
    local DB = setup(HERBS)
    DB.api = { GetMapWorldSize = function(map) if map == 37 then return 5000, 3000 end end }
    DB:ResetMapSizes()
    stub.load("Glimpse_GatheringDB/Debug/Debug.lua", "Glimpse_GatheringDB")
    DB.GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end

    local w, h = DB:GetMapSize(37)
    eq(w, 5000, "Breite")
    eq(h, 3000, "Höhe")
    eq(DB:GetMapSize(99), nil, "unbekannte Karte")

    -- 0.022 * 5000 = 110, 0.002 * 3000 = 6
    near(DB:GetMapDistance(37, 0.702, 0.302, 0.68, 0.30), math.sqrt(110 * 110 + 6 * 6), "Strecke in Yards")

    local spots = DB:GetNearestSpots("node", 10)
    eq(spots[1].distance ~= nil, true, "Yards am Ort")
    eq(spots[1].mapDistance ~= nil, true, "und Anteil der Karte")
    eq(spots[1].distance < spots[2].distance, true, "nach Yards sortiert")

    local lines = DB:DebugSpotLines("node", { 10 })
    eq(lines[3][2]:find("110 yards away", 1, true) ~= nil, true, "Anzeige in Yards")
    teardown()
end)

test("Entfernung: Größe aus Weltpositionen, wenn GetMapWorldSize fehlt", function()
    local DB = setup(HERBS)
    _G.CreateVector2D = function(x, y) return { x = x, y = y } end
    DB.api = {
        GetWorldPosFromMapPos = function(_, v)
            -- Welt: Karte ist 4000 breit (zweite Zahl) und 2000 hoch (erste Zahl), Ecke bei (1000, 2000)
            return 0, Vector(1000 - v.y * 2000, 2000 - v.x * 4000)
        end,
    }
    DB:ResetMapSizes()
    local w, h = DB:GetMapSize(37)
    eq(w, 4000, "Breite")
    eq(h, 2000, "Höhe")
    _G.CreateVector2D = nil
    teardown()
end)

test("Entfernung: ohne Kartengröße nur Anteil der Karte", function()
    local DB = setup(HERBS)
    DB.api = {}
    DB:ResetMapSizes()
    stub.load("Glimpse_GatheringDB/Debug/Debug.lua", "Glimpse_GatheringDB")
    DB.GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end
    eq(DB:GetMapDistance(37, 0.1, 0.1, 0.2, 0.2), nil, "keine Yards")

    local spots = DB:GetNearestSpots("node", 10)
    eq(spots[1].distance, nil, "kein Yards-Wert")
    eq(spots[1].mapDistance ~= nil, true, "Anteil vorhanden")
    local lines = DB:DebugSpotLines("node", { 10 })
    eq(lines[3][2]:find("% of the map away", 1, true) ~= nil, true, "Anzeige in Prozent")

    -- Fehler in der Spielfunktion werden abgefangen
    DB.api = { GetMapWorldSize = function() error("kaputt") end }
    eq(DB:GetMapSize(37), nil, "Fehler abgefangen")
    teardown()
end)
