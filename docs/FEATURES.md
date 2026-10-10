# Glimpse: Gathering – Funktionen

Stand 0.3.5-alpha.1. Zwei Addons: Glimpse: GatheringDB (erfasst) und Glimpse: GatheringTooltip (zeigt an).
Benötigt Glimpse (Core) 0.3.14 oder neuer mit Glimpse: Database.

## GatheringDB

| Funktion | Beschreibung | Option (Standard) |
| --- | --- | --- |
| Sammelknoten erfassen | Jedes Beutefenster eines Knotens (Kräuter, Erz, sonstige) mit Handwerksmaterial zählt als Versuch, dazu Menge und Treffer je Item. Truhen zählen nicht. | Erfassen (an) |
| Kreaturen-Beute erfassen | Jede geplünderte Leiche ist ein Versuch, auch ohne Material. Kills ohne Beutefenster zählen nach 2 Minuten, wenn die Leiche keine Beute mehr hat. | Erfassen (an) |
| Kürschnern erfassen | Erkannt am Kürschnern-Zauber oder an einer schon geplünderten Leiche. | Erfassen (an) |
| Eigene Sammelzähler | Kräuter, Erz, sonstige Knoten und Kürschnern je Charakter und Zone. | – |
| Fundorte | Knoten mit Zone und Koordinaten (nahe Orte zusammengefasst), Kreaturen nur mit Zone, in Instanzen die Instanz. | Fundorte aufzeichnen (an) |
| Fremde Fundorte | GatherMate2-Orte werden live hinter die eigenen gehängt, nie gespeichert. Je Anbieter abschaltbar. | Andere Addons (an) |
| Namen | Namen von Knoten, Kreaturen und Instanzen in einer eigenen SavedVariable, weil Database nur IDs speichert. | – |
| Lese-API | `Glimpse.GatheringDB` für andere Addons: Beute, Quellen eines Items, Fundorte, Skills. | – |
| Debug und Probes | Rohdaten im Tooltip (`/gli debug on`) und `/gli probe gathering stats\|skill\|gm2\|area\|names\|fishing\|node\|npc\|item`. | – |

## GatheringTooltip

| Funktion | Beschreibung | Option (Standard) |
| --- | --- | --- |
| Knoten- und Kreatur-Tooltip | Beute mit Chance, Treffer/Versuche und Ø-Menge. Kreaturen mit eigener Kürschnern-Liste. | Knoten, Kreaturen-Beute, Kürschnerbeute (an) |
| Benötigter Skill | Skill eines Knotens oder einer Kreatur, eigener Skill eingefärbt; graue Knoten ausblendbar. | Skill anzeigen (an) |
| Material-Tooltip | Beste Fundorte eines Materials: eigenes Gebiet zuerst, dann nach Entfernung, mit Symbol, Ort und Chance. Angelplätze inklusive. | Quellen anzeigen (an), Anzahl Orte (3) |
| Markierung | Kleines Symbol am Ort, an dem man steht; fünf Symbole, fünf Farben. | Markierung (an) |
| Wegpunkt | Taste (Standard Strg+G) setzt einen Wegpunkt zum besten Ort, über TomTom oder die Spielmarkierung. | Taste, Hinweiszeile |
| Filter | Nur gelernte Berufe, Mindestzahl an Versuchen, nur mit Shift/Strg/Alt. | – |

## Datenbank

| Namespace | Daten | Lesen | Schreiben |
| --- | --- | --- | --- |
| `gathering` | `node`, `nodeloot:<Objekt>`, `nodedrop:<Objekt>`, `npc`, `npcloot:<NPC>`, `npcdrop:<NPC>`, `skinned`, `skinloot:<NPC>`, `skindrop:<NPC>` (Weltwissen), `herb`, `ore`, `other`, `skin` (eigene Zähler), Fundorte der Knoten | ja | ja (nur GatheringDB) |
| `fishing` | Angelbeute und Angelplätze (Schreiber Glimpse: Professions) | ja | nein |

GatheringTooltip greift nie direkt auf Database zu, nur über die Lese-API von GatheringDB.

Außerhalb der Database: `GlimpseGatheringNames` (Namen, GatheringDB), `GlimpseGatheringDB` (alte Daten, nur für die
Übernahme durch Database, wird nie verändert). Einstellungen in `Glimpse.db`, Namespaces `GatheringDB` und
`GatheringTooltip`.
