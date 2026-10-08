local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Blizzard-API aus Core/Compat.lua
local api = DB.api

-- Erfasst Beute je Quelle (Knoten oder Kreatur), eine Quelle = ein Versuch.
-- Gespeichert werden nur Handwerksmaterialien (Handwerkswaren, Edelsteine). Kreaturen zählen auch
-- ohne Material als Versuch, sonst wäre die Chance zu hoch.
-- Angeln hat keine feste Quelle: Erkennung über IsFishingLoot, Zählung je Zone. Jeder Wurf ist ein
-- Versuch, ein Fang macht ihn zum Treffer (OnFishingStart, ProcessFishing).
--
-- Dateien: Collect (gemeinsamer Zustand, Hilfen), LootWindow (Beutefenster), Fishing, Kills,
-- Area (Debug bei Gebietswechsel), Events (Event-Frame, Start/StopCollecting).

-- Merklisten werden ab dieser Größe geleert
local MAX_REMEMBERED = 2000

-- Materialklassen: Handwerkswaren und Edelsteine. Zahlen als Fallback ohne Enum.
local ItemClass = Enum and Enum.ItemClass or {}
local TRADEGOODS = ItemClass.Tradegoods or 7
local MATERIAL_CLASSES = {
    [TRADEGOODS] = true,
    [ItemClass.Gem or 3] = true,
}

-- Gemeinsamer Zustand der Loot-Dateien, nur intern
local collect = {
    LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1,
    TRADEGOODS = TRADEGOODS,

    -- Sperre (s) gegen Doppelzählung einer Kreatur (Teilloot, Fenster erneut geöffnet). Danach ist
    -- gleiche GUID eine neue Leiche. Knoten zählen stattdessen pro Zauber (nodeMark).
    CREATURE_REPEAT = 600,

    -- Fenster sofort lesen (danach ist es weg), aber verzögert auswerten: SUCCEEDED kommt mal vor,
    -- mal nach LOOT_OPENED.
    EVALUATE_DELAY = 0.3,

    -- Zeitpunkte der letzten Zauber, gesetzt in Events.lua
    lastSuccess = 0,
    lastSent = -1000,
    lastTarget = nil,
    lastTargetTime = 0,

    -- Gezählte Quellen: "GUID|Art" -> Zeitpunkt. Die Art trennt Normal- und Kürschnerbeute derselben Leiche.
    counted = {},
    countedSize = 0,

    -- Knoten-GUID -> Zeitpunkt des zuletzt gezählten Zaubers. Zählt jeden Abbau (auch nach dem
    -- Nachwachsen), aber kein erneut geöffnetes Fenster desselben Abbaus.
    nodeMark = {},
    nodeMarkSize = 0,

    -- GUID -> Zeitpunkt der Normalbeute. Zweites Looten = Kürschnerbeute.
    looted = {},

    -- pendingKills: warten noch auf ein Beutefenster, killCounted: schon als leerer Versuch gezählt
    pendingKills = {},
    killCounted = {},

    -- PARTY_KILL vorhanden, dann entfällt der Ersatz über den Tod des Ziels (Events.lua)
    partyKillActive = false,
}
DB.collect = collect

function collect.Clean(value)
    if value ~= nil and Glimpse:IsSecret(value) then return nil end
    return value
end
local Clean = collect.Clean

-- "Creature-0-3131-2552-14367-179891-0000A5C2B1" -> "Creature", 179891
function collect.ParseGUID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

function collect.ItemID(link)
    link = Clean(link)
    return link and tonumber(strmatch(link, "item:(%d+)"))
end

-- GetItemInfoInstant braucht keine geladenen Item-Daten
function collect.IsMaterial(itemID)
    local _, _, _, _, _, classID = api.GetItemInfoInstant(itemID)
    return MATERIAL_CLASSES[classID] == true
end

-- Name/Stufe aus den Einheiten unter dem Spieler, fehlende Werte werden später ergänzt
local UNITS = { "target", "mouseover", "softenemy", "softinteract" }

function collect.UnitInfo(guid)
    for _, unit in ipairs(UNITS) do
        local unitGUID = Clean(UnitGUID(unit))
        if unitGUID == guid then
            return { name = Clean(UnitName(unit)), level = tonumber(Clean(UnitLevel(unit))) }
        end
    end
end

-- true, wenn die Quelle jetzt zählt: noch nie gesehen oder zuletzt vor mehr als `window` Sekunden
function collect.Remember(key, window, now)
    local seen = collect.counted[key]
    if seen and (now - seen) <= window then return false end

    if not seen then
        collect.countedSize = collect.countedSize + 1
        if collect.countedSize > MAX_REMEMBERED then
            wipe(collect.counted)
            wipe(collect.looted)
            wipe(collect.killCounted)
            wipe(collect.nodeMark)
            collect.nodeMarkSize = 0
            collect.countedSize = 1
        end
    end

    collect.counted[key] = now
    return true
end

-- true, wenn seit dem letzten gezählten Abbau ein neuer Zauber (gesendet oder erfolgreich) kam
function collect.NewNodeCast(guid)
    local mark = math.max(collect.lastSuccess, collect.lastSent)
    local seen = collect.nodeMark[guid]
    if seen and mark <= seen then return false end

    if not seen then
        collect.nodeMarkSize = collect.nodeMarkSize + 1
        if collect.nodeMarkSize > MAX_REMEMBERED then
            wipe(collect.nodeMark)
            collect.nodeMarkSize = 1
        end
    end
    collect.nodeMark[guid] = mark
    return true
end

-- Debug-Texte nur bauen, wenn Debug an ist
function collect.DebugOn()
    return not Glimpse.IsDebug or Glimpse:IsDebug()
end

--- Letzten Fehler merken (/gli gatheringdb stats), im Debug-Modus ausgeben
function DB:ReportError(where, err)
    self.errorCount = (self.errorCount or 0) + 1
    self.lastError = where .. ": " .. tostring(err)
    self:Debug("Fehler in", self.lastError)
end
