local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Glimpse: GatheringDB sammelt, was beim Sammeln und Looten herauskommt, und speichert es
-- account-weit, und zwar nur Handwerksmaterialien. Angezeigt wird nichts (außer im Debug-Modus),
-- das übernehmen andere Addons (z. B. GatheringTooltip).
--
-- Öffentliche Schnittstelle (API_VERSION 1), erreichbar über Glimpse.GatheringDB:
--   :GetNode(id)               Eintrag eines Sammelknotens oder nil
--   :GetNPC(id)                Eintrag einer Kreatur oder nil
--   :GetNodeDrops(id)          Liste der Beute eines Knotens, dazu die Zahl der Versuche
--   :GetNPCDrops(id, kind)     dasselbe für eine Kreatur, kind = "loot" oder "skinning"
--   :GetTooltipName(tooltip)   Name aus der ersten Zeile eines Tooltips (für Knoten ohne ID)
--   :FindNodeIDs(name)         IDs der Knoten mit diesem Namen
--   :GetNodeDropsByName(name)  wie GetNodeDrops, über den Namen (mehrere IDs zusammengerechnet)
--   :GetItemSources(itemID, minAttempts)
--                              alle Quellen eines Items, die wahrscheinlichste zuerst
--   :GetStats()                Anzahl Knoten, Kreaturen und erfasster Beutefenster
-- Nachricht GLIMPSE_GATHERING_UPDATED (kind, id), wenn sich Daten geändert haben:
--   DB:RegisterMessage("GLIMPSE_GATHERING_UPDATED", func)
-- Die zurückgegebenen Tabellen sind nur zum Lesen gedacht.
-- Aufbau in Data/Store.lua, Erfassung in Loot/Collect.lua, Debug-Anzeige in Debug/Debug.lua.
local DB = Glimpse:NewModule("GatheringDB", nil, "AceEvent-3.0")
DB.L = L
DB.API_VERSION = 1
DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"

-- Damit andere Addons ohne GetModule drankommen
Glimpse.GatheringDB = DB

-- Gesammelte Daten: eigene SavedVariable, account-weit (global). Die Version steht für
-- spätere Änderungen am Format.
local DATA_VERSION = 1
local dataDefaults = {
    global = {
        version = DATA_VERSION,
        nodes = {}, -- [objectID] = { name, category, attempts, items = { [itemID] = { hits, amount } } }
        npcs = {},  -- [npcID] = { name, level, loot = { attempts, items }, skinning = { attempts, items } }
    },
}

-- Einstellungen: im Namespace der Glimpse-Datenbank, damit sie dem Profil folgen
local settingsDefaults = {
    profile = {
        recording = true,
    },
}

function DB:OnInitialize()
    self.store = LibStub("AceDB-3.0"):New("GlimpseGatheringDB", dataDefaults, true)
    self.data = self.store.global
    self.db = Glimpse.db:RegisterNamespace("GatheringDB", settingsDefaults)

    -- Daten von einer neueren Version bleiben unangetastet, dann wird nicht aufgezeichnet
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
end

function DB:OnDisable()
    self:StopCollecting()
end
