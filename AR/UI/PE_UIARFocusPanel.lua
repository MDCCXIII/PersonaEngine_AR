-- ##################################################
-- AR/UI/PE_UIARFocusPanel.lua
-- Focus dossier, same skin as Target.
-- ##################################################

local MODULE = "AR Focus Panel"

local PE = _G.PE
if not PE or type(PE) ~= "table" then return end
PE.AR = PE.AR or {}
local AR = PE.AR
local UnitPanel = AR.UnitPanel
if not UnitPanel or not UnitPanel.Create then return end

-- Reuse helpers from TargetPanel if loaded, otherwise re-declare quickly
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

AR.FocusPanel = UnitPanel.Create{
    unitToken   = "focus",
    layoutKey   = "focusPanel",
    moduleKey   = MODULE,
    moduleName  = "AR Focus Panel",
    size        = { w = 260, h = 300 },
    modelHeight = 220,
    showPowerBar = true,

    nameFunc    = function(unit) return UnitName(unit) or "Unknown Focus" end,
    buildLine1  = BuildLevelLine,
    buildLine2  = nil,
    accentColor = ColorForReaction,
    castLineFunc = BuildCastLine,

    noUnitText  = {
        title    = "No Focus",
        subtitle = "Set a focus to scan",
    },
}

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Focus Panel", {
    name  = "AR Focus Panel",
    class = "AR HUD",
})
