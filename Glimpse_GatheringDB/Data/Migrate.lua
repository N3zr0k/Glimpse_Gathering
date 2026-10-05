local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Pflege der gespeicherten Daten beim Start: Versionsprüfung, Umstellung älterer Formate,
-- Aufräumen defekter Einträge und eine Obergrenze für die Größe.

-- Obergrenzen. Knoten gibt es nur wenige hundert, Kreaturen können sich über die Zeit anhäufen.
-- Über der Grenze fallen die Einträge mit den wenigsten Versuchen zuerst weg.
DB.MAX_NODES = 2000
DB.MAX_NPCS = 6000

-- Umstellungen: [n] hebt Daten von Version n auf n + 1. Aktuell gibt es nur Version 1.
local migrations = {}

local function IsCount(value)
    return type(value) == "number" and value >= 0 and value == value and value < 1e9
end

-- Abschnitt { attempts, items } prüfen. Gibt false zurück, wenn nichts Brauchbares drin ist.
local function CleanSection(section)
    if type(section) ~= "table" or not IsCount(section.attempts) or type(section.items) ~= "table" then
        return false
    end

    for itemID, record in pairs(section.items) do
        if type(itemID) ~= "number" or type(record) ~= "table"
            or not IsCount(record.hits) or not IsCount(record.amount) or record.hits == 0
            or record.hits > section.attempts then
            section.items[itemID] = nil
        end
    end
    return true
end

local function CleanNode(node)
    return CleanSection(node)
end

local function CleanNPC(npc)
    if type(npc) ~= "table" then return false end

    for _, kind in ipairs({ "loot", "skinning" }) do
        if npc[kind] and not CleanSection(npc[kind]) then npc[kind] = nil end
    end
    return npc.loot ~= nil or npc.skinning ~= nil
end

local function Total(entry, isNode)
    if isNode then return entry.attempts or 0 end
    return (entry.loot and entry.loot.attempts or 0) + (entry.skinning and entry.skinning.attempts or 0)
end

-- Entfernt die Einträge mit den wenigsten Versuchen, sobald mehr als limit vorhanden sind. Es bleiben
-- dann 90 % der Grenze übrig, damit neue Einträge nicht sofort wieder herausfallen.
-- Gibt die Zahl der entfernten Einträge zurück.
local function Prune(entries, limit, isNode)
    local ids = {}
    for id in pairs(entries) do tinsert(ids, id) end
    if #ids <= limit then return 0 end

    table.sort(ids, function(a, b)
        local ta, tb = Total(entries[a], isNode), Total(entries[b], isNode)
        if ta ~= tb then return ta > tb end
        return a < b
    end)

    local keep = math.floor(limit * 0.9)
    for index = keep + 1, #ids do entries[ids[index]] = nil end
    return #ids - keep
end

--- Prüft und pflegt die Daten. Gibt false zurück, wenn sie von einer neueren Version stammen:
-- dann bleiben sie unverändert und es wird nichts aufgezeichnet.
function DB:PrepareData(currentVersion)
    local data = self.data

    if type(data.version) ~= "number" then data.version = 1 end
    if data.version > currentVersion then return false end

    while data.version < currentVersion do
        local step = migrations[data.version]
        if step then step(data) end
        data.version = data.version + 1
    end

    local removed = 0
    for id, node in pairs(data.nodes) do
        if type(id) ~= "number" or not CleanNode(node) then
            data.nodes[id] = nil
            removed = removed + 1
        end
    end
    for id, npc in pairs(data.npcs) do
        if type(id) ~= "number" or not CleanNPC(npc) then
            data.npcs[id] = nil
            removed = removed + 1
        end
    end

    removed = removed + Prune(data.nodes, self.MAX_NODES, true) + Prune(data.npcs, self.MAX_NPCS, false)
    if removed > 0 then self:Debug("Daten bereinigt, entfernte Einträge:", removed) end

    return true
end

-- Prüfung nur alle paar Aufzeichnungen, denn sie geht über alle Einträge
local CHECK_EVERY = 50

--- Hält die Größe während des Spielens im Rahmen. Wird nach jeder Aufzeichnung aufgerufen.
function DB:EnforceLimits()
    self.recordsSinceCheck = (self.recordsSinceCheck or 0) + 1
    if self.recordsSinceCheck < CHECK_EVERY then return end
    self.recordsSinceCheck = 0

    Prune(self.data.nodes, self.MAX_NODES, true)
    Prune(self.data.npcs, self.MAX_NPCS, false)
end
