local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Symbol, Gruppe und Fundort einer Quelle im Tooltip eines Handwerksmaterials:
--
--   [Kräuter] Silberblatt (41, 57 · 120 yd)            93 %  Ø 1.4
--   [Pelz]    Waldwolf (Stufe 12) (Dunkelküste)        42 %  Ø 1.4
--                                 (Düsterwald)
--
-- Der Fundort steht in Klammern und in eigenen Farben (Zone und Entfernung hellblau, Koordinaten gelb wie
-- bei TomTom), damit er sich vom Namen und von der Stufe abhebt. Mehrere Orte gibt es nur bei verschiedenen
-- Zonen, jede in einer eigenen Zeile.

-- Symbole (Texturpfade ohne Endung). Fehlt eines im Client, zeigt das Spiel die grüne Fehltextur:
-- dann hier den Pfad ändern.
local ICON_PATH = "Interface\\Icons\\"
local ICONS = {
    loot = "INV_Misc_Bag_10",
    skinning = "INV_Misc_Pelt_Wolf_01",
    herb = "Trade_Herbalism",
    ore = "Trade_Mining",
    other = "INV_Misc_QuestionMark", -- Gas, Schätze, Holz ...
}

-- Welche Gruppe eine Quelle hat: Beute, Kürschnern, Kräuterkunde, Bergbau oder "other" für die übrigen Knoten
local function GroupKey(source)
    if source.kind == "node" then
        return ICONS[source.category] and source.category or "other"
    end
    return source.mode == "skinning" and "skinning" or "loot"
end

--- Symbol einer Quelle: Beutel für Beute, Berufssymbole für Kürschnern, Kräuterkunde und Bergbau,
-- ein Fragezeichen für die übrigen Knotenarten. Gibt den Texturpfad zurück.
function GT:SourceIcon(source)
    return ICON_PATH .. ICONS[GroupKey(source)]
end

--- Überschrift der Gruppe einer Quelle (für die Anzeige ohne Symbole): Beute, Kürschnern, Kräuterkunde ...
-- Gibt Schlüssel und Text zurück, gleiche Schlüssel gehören unter eine Überschrift.
function GT:SourceGroup(source)
    local key = GroupKey(source)
    local titles = {
        loot = L["Loot"], skinning = L["Skinning"], herb = L["Herbalism"], ore = L["Mining"], other = L["Gathering"],
    }
    return key, titles[key]
end

local MAX_PLACES = 3

local function InArea(spot)
    return spot.here == true or spot.mapDistance ~= nil
end

local function PlaceName(self, spot)
    if spot.instance then return spot.name or format(L["Instance %d"], spot.instance) end
    return self.data:GetMapName(spot.map) or format(L["Map %d"], spot.map)
end

local function PlaceKey(spot)
    return spot.instance and ("i" .. spot.instance) or ("m" .. spot.map)
end

local function Tag(spot)
    if spot.source and spot.source ~= "own" then return spot.source end
end

--- Fundorte einer Quelle (Eintrag aus GetLocatedItemSources) als Liste von Einträgen
-- { zone, coords, distance, tag, more }, leer wenn nichts anzuzeigen ist:
--   1. der nächste Ort im eigenen Gebiet (coords, distance), wenn die Quelle "here" ist oder ihre Orte nur von
--      anderen Addons kommen und einer davon im eigenen Gebiet liegt (in der eigenen Instanz entfällt er)
--   2. die Orte in anderen Gebieten (zone = Name der Zone oder Instanz), jede Zone einmal
-- tag ist der Name des anderen Addons bei fremden Orten, more die Zahl weiterer Zonen (nur bei "nearest").
-- Option locationLines: "off", "nearest" (ein Eintrag) oder "several" (bis zu drei Einträge, jeweils eine andere Zone).
function GT:LocationList(source)
    local profile = self.db.profile
    local mode = profile.locationLines
    if mode == "off" or not source.spots or #source.spots == 0 then return {} end

    local nearest, elsewhere, seen = nil, {}, {}
    for _, spot in ipairs(source.spots) do
        if InArea(spot) then
            nearest = nearest or spot
        else
            local key = PlaceKey(spot)
            if not seen[key] then
                seen[key] = true
                tinsert(elsewhere, spot)
            end
        end
    end

    -- Der nächste Ort im eigenen Gebiet (nur Koordinaten und Entfernung, die Zone kennt der Spieler)
    local first
    if source.area == "here" or (source.area == "external" and nearest) then
        -- in einer Instanz, in der man steht, gibt es nichts zu zeigen
        if nearest and not nearest.instance then
            local entry = { tag = Tag(nearest) }
            if profile.showCoords and nearest.x and nearest.y then
                entry.coords = format("%d, %d", math.floor(nearest.x * 100 + 0.5), math.floor(nearest.y * 100 + 0.5))
            end
            if profile.showDistance and nearest.distance then entry.distance = math.floor(nearest.distance + 0.5) end
            if entry.coords or entry.distance then first = entry end
        end
    elseif source.area ~= "elsewhere" and source.area ~= "external" then
        return {}
    end

    -- dazu die anderen Zonen, jede einmal: ein Eintrag bei "nearest" (nur wenn es keinen eigenen Ort gibt),
    -- bis zu drei insgesamt bei "several"
    local list = { first }
    for _, spot in ipairs(elsewhere) do
        if mode == "several" then
            if #list >= MAX_PLACES then break end
            tinsert(list, { zone = PlaceName(self, spot), tag = Tag(spot) })
        elseif not first and #list == 0 and source.area ~= "here" then
            tinsert(list, { zone = PlaceName(self, spot), tag = Tag(spot) })
        end
    end
    -- bei "nearest": wie viele weitere Zonen es gibt
    if mode ~= "several" and list[1] then
        local more = #elsewhere - (first and 0 or 1)
        if more > 0 then list[1].more = more end
    end
    return list
end

-- Farben: Zone, Entfernung und Klammern hellblau, Koordinaten gelb wie die Meldungen von TomTom
local LOCATION_COLOR = "|cff66ccff"
local COORD_COLOR = "|cffffff78"

local function Colored(color, text)
    return color .. text .. "|r"
end

--- Ein Eintrag aus LocationList als Text mit Klammern und Farben
function GT:FormatLocation(entry)
    local parts = {}
    if entry.zone then tinsert(parts, Colored(LOCATION_COLOR, entry.zone)) end
    if entry.coords then tinsert(parts, Colored(COORD_COLOR, entry.coords)) end
    if entry.distance then tinsert(parts, Colored(LOCATION_COLOR, format(L["%d yd"], entry.distance))) end
    if entry.tag then tinsert(parts, Colored(LOCATION_COLOR, entry.tag)) end

    local separator = Colored(LOCATION_COLOR, " · ")
    local more = entry.more and Colored(LOCATION_COLOR, "  +" .. entry.more) or ""
    return Colored(LOCATION_COLOR, "(") .. table.concat(parts, separator) .. more .. Colored(LOCATION_COLOR, ")")
end
