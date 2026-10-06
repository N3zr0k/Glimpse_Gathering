local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Anbieter für Fundorte aus GatherMate2 (wenn installiert). Wir lesen nur, wir schreiben nichts in
-- GatherMate2 und kopieren nichts in unsere Daten.
--
-- Benutzt wird die Schnittstelle von GatherMate2 (Stand der Quelle, Oktober 2026):
--   GatherMate2:GetNodesForZone(map, typ, true)   Iterator über coord, nodeID einer Karte
--   GatherMate2:DecodeLoc(coord)                  x, y (0 bis 1)
--   GatherMate2:GetIDForNode(typ, name)           Knoten-ID zu einem (lokalisierten) Namen
--   GatherMate2.HBD:GetAllMapIDs()                alle Karten (sonst: die Speicher von GatherMate2 selbst)
-- Die Karten-IDs sind uiMapIDs wie bei uns. Fehlt etwas davon, meldet sich der Anbieter als nicht
-- verfügbar, und Fehler beim Lesen werden vom Aufrufer abgefangen (DB:AddExternalSpots).

local NAME = "GatherMate2"
local CELL = 100          -- Rasterzellen von 1 % der Karte (wie SPOT_RADIUS), Punkte darin werden ein Ort
local REFRESH = 30        -- Sekunden, so lange bleibt ein veralteter Index nach Änderungen in GatherMate2 bestehen

-- Welche GatherMate2-Typen zu unserer Kategorie passen
local TYPES = {
    herb = { "Herb Gathering" },
    ore = { "Mining" },
    other = { "Extract Gas", "Treasure", "Logging" },
}
local ALL_TYPES = { "Herb Gathering", "Mining", "Extract Gas", "Treasure", "Logging" }

local index = {}          -- [typ] = { [nodeID] = { [zellenschlüssel] = { map, sx, sy, n } } }
local builtAt = {}        -- [typ] = Zeitpunkt
local dirty = false

local function GM()
    return _G.GatherMate2
end

local function Now()
    return GetTime and GetTime() or 0
end

local function IsAvailable()
    local gm = GM()
    return type(gm) == "table" and type(gm.GetNodesForZone) == "function" and type(gm.DecodeLoc) == "function"
        and type(gm.GetIDForNode) == "function" and type(gm.gmdbs) == "table"
end

-- Die Speicher (Tabellen karte -> coord -> nodeID) von GatherMate2 für einen Typ: der Hauptspeicher
-- und die der nachladbaren Datenaddons
local function Stores(gm, typ)
    local stores = {}
    local db = gm.gmdbs[typ]
    if type(db) ~= "table" then return stores end

    local base = rawget(db, "__gm2_base_storage")
    if type(base) == "table" then tinsert(stores, base) end
    local extra = rawget(db, "__gm2_storage_map")
    if type(extra) == "table" then
        for _, store in pairs(extra) do
            if type(store) == "table" then tinsert(stores, store) end
        end
    end
    return stores
end

-- Alle Karten, auf denen GatherMate2 Daten haben kann: die von HereBeDragons plus alle, für die in den
-- Speichern etwas steht (falls HereBeDragons eine Karte nicht kennt)
local function AllMaps(gm)
    local seen, maps = {}, {}
    local function Add(map)
        if type(map) == "number" and not seen[map] then seen[map] = true; tinsert(maps, map) end
    end

    local hbd = gm.HBD
    if type(hbd) == "table" and type(hbd.GetAllMapIDs) == "function" then
        local list = hbd:GetAllMapIDs()
        if type(list) == "table" then
            for _, map in pairs(list) do Add(map) end
        end
    end

    for typ in pairs(gm.gmdbs) do
        for _, store in ipairs(Stores(gm, typ)) do
            for map in pairs(store) do Add(map) end
        end
    end
    return maps
end

-- Liest alle Punkte eines Typs einmal und fasst sie je Knoten in Rasterzellen zusammen
local function Build(gm, typ)
    local nodes = {}
    for _, map in ipairs(AllMaps(gm)) do
        for coord, nodeID in gm:GetNodesForZone(map, typ, true) do
            local x, y = gm:DecodeLoc(coord)
            if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 and x <= 1 and y <= 1 then
                local cells = nodes[nodeID]
                if not cells then cells = {}; nodes[nodeID] = cells end

                local key = map .. ":" .. math.floor(x * CELL) .. ":" .. math.floor(y * CELL)
                local cell = cells[key]
                if not cell then
                    cells[key] = { map = map, sx = x, sy = y, n = 1 }
                else
                    cell.sx, cell.sy, cell.n = cell.sx + x, cell.sy + y, cell.n + 1
                end
            end
        end
    end

    index[typ], builtAt[typ] = nodes, Now()
end

-- Ein leerer Index gilt als nicht fertig und wird nach REFRESH Sekunden neu gelesen (z. B. wenn die Daten
-- beim ersten Zugriff noch nicht da waren)
local function Index(gm, typ)
    local current = index[typ]
    local stale = (dirty or (current and next(current) == nil)) and (Now() - (builtAt[typ] or 0)) >= REFRESH
    if not current or stale then Build(gm, typ) end
    return index[typ]
end

local function MarkDirty()
    dirty = true
end

local provider = { name = NAME }
provider.IsAvailable = IsAvailable

-- GatherMate2 vergibt eigene Knoten-IDs (Kupfervorkommen 201, Silberblatt 402 ...), nicht die Objekt-IDs des Spiels.
-- Der Abgleich läuft deshalb über den Namen des Knotens. Zuerst der genaue Name (GetIDForNode), dann ohne Groß-/Kleinschreibung
-- und Sonderzeichen, zuletzt, falls GatherMate2 den Knoten leicht anders schreibt (z. B. "Kupferader" statt "Kupfervorkommen"):
-- der einzige Name des Typs, der mit denselben ersten Buchstaben beginnt (mindestens PREFIX).
local PREFIX = 5

local function Normalize(text)
    return (tostring(text):lower():gsub("[%s%p]", ""))
end

local function CommonPrefix(a, b)
    local n = math.min(#a, #b)
    local i = 0
    while i < n and a:byte(i + 1) == b:byte(i + 1) do i = i + 1 end
    return i
end

-- Knoten-ID in GatherMate2 zu einem Namen (und wie sie gefunden wurde: "exact", "normalized", "prefix")
local function NodeIDByName(gm, typ, name)
    local id = gm:GetIDForNode(typ, name)
    if id then return id, "exact" end

    local names = gm.reverseNodeIDs
    names = type(names) == "table" and names[typ]
    if type(names) ~= "table" then return nil end

    local wanted = Normalize(name)
    local best, bestLength, tie = nil, 0, false
    for nodeID, nodeName in pairs(names) do
        local normalized = Normalize(nodeName)
        if normalized == wanted then return nodeID, "normalized" end

        local length = CommonPrefix(normalized, wanted)
        if length >= PREFIX and length >= bestLength then
            if length == bestLength and best ~= nodeID then
                tie = true
            else
                best, bestLength, tie = nodeID, length, false
            end
        end
    end
    if best and not tie then return best, "prefix" end
end

function provider.GetSpots(kind, id, entry)
    if kind ~= "node" or not IsAvailable() then return nil end

    local name = entry and entry.name
    if type(name) ~= "string" or name == "" then return nil end

    local gm = GM()
    local result = {}
    local function Collect(typ)
        local nodeID = NodeIDByName(gm, typ, name)
        for _, cell in pairs(nodeID and Index(gm, typ)[nodeID] or {}) do
            tinsert(result, { map = cell.map, x = cell.sx / cell.n, y = cell.sy / cell.n, density = cell.n })
        end
    end

    local types = TYPES[entry.category] or TYPES.other
    local tried = {}
    for _, typ in ipairs(types) do
        tried[typ] = true
        Collect(typ)
    end

    -- Fehlt die Kategorie oder steht sie auf "other" (beim ersten Fund war nichts Eindeutiges dabei, z. B. nur ein
    -- Edelstein), passt vielleicht ein Kräuter- oder Erzknoten: dann zählt der Name in den übrigen Typen. Bei
    -- "herb" und "ore" ist die Kategorie sicher (aus der Beute), dort wird nicht geraten.
    if #result == 0 and (entry.category == nil or entry.category == "other") then
        for _, typ in ipairs(ALL_TYPES) do
            if not tried[typ] then Collect(typ) end
        end
    end
    return result
end

function provider.GetInfo()
    local gm = GM()
    local points, nodes = 0, 0
    for _, typ in ipairs(ALL_TYPES) do
        for _, cells in pairs(Index(gm, typ)) do
            nodes = nodes + 1
            for _, cell in pairs(cells) do points = points + cell.n end
        end
    end
    return { points = points, nodes = nodes }
end

--- Prüfausgabe für "/gli gatheringdb gm2": was GatherMate2 hat und was davon bei uns ankommt.
function DB:DiagnoseGatherMate2()
    local lines = {}
    local function Add(text) tinsert(lines, text) end

    local gm = GM()
    if type(gm) ~= "table" then
        Add("GatherMate2 is not loaded.")
        return lines
    end
    Add("GatherMate2 found, interface complete: " .. tostring(IsAvailable()))
    if not IsAvailable() then return lines end

    local maps = AllMaps(gm)
    Add("Maps to read: " .. #maps .. (type(gm.HBD) == "table" and " (HereBeDragons present)" or " (no HereBeDragons)"))

    for _, typ in ipairs(ALL_TYPES) do
        -- direkt in den Speichern gezählt, unabhängig von unserem Index
        local raw, rawMaps = 0, 0
        for _, store in ipairs(Stores(gm, typ)) do
            for _, points in pairs(store) do
                if type(points) == "table" then
                    rawMaps = rawMaps + 1
                    for _ in pairs(points) do raw = raw + 1 end
                end
            end
        end

        local ok, nodes = pcall(Index, gm, typ)
        local indexed, kinds = 0, 0
        if ok then
            for _, cells in pairs(nodes) do
                kinds = kinds + 1
                for _, cell in pairs(cells) do indexed = indexed + cell.n end
            end
        end
        Add(format("%s: %d points on %d maps in storage, %d points of %d node kinds read%s",
            typ, raw, rawMaps, indexed, kinds, ok and "" or (" (ERROR: " .. tostring(nodes) .. ")")))
    end

    -- Wie viele unserer Knoten finden einen Partner
    local ours, matched = 0, 0
    for id, node in pairs(DB.data.nodes) do
        ours = ours + 1
        local list = provider.GetSpots("node", id, node)
        if list and #list > 0 then matched = matched + 1 end
    end
    Add(format("Own nodes with a match in GatherMate2: %d of %d", matched, ours))

    -- Welche Knoten finden einen Partner und welche nicht (mit Kategorie, sie wählt den Typ in GatherMate2)
    local ids = {}
    for id in pairs(DB.data.nodes) do tinsert(ids, id) end
    table.sort(ids)
    for index, id in ipairs(ids) do
        if index > 30 then
            Add("... " .. (#ids - 30) .. " more")
            break
        end
        local node = DB.data.nodes[id]
        local list = provider.GetSpots("node", id, node)
        if list and #list > 0 then
            Add(format("  %d %s [%s]: %d places in GatherMate2", id, tostring(node.name), tostring(node.category), #list))
        else
            Add(format("  %d %s [%s]: no match", id, tostring(node.name), tostring(node.category)))
            for _, typ in ipairs(TYPES[node.category] or TYPES.other) do
                local nodeID, how = nil, nil
                if type(node.name) == "string" and node.name ~= "" then nodeID, how = NodeIDByName(gm, typ, node.name) end
                if nodeID then
                    Add(format("    %s: name found as GatherMate2 id %s (%s), but no points stored for it", typ, tostring(nodeID), how))
                else
                    local known = {}
                    local names = type(gm.reverseNodeIDs) == "table" and gm.reverseNodeIDs[typ]
                    for knownID, knownName in pairs(names or {}) do tinsert(known, knownID .. "=" .. tostring(knownName)) end
                    table.sort(known)
                    Add(format("    %s: name not known to GatherMate2. Known names (%d): %s", typ, #known,
                        table.concat(known, ", ", 1, math.min(#known, 60))))
                end
            end
        end
    end
    return lines
end

DB:RegisterProvider(NAME, provider)

-- Änderungen in GatherMate2 merken (neuer Index spätestens nach REFRESH Sekunden). Die Nachrichten
-- laufen über AceEvent, das alle Addons gemeinsam benutzen.
function DB:WatchGatherMate2()
    if not IsAvailable() then return end
    for _, message in ipairs({ "GatherMate2NodeAdded", "GatherMate2NodeDeleted", "GatherMate2Cleanup" }) do
        self:RegisterMessage(message, MarkDirty)
    end
end

-- Für Tests: Zwischenspeicher leeren
function DB:ResetGatherMate2Cache()
    index, builtAt, dirty = {}, {}, false
end
