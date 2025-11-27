-- ##################################################
-- AR/UI/PE_UIARTargetPanel.lua
-- Target dossier, built from the generic UnitPanel.
-- ##################################################

local MODULE = "AR Target Panel"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR
local UnitPanel = AR.UnitPanel
if not UnitPanel or not UnitPanel.Create then
    return
end

------------------------------------------------------
-- Target-specific helpers
------------------------------------------------------

local function ColorForReaction(unit)
    if UnitIsEnemy("player", unit) then
        return 1.0, 0.25, 0.2
    elseif UnitIsFriend("player", unit) then
        return 0.2, 1.0, 0.7
    else
        return 1.0, 0.8, 0.25
    end
end

local function BuildLevelLine(unit)
    local level    = UnitLevel(unit) or -1
    local classif  = UnitClassification(unit) or "normal"
    local isPlayer = UnitIsPlayer(unit)

    local pieces = {}

    if level <= 0 then
        table.insert(pieces, "Lv ??")
    else
        table.insert(pieces, string.format("Lv %d", level))
    end

    if isPlayer then
        local race  = UnitRace(unit) or "Unknown"
        local class = UnitClass(unit) or "Adventurer"
        table.insert(pieces, race)
        table.insert(pieces, class)
    else
        local ctype = UnitCreatureType(unit) or "Creature"
        if classif == "worldboss" then
            table.insert(pieces, "WORLD BOSS")
        elseif classif == "elite" then
            table.insert(pieces, "ELITE")
        elseif classif == "rareelite" then
            table.insert(pieces, "RARE ELITE")
        elseif classif == "rare" then
            table.insert(pieces, "RARE")
        end
        table.insert(pieces, ctype)
    end

    local faction = UnitFactionGroup(unit)
    if faction then
        table.insert(pieces, faction)
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

    local dur = (endTime and startTime) and (endTime - startTime) / 1000 or 0
    local flag = notInterruptible and "|cffff4040LOCKED|r" or "|cff20ff50INTERRUPT|r"

    return string.format("CAST: %s  (%.1fs)  [%s]", name, dur, flag)
end

-- Optional fancy pose profiles: re-use your existing ones.
local PoseProfiles = {
    DEFAULT = {
        facing       = math.rad(15),
        pitch        = math.rad(2),
        camScale     = 1.05,
        offsetZ      = -0.08,
        portraitZoom = 0,
    },
    PLAYER = {
        facing       = math.rad(10),
        pitch        = math.rad(1),
        camScale     = 1.10,
        offsetZ      = -0.08,
        portraitZoom = 0,
    },
    ELITE = {
        facing       = math.rad(5),
        pitch        = math.rad(-2),
        camScale     = 1.20,
        offsetZ      = -0.02,
        portraitZoom = 0,
    },
    WORLD_BOSS = {
        facing       = math.rad(0),
        pitch        = math.rad(-6),
        camScale     = 1.40,
        offsetZ      = -0.05,
        portraitZoom = 0,
    },
    BEAST = {
        facing       = math.rad(20),
        pitch        = math.rad(-3),
        camScale     = 1.25,
        offsetZ      = -0.02,
        portraitZoom = 0,
    },
    MECHANICAL = {
        facing       = math.rad(-10),
        pitch        = math.rad(0),
        camScale     = 1.15,
        offsetZ      = -0.05,
        portraitZoom = 0,
    },
}

local function GetPoseProfileForUnit(unit)
    local profiles = PoseProfiles
    if not profiles then return nil end

    if UnitIsPlayer(unit) then
        return profiles.PLAYER or profiles.DEFAULT
    end

    local classif = UnitClassification(unit)
    if classif == "worldboss" then
        return profiles.WORLD_BOSS or profiles.ELITE or profiles.DEFAULT
    elseif classif == "elite" or classif == "rareelite" then
        return profiles.ELITE or profiles.DEFAULT
    end

    local ctype = UnitCreatureType(unit) or ""
    if ctype == "Beast" then
        return profiles.BEAST or profiles.DEFAULT
    elseif ctype == "Mechanical" then
        return profiles.MECHANICAL or profiles.DEFAULT
    end

    return profiles.DEFAULT
end

local function ApplyModelPose(unit, model)
    if not model or not unit then return end

    local profile = GetPoseProfileForUnit(unit)
    if not profile then return end

    if model.SetPortraitZoom then
        model:SetPortraitZoom(profile.portraitZoom or 0)
    end
    if model.SetCamDistanceScale then
        model:SetCamDistanceScale(profile.camScale or 1.1)
    end
    if model.SetPosition then
        model:SetPosition(0, 0, profile.offsetZ or 0)
    end

    if profile.facing and model.SetFacing then
        model:SetFacing(profile.facing)
    elseif profile.facing and model.SetRotation then
        model:SetRotation(profile.facing)
    end

    if profile.pitch and model.SetPitch then
        model:SetPitch(profile.pitch)
    end

    if model.SetAnimation then
        model:SetAnimation(0)
    end
    if model.SetPaused then
        model:SetPaused(true)
    end
end

------------------------------------------------------
-- Instantiate panel for "target"
------------------------------------------------------

AR.TargetPanel = UnitPanel.Create{
    unitToken   = "target",
    layoutKey   = "targetPanel",
    moduleKey   = MODULE,
    moduleName  = "AR Target Panel",
    size        = { w = 260, h = 300 },
    modelHeight = 220,
    showPowerBar = true,

    nameFunc    = function(unit) return UnitName(unit) or "Unknown Target" end,
    buildLine1  = BuildLevelLine,
    buildLine2  = nil, -- could add a “threat/status” line later
    accentColor = ColorForReaction,
    castLineFunc = BuildCastLine,
    poseFunc    = ApplyModelPose,

    noUnitText  = {
        title    = "No Target",
        subtitle = "Select a target to scan",
    },
}
