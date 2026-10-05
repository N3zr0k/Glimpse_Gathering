# Glimpse: Gathering, Entwickler-Dokumentation

## Aufbau

```
Glimpse_GatheringDB/        Daten sammeln und speichern
  Core/                     Modul, Optionen, Compat (alle Blizzard-Funktionen an einer Stelle)
  Data/                     Store (speichern, abfragen), Migrate (Version, Bereinigung, Grenzen)
  Loot/                     Collect (Beutefenster auswerten)
  Debug/                    Rohdaten im Tooltip, nur bei Debug-Modus
  Commands/                 /gli gatheringdb
Glimpse_GatheringTooltip/   Anzeige
  Core/                     Modul, Optionen (Tabs), Professions
  Tooltip/                  Zeilen für Knoten, Kreaturen und Items
tests/                      Logik-Tests ohne WoW
```

Beide Addons haben eine zentrale XML und pro Ordner eine eigene XML, wie der Core.

## Mit den Dateien arbeiten

Ein Klon des Repos liegt außerhalb des AddOns-Ordners, beide Addon-Ordner werden verlinkt:

```
# Windows (PowerShell als Administrator, oder Entwicklermodus)
mklink /J "...\Interface\AddOns\Glimpse_GatheringDB"      "C:\dev\Glimpse_Gathering\Glimpse_GatheringDB"
mklink /J "...\Interface\AddOns\Glimpse_GatheringTooltip" "C:\dev\Glimpse_Gathering\Glimpse_GatheringTooltip"

# macOS / Linux
ln -s ~/dev/Glimpse_Gathering/Glimpse_GatheringDB      "<AddOns>/Glimpse_GatheringDB"
ln -s ~/dev/Glimpse_Gathering/Glimpse_GatheringTooltip "<AddOns>/Glimpse_GatheringTooltip"
```

Änderungen sind dann nach `/reload` im Spiel.

## Öffentliche Schnittstelle von GatheringDB (API_VERSION 2)

Erreichbar über `Glimpse.GatheringDB` (oder `Glimpse:GetModule("GatheringDB")`). Die zurückgegebenen
Tabellen sind nur zum Lesen gedacht.

| Funktion | Rückgabe |
| --- | --- |
| `:GetNode(id)` / `:GetNPC(id)` | Rohdaten oder nil |
| `:GetNodeDrops(id)` | Liste der Beute, Zahl der Versuche |
| `:GetNPCDrops(id, kind)` | dasselbe, `kind` = `"loot"` oder `"skinning"` |
| `:GetNodeDropsByName(name)` | wie `GetNodeDrops`, über den Namen (mehrere IDs zusammengerechnet) |
| `:FindNodeIDs(name)` / `:GetTooltipName(tooltip)` | Namenssuche für Weltobjekte ohne ID |
| `:GetItemSources(itemID, minAttempts)` | alle Quellen eines Items, wahrscheinlichste zuerst |
| `:GetStats()` | Knoten, Kreaturen, erfasste Beutefenster, Fundorte |
| `:GetSpots(kind, id)` | Fundorte einer Quelle: Liste `{ map, x, y, count }`, häufigste zuerst (x, y = 0..1) |
| `:GetItemSpots(itemID, minAttempts, limit)` | Fundorte aller Quellen eines Items: `{ map, x, y, count, kind, id, mode, name, chance }` |
| `:GetMapName(map)` | Name der Karte (uiMapID) oder nil |
| `:ExportData()` | Exporttext, `{ nodes, npcs, chars }` |
| `:ImportData(text, mode)` | `true, Ergebnis` oder `false, Fehlerschlüssel`; `mode` = `"merge"` (Standard) oder `"replace"` |

Ein Eintrag der Beuteliste: `{ itemID, hits, amount, chance (0..1), average }`. Eine Quelle aus
`GetItemSources`: `{ kind ("node"|"npc"), id, mode ("gather"|"loot"|"skinning"), name, level, category,
attempts, hits, amount, chance, average }`.

Nachricht bei jeder Änderung: `GLIMPSE_GATHERING_UPDATED (kind, id)` (`kind` = `"node"`, `"npc"` oder `"reset"`).

Wer `API_VERSION` nutzt, prüft `(GatheringDB.API_VERSION or 0) >= 2` (Fundorte, Export/Import).

Für TomTom: `GetSpots`/`GetItemSpots` liefern `map` (uiMapID) und `x`, `y` als Bruchteil 0..1, also direkt
`TomTom:AddWaypoint(spot.map, spot.x, spot.y, { title = ... })`.

## Gespeicherte Daten

Eigene SavedVariable `GlimpseGatheringDB` (AceDB, `global`, account-weit):

```
nodes[objectID] = { name, category ("herb"|"ore"|"other"), attempts, items = { [itemID] = { hits, amount } } }
npcs[npcID]     = { name, level, loot = { attempts, items }, skinning = { attempts, items }, spots }
spots           = { { map = uiMapID, x, y (ganze Zahlen 1..10000 = 1/10000 der Karte), n = Funde } }
imports[id]     = Zeitpunkt (bereits zusammengeführte Exporte, höchstens 50)
version         = Datenformat (DATA_VERSION = 2 in Core/GatheringDB.lua)
```

* Fundorte (`spots`, auch bei Knoten) werden beim Öffnen des Beutefensters gelesen (Option `trackLocations`).
  Orte näher als `DB.SPOT_RADIUS` (1 % der Karte) werden gewichtet zusammengefasst, je Quelle höchstens
  `MAX_SPOTS_NODE` (40) bzw. `MAX_SPOTS_NPC` (12); der schwächste Ort fällt zuerst weg.
* Version 1 hatte noch keine `spots` und `imports`; `migrations[1]` ergänzt `imports`.
* `hits` = in wie vielen Versuchen das Item vorkam (daraus die Chance), `amount` = Gesamtmenge.
* Ändert sich das Format: `DATA_VERSION` erhöhen und in `Data/Migrate.lua` unter `migrations[alteVersion]`
  die Umstellung eintragen. Daten einer **neueren** Version rührt das Addon nicht an und zeichnet nicht auf.
* Grenzen: `DB.MAX_NODES` und `DB.MAX_NPCS`. Darüber fallen die Einträge mit den wenigsten Versuchen weg.

## Export und Import

`Data/Transfer.lua` (Logik) und `Data/TransferUI.lua` (Fenster). Befehle: `/gli gatheringdb export | import`,
dazu Schaltflächen in den Optionen.

Text: `GGDB<Format>:<Methode>:<Daten>`. Methode `D` = LibDeflate (Stufe 9) + `EncodeForPrint`, `R` = unkomprimiert
(wenn die Bibliothek fehlt). Die Daten sind `{ format, version, created, id, nodes, npcs }` in einer eigenen
Textform (keine Code-Ausführung, feste Grenzen für Länge, Tiefe und Werte).

Import: lesen → `version` prüfen (neuer als `DATA_VERSION` → `dataNewer`) → mit `DB:UpgradeData` auf die
aktuelle Version bringen (dieselben `migrations` wie beim Start) → `DB:SanitizeData` → zusammenführen
(Zähler addieren, Orte zusammenfassen) oder ersetzen. Ein schon zusammengeführter Export (`id` in `imports`)
wird abgelehnt (`duplicate`). Fehlerschlüssel: `empty`, `tooLarge`, `notExport`, `formatNewer`, `unsupported`,
`damaged`, `dataNewer`, `duplicate`.

**Neue Datenversion:** `DATA_VERSION` erhöhen, `migrations[alteVersion]` ergänzen. Alte Exporte werden dann
automatisch beim Import umgestellt; ein Test in `tests/test_transfer.lua` für die alte Version nicht vergessen.

## Wie die Beute erkannt wird

`Loot/Collect.lua` liest bei `LOOT_OPENED` sofort alle Quellen des Beutefensters und wertet 0,3 s später aus,
weil `UNIT_SPELLCAST_SUCCEEDED` je nach Reihenfolge kurz vor oder nach dem Beutefenster kommt.

* **Sammelknoten** (`GameObject`): zählt nur, wenn direkt davor (1 s) ein Zauber des Spielers erfolgreich war und
  mindestens ein Material dabei ist. Truhen gehen ohne Zauber auf und fallen deshalb weg.
* **Kreaturen** (`Creature`): Normalbeute zählt als Versuch, auch ohne Material. Kürschnerbeute wird erkannt,
  wenn davor ein Zauber erfolgreich war oder die Leiche schon einmal gelootet wurde.
* Gespeichert werden nur Handwerkswaren und Edelsteine (Item-Klassen 7 und 3).
* Dieselbe Quelle zählt pro Sitzung nur einmal (Teilloot).

Das sind Heuristiken. Im Debug-Modus schreibt `Collect.lua` pro Beutefenster eine Zeile
(`Beutefenster: Typ, ID, Zauber davor, Materialien`), damit sich Fehlerkennungen nachvollziehen lassen.
Fehler in der Auswertung werden abgefangen und gezählt (`/gli gatheringdb stats`).

## Prüfen

```
lua tests/run.lua        # Store, Migrate und die Beute-Erkennung mit nachgebautem Beutefenster
luacheck .
python3 tools/check.py
```
