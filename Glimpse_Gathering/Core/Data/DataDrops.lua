local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")
local Locations = Glimpse:GetModule("Locations")

-- Beute lesen: Fassade über Glimpse: Database. Alles ohne local ist öffentliche API (siehe Core/GatheringData.lua).
-- Eine Quelle hat drei Arten: Versuche (ID = Quelle), Menge und Beutefenster je Item ("<art>:<Quelle>", ID = Item).
-- Gelesen wird das Weltwissen aller Charaktere (DB.WORLD_SCOPE). Fundorte: DataSpots.lua, Namen: DataNames.lua.

-- Arten je Quelle: Versuche, Menge, Fenster mit dem Item. fishing liegt im Namespace fishing (Glimpse: Professions).
DB.SECTIONS = {
    node = { "node", "nodeloot", "nodedrop" },
    loot = { "npc", "npcloot", "npcdrop" },
    skinning = { "skinned", "skinloot", "skindrop" },
    fishing = { "looted", "loot", "drop" },
}

-- Gelesene Quellen bis zur nächsten Änderung in Database (OnDataChanged), false = nichts da
local cache = {}

--- Zwischenspeicher leeren (Änderung in Database)
function DB:ClearCaches()
    wipe(cache)
    self.itemIndex = nil
end

-- { attempts, items = { [itemID] = { hits, amount } } } aus Database, nil ohne Daten
local function ReadSection(reader, kinds, id)
    local scope = DB.WORLD_SCOPE
    local attempts = reader:GetCount(kinds[1], id, scope)
    local amounts = reader:GetCounts(kinds[2] .. ":" .. id, scope)
    local hits = reader:GetCounts(kinds[3] .. ":" .. id, scope)
    if attempts <= 0 and not next(hits) then return nil end

    local items = {}
    for itemID, n in pairs(hits) do
        -- zusammengeführte Importe können mehr Funde als Versuche ergeben
        if n > 0 then items[itemID] = { hits = math.min(n, attempts), amount = amounts[itemID] or n } end
    end
    return { attempts = attempts, items = items }
end

local function Section(source, id)
    id = tonumber(id)
    if not id then return nil end

    local key = source .. ":" .. id
    local entry = cache[key]
    if entry == nil then
        local reader = DB:Reader(source == "fishing" and DB.FISHING_NAMESPACE or DB.NAMESPACE)
        entry = reader and ReadSection(reader, DB.SECTIONS[source], id) or false
        cache[key] = entry
    end
    return entry or nil
end

-- Unterklassen für die Kategorie eines Knotens
local TRADEGOODS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local SUBCLASS = Enum and Enum.ItemTradeGoodsSubclass or {}
local HERB = SUBCLASS.Herb or 9
local METAL_STONE = SUBCLASS.MetalStone or 7

--- herb, ore oder other, abgeleitet aus der Beute ({ [itemID] = ... })
function DB:CategoryOf(items)
    local category = "other"
    for itemID in pairs(items or {}) do
        local _, _, _, _, _, classID, subClassID = self.api.GetItemInfoInstant(itemID)
        if classID == TRADEGOODS then
            if subClassID == HERB then return "herb" end
            if subClassID == METAL_STONE then category = "ore" end
        end
    end
    return category
end

--- Knoten { name, category, attempts, items } oder nil, nur lesen
function DB:GetNode(id)
    local node = Section("node", id)
    if node and not node.category then
        node.name = self:GetNodeName(id)
        node.category = self:CategoryOf(node.items)
    end
    return node
end

--- Kreatur { name, level, loot, skinning } oder nil, nur lesen
function DB:GetNPC(id)
    id = tonumber(id)
    if not id then return nil end

    local key = "npc:" .. id
    local npc = cache[key]
    if npc == nil then
        local loot, skinning = Section("loot", id), Section("skinning", id)
        npc = false
        if loot or skinning then
            local name, level = self:GetNPCName(id)
            npc = { name = name, level = level, loot = loot, skinning = skinning }
        end
        cache[key] = npc
    end
    return npc or nil
end

--- Angelzone (Zone wie in Glimpse: Professions, uiMapID oder -instanceID): { attempts, items } oder nil
function DB:GetFishing(zone)
    return Section("fishing", zone)
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

--- Beute eines Knotens. Gibt die Liste und die Zahl der Versuche zurück.
function DB:GetNodeDrops(id)
    return BuildDrops(self:GetNode(id))
end

--- Beute einer Kreatur. kind = "loot" (Standard) oder "skinning".
function DB:GetNPCDrops(id, kind)
    return BuildDrops(Section(kind == "skinning" and "skinning" or "loot", id))
end

--- Fänge einer Angelzone, wie GetNodeDrops: Liste und Zahl der Beutefenster.
function DB:GetFishingDrops(zone)
    return BuildDrops(self:GetFishing(zone))
end

--- Beute aller Knoten mit diesem Namen zusammengerechnet (wie GetNodeDrops), z. B. Varianten eines Vorkommens
function DB:GetNodeDropsByName(name)
    local merged = { attempts = 0, items = {} }

    for _, id in ipairs(self:FindNodeIDs(name)) do
        local node = self:GetNode(id)
        if node then
            merged.attempts = merged.attempts + node.attempts
            for itemID, record in pairs(node.items) do
                local sum = merged.items[itemID]
                if not sum then
                    sum = { hits = 0, amount = 0 }
                    merged.items[itemID] = sum
                end
                sum.hits = sum.hits + record.hits
                sum.amount = sum.amount + record.amount
            end
        end
    end

    return BuildDrops(merged)
end

--- Name einer Zone: Karte oder Instanz (negative Zahl), sonst nil
function DB:GetZoneName(zone)
    zone = tonumber(zone)
    if not zone then return nil end
    if zone < 0 then return self:GetInstanceName(-zone) end
    return Locations:GetMapName(zone)
end

-- IDs der Kreaturen mit Beute oder Kürschnerbeute
local function NPCIDs(reader)
    local ids = reader:GetCounts("npc", DB.WORLD_SCOPE)
    for id, n in pairs(reader:GetCounts("skinned", DB.WORLD_SCOPE)) do ids[id] = (ids[id] or 0) + n end
    return ids
end

-- Item -> Quellen. Wird beim ersten Abfragen gebaut und bei jeder Datenänderung verworfen (ClearCaches).
local function BuildIndex(self)
    local index = {}

    local function AddSource(kind, id, mode, name, level, category, section)
        local attempts = section and section.attempts or 0
        if attempts == 0 then return end

        for itemID, record in pairs(section.items) do
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

    local gathering = self:Reader()
    if gathering then
        for id in pairs(gathering:GetCounts("node", self.WORLD_SCOPE)) do
            local node = self:GetNode(id)
            if node then AddSource("node", id, "gather", node.name, nil, node.category, node) end
        end
        for id in pairs(NPCIDs(gathering)) do
            local npc = self:GetNPC(id)
            if npc then
                AddSource("npc", id, "loot", npc.name, npc.level, nil, npc.loot)
                AddSource("npc", id, "skinning", npc.name, npc.level, nil, npc.skinning)
            end
        end
    end

    -- Angeln: die Quelle ist die Zone, der Name ihr Karten- oder Instanzname
    local fishing = self:Reader(self.FISHING_NAMESPACE)
    if fishing then
        for zone in pairs(fishing:GetCounts("looted", self.WORLD_SCOPE)) do
            AddSource("fishing", zone, "fishing", self:GetZoneName(zone), nil, nil, self:GetFishing(zone))
        end
    end

    return index
end

--- Alle Quellen eines Items, wahrscheinlichste zuerst. Eintrag: { kind ("node" | "npc" | "fishing"),
-- id (bei "fishing" die Zone), mode ("gather" | "loot" | "skinning" | "fishing"), name?, level? (npc),
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

local function CountPlaces(reader)
    return reader and #reader:GetLocations(nil, nil, DB.WORLD_SCOPE) or 0
end

--- Knoten, Kreaturen, Beutefenster (Knoten und Kreaturen), Fundorte, Angelzonen, Angel-Beutefenster
function DB:GetStats()
    local nodes, npcs, attempts = 0, 0, 0
    local gathering = self:Reader()
    if gathering then
        for _, n in pairs(gathering:GetCounts("node", self.WORLD_SCOPE)) do
            nodes, attempts = nodes + 1, attempts + n
        end
        for _ in pairs(NPCIDs(gathering)) do npcs = npcs + 1 end
        attempts = attempts + gathering:GetCount("npc", nil, self.WORLD_SCOPE)
            + gathering:GetCount("skinned", nil, self.WORLD_SCOPE)
    end

    local zones, catches = 0, 0
    local fishing = self:Reader(self.FISHING_NAMESPACE)
    if fishing then
        for _, n in pairs(fishing:GetCounts("looted", self.WORLD_SCOPE)) do
            zones, catches = zones + 1, catches + n
        end
    end

    return nodes, npcs, attempts, CountPlaces(gathering) + CountPlaces(fishing), zones, catches
end
