local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Angeln: Würfe und Fänge je Zone zählen

local api = DB.api
local collect = DB.collect
local Clean, ItemID, IsMaterial = collect.Clean, collect.ItemID, collect.IsMaterial
local NewNodeCast, DebugOn = collect.NewNodeCast, collect.DebugOn
local LOOT_ITEM = collect.LOOT_ITEM
local EVALUATE_DELAY = collect.EVALUATE_DELAY

-- Jeder Wurf ist ein Versuch. Er wird vorgemerkt und mit dem Fang gezählt, sonst als leer: nach
-- FISHING_TIMEOUT, beim nächsten Wurf oder FISHING_GRACE nach CHANNEL_STOP (der Klick auf den
-- Schwimmer ist nicht abfangbar). Ein Fenster bis FISHING_LATE danach wird dem leeren Wurf zugerechnet.
local FISHING_TIMEOUT = 45
local FISHING_GRACE = 4
local FISHING_LATE = 10

-- Ränge von Fischen (7620) und die Variante ab MoP. Andere IDs werden über den Namen erkannt
-- (sprach- und rangunabhängig).
local FISHING_SPELLS = { 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410, 131474 }
local fishingIDs

local function IsFishingSpell(spellID)
    if type(spellID) ~= "number" then return false end

    if not fishingIDs then
        fishingIDs = {}
        for _, id in ipairs(FISHING_SPELLS) do fishingIDs[id] = true end
    end
    if fishingIDs[spellID] then return true end

    -- Erst hier nachschlagen, beim Laden kennt der Client den Namen evtl. noch nicht
    local lookup = api.GetSpellName or api.GetSpellInfo
    if not lookup then return false end
    local okName, name = pcall(lookup, 7620)
    local ok, cast = pcall(lookup, spellID)
    if not (okName and ok) or type(name) ~= "string" or type(cast) ~= "string" or Glimpse:IsSecret(cast) then return false end
    return name == cast
end

-- { [itemID] = Menge } eines Fangs, nur Materialien
local function ReadFishingLoot()
    local items = {}

    for slot = 1, api.GetNumLootItems() do
        local itemID = api.GetLootSlotType(slot) == LOOT_ITEM and ItemID(api.GetLootSlotLink(slot)) or nil
        if itemID and IsMaterial(itemID) then
            local amount = tonumber(Clean(select(2, api.GetLootSourceInfo(slot)))) or 1
            items[itemID] = (items[itemID] or 0) + amount
        end
    end

    return items
end

local pendingCast, castCounter = nil, 0
-- Sitzungszähler (nicht gespeichert), für Debug und /gli gatheringdb stats
DB.fishingSession = { casts = 0, windows = 0, misses = 0 }

local function SessionText()
    local session = DB.fishingSession
    return format("%d ausgeworfen, %d Beutefenster, %d ohne Fang", session.casts, session.windows, session.misses)
end
local lastMiss -- zuletzt als leer gezählter Wurf: { area, time }

local function Area(self)
    local found, area = pcall(Locations.GetPlayerArea, Locations)
    if not found then
        self:ReportError("GetPlayerArea", area)
        return nil
    end
    return area
end

-- Fang zählt zur Zone (uiMapID), die Position nur als Fundort. Aufruf aus OnLootOpened.
function DB:OnFishingLoot(opened)
    local ok, items = pcall(ReadFishingLoot)
    if not ok then return self:ReportError("ReadFishingLoot", items) end

    -- Zone immer, Koordinaten nur mit trackLocations (CountFishing)
    local found, area = pcall(Locations.GetPlayerArea, Locations)
    if not found then
        self:ReportError("GetPlayerArea", area)
        area = nil
    end

    C_Timer.After(EVALUATE_DELAY, function()
        local done, err = pcall(self.ProcessFishing, self, items, opened, area)
        if not done then self:ReportError("ProcessFishing", err) end
    end)
end

-- Zählt einen Versuch in der Zone. items = Fang oder nil.
function DB:CountFishing(area, items, how)
    if type(area) ~= "table" or type(area.map) ~= "number" then
        self:Debug("Wurf übersprungen: keine Karte (Instanz oder Ort unbekannt)")
        return
    end

    self:RecordFishing(area.map, items or {}, self.db.profile.trackLocations and area or nil)
    if DebugOn() then
        self:Debug("Gespeichert: Angeln in Zone", tostring(area.map), how, "Fundort:", self:DescribeArea(area) or "keiner")
    end
end

--- Läuft gerade ein Wurf (ausgeworfen, noch kein Fang/Ende)?
function DB:IsFishing()
    return pendingCast ~= nil
end

--- Wahrscheinlich der Schwimmer? Er hat in den Tooltip-Daten keine ID, daher: Wurf läuft und
-- der Name ist kein bekannter Knoten.
function DB:IsBobber(name)
    return pendingCast ~= nil and type(name) == "string" and #self:FindNodeIDs(name) == 0
end

--- UNIT_SPELLCAST_SENT: startet einen Wurf, wenn spellID Fischen ist
function DB:OnFishingStart(spellID)
    if not self.db.profile.recording or not IsFishingSpell(spellID) then return end

    -- Voriger Wurf endete ohne Fang
    if pendingCast then self:FinishFishingMiss(pendingCast) end

    castCounter = castCounter + 1
    local mine = { id = castCounter, area = Area(self) }
    pendingCast = mine
    self.fishingSession.casts = self.fishingSession.casts + 1
    if DebugOn() then self:Debug("Angel ausgeworfen, Wurf", self.fishingSession.casts, "dieser Sitzung (" .. SessionText() .. ")") end

    C_Timer.After(FISHING_TIMEOUT, function()
        if pendingCast ~= mine then return end
        self:FinishFishingMiss(mine)
    end)
end

-- Als Versuch ohne Fang zählen, für ein spätes Fenster merken
function DB:FinishFishingMiss(cast)
    pendingCast = nil
    self.fishingSession.misses = self.fishingSession.misses + 1
    local done, err = pcall(self.CountFishing, self, cast.area, nil, "(Wurf ohne Fang)")
    if not done then return self:ReportError("CountFishing", err) end
    lastMiss = { area = cast.area, time = GetTime() }
end

--- UI_ERROR/INFO_MESSAGE während eines Wurfs. ERR_FISH_ESCAPED beendet ihn ohne Fang, ERR_FISH_NOT_HOOKED
-- nicht (Zauber läuft evtl. weiter). Debug zeigt jede Meldung, um die Texte im Spiel zu prüfen.
function DB:OnFishingMessage(...)
    local cast = pendingCast
    if not cast or not self.db.profile.recording then return end

    for index = 1, select("#", ...) do
        local text = select(index, ...)
        if type(text) == "string" and not Glimpse:IsSecret(text) then
            if DebugOn() then self:Debug("Meldung beim Angeln:", text) end
            if _G.ERR_FISH_ESCAPED and text == _G.ERR_FISH_ESCAPED then
                self:Debug("Fisch entkommen: Wurf ohne Fang")
                self:FinishFishingMiss(cast)
                return
            end
        end
    end
end

--- UNIT_SPELLCAST_CHANNEL_STOP (Klick, Abbruch, Ablauf). Kein Fenster nach FISHING_GRACE = kein Fang.
function DB:OnFishingStop(spellID)
    local cast = pendingCast
    if not cast or not self.db.profile.recording or not IsFishingSpell(spellID) then return end

    self:Debug("Fischen beendet, warte", FISHING_GRACE, "Sekunden auf das Beutefenster")
    C_Timer.After(FISHING_GRACE, function()
        if pendingCast == cast then self:FinishFishingMiss(cast) end
    end)
end

function DB:ProcessFishing(items, _, area)
    if not self.db.profile.recording then return end

    -- Ein Fang pro Wurf, erneut geöffnete Fenster zählen nicht
    if not NewNodeCast("fishing") then
        self:Debug("Fang übersprungen: gleicher Wurf, Beutefenster erneut geöffnet")
        return
    end

    self.fishingSession.windows = self.fishingSession.windows + 1

    -- Fenster kam nach dem als leer gezählten Wurf: Fang nachtragen
    local cast = pendingCast
    if not cast and lastMiss and (GetTime() - lastMiss.time) <= FISHING_LATE and type(lastMiss.area) == "table" and lastMiss.area.map then
        local late = lastMiss
        lastMiss = nil
        self.fishingSession.misses = math.max(self.fishingSession.misses - 1, 0)
        self:AddFishingItems(late.area.map, items)
        self:Debug("Fang dem zuvor gezählten Wurf zugerechnet, Zone", tostring(late.area.map))
        return
    end

    -- Zone/Ort vom Auswerfen bevorzugen
    pendingCast = nil
    lastMiss = nil
    self:CountFishing(cast and cast.area or area, items, "(Fang)")
end
