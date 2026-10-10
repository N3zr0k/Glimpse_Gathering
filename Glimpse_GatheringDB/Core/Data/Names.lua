local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Namen, die der Client nicht aus einer ID liefern kann. Glimpse: Database speichert nur IDs; Knoten (Objekte),
-- Kreaturen und Instanzen haben ohne sichtbares Objekt keinen Namen. Knoten-Tooltips in der Welt haben dazu weder
-- GUID noch ID, nur den Namen in der ersten Zeile, deshalb die Suche über den Namen.
--
-- Eigene SavedVariable GlimpseGatheringNames (account-weit, nur Namen):
--   nodes[Objekt] = Name, npcs[NPC] = Name, levels[NPC] = Stufe, instances[Instanz] = Name
--   taken = Zeitpunkt, zu dem die Namen aus GlimpseGatheringDB übernommen wurden (einmalig)
-- GlimpseGatheringDB (alte Daten) wird nur gelesen, nie verändert; die Zahlen übernimmt Glimpse: Database.

local MAX_NAME = 100

local function Text(value)
    if type(value) ~= "string" or value == "" or Glimpse:IsSecret(value) then return nil end
    return value:sub(1, MAX_NAME)
end

-- Namen aus den alten Daten, ohne vorhandene zu überschreiben
local function TakeOver(names, old)
    for id, node in pairs(type(old.nodes) == "table" and old.nodes or {}) do
        if type(id) == "number" and type(node) == "table" then names.nodes[id] = names.nodes[id] or Text(node.name) end
    end
    for id, npc in pairs(type(old.npcs) == "table" and old.npcs or {}) do
        if type(id) == "number" and type(npc) == "table" then
            names.npcs[id] = names.npcs[id] or Text(npc.name)
            if type(npc.level) == "number" then names.levels[id] = names.levels[id] or npc.level end
        end
    end
    for id, name in pairs(type(old.instances) == "table" and old.instances or {}) do
        if type(id) == "number" then names.instances[id] = names.instances[id] or Text(name) end
    end
end

--- SavedVariable vorbereiten, beim ersten Start die Namen aus GlimpseGatheringDB übernehmen
function DB:LoadNames()
    local names = GlimpseGatheringNames
    if type(names) ~= "table" then names = {} end
    for _, key in ipairs({ "nodes", "npcs", "levels", "instances" }) do
        if type(names[key]) ~= "table" then names[key] = {} end
    end

    local old = type(GlimpseGatheringDB) == "table" and GlimpseGatheringDB.global
    if not names.taken and type(old) == "table" then
        local ok, err = pcall(TakeOver, names, old)
        if not ok then self:ReportError("TakeOverNames", err) end
        names.taken = time()
    end

    GlimpseGatheringNames = names
    self.names = names
    self.nameIndex = nil
end

local function Names()
    return DB.names or { nodes = {}, npcs = {}, levels = {}, instances = {} }
end

--- Name eines Knotens merken, nur ergänzen (der Zielname eines Zaubers ist nicht immer der Knoten)
function DB:SetNodeName(id, name)
    name = Text(name)
    local names = Names()
    if id and name and not names.nodes[id] then
        names.nodes[id] = name
        self.nameIndex = nil
    end
end

--- Name und Stufe einer Kreatur merken
function DB:SetNPCName(id, name, level)
    if not id then return end
    local names = Names()
    names.npcs[id] = Text(name) or names.npcs[id]
    if type(level) == "number" and level ~= 0 then names.levels[id] = level end
end

--- Name einer Instanz merken
function DB:SetInstanceName(id, name)
    name = Text(name)
    if id and name then Names().instances[id] = name end
end

function DB:GetNodeName(id)
    return Names().nodes[tonumber(id)]
end

--- Name und gespeicherte Stufe einer Kreatur
function DB:GetNPCName(id)
    local names = Names()
    id = tonumber(id)
    return names.npcs[id], names.levels[id]
end

--- Name einer Instanz oder nil
function DB:GetInstanceName(id)
    return Names().instances[tonumber(id)]
end

-- Farbcodes und Leerraum entfernen, damit Namen aus Tooltip und Ablage gleich aussehen
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

local function BuildNameIndex()
    local index = {}

    for id, name in pairs(Names().nodes) do
        name = NormalizeName(name)
        if name then
            index[name] = index[name] or {}
            tinsert(index[name], id)
        end
    end
    for _, ids in pairs(index) do table.sort(ids) end

    return index
end

--- IDs aller Knoten mit diesem Namen (sortierte Liste, evtl. leer).
function DB:FindNodeIDs(name)
    name = NormalizeName(name)
    if not name then return {} end

    self.nameIndex = self.nameIndex or BuildNameIndex()
    return self.nameIndex[name] or {}
end
