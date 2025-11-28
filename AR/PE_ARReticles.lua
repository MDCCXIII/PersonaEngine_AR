-- ##################################################
-- AR/PE_ARReticles.lua
-- PersonaEngine AR: screen-space unit reticles
--
-- * Custom textures for target/focus/mouseover
-- * Nameplates used as invisible anchors only
-- * Per-reticle distance-based scaling (min/max)
-- * Smooth scale animation over time
-- * Distance text stays a constant size
-- * Uses LibRangeCheck-3.0 for distance where available
-- * Tunable min/max scale per reticle (SavedVariables)
-- * Tunable torso offset per creature type (SavedVariables)
-- * Global mouseover height offset (SavedVariables)
-- * Editor UI is moved to AR/PE_ARReticleEditor.lua
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

------------------------------------------------------
-- LibRangeCheck (soft dependency)
------------------------------------------------------

local RangeCheck = nil
if _G.LibStub then
    RangeCheck = _G.LibStub("LibRangeCheck-3.0", true)
end

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
-- Defaults / Tunables
------------------------------------------------------

local REF_PLATE_HEIGHT = 20      -- "normal mob" nameplate height
local UPDATE_INTERVAL  = 0.01    -- seconds
local SCALE_SMOOTHING  = 0.25    -- 0..1, fraction of delta per update

local OWNER_PRIORITY = {
    mouseover = 3,  -- highest priority: what you’re actively mousing
    target    = 2,
    focus     = 1,  -- lowest priority
}

local RETICLE_DEFAULTS = {
    target = {
        key        = "target",
        display    = "Target",
        baseWidth  = 256,
        baseHeight = 128,
        near       = 5,      -- yards
        far        = 45,     -- yards
        minScale   = 0.01,   -- at far
        maxScale   = 0.30,   -- at near (close-range size)
        texture    = TEXTURES.targetCircle,
        offsetX    = 0,
        offsetY    = 0,      -- base; we apply a plate-based drop below
    },
    focus = {
        key        = "focus",
        display    = "Focus",
        baseWidth  = 256,
        baseHeight = 128,
        near       = 5,
        far        = 45,
        minScale   = 0.01,
        maxScale   = 0.30,
        texture    = TEXTURES.focusCircle,
        offsetX    = 0,
        offsetY    = 0,
    },
    mouseover = {
        key        = "mouseover",
        display    = "Mouseover",
        baseWidth  = 16,
        baseHeight = 16,
        near       = 5,
        far        = 350,    -- design max; engine limit is lower
        minScale   = 0.20,
        maxScale   = 0.90,
        texture    = TEXTURES.mouseover,
        offsetX    = 0,
        offsetY    = 10,     -- base; we add global offset on top
    },
}

------------------------------------------------------
-- SavedVariables helpers
------------------------------------------------------

local function GetARRoot()
    _G.PersonaEngineAR_DB = _G.PersonaEngineAR_DB or {}
    return _G.PersonaEngineAR_DB
end

local function GetReticleDB()
    local root = GetARRoot()
    root.reticles = root.reticles or {}
    return root.reticles
end

local function GetTorsoDB()
    local root = GetARRoot()
    root.torsoOffsets = root.torsoOffsets or {}
    return root.torsoOffsets
end

-- Global mouseover offset (not per creature type)
local function GetMouseoverRoot()
    local root = GetARRoot()
    if root.mouseoverOffset == nil then
        root.mouseoverOffset = 0
    end
    return root
end

function Ret.GetMouseoverOffset()
    local root = GetMouseoverRoot()
    return root.mouseoverOffset or 0
end

function Ret.SetMouseoverOffset(offset)
    local root = GetMouseoverRoot()
    root.mouseoverOffset = offset or 0
    Ret.ForceUpdate()
end

------------------------------------------------------
-- Config cache (defaults + DB overrides)
------------------------------------------------------

Ret.cfgCache = Ret.cfgCache or {}

local function CopyTable(src)
    local dest = {}
    for k, v in pairs(src) do
        dest[k] = v
    end
    return dest
end

local function MergeConfig(key)
    local defaults = RETICLE_DEFAULTS[key]
    if not defaults then
        return nil
    end

    local db      = GetReticleDB()
    local saved   = db[key]
    local cfg     = CopyTable(defaults)

    if type(saved) == "table" then
        for k, v in pairs(saved) do
            cfg[k] = v
        end
    end

    -- Sanity
    if not cfg.baseWidth or cfg.baseWidth <= 0 then
        cfg.baseWidth = defaults.baseWidth or 64
    end
    if not cfg.baseHeight or cfg.baseHeight <= 0 then
        cfg.baseHeight = defaults.baseHeight or 64
    end
    if not cfg.near then
        cfg.near = defaults.near or 0
    end
    if not cfg.far or cfg.far <= cfg.near then
        cfg.far = (defaults.far or (cfg.near + 1))
    end
    if not cfg.minScale or cfg.minScale <= 0 then
        cfg.minScale = defaults.minScale or 0.5
    end
    if not cfg.maxScale or cfg.maxScale <= 0 then
        cfg.maxScale = defaults.maxScale or 1.0
    end

    return cfg
end

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
    if not key then return nil end
    if not Ret.cfgCache[key] then
        Ret.cfgCache[key] = MergeConfig(key)
    end
    return Ret.cfgCache[key]
end

function Ret.SetReticleField(key, field, value)
    if not key or not field then return end
    local defaults = RETICLE_DEFAULTS[key]
    if not defaults then return end

    local db = GetReticleDB()
    db[key] = db[key] or {}
    db[key][field] = value

    Ret.cfgCache[key] = MergeConfig(key)
end

------------------------------------------------------
-- Torso offset per creature type
------------------------------------------------------

local function GetCreatureType(unit)
    if not unit or not UnitExists(unit) then
        return nil
    end
    return UnitCreatureType(unit) or "UNKNOWN"
end

function Ret.GetTorsoOffset(reticleKey, unit)
    local creatureType = GetCreatureType(unit)
    if not creatureType then
        return 0
    end

    local torsoDB = GetTorsoDB()
    local perType = torsoDB[creatureType]
    if not perType then
        return 0
    end

    -- Shared offset for this creature type, fallback to any legacy per-key values.
    local val = perType.shared
            or perType.target
            or perType.focus
            or perType[reticleKey]

    if type(val) ~= "number" then
        return 0
    end
    return val
end


function Ret.SetTorsoOffset(reticleKey, creatureType, offset)
    if not creatureType then
        return
    end

    local torsoDB = GetTorsoDB()
    torsoDB[creatureType] = torsoDB[creatureType] or {}

    -- Store as shared so target & focus both use it.
    torsoDB[creatureType].shared = offset

    Ret.ForceUpdate()
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
    return UnitExists(unit) and not UnitIsDeadOrGhost(unit)
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
            return (minR + maxR) / 2
        end
        return minR or maxR
    end

    return nil
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
    end

    local t = (dist - near) / (far - near)
    return maxScale + (minScale - maxScale) * t
end

------------------------------------------------------
-- Nameplate helpers (visual stripping only)
------------------------------------------------------

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

local function EnsureNameplateCVars()
    if not (GetCVar and SetCVar) then return end

    if tonumber(GetCVar("nameplateShowEnemies") or "0") == 0 then
        SetCVar("nameplateShowEnemies", 1)
    end
    if tonumber(GetCVar("nameplateShowAll") or "0") == 0 then
        SetCVar("nameplateShowAll", 1)
    end
    if tonumber(GetCVar("nameplateShowSelf") or "1") ~= 0 then
        SetCVar("nameplateShowSelf", 0)
    end
end

------------------------------------------------------
-- Reticle frame factories
------------------------------------------------------

local function CreateReticleFrame(name, key)
    local cfg = Ret.GetReticleConfig(key)
    if not cfg then
        return nil
    end

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

    f.cfg          = cfg
    f.key          = key      -- "target", "focus", "mouseover"
    f.unit         = nil
    f.anchor       = nil
    f.dist         = nil
    f._currentScale = nil

    f:Hide()
    return f
end

------------------------------------------------------
-- State
------------------------------------------------------

Ret.frames = Ret.frames or {}

local function EnsureFrames()
    if Ret.frames.target and Ret.frames.focus and Ret.frames.mouseover then
        return
    end

    Ret.frames.target    = Ret.frames.target    or CreateReticleFrame("PE_AR_TargetReticle",      "target")
    Ret.frames.focus     = Ret.frames.focus     or CreateReticleFrame("PE_AR_FocusReticle",       "focus")
    Ret.frames.mouseover = Ret.frames.mouseover or CreateReticleFrame("PE_AR_MouseoverIndicator", "mouseover")
end

------------------------------------------------------
-- Core update logic (with smooth scaling)
------------------------------------------------------

local function HideReticleFrame(frame)
    if not frame then return end
    frame.unit         = nil
    frame.anchor       = nil
    frame.dist         = nil
    frame._currentScale = nil

    if frame.distFS then
        frame.distFS:SetText("")
        frame.distFS:SetScale(1)
    end

    frame:Hide()
end

local function ApplySmoothScale(frame, targetScale)
    if targetScale <= 0 then
        targetScale = 0.01
    end

    local current = frame._currentScale or targetScale
    local newScale = current + (targetScale - current) * SCALE_SMOOTHING

    frame._currentScale = newScale
    frame:SetScale(newScale)

    if frame.distFS then
        frame.distFS:SetScale(1 / newScale)
    end
end

local function UpdateReticleForUnit(unit, frame, guidOwner)
    if not frame then return end

    local cfg = Ret.GetReticleConfig(frame.key)
    if not cfg then
        HideReticleFrame(frame)
        return
    end
    frame.cfg = cfg

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
        HideReticleFrame(frame)
        return
    end

    frame.unit   = unit
    frame.anchor = anchor

    local plateH = anchor:GetHeight() or 0
    if plateH <= 0 then
        plateH = REF_PLATE_HEIGHT
    end

    local sizeScaleRaw = plateH / REF_PLATE_HEIGHT
    local sizeScale    = math.min(math.max(sizeScaleRaw, 0.4), 1.6)

    local baseYOffset = (cfg.offsetY or 0) - (plateH * 5)
    local torsoOffset = Ret.GetTorsoOffset(frame.key, unit) or 0

    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint(
        "CENTER",
        anchor,
        "CENTER",
        (cfg.offsetX or 0),
        baseYOffset + torsoOffset
    )

        -- Distance label (only one owner per unit GUID)
    local dist = GetUnitDistanceYards(unit)
    frame.dist = dist

    local canShow = true
    if guidOwner and UnitExists(unit) then
        local guid = UnitGUID(unit)
        if guid then
            local owner = guidOwner[guid]
            if owner and owner.key ~= frame.key then
                canShow = false
            end
        end
    end

    if frame.distFS then
        if canShow and dist then
            frame.distFS:SetFormattedText("%.0f yd", dist)
        elseif canShow and not dist then
            frame.distFS:SetText("--")
        else
            -- Another reticle “owns” this unit → no text here
            frame.distFS:SetText("")
        end
    end

    local distScale = ComputeScale(dist, cfg)
    if distScale < 0.1 then
        distScale = 0.1
    end

    local targetScale = distScale * sizeScale
    ApplySmoothScale(frame, targetScale)

    frame:Show()
end

local function UpdateMouseoverIndicator(frame, guidOwner)
    if not frame then return end

    local cfg = Ret.GetReticleConfig(frame.key)
    if not cfg then
        HideReticleFrame(frame)
        return
    end
    frame.cfg = cfg

    if not IsAREnabled() then
        HideReticleFrame(frame)
        return
    end

    if not UnitExists("mouseover") or UnitIsDeadOrGhost("mouseover") then
        HideReticleFrame(frame)
        return
    end

    local anchor = GetUnitAnchor("mouseover")
    if not anchor or not anchor:IsVisible() then
        HideReticleFrame(frame)
        return
    end

    -- We still use plate height to shape scaling, but NOT for vertical offset.
    local plateH       = anchor:GetHeight() or REF_PLATE_HEIGHT
    local sizeScaleRaw = plateH / REF_PLATE_HEIGHT
    local sizeScale    = math.min(math.max(sizeScaleRaw, 0.4), 1.6)

    -- Fixed offset over the nameplate: config + per-creature torso + global slider.
    local baseYOffset  = (cfg.offsetY or 0)
    local torsoOffset  = Ret.GetTorsoOffset(frame.key, "mouseover") or 0
    local globalOffset = Ret.GetMouseoverOffset() or 0

    frame.anchor = anchor
    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint(
        "CENTER",
        anchor,
        "CENTER",
        (cfg.offsetX or 0),
        baseYOffset + torsoOffset + globalOffset
    )

    -- Distance & label ownership
    local dist = GetUnitDistanceYards("mouseover")
    frame.dist = dist

    local canShow = true
    if guidOwner and UnitExists("mouseover") then
        local guid = UnitGUID("mouseover")
        if guid then
            local owner = guidOwner[guid]
            if owner and owner.key ~= frame.key then
                canShow = false
            end
        end
    end

    if frame.distFS then
        if canShow and dist then
            frame.distFS:SetFormattedText("%.0f yd", dist)
        elseif canShow and not dist then
            frame.distFS:SetText("--")
        else
            frame.distFS:SetText("")
        end
    end

    -- Smooth scaling with distance, but this no longer affects offset.
    local distScale = ComputeScale(dist, cfg)
    if distScale < 0.1 then
        distScale = 0.1
    end

    local targetScale = distScale * sizeScale
    ApplySmoothScale(frame, targetScale)

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

    -- Decide which reticle "owns" the distance text for each unit GUID.
    local guidOwner = {}

    local function claim(unit, key)
        if not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid then return end

        local prio = OWNER_PRIORITY[key] or 0
        local current = guidOwner[guid]
        if not current or prio > current.prio then
            guidOwner[guid] = { key = key, prio = prio }
        end
    end

    -- Priority: mouseover > target > focus
    claim("mouseover", "mouseover")
    claim("target",    "target")
    claim("focus",     "focus")

    local tCfg = Ret.GetReticleConfig("target")
    local fCfg = Ret.GetReticleConfig("focus")
    local mCfg = Ret.GetReticleConfig("mouseover")

    UpdateReticleForUnit("target", Ret.frames.target, tCfg, guidOwner)
    UpdateReticleForUnit("focus",  Ret.frames.focus,  fCfg, guidOwner)
    UpdateMouseoverIndicator(Ret.frames.mouseover, mCfg, guidOwner)
end


local function OnNameplateAdded(_, event, unit)
    if event ~= "NAME_PLATE_UNIT_ADDED" then return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    HideNameplateArt(plate)
    MuteNameplate(plate)
end

function Ret.Init()
    if driver then
        return
    end

    EnsureNameplateCVars()
    EnsureFrames()

    driver = CreateFrame("Frame", "PE_AR_ReticleDriver", UIParent)
    driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    driver:SetScript("OnEvent", OnNameplateAdded)
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
-- Editor integration stub (real UI in PE_ARReticleEditor.lua)
------------------------------------------------------

function Ret.SetEditorEnabled(flag)
    flag = not not flag
    if AR and AR.ReticleEditor and AR.ReticleEditor.SetEnabled then
        AR.ReticleEditor.SetEnabled(flag)
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
