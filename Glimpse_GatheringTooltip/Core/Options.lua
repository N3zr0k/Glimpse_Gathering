local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Die Optionsseite hat drei Tabs (RegisterAddonOptions mit tabs = true):
--   Allgemein:         gilt für beides
--   Handwerksmaterial: Tooltip eines Materials im Inventar, mit den Quellen
--   Ziel:              Tooltip des Ziels (Sammelknoten, Kreatur)

local function Toggle(self, key, order, name, desc)
    return {
        type = "toggle", order = order, width = "full",
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

function GT:BuildOptions()
    return {
        items = {
            type = "group", order = 2, name = L["Crafting materials"],
            args = {
                showItemSource = Toggle(self, "showItemSource", 1, "Show sources on items",
                    "Show where a crafting material comes from in its tooltip."),
                maxSources = Range(self, "maxSources", 2, "Number of sources",
                    "How many sources are shown: your area first, then other areas, each the most likely first.", 1, 10),
                externalSeparate = {
                    type = "toggle", order = 3, width = "full",
                    name = L["List sources with outside locations separately"],
                    desc = L["On: sources that only have locations from other addons (GatherMate2) come after those with your own. Off: those locations count like your own when sorting."],
                    -- nur sinnvoll, wenn GatheringDB ein Addon mit Fundorten gefunden hat
                    disabled = function() return not (self.data.HasAvailableProvider and self.data:HasAvailableProvider()) end,
                    get = function() return self.db.profile.externalSeparate end,
                    set = function(_, value)
                        self.db.profile.externalSeparate = value
                        self:RefreshTooltip()
                    end,
                },
                showSourceIcons = Toggle(self, "showSourceIcons", 4, "Show source icons",
                    "Show a bag for loot and the profession icon for skinning, herbalism and mining in front of each source. Off: a heading for loot or the profession is shown above its sources."),
                locationLines = {
                    type = "select", order = 5, width = "full",
                    name = L["Locations per source"],
                    desc = L["Shows the location in brackets behind each source: coordinates and distance in your area, the zone or instance elsewhere."],
                    values = function()
                        return {
                            off = L["Off"],
                            nearest = L["Nearest location"],
                            several = L["Up to three zones"],
                        }
                    end,
                    get = function() return self.db.profile.locationLines end,
                    set = function(_, value)
                        self.db.profile.locationLines = value
                        self:RefreshTooltip()
                    end,
                },
                showCoords = Toggle(self, "showCoords", 6, "Show coordinates",
                    "Show the coordinates of locations in your area."),
                showDistance = Toggle(self, "showDistance", 7, "Show distance",
                    "Show the distance in yards to locations in your area."),
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
                maxItems = Range(self, "maxItems", 4, "Items per list",
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
            },
        },
    }
end
