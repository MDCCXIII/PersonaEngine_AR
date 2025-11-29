-- ##################################################
-- AR/PE_ARReticleEditor.lua
-- PersonaEngine AR: Reticle + Theo editor
--
-- Exposes:
--   * Target / Focus min/max scale, near/far, offsets
--   * Shared torso offset per creature type
--   * Global mouseover offset
--   * Theo front cone angle
--   * Theo arrow scales for target/focus
--
-- Slash:
--   /pearreticle  → toggle the editor
-- ##################################################

local MODULE = "AR Reticle Editor"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

local Ret = AR.Reticles
if not Ret then
    return
end

local UnitExists       = _G.UnitExists
local UnitCreatureType = _G.UnitCreatureType
local UIParent         = _G.UIParent

------------------------------------------------------
-- Editor SavedVariables (position)
------------------------------------------------------

local function GetEditorDB()
    _G.PersonaEngineAR_DB = _G.PersonaEngineAR_DB or {}
    local root = _G.PersonaEngineAR_DB

    root.reticleEditor = root.reticleEditor or {}
    return root.reticleEditor
end

local function LoadEditorPosition(frame)
    local db = GetEditorDB()
    if not db.point then
        return false
    end

    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
    return true
end

local function SaveEditorPosition(frame)
    local db = GetEditorDB()
    local point, relativeTo, relPoint, x, y = frame:GetPoint(1)
    if not point then
        return
    end

    db.point    = point
    db.relPoint = relPoint or point
    db.x        = x or 0
    db.y        = y or 0
end

------------------------------------------------------
-- Editor frame
------------------------------------------------------

Ret.EditorUI = Ret.EditorUI or {}
local UI = Ret.EditorUI

local function CreateNamedSlider(baseName, parent, labelText, minVal, maxVal, step)
    local slider = CreateFrame("Slider", baseName, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    local nameFS   = _G[baseName .. "Text"]
    local lowFS    = _G[baseName .. "Low"]
    local highFS   = _G[baseName .. "High"]

    if nameFS then nameFS:SetText(labelText or baseName) end
    if lowFS  then lowFS:SetText(tostring(minVal)) end
    if highFS then highFS:SetText(tostring(maxVal)) end

    slider.labelFS = nameFS

    return slider
end

local function CreateEditorFrame()
    if UI.frame then
        return
    end

    local f = CreateFrame("Frame", "PE_AR_ReticleEditor", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(420, 600)

    -- Try to restore saved position; fall back to a default if none.
    if not LoadEditorPosition(f) then
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end

    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(60)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveEditorPosition(self)
    end)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -6)
    f.title:SetText("PersonaEngine AR — Reticles / Theo")

    local y = -40

    --------------------------------------------------
    -- Target / Focus scale & distance
    --------------------------------------------------

    local sTargetMax = CreateNamedSlider("PE_AR_TargetMaxScale", f, "Target Max Scale", 0.10, 1.0, 0.01)
    sTargetMax:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    local sTargetMin = CreateNamedSlider("PE_AR_TargetMinScale", f, "Target Min Scale", 0.05, 1.0, 0.01)
    sTargetMin:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    local sTargetNear = CreateNamedSlider("PE_AR_TargetNear", f, "Target Near Distance", 0, 20, 0.5)
    sTargetNear:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    local sTargetFar = CreateNamedSlider("PE_AR_TargetFar", f, "Target Far Distance", 5, 80, 0.5)
    sTargetFar:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    --------------------------------------------------
    -- Mouseover offset
    --------------------------------------------------

    local sMouseoverOffset = CreateNamedSlider("PE_AR_MouseoverOffset", f, "Mouseover Height Offset", -200, 200, 1)
    sMouseoverOffset:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    --------------------------------------------------
    -- Theo front angle + arrow scales
    --------------------------------------------------

    local sTheoAngle = CreateNamedSlider("PE_AR_TheoAngle", f, "Theo Front Cone Angle (deg)", 10, 120, 1)
    sTheoAngle:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    local sTheoTargetScale = CreateNamedSlider("PE_AR_TheoTargetScale", f, "Theo Target Arrow Scale", 0.3, 2.0, 0.05)
    sTheoTargetScale:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    local sTheoFocusScale = CreateNamedSlider("PE_AR_TheoFocusScale", f, "Theo Focus Arrow Scale", 0.3, 2.0, 0.05)
    sTheoFocusScale:SetPoint("TOPLEFT", 16, y)
    y = y - 50

    --------------------------------------------------
    -- Torso offset (shared target/focus)
    --------------------------------------------------

    local sTorso = CreateNamedSlider("PE_AR_TorsoOffset", f, "Torso Offset (shared)", -600, 0, 5)
    sTorso:SetPoint("TOPLEFT", 16, y)
    local torsoTypeFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    torsoTypeFS:SetPoint("TOPLEFT", sTorso, "BOTTOMLEFT", 4, -2)
    torsoTypeFS:SetText("Creature type: Humanoid")

    UI.torsoTypeFS = torsoTypeFS
    UI.currentCreatureType = "Humanoid"

    y = y - 70

    --------------------------------------------------
    -- Wiring
    --------------------------------------------------

    UI.frame             = f
    UI.sTargetMaxScale   = sTargetMax
    UI.sTargetMinScale   = sTargetMin
    UI.sTargetNear       = sTargetNear
    UI.sTargetFar        = sTargetFar
    UI.sMouseoverOffset  = sMouseoverOffset
    UI.sTheoAngle        = sTheoAngle
    UI.sTheoTargetScale  = sTheoTargetScale
    UI.sTheoFocusScale   = sTheoFocusScale
    UI.sTorso            = sTorso

    local function Refresh()
        local tCfg = Ret.GetReticleConfig("target")
        if tCfg then
            sTargetMax:SetValue(tCfg.maxScale or 0.35)
            sTargetMin:SetValue(tCfg.minScale or 0.05)
            sTargetNear:SetValue(tCfg.near or 5)
            sTargetFar:SetValue(tCfg.far or 45)
        end

        sMouseoverOffset:SetValue(Ret.GetMouseoverOffset() or 0)

        sTheoAngle:SetValue(Ret.GetTheoFrontAngleDeg() or 60)
        sTheoTargetScale:SetValue(Ret.GetTheoArrowScale("target") or 1.0)
        sTheoFocusScale:SetValue(Ret.GetTheoArrowScale("focus") or 1.0)

        -- Torso offset: use the current target/focus creature type if available, else Humanoid.
        local sampleType = "Humanoid"
        if UnitExists("target") then
            sampleType = UnitCreatureType("target") or "Humanoid"
        elseif UnitExists("focus") then
            sampleType = UnitCreatureType("focus") or "Humanoid"
        end

        UI.currentCreatureType = sampleType

        local torso = Ret.GetTorsoOffset("target", sampleType) or 0
        sTorso:SetValue(torso)

        if UI.torsoTypeFS then
            UI.torsoTypeFS:SetFormattedText("Creature type: %s", sampleType)
        end
    end

    f.Refresh = Refresh

    -- Keep torso-offset creature type in sync with actual target/focus.
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_FOCUS_CHANGED")
    f:SetScript("OnEvent", function(self, event)
        if self:IsShown() and self.Refresh then
            self:Refresh()
        end
    end)

    -- Callbacks
    sTargetMax:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField("target", "maxScale", val)
    end)
    sTargetMin:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField("target", "minScale", val)
    end)
    sTargetNear:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField("target", "near", val)
    end)
    sTargetFar:SetScript("OnValueChanged", function(self, val)
        Ret.SetReticleField("target", "far", val)
    end)

    sMouseoverOffset:SetScript("OnValueChanged", function(self, val)
        Ret.SetMouseoverOffset(val)
    end)

    sTheoAngle:SetScript("OnValueChanged", function(self, val)
        Ret.SetTheoFrontAngleDeg(val)
    end)

    sTheoTargetScale:SetScript("OnValueChanged", function(self, val)
        Ret.SetTheoArrowScale("target", val)
    end)

    sTheoFocusScale:SetScript("OnValueChanged", function(self, val)
        Ret.SetTheoArrowScale("focus", val)
    end)

    sTorso:SetScript("OnValueChanged", function(self, val)
        local creatureType = UI.currentCreatureType or "Humanoid"
        Ret.SetTorsoOffset(creatureType, val)
    end)

    Refresh()
end

------------------------------------------------------
-- Public API used by Reticles + slash command
------------------------------------------------------

function UI.SetEnabled(flag)
    CreateEditorFrame()
    if flag then
        UI.frame:Show()
        if UI.frame.Refresh then
            UI.frame:Refresh()
        end
    else
        UI.frame:Hide()
    end
end

-- Called from AR/PE_ARReticles.lua shim.
Ret.EditorUI.SetEnabled = UI.SetEnabled

SLASH_PE_ARRETICLE1 = "/pearreticle"
SlashCmdList["PE_ARRETICLE"] = function()
    CreateEditorFrame()
    UI.SetEnabled(not UI.frame:IsShown())
end

PE.LogInit(MODULE)
PE.RegisterModule("AR Reticle Editor", {
    name  = "AR Reticle Editor",
    class = "AR HUD",
})
