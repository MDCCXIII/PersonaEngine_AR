-- ##################################################
-- AR/UI/PE_UIARHUD.lua
-- AR HUD logic: decides *who* gets a HUD and *when*.
-- All visuals delegated to AR.HUDSkin.
-- ##################################################

local MODULE = "AR HUD"

local PE = _G.PE
if not PE then
    print("|cffff0000[PersonaEngine] AR HUD: PE missing at load.|r")
    return
end

-- Make sure AR namespace exists even if ARCore hasn't run yet
PE.AR = PE.AR or {}
local AR = PE.AR

AR.HUD = AR.HUD or {}
local HUD = AR.HUD

HUD.lastTargetGUID  = nil
HUD.lastApplyTime   = 0
HUD.hideGraceWindow = 0.2  -- seconds to wait before hiding on “no data”

local MAX_FRAMES = 1 -- 1= only target HUD

-- Set this to false if you ever want Blizzard nameplates visible again.
local HIDE_BASE_NAMEPLATES = true

------------------------------------------------------
-- Helper: always fetch the current skin table
------------------------------------------------------

local function GetSkin()
    return AR.HUDSkin
end

------------------------------------------------------
-- Nameplate hiding helpers
------------------------------------------------------

local function HideBasePlateVisuals(plate)
    if not HIDE_BASE_NAMEPLATES or not plate then
        return
    end

    -- Try the default UnitFrame first (Dragonflight/Retail)
    local uf = plate.UnitFrame or plate.unitFrame
    if uf and uf.SetAlpha then
        uf:SetAlpha(0)
    end

    -- Hide any direct regions on the plate that aren't AR HUD bits
    local regions = { plate:GetRegions() }
    for _, region in ipairs(regions) do
        if region and not region.peIsARHUD and region.SetAlpha then
            region:SetAlpha(0)
        end
    end

    -- Hide direct child frames that aren't AR HUD frames
    local numChildren = plate:GetNumChildren()
    for i = 1, numChildren do
        local child = select(i, plate:GetChildren())
        if child and not child.peIsARHUD and child.SetAlpha then
            child:SetAlpha(0)
        end
    end
end

local function ApplyHideAllBaseNameplates()
    if not HIDE_BASE_NAMEPLATES or not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end

    local plates = C_NamePlate.GetNamePlates()
    if not plates then return end

    for _, plate in ipairs(plates) do
        HideBasePlateVisuals(plate)
    end
end

------------------------------------------------------
-- HUD lifecycle
------------------------------------------------------

function HUD.Init()
    -- Frames come from HUDSkin
    ApplyHideAllBaseNameplates()

    -- Event-driven updates
    AR.RegisterEvent("PLAYER_TARGET_CHANGED")
    AR.RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    AR.RegisterEvent("NAME_PLATE_UNIT_ADDED")
    AR.RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

function HUD.OnEvent(event, ...)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
        HideBasePlateVisuals(plate)
    end

    HUD.Refresh(event, ...)
end

function HUD.HideAll()
    local Skin = GetSkin()
    if Skin and Skin.HideAll then
        Skin.HideAll()
    end
end

------------------------------------------------------
-- Main refresh
------------------------------------------------------

function HUD.Refresh(reason)
    local Skin = GetSkin()

    if not (AR.IsEnabled and AR.IsEnabled()) or not Skin or not Skin.GetFrame then
        HUD.HideAll()
        return
    end

    -- If we don't even have a target, no HUD.
    if not UnitExists("target") then
        HUD.HideAll()
        return
    end

    local snapshot = AR.GetCurrentSnapshot and AR.GetCurrentSnapshot()
    local targetGUID = UnitGUID("target")

    -- Try to find the snapshot entry for our current target.
    local targetEntry = nil
    if snapshot and #snapshot > 0 and targetGUID then
        for _, entry in ipairs(snapshot) do
            if entry.guid == targetGUID then
                targetEntry = entry
                break
            end
        end
    end

    -- If scanner didn't give us anything yet, just bail quietly this tick
    -- without hiding. Next tick will likely catch up.
    if not targetEntry then
        return
    end

    local expanded = AR.IsExpanded and AR.IsExpanded()

    -- Single HUD frame for target only
    local SkinNow = GetSkin()
    local frame   = SkinNow and SkinNow.GetFrame and SkinNow.GetFrame(1)

    if not frame then
        return
    end

    local unit  = "target"               -- FORCE: always use real target unit
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    local data  = targetEntry.data

    -- If we can't find a plate or data, don't spam hide/show: just skip this tick.
    if not (plate and data) then
        return
    end

    HideBasePlateVisuals(plate)

    local ctx = {
        role      = "target",
        isPrimary = true,
        expanded  = expanded,
    }

    SkinNow.Apply(frame, plate, targetEntry, ctx)
end





----------------------------------------------------
-- Module registration
----------------------------------------------------

if PE.LogInit then
    PE.LogInit(MODULE)
end

if PE.RegisterModule then
    PE.RegisterModule("AR HUD", {
        name  = "AR HUD",
        class = "AR HUD",
    })
end
