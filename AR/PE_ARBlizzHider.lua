-- ##################################################
-- AR/PE_ARBlizzHider.lua
-- PersonaEngine AR: Explicit Blizzard frame hider
-- Hides default unit/cast frames via alpha only.
-- ##################################################

local MODULE = "AR Blizzard Hider"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.BlizzHider = AR.BlizzHider or {}
local Hider = AR.BlizzHider

------------------------------------------------------
-- Config: which frames we blank out
-- (You can comment lines out while you work.)
------------------------------------------------------

local FRAME_NAMES = {
    -- Core unit frames
    "PlayerFrame",
    "PetFrame",
    "TargetFrame",
    "TargetFrameToT",
    "FocusFrame",
    "FocusFrameToT",

    -- Cast bars
    -- "CastingBarFrame",
    -- "PetCastingBarFrame",
    -- "TargetFrameSpellBar",
    -- "FocusFrameSpellBar",
	
	"NamePlate",
}

------------------------------------------------------
-- State
------------------------------------------------------

Hider.enabled       = false
Hider.originalAlpha = Hider.originalAlpha or {}

------------------------------------------------------
-- Internal helpers
------------------------------------------------------

local function ApplyToFrame(frame, enabled)
    if not frame or frame:IsForbidden() then
        return
    end

    -- Remember original alpha
    local orig = Hider.originalAlpha[frame]
    if not orig then
        Hider.originalAlpha[frame] = frame:GetAlpha() or 1
        orig = Hider.originalAlpha[frame]
    end

    if enabled then
        frame:SetAlpha(0)     -- visually gone, still exists
    else
        frame:SetAlpha(orig)  -- restore whatever it had
    end
end

local function ApplyAll(enabled)
    for _, name in ipairs(FRAME_NAMES) do
        local f = _G[name]
        if f then
            ApplyToFrame(f, enabled)
        end
    end
end

------------------------------------------------------
-- Public API
------------------------------------------------------

function Hider.SetEnabled(flag)
    flag = not not flag
    if flag == Hider.enabled then
        return
    end

    Hider.enabled = flag
    ApplyAll(flag)
end

function Hider.Refresh()
    if not Hider.enabled then
        return
    end
    ApplyAll(true)
end

function Hider.Init()
    -- Nothing fancy yet; just make sure first application happens
    -- once frames exist (after PLAYER_LOGIN).
    Hider.Refresh()
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Blizzard Hider", {
    name  = "AR Blizzard Hider",
    class = "AR HUD",
})
