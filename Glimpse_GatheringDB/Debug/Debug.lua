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
