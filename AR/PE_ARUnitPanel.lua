-- ##################################################
-- AR/PE_ARUnitPanel.lua
-- Generic “unit dossier” panel factory for AR HUD.
--
-- Used to build:
--   * Target, Focus, Mouseover dossiers
--   * Pet dossiers (player pet, etc.)
-- Everything shares the same visual language; behaviour is driven
-- entirely by config.
-- ##################################################

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.UnitPanel = AR.UnitPanel or {}

------------------------------------------------------
-- Helpers
------------------------------------------------------

local function Clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function DefaultName(unit)
    return UnitName(unit) or "Unknown"
end

local function DefaultCastLine(unit)
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

local function DefaultHP(unit)
    local hp    = UnitHealth(unit) or 0
    local hpMax = UnitHealthMax(unit) or 1
    local hpPct = (hpMax > 0) and (hp / hpMax) or 0
    return hp, hpMax, Clamp01(hpPct)
end

local function DefaultPower(unit)
    local mp    = UnitPower(unit) or 0
    local mpMax = UnitPowerMax(unit) or 1
    local mpPct = (mpMax > 0) and (mp / mpMax) or 0
    return mp, mpMax, Clamp01(mpPct)
end

local function DefaultPowerColor(unit)
    local pType = select(2, UnitPowerType(unit))
    if pType == "MANA" then
        return 0.2, 0.55, 1.0
    elseif pType == "RAGE" or pType == "FURY" then
        return 1.0, 0.25, 0.25
    elseif pType == "ENERGY" then
        return 1.0, 0.9, 0.3
    elseif pType == "FOCUS" then
        return 1.0, 0.55, 0.2
    else
        return 0.1, 0.95, 0.8
    end
end

local function DefaultAccent(unit)
    -- generic “reaction” accent; can be overridden per config
    if UnitIsEnemy("player", unit) then
        return 1.0, 0.25, 0.2
    elseif UnitIsFriend("player", unit) then
        return 0.2, 1.0, 0.7
    else
        return 1.0, 0.8, 0.25
    end
end

local function GetLayout()
    return AR and AR.Layout
end

------------------------------------------------------
-- Factory
------------------------------------------------------
-- opts:
--   unitToken    : "target"/"focus"/"mouseover"/"pet"/etc
--   layoutKey    : key in AR.Layout (e.g. "targetPanel")
--   moduleKey    : logging key ("AR Target Panel")
--   moduleName   : shown in PE modules list
--   size         : { w = 260, h = 300 }
--   modelHeight  : height of 3D model region
--   showPowerBar : bool (pets can turn this off if desired)
--   nameFunc     : function(unit) -> string
--   buildLine1   : function(unit) -> string (e.g. level line)
--   buildLine2   : function(unit) -> string or nil (e.g. status)
--   accentColor  : function(unit) -> r,g,b
--   castLineFunc : optional function(unit) -> string
--   poseFunc     : optional function(unit, model)
--   noUnitText   : { title = "...", subtitle = "..." }
--
function AR.UnitPanel.Create(opts)
    local unitToken   = opts.unitToken
    local layoutKey   = opts.layoutKey
    local moduleKey   = opts.moduleKey or ("AR "..unitToken.." Panel")
    local moduleName  = opts.moduleName or moduleKey
    local size        = opts.size or { w = 260, h = 300 }
    local modelHeight = opts.modelHeight or 220
    local showPower   = opts.showPowerBar ~= false

    local nameFunc    = opts.nameFunc     or DefaultName
    local line1Func   = opts.buildLine1   or function() return "" end
    local line2Func   = opts.buildLine2   -- can be nil
    local accentFunc  = opts.accentColor  or DefaultAccent
    local castFunc    = opts.castLineFunc or DefaultCastLine
    local poseFunc    = opts.poseFunc
	local hideWhenNoUnit = opts.hideWhenNoUnit or false


    local noUnitText  = opts.noUnitText or {
        title    = "No Target",
        subtitle = "Select a target to scan",
    }

    local Panel = {}
    Panel.unitToken = unitToken

    --------------------------------------------------
    -- Frame creation
    --------------------------------------------------
    local function CreatePanelFrame()
        if Panel.frame then
            return Panel.frame
        end

        local f = CreateFrame("Frame", opts.frameName or nil, UIParent)
        Panel.frame = f

        local Layout = GetLayout()
        if Layout and Layout.Attach then
            Layout.Attach(f, layoutKey)
        else
            f:SetSize(size.w, size.h)
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end

        if f:GetHeight() < size.h then
            f:SetHeight(size.h)
        end

        f:EnableMouse(false)

        if Layout and Layout.Register then
            Layout.Register(layoutKey, f, { deferAttach = true })
        end

        -- Background + grid
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        Panel.bg = bg

        local inner = f:CreateTexture(nil, "BACKGROUND")
        inner:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        inner:SetColorTexture(0.0, 0.35, 0.35, 0.35)
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

        -- Accent + borders
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
        bottomLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, -1)
        bottomLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, -1)
        Panel.bottomLine = bottomLine

        -- Scanline
        local scan = f:CreateTexture(nil, "ARTWORK")
        scan:SetColorTexture(0.9, 0.95, 1.0, 0.22)
        scan:SetPoint("LEFT", f, "LEFT", 2, 0)
        scan:SetPoint("RIGHT", f, "RIGHT", -2, 0)
        scan:SetHeight(14)
        scan:SetBlendMode("ADD")
        Panel.scanline = scan
        Panel.scanOffset = 0

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

        -- Text: name and lines
        local nameFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Med1")
        nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
        nameFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        nameFS:SetJustifyH("LEFT")
        Panel.nameFS = nameFS

        local line1FS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
        line1FS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
        line1FS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        line1FS:SetJustifyH("LEFT")
        Panel.line1FS = line1FS

        local anchorUnder
        if line2Func then
            local line2FS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
            line2FS:SetPoint("TOPLEFT", line1FS, "BOTTOMLEFT", 0, -2)
            line2FS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            line2FS:SetJustifyH("LEFT")
            Panel.line2FS = line2FS
            anchorUnder = line2FS
        else
            anchorUnder = line1FS
        end

        -- Model frame
        local modelFrame = CreateFrame("Frame", nil, f)
        modelFrame:SetPoint("TOPLEFT", anchorUnder, "BOTTOMLEFT", 0, -8)
        modelFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
        modelFrame:SetHeight(modelHeight)
        Panel.modelFrame = modelFrame

        local modelBG = modelFrame:CreateTexture(nil, "BACKGROUND")
        modelBG:SetAllPoints()
        modelBG:SetColorTexture(0, 0, 0, 0.6)
        Panel.modelBG = modelBG

        local model = CreateFrame("PlayerModel", nil, modelFrame)
        model:SetAllPoints()
        model:SetAlpha(0)
        Panel.model = model

        -- Bars & cast line
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

        if showPower then
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
        end

        local castFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
        local castAnchor = Panel.mpBar or hpBar
        castFS:SetPoint("TOPLEFT", castAnchor, "BOTTOMLEFT", 0, -6)
        castFS:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        castFS:SetJustifyH("LEFT")
        castFS:SetText("")
        Panel.castFS = castFS

        return f
    end

    --------------------------------------------------
    -- Update logic
    --------------------------------------------------
    function Panel.Update()
        local frame = CreatePanelFrame()

        if not (AR.IsEnabled and AR.IsEnabled()) then
            frame:EnableMouse(false)
            if Panel.model then
                Panel.model:SetAlpha(0)
                Panel.model:ClearModel()
            end
            return
        end

        local unit = unitToken

        if not UnitExists(unit) then
			if hideWhenNoUnit then
				-- For things like the pet dossier: vanish completely when there is no unit.
				frame:SetAlpha(0)
				frame:EnableMouse(false)
				if Panel.model then
					Panel.model:SetAlpha(0)
					Panel.model:ClearModel()
				end
			else
            -- idle state
            Panel.nameFS:SetText(noUnitText.title or "")
            Panel.line1FS:SetText(noUnitText.subtitle or "")
            if Panel.line2FS then
                Panel.line2FS:SetText("")
            end

            Panel.hpBar:SetMinMaxValues(0, 1)
            Panel.hpBar:SetValue(0)
            Panel.hpText:SetText("")
            if Panel.mpBar then
                Panel.mpBar:SetMinMaxValues(0, 1)
                Panel.mpBar:SetValue(0)
            end
            Panel.castFS:SetText("")

            if Panel.model then
                Panel.model:SetAlpha(0)
                Panel.model:ClearModel()
            end

            -- soft accent so it still feels “online”
            Panel.accent:SetColorTexture(0.2, 0.6, 0.7, 0.5)

            frame:SetAlpha(0.7)
            frame:EnableMouse(false)
            return
        end

        -- Name & header lines
        Panel.nameFS:SetText(nameFunc(unit))
        Panel.line1FS:SetText(line1Func(unit) or "")
        if Panel.line2FS then
            Panel.line2FS:SetText(line2Func(unit) or "")
        end

        local ar, ag, ab = accentFunc(unit)
        Panel.accent:SetColorTexture(ar, ag, ab, 0.95)
        Panel.hpBar:SetStatusBarColor(ar, ag, ab)

        -- HP
        local hp, hpMax, hpPct = DefaultHP(unit)
        Panel.hpBar:SetMinMaxValues(0, 1)
        Panel.hpBar:SetValue(hpPct)
        Panel.hpText:SetText(string.format("%d / %d (%.0f%%)", hp, hpMax, hpPct * 100))

        -- Power (if enabled)
        if Panel.mpBar then
            local mp, mpMax, mpPct = DefaultPower(unit)
            local pr, pg, pb = DefaultPowerColor(unit)
            Panel.mpBar:SetMinMaxValues(0, 1)
            Panel.mpBar:SetValue(mpPct)
            Panel.mpBar:SetStatusBarColor(pr, pg, pb)
        end

        -- Cast line
        Panel.castFS:SetText(castFunc(unit) or "")

        -- Model
        if Panel.model then
            if UnitIsVisible(unit) and not UnitIsDeadOrGhost(unit) then
                Panel.model:SetUnit(unit)
                Panel.model:SetAlpha(0.95)
                if poseFunc then
                    poseFunc(unit, Panel.model)
                end
            else
                Panel.model:SetAlpha(0)
                Panel.model:ClearModel()
            end
        end

        frame:SetAlpha(1)
        frame:EnableMouse(false)
    end

    --------------------------------------------------
    -- Events
    --------------------------------------------------
    local eventFrame

    local function OnEvent(self, event, arg1)
        if not PE or not PE.AR then
            return
        end

        if event == "PLAYER_LOGIN" then
            Panel.Update()
        elseif event == "PLAYER_TARGET_CHANGED" and unitToken == "target" then
            Panel.Update()
        elseif event == "PLAYER_FOCUS_CHANGED" and unitToken == "focus" then
            Panel.Update()
        elseif event == "UPDATE_MOUSEOVER_UNIT" and unitToken == "mouseover" then
            Panel.Update()
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
            or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
            or event == "UNIT_DISPLAYPOWER" or event == "UNIT_FACTION" then

            if arg1 == unitToken then
                Panel.Update()
            end
        elseif event == "UNIT_PET" and unitToken == "pet" then
            -- player pet changed; just refresh
            Panel.Update()
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            Panel.Update()
        end
    end

    function Panel.Init()
        if eventFrame then return end

        eventFrame = CreateFrame("Frame", nil, UIParent)
        eventFrame:SetScript("OnEvent", OnEvent)

        eventFrame:RegisterEvent("PLAYER_LOGIN")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("UNIT_HEALTH")
        eventFrame:RegisterEvent("UNIT_MAXHEALTH")
        eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
        eventFrame:RegisterEvent("UNIT_MAXPOWER")
        eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
        eventFrame:RegisterEvent("UNIT_FACTION")
        eventFrame:RegisterEvent("UNIT_PET")
        eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
        eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    end

    function Panel.ForceUpdate()
        Panel.Update()
    end

    -- Register as a PE module so it shows up in logs / toggles if you want.
    PE.LogInit(moduleKey)
    PE.RegisterModule(moduleKey, {
        name  = moduleName,
        class = "AR HUD",
    })

    Panel.Init()
    return Panel
end
