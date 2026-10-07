local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local L = DB.L

-- /gli gatheringdb stats | export | import | reset | gm2 | skill
local function OnCommand(_, args)
    args = strlower(args or "")

    if args == "stats" then
        local nodes, npcs, attempts, spots, zones, casts = DB:GetStats()
        Glimpse:Print(format(L["Gathering nodes: %d"], nodes))
        Glimpse:Print(format(L["Creatures: %d"], npcs))
        Glimpse:Print(format(L["Recorded loot windows: %d"], attempts))
        Glimpse:Print(format(L["Locations: %d"], spots))
        Glimpse:Print(format(L["Fishing: %d zones, %d casts"], zones, casts))
        local session = DB.fishingSession
        if session and session.casts > 0 then
            Glimpse:Print(format(L["Fishing this session: %d casts, %d loot windows, %d without catch"],
                session.casts, session.windows, session.misses))
        end
        local text = DB:ProviderStatistics()
        if text ~= "" then Glimpse:Print(text) end
        if DB.errorCount then
            Glimpse:Print(format(L["Errors while recording: %d (last: %s)"], DB.errorCount, DB.lastError))
        end
    elseif args == "gm2" then
        for _, line in ipairs(DB:DiagnoseGatherMate2()) do Glimpse:Print(line) end
    elseif args == "skill" then
        -- Rohwerte zum Prüfen im Spiel: Skill, Bonus durch Ausrüstung und der Kreaturentyp des Ziels
        for _, line in ipairs(DB:DescribeSkills()) do Glimpse:Print(line) end
        if UnitGUID("target") then
            local level = UnitLevel("target")
            local required = DB:GetSkinningSkill(level)
            Glimpse:Print(format(L["Target: creature type %s, level %s, skinning skill %s"],
                tostring(DB:GetCreatureTypeID("target")), tostring(level), tostring(required)))
        end
    elseif args == "export" then
        DB:ShowExport()
    elseif args == "import" then
        DB:ShowImport()
    elseif args == "reset" then
        DB:ResetData()
        Glimpse:Print(L["Gathering data deleted."])
    else
        Glimpse:Print(L["Usage: /gli gatheringdb stats | export | import | reset | gm2 | skill"])
    end
end

Glimpse:RegisterCommand("gatheringdb", L["Shows statistics, exports, imports or resets the gathering data, checks GatherMate2 and your gathering skills (stats | export | import | reset | gm2 | skill)"], OnCommand)
