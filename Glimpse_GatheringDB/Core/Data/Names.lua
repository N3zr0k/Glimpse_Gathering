local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Knoten über den Namen finden. Knoten-Tooltips in der Welt haben weder GUID noch ID, nur den Namen in der ersten Zeile

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
