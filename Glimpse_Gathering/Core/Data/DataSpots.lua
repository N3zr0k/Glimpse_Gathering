local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")
local Locations = Glimpse:GetModule("Locations")

-- Fundorte lesen. Alles ohne local ist öffentliche API (siehe Core/GatheringData.lua).
--
-- Quelle der Fundorte sind die Zonen einer Art (zones in Glimpse: Database) und die Orte (places):
--   Knoten     Orte mit Koordinaten (ID = Objekt), Zonen ohne Ort als Zone ohne Koordinaten
--   Kreaturen  nur Zonen (npc und skinned): Orte in Database tragen keine Art, Objekt- und NPC-IDs würden sich mischen
--   Angeln     Orte im Namespace fishing (ID = Zone), sonst die Zone selbst
-- Zonen sind uiMapIDs, in Instanzen -instanceID. count = Funde in dieser Zone.

-- Orte näher als SPOT_RADIUS (1/10000 der Karte) gelten als derselbe (LootNode.lua, DataProviders.lua)
DB.SPOT_RADIUS = 100

-- Zonen einer Quelle: { [Zone] = Funde }
local function Zones(kind, id)
    local result = {}
    local function Add(reader, kinds)
        for _, art in ipairs(kinds) do
            for zone, n in pairs(reader:GetZones(art, id, DB.WORLD_SCOPE)) do result[zone] = (result[zone] or 0) + n end
        end
    end

    if kind == "fishing" then
        local reader = DB:Reader(DB.FISHING_NAMESPACE)
        local n = reader and reader:GetCount("looted", id, DB.WORLD_SCOPE) or 0
        if n > 0 then result[id] = n end
        return result, reader
    end

    local reader = DB:Reader()
    if reader then Add(reader, kind == "npc" and { "npc", "skinned" } or { "node" }) end
    return result, reader
end

local function SpotOrder(a, b)
    if a.count ~= b.count then return a.count > b.count end
    -- Orte auf Karten vor Instanzen, sonst nach Nummer und Lage
    if (a.instance ~= nil) ~= (b.instance ~= nil) then return a.instance == nil end
    if a.instance then return a.instance < b.instance end
    if a.map ~= b.map then return a.map < b.map end
    if (a.x ~= nil) ~= (b.x ~= nil) then return a.x ~= nil end
    if a.x and a.x ~= b.x then return a.x < b.x end
    return (a.y or 0) < (b.y or 0)
end

--- Fundorte einer Quelle aus Database (kind = "node", "npc" oder "fishing" mit id = Zone), häufigste Zone zuerst:
-- { map, x, y (0..1), count, source = "own" }, passt direkt zu TomTom:AddWaypoint(map, x, y, opts).
-- Zone ohne bekannten Ort: { map, count, source } ohne x, y. In Instanzen { instance, name?, count, source }.
function DB:GetOwnSpots(kind, id)
    id = tonumber(id)
    local list = {}
    if not id then return list end

    local zones, reader = Zones(kind, id)
    for zone, count in pairs(zones) do
        if zone < 0 then
            tinsert(list, { instance = -zone, name = self:GetInstanceName(-zone), count = count, source = "own" })
        else
            local found = false
            if kind ~= "npc" then
                for _, place in ipairs(reader:GetLocations(zone, id, self.WORLD_SCOPE)) do
                    tinsert(list, { map = zone, x = place.x, y = place.y, count = count, source = "own" })
                    found = true
                end
            end
            if not found then tinsert(list, { map = zone, count = count, source = "own" }) end
        end
    end

    table.sort(list, SpotOrder)
    return list
end

--- Fundorte einer Quelle: eigene zuerst (source = "own"), dann externe (source = Anbieter, count = 0,
-- density = Punkte), außer includeExternal = false oder Option aus (Core/Data/DataProviders.lua).
function DB:GetSpots(kind, id, includeExternal)
    local list = self:GetOwnSpots(kind, id)
    if includeExternal ~= false and self.AddExternalSpots then self:AddExternalSpots(list, kind, id) end
    return list
end

--- Fundorte aller Quellen eines Items, wahrscheinlichste Quelle zuerst. Eintrag:
-- { map, x, y, count, source, density, kind, id, mode, name, chance }. limit optional, sonst wie GetItemSources/GetSpots.
function DB:GetItemSpots(itemID, minAttempts, limit, includeExternal)
    local result = {}

    for _, source in ipairs(self:GetItemSources(itemID, minAttempts)) do
        for _, spot in ipairs(self:GetSpots(source.kind, source.id, includeExternal)) do
            tinsert(result, {
                map = spot.map, x = spot.x, y = spot.y, instance = spot.instance, count = spot.count,
                source = spot.source, density = spot.density,
                kind = source.kind, id = source.id, mode = source.mode, name = source.name, chance = source.chance,
            })
            if limit and #result >= limit then return result end
        end
    end

    return result
end

--- Ort als Debug-Text: "Instanz Die Todesminen (36)" oder "Karte Elwynn (37) 41.2 / 56.8", sonst nil.
function DB:DescribeArea(area)
    if type(area) ~= "table" then return nil end

    if area.instance then
        return format("Instanz %s (%d)", tostring(area.name or self:GetInstanceName(area.instance) or "?"), area.instance)
    end
    if type(area.map) == "number" and type(area.x) == "number" and type(area.y) == "number" then
        return format("Karte %s (%d) %.1f / %.1f", tostring(Locations:GetMapName(area.map) or "?"), area.map, area.x * 100, area.y * 100)
    end
end

--- Name einer Karte (Zone) oder nil.
function DB:GetMapName(map)
    return Locations:GetMapName(map)
end
