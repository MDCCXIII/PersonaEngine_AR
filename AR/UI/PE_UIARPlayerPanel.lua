-- ##################################################
-- AR/UI/PE_UIARPlayerPanel.lua
-- PersonaEngine: Screen-space Player Info Panel
-- Tall dossier layout for the *player*:
--   Name/class on top
--   HP/Power bars in the middle
--   Status line + cast info underneath.
-- ##################################################

local MODULE = "AR Player Panel"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.PlayerPanel = AR.PlayerPanel or {}
local Panel = AR.PlayerPanel

local Layout = AR.Layout

------------------------------------------------------
-- Utilities
------------------------------------------------------

local function Clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
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
    local level = UnitLevel(unit) or -1
    local classLocalized, classFile = UnitClass(unit)
    local race = UnitRace(unit) or ""
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

    local dur = (endTime and startTime) and (endTime - startTime) / 1000 or 0
    local flag = notInterruptible and "|cffffa040UNINT|r" or "|cff20ff50CAST|r"

    return string.format("%s  (%.1fs)  [%s]", name, dur, flag)
end

------------------------------------------------------
-- Frame creation
------------------------------------------------------

local function CreatePanelFrame()
    if Panel.frame then
        return Panel.frame
    end

    local f = CreateFrame("Frame", "PE_AR_PlayerPanel", UIParent)
    Panel.frame = f

    -- Position driven by layout provider
    if Layout and Layout.Attach then
        Layout.Attach(f, "playerPanel")
    else
        f:SetSize(260, 210)
        f:SetPoint("LEFT", UIParent, "LEFT", 60, 60)
    end

    f:SetAlpha(0)
    f:EnableMouse(false)

    -- Register with layout system so it can be dragged in edit mode
    if Layout and Layout.Register then
        Layout.Register("playerPanel", f)
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
    -- Accent spine
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
    -- Text: name + class line + status
    --------------------------------------------------
    local nameFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Med1")
    nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    nameFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText("")
    Panel.nameFS = nameFS

    local classFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    classFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    classFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    classFS:SetJustifyH("LEFT")
    classFS:SetText("")
    Panel.classFS = classFS

    local statusFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    statusFS:SetPoint("TOPLEFT", classFS, "BOTTOMLEFT", 0, -2)
    statusFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetText("")
    Panel.statusFS = statusFS

    --------------------------------------------------
    -- Bars: HP + Power
    --------------------------------------------------
    local hpBar = CreateFrame("StatusBar", nil, f)
    hpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hpBar:SetPoint("TOPLEFT", statusFS, "BOTTOMLEFT", 0, -8)
    hpBar:SetPoint("TOPRIGHT", statusFS, "BOTTOMRIGHT", 0, -8)
    hpBar:SetHeight(12)
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
    mpBar:SetHeight(10)
    mpBar:SetMinMaxValues(0, 1)
    mpBar:SetValue(0)
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
    castFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
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
        Panel.scanline:SetPoint("LEFT", self, "LEFT", 2, y)
        Panel.scanline:SetPoint("RIGHT", self, "RIGHT", -2, y)
    end)

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
        return
    end

    local unit = "player"

    if not UnitExists(unit) then
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        return
    end

    -- Name & class line
    local name = UnitName(unit) or "Unknown"
    Panel.nameFS:SetText(name)
    Panel.classFS:SetText(BuildClassLine(unit))
    Panel.statusFS:SetText(BuildStatusLine(unit))

    local pr, pg, pb = ColorForPlayer()
    Panel.accent:SetColorTexture(pr, pg, pb, 0.95)
    Panel.hpBar:SetStatusBarColor(pr, pg, pb)

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

    local rr, rg, rb = ColorForPowerType(unit)
    Panel.mpBar:SetMinMaxValues(0, 1)
    Panel.mpBar:SetValue(mpPct)
    Panel.mpBar:SetStatusBarColor(rr, rg, rb)
    Panel.mpText:SetText(string.format("%d / %d (%.0f%%)", mp, mpMax, mpPct * 100))

    -- Cast line
    Panel.castFS:SetText(BuildCastLine(unit) or "")

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

    if event == "PLAYER_LOGIN" then
        Panel.Update()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if arg1 == "player" then
            Panel.Update()
        end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        if arg1 == "player" then
            Panel.Update()
        end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        Panel.Update()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Panel.Update()
    end
end

function Panel.Init()
    if eventFrame then return end

    CreatePanelFrame()

    eventFrame = CreateFrame("Frame", "PE_AR_PlayerPanelEvents", UIParent)
    eventFrame:SetScript("OnEvent", OnEvent)

    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    eventFrame:RegisterEvent("UNIT_MAXPOWER")
    eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
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
PE.RegisterModule("AR Player Panel", {
    name  = "AR Player Panel",
    class = "AR HUD",
})

Panel.Init()
