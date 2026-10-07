local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Glimpse: GatheringDB sammelt, was beim Sammeln und Looten herauskommt, und speichert es
-- account-weit, und zwar nur Handwerksmaterialien. Angezeigt wird nichts (außer im Debug-Modus),
-- das übernehmen andere Addons (z. B. GatheringTooltip).
--
-- Öffentliche Schnittstelle (API_VERSION 10), erreichbar über Glimpse.GatheringDB:
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
--                              Fundorte einer Quelle (kind = "node", "npc" oder "fishing", bei Angeln ist id die Karte): { map, x, y, count, source };
--                              in Instanzen gelootet: { instance, name, count, source } ohne map, x und y,
--                              eigene zuerst, danach die aus anderen Addons (source = "GatherMate2", count = 0);
--                              includeExternal = false liefert nur die eigenen
--   :GetOwnSpots(kind, id)     nur die eigenen Fundorte
--   :GetNearestSpots(kind, id, limit, currentMapOnly)
--                              Fundorte, die nächsten auf der Karte des Spielers zuerst (distance)
--   :GetItemSpots(itemID, minAttempts, limit, includeExternal)
--                              Fundorte aller Quellen eines Items, wahrscheinlichste Quelle zuerst
--   :GetLocatedItemSources(itemID, minAttempts, externalSeparate, minChance)
--                              Die Orte der Quellen eines Items, geordnet nach "wo findet man es am besten": je Quelle
--                              und Zone ein Eintrag; Stufe 1 eigenes Gebiet, 2 gleicher Kontinent (nach Entfernung, ab
--                              minChance), 3 sonst, 4 ohne Ort; bestätigte Orte vor externen. Felder tier, area, group,
--                              spot, spots, place dazu
--   :GetRequiredSkill(kind, id, level)
--                              Beruf ("herb", "ore", "skinning") und benötigter Skill eines Knotens (kind = "node") oder
--                              einer Kreatur (kind = "npc", Stufe aus level oder der gespeicherten), bei Kreaturen dazu,
--                              ob sie als kürschnerbar bekannt ist
--   :GetNodeSkill(id)          dasselbe für einen Knoten (Objekt-ID); :GetSkinningSkill(level) für eine Kreaturenstufe
--   :GetPlayerSkill(profession)  Skill des Spielers mit Bonus, Maximum, Name im Client, Skill ohne Bonus (nil: nicht gelernt)
--   :GetSkillColor(required, current)
--                              "red" (reicht nicht), "orange", "yellow", "green" oder "gray", dazu r, g, b
--   :HasProfession(profession), :IsKnownSkinnable(id), :GetCreatureTypeID(unit), :IsSkinnableType(typeID)
--   :GetFishing(map)           Eintrag einer Angelzone (uiMapID) oder nil: { attempts, items, spots }
--   :GetFishingDrops(map)      Liste der Fänge einer Zone, dazu die Zahl der Würfe (wie GetNodeDrops)
--   :IsFishing(), :IsBobber(name)  läuft ein Wurf; gehört der Objekt-Tooltip mit diesem Namen zum Schwimmer
--   :GetProviders()            Anbieter fremder Fundorte: { name, available, enabled }
--   :RegisterProvider(name, provider)  weiteren Anbieter anmelden (siehe Data/Providers.lua)
--   :GetMapName(map)           Name einer Karte (Zone) oder nil
--   :ExportData()              Exporttext aller Daten (komprimiert), dazu Zahlen
--   :ImportData(text, mode)    Import, mode = "merge" (Standard) oder "replace"
-- Nachricht GLIMPSE_GATHERING_UPDATED (kind, id), wenn sich Daten geändert haben:
--   DB:RegisterMessage("GLIMPSE_GATHERING_UPDATED", func)
-- Die zurückgegebenen Tabellen sind nur zum Lesen gedacht.
-- Aufbau in Data/Store.lua, Erfassung in Loot/Collect.lua, Debug-Anzeige in Debug/Debug.lua.
local DB = Glimpse:NewModule("GatheringDB", nil, "AceEvent-3.0")
DB.L = L
DB.API_VERSION = 10
DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"

-- Damit andere Addons ohne GetModule drankommen
Glimpse.GatheringDB = DB

-- Gesammelte Daten: eigene SavedVariable, account-weit (global). Die Version steht für
-- Änderungen am Format (Umstellung älterer Daten in Data/Migrate.lua).
--   1: Knoten und Kreaturen mit Beute
--   2: dazu Fundorte (spots) und die Liste schon importierter Exporte (imports)
--   3: Fundorte können auch eine Instanz sein ({ inst, n } statt { map, x, y, n }), instances = Namen der Instanzen
--   4, 5: früher ein Kill-Zähler je Kreatur (kills); er wird nicht mehr geführt und beim Prüfen der Daten entfernt
--   6: Angeln (fishing), je Zone { attempts, items, spots }
local DATA_VERSION = 6
DB.DATA_VERSION = DATA_VERSION
-- Die Version steht bewusst NICHT in den Defaults: AceDB lässt beim Speichern alle Werte weg, die dem Default
-- gleichen. Mit einem Default wäre die gespeicherte Version nach dem Logout verschwunden und beim nächsten Laden
-- immer die aktuelle gewesen, die Umstellung (Data/Migrate.lua) wäre nie gelaufen. Ohne Eintrag gilt Version 1,
-- alle Schritte laufen (sie sind wiederholbar), danach steht die Version fest in der Datei.
local dataDefaults = {
    global = {
        nodes = {}, -- [objectID] = { name, category, attempts, items = { [itemID] = { hits, amount } }, spots }
        npcs = {},  -- [npcID] = { name, level, loot = { attempts, items }, skinning = { attempts, items }, spots }
        fishing = {}, -- [uiMapID der Zone] = { attempts, items = { [itemID] = { hits, amount } }, spots }
        instances = {}, -- [instanceID] = Name der Instanz, für Fundorte in Instanzen
        imports = {}, -- [Export-ID] = Zeitpunkt, damit derselbe Export nicht zweimal zusammengeführt wird
    },
}

-- Einstellungen: im Namespace der Glimpse-Datenbank, damit sie dem Profil folgen
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
    self:WatchGatherMate2()
    self:WatchSkills()
end

function DB:OnDisable()
    self:StopCollecting()
end
