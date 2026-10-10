local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Event-Frame für Zauber und Kills, dazu Start/StopCollecting

local collect = DB.collect
local Clean = collect.Clean

local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, zielName, castGUID, spellID)
        local _, target = ...
        collect.lastSent = GetTime()
        target = Clean(target)
        if type(target) == "string" and target ~= "" then
            collect.lastTarget, collect.lastTargetTime = target, GetTime()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, castGUID, spellID)
        local _, _, spellID = ...
        collect.lastSuccess = GetTime()
        if collect.IsSkinningSpell(spellID) then collect.lastSkinning = collect.lastSuccess end
    elseif event == "PARTY_KILL" then
        local killer, victim = ...
        DB:OnPartyKill(killer, victim)
    elseif event == "UNIT_HEALTH" then
        DB:RefreshTargetGUID(false)
        DB:CheckTargetKill()
    elseif event == "PLAYER_TARGET_CHANGED" then
        DB:RefreshTargetGUID(true)
        DB:CheckTargetKill()
    elseif event == "PLAYER_REGEN_ENABLED" then
        DB:CheckTargetKill()
    end
end)

function DB:StartCollecting()
    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnAreaChanged")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnAreaChanged")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

    -- Kills ohne Beutefenster: PARTY_KILL, sonst als Ersatz der Tod des Ziels
    collect.partyKillActive = pcall(frame.RegisterEvent, frame, "PARTY_KILL")
    if collect.partyKillActive then return end

    frame:RegisterUnitEvent("UNIT_HEALTH", "target")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function DB:StopCollecting()
    self:UnregisterEvent("LOOT_OPENED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:UnregisterAllEvents()
end
