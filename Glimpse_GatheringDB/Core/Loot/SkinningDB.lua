local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Kürschnern erfassen (Namespace gathering):
--   skinned [NPC]              gekürschnerte Leiche (Weltwissen), je Zone
--   skinloot:<NPC> [Item]      Menge
--   skindrop:<NPC> [Item]      Beutefenster mit dem Item
--   skin [NPC]                 eigener Sammelzähler, je Zone

--- Kürschnerbeute einer Kreatur zählen. info = { name, level }, pos und items wie bei RecordNPC.
function DB:RecordSkinning(id, info, items, pos)
    id = tonumber(id)
    local ns = self.ns
    if not (id and ns) then return end

    local zone = self:RememberNPC(id, info, pos)
    self:CountLoot(self.SECTIONS.skinning, id, items, zone)
    ns:Count("skin", id, zone)
end
