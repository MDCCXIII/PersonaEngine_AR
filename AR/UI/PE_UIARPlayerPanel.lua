-- ##################################################
-- AR/UI/PE_UIARPlayerPanel.lua
-- PersonaEngine: Screen-space Player Info Panel
--
-- Tall dossier layout for the *player*:
--   - Name/class/spec/race + status on top
--   - 3D model in the middle
--   - HP/Power bars + cast info underneath.
-- ##################################################

local MODULE = "AR Player Panel"

-- Tunables for player card size
local PLAYER_WIDTH        = 260
local PLAYER_HEIGHT       = 340
local PLAYER_MODEL_HEIGHT = 220

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.PlayerPanel = AR.PlayerPanel or {}
local Panel = AR.PlayerPanel

------------------------------------------------------
-- Layout access (lazy, so load order can't break us)
------------------------------------------------------

local function GetLayout()
    return AR and AR.Layout
end

------------------------------------------------------
-- Utilities
------------------------------------------------------

local function Clamp01(v)
    if v < 0 then
        return 0
    end
    if v > 1 then
        return 1
    end
    return v
end

local function ColorForPlayer()
    -- Copporclang cyan
    return 0.2, 1.0, 0.7
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

local function BuildClassLine(unit)
    local level          = UnitLevel(unit) or -1
    local classLocalized = select(1, UnitClass(unit))
    local race           = UnitRace(unit) or ""
    local specName

    -- Try to grab active specialization name if available
    if GetSpecialization then
        local specIndex = GetSpecialization()
        if specIndex then
            specName = select(2, GetSpecializationInfo(specIndex))
        end
    end

    local parts = {}

    if level <= 0 then
        table.insert(parts, "Lv ??")
    else
        table.insert(parts, string.format("Lv %d", level))
    end

    if specName then
        table.insert(parts, specName)
    end

    if classLocalized then
        table.insert(parts, classLocalized)
    end

    if race and race ~= "" then
        table.insert(parts, race)
    end

    return table.concat(parts, " • ")
end

local function BuildStatusLine(unit)
    local pieces = {}

    if UnitAffectingCombat(unit) then
        table.insert(pieces, "|cffff4040COMBAT|r")
    else
        table.insert(pieces, "|cff20ff70IDLE|r")
    end

    if IsResting() then
        table.insert(pieces, "|cffb0b0ffRESTED|r")
    end

    local zone = GetZoneText() or ""
    if zone ~= "" then
        table.insert(pieces, zone)
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

    local dur  = (endTime and startTime) and (endTime - startTime) / 1000 or 0
    local flag = notInterruptible and "|cffffa040UNINT|r" or "|cff20ff50CAST|r"

    return string.format("%s (%.1fs) [%s]", name, dur, flag)
end

-- Central gate for "is AR HUD enabled?"
local function IsAREnabled()
    if AR.IsEnabled and type(AR.IsEnabled) == "function" then
        return AR.IsEnabled()
    end
    if AR.enabled ~= nil then
        return AR.enabled
    end
    return true -- assume on if nothing explicit is exposed
end

------------------------------------------------------
-- Frame creation
------------------------------------------------------

local function CreatePanelFrame()
    if Panel.frame then
        return Panel.frame
    end

    -- Main player panel frame
    local f = CreateFrame("Frame", "PE_AR_PlayerPanel", UIParent)
    Panel.frame = f

    -- Strata / level for root
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(0)

    -- Position driven by layout provider (or fallback)
    local Layout = GetLayout()
    if Layout and Layout.Attach then
        Layout.Attach(f, "playerPanel")
    end

    -- Fallback position if layout didn't attach
    local point = f:GetPoint(1)
    if not point then
        f:SetPoint("LEFT", UIParent, "LEFT", 60, 60)
    end

    -- Make sure the card is tall enough for:
    -- name + class + status + tall model + bars + cast text.
    f:SetSize(PLAYER_WIDTH, PLAYER_HEIGHT)
    local minHeight = PLAYER_HEIGHT
    if f:GetHeight() < minHeight then
        f:SetHeight(minHeight)
    end

    f:SetAlpha(0)
    f:EnableMouse(false)

    -- Register with layout system so it can be dragged in edit mode.
    -- We use deferAttach=true because we already called Attach above.
    if Layout and Layout.Register then
        Layout.Register("playerPanel", f, { deferAttach = true })
    end

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
    inner:SetColorTexture(0.0, 0.25, 0.25, 0.35)
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
        local x = (i / (gridCols + 1)) * f:GetWidth()
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
        local y = -(i / (gridRows + 1)) * f:GetHeight()
        line:SetPoint("LEFT", f, "LEFT", 2, y)
        line:SetPoint("RIGHT", f, "RIGHT", -2, y)
        line:SetHeight(1)
    end

    --------------------------------------------------
    -- Accent spine + borders
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
    -- NOTE: -1 keeps it *inside* the card, avoids ghost line below.
    bottomLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, -1)
    bottomLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, -1)
    Panel.bottomLine = bottomLine

    --------------------------------------------------
    -- Scanline overlay (animated)
    --------------------------------------------------

    local scan = f:CreateTexture(nil, "ARTWORK")
    scan:SetColorTexture(0.9, 0.95, 1.0, 0.22)
    scan:SetPoint("LEFT",  f, "LEFT",  2, 0)
    scan:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    scan:SetHeight(14)
    scan:SetBlendMode("ADD")
    Panel.scanline   = scan
    Panel.scanOffset = 0

    --------------------------------------------------
    -- Text: name + class line + status
    --------------------------------------------------

    local nameFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Med1")
    nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    nameFS:SetPoint("RIGHT",   f, "RIGHT",   -8, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText("")
    Panel.nameFS = nameFS

    local classFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    classFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    classFS:SetPoint("RIGHT",   f,      "RIGHT",      -8, 0)
    classFS:SetJustifyH("LEFT")
    classFS:SetText("")
    Panel.classFS = classFS

    local statusFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    statusFS:SetPoint("TOPLEFT", classFS, "BOTTOMLEFT", 0, -2)
    statusFS:SetPoint("RIGHT",   f,       "RIGHT",      -8, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetText("")
    Panel.statusFS = statusFS

    --------------------------------------------------
    -- 3D model
    --------------------------------------------------

    -- Model frame for the player (under status line, above bars)
    local modelFrame = CreateFrame("Frame", "PE_AR_PlayerModelFrame", f)
    modelFrame:SetPoint("TOPLEFT",  statusFS, "BOTTOMLEFT",  0, -8)
    modelFrame:SetPoint("TOPRIGHT", statusFS, "BOTTOMRIGHT", 0, -8)
    modelFrame:SetHeight(PLAYER_MODEL_HEIGHT)
    modelFrame:SetFrameStrata("LOW")
    modelFrame:SetFrameLevel(1)
    Panel.modelFrame = modelFrame

    local modelBG = modelFrame:CreateTexture(nil, "BACKGROUND")
    modelBG:SetAllPoints()
    modelBG:SetColorTexture(0, 0, 0, 0.55)
    Panel.modelBG = modelBG

    local model = CreateFrame("PlayerModel", "PE_AR_PlayerModel", modelFrame)
    model:SetAllPoints()
    model:SetAlpha(0.95)
    model:SetFrameStrata("LOW")
    model:SetFrameLevel(2)
    Panel.model = model

    -- Boot / recovery text overlay, sits on top of the model area
    local bootFS = modelFrame:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    bootFS:SetPoint("CENTER", modelFrame, "CENTER", 0, 0)
    bootFS:SetJustifyH("CENTER")
    bootFS:SetJustifyV("MIDDLE")
    bootFS:SetText("")
    Panel.bootFS = bootFS
    Panel.modelOnline = false -- becomes true once the PlayerModel is actually up

    --------------------------------------------------
    -- Bars: HP + Power
    --------------------------------------------------

    local hpBar = CreateFrame("StatusBar", "PE_AR_PlayerHPBar", f)
    hpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hpBar:SetPoint("TOPLEFT",  modelFrame, "BOTTOMLEFT",  0, -8)
    hpBar:SetPoint("TOPRIGHT", modelFrame, "BOTTOMRIGHT", 0, -8)
    hpBar:SetHeight(12)
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(0)
    hpBar:SetFrameStrata("LOW")
    hpBar:SetFrameLevel(1)
    Panel.hpBar = hpBar

    local hpBG = hpBar:CreateTexture(nil, "BACKGROUND")
    hpBG:SetAllPoints()
    hpBG:SetColorTexture(0, 0, 0, 0.7)
    Panel.hpBG = hpBG

    local hpText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    hpText:SetPoint("CENTER", hpBar, "CENTER", 0, 0)
    hpText:SetJustifyH("CENTER")
    Panel.hpText = hpText

    local mpBar = CreateFrame("StatusBar", "PE_AR_PlayerMPBar", f)
    mpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    mpBar:SetPoint("TOPLEFT",  hpBar, "BOTTOMLEFT",  0, -4)
    mpBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, -4)
    mpBar:SetHeight(10)
    mpBar:SetMinMaxValues(0, 1)
    mpBar:SetValue(0)
    mpBar:SetFrameStrata("LOW")
    mpBar:SetFrameLevel(1)
    Panel.mpBar = mpBar

    local mpBG = mpBar:CreateTexture(nil, "BACKGROUND")
    mpBG:SetAllPoints()
    mpBG:SetColorTexture(0, 0, 0, 0.7)
    Panel.mpBG = mpBG

    local mpText = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    mpText:SetPoint("CENTER", mpBar, "CENTER", 0, 0)
    mpText:SetJustifyH("CENTER")
    Panel.mpText = mpText

    --------------------------------------------------
    -- Cast line (bottom)
    --------------------------------------------------

    local castFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    castFS:SetPoint("TOPLEFT", mpBar, "BOTTOMLEFT", 0, -6)
    castFS:SetPoint("RIGHT",   f,     "RIGHT",      -8, 0)
    castFS:SetJustifyH("LEFT")
    castFS:SetText("")
    Panel.castFS = castFS

    --------------------------------------------------
    -- OnUpdate: scanline drift
    --------------------------------------------------

    f:SetScript("OnUpdate", function(self, elapsed)
        Panel.scanOffset = (Panel.scanOffset or 0) + elapsed * 25
        local h = self:GetHeight()
        if Panel.scanOffset > h then
            Panel.scanOffset = 0
        end
        local y = Panel.scanOffset - (h / 2)
        Panel.scanline:ClearAllPoints()
        Panel.scanline:SetPoint("LEFT",  self, "LEFT",  2, y)
        Panel.scanline:SetPoint("RIGHT", self, "RIGHT", -2, y)
    end)

    return f
end

------------------------------------------------------
-- Core update logic
------------------------------------------------------

function Panel.Update()
    local frame = CreatePanelFrame()

    if not IsAREnabled() then
        frame:SetAlpha(0)
        frame:EnableMouse(false)

        if Panel.model then
            Panel.model:SetAlpha(0)
            Panel.model:ClearModel()
        end

        return
    end

    local unit = "player"

    -- Name & class/status lines
    local name = UnitName(unit) or "Unknown"
    Panel.nameFS:SetText(name)
    Panel.classFS:SetText(BuildClassLine(unit))
    Panel.statusFS:SetText(BuildStatusLine(unit))

    -- Accent / HP color
    local r, g, b = ColorForPlayer()
    Panel.accent:SetColorTexture(r, g, b, 0.95)
    Panel.hpBar:SetStatusBarColor(r, g, b)

    -- HP values
    local hp    = UnitHealth(unit) or 0
    local hpMax = UnitHealthMax(unit) or 1
    local hpPct = (hpMax > 0) and (hp / hpMax) or 0
    hpPct       = Clamp01(hpPct)

    Panel.hpBar:SetMinMaxValues(0, 1)
    Panel.hpBar:SetValue(hpPct)
    Panel.hpText:SetText(("%d / %d (%.0f%%)"):format(hp, hpMax, hpPct * 100))

    -- Power values
    local mp    = UnitPower(unit) or 0
    local mpMax = UnitPowerMax(unit) or 1
    local mpPct = (mpMax > 0) and (mp / mpMax) or 0
    mpPct       = Clamp01(mpPct)

    local pr, pg, pb = ColorForPowerType(unit)
    Panel.mpBar:SetStatusBarColor(pr, pg, pb)
    Panel.mpBar:SetMinMaxValues(0, 1)
    Panel.mpBar:SetValue(mpPct)
    Panel.mpText:SetText(("%d / %d (%.0f%%)"):format(mp, mpMax, mpPct * 100))

    -- Cast line
    Panel.castFS:SetText(BuildCastLine(unit) or "")

    -- 3D model
    if Panel.model then
        if UnitIsVisible(unit) and not UnitIsDeadOrGhost(unit) then
            Panel.model:SetUnit(unit)
            Panel.model:SetPortraitZoom(0)
            Panel.model:SetCamDistanceScale(1.31)
            Panel.model:SetPosition(0, 0, 0)

            if Panel.model.SetAnimation then
                Panel.model:SetAnimation(0)
            end
            if Panel.model.SetPaused then
                Panel.model:SetPaused(true)
            end

            Panel.model:SetAlpha(0.95)
            Panel.modelOnline = true
            Panel.bootFS:SetText("")
        else
            Panel.model:SetAlpha(0)
            Panel.model:ClearModel()
            Panel.modelOnline = false
            Panel.bootFS:SetText("")
        end
    end

    frame:SetAlpha(1)
    frame:EnableMouse(false)
end

------------------------------------------------------
-- Events
------------------------------------------------------

local eventFrame

local function OnEvent(self, event, arg1)
    if not PE or not PE.AR then
        return
    end

    if event == "PLAYER_LOGIN"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_UPDATE_RESTING"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA"
    then
        Panel.Update()
    elseif (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and arg1 == "player" then
        Panel.Update()
    elseif (event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER") and arg1 == "player" then
        Panel.Update()
    end
end

function Panel.Init()
    if eventFrame then
        return
    end

    eventFrame = CreateFrame("Frame", "PE_AR_PlayerPanelEvents", UIParent)
    eventFrame:SetFrameStrata("LOW")
    eventFrame:SetFrameLevel(0)
    eventFrame:SetScript("OnEvent", OnEvent)

    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    eventFrame:RegisterEvent("ZONE_CHANGED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    eventFrame:RegisterEvent("UNIT_MAXPOWER")
    eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
end

function Panel.ForceUpdate()
    Panel.Update()
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Player Panel", {
    name  = "AR Player Panel",
    class = "AR HUD",
})

Panel.Init()
