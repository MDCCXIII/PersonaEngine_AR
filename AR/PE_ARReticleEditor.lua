-- ##################################################
-- AR/PE_ARReticleEditor.lua
-- PersonaEngine AR: Reticle Editor UI
--
-- * Min/max scale per reticle (target/focus/mouseover)
-- * Torso offset per creature type (for target/focus/mouseover)
-- * Global mouseover height offset slider
-- * Coordinates with AR Layout Editor via Ret.SetEditorEnabled
-- ##################################################

local MODULE = "AR Reticle Editor"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Reticles = AR.Reticles or {}
local Ret = AR.Reticles

AR.ReticleEditor = AR.ReticleEditor or {}
local RE = AR.ReticleEditor

------------------------------------------------------
-- Local helpers
------------------------------------------------------

local function GetCreatureType(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end
    return UnitCreatureType(unit) or "UNKNOWN"
end

------------------------------------------------------
-- UI state
------------------------------------------------------

RE.UI = RE.UI or {}
local UI = RE.UI

------------------------------------------------------
-- Frame creation
------------------------------------------------------

local function CreateReticleEditorFrame()
    if UI.frame then
        return
    end

    local f = CreateFrame("Frame", "PE_AR_ReticleEditor", UIParent, "BackdropTemplate")
    f:SetSize(400, 340)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(60)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("PersonaEngine AR — Reticle Editor")

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("Scale & torso offset (per creature type)")

    UI.rows = {}

    local rowY = -40

    local function MakeRow(key)
        local cfg = Ret.GetReticleConfig and Ret.GetReticleConfig(key)
        if not cfg then return end

        local row = {}
        row.key = key

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", f, "TOPLEFT", 10, rowY)
        label:SetText(cfg.display or key)
        row.label = label

        -- Min scale slider
        local minName = "PE_AR_ReticleEditor_" .. key .. "_Min"
        local minSlider = CreateFrame("Slider", minName, f, "OptionsSliderTemplate")
        minSlider:SetMinMaxValues(0.01, 1.00)
        minSlider:SetValueStep(0.01)
        minSlider:SetObeyStepOnDrag(true)
        minSlider:SetOrientation("HORIZONTAL")
        minSlider:SetWidth(160)
        minSlider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)

        local low  = _G[minName .. "Low"]
        local high = _G[minName .. "High"]
        local text = _G[minName .. "Text"]
        if low  then low:SetText("0.01") end
        if high then high:SetText("1.00") end
        if text then text:SetText("Min Scale") end

        row.minSlider = minSlider

        -- Max scale slider
        local maxName = "PE_AR_ReticleEditor_" .. key .. "_Max"
        local maxSlider = CreateFrame("Slider", maxName, f, "OptionsSliderTemplate")
        maxSlider:SetMinMaxValues(0.01, 1.50)
        maxSlider:SetValueStep(0.01)
        maxSlider:SetObeyStepOnDrag(true)
        maxSlider:SetOrientation("HORIZONTAL")
        maxSlider:SetWidth(160)
        maxSlider:SetPoint("TOPLEFT", minSlider, "BOTTOMLEFT", 0, -10)

        local mLow  = _G[maxName .. "Low"]
        local mHigh = _G[maxName .. "High"]
        local mText = _G[maxName .. "Text"]
        if mLow  then mLow:SetText("0.01") end
        if mHigh then mHigh:SetText("1.50") end
        if mText then mText:SetText("Max Scale") end

        row.maxSlider = maxSlider

        UI.rows[key] = row
        rowY = rowY - 60
    end

    MakeRow("target")
    MakeRow("focus")
    MakeRow("mouseover")

    -- Torso offset controls (current target creature type)
    local torsoLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    torsoLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, rowY)
    torsoLabel:SetText("Torso offset (current target creature type)")
    UI.torsoLabel = torsoLabel

    local torsoName = "PE_AR_ReticleEditor_Torso"
    local torsoSlider = CreateFrame("Slider", torsoName, f, "OptionsSliderTemplate")
    torsoSlider:SetMinMaxValues(-800, -100)
    torsoSlider:SetValueStep(1)
    torsoSlider:SetObeyStepOnDrag(true)
    torsoSlider:SetOrientation("HORIZONTAL")
    torsoSlider:SetWidth(260)
    torsoSlider:SetPoint("TOPLEFT", torsoLabel, "BOTTOMLEFT", 0, -6)

    local tLow  = _G[torsoName .. "Low"]
    local tHigh = _G[torsoName .. "High"]
    local tText = _G[torsoName .. "Text"]
    if tLow  then tLow:SetText("-800") end
    if tHigh then tHigh:SetText("-100") end
    if tText then tText:SetText("Target Reticle Torso Offset (px)") end

    UI.torsoSlider = torsoSlider

    local torsoType = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    torsoType:SetPoint("TOPLEFT", torsoSlider, "BOTTOMLEFT", 0, -4)
    torsoType:SetText("No target")
    UI.torsoType = torsoType

    rowY = rowY - 80

    -- Global mouseover offset slider
    local moLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, rowY)
    moLabel:SetText("Mouseover offset (global)")
    UI.moLabel = moLabel

    local moName = "PE_AR_ReticleEditor_MouseoverOffset"
    local moSlider = CreateFrame("Slider", moName, f, "OptionsSliderTemplate")
    moSlider:SetMinMaxValues(-300, 1000)
    moSlider:SetValueStep(1)
    moSlider:SetObeyStepOnDrag(true)
    moSlider:SetOrientation("HORIZONTAL")
    moSlider:SetWidth(260)
    moSlider:SetPoint("TOPLEFT", moLabel, "BOTTOMLEFT", 0, -6)

    local moLow  = _G[moName .. "Low"]
    local moHigh = _G[moName .. "High"]
    local moText = _G[moName .. "Text"]
    if moLow  then moLow:SetText("-300") end
    if moHigh then moHigh:SetText("300") end
    if moText then moText:SetText("Mouseover Offset (px)") end

    UI.moSlider = moSlider

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    UI.frame = f

    --------------------------------------------------
    -- Slider wiring
    --------------------------------------------------

    local function RefreshScaleSliders()
        if not Ret.GetReticleConfig then return end

        for key, row in pairs(UI.rows) do
            local cfg = Ret.GetReticleConfig(key)
            if cfg then
                row.minSlider:SetValue(cfg.minScale or 0.01)
                row.maxSlider:SetValue(cfg.maxScale or 1.00)
            end
        end
    end
    UI.RefreshScaleSliders = RefreshScaleSliders

    for key, row in pairs(UI.rows) do
        row.minSlider:SetScript("OnValueChanged", function(self, val)
            local cfg = Ret.GetReticleConfig and Ret.GetReticleConfig(key)
            local maxScale = cfg and cfg.maxScale or 1.0
            if val > maxScale then
                val = maxScale
                self:SetValue(val)
            end
            if Ret.SetReticleField then
                Ret.SetReticleField(key, "minScale", val)
            end
        end)

        row.maxSlider:SetScript("OnValueChanged", function(self, val)
            local cfg = Ret.GetReticleConfig and Ret.GetReticleConfig(key)
            local minScale = cfg and cfg.minScale or 0.01
            if val < minScale then
                val = minScale
                self:SetValue(val)
            end
            if Ret.SetReticleField then
                Ret.SetReticleField(key, "maxScale", val)
            end
        end)
    end

    local function RefreshTorsoControls()
        if not Ret.GetTorsoOffset then return end

        local unit = "target"
        local creatureType = GetCreatureType(unit)
        if not creatureType then
            UI.torsoType:SetText("No target")
            UI.torsoSlider:SetEnabled(false)
            UI.torsoSlider:SetValue(0)
            return
        end

        local current = Ret.GetTorsoOffset("target", unit) or 0
        UI.torsoType:SetText("Creature type: " .. creatureType)
        UI.torsoSlider:SetEnabled(true)
        UI.torsoSlider:SetValue(current)
    end
    UI.RefreshTorsoControls = RefreshTorsoControls

    torsoSlider:SetScript("OnValueChanged", function(self, val)
        if not Ret.SetTorsoOffset then return end
        local unit = "target"
        local creatureType = GetCreatureType(unit)
        if not creatureType then
            return
        end
        Ret.SetTorsoOffset("target", creatureType, val)
    end)

    local function RefreshMouseoverControls()
        if not Ret.GetMouseoverOffset then return end
        UI.moSlider:SetValue(Ret.GetMouseoverOffset() or 0)
    end
    UI.RefreshMouseoverControls = RefreshMouseoverControls

    moSlider:SetScript("OnValueChanged", function(self, val)
        if Ret.SetMouseoverOffset then
            Ret.SetMouseoverOffset(val)
        end
    end)

    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" and f:IsShown() then
            if UI.RefreshTorsoControls then
                UI.RefreshTorsoControls()
            end
        end
    end)

    f:SetScript("OnShow", function()
        if UI.RefreshScaleSliders then UI.RefreshScaleSliders() end
        if UI.RefreshTorsoControls then UI.RefreshTorsoControls() end
        if UI.RefreshMouseoverControls then UI.RefreshMouseoverControls() end
    end)
end

------------------------------------------------------
-- Public API
------------------------------------------------------

function RE.SetEnabled(flag)
    flag = not not flag
    CreateReticleEditorFrame()

    if flag then
        UI.frame:Show()
        if UI.RefreshScaleSliders then UI.RefreshScaleSliders() end
        if UI.RefreshTorsoControls then UI.RefreshTorsoControls() end
        if UI.RefreshMouseoverControls then UI.RefreshMouseoverControls() end
    else
        UI.frame:Hide()
    end
end

------------------------------------------------------
-- Slash command (optional manual toggle)
------------------------------------------------------

SLASH_PE_ARRETICLE1 = "/pearreticle"
SlashCmdList["PE_ARRETICLE"] = function()
    CreateReticleEditorFrame()
    if UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.frame:Show()
        if UI.RefreshScaleSliders then UI.RefreshScaleSliders() end
        if UI.RefreshTorsoControls then UI.RefreshTorsoControls() end
        if UI.RefreshMouseoverControls then UI.RefreshMouseoverControls() end
    end
end

------------------------------------------------------
-- Module registration (optional, for diagnostics)
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Reticle Editor", {
    name  = "AR Reticle Editor",
    class = "AR HUD",
})
