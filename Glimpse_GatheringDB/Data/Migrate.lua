local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Pflege der gespeicherten Daten: Versionsprüfung, Umstellung älterer Formate, Aufräumen defekter
-- Einträge und eine Obergrenze für die Größe. Dieselben Schritte gelten für importierte Daten
-- (Data/Transfer.lua): UpgradeData und SanitizeData arbeiten auf einer beliebigen Datentabelle.

-- Obergrenzen. Knoten gibt es nur wenige hundert, Kreaturen können sich über die Zeit anhäufen.
-- Über der Grenze fallen die Einträge mit den wenigsten Versuchen zuerst weg.
DB.MAX_NODES = 2000
DB.MAX_NPCS = 6000

local function BackfillKills(data)
    for _, npc in pairs(data.npcs or {}) do
        local looted = type(npc) == "table" and type(npc.loot) == "table" and tonumber(npc.loot.attempts) or 0
        if looted > 0 then npc.kills = math.max(tonumber(npc.kills) or 0, looted) end
    end
end

-- Umstellungen: [n] hebt Daten von Version n auf n + 1 (in der Tabelle selbst, ohne Rückgabe).
-- Neue Version: DATA_VERSION in Core/GatheringDB.lua erhöhen und hier den Schritt ergänzen.
local migrations = {
    -- 1 -> 2: Fundorte (spots) und Liste der importierten Exporte kommen dazu. Beides ist optional,
    -- alte Einträge bleiben, wie sie sind.
    [1] = function(data)
        data.imports = data.imports or {}
    end,
    -- 2 -> 3: Fundorte in Instanzen ({ inst, n }) und die Namen der Instanzen (instances) kommen dazu.
    [2] = function(data)
        data.instances = data.instances or {}
    end,
    -- 3 -> 4 und 4 -> 5: Kreaturen haben einen eigenen Zähler für Kills (kills, optional). Jede Beute einer
    -- Kreatur war ein Kill, deshalb beginnt der Zähler bei den Versuchen der Normalbeute (nie darunter).
    [3] = function(data) BackfillKills(data) end,
    [4] = function(data) BackfillKills(data) end,
}

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

-- Fundorte { map, x, y, n } oder { inst, n } prüfen: x und y in 1/10000 der Karte, n = Zahl der Beutefenster dort.
-- Die Liste wird auf limit Einträge gekürzt (die mit den wenigsten Funden fallen weg).
local function CleanSpots(entry, limit)
    if entry.spots == nil then return end
    if type(entry.spots) ~= "table" then
        entry.spots = nil
        return
    end

    local clean = {}
    for _, spot in ipairs(entry.spots) do
        if type(spot) == "table" and IsCount(spot.n) and spot.n >= 1 then
            if spot.inst ~= nil then
                -- Instanz: nur die Nummer
                if type(spot.inst) == "number" and spot.inst >= 1 and spot.inst < 1e6 and spot.inst == math.floor(spot.inst) then
                    tinsert(clean, { inst = spot.inst, n = math.floor(spot.n) })
                end
            elseif type(spot.map) == "number" and spot.map >= 1 and spot.map == math.floor(spot.map)
                and spot.map < 1e6 and type(spot.x) == "number" and spot.x > 0 and spot.x <= 10000
                and type(spot.y) == "number" and spot.y > 0 and spot.y <= 10000 then
                tinsert(clean, {
                    map = spot.map, n = math.floor(spot.n),
                    x = math.floor(spot.x + 0.5), y = math.floor(spot.y + 0.5),
                })
            end
        end
    end

    table.sort(clean, function(a, b) return a.n > b.n end)
    while #clean > limit do tremove(clean) end
    entry.spots = #clean > 0 and clean or nil
end

local function CleanNode(node)
    if not CleanSection(node) then return false end
    CleanSpots(node, DB.MAX_SPOTS_NODE)
    return true
end

local function CleanNPC(npc)
    if type(npc) ~= "table" then return false end

    for _, kind in ipairs({ "loot", "skinning" }) do
        if npc[kind] and not CleanSection(npc[kind]) then npc[kind] = nil end
    end
    CleanSpots(npc, DB.MAX_SPOTS_NPC)

    -- Kills: ganze Zahl, sonst weg
    if npc.kills ~= nil then
        npc.kills = IsCount(npc.kills) and math.floor(npc.kills) or nil
        if npc.kills == 0 then npc.kills = nil end
    end
    return npc.loot ~= nil or npc.skinning ~= nil or npc.kills ~= nil
end

-- Namen der Instanzen prüfen: Nummer als Schlüssel, Text als Wert
local MAX_INSTANCE_NAME = 100

local function CleanInstances(data)
    if type(data.instances) ~= "table" then data.instances = {} end

    for id, name in pairs(data.instances) do
        if type(id) ~= "number" or id < 1 or id >= 1e6 or id ~= math.floor(id)
            or type(name) ~= "string" or name == "" or #name > MAX_INSTANCE_NAME then
            data.instances[id] = nil
        end
    end
end

-- Namen von Instanzen, zu denen kein Fundort mehr gehört, fallen weg
local function DropUnusedInstances(data)
    local used = {}
    for _, group in ipairs({ data.nodes, data.npcs }) do
        for _, entry in pairs(group) do
            for _, spot in ipairs(entry.spots or {}) do
                if spot.inst then used[spot.inst] = true end
            end
        end
    end
    for id in pairs(data.instances or {}) do
        if not used[id] then data.instances[id] = nil end
    end
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

--- Hebt eine Datentabelle auf die aktuelle Version. Gibt false zurück, wenn sie von einer neueren
-- Version stammt (oder die Versionsnummer unbrauchbar ist): dann bleibt sie unverändert.
function DB:UpgradeData(data, currentVersion)
    if type(data.version) ~= "number" then data.version = 1 end
    if data.version < 1 or data.version ~= math.floor(data.version) then return false end
    if data.version > currentVersion then return false end

    while data.version < currentVersion do
        local step = migrations[data.version]
        if step then step(data) end
        data.version = data.version + 1
    end
    return true
end

--- Entfernt defekte Einträge und stellt sicher, dass nodes, npcs, imports und instances Tabellen sind.
-- Gibt die Zahl der entfernten Einträge zurück.
function DB:SanitizeData(data)
    if type(data.nodes) ~= "table" then data.nodes = {} end
    if type(data.npcs) ~= "table" then data.npcs = {} end
    if type(data.imports) ~= "table" then data.imports = {} end
    CleanInstances(data)

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
    return removed
end

--- Hält die Zahl der Einträge unter den Obergrenzen. Gibt die Zahl der entfernten Einträge zurück.
function DB:PruneData()
    local removed = Prune(self.data.nodes, self.MAX_NODES, true) + Prune(self.data.npcs, self.MAX_NPCS, false)
    DropUnusedInstances(self.data)
    return removed
end

--- Prüft und pflegt die gespeicherten Daten beim Start. Gibt false zurück, wenn sie von einer neueren
-- Version stammen: dann bleiben sie unverändert und es wird nichts aufgezeichnet.
function DB:PrepareData(currentVersion)
    if not self:UpgradeData(self.data, currentVersion) then return false end

    local removed = self:SanitizeData(self.data) + self:PruneData()
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

    self:PruneData()
end
