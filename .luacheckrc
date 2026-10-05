-- luacheck-Konfiguration für alle Glimpse-Addons (WoW Forever, Lua 5.1-Dialekt)
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "**/Libs/**" }
ignore = {
    "212/self",   -- ungenutztes self
    "212/_.*",    -- ungenutzte Argumente mit Unterstrich
    "211/ADDON_NAME",
}

-- Globale, die die Addons selbst setzen
globals = { "Glimpse", "GlimpseDB", "GlimpseGatheringDB", "SLASH_GLIMPSE1" }

-- Blizzard-API und Mixins (nur lesen)
read_globals = {
    "LibStub", "CreateFrame", "C_Timer", "C_Item", "C_Loot", "C_AddOns", "C_ClickBindings", "C_Spell",
    "C_Container", "C_TooltipInfo", "C_ActionBar", "Enum", "TooltipDataProcessor",
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "UIParent", "Settings",
    "GetTime", "UnitGUID", "UnitName", "UnitLevel", "GetLocale", "GetAddOnMetadata", "IsAddOnLoaded",
    "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown", "issecretvalue", "hooksecurefunc",
    "GetProfessions", "GetProfessionInfo", "GetItemInfoInstant", "GetNumLootItems", "GetLootSlotType",
    "GetLootSlotLink", "GetLootSourceInfo", "GetBindingKey", "GetBindingText", "GetBindingAction",
    "GetActionInfo", "GetMacroInfo", "GetMacroBody", "GetShapeshiftForm", "GetBonusBarOffset",
    "GetActionBarPage", "GetOverrideBarIndex", "HasVehicleActionBar", "HasOverrideActionBar",
    "HasBonusActionBar", "GetNumShapeshiftForms", "InCombatLockdown", "GetCVar",
    "tinsert", "tremove", "wipe", "format", "strsplit", "strjoin", "strmatch", "strtrim", "strlower",
    "strupper", "strfind", "gsub", "strsub", "tostringall", "date", "time", "ceil", "floor",
    "tContains", "CopyTable", "Mixin", "_G",
    "SlashCmdList", "NUM_ACTIONBAR_BUTTONS", "bit", "geterrorhandler", "issecrettable", "TooltipUtil",
    "GetBuildInfo", "GetNumAddOns", "GetAddOnInfo", "GetAddOnDependencies", "MAX_ACCOUNT_MACROS",
    "GetNumBindings", "GetBinding", "GetShapeshiftFormInfo", "GetNumMacros", "GetMacroItem",
    "GetMacroSpell", "ITEM_QUALITY_COLORS",
}

