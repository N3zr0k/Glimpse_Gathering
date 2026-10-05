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
}

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
