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

local function GetLayout()
    return AR and AR.Layout
end

-- Generic "is this unit something we can actually draw for?"
local function IsValidUnit(unit)
    return UnitExists(unit) and not UnitIsDeadOrGhost(unit)
end

-- Distance in yards using UnitDistanceSquared (Retail-only, but perfect here)
local function GetUnitDistanceYards(unit)
    if not IsValidUnit(unit) then
        return nil
    end

    if UnitDistanceSquared then
        local d2, checked = UnitDistanceSquared(unit)
        if checked and d2 and d2 > 0 then
            return sqrt(d2)
        end
    end

    -- Very soft fallback: nil means "unknown"
    return nil
end

-- Preferred anchor for screen position:
-- 1) Nameplate (if visible),
-- 2) Blizz unit frame (TargetFrame / FocusFrame),
-- 3) nil if we really can't.
local function GetUnitAnchor(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then
            return plate
        end
    end

    if unit == "target" then
        return _G.TargetFrame
    elseif unit == "focus" then
        return _G.FocusFrame
    elseif unit == "mouseover" then
        -- Mouseover has no fixed frame; rely on nameplates only
        return nil
    end

    return nil
end

------------------------------------------------------
-- Reticle frame creation
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

    -- Optional distance label underneath
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
    -- Small downward-pointing-ish diamond; tweak later if you add a custom arrow texture
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

    Ret.frames.target   = CreateRingReticle("PE_AR_TargetReticle", 1.0, 0.9, 0.2) -- gold-ish
    Ret.frames.focus    = CreateRingReticle("PE_AR_FocusReticle",  0.2, 1.0, 0.9) -- teal-ish
    Ret.frames.mouseover = CreateMouseoverIndicator()

    -- Optional: register with layout so you can drag the "reticle origin" later
    local Layout = GetLayout()
    if Layout and Layout.Register then
        -- These are conceptual anchors; for now we just keep them at 0,0 and let
        -- world anchors drive the actual position. But we register anyway so they
        -- can be toggled / inspected from the layout editor.
        Layout.Register("targetReticle", Ret.frames.target, { lock = true })
        Layout.Register("focusReticle",  Ret.frames.focus,  { lock = true })
        Layout.Register("mouseoverIndicator", Ret.frames.mouseover, { lock = true })
    end
end

------------------------------------------------------
-- Core update logic
------------------------------------------------------

local function UpdateReticleForUnit(unit, frame, opts)
    opts = opts or {}

    if not IsAREnabled() then
        frame:Hide()
        frame.unit   = nil
        frame.anchor = nil
        frame.dist   = nil
        if frame.distFS then
            frame.distFS:SetText("")
        end
        return
    end

    if not IsValidUnit(unit) then
        frame:Hide()
        frame.unit   = nil
        frame.anchor = nil
        frame.dist   = nil
        if frame.distFS then
            frame.distFS:SetText("")
        end
        return
    end

    local anchor = GetUnitAnchor(unit)
    if not anchor or not anchor:IsShown() then
        -- On-screen directional pointers will hook here later when
        -- the unit is off-screen / nameplate hidden.
        frame:Hide()
        frame.unit   = unit
        frame.anchor = nil
        frame.dist   = nil
        if frame.distFS then
            frame.distFS:SetText("")
        end
        return
    end

    frame.unit   = unit
    frame.anchor = anchor

    -- Position the reticle relative to the anchor.
    -- Slight downward offset to bias toward torso/body.
    local offsetX = opts.offsetX or 0
    local offsetY = opts.offsetY or -10

    frame:ClearAllPoints()
    frame:SetParent(anchor)
    frame:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)

    -- Distance readout (for now just show, later you can replace with color/size logic)
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
    if not anchor or not anchor:IsShown() then
        -- No anchor => nothing on-screen to point at
        frame:Hide()
        frame.anchor = nil
        return
    end

    -- Don't double-indicate if mouseover == target/focus and you decide
    -- that reticles are "enough" – for now we allow it, but you can
    -- uncomment this block if you want to suppress:
    --
    if UnitIsUnit("mouseover", "target") or UnitIsUnit("mouseover", "focus") then
        frame:Hide()
        frame.anchor = nil
        return
    end

    frame.anchor = anchor

    frame:ClearAllPoints()
    frame:SetParent(anchor)
    -- Slightly above the nameplate/head, pointing down
    frame:SetPoint("BOTTOM", anchor, "TOP", 0, 14)

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

    -- Target / focus reticles
    UpdateReticleForUnit("target", Ret.frames.target, { offsetX = 0, offsetY = -8 })
    UpdateReticleForUnit("focus",  Ret.frames.focus,  { offsetX = 0, offsetY = -8 })

    -- Mouseover indicator
    UpdateMouseoverIndicator(Ret.frames.mouseover)
end

function Ret.Init()
    if driver then
        return
    end

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
