-- ##################################################
-- AR/PE_ARReticles.lua
-- PersonaEngine AR: Reticles + Theo arrows
--
-- * Custom textures for target / focus / mouseover
-- * Distance in yards via LibRangeCheck-3.0 (if present)
-- * Smooth scaling vs distance
-- * Global mouseover offset (no range-based drift)
-- * Shared offsets for target+focus (they always overlap)
-- * Theo mode:
--   - If unit is inside a configurable front cone → screen reticle
--   - If unit is outside the cone → arrow on Theo box border
-- * Exactly one distance label per unit (mouseover/target/focus priority)
-- * Editors:
--   /pearreticle → reticle + torso + mouseover offset
--   /pearlayout → layout editor toggles Theo box + reticle editor
-- ##################################################

local MODULE = "AR Reticles"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR      = PE.AR
AR.Reticles   = AR.Reticles or {}
local Ret     = AR.Reticles

------------------------------------------------------
-- Libs / globals
------------------------------------------------------

local RangeCheck       = _G.LibStub and _G.LibStub("LibRangeCheck-3.0", true)
local UIParent         = _G.UIParent
local CreateFrame      = _G.CreateFrame
local UnitExists       = _G.UnitExists
local UnitIsDeadOrGhost= _G.UnitIsDeadOrGhost
local UnitGUID         = _G.UnitGUID
local UnitPosition     = _G.UnitPosition
local UnitCreatureType = _G.UnitCreatureType
local GetPlayerFacing  = _G.GetPlayerFacing
local C_NamePlate      = _G.C_NamePlate
local GetCVar          = _G.GetCVar
local SetCVar          = _G.SetCVar

local cos, sin, atan2, abs, sqrt, pi =
    math.cos, math.sin, math.atan2, math.abs, math.sqrt, math.pi

------------------------------------------------------
-- Media
------------------------------------------------------

local ADDON_NAME = ...
local MEDIA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

local TEXTURES = {
    targetReticle = MEDIA_PATH .. "My Target Reticle - Red",
    focusReticle  = MEDIA_PATH .. "My Focus Reticle - Teal",
    mouseover     = MEDIA_PATH .. "My Mouseover Indicator - Glowing",
    targetArrow   = MEDIA_PATH .. "My Target Arrow - Red.tga",
    focusArrow    = MEDIA_PATH .. "My Focus Arrow - Teal.tga",
}

------------------------------------------------------
-- Tunables / defaults
------------------------------------------------------

local UPDATE_INTERVAL   = 0.01 -- seconds
local SCALE_SMOOTHING   = 0.25 -- 0..1, fraction of delta each update
local DEG2RAD           = pi / 180

-- Distance label ownership per unit GUID.
-- Lower number = higher priority.
local OWNER_PRIORITY = {
    mouseover = 3, -- highest priority (your custom choice)
    target    = 2,
    focus     = 1, -- lowest priority
}

local RETICLE_DEFAULTS = {
    target = {
        key        = "target",
        label      = "Target",
        baseWidth  = 256,
        baseHeight = 128,
        near       = 5,
        far        = 45,
        minScale   = 0.05,
        maxScale   = 0.35,
        texture    = TEXTURES.targetReticle,
        offsetX    = 0,
        offsetY    = 0,
    },
    focus = {
        key        = "focus",
        label      = "Focus",
        baseWidth  = 256,
        baseHeight = 128,
        near       = 5,
        far        = 45,
        minScale   = 0.05,
        maxScale   = 0.35,
        texture    = TEXTURES.focusReticle,
        offsetX    = 0,
        offsetY    = 0,
    },
    mouseover = {
        key        = "mouseover",
        label      = "Mouseover",
        baseWidth  = 32,
        baseHeight = 32,
        near       = 5,
        far        = 45,
        minScale   = 0.40,
        maxScale   = 0.90,
        texture    = TEXTURES.mouseover,
        offsetX    = 0,
        offsetY    = 10,
    },
}

-- Torso offsets per creature type (pixels), shared target+focus
local DEFAULT_TORSO_OFFSETS = {
    ["Humanoid"]   = -360,
    ["Beast"]      = -300,
    ["Mechanical"] = -330,
}

------------------------------------------------------
-- DB helpers
------------------------------------------------------

local function GetARRoot()
    _G.PersonaEngineAR_DB = _G.PersonaEngineAR_DB or {}
    _G.PersonaEngineAR_DB.reticles = _G.PersonaEngineAR_DB.reticles or {}
    return _G.PersonaEngineAR_DB.reticles
end

-- Per-reticle config (target/focus/mouseover)
local function GetReticleDB()
    local root = GetARRoot()
    root.config = root.config or {}
    return root.config
end

-- Torso DB: per creature type, shared between target/focus
local function GetTorsoDB()
    local root = GetARRoot()
    root.torso = root.torso or {}
    return root.torso
end

-- Theo DB: front angle + arrow scales (box rect now lives in layout DB)
local function GetTheoDB()
    local root = GetARRoot()
    root.theo = root.theo or {}

    local t = root.theo
    if t.frontAngleDeg == nil then
        t.frontAngleDeg = 60
    end -- default cone
    if t.targetScale == nil then
        t.targetScale = 1.0
    end
    if t.focusScale == nil then
        t.focusScale = 1.0
    end

    return t
end

-- Global mouseover offset
local function GetMouseoverDB()
    local root = GetARRoot()
    root.mouseover = root.mouseover or {}
    return root.mouseover
end

------------------------------------------------------
-- Reticle config access
------------------------------------------------------

local function CopyTableShallow(src)
    local t = {}
    if type(src) == "table" then
        for k, v in pairs(src) do
            t[k] = v
        end
    end
    return t
end

local function MergeConfig(key)
    local defaults = RETICLE_DEFAULTS[key]
    if not defaults then
        return nil
    end

    local db    = GetReticleDB()
    local saved = db[key]

    local cfg = CopyTableShallow(defaults)
    if type(saved) == "table" then
        for k, v in pairs(saved) do
            cfg[k] = v
        end
    end

    -- One-time fix: if old mouseover configs still use target texture, swap them.
    if key == "mouseover" and cfg.texture == TEXTURES.targetReticle then
        cfg.texture = TEXTURES.mouseover
    end

    return cfg
end

Ret.cfgCache = Ret.cfgCache or {}

function Ret.InvalidateConfig(key)
    if key then
        Ret.cfgCache[key] = nil
    else
        for k in pairs(Ret.cfgCache) do
            Ret.cfgCache[k] = nil
        end
    end
end

function Ret.GetReticleConfig(key)
    if not key then
        return nil
    end

    if not Ret.cfgCache[key] then
        Ret.cfgCache[key] = MergeConfig(key)
    end

    return Ret.cfgCache[key]
end

-- Important: when you change core fields for target or focus, the other is mirrored
local function IsSharedReticleField(field)
    return field == "offsetX"
        or field == "offsetY"
        or field == "minScale"
        or field == "maxScale"
        or field == "near"
        or field == "far"
end

function Ret.SetReticleField(key, field, value)
    if not key or not field then
        return
    end
    if not RETICLE_DEFAULTS[key] then
        return
    end

    local db = GetReticleDB()
    db[key] = db[key] or {}
    db[key][field] = value

    -- Mirror shared fields between target and focus so they always overlap
    if (key == "target" or key == "focus") and IsSharedReticleField(field) then
        local other = (key == "target") and "focus" or "target"
        if RETICLE_DEFAULTS[other] then
            db[other] = db[other] or {}
            db[other][field] = value
            Ret.cfgCache[other] = MergeConfig(other)
        end
    end

    Ret.cfgCache[key] = MergeConfig(key)
    Ret.ForceUpdate()
end

------------------------------------------------------
-- Torso offsets (target + focus share per creature type)
------------------------------------------------------

local function GetCreatureType(unitOrType)
    if not unitOrType then
        return nil
    end

    -- If it's a real unit token, try to read from the game.
    if UnitExists(unitOrType) then
        return UnitCreatureType(unitOrType) or "UNKNOWN"
    end

    -- Otherwise treat it as a literal creature-type string.
    if type(unitOrType) == "string" then
        return unitOrType
    end

    return nil
end

function Ret.GetTorsoOffset(reticleKey, unitOrType)
    -- Mouseover doesn’t use torso offsets
    if reticleKey == "mouseover" then
        return 0
    end

    local creatureType = GetCreatureType(unitOrType)
    if not creatureType then
        return 0
    end

    local db   = GetTorsoDB()
    local perT = db[creatureType]

    if type(perT) == "table" and type(perT.shared) == "number" then
        return perT.shared
    end

    return DEFAULT_TORSO_OFFSETS[creatureType] or 0
end

function Ret.SetTorsoOffset(creatureType, offset)
    if not creatureType then
        return
    end

    local db = GetTorsoDB()
    db[creatureType] = db[creatureType] or {}
    db[creatureType].shared = offset or 0

    Ret.ForceUpdate()
end

------------------------------------------------------
-- Global mouseover offset (fixed height above plate)
------------------------------------------------------

function Ret.GetMouseoverOffset()
    local db = GetMouseoverDB()
    return db.offsetY or 0
end

function Ret.SetMouseoverOffset(offset)
    local db = GetMouseoverDB()
    db.offsetY = offset or 0
    Ret.ForceUpdate()
end

------------------------------------------------------
-- Theo config helpers
------------------------------------------------------

function Ret.GetTheoFrontAngleDeg()
    local t = GetTheoDB()
    return t.frontAngleDeg or 60
end

function Ret.SetTheoFrontAngleDeg(deg)
    if type(deg) ~= "number" then
        return
    end

    if deg < 10 then
        deg = 10
    end
    if deg > 120 then
        deg = 120
    end

    local t = GetTheoDB()
    t.frontAngleDeg = deg
    Ret.ForceUpdate()
end

function Ret.GetTheoFrontAngleRad()
    return Ret.GetTheoFrontAngleDeg() * DEG2RAD
end

function Ret.GetTheoArrowScale(key)
    local t = GetTheoDB()
    if key == "target" then
        return t.targetScale or 1.0
    elseif key == "focus" then
        return t.focusScale or 1.0
    end
    return 1.0
end

function Ret.SetTheoArrowScale(key, val)
    if type(val) ~= "number" then
        return
    end

    if val < 0.3 then
        val = 0.3
    end
    if val > 2.0 then
        val = 2.0
    end

    local t = GetTheoDB()
    if key == "target" then
        t.targetScale = val
    elseif key == "focus" then
        t.focusScale = val
    end

    Ret.ForceUpdate()
end

------------------------------------------------------
-- Nameplate CVars guard (overlapping plates)
------------------------------------------------------

local originalNameplateMotion = nil

local function EnsureNameplateCVars()
    if not C_NamePlate then
        return
    end

    if originalNameplateMotion == nil then
        originalNameplateMotion = GetCVar("nameplateMotion")
    end

    if GetCVar("nameplateMotion") ~= "1" then
        SetCVar("nameplateMotion", "1")
    end
end

local function RestoreNameplateCVars()
    if originalNameplateMotion ~= nil then
        SetCVar("nameplateMotion", originalNameplateMotion)
    end
end

------------------------------------------------------
-- Misc helpers
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
    return unit and UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

local function GetUnitDistanceYards(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end

    if RangeCheck then
        local minR, maxR = RangeCheck:GetRange(unit)
        if not minR and not maxR then
            return nil
        end
        if minR and maxR then
            return (minR + maxR) * 0.5
        end
        return minR or maxR
    end

    return nil
end

-- Relative angle (radians) and 2D distance from player → unit
local function GetRelativeAngleAndDistance(unit)
    if not IsValidUnit(unit) then
        return nil
    end

    local px, py, pz, pm = UnitPosition("player")
    local ux, uy, uz, um = UnitPosition(unit)
    if not px or not ux or pm ~= um then
        return nil
    end

    local dx     = ux - px
    local dy     = uy - py
    local dist2D = sqrt(dx * dx + dy * dy)
    local facing = GetPlayerFacing() or 0
    local angle  = atan2(dy, dx)
    local rel    = angle - facing

    if rel > pi then
        rel = rel - 2 * pi
    elseif rel < -pi then
        rel = rel + 2 * pi
    end

    return rel, dist2D
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
        return maxScale
    end

    if dist <= near then
        return maxScale
    elseif dist >= far then
        return minScale
    else
        local t = (dist - near) / (far - near)
        return maxScale - (maxScale - minScale) * t
    end
end

------------------------------------------------------
-- Reticle frame factory
------------------------------------------------------

local function CreateReticleFrame(name, key)
    local cfg = Ret.GetReticleConfig(key)
    if not cfg then
        return nil
    end

    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(cfg.baseWidth or 64, cfg.baseHeight or 64)
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(1)
    f:EnableMouse(false)
    f:SetIgnoreParentAlpha(true)

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(cfg.texture or "Interface\\Cooldown\\ping4")
    tex:SetBlendMode("ADD")
    f.tex = tex

    local distFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    -- UNDERNEATH the reticle
    distFS:SetPoint("TOP", f, "BOTTOM", 0, -2)
    distFS:SetJustifyH("CENTER")
    distFS:SetTextColor(1, 1, 1, 0.9)
    distFS:SetText("")
    f.distFS = distFS

    f.key           = key
    f.unit          = nil
    f.dist          = nil
    f._currentScale = 1
    f:Hide()

    return f
end

------------------------------------------------------
-- Theo box + arrow frames
------------------------------------------------------

Ret.frames    = Ret.frames or {}
Ret.theoBox   = Ret.theoBox or nil
Ret.theoArrow = Ret.theoArrow or {} -- per key

local function EnsureTheoBox()
    if Ret.theoBox then
        return
    end

    local box = CreateFrame("Frame", "PE_AR_TheoBox", UIParent, "BackdropTemplate")
    box:SetFrameStrata("LOW")
    box:SetFrameLevel(0)
    box:EnableMouse(false)           -- always click-through in normal play
    box:SetIgnoreParentAlpha(true)
    box:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    box:SetBackdropBorderColor(0.2, 1.0, 0.7, 0.9)
    box:SetAlpha(0)                  -- hidden by default
    Ret.theoBox = box

    local center = box:CreateTexture(nil, "OVERLAY")
    center:SetSize(8, 8)
    center:SetColorTexture(0.2, 1.0, 0.2, 0.8)
    center:SetPoint("CENTER", box, "CENTER", 0, 0)
    center:Hide()
    Ret.theoCenter = center

    -- Let layout system control position/size (defaults + saved)
    if AR.Layout and AR.Layout.Register then
        AR.Layout.Register("Theo Box", box)
    end
end

local function CreateTheoArrowFrame(name, key)
    EnsureTheoBox()

    local f = CreateFrame("Frame", name, Ret.theoBox)
    f:SetSize(48, 48)
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(1)
    f:EnableMouse(false)
    f:SetIgnoreParentAlpha(true)

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetBlendMode("ADD")
    if key == "focus" then
        tex:SetTexture(TEXTURES.focusArrow)
    else
        tex:SetTexture(TEXTURES.targetArrow)
    end
    f.tex = tex

    local distFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    distFS:SetPoint("TOP", f, "BOTTOM", 0, -2)
    distFS:SetJustifyH("CENTER")
    distFS:SetTextColor(1, 1, 1, 0.9)
    distFS:SetText("")
    f.distFS = distFS

    f.key  = key
    f.unit = nil
    f:Hide()

    return f
end

local function EnsureFrames()
    if not Ret.frames.target then
        Ret.frames.target   = CreateReticleFrame("PE_AR_TargetReticle", "target")
        Ret.frames.focus    = CreateReticleFrame("PE_AR_FocusReticle", "focus")
        Ret.frames.mouseover= CreateReticleFrame("PE_AR_MouseoverIndicator", "mouseover")
    end

    if not Ret.theoArrow.target then
        Ret.theoArrow.target = CreateTheoArrowFrame("PE_AR_TheoTarget", "target")
    end

    if not Ret.theoArrow.focus then
        Ret.theoArrow.focus = CreateTheoArrowFrame("PE_AR_TheoFocus", "focus")
    end
end

------------------------------------------------------
-- Show/hide helpers
------------------------------------------------------

local function HideReticleFrame(f)
    if not f then
        return
    end

    f.unit          = nil
    f.dist          = nil
    f._currentScale = 1

    if f.distFS then
        f.distFS:SetText("")
        f.distFS:SetScale(1)
    end

    f:Hide()
end

local function HideTheoArrow(f)
    if not f then
        return
    end

    f.unit = nil

    if f.distFS then
        f.distFS:SetText("")
        f.distFS:SetScale(1)
    end

    f:Hide()
end

local function ApplySmoothScale(frame, targetScale)
    if not frame then
        return
    end

    targetScale = targetScale or 1.0
    local current = frame._currentScale or targetScale
    local new     = current + (targetScale - current) * SCALE_SMOOTHING

    frame._currentScale = new
    frame:SetScale(new)

    if frame.distFS then
        frame.distFS:SetScale(1 / new)
    end
end

------------------------------------------------------
-- Distance-label ownership per GUID
------------------------------------------------------

local function BuildGuidOwner()
    local guidOwner = {}

    local function claim(unit, key)
        if not UnitExists(unit) then
            return
        end

        local guid = UnitGUID(unit)
        if not guid then
            return
        end

        local prio = OWNER_PRIORITY[key] or 999
        local cur  = guidOwner[guid]

        if not cur or prio < cur.prio then
            -- lower = higher priority
            guidOwner[guid] = { key = key, prio = prio }
        end
    end

    claim("mouseover", "mouseover")
    claim("target",    "target")
    claim("focus",     "focus")

    return guidOwner
end

local function HasOwnershipForUnit(guidOwner, unit, key)
    if not guidOwner or not unit or not key or not UnitExists(unit) then
        return false
    end

    local guid = UnitGUID(unit)
    if not guid then
        return false
    end

    local owner = guidOwner[guid]
    return owner and owner.key == key
end

------------------------------------------------------
-- Core update helpers
------------------------------------------------------

local function UpdateScreenReticle(unit, frame, cfg, guidOwner)
    if not frame or not cfg then
        return HideReticleFrame(frame)
    end

    if not IsAREnabled() or not IsValidUnit(unit) then
        return HideReticleFrame(frame)
    end

    local plate =
        C_NamePlate and C_NamePlate.GetNamePlateForUnit and
        C_NamePlate.GetNamePlateForUnit(unit)

    if not plate or not plate.UnitFrame or not plate.UnitFrame.healthBar then
        return HideReticleFrame(frame)
    end

    local anchor = plate.UnitFrame.healthBar

    frame:ClearAllPoints()
    local torsoOffset = Ret.GetTorsoOffset(frame.key, unit) or 0
    frame:SetPoint(
        "CENTER",
        anchor,
        "CENTER",
        cfg.offsetX or 0,
        (cfg.offsetY or 0) + torsoOffset
    )

    local dist = GetUnitDistanceYards(unit)
    frame.unit = unit
    frame.dist = dist

    local showText = HasOwnershipForUnit(guidOwner, unit, frame.key)

    if frame.distFS then
        if showText and dist then
            frame.distFS:SetFormattedText("%.0f yd", dist)
        elseif showText then
            frame.distFS:SetText("--")
        else
            frame.distFS:SetText("")
        end
    end

    local distScale = ComputeScale(dist, cfg)
    if distScale < 0.1 then
        distScale = 0.1
    end

    ApplySmoothScale(frame, distScale)
    frame:Show()
end

local function UpdateTheoArrow(unit, key, arrowFrame, guidOwner)
    if not arrowFrame then
        return
    end

    if not IsAREnabled() or not IsValidUnit(unit) then
        return HideTheoArrow(arrowFrame)
    end

    local relAngle, dist = GetRelativeAngleAndDistance(unit)
    if not relAngle then
        return HideTheoArrow(arrowFrame)
    end

    local box = Ret.theoBox
    if not box then
        return HideTheoArrow(arrowFrame)
    end

    arrowFrame:ClearAllPoints()

    local absRel = abs(relAngle)
    local forty5 = 45 * DEG2RAD
    local one35  = 135 * DEG2RAD

    if absRel >= one35 then
        arrowFrame:SetPoint("BOTTOM", box, "BOTTOM", 0, 4)
    elseif relAngle > 0 then
        if absRel > forty5 then
            arrowFrame:SetPoint("RIGHT", box, "RIGHT", -4, 0)
        else
            arrowFrame:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4)
        end
    else
        if absRel > forty5 then
            arrowFrame:SetPoint("LEFT", box, "LEFT", 4, 0)
        else
            arrowFrame:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
        end
    end

    if arrowFrame.tex then
        arrowFrame.tex:SetRotation(-relAngle)
    end

    local scale = Ret.GetTheoArrowScale(key) or 1.0
    if scale < 0.3 then
        scale = 0.3
    end
    if scale > 2.0 then
        scale = 2.0
    end

    arrowFrame:SetScale(scale)

    local showText = HasOwnershipForUnit(guidOwner, unit, key)
    local distText = arrowFrame.distFS

    if distText then
        if showText and dist then
            distText:SetFormattedText("%.0f yd", dist)
        elseif showText then
            distText:SetText("--")
        else
            distText:SetText("")
        end

        distText:SetScale(1 / scale)
    end

    arrowFrame.unit = unit
    arrowFrame:Show()
end

local function UpdateMouseoverIndicator(frame, cfg, guidOwner)
    if not frame or not cfg then
        return HideReticleFrame(frame)
    end

    if not IsAREnabled() or not IsValidUnit("mouseover") then
        return HideReticleFrame(frame)
    end

    local plate =
        C_NamePlate and C_NamePlate.GetNamePlateForUnit and
        C_NamePlate.GetNamePlateForUnit("mouseover")

    if not plate or not plate.UnitFrame or not plate.UnitFrame.healthBar then
        return HideReticleFrame(frame)
    end

    local anchor = plate.UnitFrame.healthBar

    frame:ClearAllPoints()
    local globalOffsetY = Ret.GetMouseoverOffset() or 0
    frame:SetPoint(
        "CENTER",
        anchor,
        "CENTER",
        cfg.offsetX or 0,
        (cfg.offsetY or 0) + globalOffsetY
    )

    local dist = GetUnitDistanceYards("mouseover")
    frame.unit = "mouseover"
    frame.dist = dist

    local showText = HasOwnershipForUnit(guidOwner, "mouseover", "mouseover")

    if frame.distFS then
        if showText and dist then
            frame.distFS:SetFormattedText("%.0f yd", dist)
        elseif showText then
            frame.distFS:SetText("--")
        else
            frame.distFS:SetText("")
        end
    end

    local distScale = ComputeScale(dist, cfg)
    if distScale < 0.1 then
        distScale = 0.1
    end

    ApplySmoothScale(frame, distScale)
    frame:Show()
end

------------------------------------------------------
-- Driver
------------------------------------------------------

local driver
local updateThrottle = 0

function Ret.ForceUpdate()
    updateThrottle = 0
end

local function OnUpdate(self, elapsed)
    updateThrottle = updateThrottle + elapsed
    if updateThrottle < UPDATE_INTERVAL then
        return
    end
    updateThrottle = 0

    EnsureFrames()
    EnsureTheoBox()

    local guidOwner = BuildGuidOwner()
    local frontAngle= Ret.GetTheoFrontAngleRad()

    -- TARGET
    do
        local unit      = "target"
        local reticle   = Ret.frames.target
        local theoArrow = Ret.theoArrow.target
        local cfg       = Ret.GetReticleConfig("target")

        if IsValidUnit(unit) then
            local rel = select(1, GetRelativeAngleAndDistance(unit))
            if rel and abs(rel) > frontAngle then
                HideReticleFrame(reticle)
                UpdateTheoArrow(unit, "target", theoArrow, guidOwner)
            else
                HideTheoArrow(theoArrow)
                UpdateScreenReticle(unit, reticle, cfg, guidOwner)
            end
        else
            HideReticleFrame(reticle)
            HideTheoArrow(theoArrow)
        end
    end

    -- FOCUS
    do
        local unit      = "focus"
        local reticle   = Ret.frames.focus
        local theoArrow = Ret.theoArrow.focus
        local cfg       = Ret.GetReticleConfig("focus")

        if IsValidUnit(unit) then
            local rel = select(1, GetRelativeAngleAndDistance(unit))
            if rel and abs(rel) > frontAngle then
                HideReticleFrame(reticle)
                UpdateTheoArrow(unit, "focus", theoArrow, guidOwner)
            else
                HideTheoArrow(theoArrow)
                UpdateScreenReticle(unit, reticle, cfg, guidOwner)
            end
        else
            HideReticleFrame(reticle)
            HideTheoArrow(theoArrow)
        end
    end

    -- MOUSEOVER: always world reticle, no Theo box
    do
        local cfg = Ret.GetReticleConfig("mouseover")
        UpdateMouseoverIndicator(Ret.frames.mouseover, cfg, guidOwner)
    end
end

local function OnNameplateAdded(_, event, unit)
    if event ~= "NAME_PLATE_UNIT_ADDED" then
        return
    end

    local plate =
        C_NamePlate and C_NamePlate.GetNamePlateForUnit and
        C_NamePlate.GetNamePlateForUnit(unit)

    if not plate or not plate.UnitFrame then
        return
    end

    local uf = plate.UnitFrame
    if uf.healthBar then
        uf.healthBar:SetAlpha(0.0)
    end
    if uf.castBar then
        uf.castBar:SetAlpha(0.0)
    end
    if uf.name then
        uf.name:SetAlpha(0.0)
    end
end

function Ret.Init()
    if driver then
        return
    end

    EnsureNameplateCVars()
    EnsureFrames()
    EnsureTheoBox()

    driver = CreateFrame("Frame", "PE_AR_ReticleDriver", UIParent)
    driver:SetFrameStrata("LOW")
    driver:SetFrameLevel(0)
    driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    driver:SetScript("OnEvent", OnNameplateAdded)
    driver:SetScript("OnUpdate", OnUpdate)
end

------------------------------------------------------
-- Layout editor integration (SetEditorEnabled shim)
------------------------------------------------------

function Ret.SetEditorEnabled(flag)
    flag = not not flag

    if Ret.EditorUI and Ret.EditorUI.SetEnabled then
        Ret.EditorUI.SetEnabled(flag)
    end

    if Ret.theoBox then
        Ret.theoBox:SetAlpha(flag and 1 or 0)
    end

    if Ret.theoCenter then
        if flag then
            Ret.theoCenter:Show()
        else
            Ret.theoCenter:Hide()
        end
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
