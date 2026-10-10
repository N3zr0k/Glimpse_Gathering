local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")
local Locations = Glimpse:GetModule("Locations")

-- Fundorte aus anderen Addons (z. B. GatherMate2). Nie gespeichert oder exportiert, nur bei
-- DB:GetSpots hinter die eigenen Orte gehängt. Kein Adapter von Glimpse: Database, weil die Orte eine Dichte
-- tragen, je Anbieter abschaltbar sind und GatherMate2 die Knoten über den Namen statt über die Objekt-ID findet.
--
-- Ein Anbieter ist eine Tabelle mit:
--   IsAvailable()                        true, wenn das andere Addon da und benutzbar ist
--   GetSpots(kind, id, entry)            Liste { map, x, y, density } (x, y von 0 bis 1) oder nil;
--                                        entry = Knoten bzw. Kreatur aus GetNode/GetNPC (mit Name)
--   GetInfo()  (optional)                { points = Zahl der Punkte, ... } für die Statistik
-- Fehler eines Anbieters werden abgefangen, es fehlen dann nur dessen Orte.

DB.EXTERNAL_LIMIT = 60 -- höchstens so viele fremde Orte je Quelle (der beste jeder Karte zuerst)

local providers = {}   -- Reihenfolge der Anmeldung
local byName = {}

--- Meldet einen Anbieter an. Gleicher Name ersetzt den alten.
function DB:RegisterProvider(name, provider)
    if type(name) ~= "string" or type(provider) ~= "table" then return end

    if byName[name] then
        for index, entry in ipairs(providers) do
            if entry.name == name then providers[index] = { name = name, provider = provider } end
        end
    else
        tinsert(providers, { name = name, provider = provider })
    end
    byName[name] = provider
end

local function Available(provider)
    local ok, result = pcall(provider.IsAvailable)
    return ok and result and true or false
end

--- Anbieter in den Optionen zugelassen? Standard ja, auch ohne Einstellungen.
function DB:IsProviderEnabled(name)
    local profile = self.db and self.db.profile
    local chosen = profile and profile.externalSources
    return not chosen or chosen[name] ~= false
end

--- Ist das Addon dieses Anbieters da und benutzbar?
function DB:GetProviderAvailable(name)
    return byName[name] ~= nil and Available(byName[name])
end

--- Liste der Anbieter: { name, available (Addon da), enabled (in den Optionen zugelassen) }.
function DB:GetProviders()
    local list = {}
    for _, entry in ipairs(providers) do
        tinsert(list, {
            name = entry.name, available = Available(entry.provider), enabled = self:IsProviderEnabled(entry.name),
        })
    end
    return list
end

--- Option "Daten anderer Addons verwenden" an? Ohne Einstellungen (Tests) ja.
function DB:UseExternalSpots()
    local profile = self.db and self.db.profile
    return not profile or profile.useExternalSpots ~= false
end

--- Informationen der Anbieter für die Statistik: Liste { name, available, points }.
function DB:GetProviderInfo()
    local list = {}
    for _, entry in ipairs(providers) do
        local item = {
            name = entry.name, available = Available(entry.provider), enabled = self:IsProviderEnabled(entry.name), points = 0,
        }
        if item.available and item.enabled and entry.provider.GetInfo then
            local ok, info = pcall(entry.provider.GetInfo)
            if ok and type(info) == "table" then item.points = tonumber(info.points) or 0 else self:ReportError(entry.name, info) end
        end
        tinsert(list, item)
    end
    return list
end

--- Gibt es einen benutzbaren Anbieter?
function DB:HasAvailableProvider()
    for _, entry in ipairs(providers) do
        if Available(entry.provider) then return true end
    end
    return false
end

--- Statistikzeilen wie "GatherMate2: 1234 Punkte", leer ohne Anbieter oder bei Option aus.
function DB:ProviderStatistics()
    if not self:UseExternalSpots() then return "" end

    local L = self.L
    local lines = {}
    for _, info in ipairs(self:GetProviderInfo()) do
        if info.available and info.enabled then tinsert(lines, format(L["%s: %d locations"], info.name, info.points)) end
    end
    return table.concat(lines, "\n")
end

--- Beschreibung der Option, je nachdem ob ein Anbieter da ist.
function DB:ExternalSpotsDescription()
    local L = self.L
    if self:HasAvailableProvider() then
        return L["Also lists locations from other addons (GatherMate2) after your own. They are not saved or exported."]
    end
    return L["No supported addon found. Install GatherMate2 to use its locations."]
end

local function Near(list, map, x, y, radius2)
    for _, spot in ipairs(list) do
        if spot.map == map and spot.x then
            local dx, dy = spot.x - x, spot.y - y
            if dx * dx + dy * dy <= radius2 then return true end
        end
    end
    return false
end

--- Hängt Orte der Anbieter an list an (aus DB:GetSpots). Fremde Orte nahe an eigenen fallen weg.
-- Eintrag: { map, x, y, count = 0, density, source = Anbieter }.
function DB:AddExternalSpots(list, kind, id)
    if #providers == 0 or not self:UseExternalSpots() then return end

    local entry
    if kind == "node" then entry = self:GetNode(id) elseif kind == "npc" then entry = self:GetNPC(id) end
    if not entry then return end

    local radius = self.SPOT_RADIUS / 10000
    local radius2 = radius * radius
    local own = #list
    local ownSpots = {}
    for index = 1, own do ownSpots[index] = list[index] end

    for _, item in ipairs(providers) do
        if self:IsProviderEnabled(item.name) and Available(item.provider) then
            local ok, spots = pcall(item.provider.GetSpots, kind, id, entry)
            if not ok then
                self:ReportError(item.name, spots)
            elseif type(spots) == "table" then
                local added = {}
                for _, spot in ipairs(spots) do
                    if type(spot.map) == "number" and type(spot.x) == "number" and type(spot.y) == "number"
                        and spot.x > 0 and spot.x <= 1 and spot.y > 0 and spot.y <= 1
                        and not Near(ownSpots, spot.map, spot.x, spot.y, radius2) then
                        tinsert(added, {
                            map = spot.map, x = spot.x, y = spot.y, count = 0,
                            density = tonumber(spot.density) or 1, source = item.name,
                        })
                    end
                end

                table.sort(added, function(a, b)
                    if a.density ~= b.density then return a.density > b.density end
                    if a.map ~= b.map then return a.map < b.map end
                    if a.x ~= b.x then return a.x < b.x end
                    return a.y < b.y
                end)

                -- Erst der beste Ort jeder Karte, dann der Rest nach Dichte, damit keine Zone verdrängt wird.
                -- Insgesamt max. EXTERNAL_LIMIT.
                local firsts, rest, seenMap = {}, {}, {}
                for _, spot in ipairs(added) do
                    if seenMap[spot.map] then
                        tinsert(rest, spot)
                    else
                        seenMap[spot.map] = true
                        tinsert(firsts, spot)
                    end
                end
                local taken = 0
                for _, group in ipairs({ firsts, rest }) do
                    for _, spot in ipairs(group) do
                        if taken >= self.EXTERNAL_LIMIT then break end
                        tinsert(list, spot)
                        taken = taken + 1
                    end
                end
            end
        end
    end
end

--- Fundort im Gebiet des Spielers (gleiche Karte oder Instanz)? area = GetPlayerArea().
function DB:IsSpotHere(spot, area)
    if not area then return false end
    if spot.instance then return area.instance == spot.instance end
    return area.map ~= nil and spot.map == area.map
end

--- Nächste Fundorte einer Quelle, mit Stufe (tier) relativ zum Spieler:
--   1  eigenes Gebiet; auf Karten mit distance (Yards, wenn Kartengröße bekannt) und mapDistance (Anteil Kartenbreite),
--      eine Zone ohne Koordinaten ohne Entfernung (hinter den Orten)
--   2  andere Karte desselben Kontinents, distance = Luftlinie (wenn Weltpositionen verfügbar). Ist der
--      Kontinent unbekannt (keine Position, Instanz, keine Kartenfunktion), landen alle Karten hier
--   3  anderer Kontinent oder andere Instanz
-- Sortiert nach Stufe, in 1 und 2 nach Entfernung (ohne dahinter), sonst wie GetSpots. In einer Instanz
-- kommt deren Fundort zuerst (here = true). currentMapOnly: nur Stufe 1. Ohne Position: Karten 2, Instanzen 3.
function DB:GetNearestSpots(kind, id, limit, currentMapOnly)
    local spots = self:GetSpots(kind, id)
    local position = Locations:GetPlayerArea()
    if not position then
        if currentMapOnly then return {} end
        for _, spot in ipairs(spots) do spot.tier = spot.instance and 3 or 2 end
        if limit then while #spots > limit do tremove(spots) end end
        return spots
    end

    -- Kontinent und Weltposition des Spielers (nur auf einer Karte, nicht in einer Instanz)
    local playerContinent, playerWorld, playerA, playerB
    if position.map and not currentMapOnly then
        playerContinent = Locations:GetContinent(position.map)
        playerWorld, playerA, playerB = Locations:GetWorldPosition(position.map, position.x, position.y)
    end

    local inside, near, far = {}, {}, {}
    for index, spot in ipairs(spots) do
        if spot.instance then
            -- eine Instanz hat keine Koordinaten, also auch keine Entfernung
            if self:IsSpotHere(spot, position) then
                spot.here, spot.tier = true, 1
                tinsert(inside, spot)
            elseif not currentMapOnly then
                spot.tier = 3
                tinsert(far, { spot = spot, index = index })
            end
        elseif position.map and spot.map == position.map then
            spot.tier = 1
            if spot.x then
                local dx, dy = spot.x - position.x, spot.y - position.y
                spot.mapDistance = math.sqrt(dx * dx + dy * dy)
                spot.distance = Locations:GetMapDistance(spot.map, spot.x, spot.y, position.x, position.y)
            end
            tinsert(near, spot)
        elseif not currentMapOnly then
            -- andere Karte: derselbe Kontinent (Stufe 2) oder ein anderer (Stufe 3)
            local same
            if position.map then
                local continent = Locations:GetContinent(spot.map)
                if playerContinent and continent then same = playerContinent == continent end

                local world, a, b
                if spot.x then world, a, b = Locations:GetWorldPosition(spot.map, spot.x, spot.y) end
                if playerWorld and world then
                    if same == nil then same = playerWorld == world end
                    if world == playerWorld then
                        local da, db = a - playerA, b - playerB
                        spot.distance = math.sqrt(da * da + db * db)
                    end
                end
            end
            spot.tier = same == false and 3 or 2
            tinsert(far, { spot = spot, index = index })
        end
    end
    -- auf einer Karte haben alle Orte Yards oder keiner, also vergleichbar; Zonen ohne Koordinaten dahinter
    table.sort(near, function(a, b)
        local da, db = a.distance or a.mapDistance, b.distance or b.mapDistance
        if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
        if da and da ~= db then return da < db end
        return a.count > b.count
    end)
    table.sort(far, function(a, b)
        if a.spot.tier ~= b.spot.tier then return a.spot.tier < b.spot.tier end
        local da, db = a.spot.distance, b.spot.distance
        if da and db and da ~= db then return da < db end
        if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
        return a.index < b.index
    end)
    -- in der Instanz, in der man steht, kommt sie vor allem anderen
    for index, spot in ipairs(inside) do tinsert(near, index, spot) end
    for _, item in ipairs(far) do tinsert(near, item.spot) end

    if limit then while #near > limit do tremove(near) end end
    return near
end
