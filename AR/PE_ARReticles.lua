-- ##################################################
-- AR/PE_ARReticles.lua
-- PersonaEngine AR: screen-space unit reticles
--
-- * Custom textures for target/focus/mouseover
-- * Nameplates used as invisible anchors only
-- * Per-reticle distance-based scaling (min/max)
-- * Distance text stays a constant size
-- * Uses LibRangeCheck-3.0 for distance where available
-- * Tunable min/max scale per reticle (SavedVariables)
-- * Tunable torso offset per creature type (SavedVariables)
-- * Simple in-game editor hooked to AR Layout Editor
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
-- 
-- Each reticle key has defaults; user overrides live in
-- PersonaEngineAR_DB.reticles[key].
------------------------------------------------------

local REF_PLATE_HEIGHT = 20      -- "normal mob" nameplate height
local UPDATE_INTERVAL  = 0.01    -- seconds

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
        offsetY    = 0,      -- base, we apply a plate-based drop below
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
        offsetY    = 10,     -- above head
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
        -- nuke all
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

-- Public: update a single field in DB and cache
function Ret.SetReticleField(key, field, value)
    if not key or not field then return end
    local defaults = RETICLE_DEFAULTS[key]
    if not defaults then return end

    local db = GetReticleDB()
    db[key] = db[key] or {}
    db[key][field] = value

    -- update cache immediately
    Ret.cfgCache[key] = MergeConfig(key)
end

------------------------------------------------------
-- Torso offset per creature type
--
-- Stored as:
--   torsoOffsets[creatureType][reticleKey] = offsetPixels
--
-- The offset is added on top of our base plate-based Y.
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

    local val = perType[reticleKey]
    if type(val) ~= "number" then
        return 0
    end
    return val
end

function Ret.SetTorsoOffset(reticleKey, creatureType, offset)
    if not reticleKey or not creatureType then
        return
    end

    local torsoDB = GetTorsoDB()
    torsoDB[creatureType] = torsoDB[creatureType] or {}
    torsoDB[creatureType][reticleKey] = offset

    -- immediate visual update
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

    -- Fallback: no LibRangeCheck → "no data"
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
        -- If range is unknown, use maxScale as a default.
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

    f.cfg    = cfg
    f.key    = key      -- "target", "focus", "mouseover"
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
    if Ret.frames.target and Ret.frames.focus and Ret.frames.mouseover then
        return
    end

    Ret.frames.target    = Ret.frames.target    or CreateReticleFrame("PE_AR_TargetReticle",      "target")
    Ret.frames.focus     = Ret.frames.focus     or CreateReticleFrame("PE_AR_FocusReticle",       "focus")
    Ret.frames.mouseover = Ret.frames.mouseover or CreateReticleFrame("PE_AR_MouseoverIndicator", "mouseover")
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

local function UpdateReticleForUnit(unit, frame)
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
        -- Off-screen / no anchor → future directional-pointer hook.
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

    -- Base Y: "torso-ish" drop from plate center
    local baseYOffset = (cfg.offsetY or 0) - (plateH * 5)

    -- Per-creature-type torso adjustment
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

local function UpdateMouseoverIndicator(frame)
    if not frame then return end

    local cfg = Ret.GetReticleConfig(frame.key)
    if not cfg then
        frame:Hide()
        frame.anchor = nil
        return
    end
    frame.cfg = cfg

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

    local plateH = anchor:GetHeight() or REF_PLATE_HEIGHT
    local sizeScaleRaw = plateH / REF_PLATE_HEIGHT
    local sizeScale    = math.min(math.max(sizeScaleRaw, 0.4), 1.6)

    local baseYOffset = (cfg.offsetY or 0) + (plateH * 0.3)
    local torsoOffset = Ret.GetTorsoOffset(frame.key, "mouseover") or 0

    frame.anchor = anchor
    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint(
        "CENTER",
        anchor,
        "CENTER",
        (cfg.offsetX or 0),
        baseYOffset + torsoOffset
    )

    local dist = GetUnitDistanceYards("mouseover")
    frame.dist = dist

    if frame.distFS then
        if dist then
            frame.distFS:SetFormattedText("%.0f yd", dist)
        else
            frame.distFS:SetText("--")
        end
    end

    local distScale = ComputeScale(dist, cfg)
    if distScale < 0.1 then
        distScale = 0.1
    end

    local finalScale = distScale * sizeScale
    frame:SetScale(finalScale)

    if frame.distFS then
        frame.distFS:SetScale(1 / finalScale)
    end

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

    if Ret.frames.target then
        UpdateReticleForUnit("target", Ret.frames.target)
    end
    if Ret.frames.focus then
        UpdateReticleForUnit("focus", Ret.frames.focus)
    end
    if Ret.frames.mouseover then
        UpdateMouseoverIndicator(Ret.frames.mouseover)
    end
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
-- Simple AR HUD "Reticle Editor" UI
--
-- This is toggled by the AR Layout Editor so you get
-- one combined "AR HUD edit" mode:
--   * Min/max scale per reticle (sliders)
--   * Torso offset per creature type (slider, uses current target)
------------------------------------------------------

local EditorUI = {}
Ret.EditorUI = EditorUI

local function CreateSlider(parent, labelText, minVal, maxVal, step, width)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step or 0.01)
    slider:SetObeyStepOnDrag(true)
    slider:SetOrientation("HORIZONTAL")
    slider:SetWidth(width or 140)

    _G[slider:GetName() .. "Low"]    :SetText(string.format("%.2f", minVal))
    _G[slider:GetName() .. "High"]   :SetText(string.format("%.2f", maxVal))
    _G[slider:GetName() .. "Text"]   :SetText(labelText or "")

    return slider
end

local function CreateReticleEditorFrame()
    if EditorUI.frame then
        return
    end

    local f = CreateFrame("Frame", "PE_AR_ReticleEditor", UIParent, "BackdropTemplate")
    f:SetSize(360, 260)
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

    -- Rows for each reticle
    local rowY = -40
    EditorUI.rows = {}

    local function MakeRow(key)
        local cfg = RETICLE_DEFAULTS[key]
        if not cfg then return end

        local row = {}
        row.key = key

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", f, "TOPLEFT", 10, rowY)
        label:SetText(cfg.display or key)
        row.label = label

        local minSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
        minSlider:SetMinMaxValues(0.01, 1.00)
        minSlider:SetValueStep(0.01)
        minSlider:SetObeyStepOnDrag(true)
        minSlider:SetOrientation("HORIZONTAL")
        minSlider:SetWidth(140)
        minSlider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        _G[minSlider:GetName() .. "Low"]:SetText("0.01")
        _G[minSlider:GetName() .. "High"]:SetText("1.00")
        _G[minSlider:GetName() .. "Text"]:SetText("Min Scale")
        row.minSlider = minSlider

        local maxSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
        maxSlider:SetMinMaxValues(0.01, 1.50)
        maxSlider:SetValueStep(0.01)
        maxSlider:SetObeyStepOnDrag(true)
        maxSlider:SetOrientation("HORIZONTAL")
        maxSlider:SetWidth(140)
        maxSlider:SetPoint("TOPLEFT", minSlider, "BOTTOMLEFT", 0, -10)
        _G[maxSlider:GetName() .. "Low"]:SetText("0.01")
        _G[maxSlider:GetName() .. "High"]:SetText("1.50")
        _G[maxSlider:GetName() .. "Text"]:SetText("Max Scale")
        row.maxSlider = maxSlider

        EditorUI.rows[key] = row
        rowY = rowY - 60
    end

    MakeRow("target")
    MakeRow("focus")
    MakeRow("mouseover")

    -- Torso offset controls (per creature type, using current target)
    local torsoLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    torsoLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, rowY)
    torsoLabel:SetText("Torso offset (current target creature type)")
    EditorUI.torsoLabel = torsoLabel

    local torsoSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    torsoSlider:SetMinMaxValues(-200, 200)
    torsoSlider:SetValueStep(1)
    torsoSlider:SetObeyStepOnDrag(true)
    torsoSlider:SetOrientation("HORIZONTAL")
    torsoSlider:SetWidth(260)
    torsoSlider:SetPoint("TOPLEFT", torsoLabel, "BOTTOMLEFT", 0, -6)
    _G[torsoSlider:GetName() .. "Low"]:SetText("-200")
    _G[torsoSlider:GetName() .. "High"]:SetText("200")
    _G[torsoSlider:GetName() .. "Text"]:SetText("Target Reticle Torso Offset (px)")
    EditorUI.torsoSlider = torsoSlider

    -- Current creature type text
    local torsoType = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    torsoType:SetPoint("TOPLEFT", torsoSlider, "BOTTOMLEFT", 0, -4)
    torsoType:SetText("No target")
    EditorUI.torsoType = torsoType

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    EditorUI.frame = f

    --------------------------------------------------
    -- Slider wiring
    --------------------------------------------------

    local function RefreshScaleSliders()
        for key, row in pairs(EditorUI.rows) do
            local cfg = Ret.GetReticleConfig(key)
            if cfg then
                row.minSlider:SetValue(cfg.minScale or 0.01)
                row.maxSlider:SetValue(cfg.maxScale or 1.00)
            end
        end
    end

    EditorUI.RefreshScaleSliders = RefreshScaleSliders

    for key, row in pairs(EditorUI.rows) do
        row.minSlider:SetScript("OnValueChanged", function(self, val)
            local cfg = Ret.GetReticleConfig(key)
            local maxScale = cfg and cfg.maxScale or 1.0
            -- Ensure min <= max
            if val > maxScale then
                val = maxScale
                self:SetValue(val)
            end
            Ret.SetReticleField(key, "minScale", val)
        end)

        row.maxSlider:SetScript("OnValueChanged", function(self, val)
            local cfg = Ret.GetReticleConfig(key)
            local minScale = cfg and cfg.minScale or 0.01
            if val < minScale then
                val = minScale
                self:SetValue(val)
            end
            Ret.SetReticleField(key, "maxScale", val)
        end)
    end

    local function RefreshTorsoControls()
        local unit = "target"
        local creatureType = GetCreatureType(unit)
        if not creatureType then
            EditorUI.torsoType:SetText("No target")
            EditorUI.torsoSlider:SetEnabled(false)
            EditorUI.torsoSlider:SetValue(0)
            return
        end

        EditorUI.torsoType:SetText("Creature type: " .. creatureType)

        local current = Ret.GetTorsoOffset("target", unit) or 0
        EditorUI.torsoSlider:SetEnabled(true)
        EditorUI.torsoSlider:SetValue(current)
    end

    EditorUI.RefreshTorsoControls = RefreshTorsoControls

    torsoSlider:SetScript("OnValueChanged", function(self, val)
        local unit = "target"
        local creatureType = GetCreatureType(unit)
        if not creatureType then
            return
        end
        Ret.SetTorsoOffset("target", creatureType, val)
    end)

    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            if f:IsShown() then
                EditorUI.RefreshTorsoControls()
            end
        end
    end)

    f:SetScript("OnShow", function()
        EditorUI.RefreshScaleSliders()
        EditorUI.RefreshTorsoControls()
    end)
end

function Ret.SetEditorEnabled(flag)
    flag = not not flag
    CreateReticleEditorFrame()

    if flag then
        EditorUI.frame:Show()
        EditorUI.RefreshScaleSliders()
        EditorUI.RefreshTorsoControls()
    else
        EditorUI.frame:Hide()
    end
end

------------------------------------------------------
-- Slash (optional manual toggle)
------------------------------------------------------

SLASH_PE_ARRETICLE1 = "/pearreticle"
SlashCmdList["PE_ARRETICLE"] = function()
    CreateReticleEditorFrame()
    if EditorUI.frame:IsShown() then
        EditorUI.frame:Hide()
    else
        EditorUI.frame:Show()
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
