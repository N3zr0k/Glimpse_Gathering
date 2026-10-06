local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Export und Import der gesammelten Daten, zum Sichern, zum Übertragen auf einen anderen Account
-- oder Rechner und zum Zusammenführen mehrerer Datenbestände.
--
-- Aufbau eines Exporttexts:   GGDB<Format>:<Methode>:<Daten>
--   Format   Version dieses Textformats (FORMAT), nicht zu verwechseln mit der Version der Daten
--   Methode  "D" = Deflate-komprimiert und druckbar kodiert (LibDeflate), "R" = unkomprimierter Text
--   Daten    die Tabelle { format, version, created, id, nodes, npcs, instances } in einer eigenen, einfachen
--            Textform (unten). Es wird nie Code geladen oder ausgeführt, nur gelesen und geprüft.
--
-- Beim Import wird die Datenversion (version) mit DATA_VERSION verglichen: ältere Daten werden mit
-- denselben Schritten umgestellt wie beim Start (DB:UpgradeData, Data/Migrate.lua), neuere werden
-- abgelehnt. Danach läuft die gewohnte Prüfung (DB:SanitizeData), erst dann werden die Daten
-- zusammengeführt oder ersetzt.

local FORMAT = 1
local MAGIC = "GGDB"

-- Grenzen gegen beschädigte oder bösartige Texte
local MAX_TEXT = 40000000   -- Länge des eingefügten Texts
local MAX_DEPTH = 8         -- Verschachtelung der Tabellen
local MAX_STRING = 500      -- Länge eines einzelnen Texts in den Daten (Namen)
local MAX_VALUES = 6000000  -- Zahl der Werte insgesamt
local MAX_IMPORTS = 50      -- so viele Export-IDs merken wir uns

-- ---------------------------------------------------------------------------
-- Eigene Textform für Tabellen
-- ---------------------------------------------------------------------------
--   n123.5;   Zahl                 s5:hallo   Text mit Längenangabe
--   T  /  F   Wahrheitswert        {k v k v}  Tabelle, abwechselnd Schlüssel und Wert

local function WriteValue(out, value, depth)
    local kind = type(value)

    if kind == "number" then
        out[#out + 1] = "n" .. format("%.14g", value) .. ";"
    elseif kind == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif kind == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif kind == "table" then
        if depth > MAX_DEPTH then error("table too deep") end

        local keys = {}
        for key in pairs(value) do
            local keyType = type(key)
            if keyType == "number" or keyType == "string" then keys[#keys + 1] = key end
        end
        -- feste Reihenfolge: gleicher Inhalt ergibt gleichen Text
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return a < b
        end)

        out[#out + 1] = "{"
        for _, key in ipairs(keys) do
            WriteValue(out, key, depth + 1)
            WriteValue(out, value[key], depth + 1)
        end
        out[#out + 1] = "}"
    else
        error("unsupported value type " .. kind)
    end
end

--- Tabelle in Text umwandeln.
function DB.Serialize(value)
    local out = {}
    WriteValue(out, value, 0)
    return table.concat(out)
end

-- Liest einen Wert ab Position pos. Gibt Wert und neue Position zurück, bei Fehlern wird error()
-- aufgerufen (der Aufrufer fängt das mit pcall ab).
local function ReadValue(text, pos, depth, state)
    state.values = state.values + 1
    if state.values > MAX_VALUES then error("too many values") end

    local tag = text:sub(pos, pos)

    if tag == "n" then
        local stop = text:find(";", pos, true)
        local number = stop and tonumber(text:sub(pos + 1, stop - 1))
        -- NaN (number ~= number) und unendlich werden abgelehnt
        if not number or number ~= number or number >= 1e15 or number <= -1e15 then error("bad number") end
        return number, stop + 1

    elseif tag == "s" then
        local colon = text:find(":", pos, true)
        local length = colon and tonumber(text:sub(pos + 1, colon - 1))
        if not length or length < 0 or length > MAX_STRING or length ~= math.floor(length) then
            error("bad string length")
        end
        local value = text:sub(colon + 1, colon + length)
        if #value ~= length then error("truncated string") end
        return value, colon + length + 1

    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1

    elseif tag == "{" then
        if depth >= MAX_DEPTH then error("table too deep") end

        local result = {}
        pos = pos + 1
        while text:sub(pos, pos) ~= "}" do
            if pos > #text then error("unterminated table") end

            local key, value
            key, pos = ReadValue(text, pos, depth + 1, state)
            if type(key) ~= "number" and type(key) ~= "string" then error("bad key") end
            value, pos = ReadValue(text, pos, depth + 1, state)
            result[key] = value
        end
        return result, pos + 1
    end

    error("unexpected character at " .. pos)
end

--- Text in eine Tabelle zurückverwandeln. Gibt die Tabelle zurück, bei Fehlern nil und eine Meldung.
function DB.Deserialize(text)
    local ok, value, pos = pcall(ReadValue, text, 1, 0, { values = 0 })
    if not ok then return nil, value end
    if pos ~= #text + 1 then return nil, "unexpected data at the end" end
    if type(value) ~= "table" then return nil, "not a table" end
    return value
end

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

local function Compressor()
    return LibStub("LibDeflate", true)
end

local function NewExportID()
    return format("%x-%x", time(), math.random(0, 0xFFFFFF))
end

local function Count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

--- Alle gesammelten Daten als Text zum Kopieren. Gibt den Text und eine Tabelle { nodes, npcs, chars }
-- zurück.
function DB:ExportData()
    local payload = {
        format = FORMAT,
        version = self.DATA_VERSION,
        created = time(),
        id = NewExportID(),
        nodes = self.data.nodes,
        npcs = self.data.npcs,
        instances = self.data.instances,
    }
    local text = self.Serialize(payload)

    local method, body = "R", text
    local lib = Compressor()
    if lib then
        local packed = lib:CompressDeflate(text, { level = 9 })
        if packed then method, body = "D", lib:EncodeForPrint(packed) end
    end

    local result = MAGIC .. FORMAT .. ":" .. method .. ":" .. body
    return result, { nodes = Count(self.data.nodes), npcs = Count(self.data.npcs), chars = #result }
end

-- ---------------------------------------------------------------------------
-- Import
-- ---------------------------------------------------------------------------

-- Fehlerschlüssel von ImportData (die Oberfläche übersetzt sie):
--   empty        nichts eingefügt
--   tooLarge     Text länger als MAX_TEXT
--   notExport    kein Exporttext von GatheringDB
--   formatNewer  Exportformat stammt aus einer neueren Version des Addons
--   unsupported  Kompression ist hier nicht verfügbar
--   damaged      Text beschädigt oder unvollständig
--   dataNewer    Daten stammen aus einer neueren Version des Addons
--   duplicate    dieser Export wurde schon zusammengeführt

--- Text lesen und prüfen. Gibt die Nutzdaten zurück oder nil und einen Fehlerschlüssel.
function DB:DecodeExport(text)
    if type(text) ~= "string" then return nil, "empty" end
    if #text > MAX_TEXT then return nil, "tooLarge" end

    local version, method, body = text:match("^%s*" .. MAGIC .. "(%d+):(%a):(.*)$")
    if not version then
        if text:match("^%s*$") then return nil, "empty" end
        return nil, "notExport"
    end
    if tonumber(version) > FORMAT then return nil, "formatNewer" end

    local serialized
    if method == "D" then
        local lib = Compressor()
        if not lib then return nil, "unsupported" end

        -- beim Einfügen können Zeilenumbrüche entstehen
        body = body:gsub("%s+", "")
        local packed = lib:DecodeForPrint(body)
        serialized = packed and lib:DecompressDeflate(packed)
        if not serialized then return nil, "damaged" end
    elseif method == "R" then
        serialized = body:gsub("%s+$", "")
    else
        return nil, "notExport"
    end

    local payload = self.Deserialize(serialized)
    if not payload or type(payload.version) ~= "number" then return nil, "damaged" end
    return payload
end

-- Zählt b zu a (Abschnitt { attempts, items }), die Zahlen bleiben unter der Obergrenze
local COUNT_MAX = 1e9 - 1

local function MergeSection(target, source)
    target.attempts = math.min((target.attempts or 0) + source.attempts, COUNT_MAX)
    target.items = target.items or {}

    for itemID, record in pairs(source.items) do
        local sum = target.items[itemID]
        if sum then
            sum.hits = math.min(sum.hits + record.hits, COUNT_MAX)
            sum.amount = math.min(sum.amount + record.amount, COUNT_MAX)
            -- Treffer können nie über den Versuchen liegen
            if sum.hits > target.attempts then sum.hits = target.attempts end
        else
            target.items[itemID] = { hits = record.hits, amount = record.amount }
        end
    end
end

local function MergeSpots(self, target, source, kind)
    if not source.spots then return end

    target.spots = target.spots or {}
    local limit = kind == "node" and self.MAX_SPOTS_NODE or self.MAX_SPOTS_NPC
    for _, spot in ipairs(source.spots) do
        if spot.inst then
            self:MergeInstanceSpot(target.spots, spot.inst, spot.n, limit)
        else
            self:MergeSpot(target.spots, spot.map, spot.x, spot.y, spot.n, limit)
        end
    end
end

-- Führt geprüfte Daten in die gespeicherten zusammen: Zähler werden addiert, Name, Stufe und
-- Kategorie nur ergänzt, Fundorte zusammengefasst.
local function MergeData(self, incoming)
    local data = self.data

    -- Namen von Instanzen: vorhandene bleiben, neue kommen dazu
    data.instances = data.instances or {}
    for id, name in pairs(incoming.instances or {}) do
        data.instances[id] = data.instances[id] or name
    end

    for id, node in pairs(incoming.nodes) do
        local target = data.nodes[id]
        if not target then
            data.nodes[id] = node
        else
            MergeSection(target, node)
            target.name = target.name or node.name
            if node.category and (not target.category or target.category == "other") then
                target.category = node.category
            end
            MergeSpots(self, target, node, "node")
        end
    end

    for id, npc in pairs(incoming.npcs) do
        local target = data.npcs[id]
        if not target then
            data.npcs[id] = npc
        else
            target.name = target.name or npc.name
            target.level = target.level or npc.level
            if npc.kills then target.kills = math.min((target.kills or 0) + npc.kills, COUNT_MAX) end
            for _, kind in ipairs({ "loot", "skinning" }) do
                if npc[kind] then
                    target[kind] = target[kind] or { attempts = 0, items = {} }
                    MergeSection(target[kind], npc[kind])
                end
            end
            MergeSpots(self, target, npc, "npc")
        end
    end
end

local function RememberImport(data, id)
    if type(id) ~= "string" then return end

    data.imports = data.imports or {}
    data.imports[id] = time()

    -- nur die neuesten MAX_IMPORTS behalten
    local ids = {}
    for key in pairs(data.imports) do ids[#ids + 1] = key end
    if #ids <= MAX_IMPORTS then return end

    table.sort(ids, function(a, b)
        local ta, tb = data.imports[a], data.imports[b]
        if ta ~= tb then return ta > tb end
        return a < b
    end)
    for index = MAX_IMPORTS + 1, #ids do data.imports[ids[index]] = nil end
end

--- Importiert einen Exporttext. mode = "merge" (Standard: Zähler addieren, vorhandene Daten bleiben)
-- oder "replace" (alle gespeicherten Daten werden ersetzt).
-- Gibt true und { nodes, npcs, version, migrated, removed } zurück, bei Fehlern false und einen
-- Fehlerschlüssel (siehe oben).
function DB:ImportData(text, mode)
    mode = mode == "replace" and "replace" or "merge"

    local payload, err = self:DecodeExport(text)
    if not payload then return false, err end

    -- Dieselbe Umstellung und Prüfung wie bei den eigenen Daten, nur auf einer Kopie
    local incoming = {
        version = payload.version, nodes = payload.nodes, npcs = payload.npcs, instances = payload.instances,
    }
    if not self:UpgradeData(incoming, self.DATA_VERSION) then return false, "dataNewer" end
    local removed = self:SanitizeData(incoming)

    local data = self.data
    if mode == "merge" and type(payload.id) == "string" and data.imports and data.imports[payload.id] then
        return false, "duplicate"
    end

    if mode == "replace" then
        wipe(data.nodes)
        wipe(data.npcs)
        data.instances = data.instances or {}
        wipe(data.instances)
        for id, name in pairs(incoming.instances) do data.instances[id] = name end
        for id, node in pairs(incoming.nodes) do data.nodes[id] = node end
        for id, npc in pairs(incoming.npcs) do data.npcs[id] = npc end
    else
        MergeData(self, incoming)
    end

    RememberImport(data, payload.id)
    removed = removed + self:PruneData()

    self.itemIndex, self.nameIndex = nil, nil
    self:SendMessage(self.MESSAGE_UPDATED, "import")

    return true, {
        nodes = Count(incoming.nodes), npcs = Count(incoming.npcs),
        version = payload.version, migrated = payload.version < self.DATA_VERSION,
        removed = removed, mode = mode,
    }
end
