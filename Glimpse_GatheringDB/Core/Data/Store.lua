local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Beute speichern und abfragen. Alles ohne local ist öffentliche API (siehe Core/GatheringDB.lua).
-- Fundorte: Spots.lua, Knoten über den Namen: Names.lua.

-- Ein Beutefenster in { attempts, items } zählen. items = { [itemID] = Menge } dieses Fensters.
-- hits = Versuche mit dem Item (Basis der Chance), amount = Gesamtmenge.
local function AddItems(section, items)
    section.items = section.items or {}

    for itemID, amount in pairs(items) do
        local record = section.items[itemID]
        if not record then
            record = { hits = 0, amount = 0 }
            section.items[itemID] = record
        end
        record.hits = record.hits + 1
        record.amount = record.amount + amount
    end
end

local function CountAttempt(section, items)
    section.attempts = (section.attempts or 0) + 1
    AddItems(section, items)
end

--- Beutefenster eines Knotens zählen. info = { name, category }, pos siehe AddSpot (beides optional).
function DB:RecordNode(id, info, items, pos)
    id = tonumber(id)
    if not id then return end

    local node = self.data.nodes[id]
    if not node then
        node = {}
        self.data.nodes[id] = node
    end

    -- Name und Kategorie nur ergänzen, nie überschreiben
    if info then
        node.name = node.name or info.name
        if info.category and (not node.category or node.category == "other") then
            node.category = info.category
        end
    end

    CountAttempt(node, items)
    if pos then self:AddSpot(node, "node", pos) end
    self:EnforceLimits()
    self.itemIndex, self.nameIndex = nil, nil -- Indizes sind veraltet
    self:SendMessage(self.MESSAGE_UPDATED, "node", id)
end

--- Beutefenster einer Kreatur zählen. kind = "loot" oder "skinning", info = { name, level }, pos optional.
function DB:RecordNPC(id, kind, info, items, pos)
    id = tonumber(id)
    if not id then return end

    local npc = self.data.npcs[id]
    if not npc then
        npc = {}
        self.data.npcs[id] = npc
    end

    if info then
        npc.name = npc.name or info.name
        npc.level = npc.level or info.level
    end

    npc[kind] = npc[kind] or {}
    CountAttempt(npc[kind], items)
    if pos then self:AddSpot(npc, "npc", pos) end
    self:EnforceLimits()
    self.itemIndex = nil
    self:SendMessage(self.MESSAGE_UPDATED, "npc", id)
end

-- { attempts, items } -> sortierte Liste { itemID, hits, amount, chance (0..1), average (Menge je Fund) }
local function BuildDrops(section)
    local list = {}
    local attempts = section and section.attempts or 0
    if attempts == 0 then return list, 0 end

    for itemID, record in pairs(section.items or {}) do
        tinsert(list, {
            itemID = itemID,
            hits = record.hits,
            attempts = attempts,
            amount = record.amount,
            chance = record.hits / attempts,
            average = record.amount / record.hits,
        })
    end

    table.sort(list, function(a, b)
        if a.hits ~= b.hits then return a.hits > b.hits end
        return a.itemID < b.itemID
    end)
    return list, attempts
end

--- Wurf in Zone map (uiMapID) zählen. items = { [itemID] = Menge }, leer bei Wurf ohne Fang. pos optional.
function DB:RecordFishing(map, items, pos)
    map = tonumber(map)
    if not map or map < 1 then return end

    self.data.fishing = self.data.fishing or {}
    local zone = self.data.fishing[map]
    if not zone then
        zone = {}
        self.data.fishing[map] = zone
    end

    CountAttempt(zone, items)
    if pos then self:AddSpot(zone, "fishing", pos) end
    self:EnforceLimits()
    self.itemIndex = nil
    self:SendMessage(self.MESSAGE_UPDATED, "fishing", map)
end

--- Beute zu einem schon gezählten Versuch (Kill ohne Fenster, später gelootet). Kein neuer Versuch.
function DB:AddNPCItems(id, kind, items)
    id = tonumber(id)
    local section = id and self.data.npcs[id] and self.data.npcs[id][kind]
    if not section then return end

    AddItems(section, items)
    self.itemIndex = nil
    self:SendMessage(self.MESSAGE_UPDATED, "npc", id)
end

function DB:GetNode(id)
    return self.data.nodes[tonumber(id)]
end

--- Fang zu einem als leer gezählten Wurf (Fenster kam spät). Kein neuer Versuch.
function DB:AddFishingItems(map, items)
    local zone = self:GetFishing(map)
    if not zone then return end

    AddItems(zone, items)
    self.itemIndex = nil
    self:SendMessage(self.MESSAGE_UPDATED, "fishing", tonumber(map))
end

--- Eintrag einer Angelzone (map = uiMapID) oder nil, nur lesen
function DB:GetFishing(map)
    return self.data.fishing and self.data.fishing[tonumber(map)]
end

--- Fänge einer Angelzone, wie GetNodeDrops: Liste und Zahl der Würfe.
function DB:GetFishingDrops(map)
    return BuildDrops(self:GetFishing(map))
end

--- Eintrag einer Kreatur oder nil, nur lesen
function DB:GetNPC(id)
    return self.data.npcs[tonumber(id)]
end

--- Beute eines Knotens. Gibt die Liste und die Zahl der Versuche zurück.
function DB:GetNodeDrops(id)
    return BuildDrops(self:GetNode(id))
end

--- Beute einer Kreatur. kind = "loot" (Standard) oder "skinning".
function DB:GetNPCDrops(id, kind)
    local npc = self:GetNPC(id)
    return BuildDrops(npc and npc[kind or "loot"])
end

--- Knoten, Kreaturen, Beutefenster, Fundorte, Angelzonen, Würfe (Würfe zählen nicht als Beutefenster)
function DB:GetStats()
    local nodes, npcs, attempts, spots = 0, 0, 0, 0
    local zones, casts = 0, 0
    for _, zone in pairs(self.data.fishing or {}) do
        zones = zones + 1
        casts = casts + (zone.attempts or 0)
        spots = spots + (zone.spots and #zone.spots or 0)
    end

    for _, node in pairs(self.data.nodes) do
        nodes = nodes + 1
        attempts = attempts + (node.attempts or 0)
        spots = spots + (node.spots and #node.spots or 0)
    end
    for _, npc in pairs(self.data.npcs) do
        npcs = npcs + 1
        attempts = attempts + (npc.loot and npc.loot.attempts or 0) + (npc.skinning and npc.skinning.attempts or 0)
        spots = spots + (npc.spots and #npc.spots or 0)
    end

    return nodes, npcs, attempts, spots, zones, casts
end

--- Löscht alle Daten. Die Tabellen bleiben, damit gemerkte Verweise gültig sind.
function DB:ResetData()
    wipe(self.data.nodes)
    wipe(self.data.npcs)
    if self.data.fishing then wipe(self.data.fishing) end
    if self.data.imports then wipe(self.data.imports) end
    if self.data.instances then wipe(self.data.instances) end
    self.itemIndex, self.nameIndex = nil, nil
    self:SendMessage(self.MESSAGE_UPDATED, "reset")
end

-- Item -> Quellen. Wird beim ersten Abfragen gebaut und bei jeder Datenänderung verworfen (itemIndex = nil).
local function BuildIndex(self)
    local index = {}

    -- section ist { attempts, items }, bei Knoten der Knoten selbst
    local function AddSource(kind, id, mode, name, level, category, section)
        local attempts = section and section.attempts or 0
        if attempts == 0 then return end

        for itemID, record in pairs(section.items or {}) do
            local list = index[itemID]
            if not list then
                list = {}
                index[itemID] = list
            end
            tinsert(list, {
                kind = kind, id = id, mode = mode, name = name, level = level, category = category,
                attempts = attempts, hits = record.hits, amount = record.amount,
                chance = record.hits / attempts, average = record.amount / record.hits,
            })
        end
    end

    for id, node in pairs(self.data.nodes) do AddSource("node", id, "gather", node.name, nil, node.category, node) end
    for id, npc in pairs(self.data.npcs) do
        AddSource("npc", id, "loot", npc.name, npc.level, nil, npc.loot)
        AddSource("npc", id, "skinning", npc.name, npc.level, nil, npc.skinning)
    end
    -- Angeln: die Quelle ist die Zone, der Name ihr Kartenname
    for map, zone in pairs(self.data.fishing or {}) do AddSource("fishing", map, "fishing", Locations:GetMapName(map), nil, nil, zone) end

    return index
end

--- Alle Quellen eines Items, wahrscheinlichste zuerst. Eintrag: { kind ("node" | "npc" | "fishing"),
-- id (bei "fishing" die Karte), mode ("gather" | "loot" | "skinning" | "fishing"), name?, level? (npc),
-- category? (node: "herb", "ore", "other"), attempts, hits, amount, chance (0..1), average }.
-- minAttempts (Standard 1) blendet Quellen mit zu wenig Versuchen aus.
function DB:GetItemSources(itemID, minAttempts)
    itemID = tonumber(itemID)
    if not itemID then return {} end

    self.itemIndex = self.itemIndex or BuildIndex(self)

    local result = {}
    for _, source in ipairs(self.itemIndex[itemID] or {}) do
        if source.attempts >= (minAttempts or 1) then tinsert(result, source) end
    end

    table.sort(result, function(a, b)
        if a.chance ~= b.chance then return a.chance > b.chance end
        if a.attempts ~= b.attempts then return a.attempts > b.attempts end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.id < b.id
    end)
    return result
end

--- Beute aller Knoten mit diesem Namen zusammengerechnet (wie GetNodeDrops), z. B. Varianten eines Vorkommens
function DB:GetNodeDropsByName(name)
    local merged = { attempts = 0, items = {} }

    for _, id in ipairs(self:FindNodeIDs(name)) do
        local node = self.data.nodes[id]
        merged.attempts = merged.attempts + (node.attempts or 0)

        for itemID, record in pairs(node.items or {}) do
            local sum = merged.items[itemID]
            if not sum then
                sum = { hits = 0, amount = 0 }
                merged.items[itemID] = sum
            end
            sum.hits = sum.hits + record.hits
            sum.amount = sum.amount + record.amount
        end
    end

    return BuildDrops(merged)
end
