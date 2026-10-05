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
