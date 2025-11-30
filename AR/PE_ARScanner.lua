local MODULE = "AR Scanner"

-- ##################################################
-- AR/PE_ARScanner.lua
-- Unit + tooltip scanner for AR HUD
-- Enriched data model: health, power, threat, PVP,
-- tap denied, civilians, auras, distance, range, etc.
-- ##################################################

local PE = _G.PE
local AR = PE and PE.AR
if not AR then
    return
end

AR.Scanner = AR.Scanner or {}
local Scanner = AR.Scanner

Scanner.units   = Scanner.units   or {}
Scanner.tooltip = Scanner.tooltip or nil

------------------------------------------------------
-- Tooltip helper
------------------------------------------------------

local function EnsureTooltip()
    if Scanner.tooltip then
        return Scanner.tooltip
    end

    -- Hidden scanning tooltip
    local tt = CreateFrame("GameTooltip", "PE_AR_HiddenTooltip", UIParent, "GameTooltipTemplate")
    tt:SetFrameStrata("LOW")
    tt:SetFrameLevel(0)
    tt:SetOwner(UIParent, "ANCHOR_NONE")

    Scanner.tooltip = tt
    return tt
end

local function BuildTooltipForUnit(unitID, data)
    local tt = EnsureTooltip()
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    tt:ClearLines()
    tt:SetUnit(unitID)

    local tooltip = {
        header    = data.name or UnitName(unitID) or "",
        subHeader = nil,
        lines     = {},
        tags      = {
            isPlayer    = UnitIsPlayer(unitID) or false,
            isQuestGiver = false,
            isVendor     = false,
            isTrainer    = false,
        },
    }

    for i = 1, 6 do
        local fs   = _G["PE_AR_HiddenTooltipTextLeft" .. i]
        local text = fs and fs:GetText()

        if text and text ~= "" then
            if i == 1 then
                tooltip.header = text
            elseif i == 2 then
                tooltip.subHeader = text
            else
                table.insert(tooltip.lines, text)

                if text:find("Quest") then
                    tooltip.tags.isQuestGiver = true
                end
                if text:find("Vendor") or text:find("Merchant") then
                    tooltip.tags.isVendor = true
                end
                if text:find("Trainer") then
                    tooltip.tags.isTrainer = true
                end
            end
        end
    end

    return tooltip
end

------------------------------------------------------
-- Casting helper
------------------------------------------------------

local function UpdateCastInfo(unitID, data)
    local name, _, _, _, endTime, _, _, notInterruptible = UnitCastingInfo(unitID)
    if not name then
        name, _, _, _, endTime, _, notInterruptible = UnitChannelInfo(unitID)
    end

    if name then
        data.isCasting              = true
        data.currentCastName        = name
        data.castEndTimeMS          = endTime
        data.castNotInterruptible   = not notInterruptible
        data.isCastingInterruptible = not notInterruptible
    else
        data.isCasting              = false
        data.currentCastName        = nil
        data.castEndTimeMS          = nil
        data.castNotInterruptible   = false
        data.isCastingInterruptible = false
    end
end

------------------------------------------------------
-- Range / distance helpers (cheap approximations)
------------------------------------------------------

local function EstimateDistance(unitID)
    -- Uses UnitPosition() which works anywhere except some instances
    local px, py = UnitPosition("player")
    local ux, uy = UnitPosition(unitID)
    if not px or not ux then
        return nil
    end

    local dx, dy = ux - px, uy - py
    return math.sqrt(dx * dx + dy * dy)
end

------------------------------------------------------
-- Aura helpers (lightweight summaries)
------------------------------------------------------

local function CountBuffs(unit)
    -- Some environments may not expose UnitBuff
    if type(UnitBuff) ~= "function" then
        return 0
    end

    local count = 0
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then
            break
        end
        count = count + 1
    end
    return count
end

local function CountDebuffs(unit)
    -- Some environments may not expose UnitDebuff
    if type(UnitDebuff) ~= "function" then
        return 0
    end

    local count = 0
    for i = 1, 40 do
        local name = UnitDebuff(unit, i)
        if not name then
            break
        end
        count = count + 1
    end
    return count
end

------------------------------------------------------
-- Scanner lifecycle
------------------------------------------------------

function Scanner.Init()
    AR.RegisterEvent("PLAYER_TARGET_CHANGED")
    AR.RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    AR.RegisterEvent("NAME_PLATE_UNIT_ADDED")
    AR.RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    AR.RegisterEvent("MODIFIER_STATE_CHANGED")
    AR.RegisterEvent("UNIT_FACTION")
    AR.RegisterEvent("UNIT_FLAGS")
    AR.RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    AR.RegisterEvent("UNIT_SPELLCAST_START")
    AR.RegisterEvent("UNIT_SPELLCAST_STOP")
    AR.RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    AR.RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
end

function Scanner.OnEvent(event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        Scanner:UpdateUnit("target")

    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if UnitExists("mouseover") then
            Scanner:UpdateUnit("mouseover")
        end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Scanner:UpdateUnit(...)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        Scanner:RemoveUnit(...)

    elseif event == "MODIFIER_STATE_CHANGED" then
        local key, down = ...

        if key == "LALT" or key == "RALT" or key == "ALT" then
            AR.expanded = (down == 1) or IsAltKeyDown()

            if AR.HUD and AR.HUD.Refresh then
                AR.HUD.Refresh("MODIFIER")
            end
        end

    elseif event:find("UNIT_SPELLCAST") then
        Scanner:UpdateUnit(...)

    elseif event == "UNIT_THREAT_LIST_UPDATE"
        or event == "UNIT_FACTION"
        or event == "UNIT_FLAGS"
    then
        Scanner:UpdateUnit(...)
    end
end

------------------------------------------------------
-- Main unit update
------------------------------------------------------

function Scanner:UpdateUnit(unitID)
    if not unitID or not UnitExists(unitID) then
        return
    end

    local guid = UnitGUID(unitID)
    if not guid then
        return
    end

    local data = Scanner.units[guid] or {}

    --------------------------------------------------
    -- Identity & classification
    --------------------------------------------------
    data.unit       = unitID
    data.guid       = guid
    data.name       = UnitName(unitID)
    data.level      = UnitLevel(unitID)
    data.isPlayer   = UnitIsPlayer(unitID)
    data.hostile    = UnitIsEnemy("player", unitID)
    data.friendly   = UnitIsFriend("player", unitID)
    data.reaction   = UnitReaction("player", unitID)
    data.classif    = UnitClassification(unitID)
    data.creature   = UnitCreatureType(unitID)
    data.faction    = UnitFactionGroup(unitID)
    data.isPet      = UnitIsUnit(unitID, "pet") or UnitIsOtherPlayersPet(unitID)
    -- data.isTarget   = UnitIsUnit(unitID, "target")
    -- data.isMouseover= UnitIsUnit(unitID, "mouseover")
    data.isBoss     = (data.classif == "worldboss")
    data.isElite    = (data.classif == "elite" or data.classif == "rareelite")

    --------------------------------------------------
    -- Health & power
    --------------------------------------------------
    data.health   = UnitHealth(unitID)
    data.healthMax = UnitHealthMax(unitID)
    data.hpPct    = (data.healthMax > 0) and (data.health / data.healthMax) or 0

    data.power    = UnitPower(unitID)
    data.powerMax = UnitPowerMax(unitID)
    data.powerType = select(2, UnitPowerType(unitID))
    data.powerPct  = (data.powerMax > 0) and (data.power / data.powerMax) or 0

    --------------------------------------------------
    -- Threat / PvP / flags
    --------------------------------------------------
    data.threat      = UnitThreatSituation("player", unitID)
    data.isPVP       = UnitIsPVP(unitID)
    data.isPVPFFA    = UnitIsPVPFreeForAll(unitID)
    data.isTapDenied = UnitIsTapDenied(unitID)

    -- Optional APIs (not present on all clients)
    if type(UnitIsCivilian) == "function" then
        data.isCivilian = UnitIsCivilian(unitID)
    else
        data.isCivilian = false
    end

    if type(UnitIsWildBattlePet) == "function" then
        data.isBattlePet = UnitIsWildBattlePet(unitID)
    else
        data.isBattlePet = false
    end

    --------------------------------------------------
    -- Auras (summary only)
    --------------------------------------------------
    data.buffCount   = CountBuffs(unitID)
    data.debuffCount = CountDebuffs(unitID)

    --------------------------------------------------
    -- Distance & range
    --------------------------------------------------
    data.distance = EstimateDistance(unitID)
    data.inRange  = UnitInRange(unitID) -- nil/true/false

    --------------------------------------------------
    -- Casting
    --------------------------------------------------
    UpdateCastInfo(unitID, data)

    --------------------------------------------------
    -- Tooltip
    --------------------------------------------------
    data.tooltip = BuildTooltipForUnit(unitID, data)
    data.lastSeen = GetTime()

    Scanner.units[guid] = data
end

function Scanner:RemoveUnit(unitID)
    local guid = UnitGUID(unitID)
    if guid then
        Scanner.units[guid] = nil
    end
end

------------------------------------------------------
-- Snapshot (priority sort)
------------------------------------------------------

function Scanner.BuildSnapshot()
    local snapshot    = {}
    local playerLevel = UnitLevel("player") or 0
    local now         = GetTime()

    -- Who is actually target / mouseover *right now*?
    local targetGUID = UnitExists("target") and UnitGUID("target") or nil
    local mouseGUID  = UnitExists("mouseover") and UnitGUID("mouseover") or nil

    for guid, data in pairs(Scanner.units) do
        -- Fresh flags based on GUID, not cached booleans
        local isTargetNow    = (targetGUID and guid == targetGUID) or false
        local isMouseoverNow = (mouseGUID and guid == mouseGUID) or false

        -- Age-out, but never drop current target/mouseover just for being old
        local tooOld = data.lastSeen and ((now - data.lastSeen) > 30)

        if tooOld and not isTargetNow and not isMouseoverNow then
            Scanner.units[guid] = nil
        else
            local score = 0

            if isTargetNow then
                score = score + 300
            end
            if isMouseoverNow then
                score = score + 200
            end
            if data.hostile then
                score = score + 30
            end
            if data.isBoss then
                score = score + 40
            end
            if data.isElite then
                score = score + 15
            end
            if data.isCastingInterruptible then
                score = score + 20
            end

            if data.level > playerLevel + 2 then
                score = score + 5
            elseif data.level < playerLevel - 3 then
                score = score - 5
            end

            table.insert(snapshot, {
                guid       = guid,
                data       = data,

                -- force unit tokens for live focus points
                unit       = isTargetNow and "target"
                             or (isMouseoverNow and "mouseover" or data.unit),
                isTarget   = isTargetNow,
                isMouseover= isMouseoverNow,
                score      = score,
            })
        end
    end

    table.sort(snapshot, function(a, b)
        return a.score > b.score
    end)

    return snapshot
end

PE.LogInit(MODULE)
if PE.RegisterModule then
    PE.RegisterModule("AR HUD Scanner", {
        name  = "AR HUD Scanner",
        class = "AR HUD",
    })
end
