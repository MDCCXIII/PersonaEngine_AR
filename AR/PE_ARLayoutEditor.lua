-- ##################################################
-- AR/PE_ARLayoutEditor.lua
-- PersonaEngine AR: simple in-game layout editor
-- Lets you drag registered AR frames and saves
-- their positions into the layout DB.
-- Also coordinates with AR Reticles' editor so that
-- all AR HUD editing feels like one mode.
-- ##################################################

local MODULE = "AR Layout Editor"

local PE = _G.PE
if not PE or type(PE) ~= "table" then
    return
end

PE.AR = PE.AR or {}
local AR = PE.AR

AR.Layout      = AR.Layout or {}
local Layout   = AR.Layout
if not Layout then
    return
end

AR.LayoutEditor = AR.LayoutEditor or {}
local Editor    = AR.LayoutEditor

------------------------------------------------------
-- State
------------------------------------------------------

Editor.enabled  = false
Editor.handles  = Editor.handles or {}
Editor.original = Editor.original or {}  -- per-frame original scripts/flags

------------------------------------------------------
-- Internal helpers
------------------------------------------------------

local function CreateHandle(regionName, frame)
    if not frame or frame:IsForbidden() then
        return nil
    end

    local handle = Editor.handles[frame]
    if not handle then
        -- Build a stable name for the handle
        local safeName = tostring(regionName or "Region"):gsub("%s+", "")
        local handleName = "PE_AR_LayoutHandle_" .. safeName

        handle = CreateFrame("Frame", handleName, frame, "BackdropTemplate")
        Editor.handles[frame] = handle

        -- Strata / level discipline
        handle:SetFrameStrata("LOW")
        local baseLevel = frame:GetFrameLevel() or 0
        if baseLevel < 0 then
            baseLevel = 0
        end
        if baseLevel >= 50 then
            baseLevel = 49
        end
        handle:SetFrameLevel(baseLevel + 1)

        if regionName == "Theo Box" then
            -- Only a thin top bar is draggable/clickable; interior stays click-through.
            handle:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
            handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            handle:SetHeight(20)
        else
            handle:SetAllPoints(frame)
        end

        -- For most regions, the handle draws the border.
        -- For Theo Box, the real box has the border; handle is invisible.
        if regionName ~= "Theo Box" then
            handle:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12,
            })
            handle:SetBackdropBorderColor(0.2, 1.0, 0.7, 0.9)
        end

        handle.label = handle:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
        handle.label:SetPoint("TOPLEFT", handle, "TOPLEFT", 4, -4)
        handle.label:SetText(regionName or "AR Region")

        -- Mousewheel resize for Theo box while in /pearlayout
		handle:EnableMouseWheel(true)
		handle:SetScript("OnMouseWheel", function(self, delta)
			-- Regions that can be resized via mousewheel in /pearlayout
			local isResizable =
				(regionName == "Theo Box") or
				(regionName == "Cardinal Helper")

			if not isResizable then
				return
			end

			local parent = self:GetParent()
			if not parent then return end

			local step    = 8 * delta
			local minSize = 40

			local w, h = parent:GetSize()
			if IsAltKeyDown() then
				-- Alt: adjust vertical size only
				h = math.max(minSize, h + step)
			else
				-- Normal: grow/shrink both width and height together
				w = math.max(minSize, w + step)
				h = math.max(minSize, h + step)
			end

			parent:SetSize(w, h)

			-- Persist the new size into layout DB
			if Layout.SaveFromFrame then
				Layout.SaveFromFrame(regionName, parent)
			end
		end)


        handle:Hide()
    end

    if handle.label then
        handle.label:SetText(regionName or "AR Region")
    end

    return handle
end

local function HookFrameForEdit(regionName, frame)
    if not frame or frame:IsForbidden() then
        return
    end

    if Editor.original[frame] then
        return -- already hooked
    end

    local info = {
        movable      = frame:IsMovable(),
        mouseEnabled = frame:IsMouseEnabled(),
        dragStart    = frame:GetScript("OnDragStart"),
        dragStop     = frame:GetScript("OnDragStop"),
    }
    Editor.original[frame] = info

    -- Special case: Theo Box should be mostly click-through,
    -- with only the border draggable.
    if regionName == "Theo Box" then
        frame:SetMovable(true) -- allow moving, but keep it mouse-transparent

        local handle = CreateHandle(regionName, frame)
        if handle then
            handle:Show()
            handle:SetMovable(true)
            handle:EnableMouse(true)
            handle:RegisterForDrag("LeftButton")

            handle:SetScript("OnDragStart", function(h)
                frame:StartMoving()
            end)

            handle:SetScript("OnDragStop", function(h)
                frame:StopMovingOrSizing()
                if Layout.SaveFromFrame then
                    Layout.SaveFromFrame(regionName, frame)
                end
            end)
        end

        return
    end

    -- Default behavior for all other regions
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        Layout.SaveFromFrame(regionName, f)
    end)

    local handle = CreateHandle(regionName, frame)
    if handle then
        handle:Show()
    end
end

local function UnhookFrame(frame)
    if not frame or frame:IsForbidden() then
        return
    end

    local info = Editor.original[frame]
    if not info then
        return
    end

    frame:SetMovable(info.movable or false)
    frame:EnableMouse(info.mouseEnabled or false)
    frame:SetScript("OnDragStart", info.dragStart)
    frame:SetScript("OnDragStop",  info.dragStop)

    local handle = Editor.handles[frame]
    if handle then
        handle:Hide()
    end

    Editor.original[frame] = nil
end

local function ApplyEditMode()
    local registered = Layout.GetRegistered and Layout.GetRegistered()
    if not registered then
        return
    end

    if Editor.enabled then
        for regionName, frame in pairs(registered) do
            HookFrameForEdit(regionName, frame)
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF98[PersonaEngine AR]|r Layout edit |cff20ff70ENABLED|r. Drag frames to reposition.")
    else
        for _, frame in pairs(registered) do
            UnhookFrame(frame)
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF98[PersonaEngine AR]|r Layout edit |cffff4040DISABLED|r.")
    end

    -- Coordinate with AR Reticles editor (if present)
    if AR and AR.Reticles and AR.Reticles.SetEditorEnabled then
        AR.Reticles.SetEditorEnabled(Editor.enabled)
    end
end

------------------------------------------------------
-- Public API
------------------------------------------------------

function Editor.SetEnabled(flag)
    flag = not not flag
    if flag == Editor.enabled then
        return
    end

    Editor.enabled = flag
    ApplyEditMode()
end

function Editor.Toggle()
    Editor.SetEnabled(not Editor.enabled)
end

------------------------------------------------------
-- Slash command
------------------------------------------------------

SLASH_PE_ARLAYOUT1 = "/pearlayout"
SlashCmdList["PE_ARLAYOUT"] = function(msg)
    Editor.Toggle()
end

------------------------------------------------------
-- Module registration
------------------------------------------------------

PE.LogInit(MODULE)
PE.RegisterModule("AR Layout Editor", {
    name  = "AR Layout Editor",
    class = "AR HUD",
})
