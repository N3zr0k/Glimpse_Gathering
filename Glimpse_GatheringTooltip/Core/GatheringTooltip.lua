local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Zeigt in Knoten- und Kreatur-Tooltips, was dort gefunden wurde. Daten aus Glimpse: GatheringDB.
--
-- Aufteilung: Core/     = Modul, Optionen
--             Tooltip/  = Tooltip-Zeilen
-- Core/Professions.lua prüft, ob der Spieler einen Beruf gelernt hat.
local GT = Glimpse:NewModule("GatheringTooltip", nil, "AceEvent-3.0")
GT.L = L

local defaults = {
    profile = {
        showNodes = true,
        showLoot = true,
        showSkinning = true,
        showItemSource = true,
        maxSources = 3,
        minChance = 10, -- Prozent: Quellen in anderen Zonen desselben Kontinents erscheinen erst ab dieser Chance (0 = alle)
        externalSeparate = true, -- Quellen, die nur Fundorte aus anderen Addons haben, getrennt hinten aufführen
        showSourceIcons = true, -- Symbol vor jeder Quelle (Beutel, Beruf) statt Text hinter dem Namen
        showLocations = true, -- Fundort der Quelle in Klammern hinter dem Namen
        waypointKey = "CTRL-G", -- Taste für den Wegpunkt zum besten Fundort ("off" = aus)
        showWaypointHint = true, -- Hinweis auf die Taste im Tooltip
        showHereIcon = true, -- Markierung vor dem eigenen Ort
        hereIcon = "pinsolid", -- Symbol: pin, pinsolid, pinline, person, arrow
        hereColor = "blue", -- Farbe: blue, white, yellow, green, red
        showAttempts = true, -- Treffer/Versuche hinter der Chance, z. B. (13/14)
        showCoords = true,
        showDistance = true,
        onlyLearned = false,
        showNodeSkill = true, -- benötigter Skill im Tooltip von Kräutern und Erzadern
        showMobSkill = true, -- benötigter Kürschnerei-Skill im Tooltip von Kreaturen
        skillOnlyLearned = true, -- die Skill-Zeile nur, wenn der Spieler den Beruf hat
        hideGraySkill = false, -- Knoten ausblenden, die keinen Skill mehr bringen
        maxItems = 8,
        minAttempts = 1,
        modShift = false,
        modCtrl = false,
        modAlt = false,
    },
}

function GT:OnInitialize()
    self.db = Glimpse.db:RegisterNamespace("GatheringTooltip", defaults)

    -- BuildOptions steht in Core/Options.lua
    Glimpse:RegisterAddonOptions(ADDON_NAME, self:BuildOptions(), true, self:BuildCredits()) -- true = Tabs
end

function GT:OnEnable()
    -- GatheringDB ist Pflicht (## Dependencies), hier nur Prüfung auf zu alte Version
    self.data = Glimpse:GetModule("GatheringDB")
    if (self.data.API_VERSION or 0) < 9 then
        self:Debug("GatheringDB ist zu alt")
        return
    end

    self:RegisterTooltips()
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfo")
    self:RegisterEvent("MODIFIER_STATE_CHANGED", "OnModifierChanged")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateWaypointListener") -- Tastaturabfrage nach dem Kampf nachstellen
end

-- Beim Drücken oder Loslassen den sichtbaren Tooltip neu aufbauen, aber nur wenn Tasten verlangt sind
function GT:OnModifierChanged()
    if Glimpse:ModifiersRequired(self.db.profile) then self:RefreshTooltip() end
end
