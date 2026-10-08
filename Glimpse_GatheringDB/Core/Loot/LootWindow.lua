local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Beutefenster von Knoten und Kreaturen auswerten (Angeln: Fishing.lua)

local api = DB.api
local collect = DB.collect
local Clean, ParseGUID, ItemID, IsMaterial = collect.Clean, collect.ParseGUID, collect.ItemID, collect.IsMaterial
local UnitInfo, Remember, NewNodeCast, DebugOn = collect.UnitInfo, collect.Remember, collect.NewNodeCast, collect.DebugOn

-- Max. Abstand (s) zwischen erfolgreichem Zauber und Beutefenster (Kürschnern, Pflücken, Bergbau)
local CAST_WINDOW = 1.0

-- Gültigkeit (s) des Zielnamens aus UNIT_SPELLCAST_SENT für Knoten
local TARGET_WINDOW = 15

-- Objektbeute gilt bis so lange nach UNIT_SPELLCAST_SENT als Sammelergebnis, auch ohne SUCCEEDED
local SENT_WINDOW = 10

local CREATURE_REPEAT = collect.CREATURE_REPEAT
local LOOT_ITEM = collect.LOOT_ITEM
local EVALUATE_DELAY = collect.EVALUATE_DELAY

-- Unterklassen nur für die Knoten-Kategorie
local TRADEGOODS = collect.TRADEGOODS
local SUBCLASS = Enum and Enum.ItemTradeGoodsSubclass or {}
local HERB = SUBCLASS.Herb or 9
local METAL_STONE = SUBCLASS.MetalStone or 7

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

-- herb, ore oder other, abgeleitet aus der Beute
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

function DB:OnLootOpened()
    if not self.db.profile.recording then return end

    local opened = GetTime()

    -- Angelbeute hat keine Kreatur und keinen Knoten als Quelle
    local fishing = false
    if api.IsFishingLoot then
        local asked, value = pcall(api.IsFishingLoot)
        fishing = asked and Clean(value) == true
    end
    if fishing then return self:OnFishingLoot(opened) end

    -- Fehler dürfen Looten und andere Addons nicht stören
    local ok, sources = pcall(ReadLoot)
    if not ok then return self:ReportError("ReadLoot", sources) end

    -- Position beim Öffnen, nicht nach der Verzögerung
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

function DB:ProcessLoot(sources, opened, position)
    if not self.db.profile.recording then return end

    -- SUCCEEDED kurz vor oder (dank EVALUATE_DELAY) kurz nach dem Fenster
    local afterCast = collect.lastSuccess >= (opened - CAST_WINDOW)
    local afterSent = collect.lastSent >= (opened - SENT_WINDOW)

    -- Objekte: gesendeter Zauber reicht, nicht jeder Client meldet SUCCEEDED für Sammelzauber
    local afterNodeCast = afterCast or afterSent

    for guid, items in pairs(sources) do
        local kind, id = ParseGUID(guid)
        self:Debug("Beutefenster:", tostring(kind), tostring(id), "Zauber davor:", tostring(afterCast),
            "Zauber abgeschickt:", tostring(afterSent),
            "Materialien:", tostring(next(items) ~= nil))

        if kind == "GameObject" then
            -- Knoten brauchen Zauber und Material. Truhen öffnen ohne Zauber und fallen so raus.
            if not afterNodeCast then
                self:Debug("Knoten übersprungen: kein Zauber vor dem Beutefenster")
            elseif not next(items) then
                self:Debug("Knoten übersprungen: kein Handwerksmaterial in der Beute")
            elseif NewNodeCast(guid) then
                local info = UnitInfo(guid) or {}
                if not info.name and collect.lastTarget and (opened - collect.lastTargetTime) <= TARGET_WINDOW then
                    info.name = collect.lastTarget
                end
                info.category = CategoryOf(items)
                self:RecordNode(id, info, items, position)
                if DebugOn() then self:Debug("Gespeichert: Knoten", tostring(id), "Fundort:", self:DescribeArea(position) or "keiner") end
            else
                self:Debug("Knoten übersprungen: gleicher Abbau, Beutefenster erneut geöffnet")
            end

        elseif kind == "Creature" then
            -- Kürschnerbeute: nach erfolgreichem Zauber oder beim zweiten Looten
            local seen = collect.looted[guid]
            local again = seen and (opened - seen) <= CREATURE_REPEAT
            local mode = (afterCast or again) and "skinning" or "loot"

            if mode == "loot" and collect.killCounted[guid] then
                -- Kill war schon als leerer Versuch gezählt, nur die Beute nachtragen
                if Remember(guid .. "|killitems", CREATURE_REPEAT, opened) then
                    collect.killCounted[guid] = nil
                    collect.looted[guid] = opened
                    self:AddNPCItems(id, mode, items)
                    if DebugOn() then self:Debug("Gespeichert: Beute der Kreatur", tostring(id), "(Kill war schon gezählt)") end
                end
            elseif Remember(guid .. "|" .. mode, CREATURE_REPEAT, opened) then
                collect.pendingKills[guid] = nil
                if mode == "loot" then collect.looted[guid] = opened end
                self:RecordNPC(id, mode, UnitInfo(guid), items, position)
                if DebugOn() then
                    self:Debug("Gespeichert: Kreatur", tostring(id), mode, "Fundort:", self:DescribeArea(position) or "keiner")
                end
            end
        end
    end
end
