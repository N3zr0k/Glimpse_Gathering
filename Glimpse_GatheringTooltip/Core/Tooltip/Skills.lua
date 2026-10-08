local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Benötigter Sammel-Skill in Knoten-/Kreatur-Tooltips, nur der eigene Skill ist eingefärbt:
--
--   [Symbol] Stufe: 162 - benötigt Bergbau 155
--   [Symbol] Stufe: 140 - eventuell benötigt Kürschnerei 125   (nur nach Kreaturentyp vermutet)
--
-- Zahlen und Farben liefert GatheringDB (GetRequiredSkill, GetSkillColor, GetPlayerSkill).

local PROFESSION_LABEL = { herb = "Herbalism", ore = "Mining", skinning = "Skinning", fishing = "Fishing" }

local function Colored(text, r, g, b)
    return format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

-- Anforderung schon im Tooltip (Berufsname plus Zahl)? Dann keine zweite Zeile. Secret-Texte werden
-- übergangen (wie Glimpse: LastLineIs), die eigene Zeile (own) zählt nicht (erneute Verarbeitung).
local function AlreadyShown(tooltip, label, required, own)
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    if not name or not tooltip.NumLines then return false end

    local count = tooltip:NumLines()
    if Glimpse:IsSecret(count) then return false end

    for index = 1, count do
        local line = _G[name .. "TextLeft" .. index]
        local text = line and line:GetText()
        if type(text) == "string" and not Glimpse:IsSecret(text) and not text:find(own, 1, true) then
            -- die Zahl nur als ganzes Wort, sonst passt "15" auch auf "150"
            if text:find(label, 1, true) and text:find("%f[%d]" .. required .. "%f[%D]") then return true end
        end
    end
    return false
end

-- Auf toten, kürschnerbaren Tieren schreibt der Client selbst UNIT_SKINNABLE_LEATHER ("Häutbar") in
-- Skill-Farbe. Gibt diese Farbe zurück, true wenn nicht lesbar, nil ohne die Zeile.
local function NativeSkinnable(tooltip)
    local skinnable = _G.UNIT_SKINNABLE_LEATHER
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    if type(skinnable) ~= "string" or not name or not tooltip.NumLines then return nil end

    local count = tooltip:NumLines()
    if Glimpse:IsSecret(count) then return nil end

    for index = 1, count do
        local line = _G[name .. "TextLeft" .. index]
        local text = line and line:GetText()
        if text == skinnable and not Glimpse:IsSecret(text) then
            local ok, r, g, b = pcall(line.GetTextColor, line)
            if ok and type(r) == "number" and type(g) == "number" and type(b) == "number"
                and not (Glimpse:IsSecret(r) or Glimpse:IsSecret(g) or Glimpse:IsSecret(b)) then
                return { r, g, b }
            end
            return true -- Zeile da, Farbe nicht lesbar
        end
    end
end

-- Die Einheit zu einer GUID: Maus oder Ziel, damit Stufe und Kreaturentyp live gelesen werden können.
local function UnitOf(guid)
    if type(guid) ~= "string" then return nil end
    for _, unit in ipairs({ "mouseover", "target" }) do
        local ok, current = pcall(UnitGUID, unit)
        if ok and type(current) == "string" and not Glimpse:IsSecret(current) and current == guid then return unit end
    end
end

-- Baut die Zeile. profession = "herb", "ore" oder "skinning", guess = nur nach Kreaturentyp vermutet,
-- color = {r, g, b} vom Client statt berechnet. Gibt Zeile und Berufsname zurück, oder nil (aus, nicht
-- gelernt, grau ausgeblendet).
function GT:BuildSkillRow(profession, required, guess, color)
    local profile, db = self.db.profile, self.data

    local current, _, clientName = db:GetPlayerSkill(profession)
    local learned = db:HasProfession(profession)
    if learned == false and profile.skillOnlyLearned then return nil end

    -- Client-Name bevorzugen (passt zum Tooltip-Text), sonst die Übersetzung
    local label = clientName or L[PROFESSION_LABEL[profession]]
    local icon = self:SourceIcon(profession == "skinning" and { kind = "npc", mode = "skinning" } or { kind = "node", category = profession })

    local text
    if current then
        local key, r, g, b = db:GetSkillColor(required, current)
        if key == "gray" and profile.hideGraySkill then return nil end
        if type(color) == "table" then r, g, b = color[1], color[2], color[3] end
        text = format(guess and L["Skill: %s - possibly requires %s %d"] or L["Skill: %s - requires %s %d"],
            Colored(current, r, g, b), label, required)
    elseif learned == false then
        text = format(L["not learned - requires %s %d"], label, required)
    else
        text = format(L["Requires %s %d"], label, required)
    end

    return { text, "", 1, 1, 1, icon = icon }, label
end

--- Zeile für einen Knoten (Objekt-ID oder Name, wenn der Tooltip keine ID mitbringt), nil wenn nichts anzuzeigen ist.
function GT:NodeSkillRow(id, name, tooltip)
    if not self.db.profile.showNodeSkill then return nil end

    id = id or self.data:FindNodeIDs(name)[1]
    local profession, required = self.data:GetRequiredSkill("node", id)
    if not profession then return nil end

    local row, label = self:BuildSkillRow(profession, required)
    if row and AlreadyShown(tooltip, label, required, row[1]) then return nil end
    return row
end

--- Zeile für eine Kreatur: wenn als kürschnerbar bekannt, sonst als Vermutung nach Typ (Wildtier, Drachkin).
function GT:UnitSkillRow(id, data, tooltip)
    if not self.db.profile.showMobSkill then return nil end

    local db = self.data
    local unit = UnitOf(data.guid)

    -- Stufe der Kreatur vor Ort, sonst die gespeicherte (Boss = -1 oder unbekannt: keine Angabe)
    local level
    if unit then
        local ok, value = pcall(UnitLevel, unit)
        if ok and type(value) == "number" and not Glimpse:IsSecret(value) then level = value end
    end
    local _, required, known = db:GetRequiredSkill("npc", id, level)
    if not required then return nil end

    -- "Häutbar" im Tooltip des Clients: sicher kürschnerbar, und der Client gibt die Farbe vor
    local native = NativeSkinnable(tooltip)
    local guess = false
    if not native and not known then
        -- unbekannt: nur bei einem Typ, der Kürschnerei erlauben kann
        if not (unit and db:IsSkinnableType(db:GetCreatureTypeID(unit))) then return nil end
        guess = true
    end

    local row, label = self:BuildSkillRow("skinning", required, guess, native)
    if row and AlreadyShown(tooltip, label, required, row[1]) then return nil end
    return row
end
