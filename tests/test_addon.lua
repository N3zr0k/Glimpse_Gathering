-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

-- Ein Addon, zwei Module: die ganze XML lädt, die Optionsseite hat vier Tabs, alte Ordner werden gemeldet

local function ItemInfo(id) return id, "", "", "", "", 7, 7 end

test("Addon: ganze XML lädt, eine Optionsseite mit vier Tabs", function()
    local DB, Glimpse = stub.newGatheringDB({ display = true, api = { GetItemInfoInstant = ItemInfo } })
    local GT = Glimpse:GetModule("GatheringTooltip")
    eq(GT.data, DB, "Anzeige liest über GatheringData")
    eq(stub.lastOptions.addon, "Glimpse_Gathering", "eine Seite für das Addon")
    eq(stub.lastOptions.tabs, true, "mit Tabs")
    for _, key in ipairs({ "general", "items", "target", "recording" }) do
        eq(stub.lastOptions.args[key].type, "group", "Tab " .. key)
    end
    eq(stub.lastOptions.args.recording.args.recording ~= nil, true, "Erfassen-Schalter im Tab Erfassen")
end)

test("Addon: meldet alte Ordner von GatheringDB und GatheringTooltip", function()
    local loaded = { Glimpse_GatheringDB = true }
    stub.newGatheringDB({ api = { GetItemInfoInstant = ItemInfo, IsAddOnLoaded = function(name) return loaded[name] end } })
    local found = 0
    for _, text in ipairs(stub.printed) do
        if text:find("Glimpse_GatheringDB", 1, true) then found = found + 1 end
        assert(not text:find("Glimpse_GatheringTooltip", 1, true), "nur geladene Ordner")
    end
    eq(found, 1, "Hinweis auf den alten Ordner")
end)
