-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Skill-Daten und -Abfragen (GatheringData: Core/Data/SkillData.lua, Core/Data/Skills.lua) und die Zeile im Tooltip
-- (Core/Tooltip/Skills.lua)
local function setupDB(api)
    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringData")
    DB.L = Glimpse.L
    DB.db = { profile = { recording = true } }
    DB.api = api or {}
    -- Knoten und Kreaturen statt Glimpse: Database, Aufbau wie GetNode/GetNPC
    DB.known = { nodes = {}, npcs = {} }
    function DB:GetNode(id) return self.known.nodes[id] end
    function DB:GetNPC(id) return self.known.npcs[id] end
    stub.load("Glimpse_Gathering/Core/Data/SkillData.lua", "Glimpse_Gathering")
    stub.load("Glimpse_Gathering/Core/Data/Skills.lua", "Glimpse_Gathering")
    return DB, Glimpse
end

-- Berufe über GetProfessions/GetProfessionInfo: Liste aus { Name, Skill, Maximum, Skill-Linie, Bonus }
local function professionAPI(list)
    return {
        GetProfessions = function() local t = {} for i = 1, #list do t[i] = i end return unpack(t) end,
        GetProfessionInfo = function(i)
            local p = list[i]
            return p[1], "", p[2], p[3], 0, 0, p[4], p[5] or 0
        end,
    }
end

test("Skills: Kürschnerei nach Kreaturenstufe", function()
    local DB = setupDB()
    eq(DB:GetSkinningSkill(1), 1, "Stufe 1")
    eq(DB:GetSkinningSkill(10), 1, "Stufe 10")
    eq(DB:GetSkinningSkill(11), 10, "Stufe 11")
    eq(DB:GetSkinningSkill(15), 50, "Stufe 15")
    eq(DB:GetSkinningSkill(20), 100, "Stufe 20")
    eq(DB:GetSkinningSkill(21), 105, "Stufe 21")
    eq(DB:GetSkinningSkill(30), 150, "Stufe 30")
    eq(DB:GetSkinningSkill(-1), nil, "Boss")
    eq(DB:GetSkinningSkill(nil), nil, "unbekannt")
end)

test("Skills: Farbgrenzen", function()
    local DB = setupDB()
    eq((DB:GetSkillColor(155, 154)), "red", "knapp zu niedrig")
    eq((DB:GetSkillColor(155, 155)), "orange", "genau")
    eq((DB:GetSkillColor(155, 179)), "orange", "+24")
    eq((DB:GetSkillColor(155, 180)), "yellow", "+25")
    eq((DB:GetSkillColor(155, 204)), "yellow", "+49")
    eq((DB:GetSkillColor(155, 205)), "green", "+50")
    eq((DB:GetSkillColor(155, 254)), "green", "+99")
    eq((DB:GetSkillColor(155, 255)), "gray", "+100")
    eq(DB:GetSkillColor(nil, 5), nil, "ohne Zahl")
    local _, r, g, b = DB:GetSkillColor(1, 1)
    eq(r, 1, "Rot-Anteil orange"); eq(g, 0.5, "Grün-Anteil"); eq(b, 0.25, "Blau-Anteil")
end)

test("Skills: Knoten nach ID, sonst über das Material", function()
    local DB = setupDB()
    local profession, required = DB:GetRequiredSkill("node", 1734)
    eq(profession, "ore", "Goldader: Beruf"); eq(required, 155, "Goldader: Skill")
    eq(DB:GetNodeSkill(1620), "herb", "Mageroyal")
    eq(DB:GetNodeSkill(999999), nil, "unbekannt")

    -- unbekannte ID, aber das Material ist bekannt (Zinn, Item 2771)
    DB.known.nodes[999999] = { name = "Zinnader?", category = "ore", attempts = 3, items = { [2771] = { hits = 3, amount = 3 } } }
    local p, r = DB:GetNodeSkill(999999)
    eq(p, "ore", "über das Material: Beruf"); eq(r, 65, "über das Material: Skill")

    -- widersprüchliche Materialien: keine Aussage
    DB.known.nodes[999998] = { name = "?", category = "ore", attempts = 3, items = { [2771] = { hits = 1, amount = 1 }, [2775] = { hits = 1, amount = 1 } } }
    eq(DB:GetNodeSkill(999998), nil, "uneinig")
end)

test("Skills: Kreaturen, bekannt oder nur vermutet", function()
    local DB = setupDB()
    DB.known.npcs[100] = { name = "Wolf", level = 15, skinning = { attempts = 4, items = {} } }
    DB.known.npcs[101] = { name = "Gnoll", level = 15 }
    local profession, required, known = DB:GetRequiredSkill("npc", 100)
    eq(profession, "skinning", "Beruf"); eq(required, 50, "Skill nach gespeicherter Stufe"); eq(known, true, "bekannt")
    eq(select(3, DB:GetRequiredSkill("npc", 101)), false, "nicht bekannt")
    eq(select(2, DB:GetRequiredSkill("npc", 101, 25)), 125, "Stufe aus dem Aufruf")
    eq(DB:GetRequiredSkill("npc", 555), nil, "ohne Stufe")
end)

test("Skills: Skill des Spielers über GetProfessionInfo, mit Cache", function()
    local list = { { "Bergbau", 100, 150, 186, 5 }, { "Kürschnerei", 40, 75, 393 } }
    local DB = setupDB(professionAPI(list))
    local current, max, name, rank = DB:GetPlayerSkill("ore")
    eq(current, 105, "mit Bonus"); eq(max, 150, "Maximum"); eq(name, "Bergbau", "Name aus dem Client"); eq(rank, 100, "ohne Bonus")
    eq(DB:GetPlayerSkill("herb"), nil, "nicht gelernt")
    eq(DB:HasProfession("herb"), false, "HasProfession")
    eq(DB:HasProfession("skinning"), true, "HasProfession gelernt")

    list[1][2] = 120 -- ohne Ereignis bleibt der Cache
    eq(DB:GetPlayerSkill("ore"), 105, "Cache")
    DB:OnSkillsChanged()
    eq(DB:GetPlayerSkill("ore"), 125, "nach SKILL_LINES_CHANGED")
end)

test("Skills: Ersatzweg über GetSkillLineInfo, Namen aus dem Berufszauber", function()
    local lines = {
        { "Berufe", true }, { "Kräutersammeln", false, 0, 60, 0, 3, 150 }, { "Waffen", false, 0, 1, 0, 0, 5 },
    }
    local DB = setupDB({
        GetNumSkillLines = function() return #lines end,
        GetSkillLineInfo = function(i) return unpack(lines[i]) end,
        GetSpellName = function(id) return id == 2366 and "Kräutersammeln" or nil end,
    })
    local current = DB:GetPlayerSkill("herb")
    eq(current, 63, "Kräuterkunde über den Zaubernamen")
    eq(DB:GetPlayerSkill("ore"), nil, "Bergbau nicht gelernt")
end)

test("Skills: ohne Berufs-API ist alles unbekannt", function()
    local DB = setupDB()
    eq(DB:GetPlayerSkill("ore"), nil, "kein Skill")
    eq(DB:HasProfession("ore"), nil, "weder ja noch nein")
end)

test("Skills: Kreaturentyp über die ID oder den Namen", function()
    local DB = setupDB({ UnitCreatureType = function() return "Wildtier", 1 end })
    eq(DB:GetCreatureTypeID("target"), 1, "ID aus dem Client")
    eq(DB:IsSkinnableType(1), true, "Wildtier"); eq(DB:IsSkinnableType(2), true, "Drachkin"); eq(DB:IsSkinnableType(7), false, "Humanoid")

    local old = setupDB({
        UnitCreatureType = function() return "Beast" end,
        GetCreatureTypeInfo = function(id) return { name = id == 1 and "Beast" or ("Typ" .. id) } end,
    })
    eq(old:GetCreatureTypeID("target"), 1, "Name zugeordnet")
end)

-- Tooltip-Zeile
local function setupTooltip(profile, professions)
    local DB, Glimpse = setupDB(professionAPI(professions or { { "Bergbau", 100, 150, 186 }, { "Kürschnerei", 40, 75, 393 } }))
    local GT = Glimpse:NewModule("GatheringTooltip")
    GT.L = Glimpse.L
    GT.data = DB
    GT.db = { profile = { showNodeSkill = true, showMobSkill = true, skillOnlyLearned = true, hideGraySkill = false } }
    for key, value in pairs(profile or {}) do GT.db.profile[key] = value end
    stub.load("Glimpse_Gathering/Core/Tooltip/Sources.lua", "Glimpse_Gathering")
    stub.load("Glimpse_Gathering/Core/Tooltip/Skills.lua", "Glimpse_Gathering")
    return GT, DB
end

local function fakeTooltip(lines)
    local name = "FakeTip"
    for i, text in ipairs(lines) do _G[name .. "TextLeft" .. i] = { GetText = function() return text end } end
    return { GetName = function() return name end, NumLines = function() return #lines end }
end

test("Tooltip: Skill-Zeile für einen Erzknoten in der Farbe des eigenen Skills", function()
    local GT = setupTooltip()
    local row = GT:NodeSkillRow(1734, nil, fakeTooltip({ "Goldader" })) -- 155, eigener Skill 100: zu niedrig
    assert(row, "Zeile")
    eq(row[1], "Skill: |cffff1a1a100|r - requires Bergbau 155", "nur die Zahl ist rot")
    eq(row[6] or row.icon, "Interface\\Icons\\Trade_Mining", "Symbol")

    local silver = GT:NodeSkillRow(1733, nil, fakeTooltip({ "Silberader" })) -- 75, eigener 100: +25 gelb
    eq(silver[1], "Skill: |cffffff00100|r - requires Bergbau 75", "gelb")
end)

test("Tooltip: Optionen für Knoten", function()
    local GT = setupTooltip()
    eq(GT:NodeSkillRow(1620, nil, fakeTooltip({ "Mageroyal" })), nil, "Kräuterkunde nicht gelernt")

    GT.db.profile.skillOnlyLearned = false
    local row = GT:NodeSkillRow(1620, nil, fakeTooltip({ "Mageroyal" }))
    eq(row[1], "not learned - requires Herbalism 50", "nicht gelernt, aber angezeigt")

    GT.db.profile.showNodeSkill = false
    eq(GT:NodeSkillRow(1620, nil, fakeTooltip({ "x" })), nil, "Option aus")

    local skilled = { { "Bergbau", 150, 150, 186 } }
    local gray = setupTooltip({ hideGraySkill = true }, skilled)
    eq(gray:NodeSkillRow(1731, nil, fakeTooltip({ "Kupfer" })), nil, "Kupfer bei Skill 150 ist grau")
    local shown = setupTooltip({ hideGraySkill = false }, skilled)
    assert(shown:NodeSkillRow(1731, nil, fakeTooltip({ "Kupfer" })), "grau, aber nicht ausgeblendet")
end)

test("Tooltip: keine zweite Zeile, wenn die Anforderung schon dasteht", function()
    local GT = setupTooltip()
    eq(GT:NodeSkillRow(1734, nil, fakeTooltip({ "Goldader", "Benötigt Bergbau (155)" })), nil, "schon vorhanden")
    -- 15 steckt in 155, zählt aber nicht
    assert(GT:NodeSkillRow(1734, nil, fakeTooltip({ "Goldader", "Bergbau 15" })), "Zahl nur als ganzes Wort")
end)

test("Tooltip: Skill-Zeile für Kreaturen, sicher und vermutet", function()
    local GT, DB = setupTooltip()
    stub.units.mouseover = { guid = "Creature-0-1-2-3-100-0000", level = 15 }
    DB.known.npcs[100] = { name = "Wolf", level = 15, skinning = { attempts = 2, items = {} } }
    DB.known.npcs[101] = { name = "Bär", level = 15 }

    local row = GT:UnitSkillRow(100, { guid = "Creature-0-1-2-3-100-0000" }, fakeTooltip({ "Wolf" }))
    eq(row[1], "Skill: |cffff1a1a40|r - requires Kürschnerei 50", "sicher kürschnerbar, Skill 40 reicht nicht")

    -- unbekannt und ohne Typ-Hinweis: nichts
    stub.units.mouseover = { guid = "Creature-0-1-2-3-101-0000", level = 15 }
    eq(GT:UnitSkillRow(101, { guid = "Creature-0-1-2-3-101-0000" }, fakeTooltip({ "Bär" })), nil, "kein Hinweis")

    -- Wildtier: Vermutung
    DB.api.UnitCreatureType = function() return "Beast", 1 end
    local guess = GT:UnitSkillRow(101, { guid = "Creature-0-1-2-3-101-0000" }, fakeTooltip({ "Bär" }))
    assert(guess and guess[1]:find("possibly requires Kürschnerei 50", 1, true), "vermutet")

    -- Boss
    stub.units.mouseover.level = -1
    DB.known.npcs[101].level = nil
    eq(GT:UnitSkillRow(101, { guid = "Creature-0-1-2-3-101-0000" }, fakeTooltip({ "Boss" })), nil, "Boss ohne Angabe")
end)

test("Tooltip: Häutbar-Zeile des Clients macht sicher und liefert die Farbe", function()
    local GT, DB = setupTooltip()
    _G.UNIT_SKINNABLE_LEATHER = "Häutbar"
    DB.known.npcs[102] = { name = "Leopard", level = 8 } -- nie gekürschnert, also nur Vermutung
    stub.units.mouseover = { guid = "Creature-0-1-2-3-102-0000", level = 8 }
    local data = { guid = "Creature-0-1-2-3-102-0000" }

    eq(GT:UnitSkillRow(102, data, fakeTooltip({ "Leopard" })), nil, "ohne Häutbar-Zeile und ohne Typ nichts")
    local plain = GT:UnitSkillRow(102, data, fakeTooltip({ "Leopard", "Häutbar" }))
    assert(plain and plain[1]:find("requires", 1, true), "Zeile auch ohne lesbare Farbe, dann berechnet")

    local tip = fakeTooltip({ "Leopard", "Häutbar" })
    _G.FakeTipTextLeft2.GetTextColor = function() return 0, 1, 0 end
    local row = GT:UnitSkillRow(102, data, tip)
    assert(row, "Zeile durch den Client-Hinweis")
    assert(row[1]:find("|cff00ff00", 1, true), "Farbe vom Client")
    assert(not row[1]:find("possibly", 1, true), "sicher, keine Vermutung")
    _G.UNIT_SKINNABLE_LEATHER = nil
end)

test("Tooltip: Angelrute bleibt unverändert (der Angel-Skill steht bei Glimpse: Professions)", function()
    local GT = setupTooltip({}, { { "Angeln", 1, 75, 356 } })
    _G.C_Item = { GetItemInfoInstant = function(id) return id, "", "", "", "", id == 6256 and 2 or 7, id == 6256 and 20 or 8 end }
    LibStub():GetAddon().ModifiersHeld = function() return true end
    local callbacks = {}
    function GT:RegisterTooltipLine(kind, func) callbacks[kind] = func end
    _G.Enum.TooltipDataType = { Object = 1, Unit = 2, Item = 3 }
    _G.GetItemInfoInstant = _G.C_Item.GetItemInfoInstant
    GT.data.GetLocatedItemSources = function() return {} end
    GT.db.profile.showItemSource = true
    GT.SetWaypointTarget = function() end
    GT.db.profile.minAttempts, GT.db.profile.maxSources, GT.db.profile.minChance = 1, 3, 10
    stub.load("Glimpse_Gathering/Core/Tooltip/Tooltip.lua", "Glimpse_Gathering")
    GT:RegisterTooltips()

    local rows = callbacks[3](GT, { id = 6256 }, {})
    eq(rows, nil, "keine Skill-Zeile auf der Angelrute")
    eq(callbacks[3](GT, { id = 2589 }, {}), nil, "andere Items unverändert")
    _G.C_Item, _G.GetItemInfoInstant = nil, nil
end)
