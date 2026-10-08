local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Event-Frame für Zauber, Angelmeldungen und Kills, dazu Start/StopCollecting

local collect = DB.collect
local Clean = collect.Clean

local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, zielName, castGUID, spellID)
        local _, target, _, spellID = ...
        collect.lastSent = GetTime()
        DB:OnFishingStart(Clean(spellID))
        target = Clean(target)
        if type(target) == "string" and target ~= "" then
            collect.lastTarget, collect.lastTargetTime = target, GetTime()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- (unit, castGUID, spellID)
        local _, _, spellID = ...
        DB:OnFishingStop(Clean(spellID))
    elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
        DB:OnFishingMessage(...)
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
    else
        collect.lastSuccess = GetTime()
    end
end)

function DB:StartCollecting()
    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnAreaChanged")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnAreaChanged")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    frame:RegisterEvent("UI_ERROR_MESSAGE")
    frame:RegisterEvent("UI_INFO_MESSAGE")

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
