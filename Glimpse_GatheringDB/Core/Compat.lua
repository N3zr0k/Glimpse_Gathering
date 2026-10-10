local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Alle Blizzard-Funktionen für GatheringDB an einer Stelle (global oder C_-Namespace je nach Client).
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
