local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local L = DB.L

-- Skill-Abfragen: was ein Knoten oder eine Kreatur verlangt, wie weit der Spieler ist und welche Farbe daraus wird.
-- Die Tabellen stehen in Data/SkillData.lua. Berufe heißen hier "herb" (Kräuterkunde), "ore" (Bergbau) und
-- "skinning" (Kürschnerei) und "fishing" (Angeln), wie die Kategorien der Knoten.

-- Skill-Linie und Berufszauber je Beruf. Die Linien-IDs stammen von https://warcraft.wiki.gg/wiki/TradeSkillLineID,
-- die Zauber von classicdb.ch (2366 Herb Gathering, 2575 Mining, 8613 Skinning). Der Zauber "Herb Gathering" heißt
-- anders als die Skill-Linie "Herbalism", deshalb steht zusätzlich der übersetzte Name aus den Locale-Dateien dabei.
local PROFESSIONS = {
    herb = { line = 182, spell = 2366, label = "Herbalism" },
    ore = { line = 186, spell = 2575, label = "Mining" },
    skinning = { line = 393, spell = 8613, label = "Skinning" },
    fishing = { line = 356, spell = 7620, label = "Fishing" },
}

-- ---------------------------------------------------------------------------
-- Benötigter Skill
-- ---------------------------------------------------------------------------

--- Benötigter Kürschnerei-Skill für eine Kreatur dieser Stufe (nil bei unbekannter oder Boss-Stufe).
function DB:GetSkinningSkill(level)
    level = tonumber(level)
    if not level or level <= 0 then return nil end

    if level <= self.SKINNING_FREE_LEVEL then return 1 end
    if level <= self.SKINNING_STEP_LEVEL then return (level - 10) * 10 end
    return level * 5
end

--- Beruf ("herb" oder "ore") und benötigter Skill eines Sammelknotens (Objekt-ID), sonst nil.
-- Steht die ID nicht in der Tabelle, aber der Knoten ist schon aufgezeichnet, entscheidet das Material, das er geliefert
-- hat (nur, wenn alle bekannten Materialien denselben Skill verlangen).
function DB:GetNodeSkill(id)
    id = tonumber(id)
    if not id then return nil end

    local entry = self.NodeSkills[id]
    if entry then return entry[1], entry[2] end

    local node = self:GetNode(id)
    local profession, required
    for itemID in pairs(node and node.items or {}) do
        local item = self.ItemSkills[itemID]
        if item then
            if required and (item[1] ~= profession or item[2] ~= required) then return nil end
            profession, required = item[1], item[2]
        end
    end
    return profession, required
end

--- true, wenn von dieser Kreatur schon Kürschner-Beute aufgezeichnet wurde.
function DB:IsKnownSkinnable(id)
    local npc = self:GetNPC(id)
    return npc ~= nil and npc.skinning ~= nil and (npc.skinning.attempts or 0) > 0
end

--- Beruf und benötigter Skill einer Quelle: kind = "node" (id = Objekt-ID) oder "npc" (id = Kreatur-ID, level =
-- Stufe der Kreatur, ohne Angabe gilt die gespeicherte). Bei Kreaturen kommt als dritter Wert, ob sie als kürschnerbar
-- bekannt ist. Ohne Ergebnis nil.
function DB:GetRequiredSkill(kind, id, level)
    if kind == "node" then
        local profession, required = self:GetNodeSkill(id)
        return profession, required, profession ~= nil
    end
    if kind == "npc" then
        local npc = self:GetNPC(id)
        local required = self:GetSkinningSkill(level or (npc and npc.level))
        if not required then return nil end
        return "skinning", required, self:IsKnownSkinnable(id)
    end
end

--- Farbe, in der ein Knoten oder eine Kreatur für diesen Skill erscheint: "red" (Skill reicht nicht), "orange", "yellow",
-- "green" oder "gray" (bringt keine Skillpunkte mehr), dazu r, g, b. Ohne Zahlen nil.
function DB:GetSkillColor(required, current)
    required, current = tonumber(required), tonumber(current)
    if not (required and current) then return nil end

    local delta = current - required
    local key = "red"
    if delta >= self.SKILL_GRAY then
        key = "gray"
    elseif delta >= self.SKILL_GREEN then
        key = "green"
    elseif delta >= self.SKILL_YELLOW then
        key = "yellow"
    elseif delta >= 0 then
        key = "orange"
    end

    local color = self.SkillColors[key]
    return key, color[1], color[2], color[3]
end

-- ---------------------------------------------------------------------------
-- Skill des Spielers
-- ---------------------------------------------------------------------------

local function SpellName(spellID)
    local api = DB.api
    if api.GetSpellName then return api.GetSpellName(spellID) end
    if api.GetSpellInfo then return (api.GetSpellInfo(spellID)) end
end

-- Alle Berufe über GetProfessions/GetProfessionInfo (so liest auch GatheringTooltip die gelernten Berufe). Der
-- Ausrüstungsbonus steht in skillModifier. Gibt nil zurück, wenn der Client die Funktionen nicht hat.
local function ScanProfessions()
    local api = DB.api
    if not (api.GetProfessions and api.GetProfessionInfo) then return nil end

    local found = {}
    local ok = pcall(function()
        -- Rückgabe: Beruf 1, Beruf 2, Archäologie, Angeln, Kochen (einzelne können nil sein)
        local indexes = { api.GetProfessions() }
        for position = 1, 5 do
            local index = indexes[position]
            if index then
                local name, _, rank, maximum, _, _, line, modifier = api.GetProfessionInfo(index)
                for profession, info in pairs(PROFESSIONS) do
                    if line == info.line then
                        found[profession] = { name = name, rank = rank or 0, modifier = modifier or 0, max = maximum or 0, via = "GetProfessionInfo" }
                    end
                end
            end
        end
    end)
    if not ok then return nil end
    return found
end

-- Ersatz über GetSkillLineInfo: dort gibt es keine IDs, die Skill-Linien werden über den Namen gefunden. Der kommt aus dem
-- Berufszauber (GetSpellInfo), nicht aus einer festen Übersetzung. Für Kräuterkunde heißt der Zauber anders als die Linie,
-- dafür gilt zusätzlich der Name aus den Locale-Dateien. Ob der Ausrüstungsbonus hier in skillModifier oder in
-- numTempPoints steht, ist nicht belegt, es zählt skillModifier (siehe /gli gatheringdb skill).
local function ScanSkillLines()
    local api = DB.api
    if not (api.GetNumSkillLines and api.GetSkillLineInfo) then return nil end

    local names = {}
    for profession, info in pairs(PROFESSIONS) do
        names[profession] = {}
        local spell = SpellName(info.spell)
        if spell then names[profession][spell] = true end
        names[profession][L[info.label]] = true
    end

    local found = {}
    local ok = pcall(function()
        for index = 1, api.GetNumSkillLines() do
            local name, header, _, rank, temp, modifier, maximum = api.GetSkillLineInfo(index)
            if name and not header then
                for profession, set in pairs(names) do
                    if set[name] then
                        found[profession] = { name = name, rank = rank or 0, modifier = modifier or 0, temp = temp or 0, max = maximum or 0, via = "GetSkillLineInfo" }
                    end
                end
            end
        end
    end)
    if not ok then return nil end
    return found
end

-- Der Cache wird nur bei SKILL_LINES_CHANGED (und beim Wechsel der Ausrüstung, die den Bonus ändert) geleert.
local function Skills(self)
    if not self.skillCache then
        self.skillCache = ScanProfessions() or ScanSkillLines() or {}
    end
    return self.skillCache
end

--- Skill des Spielers in diesem Beruf ("herb", "ore" oder "skinning"): aktuell (mit Bonus), Maximum, Name des Berufs im
-- Client, Skill ohne Bonus. Hat der Spieler den Beruf nicht gelernt (oder der Client verrät es nicht), nil.
function DB:GetPlayerSkill(profession)
    local info = Skills(self)[profession]
    if not info then return nil end
    return info.rank + info.modifier, info.max, info.name, info.rank
end

--- Hat der Spieler diesen Beruf? nil, wenn der Client die Berufe nicht auslesen lässt.
function DB:HasProfession(profession)
    if not (self.api.GetProfessions or self.api.GetNumSkillLines) then return nil end
    return Skills(self)[profession] ~= nil
end

--- Leert den Skill-Cache (SKILL_LINES_CHANGED).
function DB:OnSkillsChanged()
    self.skillCache = nil
end

function DB:WatchSkills()
    self:RegisterEvent("SKILL_LINES_CHANGED", "OnSkillsChanged")
    -- Ein Kürschnermesser oder Handschuhe mit Verzauberung ändern den Bonus
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnSkillsChanged")
end

--- Rohwerte zur Prüfung im Spiel (/gli gatheringdb skill): je Beruf Skill, Bonus und welcher Weg ihn geliefert hat.
function DB:DescribeSkills()
    self.skillCache = nil -- frisch lesen
    local lines = {}
    for _, profession in ipairs({ "ore", "herb", "skinning", "fishing" }) do
        local info = Skills(self)[profession]
        local label = L[PROFESSIONS[profession].label]
        if info then
            local text = format(L["%s: skill %d, bonus %d, maximum %d (%s)"], info.name or label, info.rank, info.modifier, info.max, info.via)
            if info.temp then text = text .. format(", numTempPoints %d", info.temp) end
            lines[#lines + 1] = text
        else
            lines[#lines + 1] = format(L["%s: not learned"], label)
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Kreaturentyp
-- ---------------------------------------------------------------------------

local typeIDs

--- ID des Kreaturentyps einer Einheit (z. B. 1 = Wildtier), unabhängig von der Sprache des Clients. Neuere Clients
-- liefern die ID als zweiten Wert von UnitCreatureType, sonst wird der Name über C_CreatureInfo.GetCreatureTypeInfo
-- zugeordnet. nil, wenn nichts zu ermitteln ist.
function DB:GetCreatureTypeID(unit)
    local api = self.api
    if not api.UnitCreatureType then return nil end

    local ok, name, id = pcall(api.UnitCreatureType, unit)
    if not ok then return nil end
    if type(id) == "number" then return id end
    if type(name) ~= "string" or Glimpse:IsSecret(name) then return nil end

    if not typeIDs then
        typeIDs = {}
        if api.GetCreatureTypeInfo then
            for typeID = 1, 15 do
                local info = api.GetCreatureTypeInfo(typeID)
                if info and info.name then typeIDs[info.name] = typeID end
            end
        end
    end
    return typeIDs[name]
end

--- Kann eine Kreatur dieses Typs kürschnerbar sein (Wildtier, Drachkin)? Nur ein Hinweis, nicht jedes Tier ist es.
function DB:IsSkinnableType(typeID)
    return typeID == self.CREATURE_BEAST or typeID == self.CREATURE_DRAGONKIN
end
