local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")
local Locations = Glimpse:GetModule("Locations")
local L = DB.L

-- Probes für Tester (/gli probe gathering ...): dieselben Rohdaten wie der Debug-Tooltip, dazu Statistik,
-- GatherMate2, Skills, Ortserkennung und die Namensablage.

local function Text(lines)
    local result = {}
    for _, line in ipairs(lines) do
        if type(line) == "table" then
            result[#result + 1] = line[2] and (line[1] .. "  " .. line[2]) or line[1]
        else
            result[#result + 1] = line
        end
    end
    return result
end

local function StatsLines(self)
    local nodes, npcs, attempts, spots, zones, catches = self:GetStats()
    local lines = {
        format(L["Gathering nodes: %d"], nodes),
        format(L["Creatures: %d"], npcs),
        format(L["Recorded loot windows: %d"], attempts),
        format(L["Locations: %d"], spots),
        format(L["Fishing: %d zones, %d loot windows"], zones, catches),
        "Database: " .. (self.ns and "gathering registered" or ("not available (" .. tostring(self.registerError) .. ")")),
    }
    local providers = self:ProviderStatistics()
    if providers ~= "" then lines[#lines + 1] = providers end
    if self.errorCount then
        lines[#lines + 1] = format(L["Errors while recording: %d (last: %s)"], self.errorCount, self.lastError)
    end
    return lines
end

local function SkillLines(self)
    local lines = self:DescribeSkills()
    if UnitGUID("target") then
        local level = UnitLevel("target")
        lines[#lines + 1] = format(L["Target: creature type %s, level %s, skinning skill %s"],
            tostring(self:GetCreatureTypeID("target")), tostring(level), tostring(self:GetSkinningSkill(level)))
    end
    return lines
end

local function NamesLines(self)
    local names = self.names or {}
    local function Count(t)
        local n = 0
        for _ in pairs(t or {}) do n = n + 1 end
        return n
    end
    return {
        format("Names: %d nodes, %d creatures, %d instances", Count(names.nodes), Count(names.npcs), Count(names.instances)),
    }
end

-- Woher die Daten kommen, für /gli probe db sources (Core)
local function SourceLines(self)
    local fishing = _G.GlimpseDB and _G.GlimpseDB:Get("fishing")
    local lines = {
        "records: namespace gathering (" .. (self.ns and "writer" or ("not available: " .. tostring(self.registerError))) .. ")",
        "fishing: read from namespace fishing (" .. (fishing and "available" or "missing, Glimpse: Professions records it") .. ")",
    }
    for _, line in ipairs(NamesLines(self)) do lines[#lines + 1] = "names in GlimpseGatheringNames: " .. line end
    for _, info in ipairs(self:GetProviderInfo()) do
        local state = not info.available and "not installed"
            or (info.enabled and format("%d locations, read live, not saved", info.points) or "switched off")
        lines[#lines + 1] = format("locations from %s: %s", info.name, state)
    end
    return lines
end

-- Angelzone: Argument oder Zone des Spielers
local function FishingLines(self, args)
    local zone = tonumber(args)
    if not zone then
        local area = Locations:GetPlayerArea()
        zone = area and (area.map or (area.instance and -area.instance))
    end
    if not zone then return { L["No zone known"] } end

    local drops, windows = self:GetFishingDrops(zone)
    local lines = { format("%s: %s (%d)", L["Zone"], tostring(self:GetZoneName(zone) or "?"), zone),
        format("Loot windows: %d", windows) }
    for _, drop in ipairs(drops) do
        lines[#lines + 1] = format("  %d: %d hits, %d total", drop.itemID, drop.hits, drop.amount)
    end
    return lines
end

local function WithID(func)
    return function(args)
        local id = tonumber(strmatch(args or "", "%d+"))
        if not id then return { "ID expected" } end
        return Text(func(id))
    end
end

function DB:RegisterProbes()
    local group = "gathering"
    Glimpse:RegisterProbe(group, "stats", function() return StatsLines(self) end, "Statistics, Database and errors")
    Glimpse:RegisterProbe(group, "gm2", function() return self:DiagnoseGatherMate2() end, "What GatherMate2 provides")
    Glimpse:RegisterProbe(group, "skill", function() return SkillLines(self) end, "Gathering skills and target")
    Glimpse:RegisterProbe(group, "area", function() return self:AreaLines() end, "Detected position")
    Glimpse:RegisterProbe(group, "names", function() return NamesLines(self) end, "Stored names")
    Glimpse:RegisterProbe(group, "fishing", function(args) return FishingLines(self, args) end,
        "Fishing loot of a zone (default: current zone)")
    Glimpse:RegisterProbe(group, "node", WithID(function(id) return self:DebugSourceLines("node", id) end),
        "Data of a node: <object ID>")
    Glimpse:RegisterProbe(group, "npc", WithID(function(id) return self:DebugSourceLines("npc", id) end),
        "Data of a creature: <NPC ID>")
    Glimpse:RegisterProbe(group, "item", WithID(function(id) return self:DebugItemLines(id) end),
        "Sources of an item: <item ID>")
    if Glimpse.RegisterDataSource then
        Glimpse:RegisterDataSource("Glimpse_Gathering", function() return SourceLines(self) end)
    end
end
