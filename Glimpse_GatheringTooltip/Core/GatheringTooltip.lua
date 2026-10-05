local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Zeigt in den Tooltips von Sammelknoten und Kreaturen, was dort bisher gefunden wurde.
-- Die Daten kommen aus Glimpse: GatheringDB, hier wird nur angezeigt.
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
        maxSources = 1,
        externalSeparate = true, -- Quellen, die nur Fundorte aus anderen Addons haben, getrennt hinten aufführen
        showSourceIcons = true, -- Symbol vor jeder Quelle (Beutel, Beruf) statt Text hinter dem Namen
        locationLines = "nearest", -- Fundorte unter jeder Quelle: "off", "nearest" oder "several"
        showCoords = true,
        showDistance = true,
        onlyLearned = false,
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
    Glimpse:RegisterAddonOptions(ADDON_NAME, self:BuildOptions(), true) -- true = Tabs
end

function GT:OnEnable()
    -- Die Datenbank ist Pflicht (## Dependencies), die Prüfung fängt nur eine zu alte Version ab
    self.data = Glimpse:GetModule("GatheringDB")
    if (self.data.API_VERSION or 0) < 3 then
        self:Debug("GatheringDB ist zu alt")
        return
    end

    self:RegisterTooltips()
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfo")
    self:RegisterEvent("MODIFIER_STATE_CHANGED", "OnModifierChanged")
end

-- Beim Drücken oder Loslassen den sichtbaren Tooltip neu aufbauen, aber nur wenn Tasten verlangt sind
function GT:OnModifierChanged()
    if Glimpse:ModifiersRequired(self.db.profile) then self:RefreshTooltip() end
end
