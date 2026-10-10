# Glimpse: Gathering – Dateien

Das Repo enthält zwei Addons: `Glimpse_GatheringDB` (erfasst) und `Glimpse_GatheringTooltip` (zeigt an). Aufgeführt sind
alle Dateien der beiden Addon-Ordner, in Ladereihenfolge.

Glimpse: Database:
- `gathering`: Schreiber ist GatheringDB. Arten `node`/`nodeloot:<Objekt>`/`nodedrop:<Objekt>`,
  `npc`/`npcloot:<NPC>`/`npcdrop:<NPC>`, `skinned`/`skinloot:<NPC>`/`skindrop:<NPC>` (Weltwissen), dazu die eigenen
  Sammelzähler `herb`, `ore`, `other`, `skin` und die Fundorte der Knoten (ID = Objekt).
- `fishing`: Schreiber ist Glimpse: Professions, GatheringDB liest nur.

GatheringTooltip greift nicht selbst auf Database zu, sondern nur über die Lese-API von GatheringDB
(`Glimpse:GetModule("GatheringDB")`, `API_VERSION` 11).

Eigene SavedVariables (nur GatheringDB): `GlimpseGatheringNames` (Namen zu IDs, Database speichert nur IDs) und
`GlimpseGatheringDB` (alte Daten, nur noch für die AlphaMigration von Database, wird nie verändert). Einstellungen
liegen in `Glimpse.db` (SavedVariable `GlimpseSettings` des Cores), Namespaces `GatheringDB` und `GatheringTooltip`.

## Glimpse_GatheringDB

| Datei | Beschreibung | Database | Weitere Abhängigkeiten |
|---|---|---|---|
| `Glimpse_GatheringDB.toc` | Metadaten, lädt nur `Glimpse_GatheringDB.xml` | – | Benötigt Glimpse und Glimpse_Database (min. Core 0.3.14), optional GatherMate2. SavedVariables `GlimpseGatheringDB`, `GlimpseGatheringNames` |
| `Glimpse_GatheringDB.xml` | Lädt Locales, Core, Data, Loot, Debug in dieser Reihenfolge | – | – |
| `Locales/Locales.xml` | Lädt die Sprachdateien, `enUS` zuerst | – | – |
| `Locales/enUS.lua` | Englische Texte (Standard) | – | AceLocale-3.0 |
| `Locales/deDE.lua` | Deutsche Texte | – | AceLocale-3.0 |
| `Core/Core.xml` | Lädt die Core-Dateien, `GatheringDB.lua` zuerst | – | – |
| `Core/GatheringDB.lua` | Legt das Modul an, Konstanten, Einstellungen, Anmeldung bei Database, Start der Erfassung, Beschreibung der Lese-API | schreibt: meldet `gathering` an (`Register`); liest: `Get("gathering")`, `Get("fishing")`, Callback `EVENT_CHANGED` | `GlimpseDB`, Glimpse (`NewModule`, `NewDebugger`, `RegisterAddonOptions`), Namespace `GatheringDB` in `Glimpse.db` |
| `Core/Compat.lua` | Alle Blizzard-Funktionen an einer Stelle, `CheckAPI` meldet fehlende | – | Blizzard: `C_Item`, `C_Loot`, `C_Spell`, `C_CreatureInfo` |
| `Core/Options.lua` | Optionsseite: Fundorte aufzeichnen, Schalter je Fremd-Anbieter, Übersicht | liest über `GetStats` | Namespace `GatheringDB`, GatherMate2 (nur Schalter) |
| `Core/Data/Data.xml` | Lädt die Lese-Dateien | – | – |
| `Core/Data/Names.lua` | Namen von Knoten, NPCs und Instanzen, Suche über den Namen; übernimmt einmalig die Namen aus den alten Daten | – | liest und schreibt `GlimpseGatheringNames`, liest `GlimpseGatheringDB` |
| `Core/Data/Drops.lua` | Lese-API für Beute: Knoten, Kreaturen, Quellen eines Items, Statistik | liest: `gathering`, `fishing` (Weltwissen) | Modul Locations (Zonennamen) |
| `Core/Data/Spots.lua` | Lese-API für Fundorte aus Zonen und Orten | liest: `gathering`, `fishing` | Modul Locations |
| `Core/Data/Providers.lua` | Fundorte fremder Addons anhängen, Entfernung und Kontinent zum Spieler | – (nie gespeichert) | Modul Locations |
| `Core/Data/GatherMate2.lua` | Anbieter GatherMate2, nur lesend; Diagnose für die Probe | liest: `gathering` (Knotenliste für die Diagnose) | GatherMate2 (`GetNodesForZone`, `DecodeLoc`, `GetIDForNode`, `HBD`), dessen Callbacks |
| `Core/Data/Sources.lua` | Beste Fundorte je Material, sortiert nach Nähe (für GatheringTooltip) | liest über `Drops.lua`, `Spots.lua` | – |
| `Core/Data/SkillData.lua` | Statische Skill-Tabellen der Sammelknoten | – | – |
| `Core/Data/Skills.lua` | Benötigter Skill, Spieler-Skill, Farbe | – | Blizzard: Berufs- und Zauber-API |
| `Core/Loot/Loot.xml` | Lädt die Erfassung, `Loot.lua` zuerst, `LootEvents.lua` zuletzt | – | – |
| `Core/Loot/Loot.lua` | Gemeinsamer Zustand `DB.collect`, nur Handwerksmaterialien, Zählen einer Quelle | schreibt: `gathering` (`Count`) | `Compat.lua` |
| `Core/Loot/NodeDB.lua` | Abbau eines Knotens erfassen | schreibt: `gathering` (`node*`, `herb`/`ore`/`other`, Orte) | `Names.lua` |
| `Core/Loot/CreatureDB.lua` | Beute einer Kreatur erfassen | schreibt: `gathering` (`npc*`) | `Names.lua` |
| `Core/Loot/SkinningDB.lua` | Kürschnern erfassen | schreibt: `gathering` (`skinned*`, `skin`) | `CreatureDB.lua` |
| `Core/Loot/LootWindow.lua` | Beutefenster von Knoten und Kreaturen auswerten, Angelbeute ausgenommen | schreibt über `NodeDB`, `CreatureDB`, `SkinningDB` | Modul Locations, `Compat.lua` |
| `Core/Loot/LootKills.lua` | Kills ohne Beutefenster als Versuch zählen | schreibt über `CreatureDB.lua` | Modul Locations, `CanLootUnit` |
| `Core/Loot/LootArea.lua` | Debug-Ausgabe der Ortserkennung bei Gebietswechsel | – | Modul Locations, Debugger (Kategorie `area`) |
| `Core/Loot/LootEvents.lua` | Event-Frame (Zauber, Kills, Beute, Gebiet), `Start/StopCollecting` | – | AceEvent-3.0 |
| `Modules/Debug/Debug.xml` | Lädt Debug und Probes | – | – |
| `Modules/Debug/Debug.lua` | Debug-Tooltip mit Rohdaten (`/gli debug on`) | liest über die Lese-API | Modul Locations, `Glimpse:DebugTag` (Kopfzeile), liest Einstellungen von GatheringTooltip (falls geladen) |
| `Modules/Debug/DebugProbes.lua` | Probes `/gli probe gathering ...`, Zeilen für `/gli probe db sources` | liest: `gathering`, `fishing` | Glimpse (`RegisterProbe`, `RegisterDataSource`), liest `GlimpseGatheringDB`, `GlimpseGatheringNames` |
| `Media/Icon.tga` | Addon-Icon | – | – |
| `LICENSE` | MIT-Lizenz | – | – |

## Glimpse_GatheringTooltip

| Datei | Beschreibung | Database | Weitere Abhängigkeiten |
|---|---|---|---|
| `Glimpse_GatheringTooltip.toc` | Metadaten, lädt nur `Glimpse_GatheringTooltip.xml` | – | Benötigt Glimpse, Glimpse_Database, Glimpse_GatheringDB (min. Core 0.3.14), optional TomTom |
| `Glimpse_GatheringTooltip.xml` | Lädt Locales, Core, Tooltip in dieser Reihenfolge | – | – |
| `Locales/Locales.xml` | Lädt die Sprachdateien, `enUS` zuerst | – | – |
| `Locales/enUS.lua` | Englische Texte (Standard) | – | AceLocale-3.0 |
| `Locales/deDE.lua` | Deutsche Texte | – | AceLocale-3.0 |
| `Core/Core.xml` | Lädt die Core-Dateien, `GatheringTooltip.lua` zuerst | – | – |
| `Core/GatheringTooltip.lua` | Legt das Modul an, Einstellungen, prüft die API-Version von GatheringDB | – (nur über GatheringDB) | GatheringDB (`API_VERSION` ≥ 11), Namespace `GatheringTooltip` in `Glimpse.db`, AceEvent-3.0 |
| `Core/Professions.lua` | Hat der Spieler den Beruf gelernt (Option "Nur gelernte Berufe") | – | Blizzard: Berufs-API |
| `Core/Options.lua` | Optionsseite mit drei Tabs (Allgemein, Handwerksmaterial, Ziel) | – | Namespace `GatheringTooltip`, Modul Locations (`HasTomTom`), AceConfigRegistry-3.0 |
| `Core/Tooltip/Tooltip.xml` | Lädt die Tooltip-Dateien, `Tooltip.lua` zuletzt | – | – |
| `Core/Tooltip/Sources.lua` | Quelle mit Symbol, Fundort, Entfernung und Chance im Material-Tooltip, Markierung aus `Media/Markers` | liest über GatheringDB (`GetLocatedItemSources`) | Modul Locations (`FormatCoords`, `FormatDistance`) |
| `Core/Tooltip/Waypoint.lua` | Wegpunkt zum besten Fundort per Taste (Standard Strg+G), Tastenwahl-Dialog | liest über GatheringDB | Modul Locations (`SetWaypoint`, TomTom oder Spiel-Markierung) |
| `Core/Tooltip/Skills.lua` | Benötigter Sammel-Skill in Knoten- und Kreatur-Tooltips | – | GatheringDB (`GetRequiredSkill`, `GetSkillColor`, `GetPlayerSkill`) |
| `Core/Tooltip/Tooltip.lua` | Tooltip-Zeilen für Knoten, Kreaturen und Materialien | liest über GatheringDB (`gathering`, `fishing`) | Glimpse (`RegisterTooltipLine`, Modifier-Tasten), `C_Item` |
| `Media/Icon.tga` | Addon-Icon | – | – |
| `Media/Markers/*.tga` | Markierung des eigenen Fundorts im Material-Tooltip (Pfeil, Person, Pins) in fünf Farben | – | genutzt von `Sources.lua` |
| `Media/Markers/CREDITS.md` | Bildnachweis der Symbole (Flaticon, Namensnennung). Die Optionen zeigen keine eigenen Credits, die stehen nur in der Glimpse-Übersicht | – | – |
| `LICENSE` | MIT-Lizenz | – | – |
