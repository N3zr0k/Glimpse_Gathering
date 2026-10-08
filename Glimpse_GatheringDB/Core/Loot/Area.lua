local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Debug: Ortserkennung bei Gebietswechsel ausgeben. Verzögert, weil Instanzdaten direkt nach dem
-- Event noch falsch sein können; mehrere Events werden zusammengefasst.

local Clean, DebugOn = DB.collect.Clean, DB.collect.DebugOn

local AREA_DELAY = 1
local areaPending = false

local function RawValues(func)
    if not func then return "nicht vorhanden" end

    local values = { pcall(func) }
    if not values[1] then return "Fehler: " .. tostring(values[2]) end

    local parts = {}
    for i = 2, math.max(#values, 9) do parts[#parts + 1] = tostring(Clean(values[i])) end
    return table.concat(parts, ", ")
end

function DB:DebugArea(event)
    self:Debug("Gebiet (" .. tostring(event) .. "):", self:DescribeArea(Locations:GetPlayerArea()) or "nicht bestimmbar (keine Karte, Koordinaten oder Instanz)")
    self:Debug("IsInInstance:", RawValues(Locations.api.IsInInstance))
    self:Debug("GetInstanceInfo:", RawValues(Locations.api.GetInstanceInfo))
    self:Debug("Aufzeichnung der Fundorte:", self.db.profile.trackLocations and "an" or "aus")
end

function DB:OnAreaChanged(event)
    if areaPending or not DebugOn() then return end

    areaPending = true
    C_Timer.After(AREA_DELAY, function()
        areaPending = false
        if not DebugOn() then return end

        local ok, err = pcall(self.DebugArea, self, event)
        if not ok then self:ReportError("DebugArea", err) end
    end)
end
