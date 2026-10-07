local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")

-- Statische Skill-Daten für Sammelknoten. Nichts davon landet in den SavedVariables.
-- Die Logik dazu steht in Data/Skills.lua.
--
-- Quellen (Stand 2026-10-06, Werte von Classic Era / Vanilla 1.12, die Forever-Inhalte sind dieselben, eine
-- Abweichung ist mir nirgends begegnet, geprüft habe ich sie aber nicht ingame):
--   * Wowhead-Classic-Objektseiten https://www.wowhead.com/classic/object=<ID> (Zeile "Requires Herbalism/Mining (X)").
--     Damit belegt sind die Einträge unter "A".
--   * Alle übrigen Einträge ("B"): warcraft.wiki.gg (Seiten der einzelnen Kräuter und Knoten, dort stehen auch die
--     Objekt-IDs), Wowhead-Guides zu Bergbau und Kräuterkunde (1-300) und icy-veins.com (Kräuterkunde), bei einzelnen
--     Objekten auch Wowhead-Seiten anderer Spielversionen (Retail, WotLK, TBC, MoP Classic). Die Werte passen zu den
--     Classic-Werten, sind aber nicht auf einer Classic-Era-Seite gegengeprüft.
--   * Widersprüchliche Quellen: Bruiseweed 85 (wiki.gg) gegen 100 (Wowhead Classic, Guides): 100 gilt; Fadeleaf 150
--     (Retail-Seite) gegen 160 (Classic, Forever-Itemseite): 160; Goldthorn 150 gegen 170 (Classic): 170; Khadgar's
--     Whisker 160 gegen 185 (Classic): 185.
--   * Weggelassen, weil nicht belegt: Objekt 176644 (Rich Thorium Vein, die Seite nennt 215 und keinen Fundort).
--     Dünne Stelle: ein Guide nennt für Thorium abweichende Werte (250/275), die Objektseiten sagen 245 und 275.
--
-- Schlüssel sind die Objekt-IDs aus der GUID ("GameObject-0-...-1731-..."), nicht die Namen, die der Client
-- lokalisiert. Wert: { Beruf, benötigter Skill }, Beruf = "herb" oder "ore" (wie die Kategorie der Knoten).
-- Zusätzlich stehen unten die Items, die ein Knoten liefert: Für Objekte, die hier fehlen (Varianten anderer
-- Spielversionen), aber schon aufgezeichnet wurden, reicht dann die Beute zur Zuordnung.

local HERB, ORE = "herb", "ore"

DB.NodeSkills = {
    -- A: Wowhead Classic
    [1618] = { HERB, 1 },      -- Peacebloom
    [1619] = { HERB, 15 },     -- Earthroot
    [1621] = { HERB, 70 },     -- Briarthorn
    [1622] = { HERB, 100 },    -- Bruiseweed
    [1623] = { HERB, 115 },    -- Wild Steelbloom
    [1628] = { HERB, 120 },    -- Grave Moss
    [2041] = { HERB, 150 },    -- Liferoot
    [2042] = { HERB, 160 },    -- Fadeleaf
    [2043] = { HERB, 185 },    -- Khadgar's Whisker
    [2044] = { HERB, 195 },    -- Wintersbite
    [2045] = { HERB, 85 },     -- Stranglekelp
    [2046] = { HERB, 170 },    -- Goldthorn
    [142140] = { HERB, 210 },  -- Purple Lotus
    [142144] = { HERB, 245 },  -- Ghost Mushroom
    [176640] = { HERB, 280 },  -- Mountain Silversage (Felwood)
    [1667] = { ORE, 65 },      -- Incendicite Mineral Vein
    [2653] = { ORE, 75 },      -- Lesser Bloodstone Deposit
    [19903] = { ORE, 150 },    -- Indurium Mineral Vein
    [165658] = { ORE, 230 },   -- Dark Iron Deposit
    [123309] = { ORE, 230 },   -- Ooze Covered Truesilver Deposit
    [175404] = { ORE, 275 },   -- Rich Thorium Vein
    [177388] = { ORE, 275 },   -- Ooze Covered Rich Thorium Vein
    [180215] = { ORE, 275 },   -- Hakkari Thorium Vein

    -- B: übrige Quellen, siehe oben
    [1617] = { HERB, 1 },      -- Silverleaf
    [1620] = { HERB, 50 },     -- Mageroyal
    [1624] = { HERB, 125 },    -- Kingsblood
    [2866] = { HERB, 205 },    -- Firebloom
    [142141] = { HERB, 220 },  -- Arthas' Tears
    [142142] = { HERB, 230 },  -- Sungrass
    [142143] = { HERB, 235 },  -- Blindweed
    [142145] = { HERB, 250 },  -- Gromsblood
    [176583] = { HERB, 260 },  -- Golden Sansam
    [176584] = { HERB, 270 },  -- Dreamfoil
    [176586] = { HERB, 280 },  -- Mountain Silversage
    [176641] = { HERB, 285 },  -- Plaguebloom
    [176588] = { HERB, 290 },  -- Icecap
    [176589] = { HERB, 300 },  -- Black Lotus

    [1731] = { ORE, 1 },       -- Copper Vein
    [2055] = { ORE, 1 },       -- Copper Vein (Variante laut Wiki)
    [3763] = { ORE, 1 },
    [103713] = { ORE, 1 },
    [1732] = { ORE, 65 },      -- Tin Vein
    [2054] = { ORE, 65 },      -- Tin Vein (Variante laut Wiki)
    [3764] = { ORE, 65 },
    [103711] = { ORE, 65 },
    [1733] = { ORE, 75 },      -- Silver Vein
    [105569] = { ORE, 75 },    -- Silver Vein (Variante laut Wiki)
    [73940] = { ORE, 75 },     -- Ooze Covered Silver Vein
    [1735] = { ORE, 125 },     -- Iron Deposit
    [73939] = { ORE, 125 },    -- Ooze Covered Iron Deposit
    [1734] = { ORE, 155 },     -- Gold Vein
    [181109] = { ORE, 155 },   -- Gold Vein (Felwood)
    [73941] = { ORE, 155 },    -- Ooze Covered Gold Vein
    [2040] = { ORE, 175 },     -- Mithril Deposit
    [176645] = { ORE, 175 },   -- Mithril Deposit (Felwood)
    [123310] = { ORE, 175 },   -- Ooze Covered Mithril Deposit
    [2047] = { ORE, 230 },     -- Truesilver Deposit
    [181108] = { ORE, 230 },   -- Truesilver Deposit (Felwood)
    [324] = { ORE, 245 },      -- Small Thorium Vein
    [176643] = { ORE, 245 },   -- Small Thorium Vein (Felwood)
    [123848] = { ORE, 245 },   -- Ooze Covered Thorium Vein
}

-- Das Material, das ein Knoten liefert, und der Skill, den der Knoten dafür verlangt. Thorium fehlt mit Absicht
-- (Small Thorium Vein 245, Rich Thorium Vein 275: das Item sagt nicht, welcher Knoten es war). Herkunft wie oben;
-- ein paar Item-IDs standen nur in Suchergebnissen der Datenbanken, nicht in einer abgerufenen Seite.
DB.ItemSkills = {
    -- Kräuter
    [765] = { HERB, 1 }, [2447] = { HERB, 1 }, [2449] = { HERB, 15 }, [785] = { HERB, 50 }, [2450] = { HERB, 70 },
    [3820] = { HERB, 85 }, [2453] = { HERB, 100 }, [3355] = { HERB, 115 }, [3369] = { HERB, 120 },
    [3356] = { HERB, 125 }, [3357] = { HERB, 150 }, [3818] = { HERB, 160 }, [3821] = { HERB, 170 },
    [3358] = { HERB, 185 }, [3819] = { HERB, 195 }, [4625] = { HERB, 205 }, [8831] = { HERB, 210 },
    [8836] = { HERB, 220 }, [8838] = { HERB, 230 }, [8839] = { HERB, 235 }, [8845] = { HERB, 245 },
    [8846] = { HERB, 250 }, [13464] = { HERB, 260 }, [13463] = { HERB, 270 }, [13465] = { HERB, 280 },
    [13466] = { HERB, 285 }, [13467] = { HERB, 290 }, [13468] = { HERB, 300 },
    -- Erze
    [2770] = { ORE, 1 }, [2771] = { ORE, 65 }, [3340] = { ORE, 65 }, [2775] = { ORE, 75 }, [4278] = { ORE, 75 },
    [2772] = { ORE, 125 }, [5833] = { ORE, 150 }, [2776] = { ORE, 155 }, [3858] = { ORE, 175 },
    [7911] = { ORE, 230 }, [11370] = { ORE, 230 },
}

-- Abstände der Farben zum benötigten Skill: orange ab dem Wert, gelb ab +25, grün ab +50, grau ab +100.
-- Quelle: Wowhead-Guide Bergbau 1-300 (Classic), Kräuter nach icy-veins.com in demselben Muster. Für Kürschnerei habe
-- ich keine Zahlen gefunden, die Allakhazam-FAQ fasst alle drei Berufe zusammen (orange 100 %, gelb mittel, grün selten,
-- grau nie), darum gilt dort dasselbe.
DB.SKILL_YELLOW = 25
DB.SKILL_GREEN = 50
DB.SKILL_GRAY = 100

-- Farben wie die Schwierigkeitsfarben der Rezepte im Spiel
DB.SkillColors = {
    red = { 1.00, 0.10, 0.10 },
    orange = { 1.00, 0.50, 0.25 },
    yellow = { 1.00, 1.00, 0.00 },
    green = { 0.25, 0.75, 0.25 },
    gray = { 0.50, 0.50, 0.50 },
}

-- Kürschnerei: benötigter Skill nach Kreaturenstufe (Classic Era). Stufe 1-10: 1, Stufe 11-20: (Stufe - 10) * 10,
-- ab Stufe 21: Stufe * 5. Quellen: https://warcraft.wiki.gg/wiki/Skinnable ("lvl * 5" ab Stufe 21),
-- https://wowpedia.fandom.com/wiki/Skinning (Stufe 11-20: 10 mal Stufe minus 100), beide stimmen überein. Bossen und
-- manchen Raid-Tieren genügt das nicht (Guides nennen 310 bis 315), dafür gibt es hier keine Zahlen.
DB.SKINNING_FREE_LEVEL = 10
DB.SKINNING_STEP_LEVEL = 20

-- Kreaturentypen, die Kürschnerei erlauben können: Wildtier und Drachkin (warcraft.wiki.gg/wiki/Skinning). Das Typ-Flag
-- reicht nicht, nicht jedes Tier ist kürschnerbar (die meisten Vögel nicht), deshalb nur als Hinweis. IDs nach
-- https://warcraft.wiki.gg/wiki/API_C_CreatureInfo.GetCreatureTypeInfo
DB.CREATURE_BEAST = 1
DB.CREATURE_DRAGONKIN = 2
