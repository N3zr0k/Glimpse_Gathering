local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Alle Blizzard-Funktionen, die GatheringDB braucht, an einer Stelle. Je nach Clientstand liegen
-- sie global oder in einem C_-Namespace; ändert sich das, muss nur diese Datei angepasst werden.
-- Fehlt eine Funktion ganz, bleibt der Eintrag nil und DB:CheckAPI() meldet es beim Start.
local NAMES = {
    "GetItemInfoInstant", "GetNumLootItems", "GetLootSlotType", "GetLootSlotLink", "GetLootSourceInfo",
}

DB.api = {
    GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant,
    GetNumLootItems = (C_Loot and C_Loot.GetNumLootItems) or GetNumLootItems,
    GetLootSlotType = (C_Loot and C_Loot.GetLootSlotType) or GetLootSlotType,
    GetLootSlotLink = (C_Loot and C_Loot.GetLootSlotLink) or GetLootSlotLink,
    GetLootSourceInfo = (C_Loot and C_Loot.GetLootSourceInfo) or GetLootSourceInfo,

    -- Angeln: erkennt das Beutefenster eines Fangs (für Forever dokumentiert, https://warcraft.wiki.gg/wiki/API_IsFishingLoot).
    -- Nicht in NAMES: fehlt sie, bleibt nur die Angelbeute unerfasst.
    IsFishingLoot = IsFishingLoot,

    -- Berufe und Skill (Data/Skills.lua). Nicht in NAMES: ohne sie gibt es nur keine Skill-Anzeige, die Aufzeichnung
    -- läuft weiter. Je nach Clientstand gibt es GetProfessionInfo oder (Classic) GetSkillLineInfo.
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

--- Prüft, ob alle benötigten Funktionen vorhanden sind. Gibt true zurück oder false und die
-- Liste der fehlenden Namen.
function DB:CheckAPI()
    -- Über die Namensliste gehen: fehlende Einträge stehen als nil gar nicht in der Tabelle
    local missing = {}
    for _, name in ipairs(NAMES) do
        if type(self.api[name]) ~= "function" then tinsert(missing, name) end
    end
    return #missing == 0, missing
end
