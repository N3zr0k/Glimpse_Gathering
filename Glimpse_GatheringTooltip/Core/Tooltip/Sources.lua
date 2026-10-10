local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Symbol, Gruppe und Fundort einer Quelle im Tooltip eines Handwerksmaterials:
--
--   [Kräuter] Silberblatt (41, 57) - 120 yd                        93 %  Ø 1.4
--   [Pelz]    Waldwolf (Stufe 12) (Dunkelküste - 2300 yd - GatherMate2)  42 %  Ø 1.4
--
-- Fundort in Klammern, farblich abgesetzt (Zone/Entfernung hellblau, Koordinaten gelb wie TomTom).
-- Pro Quelle nur der beste Ort.

-- Texturpfade ohne Endung. Grüne Fehltextur im Spiel = Pfad fehlt im Client.
local ICON_PATH = "Interface\\Icons\\"
local ICONS = {
    loot = "INV_Misc_Bag_10",
    skinning = "INV_Misc_Pelt_Wolf_01",
    herb = "Trade_Herbalism",
    ore = "Trade_Mining",
    fishing = "Trade_Fishing",
    other = "INV_Misc_QuestionMark", -- Gas, Schätze, Holz ...
}

-- Welche Gruppe eine Quelle hat: Beute, Kürschnern, Kräuterkunde, Bergbau, Angeln oder "other" für die übrigen Knoten
local function GroupKey(source)
    if source.kind == "fishing" then return "fishing" end
    if source.kind == "node" then
        return ICONS[source.category] and source.category or "other"
    end
    return source.mode == "skinning" and "skinning" or "loot"
end

--- Texturpfad des Symbols einer Quelle: Beutel (Beute), Berufssymbol, sonst Fragezeichen
function GT:SourceIcon(source)
    return ICON_PATH .. ICONS[GroupKey(source)]
end

--- Gruppenüberschrift einer Quelle (Anzeige ohne Symbole): Schlüssel und Text, gleicher Schlüssel =
-- gleiche Überschrift
function GT:SourceGroup(source)
    local key = GroupKey(source)
    local titles = {
        loot = L["Loot"], skinning = L["Skinning"], herb = L["Herbalism"], ore = L["Mining"], fishing = L["Fishing"], other = L["Gathering"],
    }
    return key, titles[key]
end

local function PlaceName(self, spot)
    if spot.instance then return spot.name or format(L["Instance %d"], spot.instance) end
    return self.data:GetMapName(spot.map) or format(L["Map %d"], spot.map)
end

local function Tag(spot)
    if spot.source and spot.source ~= "own" then return spot.source end
end

--- Bester Fundort einer Quelle (source.spot) als Liste mit max. einem { zone, coords, distance, tag, here }:
--   Stufe 1 (eigenes Gebiet)   zone (mit here = true), coords und distance; in einer Instanz nur zone
--   Stufe 2 (gleicher Kontinent)  zone und distance (Luftlinie, wenn bekannt)
--   Stufe 3 (sonst)            zone (Zone oder Instanz)
--   Stufe 4                    nichts
-- tag = Anbietername bei rein externen Orten. showLocations aus: leer.
function GT:LocationList(source)
    local profile = self.db.profile
    local spot = source.spot
    if not profile.showLocations or not spot then return {} end

    local entry = { tag = Tag(spot), zone = PlaceName(self, spot) }
    if source.tier == 1 then
        entry.here = true -- hier befindest du dich
        if not spot.instance then
            if profile.showCoords and spot.x and spot.y then
                entry.coords = Glimpse:GetModule("Locations"):FormatCoords(spot.x, spot.y, 0)
            end
            if profile.showDistance and spot.distance then entry.distance = math.floor(spot.distance + 0.5) end
        end
    elseif source.tier == 2 or source.tier == 3 then
        if source.tier == 2 and profile.showDistance and spot.distance then entry.distance = math.floor(spot.distance + 0.5) end
    else
        return {}
    end
    return { entry }
end

-- Farben: Koordinaten gelb wie die Meldungen von TomTom, Zone hellblau, Entfernung weiß, Anbieter und Trenner grau
local LOCATION_COLOR = "|cff66ccff"
local COORD_COLOR = "|cffffff78"
local DISTANCE_COLOR = "|cffffffff"
local TAG_COLOR = "|cff999999"

local function Colored(color, text)
    return color .. text .. "|r"
end

-- Markierung für den eigenen Ort: Media/Markers (Symbol_Farbe.tga, 64x64), je Farbe vorgefertigt, da
-- Tooltips Texturen nicht sicher einfärben. Optionen: showHereIcon, hereIcon, hereColor.
local MEDIA_PATH = "Interface\\AddOns\\Glimpse_GatheringTooltip\\Media\\Markers\\"

-- Symbole in der Reihenfolge der Auswahl; size ist die Höhe im Tooltip in Pixel
GT.MarkerIcons = {
    { key = "pin", size = 11 },
    { key = "pinsolid", size = 11 },
    { key = "pinline", size = 11 },
    { key = "person", size = 11 },
    { key = "arrow", size = 10 },
}
GT.MarkerColors = { "blue", "white", "yellow", "green", "red" }

-- Bildnachweis der Symbole (Flaticon, Namensnennung): Media/Markers/CREDITS.md und README.md.

local DEFAULT_ICON = "pinsolid"

local function FindIcon(key)
    local default
    for _, icon in ipairs(GT.MarkerIcons) do
        if icon.key == key then return icon end
        if icon.key == DEFAULT_ICON then default = icon end
    end
    return default
end

local function FindColor(key)
    for _, color in ipairs(GT.MarkerColors) do
        if color == key then return key end
    end
    return GT.MarkerColors[1]
end

--- Texturpfad eines Symbols in einer Farbe (für die Optionen); ohne Angaben die gewählten Werte
function GT:MarkerPath(iconKey, colorKey)
    local profile = self.db.profile
    local icon = FindIcon(iconKey or profile.hereIcon)
    return MEDIA_PATH .. icon.key .. "_" .. FindColor(colorKey or profile.hereColor) .. ".tga", icon.size
end

--- Text der Markierung für den eigenen Ort (mit Leerzeichen dahinter), leer wenn sie ausgeschaltet ist
function GT:HereIcon()
    if self.db.profile.showHereIcon == false then return "" end
    local path, size = self:MarkerPath()
    return "|T" .. path .. ":" .. size .. "|t "
end

--- Koordinaten als gelber Text in Klammern, (41, 57); nil ohne Koordinaten
function GT:FormatCoords(entry)
    if entry.coords then return Colored(COORD_COLOR, "(" .. entry.coords .. ")") end
end

--- Entfernung in der in Glimpse gewählten Einheit (Yards/Meter, Standard nach Client-Sprache). Rechnung im Kern.
function GT:FormatDistance(yards)
    return Glimpse:GetModule("Locations"):FormatDistance(yards)
end

--- Ort als Text, z. B. (Loch Modan - 2288 yd - GatherMate2): Zone blau, Entfernung weiß, Anbieter grau,
-- eigener Ort mit Markierung davor.
function GT:FormatPlace(entry)
    local separator = Colored(TAG_COLOR, " - ")
    local parts = {}
    if entry.zone then tinsert(parts, Colored(LOCATION_COLOR, entry.zone)) end
    if entry.distance then tinsert(parts, Colored(DISTANCE_COLOR, self:FormatDistance(entry.distance))) end
    if entry.tag then tinsert(parts, Colored(TAG_COLOR, entry.tag)) end
    return (entry.here and self:HereIcon() or "") .. Colored(LOCATION_COLOR, "(") .. table.concat(parts, separator)
        .. Colored(LOCATION_COLOR, ")")
end

-- ---------------------------------------------------------------------------
-- Tabelle: Name, Koordinaten und Zone stehen in allen Quellen untereinander
-- ---------------------------------------------------------------------------

-- Tooltips haben nur zwei Spalten. Die linken Spalten entstehen durch Messen und Auffüllen mit Leerzeichen:
--
--   [Symbol] Silberblatt             (41, 57)  [Pin] (Dun Morogh - 120 yd)
--   [Symbol] Waldwolf (Stufe 12)               (Dunkelküste - 2300 yd - GatherMate2)
--
-- Gemessen wird mit einer unsichtbaren Textzeile im Tooltip-Font, ohne sie (Tests) per Zeichenzahl.

local GAP = 8 -- Abstand zwischen den Spalten in Pixel

local meter
local function Meter()
    if meter == nil then
        meter = false
        if UIParent and UIParent.CreateFontString then
            local ok, fontString = pcall(UIParent.CreateFontString, UIParent, nil, "ARTWORK", "GameTooltipText")
            if ok and fontString then
                fontString:Hide()
                meter = fontString
            end
        end
    end
    return meter or nil
end

-- Breite eines Textes in Pixel (ohne die Farbcodes)
function GT.Measure(text)
    local fontString = Meter()
    if fontString then
        local ok, width = pcall(function()
            fontString:SetText(text)
            return fontString:GetStringWidth()
        end)
        if ok and type(width) == "number" then return width end
    end

    -- Ersatz: ein Zeichen = eine Einheit
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return #text:gsub("[\128-\191]", "")
end

-- Leerzeichen, die so breit sind wie width Pixel (mindestens keines)
local function Pad(width)
    local space = GT.Measure("a a") - GT.Measure("aa")
    if type(space) ~= "number" or space <= 0 then space = 4 end
    return string.rep(" ", math.max(0, math.floor(width / space + 0.5)))
end

--- Richtet Fundorte mehrerer Quellen als Tabelle aus. items: { name, locations } (aus LocationList, max.
-- ein Eintrag), setzt je Eintrag text. Ohne Koordinaten bleibt die Spalte leer, die Orte stehen trotzdem untereinander.
function GT:AlignLocations(items)
    local nameWidth, coordWidth = 0, 0
    for _, item in ipairs(items) do
        nameWidth = math.max(nameWidth, GT.Measure(item.name))
        local location = item.locations[1]
        local coords = location and self:FormatCoords(location)
        if coords then coordWidth = math.max(coordWidth, GT.Measure(coords)) end
    end

    local hereWidth = GT.Measure(self:HereIcon())
    local hasHere = false
    for _, item in ipairs(items) do
        local location = item.locations[1]
        if location and location.here then hasHere = true end
    end

    for _, item in ipairs(items) do
        item.text = item.name
        local location = item.locations[1]
        if location then
            local coords = self:FormatCoords(location)
            local text = item.name .. Pad(nameWidth - GT.Measure(item.name) + GAP)
            if coordWidth > 0 then
                text = text .. (coords or "") .. Pad(coordWidth - (coords and GT.Measure(coords) or 0) + GAP)
            end
            -- der Ort der anderen Zeilen rückt so weit ein wie die Markierung breit ist
            if hasHere and not location.here then text = text .. Pad(hereWidth) end
            item.text = text .. self:FormatPlace(location)
        end
    end
end
