# Glimpse: Gathering – Dateien

Das Repo enthält ein Addon, `Glimpse_Gathering` (bis 0.3.5 die zwei Addons GatheringDB und GatheringTooltip). Aufgeführt
sind alle Dateien des Addon-Ordners, in Ladereihenfolge. Zwei Module: `GatheringData` erfasst und liest,
`GatheringTooltip` zeigt an.

Glimpse: Database:
- `gathering`: Schreiber ist Glimpse: Gathering. Arten `node`/`nodeloot:<Objekt>`/`nodedrop:<Objekt>`,
  `npc`/`npcloot:<NPC>`/`npcdrop:<NPC>`, `skinned`/`skinloot:<NPC>`/`skindrop:<NPC>` (Weltwissen), dazu die eigenen
  Sammelzähler `herb`, `ore`, `other`, `skin` und die Fundorte der Knoten (ID = Objekt).
- `fishing`: Schreiber ist Glimpse: Professions, Gathering liest nur.

Die Anzeige greift nicht selbst auf Database zu, sondern über die Lese-API von `GatheringData` (`API_VERSION` 11).

Eigene SavedVariable: `GlimpseGatheringNames` (Namen zu IDs, Database speichert nur IDs). Einstellungen liegen in
`Glimpse.db` (SavedVariable `GlimpseSettings` des Cores), Namespaces `GatheringDB` und `GatheringTooltip` (Namen von
früher, damit die Einstellungen bleiben).

## Glimpse_Gathering

| Datei | Beschreibung | Database | Weitere Abhängigkeiten |
|---|---|---|---|
| `Glimpse_Gathering.toc` | Metadaten, lädt nur `Glimpse_Gathering.xml` | – | Benötigt Glimpse und Glimpse_Database (min. Core 0.3.33), optional GatherMate2 und TomTom. SavedVariables `GlimpseGatheringNames` |
| `Glimpse_Gathering.xml` | Lädt Locales, Core, Data, Loot, Tooltip, Debug in dieser Reihenfolge | – | – |
| `Locales/Locales.xml` | Lädt die Sprachdateien, `enUS` zuerst | – | – |
| `Locales/enUS.lua` | Englische Texte (Standard) | – | AceLocale-3.0 |
| `Locales/deDE.lua` | Deutsche Texte | – | AceLocale-3.0 |
| `Core/Core.xml` | Lädt die Core-Dateien, `GatheringData.lua` zuerst | – | – |
| `Core/GatheringData.lua` | Legt das Modul `GatheringData` an, Konstanten, Einstellungen, Anmeldung bei Database, Start der Erfassung, Beschreibung der Lese-API, Hinweis auf alte Addon-Ordner | schreibt: meldet `gathering` an (`Register`); liest: `Get("gathering")`, `Get("fishing")`, Callback `EVENT_CHANGED` | `GlimpseDB`, Glimpse (`NewModule`, `NewDebugger`), Namespace `GatheringDB` in `Glimpse.db` |
| `Core/Compat.lua` | Alle Blizzard-Funktionen an einer Stelle, `CheckAPI` meldet fehlende | – | Blizzard: `C_Item`, `C_Loot`, `C_Spell`, `C_CreatureInfo`, `C_AddOns`, `C_TooltipInfo` |
| `Core/OptionsRecording.lua` | Tab Erfassen: Fundorte aufzeichnen, Schalter je Fremd-Anbieter, Übersicht | liest über `GetStats` | Namespace `GatheringDB`, GatherMate2 (nur Schalter) |
| `Core/GatheringTooltip.lua` | Legt das Modul `GatheringTooltip` an, Einstellungen, meldet die Optionsseite an | – (nur über `GatheringData`) | Namespace `GatheringTooltip` in `Glimpse.db`, Glimpse (`RegisterAddonOptions`), AceEvent-3.0 |
| `Core/Professions.lua` | Hat der Spieler den Beruf gelernt (Option "Nur gelernte Berufe") | – | Blizzard: Berufs-API |
| `Core/Options.lua` | Optionsseite mit vier Tabs (Allgemein, Handwerksmaterial, Ziel, Erfassen) | – | Namespace `GatheringTooltip`, `OptionsRecording.lua`, Modul Locations (`HasTomTom`), AceConfigRegistry-3.0 |
| `Core/Data/Data.xml` | Lädt die Lese-Dateien | – | – |
| `Core/Data/Names.lua` | Namen von Knoten, NPCs und Instanzen, Suche über den Namen; Kreaturnamen aus dem Client-Cache (Unit-Link), Namen vom Mouseover lernen | – | liest und schreibt `GlimpseGatheringNames` |
| `Core/Data/Drops.lua` | Lese-API für Beute: Knoten, Kreaturen, Quellen eines Items, Statistik | liest: `gathering`, `fishing` (Weltwissen) | Modul Locations (Zonennamen) |
| `Core/Data/Spots.lua` | Lese-API für Fundorte aus Zonen und Orten | liest: `gathering`, `fishing` | Modul Locations |
| `Core/Data/Providers.lua` | Fundorte fremder Addons anhängen, Entfernung und Kontinent zum Spieler | – (nie gespeichert) | Modul Locations |
| `Core/Data/GatherMate2.lua` | Anbieter GatherMate2, nur lesend; Diagnose für die Probe | liest: `gathering` (Knotenliste für die Diagnose) | GatherMate2 (`GetNodesForZone`, `DecodeLoc`, `GetIDForNode`, `HBD`), dessen Callbacks |
| `Core/Data/Sources.lua` | Beste Fundorte je Material, sortiert nach Nähe (für den Material-Tooltip) | liest über `Drops.lua`, `Spots.lua` | – |
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
| `Core/Tooltip/Tooltip.xml` | Lädt die Tooltip-Dateien, `Tooltip.lua` zuletzt | – | – |
| `Core/Tooltip/Sources.lua` | Quelle mit Symbol, Fundort, Entfernung und Chance im Material-Tooltip, Markierung aus `Media/Markers` | liest über `GatheringData` (`GetLocatedItemSources`) | Modul Locations (`FormatCoords`, `FormatDistance`) |
| `Core/Tooltip/Waypoint.lua` | Wegpunkt zum besten Fundort per Taste (Standard Strg+G), Tastenwahl-Dialog | liest über `GatheringData` | Modul Locations (`SetWaypoint`, TomTom oder Spiel-Markierung) |
| `Core/Tooltip/Skills.lua` | Benötigter Sammel-Skill in Knoten- und Kreatur-Tooltips | – | `GatheringData` (`GetRequiredSkill`, `GetSkillColor`, `GetPlayerSkill`) |
| `Core/Tooltip/Tooltip.lua` | Tooltip-Zeilen für Knoten, Kreaturen und Materialien | liest über `GatheringData` (`gathering`, `fishing`) | Glimpse (`RegisterTooltipLine`, Modifier-Tasten), `C_Item` |
| `Modules/Debug/Debug.xml` | Lädt Debug und Probes | – | – |
| `Modules/Debug/Debug.lua` | Debug-Tooltip mit Rohdaten (`/gli debug on`) | liest über die Lese-API | Modul Locations, `Glimpse:DebugTag` (Kopfzeile), liest die Tooltip-Einstellungen (Sortierung) |
| `Modules/Debug/DebugProbes.lua` | Probes `/gli probe gathering ...`, Zeilen für `/gli probe db sources` | liest: `gathering`, `fishing` | Glimpse (`RegisterProbe`, `RegisterDataSource`), liest `GlimpseGatheringNames` |
| `Media/Icon.tga` | Addon-Icon | – | – |
| `Media/Markers/*.tga` | Markierung des eigenen Fundorts im Material-Tooltip (Pfeil, Person, Pins) in fünf Farben | – | genutzt von `Sources.lua` |
| `Media/Markers/CREDITS.md` | Bildnachweis der Symbole (Flaticon, Namensnennung). Die Optionen zeigen keine eigenen Credits, die stehen nur in der Glimpse-Übersicht | – | – |
| `LICENSE` | MIT-Lizenz | – | – |
