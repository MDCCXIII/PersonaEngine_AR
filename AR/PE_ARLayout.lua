-- ##################################################
-- AR/PE_ARLayout.lua
-- PersonaEngine AR: Screen layout provider
-- Defines named regions for AR HUD elements and
-- attaches frames to those regions.
-- ##################################################

local MODULE = "AR Layout"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Layout = AR.Layout or {}
local Layout = AR.Layout

------------------------------------------------------
-- SavedVariables root
------------------------------------------------------

-- NOTE:
-- Add this to your .toc if not already present:
-- ## SavedVariables: PersonaEngineARDB
local function GetLayoutDB()
    _G.PersonaEngineARDB = _G.PersonaEngineARDB or {}
    local root  = _G.PersonaEngineARDB
    root.profile = root.profile or {}
    root.profile.layout = root.profile.layout or {}
    return root.profile.layout
end

------------------------------------------------------
-- Default regions
--
-- These are our "first guess" for where things live.
-- Users (or a future editor) can override per region.
------------------------------------------------------

Layout.defaults = Layout.defaults or {
    -- Right side stack: focus (top), target, mouseover, pets
    targetPanel = {
        point    = "RIGHT",
        relPoint = "RIGHT",
        x        = -60,
        y        = 0,
        width    = 260,
        height   = 300,
    },

    focusPanel = {
        point    = "RIGHT",
        relPoint = "RIGHT",
        x        = -60,
        y        = 220,
        width    = 260,
        height   = 210,
    },

    mouseoverPanel = {
        point    = "RIGHT",
        relPoint = "RIGHT",
        x        = -60,
        y        = -220,
        width    = 260,
        height   = 180,
    },

    targetPetPanel = {
        point    = "RIGHT",
        relPoint = "RIGHT",
        x        = -330,
        y        = -40,
        width    = 220,
        height   = 140,
    },

    focusPetPanel = {
        point    = "RIGHT",
        relPoint = "RIGHT",
        x        = -330,
        y        = 180,
        width    = 220,
        height   = 140,
    },

    -- Left side: player + pet dossiers
    playerPanel = {
        point    = "LEFT",
        relPoint = "LEFT",
        x        = 60,
        y        = 60,
        width    = 260,
        height   = 210,
    },

    playerPetPanel = {
        point    = "LEFT",
        relPoint = "LEFT",
        x        = 60,
        y        = -160,
        width    = 220,
        height   = 140,
    },

    -- If we ever want a dedicated minimap frame region:
    minimapPanel = {
        point    = "TOPLEFT",
        relPoint = "TOPLEFT",
        x        = 40,
        y        = -40,
        width    = 220,
        height   = 220,
    },

    -- Future: recommended actions strip, etc.
    actionsPanel = {
        point    = "BOTTOM",
        relPoint = "BOTTOM",
        x        = 0,
        y        = 120,
        width    = 260,
        height   = 80,
    },
}

------------------------------------------------------
-- Frame registry (who lives in which region)
------------------------------------------------------

Layout.registered = Layout.registered or {}

function Layout.Register(regionName, frame)
    if not regionName or not frame then return end
    Layout.registered[regionName] = frame
end

function Layout.GetRegistered()
    return Layout.registered
end


------------------------------------------------------
-- Helpers
------------------------------------------------------

local function MergeDefaults(regionName)
    local db       = GetLayoutDB()
    local defaults = Layout.defaults[regionName]
    local saved    = db[regionName]

    if not defaults and not saved then
        return nil
    end

    local cfg = {}

    if defaults then
        for k, v in pairs(defaults) do
            cfg[k] = v
        end
    end

    if saved then
        for k, v in pairs(saved) do
            cfg[k] = v
        end
    end

    -- Basic sanity
    if not cfg.point then cfg.point = "CENTER" end
    if not cfg.relPoint then cfg.relPoint = cfg.point end
    if not cfg.width then cfg.width = 200 end
    if not cfg.height then cfg.height = 100 end
    if type(cfg.x) ~= "number" then cfg.x = 0 end
    if type(cfg.y) ~= "number" then cfg.y = 0 end

    return cfg
end

------------------------------------------------------
-- Public API
------------------------------------------------------

function Layout.Get(regionName)
    if not regionName then return nil end
    return MergeDefaults(regionName)
end

-- Override a region's layout and persist to SavedVariables
function Layout.Set(regionName, cfg)
    if not regionName or type(cfg) ~= "table" then
        return
    end
    local db = GetLayoutDB()
    db[regionName] = db[regionName] or {}

    local dest = db[regionName]
    for k, v in pairs(cfg) do
        dest[k] = v
    end
end

-- Attach a frame to a named region: does SetPoint + SetSize.
-- Optional opts:
--   opts.noSize = true  -> don't touch width/height
function Layout.Attach(frame, regionName, opts)
    if not frame or not regionName then
        return
    end

    local cfg = Layout.Get(regionName)
    if not cfg then
        return
    end

    frame:ClearAllPoints()
    frame:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)

    if not (opts and opts.noSize) then
        if cfg.width and cfg.width > 0 then
            frame:SetWidth(cfg.width)
        end
        if cfg.height and cfg.height > 0 then
            frame:SetHeight(cfg.height)
        end
    end
end

-- For future use: we can add a drag/resize editor that calls Layout.Set.

-- Save the current position/size of a frame back into layout DB.
-- Typically called when the user finishes dragging in layout edit mode.
function Layout.SaveFromFrame(regionName, frame)
    if not regionName or not frame then return end

    local point, relativeTo, relPoint, x, y = frame:GetPoint(1)
    if not point then
        return
    end

    local cfg = {
        point    = point,
        relPoint = relPoint or point,
        x        = x or 0,
        y        = y or 0,
        width    = frame:GetWidth(),
        height   = frame:GetHeight(),
    }

    Layout.Set(regionName, cfg)
end


------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Layout", {
    name  = "AR Layout",
    class = "AR HUD",
})
