-- luacheck: ignore 111 113 122 143 432
-- Minimale Nachbildung der WoW-Umgebung, damit sich die reine Logik der Addons offline testen lässt.
-- Aufruf aus dem Ordner mit den Addon-Ordnern:  lua tests/run.lua
local stub = {}

local ROOT = ((arg and arg[0] or ""):match("^(.*)/[^/]*$") or ".") .. "/.."
stub.root = ROOT

-- Ordner des Kerns Glimpse (mit Modules/Locations)
function stub.coreDir()
    -- Jeder Kandidat ist ein Repo (Addon im Unterordner Glimpse) oder der Addon-Ordner selbst
    local candidates = { os.getenv("GLIMPSE_DIR"), ROOT .. "/../Glimpse", ROOT .. "/.glimpse" }
    for _, base in ipairs(candidates) do
        for _, dir in ipairs({ base .. "/Glimpse", base }) do
            local file = io.open(dir .. "/Modules/Locations/Locations.lua", "r")
            if file then file:close() return dir end
        end
    end
    return ROOT .. "/../Glimpse/Glimpse"
end

-- Globale der SavedVariables und von Database, für jeden Test und jeden neuen Start
local GLOBALS = { "GlimpseDB", "GlimpseDB_Meta", "GlimpseDB_Core", "GlimpseDB_Gathering", "GlimpseDB_Professions",
    "GlimpseDB_Reputation", "GlimpseDB_Misc", "GlimpseGatheringDB", "GlimpseGatheringNames", "GatherMate2" }

function stub.reset()
    -- Lua-5.1-Ausdrücke, die der Client mitbringt
    _G.unpack = _G.unpack or table.unpack -- Lua 5.4 (CI) hat nur table.unpack, der Client bringt unpack mit
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.format = string.format
    _G.strmatch = string.match
    _G.strlower = string.lower
    _G.gsub = string.gsub
    _G.strsplit = function(sep, text)
        local parts, pos = {}, 1
        while true do
            local from, to = text:find(sep, pos, true)
            if not from then parts[#parts + 1] = text:sub(pos) break end
            parts[#parts + 1] = text:sub(pos, from - 1)
            pos = to + 1
        end
        return (table.unpack or unpack)(parts)
    end
    _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

    _G.time = function() return stub.clock end
    stub.clock = 1700000000

    -- Spielzeit und Zeitgeber, vom Test gesteuert
    stub.now = 0
    stub.timers = {}
    _G.GetTime = function() return stub.now end
    _G.C_Timer = { After = function(_, func) stub.timers[#stub.timers + 1] = func end }
    function stub.flush()
        local list = stub.timers
        stub.timers = {}
        for _, func in ipairs(list) do func() end
    end

    stub.keys = { shift = false, ctrl = false, alt = false }
    _G.IsShiftKeyDown = function() return stub.keys.shift end
    _G.IsControlKeyDown = function() return stub.keys.ctrl end
    _G.IsAltKeyDown = function() return stub.keys.alt end

    _G.Enum = {
        LootSlotType = { Item = 1 },
        ItemClass = { Tradegoods = 7, Gem = 3, Weapon = 2 },
        ItemTradeGoodsSubclass = { Herb = 9, MetalStone = 7 },
    }

    -- Für Glimpse_Database: Serverzeit, Spieler, Fehlerbehandlung, LoadOnDemand-Bereiche
    _G.date = os.date
    _G.debugprofilestop = function() return os.clock() * 1000 end
    _G.securecallfunction = function(func, ...) return func(...) end
    _G.geterrorhandler = function() return function(err) error(err, 0) end end
    stub.serverTime = 1767225600 + 86400 * 10 -- 2026-01-11 00:00 UTC
    _G.GetServerTime = function() return stub.serverTime end
    _G.UnitClass = function() return "MAGE", "MAGE" end
    _G.GetRealmName = function() return "Forever" end
    _G.C_AddOns = {
        IsAddOnLoaded = function(name) return stub.addons[name] == true end,
        LoadAddOn = function(name) stub.addons[name] = true return true end,
        GetAddOnMetadata = function(_, field) if field == "Version" then return stub.databaseVersion end end,
    }
    stub.addons = {}
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
    stub.realLibStub = nil

    stub.units = { player = { guid = "Player-1-00000001", name = "Flovy" } }
    _G.UnitGUID = function(unit) return stub.units[unit] and stub.units[unit].guid end
    _G.UnitName = function(unit) return stub.units[unit] and stub.units[unit].name end
    _G.UnitLevel = function(unit) return stub.units[unit] and stub.units[unit].level end

    -- Frame, das nur Skripte und Events merkt
    stub.frames = {}
    _G.CreateFrame = function()
        local frame = { events = {} }
        function frame:SetScript(_, func) self.onEvent = func end
        function frame:RegisterUnitEvent(event) self.events[event] = true end
        function frame:RegisterEvent(event)
            -- Standard: der Client kennt PARTY_KILL nicht (die Tests des Ersatzwegs); stub.partyKill = true schaltet es ein
            if event == "PARTY_KILL" and not stub.partyKill then error("Attempt to register unknown event") end
            self.events[event] = true
        end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        stub.frames[#stub.frames + 1] = frame
        return frame
    end
end

-- Das Addon-Objekt und seine Module
function stub.newGlimpse()
    local Glimpse = { L = setmetatable({}, { __index = function(_, key) return key end }), modules = {} }
    function Glimpse:IsSecret() return false end
    function Glimpse:GetModule(name) return self.modules[name] end
    function Glimpse:NewModule(name)
        local module = {
            name = name, messages = {}, debugLines = {},
            Debug = function(self, ...) self.debugLines[#self.debugLines + 1] = table.concat({ ... }, " ") end,
            SendMessage = function(self, message, ...) self.messages[#self.messages + 1] = { message, ... } end,
            RegisterEvent = function() end,
            UnregisterEvent = function() end,
        }
        self.modules[name] = module
        return module
    end

    -- Das Modul Locations gehört zum Kern (Repo Glimpse) und wird von dort geladen. Gesucht wird in dieser
    -- Reihenfolge: Umgebungsvariable GLIMPSE_DIR (so macht es die CI), Nachbarordner Glimpse, Ordner .glimpse im Repo.
    -- Seine Blizzard-Funktionen stehen in Locations.api, die Tests ersetzen sie.
    _G.LibStub = function() return { GetAddon = function() return Glimpse end } end
    local core = stub.coreDir()
    -- Ab Core 0.3.40 liegt Locations unter Modules/Helper/
    local dir = core .. "/Modules/Helper/Locations/"
    local probe = io.open(dir .. "Locations.lua")
    if probe then probe:close() else dir = core .. "/Modules/Locations/" end
    for _, file in ipairs({ "Locations", "Maps", "Position", "Distance", "Units", "Coords", "Waypoint" }) do
        local chunk, err = loadfile(dir .. file .. ".lua")
        assert(chunk, "Kern Glimpse nicht gefunden (Modul Locations), siehe tests/wowstub.lua: " .. tostring(err))
        chunk("Glimpse")
    end
    Glimpse.db = { profile = {} }
    Glimpse.modules.Locations.api = {}

    -- Ace3 ist nachgebaut; Bibliotheken von Glimpse_Database (CallbackHandler ...) kommen aus dessen LibStub
    _G.LibStub = function(name)
        if name == "AceLocale-3.0" then return { GetLocale = function() return Glimpse.L end } end
        local lib = name and stub.realLibStub and stub.realLibStub(name, true)
        if lib then return lib end
        return { GetAddon = function() return Glimpse end }
    end
    return Glimpse
end

-- Dateien einer XML in Ladereihenfolge (Script und Include, rekursiv), wie der Client
local function XmlFiles(path, list)
    local base = path:match("^(.*)/[^/]*$")
    local handle = assert(io.open(path))
    local text = handle:read("*a"):gsub("<!%-%-.-%-%->", "")
    handle:close()
    for tag, file in text:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
        file = base .. "/" .. file:gsub("\\", "/")
        if tag == "Include" then XmlFiles(file, list) else list[#list + 1] = file end
    end
    return list
end
stub.XmlFiles = XmlFiles

-- Ereignis an alle Frames, die es angemeldet haben
function stub.fire(event, ...)
    for _, frame in ipairs(stub.frames) do
        if frame.events[event] and frame.onEvent then frame.onEvent(frame, event, ...) end
    end
end

--- Lädt die echte Glimpse_Database aus dem Kern-Repo (Ordner neben dem Addon Glimpse) wie der Client: Dateien,
-- SavedVariables (saved, optional), ADDON_LOADED. PLAYER_LOGIN löst der Aufrufer aus (stub.login).
function stub.loadDatabase(saved)
    local dir = stub.coreDir() .. "/../Glimpse_Database"
    local toc = io.open(dir .. "/Glimpse_Database.toc")
    assert(toc, "Glimpse_Database nicht gefunden, siehe tests/wowstub.lua (GLIMPSE_DIR)")
    stub.databaseVersion = toc:read("*a"):match("## Version: (%S+)")
    toc:close()

    local fake = _G.LibStub
    _G.LibStub = nil -- die eingebettete LibStub legt sich selbst an
    local private = {}
    for _, file in ipairs(XmlFiles(dir .. "/Glimpse_Database.xml", {})) do
        assert(loadfile(file))("Glimpse_Database", private)
    end
    stub.realLibStub = _G.LibStub
    _G.LibStub = fake

    for name, value in pairs(saved or {}) do _G[name] = value end
    stub.fire("ADDON_LOADED", "Glimpse_Database")
    stub.databasePrivate = private
    return _G.GlimpseDB, private
end

function stub.login()
    stub.fire("PLAYER_LOGIN")
end

-- Debugger wie Glimpse:NewDebugger, merkt die Zeilen in stub.debugLines; stub.debugOn = false schaltet ab
local function NewDebugger(name)
    local debugger = { name = name }
    function debugger:IsOn() return stub.debugOn ~= false end
    local function Add(_, category, text, ...)
        if select("#", ...) > 0 then text = format(text, ...) end
        stub.debugLines[#stub.debugLines + 1] = category .. ": " .. text
    end
    function debugger:Log(...) if self:IsOn() then Add(self, ...) end end
    debugger.Warn = debugger.Log
    debugger.Error = Add
    return debugger
end

--- Glimpse (nachgebaut) mit Locations, die echte Glimpse_Database und der Datenteil von Glimpse: Gathering nach
-- seiner XML (ohne Locales und Anzeige), dazu OnInitialize, PLAYER_LOGIN und OnEnable wie im Client. options:
--   saved       SavedVariables vor dem Laden ({ GlimpseGatheringNames = ..., GlimpseDB_Meta = ... })
--   noDatabase  ohne Glimpse_Database
--   display     auch den Anzeigeteil laden und GatheringTooltip:OnInitialize aufrufen (stub.lastOptions)
--   noEnable    nur bis OnInitialize und PLAYER_LOGIN
--   api         Ersatz für Einträge in DB.api (Blizzard-Funktionen)
-- Gibt das Modul GatheringData und Glimpse zurück.
-- Locales und Anzeigeteil (Modul GatheringTooltip) lädt jeder Test selbst
local DISPLAY = { "/Locales/", "/Core/Tooltip/", "/Core/GatheringTooltip.lua", "/Core/Professions.lua", "/Core/Options.lua" }

local function IsDisplayFile(file)
    for _, part in ipairs(DISPLAY) do
        if file:find(part, 1, true) then return true end
    end
    return false
end

function stub.newGatheringDB(options)
    options = options or {}
    -- neuer Start: alte Frames und Daten (außer GatherMate2) vergessen
    stub.frames, stub.addons = {}, {}
    for _, name in ipairs(GLOBALS) do
        if name ~= "GatherMate2" then _G[name] = nil end
    end
    local Glimpse = stub.newGlimpse()
    Glimpse.name = "Glimpse"
    stub.debugLines, stub.printed, Glimpse.probes, Glimpse.dataSources = {}, {}, {}, {}
    function Glimpse:NewDebugger(name) return NewDebugger(name) end
    function Glimpse:RegisterProbe(group, name, func) self.probes[group .. " " .. name] = func end
    function Glimpse:RegisterDataSource(addon, func) self.dataSources[addon] = func end
    function Glimpse:RegisterAddonOptions(addon, args, tabs)
        self.options = args
        stub.lastOptions = { addon = addon, args = args, tabs = tabs }
    end
    function Glimpse:BuildModifierOptions() return { type = "group", args = {} } end
    function Glimpse:Print(text) stub.printed[#stub.printed + 1] = text end
    function Glimpse:IsDebug() return stub.debugOn ~= false end
    function Glimpse:DebugTag(addon) return "[" .. tostring(addon or self.name) .. "]" end
    Glimpse.db.RegisterNamespace = function(_, _, defaults)
        local profile = {}
        for key, value in pairs(defaults.profile) do profile[key] = type(value) == "table" and {} or value end
        return { profile = profile }
    end
    local newModule = Glimpse.NewModule
    function Glimpse:NewModule(name)
        local module = newModule(self, name)
        module.events, module.tooltipLines = {}, {}
        function module:GetName() return name end
        function module:RegisterEvent(event, method) self.events[event] = method or true end
        function module:UnregisterEvent(event) self.events[event] = nil end
        function module:RegisterMessage() end
        function module:RegisterTooltipLine(kind, func) self.tooltipLines[kind] = func end
        return module
    end
    _G.Enum.TooltipDataType = { Item = 0, Unit = 2, Object = 9 }
    _G.C_Item = _G.C_Item or { GetItemNameByID = function() return nil end }

    for name, value in pairs(options.saved or {}) do
        if not name:find("^GlimpseDB") then _G[name] = value end
    end
    if not options.noDatabase then stub.loadDatabase(options.saved) end

    local addon = stub.root .. "/Glimpse_Gathering"
    for _, file in ipairs(XmlFiles(addon .. "/Glimpse_Gathering.xml", {})) do
        local skip = file:find("/Locales/", 1, true) or (not options.display and IsDisplayFile(file))
        if not skip then assert(loadfile(file))("Glimpse_Gathering") end
    end
    local DB = Glimpse:GetModule("GatheringData")
    for name, func in pairs(options.api or {}) do DB.api[name] = func end
    DB:OnInitialize()
    if options.display then Glimpse:GetModule("GatheringTooltip"):OnInitialize() end
    if not options.noDatabase then stub.login() end
    if not options.noEnable then DB:OnEnable() end
    return DB, Glimpse
end

-- Lädt eine Addon-Datei, ADDON_NAME wird wie vom Client als erstes Argument übergeben
function stub.load(path, addonName)
    local chunk, err = loadfile(ROOT .. "/" .. path)
    assert(chunk, err)
    return chunk(addonName or "Test")
end

return stub
