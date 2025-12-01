-- ##################################################
-- AR/PE_ARReticleEditor.lua
-- PersonaEngine AR: Simple in-game editor for
--   * Reticle distances + scale
--   * Torso offsets per creature type
--   * Global mouseover offset
--   * Theo front angle + arrow scales
--
-- UI is intentionally lightweight / nerdy.
-- ##################################################

local MODULE = "AR Reticle Editor"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR  = PE.AR
local Ret = AR.Reticles

if not Ret then
    return
end

AR.ReticleEditor      = AR.ReticleEditor or {}
local Editor         = AR.ReticleEditor
Editor.enabled       = Editor.enabled or false
Editor.currentType   = Editor.currentType or "Humanoid"
Editor.currentRetKey = Editor.currentRetKey or "target"

local CreateFrame = _G.CreateFrame
local UIParent    = _G.UIParent
local UnitExists  = _G.UnitExists
local UnitCreatureType = _G.UnitCreatureType

------------------------------------------------------
-- Simple slider helper
------------------------------------------------------

local function CreateLabeledSlider(parent, name, text, minVal, maxVal, step)
    local f = CreateFrame("Frame", name, parent)
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(parent:GetFrameLevel() + 1)
    f:SetSize(220, 40)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text or name)

    local slider = CreateFrame("Slider", name .. "Slider", f, "OptionsSliderTemplate")
    slider:SetFrameStrata("LOW")
    slider:SetFrameLevel(f:GetFrameLevel() + 1)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    slider:SetWidth(180)
    slider:SetHeight(14)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    local low = _G[slider:GetName() .. "Low"]
    local hi  = _G[slider:GetName() .. "High"]
    local txt = _G[slider:GetName() .. "Text"]
    if low then low:SetText(tostring(minVal)) end
    if hi  then hi:SetText(tostring(maxVal))  end
    if txt then txt:SetText("") end

    f.label  = label
    f.slider = slider

    return f
end

------------------------------------------------------
-- Torso target drag widget (for visual offset tuning)
------------------------------------------------------

local torsoTargetFrame
local torsoTargetTexture

local function EnsureTorsoTarget()
    if torsoTargetFrame then
        return torsoTargetFrame
    end

    torsoTargetFrame = CreateFrame("Frame", "PE_AR_TorsoTarget", UIParent)
    torsoTargetFrame:SetFrameStrata("LOW")
    torsoTargetFrame:SetFrameLevel(13)
    torsoTargetFrame:SetSize(32, 32)
    torsoTargetFrame:EnableMouse(true)
    torsoTargetFrame:SetMovable(true)
    torsoTargetFrame:Hide()

    torsoTargetTexture = torsoTargetFrame:CreateTexture(nil, "OVERLAY")
    torsoTargetTexture:SetAllPoints()
    torsoTargetTexture:SetTexture("Interface\\CURSOR\\Crosshairs")
    torsoTargetTexture:SetVertexColor(0.2, 1.0, 0.7, 0.9)

    torsoTargetFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)

    torsoTargetFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:StopMovingOrSizing()

            local _, _, _, _, y = self:GetPoint(1)
            y = y or 0

            local creatureType = Editor.currentType or "Humanoid"
            Ret.SetTorsoOffset(creatureType, y)
        end
    end)

    return torsoTargetFrame
end

local function SetTorsoTargetOffset(offsetY)
    local frame = EnsureTorsoTarget()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, offsetY or 0)
end

------------------------------------------------------
-- Main editor frame
------------------------------------------------------

Editor.frame = Editor.frame or nil

local function EnsureEditorFrame()
    if Editor.frame then
        return Editor.frame
    end

    local f = CreateFrame("Frame", "PE_AR_ReticleEditor", UIParent, "BackdropTemplate")
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(10)
    f:SetSize(320, 700)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetBackdropBorderColor(0.2, 1.0, 0.7, 0.9)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    Editor.frame = f

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("AR Reticle Editor")
    Editor.title = title

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetWidth(260)
    sub:SetJustifyH("LEFT")
    sub:SetText("Tune reticles, torso offsets, mouseover offset, and Theo front angle.")
    Editor.subtitle = sub

    local scroll = CreateFrame("Frame", "PE_AR_ReticleEditorScroll", f)
    scroll:SetFrameStrata("LOW")
    scroll:SetFrameLevel(11)
    scroll:SetSize(300, 320)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -60)
    Editor.scroll = scroll

    local y = 0

    local function AddControl(frame)
        frame:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, y)
        y = y - (frame:GetHeight() + 8)
    end

    -- RETICLE: near / far / minScale / maxScale
    Editor.sliders = Editor.sliders or {}

    local nearS = CreateLabeledSlider(scroll, "PE_AR_RetNearSlider", "Reticle Near Distance", 2, 30, 1)
    AddControl(nearS)
    Editor.sliders.near = nearS

    local farS = CreateLabeledSlider(scroll, "PE_AR_RetFarSlider", "Reticle Far Distance", 10, 60, 1)
    AddControl(farS)
    Editor.sliders.far = farS

    local minS = CreateLabeledSlider(scroll, "PE_AR_RetMinScaleSlider", "Reticle Min Scale", 5, 90, 1)
    AddControl(minS)
    Editor.sliders.minScale = minS

    local maxS = CreateLabeledSlider(scroll, "PE_AR_RetMaxScaleSlider", "Reticle Max Scale", 10, 150, 1)
    AddControl(maxS)
    Editor.sliders.maxScale = maxS

    local offXS = CreateLabeledSlider(scroll, "PE_AR_RetOffsetXSlider", "Reticle Offset X", -300, 300, 1)
    AddControl(offXS)
    Editor.sliders.offsetX = offXS

    local offYS = CreateLabeledSlider(scroll, "PE_AR_RetOffsetYSlider", "Reticle Offset Y", -500, 500, 1)
    AddControl(offYS)
    Editor.sliders.offsetY = offYS

    -- TORSO OFFSET per creature type (drag gizmo + slider)
    local torsoLabel = scroll:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    torsoLabel:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, y)
    torsoLabel:SetText("Torso Offset (per creature type)")
    y = y - 18
    Editor.torsoLabel = torsoLabel

    local torsoSlider = CreateLabeledSlider(scroll, "PE_AR_TorsoOffsetSlider", "Torso Offset (visual)", -600, 200, 1)
    AddControl(torsoSlider)
    Editor.torsoSlider = torsoSlider

    -- MOUSEOVER OFFSET (global)
    local moOffsetSlider = CreateLabeledSlider(scroll, "PE_AR_MouseoverOffsetSlider", "Mouseover Offset Y (global)", -500, 500, 1)
    AddControl(moOffsetSlider)
    Editor.mouseoverOffsetSlider = moOffsetSlider

    -- THEO FRONT ANGLE + SCALES
    local theoLabel = scroll:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    theoLabel:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, y)
    theoLabel:SetText("Theo Configuration")
    y = y - 18
    Editor.theoLabel = theoLabel

    local theoAngle = CreateLabeledSlider(scroll, "PE_AR_TheoAngleSlider", "Theo Front Angle (deg)", 20, 120, 1)
    AddControl(theoAngle)
    Editor.theoAngleSlider = theoAngle

    local theoTargetScale = CreateLabeledSlider(scroll, "PE_AR_TheoTargetScaleSlider", "Theo Target Arrow Scale", 30, 200, 1)
    AddControl(theoTargetScale)
    Editor.theoTargetScale = theoTargetScale

    local theoFocusScale = CreateLabeledSlider(scroll, "PE_AR_TheoFocusScaleSlider", "Theo Focus Arrow Scale", 30, 200, 1)
    AddControl(theoFocusScale)
    Editor.theoFocusScale = theoFocusScale

    local closeBtn = CreateFrame("Button", "PE_AR_ReticleEditorClose", f, "UIPanelButtonTemplate")
    closeBtn:SetFrameStrata("LOW")
    closeBtn:SetFrameLevel(12)
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        Editor.SetEnabled(false)
    end)
    Editor.closeBtn = closeBtn

    return f
end

------------------------------------------------------
-- Sync sliders ↔ DB
------------------------------------------------------

local function SyncReticleSliders()
    local cfg = Ret.GetReticleConfig(Editor.currentRetKey)
    if not cfg then
        return
    end

    local s = Editor.sliders
    if not s then
        return
    end

    s.near.slider:SetValue(cfg.near or 5)
    s.far.slider:SetValue(cfg.far or 45)
    s.minScale.slider:SetValue((cfg.minScale or 0.05) * 100)
    s.maxScale.slider:SetValue((cfg.maxScale or 0.35) * 100)
    s.offsetX.slider:SetValue(cfg.offsetX or 0)
    s.offsetY.slider:SetValue(cfg.offsetY or 0)
end

local function SyncTorsoSlider()
    local ct = Editor.currentType or "Humanoid"
    local off = Ret.GetTorsoOffset("target", ct) or 0
    local s   = Editor.torsoSlider and Editor.torsoSlider.slider
    if not s then
        return
    end
    s:SetValue(off)
    SetTorsoTargetOffset(off)
end

local function SyncMouseoverOffsetSlider()
    local s = Editor.mouseoverOffsetSlider and Editor.mouseoverOffsetSlider.slider
    if not s then
        return
    end
    local off = Ret.GetMouseoverOffset() or 0
    s:SetValue(off)
end

local function SyncTheoSliders()
    local sAngle   = Editor.theoAngleSlider and Editor.theoAngleSlider.slider
    local sTarget  = Editor.theoTargetScale and Editor.theoTargetScale.slider
    local sFocus   = Editor.theoFocusScale and Editor.theoFocusScale.slider

    if sAngle then
        sAngle:SetValue(Ret.GetTheoFrontAngleDeg() or 60)
    end

    if sTarget then
        sTarget:SetValue((Ret.GetTheoArrowScale("target") or 1.0) * 100)
    end

    if sFocus then
        sFocus:SetValue((Ret.GetTheoArrowScale("focus") or 1.0) * 100)
    end
end

local function SyncAllSliders()
    SyncReticleSliders()
    SyncTorsoSlider()
    SyncMouseoverOffsetSlider()
    SyncTheoSliders()
end

------------------------------------------------------
-- Slider change handlers
------------------------------------------------------

local function HookSliderCallbacks()
    local s = Editor.sliders
    if not s then
        return
    end

    s.near.slider:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField(Editor.currentRetKey, "near", val)
    end)

    s.far.slider:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField(Editor.currentRetKey, "far", val)
    end)

    s.minScale.slider:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField(Editor.currentRetKey, "minScale", val / 100)
    end)

    s.maxScale.slider:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField(Editor.currentRetKey, "maxScale", val / 100)
    end)

    s.offsetX.slider:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField(Editor.currentRetKey, "offsetX", val)
    end)

    s.offsetY.slider:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField(Editor.currentRetKey, "offsetY", val)
    end)

    if Editor.torsoSlider and Editor.torsoSlider.slider then
        Editor.torsoSlider.slider:SetScript("OnValueChanged", function(self, val)
            Ret.SetTorsoOffset(Editor.currentType or "Humanoid", val)
            SetTorsoTargetOffset(val)
        end)
    end

    if Editor.mouseoverOffsetSlider and Editor.mouseoverOffsetSlider.slider then
        Editor.mouseoverOffsetSlider.slider:SetScript("OnValueChanged", function(self, val)
            Ret.SetMouseoverOffset(val)
        end)
    end

    if Editor.theoAngleSlider and Editor.theoAngleSlider.slider then
        Editor.theoAngleSlider.slider:SetScript("OnValueChanged", function(self, val)
            Ret.SetTheoFrontAngleDeg(val)
        end)
    end

    if Editor.theoTargetScale and Editor.theoTargetScale.slider then
        Editor.theoTargetScale.slider:SetScript("OnValueChanged", function(self, val)
            Ret.SetTheoArrowScale("target", val / 100)
        end)
    end

    if Editor.theoFocusScale and Editor.theoFocusScale.slider then
        Editor.theoFocusScale.slider:SetScript("OnValueChanged", function(self, val)
            Ret.SetTheoArrowScale("focus", val / 100)
        end)
    end
end

------------------------------------------------------
-- Creature type detection helper
------------------------------------------------------

local function DetectCurrentCreatureType()
    if UnitExists("target") then
        return UnitCreatureType("target") or "Humanoid"
    end
    if UnitExists("focus") then
        return UnitCreatureType("focus") or "Humanoid"
    end
    return Editor.currentType or "Humanoid"
end

------------------------------------------------------
-- Public API
------------------------------------------------------

function Editor.SetEnabled(flag)
    flag = not not flag
    Editor.enabled = flag

    local frame = EnsureEditorFrame()
    if flag then
        Editor.currentType   = DetectCurrentCreatureType()
        Editor.currentRetKey = Editor.currentRetKey or "target"

        SyncAllSliders()
        HookSliderCallbacks()

        frame:Show()
        EnsureTorsoTarget()
        torsoTargetFrame:Show()
    else
        frame:Hide()
        if torsoTargetFrame then
            torsoTargetFrame:Hide()
        end
    end

    if Ret.SetEditorEnabled then
        Ret.SetEditorEnabled(flag)
    end
end

function Editor.Toggle()
    Editor.SetEnabled(not Editor.enabled)
end

------------------------------------------------------
-- Events
------------------------------------------------------

local driver

local function OnEvent(self, event, unit)
    if not Editor.enabled then
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        Editor.currentType = DetectCurrentCreatureType()
        SyncTorsoSlider()
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Editor.currentType = DetectCurrentCreatureType()
        SyncTorsoSlider()
    end
end

local function InitEvents()
    if driver then
        return
    end

    driver = CreateFrame("Frame", "PE_AR_ReticleEditorDriver", UIParent)
    driver:SetFrameStrata("LOW")
    driver:SetFrameLevel(0)
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
    driver:SetScript("OnEvent", OnEvent)
end

------------------------------------------------------
-- Slash command hookup
------------------------------------------------------

SLASH_PE_ARRETEDITOR1 = "/pearreticle"
SlashCmdList["PE_ARRETEDITOR"] = function(msg)
    InitEvents()
    Editor.Toggle()
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Reticle Editor", {
    name  = "AR Reticle Editor",
    class = "AR HUD",
})

InitEvents()
