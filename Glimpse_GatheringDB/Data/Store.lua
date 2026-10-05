local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Speichern und Abfragen. Alles, was hier ohne lokales "local" steht, ist die öffentliche
-- Schnittstelle (siehe Kopf von Core/GatheringDB.lua).

-- ---------------------------------------------------------------------------
-- Fundorte
-- ---------------------------------------------------------------------------

-- Zu jeder Quelle merken wir, wo der Spieler beim Looten stand: Karte (uiMapID) und Position.
-- Koordinaten werden als ganze Zahlen von 1 bis 10000 gespeichert (1/10000 der Kartenbreite bzw.
-- -höhe), das hält die Datei klein. Fundorte, die näher als SPOT_RADIUS beieinander liegen, werden
-- zu einem zusammengefasst (gewichteter Mittelpunkt, n zählt die Beutefenster dort). Je Quelle gibt
-- es höchstens MAX_SPOTS_*, darüber fällt der Ort mit den wenigsten Funden weg.
DB.SPOT_RADIUS = 100 -- 1 % der Karte
DB.MAX_SPOTS_NODE = 40
DB.MAX_SPOTS_NPC = 12

local SPOT_MAX = 10000
local COUNT_MAX = 1e9 - 1

--- Führt einen Ort in eine Liste von Fundorten ein. x und y in 1/10000, n = Zahl der Funde.
function DB:MergeSpot(list, map, x, y, n, limit)
    local radius2 = self.SPOT_RADIUS * self.SPOT_RADIUS
    local best, bestDistance

    for _, spot in ipairs(list) do
        if spot.map == map then
            local dx, dy = spot.x - x, spot.y - y
            local distance = dx * dx + dy * dy
            if distance <= radius2 and (not bestDistance or distance < bestDistance) then
                best, bestDistance = spot, distance
            end
        end
    end

    if best then
        local total = best.n + n
        best.x = math.floor((best.x * best.n + x * n) / total + 0.5)
        best.y = math.floor((best.y * best.n + y * n) / total + 0.5)
        best.n = math.min(total, COUNT_MAX)
        return
    end

    tinsert(list, { map = map, x = x, y = y, n = math.min(n, COUNT_MAX) })

    if #list > limit then
        -- den schwächsten Ort entfernen, bei Gleichstand den ältesten
        local weakest = 1
        for index = 2, #list do
            if list[index].n < list[weakest].n then weakest = index end
        end
        tremove(list, weakest)
    end
end

--- Merkt einen Fundort für einen Knoten- oder Kreatureneintrag. pos = { map, x, y } mit x und y von
-- 0 bis 1 (wie C_Map.GetPlayerMapPosition). Ungültige Orte werden ignoriert.
function DB:AddSpot(entry, kind, pos)
    if type(pos) ~= "table" or type(pos.map) ~= "number" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then
        return
    end

    local x = math.floor(pos.x * SPOT_MAX + 0.5)
    local y = math.floor(pos.y * SPOT_MAX + 0.5)
    if pos.map < 1 or x < 1 or y < 1 or x > SPOT_MAX or y > SPOT_MAX then return end

    entry.spots = entry.spots or {}
    self:MergeSpot(entry.spots, pos.map, x, y, 1, kind == "node" and self.MAX_SPOTS_NODE or self.MAX_SPOTS_NPC)
end

-- Ein Beutefenster zu einem Abschnitt { attempts, items } zählen.
-- items ist { [itemID] = Menge } aus genau diesem Fenster. hits zählt, in wie vielen Versuchen
-- das Item vorkam (daraus ergibt sich die Chance), amount die Gesamtmenge.
local function CountAttempt(section, items)
    section.attempts = (section.attempts or 0) + 1
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

--- Zählt ein Beutefenster eines Sammelknotens. info = { name, category }, beides optional.
-- pos = { map, x, y } ist der Fundort (optional, siehe AddSpot).
function DB:RecordNode(id, info, items, pos)
    id = tonumber(id)
    if not id then return end

    local node = self.data.nodes[id]
    if not node then
        node = {}
        self.data.nodes[id] = node
    end

    -- Name und Kategorie füllen wir nur, solange sie fehlen
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

--- Zählt ein Beutefenster einer Kreatur. kind ist "loot" oder "skinning", info = { name, level }.
-- pos = { map, x, y } ist der Fundort (optional, siehe AddSpot).
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

-- Aus { attempts, items } wird eine sortierte Liste:
-- { itemID, hits, amount, chance (0..1, Anteil der Versuche), average (Menge je Fund) }
local function BuildDrops(section)
    local list = {}
    local attempts = section and section.attempts or 0
    if attempts == 0 then return list, 0 end

    for itemID, record in pairs(section.items or {}) do
        tinsert(list, {
            itemID = itemID,
            hits = record.hits,
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

--- Eintrag eines Sammelknotens (nur lesen!) oder nil.
function DB:GetNode(id)
    return self.data.nodes[tonumber(id)]
end

--- Eintrag einer Kreatur (nur lesen!) oder nil.
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

--- Anzahl Knoten, Anzahl Kreaturen, Gesamtzahl der erfassten Beutefenster und Zahl der Fundorte.
function DB:GetStats()
    local nodes, npcs, attempts, spots = 0, 0, 0, 0

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

    return nodes, npcs, attempts, spots
end

--- Löscht alle gesammelten Daten. Die Tabellen bleiben dieselben, damit gemerkte Verweise gültig sind.
function DB:ResetData()
    wipe(self.data.nodes)
    wipe(self.data.npcs)
    if self.data.imports then wipe(self.data.imports) end
    self.itemIndex, self.nameIndex = nil, nil
    self:SendMessage(self.MESSAGE_UPDATED, "reset")
end

-- Index Item -> alle Quellen, in denen es vorkam. Wird beim ersten Abfragen aufgebaut und bei
-- jeder Änderung der Daten verworfen (itemIndex = nil), kostet also nur nach neuer Beute etwas.
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

    return index
end

--- Alle Quellen, aus denen ein Item bisher kam, die wahrscheinlichste zuerst. Jeder Eintrag:
-- { kind ("node" | "npc"), id, mode ("gather" | "loot" | "skinning"), name, level (Kreaturen) und category (Knoten: "herb", "ore", "other"), können fehlen,
--   attempts, hits, amount, chance (0..1), average }.
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

-- ---------------------------------------------------------------------------
-- Fundorte abfragen
-- ---------------------------------------------------------------------------

--- Fundorte einer Quelle, kind = "node" oder "npc". Jeder Eintrag: { map (uiMapID), x, y (0 bis 1),
-- count (Beutefenster an diesem Ort) }, die häufigsten zuerst. Das sind genau die Werte für
-- TomTom: TomTom:AddWaypoint(map, x, y, { title = ... }).
function DB:GetSpots(kind, id)
    local entry
    if kind == "node" then entry = self:GetNode(id) elseif kind == "npc" then entry = self:GetNPC(id) end

    local list = {}
    for _, spot in ipairs(entry and entry.spots or {}) do
        tinsert(list, { map = spot.map, x = spot.x / SPOT_MAX, y = spot.y / SPOT_MAX, count = spot.n })
    end

    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.map ~= b.map then return a.map < b.map end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return list
end

--- Fundorte aller Quellen eines Items: erst die Orte der wahrscheinlichsten Quelle, dann die der
-- nächsten. Jeder Eintrag: { map, x, y, count, kind, id, mode, name, chance }. minAttempts wie bei
-- GetItemSources, limit (optional) begrenzt die Länge der Liste.
function DB:GetItemSpots(itemID, minAttempts, limit)
    local result = {}

    for _, source in ipairs(self:GetItemSources(itemID, minAttempts)) do
        for _, spot in ipairs(self:GetSpots(source.kind, source.id)) do
            tinsert(result, {
                map = spot.map, x = spot.x, y = spot.y, count = spot.count,
                kind = source.kind, id = source.id, mode = source.mode, name = source.name, chance = source.chance,
            })
            if limit and #result >= limit then return result end
        end
    end

    return result
end

--- Name einer Karte (Zone) oder nil.
function DB:GetMapName(map)
    local info = self.api.GetMapInfo and self.api.GetMapInfo(map)
    return info and info.name or nil
end

-- ---------------------------------------------------------------------------
-- Knoten über den Namen finden
-- ---------------------------------------------------------------------------

-- Der Tooltip eines Sammelknotens in der Welt bringt weder GUID noch ID mit, nur den Namen in der
-- ersten Zeile. Deshalb lassen sich Knoten auch über ihren Namen abfragen.

-- Farbcodes und Leerraum entfernen, damit Namen aus Tooltip und Datenbank gleich aussehen
local function NormalizeName(name)
    if type(name) ~= "string" or Glimpse:IsSecret(name) then return nil end

    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

--- Text der ersten Zeile eines Tooltips (der Name), oder nil. Geschützte Texte ergeben nil.
function DB:GetTooltipName(tooltip)
    local frameName = tooltip and tooltip.GetName and tooltip:GetName()
    if type(frameName) ~= "string" then return nil end

    local line = _G[frameName .. "TextLeft1"]
    return line and NormalizeName(line:GetText())
end

local function BuildNameIndex(self)
    local index = {}

    for id, node in pairs(self.data.nodes) do
        local name = NormalizeName(node.name)
        if name then
            index[name] = index[name] or {}
            tinsert(index[name], id)
        end
    end
    for _, ids in pairs(index) do table.sort(ids) end

    return index
end

--- IDs aller gespeicherten Knoten mit diesem Namen (sortierte Liste, evtl. leer).
function DB:FindNodeIDs(name)
    name = NormalizeName(name)
    if not name then return {} end

    self.nameIndex = self.nameIndex or BuildNameIndex(self)
    return self.nameIndex[name] or {}
end

--- Beute aller Knoten mit diesem Namen zusammengerechnet (wie GetNodeDrops).
-- Es kann mehrere IDs mit demselben Namen geben, z. B. Varianten eines Vorkommens.
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
