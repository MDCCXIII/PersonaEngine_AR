-- ##################################################
-- AR/PE_ARReticles.lua
-- PersonaEngine AR: screen-space unit reticles
--
-- * Custom textures for target/focus/mouseover
-- * Nameplates used as invisible anchors only
-- * Per-reticle distance-based scaling (min/max)
-- * Distance text stays a constant size
-- ##################################################

local MODULE = "AR Reticles"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Reticles = AR.Reticles or {}
local Ret = AR.Reticles

local sqrt = math.sqrt

------------------------------------------------------
-- Media paths
------------------------------------------------------

local MEDIA_PATH = "Interface\\AddOns\\PersonaEngine_AR\\media\\"

local TEXTURES = {
    targetCircle = MEDIA_PATH .. "My Target Reticle - Red",
    focusCircle  = MEDIA_PATH .. "My Focus Reticle - Teal",
    mouseover    = MEDIA_PATH .. "My Mouseover Indicator - Glowing",

    -- Reserved for future off-screen pointer logic:
    targetArrow  = MEDIA_PATH .. "My Target Arrow - Red",
    focusArrow   = MEDIA_PATH .. "My Focus Arrow - Teal",
}

------------------------------------------------------
-- Tunables
--
-- Each reticle can define:
--   baseWidth, baseHeight  : raw texture dimensions
--   near, far              : yard ranges for scaling
--   minScale, maxScale     : scale factors at far/near
--   texture                : texture path
--   offsetX, offsetY       : anchor offset from nameplate
------------------------------------------------------

local RETICLE_CONFIG = {
    target = {
        baseWidth  = 256,
        baseHeight = 128,
        near       = 5,
        far        = 45,
        minScale   = 0.01,
        maxScale   = 0.30,   -- close-range size
        texture    = TEXTURES.targetCircle,
        offsetX    = 0,
        offsetY    = -0,    -- torso-ish
    },
    focus = {
        baseWidth  = 256,
        baseHeight = 128,
        near       = 5,
        far        = 45,
        minScale   = 0.01,
        maxScale   = 0.30,
        texture    = TEXTURES.focusCircle,
        offsetX    = 0,
        offsetY    = -0,
    },
    mouseover = {
        baseWidth  = 16,
        baseHeight = 16,
        near       = 5,
        far        = 350,    -- "design" max; engine limit is lower
        minScale   = 0.20,
        maxScale   = 0.90,
        texture    = TEXTURES.mouseover,
        offsetX    = 0,
        offsetY    = 10,     -- above head
    },
}

local REF_PLATE_HEIGHT = 20  -- tune this to "normal mob" nameplate height

-- Update rate (seconds)
local UPDATE_INTERVAL = 0.03

------------------------------------------------------
-- Helpers
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

local function IsValidUnit(unit)
    return UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

local function GetUnitDistanceYards(unit)
    if not IsValidUnit(unit) then
        return nil
    end

    local px, py, pz, pInstance = UnitPosition("player")
    local ux, uy, uz, uInstance = UnitPosition(unit)

    if not px or not ux or pInstance ~= uInstance then
        return nil
    end

    pz, uz = pz or 0, uz or 0

    local dx = ux - px
    local dy = uy - py
    local dz = uz - pz

    return sqrt(dx*dx + dy*dy + dz*dz)
end


local function ComputeScale(dist, cfg)
    if not cfg then
        return 1.0
    end

    local near     = cfg.near or 0
    local far      = cfg.far or (near + 1)
    local minScale = cfg.minScale or 0.5
    local maxScale = cfg.maxScale or 1.0

    if not dist then
        -- If the API refuses to give us distance, use default (maxScale).
        return maxScale
    end

    if dist <= near then
        return maxScale
    elseif dist >= far then
        return minScale
    end

    local t = (dist - near) / (far - near)
    return maxScale + (minScale - maxScale) * t
end

-- Recursively strip *all* visuals from a frame tree, but keep alpha.
local function StripFrameVisuals(frame)
    if not frame or frame._PE_AR_Stripped then
        return
    end
    frame._PE_AR_Stripped = true

    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        StripFrameVisuals(child)
    end

    local regions = { frame:GetRegions() }
    for _, r in ipairs(regions) do
        if r:IsObjectType("Texture") or r:IsObjectType("FontString") then
            r:SetAlpha(0)
        end
    end
end

-- Use plate as invisible anchor: no bars, no names.
local function HideNameplateArt(plate)
    if not plate then return end

    StripFrameVisuals(plate)

    local uf = plate.UnitFrame or plate.unitFrame
    if uf then
        StripFrameVisuals(uf)
    end
end

local function MuteNameplate(plate)
    if not plate then return end
    plate:SetAlpha(0)

    local uf = plate.UnitFrame or plate.unitFrame
    if uf and uf.SetAlpha then
        uf:SetAlpha(0)
    end
end


-- Prefer nameplates (invisible), fall back to Blizz target/focus frames.
local function GetUnitAnchor(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then
            HideNameplateArt(plate)
			MuteNameplate(plate)

            local uf = plate.UnitFrame or plate.unitFrame
            if uf and uf.healthBar then
                return uf.healthBar
            end
            return plate
        end
    end

    if unit == "target" then
        return _G.TargetFrame
    elseif unit == "focus" then
        return _G.FocusFrame
    end

    return nil
end

-- Make sure nameplates exist as anchors, but their own visuals are off.
local function EnsureNameplateCVars()
    if not (GetCVar and SetCVar) then return end

    if tonumber(GetCVar("nameplateShowEnemies") or "0") == 0 then
        SetCVar("nameplateShowEnemies", 1)
    end
    if tonumber(GetCVar("nameplateShowAll") or "0") == 0 then
        SetCVar("nameplateShowAll", 1)
    end
    -- Kill the personal bar under your feet
    if tonumber(GetCVar("nameplateShowSelf") or "1") ~= 0 then
        SetCVar("nameplateShowSelf", 0)
    end
end

------------------------------------------------------
-- Reticle frame factories
------------------------------------------------------

local function CreateReticleFrame(name, cfg)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(cfg.baseWidth or 64, cfg.baseHeight or 64)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(40)
    f:EnableMouse(false)

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(cfg.texture or "Interface\\Cooldown\\ping4")
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetBlendMode("ADD")
    f.tex = tex

    local distFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    distFS:SetPoint("TOP", f, "BOTTOM", 0, -2)
    distFS:SetJustifyH("CENTER")
    distFS:SetTextColor(1, 1, 1, 0.9)
    distFS:SetText("")
    f.distFS = distFS
	
	if f.SetIgnoreParentAlpha then
        f:SetIgnoreParentAlpha(true)
    end
    if f.distFS and f.distFS.SetIgnoreParentAlpha then
        f.distFS:SetIgnoreParentAlpha(true)
    end


    f.cfg    = cfg
    f.unit   = nil
    f.anchor = nil
    f.dist   = nil

    f:Hide()
    return f
end

------------------------------------------------------
-- State
------------------------------------------------------

Ret.frames = Ret.frames or {}

local function EnsureFrames()
    if Ret.frames.target then
        return
    end

    Ret.frames.target    = CreateReticleFrame("PE_AR_TargetReticle",       RETICLE_CONFIG.target)
    Ret.frames.focus     = CreateReticleFrame("PE_AR_FocusReticle",        RETICLE_CONFIG.focus)
    Ret.frames.mouseover = CreateReticleFrame("PE_AR_MouseoverIndicator",  RETICLE_CONFIG.mouseover)
end

------------------------------------------------------
-- Core update logic
------------------------------------------------------

local function HideReticleFrame(frame)
    if not frame then return end
    frame.unit   = nil
    frame.anchor = nil
    frame.dist   = nil
    if frame.distFS then
        frame.distFS:SetText("")
    end
    frame:Hide()
end

local function UpdateReticleForUnit(unit, frame, cfg)
    if not frame or not cfg then return end

    if not IsAREnabled() then
        HideReticleFrame(frame)
        return
    end

    if not IsValidUnit(unit) then
        HideReticleFrame(frame)
        return
    end

    local anchor = GetUnitAnchor(unit)
    if not anchor or not anchor:IsVisible() then
        -- Off-screen / no anchor → future directional-pointer hook.
        HideReticleFrame(frame)
        return
    end

    frame.unit   = unit
    frame.anchor = anchor

    -- Measure the plate to infer unit size / distance
    local plateH       = anchor:GetHeight() or REF_PLATE_HEIGHT
    local sizeScaleRaw = plateH / REF_PLATE_HEIGHT
    -- Clamp it a bit so bosses don’t go insane and critters don’t vanish
    local sizeScale    = math.min(math.max(sizeScaleRaw, 0.4), 1.6)

    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint(
        "CENTER",
        anchor,
        "CENTER",
        (cfg.offsetX or 0),
        (cfg.offsetY or 0) - (plateH * 0.7)*   -- move further down for tall dudes
    )

    local dist = GetUnitDistanceYards(unit)
    frame.dist = dist

    -- Distance label ("--" if we can't get a number)
    if frame.distFS then
        if dist then
            frame.distFS:SetFormattedText("%.0f yd", dist)
        else
            frame.distFS:SetText("--")
        end
    end

    -- Distance-based scaling
    local distScale = ComputeScale(dist, cfg)
    if distScale < 0.1 then
        distScale = 0.1
    end

    -- Final scale = distance scale * plate-height scale
    local finalScale = distScale * sizeScale
    frame:SetScale(finalScale)

    -- Counter-scale the distance text so it stays a constant size
    if frame.distFS then
        frame.distFS:SetScale(1 / finalScale)
    end

    frame:Show()
end


local function UpdateMouseoverIndicator(frame, cfg)
    if not frame or not cfg then return end

    if not IsAREnabled() then
        frame:Hide()
        frame.anchor = nil
        return
    end

    if not UnitExists("mouseover") or UnitIsDeadOrGhost("mouseover") then
        frame:Hide()
        frame.anchor = nil
        return
    end

    local anchor = GetUnitAnchor("mouseover")
    if not anchor or not anchor:IsVisible() then
        frame:Hide()
        frame.anchor = nil
        return
    end

    local plateH       = anchor:GetHeight() or REF_PLATE_HEIGHT
    local sizeScaleRaw = plateH / REF_PLATE_HEIGHT
    local sizeScale    = math.min(math.max(sizeScaleRaw, 0.4), 1.6)

    frame.anchor = anchor
    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint(
        "CENTER",
        anchor,
        "CENTER",
        (cfg.offsetX or 0),
        (cfg.offsetY or 0) * (plateH * 0.3)  -- slightly above head, scaled
    )

    local dist      = GetUnitDistanceYards("mouseover")
    frame.dist      = dist
    local distScale = ComputeScale(dist, cfg)
    if distScale < 0.1 then
        distScale = 0.1
    end

    local finalScale = distScale * sizeScale
    frame:SetScale(finalScale)

    frame:Show()
end

------------------------------------------------------
-- Driver
------------------------------------------------------

local driver
local updateThrottle = 0

local function OnUpdate(self, elapsed)
    updateThrottle = updateThrottle + elapsed
    if updateThrottle < UPDATE_INTERVAL then
        return
    end
    updateThrottle = 0

    EnsureFrames()

    UpdateReticleForUnit("target", Ret.frames.target, RETICLE_CONFIG.target)
    UpdateReticleForUnit("focus",  Ret.frames.focus,  RETICLE_CONFIG.focus)
    UpdateMouseoverIndicator(Ret.frames.mouseover, RETICLE_CONFIG.mouseover)
end

function Ret.Init()
    if driver then
        return
    end

    EnsureNameplateCVars()
    EnsureFrames()

    driver = CreateFrame("Frame", "PE_AR_ReticleDriver", UIParent)
    driver:SetScript("OnUpdate", OnUpdate)
end

function Ret.ForceUpdate()
    if driver then
        OnUpdate(driver, UPDATE_INTERVAL)
    else
        Ret.Init()
    end
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Reticles", {
    name  = "AR Reticles",
    class = "AR HUD",
})

Ret.Init()
