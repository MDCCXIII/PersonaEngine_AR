-- ##################################################
-- AR/PE_ARGoggles.lua
-- PersonaEngine AR: Visor (Goggles) cloaking system
--
-- Behavior:
--   * Determine "visor ON" from, in priority order:
--       1) Head transmog visual
--       2) Equipped head item
--       3) Player buff(s)
--
--   * When visor is OFF:
--       - For every frame discovered via EnumerateFrames():
--           * If its frame strata / level are BELOW a configurable cutoff,
--             and it is not explicitly exempt (nor a child of an exempt),
--             alpha is set to 0 and mouse clicks are disabled.
--           * Any frame whose name or ancestor matches FORCE_HIDE rules
--             is also hidden, regardless of strata/level.
--
--   * When visor is ON:
--       - Any frame we previously modified has its original alpha restored
--         and its original mouse-enabled state restored.
--
-- We use SetAlpha (not Hide/Show) to avoid secure taint wherever possible.
-- ##################################################

local MODULE = "AR Goggles"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Goggles = AR.Goggles or {}
local Goggles = AR.Goggles

------------------------------------------------------
-- CONFIG: Visor sources (transmog / item / buff)
------------------------------------------------------

-- 1) Head transmog visuals
-- These are APPEARANCE VISUAL IDs, not item IDs.
-- You can find them with:
--   /dump C_Transmog.GetSlotVisualInfo(INVSLOT_HEAD, Enum.TransmogType.Appearance)
-- and inspecting the returned values.
local VISOR_HEAD_TRANSMOG_VISUAL_IDS = {
    -- [12345] = true, -- example visual ID
}

-- 2) Equipped head items (item IDs in the HEAD slot)
-- If any of these is actually equipped, visor counts as ON.
local VISOR_HEAD_ITEM_IDS = {
    -- [ITEM_ID_HERE] = true, -- example item ID
}

-- 3) Buff names
-- Any of these buff names on the player will turn visor ON
-- (if no transmog or equipped item matched first).
local VISOR_BUFF_NAMES = {
    "Tricked-Out Thinking Cap",
    "Tricked Out Thinking Cap",
}

------------------------------------------------------
-- CONFIG: Strata / frame level cutoff
------------------------------------------------------
-- Frame strata in WoW, from lowest to highest draw order:
--
--   "BACKGROUND"        (1) - Behind almost everything
--   "LOW"               (2)
--   "MEDIUM"            (3)
--   "HIGH"              (4)
--   "DIALOG"            (5)
--   "FULLSCREEN"        (6)
--   "FULLSCREEN_DIALOG" (7)
--   "TOOLTIP"           (8) - Topmost, e.g. tooltips
--
-- Frame level is an integer; higher numbers draw on top of lower ones
-- *within the same strata*. Typical UI frames are in the ~0-50 range,
-- but can go higher.
--
-- The rule we use when visor is OFF:
--
--   * If frameStrataRank <  cutoffStrataRank -> HIDE
--   * If frameStrataRank == cutoffStrataRank
--          AND frameLevel <= cutoffFrameLevel -> HIDE
--   * Else -> do not touch (unless forced by name/prefix)
--

-- Your requested default:
local GOGGLES_MIN_STRATA_NAME = "LOW" -- change to any listed above
local GOGGLES_MIN_FRAME_LEVEL = 50    -- integer level cutoff

-- Mapping of strata names to an ordered rank
local STRATA_ORDER = {
    BACKGROUND        = 1,
    LOW               = 2,
    MEDIUM            = 3,
    HIGH              = 4,
    DIALOG            = 5,
    FULLSCREEN        = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP           = 8,
}

------------------------------------------------------
-- CONFIG: Explicit per-frame overrides
------------------------------------------------------

-- NEVER_HIDE_NAMES:
-- Frames we will *never* alter, regardless of strata/level,
-- and all of their children / descendants are also exempt.
-- Keys can be:
--   * Exact names: "WorldMapFrame"
--   * Patterns:    "^WorldMap", "^Blizzard_.*"
local NEVER_HIDE_NAMES = {
    -- System / menus
    ["GameMenuFrame"]       = true,
    ["WorldMapFrame"]       = true,
    ["CharacterFrame"]      = true,
    ["SpellBookFrame"]      = true,
    ["CollectionsJournal"]  = true,
    ["EncounterJournal"]    = true,
    ["AdventureJournal"]    = true,
    ["HelpFrame"]           = true,
    ["PVEFrame"]            = true,
    ["KeyBindingFrame"]     = true,
    ["FriendsFrame"]        = true,
    ["GuildFrame"]          = true,
    ["CommunitiesFrame"]    = true,

    -- Bags: we generally want these to appear when opened
    ["ContainerFrame1"]     = true,
    ["ContainerFrame2"]     = true,
    ["ContainerFrame3"]     = true,
    ["ContainerFrame4"]     = true,
    ["ContainerFrame5"]     = true,
    ["ContainerFrame6"]     = true,
    ["ContainerFrame7"]     = true,

    -- Extra/Zone abilities should always stay visible
    ["ExtraActionBarFrame"] = true,
    ["ZoneAbilityFrame"]    = true,
	
	["MinimapCluster"]        = true,
	["ObjectiveTrackerFrame"] = true,
}

-- FORCE_HIDE_NAMES:
-- Frames we ALWAYS cloak when visor is OFF, *even if* their
-- strata/level would normally survive the cutoff.
-- Keys can be:
--   * Exact names: "ObjectiveTrackerFrame"
--   * Patterns:    "^PE_AR", "^PE_UIAR"
local FORCE_HIDE_NAMES = {
    -- AR HUD by prefix:
    ["^PE_AR"]   = true,
    ["^PE_UIAR"] = true,

    -- You can add more if desired:
    -- ["ObjectiveTrackerFrame"] = true,
    -- ["MinimapCluster"]        = true,
	
	["PlayerFrame"] = true,
    ["PetFrame"] = true,
    ["TargetFrame"] = true,
    ["TargetFrameToT"] = true,
    ["FocusFrame"] = true,
    ["FocusFrameToT"] = true,

    -- Cast bars
    ["CastingBarFrame"] = true,
    ["PetCastingBarFrame"] = true,
    ["TargetFrameSpellBar"] = true,
    ["FocusFrameSpellBar"] = true,
	
	["NamePlate"] = true,
}

------------------------------------------------------
-- INTERNAL: state tracking
------------------------------------------------------

local LibStub       = _G.LibStub
local AuraUtil      = _G.AuraUtil
local C_Transmog    = _G.C_Transmog
local TransmogUtil  = _G.TransmogUtil
local EnumTbl       = _G.Enum or {}

local GetInventoryItemID = _G.GetInventoryItemID
local INVSLOT_HEAD       = _G.INVSLOT_HEAD or 1

-- frame -> { origAlpha = number, mouseEnabled = bool or nil }
local managed = {}

------------------------------------------------------
-- Split exact names vs patterns
------------------------------------------------------

local NEVER_HIDE_EXACT   = {}
local NEVER_HIDE_PATTERNS = {}

local FORCE_HIDE_EXACT    = {}
local FORCE_HIDE_PATTERNS = {}

local function BuildNameMaps()
    for key, flag in pairs(NEVER_HIDE_NAMES) do
        if flag and type(key) == "string" then
            -- Treat things that look like patterns as patterns:
            if key:find("^%^") or key:find("%.") or key:find("%*") or key:find("%+") or key:find("%-") or key:find("%$") or key:find("%[") or key:find("%(") then
                table.insert(NEVER_HIDE_PATTERNS, key)
            else
                NEVER_HIDE_EXACT[key] = true
            end
        end
    end

    for key, flag in pairs(FORCE_HIDE_NAMES) do
        if flag and type(key) == "string" then
            if key:find("^%^") or key:find("%.") or key:find("%*") or key:find("%+") or key:find("%-") or key:find("%$") or key:find("%[") or key:find("%(") then
                table.insert(FORCE_HIDE_PATTERNS, key)
            else
                FORCE_HIDE_EXACT[key] = true
            end
        end
    end
end

BuildNameMaps()

local function NameMatchesNeverHide(name)
    if not name then return false end
    if NEVER_HIDE_EXACT[name] then
        return true
    end
    for _, pat in ipairs(NEVER_HIDE_PATTERNS) do
        if name:match(pat) then
            return true
        end
    end
    return false
end

local function NameMatchesForceHide(name)
    if not name then return false end
    if FORCE_HIDE_EXACT[name] then
        return true
    end
    for _, pat in ipairs(FORCE_HIDE_PATTERNS) do
        if name:match(pat) then
            return true
        end
    end
    return false
end

------------------------------------------------------
-- Track & restore alpha + clickability
------------------------------------------------------

local function TrackAndSetAlpha(frame, alpha)
    if not frame
       or frame:IsForbidden()
       or type(frame.SetAlpha) ~= "function"
    then
        return
    end

    local rec = managed[frame]
    if not rec then
        rec = {}
        rec.origAlpha = frame:GetAlpha() or 1
        if frame.IsMouseEnabled and frame.EnableMouse then
            local ok, enabled = pcall(frame.IsMouseEnabled, frame)
            if ok then
                rec.mouseEnabled = enabled
            end
        end
        managed[frame] = rec
    end

    frame:SetAlpha(alpha or 0)

    -- Disable mouse clicks while hidden, if supported.
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
end

local function RestoreAlpha(frame)
    local rec = managed[frame]
    if not rec or not frame or frame:IsForbidden() then
        return
    end
    if type(frame.SetAlpha) ~= "function" then
        return
    end

    frame:SetAlpha(rec.origAlpha or 1)

    -- Restore original mouse-enabled state, if we captured one.
    if frame.EnableMouse and rec.mouseEnabled ~= nil then
        frame:EnableMouse(rec.mouseEnabled)
    end
end

------------------------------------------------------
-- Visor source checks
------------------------------------------------------

-- 1) Head transmog visual
local function HasConfiguredHeadTransmog()
    -- If no visuals configured, there's nothing to check.
    if not VISOR_HEAD_TRANSMOG_VISUAL_IDS
       or next(VISOR_HEAD_TRANSMOG_VISUAL_IDS) == nil
    then
        return false
    end

    -- Need all these bits or we bail out safely.
    if not C_Transmog
       or type(C_Transmog.GetSlotVisualInfo) ~= "function"
       or not TransmogUtil
       or type(TransmogUtil.CreateTransmogLocation) ~= "function"
       or not EnumTbl
       or not EnumTbl.TransmogType
       or not EnumTbl.TransmogModification
    then
        return false
    end

    -- Create a proper TransmogLocation for the head slot, appearance layer.
    local loc = TransmogUtil.CreateTransmogLocation(
        INVSLOT_HEAD,
        EnumTbl.TransmogType.Appearance,
        EnumTbl.TransmogModification.Main
    )
    if not loc then
        return false
    end

    -- Retail API: returns multiple values, not a table.
    local ok,
        baseSourceID, baseVisualID,
        appliedSourceID, appliedVisualID,
        pendingSourceID, pendingVisualID,
        hasUndo, isHideVisual, itemSubclass =
        pcall(C_Transmog.GetSlotVisualInfo, loc)

    if not ok then
        -- API signature mismatch or some other weirdness; fail quietly.
        return false
    end

    -- Prefer applied visual if present, otherwise fall back to base visual.
    local visualID = appliedVisualID
    if not visualID or visualID == 0 then
        visualID = baseVisualID
    end
    if not visualID or visualID == 0 then
        return false
    end

    return VISOR_HEAD_TRANSMOG_VISUAL_IDS[visualID] == true
end

-- 2) Equipped head item
local function HasConfiguredEquippedHeadItem()
    if not GetInventoryItemID then
        return false
    end
    local itemID = GetInventoryItemID("player", INVSLOT_HEAD)
    if not itemID then
        return false
    end
    return VISOR_HEAD_ITEM_IDS[itemID] == true
end

-- 3) Buffs
local function HasConfiguredBuff()
    if not VISOR_BUFF_NAMES or #VISOR_BUFF_NAMES == 0 then
        return false
    end

    if AuraUtil and AuraUtil.FindAuraByName then
        for _, buffName in ipairs(VISOR_BUFF_NAMES) do
            local aura = AuraUtil.FindAuraByName(buffName, "player", "HELPFUL")
            if aura then
                return true
            end
        end
        return false
    end

    -- Fallback for older APIs
    for _, wanted in ipairs(VISOR_BUFF_NAMES) do
        local i = 1
        while true do
            local name = _G.UnitBuff("player", i)
            if not name then
                break
            end
            if name == wanted then
                return true
            end
            i = i + 1
        end
    end
    return false
end

-- Priority:
--   1) Head transmog visual
--   2) Equipped head item
--   3) Buff
local function IsVisorOn()
    if HasConfiguredHeadTransmog() then
        return true
    end
    if HasConfiguredEquippedHeadItem() then
        return true
    end
    if HasConfiguredBuff() then
        return true
    end
    return false
end

------------------------------------------------------
-- Strata / level decision
------------------------------------------------------

local cutoffStrataRank = STRATA_ORDER[GOGGLES_MIN_STRATA_NAME] or STRATA_ORDER.HIGH
local cutoffFrameLevel = GOGGLES_MIN_FRAME_LEVEL or 0

------------------------------------------------------
-- NEVER_HIDE and FORCE_HIDE ancestor checks
------------------------------------------------------

local function IsChildOfNeverHide(frame)
    if not frame or type(frame) ~= "table" or not frame.GetParent then
        return false
    end

    local f = frame
    while f do
        local name = f:GetName()
        if name and NameMatchesNeverHide(name) then
            return true
        end
        f = f:GetParent()
    end

    return false
end

local function IsChildOfForceHide(frame)
    if not frame or type(frame) ~= "table" or not frame.GetParent then
        return false
    end

    local f = frame
    while f do
        local name = f:GetName()
        if name and NameMatchesForceHide(name) then
            return true
        end
        f = f:GetParent()
    end

    return false
end

------------------------------------------------------
-- Should we hide this frame when visor is OFF?
------------------------------------------------------

local function ShouldHideFrame(frame)
    if not frame
       or frame:IsForbidden()
       or type(frame.GetFrameStrata) ~= "function"
    then
        return false
    end

    -- Never touch frames that are themselves in NEVER_HIDE_NAMES
    -- or any of their descendants.
    if IsChildOfNeverHide(frame) then
        return false
    end

    -- Forced hides win over everything: name or ancestor match.
    if IsChildOfForceHide(frame) then
        return true
    end

    local strata = frame:GetFrameStrata() or "MEDIUM"
    local level  = frame:GetFrameLevel() or 0

    local strataRank = STRATA_ORDER[strata] or STRATA_ORDER.MEDIUM

    -- Lower strata than cutoff? Hide.
    if strataRank < cutoffStrataRank then
        return true
    end

    -- Same strata but lower/equal frame level than cutoff? Hide.
    if strataRank == cutoffStrataRank and level <= cutoffFrameLevel then
        return true
    end

    return false
end

------------------------------------------------------
-- Apply visor state
------------------------------------------------------

local currentVisorState -- true = ON, false = OFF

local function ApplyVisorState(visorOn)
    if currentVisorState == visorOn then
        return
    end
    currentVisorState = visorOn

    -- Enumerate all frames once per state change
    local f = EnumerateFrames()
    while f do
        local doTouch = false

        repeat
            if f:IsForbidden() then
                break
            end

            if type(f.GetObjectType) ~= "function"
               or f:GetObjectType() ~= "Frame"
            then
                break
            end

            if visorOn then
                -- When visor is ON, restore only frames we previously touched.
                if managed[f] then
                    doTouch = true
                end
            else
                -- When visor is OFF, decide from strata/level/overrides.
                if ShouldHideFrame(f) then
                    doTouch = true
                end
            end

        until true

        if doTouch then
            if visorOn then
                RestoreAlpha(f)
            else
                TrackAndSetAlpha(f, 0)
            end
        end

        f = EnumerateFrames(f)
    end
end

------------------------------------------------------
-- Event driver
------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

-- Transmog changes do NOT change item IDs, so we also listen for
-- transmog-specific events when available.
ev:RegisterEvent("TRANSMOGRIFY_SUCCESS")
ev:RegisterEvent("TRANSMOG_OUTFITS_CHANGED")

ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "UNIT_AURA" and arg1 ~= "player" then
        return
    end

    local visorOn = IsVisorOn()
    ApplyVisorState(visorOn)
end)

------------------------------------------------------
-- Slash command for debugging / forcing re-eval
------------------------------------------------------

SLASH_PEARGOGGLES1 = "/pearg"
SlashCmdList.PEARGOGGLES = function()
    local visorOn = IsVisorOn()
    print("|cffff7f00[PersonaEngine AR]|r Visor check:",
        visorOn and "|cff00ff00ON|r" or "|cffff0000OFF|r")
    ApplyVisorState(visorOn)
end

------------------------------------------------------
-- Registration
------------------------------------------------------

if PE.LogInit then
    PE.LogInit(MODULE)
end

if PE.RegisterModule then
    PE.RegisterModule(MODULE, {
        name  = "AR Goggles (Visor cloaking)",
        class = "AR HUD",
    })
end
