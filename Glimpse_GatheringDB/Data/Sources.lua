local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Quellen eines Materials nach Fundort geordnet (für Anzeigen, die zeigen sollen, wo man etwas findet).
--
-- Reihenfolge, jeweils mit der höchsten Chance zuerst:
--   1. "here"      Quellen mit Fundorten im eigenen Gebiet (die Karte, auf der der Spieler steht)
--   2. "elsewhere" Quellen mit Fundorten in anderen Gebieten
--   3. "external"  Quellen, deren Fundorte nur von anderen Addons kommen (z. B. GatherMate2)
--   4. "none"      Quellen ohne bekannten Fundort
--
-- Option externalSeparate (Standard an): Fundorte anderer Addons zählen nur für Gruppe 3. Ist sie aus, zählen sie wie
-- eigene Orte: sie ordnen eine Quelle in "here" oder "elsewhere" ein, Gruppe 3 entfällt.

--- Sollen Quellen, die nur durch andere Addons einen Fundort haben, getrennt hinten stehen?
function DB:ExternalSeparate()
    local profile = self.db and self.db.profile
    return not profile or profile.externalSeparate ~= false
end

local ORDER = { here = 1, elsewhere = 2, external = 3, none = 4 }

--- Wie GetItemSources (gleiche Einträge, nicht verändern), aber nach Fundort geordnet und mit zusätzlichen Feldern:
--   area    "here" | "elsewhere" | "external" | "none"
--   spots   alle Fundorte der Quelle (eigene und fremde), die nächsten zuerst (siehe GetNearestSpots)
-- Die Einträge sind Kopien, die Daten von GetItemSources bleiben unberührt.
function DB:GetLocatedItemSources(itemID, minAttempts)
    local position = self.GetPlayerPosition and self:GetPlayerPosition()
    local here = position and position.map
    local separate = self:ExternalSeparate()

    local result = {}
    for _, source in ipairs(self:GetItemSources(itemID, minAttempts)) do
        local entry = {}
        for key, value in pairs(source) do entry[key] = value end

        local spots = self:GetNearestSpots(source.kind, source.id)
        local ownHere, ownElse, extHere, extElse = 0, 0, 0, 0
        for _, spot in ipairs(spots) do
            if spot.source == "own" then
                if spot.map == here then ownHere = ownHere + 1 else ownElse = ownElse + 1 end
            else
                if spot.map == here then extHere = extHere + 1 else extElse = extElse + 1 end
            end
        end

        if separate then
            if ownHere > 0 then entry.area = "here"
            elseif ownElse > 0 then entry.area = "elsewhere"
            elseif extHere + extElse > 0 then entry.area = "external"
            else entry.area = "none" end
        else
            if ownHere + extHere > 0 then entry.area = "here"
            elseif ownElse + extElse > 0 then entry.area = "elsewhere"
            else entry.area = "none" end
        end
        entry.spots = spots

        tinsert(result, entry)
    end

    table.sort(result, function(a, b)
        if a.area ~= b.area then return ORDER[a.area] < ORDER[b.area] end
        if a.chance ~= b.chance then return a.chance > b.chance end
        if a.attempts ~= b.attempts then return a.attempts > b.attempts end
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.id ~= b.id then return a.id < b.id end
        return a.mode < b.mode
    end)
    return result
end
