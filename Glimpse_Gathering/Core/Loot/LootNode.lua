local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringData")

-- Abbau eines Sammelknotens erfassen (Namespace gathering):
--   node [Objekt]                 Versuch, je Zone
--   nodeloot:<Objekt> [Item]      Menge
--   nodedrop:<Objekt> [Item]      Beutefenster mit dem Item
--   herb / ore / other [Objekt]   eigener Sammelzähler, je Zone (Kategorie aus der Beute)
--   Ort (ID = Objekt)             Fundort mit Koordinaten; Orte näher als SPOT_RADIUS gibt es nur einmal

local ZoneOf = DB.collect.ZoneOf

-- Liegt schon ein eigener Ort dieses Knotens in der Nähe?
local function KnownPlace(ns, id, pos)
    local radius = DB.SPOT_RADIUS / 10000
    for _, place in ipairs(ns:GetLocations(pos.map, id, { sources = "own" })) do
        local dx, dy = place.x - pos.x, place.y - pos.y
        if dx * dx + dy * dy <= radius * radius then return true end
    end
    return false
end

local function ValidXY(pos)
    return type(pos.x) == "number" and type(pos.y) == "number" and pos.x > 0 and pos.x <= 1 and pos.y > 0 and pos.y <= 1
end

--- Beutefenster eines Knotens zählen. info = { name }, pos = { map, x, y } oder { instance, name }
-- (beides optional). items = { [itemID] = Menge }, nur Materialien.
function DB:RecordNode(id, info, items, pos)
    id = tonumber(id)
    local ns = self.ns
    if not (id and ns) then return end

    local zone = ZoneOf(pos)
    self:CountLoot(self.SECTIONS.node, id, items, zone)

    ns:Count(self:CategoryOf(items), id, zone)

    if info and info.name then self:SetNodeName(id, info.name) end
    if zone and zone < 0 then
        self:SetInstanceName(-zone, pos.name)
    elseif zone and ValidXY(pos) and not KnownPlace(ns, id, pos) then
        ns:AddLocation(id, pos.map, pos.x, pos.y)
    end
end
