local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")

-- Beruf gelernt? Für die Option "Nur gelernte Berufe" (blendet Knoten und Kürschnerbeute aus).

-- Berufs-Skill-Linien (die Grundlinie des Berufs, nicht die einer Erweiterung)
-- Schlüssel: Kategorie des Knotens in GatheringDB bzw. "skinning" für Kürschnerbeute
local SKILL_LINES = {
    herb = 182,     -- Kräuterkunde
    ore = 186,      -- Bergbau
    skinning = 393, -- Kürschnerei
    fishing = 356,  -- Angeln (https://warcraft.wiki.gg/wiki/TradeSkillLineID)
}

--- true, wenn der Beruf zur Kategorie gelernt ist. Auch true bei Option aus, "other" oder wenn der
-- Client die Berufe nicht liefert (lieber zu viel anzeigen).
function GT:IsLearned(category)
    if not self.db.profile.onlyLearned then return true end

    local skillLine = SKILL_LINES[category]
    if not skillLine then return true end
    if not (GetProfessions and GetProfessionInfo) then return true end

    local ok, learned = pcall(function()
        -- Beruf 1, Beruf 2, Archäologie, Angeln, Kochen (je evtl. nil)
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
