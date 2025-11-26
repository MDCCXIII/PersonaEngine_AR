local MODULE = "AR Core"
-- ##################################################
-- AR/PE_ARCore.lua
-- PersonaEngine: Augmented Reality HUD core
-- Standalone-friendly, optional feature module.
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

AR.enabled     = true   -- runtime toggle
AR.initialized = false
AR.expanded    = false  -- compact vs expanded HUD

-- Copporclang "vision mode" state:
--  - visionEnabled: whether UIParent alpha is being driven by AR
--  - prevUIParentAlpha: remember user's normal UI alpha
--  - editMode: when true, temporarily show normal UI while visor is on
AR.visionEnabled     = false
AR.prevUIParentAlpha = nil
AR.editMode          = false

------------------------------------------------------
-- Frames we keep visible in visor mode
------------------------------------------------------

local preservedFrames = {}


--[[
Lua pattern quick-ref (for preservedNames):
  ^X      = match at start of string (e.g. "^ChatFrame")
  X$      = match at end of string   (e.g. "EditBox$")
  .       = any single character
  %d      = digit 0–9
  %a      = letter A–Z or a–z
  %w      = alphanumeric (letter or digit)
  %s      = whitespace
  %u / %l = uppercase / lowercase letter

  *       = 0 or more repeats  (".*"  = any length)
  +       = 1 or more repeats  ("%d+" = one or more digits)
  -       = 0 or more (non-greedy)
  ?       = 0 or 1

  []      = character set       ("[123]"  = 1 or 2 or 3)
            ranges allowed      ("[A-Z]"  = uppercase)
  [^ ]    = negated set         ("[^0-9]" = not a digit)

  %       = escape magic chars  ("%%"="%", "%."=".", "%["="[")

Examples:
  "^ChatFrame"          -> anything starting with "ChatFrame"
  "^ChatFrame%d+$"      -> ChatFrame1, ChatFrame2, ...
  "^ChatFrame%d+EditBox$" -> ChatFrame1EditBox, etc.
  "^Minimap"            -> Minimap, MinimapCluster, etc.
  "^TitanPanel"         -> all Titan Panel bars/buttons
]]--

-- Treat each entry as a Lua pattern, not just an exact name.
-- Plain strings still work (they just match themselves).
local preservedNames = {
	-- minimap / chat
	"^Minimap",          -- Minimap, MinimapCluster, etc.
	"^ChatFrame%d$",     -- ChatFrame1..4
	"^ChatFrame%d+EditBox$", -- ChatFrame1EditBox.. etc.

	-- Titan Panel (your bar name + any TitanPanel* stuff)
	"Titan",

	-- common UI panels/menus
	"^GameMenuFrame$",
	"^WorldMapFrame$",
	"^CharacterFrame$",
	"^SpellBookFrame$",
	"^QuestLogFrame$",
	"^FriendsFrame$",
	"^PVEFrame$",

	-- addons
	"^PersonaEngine",
	"^TomTomBlock$",
}

local deniedNames = {
    "Tooltip",     -- blocks GameTooltip, GameTooltipTextLeft1, etc.
}

local function NameMatchesPreserved(name)
	-- deny first
    for _, pat in ipairs(deniedNames) do
        if name:match(pat) then
            return false
        end
    end

    -- allow second
    for _, pat in ipairs(preservedNames) do
        if name:match(pat) then
            return true
        end
    end

    return false
end

local function IsFrameObject(f)
    local ft = type(f)
    if ft ~= "table" and ft ~= "userdata" then
        return false
    end

    -- Safely ask what kind of object this is
    local ok, objType = pcall(function()
        if f.GetObjectType then
            return f:GetObjectType()
        end
        return nil
    end)

    return ok and type(objType) == "string" -- "Frame", "Button", etc.
end

local function EnsurePreservedFrames()
    -- scan globals once and mark anything whose *name* matches
    for gName, f in pairs(_G) do
        if type(gName) == "string"
            and NameMatchesPreserved(gName)
            and not preservedFrames[f]
            and IsFrameObject(f)          -- <-- only real frame-like objects
        then
            if f.SetIgnoreParentAlpha then
                f:SetIgnoreParentAlpha(true)
            end
            preservedFrames[f] = true
        end
    end

    -- PersonaEngine minimap icon (extra safety)
    if PE and PE.Icon and PE.Icon.button and not preservedFrames[PE.Icon.button] then
        if PE.Icon.button.SetIgnoreParentAlpha then
            PE.Icon.button:SetIgnoreParentAlpha(true)
        end
        preservedFrames[PE.Icon.button] = true
    end
end


------------------------------------------------------
-- Local helpers
------------------------------------------------------

-- ScreamCall (your original version)
local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

------------------------------------------------------
-- Public API (core)
------------------------------------------------------

function AR.IsEnabled()
    return AR.enabled and AR.initialized
end

function AR.SetEnabled(flag)
    AR.enabled = not not flag

    if AR.enabled and AR.initialized and AR.HUD and AR.HUD.Refresh then
        AR.HUD.Refresh("ENABLE_TOGGLE")
    elseif not AR.enabled and AR.HUD and AR.HUD.HideAll then
        AR.HUD.HideAll()
    end
end

function AR.IsExpanded()
    return AR.expanded and AR.enabled and AR.initialized
end

-- For other systems to query a “snapshot” of what AR sees
function AR.GetCurrentSnapshot()
    if not AR.IsEnabled() or not AR.Scanner or not AR.Scanner.BuildSnapshot then
        return nil
    end
    return AR.Scanner.BuildSnapshot()
end

------------------------------------------------------
-- Public API (vision / visor control)
------------------------------------------------------

function AR.IsVisionEnabled()
    return AR.visionEnabled
end

-- Fade the default UI out / in via UIParent alpha.
-- AR HUD + AR TargetPanel use SetIgnoreParentAlpha(true) so they stay visible.
function AR.SetVisionEnabled(flag)
    flag = not not flag
    AR.visionEnabled = flag

    local parent = _G.UIParent
    if not parent then return end

    if flag then
        -- entering visor mode
        EnsurePreservedFrames()

        if AR.prevUIParentAlpha == nil then
            AR.prevUIParentAlpha = parent:GetAlpha() or 1
        end

        if not AR.editMode then
            -- fade out the *global* UI
            parent:SetAlpha(0)
        end

        -- make sure preserved frames stay visible
        for f in pairs(preservedFrames) do
            if f.SetAlpha then
                f:SetAlpha(1)
            end
        end
    else
        -- leaving visor mode: restore global alpha
        local restore = AR.prevUIParentAlpha or 1
        parent:SetAlpha(restore)
    end
end


function AR.ToggleVision()
    AR.SetVisionEnabled(not AR.visionEnabled)
end

-- While visor is ON, temporarily show bars / normal UI so user can rearrange.
function AR.ToggleEditMode()
    local parent = _G.UIParent
    if not parent or not AR.visionEnabled then
        return
    end

    AR.editMode = not AR.editMode

    if AR.editMode then
        -- show their original UI alpha
        local restore = AR.prevUIParentAlpha or parent:GetAlpha() or 1
        parent:SetAlpha(restore)
    else
        -- drop back into pure visor view
        parent:SetAlpha(0)
    end
end


-- One button to toggle “full Copporclang visor”:
--  - Vision (UI fade) on/off
--  - Make sure AR subsystems are initialized when turning it on
function AR.ToggleFullHUD()
    local entering = not AR.visionEnabled

    -- If we’re entering visor mode, make sure AR core bits are ready.
    if entering and not AR.initialized then
        SafeCall(AR.Scanner     and AR.Scanner.Init)
        SafeCall(AR.HUD         and AR.HUD.Init)
        SafeCall(AR.TargetPanel and AR.TargetPanel.Init)
        SafeCall(AR.Tooltips    and AR.Tooltips.Init)
        AR.initialized = true
    end

    -- We leave AR.enabled alone; visor is just “how we see”
    AR.SetVisionEnabled(entering)

    if AR.TargetPanel and AR.TargetPanel.ForceUpdate then
        SafeCall(AR.TargetPanel.ForceUpdate)
    end

    if AR.Tooltips and AR.Tooltips.OnARModeChanged then
        SafeCall(AR.Tooltips.OnARModeChanged)
    end
end



------------------------------------------------------
-- Init / event wiring
------------------------------------------------------

local frame

local function OnEvent(self, event, ...)
    if not AR.enabled then return end

    if event == "PLAYER_LOGIN" then
        -- Initialize scanner + HUD lazily
        SafeCall(AR.Scanner and AR.Scanner.Init)
        SafeCall(AR.HUD     and AR.HUD.Init)
        -- Also make sure the AR Target Panel is initialized
        SafeCall(AR.TargetPanel and AR.TargetPanel.Init)
		SafeCall(AR.Tooltips    and AR.Tooltips.Init)


        AR.initialized = true
    end

    -- Pass other events down to scanner/HUD as they care
    SafeCall(AR.Scanner and AR.Scanner.OnEvent, event, ...)
    SafeCall(AR.HUD     and AR.HUD.OnEvent, event, ...)
end

local function CreateEventFrame()
    if frame then return end

    frame = CreateFrame("Frame", "PE_ARCoreFrame", UIParent)
    frame:SetScript("OnEvent", OnEvent)
    frame:RegisterEvent("PLAYER_LOGIN") -- Scanner/HUD can ask ARCore to register more via helper
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
-- Slash commands for quick toggles
------------------------------------------------------

-- /pearhud      -> toggle full AR HUD (logic + vision)
-- /pearhud edit -> toggle "show bars" edit mode while visor is on
-- /pearhud vis  -> toggle vision only (keep AR logic state)
SLASH_PE_ARHUD1 = "/pearhud"
SLASH_PE_ARHUD2 = "/pear"

SlashCmdList.PE_ARHUD = function(msg)
    msg = (msg or ""):lower()

    if msg == "edit" or msg == "bars" or msg == "ui" then
        AR.ToggleEditMode()
    elseif msg == "vis" or msg == "vision" then
        AR.ToggleVision()
    else
        AR.ToggleFullHUD()
    end
end

SLASH_PEARHUDTIPS1 = "/pearhudtips"
SlashCmdList["PEARHUDTIPS"] = function(msg)
    print("|cff00ffff[PersonaEngine:AR]|r Tooltip HUD is currently disabled.")
end


----------------------------------------------------
-- Module registration
----------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Core", {
    name  = "AR Core Systems",
    class = "AR HUD",
})
