local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")
local Locations = Glimpse:GetModule("Locations")

-- Kills ohne Beutefenster: Leere Leichen öffnen kein Fenster, der Kill muss trotzdem als Versuch
-- zählen. Er zählt erst nach KILL_FALLBACK ohne Fenster und nie, wenn CanLootUnit Beute meldet.

local collect = DB.collect
local Clean, ParseGUID, UnitInfo, Remember = collect.Clean, collect.ParseGUID, collect.UnitInfo, collect.Remember
local CREATURE_REPEAT = collect.CREATURE_REPEAT
local pendingKills = collect.pendingKills

-- CanLootUnit-Prüfung nach KILL_CHECK_DELAY, Zählung nach KILL_FALLBACK
local KILL_CHECK_DELAY = 1.5
local KILL_FALLBACK = 120

local function HasLoot(guid)
    if type(CanLootUnit) ~= "function" then return nil end
    local ok, hasLoot = pcall(CanLootUnit, guid)
    if ok then return Clean(hasLoot) end
end

function DB:CommitKill(guid, position)
    if not pendingKills[guid] or not self.db.profile.recording then return end
    pendingKills[guid] = nil

    local kind, id = ParseGUID(guid)
    if kind ~= "Creature" or not id then return end

    local now = GetTime()
    if not Remember(guid .. "|loot", CREATURE_REPEAT, now) then return end

    collect.killCounted[guid] = true
    self:RecordNPC(id, "loot", UnitInfo(guid), {}, position)
    self.debug:Log("kill", "Gespeichert: Kreatur %s ohne Beutefenster (leere Leiche)", tostring(id))
end

function DB:OnKill(guid)
    if not self.db.profile.recording then return end
    if type(guid) ~= "string" or ParseGUID(guid) ~= "Creature" then return end

    self.debug:Log("kill", "Kill erkannt: %s", tostring(select(2, ParseGUID(guid))))

    -- Schon gezählt (Fenster oder früherer Kill)
    local now = GetTime()
    local counted = collect.counted[guid .. "|loot"]
    if pendingKills[guid] or (counted and (now - counted) <= CREATURE_REPEAT) then return end
    pendingKills[guid] = now

    local position
    if self.db.profile.trackLocations then
        local found, result = pcall(Locations.GetPlayerArea, Locations)
        if found then position = result end
    end

    C_Timer.After(KILL_CHECK_DELAY, function()
        if not pendingKills[guid] then return end -- inzwischen gelootet

        -- Leiche hat Beute: das Fenster zählt, nicht der Kill
        if HasLoot(guid) == true then
            pendingKills[guid] = nil
            return
        end

        -- Zählt nach KILL_FALLBACK, falls bis dahin kein Fenster kam
        C_Timer.After(KILL_FALLBACK - KILL_CHECK_DELAY, function() self:CommitKill(guid, position) end)
    end)
end

-- PARTY_KILL meldet alle Kills (auch Gruppe/Pet, ohne Ziel). Gibt es das Event, entfällt
-- CheckTargetKill (collect.partyKillActive, gesetzt in LootEvents.lua).

--- Zählt nur Kills von Spieler oder Pet
function DB:OnPartyKill(killer, victim)
    killer, victim = Clean(killer), Clean(victim)
    if type(killer) ~= "string" or type(victim) ~= "string" then return end

    local mine = killer == Clean(UnitGUID("player")) or killer == Clean(UnitGUID("pet"))
    if not mine then
        self.debug:Log("kill", "Kill-Erkennung: PARTY_KILL von jemand anderem, nicht gezählt")
        return
    end
    self.debug:Log("kill", "Kill-Erkennung: PARTY_KILL %s", victim)
    self:OnKill(victim)
end

-- Ersatz ohne PARTY_KILL: Tod des Ziels gilt als eigener Kill, außer bei fremdem Tap. Kills ohne
-- Ziel (AoE, Pet) fehlen dann. COMBAT_LOG_EVENT_UNFILTERED ist für Addons gesperrt.
-- Geprüft bei UNIT_HEALTH, Zielwechsel und Kampfende. Im Kampf kann die GUID geschützt sein, dann
-- gilt die zuletzt lesbare.
local targetGUID -- GUID des aktuellen Ziels, solange sie lesbar war

function DB:RefreshTargetGUID(reset)
    local guid = Clean(UnitGUID("target"))
    if type(guid) == "string" then
        targetGUID = guid
    elseif reset then
        targetGUID = nil -- anderes Ziel, dessen GUID wir nicht kennen
    end
end

function DB:CheckTargetKill()
    if collect.partyKillActive then return end
    local ok, dead = pcall(UnitIsDead, "target")
    if not ok then return end
    if dead ~= nil and Glimpse:IsSecret(dead) then
        self.debug:Log("kill", "Kill-Erkennung: UnitIsDead ist geschützt")
        return
    end
    if dead ~= true then return end

    local guid = Clean(UnitGUID("target"))
    if type(guid) ~= "string" then guid = targetGUID end
    if type(guid) ~= "string" then
        self.debug:Log("kill", "Kill-Erkennung: Ziel ist tot, aber die GUID ist unbekannt")
        return
    end

    if UnitIsTapDenied then
        local tapOK, denied = pcall(UnitIsTapDenied, "target")
        if tapOK and Clean(denied) == true then
            self.debug:Log("kill", "Kill-Erkennung: Ziel gehört einem anderen Spieler (Tap)")
            return
        end
    end

    self:OnKill(guid)
end
