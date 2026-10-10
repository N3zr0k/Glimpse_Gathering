local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")
local L = DB.L

-- Je Anbieter fremder Fundorte ein Schalter, nur aktiv mit geladenem Addon und eingeschaltetem
-- Hauptschalter.
function DB:BuildSourceOptions()
    local args = {
        hint = {
            type = "description", order = 0,
            name = L["Choose which addons the locations are read from."],
        },
    }

    for index, info in ipairs(self:GetProviders()) do
        local name = info.name
        args[name] = {
            type = "toggle", order = index, width = "full",
            name = name,
            desc = function()
                if self:GetProviderAvailable(name) then
                    return format(L["Reads the node locations saved by %s. They are not copied or exported."], name)
                end
                return format(L["%s was not found or is not loaded."], name)
            end,
            disabled = function() return not self.db.profile.useExternalSpots or not self:GetProviderAvailable(name) end,
            get = function() return self:IsProviderEnabled(name) end,
            set = function(_, value) self.db.profile.externalSources[name] = value end,
        }
    end

    return {
        type = "group", inline = true, order = 2.6, name = L["Sources for locations"],
        args = args,
    }
end

-- Tab "Erfassen" der Optionsseite (Core/Options.lua)
function DB:BuildRecordingOptions()
    return {
        recording = {
            type = "toggle", order = 1, width = "full",
            name = L["Record gathering data"],
            desc = L["Collects gathering nodes and creature loot while you play."],
            get = function() return self.db.profile.recording end,
            set = function(_, value) self.db.profile.recording = value end,
        },
        trackLocations = {
            type = "toggle", order = 2, width = "full",
            name = L["Record locations"],
            desc = L["Also stores the zone and the coordinates where you looted. Needed to find where something drops."],
            get = function() return self.db.profile.trackLocations end,
            set = function(_, value) self.db.profile.trackLocations = value end,
        },
        useExternalSpots = {
            type = "toggle", order = 2.5, width = "full",
            name = L["Use locations from other addons"],
            desc = function() return self:ExternalSpotsDescription() end,
            disabled = function() return not self:HasAvailableProvider() end,
            get = function() return self.db.profile.useExternalSpots end,
            set = function(_, value) self.db.profile.useExternalSpots = value end,
        },
        externalSources = self:BuildSourceOptions(),
        statistics = {
            type = "group", inline = true, order = 3, name = L["Statistics"],
            args = {
                text = {
                    type = "description", order = 1, fontSize = "medium",
                    -- Funktion, damit die Zahlen beim Öffnen aktuell sind
                    name = function()
                        local nodes, npcs, attempts, spots, zones, catches = self:GetStats()
                        return table.concat({
                            format(L["Gathering nodes: %d"], nodes),
                            format(L["Creatures: %d"], npcs),
                            format(L["Recorded loot windows: %d"], attempts),
                            format(L["Locations: %d"], spots),
                            format(L["Fishing: %d zones, %d loot windows"], zones, catches),
                            self:ProviderStatistics(),
                        }, "\n")
                    end,
                },
            },
        },
        data = {
            type = "description", order = 4,
            name = L["The data is stored in Glimpse: Database. Export, import and reset are in the Glimpse options, tab Data."],
        },
    }
end
