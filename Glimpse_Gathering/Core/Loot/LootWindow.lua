local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")
local Locations = Glimpse:GetModule("Locations")

-- Beutefenster von Knoten und Kreaturen auswerten. Angelbeute zählt nicht (Glimpse: Professions).

local api = DB.api
local collect = DB.collect
local Clean, ParseGUID, ItemID, IsMaterial = collect.Clean, collect.ParseGUID, collect.ItemID, collect.IsMaterial
local UnitInfo, Remember, NewNodeCast = collect.UnitInfo, collect.Remember, collect.NewNodeCast

-- Max. Abstand (s) zwischen erfolgreichem Zauber und Beutefenster (Kürschnern, Pflücken, Bergbau)
local CAST_WINDOW = 1.0

-- Gültigkeit (s) des Zielnamens aus UNIT_SPELLCAST_SENT für Knoten
local TARGET_WINDOW = 15
-- Gültigkeit (s) des Namens aus dem letzten Objekt-Tooltip (Mouseover vor dem Abbau)
local OBJECT_WINDOW = 30

-- Objektbeute gilt bis so lange nach UNIT_SPELLCAST_SENT als Sammelergebnis, auch ohne SUCCEEDED
local SENT_WINDOW = 10

local CREATURE_REPEAT = collect.CREATURE_REPEAT
local LOOT_ITEM = collect.LOOT_ITEM
local EVALUATE_DELAY = collect.EVALUATE_DELAY

-- guid -> { [itemID] = Menge }, nur Materialien. Quellen ohne Material bleiben als leere Tabelle (Versuch).
local function ReadLoot()
    local bySource = {}

    for slot = 1, api.GetNumLootItems() do
        -- guid1, menge1, guid2, menge2 ... (Flächenbeute)
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

local function IsFishingLoot()
    if not api.IsFishingLoot then return false end
    local asked, value = pcall(api.IsFishingLoot)
    return asked and Clean(value) == true
end

function DB:OnLootOpened()
    if not self.db.profile.recording or IsFishingLoot() then return end

    local opened = GetTime()

    -- Fehler dürfen Looten und andere Addons nicht stören
    local ok, sources = pcall(ReadLoot)
    if not ok then return self:ReportError("ReadLoot", sources) end

    -- Position beim Öffnen, nicht nach der Verzögerung
    local position
    if self.db.profile.trackLocations then
        local found, result = pcall(Locations.GetPlayerArea, Locations)
        if found then position = result else self:ReportError("GetPlayerArea", result) end

        if self.debug:IsOn("area") then
            self.debug:Log("area", "Position: %s", self:DescribeArea(position) or "nicht bestimmbar (keine Karte, Koordinaten oder Instanz)")
        end
    else
        self.debug:Log("area", "Position: Aufzeichnung der Fundorte ist aus")
    end

    C_Timer.After(EVALUATE_DELAY, function()
        local done, err = pcall(self.ProcessLoot, self, sources, opened, position)
        if not done then self:ReportError("ProcessLoot", err) end
    end)
end

-- Knoten: braucht Zauber und Material. Truhen öffnen ohne Zauber und fallen so raus.
local function ProcessNode(self, guid, id, items, opened, position, afterNodeCast)
    local debug = self.debug
    if not afterNodeCast then
        debug:Log("node", "Knoten übersprungen: kein Zauber vor dem Beutefenster")
    elseif not next(items) then
        debug:Log("node", "Knoten übersprungen: kein Handwerksmaterial in der Beute")
    elseif NewNodeCast(guid) then
        local info = UnitInfo(guid) or {}
        if not info.name and collect.lastTarget and (opened - collect.lastTargetTime) <= TARGET_WINDOW then
            info.name = collect.lastTarget
        end
        if not info.name and self.lastObjectName and (opened - self.lastObjectTime) <= OBJECT_WINDOW then
            info.name = self.lastObjectName
        end
        self:RecordNode(id, info, items, position)
        if debug:IsOn("node") then
            debug:Log("node", "Gespeichert: Knoten %s (%s), Fundort: %s", tostring(id), tostring(info.name or "ohne Namen"),
                self:DescribeArea(position) or "keiner")
        end
    else
        debug:Log("node", "Knoten übersprungen: gleicher Abbau, Beutefenster erneut geöffnet")
    end
end

-- Kreatur: Kürschnerbeute nach dem Zauber Kürschnern, oder beim zweiten Looten direkt nach einem Zauber
local function ProcessCreature(self, guid, id, items, opened, position, afterCast)
    local debug = self.debug
    local seen = collect.looted[guid]
    local again = seen ~= nil and (opened - seen) <= CREATURE_REPEAT
    local afterSkinning = collect.lastSkinning >= (opened - CAST_WINDOW)
    local mode = (afterSkinning or (afterCast and again)) and "skinning" or "loot"

    if mode == "loot" and collect.killCounted[guid] then
        -- Kill war schon als leerer Versuch gezählt, nur die Beute nachtragen
        if Remember(guid .. "|killitems", CREATURE_REPEAT, opened) then
            collect.killCounted[guid] = nil
            collect.looted[guid] = opened
            self:AddNPCItems(id, items)
            debug:Log("creature", "Gespeichert: Beute der Kreatur %s (Kill war schon gezählt)", tostring(id))
        end
    elseif Remember(guid .. "|" .. mode, CREATURE_REPEAT, opened) then
        collect.pendingKills[guid] = nil
        if mode == "loot" then collect.looted[guid] = opened end
        self:RecordNPC(id, mode, UnitInfo(guid), items, position)
        local category = mode == "skinning" and "skinning" or "creature"
        if debug:IsOn(category) then
            debug:Log(category, "Gespeichert: Kreatur %s %s, Fundort: %s", tostring(id), mode, self:DescribeArea(position) or "keiner")
        end
    end
end

function DB:ProcessLoot(sources, opened, position)
    if not self.db.profile.recording then return end

    -- SUCCEEDED kurz vor oder (dank EVALUATE_DELAY) kurz nach dem Fenster
    local afterCast = collect.lastSuccess >= (opened - CAST_WINDOW)
    local afterSent = collect.lastSent >= (opened - SENT_WINDOW)

    for guid, items in pairs(sources) do
        local kind, id = ParseGUID(guid)
        if self.debug:IsOn("node") then
            self.debug:Log("node", "Beutefenster: %s %s, Zauber davor: %s, Zauber abgeschickt: %s, Materialien: %s",
                tostring(kind), tostring(id), tostring(afterCast), tostring(afterSent), tostring(next(items) ~= nil))
        end

        if kind == "GameObject" and id then
            -- Objekte: gesendeter Zauber reicht, nicht jeder Client meldet SUCCEEDED für Sammelzauber
            ProcessNode(self, guid, id, items, opened, position, afterCast or afterSent)
        elseif kind == "Creature" and id then
            ProcessCreature(self, guid, id, items, opened, position, afterCast)
        end
    end
end
