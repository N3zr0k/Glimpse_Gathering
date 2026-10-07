local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Benötigter Sammel-Skill in den Tooltips von Knoten und Kreaturen, nur die Zahl des eigenen Skills hat die Farbe:
--
--   [Symbol] Stufe: 162 - benötigt Bergbau 155
--   [Symbol] Stufe: 140 - eventuell benötigt Kürschnerei 125   (nur nach Kreaturentyp vermutet)
--
-- Zahlen, Farben und der Skill des Spielers liefert GatheringDB (GetRequiredSkill, GetSkillColor, GetPlayerSkill),
-- hier wird nur die Zeile gebaut.

local GREY = { 0.60, 0.60, 0.60 }

local PROFESSION_LABEL = { herb = "Herbalism", ore = "Mining", skinning = "Skinning", fishing = "Fishing" }

local function Colored(text, r, g, b)
    return format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

-- Steht die Anforderung schon im Tooltip (Zeile mit Berufsname und der Zahl)? Dann kommt keine zweite Zeile dazu.
-- Zeilentexte können secret sein, die werden übergangen (wie in Glimpse: LastLineIs).
-- Die eigene Zeile (own) zählt nicht, falls der Tooltip nur erneut verarbeitet wird und sie schon dasteht.
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

-- Auf einem toten, kürschnerbaren Tier schreibt der Client selbst "Häutbar" in den Tooltip, in einer Farbe, die zum
-- Skill des Spielers passt. Der Text kommt aus der globalen Zeichenkette UNIT_SKINNABLE_LEATHER (sprachunabhängig, fehlt
-- sie im Client, bleibt es beim Berechneten). Gibt die Farbe dieser Zeile zurück, nil wenn es sie nicht gibt.
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

-- Baut die Zeile. required = benötigter Skill, profession = "herb", "ore" oder "skinning", guess = die Kreatur ist nur
-- nach ihrem Typ als kürschnerbar vermutet. Rückgabe: Zeile und Name des Berufs, oder nil (Anzeige aus, Beruf nicht
-- gelernt, graue Knoten ausgeblendet). color = {r, g, b}: Farbe vom Client statt der berechneten.
function GT:BuildSkillRow(profession, required, guess, color)
    local profile, db = self.db.profile, self.data

    local current, _, clientName = db:GetPlayerSkill(profession)
    local learned = db:HasProfession(profession)
    if learned == false and profile.skillOnlyLearned then return nil end

    -- Nach dem Namen aus dem Client (heißt er dort anders, stimmt er mit dem Tooltip überein), sonst die Übersetzung
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

--- Zeile für den Schwimmer: Symbol, Beruf und dein Angel-Skill mit Maximum, z. B. "Angeln 1/75".
function GT:FishingRow()
    local profile, db = self.db.profile, self.data
    if not profile.showNodeSkill then return nil end

    local current, maximum, clientName = db:GetPlayerSkill("fishing")
    local learned = db:HasProfession("fishing")
    if learned == false and profile.skillOnlyLearned then return nil end

    local label = clientName or L["Fishing"]
    local text = label
    if current then
        text = format(L["%s %d/%d"], label, current, maximum)
    elseif learned == false then
        text = format(L["%s - not learned"], label)
    end
    return { text, "", 1, 1, 1, icon = self:SourceIcon({ kind = "fishing" }) }
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

--- Zeile für eine Kreatur. Nur wenn sie als kürschnerbar bekannt ist oder ihr Typ (Wildtier, Drachkin) es nahelegt,
-- im zweiten Fall als Vermutung.
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
    if native then
        known = true
    elseif not known then
        -- unbekannt: nur bei einem Typ, der Kürschnerei erlauben kann
        if not (unit and db:IsSkinnableType(db:GetCreatureTypeID(unit))) then return nil end
        guess = true
    end

    local row, label = self:BuildSkillRow("skinning", required, guess, native)
    if row and AlreadyShown(tooltip, label, required, row[1]) then return nil end
    return row
end
