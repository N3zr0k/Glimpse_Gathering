local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Datenteil von Glimpse: Gathering. Erfasst, welche Handwerksmaterialien beim Sammeln und Looten anfallen, und
-- schreibt sie in den Namespace "gathering" von Glimpse: Database. Die Anzeige macht das Modul GatheringTooltip.
-- Die Lese-API unten ist eine Fassade über GlimpseDB:Get("gathering") und ("fishing").
--
-- Namespace gathering (Bereich Gathering, Zähler auch je Zone; Zone = uiMapID, in Instanzen -instanceID):
--   node / nodeloot:<Objekt> / nodedrop:<Objekt>   Abbau eines Knotens, Menge, Beutefenster mit dem Item (Weltwissen)
--   npc / npcloot:<NPC> / npcdrop:<NPC>            geplünderte Leichen (auch leere), Menge, Fenster (Weltwissen)
--   skinned / skinloot:<NPC> / skindrop:<NPC>      gekürschnerte Leichen, Menge, Fenster (Weltwissen)
--   herb / ore / other [Objekt], skin [NPC]        eigene Sammelzähler (persönlich)
--   Orte: Fundorte der Knoten (ID = Objekt)
-- Angeln schreibt Glimpse: Professions in den Namespace fishing, gelesen wird es hier nur.
--
-- API (API_VERSION 11) über Glimpse:GetModule("GatheringData"):
--   :GetNode(id)               Knoten { name, category, attempts, items = { [itemID] = { hits, amount } } } oder nil
--   :GetNPC(id)                Kreatur { name, level, loot = { attempts, items }, skinning = { ... } } oder nil
--   :GetNodeDrops(id)          Liste der Beute eines Knotens, dazu die Zahl der Versuche
--   :GetNPCDrops(id, kind)     dasselbe für eine Kreatur, kind = "loot" oder "skinning"
--   :GetTooltipName(tooltip)   Name aus der ersten Zeile eines Tooltips (für Knoten ohne ID)
--   :FindNodeIDs(name)         IDs der Knoten mit diesem Namen
--   :GetNodeDropsByName(name)  wie GetNodeDrops, über den Namen (mehrere IDs zusammengerechnet)
--   :GetItemSources(itemID, minAttempts)
--                              alle Quellen eines Items, die wahrscheinlichste zuerst
--   :GetStats()                Anzahl Knoten, Kreaturen, erfasster Beutefenster, Fundorte, Angelzonen und Fänge
--   :GetSpots(kind, id, includeExternal)
--                              Fundorte (kind = "node", "npc" oder "fishing" mit id = Zone): { map, x, y, count, source },
--                              Zone ohne Koordinaten { map, count, source }, Instanz { instance, name, count, source }.
--                              Eigene zuerst, dann externe (source = "GatherMate2", count = 0)
--   :GetOwnSpots(kind, id)     nur die Fundorte aus Glimpse: Database
--   :GetNearestSpots(kind, id, limit, currentMapOnly)
--                              Fundorte, die nächsten auf der Karte des Spielers zuerst (distance)
--   :GetItemSpots(itemID, minAttempts, limit, includeExternal)
--                              Fundorte aller Quellen eines Items, wahrscheinlichste Quelle zuerst
--   :GetLocatedItemSources(itemID, minAttempts, externalSeparate, minChance)
--                              Orte der Quellen, je Quelle und Zone ein Eintrag (Core/Data/DataSources.lua)
--   :GetRequiredSkill(kind, id, level), :GetNodeSkill(id), :GetSkinningSkill(level), :GetPlayerSkill(profession),
--   :GetSkillColor(required, current), :HasProfession(profession), :IsKnownSkinnable(id),
--   :GetCreatureTypeID(unit), :IsSkinnableType(typeID)       Skills (Core/Data/DataSkills.lua)
--   :GetFishing(zone)          Angelzone aus dem Namespace fishing: { attempts, items } oder nil
--   :GetFishingDrops(zone)     Liste der Fänge einer Zone, dazu die Zahl der Beutefenster
--   :GetProviders()            Anbieter fremder Fundorte: { name, available, enabled }
--   :RegisterProvider(name, provider)  weiteren Anbieter anmelden (siehe Core/Data/DataProviders.lua)
--   :GetMapName(map), :GetInstanceName(id)
-- Änderungen meldet Glimpse: Database (GlimpseDB.EVENT_CHANGED, Namespace "gathering" bzw. "fishing").
-- Rückgabetabellen nur lesen. Aufbau: Core/Data/ (Lesen), Core/Loot/ (Erfassen), Modules/Debug/ (Debug, Probes).
local DB = Glimpse:NewModule("GatheringData", nil, "AceEvent-3.0")
DB.L = L
DB.API_VERSION = 11

DB.NAMESPACE = "gathering"
DB.FISHING_NAMESPACE = "fishing"

-- Weltwissen lesen: alle Charaktere, auch aus Importen
DB.WORLD_SCOPE = "all"

-- Anmeldung beim Namespace. world = Arten, die als Weltwissen exportiert werden.
DB.NAMESPACE_OPTIONS = {
    area = "Gathering",
    zones = true,
    world = {
        node = true, nodeloot = true, nodedrop = true,
        npc = true, npcloot = true, npcdrop = true,
        skinned = true, skinloot = true, skindrop = true,
    },
}

-- Im Namespace der Glimpse-DB, folgt damit dem Profil. Name "GatheringDB" von früher, damit Einstellungen bleiben.
local settingsDefaults = {
    profile = {
        recording = true,
        trackLocations = true, -- Zone und Koordinaten der Fundorte mitschreiben
        useExternalSpots = true, -- Fundorte aus anderen Addons (GatherMate2) mit anzeigen
        externalSources = {},    -- [Name des Anbieters] = false schaltet nur diesen aus (Standard: an)
    },
}

function DB:OnInitialize()
    self.debug = Glimpse:NewDebugger("GatheringData", { "node", "creature", "skinning", "kill", "area", "error", "tooltip" })
    self.db = Glimpse.db:RegisterNamespace("GatheringDB", settingsDefaults)
    self:LoadNames()

    -- Früh anmelden, vor PLAYER_LOGIN
    local Database = GlimpseDB
    if type(Database) == "table" and Database.Register then
        local ok, ns, reason = pcall(Database.Register, Database, self.NAMESPACE, self.NAMESPACE_OPTIONS)
        if ok and ns then
            self.ns = ns
        else
            self.registerError = ok and tostring(reason) or tostring(ns)
        end
        if Database.RegisterCallback then
            Database.RegisterCallback(self, Database.EVENT_CHANGED, "OnDataChanged")
        end
    else
        self.registerError = "MISSING"
    end
end

function DB:OnEnable()
    self:WarnOldAddons()
    if self.registerError == "NEWER_DATA" then
        Glimpse:Print(L["The saved gathering data comes from a newer version. Recording is paused."])
    elseif not self.ns then
        Glimpse:Print(format(L["Glimpse: Database is not available, recording is off (%s)."], tostring(self.registerError)))
    else
        local ok, missing = self:CheckAPI()
        if ok then
            self:StartCollecting()
        else
            Glimpse:Print(format(L["Missing game functions, recording is off: %s"], table.concat(missing, ", ")))
        end
    end
    self:RegisterDebugTooltips()
    self:RegisterProbes()
    self:WatchGatherMate2()
    self:WatchSkills()
end

function DB:OnDisable()
    self:StopCollecting()
end

--- Leser eines Namespace (Standard gathering), nil ohne Database oder ohne Daten
function DB:Reader(name)
    local Database = GlimpseDB
    if type(Database) ~= "table" or type(Database.Get) ~= "function" then return nil end
    local ok, reader = pcall(Database.Get, Database, name or self.NAMESPACE)
    if ok and type(reader) == "table" then return reader end
end

--- Zwischenspeicher verwerfen, wenn sich gathering oder fishing ändert (nil = vieles auf einmal, z. B. Import)
function DB:OnDataChanged(_, nsName)
    if nsName == nil or nsName == self.NAMESPACE or nsName == self.FISHING_NAMESPACE then
        self:ClearCaches()
    end
end

-- Bis 0.3.5 zwei Addons. Liegen die alten Ordner noch im AddOns-Verzeichnis, laufen beide Sammler doppelt.
local OLD_ADDONS = { "Glimpse_GatheringDB", "Glimpse_GatheringTooltip" }

function DB:WarnOldAddons()
    local IsLoaded = self.api.IsAddOnLoaded
    if not IsLoaded then return end
    for _, name in ipairs(OLD_ADDONS) do
        if IsLoaded(name) then
            Glimpse:Print(format(L["%s is now part of Glimpse: Gathering. Please delete the folder %s."], name, name))
        end
    end
end
