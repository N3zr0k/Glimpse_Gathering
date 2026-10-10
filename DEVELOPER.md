# Glimpse: Gathering, Entwickler-Dokumentation

## Aufbau

```
Glimpse_Gathering/          das Addon (bis 0.3.5 zwei Addons, GatheringDB und GatheringTooltip)
  Core/                     Module GatheringData (erfassen, lesen) und GatheringTooltip (Anzeige), Compat (Beute-Funktionen;
                            Karten und Position kommen aus dem Glimpse-Modul Locations), Professions (gelernte Berufe),
                            Options (eine Seite mit Tabs), OptionsRecording (Tab Erfassen)
    Data/                   Lesen: DataDrops (Beute, Quellen, Statistik), DataSpots (Fundorte), DataNames (Namen, eigene
                            SavedVariable), DataProviders und DataGatherMate2 (Fundorte anderer Addons), DataSources (Orte eines
                            Items), DataSkills mit DataSkillsTable
    Loot/                   Erfassen: Loot (gemeinsamer Zustand, Zählhilfen), LootNode, LootCreature, LootSkinning (je ein Thema),
                            LootWindow (Beutefenster), LootKills, LootArea (Debug Gebiet), LootEvents (Event-Frame, Start/Stop)
    Tooltip/                Tooltip (Zeilen für Knoten, Kreaturen und Items), TooltipSources (Orte, Symbole, Gruppen),
                            TooltipWaypoint (Wegpunkt-Taste), TooltipSkills (Skill-Zeile)
  Modules/Debug/            Rohdaten im Tooltip (Debugger-Kategorie tooltip), Probes (/gli probe gathering ...)
  Locales/                  enUS, deDE
  Media/                    Icon, Markierungen (Markers)
tests/                      Logik-Tests ohne WoW (mit der echten Glimpse_Database aus dem Kern)
```

Eine zentrale XML und pro Ordner eine eigene XML, wie der Core. Die Einstellungen liegen weiter in den Namespaces
`GatheringDB` und `GatheringTooltip` von `Glimpse.db`, damit sie aus der Zeit der zwei Addons erhalten bleiben.

## Mit den Dateien arbeiten

Ein Klon des Repos liegt außerhalb des AddOns-Ordners, der Addon-Ordner wird verlinkt:

```
# Windows (PowerShell als Administrator, oder Entwicklermodus)
mklink /J "...\Interface\AddOns\Glimpse_Gathering" "C:\dev\Glimpse_Gathering\Glimpse_Gathering"

# macOS / Linux
ln -s ~/dev/Glimpse_Gathering/Glimpse_Gathering "<AddOns>/Glimpse_Gathering"
```

Die alten Ordner `Glimpse_GatheringDB` und `Glimpse_GatheringTooltip` müssen weg, sonst laufen zwei Sammler (das Addon
meldet das beim Start).

Änderungen sind dann nach `/reload` im Spiel.

## Lese-Schnittstelle des Moduls GatheringData (API_VERSION 11)

Erreichbar über `Glimpse:GetModule("GatheringData")`, gedacht für die Anzeige im selben Addon. Die Schnittstelle ist eine dünne
Schicht über `GlimpseDB:Get("gathering")` und `GlimpseDB:Get("fishing")`; Weltwissen wird mit Scope `"all"` gelesen
(alle Charaktere und Importe). Die zurückgegebenen Tabellen sind nur zum Lesen gedacht.

| Funktion | Rückgabe |
| --- | --- |
| `:GetNode(id)` / `:GetNPC(id)` | `{ name, category, attempts, items }` bzw. `{ name, level, loot = { attempts, items }, skinning = { ... } }` oder nil; `category` kommt aus der Beute (Kraut, Erz, sonst `"other"`) |
| `:GetNodeDrops(id)` | Liste der Beute (je Eintrag `itemID`, `hits`, `attempts`, `amount`, `chance`, `average`), Zahl der Versuche |
| `:GetNPCDrops(id, kind)` | dasselbe, `kind` = `"loot"` oder `"skinning"` |
| `:GetNodeDropsByName(name)` | wie `GetNodeDrops`, über den Namen (mehrere IDs zusammengerechnet) |
| `:FindNodeIDs(name)` / `:GetTooltipName(tooltip)` | Namenssuche für Weltobjekte ohne ID |
| `:GetItemSources(itemID, minAttempts)` | alle Quellen eines Items, wahrscheinlichste zuerst |
| `:GetStats()` | Knoten, Kreaturen, erfasste Beutefenster, Fundorte, Angelzonen, Angel-Beutefenster (seit API 11 Beutefenster statt Würfe) |
| `:GetSpots(kind, id, includeExternal)` | Fundorte einer Quelle: Liste `{ map, x, y, count, source }` (x, y = 0..1); Zone ohne bekannten Ort (Kreaturen immer): `{ map, count, source }` ohne `x`, `y`; Beute aus Instanzen: `{ instance, name, count, source }` ohne `map`, `x`, `y` (kein Wegpunkt möglich). `count` = Funde in dieser Zone. Erst die eigenen (`source = "own"`, häufigste zuerst), dann fremde (`source = "GatherMate2"`, `count = 0`, `density` = Punkte dort); `includeExternal = false` liefert nur eigene |
| `:GetOwnSpots(kind, id)` | nur die eigenen Fundorte |
| `:GetNearestSpots(kind, id, limit, currentMapOnly)` | wie `GetSpots`, aber die Orte auf der Karte des Spielers zuerst, nach Entfernung: `distance` in Yards (nur wenn die Kartengröße bekannt ist), `mapDistance` als Bruchteil der Kartenbreite |
| `:GetItemSpots(itemID, minAttempts, limit, includeExternal)` | Fundorte aller Quellen eines Items: `{ map, x, y, count, source, density, kind, id, mode, name, chance }` |
| `:GetLocatedItemSources(itemID, minAttempts, externalSeparate, minChance)` | Die Orte der Quellen eines Items, geordnet nach "wo findet man es am besten". Ein Eintrag ist eine Quelle an einem Ort (Zone oder Instanz): eine Quelle in drei Zonen ergibt drei Einträge, mehrere Orte derselben Zone einen (Kopien der Einträge von `GetItemSources` mit `tier`, `area`, `group`, `spot`, `spots`, `place`). Stufen: 1 `"here"` (Gebiet des Spielers: Karte oder Instanz), 2 `"nearby"` (andere Karte desselben Kontinents, nach Entfernung in Yards, ab `minChance` (0 bis 1)), 3 `"elsewhere"` (anderer Kontinent oder andere Instanz), 4 `"none"` (kein Ort, ein Eintrag je Quelle). Innerhalb einer Stufe zuerst `group = "own"` (bestätigter Ort), dann `"external"` (Ort nur von einem anderen Addon); danach in Stufe 1 und 3 die höchste Chance. Ein Ort in der eigenen Zone zählt auch, wenn er nur extern belegt ist. `spot` ist der beste Ort des Eintrags. `externalSeparate = false`: externe zählen wie bestätigte (Standard `true`; die Option dafür steht im Tab Handwerksmaterial) |
| `:GetRequiredSkill(kind, id, level)` | Beruf (`"herb"`, `"ore"`, `"skinning"`), benötigter Skill, bei Kreaturen dazu, ob sie als kürschnerbar bekannt sind (Kürschner-Beute aufgezeichnet). `kind` = `"node"` (Objekt-ID) oder `"npc"` (Kreatur-ID, `level` = Stufe, ohne Angabe die gespeicherte). nil ohne Ergebnis (unbekannter Knoten, Boss-Stufe). Die Tabellen stehen in `Core/Data/DataSkillsTable.lua` (Quellen dort im Kopf), nicht in den SavedVariables |
| `:GetNodeSkill(id)` / `:GetSkinningSkill(level)` | dasselbe einzeln. Ein Knoten, der nicht in der Tabelle steht, aber aufgezeichnet ist, wird über sein Material zugeordnet, wenn alle Materialien denselben Skill verlangen |
| `:GetSkillColor(required, current)` | `"red"` (reicht nicht), `"orange"` (ab `required`), `"yellow"` (+25), `"green"` (+50), `"gray"` (+100), dazu r, g, b |
| `:GetPlayerSkill(profession)` | Skill mit Ausrüstungsbonus, Maximum, Name des Berufs im Client, Skill ohne Bonus; nil = nicht gelernt. Berufe werden über Skill-Linien-IDs gefunden, nicht über Namen; Cache, geleert bei `SKILL_LINES_CHANGED` und `PLAYER_EQUIPMENT_CHANGED` |
| `:HasProfession(profession)` | true/false, nil wenn der Client die Berufe nicht auslesen lässt |
| `:IsKnownSkinnable(id)` / `:GetCreatureTypeID(unit)` / `:IsSkinnableType(typeID)` | Kreatur mit Kürschner-Beute aufgezeichnet; Typ-ID einer Einheit (1 = Wildtier, 2 = Drachkin) unabhängig von der Clientsprache; Typ kann kürschnerbar sein |
| `:GetFishing(zone)` / `:GetFishingDrops(zone)` | Angelzone aus dem Namespace `fishing` (schreibt Glimpse: Professions): `{ attempts, items }` bzw. Liste der Fänge wie bei `GetNodeDrops`, dazu die Zahl der Beutefenster. In `GetItemSources` und `GetLocatedItemSources` erscheint die Zone als Quelle mit `kind = "fishing"`, `mode = "fishing"`, `id` = Zone; `GetSpots("fishing", zone)` liefert die Orte aus `fishing`, sonst die Zone selbst |
| `:GetProviders()` / `:RegisterProvider(name, provider)` | Anbieter fremder Fundorte abfragen (`{ name, available, enabled }`) bzw. anmelden |
| `:GetMapName(map)` / `:GetInstanceName(id)` | Name der Karte (uiMapID) bzw. der Instanz oder nil |
| `:GetNodeName(id)` / `:GetNPCName(id)` | Name (bei Kreaturen dazu die Stufe) aus `GlimpseGatheringNames` |

Ein Eintrag der Beuteliste: `{ itemID, hits, attempts, amount, chance (0..1), average }` (`attempts` = Versuche der
ganzen Quelle, nicht nur dieses Items). Eine Quelle aus `GetItemSources`: `{ kind ("node"|"npc"), id,
mode ("gather"|"loot"|"skinning"), name, level, category, attempts, hits, amount, chance, average }`.

Änderungen meldet Glimpse: Database: `GlimpseDB.RegisterCallback(obj, GlimpseDB.EVENT_CHANGED, func)` mit
`(event, namespace, kind, id)`, Namespace `"gathering"` bzw. `"fishing"` (nil = vieles auf einmal, z. B. Import).
Die Nachricht `GLIMPSE_GATHERING_UPDATED` gibt es nicht mehr.

Wer `API_VERSION` nutzt, prüft `(GatheringData.API_VERSION or 0) >= 3` (2 = Fundorte, Export/Import; 3 = Fundorte aus anderen Addons, `GetNearestSpots`; 4 = `GetLocatedItemSources`; 5 = Karten, Position und Entfernungen sind in das Glimpse-Modul `Locations` gewandert, `GetMapSize`, `GetMapDistance`, `GetContinent`, `GetWorldPosition`, `GetPlayerArea` entfallen hier, `GetMapName` bleibt; 6 = `GetNPCKills`, `GetStats` liefert die Kills als fünften Wert (beides mit 10 entfernt); 7 = Skill-Funktionen `GetRequiredSkill`, `GetSkillColor`, `GetPlayerSkill` und Verwandte). 9 = `IsFishing`, `IsBobber`, `GetPlayerSkill("fishing")`; 8 = Angeln (`GetFishing`, `GetFishingDrops`, Quelle `"fishing"`, `GetStats` liefert Zonen und Würfe als sechsten und siebten Wert, Datenversion 6, Export enthält `fishing`). 10 = der Kill-Zähler ist weg: `GetNPCKills` und `RecordKill` entfallen, `GetStats` liefert Angelzonen und Würfe als fünften und sechsten Wert. 11 = Daten in Glimpse: Database: `ExportData`, `ImportData`, `ResetData`, `IsFishing`, `IsBobber`, `AddFishingItems`, `RecordFishing` und die Nachricht `GLIMPSE_GATHERING_UPDATED` entfallen; `GetStats` liefert Angel-Beutefenster statt Würfe; Fundorte von Kreaturen nur noch als Zone; neu `GetNodeName`, `GetNPCName`, `GetInstanceName`.

Für TomTom: `GetSpots`/`GetItemSpots` liefern `map` (uiMapID) und `x`, `y` als Bruchteil 0..1, also direkt
`TomTom:AddWaypoint(spot.map, spot.x, spot.y, { title = ... })`.

## Gespeicherte Daten

Die Zahlen liegen in Glimpse: Database, Namespace `gathering` (Bereich `Gathering`, Zähler auch je Zone):

```
node [Objekt]                   Abbau eines Knotens (Versuch), je Zone                       Weltwissen
nodeloot:<Objekt> [Item]        Menge                                                        Weltwissen
nodedrop:<Objekt> [Item]        Beutefenster mit dem Item                                    Weltwissen
npc / npcloot:<NPC> / npcdrop:<NPC>      geplünderte Leichen (auch leere), Menge, Fenster    Weltwissen
skinned / skinloot:<NPC> / skindrop:<NPC> gekürschnerte Leichen, Menge, Fenster              Weltwissen
herb / ore / other [Objekt]     eigene Sammelzähler je Kategorie des Knotens                 persönlich
skin [NPC]                      eigener Kürschnerzähler                                      persönlich
Orte (ID = Objekt)              Fundorte der Knoten (ns:AddLocation)
```

* Zonen sind uiMapIDs, in Instanzen `-instanceID` (wie `Glimpse.IDs:ZoneKey`).
* `hits` (aus `*drop`) = in wie vielen Versuchen das Item vorkam (daraus die Chance), `amount` (aus `*loot`) = Gesamtmenge.
  Zusammengeführte Importe können mehr Funde als Versuche haben, gelesen wird höchstens `attempts`.
* Orte tragen in Database keine Art. Damit sich Objekt- und NPC-IDs nicht mischen, bekommen nur Knoten Orte; Kreaturen
  haben nur Zonen. Orte näher als `DB.SPOT_RADIUS` (1 % der Karte) an einem eigenen Ort werden nicht noch einmal angelegt.
* Angeln schreibt Glimpse: Professions in den Namespace `fishing` (`looted [Zone]`, `loot:<Zone> [Item]`,
  `drop:<Zone> [Item]`). Gathering liest ihn nur, Angelbeute (`IsFishingLoot()`) wird hier übersprungen.
* Daten einer neueren Version (`Register` meldet `NEWER_DATA`) rührt das Addon nicht an und zeichnet nicht auf.
* Grenzen gibt es keine mehr, Speicher und Bereinigung übernimmt Database.

Database speichert nur IDs. Namen, die der Client nicht aus einer ID liefern kann, stehen in der eigenen SavedVariable
`GlimpseGatheringNames` (account-weit):

```
nodes[objectID] = Name        -- nur ergänzt, der Zielname eines Zaubers ist nicht immer der Knoten
npcs[npcID] = Name, levels[npcID] = Stufe
instances[instanceID] = Name
```

Knoten-Tooltips in der Welt haben weder GUID noch ID, nur den Namen; deshalb `FindNodeIDs` über diese Namen. Knoten
aus einem Import, die nie selbst gesehen wurden, haben keinen Namen.

### Alte Daten

Die Beta startet mit leerer Datenbank (Sven, 2026-10-10). Alte Daten werden nicht übernommen: weder `GlimpseGatheringDB`
(bis 0.2.10) noch die Zahlen und Namen von GatheringDB (bis 0.3.5).

## Export und Import

Gibt es hier nicht mehr. Export, Import und Zurücksetzen gehören zu Glimpse: Database (Glimpse-Optionen, Tab Daten).
Exportiert wird das Weltwissen (siehe oben), die eigenen Sammelzähler bleiben persönlich.

## Fundorte aus anderen Addons (GatherMate2)

`Core/Data/DataProviders.lua` hängt beim Abfragen (`DB:GetSpots`) die Orte von Anbietern hinter die eigenen. Sie werden nie
gespeichert und nie exportiert. Ein Anbieter ist `{ IsAvailable(), GetSpots(kind, id, entry), GetInfo()? }`
und meldet sich mit `DB:RegisterProvider(name, provider)` an. Fehler im Anbieter werden mit `pcall` abgefangen
(`DB:ReportError`), die eigenen Orte bleiben. Fremde Orte nahe an einem eigenen (`SPOT_RADIUS`) fallen weg, je Quelle
gibt es höchstens `DB.EXTERNAL_LIMIT` (60), dabei kommt der beste Ort jeder Karte zuerst, damit keine Zone verloren geht. Die Option `useExternalSpots` (Standard an) schaltet alles ab, `externalSources[Name] = false` nur einen Anbieter
(für jeden angemeldeten Anbieter gibt es in den Optionen einen Schalter; beim Aufbau der Optionen bereits angemeldete
Anbieter erscheinen dort, später angemeldete nicht). Fundorte ohne Koordinaten (Kreaturen, Zonen) bekommen keine
Entfernung und stehen in ihrer Stufe hinten.

GatherMate2 ist kein Adapter von Glimpse: Database: Der Abgleich läuft über Namen und Typen statt IDs, die Punkte
werden zu Dichten zusammengefasst, jeder Anbieter hat einen eigenen Schalter, und die Daten werden nie kopiert.

`Core/Data/DataGatherMate2.lua` ist der Anbieter für GatherMate2 (nur Knoten, keine Kreaturen). Benutzt wird nur dessen
Schnittstelle: `GetNodesForZone`, `DecodeLoc`, `GetIDForNode`, `HBD:GetAllMapIDs` (ohne HBD die Speicher in `gmdbs`).
GatherMate2 hat eigene Knoten-IDs (Kupfervorkommen 201, Silberblatt 402), nicht die Objekt-IDs des Spiels; der Abgleich läuft
deshalb über den Namen. Die Kategorie wählt den Typ (`herb` → Herb Gathering, `ore` → Mining, sonst Extract Gas/Treasure/Logging;
fehlt sie oder steht sie auf `other`, werden auch die übrigen Typen versucht). Gesucht wird erst der genaue Name
(`GetIDForNode`), dann ohne Groß-/Kleinschreibung und Sonderzeichen (`reverseNodeIDs`), zuletzt der einzige Name des Typs mit
gleichem Anfang (mindestens 5 Zeichen). Beim ersten Zugriff wird ein Typ einmal gelesen und je Knoten in Rasterzellen von 1 % der
Karte zusammengefasst (`density` = Punkte je Zelle). Der Index wird nach den Nachrichten `GatherMate2NodeAdded`,
`GatherMate2NodeDeleted` und `GatherMate2Cleanup` frühestens nach 30 Sekunden erneuert. Ändert GatherMate2 seine
Schnittstelle, meldet sich der Anbieter als nicht verfügbar; `/gli probe gathering gm2` zeigt, wie viele Punkte GatherMate2 hat und wie viele davon ankommen (Fehlersuche); die Tests (`tests/test_gathermate.lua`) bilden die
Struktur nach.

## Wie die Beute erkannt wird

`Core/Loot/LootWindow.lua` liest bei `LOOT_OPENED` sofort alle Quellen des Beutefensters und wertet 0,3 s später aus
(`EVALUATE_DELAY`), weil `UNIT_SPELLCAST_SUCCEEDED` je nach Reihenfolge kurz vor oder nach dem Beutefenster kommt.

* **Sammelknoten** (`GameObject`): zählt nur, wenn direkt davor (1 s) ein Zauber des Spielers erfolgreich war oder
  (Ersatz) ein Zauber innerhalb von 10 s abgeschickt wurde, und mindestens ein Material dabei ist. Gezählt wird je Zauber
  (`nodeMark`): derselbe Knoten kann mehrmals nacheinander und nach dem Nachwachsen (gleiche GUID) wieder zählen, ein
  erneut geöffnetes Fenster desselben Zaubers nicht. Truhen gehen ohne Zauber auf und fallen deshalb weg.
* **Kreaturen** (`Creature`): Normalbeute zählt als Versuch, auch ohne Material. Kürschnerbeute wird erkannt, wenn
  direkt davor (1 s) der Zauber Kürschnern erfolgreich war (bekannte Ränge oder gleicher Zaubername), oder beim zweiten
  Looten derselben Leiche direkt nach einem anderen Zauber. Dieselbe Kreatur zählt 10 Minuten
  nicht erneut (`CREATURE_REPEAT`, Teilloot).
* **Kills ohne Beutefenster** (`Core/Loot/LootKills.lua`): Quelle ist das Ereignis `PARTY_KILL` (Killer-GUID, Opfer-GUID): Es zählt, wenn der Killer
  der Spieler oder sein Haustier ist, auch ohne Ziel und ohne Beute (`DB:OnPartyKill`). Kennt der Client das Ereignis
  nicht, bleibt der Tod des Ziels als Ersatz (`UNIT_HEALTH`, Zielwechsel auf eine Leiche, Kampfende), der Kills nach
  einem Zielwechsel verpasst. Das Kampflog ist für Addons gesperrt und wird nicht benutzt. Kommt 2 Minuten lang kein
  Beutefenster (`KILL_FALLBACK`) und sagt `CanLootUnit` nicht, dass noch Beute da ist, zählt der Kill als Versuch. Beute,
  die danach kommt, wird ohne zweiten Versuch ergänzt. Das Fenster hat immer Vorrang.
* Gespeichert werden nur Handwerkswaren und Edelsteine (Item-Klassen 7 und 3).

Geschrieben wird in `LootNode.lua` (Knoten), `LootCreature.lua` (Normalbeute) und `LootSkinning.lua` (Kürschnern).

Das sind Heuristiken. Der Debugger `GatheringData` (`Glimpse:NewDebugger`, Kategorien `node`, `creature`, `skinning`,
`kill`, `area`, `error`, `tooltip`) schreibt pro Beutefenster eine Zeile (`Beutefenster: Typ, ID, Zauber davor,
Materialien`) und zu jedem Kill, warum er gezählt wurde oder nicht. Fehler in der Auswertung werden abgefangen und
gezählt (`/gli probe gathering stats`). Weitere Probes: `skill`, `gm2`, `area`, `names`, `fishing [Zone]`,
`node <ID>`, `npc <ID>`, `item <ID>` (`Modules/Debug/DebugProbes.lua`).

## Anzeige (Modul GatheringTooltip)

`Core/Tooltip/Tooltip.lua` baut die Zeilen: Knoten und Kreaturen zeigen ihre Beute wie die Quellen eines Items (Chance,
Treffer/Versuche, Durchschnitt), Materialien die besten Orte aus `GetLocatedItemSources`. Orte, die nur von einem anderen
Addon kommen, zeigen keine Chance. `Core/Tooltip/TooltipSources.lua` ordnet Symbole, Gruppen und Fundorte (Spalten) an,
`Core/Tooltip/TooltipWaypoint.lua` setzt über das Glimpse-Modul `Locations` einen Wegpunkt zum besten Ort. Der Tastenhörer dafür wird im
Kampf nicht angefasst (geschützte Aufrufe) und danach nachgezogen (`PLAYER_REGEN_ENABLED`).

## Prüfen

```
lua tests/run.lua        # Lesen und Beute-Erkennung mit nachgebautem Beutefenster und echter Glimpse_Database
luacheck .
python3 tools/check.py
```

## Veröffentlichen

Versionsschema (alle Glimpse-Addons): `X.Y.Z-PHASE.N`, Tag `vX.Y.Z-PHASE.N`, z. B. `0.3.4-alpha.2`.
* `X` Major-Release, `Y` Minor-Release, `PHASE` (`alpha`, `beta`, `latest`): gibt nur Sven vor und frei.
* `Z` Bugfix/Features: steigt bei jeder Änderung in einem Addon-Ordner des Repos (Code, TOC, Kommentare, Medien).
* `N` Repository-Version: steigt bei Änderungen außerhalb der Addon-Ordner (Checks, Tests, Workflows, Doku, README).
  Ein neues `Z` setzt `N` auf 1 zurück.
* Ändert sich nur `N`, wird kein Release gebaut (kein Tag durch `ci.yml`, ein Tag von Hand bricht `release.yml` ohne
  Release ab).
* Bevor ein Repo gebaut wird, werden die Änderungen aufgelistet und von Sven freigegeben.

Die Phase steht in der Version der TOC (`## Version:`), das Tag heißt immer `v` + diese Version:

| `## Version:` in der TOC | Tag | GitHub | CurseForge |
| --- | --- | --- | --- |
| `X.Y.Z-alpha.N` | `vX.Y.Z-alpha.N` | Prerelease | nichts |
| `X.Y.Z-beta.N` | `vX.Y.Z-beta.N` | Release mit „(Beta)“ im Titel, nicht „Latest“ | Beta |
| `X.Y.Z-latest.N` | `vX.Y.Z-latest.N` | Release, als „Latest“ markiert | Release |

Wago und WoWInterface sind abgeschaltet, bis Sven sie freigibt. Eine Version ohne Phase lehnt `tools/check.py` ab;
alte Tags ohne Phase (`v0.2.3`) zählen wie latest.

Alle TOCs eines Repos müssen dieselbe Version haben. Im `CHANGELOG.md` brauchen beta und latest den Abschnitt
`## [X.Y.Z]`, bei alpha reicht `## [Unreleased]`. Die Phase steht nicht im CHANGELOG.

1. Version in der TOC setzen und den CHANGELOG-Abschnitt schreiben.
2. Auf `main` pushen. Ist die Pipeline (Struktur, luacheck, Tests) grün und gibt es für die Basisversion noch kein Tag
   derselben oder einer höheren Phase (alpha < beta < latest, `N` zählt nicht), setzt `ci.yml` das Tag selbst und
   startet `release.yml` per `workflow_dispatch` auf dem Tag (ein mit dem `GITHUB_TOKEN` gepushtes Tag löst keinen
   Push-Workflow aus).
3. `release.yml` prüft Tag, TOC-Version und CHANGELOG, baut das ZIP mit dem BigWigs-Packager, legt das GitHub-Release
   an und kennzeichnet es nach der Tabelle oben.

Eine Version erscheint so nacheinander als alpha, beta und latest: nur die Phase in der TOC ändern
(`0.2.3-alpha.1` → `0.2.3-beta.1` → `0.2.3-latest.1`) und pushen. `0.2.3-beta.2` baut kein Release, weil sich nur das
Repo geändert hat. Von Hand geht es auch (`git tag v0.2.4-beta.1 && git push --tags`), das löst `release.yml` direkt aus.

Was jetzt anstünde, zeigt `python3 tools/check.py --next-tag` (leer: nichts). Fehlt der CHANGELOG-Abschnitt für die Version
oder weichen TOC-Versionen ab, wird kein Tag gesetzt und der Lauf schlägt fehl. Bleibt die Version gleich, passiert
nichts. Gibt es ein Tag, aber noch kein Release (ein früherer Lauf ist gescheitert), wird nur das Release gebaut.

**CurseForge:** Die Projekt-ID 1730186 steht als `## X-Curse-Project-ID` in beiden TOCs und zusätzlich als `-p` im
Packager-Schritt von `release.yml`, weil das Paket keine TOC im Hauptordner hat. Hochgeladen wird nur, wenn das
Repo-Secret `CF_API_KEY` gesetzt ist (GitHub: Settings > Secrets and variables > Actions). Der Token gehört nie ins Repo. Hochgeladen werden nur beta (als Beta) und latest (als Release).

Beide TOCs tragen `## X-Glimpse-MinVersion` (kleinste passende Core-Version).
