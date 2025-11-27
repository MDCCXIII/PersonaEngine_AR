-- ##################################################
-- AR/PE_ARLayoutEditor.lua
-- PersonaEngine AR: simple in-game layout editor
-- Lets you drag registered AR frames and saves
-- their positions into the layout DB.
-- ##################################################

local MODULE = "AR Layout Editor"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Layout = AR.Layout or {}
local Layout = AR.Layout
if not Layout then
    return
end

AR.LayoutEditor = AR.LayoutEditor or {}
local Editor = AR.LayoutEditor

------------------------------------------------------
-- State
------------------------------------------------------

Editor.enabled  = false
Editor.handles  = Editor.handles or {}
Editor.original = Editor.original or {}  -- per-frame original scripts/flags

------------------------------------------------------
-- Internal helpers
------------------------------------------------------

local function CreateHandle(regionName, frame)
    if not frame or frame:IsForbidden() then
        return nil
    end

    local handle = Editor.handles[frame]
    if not handle then
        handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        Editor.handles[frame] = handle

        handle:SetAllPoints(frame)
        handle:SetFrameStrata("FULLSCREEN_DIALOG")
        handle:SetFrameLevel(frame:GetFrameLevel() + 20)

        handle:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
        })
        handle:SetBackdropBorderColor(0.2, 1.0, 0.7, 0.9)

        handle.label = handle:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
        handle.label:SetPoint("TOPLEFT", handle, "TOPLEFT", 4, -4)
        handle.label:SetText(regionName or "AR Region")

        handle:Hide()
    end

    handle.label:SetText(regionName or "AR Region")
    return handle
end

local function HookFrameForEdit(regionName, frame)
    if not frame or frame:IsForbidden() then
        return
    end

    if Editor.original[frame] then
        return -- already hooked
    end

    local info = {
        movable      = frame:IsMovable(),
        mouseEnabled = frame:IsMouseEnabled(),
        dragStart    = frame:GetScript("OnDragStart"),
        dragStop     = frame:GetScript("OnDragStop"),
    }
    Editor.original[frame] = info

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(f)
        f:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        Layout.SaveFromFrame(regionName, f)
    end)

    local handle = CreateHandle(regionName, frame)
    if handle then
        handle:Show()
    end
end

local function UnhookFrame(frame)
    if not frame or frame:IsForbidden() then
        return
    end

    local info = Editor.original[frame]
    if not info then
        return
    end

    frame:SetMovable(info.movable or false)
    frame:EnableMouse(info.mouseEnabled or false)
    frame:SetScript("OnDragStart", info.dragStart)
    frame:SetScript("OnDragStop", info.dragStop)

    local handle = Editor.handles[frame]
    if handle then
        handle:Hide()
    end

    Editor.original[frame] = nil
end

local function ApplyEditMode()
    local registered = Layout.GetRegistered and Layout.GetRegistered()
    if not registered then
        return
    end

    if Editor.enabled then
        for regionName, frame in pairs(registered) do
            HookFrameForEdit(regionName, frame)
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF98[PersonaEngine AR]|r Layout edit |cff20ff70ENABLED|r. Drag frames to reposition.")
    else
        for _, frame in pairs(registered) do
            UnhookFrame(frame)
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF98[PersonaEngine AR]|r Layout edit |cffff4040DISABLED|r.")
    end
end

------------------------------------------------------
-- Public API
------------------------------------------------------

function Editor.SetEnabled(flag)
    flag = not not flag
    if flag == Editor.enabled then
        return
    end

    Editor.enabled = flag
    ApplyEditMode()
end

function Editor.Toggle()
    Editor.SetEnabled(not Editor.enabled)
end

------------------------------------------------------
-- Slash command
------------------------------------------------------

SLASH_PE_ARLAYOUT1 = "/pearlayout"
SlashCmdList["PE_ARLAYOUT"] = function(msg)
    Editor.Toggle()
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Layout Editor", {
    name  = "AR Layout Editor",
    class = "AR HUD",
})
