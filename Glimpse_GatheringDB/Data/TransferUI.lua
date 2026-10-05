local ADDON_NAME = ...
local Glimpse = LibStub("AceAddon-3.0"):GetAddon("Glimpse")
local DB = Glimpse:GetModule("GatheringDB")
local L = DB.L

-- Fenster zum Exportieren und Importieren (Logik in Data/Transfer.lua). Ein einziges Fenster,
-- ein erneuter Aufruf ersetzt das offene.

local AceGUI = LibStub("AceGUI-3.0")

local window

local function CloseWindow()
    if window then
        AceGUI:Release(window)
        window = nil
    end
end

-- Fehlerschlüssel von DB:ImportData -> Text
local function ErrorText(key)
    local texts = {
        empty = L["Nothing to import. Paste the exported text first."],
        tooLarge = L["The text is too long."],
        notExport = L["This is not an export of Glimpse: GatheringDB."],
        formatNewer = L["The export was made by a newer version of the addon. Please update the addon."],
        unsupported = L["The export is compressed, but the compression library is missing."],
        damaged = L["The text is damaged or incomplete. Was it copied completely?"],
        dataNewer = L["The data comes from a newer version of the addon. Please update the addon."],
        duplicate = L["This export has already been imported."],
    }
    return texts[key] or tostring(key)
end

local function SummaryText(info)
    local text = format(L["Imported: %d gathering nodes, %d creatures."], info.nodes, info.npcs)
    if info.migrated then text = text .. " " .. format(L["Data converted from version %d."], info.version) end
    if info.removed > 0 then text = text .. " " .. format(L["Removed entries: %d."], info.removed) end
    return text
end

local function RunImport(text, mode, edit)
    local ok, result = DB:ImportData(text, mode)
    if ok then
        Glimpse:Print(SummaryText(result))
        if window then window:SetStatusText(SummaryText(result)) end
        if edit then edit:SetText("") end
        LibStub("AceConfigRegistry-3.0"):NotifyChange(Glimpse.name .. "_" .. ADDON_NAME)
    else
        Glimpse:Print(ErrorText(result))
        if window then window:SetStatusText(ErrorText(result)) end
    end
end

StaticPopupDialogs["GLIMPSE_GATHERINGDB_REPLACE"] = {
    text = L["Replace ALL gathering data with the imported data? This cannot be undone."],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) RunImport(data.text, "replace", data.edit) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Open(title)
    CloseWindow()

    window = AceGUI:Create("Frame")
    window:SetTitle(title)
    window:SetWidth(580)
    window:SetHeight(440)
    window:SetLayout("List")
    window:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        if window == widget then window = nil end
    end)
    return window
end

local function AddLabel(parent, text)
    local label = AceGUI:Create("Label")
    label:SetText(text)
    label:SetFullWidth(true)
    parent:AddChild(label)
end

local function AddEditBox(parent, caption)
    local edit = AceGUI:Create("MultiLineEditBox")
    edit:SetLabel(caption)
    edit:SetFullWidth(true)
    edit:SetNumLines(14)
    edit:DisableButton(true)
    parent:AddChild(edit)
    return edit
end

--- Zeigt den Exporttext in einem Fenster zum Kopieren (Strg+C).
function DB:ShowExport()
    local text, info = self:ExportData()

    local frame = Open(L["Export gathering data"])
    frame:SetStatusText(format(L["%d gathering nodes, %d creatures, %d characters"], info.nodes, info.npcs, info.chars))
    AddLabel(frame, L["Select the text (Ctrl+A), copy it (Ctrl+C) and paste it into the import window on the other account or computer."])

    local edit = AddEditBox(frame, "")
    edit:SetText(text)
    -- Markieren erst, wenn das Fenster steht
    C_Timer.After(0.1, function()
        if window == frame and edit.editBox then
            edit.editBox:HighlightText()
            edit:SetFocus()
        end
    end)
end

--- Zeigt das Fenster zum Einfügen eines Exporttexts.
function DB:ShowImport()
    local frame = Open(L["Import gathering data"])
    AddLabel(frame, L["Paste the exported text here. Merge adds the numbers to your data, Replace deletes your data first. Older data is converted automatically."])

    local edit = AddEditBox(frame, "")

    local group = AceGUI:Create("SimpleGroup")
    group:SetFullWidth(true)
    group:SetLayout("Flow")
    frame:AddChild(group)

    local merge = AceGUI:Create("Button")
    merge:SetText(L["Merge"])
    merge:SetWidth(160)
    merge:SetCallback("OnClick", function() RunImport(edit:GetText(), "merge", edit) end)
    group:AddChild(merge)

    local replace = AceGUI:Create("Button")
    replace:SetText(L["Replace"])
    replace:SetWidth(160)
    replace:SetCallback("OnClick", function()
        StaticPopup_Show("GLIMPSE_GATHERINGDB_REPLACE", nil, nil, { text = edit:GetText(), edit = edit })
    end)
    group:AddChild(replace)
end
