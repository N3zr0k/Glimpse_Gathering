local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")
local L = DB.L

-- Debug-Tooltip (/gli debug on, Kategorie GatheringDB tooltip): Daten aus Glimpse: Database, grau, ohne Icons:
--   [Glimpse: GatheringDB]
--   ID: 179891
--   Name: Waldwolf
--   Loot: 7 attempts
--   Wolfsfell (12345)           3 hits, 4 total
--   ...
--   Locations: 2 own, 14 from other addons
--   Position: Elwynn Forest (37)  41.2 / 56.8
--   Elwynn Forest (37)  41.0 / 55.0      3 finds, 25 yards away  [own]
--   Elwynn Forest (37)  70.2 / 30.2      5 points  [GatherMate2]
-- Dieselben Zeilen gibt es als Probe (DebugProbes.lua).

-- Höchstzahl der Item-Zeilen je Liste
local MAX_ITEMS = 5

local GREY = 0.6

local function Line(text, right)
    return { text, right, GREY, GREY, GREY }
end

local function ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or "?"
end

-- { attempts, items } als Zeilen, nur Treffer und Menge
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

-- Ort eines Fundorts für die Anzeige: Karte mit Koordinaten, Zone ohne Ort oder Instanz
local function PlaceLabel(spot)
    if spot.instance then
        return L["Instance"] .. ": " .. tostring(spot.name or "?") .. " (" .. spot.instance .. ")"
    end
    if not spot.x then return MapLabel(spot.map) end
    return MapLabel(spot.map) .. "  " .. Percent(spot.x) .. " / " .. Percent(spot.y)
end

local function SpotOrder(a, b)
    -- die Instanz, in der man steht, vor allem anderen
    if (a.here == true) ~= (b.here == true) then return a.here == true end
    -- erst die Orte auf der Karte des Spielers, nach Entfernung
    if a.mapDistance or b.mapDistance then
        if not a.mapDistance then return false end
        if not b.mapDistance then return true end
        local da, db = a.distance or a.mapDistance, b.distance or b.mapDistance
        if da ~= db then return da < db end
    end
    local ownA, ownB = a.source == "own", b.source == "own"
    if ownA ~= ownB then return ownA end
    if a.count ~= b.count then return a.count > b.count end
    if (a.density or 0) ~= (b.density or 0) then return (a.density or 0) > (b.density or 0) end
    if (a.map or 0) ~= (b.map or 0) then return (a.map or 0) < (b.map or 0) end
    if (a.x or 0) ~= (b.x or 0) then return (a.x or 0) < (b.x or 0) end
    return (a.y or 0) < (b.y or 0)
end

-- Je Fundort: Karte und Koordinaten (%) links, Funde/Punkte, Entfernung und Quelle rechts
local function SpotLine(spot)
    local right
    if spot.source == "own" then
        right = format(L["%d finds"], spot.count)
    else
        right = format(L["%d points"], spot.density or 0)
    end
    if spot.distance then
        right = right .. ", " .. format(L["%d yards away"], math.floor(spot.distance + 0.5))
    elseif spot.mapDistance then
        right = right .. ", " .. format(L["%s%% of the map away"], Percent(spot.mapDistance))
    end

    if spot.here then right = right .. ", " .. L["here"] end

    return Line("  " .. PlaceLabel(spot), right .. "  [" .. spot.source .. "]")
end

--- Fundort-Zeilen für Quellen einer Art (kind = "node"/"npc", ids = Liste): Anzahl eigene/externe,
-- Spielerposition und die ersten Orte.
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

    local position = Locations:GetPlayerArea()
    if position and position.instance then
        -- in einer Instanz gibt es keine Koordinaten
        tinsert(lines, Line(L["Position"] .. ": " .. PlaceLabel(position)))
    elseif position then
        tinsert(lines, Line(L["Position"] .. ": " .. MapLabel(position.map),
            Percent(position.x) .. " / " .. Percent(position.y)))
    else
        tinsert(lines, Line(L["Position"] .. ": " .. L["unknown"]))
    end

    for index = 1, math.min(#spots, MAX_SPOTS) do tinsert(lines, SpotLine(spots[index])) end
    if #spots > MAX_SPOTS then
        tinsert(lines, Line("  " .. format(L["... %d more"], #spots - MAX_SPOTS)))
    end
    return lines
end

-- Max. Quellen und Orte je Quelle in der Material-Anzeige
local MAX_SOURCES = 5
local MAX_SOURCE_SPOTS = 2

local AREA_LABELS = {
    here = "here", nearby = "same continent", elsewhere = "elsewhere", none = "no location",
}

--- Zeilen für ein Material: Quellen in der Reihenfolge von GetLocatedItemSources, je Eintrag Chance,
-- Stufe und nächste Fundorte. Leer ohne Quelle.
function DB:DebugItemLines(itemID, externalSeparate, minChance)
    local sources = self:GetLocatedItemSources(itemID, 1, externalSeparate, minChance)
    if #sources == 0 then return {} end

    local lines = {}
    tinsert(lines, Line(L["Places"] .. ": " .. #sources .. "  (" ..
        (externalSeparate ~= false and L["outside separate"] or L["outside combined"]) .. ")"))

    for index = 1, math.min(#sources, MAX_SOURCES) do
        local source = sources[index]
        local name = tostring(source.name or "?") .. " (" .. source.kind .. " " .. source.id .. ", " .. source.mode .. ")"
        local label = L[AREA_LABELS[source.area]]
        if source.group then label = label .. ", " .. L[source.group == "own" and "confirmed" or "outside"] end
        tinsert(lines, Line(name, format("%d/%d = %.1f%%  [%s]", source.hits, source.attempts, source.chance * 100, label)))

        for spotIndex = 1, math.min(#source.spots, MAX_SOURCE_SPOTS) do
            tinsert(lines, SpotLine(source.spots[spotIndex]))
        end
        if #source.spots > MAX_SOURCE_SPOTS then
            tinsert(lines, Line("  " .. format(L["... %d more"], #source.spots - MAX_SOURCE_SPOTS)))
        end
    end
    if #sources > MAX_SOURCES then
        tinsert(lines, Line(format(L["... %d more"], #sources - MAX_SOURCES)))
    end
    return lines
end

local function AddSpotLines(lines, kind, ids)
    for _, line in ipairs(DB:DebugSpotLines(kind, ids)) do tinsert(lines, line) end
end

-- Kennung wie bei allen Debug-Ausgaben der Suite: [Glimpse: GatheringDB]
local function Header()
    return Line(Glimpse:DebugTag(ADDON_NAME))
end

local function NodeLines(id)
    local lines = { Header(), Line(L["ID"] .. ": " .. id) }
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

local function UnitLines(id)
    local lines = { Header(), Line(L["ID"] .. ": " .. id) }
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

-- "node"/"npc" und ID aus der GUID, bei Objekten notfalls data.id (wie in GatheringTooltip)
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

-- Knoten in der Welt haben im Tooltip keine ID, nur den Namen aus der ersten Zeile. Alle Knoten
-- mit diesem Namen werden zusammengezählt.
local function NodeNameLines(name, data, hidden)
    local lines = { Header() }

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

local function SourceLines(data, hidden, isObject, tooltip)
    -- Bei jedem Tooltip prüfen, damit Debug live umschaltbar ist
    if not DB.debug:IsOn("tooltip") then return nil end

    local kind, id = SourceOf(data, isObject)
    if kind == "node" then return NodeLines(id) end
    if kind == "npc" then return UnitLines(id) end
    if isObject then return NodeNameLines(DB:GetTooltipName(tooltip), data, hidden) end
end

-- Material: Quellen mit Fundorten, nur bei Debug und vorhandenen Quellen
local function ItemLines(_, data)
    if not DB.debug:IsOn("tooltip") then return nil end

    local itemID = tonumber(data.id)
    if not itemID then return nil end

    -- Sortierung von GatheringTooltip übernehmen, falls geladen (nur lesend). Ohne Mindestchance,
    -- Debug zeigt alle Quellen.
    local tooltip = Glimpse:GetModule("GatheringTooltip", true)
    local profile = tooltip and tooltip.db and tooltip.db.profile
    local sources = DB:DebugItemLines(itemID, not profile or profile.externalSeparate ~= false)
    if #sources == 0 then return nil end

    local lines = { Header(), Line(L["ID"] .. ": " .. itemID) }
    for _, line in ipairs(sources) do tinsert(lines, line) end
    return lines
end

function DB:RegisterDebugTooltips()
    local types = Enum.TooltipDataType

    self:RegisterTooltipLine(types.Item, ItemLines)
    self:RegisterTooltipLine(types.Object, function(_, data, tooltip, hidden)
        return SourceLines(data, hidden, true, tooltip)
    end)
    self:RegisterTooltipLine(types.Unit, function(_, data, tooltip, hidden)
        return SourceLines(data, hidden, false, tooltip)
    end)
end

--- Zeilen zu einem Knoten oder einer Kreatur (kind = "node" oder "npc"), auch für die Probes
function DB:DebugSourceLines(kind, id)
    return (kind == "npc" and UnitLines or NodeLines)(id)
end
