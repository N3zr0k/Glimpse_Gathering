local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")

-- Namen, die der Client nicht aus einer ID liefern kann. Glimpse: Database speichert nur IDs; Knoten (Objekte),
-- Kreaturen und Instanzen haben ohne sichtbares Objekt keinen Namen. Knoten-Tooltips in der Welt haben dazu weder
-- GUID noch ID, nur den Namen in der ersten Zeile, deshalb die Suche über den Namen.
--
-- Eigene SavedVariable GlimpseGatheringNames (account-weit, nur Namen):
--   nodes[Objekt] = Name, npcs[NPC] = Name, levels[NPC] = Stufe, instances[Instanz] = Name

local MAX_NAME = 100

local function Text(value)
    if type(value) ~= "string" or value == "" or Glimpse:IsSecret(value) then return nil end
    return value:sub(1, MAX_NAME)
end

--- SavedVariable vorbereiten
function DB:LoadNames()
    local names = GlimpseGatheringNames
    if type(names) ~= "table" then names = {} end
    for _, key in ipairs({ "nodes", "npcs", "levels", "instances" }) do
        if type(names[key]) ~= "table" then names[key] = {} end
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
        self:ClearCaches() -- Quellen-Listen tragen den Namen mit
    end
end

--- Name und Stufe einer Kreatur merken
function DB:SetNPCName(id, name, level)
    if not id then return end
    local names = Names()
    name = Text(name)
    if name and names.npcs[id] ~= name then
        names.npcs[id] = name
        self:ClearCaches()
    end
    if type(level) == "number" and level ~= 0 then names.levels[id] = level end
end

-- Kreatur über einen Unit-Link nachschlagen. Klappt nur, wenn der Client die Kreatur schon kennt (Cache), sonst
-- fragt er beim Server nach und ein späterer Aufruf findet den Namen.
local NPC_LINK = "unit:Creature-0-0-0-0-%d-0000000000"

--- Name einer Kreatur aus dem Client-Cache holen und merken, nil wenn unbekannt
function DB:LookupNPCName(id)
    id = tonumber(id)
    local GetHyperlink = self.api.GetHyperlinkInfo
    if not id or not GetHyperlink then return nil end

    local ok, info = pcall(GetHyperlink, format(NPC_LINK, id))
    local line = ok and type(info) == "table" and type(info.lines) == "table" and info.lines[1]
    local name = line and Text(line.leftText)
    if name then self:SetNPCName(id, name) end
    return name
end

--- Name eines Objekts merken, dessen Tooltip keine ID hat (Knoten in der Welt). Der nächste Abbau übernimmt ihn.
function DB:NoteObjectName(name)
    name = Text(name)
    if name then self.lastObjectName, self.lastObjectTime = name, GetTime() end
end

--- Namen aus dem Tooltip einer Kreatur oder eines Knotens lernen (Mouseover), falls noch keiner bekannt ist
function DB:LearnTooltipName(kind, id, tooltip)
    if not id then return end
    local names = Names()
    if kind == "npc" and not names.npcs[id] then
        self:SetNPCName(id, self:GetTooltipName(tooltip))
    elseif kind == "node" and not names.nodes[id] then
        self:SetNodeName(id, self:GetTooltipName(tooltip))
    end
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
