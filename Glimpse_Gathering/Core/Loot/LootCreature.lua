local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")

-- Beute einer Kreatur erfassen (Namespace gathering):
--   npc [NPC]                  geplünderte Leiche, auch leer (Kill ohne Beutefenster, LootKills.lua); je Zone
--   npcloot:<NPC> [Item]       Menge
--   npcdrop:<NPC> [Item]       Beutefenster mit dem Item
-- Kürschnern steht in LootSkinning.lua. Kreaturen haben keine Orte, nur Zonen.

local ZoneOf = DB.collect.ZoneOf

--- Name, Stufe und Instanzname merken; gibt die Zone des Fundorts zurück (auch für LootSkinning.lua)
function DB:RememberNPC(id, info, pos)
    if info then self:SetNPCName(id, info.name, info.level) end
    local zone = ZoneOf(pos)
    if zone and zone < 0 then self:SetInstanceName(-zone, pos.name) end
    return zone
end

--- Beutefenster einer Kreatur zählen. kind = "loot" oder "skinning" (LootSkinning.lua), info = { name, level },
-- pos = { map, x, y } oder { instance, name } (beides optional), items = { [itemID] = Menge }.
function DB:RecordNPC(id, kind, info, items, pos)
    if kind == "skinning" then return self:RecordSkinning(id, info, items, pos) end
    id = tonumber(id)
    if not (id and self.ns) then return end

    self:CountLoot(self.SECTIONS.loot, id, items, self:RememberNPC(id, info, pos))
end

--- Beute zu einem schon gezählten Versuch (Kill ohne Fenster, später gelootet). Kein neuer Versuch.
function DB:AddNPCItems(id, items)
    id = tonumber(id)
    if id then self:CountItems(self.SECTIONS.loot, id, items) end
end
