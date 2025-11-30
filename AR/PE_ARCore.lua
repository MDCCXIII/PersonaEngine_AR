local MODULE = "AR Core"

-- ##################################################
-- AR/PE_ARCore.lua
-- PersonaEngine: Augmented Reality HUD core
-- Standalone-friendly, optional feature module.
-- No global UI hiding; this only drives AR subsystems.
-- ##################################################

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    -- Allow clean removal / standalone experiments.
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

------------------------------------------------------
-- State
------------------------------------------------------

AR.enabled     = true   -- runtime toggle for all AR visuals
AR.initialized = false
AR.expanded    = false  -- compact vs expanded HUD (Alt mode, etc.)

------------------------------------------------------
-- Local helpers
------------------------------------------------------

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return
    end
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

------------------------------------------------------
-- Public API
------------------------------------------------------

function AR.IsEnabled()
    return AR.enabled and AR.initialized
end

function AR.SetEnabled(flag)
    AR.enabled = not not flag

    -- Core HUD overlay (nameplate HUD)
    if AR.HUD then
        if AR.enabled and AR.HUD.Refresh then
            AR.HUD.Refresh("ENABLE_TOGGLE")
        elseif not AR.enabled and AR.HUD.HideAll then
            AR.HUD.HideAll()
        end
    end

    -- Screen-space target panel
    if AR.TargetPanel and AR.TargetPanel.ForceUpdate then
        AR.TargetPanel.ForceUpdate()
    end

    -- Reticle overlay
    if AR.Reticle and AR.Reticle.SetEnabled then
        AR.Reticle.SetEnabled(AR.enabled)
    end

    -- Blizzard frame hider (unit / cast bars)
    if AR.BlizzHider and AR.BlizzHider.SetEnabled then
        AR.BlizzHider.SetEnabled(AR.enabled)
    end
end

function AR.IsExpanded()
    return AR.expanded and AR.enabled and AR.initialized
end

function AR.SetExpanded(flag)
    AR.expanded = not not flag

    -- Let HUD react if it cares about compact vs expanded
    if AR.HUD and AR.HUD.Refresh then
        AR.HUD.Refresh("EXPAND_TOGGLE")
    end

    if AR.TargetPanel and AR.TargetPanel.ForceUpdate then
        AR.TargetPanel.ForceUpdate()
    end
end

-- For other systems to query a “snapshot” of what AR sees
function AR.GetCurrentSnapshot()
    if not AR.IsEnabled()
        or not AR.Scanner
        or not AR.Scanner.BuildSnapshot
    then
        return nil
    end

    return AR.Scanner.BuildSnapshot()
end

------------------------------------------------------
-- Init / event wiring
------------------------------------------------------

local frame

local function OnEvent(self, event, ...)
    if not AR.enabled and event ~= "PLAYER_LOGIN" then
        return
    end

    if event == "PLAYER_LOGIN" then
        -- Initialize scanner + HUD lazily
        SafeCall(AR.Scanner and AR.Scanner.Init)
        SafeCall(AR.HUD and AR.HUD.Init)
        SafeCall(AR.TargetPanel and AR.TargetPanel.Init)
        SafeCall(AR.Reticle and AR.Reticle.Init)

        AR.initialized = true

        -- Initial sync
        AR.SetEnabled(AR.enabled)
    end

    -- Pass other events down to scanner/HUD as they care
    SafeCall(AR.Scanner and AR.Scanner.OnEvent, event, ...)
    SafeCall(AR.HUD and AR.HUD.OnEvent, event, ...)
end

local function CreateEventFrame()
    if frame then
        return
    end

    -- Core AR event dispatcher
    frame = CreateFrame("Frame", "PE_AR_EventFrame", UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetFrameLevel(0)

    frame:SetScript("OnEvent", OnEvent)
    frame:RegisterEvent("PLAYER_LOGIN")

    -- Scanner/HUD can ask ARCore to register more via helper
end

function AR.RegisterEvent(evt)
    if not frame then
        CreateEventFrame()
    end
    frame:RegisterEvent(evt)
end

-- Kick off
CreateEventFrame()

------------------------------------------------------
-- Slash command: simple AR toggle
------------------------------------------------------

SLASH_PE_ARHUD1 = "/pearhud"
SlashCmdList["PE_ARHUD"] = function(msg)
    AR.SetEnabled(not AR.enabled)

    local state = AR.enabled and "|cff20ff70ENABLED|r" or "|cffff4040DISABLED|r"
    DEFAULT_CHAT_FRAME:AddMessage(
        string.format("|cFF00FF98[PersonaEngine AR]|r HUD %s", state)
    )
end

----------------------------------------------------
-- Module registration
----------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Core", {
    name  = "AR Core Systems",
    class = "AR HUD",
})
