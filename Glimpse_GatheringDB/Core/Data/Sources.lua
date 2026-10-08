local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Wo man ein Material am besten findet (für Anzeigen wie GatheringTooltip).
--
-- Ein Eintrag = eine Quelle an einem Ort (Zone oder Instanz). Mehrere Orte einer Zone ergeben einen
-- Eintrag (der nächste), Quellen ohne Ort einen ohne Ort. Stufen:
--   1  "here"      im eigenen Gebiet (Karte oder Instanz des Spielers)
--   2  "nearby"    auf einer anderen Karte desselben Kontinents
--   3  "elsewhere" auf einem anderen Kontinent oder in einer anderen Instanz
--   4  "none"      kein bekannter Ort
-- Je Stufe bestätigte (own) vor externen Orten (nur mit externalSeparate). Danach Stufe 1 und 3 nach
-- Chance, Stufe 2 nach Entfernung (ohne Entfernung dahinter, nach Chance).

local AREAS = { "here", "nearby", "elsewhere", "none" }

local function PlaceKey(spot)
    return spot.instance and ("i" .. spot.instance) or ("m" .. spot.map)
end

--- Einträge zu einem Material: Kopie der Quelle aus GetItemSources (nicht verändern) plus:
--   tier    1 bis 4 (siehe oben), area = "here" | "nearby" | "elsewhere" | "none"
--   group   "own" | "external" (nil bei Stufe 4)
--   spot    bester Ort aus GetNearestSpots (nächster bestätigter, sonst nächster externer), nil bei Stufe 4
--   spots   alle Fundorte der Quelle an diesem Ort (Zone oder Instanz)
--   place   Schlüssel des Ortes ("m37" für Karte 37, "i36" für Instanz 36), nil bei Stufe 4
-- externalSeparate (Standard true): bestätigte Orte vor externen. false: externe zählen wie eigene.
-- minChance (0 bis 1, Standard keine): Einträge der Stufe 2 mit kleinerer Chance entfallen.
function DB:GetLocatedItemSources(itemID, minAttempts, externalSeparate, minChance)
    local separate = externalSeparate ~= false

    local result = {}
    local function Add(source, fields)
        local entry = {}
        for key, value in pairs(source) do entry[key] = value end
        for key, value in pairs(fields) do entry[key] = value end
        entry.area = AREAS[entry.tier]

        if not (entry.tier == 2 and minChance and entry.chance < minChance) then tinsert(result, entry) end
    end

    for _, source in ipairs(self:GetItemSources(itemID, minAttempts)) do
        -- die Orte (nächste zuerst) nach Zone oder Instanz zusammenfassen
        local places, order = {}, {}
        for _, spot in ipairs(self:GetNearestSpots(source.kind, source.id)) do
            local key = PlaceKey(spot)
            local place = places[key]
            if not place then
                place = { key = key, tier = spot.tier, spots = {} }
                places[key] = place
                tinsert(order, place)
            end
            tinsert(place.spots, spot)
        end

        if #order == 0 then Add(source, { tier = 4, spots = {} }) end

        for _, place in ipairs(order) do
            -- bester Ort: der nächste bestätigte, sonst der nächste externe (zusammengefasst: einfach der nächste)
            local best = place.spots[1]
            if separate then
                for _, spot in ipairs(place.spots) do
                    if spot.source == "own" then
                        best = spot
                        break
                    end
                end
            end
            local group = (not separate or best.source == "own") and "own" or "external"

            Add(source, { tier = place.tier, group = group, spot = best, spots = place.spots, place = place.key })
        end
    end

    local function Rank(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.group ~= b.group then return a.group == "own" end -- nur bei externalSeparate verschieden

        if a.tier == 2 then
            local da, db = a.spot and a.spot.distance, b.spot and b.spot.distance
            if da and db and da ~= db then return da < db end
            if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
        end

        if a.chance ~= b.chance then return a.chance > b.chance end
        if a.attempts ~= b.attempts then return a.attempts > b.attempts end
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.id ~= b.id then return a.id < b.id end
        if a.mode ~= b.mode then return a.mode < b.mode end
        return (a.place or "") < (b.place or "")
    end
    table.sort(result, Rank)
    return result
end
