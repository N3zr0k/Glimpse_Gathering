local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Fundorte aus anderen Addons (z. B. GatherMate2). Sie werden nie gespeichert und nie exportiert,
-- sondern erst beim Abfragen (DB:GetSpots) hinter die eigenen Orte gehängt.
--
-- Ein Anbieter ist eine Tabelle mit:
--   IsAvailable()                        true, wenn das andere Addon da und benutzbar ist
--   GetSpots(kind, id, entry)            Liste { map, x, y, density } (x, y von 0 bis 1) oder nil;
--                                        entry = gespeicherter Knoten bzw. Kreatur
--   GetInfo()  (optional)                { points = Zahl der Punkte, ... } für die Statistik
-- Fehler in einem Anbieter werden abgefangen und gemeldet, dann fehlen nur dessen Orte.

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

--- Hat der Spieler diesen Anbieter in den Optionen zugelassen? (Standard: ja, auch ohne Einstellungen.)
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

--- Ist die Option "Daten anderer Addons verwenden" an? (Ohne Einstellungen, z. B. in Tests: ja.)
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

--- Zeilen für die Statistik, z. B. "GatherMate2: 1234 Punkte" (leer, wenn kein Anbieter da ist oder die
-- Option aus ist).
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
        if spot.map == map then
            local dx, dy = spot.x - x, spot.y - y
            if dx * dx + dy * dy <= radius2 then return true end
        end
    end
    return false
end

--- Hängt die Orte der Anbieter an list an (von DB:GetSpots aufgerufen). Fremde Orte, die nahe an einem
-- eigenen liegen, fallen weg. Eintrag: { map, x, y, count = 0, density, source = Name des Anbieters }.
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

                -- Erst der beste Ort jeder Karte, dann die übrigen nach Dichte: So bleibt jede Zone, in der es
                -- die Quelle gibt, erhalten, auch wenn eine andere viel dichter ist. Insgesamt höchstens EXTERNAL_LIMIT.
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

--- Liegt der Fundort im Gebiet des Spielers? area = Ergebnis von GetPlayerArea: dieselbe Karte oder
-- dieselbe Instanz.
function DB:IsSpotHere(spot, area)
    if not area then return false end
    if spot.instance then return area.instance == spot.instance end
    return area.map ~= nil and spot.map == area.map
end

--- Die nächsten Fundorte einer Quelle. Orte auf der Karte, auf der der Spieler steht, kommen zuerst und
-- sind nach Entfernung sortiert. Sie haben distance (Yards, nur wenn die Kartengröße bekannt ist) und
-- mapDistance (Bruchteil der Kartenbreite, immer). Orte auf anderen Karten folgen in der gewohnten
-- Reihenfolge (ohne Entfernung), oder fehlen, wenn currentMapOnly gesetzt ist. Steht der Spieler in einer
-- Instanz, kommt zuerst deren Fundort (ohne Entfernung). Ohne bekannte Position wie GetSpots.
function DB:GetNearestSpots(kind, id, limit, currentMapOnly)
    local spots = self:GetSpots(kind, id)
    local position = self:GetPlayerArea()
    if not position then
        if currentMapOnly then return {} end
        if limit then while #spots > limit do tremove(spots) end end
        return spots
    end

    local inside, near, far = {}, {}, {}
    for _, spot in ipairs(spots) do
        if spot.instance then
            -- eine Instanz hat keine Koordinaten, also auch keine Entfernung
            if self:IsSpotHere(spot, position) then
                spot.here = true
                tinsert(inside, spot)
            elseif not currentMapOnly then tinsert(far, spot) end
        elseif position.map and spot.map == position.map then
            local dx, dy = spot.x - position.x, spot.y - position.y
            spot.mapDistance = math.sqrt(dx * dx + dy * dy)
            spot.distance = self:GetMapDistance(spot.map, spot.x, spot.y, position.x, position.y)
            tinsert(near, spot)
        elseif not currentMapOnly then
            tinsert(far, spot)
        end
    end
    -- auf einer Karte haben alle Orte Yards oder keiner, die Karte selbst ist also immer vergleichbar
    table.sort(near, function(a, b)
        local da, db = a.distance or a.mapDistance, b.distance or b.mapDistance
        if da ~= db then return da < db end
        return a.count > b.count
    end)
    -- in der Instanz, in der man steht, kommt sie vor allem anderen
    for index, spot in ipairs(inside) do tinsert(near, index, spot) end
    for _, spot in ipairs(far) do tinsert(near, spot) end

    if limit then while #near > limit do tremove(near) end end
    return near
end
