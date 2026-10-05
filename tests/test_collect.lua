-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Beute-Erfassung mit nachgebautem Beutefenster. Items: 100 = Kräuter, 101 = Erz, 102 = Edelstein,
-- 200 = Rüstung (kein Material).
local ITEMS = {
    [100] = { 7, 9 }, -- Handwerkswaren / Kräuter
    [101] = { 7, 7 }, -- Handwerkswaren / Erz
    [102] = { 3, 0 }, -- Edelstein
    [200] = { 4, 1 }, -- Rüstung
}

local function setup()
    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    DB.data = { version = 1, nodes = {}, npcs = {} }
    DB.db = { profile = { recording = true } }
    DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"
    stub.load("Glimpse_GatheringDB/Data/Store.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Data/Migrate.lua", "Glimpse_GatheringDB")

    -- Aktuelles Beutefenster: Liste aus { itemID, guid, menge }
    local window = {}
    DB.api = {
        GetItemInfoInstant = function(id) local c = ITEMS[id]; return id, "", "", "", "", c[1], c[2] end,
        GetNumLootItems = function() return #window end,
        GetLootSlotType = function() return 1 end,
        GetLootSlotLink = function(slot) return "|Hitem:" .. window[slot][1] .. ":0|h[x]|h" end,
        GetLootSourceInfo = function(slot) return window[slot][2], window[slot][3] or 1 end,
    }
    stub.load("Glimpse_GatheringDB/Loot/Collect.lua", "Glimpse_GatheringDB")
    DB:StartCollecting()

    local frame = stub.frames[#stub.frames]
    local env = { DB = DB, window = window }

    -- Zauber erfolgreich, dann Beutefenster öffnen und auswerten
    function env.cast(target)
        if target then frame.onEvent(frame, "UNIT_SPELLCAST_SENT", "player", target, "x", 1) end
        frame.onEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    end
    function env.loot(entries)
        for i in ipairs(window) do window[i] = nil end
        for _, entry in ipairs(entries) do window[#window + 1] = entry end
        DB:OnLootOpened()
        stub.now = stub.now + 0.4
        stub.flush()
    end
    return env
end

local NODE = "GameObject-0-3131-2552-14367-1731-0000A5C2B1"
local WOLF = "Creature-0-3131-2552-14367-179891-0000A5C2B1"

test("Collect: Sammelknoten nach Zauber wird erfasst", function()
    local e = setup()
    stub.now = 10
    e.cast("Kupfervorkommen")
    stub.now = 10.5
    e.loot({ { 101, NODE, 2 } })

    local node = e.DB:GetNode(1731)
    eq(node ~= nil, true, "Knoten gespeichert")
    eq(node.name, "Kupfervorkommen", "Name aus dem Zauberziel")
    eq(node.category, "ore", "Kategorie")
    eq(node.attempts, 1, "Versuche")
    eq(node.items[101].amount, 2, "Menge")
end)

test("Collect: Kräuter bekommen die Kategorie herb", function()
    local e = setup()
    stub.now = 5
    e.cast("Silberblatt")
    e.loot({ { 100, NODE } })
    eq(e.DB:GetNode(1731).category, "herb", "Kategorie")
end)

test("Collect: Truhe ohne Zauber wird nicht erfasst", function()
    local e = setup()
    stub.now = 50 -- letzter Zauber liegt lange zurück
    e.loot({ { 101, NODE } })
    eq(e.DB:GetNode(1731), nil, "keine Truhe")
end)

test("Collect: Knoten ohne Material wird nicht erfasst", function()
    local e = setup()
    stub.now = 5
    e.cast()
    e.loot({ { 200, NODE } })
    eq(e.DB:GetNode(1731), nil, "kein Material")
end)

test("Collect: Zauber kurz nach dem Beutefenster zählt auch", function()
    local e = setup()
    stub.now = 20
    -- Beutefenster zuerst, Zauber-Event im Verzögerungsfenster danach
    for i in ipairs(e.window) do e.window[i] = nil end
    e.window[1] = { 101, NODE, 1 }
    e.DB:OnLootOpened()
    stub.now = 20.1
    e.cast()
    stub.now = 20.4
    stub.flush()
    eq(e.DB:GetNode(1731) ~= nil, true, "erfasst")
end)

test("Collect: nur Materialien werden gespeichert, Versuch zählt trotzdem", function()
    local e = setup()
    stub.now = 100
    e.loot({ { 200, WOLF }, { 102, WOLF } })

    local npc = e.DB:GetNPC(179891)
    eq(npc.loot.attempts, 1, "Versuch")
    eq(npc.loot.items[102] ~= nil, true, "Edelstein gespeichert")
    eq(npc.loot.items[200], nil, "Rüstung nicht")
end)

test("Collect: leere Kreatur zählt als Versuch", function()
    local e = setup()
    stub.now = 100
    e.loot({ { 200, WOLF } })
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Versuch")
end)

test("Collect: Kürschnern wird nach dem Zauber erkannt", function()
    local e = setup()
    stub.now = 100
    e.loot({ { 102, WOLF } })                 -- Normalbeute
    stub.now = 130
    e.cast()
    e.loot({ { 100, WOLF } })                 -- Kürschnerbeute derselben Leiche

    local npc = e.DB:GetNPC(179891)
    eq(npc.loot.attempts, 1, "Normalbeute")
    eq(npc.skinning.attempts, 1, "Kürschnern")
end)

test("Collect: zweites Looten derselben Leiche zählt als Kürschnern, drittes nicht doppelt", function()
    local e = setup()
    stub.now = 100
    e.loot({ { 102, WOLF } })
    stub.now = 140
    e.loot({ { 100, WOLF } })
    stub.now = 180
    e.loot({ { 100, WOLF } })

    local npc = e.DB:GetNPC(179891)
    eq(npc.loot.attempts, 1, "Normalbeute einmal")
    eq(npc.skinning.attempts, 1, "Kürschnern einmal")
end)

test("Collect: Teilloot derselben Quelle zählt nicht doppelt", function()
    local e = setup()
    stub.now = 5
    e.cast("Silberblatt")
    e.loot({ { 100, NODE } })
    e.loot({ { 100, NODE } })
    eq(e.DB:GetNode(1731).attempts, 1, "nur einmal")
end)

test("Collect: Aufzeichnung aus = nichts wird gespeichert", function()
    local e = setup()
    e.DB.db.profile.recording = false
    stub.now = 100
    e.loot({ { 102, WOLF } })
    eq(e.DB:GetNPC(179891), nil, "nichts")
end)

test("Collect: Fehler in der Auswertung werden abgefangen und gemeldet", function()
    local e = setup()
    e.DB.RecordNPC = function() error("kaputt") end
    stub.now = 100
    e.loot({ { 102, WOLF } })
    eq(e.DB.errorCount, 1, "Fehlerzähler")
    eq(e.DB.lastError:find("kaputt", 1, true) ~= nil, true, "Text")
end)

test("Collect: Fehler beim Lesen des Beutefensters werden abgefangen", function()
    local e = setup()
    e.DB.api.GetNumLootItems = function() error("API weg") end
    e.DB:OnLootOpened()
    eq(e.DB.errorCount, 1, "Fehlerzähler")
end)

test("Collect: Compat meldet fehlende Funktionen", function()
    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    stub.load("Glimpse_GatheringDB/Core/Compat.lua", "Glimpse_GatheringDB")
    local ok, missing = DB:CheckAPI()
    eq(ok, false, "unvollständig")
    eq(#missing, 5, "alle fünf fehlen im Stub")
    for _, name in ipairs({ "GetItemInfoInstant", "GetNumLootItems", "GetLootSlotType", "GetLootSlotLink", "GetLootSourceInfo" }) do DB.api[name] = function() end end
    ok = DB:CheckAPI()
    eq(ok, true, "vollständig")
end)

-- ---------------------------------------------------------------------------
-- Fundorte
-- ---------------------------------------------------------------------------

local function withPosition(e, pos)
    e.DB.db.profile.trackLocations = true
    e.pos = pos
    e.DB.api.GetBestMapForUnit = function() return pos and pos.map end
    e.DB.api.GetPlayerMapPosition = function()
        if not e.pos then return nil end
        return { GetXY = function() return e.pos.x, e.pos.y end }
    end
end

test("Collect: Fundort wird mit der Beute gespeichert", function()
    local e = setup()
    withPosition(e, { map = 37, x = 0.25, y = 0.75 })
    stub.now = 5
    e.cast("Silberblatt")
    e.loot({ { 100, NODE } })

    local spots = e.DB:GetSpots("node", 1731)
    eq(#spots, 1, "ein Ort")
    eq(spots[1].map, 37, "Karte")
    near(spots[1].x, 0.25, "x")
    near(spots[1].y, 0.75, "y")
end)

test("Collect: Position gilt beim Öffnen des Beutefensters, nicht nach der Verzögerung", function()
    local e = setup()
    withPosition(e, { map = 37, x = 0.25, y = 0.25 })
    stub.now = 5
    e.cast("Silberblatt")

    e.window[1] = { 100, NODE, 1 }
    e.DB:OnLootOpened()
    e.pos = { map = 37, x = 0.9, y = 0.9 } -- Spieler läuft weiter, bevor ausgewertet wird
    stub.now = stub.now + 0.4
    stub.flush()

    local spots = e.DB:GetSpots("node", 1731)
    near(spots[1].x, 0.25, "Position vom Öffnen")
end)

test("Collect: Kreaturen bekommen den Fundort ebenfalls", function()
    local e = setup()
    withPosition(e, { map = 10, x = 0.5, y = 0.5 })
    stub.now = 5
    e.loot({ { 100, WOLF } })
    eq(#e.DB:GetSpots("npc", 179891), 1, "Ort der Kreatur")
end)

test("Collect: ohne Option oder ohne Position wird trotzdem aufgezeichnet", function()
    local e = setup()
    withPosition(e, { map = 37, x = 0.25, y = 0.75 })
    e.DB.db.profile.trackLocations = false
    stub.now = 5
    e.cast("Silberblatt")
    e.loot({ { 100, NODE } })
    eq(e.DB:GetNode(1731).attempts, 1, "Beute gezählt")
    eq(#e.DB:GetSpots("node", 1731), 0, "Option aus: kein Ort")

    -- Option an, aber keine Position (z. B. Instanz)
    e.DB.db.profile.trackLocations = true
    e.pos = nil
    stub.now = 20
    e.cast("Silberblatt")
    e.DB.itemIndex = nil
    stub.timers = {}
    -- dieselbe Quelle zählt pro Sitzung nur einmal, deshalb ein anderer Knoten
    e.loot({ { 100, "GameObject-0-3131-2552-14367-1732-0000A5C2B1" } })
    eq(e.DB:GetNode(1732).attempts, 1, "Beute gezählt")
    eq(#e.DB:GetSpots("node", 1732), 0, "keine Position: kein Ort")
end)

test("Collect: unbrauchbare Positionen werden verworfen", function()
    local e = setup()
    withPosition(e, { map = 37, x = 0, y = 0 }) -- (0, 0) = unbekannt
    stub.now = 5
    e.cast("Silberblatt")
    e.loot({ { 100, NODE } })
    eq(#e.DB:GetSpots("node", 1731), 0, "(0, 0)")

    -- ohne Kartenfunktionen
    local e2 = setup()
    e2.DB.db.profile.trackLocations = true
    e2.DB.api.GetBestMapForUnit, e2.DB.api.GetPlayerMapPosition = nil, nil
    stub.now = 5
    e2.cast("Silberblatt")
    e2.loot({ { 100, NODE } })
    eq(e2.DB:GetNode(1731).attempts, 1, "Beute gezählt")
    eq(#e2.DB:GetSpots("node", 1731), 0, "keine Kartenfunktionen")
end)

-- ---------------------------------------------------------------------------
-- Instanzen
-- ---------------------------------------------------------------------------

local function inInstance(e, kind, id, name)
    e.DB.api.IsInInstance = function() return kind ~= "none", kind end
    e.DB.api.GetInstanceInfo = function() return name, kind, 1, "Normal", 5, 0, false, id end
end

test("Collect: in einer Instanz ist die Instanz der Fundort, ohne Koordinaten", function()
    local e = setup()
    withPosition(e, { map = 37, x = 0.25, y = 0.75 }) -- selbst wenn die Karte Koordinaten liefern würde
    inInstance(e, "party", 36, "Die Todesminen")
    stub.now = 5
    e.loot({ { 100, WOLF } })

    local spots = e.DB:GetSpots("npc", 179891)
    eq(#spots, 1, "ein Ort")
    eq(spots[1].instance, 36, "Instanz")
    eq(spots[1].name, "Die Todesminen", "Name")
    eq(spots[1].map, nil, "keine Karte")
    eq(spots[1].x, nil, "keine Koordinaten")
    eq(e.DB.data.instances[36], "Die Todesminen", "Name gemerkt")
    eq(e.DB:GetPlayerPosition(), nil, "in der Instanz keine Position")
end)

test("Collect: gleiche Instanz zählt zusammen, andere Instanz und offene Welt getrennt", function()
    local e = setup()
    withPosition(e, { map = 37, x = 0.25, y = 0.75 })
    inInstance(e, "raid", 409, "Geschmolzener Kern")
    stub.now = 5
    e.loot({ { 100, "Creature-0-3131-2552-14367-179891-0000A5C2B1" } })
    e.DB.itemIndex = nil
    stub.now = 20
    e.loot({ { 100, "Creature-0-3131-2552-14367-179891-0000A5C2B2" } })
    inInstance(e, "party", 36, "Die Todesminen")
    stub.now = 40
    e.loot({ { 100, "Creature-0-3131-2552-14367-179891-0000A5C2B3" } })
    inInstance(e, "none", 0, "Azeroth")
    stub.now = 60
    e.loot({ { 100, "Creature-0-3131-2552-14367-179891-0000A5C2B4" } })

    local spots = e.DB:GetSpots("npc", 179891)
    eq(#spots, 3, "Kern, Todesminen und Karte")
    eq(spots[1].instance, 409, "häufigster Ort zuerst")
    eq(spots[1].count, 2, "zweimal im Kern")
    local sawMap = false
    for _, spot in ipairs(spots) do if spot.map == 37 then sawMap = true end end
    eq(sawMap, true, "offene Welt als Karte gespeichert")
end)

test("Collect: unbrauchbare Instanzangaben ergeben keinen Fundort", function()
    local e = setup()
    e.DB.db.profile.trackLocations = true
    e.DB.api.IsInInstance = function() return true, "party" end
    e.DB.api.GetInstanceInfo = function() return "Etwas", "party", 1, "", 5, 0, false, nil end
    eq(e.DB:GetPlayerInstance(), nil, "ohne Instanz-ID")

    -- ohne die Funktionen
    e.DB.api.IsInInstance, e.DB.api.GetInstanceInfo = nil, nil
    eq(e.DB:GetPlayerInstance(), nil, "ohne Spielfunktionen")

    -- Option aus: auch in Instanzen kein Ort
    inInstance(e, "party", 36, "Die Todesminen")
    e.DB.db.profile.trackLocations = false
    stub.now = 5
    e.loot({ { 100, WOLF } })
    eq(#e.DB:GetSpots("npc", 179891), 0, "Option aus")
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Beute trotzdem gezählt")
end)
