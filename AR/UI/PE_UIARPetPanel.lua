-- ##################################################
-- AR/UI/PE_UIARPetPanel.lua
-- Player pet dossier built from the generic UnitPanel.
-- Smaller card, HP-only, only visible when you actually
-- have a pet.
-- ##################################################

local MODULE = "AR Pet Panel"

local PE = _G.PE
if not PE or type(PE) ~= "table" then return end

PE.AR = PE.AR or {}
local AR = PE.AR

local UnitPanel = AR.UnitPanel
if not UnitPanel or not UnitPanel.Create then
    -- Failsafe so you see something in chat if load order is wrong
    print("|cffff0000[PersonaEngine_AR] AR.UnitPanel missing for PetPanel|r")
    return
end

------------------------------------------------------
-- Pet-specific helpers
------------------------------------------------------

local function PetName(unit)
    return UnitName(unit) or "No Active Pet"
end

local function PetLine(unit)
    local level = UnitLevel(unit) or -1
    local ctype = UnitCreatureType(unit) or "Mechanical"
    local pieces = {}

    if level <= 0 then
        table.insert(pieces, "Lv ??")
    else
        table.insert(pieces, string.format("Lv %d", level))
    end

    table.insert(pieces, ctype)

    local family = UnitCreatureFamily and UnitCreatureFamily(unit)
    if family and family ~= ctype then
        table.insert(pieces, family)
    end

    return table.concat(pieces, " • ")
end

local function PetAccent(unit)
    -- Ride along with Copporclang’s cyan
    return 0.2, 1.0, 0.7
end

-- Pets don’t really need a cast line right now
local function EmptyCastLine(unit)
    return ""
end

------------------------------------------------------
-- Instantiate panel for "pet"
------------------------------------------------------

AR.PetPanel = UnitPanel.Create{
    unitToken     = "pet",
    layoutKey     = "petPanel",
    moduleKey     = MODULE,
    moduleName    = "AR Pet Panel",

    size          = { w = 220, h = 260 },
    modelHeight   = 180,
    showPowerBar  = false,        -- HP only for now
    hideWhenNoUnit = true,        -- <- vanish if no pet

    nameFunc      = PetName,
    buildLine1    = PetLine,
    buildLine2    = nil,          -- no third line
    accentColor   = PetAccent,
    castLineFunc  = EmptyCastLine,

    noUnitText    = {
        title    = "No Active Pet",
        subtitle = "Summon a companion to monitor", -- only used if hideWhenNoUnit=false
    },
}
