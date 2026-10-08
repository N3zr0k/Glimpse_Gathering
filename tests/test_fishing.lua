-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Angeln: Aufzeichnung (Core/Loot/Fishing.lua), Speicherung (Core/Data/Store.lua), Pflege und Austausch der Daten
-- Items: 300 = Fisch (Handwerkswaren), 301 = Schrott (Verbrauchsgut), 200 = Rüstung. Zauber 7620 = Fischen.
local ITEMS = { [300] = { 7, 8 }, [301] = { 0, 0 }, [200] = { 4, 1 } }

local function setup()
    stub.libs.LibDeflate = nil
    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    DB.DATA_VERSION = 6
    DB.data = { version = 6, nodes = {}, npcs = {}, fishing = {}, imports = {} }
    DB.db = { profile = { recording = true, trackLocations = true } }
    DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"
    stub.load("Glimpse_GatheringDB/Core/Data/Spots.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Store.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Names.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Migrate.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Transfer.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Providers.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Data/Sources.lua", "Glimpse_GatheringDB")

    -- Zeitgeber, die ihre Wartezeit beachten (der Standard der Tests führt alle auf einmal aus)
    local timers = {}
    _G.C_Timer = { After = function(delay, func) timers[#timers + 1] = { due = stub.now + delay, func = func } end }

    local window = {}
    local env = { DB = DB, window = window, fishing = true }
    DB.api = {
        GetItemInfoInstant = function(id) local c = ITEMS[id]; return id, "", "", "", "", c[1], c[2] end,
        GetNumLootItems = function() return #window end,
        GetLootSlotType = function() return 1 end,
        GetLootSlotLink = function(slot) return "|Hitem:" .. window[slot][1] .. ":0|h[x]|h" end,
        GetLootSourceInfo = function(slot) return window[slot][2], window[slot][3] or 1 end,
        IsFishingLoot = function() return env.fishing end,
        GetSpellName = function(id) return (id == 7620 or id == 7731) and "Fischen" or "Anderes" end,
    }
    stub.load("Glimpse_GatheringDB/Core/Loot/Collect.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Loot/LootWindow.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Loot/Fishing.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Loot/Kills.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Loot/Area.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Loot/Events.lua", "Glimpse_GatheringDB")
    DB:StartCollecting()
    local frame = stub.frames[#stub.frames]

    local Locations = Glimpse:GetModule("Locations")
    env.pos = { map = 37, x = 0.25, y = 0.75 }
    Locations.api.GetBestMapForUnit = function() return env.pos and env.pos.map end
    Locations.api.GetPlayerMapPosition = function()
        if not env.pos then return nil end
        return { GetXY = function() return env.pos.x, env.pos.y end }
    end

    function env.flush()
        local due, rest = {}, {}
        for _, timer in ipairs(timers) do tinsert(timer.due <= stub.now and due or rest, timer) end
        timers = rest
        for _, timer in ipairs(due) do timer.func() end
    end
    function env.stop(spell)
        frame.onEvent(frame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "", spell or 7620)
    end
    function env.cast(spell)
        frame.onEvent(frame, "UNIT_SPELLCAST_SENT", "player", "", "x", spell or 7620)
    end
    function env.loot(entries)
        for i in ipairs(window) do window[i] = nil end
        for _, entry in ipairs(entries) do window[#window + 1] = entry end
        DB:OnLootOpened()
        stub.now = stub.now + 0.4
        env.flush()
    end
    return env
end

test("Angeln: ein Fang wird in der Zone gezählt, mit Fundort", function()
    local e = setup()
    stub.now = 10
    e.cast()
    stub.now = 22 -- der Fisch beißt erst später
    e.loot({ { 300, "GameObject-0-1-2-3-35591-0000", 1 } })

    e.flush()
    local zone = e.DB:GetFishing(37)
    assert(zone, "Zone gespeichert")
    eq(zone.attempts, 1, "Würfe")
    eq(zone.items[300].hits, 1, "Fisch")
    eq(#zone.spots, 1, "Fundort")
    eq(#e.DB:GetSpots("fishing", 37), 1, "Fundort über die Schnittstelle")
    eq(e.DB:GetNode(35591), nil, "der Schwimmer ist kein Sammelknoten")
end)

test("Angeln: Würfe ohne Fang zählen als Versuch, Schrott nicht als Fang", function()
    local e = setup()
    -- drei Fänge (einer mit Schrott und Rüstung dabei), ein Wurf ohne Fenster
    for i = 1, 3 do
        stub.now = i * 30
        e.cast()
        e.loot({ { 300, "GameObject-0-1-2-3-1-0", 1 }, { 200, "GameObject-0-1-2-3-1-0", 1 }, { 301, "GameObject-0-1-2-3-1-0", 1 } })
    end
    stub.now = 120
    e.cast()
    stub.now = 170
    e.flush() -- Wartezeit abgelaufen: Wurf ohne Fang

    local drops, attempts = e.DB:GetFishingDrops(37)
    eq(attempts, 4, "vier Würfe")
    eq(#drops, 1, "nur der Fisch, kein Schrott")
    near(drops[1].chance, 0.75, "Chance 3 von 4")
end)

test("Angeln: ein neuer Wurf schließt den vorigen ohne Fang ab", function()
    local e = setup()
    stub.now = 10
    e.cast()
    stub.now = 20
    e.cast() -- der erste blieb ohne Fenster
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    local _, attempts = e.DB:GetFishingDrops(37)
    eq(attempts, 2, "beide Würfe gezählt")
    eq(e.DB:GetFishing(37).items[300].hits, 1, "ein Fang")
end)

test("Angeln: andere Zauber und andere Ränge des Fischens", function()
    local e = setup()
    e.cast(1234) -- kein Fischen
    stub.now = stub.now + 100
    e.flush()
    eq(e.DB:GetFishing(37), nil, "anderer Zauber zählt nicht")

    e.cast(7731) -- anderer Rang, gleicher Name
    stub.now = stub.now + 100
    e.flush()
    eq(e.DB:GetFishing(37).attempts, 1, "Rang erkannt")
end)

test("Angeln: dasselbe Fenster zweimal geöffnet zählt einmal", function()
    local e = setup()
    stub.now = 10
    e.cast()
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    stub.now = 14
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    eq(e.DB:GetFishing(37).attempts, 1, "ein Wurf")
end)

test("Angeln: ohne Option für Fundorte nur die Zone, in einer Instanz nichts", function()
    local e = setup()
    e.DB.db.profile.trackLocations = false
    stub.now = 10
    e.cast()
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    eq(e.DB:GetFishing(37).spots, nil, "kein Ort")

    local f = setup()
    f.pos = nil -- keine Karte
    stub.now = 10
    f.cast()
    f.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    eq(next(f.DB.data.fishing), nil, "ohne Zone nichts gespeichert")
end)

test("Angeln: Quelle im Index eines Fisches", function()
    local e = setup()
    stub.now = 10
    e.cast()
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })

    local sources = e.DB:GetItemSources(300)
    eq(#sources, 1, "eine Quelle")
    eq(sources[1].kind, "fishing", "Art")
    eq(sources[1].id, 37, "Karte")
    eq(sources[1].mode, "fishing", "Modus")
    near(sources[1].chance, 1, "Chance")
    eq(#e.DB:GetLocatedItemSources(300), 1, "mit Ort")
end)

test("Angeln: Export, Import, Zusammenführen und Zurücksetzen", function()
    local a = setup()
    a.DB:RecordFishing(37, { [300] = 2 }, { map = 37, x = 0.5, y = 0.5 })
    a.DB:RecordFishing(37, {}, nil)
    local text, info = a.DB:ExportData()
    eq(info.fishing, 1, "Zonen im Export")

    local b = setup()
    b.DB:RecordFishing(37, { [300] = 1 }, nil)
    local ok, res = b.DB:ImportData(text)
    eq(ok, true, "Import")
    eq(res.fishing, 1, "Zonen importiert")
    eq(b.DB:GetFishing(37).attempts, 3, "Würfe zusammengeführt")
    eq(b.DB:GetFishing(37).items[300].hits, 2, "Treffer zusammengeführt")
    eq(#b.DB:GetFishing(37).spots, 1, "Ort übernommen")

    local _, zones, casts = nil, select(5, b.DB:GetStats()), select(6, b.DB:GetStats())
    eq(zones, 1, "Statistik: Zonen"); eq(casts, 3, "Statistik: Würfe")

    b.DB:ResetData()
    eq(next(b.DB.data.fishing), nil, "zurückgesetzt")
end)

test("Angeln: ältere Daten bekommen die Tabelle, defekte Zonen fallen weg", function()
    local e = setup()
    local data = { version = 5, nodes = {}, npcs = {} }
    eq(e.DB:UpgradeData(data, 6), true, "Umstellung")
    eq(type(data.fishing), "table", "fishing angelegt")

    data.fishing[37] = { attempts = 2, items = { [300] = { hits = 5, amount = 5 } } } -- Treffer über den Würfen
    data.fishing["x"] = { attempts = 1, items = {} }
    data.fishing[38] = "kaputt"
    e.DB:SanitizeData(data)
    eq(data.fishing[37].items[300], nil, "unmöglicher Fang entfernt")
    eq(data.fishing["x"], nil, "falscher Schlüssel")
    eq(data.fishing[38], nil, "kein Eintrag")
end)

test("Angeln: Symbol und Überschrift im Tooltip", function()
    local Glimpse = stub.newGlimpse()
    local GT = Glimpse:NewModule("GatheringTooltip")
    GT.L = Glimpse.L
    GT.db = { profile = { showLocations = true } }
    stub.load("Glimpse_GatheringTooltip/Core/Tooltip/Sources.lua", "Glimpse_GatheringTooltip")
    eq(GT:SourceIcon({ kind = "fishing" }), "Interface\\Icons\\Trade_Fishing", "Symbol")
    local key, title = GT:SourceGroup({ kind = "fishing" })
    eq(key, "fishing", "Gruppe"); eq(title, "Fishing", "Überschrift")
end)

test("Angeln: Ende des Zaubers ohne Beutefenster schließt den Wurf nach kurzer Wartezeit ab", function()
    local e = setup()
    stub.now = 10
    e.cast()
    stub.now = 25
    e.stop()
    stub.now = 26
    e.flush()
    eq(e.DB:GetFishing(37), nil, "noch in der Wartezeit")
    stub.now = 29.5
    e.flush()
    eq(e.DB:GetFishing(37).attempts, 1, "Wurf ohne Fang gezählt, ohne 45 Sekunden")
    eq(next(e.DB:GetFishing(37).items), nil, "kein Fang")
end)

test("Angeln: Klick mit Fang kurz nach dem Ende des Zaubers zählt als ein Wurf", function()
    local e = setup()
    stub.now = 10
    e.cast()
    stub.now = 25
    e.stop()
    stub.now = 26
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    stub.now = 40
    e.flush()
    eq(e.DB:GetFishing(37).attempts, 1, "ein Versuch")
    eq(e.DB:GetFishing(37).items[300].hits, 1, "mit Fang")
end)

test("Angeln: Fenster nach schon gezähltem leerem Wurf wird dem Wurf zugerechnet", function()
    local e = setup()
    stub.now = 10
    e.cast()
    stub.now = 25
    e.stop()
    stub.now = 29.5
    e.flush() -- als leer gezählt
    stub.now = 33
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    eq(e.DB:GetFishing(37).attempts, 1, "kein zweiter Versuch")
    eq(e.DB:GetFishing(37).items[300].hits, 1, "Fang nachgetragen")
end)

test("Angeln: Meldung 'Fisch entkommen' beendet den Wurf sofort, andere Meldungen nicht", function()
    _G.ERR_FISH_ESCAPED = "Der Fisch ist entkommen."
    _G.ERR_FISH_NOT_HOOKED = "Kein Fisch hat angebissen."
    local e = setup()
    local frame = stub.frames[#stub.frames]

    stub.now = 10
    e.cast()
    frame.onEvent(frame, "UI_ERROR_MESSAGE", 1, "Kein Fisch hat angebissen.")
    eq(e.DB:GetFishing(37), nil, "angebissen-Meldung zählt noch nicht")
    frame.onEvent(frame, "UI_ERROR_MESSAGE", 1, "Der Fisch ist entkommen.")
    eq(e.DB:GetFishing(37).attempts, 1, "entkommen: Wurf ohne Fang gezählt")

    -- ohne laufenden Wurf passiert nichts
    frame.onEvent(frame, "UI_ERROR_MESSAGE", 1, "Der Fisch ist entkommen.")
    eq(e.DB:GetFishing(37).attempts, 1, "nicht doppelt")
    _G.ERR_FISH_ESCAPED, _G.ERR_FISH_NOT_HOOKED = nil, nil
end)

test("Angeln: Zähler dieser Sitzung (ausgeworfen, Beutefenster, ohne Fang)", function()
    local e = setup()
    stub.now = 10
    e.cast()
    e.loot({ { 300, "GameObject-0-1-2-3-1-0" } })
    stub.now = 30
    e.cast()
    stub.now = 40
    e.cast() -- der zweite Wurf blieb ohne Fenster
    stub.now = 100
    e.flush()
    local session = e.DB.fishingSession
    eq(session.casts, 3, "ausgeworfen"); eq(session.windows, 1, "Beutefenster"); eq(session.misses, 2, "ohne Fang")
end)

test("Angeln: Schwimmer wird während eines Wurfs am Namen erkannt", function()
    local e = setup()
    eq(e.DB:IsBobber("Schwimmer"), false, "ohne Wurf nicht")
    stub.now = 10
    e.cast()
    eq(e.DB:IsFishing(), true, "Wurf läuft")
    eq(e.DB:IsBobber("Schwimmer"), true, "Wurf läuft, unbekannter Name")
    eq(e.DB:IsBobber(nil), false, "ohne Namen nicht")

    e.DB.data.nodes[1731] = { name = "Kupfervorkommen", category = "ore", attempts = 1, items = {} }
    e.DB.nameIndex = nil -- Namensindex neu aufbauen
    eq(e.DB:IsBobber("Kupfervorkommen"), false, "bekannter Knoten ist kein Schwimmer")
end)
