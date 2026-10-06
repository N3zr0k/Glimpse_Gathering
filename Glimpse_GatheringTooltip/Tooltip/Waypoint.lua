local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local GT = Glimpse:GetModule("GatheringTooltip")
local L = GT.L

-- Wegpunkt zum besten Fundort eines Materials. Ein Tooltip lässt sich nicht anklicken, deshalb löst eine
-- Taste aus (Option "Taste", Standard Strg+G), solange der Tooltip des Materials angezeigt wird.
-- Der Wegpunkt kommt aus dem Glimpse-Modul Locations: TomTom, wenn es installiert ist, sonst die Markierung des Spiels.

local target -- { map, x, y, title }, solange ein Tooltip mit Fundort sichtbar ist
local listener

--- Der Text einer Taste für Hinweise und Optionen: "CTRL-SHIFT-G" -> "Strg+Umschalt+G", "off" -> "Aus"
function GT:WaypointKeyName(key)
    key = key or self.db.profile.waypointKey
    if not key or key == "off" then return L["Off"] end

    local parts = {}
    for _, modifier in ipairs({ { "CTRL", L["Ctrl"] }, { "SHIFT", L["Shift"] }, { "ALT", L["Alt"] } }) do
        if key:find(modifier[1] .. "-", 1, true) then parts[#parts + 1] = modifier[2] end
    end
    parts[#parts + 1] = key:match("[^%-]+$") or key
    return table.concat(parts, "+")
end

-- Tasten, die nur Umschalter sind und allein keine Taste ergeben
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true,
}

-- Die gedrückte Kombination in der Schreibweise des Spiels (ALT-CTRL-SHIFT-Taste), wie GetBindingAction sie erwartet
local function PressedKey(key)
    local chord = ""
    if IsAltKeyDown and IsAltKeyDown() then chord = chord .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then chord = chord .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then chord = chord .. "SHIFT-" end
    return chord .. key
end
GT.PressedKey = PressedKey

--- Wofür die Kombination im Spiel schon belegt ist: Name der Aktion (z. B. "Vorwärts") oder nil, wenn sie frei ist.
-- Prüft die Tastenbelegung des Spiels (Optionen > Tastenbelegung). Zuerst die direkte Abfrage, danach ein Vergleich mit
-- allen Belegungen, weil die Schreibweise von Sondertasten (Ü, Ö, Ä ...) je nach Tastaturlayout abweichen kann.
function GT:FindBindingConflict(chord)
    if not chord or chord == "off" then return nil end

    local function Name(action)
        return _G["BINDING_NAME_" .. action] or action
    end

    -- direkt abfragen (mit checkOverride, damit auch Belegungen anderer Addons zählen), Groß- und Kleinschreibung
    -- und Umlaute können je nach Client abweichen
    if GetBindingAction then
        for _, variant in ipairs({ chord, chord:upper() }) do
            local ok, action = pcall(GetBindingAction, variant, true)
            if ok and type(action) == "string" and action ~= "" then return Name(action) end
        end
    end

    -- sonst alle Belegungen durchsehen
    if GetNumBindings and GetBinding then
        local wanted = chord:upper()
        for index = 1, GetNumBindings() do
            local values = { GetBinding(index) }
            for position = 3, #values do
                if type(values[position]) == "string" and values[position]:upper() == wanted then
                    return Name(values[1])
                end
            end
        end
    end
    return nil
end

--- Stellt die Taste ein. Gibt true zurück oder false und den Namen der Belegung, wenn die Kombination im Spiel
-- schon benutzt wird (dann bleibt die alte Taste). "off" schaltet die Taste aus.
function GT:SetWaypointKey(chord)
    local conflict = self:FindBindingConflict(chord)
    if conflict then return false, conflict end

    self.db.profile.waypointKey = chord
    self:UpdateWaypointListener()
    return true
end

-- Fehlermeldung als Fenster, wenn die gewünschte Kombination schon belegt ist
local POPUP = "GLIMPSE_GATHERINGTOOLTIP_KEY_IN_USE"

local errorFrame

-- Eigenes Fenster in der Bildschirmmitte: Überschrift, Text, Knopf. Wirft einen Fehler, wenn der Client die
-- nötigen Funktionen nicht hat (dann greift der Ersatz mit StaticPopup).
local function ShowErrorFrame(title, text)
    if not errorFrame then
        local frame = CreateFrame("Frame", "GlimpseGatheringTooltipErrorFrame", UIParent, "BackdropTemplate")
        frame:SetSize(380, 130)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        frame:SetFrameStrata("DIALOG")
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        frame:EnableMouse(true)

        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.title:SetPoint("TOP", 0, -18)
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.text:SetPoint("TOPLEFT", 24, -46)
        frame.text:SetPoint("TOPRIGHT", -24, -46)
        frame.text:SetJustifyH("CENTER")

        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(100, 22)
        button:SetPoint("BOTTOM", 0, 18)
        button:SetText(OKAY or "OK")
        button:SetScript("OnClick", function() frame:Hide() end)

        -- Escape schließt das Fenster
        if UISpecialFrames then tinsert(UISpecialFrames, "GlimpseGatheringTooltipErrorFrame") end
        errorFrame = frame
    end

    errorFrame.title:SetText(title)
    errorFrame.text:SetText(text)
    errorFrame:Show()
end

--- Meldung, dass die gewünschte Kombination schon belegt ist: Fenster in der Bildschirmmitte mit der Taste in Blau
function GT:ShowKeyInUse(chord, conflict)
    local text = format(L["The key %s is already used in the game: %s"], "|cff66ccff" .. self:WaypointKeyName(chord) .. "|r", conflict)
    local title = "|cffff5050" .. L["Error"] .. "|r"

    if CreateFrame and UIParent and pcall(ShowErrorFrame, title, text) then return end

    -- Ersatz: Standardfenster des Spiels oder Chat
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[POPUP] = StaticPopupDialogs[POPUP] or {
            text = "%s", button1 = OKAY or "OK", timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(POPUP, title .. "\n\n" .. text)
    else
        Glimpse:Print(text)
    end
end

local capture

--- Wartet auf die nächste Tastenkombination (für die Optionen). Escape bricht ab, Entf oder Rücktaste schaltet
-- die Taste aus. callback(chord oder nil bei Abbruch) wird einmal aufgerufen.
function GT:CaptureKey(callback)
    if not CreateFrame then return end
    if capture and capture.active then capture.callback(nil) end

    if not capture then
        capture = CreateFrame("Frame")
        capture:SetScript("OnKeyDown", function(frame, key)
            if not frame.active or MODIFIER_KEYS[key] then return end
            pcall(function() frame:SetPropagateKeyboardInput(false) end)
            frame.active = false
            pcall(function() frame:EnableKeyboard(false) end)

            local done = frame.callback
            if key == "ESCAPE" then return done(nil) end
            if key == "DELETE" or key == "BACKSPACE" then return done("off") end
            done(PressedKey(key))
        end)
    end
    capture.active, capture.callback = true, callback
    pcall(function()
        capture:EnableKeyboard(true)
        capture:SetPropagateKeyboardInput(false) -- die Taste nicht ans Spiel weitergeben, sonst läuft der Charakter los
    end)
end

function GT:IsCapturingKey()
    return capture ~= nil and capture.active == true
end

--- Das Ziel für die Taste setzen: spot = Fundort mit map, x, y (Instanzen haben keine Koordinaten); title = Name
-- der Quelle. Ohne gültigen Fundort fällt das Ziel weg.
function GT:SetWaypointTarget(spot, title)
    if spot and type(spot.map) == "number" and type(spot.x) == "number" and type(spot.y) == "number" then
        target = { map = spot.map, x = spot.x, y = spot.y, title = title }
    else
        target = nil
    end
    self:UpdateWaypointListener()
    return target ~= nil
end

function GT:HasWaypointTarget()
    return target ~= nil and self.db.profile.waypointKey ~= "off"
end

--- Setzt den Wegpunkt zum Ziel. Gibt true zurück, wenn einer gesetzt wurde.
function GT:SetWaypoint()
    if not target then return false end

    local Locations = Glimpse:GetModule("Locations")
    local zone = self.data:GetMapName(target.map) or format(L["Map %d"], target.map)
    local title = target.title and (target.title .. " - " .. zone) or zone
    local coords = Locations:FormatCoords(target.x, target.y, 1)

    if Locations:SetWaypoint(target.map, target.x, target.y, title) then
        Glimpse:Print(format(L["Waypoint set: %s (%s)"], title, coords))
        return true
    end
    Glimpse:Print(format(L["No waypoint possible here: %s (%s)"], title, coords))
    return false
end

-- Tastaturabfrage nur, solange ein Ziel da ist. Die Taste wird weitergegeben, sie sperrt also nichts anderes.
function GT:UpdateWaypointListener()
    if not CreateFrame then return end
    if not listener then
        listener = CreateFrame("Frame")
        listener:SetScript("OnKeyDown", function(_, key)
            if not GT:HasWaypointTarget() then return end
            if PressedKey(key) == GT.db.profile.waypointKey then GT:SetWaypoint() end
        end)
        if GameTooltip and GameTooltip.HookScript then
            GameTooltip:HookScript("OnHide", function() GT:SetWaypointTarget(nil) end)
        end
    end

    local wanted = self:HasWaypointTarget()
    pcall(function()
        listener:EnableKeyboard(wanted)
        if listener.SetPropagateKeyboardInput then listener:SetPropagateKeyboardInput(true) end
    end)
end

--- Hinweiszeile für den Tooltip oder nil
function GT:WaypointHint()
    if not self.db.profile.showWaypointHint or not self:HasWaypointTarget() then return nil end
    local text = format(L["%s: set waypoint"], self:WaypointKeyName())
    if Glimpse:GetModule("Locations"):HasTomTom() then text = text .. " (TomTom)" end
    return "|cff999999" .. text .. "|r"
end
