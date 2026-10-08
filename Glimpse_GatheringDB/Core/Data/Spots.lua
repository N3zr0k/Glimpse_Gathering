local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Fundorte speichern und abfragen. Alles ohne local ist öffentliche API (siehe Core/GatheringDB.lua).

-- Fundorte je Quelle: Karte (uiMapID) und Position beim Looten. Koordinaten als Ganzzahl 1..10000
-- (kleine Datei). Orte näher als SPOT_RADIUS werden zusammengefasst (gewichteter Mittelpunkt, n = Funde).
-- Max. MAX_SPOTS_* je Quelle, darüber fällt der Ort mit den wenigsten Funden weg.
DB.SPOT_RADIUS = 100 -- 1 % der Karte
DB.MAX_SPOTS_NODE = 40
DB.MAX_SPOTS_NPC = 12

local SPOT_MAX = 10000
local COUNT_MAX = 1e9 - 1

--- Führt einen Ort in eine Liste von Fundorten ein. x und y in 1/10000, n = Zahl der Funde.
function DB:MergeSpot(list, map, x, y, n, limit)
    local radius2 = self.SPOT_RADIUS * self.SPOT_RADIUS
    local best, bestDistance

    for _, spot in ipairs(list) do
        if spot.map == map then
            local dx, dy = spot.x - x, spot.y - y
            local distance = dx * dx + dy * dy
            if distance <= radius2 and (not bestDistance or distance < bestDistance) then
                best, bestDistance = spot, distance
            end
        end
    end

    if best then
        local total = best.n + n
        best.x = math.floor((best.x * best.n + x * n) / total + 0.5)
        best.y = math.floor((best.y * best.n + y * n) / total + 0.5)
        best.n = math.min(total, COUNT_MAX)
        return
    end

    tinsert(list, { map = map, x = x, y = y, n = math.min(n, COUNT_MAX) })

    if #list > limit then
        -- den schwächsten Ort entfernen, bei Gleichstand den ältesten
        local weakest = 1
        for index = 2, #list do
            if list[index].n < list[weakest].n then weakest = index end
        end
        tremove(list, weakest)
    end
end

--- Führt eine Instanz als Fundort in eine Liste ein: { inst = instanceID, n = Zahl der Funde }.
function DB:MergeInstanceSpot(list, instance, n, limit)
    for _, spot in ipairs(list) do
        if spot.inst == instance then
            spot.n = math.min(spot.n + n, COUNT_MAX)
            return
        end
    end

    tinsert(list, { inst = instance, n = math.min(n, COUNT_MAX) })

    if #list > limit then
        local weakest = 1
        for index = 2, #list do
            if list[index].n < list[weakest].n then weakest = index end
        end
        tremove(list, weakest)
    end
end

local MAX_INSTANCE_NAME = 100

--- Fundort für Knoten/Kreatur merken. pos = { map, x, y } (x, y 0..1 wie C_Map.GetPlayerMapPosition)
-- oder { instance, name } in Instanzen. Ungültige Orte werden ignoriert.
function DB:AddSpot(entry, kind, pos)
    if type(pos) ~= "table" then return end
    local limit = kind == "npc" and self.MAX_SPOTS_NPC or self.MAX_SPOTS_NODE

    if pos.instance ~= nil then
        local id = pos.instance
        if type(id) ~= "number" or id < 1 or id >= 1e6 or id ~= math.floor(id) then return end

        entry.spots = entry.spots or {}
        self:MergeInstanceSpot(entry.spots, id, 1, limit)

        -- Name der Instanz einmal je ID merken (der aktuelle gilt)
        if type(pos.name) == "string" and pos.name ~= "" then
            self.data.instances = self.data.instances or {}
            self.data.instances[id] = pos.name:sub(1, MAX_INSTANCE_NAME)
        end
        return
    end

    if type(pos.map) ~= "number" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end

    local x = math.floor(pos.x * SPOT_MAX + 0.5)
    local y = math.floor(pos.y * SPOT_MAX + 0.5)
    if pos.map < 1 or x < 1 or y < 1 or x > SPOT_MAX or y > SPOT_MAX then return end

    entry.spots = entry.spots or {}
    self:MergeSpot(entry.spots, pos.map, x, y, 1, limit)
end

--- Name einer Instanz (aus gelooteter Beute) oder nil.
function DB:GetInstanceName(instance)
    local names = self.data.instances
    return names and names[instance] or nil
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

--- Eigene Fundorte einer Quelle (kind = "node", "npc" oder "fishing" mit id = Karte), häufigste zuerst:
-- { map, x, y (0..1), count, source = "own" }, passt direkt zu TomTom:AddWaypoint(map, x, y, opts).
-- In Instanzen { instance, name?, count, source = "own" } ohne Wegpunkt.
function DB:GetOwnSpots(kind, id)
    local entry
    if kind == "node" then entry = self:GetNode(id) elseif kind == "npc" then entry = self:GetNPC(id)
    elseif kind == "fishing" then entry = self:GetFishing(id) end

    local list = {}
    for _, spot in ipairs(entry and entry.spots or {}) do
        if spot.inst then
            tinsert(list, { instance = spot.inst, name = self:GetInstanceName(spot.inst), count = spot.n, source = "own" })
        else
            tinsert(list, { map = spot.map, x = spot.x / SPOT_MAX, y = spot.y / SPOT_MAX, count = spot.n, source = "own" })
        end
    end

    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        -- Orte auf Karten vor Instanzen, sonst nach Nummer und Lage
        if (a.instance ~= nil) ~= (b.instance ~= nil) then return a.instance == nil end
        if a.instance then return a.instance < b.instance end
        if a.map ~= b.map then return a.map < b.map end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return list
end

--- Fundorte einer Quelle: { map, x, y (0..1), count, source }. Eigene zuerst (source = "own", count = Funde),
-- dann externe (source = Anbieter, count = 0, density = Punkte), außer includeExternal = false oder
-- Option aus (Core/Data/Providers.lua).
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
                map = spot.map, x = spot.x, y = spot.y, count = spot.count, source = spot.source, density = spot.density,
                kind = source.kind, id = source.id, mode = source.mode, name = source.name, chance = source.chance,
            })
            if limit and #result >= limit then return result end
        end
    end

    return result
end

--- Name einer Karte (Zone) oder nil.
function DB:GetMapName(map)
    return Locations:GetMapName(map)
end
