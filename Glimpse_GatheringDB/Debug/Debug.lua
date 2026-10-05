local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local L = DB.L

-- Debug-Anzeige: zeigt im Tooltip, was GatheringDB zu einem Sammelknoten oder einer Kreatur
-- bisher erfasst hat. Nur bei aktivem Debug-Modus (/gli debug on), grau, ohne Icons und ohne
-- Berechnung, also die Rohzahlen:
--
--   [DEBUG] Glimpse(GatheringDB)
--   ID: 179891
--   Name: Waldwolf
--   Loot: 7 attempts
--   Wolfsfell (12345)           3 hits, 4 total
--   ...
--   Locations: 2 own, 14 from other addons
--   Position: Elwynn Forest (37)  41.2 / 56.8
--   Elwynn Forest (37)  41.0 / 55.0      3 finds, 0.4 away  [own]
--   Elwynn Forest (37)  70.2 / 30.2      5 points  [GatherMate2]

-- Höchstzahl der Item-Zeilen je Liste
local MAX_ITEMS = 5

local GREY = 0.6

local function Line(text, right)
    return { text, right, GREY, GREY, GREY }
end

local function ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or "?"
end

-- Abschnitt { attempts, items } als Zeilen. Die sortierte Liste kommt aus der API, wir zeigen
-- aber nur Treffer und Menge.
local function AddItems(lines, drops)
    for index = 1, math.min(#drops, MAX_ITEMS) do
        local drop = drops[index]
        tinsert(lines, Line("  " .. ItemName(drop.itemID) .. " (" .. drop.itemID .. ")",
            format(L["%d hits, %d total"], drop.hits, drop.amount)))
    end

    if #drops > MAX_ITEMS then
        tinsert(lines, Line("  " .. format(L["... %d more"], #drops - MAX_ITEMS)))
    end
end

-- Höchstzahl der Fundort-Zeilen
local MAX_SPOTS = 5

local function MapLabel(map)
    local name = DB:GetMapName(map)
    return name and (name .. " (" .. map .. ")") or tostring(map)
end

local function Percent(value)
    return format("%.1f", value * 100)
end

local function SpotOrder(a, b)
    -- erst die Orte auf der Karte des Spielers, nach Entfernung
    if a.distance or b.distance then
        if not a.distance then return false end
        if not b.distance then return true end
        if a.distance ~= b.distance then return a.distance < b.distance end
    end
    local ownA, ownB = a.source == "own", b.source == "own"
    if ownA ~= ownB then return ownA end
    if a.count ~= b.count then return a.count > b.count end
    if (a.density or 0) ~= (b.density or 0) then return (a.density or 0) > (b.density or 0) end
    if a.map ~= b.map then return a.map < b.map end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end

--- Zeilen zu Fundorten und Koordinaten einer oder mehrerer Quellen derselben Art (kind = "node" oder
-- "npc", ids = Liste): Zahl der Orte (eigene und aus anderen Addons), die Position des Spielers und die
-- ersten Orte mit Karte, Koordinaten (in Prozent), Funden bzw. Punkten, Entfernung und Quelle.
function DB:DebugSpotLines(kind, ids)
    local lines = {}
    local spots, own, external = {}, 0, 0

    for _, id in ipairs(ids) do
        for _, spot in ipairs(self:GetNearestSpots(kind, id)) do
            tinsert(spots, spot)
            if spot.source == "own" then own = own + 1 else external = external + 1 end
        end
    end
    table.sort(spots, SpotOrder)

    tinsert(lines, Line(format(L["Locations: %d own, %d from other addons"], own, external)))

    local position = self.GetPlayerPosition and self:GetPlayerPosition()
    if position then
        tinsert(lines, Line(L["Position"] .. ": " .. MapLabel(position.map),
            Percent(position.x) .. " / " .. Percent(position.y)))
    else
        tinsert(lines, Line(L["Position"] .. ": " .. L["unknown"]))
    end

    for index = 1, math.min(#spots, MAX_SPOTS) do
        local spot = spots[index]
        local right
        if spot.source == "own" then
            right = format(L["%d finds"], spot.count)
        else
            right = format(L["%d points"], spot.density or 0)
        end
        if spot.distance then right = right .. ", " .. format(L["%s away"], Percent(spot.distance)) end

        tinsert(lines, Line("  " .. MapLabel(spot.map) .. "  " .. Percent(spot.x) .. " / " .. Percent(spot.y),
            right .. "  [" .. spot.source .. "]"))
    end
    if #spots > MAX_SPOTS then
        tinsert(lines, Line("  " .. format(L["... %d more"], #spots - MAX_SPOTS)))
    end
    return lines
end

local function AddSpotLines(lines, kind, ids)
    for _, line in ipairs(DB:DebugSpotLines(kind, ids)) do tinsert(lines, line) end
end

local function Header(module)
    return Line(format("|cff9d9d9d[DEBUG]|r %s(%s)", Glimpse.name, module:GetName()))
end

local function NodeLines(module, id)
    local lines = { Header(module), Line(L["ID"] .. ": " .. id) }
    local node = DB:GetNode(id)

    if not node then
        tinsert(lines, Line(L["No data recorded yet"]))
        return lines
    end

    tinsert(lines, Line(L["Name"] .. ": " .. tostring(node.name or "?")))
    tinsert(lines, Line(L["Category"] .. ": " .. tostring(node.category or "?")))

    local drops, attempts = DB:GetNodeDrops(id)
    tinsert(lines, Line(format(L["%d attempts"], attempts)))
    AddItems(lines, drops)
    AddSpotLines(lines, "node", { id })
    return lines
end

local function UnitLines(module, id)
    local lines = { Header(module), Line(L["ID"] .. ": " .. id) }
    local npc = DB:GetNPC(id)

    if not npc then
        tinsert(lines, Line(L["No data recorded yet"]))
        return lines
    end

    tinsert(lines, Line(L["Name"] .. ": " .. tostring(npc.name or "?")))
    if npc.level then tinsert(lines, Line(L["Level"] .. ": " .. npc.level)) end

    for _, kind in ipairs({ "loot", "skinning" }) do
        if npc[kind] then
            local drops, attempts = DB:GetNPCDrops(id, kind)
            tinsert(lines, Line(L[kind == "loot" and "Loot" or "Skinning"] .. ": " .. format(L["%d attempts"], attempts)))
            AddItems(lines, drops)
        end
    end
    AddSpotLines(lines, "npc", { id })
    return lines
end

-- Was ein Tooltip beschreibt: "node" oder "npc" und die ID, aus der GUID, bei Objekten notfalls
-- aus data.id (dasselbe wie in GatheringTooltip)
local function SourceOf(data, isObject)
    local guid = data.guid
    if type(guid) == "string" then
        local kind, _, _, _, _, id = strsplit("-", guid)
        id = tonumber(id)

        if id then
            if kind == "GameObject" then return "node", id end
            if kind == "Creature" or kind == "Vehicle" then return "npc", id end
        end
    end

    if isObject and data.id then return "node", data.id end
end

-- Objekt-Tooltips ohne ID (so kommen Sammelknoten in der Welt an): Der Name aus der ersten Zeile
-- ist alles, was wir haben. Die Rohdaten aller Knoten mit diesem Namen werden zusammengezählt.
local function NodeNameLines(module, name, data, hidden)
    local lines = { Header(module) }

    if not name then
        tinsert(lines, Line(L["No source ID in tooltip data"]))
        local keys = {}
        for key in pairs(data) do tinsert(keys, tostring(key)) end
        table.sort(keys)
        tinsert(lines, Line(L["Fields"] .. ": " .. table.concat(keys, ", ")))
        if hidden and #hidden > 0 then
            tinsert(lines, Line(L["Secret fields"] .. ": " .. table.concat(hidden, ", ")))
        end
        return lines
    end

    tinsert(lines, Line(L["Name"] .. ": " .. name .. " (" .. L["no ID in tooltip"] .. ")"))

    local ids = DB:FindNodeIDs(name)
    if #ids == 0 then
        tinsert(lines, Line(L["No data recorded yet"]))
        return lines
    end

    tinsert(lines, Line(L["ID"] .. ": " .. table.concat(ids, ", ")))

    local drops, attempts = DB:GetNodeDropsByName(name)
    tinsert(lines, Line(format(L["%d attempts"], attempts)))
    AddItems(lines, drops)
    AddSpotLines(lines, "node", ids)
    return lines
end

local function SourceLines(module, data, hidden, isObject, tooltip)
    -- Der Schalter wird bei jedem Tooltip geprüft, damit man Debug live umschalten kann
    if not Glimpse:IsDebug() then return nil end

    local kind, id = SourceOf(data, isObject)
    if kind == "node" then return NodeLines(module, id) end
    if kind == "npc" then return UnitLines(module, id) end
    if isObject then return NodeNameLines(module, DB:GetTooltipName(tooltip), data, hidden) end
end

function DB:RegisterDebugTooltips()
    local types = Enum.TooltipDataType

    self:RegisterTooltipLine(types.Object, function(module, data, tooltip, hidden)
        return SourceLines(module, data, hidden, true, tooltip)
    end)
    self:RegisterTooltipLine(types.Unit, function(module, data, tooltip, hidden)
        return SourceLines(module, data, hidden, false, tooltip)
    end)
end
