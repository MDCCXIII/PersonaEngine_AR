-- ##################################################
-- AR/UI/PE_UIARCardinalHelper.lua
-- PersonaEngine AR: Cardinals Helper sigil
--
-- Shows a floating N/E/S/W graphic only while the
-- Tricked-Out Thinking Cap buff is active.
--
-- - Position is managed by AR Layout ("/pearlayout").
-- - Draggable + mousewheel-resize only in layout mode.
-- - Click-through in normal gameplay.
-- ##################################################

local MODULE = "AR Cardinal Helper"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.CardinalHelper = AR.CardinalHelper or {}
local Helper = AR.CardinalHelper

------------------------------------------------------
-- Layout access (lazy)
------------------------------------------------------

local function GetLayout()
    return AR and AR.Layout
end

------------------------------------------------------
-- Config
------------------------------------------------------

-- Path to your .tga in the addon media folder
local ICON_TEXTURE = "Interface\\AddOns\\PersonaEngine_AR\\media\\Cardinals-Helpers.tga"

-- Buff names that should turn this on
local CAP_BUFF_NAMES = {
    "Tricked-Out Thinking Cap",
    "Tricked Out Thinking Cap", -- safety for name variants
}

------------------------------------------------------
-- Utilities
------------------------------------------------------

local function IsAREnabled()
    if AR.IsEnabled and type(AR.IsEnabled) == "function" then
        return AR.IsEnabled()
    end
    if AR.enabled ~= nil then
        return AR.enabled
    end
    return true
end

local AuraUtil = _G.AuraUtil

local function HasCapBuff()
    -- Retail helper first
    if AuraUtil and AuraUtil.FindAuraByName then
        for _, buffName in ipairs(CAP_BUFF_NAMES) do
            local aura = AuraUtil.FindAuraByName(buffName, "player", "HELPFUL")
            if aura then
                return true
            end
        end
        return false
    end

    -- Fallback scan for older APIs
    for _, wanted in ipairs(CAP_BUFF_NAMES) do
        local i = 1
        while true do
            local name = _G.UnitBuff("player", i)
            if not name then break end
            if name == wanted then
                return true
            end
            i = i + 1
        end
    end

    return false
end

local function ShouldShow()
    -- You asked for: ONLY when the Tricked-Out Thinking Cap buff is active
    return IsAREnabled() and HasCapBuff()
end

------------------------------------------------------
-- Frame creation
------------------------------------------------------

local function CreateIconFrame()
    if Helper.frame then
        return Helper.frame
    end

    local Layout = GetLayout()

    local f = CreateFrame("Frame", "PE_AR_CardinalHelper", UIParent)
    Helper.frame = f

    -- Strata / level discipline: same as other AR HUD panels
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(0)

    -- Size/position driven by layout; defaults are in AR/PE_ARLayout.lua
    if Layout and Layout.Attach then
        Layout.Attach(f, "Cardinal Helper")
    end

    local point = f:GetPoint(1)
    if not point then
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end

    f:SetSize(128, 128)

    -- Start hidden & click-through
    f:SetAlpha(0)
    f:Hide()
    f:EnableMouse(false)
    f:EnableMouseWheel(false)

    -- Texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(ICON_TEXTURE)
    tex:SetBlendMode("ADD")  -- subtle glow; remove if too bright

    Helper.texture = tex

    -- Register with layout so /pearlayout can drag/resize it.
    -- Use deferAttach=true since we already attached above.
    if Layout and Layout.Register then
        Layout.Register("Cardinal Helper", f, { deferAttach = true })
    end

    return f
end

------------------------------------------------------
-- Visibility driver
------------------------------------------------------

local function UpdateIcon()
    local frame = CreateIconFrame()
    if not frame then return end

    if ShouldShow() then
        frame:SetAlpha(1)
        frame:Show()
    else
        frame:SetAlpha(0)
        frame:Hide()
    end
end

Helper.Update = UpdateIcon

------------------------------------------------------
-- Events
------------------------------------------------------

local eventFrame

local function OnEvent(self, event, arg1)
    if event == "UNIT_AURA" and arg1 ~= "player" then
        return
    end
    -- For PLAYER_LOGIN / PLAYER_ENTERING_WORLD / UNIT_AURA
    UpdateIcon()
end

function Helper.Init()
    if eventFrame then
        return
    end

    eventFrame = CreateFrame("Frame", "PE_AR_CardinalHelperEvents", UIParent)
    eventFrame:SetFrameStrata("LOW")
    eventFrame:SetFrameLevel(0)

    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_AURA")
end

function Helper.ForceUpdate()
    UpdateIcon()
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

if PE.LogInit then
    PE.LogInit(MODULE)
end

if PE.RegisterModule then
    PE.RegisterModule("AR Cardinal Helper", {
        name  = "AR Cardinal Helper",
        class = "AR HUD",
    })
end

Helper.Init()
