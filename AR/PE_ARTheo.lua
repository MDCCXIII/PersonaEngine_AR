-- ##################################################
-- AR/PE_ARTheo.lua
-- PersonaEngine AR: Theo off-screen arrows
--
-- Self-contained layer:
-- * Uses AR.Reticles for:
--     - Theo arrow scales (target vs focus)
-- * Uses AR.Layout's "Theo Box" region for position/size
-- * Does NOT touch:
--     - range text ownership logic
--     - torso offsets
--     - scale sliders in AR Reticles
--
-- Rule:
-- * If unit's NAMEPLATE exists & is shown -> reticle
-- * Else -> Theo arrow
-- * Angle (playerFacing -> unit) only affects arrow
--   position/rotation; if angle is missing we:
--   - suppress the arrow
--   - show a "TPS Signal Lost - Target/Focus is N yds away"
--     message on the Theo box that:
--       * updates its range text continuously for 3 seconds
--       * then fades out over 0.5s without further updates
--       * clears immediately if a reticle/arrow returns
-- ##################################################

local MODULE = "AR Theo"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Theo = AR.Theo or {}
local Theo = AR.Theo

local Layout -- filled at init
local Ret    -- AR.Reticles

------------------------------------------------------
-- Libs / globals
------------------------------------------------------

local LibStub    = _G.LibStub
local HBD        = LibStub and LibStub("HereBeDragons-2.0", true) or nil
local RangeCheck = LibStub and LibStub("LibRangeCheck-3.0", true)
                    or _G.LibStub and _G.LibStub("LibRangeCheck-3.0", true)

local CreateFrame     = _G.CreateFrame
local UIParent        = _G.UIParent
local UnitExists      = _G.UnitExists
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitPosition    = _G.UnitPosition
local GetPlayerFacing = _G.GetPlayerFacing
local C_NamePlate     = _G.C_NamePlate

local cos, sin, atan2, abs, pi =
    math.cos, math.sin, math.atan2, math.abs, math.pi

local function AreVisualsAllowed()
    if PE and PE.ARHUDVisualsAllowed ~= nil then
        return PE.ARHUDVisualsAllowed
    end
    if AR and AR.HUDVisualsAllowed ~= nil then
        return AR.HUDVisualsAllowed
    end
    return true
end

local function IsAREnabled()
    local enabled
    if AR.IsEnabled and type(AR.IsEnabled) == "function" then
        enabled = AR.IsEnabled()
    elseif AR.enabled ~= nil then
        enabled = AR.enabled
    else
        enabled = true
    end
    return enabled and AreVisualsAllowed()
end

------------------------------------------------------
-- Media
------------------------------------------------------

local ADDON_NAME = ...
local MEDIA_PATH = "Interface\\AddOns\\" .. (ADDON_NAME or "PersonaEngine_AR") .. "\\media\\"

local TEXTURES = {
    target = MEDIA_PATH .. "My Target Arrow - Red.tga",
    focus  = MEDIA_PATH .. "My Focus Arrow - Teal.tga",
}

------------------------------------------------------
-- Basic helpers
------------------------------------------------------

local function GetUnitDistanceYards(unit)
    if not RangeCheck or not UnitExists(unit) then
        return nil
    end
    local minR, maxR = RangeCheck:GetRange(unit)
    if not minR and not maxR then
        return nil
    end
    if minR and maxR then
        return (minR + maxR) * 0.5
    end
    return minR or maxR
end

local function GetReticleFrameForUnit(unit)
    if unit == "target" then
        return _G.PE_AR_TargetReticle
    elseif unit == "focus" then
        return _G.PE_AR_FocusReticle
    end
    return nil
end

local function IsNameplateVisible(unit)
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
        return false
    end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    -- Alpha does NOT matter; you can zero it out.
    return plate ~= nil and plate:IsShown()
end

-- Use HBD world position when available, otherwise fall back to UnitPosition.
-- Returns dx, dy in world space, or nil if we can't reliably compute.
local function GetWorldDeltaFromPlayerToUnit(unit)
    if not UnitExists("player") or not UnitExists(unit) then
        return nil
    end

    -- Prefer HereBeDragons for better consistency.
    if HBD and HBD.GetUnitWorldPosition then
        local px, py, pInstance = HBD:GetUnitWorldPosition("player")
        local ux, uy, uInstance = HBD:GetUnitWorldPosition(unit)
        if px and ux and pInstance == uInstance then
            return (ux - px), (uy - py)
        end
    end

    -- Fallback: raw UnitPosition.
    local px, py, pInstance = UnitPosition("player")
    local ux, uy, uInstance = UnitPosition(unit)
    if not px or not ux or pInstance ~= uInstance then
        return nil
    end
    return (ux - px), (uy - py)
end

-- Angle from player-facing to unit, normalized to [-pi, pi]
local function GetRelativeAngleToUnit(unit)
    local dx, dy = GetWorldDeltaFromPlayerToUnit(unit)
    if not dx or not dy then
        return nil
    end
    if dx == 0 and dy == 0 then
        return 0
    end

    local facing = (GetPlayerFacing and GetPlayerFacing()) or 0
    local angleToUnit = atan2(dy, dx)
    local rel = angleToUnit - facing

    -- Normalize into [-pi, pi]
    rel = atan2(sin(rel), cos(rel))
    return rel
end

------------------------------------------------------
-- Theo box + arrows
------------------------------------------------------

Theo.arrows = Theo.arrows or {}

local function EnsureTheoBox()
    if Theo.box and Theo.box.GetObjectType and Theo.box:GetObjectType() == "Frame" then
        return Theo.box
    end

    local box = CreateFrame("Frame", "PE_AR_TheoBox", UIParent, "BackdropTemplate")
    box:SetFrameStrata("LOW")
    box:SetFrameLevel(0)
    box:SetSize(260, 140)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, -220)

    -- Fully transparent; layout editor tints it in edit mode.
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0, 0, 0, 0.0)
    box:SetBackdropBorderColor(0, 0, 0, 0.0)

    Theo.box = box

    Layout = Layout or (PE.AR and PE.AR.Layout)
    if Layout and Layout.Register then
        Layout.Register("Theo Box", box)
    end

    return box
end

local function EnsureArrow(which)
    local box = EnsureTheoBox()
    if not box then
        return nil
    end

    local arrow = Theo.arrows[which]
    if arrow and arrow.GetObjectType and arrow:GetObjectType() == "Frame" then
        arrow:SetParent(box)
        return arrow
    end

    local name = "PE_AR_TheoArrow_" .. which
    arrow = CreateFrame("Frame", name, box)
    arrow:SetFrameStrata("LOW")

    local baseLevel = box:GetFrameLevel() or 0
    if baseLevel < 0   then baseLevel = 0   end
    if baseLevel >= 50 then baseLevel = 49 end
    arrow:SetFrameLevel(baseLevel + 1)

    arrow:SetSize(32, 32)
    arrow:SetIgnoreParentScale(true)
    arrow:SetIgnoreParentAlpha(true)

    local tex = arrow:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(TEXTURES[which] or TEXTURES.target)
    tex:SetBlendMode("ADD")
    arrow.tex = tex

    local distFS = arrow:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    distFS:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    distFS:SetJustifyH("CENTER")
    distFS:SetTextColor(1, 1, 1, 0.9)
    distFS:SetText("")
    arrow.distFS = distFS

    arrow:Hide()
    Theo.arrows[which] = arrow

    return arrow
end

local function HideArrow(which)
    local arrow = Theo.arrows[which]
    if not arrow then
        return
    end
    if arrow.distFS then
        arrow.distFS:SetText("")
    end
    arrow:Hide()
end

------------------------------------------------------
-- "TPS Signal Lost" message system
------------------------------------------------------

Theo.noSignal = Theo.noSignal or {}

local function EnsureNoSignalLabel(which)
    local box = EnsureTheoBox()
    if not box then
        return nil
    end

    local slot = Theo.noSignal[which]
    if slot and slot.label then
        return slot.label
    end

    local fs = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

    -- Stack messages: Target on top, Focus just below.
    if which == "target" then
        fs:SetPoint("TOP", box, "TOP", 0, -6)
    else
        -- "focus"
        fs:SetPoint("TOP", box, "TOP", 0, -26)
    end

    fs:SetTextColor(1, 0.68, 0.2, 1) -- yellow-orange #FFAA33
    fs:SetText("")
    fs:Hide()

    Theo.noSignal[which] = {
        label        = fs,
        unit         = nil,
        liveTime     = 0,
        fading       = false,
        fadeRemaining= 0,
    }

    return fs
end

local function ShowNoSignal(which, unit)
    if not AreVisualsAllowed() then
        return
    end

    local fs = EnsureNoSignalLabel(which)
    if not fs then
        return
    end

    fs:SetAlpha(1)
    fs:Show()

    local slot = Theo.noSignal[which]
    if not slot then
        slot = {}
        Theo.noSignal[which] = slot
    end

    slot.label        = fs
    slot.unit         = unit
    slot.liveTime     = 3.0 -- seconds of live updating
    slot.fading       = false
    slot.fadeRemaining= 0
end

local function ClearNoSignal(which)
    local slot = Theo.noSignal[which]
    if not slot or not slot.label then
        return
    end

    local fs = slot.label
    fs:SetText("")
    fs:Hide()

    slot.unit          = nil
    slot.liveTime      = 0
    slot.fading        = false
    slot.fadeRemaining = 0
end

local function UpdateNoSignal(elapsed)
    -- If HUD visuals are disallowed, nuke all labels and bail.
    if not AreVisualsAllowed() then
        for which, slot in pairs(Theo.noSignal) do
            if slot and slot.label then
                slot.label:SetText("")
                slot.label:Hide()
            end
            if slot then
                slot.unit          = nil
                slot.liveTime      = 0
                slot.fading        = false
                slot.fadeRemaining = 0
            end
        end
        return
    end

    for which, slot in pairs(Theo.noSignal) do
        local fs = slot.label
        if not fs or not fs:IsShown() then
            -- nothing to do
        else
            if not slot.fading then
                -- Live phase: update text + countdown
                if slot.liveTime and slot.liveTime > 0 then
                    slot.liveTime = slot.liveTime - elapsed
                end

                -- Update range text each frame during live phase
                local labelUnit = (which == "focus") and "Focus" or "Target"
                local distText  = "--"

                if slot.unit then
                    local dist = GetUnitDistanceYards(slot.unit)
                    if dist then
                        distText = string.format("%d", dist + 0.5)
                    end
                end

                fs:SetText(string.format(
                    "TPS Signal Lost - %s is %s yds away",
                    labelUnit,
                    distText
                ))
                fs:SetAlpha(1)

                if slot.liveTime and slot.liveTime <= 0 then
                    -- Start fade phase
                    slot.fading       = true
                    slot.fadeRemaining= 0.5
                end
            else
                -- Fade-out phase: no more updates, just fade alpha
                if slot.fadeRemaining and slot.fadeRemaining > 0 then
                    slot.fadeRemaining = slot.fadeRemaining - elapsed
                    local t = slot.fadeRemaining
                    local alpha = math.max(0, t / 0.5)
                    fs:SetAlpha(alpha)
                    if t <= 0 then
                        fs:Hide()
                        fs:SetText("")
                        slot.unit          = nil
                        slot.liveTime      = 0
                        slot.fading        = false
                        slot.fadeRemaining = 0
                    end
                else
                    fs:Hide()
                end
            end
        end
    end
end

------------------------------------------------------
-- Per-unit update
------------------------------------------------------

local function UpdateArrowForUnit(unit, which)
    if not IsAREnabled() then
        HideArrow(which)
        ClearNoSignal(which)
        return
    end

    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
        HideArrow(which)
        ClearNoSignal(which)
        return
    end

    local reticleFrame = GetReticleFrameForUnit(unit)
    local plateVisible = IsNameplateVisible(unit)

    -- If nameplate is visible, always prefer reticle mode.
    if plateVisible and reticleFrame and reticleFrame.Show then
        HideArrow(which)
        ClearNoSignal(which)
        reticleFrame:Show()
        return
    end

    -- Otherwise, Theo arrow mode (unit off-screen / plate hidden).
    if reticleFrame and reticleFrame.Hide then
        reticleFrame:Hide()
    end

    local box = EnsureTheoBox()
    if not box or box:IsForbidden() then
        HideArrow(which)
        ClearNoSignal(which)
        return
    end

    local arrow = EnsureArrow(which)
    if not arrow then
        ClearNoSignal(which)
        return
    end

    local w, h = box:GetWidth(), box:GetHeight()
    local radius = math.min(w, h) * 0.5 - 18
    if radius < 10 then
        radius = 10
    end

    local angle = GetRelativeAngleToUnit(unit)
    local x, y

    if angle then
        -- Place arrow along the box border, based on relative angle.
        local xRel = cos(angle) * radius
        local yRel = sin(angle) * radius

        local halfW = w * 0.5 - 10
        local halfH = h * 0.5 - 10

        x, y = xRel, yRel

        if abs(xRel) / halfW > abs(yRel) / halfH then
            -- Hits left/right edge first.
            if xRel > 0 then
                x = halfW
            else
                x = -halfW
            end
            y = yRel * (halfW / abs(xRel))
        else
            -- Hits top/bottom edge first.
            if yRel > 0 then
                y = halfH
            else
                y = -halfH
            end
            x = xRel * (halfH / abs(yRel))
        end

        -- Rotate arrow to point toward unit.
        if arrow.tex and arrow.tex.SetRotation then
            arrow.tex:SetRotation(angle)
        end

        -- Since we have a valid arrow, kill any existing "no signal" message.
        ClearNoSignal(which)
    else
        -- Angle math failed: hide arrow and show TPS Signal Lost with live range.
        HideArrow(which)
        ShowNoSignal(which, unit)
        return
    end

    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", box, "CENTER", x, y)

    -- Distance label via LibRangeCheck
    local dist = GetUnitDistanceYards(unit)
    if arrow.distFS then
        if dist then
            arrow.distFS:SetFormattedText("%.0f yd", dist)
        else
            arrow.distFS:SetText("--")
        end
    end

    -- Per-unit scale from Reticles DB (target vs focus).
    local scale = 1.0
    if Ret and Ret.GetTheoArrowScale then
        scale = Ret.GetTheoArrowScale(which) or 1.0
    end
    arrow:SetScale(scale)

    if AreVisualsAllowed() then
        arrow:Show()
    else
        arrow:Hide()
    end
end

------------------------------------------------------
-- Driver
------------------------------------------------------

local driver
local throttle = 0
local INTERVAL = 0.02

local function OnUpdate(self, elapsed)
    -- Always drive "TPS Signal Lost" fade/update logic
    UpdateNoSignal(elapsed)

    throttle = throttle + elapsed
    if throttle < INTERVAL then
        return
    end
    throttle = 0

    -- Target + focus only; mouseover stays pure reticle.
    UpdateArrowForUnit("target", "target")
    UpdateArrowForUnit("focus",  "focus")
end

function Theo.Init()
    if Theo.initialized then
        return
    end

    Layout = PE.AR and PE.AR.Layout or AR.Layout
    Ret    = PE.AR and PE.AR.Reticles or AR.Reticles

    EnsureTheoBox()
    EnsureArrow("target")
    EnsureArrow("focus")

    driver = CreateFrame("Frame", "PE_AR_TheoDriver", UIParent)
    driver:SetFrameStrata("LOW")
    driver:SetFrameLevel(0)
    driver:SetScript("OnUpdate", OnUpdate)

    Theo.initialized = true
end

------------------------------------------------------
-- Event: init at PLAYER_LOGIN
------------------------------------------------------

local evt = CreateFrame("Frame", "PE_AR_TheoEventDriver", UIParent)
evt:SetFrameStrata("LOW")
evt:SetFrameLevel(0)
evt:RegisterEvent("PLAYER_LOGIN")
evt:SetScript("OnEvent", function()
    Theo.Init()
end)

------------------------------------------------------
-- Module registration
------------------------------------------------------

if PE.LogInit then
    PE.LogInit(MODULE)
end

if PE.RegisterModule then
    PE.RegisterModule("AR Theo", {
        name  = "Theo off-screen arrows",
        class = "AR HUD",
    })
end
