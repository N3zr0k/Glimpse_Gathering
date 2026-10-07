local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Die Optionsseite hat drei Tabs (RegisterAddonOptions mit tabs = true):
--   Allgemein:         gilt für beides
--   Handwerksmaterial: Tooltip eines Materials im Inventar, mit den Quellen
--   Ziel:              Tooltip des Ziels (Sammelknoten, Kreatur)

-- relWidth: Anteil der Breite (0.49 = zwei Haken je Reihe). "half" hat eine feste, kleine Breite und kürzt die Texte.
local function Toggle(self, key, order, name, desc, relWidth)
    return {
        type = "toggle", order = order, width = relWidth and "relative" or "full", relWidth = relWidth,
        name = L[name], desc = L[desc],
        get = function() return self.db.profile[key] end,
        set = function(_, value)
            self.db.profile[key] = value
            self:RefreshTooltip()
        end,
    }
end

local function Range(self, key, order, name, desc, min, max)
    return {
        type = "range", order = order, width = "full",
        name = L[name], desc = L[desc],
        min = min, max = max, step = 1,
        get = function() return self.db.profile[key] end,
        set = function(_, value)
            self.db.profile[key] = value
            self:RefreshTooltip()
        end,
    }
end

-- Auswahl der Markierung für den eigenen Ort: Symbole nebeneinander zum Anklicken, Farbe per Auswahlliste
-- (jeder Eintrag zeigt das gewählte Symbol in seiner Farbe)
local APP_NAME = "Glimpse_GatheringTooltip"

local function IconName(key)
    return ({
        pin = L["Pin"], pinsolid = L["Solid pin"], pinline = L["Outline pin"], person = L["Position"], arrow = L["Arrow"],
    })[key]
end

local function ColorName(key)
    return ({ blue = L["Blue"], white = L["White"], yellow = L["Yellow"], green = L["Green"], red = L["Red"] })[key]
end

function GT:BuildMarkerOptions()
    local function Refresh()
        self:RefreshTooltip()
        LibStub("AceConfigRegistry-3.0"):NotifyChange(Glimpse.name .. "_" .. APP_NAME)
    end

    local args = {
        show = {
            type = "toggle", order = 1, width = "full",
            name = L["Show marker"], desc = L["Symbol in front of the location where you are."],
            get = function() return self.db.profile.showHereIcon ~= false end,
            set = function(_, value) self.db.profile.showHereIcon = value; Refresh() end,
        },
        color = {
            type = "select", order = 2, width = "normal",
            name = L["Color"],
            values = function()
                local values = {}
                for _, key in ipairs(self.MarkerColors) do
                    local path, size = self:MarkerPath(nil, key)
                    values[key] = "|T" .. path .. ":" .. (size + 4) .. "|t  " .. ColorName(key)
                end
                return values
            end,
            sorting = self.MarkerColors,
            get = function() return self.db.profile.hereColor or "blue" end,
            set = function(_, value) self.db.profile.hereColor = value; Refresh() end,
        },
        spacer = { type = "description", order = 3, width = "full", name = " " },
    }

    for index, icon in ipairs(self.MarkerIcons) do
        args["icon_" .. icon.key] = {
            type = "execute", order = 3 + index, width = "relative", relWidth = 0.19,
            image = function() return (self:MarkerPath(icon.key)) end,
            imageWidth = 28, imageHeight = 28,
            name = function()
                local selected = (self.db.profile.hereIcon or "pinsolid") == icon.key
                return (selected and "|cffffd100" or "") .. IconName(icon.key) .. (selected and "|r" or "")
            end,
            desc = L["Click to use this symbol."],
            func = function() self.db.profile.hereIcon = icon.key; Refresh() end,
        }
    end

    return { type = "group", inline = true, order = 10, name = L["Marker for your place"], args = args }
end

-- Wegpunkt zum besten Fundort: Taste (beliebige Kombination aus Strg, Umschalt, Alt und einer Taste) und Hinweis
function GT:BuildWaypointOptions()
    local function Refresh()
        LibStub("AceConfigRegistry-3.0"):NotifyChange(Glimpse.name .. "_" .. APP_NAME)
        self:RefreshTooltip()
    end

    return {
        type = "group", inline = true, order = 4, name = L["Waypoint"],
        args = {
            key = {
                type = "execute", order = 1, width = "normal",
                name = function()
                    if self:IsCapturingKey() then return L["Press a key ..."] end
                    return L["Key"] .. ": " .. self:WaypointKeyName()
                end,
                desc = L["While the tooltip of a crafting material is shown, this key sets a waypoint to its best place: TomTom if installed, otherwise the game marker. Click, then press the new combination (Ctrl, Shift and Alt can be combined). Escape cancels, Delete turns the key off. Keys that are already used in the game are refused."],
                func = function()
                    self:CaptureKey(function(chord)
                        if chord then
                            local ok, conflict = self:SetWaypointKey(chord)
                            if not ok then self:ShowKeyInUse(chord, conflict) end
                        end
                        Refresh()
                    end)
                    Refresh()
                end,
            },
            tomtom = {
                type = "description", order = 2, width = "full",
                name = function()
                    if Glimpse:GetModule("Locations"):HasTomTom() then
                        return "|cff66e066" .. L["TomTom detected: waypoints are set through TomTom."] .. "|r"
                    end
                    return "|cff999999" .. L["TomTom not found: waypoints are set with the game marker."] .. "|r"
                end,
            },
            hint = {
                type = "toggle", order = 3, width = "full",
                name = L["Show hint"], desc = L["Shows the key as a line at the end of the tooltip."],
                disabled = function() return self.db.profile.waypointKey == "off" end,
                get = function() return self.db.profile.showWaypointHint end,
                set = function(_, value)
                    self.db.profile.showWaypointHint = value
                    self:RefreshTooltip()
                end,
            },
        },
    }
end

-- Bildnachweis der Symbole für den Credits-Bereich der Optionsseite (Glimpse:BuildCreditsArgs); die Links stehen in der README
function GT:BuildCredits()
    local images = {}
    for _, credit in ipairs(self.IconCredits) do
        -- der Link steht in Klammern und blau (anklickbar ist er in den Optionen nicht, zum Kopieren)
        images[#images + 1] = (IconName(credit.key) or credit.key) .. " - " .. credit.author .. " |cff66ccff(" .. credit.url .. ")|r"
    end
    return { images = images }
end

function GT:BuildOptions()
    return {
        items = {
            type = "group", order = 2, name = L["Crafting materials"],
            args = {
                showItemSource = Toggle(self, "showItemSource", 1, "Show sources on items",
                    "Show where a crafting material comes from in its tooltip."),
                maxSources = Range(self, "maxSources", 2, "Number of places",
                    "How many places are shown (a source in two zones counts twice). Order: your area first, then other zones on your continent by distance, then everything else.", 1, 10),
                minChance = Range(self, "minChance", 3, "Minimum chance for other zones",
                    "Sources in other zones of your continent are only shown from this chance (in percent). 0 shows all.", 0, 50),
                externalSeparate = {
                    type = "toggle", order = 4, width = "full",
                    name = L["List sources with outside locations separately"],
                    desc = L["On: within each step, sources with locations you found yourself come before those with locations from other addons only (GatherMate2). Off: both count the same."],
                    -- nur sinnvoll, wenn GatheringDB ein Addon mit Fundorten gefunden hat
                    disabled = function() return not (self.data.HasAvailableProvider and self.data:HasAvailableProvider()) end,
                    get = function() return self.db.profile.externalSeparate end,
                    set = function(_, value)
                        self.db.profile.externalSeparate = value
                        self:RefreshTooltip()
                    end,
                },
                showSourceIcons = Toggle(self, "showSourceIcons", 5, "Show source icons",
                    "Show a bag for loot and the profession icon for skinning, herbalism and mining in front of each source. Off: a heading for loot or the profession is shown above its sources."),
                -- Darstellung der Fundorte: vier Haken in zwei Reihen
                display = {
                    type = "group", inline = true, order = 6, name = L["Display"],
                    args = {
                        showLocations = Toggle(self, "showLocations", 1, "Show locations",
                            "Shows the location in brackets behind each source: coordinates and distance in your area, the zone and distance elsewhere.", 0.49),
                        showCoords = Toggle(self, "showCoords", 2, "Show coordinates",
                            "Show the coordinates of locations in your area.", 0.49),
                        showDistance = Toggle(self, "showDistance", 3, "Show distance",
                            "Show the distance to the location.", 0.49),
                        showAttempts = Toggle(self, "showAttempts", 4, "Show attempts",
                            "Show hits and attempts behind the chance, e.g. (13/14), to see how reliable the chance is.", 0.49),
                    },
                },
                hereMarker = self:BuildMarkerOptions(),
            },
        },
        target = {
            type = "group", order = 3, name = L["Target"],
            args = {
                showNodes = Toggle(self, "showNodes", 1, "Show gathering nodes",
                    "Show herb and ore nodes in their tooltips."),
                showLoot = Toggle(self, "showLoot", 2, "Show creature loot",
                    "Show the loot of creatures in their tooltips."),
                showSkinning = Toggle(self, "showSkinning", 3, "Show skinning loot",
                    "Show the skinning loot of creatures in their tooltips."),
                showNodeSkill = Toggle(self, "showNodeSkill", 4, "Show required skill on nodes",
                    "Show the skill a herb or ore node needs, your own skill and the colour in its tooltip."),
                showMobSkill = Toggle(self, "showMobSkill", 5, "Show required skill on creatures",
                    "Show the skinning skill a creature needs. Creatures with recorded skinning loot are shown for sure, beasts and dragonkin as a guess."),
                skillOnlyLearned = Toggle(self, "skillOnlyLearned", 6, "Skill only for learned professions",
                    "Only show the required skill if you have the profession."),
                hideGraySkill = Toggle(self, "hideGraySkill", 7, "Hide gray nodes",
                    "Do not show the skill for nodes and creatures that no longer raise your skill."),
                maxItems = Range(self, "maxItems", 8, "Items per list",
                    "Maximum number of items shown per list.", 1, 20),
            },
        },
        general = {
            type = "group", order = 1, name = L["General"],
            args = {
                onlyLearned = Toggle(self, "onlyLearned", 1, "Only learned professions",
                    "Only show nodes, skinning loot and sources for professions you have learned."),
                minAttempts = Range(self, "minAttempts", 2, "Minimum attempts",
                    "Lists are only shown after this many recorded attempts.", 1, 20),
                modifiers = Glimpse:BuildModifierOptions(self.db.profile, function() self:RefreshTooltip() end, 3),
                waypoint = self:BuildWaypointOptions(),
            },
        },
    }
end
