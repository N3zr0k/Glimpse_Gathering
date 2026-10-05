local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")

-- Prüft, ob der Spieler einen Beruf gelernt hat. Damit lassen sich Knoten und Kürschnerbeute
-- ausblenden, die ihn ohnehin nicht betreffen (Option "Nur gelernte Berufe").

-- Berufs-Skill-Linien (die Grundlinie des Berufs, nicht die einer Erweiterung)
-- Schlüssel: Kategorie des Knotens in GatheringDB bzw. "skinning" für Kürschnerbeute
local SKILL_LINES = {
    herb = 182,     -- Kräuterkunde
    ore = 186,      -- Bergbau
    skinning = 393, -- Kürschnerei
}

--- true, wenn der Spieler den Beruf zu dieser Kategorie gelernt hat.
-- Gilt immer als erfüllt, wenn die Option aus ist, die Kategorie keinen Beruf braucht ("other")
-- oder der Client die Berufe nicht auslesen lässt (lieber zu viel anzeigen als zu wenig).
function GT:IsLearned(category)
    if not self.db.profile.onlyLearned then return true end

    local skillLine = SKILL_LINES[category]
    if not skillLine then return true end
    if not (GetProfessions and GetProfessionInfo) then return true end

    local ok, learned = pcall(function()
        -- Rückgabe: Beruf 1, Beruf 2, Archäologie, Angeln, Kochen (einzelne können nil sein)
        local indexes = { GetProfessions() }

        for position = 1, 5 do
            local index = indexes[position]
            if index then
                local _, _, _, _, _, _, line = GetProfessionInfo(index)
                if line == skillLine then return true end
            end
        end
        return false
    end)

    -- Bei einem Fehler im Client nichts verstecken
    if not ok then return true end
    return learned
end
