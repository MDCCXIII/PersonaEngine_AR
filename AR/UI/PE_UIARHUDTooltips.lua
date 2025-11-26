-- ##################################################
-- PE_UIARHUDTooltips.lua
-- PersonaEngine - AR HUD tooltip projection + native override
-- ##################################################

local MODULE = "UI_ARHUDTooltips"
local PE     = _G.PE
if not PE or type(PE) ~= "table" then
    print("|cffff0000[PersonaEngine] ERROR: PE table missing in " .. MODULE .. "|r")
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Tooltips = AR.Tooltips or {}
local TT = AR.Tooltips

----------------------------------------------------
-- Config
----------------------------------------------------

-- HUD tooltip panel sizing
local PANEL_WIDTH      = 320
local PANEL_MAX_HEIGHT = 220
local PANEL_MIN_HEIGHT = 60
local LINGER_SECONDS   = 0.35  -- linger time after tooltip hides

-- Priority table for future multi-source support
local SOURCE_PRIORITY = {
    GameTooltip = 100,
    Default     = 10,
}

----------------------------------------------------
-- State
----------------------------------------------------

local panelFrame
local scrollFrame
local textFS
local hooked = false

local activeSource   = nil
local sources        = {}
local lingering      = false
local lingerElapsed  = 0

-- Native override flag:
-- false = AR HUD projection mode (tooltips hidden, HUD shows text)
-- true  = native Blizzard tooltip windows visible over HUD
TT.nativeOverride = false

----------------------------------------------------
-- Tooltip frame list for native override
----------------------------------------------------

local tooltipFrames = {
    _G.GameTooltip,
    _G.ItemRefTooltip,
    _G.ShoppingTooltip1,
    _G.ShoppingTooltip2,
    _G.EmbeddedItemTooltip, -- may be nil in some versions
}

----------------------------------------------------
-- Helpers
----------------------------------------------------

local function HUDActive()
    -- AR.IsEnabled is defined in PE_ARCore.lua
    return AR and AR.IsEnabled and AR.IsEnabled() and AR.visionEnabled
end

local function EnsurePanel()
    if panelFrame then return panelFrame end

    local f = CreateFrame("Frame", "PE_ARHUD_TooltipPanel", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_MIN_HEIGHT)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 140)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(60)
    f:SetIgnoreParentAlpha(true)
    f:SetAlpha(0) -- start hidden

    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetBackdropBorderColor(0.1, 0.8, 1.0, 0.8)

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 4)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(PANEL_WIDTH - 24, PANEL_MIN_HEIGHT - 8)
    sf:SetScrollChild(content)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT",  content, "TOPLEFT",  2, -2)
    text:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -2)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWidth(PANEL_WIDTH - 28)
    text:SetText("")

    panelFrame  = f
    scrollFrame = sf
    textFS      = text

    f:SetScript("OnUpdate", function(self, elapsed)
        if not lingering then return end
        lingerElapsed = lingerElapsed + elapsed
        if lingerElapsed >= LINGER_SECONDS then
            lingering     = false
            lingerElapsed = 0
            self:SetAlpha(0)
        end
    end)

    return panelFrame
end

local function ShowHUDTooltip(sourceId, lines)
    if not HUDActive() then
        if panelFrame then
            panelFrame:SetAlpha(0)
        end
        return
    end

    EnsurePanel()

    local text = table.concat(lines, "\n")
    textFS:SetText(text)

    -- Calculate required height
    textFS:SetWidth(PANEL_WIDTH - 28)
    local neededHeight  = textFS:GetStringHeight() + 8
    local clampedHeight = math.min(math.max(neededHeight, PANEL_MIN_HEIGHT), PANEL_MAX_HEIGHT)

    panelFrame:SetHeight(clampedHeight)

    local content = textFS:GetParent()
    content:SetHeight(neededHeight)

    -- Scrolling control
    if neededHeight > clampedHeight then
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local min, max = 0, self:GetVerticalScrollRange()
            local step   = 15 * (delta > 0 and -1 or 1)
            local target = math.min(math.max(current + step, min), max)
            self:SetVerticalScroll(target)
        end)
    else
        scrollFrame:SetVerticalScroll(0)
        scrollFrame:EnableMouseWheel(false)
    end

    panelFrame:SetAlpha(1)
    lingering     = false
    lingerElapsed = 0
    activeSource  = sourceId
end

local function HideHUDTooltip()
    if not panelFrame then return end

    if not HUDActive() then
        panelFrame:SetAlpha(0)
        activeSource = nil
        return
    end

    if activeSource then
        lingering     = true
        lingerElapsed = 0
    else
        panelFrame:SetAlpha(0)
    end
end

local function CollectLinesFromTooltipFrame(ttFrame)
    local lines = {}
    if not ttFrame or not ttFrame:IsShown() then
        return lines
    end

    local numLines = ttFrame:NumLines() or 0
    local baseName = ttFrame:GetName()
    if not baseName then
        return lines
    end

    for i = 1, numLines do
        local left = _G[baseName .. "TextLeft" .. i]
        if left then
            local txt = left:GetText()
            if txt and txt ~= "" then
                table.insert(lines, txt)
            end
        end
    end

    return lines
end

----------------------------------------------------
-- Source registration / priority
----------------------------------------------------

local function SetSourceVisible(sourceId, frame, visible)
    local priority = SOURCE_PRIORITY[sourceId] or SOURCE_PRIORITY.Default

    if visible then
        local lines = CollectLinesFromTooltipFrame(frame)
        if #lines == 0 then
            sources[sourceId] = nil
        else
            sources[sourceId] = {
                frame    = frame,
                lines    = lines,
                priority = priority,
            }
        end
    else
        sources[sourceId] = nil
    end

    -- Choose best source by priority
    local bestId, best = nil, nil
    for id, info in pairs(sources) do
        if not best or info.priority > best.priority then
            bestId, best = id, info
        end
    end

    if bestId and best then
        ShowHUDTooltip(bestId, best.lines)
    else
        activeSource = nil
        HideHUDTooltip()
    end
end

----------------------------------------------------
-- Native override visibility control
----------------------------------------------------

local function ApplyNativeTooltipVisibility(ignore)
    for _, f in ipairs(tooltipFrames) do
        if f and f.SetIgnoreParentAlpha then
            f:SetIgnoreParentAlpha(ignore)
            if ignore and f.SetAlpha then
                f:SetAlpha(1) -- ensure visibility even if UIParent alpha is 0
            end
        end
    end
end

function TT.SetNativeOverride(flag)
    TT.nativeOverride = not not flag

    if TT.nativeOverride then
        -- Let Blizzard tooltip frames be visible over HUD in visor
        ApplyNativeTooltipVisibility(true)

        -- Hide HUD tooltip panel (we're in "native" mode)
        if panelFrame then
            panelFrame:SetAlpha(0)
        end
        activeSource = nil
        wipe(sources)
    else
        -- Tooltips go back to obeying UIParent alpha; HUD owns projection
        ApplyNativeTooltipVisibility(false)
    end
end

function TT.ToggleNativeOverride()
    TT.SetNativeOverride(not TT.nativeOverride)
end

function TT.IsNativeOverride()
    return TT.nativeOverride
end

----------------------------------------------------
-- GameTooltip hooks
----------------------------------------------------

local function OnGameTooltipShow(self)
    if not HUDActive() then return end

    if TT.nativeOverride then
        -- Native mode: do nothing; Blizzard handles display
        return
    end

    -- HUD mode: keep real tooltip invisible, project its contents into HUD
    self:SetAlpha(0)
    SetSourceVisible("GameTooltip", self, true)
end

local function OnGameTooltipHide(self)
    if TT.nativeOverride then
        return
    end
    SetSourceVisible("GameTooltip", self, false)
end

local function OnGameTooltipUpdate(self)
    if not HUDActive() then return end

    if TT.nativeOverride then
        -- Native mode: allow normal tooltip behavior
        return
    end

    self:SetAlpha(0)
    SetSourceVisible("GameTooltip", self, true)
end

----------------------------------------------------
-- Public API
----------------------------------------------------

function TT.Init()
    EnsurePanel()

    if GameTooltip and not hooked then
        GameTooltip:HookScript("OnShow",   OnGameTooltipShow)
        GameTooltip:HookScript("OnHide",   OnGameTooltipHide)
        GameTooltip:HookScript("OnUpdate", OnGameTooltipUpdate)
        hooked = true
    end
end

-- Optional: ARCore can call this when visor mode toggles
function TT.OnARModeChanged()
    if not HUDActive() then
        activeSource = nil
        wipe(sources)
        HideHUDTooltip()
    end
end

----------------------------------------------------
-- Module registration
----------------------------------------------------

if PE.LogInit then PE.LogInit(MODULE) end
if PE.RegisterModule then
    PE.RegisterModule("AR HUD Tooltips", {
        name  = "AR HUD Tooltips",
        class = "AR HUD",
    })
end
