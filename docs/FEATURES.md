# Glimpse: Gathering – Funktionen

Stand 0.3.10-beta.2. Ein Addon, das erfasst und anzeigt (bis 0.3.5 zwei Addons: GatheringDB und GatheringTooltip).
Benötigt Glimpse (Core) 0.3.33 oder neuer mit Glimpse: Database.

## Erfassen

| Funktion | Beschreibung | Option (Standard) |
| --- | --- | --- |
| Sammelknoten erfassen | Jedes Beutefenster eines Knotens (Kräuter, Erz, sonstige) mit Handwerksmaterial zählt als Versuch, dazu Menge und Treffer je Item. Truhen zählen nicht. | Erfassen (an) |
| Kreaturen-Beute erfassen | Jede geplünderte Leiche ist ein Versuch, auch ohne Material. Kills ohne Beutefenster zählen nach 2 Minuten, wenn die Leiche keine Beute mehr hat. | Erfassen (an) |
| Kürschnern erfassen | Erkannt am Kürschnern-Zauber oder an einer schon geplünderten Leiche. | Erfassen (an) |
| Eigene Sammelzähler | Kräuter, Erz, sonstige Knoten und Kürschnern je Charakter und Zone. | – |
| Fundorte | Knoten mit Zone und Koordinaten (nahe Orte zusammengefasst), Kreaturen nur mit Zone, in Instanzen die Instanz. | Fundorte aufzeichnen (an) |
| Fremde Fundorte | GatherMate2-Orte werden live hinter die eigenen gehängt, nie gespeichert. Je Anbieter abschaltbar. | Andere Addons (an) |
| Namen | Namen von Knoten, Kreaturen und Instanzen in einer eigenen SavedVariable, weil Database nur IDs speichert. Gelernt beim Looten und beim Mouseover (Knoten: Name aus dem Tooltip vor dem Abbau), Kreaturen auch aus dem Client-Cache. | – |
| Hinweis auf alte Ordner | Liegen `Glimpse_GatheringDB` oder `Glimpse_GatheringTooltip` noch im AddOns-Ordner, kommt beim Start ein Hinweis im Chat. | – |
| Debug und Probes | Rohdaten im Tooltip (`/gli debug on`) und `/gli probe gathering stats\|skill\|gm2\|area\|names\|fishing\|node\|npc\|item`. | – |

## Anzeige

| Funktion | Beschreibung | Option (Standard) |
| --- | --- | --- |
| Knoten- und Kreatur-Tooltip | Beute mit Chance, Treffer/Versuche und Ø-Menge. Kreaturen mit eigener Kürschnern-Liste. | Knoten, Kreaturen-Beute, Kürschnerbeute (an) |
| Benötigter Skill | Skill eines Knotens oder einer Kreatur, eigener Skill eingefärbt; graue Knoten ausblendbar. | Skill anzeigen (an) |
| Material-Tooltip | Beste Fundorte eines Materials: eigenes Gebiet zuerst, dann nach Entfernung, mit Symbol, Ort und Chance. Angelplätze inklusive. | Quellen anzeigen (an), Anzahl Orte (3) |
| Markierung | Kleines Symbol am Ort, an dem man steht; fünf Symbole, fünf Farben. | Markierung (an) |
| Wegpunkt | Taste (Standard Strg+G) setzt einen Wegpunkt zum besten Ort, über TomTom oder die Spielmarkierung. | Taste, Hinweiszeile |
| Filter | Nur gelernte Berufe, Mindestzahl an Versuchen, nur mit Shift/Strg/Alt. | – |
| Optionen | Eine Seite mit vier Tabs: Allgemein, Handwerksmaterial, Ziel, Erfassen. | – |

## Datenbank

| Namespace | Daten | Lesen | Schreiben | Beides |
| --- | --- | --- | --- | --- |
| `gathering` | `node`, `nodeloot:<Objekt>`, `nodedrop:<Objekt>`, `npc`, `npcloot:<NPC>`, `npcdrop:<NPC>`, `skinned`, `skinloot:<NPC>`, `skindrop:<NPC>` (Weltwissen), `herb`, `ore`, `other`, `skin` (eigene Zähler), Fundorte der Knoten | – | – | ja (Besitzer, einziger Schreiber) |
| `fishing` | Angelbeute und Angelplätze (Schreiber Glimpse: Professions) | ja | – | – |

Die Anzeige liest über das Modul `GatheringData`, nie direkt.

Außerhalb der Database: `GlimpseGatheringNames` (Namen). Einstellungen in `Glimpse.db`, Namespaces `GatheringDB` und
`GatheringTooltip` (Namen von früher, damit die Einstellungen bleiben).
