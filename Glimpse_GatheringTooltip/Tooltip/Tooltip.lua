local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Je nach Clientstand liegt die Funktion global oder in C_Item
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Die Zeilen im Tooltip. Anhängen, Trennlinie, Icon links und der Schutz vor Secret-Werten
-- übernimmt Glimpse (RegisterTooltipLine), hier wird nur festgelegt, was drinsteht:
--
--   Gesammelt (14 Versuche)
--   [Icon] Silberblatt          93 %
--   [Icon] Erdwurzel            21 %  Ø 1.4   (Ø = Menge je Fund)
--   Kürschnern (6 Versuche)
--   ...
--
-- Im Tooltip eines Handwerksmaterials steht die wahrscheinlichste Quelle:
--
--   Beste Quelle
--   Waldwolf (Kürschnern)       42 %  Ø 1.4

local HEADER_COLOR = { 1.00, 0.82, 0.00 }
local GREY = "|cff999999"

local function Colored(text, r, g, b)
    return format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

-- Items, deren Namen der Client noch nicht kennt: sie werden angefordert, und sobald sie da
-- sind (GET_ITEM_INFO_RECEIVED), baut sich der Tooltip neu auf.
local waitingForNames = false

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if name then
        local quality = C_Item.GetItemQualityByID(itemID)
        local color = quality and ITEM_QUALITY_COLORS[quality]
        return color and Colored(name, color.r, color.g, color.b) or name
    end

    waitingForNames = true
    C_Item.RequestLoadItemDataByID(itemID)
    return GREY .. "[" .. itemID .. "]|r"
end

-- Rechte Spalte: Chance in Prozent und die durchschnittliche Menge je Fund
local function ChanceText(drop)
    return format("%d %%", math.floor(drop.chance * 100 + 0.5))
        .. "  " .. GREY .. format(L["Avg. %.1f"], drop.average) .. "|r"
end

-- Fügt Überschrift und Item-Zeilen einer Beuteliste an rows an. Zu wenige Versuche: nichts.
local function AddSection(rows, title, drops, attempts, profile)
    if #drops == 0 or attempts < profile.minAttempts then return end

    tinsert(rows, {
        Colored(title, unpack(HEADER_COLOR)) .. "  " .. GREY .. format(L["%d attempts"], attempts) .. "|r",
    })

    for index = 1, math.min(#drops, profile.maxItems) do
        local drop = drops[index]
        local _, _, _, _, icon = GetItemInfoInstant(drop.itemID)

        tinsert(rows, { ItemName(drop.itemID), ChanceText(drop), 1, 1, 1, icon = icon })
    end
end

-- Was ein Tooltip beschreibt: "node" (Sammelknoten) oder "npc" (Kreatur), dazu die ID.
-- Die ID steckt in der GUID ("GameObject-0-3131-2552-14367-1731-0000A5C2B1" -> 1731).
-- Bei Objekten fällt es auf data.id zurück, falls die GUID fehlt oder geschützt ist.
local function SourceOf(data, isObject)
    local guid = data.guid
    if type(guid) == "string" then
        local kind, _, _, _, _, id = strsplit("-", guid)
        id = tonumber(id)

        if id then
            if kind == "GameObject" then return "node", id end
            if kind == "Creature" or kind == "Vehicle" then return "npc", id end
        end
    end

    if isObject and data.id then return "node", data.id end
end

-- Der Tooltip eines Knotens in der Welt bringt keine ID mit. Dann gilt der Name aus der ersten
-- Zeile (GetNodeDropsByName), sonst die ID.
local function NodeLines(self, id, name)
    local profile = self.db.profile
    if not profile.showNodes then return nil end

    -- Kategorie des Knotens (Kräuter, Erz) entscheidet über den passenden Beruf
    local node = self.data:GetNode(id or self.data:FindNodeIDs(name)[1])
    if node and not self:IsLearned(node.category) then return nil end

    local rows = {}
    local drops, attempts
    if id then
        drops, attempts = self.data:GetNodeDrops(id)
    else
        drops, attempts = self.data:GetNodeDropsByName(name)
    end
    AddSection(rows, L["Gathered"], drops, attempts, profile)

    if #rows > 0 then return rows end
end

local function UnitLines(self, id)
    local profile = self.db.profile

    local rows = {}
    if profile.showLoot then
        local drops, attempts = self.data:GetNPCDrops(id, "loot")
        AddSection(rows, L["Loot"], drops, attempts, profile)
    end
    if profile.showSkinning and self:IsLearned("skinning") then
        local drops, attempts = self.data:GetNPCDrops(id, "skinning")
        AddSection(rows, L["Skinning"], drops, attempts, profile)
    end

    if #rows > 0 then return rows end
end

-- Knoten und Kreaturen können als Objekt- oder als Einheiten-Tooltip ankommen, deshalb gilt für
-- beide Typen dieselbe Auswertung
local function SourceLines(self, data, isObject, tooltip)
    waitingForNames = false

    local kind, id = SourceOf(data, isObject)
    if kind == "node" then return NodeLines(self, id) end
    if kind == "npc" then return UnitLines(self, id) end

    -- Objekt ohne ID: über den Namen suchen
    if isObject then return NodeLines(self, nil, self.data:GetTooltipName(tooltip)) end
end

-- Wahrscheinlichste Quelle eines Items (Knoten oder Kreatur) aus dem Index von GatheringDB
-- Ist die Quelle für den Spieler relevant? Knoten brauchen ihren Beruf (Kräuter, Erz),
-- Kürschnerbeute braucht Kürschnerei, normale Beute braucht nichts.
local function IsRelevant(self, source)
    if source.kind == "node" then return self:IsLearned(source.category) end
    if source.mode == "skinning" then return self:IsLearned("skinning") end
    return true
end

-- Eine Zeile pro Quelle: Name (bei Kreaturen mit Stufe und Art), rechts die Chance
local function SourceRow(source)
    local name = source.name
    if not name then
        name = format(source.kind == "node" and L["Node %d"] or L["Creature %d"], source.id)
    end

    -- Bei Kreaturen steht dahinter die Stufe (-1 = Boss, "??") und ob es Beute oder Kürschnern ist.
    -- Knoten brauchen keinen Zusatz.
    local extra = {}
    if source.kind == "npc" and source.level then
        tinsert(extra, format(L["Level %s"], source.level < 0 and "??" or source.level))
    end
    if source.mode == "loot" then
        tinsert(extra, L["Loot"])
    elseif source.mode == "skinning" then
        tinsert(extra, L["Skinning"])
    end
    if #extra > 0 then
        name = name .. " " .. GREY .. "(" .. table.concat(extra, ", ") .. ")|r"
    end

    return { name, ChanceText(source), 1, 1, 1 }
end

-- Die wahrscheinlichsten Quellen eines Materials aus dem Index von GatheringDB
-- (schon nach Chance sortiert), so viele wie in den Optionen eingestellt
local function ItemLines(self, data)
    local profile = self.db.profile
    if not profile.showItemSource or not data.id then return nil end

    local rows = {}
    for _, source in ipairs(self.data:GetItemSources(data.id, profile.minAttempts)) do
        if IsRelevant(self, source) then
            tinsert(rows, SourceRow(source))
            if #rows >= profile.maxSources then break end
        end
    end
    if #rows == 0 then return nil end

    tinsert(rows, 1, { Colored(#rows == 1 and L["Best source"] or L["Sources"], unpack(HEADER_COLOR)) })
    return rows
end

function GT:RegisterTooltips()
    local types = Enum.TooltipDataType

    -- Ohne die gewählten Zusatztasten (Option "Nur mit Taste") bleibt der Tooltip unverändert.
    -- Der Provider bekommt (module, data, tooltip, hidden), data ist schon bereinigt.
    local function Gated(func)
        return function(module, data, tooltip, ...)
            if not Glimpse:ModifiersHeld(module.db.profile) then return nil end
            return func(module, data, tooltip, ...)
        end
    end

    self:RegisterTooltipLine(types.Object, Gated(function(module, data, tooltip)
        return SourceLines(module, data, true, tooltip)
    end))
    self:RegisterTooltipLine(types.Unit, Gated(function(module, data, tooltip)
        return SourceLines(module, data, false, tooltip)
    end))
    -- Item-Tooltips: die Namen kommen aus der Datenbank, hier muss nichts nachgeladen werden
    self:RegisterTooltipLine(types.Item, Gated(ItemLines))
end

-- Baut den sichtbaren Tooltip neu auf, z. B. nach einer geänderten Option
function GT:RefreshTooltip()
    if GameTooltip:IsShown() and GameTooltip.RefreshData then
        GameTooltip:RefreshData()
    end
end

function GT:OnItemInfo()
    if not waitingForNames then return end
    waitingForNames = false

    -- Viele Items kommen kurz hintereinander an, deshalb ein kurzer Aufschub
    C_Timer.After(0.1, function() self:RefreshTooltip() end)
end
