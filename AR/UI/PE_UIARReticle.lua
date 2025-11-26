-- ##################################################
-- PE_UIARReticle.lua
-- PersonaEngine AR - target-locked reticle + distance
-- ##################################################

local MODULE = "UI_ARReticle"
local PE     = _G.PE

if not PE or type(PE) ~= "table" then
    print("|cffff0000[PersonaEngine:AR] ERROR: PE table missing in " .. MODULE .. "|r")
    return
end

PE.AR = PE.AR or {}
local AR  = PE.AR

AR.Reticle = AR.Reticle or {}
local RT   = AR.Reticle

local frame, hLine, vLine, distFS
local enabled     = false
local updateAccum = 0

----------------------------------------------------
-- Helpers
----------------------------------------------------

local function HUDActive()
    -- For the reticle, "HUD active" just means visor is on.
    return AR and AR.visionEnabled
end

local function Clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

local function ComputeDistance()
    if not UnitExists("target") then
        return nil
    end

    local px, py, pz, pInst = UnitPosition("player")
    local tx, ty, tz, tInst = UnitPosition("target")

    if not px or not tx or pInst ~= tInst then
        return nil
    end

    local dx = tx - px
    local dy = ty - py
    -- z doesn’t really matter for “feel”, stick to 2D
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist
end

-- Distance → reticle scale:
--   closer = bigger, farther = smaller, but clamped.
local function ScaleForDistance(dist)
    if not dist then
        return 1.0
    end

    -- 10y => 1.0, 5y => 1.6, 40y => ~0.25
    local inv  = 10 / Clamp(dist, 2, 60)
    local s    = inv * 1.0
    return Clamp(s, 0.3, 1.8)
end

----------------------------------------------------
-- Frame creation
----------------------------------------------------

local function EnsureFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "PE_ARHUD_Reticle", UIParent)
    frame:SetIgnoreParentAlpha(true)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(80)
    frame:SetSize(120, 120)
    frame.peIsARHUD = true -- don’t get alpha-wiped by our nameplate hider
    frame:Hide()

    -- Horizontal line
    hLine = frame:CreateTexture(nil, "OVERLAY")
    hLine:SetColorTexture(0, 1, 1, 0.7)
    hLine:SetHeight(2)
    hLine:SetPoint("CENTER", frame, "CENTER", 0, 0)

    -- Vertical line
    vLine = frame:CreateTexture(nil, "OVERLAY")
    vLine:SetColorTexture(0, 1, 1, 0.7)
    vLine:SetWidth(2)
    vLine:SetPoint("CENTER", frame, "CENTER", 0, 0)

    -- Distance label (yards)
    distFS = frame:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    distFS:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    distFS:SetJustifyH("CENTER")
    distFS:SetText("")

    frame:SetScript("OnUpdate", function(self, elapsed)
        if not enabled or not HUDActive() then
			self:Hide()
			return
		end

        updateAccum = updateAccum + elapsed
        if updateAccum < 0.05 then
            return
        end
        updateAccum = 0

        -- Anchor to target's nameplate if possible
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
        if plate then
            self:SetParent(plate)
            self:ClearAllPoints()
            self:SetPoint("CENTER", plate, "CENTER", 0, 0)
        else
            -- Fallback: center-screen if no nameplate available
            self:SetParent(UIParent)
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end

        -- Distance + scale
        local dist = ComputeDistance()
        if dist and distFS then
            distFS:SetText(string.format("%.1f yd", dist))
        else
            distFS:SetText("")
        end

        local scale = ScaleForDistance(dist)
        local baseLen = 80

        if hLine then
            hLine:SetWidth(baseLen * scale)
        end
        if vLine then
            vLine:SetHeight(baseLen * scale)
        end

        self:Show()
    end)

    return frame
end

----------------------------------------------------
-- Public API
----------------------------------------------------

function RT.Init()
    EnsureFrame()
end

function RT.SetEnabled(flag)
    enabled = not not flag
    if not flag and frame then
        frame:Hide()
    end
end

function RT.UpdateVisibility()
    if not frame then
        EnsureFrame()
    end

    if enabled and HUDActive() and UnitExists("target") then
        frame:Show()
    else
        frame:Hide()
    end
end

----------------------------------------------------
-- Module registration
----------------------------------------------------

if PE.LogInit then
    PE.LogInit(MODULE)
end

if PE.RegisterModule then
    PE.RegisterModule("AR Reticle", {
        name  = "AR HUD Reticle",
        class = "AR HUD",
    })
end
