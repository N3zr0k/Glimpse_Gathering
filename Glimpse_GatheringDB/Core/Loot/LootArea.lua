local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Debug (Kategorie area): Ortserkennung bei Gebietswechsel ausgeben. Verzögert, weil Instanzdaten direkt nach
-- dem Event noch falsch sein können; mehrere Events werden zusammengefasst.

local Clean = DB.collect.Clean

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

--- Zeilen zur Ortserkennung (Debug und Probe gathering area)
function DB:AreaLines(event)
    return {
        format("Gebiet (%s): %s", tostring(event or "jetzt"),
            self:DescribeArea(Locations:GetPlayerArea()) or "nicht bestimmbar (keine Karte, Koordinaten oder Instanz)"),
        "IsInInstance: " .. RawValues(Locations.api.IsInInstance),
        "GetInstanceInfo: " .. RawValues(Locations.api.GetInstanceInfo),
        "Aufzeichnung der Fundorte: " .. (self.db.profile.trackLocations and "an" or "aus"),
    }
end

function DB:OnAreaChanged(event)
    if areaPending or not self.debug:IsOn("area") then return end

    areaPending = true
    C_Timer.After(AREA_DELAY, function()
        areaPending = false
        if not self.debug:IsOn("area") then return end

        local ok, lines = pcall(self.AreaLines, self, event)
        if not ok then return self:ReportError("AreaLines", lines) end
        for _, line in ipairs(lines) do self.debug:Log("area", "%s", line) end
    end)
end
