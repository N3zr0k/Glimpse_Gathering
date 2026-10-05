-- luacheck: ignore 111 113 122 143 432
-- Minimale Nachbildung der WoW-Umgebung, damit sich die reine Logik der Addons offline testen lässt.
-- Aufruf aus dem Ordner mit den Addon-Ordnern:  lua tests/run.lua
local stub = {}

local ROOT = ((arg and arg[0] or ""):match("^(.*)/[^/]*$") or ".") .. "/.."
stub.root = ROOT

function stub.reset()
    -- Lua-5.1-Ausdrücke, die der Client mitbringt
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

    stub.units = {}
    _G.UnitGUID = function(unit) return stub.units[unit] and stub.units[unit].guid end
    _G.UnitName = function(unit) return stub.units[unit] and stub.units[unit].name end
    _G.UnitLevel = function(unit) return stub.units[unit] and stub.units[unit].level end

    -- Frame, das nur Skripte und Events merkt
    stub.frames = {}
    _G.CreateFrame = function()
        local frame = { events = {} }
        function frame:SetScript(_, func) self.onEvent = func end
        function frame:RegisterUnitEvent(event) self.events[event] = true end
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

    -- Mitgelieferte Bibliotheken sind über stub.libs erreichbar (LibStub("LibDeflate", true))
    _G.LibStub = function(name)
        if name == "LibDeflate" then return stub.libs.LibDeflate end
        return { GetAddon = function() return Glimpse end }
    end
    return Glimpse
end

stub.libs = {}
local deflate

--- Lädt LibDeflate (einmal) und macht es über LibStub("LibDeflate", true) verfügbar. Ohne Aufruf
-- (oder mit stub.libs.LibDeflate = nil) gibt es keine Kompression, dann exportiert das Addon unkomprimiert.
function stub.useLibDeflate()
    if not deflate then
        local savedStub, savedArg = _G.LibStub, _G.arg
        _G.LibStub, _G.arg = nil, nil -- die Bibliothek läuft dann allein, ohne LibStub und ohne Kommandozeile
        deflate = stub.load("Glimpse_GatheringDB/Libs/LibDeflate/LibDeflate.lua")
        _G.LibStub, _G.arg = savedStub, savedArg
    end
    stub.libs.LibDeflate = deflate
    return deflate
end

-- Lädt eine Addon-Datei, ADDON_NAME wird wie vom Client als erstes Argument übergeben
function stub.load(path, addonName)
    local chunk, err = loadfile(ROOT .. "/" .. path)
    assert(chunk, err)
    return chunk(addonName or "Test")
end

return stub
