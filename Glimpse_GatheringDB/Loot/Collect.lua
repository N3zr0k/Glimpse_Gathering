local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Blizzard-Funktionen kommen gesammelt aus Core/Compat.lua
local api = DB.api

-- Erfasst beim Öffnen eines Beutefensters, aus welcher Quelle (Sammelknoten oder Kreatur) welche
-- Items kamen. Eine Quelle zählt als ein Versuch.
--
-- Gespeichert werden nur Handwerksmaterialien (Handwerkswaren und Edelsteine), alles andere
-- (Rüstung, Waffen, Müll) fällt weg. Jede gelootete Kreatur zählt trotzdem als Versuch, auch wenn
-- kein Material dabei war, sonst wäre die Chance zu hoch. Angelbeute lässt sich nicht erfassen,
-- weil sie keine Quelle hat.

-- Zeitfenster in Sekunden: so kurz muss ein Zauber vor dem Beutefenster erfolgreich gewesen sein,
-- damit das Fenster als Ergebnis dieses Zaubers gilt (Kürschnern, Pflücken, Bergbau)
local CAST_WINDOW = 1.0

-- Wie lange der Zielname eines Zaubers für einen Sammelknoten verwendet werden darf
local TARGET_WINDOW = 15

-- Obergrenze der Merkliste, danach wird sie geleert
local MAX_REMEMBERED = 2000

local LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

-- Item-Klassen, die als Handwerksmaterial gelten: Handwerkswaren (Stoff, Leder, Erz, Kräuter,
-- Kochzutaten ...) und Edelsteine. Fallback-Zahlen, falls die Enums fehlen.
local ItemClass = Enum and Enum.ItemClass or {}
local TRADEGOODS = ItemClass.Tradegoods or 7
local MATERIAL_CLASSES = {
    [TRADEGOODS] = true,
    [ItemClass.Gem or 3] = true,
}

-- Unterklassen der Handwerkswaren, nur für die Kategorie eines Knotens
local SUBCLASS = Enum and Enum.ItemTradeGoodsSubclass or {}
local HERB = SUBCLASS.Herb or 9
local METAL_STONE = SUBCLASS.MetalStone or 7

local lastSuccess, lastTarget, lastTargetTime = 0, nil, 0

-- Quellen, die in dieser Sitzung schon gezählt wurden: verhindert doppeltes Zählen, wenn das
-- Beutefenster erneut aufgeht (Teilloot). Der Schlüssel enthält die Art, damit Normalbeute und
-- Kürschnerbeute derselben Leiche getrennt zählen.
local counted = {}
local countedSize = 0

-- Kreaturen, deren Normalbeute schon gezählt wurde. Wird sie ein zweites Mal gelootet, ist es
-- Kürschnerbeute.
local looted = {}

local function Clean(value)
    if value ~= nil and Glimpse:IsSecret(value) then return nil end
    return value
end

-- "Creature-0-3131-2552-14367-179891-0000A5C2B1" -> "Creature", 179891
local function ParseGUID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

local function ItemID(link)
    link = Clean(link)
    return link and tonumber(strmatch(link, "item:(%d+)"))
end

-- true, wenn das Item ein Handwerksmaterial ist. GetItemInfoInstant braucht keine geladenen
-- Item-Daten, es muss nichts nachgeladen werden.
local function IsMaterial(itemID)
    local _, _, _, _, _, classID = api.GetItemInfoInstant(itemID)
    return MATERIAL_CLASSES[classID] == true
end

-- Liest das offene Beutefenster: guid -> { [itemID] = Menge }, nur Materialien.
-- Jede Quelle taucht auf, auch wenn kein Material dabei war (leere Tabelle), denn sie zählt als Versuch.
local function ReadLoot()
    local bySource = {}

    for slot = 1, api.GetNumLootItems() do
        -- Rückgabe: guid1, menge1, guid2, menge2 ... (mehrere bei Flächenbeute)
        local info = { api.GetLootSourceInfo(slot) }
        local itemID = api.GetLootSlotType(slot) == LOOT_ITEM and ItemID(api.GetLootSlotLink(slot)) or nil
        if itemID and not IsMaterial(itemID) then itemID = nil end

        for i = 1, #info, 2 do
            local guid, amount = Clean(info[i]), tonumber(Clean(info[i + 1])) or 1

            if type(guid) == "string" then
                local items = bySource[guid]
                if not items then
                    items = {}
                    bySource[guid] = items
                end
                if itemID then items[itemID] = (items[itemID] or 0) + amount end
            end
        end
    end

    return bySource
end

-- Kategorie eines Knotens aus seiner Beute: Kräuter, Erz oder sonst
local function CategoryOf(items)
    local category = "other"

    for itemID in pairs(items) do
        local _, _, _, _, _, classID, subClassID = api.GetItemInfoInstant(itemID)
        if classID == TRADEGOODS then
            if subClassID == HERB then return "herb" end
            if subClassID == METAL_STONE then category = "ore" end
        end
    end

    return category
end

-- Name und Stufe über die Einheiten, auf die der Spieler gerade zeigt. Fehlt ein Wert, bleibt er
-- leer und kann später ergänzt werden.
local UNITS = { "target", "mouseover", "softenemy", "softinteract" }

local function UnitInfo(guid)
    for _, unit in ipairs(UNITS) do
        local unitGUID = Clean(UnitGUID(unit))
        if unitGUID == guid then
            return { name = Clean(UnitName(unit)), level = tonumber(Clean(UnitLevel(unit))) }
        end
    end
end

local function Remember(key)
    if counted[key] then return false end

    countedSize = countedSize + 1
    if countedSize > MAX_REMEMBERED then
        wipe(counted)
        wipe(looted)
        countedSize = 1
    end

    counted[key] = true
    return true
end

-- Debug-Ausgaben nur bauen, wenn der Debug-Modus an ist (die Texte kosten sonst unnötig Zeit)
local function DebugOn()
    return not Glimpse.IsDebug or Glimpse:IsDebug()
end

-- Das Beutefenster wird sofort gelesen, denn danach ist es weg. Ausgewertet wird erst einen
-- Moment später: Je nach Reihenfolge der Events kommt der erfolgreiche Zauber kurz vor oder kurz
-- nach LOOT_OPENED, und beides muss als "direkt nach dem Zauber" zählen.
local EVALUATE_DELAY = 0.3

function DB:OnLootOpened()
    if not self.db.profile.recording then return end

    local opened = GetTime()

    -- Fehler hier dürfen weder das Looten noch andere Addons stören: abfangen und merken
    local ok, sources = pcall(ReadLoot)
    if not ok then return self:ReportError("ReadLoot", sources) end

    -- Wo der Spieler jetzt steht, nicht erst nach der Verzögerung
    local position
    if self.db.profile.trackLocations then
        local found, result = pcall(Locations.GetPlayerArea, Locations)
        if found then position = result else self:ReportError("GetPlayerArea", result) end

        if DebugOn() then
            self:Debug("Position:", self:DescribeArea(position) or "nicht bestimmbar (keine Karte, Koordinaten oder Instanz)")
        end
    elseif DebugOn() then
        self:Debug("Position: Aufzeichnung der Fundorte ist aus")
    end

    C_Timer.After(EVALUATE_DELAY, function()
        local done, err = pcall(self.ProcessLoot, self, sources, opened, position)
        if not done then self:ReportError("ProcessLoot", err) end
    end)
end

-- Beim Betreten oder Wechseln eines Gebiets (Ladebildschirm, Instanz, neue Zone) zeigt der Debug-Modus,
-- was das Addon über den Ort weiß. So lässt sich die Erkennung prüfen, ohne in der Instanz zu farmen.
-- Kurz warten, weil die Instanzdaten direkt nach dem Event noch nicht immer stimmen, und mehrere
-- Events kurz hintereinander zusammenfassen.
local AREA_DELAY = 1
local areaPending = false

local function RawValues(func)
    if not func then return "nicht vorhanden" end

    local values = { pcall(func) }
    if not values[1] then return "Fehler: " .. tostring(values[2]) end

    local parts = {}
    for i = 2, math.max(#values, 9) do parts[#parts + 1] = tostring(Clean(values[i])) end
    return table.concat(parts, ", ")
end

function DB:DebugArea(event)
    self:Debug("Gebiet (" .. tostring(event) .. "):", self:DescribeArea(Locations:GetPlayerArea()) or "nicht bestimmbar (keine Karte, Koordinaten oder Instanz)")
    self:Debug("IsInInstance:", RawValues(Locations.api.IsInInstance))
    self:Debug("GetInstanceInfo:", RawValues(Locations.api.GetInstanceInfo))
    self:Debug("Aufzeichnung der Fundorte:", self.db.profile.trackLocations and "an" or "aus")
end

function DB:OnAreaChanged(event)
    if areaPending or not DebugOn() then return end

    areaPending = true
    C_Timer.After(AREA_DELAY, function()
        areaPending = false
        if not DebugOn() then return end

        local ok, err = pcall(self.DebugArea, self, event)
        if not ok then self:ReportError("DebugArea", err) end
    end)
end

--- Merkt sich den letzten Fehler (sichtbar in /gli gatheringdb stats) und zeigt ihn im Debug-Modus.
function DB:ReportError(where, err)
    self.errorCount = (self.errorCount or 0) + 1
    self.lastError = where .. ": " .. tostring(err)
    self:Debug("Fehler in", self.lastError)
end

function DB:ProcessLoot(sources, opened, position)
    if not self.db.profile.recording then return end

    -- Zauber erfolgreich im Zeitfenster vor dem Beutefenster (oder kurz danach)
    local afterCast = lastSuccess >= (opened - CAST_WINDOW)

    for guid, items in pairs(sources) do
        local kind, id = ParseGUID(guid)
        self:Debug("Beutefenster:", tostring(kind), tostring(id), "Zauber davor:", tostring(afterCast),
            "Materialien:", tostring(next(items) ~= nil))

        if kind == "GameObject" then
            -- Truhen werden nicht erfasst. Ein Sammelknoten braucht einen Zauber (Pflücken, Bergbau ...),
            -- das Beutefenster hängt also direkt an einem erfolgreichen Zauber. Eine Truhe geht ohne
            -- Zauber auf. Außerdem muss ein Material dabei sein.
            if afterCast and next(items) and Remember(guid .. "|node") then
                local info = UnitInfo(guid) or {}
                if not info.name and lastTarget and (opened - lastTargetTime) <= TARGET_WINDOW then
                    info.name = lastTarget
                end
                info.category = CategoryOf(items)
                self:RecordNode(id, info, items, position)
                if DebugOn() then self:Debug("Gespeichert: Knoten", tostring(id), "Fundort:", self:DescribeArea(position) or "keiner") end
            end

        elseif kind == "Creature" then
            -- Kürschnerbeute: direkt nach einem erfolgreichen Zauber oder bei zweitem Looten
            local mode = (afterCast or looted[guid]) and "skinning" or "loot"

            if Remember(guid .. "|" .. mode) then
                if mode == "loot" then looted[guid] = true end
                self:RecordNPC(id, mode, UnitInfo(guid), items, position)
                if DebugOn() then
                    self:Debug("Gespeichert: Kreatur", tostring(id), mode, "Fundort:", self:DescribeArea(position) or "keiner")
                end
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, zielName, castGUID, spellID)
        local _, target = ...
        target = Clean(target)
        if type(target) == "string" and target ~= "" then
            lastTarget, lastTargetTime = target, GetTime()
        end
    else
        lastSuccess = GetTime()
    end
end)

function DB:StartCollecting()
    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnAreaChanged")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnAreaChanged")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

function DB:StopCollecting()
    self:UnregisterEvent("LOOT_OPENED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:UnregisterAllEvents()
end
