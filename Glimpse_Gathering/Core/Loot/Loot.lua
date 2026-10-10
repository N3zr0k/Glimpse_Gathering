local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")

-- Blizzard-API aus Core/Compat.lua
local api = DB.api

-- Erfasst Beute je Quelle (Knoten oder Kreatur), eine Quelle = ein Versuch, und schreibt sie in den Namespace
-- gathering von Glimpse: Database. Gespeichert werden nur Handwerksmaterialien (Handwerkswaren, Edelsteine).
-- Kreaturen zählen auch ohne Material als Versuch, sonst wäre die Chance zu hoch. Angelbeute zählt hier nicht.
--
-- Dateien: Loot (gemeinsamer Zustand, Hilfen), LootWindow (Beutefenster), LootKills (Kills ohne Fenster),
-- LootArea (Debug bei Gebietswechsel), LootEvents (Event-Frame, Start/StopCollecting).
-- Geschrieben wird in NodeDB, CreatureDB und SkinningDB.

-- Merklisten werden ab dieser Größe geleert
local MAX_REMEMBERED = 2000

-- Materialklassen: Handwerkswaren und Edelsteine. Zahlen als Fallback ohne Enum.
local ItemClass = Enum and Enum.ItemClass or {}
local MATERIAL_CLASSES = {
    [ItemClass.Tradegoods or 7] = true,
    [ItemClass.Gem or 3] = true,
}

-- Gemeinsamer Zustand der Loot-Dateien, nur intern
local collect = {
    LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1,

    -- Sperre (s) gegen Doppelzählung einer Kreatur (Teilloot, Fenster erneut geöffnet). Danach ist
    -- gleiche GUID eine neue Leiche. Knoten zählen stattdessen pro Zauber (nodeMark).
    CREATURE_REPEAT = 600,

    -- Fenster sofort lesen (danach ist es weg), aber verzögert auswerten: SUCCEEDED kommt mal vor,
    -- mal nach LOOT_OPENED.
    EVALUATE_DELAY = 0.3,

    -- Zeitpunkte der letzten Zauber, gesetzt in LootEvents.lua
    lastSuccess = 0,
    lastSkinning = -1000,
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

    -- GUID -> Zeitpunkt der Normalbeute. Zweites Looten nach einem Zauber = Kürschnerbeute.
    looted = {},

    -- pendingKills: warten noch auf ein Beutefenster, killCounted: schon als leerer Versuch gezählt
    pendingKills = {},
    killCounted = {},

    -- PARTY_KILL vorhanden, dann entfällt der Ersatz über den Tod des Ziels (LootEvents.lua)
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

-- Name/Stufe aus den Einheiten unter dem Spieler
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

-- Kürschnern: bekannte Ränge, andere IDs über den Zaubernamen (sprachunabhängig)
local SKINNING_SPELLS = { 8613, 8617, 8618, 10768, 32678, 50305, 74522 }
local skinningID, skinningName = {}, {}
for _, id in ipairs(SKINNING_SPELLS) do skinningID[id] = true end

local function SpellName(spellID)
    local lookup = api.GetSpellName or api.GetSpellInfo
    if not lookup then return nil end
    local ok, name = pcall(lookup, spellID)
    if ok and type(name) == "string" and not Glimpse:IsSecret(name) then return name end
end

function collect.IsSkinningSpell(spellID)
    spellID = tonumber(Clean(spellID))
    if not spellID then return false end
    if skinningID[spellID] then return true end
    if skinningName[spellID] ~= nil then return skinningName[spellID] end

    local name, reference = SpellName(spellID), SpellName(SKINNING_SPELLS[1])
    if not (name and reference) then return false end -- noch nicht im Cache, nicht merken
    skinningName[spellID] = name == reference
    return skinningName[spellID]
end

--- Zone eines Fundorts: uiMapID oder -instanceID, nil ohne Ort (wie Glimpse.IDs:ZoneKey)
function collect.ZoneOf(pos)
    if type(pos) ~= "table" then return nil end
    local instance = pos.instance
    if type(instance) == "number" then
        if instance >= 1 and instance < 1e6 and instance == math.floor(instance) then return -instance end
        return nil
    end
    if type(pos.map) == "number" and pos.map >= 1 and pos.map == math.floor(pos.map) then return pos.map end
end

--- Ein Beutefenster einer Quelle zählen: Versuch (mit Zone), dazu Menge und Fenster je Item.
-- kinds = DB.SECTIONS.node/.loot/.skinning, items = { [itemID] = Menge }.
function DB:CountLoot(kinds, id, items, zone)
    local ns = self.ns
    if not ns then return end
    ns:Count(kinds[1], id, zone)
    self:CountItems(kinds, id, items)
end

--- Nur die Items zu einem schon gezählten Versuch (Kill ohne Fenster, später gelootet)
function DB:CountItems(kinds, id, items)
    local ns = self.ns
    if not ns then return end
    for itemID, amount in pairs(items) do
        ns:Count(kinds[2] .. ":" .. id, itemID, nil, amount)
        ns:Count(kinds[3] .. ":" .. id, itemID)
    end
end

--- Letzten Fehler merken (Probe gathering stats), im Debug-Modus ausgeben
function DB:ReportError(where, err)
    self.errorCount = (self.errorCount or 0) + 1
    self.lastError = where .. ": " .. tostring(err)
    if self.debug then self.debug:Warn("error", "%s", self.lastError) end
end
