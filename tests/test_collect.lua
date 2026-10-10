-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")
local function Locations() return LibStub():GetAddon():GetModule("Locations") end

-- Beute-Erfassung mit nachgebautem Beutefenster. Items: 100 = Kräuter, 101 = Erz, 102 = Edelstein,
-- 200 = Rüstung (kein Material).
local ITEMS = {
    [100] = { 7, 9 }, -- Handwerkswaren / Kräuter
    [101] = { 7, 7 }, -- Handwerkswaren / Erz
    [102] = { 3, 0 }, -- Edelstein
    [200] = { 4, 1 }, -- Rüstung
}

local function setup()
    -- Aktuelles Beutefenster: Liste aus { itemID, guid, menge }
    local window = {}
    local DB = stub.newGatheringDB({ api = {
        GetItemInfoInstant = function(id) local c = ITEMS[id]; return id, "", "", "", "", c[1], c[2] end,
        GetNumLootItems = function() return #window end,
        GetLootSlotType = function() return 1 end,
        GetLootSlotLink = function(slot) return "|Hitem:" .. window[slot][1] .. ":0|h[x]|h" end,
        GetLootSourceInfo = function(slot) return window[slot][2], window[slot][3] or 1 end,
    } })
    DB.db.profile.trackLocations = false

    local frame = stub.frames[#stub.frames]
    local env = { DB = DB, window = window, frame = frame }

    -- Zauber erfolgreich, dann Beutefenster öffnen und auswerten
    function env.cast(target, spellID)
        if target then frame.onEvent(frame, "UNIT_SPELLCAST_SENT", "player", target, "x", 1) end
        frame.onEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player", "x", spellID)
    end
    function env.loot(entries)
        for i in ipairs(window) do window[i] = nil end
        for _, entry in ipairs(entries) do window[#window + 1] = entry end
        DB:OnLootOpened()
        stub.now = stub.now + 0.4
        stub.flush()
    end
    -- Zähler dieses Charakters im Namespace gathering
    function env.count(kind, id) return GlimpseDB:Get("gathering"):GetCount(kind, id) end
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

test("Collect: zweites Looten derselben Leiche nach einem Zauber zählt als Kürschnern, drittes nicht doppelt", function()
    local e = setup()
    stub.now = 100
    e.loot({ { 102, WOLF } })
    stub.now = 140
    e.loot({ { 100, WOLF } })                 -- ohne Zauber: dieselbe Leiche erneut geöffnet
    eq(e.DB:GetNPC(179891).skinning, nil, "ohne Zauber kein Kürschnern")
    stub.now = 160
    e.cast()
    e.loot({ { 100, WOLF } })
    stub.now = 180
    e.cast()
    e.loot({ { 100, WOLF } })

    local npc = e.DB:GetNPC(179891)
    eq(npc.loot.attempts, 1, "Normalbeute einmal")
    eq(npc.skinning.attempts, 1, "Kürschnern einmal")
end)

test("Collect: der Zauber Kürschnern erkennt die Kürschnerbeute auch ohne vorheriges Looten", function()
    local e = setup()
    stub.now = 100
    e.cast(nil, 8613)
    e.loot({ { 100, WOLF, 2 } })

    local npc = e.DB:GetNPC(179891)
    eq(npc.loot, nil, "keine Normalbeute")
    eq(npc.skinning.attempts, 1, "Kürschnern")
    eq(npc.skinning.items[100].amount, 2, "Menge")
    eq(e.count("skinned", 179891), 1, "Weltwissen skinned")
    eq(e.count("skin", 179891), 1, "eigener Zähler skin")
    eq(e.count("skinloot:179891", 100), 2, "skinloot")
    eq(e.count("skindrop:179891", 100), 1, "skindrop")
end)

test("Collect: andere Ränge von Kürschnern über den Zaubernamen", function()
    local e = setup()
    e.DB.api.GetSpellName = function(id) return (id == 8613 or id == 99999) and "Kürschnern" or "Anderes" end
    stub.now = 100
    e.cast(nil, 99999)
    e.loot({ { 100, WOLF } })
    eq(e.DB:GetNPC(179891).skinning.attempts, 1, "unbekannte ID mit gleichem Namen")

    stub.now = 200
    e.cast(nil, 12345)
    e.loot({ { 100, "Creature-0-3131-2552-14367-555-0000A5C2B1" } })
    eq(e.DB:GetNPC(555).skinning, nil, "anderer Zauber ohne vorheriges Looten ist Normalbeute")
end)

test("Collect: Teilloot derselben Quelle zählt nicht doppelt", function()
    local e = setup()
    stub.now = 5
    e.cast("Silberblatt")
    e.loot({ { 100, NODE } })
    e.loot({ { 100, NODE } })
    eq(e.DB:GetNode(1731).attempts, 1, "nur einmal")
end)

test("Collect: nachgewachsener Knoten mit gleicher GUID zählt wieder", function()
    local e = setup()
    stub.now = 10
    e.cast("Kupfervorkommen")
    e.loot({ { 101, NODE } })
    stub.now = 300 -- Knoten ist nachgewachsen, gleiche GUID
    e.cast("Kupfervorkommen")
    e.loot({ { 101, NODE } })
    eq(e.DB:GetNode(1731).attempts, 2, "beide Male erfasst")
end)

test("Collect: derselbe Knoten mehrmals hintereinander abgebaut zählt jedes Mal", function()
    local e = setup()
    stub.now = 10
    e.cast("Kupfervorkommen")
    e.loot({ { 101, NODE, 2 } })
    stub.now = 14 -- gleich der nächste Abbau am selben Knoten, wenige Sekunden später
    e.cast("Kupfervorkommen")
    e.loot({ { 101, NODE, 3 } })
    stub.now = 18
    e.cast("Kupfervorkommen")
    e.loot({ { 101, NODE, 1 } })
    local node = e.DB:GetNode(1731)
    eq(node.attempts, 3, "drei Abbauten")
    eq(node.items[101].amount, 6, "alle Mengen")
end)

test("Collect: erneut geöffnetes Fenster desselben Abbaus zählt nicht, auch ohne SUCCEEDED", function()
    local e = setup()
    local frame = stub.frames[#stub.frames]
    stub.now = 10
    frame.onEvent(frame, "UNIT_SPELLCAST_SENT", "player", "Kupfervorkommen", "x", 1)
    stub.now = 13
    e.loot({ { 101, NODE } })
    stub.now = 14
    e.loot({ { 101, NODE } })
    eq(e.DB:GetNode(1731).attempts, 1, "einmal")
end)

test("Collect: Knoten ohne UNIT_SPELLCAST_SUCCEEDED, aber mit abgeschicktem Zauber wird erfasst", function()
    local e = setup()
    local frame = stub.frames[#stub.frames]
    stub.now = 10
    frame.onEvent(frame, "UNIT_SPELLCAST_SENT", "player", "Kupfervorkommen", "x", 1)
    stub.now = 13 -- Zauberdauer, danach das Beutefenster, kein SUCCEEDED
    e.loot({ { 101, NODE } })
    eq(e.DB:GetNode(1731) ~= nil, true, "erfasst")
end)

test("Collect: Debug nennt den Grund, wenn ein Knoten übersprungen wird", function()
    local e = setup()
    stub.now = 500
    e.loot({ { 101, NODE } })
    local text = table.concat(stub.debugLines, "\n")
    eq(text:find("Knoten übersprungen: kein Zauber", 1, true) ~= nil, true, "Grund steht im Debug")
end)

-- Das Ziel stirbt: UNIT_HEALTH mit totem Ziel. tapDenied = ein anderer Spieler hat das Tap.
local function withCombatLog(guid, tapDenied)
    stub.units.target = { guid = guid, dead = true, tapDenied = tapDenied }
    _G.UnitIsDead = function(unit) return stub.units[unit] and stub.units[unit].dead end
    _G.UnitIsTapDenied = function(unit) return stub.units[unit] and stub.units[unit].tapDenied end
    local frame = stub.frames[#stub.frames]
    frame.onEvent(frame, "UNIT_HEALTH", "target")
end

test("Collect: Kill ohne Beutefenster zählt als Ersatz erst nach der Wartezeit", function()
    local e = setup()
    _G.CanLootUnit = function() return false, false end
    stub.now = 100
    withCombatLog(WOLF)
    stub.now = 101.6
    stub.flush()
    eq(e.DB:GetNPC(179891), nil, "Beutefenster hat Vorrang, noch nichts gezählt")
    stub.now = 230
    stub.flush()
    _G.CanLootUnit = nil
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Versuch ohne Beute")
end)

test("Collect: Kill einer Leiche mit Beute zählt erst beim Looten", function()
    local e = setup()
    _G.CanLootUnit = function() return true, true end
    stub.now = 100
    withCombatLog(WOLF)
    stub.now = 101.6
    stub.flush()
    _G.CanLootUnit = nil
    eq(e.DB:GetNPC(179891), nil, "noch nichts gezählt")
    stub.now = 105
    e.loot({ { 102, WOLF } })
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "ein Versuch durch das Beutefenster")
end)

test("Collect: der Kill zählt nach der Wartezeit, ein Beutefenster davor hat Vorrang", function()
    local e = setup()
    stub.now = 100
    withCombatLog(WOLF)
    stub.now = 101.6
    stub.flush()
    eq(e.DB:GetNPC(179891), nil, "wartet noch")
    stub.now = 230
    stub.flush()
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "nach der Wartezeit gezählt")

    -- zweite Kreatur wird vorher gelootet: kein doppelter Versuch
    local other = "Creature-0-3131-2552-14367-555-0000A5C2B1"
    stub.now = 300
    withCombatLog(other)
    stub.now = 302
    stub.flush()
    e.loot({ { 102, other } })
    stub.now = 500
    stub.flush()
    eq(e.DB:GetNPC(555).loot.attempts, 1, "genau ein Versuch")
    eq(e.DB:GetNPC(555).loot.items[102].hits, 1, "Beute gezählt")
end)

test("Collect: Beute nach einem als leer gezählten Kill kommt dazu, ohne neuen Versuch", function()
    local e = setup()
    stub.now = 100
    withCombatLog(WOLF)
    stub.now = 101.6
    stub.flush()
    stub.now = 230
    stub.flush()                 -- Ersatz greift: Kill zählt als leerer Versuch
    stub.now = 250
    e.loot({ { 102, WOLF } })    -- Beutefenster geht doch noch auf
    local npc = e.DB:GetNPC(179891)
    eq(npc.loot.attempts, 1, "weiter ein Versuch")
    eq(npc.loot.items[102].hits, 1, "Beute trotzdem erfasst")
    eq(npc.skinning, nil, "kein Kürschnern")
end)

test("Collect: ein Kill wird nicht gespeichert, nur der Versuch nach der Wartezeit", function()
    local e = setup()
    stub.now = 100
    withCombatLog(WOLF)
    stub.now = 101.6
    stub.flush()
    eq(e.DB:GetNPC(179891), nil, "der Kill allein speichert nichts")

    -- dieselbe Leiche stirbt im Event mehrfach (UNIT_HEALTH kommt oft): ein Versuch
    stub.now = 102
    withCombatLog(WOLF)
    stub.now = 230
    stub.flush()
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "ein Versuch")
    eq(e.DB:GetNPC(179891).kills, nil, "kein Kill-Zähler")

    -- zweite Leiche gleicher Art (andere GUID): eigener Versuch
    local other = "Creature-0-3131-2552-14367-179891-0000A5C2B2"
    stub.now = 240
    withCombatLog(other)
    stub.now = 241.6
    stub.flush()
    stub.now = 400
    stub.flush()
    eq(e.DB:GetNPC(179891).loot.attempts, 2, "zwei Versuche")
end)

test("Collect: gelootete Leiche ist ein Versuch, Kürschnern kein zweiter", function()
    local e = setup()
    stub.now = 100
    e.loot({ { 102, WOLF } })
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Versuch")

    stub.now = 140
    e.cast()
    e.loot({ { 100, WOLF } }) -- Kürschnern derselben Leiche
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Kürschnern ist kein zweiter Versuch")
end)

test("Collect: Kill im Ziel und anschließendes Looten zählen nur einen Versuch", function()
    local e = setup()
    stub.now = 100
    withCombatLog(WOLF)
    stub.now = 101.6
    stub.flush()
    stub.now = 105
    e.loot({ { 102, WOLF } })
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "ein Versuch")
end)

test("Collect: ohne Aufzeichnung kein Versuch durch Kills", function()
    local e = setup()
    e.DB.db.profile.recording = false
    stub.now = 100
    withCombatLog(WOLF)
    stub.now = 102
    stub.flush()
    stub.now = 230
    stub.flush()
    eq(select(2, e.DB:GetStats()), 0, "nichts gespeichert")
end)

test("Collect: Kill wird auch beim Zielwechsel auf eine Leiche und am Kampfende erkannt", function()
    local e = setup()
    local frame = stub.frames[#stub.frames]
    _G.UnitIsDead = function(unit) return stub.units[unit] and stub.units[unit].dead end
    _G.UnitIsTapDenied = function(unit) return stub.units[unit] and stub.units[unit].tapDenied end

    stub.now = 100
    stub.units.target = { guid = WOLF, dead = true }
    frame.onEvent(frame, "PLAYER_TARGET_CHANGED")
    stub.now = 101.6
    stub.flush()
    stub.now = 230
    stub.flush()
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Zielwechsel auf die Leiche")

    local other = "Creature-0-3131-2552-14367-555-0000A5C2B1"
    stub.units.target = { guid = other, dead = true }
    frame.onEvent(frame, "PLAYER_REGEN_ENABLED")
    stub.now = 231.6
    stub.flush()
    stub.now = 400
    stub.flush()
    eq(e.DB:GetNPC(555).loot.attempts, 1, "Kampfende")
end)

test("Collect: geschützte GUID im Kampf: die zuletzt lesbare GUID des Ziels gilt", function()
    local e = setup()
    local frame = stub.frames[#stub.frames]
    local Glimpse = LibStub():GetAddon()
    function Glimpse:IsSecret(value) return value == "SECRET" end
    _G.UnitIsDead = function(unit) return stub.units[unit] and stub.units[unit].dead end
    _G.UnitIsTapDenied = function() return false end

    stub.now = 100
    stub.units.target = { guid = WOLF, dead = false }
    frame.onEvent(frame, "PLAYER_TARGET_CHANGED")       -- GUID lesbar, Ziel lebt
    stub.units.target = { guid = "SECRET", dead = true } -- im Kampf geschützt, Ziel stirbt
    frame.onEvent(frame, "UNIT_HEALTH", "target")
    stub.now = 101.6
    stub.flush()
    stub.now = 230
    stub.flush()
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Kill mit der gemerkten GUID")

    -- anderes Ziel mit geschützter GUID: nichts raten
    stub.units.target = { guid = "SECRET", dead = false }
    frame.onEvent(frame, "PLAYER_TARGET_CHANGED")
    stub.units.target = { guid = "SECRET", dead = true }
    frame.onEvent(frame, "UNIT_HEALTH", "target")
    stub.now = 400
    stub.flush()
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "kein zweiter Versuch durch die alte GUID")
    local text = table.concat(stub.debugLines, "\n")
    eq(text:find("GUID ist unbekannt", 1, true) ~= nil, true, "Debug nennt den Grund")
end)

test("Collect: Kills mit fremdem Tap zählen nicht, eigene Kills schon", function()
    local e = setup()
    stub.now = 100
    withCombatLog(WOLF, true)
    stub.now = 102
    stub.flush()
    stub.now = 230
    stub.flush()
    eq(e.DB:GetNPC(179891), nil, "fremder Kill ignoriert")
    withCombatLog(WOLF)
    stub.now = 232
    stub.flush()
    stub.now = 400
    stub.flush()
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "eigener Kill gezählt")
end)

test("Collect: Kills nur von Kreaturen, nicht von Spielern", function()
    local e = setup()
    stub.now = 100
    withCombatLog("Player-9-0000A5C2B1")
    stub.now = 102
    stub.flush()
    stub.now = 230
    stub.flush()
    eq(select(2, e.DB:GetStats()), 0, "nichts gespeichert")
end)

test("Collect: Leiche, die nach langer Zeit mit gleicher GUID wiederkommt, ist neue Normalbeute", function()
    local e = setup()
    stub.now = 100
    e.loot({ { 102, WOLF } })
    stub.now = 1000 -- Respawn mit gleicher GUID
    e.loot({ { 102, WOLF } })
    local npc = e.DB:GetNPC(179891)
    eq(npc.loot.attempts, 2, "zwei Normalbeuten")
    eq(npc.skinning, nil, "kein Kürschnern")
end)

test("Collect: der Kampflog wird nicht registriert (für Addons gesperrt)", function()
    setup()
    local frame = stub.frames[#stub.frames]
    eq(frame.events["COMBAT_LOG_EVENT_UNFILTERED"], nil, "kein Kampflog")
    eq(frame.events["UNIT_HEALTH"], true, "Zieltod wird beobachtet")
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
    local DB = Glimpse:NewModule("GatheringData")
    stub.load("Glimpse_Gathering/Core/Compat.lua", "Glimpse_Gathering")
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
    Locations().api.GetBestMapForUnit = function() return pos and pos.map end
    Locations().api.GetPlayerMapPosition = function()
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
    Locations().api.GetBestMapForUnit, Locations().api.GetPlayerMapPosition = nil, nil
    stub.now = 5
    e2.cast("Silberblatt")
    e2.loot({ { 100, NODE } })
    eq(e2.DB:GetNode(1731).attempts, 1, "Beute gezählt")
    eq(#e2.DB:GetSpots("node", 1731), 0, "keine Kartenfunktionen")
end)

-- ---------------------------------------------------------------------------
-- Instanzen
-- ---------------------------------------------------------------------------

local function inInstance(_, kind, id, name)
    Locations().api.IsInInstance = function() return kind ~= "none", kind end
    Locations().api.GetInstanceInfo = function() return name, kind, 1, "Normal", 5, 0, false, id end
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
    eq(e.DB:GetInstanceName(36), "Die Todesminen", "Name gemerkt")
    eq(Locations():GetPlayerPosition(), nil, "in der Instanz keine Position")
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
    Locations().api.IsInInstance = function() return true, "party" end
    Locations().api.GetInstanceInfo = function() return "Etwas", "party", 1, "", 5, 0, false, nil end
    eq(Locations():GetPlayerInstance(), nil, "ohne Instanz-ID")

    -- ohne die Funktionen
    Locations().api.IsInInstance, Locations().api.GetInstanceInfo = nil, nil
    eq(Locations():GetPlayerInstance(), nil, "ohne Spielfunktionen")

    -- Option aus: auch in Instanzen kein Ort
    inInstance(e, "party", 36, "Die Todesminen")
    e.DB.db.profile.trackLocations = false
    stub.now = 5
    e.loot({ { 100, WOLF } })
    eq(#e.DB:GetSpots("npc", 179891), 0, "Option aus")
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Beute trotzdem gezählt")
end)

test("Collect: Debug-Ausgabe nennt Position und gespeicherten Fundort", function()
    local e = setup()
    Locations().api.GetMapInfo = function() return { name = "Elwynn" } end
    withPosition(e, { map = 37, x = 0.412, y = 0.568 })
    stub.now = 5
    e.cast("Silberblatt")
    e.loot({ { 100, NODE } })

    local text = table.concat(stub.debugLines, "\n")
    eq(text:find("Position: Karte Elwynn (37) 41.2 / 56.8", 1, true) ~= nil, true, "Position")
    eq(text:find("Gespeichert: Knoten 1731 (Silberblatt), Fundort: Karte Elwynn (37) 41.2 / 56.8", 1, true) ~= nil, true, "Fundort des Knotens")

    -- in einer Instanz
    stub.debugLines = {}
    inInstance(e, "party", 36, "Die Todesminen")
    stub.now = 40
    e.loot({ { 100, WOLF } })
    text = table.concat(stub.debugLines, "\n")
    eq(text:find("Position: Instanz Die Todesminen (36)", 1, true) ~= nil, true, "Instanz als Position")
    eq(text:find("Gespeichert: Kreatur 179891 loot, Fundort: Instanz Die Todesminen (36)", 1, true) ~= nil, true, "Fundort der Kreatur")
end)

test("Collect: Debug-Ausgabe erklärt fehlende Orte", function()
    local e = setup()
    e.DB.db.profile.trackLocations = true
    stub.now = 5
    e.loot({ { 100, WOLF } })
    local text = table.concat(stub.debugLines, "\n")
    eq(text:find("Position: nicht bestimmbar", 1, true) ~= nil, true, "keine Position")
    eq(text:find("Fundort: keiner", 1, true) ~= nil, true, "kein Fundort")

    stub.debugLines = {}
    e.DB.db.profile.trackLocations = false
    stub.now = 40
    e.loot({ { 100, "Creature-0-3131-2552-14367-179892-0000A5C2B1" } })
    eq(table.concat(stub.debugLines, "\n"):find("Aufzeichnung der Fundorte ist aus", 1, true) ~= nil, true, "Option aus")
end)

test("Collect: Debug-Ausgabe beim Gebietswechsel nennt Ort und Rohwerte", function()
    local e = setup()
    e.DB.db.profile.trackLocations = true
    inInstance(e, "party", 36, "Die Todesminen")
    stub.now = 5
    e.DB:OnAreaChanged("PLAYER_ENTERING_WORLD")
    e.DB:OnAreaChanged("ZONE_CHANGED_NEW_AREA") -- zusammengefasst
    eq(#stub.debugLines, 0, "erst nach der Verzögerung")
    stub.now = 7
    stub.flush()

    local text = table.concat(stub.debugLines, "\n")
    eq(text:find("Gebiet (PLAYER_ENTERING_WORLD): Instanz Die Todesminen (36)", 1, true) ~= nil, true, "Gebiet")
    eq(text:find("IsInInstance: true, party", 1, true) ~= nil, true, "IsInInstance roh")
    eq(text:find("GetInstanceInfo: Die Todesminen, party, 1, Normal, 5, 0, false, 36", 1, true) ~= nil, true, "GetInstanceInfo roh")
    eq(text:find("ZONE_CHANGED", 1, true), nil, "nur einmal ausgegeben")

    -- ohne Spielfunktionen oder mit Fehler
    stub.debugLines = {}
    Locations().api.IsInInstance = nil
    Locations().api.GetInstanceInfo = function() error("kaputt") end
    e.DB:OnAreaChanged("ZONE_CHANGED_NEW_AREA")
    stub.flush()
    text = table.concat(stub.debugLines, "\n")
    eq(text:find("IsInInstance: nicht vorhanden", 1, true) ~= nil, true, "fehlende Funktion")
    eq(text:find("GetInstanceInfo: Fehler:", 1, true) ~= nil, true, "Fehler abgefangen")
end)

-- PARTY_KILL (Killer, Opfer): die Quelle für Kills, wenn der Client das Ereignis kennt
local function setupPartyKill()
    stub.partyKill = true
    local e = setup()
    stub.units.player = { guid = "Player-1-A" }
    stub.units.pet = { guid = "Creature-0-1-2-3-999-PET" }
    e.frame = stub.frames[#stub.frames]
    eq(e.frame.events.PARTY_KILL, true, "PARTY_KILL angemeldet")
    eq(e.frame.events.UNIT_HEALTH, nil, "Tod des Ziels nicht angemeldet")
    return e
end

test("Collect: PARTY_KILL zählt Kills von uns und dem Haustier, ohne Ziel und ohne Beute", function()
    local e = setupPartyKill()
    local frame = e.frame
    _G.CanLootUnit = function() return false, false end
    stub.now = 100
    frame.onEvent(frame, "PARTY_KILL", "Player-1-A", WOLF)

    -- Haustier
    local other = "Creature-0-3131-2552-14367-555-0000A5C2B1"
    frame.onEvent(frame, "PARTY_KILL", "Creature-0-1-2-3-999-PET", other)

    -- fremder Kill und Spieler als Opfer: nichts
    local third = "Creature-0-3131-2552-14367-777-0000A5C2B1"
    frame.onEvent(frame, "PARTY_KILL", "Player-9-Z", third)
    frame.onEvent(frame, "PARTY_KILL", "Player-1-A", "Player-2-B")

    -- derselbe Kill nochmal (z. B. zweites Ereignis): ein Versuch
    frame.onEvent(frame, "PARTY_KILL", "Player-1-A", WOLF)

    -- ohne Beutefenster zählt er nach der Wartezeit als Versuch
    stub.now = 101.6
    stub.flush()
    eq(e.DB:GetNPC(179891), nil, "wartet noch, der Kill allein speichert nichts")
    stub.now = 230
    stub.flush()
    _G.CanLootUnit = nil
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "Versuch ohne Beute, nur einer")
    eq(e.DB:GetNPC(555).loot.attempts, 1, "Kill des Haustiers als Versuch")
    eq(e.DB:GetNPC(777), nil, "fremder Kill zählt nicht")
    eq(select(2, e.DB:GetStats()), 2, "nur die beiden eigenen Kreaturen gespeichert")
end)

test("Collect: mit PARTY_KILL ist der Tod des Ziels nur Ersatz und zählt nicht", function()
    local e = setupPartyKill()
    stub.now = 100
    withCombatLog(WOLF)  -- UNIT_HEALTH eines toten Ziels
    stub.now = 102
    stub.flush()
    stub.now = 230
    stub.flush()
    eq(e.DB:GetNPC(179891), nil, "ohne PARTY_KILL kein Versuch")
end)

test("Collect: PARTY_KILL und Looten zählen den Kill nur einmal", function()
    local e = setupPartyKill()
    local frame = e.frame
    stub.now = 100
    frame.onEvent(frame, "PARTY_KILL", "Player-1-A", WOLF)
    stub.now = 105
    e.loot({ { 102, WOLF } })
    eq(e.DB:GetNPC(179891).loot.attempts, 1, "ein Versuch")
end)
