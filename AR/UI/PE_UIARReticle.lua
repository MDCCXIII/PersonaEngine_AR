-- ##################################################
-- PE_UIARReticle.lua
-- PersonaEngine AR - center-screen reticle overlay
-- ##################################################

local MODULE = "UI_ARReticle"
local PE     = _G.PE

if not PE or type(PE) ~= "table" then
    print("|cffff0000[PersonaEngine:AR] ERROR: PE table missing in " .. MODULE .. "|r")
    return
end

PE.AR = PE.AR or {}
local AR  = PE.AR

AR.Reticle = AR.Reticle or {}
local RT   = AR.Reticle

local frame
local enabled = false

local function HUDActive()
    return AR and AR.IsEnabled and AR.IsEnabled() and AR.visionEnabled
end

local function EnsureFrame()
    if frame then return frame end

    local parent = AR.HUD and AR.HUD.Regions and AR.HUD.Regions.CENTER_RETICLE or UIParent
    frame = CreateFrame("Frame", "PE_ARHUD_Reticle", parent)
    frame:SetIgnoreParentAlpha(true)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(80)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- Simple crosshair: two thin lines
    local h = frame:CreateTexture(nil, "OVERLAY")
    h:SetColorTexture(0, 1, 1, 0.7)
    h:SetHeight(2)
    h:SetWidth(120)
    h:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local v = frame:CreateTexture(nil, "OVERLAY")
    v:SetColorTexture(0, 1, 1, 0.7)
    v:SetWidth(2)
    v:SetHeight(120)
    v:SetPoint("CENTER", frame, "CENTER", 0, 0)

    return frame
end

function RT.Init()
    EnsureFrame()
end

function RT.SetEnabled(flag)
    enabled = not not flag
    RT.UpdateVisibility()
end

function RT.UpdateVisibility()
    if not frame then
        EnsureFrame()
    end

    if enabled and HUDActive() then
        frame:Show()
    else
        frame:Hide()
    end
end

----------------------------------------------------
-- Module registration
----------------------------------------------------

if PE.LogInit then
    PE.LogInit(MODULE)
end

if PE.RegisterModule then
    PE.RegisterModule("AR Reticle", {
        name  = "AR HUD Reticle",
        class = "AR HUD",
    })
end
