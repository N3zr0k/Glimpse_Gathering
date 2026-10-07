local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local Locations = Glimpse:GetModule("Locations")

-- Blizzard-Funktionen kommen gesammelt aus Core/Compat.lua
local api = DB.api

-- Erfasst beim Öffnen eines Beutefensters, aus welcher Quelle (Sammelknoten oder Kreatur) welche
-- Items kamen. Eine Quelle zählt als ein Versuch.
--
-- Gespeichert werden nur Handwerksmaterialien (Handwerkswaren und Edelsteine), alles andere
-- (Rüstung, Waffen, Müll) fällt weg. Jede gelootete Kreatur zählt trotzdem als Versuch, auch wenn
-- kein Material dabei war, sonst wäre die Chance zu hoch.
--
-- Angelbeute hat keine feste Quelle (die Quelle des Beutefensters ist der Schwimmer oder ein Schwarm). Sie wird über
-- IsFishingLoot erkannt und je Zone gezählt (siehe ProcessFishing). Gespeichert werden auch hier nur Handwerksmaterialien.
-- Jedes Auswerfen zählt als Versuch, der Fang macht ihn zum Treffer (OnFishingStart).

-- Zeitfenster in Sekunden: so kurz muss ein Zauber vor dem Beutefenster erfolgreich gewesen sein,
-- damit das Fenster als Ergebnis dieses Zaubers gilt (Kürschnern, Pflücken, Bergbau)
local CAST_WINDOW = 1.0

-- Wie lange der Zielname eines Zaubers für einen Sammelknoten verwendet werden darf
local TARGET_WINDOW = 15

-- Obergrenze der Merkliste, danach wird sie geleert
local MAX_REMEMBERED = 2000

-- Wie lange dieselbe Kreatur nicht noch einmal zählt (Teilloot, mehrfaches Öffnen des Fensters).
-- Danach zählt sie neu: eine Kreatur, die mit derselben GUID wiederkommt, ist eine neue Leiche.
-- Eine Leiche bleibt einige Minuten liegen (Kürschnern). Sammelknoten zählen dagegen pro Zauber
-- (siehe nodeMark): derselbe Knoten kann mehrmals abgebaut werden und wächst mit gleicher GUID nach.
local CREATURE_REPEAT = 600

-- Bis wie viele Sekunden nach dem Absenden eines Zaubers ein Beutefenster eines Objekts als dessen
-- Ergebnis gilt, auch wenn kein UNIT_SPELLCAST_SUCCEEDED gesehen wurde (Sammelzauber dauern wenige Sekunden)
local SENT_WINDOW = 10

-- Kreaturen ohne Beute: so lange nach dem Tod auf ein Beutefenster warten, bevor der Kill als
-- Versuch zählt (KILL_CHECK_DELAY: wann CanLootUnit gefragt wird)
local KILL_CHECK_DELAY = 1.5
local KILL_FALLBACK = 120

local LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

-- Item-Klassen, die als Handwerksmaterial gelten: Handwerkswaren (Stoff, Leder, Erz, Kräuter,
-- Kochzutaten ...) und Edelsteine. Fallback-Zahlen, falls die Enums fehlen.
local ItemClass = Enum and Enum.ItemClass or {}
local TRADEGOODS = ItemClass.Tradegoods or 7
local MATERIAL_CLASSES = {
    [TRADEGOODS] = true,
    [ItemClass.Gem or 3] = true,
}

-- Unterklassen der Handwerkswaren, nur für die Kategorie eines Knotens
local SUBCLASS = Enum and Enum.ItemTradeGoodsSubclass or {}
local HERB = SUBCLASS.Herb or 9
local METAL_STONE = SUBCLASS.MetalStone or 7

local lastSuccess, lastSent, lastTarget, lastTargetTime = 0, -1000, nil, 0

-- Quellen, die zuletzt gezählt wurden: Schlüssel -> Zeitpunkt. Verhindert doppeltes Zählen, wenn das
-- Beutefenster erneut aufgeht (Teilloot). Der Schlüssel enthält die Art, damit Normalbeute und
-- Kürschnerbeute derselben Leiche getrennt zählen.
local counted = {}
local countedSize = 0

-- Sammelknoten: GUID -> Zeitpunkt des Zaubers, der zuletzt gezählt wurde. Ein Beutefenster zählt nur,
-- wenn seitdem ein neuer Zauber kam. So zählt jeder Abbau (auch mehrere am selben Knoten, auch nach
-- dem Nachwachsen), ein erneut geöffnetes Fenster desselben Abbaus aber nicht.
local nodeMark = {}
local nodeMarkSize = 0

-- Kreaturen, deren Normalbeute schon gezählt wurde (GUID -> Zeitpunkt). Wird sie ein zweites Mal
-- gelootet, ist es Kürschnerbeute.
local looted = {}

-- Kreaturen, die wir kurz nach dem Tod erschlagen haben (GUID -> Zeitpunkt), und solche, die ohne
-- Beutefenster schon als leerer Versuch gezählt wurden
local pendingKills = {}
local killCounted = {}

local function Clean(value)
    if value ~= nil and Glimpse:IsSecret(value) then return nil end
    return value
end

-- "Creature-0-3131-2552-14367-179891-0000A5C2B1" -> "Creature", 179891
local function ParseGUID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

local function ItemID(link)
    link = Clean(link)
    return link and tonumber(strmatch(link, "item:(%d+)"))
end

-- true, wenn das Item ein Handwerksmaterial ist. GetItemInfoInstant braucht keine geladenen
-- Item-Daten, es muss nichts nachgeladen werden.
local function IsMaterial(itemID)
    local _, _, _, _, _, classID = api.GetItemInfoInstant(itemID)
    return MATERIAL_CLASSES[classID] == true
end

-- Liest das offene Beutefenster: guid -> { [itemID] = Menge }, nur Materialien.
-- Jede Quelle taucht auf, auch wenn kein Material dabei war (leere Tabelle), denn sie zählt als Versuch.
local function ReadLoot()
    local bySource = {}

    for slot = 1, api.GetNumLootItems() do
        -- Rückgabe: guid1, menge1, guid2, menge2 ... (mehrere bei Flächenbeute)
        local info = { api.GetLootSourceInfo(slot) }
        local itemID = api.GetLootSlotType(slot) == LOOT_ITEM and ItemID(api.GetLootSlotLink(slot)) or nil
        if itemID and not IsMaterial(itemID) then itemID = nil end

        for i = 1, #info, 2 do
            local guid, amount = Clean(info[i]), tonumber(Clean(info[i + 1])) or 1

            if type(guid) == "string" then
                local items = bySource[guid]
                if not items then
                    items = {}
                    bySource[guid] = items
                end
                if itemID then items[itemID] = (items[itemID] or 0) + amount end
            end
        end
    end

    return bySource
end

-- Liest das Beutefenster eines Fangs: { [itemID] = Menge }, nur Handwerksmaterialien. Die Quelle ist egal.
local function ReadFishingLoot()
    local items = {}

    for slot = 1, api.GetNumLootItems() do
        local itemID = api.GetLootSlotType(slot) == LOOT_ITEM and ItemID(api.GetLootSlotLink(slot)) or nil
        if itemID and IsMaterial(itemID) then
            local amount = tonumber(Clean(select(2, api.GetLootSourceInfo(slot)))) or 1
            items[itemID] = (items[itemID] or 0) + amount
        end
    end

    return items
end

-- Kategorie eines Knotens aus seiner Beute: Kräuter, Erz oder sonst
local function CategoryOf(items)
    local category = "other"

    for itemID in pairs(items) do
        local _, _, _, _, _, classID, subClassID = api.GetItemInfoInstant(itemID)
        if classID == TRADEGOODS then
            if subClassID == HERB then return "herb" end
            if subClassID == METAL_STONE then category = "ore" end
        end
    end

    return category
end

-- Name und Stufe über die Einheiten, auf die der Spieler gerade zeigt. Fehlt ein Wert, bleibt er
-- leer und kann später ergänzt werden.
local UNITS = { "target", "mouseover", "softenemy", "softinteract" }

local function UnitInfo(guid)
    for _, unit in ipairs(UNITS) do
        local unitGUID = Clean(UnitGUID(unit))
        if unitGUID == guid then
            return { name = Clean(UnitName(unit)), level = tonumber(Clean(UnitLevel(unit))) }
        end
    end
end

-- true, wenn die Quelle jetzt zählt: noch nie gesehen oder zuletzt vor mehr als `window` Sekunden
local function Remember(key, window, now)
    local seen = counted[key]
    if seen and (now - seen) <= window then return false end

    if not seen then
        countedSize = countedSize + 1
        if countedSize > MAX_REMEMBERED then
            wipe(counted)
            wipe(looted)
            wipe(killCounted)
            wipe(nodeMark)
            nodeMarkSize = 0
            countedSize = 1
        end
    end

    counted[key] = now
    return true
end

-- true, wenn seit dem zuletzt gezählten Abbau dieses Knotens ein neuer Zauber kam. Gilt der jüngste
-- Zauber (gesendet oder erfolgreich) schon für einen gezählten Abbau, ist es dasselbe Beutefenster.
local function NewNodeCast(guid)
    local mark = math.max(lastSuccess, lastSent)
    local seen = nodeMark[guid]
    if seen and mark <= seen then return false end

    if not seen then
        nodeMarkSize = nodeMarkSize + 1
        if nodeMarkSize > MAX_REMEMBERED then
            wipe(nodeMark)
            nodeMarkSize = 1
        end
    end
    nodeMark[guid] = mark
    return true
end

-- Debug-Ausgaben nur bauen, wenn der Debug-Modus an ist (die Texte kosten sonst unnötig Zeit)
local function DebugOn()
    return not Glimpse.IsDebug or Glimpse:IsDebug()
end

-- Das Beutefenster wird sofort gelesen, denn danach ist es weg. Ausgewertet wird erst einen
-- Moment später: Je nach Reihenfolge der Events kommt der erfolgreiche Zauber kurz vor oder kurz
-- nach LOOT_OPENED, und beides muss als "direkt nach dem Zauber" zählen.
local EVALUATE_DELAY = 0.3

function DB:OnLootOpened()
    if not self.db.profile.recording then return end

    local opened = GetTime()

    -- Angeln: eigener Weg, das Beutefenster hat keine Kreatur oder keinen Knoten als Quelle
    local fishing = false
    if api.IsFishingLoot then
        local asked, value = pcall(api.IsFishingLoot)
        fishing = asked and Clean(value) == true
    end
    if fishing then return self:OnFishingLoot(opened) end

    -- Fehler hier dürfen weder das Looten noch andere Addons stören: abfangen und merken
    local ok, sources = pcall(ReadLoot)
    if not ok then return self:ReportError("ReadLoot", sources) end

    -- Wo der Spieler jetzt steht, nicht erst nach der Verzögerung
    local position
    if self.db.profile.trackLocations then
        local found, result = pcall(Locations.GetPlayerArea, Locations)
        if found then position = result else self:ReportError("GetPlayerArea", result) end

        if DebugOn() then
            self:Debug("Position:", self:DescribeArea(position) or "nicht bestimmbar (keine Karte, Koordinaten oder Instanz)")
        end
    elseif DebugOn() then
        self:Debug("Position: Aufzeichnung der Fundorte ist aus")
    end

    C_Timer.After(EVALUATE_DELAY, function()
        local done, err = pcall(self.ProcessLoot, self, sources, opened, position)
        if not done then self:ReportError("ProcessLoot", err) end
    end)
end

-- Ein Fang: Items und Ort sofort lesen, ausgewertet wird wie bei den übrigen Beutefenstern etwas später.
-- Der Fang gehört zur Zone (uiMapID), in der der Spieler steht, der genaue Ort kommt als Fundort dazu.
function DB:OnFishingLoot(opened)
    local ok, items = pcall(ReadFishingLoot)
    if not ok then return self:ReportError("ReadFishingLoot", items) end

    -- Die Zone braucht es immer, die Koordinaten nur mit der Option "Fundorte aufzeichnen"
    local found, area = pcall(Locations.GetPlayerArea, Locations)
    if not found then
        self:ReportError("GetPlayerArea", area)
        area = nil
    end

    C_Timer.After(EVALUATE_DELAY, function()
        local done, err = pcall(self.ProcessFishing, self, items, opened, area)
        if not done then self:ReportError("ProcessFishing", err) end
    end)
end

-- Das Auswerfen der Angel zählt als Versuch, auch ohne Fang. Ob sich ein Beutefenster öffnet, ist erst später klar, deshalb
-- läuft es wie bei den Kills: Das Auswerfen wird vorgemerkt (Zone und Ort zu diesem Zeitpunkt). Öffnet sich ein Beutefenster
-- eines Fangs, wird der Versuch mit dem Fang gezählt. Sonst zählt er nach FISHING_TIMEOUT Sekunden ohne Fang, oder sofort,
-- wenn schon ausgeworfen wird. Ein abgebrochener Wurf zählt deshalb auch als Versuch.
--
-- Den Klick auf den Schwimmer kann ein Addon nicht abfangen, wohl aber das Ende des Zaubers (UNIT_SPELLCAST_CHANNEL_STOP,
-- der Zauber ist ein Kanalzauber): Nach FISHING_GRACE Sekunden ohne Beutefenster ist der Wurf ohne Fang beendet, ohne
-- die 45 Sekunden abzuwarten. Kommt das Fenster doch noch (FISHING_LATE), wird der Fang dem schon gezählten Wurf zugerechnet.
local FISHING_TIMEOUT = 45
local FISHING_GRACE = 4
local FISHING_LATE = 10

-- Der Zauber "Fischen" (Rang 1: 7620) und seine Ränge heißen alle gleich. Erkannt wird er über den Namen, damit es in jeder
-- Sprache und für jeden Rang klappt. Die übrigen IDs sind die weiteren Ränge und der Zauber ab Mists of Pandaria.
local FISHING_SPELLS = { 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410, 131474 }
local fishingIDs, fishingNames

local function IsFishingSpell(spellID)
    if type(spellID) ~= "number" then return false end

    if not fishingIDs then
        fishingIDs, fishingNames = {}, {}
        for _, id in ipairs(FISHING_SPELLS) do fishingIDs[id] = true end
    end
    if fishingIDs[spellID] then return true end

    -- Der Name des Zaubers von Rang 1 gilt für alle Ränge. Erst jetzt nachschlagen: beim Laden kennt der Client ihn noch nicht immer.
    local lookup = api.GetSpellName or api.GetSpellInfo
    if not lookup then return false end
    local ok, name = pcall(lookup, 7620)
    local cast
    ok, cast = pcall(lookup, spellID)
    if not ok or type(name) ~= "string" or type(cast) ~= "string" or Glimpse:IsSecret(cast) then return false end
    return name == cast
end

local pendingCast, castCounter = nil, 0
-- Zähler dieser Sitzung (nicht gespeichert): ausgeworfen, Beutefenster, Würfe ohne Fang. Zu sehen im Debug-Chat und in
-- /gli gatheringdb stats.
DB.fishingSession = { casts = 0, windows = 0, misses = 0 }

local function SessionText()
    local session = DB.fishingSession
    return format("%d ausgeworfen, %d Beutefenster, %d ohne Fang", session.casts, session.windows, session.misses)
end
local lastMiss -- zuletzt als leer gezählter Wurf: { area, time }

local function Area(self)
    local found, area = pcall(Locations.GetPlayerArea, Locations)
    if not found then
        self:ReportError("GetPlayerArea", area)
        return nil
    end
    return area
end

-- Zählt einen Versuch in der Zone des Ortes. items = Fang oder nichts.
function DB:CountFishing(area, items, how)
    if type(area) ~= "table" or type(area.map) ~= "number" then
        self:Debug("Wurf übersprungen: keine Karte (Instanz oder Ort unbekannt)")
        return
    end

    self:RecordFishing(area.map, items or {}, self.db.profile.trackLocations and area or nil)
    if DebugOn() then
        self:Debug("Gespeichert: Angeln in Zone", tostring(area.map), how, "Fundort:", self:DescribeArea(area) or "keiner")
    end
end

--- Läuft gerade ein Wurf (ausgeworfen, noch kein Fang und kein Ende)?
function DB:IsFishing()
    return pendingCast ~= nil
end

--- Gehört dieser Objekt-Tooltip (Name aus der ersten Zeile) wahrscheinlich zum Schwimmer? Der Schwimmer hat in den
-- Tooltip-Daten keine ID, nur einen Namen (je nach Sprache verschieden). Deshalb gilt: Es läuft ein Wurf und der Name
-- gehört zu keinem bekannten Sammelknoten.
function DB:IsBobber(name)
    return pendingCast ~= nil and type(name) == "string" and #self:FindNodeIDs(name) == 0
end

--- Eine Angel wurde ausgeworfen (UNIT_SPELLCAST_SENT mit der ID des Zaubers).
function DB:OnFishingStart(spellID)
    if not self.db.profile.recording or not IsFishingSpell(spellID) then return end

    -- Der vorige Wurf ist zu Ende, ohne dass ein Fang kam
    if pendingCast then self:FinishFishingMiss(pendingCast) end

    castCounter = castCounter + 1
    local mine = { id = castCounter, area = Area(self) }
    pendingCast = mine
    self.fishingSession.casts = self.fishingSession.casts + 1
    if DebugOn() then self:Debug("Angel ausgeworfen, Wurf", self.fishingSession.casts, "dieser Sitzung (" .. SessionText() .. ")") end

    C_Timer.After(FISHING_TIMEOUT, function()
        if pendingCast ~= mine then return end
        self:FinishFishingMiss(mine)
    end)
end

-- Der Wurf blieb ohne Beutefenster: als Versuch ohne Fang zählen und für ein spätes Fenster merken
function DB:FinishFishingMiss(cast)
    pendingCast = nil
    self.fishingSession.misses = self.fishingSession.misses + 1
    local done, err = pcall(self.CountFishing, self, cast.area, nil, "(Wurf ohne Fang)")
    if not done then return self:ReportError("CountFishing", err) end
    lastMiss = { area = cast.area, time = GetTime() }
end

--- Eine Bildschirmmeldung (UI_ERROR_MESSAGE, UI_INFO_MESSAGE) während eines Wurfs. "Der Fisch ist entkommen"
-- (ERR_FISH_ESCAPED) heißt: Er hat gebissen, der Klick kam zu spät. Der Wurf ist dann ohne Fang zu Ende. Die Texte stammen
-- aus den globalen Zeichenketten des Clients, nicht aus einer festen Übersetzung. "Keine Fische angebissen"
-- (ERR_FISH_NOT_HOOKED) zählt hier nicht: Der Zauber läuft danach womöglich weiter. Im Debug-Modus steht jede Meldung im
-- Chat, damit sich die Texte im Spiel prüfen lassen.
function DB:OnFishingMessage(...)
    local cast = pendingCast
    if not cast or not self.db.profile.recording then return end

    for index = 1, select("#", ...) do
        local text = select(index, ...)
        if type(text) == "string" and not Glimpse:IsSecret(text) then
            if DebugOn() then self:Debug("Meldung beim Angeln:", text) end
            if _G.ERR_FISH_ESCAPED and text == _G.ERR_FISH_ESCAPED then
                self:Debug("Fisch entkommen: Wurf ohne Fang")
                self:FinishFishingMiss(cast)
                return
            end
        end
    end
end

--- Der Fischen-Zauber ist zu Ende (UNIT_SPELLCAST_CHANNEL_STOP: Klick auf den Schwimmer, Abbruch oder Ablauf).
-- Gibt es kurz danach kein Beutefenster, war der Wurf ohne Fang.
function DB:OnFishingStop(spellID)
    local cast = pendingCast
    if not cast or not self.db.profile.recording or not IsFishingSpell(spellID) then return end

    self:Debug("Fischen beendet, warte", FISHING_GRACE, "Sekunden auf das Beutefenster")
    C_Timer.After(FISHING_GRACE, function()
        if pendingCast == cast then self:FinishFishingMiss(cast) end
    end)
end

function DB:ProcessFishing(items, _, area)
    if not self.db.profile.recording then return end

    -- Wie bei Knoten: ein Fang zählt einmal je Wurf, ein erneut geöffnetes Fenster nicht
    if not NewNodeCast("fishing") then
        self:Debug("Fang übersprungen: gleicher Wurf, Beutefenster erneut geöffnet")
        return
    end

    self.fishingSession.windows = self.fishingSession.windows + 1

    -- Der Wurf wurde schon als leer gezählt, das Fenster kam spät: der Fang gehört dazu
    local cast = pendingCast
    if not cast and lastMiss and (GetTime() - lastMiss.time) <= FISHING_LATE and type(lastMiss.area) == "table" and lastMiss.area.map then
        local late = lastMiss
        lastMiss = nil
        self.fishingSession.misses = math.max(self.fishingSession.misses - 1, 0)
        self:AddFishingItems(late.area.map, items)
        self:Debug("Fang dem zuvor gezählten Wurf zugerechnet, Zone", tostring(late.area.map))
        return
    end

    -- Der vorgemerkte Wurf liefert die Zone und den Ort vom Auswerfen, sonst gilt der Ort jetzt
    pendingCast = nil
    lastMiss = nil
    self:CountFishing(cast and cast.area or area, items, "(Fang)")
end

-- Beim Betreten oder Wechseln eines Gebiets (Ladebildschirm, Instanz, neue Zone) zeigt der Debug-Modus,
-- was das Addon über den Ort weiß. So lässt sich die Erkennung prüfen, ohne in der Instanz zu farmen.
-- Kurz warten, weil die Instanzdaten direkt nach dem Event noch nicht immer stimmen, und mehrere
-- Events kurz hintereinander zusammenfassen.
local AREA_DELAY = 1
local areaPending = false

local function RawValues(func)
    if not func then return "nicht vorhanden" end

    local values = { pcall(func) }
    if not values[1] then return "Fehler: " .. tostring(values[2]) end

    local parts = {}
    for i = 2, math.max(#values, 9) do parts[#parts + 1] = tostring(Clean(values[i])) end
    return table.concat(parts, ", ")
end

function DB:DebugArea(event)
    self:Debug("Gebiet (" .. tostring(event) .. "):", self:DescribeArea(Locations:GetPlayerArea()) or "nicht bestimmbar (keine Karte, Koordinaten oder Instanz)")
    self:Debug("IsInInstance:", RawValues(Locations.api.IsInInstance))
    self:Debug("GetInstanceInfo:", RawValues(Locations.api.GetInstanceInfo))
    self:Debug("Aufzeichnung der Fundorte:", self.db.profile.trackLocations and "an" or "aus")
end

function DB:OnAreaChanged(event)
    if areaPending or not DebugOn() then return end

    areaPending = true
    C_Timer.After(AREA_DELAY, function()
        areaPending = false
        if not DebugOn() then return end

        local ok, err = pcall(self.DebugArea, self, event)
        if not ok then self:ReportError("DebugArea", err) end
    end)
end

--- Merkt sich den letzten Fehler (sichtbar in /gli gatheringdb stats) und zeigt ihn im Debug-Modus.
function DB:ReportError(where, err)
    self.errorCount = (self.errorCount or 0) + 1
    self.lastError = where .. ": " .. tostring(err)
    self:Debug("Fehler in", self.lastError)
end

function DB:ProcessLoot(sources, opened, position)
    if not self.db.profile.recording then return end

    -- Zauber erfolgreich im Zeitfenster vor dem Beutefenster (oder kurz danach)
    local afterCast = lastSuccess >= (opened - CAST_WINDOW)

    -- Für Objekte reicht auch ein gerade abgeschickter Zauber: nicht jeder Client meldet den Erfolg
    -- eines Sammelzaubers als UNIT_SPELLCAST_SUCCEEDED
    local afterNodeCast = afterCast or lastSent >= (opened - SENT_WINDOW)

    for guid, items in pairs(sources) do
        local kind, id = ParseGUID(guid)
        self:Debug("Beutefenster:", tostring(kind), tostring(id), "Zauber davor:", tostring(afterCast),
            "Zauber abgeschickt:", tostring(lastSent >= (opened - SENT_WINDOW)),
            "Materialien:", tostring(next(items) ~= nil))

        if kind == "GameObject" then
            -- Truhen werden nicht erfasst. Ein Sammelknoten braucht einen Zauber (Pflücken, Bergbau ...),
            -- das Beutefenster hängt also direkt an einem Zauber. Eine Truhe geht ohne Zauber auf.
            -- Außerdem muss ein Material dabei sein.
            if not afterNodeCast then
                self:Debug("Knoten übersprungen: kein Zauber vor dem Beutefenster")
            elseif not next(items) then
                self:Debug("Knoten übersprungen: kein Handwerksmaterial in der Beute")
            elseif NewNodeCast(guid) then
                local info = UnitInfo(guid) or {}
                if not info.name and lastTarget and (opened - lastTargetTime) <= TARGET_WINDOW then
                    info.name = lastTarget
                end
                info.category = CategoryOf(items)
                self:RecordNode(id, info, items, position)
                if DebugOn() then self:Debug("Gespeichert: Knoten", tostring(id), "Fundort:", self:DescribeArea(position) or "keiner") end
            else
                self:Debug("Knoten übersprungen: gleicher Abbau, Beutefenster erneut geöffnet")
            end

        elseif kind == "Creature" then
            -- Kürschnerbeute: direkt nach einem erfolgreichen Zauber oder bei zweitem Looten
            local seen = looted[guid]
            local again = seen and (opened - seen) <= CREATURE_REPEAT
            local mode = (afterCast or again) and "skinning" or "loot"

            if mode == "loot" and killCounted[guid] then
                -- Der Kill zählte schon als Versuch (die Leiche schien leer), jetzt kommt die Beute dazu
                if Remember(guid .. "|killitems", CREATURE_REPEAT, opened) then
                    killCounted[guid] = nil
                    looted[guid] = opened
                    self:AddNPCItems(id, mode, items)
                    if DebugOn() then self:Debug("Gespeichert: Beute der Kreatur", tostring(id), "(Kill war schon gezählt)") end
                end
            elseif Remember(guid .. "|" .. mode, CREATURE_REPEAT, opened) then
                pendingKills[guid] = nil
                if mode == "loot" then looted[guid] = opened end
                self:RecordNPC(id, mode, UnitInfo(guid), items, position)
                if DebugOn() then
                    self:Debug("Gespeichert: Kreatur", tostring(id), mode, "Fundort:", self:DescribeArea(position) or "keiner")
                end
            end
        end
    end
end

-- Kreaturen ohne Beute: Eine leere Leiche öffnet kein Beutefenster, der Kill muss trotzdem als Versuch
-- zählen, sonst wirkt jede Beute zu häufig. Das Beutefenster hat Vorrang. Der Kill ist nur der
-- Ersatz: Er kommt vom Tod des anvisierten Ziels und zählt erst, wenn nach KILL_FALLBACK Sekunden
-- noch kein Beutefenster aufging. Sagt CanLootUnit, dass die Leiche Beute hat, zählt der Kill nie.
local function HasLoot(guid)
    if type(CanLootUnit) ~= "function" then return nil end
    local ok, hasLoot = pcall(CanLootUnit, guid)
    if ok then return Clean(hasLoot) end
end

function DB:CommitKill(guid, position)
    if not pendingKills[guid] or not self.db.profile.recording then return end
    pendingKills[guid] = nil

    local kind, id = ParseGUID(guid)
    if kind ~= "Creature" or not id then return end

    local now = GetTime()
    if not Remember(guid .. "|loot", CREATURE_REPEAT, now) then return end

    killCounted[guid] = true
    self:RecordNPC(id, "loot", UnitInfo(guid), {}, position)
    if DebugOn() then
        self:Debug("Gespeichert: Kreatur", tostring(id), "loot", "ohne Beutefenster (leere Leiche)")
    end
end

function DB:OnKill(guid)
    if not self.db.profile.recording then return end
    if type(guid) ~= "string" or ParseGUID(guid) ~= "Creature" then return end

    if DebugOn() then self:Debug("Kill erkannt:", tostring(select(2, ParseGUID(guid)))) end

    -- Schon als Versuch gezählt (Beutefenster oder früherer Kill derselben Leiche)
    local now = GetTime()
    if pendingKills[guid] or (counted[guid .. "|loot"] and (now - counted[guid .. "|loot"]) <= CREATURE_REPEAT) then return end
    pendingKills[guid] = now

    -- Wo der Spieler beim Kill steht
    local position
    if self.db.profile.trackLocations then
        local found, result = pcall(Locations.GetPlayerArea, Locations)
        if found then position = result end
    end

    C_Timer.After(KILL_CHECK_DELAY, function()
        if not pendingKills[guid] then return end -- inzwischen gelootet

        -- Hat die Leiche laut Client Beute, zählt das Beutefenster und der Kill nie
        if HasLoot(guid) == true then
            pendingKills[guid] = nil
            return
        end

        -- Sonst zuerst auf das Beutefenster warten, erst danach zählt der Kill als Versuch
        C_Timer.After(KILL_FALLBACK - KILL_CHECK_DELAY, function() self:CommitKill(guid, position) end)
    end)
end

local frame = CreateFrame("Frame")
-- Ersatz ohne PARTY_KILL: Stirbt das Ziel, das wir gerade anvisieren, ist es ein Kill von uns, sofern nicht ein
-- anderer Spieler das Tap hat. Kills außerhalb des Ziels (Flächenschaden, Haustier) fehlen dabei, der Kill ist nur der
-- Ersatz für das Beutefenster. Der Kampflog (COMBAT_LOG_EVENT_UNFILTERED) ist für Addons gesperrt und löst
-- eine Blockmeldung aus, deshalb wird er nicht verwendet.
--
-- Geprüft wird bei UNIT_HEALTH des Ziels, beim Wechsel des Ziels (auch auf eine Leiche) und am Ende des
-- Kampfes. Im Kampf kann die GUID des Ziels geschützt sein: dann gilt die zuletzt lesbare GUID desselben Ziels.
local targetGUID -- GUID des aktuellen Ziels, solange sie lesbar war

local function RefreshTargetGUID(reset)
    local guid = Clean(UnitGUID("target"))
    if type(guid) == "string" then
        targetGUID = guid
    elseif reset then
        targetGUID = nil -- anderes Ziel, dessen GUID wir nicht kennen
    end
end

-- PARTY_KILL (Killer-GUID, Opfer-GUID) meldet jeden Kill von uns, Gruppenmitgliedern und Haustieren, auch ohne Ziel und
-- ohne Beute. Kennt der Client das Ereignis, ist es die Quelle; der Tod des Ziels (CheckTargetKill) ist nur der Ersatz
-- für Clients ohne dieses Ereignis, weil er Kills nach einem Zielwechsel oder ohne Todesmeldung verpasst.
local partyKillActive = false

--- Kill laut PARTY_KILL: zählt, wenn der Killer der Spieler selbst oder sein Haustier ist.
function DB:OnPartyKill(killer, victim)
    killer, victim = Clean(killer), Clean(victim)
    if type(killer) ~= "string" or type(victim) ~= "string" then return end

    local mine = killer == Clean(UnitGUID("player")) or killer == Clean(UnitGUID("pet"))
    if not mine then
        if DebugOn() then self:Debug("Kill-Erkennung: PARTY_KILL von jemand anderem, nicht gezählt") end
        return
    end
    if DebugOn() then self:Debug("Kill-Erkennung: PARTY_KILL", victim) end
    self:OnKill(victim)
end

local function CheckTargetKill()
    if partyKillActive then return end
    local ok, dead = pcall(UnitIsDead, "target")
    if not ok then return end
    if dead ~= nil and Glimpse:IsSecret(dead) then
        if DebugOn() then DB:Debug("Kill-Erkennung: UnitIsDead ist geschützt") end
        return
    end
    if dead ~= true then return end

    local guid = Clean(UnitGUID("target"))
    if type(guid) ~= "string" then guid = targetGUID end
    if type(guid) ~= "string" then
        if DebugOn() then DB:Debug("Kill-Erkennung: Ziel ist tot, aber die GUID ist unbekannt") end
        return
    end

    if UnitIsTapDenied then
        local tapOK, denied = pcall(UnitIsTapDenied, "target")
        if tapOK and Clean(denied) == true then
            if DebugOn() then DB:Debug("Kill-Erkennung: Ziel gehört einem anderen Spieler (Tap)") end
            return
        end
    end

    DB:OnKill(guid)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, zielName, castGUID, spellID)
        local _, target, _, spellID = ...
        lastSent = GetTime()
        DB:OnFishingStart(Clean(spellID))
        target = Clean(target)
        if type(target) == "string" and target ~= "" then
            lastTarget, lastTargetTime = target, GetTime()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- (unit, castGUID, spellID)
        local _, _, spellID = ...
        DB:OnFishingStop(Clean(spellID))
    elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
        DB:OnFishingMessage(...)
    elseif event == "PARTY_KILL" then
        local killer, victim = ...
        DB:OnPartyKill(killer, victim)
    elseif event == "UNIT_HEALTH" then
        RefreshTargetGUID(false)
        CheckTargetKill()
    elseif event == "PLAYER_TARGET_CHANGED" then
        RefreshTargetGUID(true)
        CheckTargetKill()
    elseif event == "PLAYER_REGEN_ENABLED" then
        CheckTargetKill()
    else
        lastSuccess = GetTime()
    end
end)

function DB:StartCollecting()
    self:RegisterEvent("LOOT_OPENED", "OnLootOpened")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnAreaChanged")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnAreaChanged")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    frame:RegisterEvent("UI_ERROR_MESSAGE")
    frame:RegisterEvent("UI_INFO_MESSAGE")

    -- Kills ohne Beutefenster: PARTY_KILL, sonst als Ersatz der Tod des Ziels
    partyKillActive = pcall(frame.RegisterEvent, frame, "PARTY_KILL")
    if partyKillActive then return end

    frame:RegisterUnitEvent("UNIT_HEALTH", "target")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function DB:StopCollecting()
    self:UnregisterEvent("LOOT_OPENED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:UnregisterAllEvents()
end
