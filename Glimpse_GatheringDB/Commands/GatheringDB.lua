local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local L = DB.L

-- /gli gatheringdb stats | export | import | reset
local function OnCommand(_, args)
    args = strlower(args or "")

    if args == "stats" then
        local nodes, npcs, attempts, spots, kills = DB:GetStats()
        Glimpse:Print(format(L["Gathering nodes: %d"], nodes))
        Glimpse:Print(format(L["Creatures: %d"], npcs))
        Glimpse:Print(format(L["Recorded loot windows: %d"], attempts))
        Glimpse:Print(format(L["Kills: %d"], kills))
        Glimpse:Print(format(L["Locations: %d"], spots))
        local text = DB:ProviderStatistics()
        if text ~= "" then Glimpse:Print(text) end
        if DB.errorCount then
            Glimpse:Print(format(L["Errors while recording: %d (last: %s)"], DB.errorCount, DB.lastError))
        end
    elseif args == "gm2" then
        for _, line in ipairs(DB:DiagnoseGatherMate2()) do Glimpse:Print(line) end
    elseif args == "export" then
        DB:ShowExport()
    elseif args == "import" then
        DB:ShowImport()
    elseif args == "reset" then
        DB:ResetData()
        Glimpse:Print(L["Gathering data deleted."])
    else
        Glimpse:Print(L["Usage: /gli gatheringdb stats | export | import | reset"])
    end
end

Glimpse:RegisterCommand("gatheringdb", L["Shows statistics, exports, imports or resets the gathering data (stats | export | import | reset)"], OnCommand)
