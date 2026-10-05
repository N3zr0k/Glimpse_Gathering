local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local L = DB.L

-- Inhalt des Rahmens "Optionen" auf der einheitlichen Erweiterungsseite (siehe Glimpse)
function DB:BuildOptions()
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
        statistics = {
            type = "group", inline = true, order = 3, name = L["Statistics"],
            args = {
                text = {
                    type = "description", order = 1, fontSize = "medium",
                    -- als Funktion, damit die Zahlen beim Anzeigen aktuell sind
                    name = function()
                        local nodes, npcs, attempts, spots = self:GetStats()
                        return table.concat({
                            format(L["Gathering nodes: %d"], nodes),
                            format(L["Creatures: %d"], npcs),
                            format(L["Recorded loot windows: %d"], attempts),
                            format(L["Locations: %d"], spots),
                            self:ProviderStatistics(),
                        }, "\n")
                    end,
                },
            },
        },
        transfer = {
            type = "group", inline = true, order = 4, name = L["Export and import"],
            args = {
                export = {
                    type = "execute", order = 1,
                    name = L["Export"],
                    desc = L["Shows all collected data as text to copy, for a backup or another account."],
                    func = function() self:ShowExport() end,
                },
                import = {
                    type = "execute", order = 2,
                    name = L["Import"],
                    desc = L["Paste exported data to merge it with yours or to replace it."],
                    func = function() self:ShowImport() end,
                },
            },
        },
        reset = {
            type = "execute", order = 5,
            name = L["Reset data"],
            desc = L["Deletes all collected gathering data."],
            confirm = true,
            confirmText = L["Really delete all collected gathering data?"],
            func = function()
                self:ResetData()
                LibStub("AceConfigRegistry-3.0"):NotifyChange(Glimpse.name .. "_" .. ADDON_NAME)
            end,
        },
    }
end
