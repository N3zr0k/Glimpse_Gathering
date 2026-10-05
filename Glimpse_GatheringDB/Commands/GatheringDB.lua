local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local L = DB.L

-- /gli gatheringdb stats | reset
local function OnCommand(_, args)
    args = strlower(args or "")

    if args == "stats" then
        local nodes, npcs, attempts = DB:GetStats()
        Glimpse:Print(format(L["Gathering nodes: %d"], nodes))
        Glimpse:Print(format(L["Creatures: %d"], npcs))
        Glimpse:Print(format(L["Recorded loot windows: %d"], attempts))
        if DB.errorCount then
            Glimpse:Print(format(L["Errors while recording: %d (last: %s)"], DB.errorCount, DB.lastError))
        end
    elseif args == "reset" then
        DB:ResetData()
        Glimpse:Print(L["Gathering data deleted."])
    else
        Glimpse:Print(L["Usage: /gli gatheringdb stats | reset"])
    end
end

Glimpse:RegisterCommand("gatheringdb", L["Shows statistics or resets the gathering data (stats | reset)"], OnCommand)
