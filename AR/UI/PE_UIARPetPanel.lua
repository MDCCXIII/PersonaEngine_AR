-- ##################################################
-- AR/UI/PE_UIARPetPanel.lua
-- PersonaEngine AR: Player Pet Info Panel
--
-- Smaller dossier for the *player's pet*:
--   - Name/level/creature type on top
--   - 3D model in the middle
--   - HP bar + optional cast line underneath.
--
-- Only visible while UnitExists("pet").
-- ##################################################

local MODULE = "AR Pet Panel"

-- Tunables for pet card size
local PET_WIDTH        = 150
local PET_HEIGHT       = 160
local PET_MODEL_HEIGHT = 90

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

-- DEBUG: confirm file actually loaded
-- print("|cff20ff80[PersonaEngine_AR] AR Pet Panel module loaded|r")

PE.AR = PE.AR or {}
local AR = PE.AR

AR.PetPanel = AR.PetPanel or {}
local Panel = AR.PetPanel

------------------------------------------------------
-- Helpers
------------------------------------------------------

local function GetLayout()
    return AR and AR.Layout
end

local function Clamp01(v)
    if v < 0 then
        return 0
    end
    if v > 1 then
        return 1
    end
    return v
end

local function ColorForPet()
    -- Match Copporclang cyan accent
    return 0.2, 1.0, 0.7
end

local function BuildPetLine(unit)
    local level  = UnitLevel(unit) or -1
    local ctype  = UnitCreatureType(unit) or "Mechanical"
    local pieces = {}

    if level <= 0 then
        table.insert(pieces, "Lv ??")
    else
        table.insert(pieces, ("Lv %d"):format(level))
    end

    table.insert(pieces, ctype)

    local family = UnitCreatureFamily and UnitCreatureFamily(unit)
    if family and family ~= ctype then
        table.insert(pieces, family)
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
    local flag = notInterruptible and "|cffff4040LOCKED|r" or "|cff20ff50INTERRUPT|r"

    return ("CAST: %s (%.1fs) [%s]"):format(name, dur, flag)
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

    -- Main pet panel frame
    local f = CreateFrame("Frame", "PE_AR_PetPanel", UIParent)
    Panel.frame = f

    -- Strata / level for root
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(0)

    -- Try layout attach *first* (so editor can move it),
    -- but always enforce a sane on-screen default after.
    local Layout = GetLayout()
    if Layout and Layout.Attach then
        Layout.Attach(f, "petPanel")
    end

    -- If layout didn't set anything meaningful, force a default anchor
    local point = f:GetPoint(1)
    if not point then
        f:SetPoint("RIGHT", UIParent, "RIGHT", -60, -300)
    end

    -- Always enforce compact pet size; layout only moves it
    f:SetSize(PET_WIDTH, PET_HEIGHT)
    f:SetAlpha(0)
    f:EnableMouse(false)

    if Layout and Layout.Register then
        Layout.Register("petPanel", f, { deferAttach = true })
    end

    --------------------------------------------------
    -- Background + inner panel
    --------------------------------------------------

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    Panel.bg = bg

    local inner = f:CreateTexture(nil, "BACKGROUND")
    inner:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.0, 0.35, 0.35, 0.35)
    Panel.inner = inner

    --------------------------------------------------
    -- Grid
    --------------------------------------------------

    Panel.gridLines = Panel.gridLines or {}
    local gridCols  = 6
    for i = 1, gridCols do
        local line = Panel.gridLines[i]
        if not line then
            line = f:CreateTexture(nil, "BACKGROUND")
            Panel.gridLines[i] = line
        end

        line:SetColorTexture(0.1, 0.9, 0.8, 0.16)
        local x = (i / (gridCols + 1)) * PET_WIDTH
        line:SetPoint("TOPLEFT", f, "TOPLEFT", x, -2)
        line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 2)
        line:SetWidth(1)
    end

    Panel.gridRows = Panel.gridRows or {}
    local gridRows = 4
    for i = 1, gridRows do
        local line = Panel.gridRows[i]
        if not line then
            line = f:CreateTexture(nil, "BACKGROUND")
            Panel.gridRows[i] = line
        end

        line:SetColorTexture(0.1, 0.9, 0.8, 0.14)
        local y = -(i / (gridRows + 1)) * PET_HEIGHT
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
    bottomLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, -1)
    bottomLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, -1)
    Panel.bottomLine = bottomLine

    --------------------------------------------------
    -- Scanline
    --------------------------------------------------

    local scan = f:CreateTexture(nil, "ARTWORK")
    scan:SetColorTexture(0.9, 0.95, 1.0, 0.22)
    scan:SetPoint("LEFT",  f, "LEFT",  2,  0)
    scan:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    scan:SetHeight(12)
    scan:SetBlendMode("ADD")
    Panel.scanline   = scan
    Panel.scanOffset = 0

    f:SetScript("OnUpdate", function(self, elapsed)
        Panel.scanOffset = (Panel.scanOffset or 0) + elapsed * 25
        local h = self:GetHeight()
        if Panel.scanOffset > h then
            Panel.scanOffset = 0
        end
        local y = Panel.scanOffset - (h / 2)
        Panel.scanline:ClearAllPoints()
        Panel.scanline:SetPoint("LEFT",  self, "LEFT",  2,  y)
        Panel.scanline:SetPoint("RIGHT", self, "RIGHT", -2, y)
    end)

    --------------------------------------------------
    -- Text
    --------------------------------------------------

    local nameFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Med1")
    nameFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    nameFS:SetPoint("RIGHT",   f, "RIGHT",   -8, 0)
    nameFS:SetJustifyH("LEFT")
    Panel.nameFS = nameFS

    local lineFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    lineFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    lineFS:SetPoint("RIGHT",   f,      "RIGHT",      -8, 0)
    lineFS:SetJustifyH("LEFT")
    Panel.lineFS = lineFS

    --------------------------------------------------
    -- Model
    --------------------------------------------------

    local modelFrame = CreateFrame("Frame", "PE_AR_PetModelFrame", f)
    modelFrame:SetPoint("TOPLEFT",  lineFS, "BOTTOMLEFT", 0, -8)
    modelFrame:SetPoint("TOPRIGHT", f,      "TOPRIGHT",   -8, -8)
    modelFrame:SetHeight(PET_MODEL_HEIGHT)
    modelFrame:SetFrameStrata("LOW")
    modelFrame:SetFrameLevel(1)
    Panel.modelFrame = modelFrame

    local modelBG = modelFrame:CreateTexture(nil, "BACKGROUND")
    modelBG:SetAllPoints()
    modelBG:SetColorTexture(0, 0, 0, 0.6)
    Panel.modelBG = modelBG

    local model = CreateFrame("PlayerModel", "PE_AR_PetModel", modelFrame)
    model:SetAllPoints()
    model:SetAlpha(0)
    model:SetFrameStrata("LOW")
    model:SetFrameLevel(2)
    Panel.model = model

    --------------------------------------------------
    -- HP bar
    --------------------------------------------------

    local hpBar = CreateFrame("StatusBar", "PE_AR_PetHPBar", f)
    hpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hpBar:SetPoint("TOPLEFT",  modelFrame, "BOTTOMLEFT",  0, -8)
    hpBar:SetPoint("TOPRIGHT", modelFrame, "BOTTOMRIGHT", 0, -8)
    hpBar:SetHeight(10)
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

    --------------------------------------------------
    -- Cast line (optional flavour)
    --------------------------------------------------

    local castFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    castFS:SetPoint("TOPLEFT", hpBar, "BOTTOMLEFT", 0, -6)
    castFS:SetPoint("RIGHT",   f,     "RIGHT",      -8, 0)
    castFS:SetJustifyH("LEFT")
    castFS:SetText("")
    Panel.castFS = castFS

    return f
end

------------------------------------------------------
-- Update
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

    local unit = "pet"
    if not UnitExists(unit) then
        -- Hide completely when there's no pet out
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        if Panel.model then
            Panel.model:SetAlpha(0)
            Panel.model:ClearModel()
        end
        return
    end

    -- Name / info
    Panel.nameFS:SetText(UnitName(unit) or "Pet")
    Panel.lineFS:SetText(BuildPetLine(unit))

    -- Accent + HP color
    local r, g, b = ColorForPet()
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

    -- Cast line
    Panel.castFS:SetText(BuildCastLine(unit) or "")

    -- Model
    if Panel.model then
        if UnitIsVisible(unit) and not UnitIsDeadOrGhost(unit) then
            Panel.model:SetUnit(unit)
            Panel.model:SetPortraitZoom(0.3)
            Panel.model:SetCamDistanceScale(1.20)
            Panel.model:SetPosition(0, 0, 0)
            if Panel.model.SetAnimation then
                Panel.model:SetAnimation(0)
            end
            if Panel.model.SetPaused then
                Panel.model:SetPaused(true)
            end
            Panel.model:SetAlpha(0.95)
        else
            Panel.model:SetAlpha(0)
            Panel.model:ClearModel()
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

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Panel.Update()
    elseif event == "UNIT_PET" and arg1 == "player" then
        Panel.Update()
    elseif (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and arg1 == "pet" then
        Panel.Update()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        Panel.Update()
    end
end

function Panel.Init()
    if eventFrame then
        return
    end

    eventFrame = CreateFrame("Frame", "PE_AR_PetPanelEvents", UIParent)
    eventFrame:SetFrameStrata("LOW")
    eventFrame:SetFrameLevel(0)
    eventFrame:SetScript("OnEvent", OnEvent)

    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
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
PE.RegisterModule("AR Pet Panel", {
    name  = "AR Pet Panel",
    class = "AR HUD",
})

Panel.Init()
