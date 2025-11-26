-- ##################################################
-- AR/PE_ARAdvisor.lua
-- PersonaEngine AR: Threat-aware action suggestions
-- ##################################################

local MODULE = "AR Advisor"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Advisor = AR.Advisor or {}
local Advisor = AR.Advisor

------------------------------------------------------
-- Spell / item configuration (to be tuned by you)
------------------------------------------------------

-- Simple helpers so this file is spec-agnostic; you can
-- swap IDs per char/spec in the future.
local SPELL = {
    INTERRUPT        = 187707, -- Muzzle (example)
    BIG_DEFENSIVE    = 186265, -- Aspect of the Turtle
    SELF_HEAL        = 109304, -- Exhilaration
    KICK_ALT         = nil,    -- second interrupt if any

    CORE_1           = 259489, -- Kill Command
    CORE_2           = 186270, -- Raptor Strike / main spender
    CORE_FILLER      = 259391, -- Flanking Strike / filler
    AOE_CORE         = 259495, -- Wildfire Bomb, etc.

    HARD_CC          = 187650, -- Freezing Trap
    SOFT_CC          = 187698, -- Tar Trap
    BUFF_DAMAGE      = 193526, -- Trueshot-ish example
}

-- Utility: is spell usable & off cooldown?
local function IsSpellReady(spellId)
    if not spellId then return false end
    if not IsUsableSpell(spellId) then return false end
    local start, dur, enabled = GetSpellCooldown(spellId)
    if enabled == 0 then return false end
    if not start or start == 0 or dur == 0 then
        return true
    end
    local remaining = start + dur - GetTime()
    return remaining <= 0
end

local function GetCooldownRemaining(spellId)
    local start, dur, enabled = GetSpellCooldown(spellId)
    if enabled == 0 or not start or start == 0 or dur == 0 then
        return 0
    end
    local remaining = start + dur - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining
end

------------------------------------------------------
-- Context building
------------------------------------------------------

local function BuildContext()
    local ctx = {}

    ctx.inCombat = UnitAffectingCombat("player") and true or false

    -- Player state
    local hp    = UnitHealth("player") or 0
    local hpMax = UnitHealthMax("player") or 1
    ctx.playerHP        = hp
    ctx.playerHPMax     = hpMax
    ctx.playerHPPct     = (hpMax > 0) and (hp / hpMax) or 0
    ctx.playerHPCrit    = ctx.playerHPPct <= 0.35
    ctx.playerHPWorry   = ctx.playerHPPct <= 0.60

    -- Target state
    if UnitExists("target") and UnitCanAttack("player", "target") then
        ctx.hasHostileTarget = true
        ctx.targetIsBoss     = UnitClassification("target") == "worldboss"
                              or UnitLevel("target") == -1

        ctx.targetHP     = UnitHealth("target") or 0
        ctx.targetHPMax  = UnitHealthMax("target") or 1
        ctx.targetHPPct  = (ctx.targetHPMax > 0) and (ctx.targetHP / ctx.targetHPMax) or 0

        -- Casting info
        local name, _, _, startTime, endTime, _, _, notInterruptible = UnitCastingInfo("target")
        ctx.castName            = name
        ctx.castInterruptible   = name and not notInterruptible or false
        ctx.castRemaining       = 0
        if name and startTime and endTime then
            local now = GetTime() * 1000
            ctx.castRemaining = math.max(0, (endTime - now) / 1000)
        end
        -- crude "danger" flag: you can later plug in a spell-id table
        ctx.castDangerous = ctx.castInterruptible and ctx.castRemaining <= 2.0
    else
        ctx.hasHostileTarget = false
    end

    return ctx
end

------------------------------------------------------
-- Track 1: Counter / Mitigate
------------------------------------------------------

local function ChooseCounterMitigate(ctx)
    if not ctx.inCombat or not ctx.hasHostileTarget then
        return nil
    end

    -- 1) Hard interrupt if enemy is casting something bad
    if ctx.castInterruptible and ctx.castDangerous and IsSpellReady(SPELL.INTERRUPT) then
        return {
            track    = "counter",
            spellId  = SPELL.INTERRUPT,
            label    = "Interrupt",
            reason   = "Dangerous cast",
            urgency  = 1.0, -- max within track
        }
    end

    -- 2) Panic defensive if we are about to explode
    if ctx.playerHPCrit and IsSpellReady(SPELL.BIG_DEFENSIVE) then
        return {
            track    = "counter",
            spellId  = SPELL.BIG_DEFENSIVE,
            label    = "Defensive",
            reason   = "Critical HP",
            urgency  = 0.9,
        }
    end

    -- 3) Self-heal if low-ish and safe enough to channel it
    if ctx.playerHPWorry and IsSpellReady(SPELL.SELF_HEAL) then
        return {
            track    = "counter",
            spellId  = SPELL.SELF_HEAL,
            label    = "Self Heal",
            reason   = "Stabilize HP",
            urgency  = 0.7,
        }
    end

    return nil
end

------------------------------------------------------
-- Track 2: Damage rotation
------------------------------------------------------

local function ChooseDamage(ctx)
    if not ctx.inCombat or not ctx.hasHostileTarget then
        return nil
    end

    -- Extremely dumb prototype priority:
    -- 1) AOE if lots of enemies later (we'd need Scanner info)
    -- 2) Core big hit
    -- 3) Filler

    if IsSpellReady(SPELL.CORE_1) then
        return {
            track   = "damage",
            spellId = SPELL.CORE_1,
            label   = "Core",
            reason  = "Primary generator",
        }
    end

    if IsSpellReady(SPELL.CORE_2) then
        return {
            track   = "damage",
            spellId = SPELL.CORE_2,
            label   = "Core",
            reason  = "Primary spender",
        }
    end

    if IsSpellReady(SPELL.CORE_FILLER) then
        return {
            track   = "damage",
            spellId = SPELL.CORE_FILLER,
            label   = "Filler",
            reason  = "Keep GCD rolling",
        }
    end

    return nil
end

------------------------------------------------------
-- Track 3: Control / Heal / Buff
------------------------------------------------------

local function ChooseControlSupport(ctx)
    if not ctx.inCombat or not ctx.hasHostileTarget then
        -- Out of combat: maybe suggest buff
        if IsSpellReady(SPELL.BUFF_DAMAGE) then
            return {
                track   = "support",
                spellId = SPELL.BUFF_DAMAGE,
                label   = "Buff",
                reason  = "Pre-pull damage buff",
            }
        end
        return nil
    end

    -- In combat:
    -- 1) If target is not already hard-CC'd and we want an option:
    if IsSpellReady(SPELL.HARD_CC) then
        return {
            track   = "support",
            spellId = SPELL.HARD_CC,
            label   = "CC",
            reason  = "Control option",
        }
    end

    -- 2) Damage buff as a “spike now” choice
    if IsSpellReady(SPELL.BUFF_DAMAGE) then
        return {
            track   = "support",
            spellId = SPELL.BUFF_DAMAGE,
            label   = "Buff",
            reason  = "Burst window",
        }
    end

    return nil
end

------------------------------------------------------
-- Track priority scoring (which slot 1/2/3?)
------------------------------------------------------

local function ScoreTrack(ctx, rec)
    if not rec then return 0 end

    if rec.track == "counter" then
        -- Counter is top dog when:
        -- - we're low HP
        -- - or there is a dangerous cast
        local score = 50
        if ctx.castDangerous then score = score + 40 end
        if ctx.playerHPCrit then score = score + 40
        elseif ctx.playerHPWorry then score = score + 20 end
        return score
    elseif rec.track == "damage" then
        local score = 40
        if not ctx.inCombat or not ctx.hasHostileTarget then
            score = 5
        elseif not ctx.playerHPWorry and not ctx.castDangerous then
            score = score + 20 -- everything is fine, blast
        end
        return score
    elseif rec.track == "support" then
        local score = 30
        if ctx.playerHPWorry and not ctx.playerHPCrit then
            score = score + 15
        end
        return score
    end

    return 0
end

------------------------------------------------------
-- Public: get up to 3 ordered recommendations
------------------------------------------------------

function Advisor.GetRecommendations()
    local ctx = BuildContext()

    local recCounter = ChooseCounterMitigate(ctx)   -- may be nil
    local recDamage  = ChooseDamage(ctx)            -- may be nil
    local recSupport = ChooseControlSupport(ctx)    -- may be nil

    -- Always *try* to keep one per track; if a track is nil,
    -- it just won't participate.
    local tracks = {}

    if recCounter then
        recCounter.priority = ScoreTrack(ctx, recCounter)
        table.insert(tracks, recCounter)
    end
    if recDamage then
        recDamage.priority = ScoreTrack(ctx, recDamage)
        table.insert(tracks, recDamage)
    end
    if recSupport then
        recSupport.priority = ScoreTrack(ctx, recSupport)
        table.insert(tracks, recSupport)
    end

    table.sort(tracks, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)

    -- Normalize to exactly 3 slots (some may be nil)
    local slot1 = tracks[1]
    local slot2 = tracks[2]
    local slot3 = tracks[3]

    return slot1, slot2, slot3, ctx
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Advisor", {
    name  = "AR Advisor",
    class = "AR HUD",
})
