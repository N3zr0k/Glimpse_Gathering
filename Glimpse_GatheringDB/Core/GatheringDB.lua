local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Glimpse: GatheringDB speichert account-weit, welche Handwerksmaterialien beim Sammeln und Looten
-- anfallen. Keine eigene Anzeige (außer Debug), das übernimmt z. B. GatheringTooltip.
--
-- API (API_VERSION 10) über Glimpse.GatheringDB:
--   :GetNode(id)               Eintrag eines Sammelknotens oder nil
--   :GetNPC(id)                Eintrag einer Kreatur oder nil
--   :GetNodeDrops(id)          Liste der Beute eines Knotens, dazu die Zahl der Versuche
--   :GetNPCDrops(id, kind)     dasselbe für eine Kreatur, kind = "loot" oder "skinning"
--   :GetTooltipName(tooltip)   Name aus der ersten Zeile eines Tooltips (für Knoten ohne ID)
--   :FindNodeIDs(name)         IDs der Knoten mit diesem Namen
--   :GetNodeDropsByName(name)  wie GetNodeDrops, über den Namen (mehrere IDs zusammengerechnet)
--   :GetItemSources(itemID, minAttempts)
--                              alle Quellen eines Items, die wahrscheinlichste zuerst
--   :GetStats()                Anzahl Knoten, Kreaturen, erfasster Beutefenster, Fundorte, Angelzonen und Würfe
--   :GetSpots(kind, id, includeExternal)
--                              Fundorte (kind = "node", "npc" oder "fishing" mit id = Karte): { map, x, y, count, source },
--                              in Instanzen { instance, name, count, source }. Eigene zuerst, dann externe
--                              (source = "GatherMate2", count = 0); includeExternal = false nur eigene
--   :GetOwnSpots(kind, id)     nur die eigenen Fundorte
--   :GetNearestSpots(kind, id, limit, currentMapOnly)
--                              Fundorte, die nächsten auf der Karte des Spielers zuerst (distance)
--   :GetItemSpots(itemID, minAttempts, limit, includeExternal)
--                              Fundorte aller Quellen eines Items, wahrscheinlichste Quelle zuerst
--   :GetLocatedItemSources(itemID, minAttempts, externalSeparate, minChance)
--                              Orte der Quellen, je Quelle und Zone ein Eintrag. tier 1 eigenes Gebiet, 2 gleicher
--                              Kontinent (nach Entfernung, ab minChance), 3 sonst, 4 ohne Ort; bestätigte vor
--                              externen. Zusatzfelder tier, area, group, spot, spots, place
--   :GetRequiredSkill(kind, id, level)
--                              Beruf ("herb", "ore", "skinning") und benötigter Skill; bei kind = "npc" Stufe aus
--                              level oder gespeichert, dazu ob als kürschnerbar bekannt
--   :GetNodeSkill(id)          dasselbe für einen Knoten (Objekt-ID); :GetSkinningSkill(level) für eine Kreaturenstufe
--   :GetPlayerSkill(profession)  Skill des Spielers mit Bonus, Maximum, Name im Client, Skill ohne Bonus (nil: nicht gelernt)
--   :GetSkillColor(required, current)
--                              "red" (reicht nicht), "orange", "yellow", "green" oder "gray", dazu r, g, b
--   :HasProfession(profession), :IsKnownSkinnable(id), :GetCreatureTypeID(unit), :IsSkinnableType(typeID)
--   :GetFishing(map)           Eintrag einer Angelzone (uiMapID) oder nil: { attempts, items, spots }
--   :GetFishingDrops(map)      Liste der Fänge einer Zone, dazu die Zahl der Würfe (wie GetNodeDrops)
--   :IsFishing(), :IsBobber(name)  läuft ein Wurf; gehört der Objekt-Tooltip mit diesem Namen zum Schwimmer
--   :GetProviders()            Anbieter fremder Fundorte: { name, available, enabled }
--   :RegisterProvider(name, provider)  weiteren Anbieter anmelden (siehe Core/Data/Providers.lua)
--   :GetMapName(map)           Name einer Karte (Zone) oder nil
--   :ExportData()              Exporttext aller Daten (komprimiert), dazu Zahlen
--   :ImportData(text, mode)    Import, mode = "merge" (Standard) oder "replace"
-- Nachricht GLIMPSE_GATHERING_UPDATED (kind, id), wenn sich Daten geändert haben:
--   DB:RegisterMessage("GLIMPSE_GATHERING_UPDATED", func)
-- Rückgabetabellen nur lesen.
-- Aufbau in Core/Data/ (Store.lua, Spots.lua, Names.lua), Erfassung in Core/Loot/, Debug-Anzeige in Modules/Debug/Debug.lua.
local DB = Glimpse:NewModule("GatheringDB", nil, "AceEvent-3.0")
DB.L = L
DB.API_VERSION = 10
DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"

-- Zugriff ohne GetModule
Glimpse.GatheringDB = DB

-- Account-weite SavedVariable. version = Datenformat, Umstellung in Core/Data/Migrate.lua:
--   1: Knoten und Kreaturen mit Beute
--   2: Fundorte (spots), importierte Exporte (imports)
--   3: Fundorte auch als Instanz ({ inst, n } statt { map, x, y, n }), instances = Instanznamen
--   4, 5: Kill-Zähler je Kreatur (kills), wird beim Prüfen entfernt
--   6: Angeln (fishing), je Zone { attempts, items, spots }
local DATA_VERSION = 6
DB.DATA_VERSION = DATA_VERSION
-- version absichtlich nicht in den Defaults: AceDB speichert keine Default-Werte, die Version wäre nach
-- dem Logout weg und Migrate liefe nie. Ohne Eintrag gilt 1, alle (wiederholbaren) Schritte laufen.
local dataDefaults = {
    global = {
        nodes = {}, -- [objectID] = { name, category, attempts, items = { [itemID] = { hits, amount } }, spots }
        npcs = {},  -- [npcID] = { name, level, loot = { attempts, items }, skinning = { attempts, items }, spots }
        fishing = {}, -- [uiMapID der Zone] = { attempts, items = { [itemID] = { hits, amount } }, spots }
        instances = {}, -- [instanceID] = Name der Instanz, für Fundorte in Instanzen
        imports = {}, -- [Export-ID] = Zeitpunkt, gegen doppeltes Zusammenführen
    },
}

-- Im Namespace der Glimpse-DB, folgt damit dem Profil
local settingsDefaults = {
    profile = {
        recording = true,
        trackLocations = true, -- Zone und Koordinaten der Fundorte mitschreiben
        useExternalSpots = true, -- Fundorte aus anderen Addons (GatherMate2) mit anzeigen
        externalSources = {},    -- [Name des Anbieters] = false schaltet nur diesen aus (Standard: an)
    },
}

function DB:OnInitialize()
    self.store = LibStub("AceDB-3.0"):New("GlimpseGatheringDB", dataDefaults, true)
    self.data = self.store.global
    self.db = Glimpse.db:RegisterNamespace("GatheringDB", settingsDefaults)

    -- Daten einer neueren Version nicht anfassen, nicht aufzeichnen
    self.dataTooNew = not self:PrepareData(DATA_VERSION)

    -- BuildOptions steht in Core/Options.lua
    Glimpse:RegisterAddonOptions(ADDON_NAME, self:BuildOptions())
end

function DB:OnEnable()
    if self.dataTooNew then
        Glimpse:Print(L["The saved gathering data comes from a newer version. Recording is paused."])
    else
        local ok, missing = self:CheckAPI()
        if ok then
            self:StartCollecting()
        else
            Glimpse:Print(format(L["Missing game functions, recording is off: %s"], table.concat(missing, ", ")))
        end
    end
    self:RegisterDebugTooltips()
    self:WatchGatherMate2()
    self:WatchSkills()
end

function DB:OnDisable()
    self:StopCollecting()
end
