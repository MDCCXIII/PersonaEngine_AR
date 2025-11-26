-- ##################################################
-- AR/UI/PE_UIARTargetPanel.lua
-- PersonaEngine: Screen-space Target Info Panel
-- Tall dossier layout:
--   Name/level on top
--   3D model full-width in the middle
--   HP/Power bars + cast line underneath.
-- With per-unit-type "scan pose" profiles.
-- ##################################################

local MODULE = "AR Target Panel"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.TargetPanel = AR.TargetPanel or {}
local Panel = AR.TargetPanel

------------------------------------------------------
-- Utilities
------------------------------------------------------

local function Clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function ColorForReaction(unit)
    if UnitIsEnemy("player", unit) then
        -- Hostile: red/orange military alert
        return 1.0, 0.25, 0.2
    elseif UnitIsFriend("player", unit) then
        -- Friendly: Copporclang cyan
        return 0.2, 1.0, 0.7
    else
        -- Neutral: orange
        return 1.0, 0.8, 0.25
    end
end

local function ColorForPowerType(unit)
    local pType = select(2, UnitPowerType(unit)) -- "MANA", "RAGE", etc.
    if pType == "MANA" then
        return 0.2, 0.55, 1.0
    elseif pType == "RAGE" or pType == "FURY" then
        return 1.0, 0.25, 0.25
    elseif pType == "ENERGY" then
        return 1.0, 0.9, 0.3
    elseif pType == "FOCUS" then
        return 1.0, 0.55, 0.2
    else
        -- Exotic resources: teal-ish
        return 0.1, 0.95, 0.8
    end
end

local function BuildLevelLine(unit)
    local level    = UnitLevel(unit) or -1
    local classif  = UnitClassification(unit) or "normal"
    local isPlayer = UnitIsPlayer(unit)

    local pieces = {}

    if level <= 0 then
        table.insert(pieces, "Lv ??")
    else
        table.insert(pieces, string.format("Lv %d", level))
    end

    if isPlayer then
        local race  = UnitRace(unit) or "Unknown"
        local class = UnitClass(unit) or "Adventurer"
        table.insert(pieces, race)
        table.insert(pieces, class)
    else
        local ctype = UnitCreatureType(unit) or "Creature"
        if classif == "worldboss" then
            table.insert(pieces, "WORLD BOSS")
        elseif classif == "elite" then
            table.insert(pieces, "ELITE")
        elseif classif == "rareelite" then
            table.insert(pieces, "RARE ELITE")
        elseif classif == "rare" then
            table.insert(pieces, "RARE")
        end
        table.insert(pieces, ctype)
    end

    local faction = UnitFactionGroup(unit)
    if faction then
        table.insert(pieces, faction)
    end

    return table.concat(pieces, " • ")
end

local function BuildCastLine(unit)
    local name, _, _, startTime, endTime, _, _, notInterruptible = UnitCastingInfo(unit)
    if not name then
        name, _, _, startTime, endTime, _, notInterruptible = UnitChannelInfo(unit)
    end
    if not name then
        return ""
    end

    local dur = (endTime and startTime) and (endTime - startTime) / 1000 or 0
    local flag = notInterruptible and "|cffff4040LOCKED|r" or "|cff20ff50INTERRUPT|r"

    return string.format("CAST: %s  (%.1fs)  [%s]", name, dur, flag)
end

------------------------------------------------------
-- Scan pose profiles
------------------------------------------------------
-- You can tweak these per unit type. All angles in radians.

Panel.PoseProfiles = {
    DEFAULT = {
        facing      = math.rad(15),   -- slight turn
        pitch       = math.rad(2),    -- tiny downward tilt
        camScale    = 1.05,
        offsetZ     = -0.08,
        portraitZoom = 0,
    },
    PLAYER = {
        facing      = math.rad(10),
        pitch       = math.rad(1),
        camScale    = 1.10,
        offsetZ     = -0.08,
        portraitZoom = 0,
    },
    ELITE = {
        facing      = math.rad(5),
        pitch       = math.rad(-2),   -- slightly from below: imposing
        camScale    = 1.20,
        offsetZ     = -0.02,
        portraitZoom = 0,
    },
    WORLD_BOSS = {
        facing      = math.rad(0),
        pitch       = math.rad(-6),
        camScale    = 1.40,
        offsetZ     = -0.05,
        portraitZoom = 0,
    },
    BEAST = {
        facing      = math.rad(20),
        pitch       = math.rad(-3),
        camScale    = 1.25,
        offsetZ     = -0.02,
        portraitZoom = 0,
    },
    MECHANICAL = {
        facing      = math.rad(-10),
        pitch       = math.rad(0),
        camScale    = 1.15,
        offsetZ     = -0.05,
        portraitZoom = 0,
    },
}

local function GetPoseProfileForUnit(unit)
    local profiles = Panel.PoseProfiles
    if not profiles then return nil end

    if UnitIsPlayer(unit) then
        return profiles.PLAYER or profiles.DEFAULT
    end

    local classif = UnitClassification(unit)
    if classif == "worldboss" then
        return profiles.WORLD_BOSS or profiles.ELITE or profiles.DEFAULT
    elseif classif == "elite" or classif == "rareelite" then
        return profiles.ELITE or profiles.DEFAULT
    end

    local ctype = UnitCreatureType(unit) or ""
    -- These comparisons are localized in theory, but this is fine for enUS.
    if ctype == "Beast" then
        return profiles.BEAST or profiles.DEFAULT
    elseif ctype == "Mechanical" then
        return profiles.MECHANICAL or profiles.DEFAULT
    end

    return profiles.DEFAULT
end

local function ApplyModelPose(unit, model)
    if not model or not unit then return end

    local profile = GetPoseProfileForUnit(unit)
    if not profile then return end

    -- Basic camera
    if model.SetPortraitZoom then
        model:SetPortraitZoom(profile.portraitZoom or 0)
    end
    if model.SetCamDistanceScale then
        model:SetCamDistanceScale(profile.camScale or 1.1)
    end
    if model.SetPosition then
        model:SetPosition(0, 0, profile.offsetZ or 0)
    end

    -- Orientation
    if profile.facing and model.SetFacing then
        model:SetFacing(profile.facing)
    elseif profile.facing and model.SetRotation then
        -- Fallback to rotation if Facing isn't there
        model:SetRotation(profile.facing)
    end

    if profile.pitch and model.SetPitch then
        model:SetPitch(profile.pitch)
    end

    -- Freeze animation at idle frame if API allows it.
    if model.SetAnimation then
        model:SetAnimation(0) -- idle loop
    end
    if model.SetPaused then
        model:SetPaused(true) -- freeze on a frame if supported
    end
end

------------------------------------------------------
-- Frame creation
------------------------------------------------------

local function CreatePanelFrame()
    if Panel.frame then
        return Panel.frame
    end

    local f = CreateFrame("Frame", "PE_AR_TargetPanel", UIParent)
    Panel.frame = f
	
	-- Copporclang visor: ignore global UI fades
    f:SetIgnoreParentAlpha(true)
    f:SetIgnoreParentScale(true)

    -- Taller dossier-style card
    f:SetSize(260, 300)
    f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0)
    f:SetAlpha(0)
    f:EnableMouse(false)

    --------------------------------------------------
    -- Background + lattice grid
    --------------------------------------------------
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    Panel.bg = bg

    local inner = f:CreateTexture(nil, "BACKGROUND")
    inner:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.0, 0.4, 0.4, 0.35)
    Panel.inner = inner

    Panel.gridLines = Panel.gridLines or {}
    local gridCols = 6
    for i = 1, gridCols do
        local line = Panel.gridLines[i]
        if not line then
            line = f:CreateTexture(nil, "BACKGROUND")
            Panel.gridLines[i] = line
        end
        line:SetColorTexture(0.1, 0.9, 0.8, 0.18)
        local x = (i / (gridCols + 1)) * (f:GetWidth())
        line:SetPoint("TOPLEFT", f, "TOPLEFT", x, -2)
        line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 2)
        line:SetWidth(1)
    end

    Panel.gridRows = Panel.gridRows or {}
    local gridRows = 5
    for i = 1, gridRows do
        local line = Panel.gridRows[i]
        if not line then
            line = f:CreateTexture(nil, "BACKGROUND")
            Panel.gridRows[i] = line
        end
        line:SetColorTexture(0.1, 0.9, 0.8, 0.14)
        local y = -(i / (gridRows + 1)) * (f:GetHeight())
        line:SetPoint("LEFT", f, "LEFT", 2, y)
        line:SetPoint("RIGHT", f, "RIGHT", -2, y)
        line:SetHeight(1)
    end

    --------------------------------------------------
    -- Vector frame / corners / accent
    --------------------------------------------------

    local accent = f:CreateTexture(nil, "BORDER")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    accent:SetColorTexture(0.2, 1.0, 0.7, 0.95)
    Panel.accent = accent

    local topLine = f:CreateTexture(nil, "BORDER")
    topLine:SetColorTexture(0.7, 0.9, 1.0, 0.8)
    topLine:SetHeight(1)
    topLine:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -1)
    topLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -1)
    Panel.topLine = topLine

    local bottomLine = f:CreateTexture(nil, "BORDER")
    bottomLine:SetColorTexture(0.7, 0.9, 1.0, 0.6)
    bottomLine:SetHeight(1)
    bottomLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 1)
    bottomLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 1)
    Panel.bottomLine = bottomLine

    local tlCorner = f:CreateTexture(nil, "BORDER")
    tlCorner:SetColorTexture(0.8, 0.95, 1.0, 0.9)
    tlCorner:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    tlCorner:SetSize(20, 2)
    Panel.tlCorner = tlCorner

    local tlCornerV = f:CreateTexture(nil, "BORDER")
    tlCornerV:SetColorTexture(0.8, 0.95, 1.0, 0.9)
    tlCornerV:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    tlCornerV:SetSize(2, 14)
    Panel.tlCornerV = tlCornerV

    local brCorner = f:CreateTexture(nil, "BORDER")
    brCorner:SetColorTexture(0.8, 0.95, 1.0, 0.9)
    brCorner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    brCorner:SetSize(20, 2)
    Panel.brCorner = brCorner

    local brCornerV = f:CreateTexture(nil, "BORDER")
    brCornerV:SetColorTexture(0.8, 0.95, 1.0, 0.9)
    brCornerV:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    brCornerV:SetSize(2, 14)
    Panel.brCornerV = brCornerV

    --------------------------------------------------
    -- Scanline overlay (animated)
    --------------------------------------------------
    local scan = f:CreateTexture(nil, "ARTWORK")
    scan:SetColorTexture(0.9, 0.95, 1.0, 0.22)
    scan:SetPoint("LEFT", f, "LEFT", 2, 0)
    scan:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    scan:SetHeight(14)
    scan:SetBlendMode("ADD")
    Panel.scanline = scan
    Panel.scanOffset = 0

    --------------------------------------------------
    -- 3D model preview (middle, full width)
    --------------------------------------------------

    -- Name / level text above the model
    local nameFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Med1")
    nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    nameFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText("")
    Panel.nameFS = nameFS

    local levelFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    levelFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    levelFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    levelFS:SetJustifyH("LEFT")
    levelFS:SetText("")
    Panel.levelFS = levelFS

    -- Model frame spans almost full width under level line
    local modelFrame = CreateFrame("Frame", "PE_AR_TargetModelFrame", f)
    modelFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -40)
    modelFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -40)
    modelFrame:SetHeight(220)
    Panel.modelFrame = modelFrame

    local modelBG = modelFrame:CreateTexture(nil, "BACKGROUND")
    modelBG:SetAllPoints()
    modelBG:SetColorTexture(0, 0, 0, 0.6)
    Panel.modelBG = modelBG

    local model = CreateFrame("PlayerModel", "PE_AR_TargetModel", modelFrame)
    model:SetAllPoints()
    model:SetAlpha(0)
    Panel.model = model

    -- Thin cyan bracket around model
    local mTop = modelFrame:CreateTexture(nil, "BORDER")
    mTop:SetColorTexture(0.7, 0.95, 1.0, 0.8)
    mTop:SetHeight(1)
    mTop:SetPoint("TOPLEFT", modelFrame, "TOPLEFT", -2, 1)
    mTop:SetPoint("TOPRIGHT", modelFrame, "TOPRIGHT", 2, 1)

    local mBottom = modelFrame:CreateTexture(nil, "BORDER")
    mBottom:SetColorTexture(0.7, 0.95, 1.0, 0.8)
    mBottom:SetHeight(1)
    mBottom:SetPoint("BOTTOMLEFT", modelFrame, "BOTTOMLEFT", -2, -1)
    mBottom:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", 2, -1)

    local mLeft = modelFrame:CreateTexture(nil, "BORDER")
    mLeft:SetColorTexture(0.7, 0.95, 1.0, 0.8)
    mLeft:SetWidth(1)
    mLeft:SetPoint("TOPLEFT", modelFrame, "TOPLEFT", -1, 2)
    mLeft:SetPoint("BOTTOMLEFT", modelFrame, "BOTTOMLEFT", -1, -2)

    local mRight = modelFrame:CreateTexture(nil, "BORDER")
    mRight:SetColorTexture(0.7, 0.95, 1.0, 0.8)
    mRight:SetWidth(1)
    mRight:SetPoint("TOPRIGHT", modelFrame, "TOPRIGHT", 1, 2)
    mRight:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", 1, -2)

    --------------------------------------------------
    -- OnUpdate: scanline only
    --------------------------------------------------
    f:SetScript("OnUpdate", function(self, elapsed)
        Panel.scanOffset = (Panel.scanOffset or 0) + elapsed * 25
        local h = self:GetHeight()
        if Panel.scanOffset > h then
            Panel.scanOffset = 0
        end
        local y = Panel.scanOffset - (h / 2)
        Panel.scanline:ClearAllPoints()
        Panel.scanline:SetPoint("LEFT", self, "LEFT", 2, y)
        Panel.scanline:SetPoint("RIGHT", self, "RIGHT", -2, y)
    end)

    --------------------------------------------------
    -- Bars & cast line (under model, full width)
    --------------------------------------------------

    local hpBar = CreateFrame("StatusBar", nil, f)
    hpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hpBar:SetPoint("TOPLEFT", modelFrame, "BOTTOMLEFT", 0, -8)
    hpBar:SetPoint("TOPRIGHT", modelFrame, "BOTTOMRIGHT", 0, -8)
    hpBar:SetHeight(10)
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(0)
    Panel.hpBar = hpBar

    local hpBG = hpBar:CreateTexture(nil, "BACKGROUND")
    hpBG:SetAllPoints()
    hpBG:SetColorTexture(0, 0, 0, 0.7)
    Panel.hpBG = hpBG

    local hpText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    hpText:SetPoint("CENTER", hpBar, "CENTER", 0, 0)
    hpText:SetJustifyH("CENTER")
    Panel.hpText = hpText

    local mpBar = CreateFrame("StatusBar", nil, f)
    mpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    mpBar:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, -4)
    mpBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, -4)
    mpBar:SetHeight(8)
    mpBar:SetMinMaxValues(0, 1)
    mpBar:SetValue(0)
    Panel.mpBar = mpBar

    local mpBG = mpBar:CreateTexture(nil, "BACKGROUND")
    mpBG:SetAllPoints()
    mpBG:SetColorTexture(0, 0, 0, 0.7)
    Panel.mpBG = mpBG

    local castFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    castFS:SetPoint("TOPLEFT", mpBar, "BOTTOMLEFT", 0, -6)
    castFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    castFS:SetJustifyH("LEFT")
    castFS:SetText("")
    Panel.castFS = castFS

    return f
end

------------------------------------------------------
-- Core update logic
------------------------------------------------------

function Panel.Update()
    local frame = CreatePanelFrame()

    if not (AR.IsEnabled and AR.IsEnabled()) then
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        if Panel.model then
            Panel.model:SetAlpha(0)
            Panel.model:ClearModel()
        end
        return
    end

    if not UnitExists("target") then
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        if Panel.model then
            Panel.model:SetAlpha(0)
            Panel.model:ClearModel()
        end
        return
    end

    local unit = "target"

    -- Name & reaction
    local name = UnitName(unit) or "Unknown Target"
    Panel.nameFS:SetText(name)

    local r, g, b = ColorForReaction(unit)
    Panel.accent:SetColorTexture(r, g, b, 0.95)
    Panel.hpBar:SetStatusBarColor(r, g, b)

    -- Level / type line
    Panel.levelFS:SetText(BuildLevelLine(unit))

    -- Health
    local hp    = UnitHealth(unit) or 0
    local hpMax = UnitHealthMax(unit) or 1
    local hpPct = (hpMax > 0) and (hp / hpMax) or 0
    hpPct = Clamp01(hpPct)

    Panel.hpBar:SetMinMaxValues(0, 1)
    Panel.hpBar:SetValue(hpPct)
    Panel.hpText:SetText(string.format("%d / %d (%.0f%%)", hp, hpMax, hpPct * 100))

    -- Power
    local mp    = UnitPower(unit) or 0
    local mpMax = UnitPowerMax(unit) or 1
    local mpPct = (mpMax > 0) and (mp / mpMax) or 0
    mpPct = Clamp01(mpPct)

    local pr, pg, pb = ColorForPowerType(unit)

    Panel.mpBar:SetMinMaxValues(0, 1)
    Panel.mpBar:SetValue(mpPct)
    Panel.mpBar:SetStatusBarColor(pr, pg, pb)

    -- Cast line
    local castLine = BuildCastLine(unit)
    Panel.castFS:SetText(castLine or "")

    -- Model preview with pose profile
    if Panel.model then
        if UnitIsVisible(unit) and not UnitIsDeadOrGhost(unit) then
            Panel.model:SetUnit(unit)
            Panel.model:SetAlpha(0.95)

            ApplyModelPose(unit, Panel.model)
        else
            Panel.model:SetAlpha(0)
            Panel.model:ClearModel()
        end
    end

    -- Visible (alpha only)
    frame:SetAlpha(1)
    frame:EnableMouse(false)
end

------------------------------------------------------
-- Event handling
------------------------------------------------------

local eventFrame

local function OnEvent(self, event, arg1)
    if not PE or not PE.AR then
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        Panel.Update()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if arg1 == "target" then
            Panel.Update()
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        if arg1 == "target" then
            Panel.Update()
        end
    elseif event == "UNIT_FACTION" then
        if arg1 == "target" then
            Panel.Update()
        end
    elseif event == "PLAYER_LOGIN" then
        Panel.Update()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        Panel.Update()
    end
end

function Panel.Init()
    if eventFrame then return end

    CreatePanelFrame()

    eventFrame = CreateFrame("Frame", "PE_AR_TargetPanelEvents", UIParent)
    eventFrame:SetScript("OnEvent", OnEvent)

    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    eventFrame:RegisterEvent("UNIT_MAXPOWER")
    eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
    eventFrame:RegisterEvent("UNIT_FACTION")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function Panel.ForceUpdate()
    Panel.Update()
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Target Panel", {
    name  = "AR Target Panel",
    class = "AR HUD",
})

Panel.Init()
