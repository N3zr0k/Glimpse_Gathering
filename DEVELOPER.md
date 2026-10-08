# Glimpse: Gathering, Entwickler-Dokumentation

## Aufbau

```
Glimpse_GatheringDB/        Daten sammeln und speichern
  Core/                     Modul, Optionen, Compat (Beute-Funktionen; Karten und Position kommen aus dem Glimpse-Modul Locations)
    Data/                   Spots (Fundorte), Store (Beute speichern, abfragen), Names (Knoten über den Namen),
                            Migrate (Version, Bereinigung, Grenzen), Transfer und TransferUI (Export, Import),
                            Providers und GatherMate2 (Fundorte anderer Addons), Sources (Orte eines Items)
    Loot/                   Collect (gemeinsamer Zustand), LootWindow (Beutefenster), Fishing, Kills, Area (Debug Gebiet),
                            Events (Event-Frame, Start/Stop)
  Modules/Debug/            Rohdaten im Tooltip, nur bei Debug-Modus
  Commands/                 /gli gatheringdb
  Locales/                  enUS, deDE
  Libs/                     LibDeflate (Export komprimieren)
  Media/                    Icon
Glimpse_GatheringTooltip/   Anzeige
  Core/                     Modul, Optionen (Tabs), Professions (gelernte Berufe)
    Tooltip/                Tooltip (Zeilen für Knoten, Kreaturen und Items), Sources (Orte, Symbole, Gruppen), Waypoint (Wegpunkt-Taste)
  Locales/                  enUS, deDE
  Media/                    Icon, Markierungen (Markers)
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

## Öffentliche Schnittstelle von GatheringDB (API_VERSION 10)

Erreichbar über `Glimpse.GatheringDB` (oder `Glimpse:GetModule("GatheringDB")`). Die zurückgegebenen
Tabellen sind nur zum Lesen gedacht.

| Funktion | Rückgabe |
| --- | --- |
| `:GetNode(id)` / `:GetNPC(id)` | Rohdaten oder nil |
| `:GetNodeDrops(id)` | Liste der Beute (je Eintrag `itemID`, `hits`, `attempts`, `amount`, `chance`, `average`), Zahl der Versuche |
| `:GetNPCDrops(id, kind)` | dasselbe, `kind` = `"loot"` oder `"skinning"` |
| `:GetNodeDropsByName(name)` | wie `GetNodeDrops`, über den Namen (mehrere IDs zusammengerechnet) |
| `:FindNodeIDs(name)` / `:GetTooltipName(tooltip)` | Namenssuche für Weltobjekte ohne ID |
| `:GetItemSources(itemID, minAttempts)` | alle Quellen eines Items, wahrscheinlichste zuerst |
| `:GetStats()` | Knoten, Kreaturen, erfasste Beutefenster, Fundorte, Angelzonen, Angelwürfe (der Kill-Wert fiel mit API 10 weg, die späteren rücken auf) |
| `:GetSpots(kind, id, includeExternal)` | Fundorte einer Quelle: Liste `{ map, x, y, count, source }` (x, y = 0..1); Beute aus Instanzen: `{ instance, name, count, source }` ohne `map`, `x`, `y` (kein Wegpunkt möglich). Erst die eigenen (`source = "own"`, häufigste zuerst), dann fremde (`source = "GatherMate2"`, `count = 0`, `density` = Punkte dort); `includeExternal = false` liefert nur eigene |
| `:GetOwnSpots(kind, id)` | nur die eigenen Fundorte |
| `:GetNearestSpots(kind, id, limit, currentMapOnly)` | wie `GetSpots`, aber die Orte auf der Karte des Spielers zuerst, nach Entfernung: `distance` in Yards (nur wenn die Kartengröße bekannt ist), `mapDistance` als Bruchteil der Kartenbreite |
| `:GetItemSpots(itemID, minAttempts, limit, includeExternal)` | Fundorte aller Quellen eines Items: `{ map, x, y, count, source, density, kind, id, mode, name, chance }` |
| `:GetLocatedItemSources(itemID, minAttempts, externalSeparate, minChance)` | Die Orte der Quellen eines Items, geordnet nach "wo findet man es am besten". Ein Eintrag ist eine Quelle an einem Ort (Zone oder Instanz): eine Quelle in drei Zonen ergibt drei Einträge, mehrere Orte derselben Zone einen (Kopien der Einträge von `GetItemSources` mit `tier`, `area`, `group`, `spot`, `spots`, `place`). Stufen: 1 `"here"` (Gebiet des Spielers: Karte oder Instanz), 2 `"nearby"` (andere Karte desselben Kontinents, nach Entfernung in Yards, ab `minChance` (0 bis 1)), 3 `"elsewhere"` (anderer Kontinent oder andere Instanz), 4 `"none"` (kein Ort, ein Eintrag je Quelle). Innerhalb einer Stufe zuerst `group = "own"` (bestätigter Ort), dann `"external"` (Ort nur von einem anderen Addon); danach in Stufe 1 und 3 die höchste Chance. Ein Ort in der eigenen Zone zählt auch, wenn er nur extern belegt ist. `spot` ist der beste Ort des Eintrags. `externalSeparate = false`: externe zählen wie bestätigte (Standard `true`; die Option dafür liegt in GatheringTooltip, Tab Handwerksmaterial) |
| `:GetRequiredSkill(kind, id, level)` | Beruf (`"herb"`, `"ore"`, `"skinning"`), benötigter Skill, bei Kreaturen dazu, ob sie als kürschnerbar bekannt sind (Kürschner-Beute aufgezeichnet). `kind` = `"node"` (Objekt-ID) oder `"npc"` (Kreatur-ID, `level` = Stufe, ohne Angabe die gespeicherte). nil ohne Ergebnis (unbekannter Knoten, Boss-Stufe). Die Tabellen stehen in `Core/Data/SkillData.lua` (Quellen dort im Kopf), nicht in den SavedVariables |
| `:GetNodeSkill(id)` / `:GetSkinningSkill(level)` | dasselbe einzeln. Ein Knoten, der nicht in der Tabelle steht, aber aufgezeichnet ist, wird über sein Material zugeordnet, wenn alle Materialien denselben Skill verlangen |
| `:GetSkillColor(required, current)` | `"red"` (reicht nicht), `"orange"` (ab `required`), `"yellow"` (+25), `"green"` (+50), `"gray"` (+100), dazu r, g, b |
| `:GetPlayerSkill(profession)` | Skill mit Ausrüstungsbonus, Maximum, Name des Berufs im Client, Skill ohne Bonus; nil = nicht gelernt. Berufe werden über Skill-Linien-IDs gefunden, nicht über Namen; Cache, geleert bei `SKILL_LINES_CHANGED` und `PLAYER_EQUIPMENT_CHANGED` |
| `:HasProfession(profession)` | true/false, nil wenn der Client die Berufe nicht auslesen lässt |
| `:IsKnownSkinnable(id)` / `:GetCreatureTypeID(unit)` / `:IsSkinnableType(typeID)` | Kreatur mit Kürschner-Beute aufgezeichnet; Typ-ID einer Einheit (1 = Wildtier, 2 = Drachkin) unabhängig von der Clientsprache; Typ kann kürschnerbar sein |
| `:GetFishing(map)` / `:GetFishingDrops(map)` | Angelzone (uiMapID): Rohdaten `{ attempts, items, spots }` bzw. Liste der Fänge wie bei `GetNodeDrops`, dazu die Zahl der Würfe. Jedes Auswerfen (Zauber "Fischen", erkannt über den Namen) zählt als Versuch, ein Beutefenster (`IsFishingLoot()`) macht ihn zum Treffer; ein Wurf ohne Fenster zählt sofort bei der Meldung `ERR_FISH_ESCAPED` (`UI_ERROR_MESSAGE`/`UI_INFO_MESSAGE`), sonst 4 s nach `UNIT_SPELLCAST_CHANNEL_STOP`, beim nächsten Wurf oder nach 45 s (ein spätes Fenster wird über `AddFishingItems` nachgetragen). Gespeichert werden nur Handwerksmaterialien. In `GetItemSources` und `GetLocatedItemSources` erscheint die Zone als Quelle mit `kind = "fishing"`, `mode = "fishing"`, `id` = Karte; `GetSpots("fishing", map)` liefert die Orte, an denen geangelt wurde |
| `:GetProviders()` / `:RegisterProvider(name, provider)` | Anbieter fremder Fundorte abfragen (`{ name, available, enabled }`) bzw. anmelden |
| `:GetMapName(map)` | Name der Karte (uiMapID) oder nil |
| `:ExportData()` | Exporttext, `{ nodes, npcs, chars }` |
| `:ImportData(text, mode)` | `true, Ergebnis` oder `false, Fehlerschlüssel`; `mode` = `"merge"` (Standard) oder `"replace"` |

Ein Eintrag der Beuteliste: `{ itemID, hits, attempts, amount, chance (0..1), average }` (`attempts` = Versuche der
ganzen Quelle, nicht nur dieses Items). Eine Quelle aus `GetItemSources`: `{ kind ("node"|"npc"), id,
mode ("gather"|"loot"|"skinning"), name, level, category, attempts, hits, amount, chance, average }`.

Nachricht bei jeder Änderung: `GLIMPSE_GATHERING_UPDATED (kind, id)` (`kind` = `"node"`, `"npc"` oder `"reset"`).

Wer `API_VERSION` nutzt, prüft `(GatheringDB.API_VERSION or 0) >= 3` (2 = Fundorte, Export/Import; 3 = Fundorte aus anderen Addons, `GetNearestSpots`; 4 = `GetLocatedItemSources`; 5 = Karten, Position und Entfernungen sind in das Glimpse-Modul `Locations` gewandert, `GetMapSize`, `GetMapDistance`, `GetContinent`, `GetWorldPosition`, `GetPlayerArea` entfallen hier, `GetMapName` bleibt; 6 = `GetNPCKills`, `GetStats` liefert die Kills als fünften Wert (beides mit 10 entfernt); 7 = Skill-Funktionen `GetRequiredSkill`, `GetSkillColor`, `GetPlayerSkill` und Verwandte). 9 = `IsFishing`, `IsBobber`, `GetPlayerSkill("fishing")`; 8 = Angeln (`GetFishing`, `GetFishingDrops`, Quelle `"fishing"`, `GetStats` liefert Zonen und Würfe als sechsten und siebten Wert, Datenversion 6, Export enthält `fishing`). 10 = der Kill-Zähler ist weg: `GetNPCKills` und `RecordKill` entfallen, `GetStats` liefert Angelzonen und Würfe als fünften und sechsten Wert. GatheringTooltip verlangt Version 8.

Für TomTom: `GetSpots`/`GetItemSpots` liefern `map` (uiMapID) und `x`, `y` als Bruchteil 0..1, also direkt
`TomTom:AddWaypoint(spot.map, spot.x, spot.y, { title = ... })`.

## Gespeicherte Daten

Eigene SavedVariable `GlimpseGatheringDB` (AceDB, `global`, account-weit):

```
nodes[objectID] = { name, category ("herb"|"ore"|"other"), attempts, items = { [itemID] = { hits, amount } }, spots }
npcs[npcID]     = { name, level, loot = { attempts, items }, skinning = { attempts, items }, spots }
spots           = { { map = uiMapID, x, y (ganze Zahlen 1..10000 = 1/10000 der Karte), n = Funde },
                    { inst = instanceID, n = Funde } }   -- Beute in einer Instanz: ohne Karte und Koordinaten
instances[id]   = Name der Instanz (zuletzt gesehen, nur für vorhandene Fundorte)
imports[id]     = Zeitpunkt (bereits zusammengeführte Exporte, höchstens 50)
version         = Datenformat (DATA_VERSION = 5 in Core/GatheringDB.lua); fehlt er, gilt 1
```

* Fundorte (`spots`, auch bei Knoten) werden beim Öffnen des Beutefensters gelesen (Option `trackLocations`).
  Orte näher als `DB.SPOT_RADIUS` (1 % der Karte) werden gewichtet zusammengefasst, je Quelle höchstens
  `MAX_SPOTS_NODE` (40) bzw. `MAX_SPOTS_NPC` (12); der schwächste Ort fällt zuerst weg.
* Versionen: 1 Knoten und Kreaturen mit Beute; 2 dazu `spots` und `imports` (`migrations[1]`); 3 Instanzen als Fundort
  und `instances` (`migrations[2]`); 4 und 5 früher `kills` je Kreatur (`migrations[3]` und `[4]`, jetzt leer; füllten `kills` aus den
  Versuchen der Normalbeute auf, nie darunter).
* Früher gab es einen Kill-Zähler `kills` je Kreatur. Er wird nicht mehr geführt (Kills zählt Glimpse: Statistics); ein
  vorhandener Wert wird beim Prüfen der Daten entfernt, ebenso eine Kreatur, die nur Kills hatte.
* Die Version steht **nicht** in den AceDB-Defaults (AceDB lässt Werte weg, die dem Default gleichen, die Umstellung
  würde nie laufen). Eine fehlende Version gilt als 1, deshalb müssen alle Schritte in `migrations` wiederholbar sein.
* Kreaturen werden nach ihrer ID gespeichert, nicht nach Stufe.
* Instanzen: In einer Instanz (`IsInInstance`, Art nicht `none`) gibt es keine brauchbaren Koordinaten. Die Beute
  bekommt dann als Fundort die Instanz (`DB:GetPlayerInstance()`, instanceID aus `GetInstanceInfo`), nie Karte
  und Koordinaten. `Locations:GetPlayerArea()` (Glimpse-Kern, Modul `Locations`) liefert `{ instance, name }` oder `{ map, x, y }`.
* `hits` = in wie vielen Versuchen das Item vorkam (daraus die Chance), `amount` = Gesamtmenge.
* Ändert sich das Format: `DATA_VERSION` erhöhen und in `Core/Data/Migrate.lua` unter `migrations[alteVersion]`
  die Umstellung eintragen. Daten einer **neueren** Version rührt das Addon nicht an und zeichnet nicht auf.
* Grenzen: `DB.MAX_NODES` und `DB.MAX_NPCS`. Darüber fallen die Einträge mit den wenigsten Versuchen weg.

## Export und Import

`Core/Data/Transfer.lua` (Logik) und `Core/Data/TransferUI.lua` (Fenster). Befehle: `/gli gatheringdb export | import`,
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

## Fundorte aus anderen Addons (GatherMate2)

`Core/Data/Providers.lua` hängt beim Abfragen (`DB:GetSpots`) die Orte von Anbietern hinter die eigenen. Sie werden nie
gespeichert und nie exportiert. Ein Anbieter ist `{ IsAvailable(), GetSpots(kind, id, entry), GetInfo()? }`
und meldet sich mit `DB:RegisterProvider(name, provider)` an. Fehler im Anbieter werden mit `pcall` abgefangen
(`DB:ReportError`), die eigenen Orte bleiben. Fremde Orte nahe an einem eigenen (`SPOT_RADIUS`) fallen weg, je Quelle
gibt es höchstens `DB.EXTERNAL_LIMIT` (60), dabei kommt der beste Ort jeder Karte zuerst, damit keine Zone verloren geht. Die Option `useExternalSpots` (Standard an) schaltet alles ab, `externalSources[Name] = false` nur einen Anbieter
(für jeden angemeldeten Anbieter gibt es in den Optionen einen Schalter; beim Aufbau der Optionen bereits angemeldete
Anbieter erscheinen dort, später angemeldete nicht).

`Core/Data/GatherMate2.lua` ist der Anbieter für GatherMate2 (nur Knoten, keine Kreaturen). Benutzt wird nur dessen
Schnittstelle: `GetNodesForZone`, `DecodeLoc`, `GetIDForNode`, `HBD:GetAllMapIDs` (ohne HBD die Speicher in `gmdbs`).
GatherMate2 hat eigene Knoten-IDs (Kupfervorkommen 201, Silberblatt 402), nicht die Objekt-IDs des Spiels; der Abgleich läuft
deshalb über den Namen. Die Kategorie wählt den Typ (`herb` → Herb Gathering, `ore` → Mining, sonst Extract Gas/Treasure/Logging;
fehlt sie oder steht sie auf `other`, werden auch die übrigen Typen versucht). Gesucht wird erst der genaue Name
(`GetIDForNode`), dann ohne Groß-/Kleinschreibung und Sonderzeichen (`reverseNodeIDs`), zuletzt der einzige Name des Typs mit
gleichem Anfang (mindestens 5 Zeichen). Beim ersten Zugriff wird ein Typ einmal gelesen und je Knoten in Rasterzellen von 1 % der
Karte zusammengefasst (`density` = Punkte je Zelle). Der Index wird nach den Nachrichten `GatherMate2NodeAdded`,
`GatherMate2NodeDeleted` und `GatherMate2Cleanup` frühestens nach 30 Sekunden erneuert. Ändert GatherMate2 seine
Schnittstelle, meldet sich der Anbieter als nicht verfügbar; `/gli gatheringdb gm2` zeigt, wie viele Punkte GatherMate2 hat und wie viele davon ankommen (Fehlersuche); die Tests (`tests/test_gathermate.lua`) bilden die
Struktur nach.

## Wie die Beute erkannt wird

`Core/Loot/LootWindow.lua` liest bei `LOOT_OPENED` sofort alle Quellen des Beutefensters und wertet 0,3 s später aus
(`EVALUATE_DELAY`), weil `UNIT_SPELLCAST_SUCCEEDED` je nach Reihenfolge kurz vor oder nach dem Beutefenster kommt.

* **Sammelknoten** (`GameObject`): zählt nur, wenn direkt davor (1 s) ein Zauber des Spielers erfolgreich war oder
  (Ersatz) ein Zauber innerhalb von 10 s abgeschickt wurde, und mindestens ein Material dabei ist. Gezählt wird je Zauber
  (`nodeMark`): derselbe Knoten kann mehrmals nacheinander und nach dem Nachwachsen (gleiche GUID) wieder zählen, ein
  erneut geöffnetes Fenster desselben Zaubers nicht. Truhen gehen ohne Zauber auf und fallen deshalb weg.
* **Kreaturen** (`Creature`): Normalbeute zählt als Versuch und als Kill, auch ohne Material. Kürschnerbeute wird erkannt,
  wenn davor ein Zauber erfolgreich war oder die Leiche schon einmal gelootet wurde. Dieselbe Kreatur zählt 10 Minuten
  nicht erneut (`CREATURE_REPEAT`, Teilloot).
* **Kills ohne Beutefenster** (`Core/Loot/Kills.lua`): Quelle ist das Ereignis `PARTY_KILL` (Killer-GUID, Opfer-GUID): Es zählt, wenn der Killer
  der Spieler oder sein Haustier ist, auch ohne Ziel und ohne Beute (`DB:OnPartyKill`). Kennt der Client das Ereignis
  nicht, bleibt der Tod des Ziels als Ersatz (`UNIT_HEALTH`, Zielwechsel auf eine Leiche, Kampfende), der Kills nach
  einem Zielwechsel verpasst. Das Kampflog ist für Addons gesperrt und wird nicht benutzt. Kommt 2 Minuten lang kein
  Beutefenster (`KILL_FALLBACK`) und sagt `CanLootUnit` nicht, dass noch Beute da ist, zählt der Kill als Versuch. Beute,
  die danach kommt, wird ohne zweiten Versuch ergänzt. Das Fenster hat immer Vorrang.
* Gespeichert werden nur Handwerkswaren und Edelsteine (Item-Klassen 7 und 3).

Das sind Heuristiken. Im Debug-Modus schreibt `LootWindow.lua` pro Beutefenster eine Zeile
(`Beutefenster: Typ, ID, Zauber davor, Materialien`), `Kills.lua` zu jedem Kill, warum er gezählt wurde oder nicht.
Fehler in der Auswertung werden abgefangen und gezählt (`/gli gatheringdb stats`).

## GatheringTooltip

`Core/Tooltip/Tooltip.lua` baut die Zeilen: Knoten und Kreaturen zeigen ihre Beute wie die Quellen eines Items (Chance,
Treffer/Versuche, Durchschnitt), Materialien die besten Orte aus `GetLocatedItemSources`. Orte, die nur von einem anderen
Addon kommen, zeigen keine Chance. `Core/Tooltip/Sources.lua` ordnet Symbole, Gruppen und Fundorte (Spalten) an,
`Core/Tooltip/Waypoint.lua` setzt über das Glimpse-Modul `Locations` einen Wegpunkt zum besten Ort. Der Tastenhörer dafür wird im
Kampf nicht angefasst (geschützte Aufrufe) und danach nachgezogen (`PLAYER_REGEN_ENABLED`).

## Prüfen

```
lua tests/run.lua        # Store, Migrate und die Beute-Erkennung mit nachgebautem Beutefenster
luacheck .
python3 tools/check.py
```
