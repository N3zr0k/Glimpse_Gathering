-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")
local function Locations() return LibStub():GetAddon():GetModule("Locations") end

-- Nachbau der Schnittstelle von GatherMate2 (Aufbau wie im Quelltext: coord = x * 1e6 + y * 100 in 1/10000)
local NODE_IDS = {
    ["Herb Gathering"] = { Silberblatt = 1, Friedensblume = 4 },
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
    gm.reverseNodeIDs = {}
    for typ, names in pairs(NODE_IDS) do
        gm.reverseNodeIDs[typ] = {}
        for name, nodeID in pairs(names) do gm.reverseNodeIDs[typ][nodeID] = name end
    end
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
    stub.load("Glimpse_GatheringDB/Core/Data/Spots.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Store.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Names.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Migrate.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Providers.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/GatherMate2.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Sources.lua", "Glimpse_GatheringDB")
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

test("GatherMate2: falsche Kategorie (other statt Erz) findet den Knoten trotzdem über den Namen", function()
    local DB = setup({ Mining = { [37] = { { 0.70, 0.30, 2 }, { 0.20, 0.80, 2 } } } })
    DB:RecordNode(11, { name = "Kupfervorkommen", category = "other" }, { [101] = 1 }, { map = 37, x = 0.40, y = 0.10 })
    local spots = DB:GetSpots("node", 11)
    eq(#spots, 3, "eigener Ort und zwei aus GatherMate2")
    DB:RecordNode(12, { name = "Kupfervorkommen" }, { [101] = 1 }, { map = 37, x = 0.45, y = 0.15 }) -- ohne Kategorie
    eq(#DB:GetSpots("node", 12) >= 3, true, "ohne Kategorie ebenso")
    teardown()
end)

test("GatherMate2: Prüfausgabe listet jeden Knoten mit Kategorie und Treffern", function()
    local DB = setup({ Mining = { [37] = { { 0.70, 0.30, 2 } } } })
    DB:RecordNode(11, { name = "Kupfervorkommen", category = "ore" }, { [101] = 1 })
    DB:RecordNode(12, { name = "Unbekannt", category = "ore" }, { [101] = 1 })
    local text = table.concat(DB:DiagnoseGatherMate2(), "\n")
    eq(text:find("11 Kupfervorkommen [ore]: 1 places in GatherMate2", 1, true) ~= nil, true, "Treffer mit Kategorie")
    eq(text:find("12 Unbekannt [ore]: no match", 1, true) ~= nil, true, "kein Treffer")
    teardown()
end)

test("GatherMate2: Abgleich über den Namen, nicht über die Objekt-ID", function()
    -- GatherMate2 hat eigene IDs (Kupfervorkommen 2): unsere Objekt-ID (1731) spielt keine Rolle
    local DB = setup({ Mining = { [37] = { { 0.70, 0.30, 2 }, { 0.20, 0.80, 2 } } } })
    DB:RecordNode(1731, { name = "Kupfervorkommen", category = "ore" }, { [101] = 1 }, { map = 37, x = 0.40, y = 0.10 })
    eq(#DB:GetSpots("node", 1731), 3, "eigener Ort und zwei aus GatherMate2")

    -- gleiche Zahl wie die GatherMate2-ID, aber anderer Name: kein Treffer
    DB:RecordNode(2, { name = "Gänseblümchen", category = "ore" }, { [101] = 1 })
    eq(#DB:GetSpots("node", 2), 0, "ID allein genügt nicht")
    teardown()
end)

test("GatherMate2: Schreibweise, Groß-/Kleinschreibung und ähnliche Namen", function()
    local points = { Mining = { [37] = { { 0.70, 0.30, 2 } } } }
    local DB = setup(points)
    DB:RecordNode(11, { name = "kupfer-vorkommen", category = "ore" }, { [101] = 1 })
    eq(#DB:GetSpots("node", 11), 1, "ohne Groß-/Kleinschreibung und Sonderzeichen")
    DB:RecordNode(12, { name = "Kupferader", category = "ore" }, { [101] = 1 })
    eq(#DB:GetSpots("node", 12), 1, "eindeutig gleicher Anfang")
    DB:RecordNode(13, { name = "Kupfe", category = "ore" }, { [101] = 1 })
    eq(#DB:GetSpots("node", 13), 1, "genau PREFIX Zeichen")
    DB:RecordNode(14, { name = "Kupf", category = "ore" }, { [101] = 1 })
    eq(#DB:GetSpots("node", 14), 0, "zu kurz")
    DB:RecordNode(15, { name = "Zinnader", category = "ore" }, { [101] = 1 })
    eq(#DB:GetSpots("node", 15), 0, "anderer Anfang")
    teardown()
end)

test("GatherMate2: mehrdeutiger Anfang findet nichts", function()
    local DB = setup({ Mining = { [37] = { { 0.70, 0.30, 2 } } } })
    _G.GatherMate2.reverseNodeIDs["Mining"][5] = "Kupfergrube"
    DB:RecordNode(11, { name = "Kupferader", category = "ore" }, { [101] = 1 })
    eq(#DB:GetSpots("node", 11), 0, "zwei gleich gute Namen")
    teardown()
end)

test("GatherMate2: Prüfausgabe nennt bei fehlendem Treffer die Namen von GatherMate2", function()
    local DB = setup({ Mining = { [37] = { { 0.70, 0.30, 2 } } } })
    DB:RecordNode(12, { name = "Unbekannt", category = "ore" }, { [101] = 1 })
    local text = table.concat(DB:DiagnoseGatherMate2(), "\n")
    eq(text:find("name not known to GatherMate2", 1, true) ~= nil, true, "Hinweis")
    eq(text:find("2=Kupfervorkommen", 1, true) ~= nil, true, "Namen mit GatherMate2-ID")

    DB:RecordNode(13, { name = "Truhe", category = "other" }, { [101] = 1 }) -- bekannt, aber ohne Punkte
    text = table.concat(DB:DiagnoseGatherMate2(), "\n")
    eq(text:find("Treasure: name found as GatherMate2 id 3 (exact), but no points stored for it", 1, true) ~= nil, true, "Name bekannt, keine Punkte")
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
    Locations().GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end

    local spots = DB:GetNearestSpots("node", 10)
    eq(spots[1].density, 3, "Haufen in der Nähe zuerst")
    eq(spots[1].mapDistance < 0.05, true, "Entfernung")
    eq(#spots, 3, "alle")
    eq(#DB:GetNearestSpots("node", 10, 1), 1, "limit")

    Locations().GetPlayerPosition = function() return { map = 99, x = 0.5, y = 0.5 } end
    eq(#DB:GetNearestSpots("node", 10, nil, true), 0, "andere Karte, nur aktuelle")
    eq(#DB:GetNearestSpots("node", 10), 3, "andere Karte, alle")
    eq(DB:GetNearestSpots("node", 10)[1].source, "own", "Reihenfolge wie GetSpots")

    Locations().GetPlayerPosition = function() return nil end
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
    Locations().api = { GetMapInfo = function(map) return map == 37 and { name = "Elwynn" } or nil end }
    stub.load("Glimpse_GatheringDB/Modules/Debug/Debug.lua", "Glimpse_GatheringDB")

    Locations().GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end
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

    Locations().GetPlayerPosition = function() return nil end
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
    Locations().api = { GetMapWorldSize = function(map) if map == 37 then return 5000, 3000 end end }
    Locations():ResetCaches()
    stub.load("Glimpse_GatheringDB/Modules/Debug/Debug.lua", "Glimpse_GatheringDB")
    Locations().GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end

    local w, h = Locations():GetMapSize(37)
    eq(w, 5000, "Breite")
    eq(h, 3000, "Höhe")
    eq(Locations():GetMapSize(99), nil, "unbekannte Karte")

    -- 0.022 * 5000 = 110, 0.002 * 3000 = 6
    near(Locations():GetMapDistance(37, 0.702, 0.302, 0.68, 0.30), math.sqrt(110 * 110 + 6 * 6), "Strecke in Yards")

    local spots = DB:GetNearestSpots("node", 10)
    eq(spots[1].distance ~= nil, true, "Yards am Ort")
    eq(spots[1].mapDistance ~= nil, true, "und Anteil der Karte")
    eq(spots[1].distance < spots[2].distance, true, "nach Yards sortiert")

    local lines = DB:DebugSpotLines("node", { 10 })
    eq(lines[3][2]:find("110 yards away", 1, true) ~= nil, true, "Anzeige in Yards")
    teardown()
end)

test("Entfernung: Größe aus Weltpositionen, wenn GetMapWorldSize fehlt", function()
    setup(HERBS)
    _G.CreateVector2D = function(x, y) return { x = x, y = y } end
    Locations().api = {
        GetWorldPosFromMapPos = function(_, v)
            -- Welt: Karte ist 4000 breit (zweite Zahl) und 2000 hoch (erste Zahl), Ecke bei (1000, 2000)
            return 0, Vector(1000 - v.y * 2000, 2000 - v.x * 4000)
        end,
    }
    Locations():ResetCaches()
    local w, h = Locations():GetMapSize(37)
    eq(w, 4000, "Breite")
    eq(h, 2000, "Höhe")
    _G.CreateVector2D = nil
    teardown()
end)

test("Entfernung: ohne Kartengröße nur Anteil der Karte", function()
    local DB = setup(HERBS)
    Locations().api = {}
    Locations():ResetCaches()
    stub.load("Glimpse_GatheringDB/Modules/Debug/Debug.lua", "Glimpse_GatheringDB")
    Locations().GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end
    eq(Locations():GetMapDistance(37, 0.1, 0.1, 0.2, 0.2), nil, "keine Yards")

    local spots = DB:GetNearestSpots("node", 10)
    eq(spots[1].distance, nil, "kein Yards-Wert")
    eq(spots[1].mapDistance ~= nil, true, "Anteil vorhanden")
    local lines = DB:DebugSpotLines("node", { 10 })
    eq(lines[3][2]:find("% of the map away", 1, true) ~= nil, true, "Anzeige in Prozent")

    -- Fehler in der Spielfunktion werden abgefangen
    Locations().api = { GetMapWorldSize = function() error("kaputt") end }
    eq(Locations():GetMapSize(37), nil, "Fehler abgefangen")
    teardown()
end)


-- Welt für die Stufen: Karte 37 und 38 liegen auf Kontinent 1 (Welt 0, 2000 Yards auseinander), Karte 39 auf Kontinent 2.
local MAP_INFO = {
    [1] = { name = "Kontinent1", mapType = 2 },
    [2] = { name = "Kontinent2", mapType = 2 },
    [37] = { name = "Karte37", mapType = 3, parentMapID = 1 },
    [38] = { name = "Karte38", mapType = 3, parentMapID = 1 },
    [39] = { name = "Karte39", mapType = 3, parentMapID = 2 },
}
local WORLD = { [37] = { 0, 0, 0 }, [38] = { 0, 2000, 0 }, [39] = { 1, 0, 0 } } -- Welt, Ursprung x, y; jede Karte 1000 x 1000 Yards

local function WorldApi(withContinents, withWorld)
    local api = {}
    api.GetMapInfo = function(map)
        local info = MAP_INFO[map]
        if not info then return nil end
        if withContinents then return info end
        return { name = info.name }
    end
    if withWorld then
        _G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
        api.GetWorldPosFromMapPos = function(map, vector)
            local world = WORLD[map]
            if not world then return nil end
            return world[1], CreateVector2D(world[2] + vector.x * 1000, world[3] + vector.y * 1000)
        end
    end
    return api
end

-- Quellen eines Materials (Item 100):
--   10 Silberblatt     bestätigter Ort auf Karte 37 (hier, Stufe 1), 50 %
--   11 Kupfer          bestätigter Ort auf Karte 38 (gleicher Kontinent, Stufe 2), 100 %
--   12 Friedensblume   kein eigener Ort, GatherMate2-Ort auf Karte 37 (Stufe 1, extern), 100 %
--   13 Unbekannt       gar kein Ort (Stufe 4), 100 %
local function SourcesSetup(continents, world)
    local points = { ["Herb Gathering"] = { [37] = {
        { 0.70, 0.30, 4 },   -- Friedensblume, auf der Karte des Spielers
        { 0.20, 0.20, 1 },   -- Silberblatt
    } } }
    local DB = setup(points)
    Locations().api = WorldApi(continents ~= false, world ~= false)
    Locations().GetPlayerPosition = function() return { map = 37, x = 0.68, y = 0.30 } end
    DB.data.nodes[10] = nil
    DB:RecordNode(10, { name = "Silberblatt", category = "herb" }, {}, { map = 37, x = 0.40, y = 0.50 })
    DB:RecordNode(10, nil, { [100] = 1 }, { map = 37, x = 0.40, y = 0.50 })
    DB:RecordNode(11, { name = "Kupfer", category = "ore" }, { [100] = 1 }, { map = 38, x = 0.5, y = 0.5 })
    DB:RecordNode(12, { name = "Friedensblume", category = "herb" }, { [100] = 1 })
    DB:RecordNode(13, { name = "Unbekannt", category = "other" }, { [100] = 1 })
    return DB
end

local function Ids(list)
    local ids = {}
    for _, source in ipairs(list) do tinsert(ids, source.id) end
    return table.concat(ids, ",")
end

test("Quellen: eigenes Gebiet, gleicher Kontinent, ohne Ort; bestätigt vor extern", function()
    local DB = SourcesSetup()
    local list = DB:GetLocatedItemSources(100)

    eq(Ids(list), "10,12,11,13", "Reihenfolge")
    eq(list[1].tier, 1, "bestätigter Ort hier")
    eq(list[1].area, "here", "Gebiet")
    eq(list[1].group, "own", "bestätigt")
    eq(list[2].tier, 1, "externer Ort hier: ebenfalls Stufe 1 (der Ort in der eigenen Zone zählt)")
    eq(list[2].group, "external", "aber extern, deshalb hinter den bestätigten")
    eq(list[2].spot.source, "GatherMate2", "bester Ort")
    eq(list[3].tier, 2, "andere Karte, gleicher Kontinent")
    eq(list[3].area, "nearby", "Gebiet")
    eq(list[4].tier, 4, "ohne Ort")
    eq(list[4].spot, nil, "kein Ort")
    eq(list[4].group, nil, "keine Gruppe")
    eq(#DB:GetItemSources(100), 4, "GetItemSources bleibt unverändert")
    eq(DB:GetItemSources(100)[1].tier, nil, "und ohne Zusatzfelder")
    teardown()
end)

test("Quellen: Stufe 2 nach Entfernung in Yards, Stufe 1 nach Chance", function()
    local DB = SourcesSetup()
    -- Spieler auf Karte 37 bei (0.68, 0.30): Karte 38 liegt 2000 Yards weiter, Mitte der Karte 38 bei 2500
    local kupfer = DB:GetLocatedItemSources(100)[3]
    eq(kupfer.spot.map, 38, "Ort")
    near(kupfer.spot.distance, math.sqrt((2500 - 680) ^ 2 + (500 - 300) ^ 2), "Luftlinie über die Weltpositionen")

    -- zweite Quelle auf Karte 38, näher am Spieler, aber schlechtere Chance: kommt trotzdem vor Kupfer
    DB:RecordNode(14, { name = "Zink", category = "ore" }, { [100] = 1 }, { map = 38, x = 0.1, y = 0.3 })
    DB:RecordNode(14, nil, {}, { map = 38, x = 0.1, y = 0.3 })
    DB:RecordNode(14, nil, {}, { map = 38, x = 0.1, y = 0.3 }) -- 1 von 3
    eq(Ids(DB:GetLocatedItemSources(100)), "10,12,14,11,13", "Stufe 2: der nähere Ort zuerst")

    -- Stufe 1: höchste Chance zuerst
    DB:RecordNode(15, { name = "Dritte", category = "other" }, { [100] = 1 }, { map = 37, x = 0.9, y = 0.9 }) -- 100 %
    eq(Ids(DB:GetLocatedItemSources(100)), "15,10,12,14,11,13", "Stufe 1: 100 % vor 50 %")
    teardown()
end)

test("Quellen: Mindestchance gilt nur in Stufe 2", function()
    local DB = SourcesSetup()
    DB:RecordNode(14, { name = "Zink", category = "ore" }, { [100] = 1 }, { map = 38, x = 0.1, y = 0.3 })
    for _ = 1, 9 do DB:RecordNode(14, nil, {}, { map = 38, x = 0.1, y = 0.3 }) end -- 1 von 10 = 10 %
    DB:RecordNode(16, { name = "Eisen", category = "ore" }, { [100] = 1 }, { map = 38, x = 0.2, y = 0.2 })
    for _ = 1, 3 do DB:RecordNode(16, nil, {}, { map = 38, x = 0.2, y = 0.2 }) end -- 1 von 4 = 25 %
    DB:RecordNode(17, { name = "Fern", category = "ore" }, { [100] = 1 }, { map = 39, x = 0.5, y = 0.5 })
    for _ = 1, 9 do DB:RecordNode(17, nil, {}, { map = 39, x = 0.5, y = 0.5 }) end -- 10 %, anderer Kontinent

    eq(Ids(DB:GetLocatedItemSources(100)), "10,12,14,16,11,17,13", "ohne Mindestchance alle")
    eq(Ids(DB:GetLocatedItemSources(100, nil, nil, 0.2)), "10,12,16,11,17,13", "Zink (10 %) entfällt in Stufe 2, Fern (10 %) in Stufe 3 bleibt")
    eq(Ids(DB:GetLocatedItemSources(100, nil, nil, 0)), "10,12,14,16,11,17,13", "0 = alle")
    teardown()
end)

test("Quellen: anderer Kontinent und Instanzen sind Stufe 3, nach Chance", function()
    local DB = SourcesSetup()
    DB:RecordNode(17, { name = "Fern", category = "ore" }, { [100] = 1 }, { map = 39, x = 0.5, y = 0.5 })
    local list = DB:GetLocatedItemSources(100)
    eq(Ids(list), "10,12,11,17,13", "Fern hinter dem gleichen Kontinent")
    eq(list[4].tier, 3, "Stufe 3")
    eq(list[4].area, "elsewhere", "Gebiet")
    eq(list[4].spot.distance, nil, "ohne Entfernung")
    teardown()
end)

test("Quellen: ohne Kontinentangaben gelten andere Karten als Stufe 2, nach Chance", function()
    local DB = SourcesSetup(false, false)
    DB:RecordNode(17, { name = "Fern", category = "ore" }, { [100] = 1 }, { map = 39, x = 0.5, y = 0.5 })
    DB:RecordNode(18, { name = "Halb", category = "ore" }, { [100] = 1 }, { map = 38, x = 0.5, y = 0.5 })
    DB:RecordNode(18, nil, {}, { map = 38, x = 0.5, y = 0.5 }) -- 50 %
    local list = DB:GetLocatedItemSources(100)
    eq(Ids(list), "10,12,11,17,18,13", "Stufe 2: 100 % vor 50 %, ohne Entfernung nach Chance")
    eq(list[3].tier, 2, "Karte 38")
    eq(list[4].tier, 2, "Karte 39: Kontinent unbekannt")
    eq(list[3].spot.distance, nil, "keine Entfernung ohne Weltpositionen")
    teardown()
end)

test("Quellen: Kontinent aus den Weltpositionen, wenn die Karten keine Typen liefern", function()
    local DB = SourcesSetup(false, true)
    DB:RecordNode(17, { name = "Fern", category = "ore" }, { [100] = 1 }, { map = 39, x = 0.5, y = 0.5 })
    local list = DB:GetLocatedItemSources(100)
    eq(list[3].tier, 2, "Karte 38: gleiche Welt")
    near(list[3].spot.distance, math.sqrt((2500 - 680) ^ 2 + (500 - 300) ^ 2), "Entfernung")
    eq(list[4].tier, 3, "Karte 39: andere Welt")
    teardown()
end)

test("Quellen: eine Quelle in mehreren Zonen ergibt mehrere Einträge", function()
    local DB = SourcesSetup()
    -- Friedensblume hat zusätzlich einen bestätigten Ort auf Karte 38 und auf Karte 39 (anderer Kontinent)
    DB:RecordNode(12, nil, { [100] = 1 }, { map = 38, x = 0.5, y = 0.5 })
    DB:RecordNode(12, nil, { [100] = 1 }, { map = 39, x = 0.5, y = 0.5 })

    local list = DB:GetLocatedItemSources(100)
    eq(Ids(list), "10,12,12,11,12,13", "Friedensblume in drei Zonen (Stufe 1, 2, 3), in Stufe 2 vor Kupfer: gleiche Entfernung, mehr Versuche")

    eq(list[2].tier, 1, "hier: der Ort in der eigenen Zone zählt, auch wenn er nur extern belegt ist")
    eq(list[2].group, "external", "extern, deshalb hinter dem bestätigten Silberblatt")
    eq(list[2].spot.map, 37, "Ort")
    eq(list[3].tier, 2, "gleicher Kontinent")
    eq(list[3].group, "own", "dort bestätigt")
    eq(list[3].spot.map, 38, "Ort")
    eq(list[5].tier, 3, "anderer Kontinent")
    eq(list[5].spot.map, 39, "Ort")
    eq(list[2].place, "m37", "Schlüssel des Ortes")
    eq(#DB:GetItemSources(100), 4, "GetItemSources bleibt unverändert: vier Quellen")
    teardown()
end)

test("Quellen: mehrere Orte in derselben Zone sind ein Eintrag, der nächste bestätigte zählt", function()
    local DB = SourcesSetup()
    -- zweiter bestätigter Ort von Silberblatt weit weg vom ersten, ebenfalls Karte 37, näher am Spieler (0.68, 0.30)
    DB:RecordNode(10, nil, { [100] = 1 }, { map = 37, x = 0.60, y = 0.30 })
    local list = DB:GetLocatedItemSources(100)

    local entries = 0
    for _, source in ipairs(list) do if source.id == 10 then entries = entries + 1 end end
    eq(entries, 1, "ein Eintrag für Karte 37")
    eq(list[1].id, 10, "bestätigt vor extern")
    eq(#list[1].spots, 3, "alle Orte der Zone (zwei bestätigte, einer von GatherMate2)")
    near(list[1].spot.x, 0.60, "der nähere Ort")
    teardown()
end)

test("Quellen: zusammengefasst zählen externe Orte wie bestätigte", function()
    local DB = SourcesSetup()
    local list = DB:GetLocatedItemSources(100, nil, false)

    eq(Ids(list), "12,10,11,13", "Friedensblume (100 %) vor Silberblatt (50 %), beide Stufe 1")
    eq(list[1].group, "own", "keine Trennung")
    eq(list[1].tier, 1, "Stufe")

    eq(Ids(DB:GetLocatedItemSources(100, nil, true)), "10,12,11,13", "ausdrücklich getrennt")
    eq(Ids(DB:GetLocatedItemSources(100)), "10,12,11,13", "ohne Angabe getrennt")
    teardown()
end)

test("Quellen: ohne externe Daten gibt es nur bestätigte Orte", function()
    local DB = SourcesSetup()
    DB.db = { profile = { useExternalSpots = false } }
    local list = DB:GetLocatedItemSources(100)
    eq(Ids(list), "10,11,12,13", "Friedensblume ohne Ort in Stufe 4")
    for _, source in ipairs(list) do eq(source.group ~= "external", true, "keine externe Gruppe") end
    eq(list[3].tier, 4, "Friedensblume")
    teardown()
end)

test("Quellen: ohne Position gibt es kein eigenes Gebiet", function()
    local DB = SourcesSetup()
    Locations().GetPlayerPosition = function() return nil end
    local list = DB:GetLocatedItemSources(100)
    eq(Ids(list), "11,10,12,13", "alle Orte auf Karten sind Stufe 2, nach Chance")
    eq(list[1].tier, 2, "Stufe 2")
    eq(list[1].spot.distance, nil, "ohne Entfernung")
    teardown()
end)

test("Quellen: Debug-Zeilen für ein Material", function()
    local DB = SourcesSetup()
    stub.load("Glimpse_GatheringDB/Modules/Debug/Debug.lua", "Glimpse_GatheringDB")

    local lines = DB:DebugItemLines(100)
    eq(lines[1][1], "Places: 4  (outside separate)", "Kopfzeile")
    eq(lines[2][1], "Silberblatt (node 10, gather)", "erste Quelle")
    eq(lines[2][2]:find("[here, confirmed]", 1, true) ~= nil, true, "Gebiet und Gruppe")
    eq(lines[2][2]:find("50.0%", 1, true) ~= nil, true, "Chance")
    eq(lines[3][1], "  Karte37 (37)  40.0 / 50.0", "Ort darunter")
    eq(#DB:DebugItemLines(4711), 0, "Item ohne Quelle: nichts")

    local combined = DB:DebugItemLines(100, false)
    eq(combined[1][1], "Places: 4  (outside combined)", "zusammengefasst")
    eq(combined[2][1], "Friedensblume (node 12, gather)", "andere Reihenfolge")

    -- höchstens 5 Quellen, 2 Orte je Quelle
    for id = 20, 30 do DB:RecordNode(id, { name = "N" .. id, category = "other" }, { [100] = 1 }) end
    local many = DB:DebugItemLines(100)
    eq(many[#many][1], "... 10 more", "Rest der Quellen")
    teardown()
end)

test("GatherMate2: jede Zone bleibt trotz Begrenzung erhalten", function()
    local DB = stub.newGlimpse():NewModule("GatheringDB")
    DB.data = { version = 3, nodes = { [1] = { name = "Silberblatt", category = "herb", items = {} } }, npcs = {}, instances = {} }
    DB.db = { profile = { useExternalSpots = true, externalSources = {} } }
    DB.SPOT_RADIUS = 100
    DB.GetNode = function(self, id) return self.data.nodes[id] end
    DB.GetNPC = function() return nil end
    DB.ReportError = function() end
    stub.load("Glimpse_GatheringDB/Core/Data/Providers.lua", "Glimpse_GatheringDB")

    -- eine dichte Zone mit vielen Zellen und eine dünne mit einer einzigen
    local spots = {}
    for i = 1, DB.EXTERNAL_LIMIT + 20 do spots[#spots + 1] = { map = 10, x = 0.01 * (i % 90 + 1), y = 0.01 * (math.floor(i / 90) + 1), density = 50 } end
    spots[#spots + 1] = { map = 14, x = 0.5, y = 0.5, density = 1 }
    DB:RegisterProvider("Fake", { IsAvailable = function() return true end, GetSpots = function() return spots end })

    local list = {}
    DB:AddExternalSpots(list, "node", 1)
    eq(#list, DB.EXTERNAL_LIMIT, "Begrenzung gilt")
    local zones = {}
    for _, spot in ipairs(list) do zones[spot.map] = true end
    eq(zones[14], true, "auch die dünne Zone ist dabei")
    eq(list[1].map, 10, "der dichteste Ort zuerst")
    eq(list[2].map, 14, "dann der beste Ort jeder weiteren Zone")
end)
