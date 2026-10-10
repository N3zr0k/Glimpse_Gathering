local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")

-- Alle Blizzard-Funktionen für den Datenteil an einer Stelle (global oder C_-Namespace je nach Client).
-- Fehlende bleiben nil, DB:CheckAPI() meldet sie beim Start.
local NAMES = {
    "GetItemInfoInstant", "GetNumLootItems", "GetLootSlotType", "GetLootSlotLink", "GetLootSourceInfo",
}

DB.api = {
    GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant,
    GetNumLootItems = (C_Loot and C_Loot.GetNumLootItems) or GetNumLootItems,
    GetLootSlotType = (C_Loot and C_Loot.GetLootSlotType) or GetLootSlotType,
    GetLootSlotLink = (C_Loot and C_Loot.GetLootSlotLink) or GetLootSlotLink,
    GetLootSourceInfo = (C_Loot and C_Loot.GetLootSourceInfo) or GetLootSourceInfo,

    -- Erkennt Angelbeute (https://warcraft.wiki.gg/wiki/API_IsFishingLoot), die hier nicht zählt (Angeln erfasst
    -- Glimpse: Professions). Nicht in NAMES: fehlt sie, kann Angelbeute als Knoten zählen.
    IsFishingLoot = IsFishingLoot,

    -- Berufe/Skill (Core/Data/Skills.lua): GetProfessionInfo bzw. GetSkillLineInfo (Classic). Nicht in NAMES:
    -- fehlen sie, entfällt nur die Skill-Anzeige. Zaubernamen auch für die Erkennung des Kürschnerns.
    GetProfessions = GetProfessions,
    GetProfessionInfo = GetProfessionInfo,
    GetNumSkillLines = GetNumSkillLines,
    GetSkillLineInfo = GetSkillLineInfo,
    GetSpellName = C_Spell and C_Spell.GetSpellName or nil,
    GetSpellInfo = GetSpellInfo,
    UnitCreatureType = UnitCreatureType,
    GetCreatureTypeInfo = C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo or nil,

    -- Namen von Kreaturen aus dem Client-Cache (Core/Data/Names.lua). Fehlt sie, bleibt "Kreatur 123".
    GetHyperlinkInfo = C_TooltipInfo and C_TooltipInfo.GetHyperlink or nil,

    -- Nur für den Hinweis auf alte Addon-Ordner
    IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded,
}

-- Karten, Position und Entfernungen kommen aus dem Glimpse-Modul Locations.

--- true, oder false und die Liste der fehlenden Namen
function DB:CheckAPI()
    -- Über NAMES gehen, nil-Einträge fehlen in der Tabelle
    local missing = {}
    for _, name in ipairs(NAMES) do
        if type(self.api[name]) ~= "function" then tinsert(missing, name) end
    end
    return #missing == 0, missing
end
