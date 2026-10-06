-- luacheck: ignore 111 113 122 143 432
local stub = require("wowstub")

local function setup(compress)
    stub.libs.LibDeflate = nil
    if compress then stub.useLibDeflate() end
    local Glimpse = stub.newGlimpse()
    local DB = Glimpse:NewModule("GatheringDB")
    DB.DATA_VERSION = 2
    DB.data = { version = 2, nodes = {}, npcs = {}, imports = {} }
    DB.MESSAGE_UPDATED = "GLIMPSE_GATHERING_UPDATED"
    stub.load("Glimpse_GatheringDB/Data/Store.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Data/Migrate.lua", "Glimpse_GatheringDB")
    stub.load("Glimpse_GatheringDB/Data/Transfer.lua", "Glimpse_GatheringDB")
    return DB
end

local function fill(DB)
    DB:RecordNode(10, { name = "Kupfer", category = "ore" }, { [101] = 2 }, { map = 37, x = 0.4, y = 0.5 })
    DB:RecordNode(10, nil, { [101] = 1 }, { map = 37, x = 0.8, y = 0.2 })
    DB:RecordNPC(77, "loot", { name = "Wolf", level = 5 }, { [102] = 1 }, { map = 10, x = 0.3, y = 0.3 })
end

for _, compress in ipairs({ true, false }) do
    local label = compress and "komprimiert" or "unkomprimiert"

    test("Transfer (" .. label .. "): Export und Import ergeben dieselben Daten", function()
        local a = setup(compress)
        fill(a)
        local text, info = a:ExportData()
        eq(text:sub(1, 7), compress and "GGDB1:D" or "GGDB1:R", "Kopf")
        eq(info.nodes, 1, "Knoten")
        eq(info.npcs, 1, "Kreaturen")

        local b = setup(compress)
        local ok, res = b:ImportData(text)
        eq(ok, true, "Import")
        eq(res.migrated, false, "keine Migration")
        eq(b:GetNode(10).attempts, 2, "Versuche")
        eq(b:GetNode(10).items[101].amount, 3, "Menge")
        eq(b:GetNode(10).name, "Kupfer", "Name")
        eq(#b:GetSpots("node", 10), 2, "Orte")
        eq(b:GetNPC(77).loot.attempts, 1, "Kreatur")
        eq(b:GetNPC(77).level, 5, "Stufe")
        eq(#b:GetSpots("npc", 77), 1, "Ort der Kreatur")
    end)
end

test("Transfer: Zeilenumbrüche im komprimierten Text stören nicht", function()
    local a = setup(true)
    fill(a)
    local text = a:ExportData()
    local head, body = text:match("^(GGDB1:D:)(.*)$")
    local wrapped = head .. body:gsub("(" .. ("."):rep(40) .. ")", "%1\n  ")
    local b = setup(true)
    eq((b:ImportData(wrapped)), true, "Import")
    eq(b:GetNode(10).attempts, 2, "Daten")
end)

test("Transfer: Serializer Rundlauf", function()
    local a = setup(false)
    local value = { s = "hallo: {x}", n = -12.5, t = true, f = false, [1] = { [2] = "z" }, empty = {} }
    local back = a.Deserialize(a.Serialize(value))
    eq(back.s, "hallo: {x}", "Text")
    eq(back.n, -12.5, "Zahl")
    eq(back.t, true, "wahr")
    eq(back.f, false, "falsch")
    eq(back[1][2], "z", "verschachtelt")
    eq(next(back.empty), nil, "leer")
    eq(a.Serialize(value), a.Serialize(back), "feste Reihenfolge")
end)

test("Transfer: Serializer lehnt Müll ab", function()
    local a = setup(false)
    local function bad(text, why) eq(a.Deserialize(text), nil, why) end
    bad("{s5:abc}", "zu kurzer Text")
    bad("{s9999:x}", "zu lange Längenangabe")
    bad("{s-1:x}", "negative Länge")
    bad("{n1;n2;", "nicht abgeschlossen")
    bad("{n1;n2;}x", "Daten am Ende")
    bad("n1;", "keine Tabelle")
    bad("{nabc;n1;}", "keine Zahl")
    bad("{nnan;n1;}", "NaN")
    bad("{n1e99;n1;}", "zu groß")
    bad("{Tn1;}", "Wahrheitswert als Schlüssel")
    bad("{q}", "unbekanntes Zeichen")
    bad("", "leer")
    bad(("{n1;"):rep(20) .. ("}"):rep(20), "zu tief")
end)

test("Transfer: Fehlerschlüssel bei fremdem oder beschädigtem Text", function()
    local a = setup(true)
    local function err(text, key) local ok, e = a:ImportData(text); eq(ok, false, key); eq(e, key, key) end
    err("", "empty")
    err("   \n ", "empty")
    err(nil, "empty")
    err("hallo welt", "notExport")
    err("GGDB1:X:abc", "notExport")
    err("GGDB9:D:abc", "formatNewer")
    err("GGDB1:D:!!!!", "damaged")
    err("GGDB1:R:{s5:ab}", "damaged")
    err("GGDB1:R:{n1;n2;}", "damaged") -- keine Version

    local text = a:ExportData()
    err(text:sub(1, #text - 15), "damaged")
    err(("x"):rep(40000001), "tooLarge")

    local noLib = setup(false)
    local ok, e = noLib:ImportData(text)
    eq(ok, false, "ohne Bibliothek")
    eq(e, "unsupported", "Kompression nicht verfügbar")
end)

test("Transfer: Kills werden beim Zusammenführen addiert", function()
    local a = setup(true)
    a:RecordKill(77, { name = "Wolf" })
    a:RecordKill(77)
    local text = a:ExportData()

    local b = setup(true)
    b:RecordKill(77)
    eq((b:ImportData(text)), true, "Import")
    eq(b:GetNPCKills(77), 3, "Kills addiert")

    local c = setup(true)
    eq((c:ImportData(text)), true, "Import in leere Daten")
    eq(c:GetNPCKills(77), 2, "Kills übernommen")
end)

test("Transfer: Zusammenführen addiert Zähler und führt Orte zusammen", function()
    local a = setup(true)
    fill(a)
    local text = a:ExportData()

    local b = setup(true)
    b:RecordNode(10, nil, { [101] = 5 }, { map = 37, x = 0.4, y = 0.5 })
    b:RecordNode(11, { name = "Zinn" }, { [103] = 1 })
    eq((b:ImportData(text)), true, "Import")

    eq(b:GetNode(10).attempts, 3, "Versuche addiert")
    eq(b:GetNode(10).items[101].amount, 8, "Menge addiert")
    eq(b:GetNode(10).name, "Kupfer", "Name ergänzt")
    eq(b:GetNode(11).attempts, 1, "andere Knoten bleiben")
    eq(b:GetNPC(77) ~= nil, true, "neue Kreatur")
    local spots = b:GetSpots("node", 10)
    eq(#spots, 2, "ähnliche Orte zusammengefasst")
    eq(spots[1].count, 2, "Haufen")
end)

test("Transfer: derselbe Export wird nicht zweimal zusammengeführt", function()
    local a = setup(true)
    fill(a)
    local text = a:ExportData()

    local b = setup(true)
    eq((b:ImportData(text)), true, "erstes Mal")
    local ok, e = b:ImportData(text)
    eq(ok, false, "zweites Mal")
    eq(e, "duplicate", "Schlüssel")
    eq(b:GetNode(10).attempts, 2, "nicht doppelt gezählt")

    -- Ersetzen ist erlaubt
    eq((b:ImportData(text, "replace")), true, "Ersetzen")
    eq(b:GetNode(10).attempts, 2, "ersetzt statt addiert")

    -- nach dem Zurücksetzen wieder möglich
    b:ResetData()
    eq((b:ImportData(text)), true, "nach Reset")
end)

test("Transfer: Ersetzen löscht vorhandene Daten", function()
    local a = setup(true)
    fill(a)
    local text = a:ExportData()

    local b = setup(true)
    b:RecordNode(99, { name = "Alt" }, { [1] = 1 })
    local ok, res = b:ImportData(text, "replace")
    eq(ok, true, "Import")
    eq(res.mode, "replace", "Modus")
    eq(b:GetNode(99), nil, "alter Knoten weg")
    eq(b:GetNode(10) ~= nil, true, "neuer Knoten da")
end)

test("Transfer: Daten der Version 1 werden beim Import migriert", function()
    local b = setup(false)
    local payload = b.Serialize({
        format = 1, version = 1, id = "alt-1",
        nodes = { [10] = { name = "Kupfer", category = "ore", attempts = 3, items = { [101] = { hits = 2, amount = 4 } } } },
        npcs = {},
    })
    local ok, res = b:ImportData("GGDB1:R:" .. payload)
    eq(ok, true, "Import")
    eq(res.migrated, true, "migriert")
    eq(res.version, 1, "Ausgangsversion")
    eq(b:GetNode(10).attempts, 3, "Daten übernommen")
    eq(#b:GetSpots("node", 10), 0, "noch keine Orte")
end)

test("Transfer: neuere Datenversion wird abgelehnt, nichts ändert sich", function()
    local b = setup(false)
    b:RecordNode(1, { name = "Eins" }, { [1] = 1 })
    local payload = b.Serialize({ format = 1, version = 99, id = "neu", nodes = {}, npcs = {} })
    local ok, e = b:ImportData("GGDB1:R:" .. payload, "replace")
    eq(ok, false, "abgelehnt")
    eq(e, "dataNewer", "Schlüssel")
    eq(b:GetNode(1) ~= nil, true, "Daten unverändert")
end)

test("Transfer: Import bereinigt ungültige Einträge", function()
    local b = setup(false)
    local payload = b.Serialize({
        format = 1, version = 2, id = "boese",
        nodes = {
            [10] = { attempts = 2, items = { [101] = { hits = 99, amount = 1 } }, name = ("x"):rep(400) },
            [-5] = { attempts = 1, items = {} },
            abc = { attempts = 1, items = {} },
        },
        npcs = { [7] = "kein Eintrag" },
    })
    local ok = b:ImportData("GGDB1:R:" .. payload)
    eq(ok, true, "Import")
    eq(b.data.nodes.abc, nil, "Text als ID")
    eq(b:GetNode(10).items[101], nil, "unplausible Treffer entfernt")
    eq(b:GetNPC(7), nil, "kaputte Kreatur")
end)

test("Transfer: Import meldet die Aktualisierung", function()
    local a = setup(false)
    fill(a)
    local b = setup(false)
    b:ImportData((a:ExportData()))
    eq(b.messages[#b.messages][1], "GLIMPSE_GATHERING_UPDATED", "Nachricht")
end)
