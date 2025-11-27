-- ##################################################
-- AR/PE_ARReticles.lua
-- PersonaEngine AR: screen-space unit reticles
--
-- * Unique reticles for target + focus
-- * Mouseover indicator above the head
-- * Reticles lock to unit's screen-space anchor
--   (nameplate if available, Blizz frames as fallback)
-- * Distance (yards) is tracked per-unit for later use
--   (viewport boundary & directional pointer logic).
-- ##################################################

local MODULE = "AR Reticles"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

print("|cff20ff80[PersonaEngine_AR] AR Reticles module loaded|r")

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Reticles = AR.Reticles or {}
local Ret = AR.Reticles

local sqrt = math.sqrt

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

-- Only bother on live units that aren't corpses
local function IsValidUnit(unit)
    return UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

-- Distance in yards using UnitDistanceSquared (Retail)
local function GetUnitDistanceYards(unit)
    if not IsValidUnit(unit) then
        return nil
    end

    if UnitDistanceSquared then
        local d2, ok = UnitDistanceSquared(unit)
        if ok and d2 and d2 > 0 then
            return sqrt(d2)
        end
    end

    return nil -- unknown
end

-- Strip Blizzard nameplate visuals but keep the plate as an anchor.
local function HideNameplateArt(plate)
    if not plate or plate._PE_AR_Skinned then
        return
    end
    plate._PE_AR_Skinned = true

    local function strip(frame)
        if not frame then return end

        -- Hide all textures + fontstrings on this frame
        local regions = { frame:GetRegions() }
        for _, r in ipairs(regions) do
            if r:IsObjectType("Texture") or r:IsObjectType("FontString") then
                r:SetAlpha(0)
            end
        end

        -- Hide status bars if present
        if frame.healthBar then
            frame.healthBar:SetAlpha(0)
        end
        if frame.castBar then
            frame.castBar:SetAlpha(0)
        end
    end

    -- Default nameplates usually have UnitFrame on them; fall back to plate itself.
    strip(plate.UnitFrame or plate.unitFrame or plate)
end


-- Prefer nameplate, fall back to target/focus frames if needed
local function GetUnitAnchor(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then
			HideNameplateArt(plate)    -- NEW: nuke Blizz art, keep plate alive
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

    -- Enemies: always have plates so we can anchor, even if user turned them off.
    if tonumber(GetCVar("nameplateShowEnemies") or "0") == 0 then
        SetCVar("nameplateShowEnemies", 1)
    end

    -- "All" makes nameplates always show in world, not just in combat.
    if tonumber(GetCVar("nameplateShowAll") or "0") == 0 then
        SetCVar("nameplateShowAll", 1)
    end
end


------------------------------------------------------
-- Reticle frame factories
------------------------------------------------------

local function CreateRingReticle(name, r, g, b)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(64, 64)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(40)

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Cooldown\\ping4")  -- circular ping ring
    tex:SetVertexColor(r, g, b, 0.9)
    f.tex = tex

    local distFS = f:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    distFS:SetPoint("TOP", f, "BOTTOM", 0, -2)
    distFS:SetJustifyH("CENTER")
    distFS:SetText("")
    f.distFS = distFS

    f.unit   = nil
    f.anchor = nil
    f.dist   = nil

    f:Hide()
    return f
end

local function CreateMouseoverIndicator()
    local f = CreateFrame("Frame", "PE_AR_MouseoverIndicator", UIParent)
    f:SetSize(26, 26)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(45)

    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Cooldown\\ping4")
    tex:SetVertexColor(1.0, 0.9, 0.2, 0.95)
    f.tex = tex

    f.unit   = "mouseover"
    f.anchor = nil
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

    Ret.frames.target    = CreateRingReticle("PE_AR_TargetReticle", 1.0, 0.9, 0.2) -- gold
    Ret.frames.focus     = CreateRingReticle("PE_AR_FocusReticle",  0.2, 1.0, 0.9) -- teal
    Ret.frames.mouseover = CreateMouseoverIndicator()
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

local debugPrintedOnce = false

local function UpdateReticleForUnit(unit, frame, offsetX, offsetY)
    offsetX = offsetX or 0
    offsetY = offsetY or -8

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
        -- Off-screen / no anchor → later this becomes “directional pointer mode”
        HideReticleFrame(frame)
        return
    end

    frame.unit   = unit
    frame.anchor = anchor

    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)

    local dist = GetUnitDistanceYards(unit)
    frame.dist = dist

    if frame.distFS then
        if dist then
            frame.distFS:SetFormattedText("%.0f yd", dist)
        else
            frame.distFS:SetText("")
        end
    end

    frame:Show()

    -- Tiny one-time debug ping so we know it actually bound to something
    if not debugPrintedOnce and unit == "target" then
        debugPrintedOnce = true
        print("|cff20ff80[PersonaEngine_AR] Reticle bound to target anchor:|r", anchor:GetName() or "<?>")
    end
end

local function UpdateMouseoverIndicator(frame)
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

    frame.anchor = anchor
    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint("BOTTOM", anchor, "TOP", 0, 14) -- above head/nameplate
    frame:Show()
end

------------------------------------------------------
-- Driver
------------------------------------------------------

local driver
local updateThrottle = 0

local function OnUpdate(self, elapsed)
    updateThrottle = updateThrottle + elapsed
    if updateThrottle < 0.03 then
        return
    end
    updateThrottle = 0

    EnsureFrames()

    UpdateReticleForUnit("target", Ret.frames.target, 0, -8)
    UpdateReticleForUnit("focus",  Ret.frames.focus,  0, -8)

    UpdateMouseoverIndicator(Ret.frames.mouseover)
end

function Ret.Init()
    if driver then
        return
    end
	
	EnsureNameplateCVars()   -- NEW: make sure plates actually exist

    EnsureFrames()

    driver = CreateFrame("Frame", "PE_AR_ReticleDriver", UIParent)
    driver:SetScript("OnUpdate", OnUpdate)
end

function Ret.ForceUpdate()
    if driver then
        OnUpdate(driver, 0.1)
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
