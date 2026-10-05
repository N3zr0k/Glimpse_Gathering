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
        statistics = {
            type = "group", inline = true, order = 2, name = L["Statistics"],
            args = {
                text = {
                    type = "description", order = 1, fontSize = "medium",
                    -- als Funktion, damit die Zahlen beim Anzeigen aktuell sind
                    name = function()
                        local nodes, npcs, attempts = self:GetStats()
                        return table.concat({
                            format(L["Gathering nodes: %d"], nodes),
                            format(L["Creatures: %d"], npcs),
                            format(L["Recorded loot windows: %d"], attempts),
                        }, "\n")
                    end,
                },
            },
        },
        reset = {
            type = "execute", order = 3,
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
