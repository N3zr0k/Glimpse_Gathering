-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Angeln: Gathering zeichnet nichts auf, liest aber den Namespace fishing (schreibt Glimpse: Professions).
-- Hier übernimmt der Test die Rolle von Professions. Items: 300 = Fisch, 301 = Edelstein.
local function setup(api)
    local DB = stub.newGatheringDB({ api = api })
    local fishing = assert(GlimpseDB:Register("fishing", {
        area = "Professions", zones = true, world = { looted = true, loot = true, drop = true },
    }))
    -- ein Beutefenster in einer Zone, items = { [itemID] = Menge }
    local function catch(zone, items)
        fishing:Count("looted", zone, zone)
        for itemID, amount in pairs(items) do
            fishing:Count("loot:" .. zone, itemID, nil, amount)
            fishing:Count("drop:" .. zone, itemID)
        end
    end
    return DB, catch, fishing
end

test("Angeln: Fänge einer Zone aus dem Namespace fishing", function()
    local DB, catch = setup()
    eq(DB:GetFishing(37), nil, "noch nichts")
    catch(37, { [300] = 2 })
    catch(37, { [300] = 1, [301] = 1 })
    catch(37, {})

    local zone = DB:GetFishing(37)
    eq(zone.attempts, 3, "Beutefenster")
    eq(zone.items[300].hits, 2, "Fenster mit Fisch")
    eq(zone.items[300].amount, 3, "Menge Fisch")

    local drops, windows = DB:GetFishingDrops(37)
    eq(windows, 3, "Fenster")
    eq(drops[1].itemID, 300, "häufigster Fang zuerst")
    near(drops[1].chance, 2 / 3, "Chance")
    eq(DB:GetFishing(38), nil, "andere Zone")
end)

test("Angeln: Zone als Quelle im Index eines Fisches, mit Fundort", function()
    local DB, catch = setup()
    catch(37, { [300] = 1 })
    local sources = DB:GetItemSources(300)
    eq(#sources, 1, "eine Quelle")
    eq(sources[1].kind, "fishing", "Art")
    eq(sources[1].id, 37, "ID = Zone")
    eq(sources[1].mode, "fishing", "Modus")

    local spots = DB:GetOwnSpots("fishing", 37)
    eq(#spots, 1, "ein Fundort")
    eq(spots[1].map, 37, "Zone")
    eq(spots[1].x, nil, "ohne Koordinaten")
    eq(spots[1].count, 1, "Funde")
end)

test("Angeln: Änderung im Namespace fishing leert den Zwischenspeicher", function()
    local DB, catch = setup()
    catch(37, { [300] = 1 })
    eq(DB:GetFishing(37).attempts, 1, "erst eins")
    catch(37, { [300] = 1 })
    eq(DB:GetFishing(37).attempts, 2, "nach der Änderung")
    eq(#DB:GetItemSources(300), 1, "Index neu gebaut")
end)

test("Angeln: Statistik und Probe", function()
    local DB, catch = setup()
    catch(37, { [300] = 1 })
    catch(40, {})
    local _, _, _, _, zones, windows = DB:GetStats()
    eq(zones, 2, "Angelzonen")
    eq(windows, 2, "Beutefenster")

    local lines = LibStub("AceAddon-3.0"):GetAddon("Glimpse").probes["gathering fishing"]("37")
    local text = table.concat(lines, "\n")
    assert(text:find("Loot windows: 1", 1, true), "Fenster in der Probe")
    assert(text:find("300: 1 hits, 1 total", 1, true), "Fang in der Probe")
end)

test("Angeln: Angelbeute zählt nicht als Knoten oder Kreatur", function()
    local window = { { "GameObject-0-1-2-3-500-0000", 300 } }
    local DB = setup({
        IsFishingLoot = function() return true end,
        GetNumLootItems = function() return #window end,
        GetLootSourceInfo = function(slot) return window[slot][1], 1 end,
        GetLootSlotType = function() return 1 end,
        GetLootSlotLink = function(slot) return "item:" .. window[slot][2] end,
        GetItemInfoInstant = function(id) return id, "", "", "", "", 7, 8 end,
    })
    DB:OnLootOpened()
    eq(DB:GetNode(500), nil, "kein Knoten")
    eq(select(3, DB:GetStats()), 0, "keine Beutefenster")
end)

test("Angeln: Symbol und Überschrift im Tooltip", function()
    local Glimpse = stub.newGlimpse()
    local GT = Glimpse:NewModule("GatheringTooltip")
    GT.L = Glimpse.L
    GT.db = { profile = { showLocations = true } }
    stub.load("Glimpse_Gathering/Core/Tooltip/TooltipSources.lua", "Glimpse_Gathering")
    eq(GT:SourceIcon({ kind = "fishing" }), "Interface\\Icons\\Trade_Fishing", "Symbol")
    local key, title = GT:SourceGroup({ kind = "fishing" })
    eq(key, "fishing", "Gruppe"); eq(title, "Fishing", "Überschrift")
end)
