local MAJOR, MINOR = "LibChangelog-1.0", 1
local lib = LibStub(MAJOR, true)

if
    not lib
    or lib._implementationMinor ~= MINOR
    or not lib:_BeginModule("Window", MINOR)
then
    return
end

local WIDTH, HEIGHT = 930, 640
local SIDEBAR_WIDTH = 230
local INSET, CONTENT_TOP = 16, 38
local DISMISS_HEIGHT, DISMISS_GAP = 34, 12
local ROW_PADDING_X, ROW_PADDING_Y = 8, 5
local ROW_BUTTON_SIZE, ROW_ICON_SIZE = 40, 28
local ROW_TEXT_GAP, ROW_LINE_GAP = 8, 4
local LAYOUT_EPSILON = 0.001
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function createSidebarBorder(frame)
    local border = CreateFrame("Frame", nil, frame)
    border:EnableMouse(false)
    border:Hide()

    -- Use solid strokes like LibYvSkins' pixel borders. A textured backdrop
    -- adds sampling and nine-slice geometry that a one-pixel outline does not need.
    local edges = {}

    for index = 1, 4 do
        local edge = border:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(1, 0.82, 0, 0.9)
        edge:SetBlendMode("BLEND")
        edge:SetSnapToPixelGrid(false)
        edge:SetTexelSnappingBias(0)
        edges[index] = edge
    end

    local top, bottom, left, right = unpack(edges)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")

    -- Horizontal strokes own the corners so the translucent edges never overlap.
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")

    return border, edges
end

local function layoutSidebarBorder(row)
    local frame, border = row.frame, row.border

    if not row.selected or not frame:IsVisible() then
        border:Hide()
        return
    end

    local scale = frame:GetEffectiveScale()
    local unit = PixelUtil.GetPixelToUIUnitFactor() / scale

    if frame:GetWidth() < unit * 4 or frame:GetHeight() < unit * 4 then
        border:Hide()
        return
    end

    -- Native pixel layout owns the row and its descendants. Re-snapping
    -- measured screen edges during a drag introduces a second rounding path.
    if row.borderUnit ~= unit then
        local edges = row.borderEdges
        border:SetPoint("TOPLEFT", frame, "TOPLEFT", unit, -unit)
        border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -unit, unit)
        edges[1]:SetHeight(unit)
        edges[2]:SetHeight(unit)
        edges[3]:SetWidth(unit)
        edges[4]:SetWidth(unit)
        row.borderUnit = unit
    end

    border:Show()
end

local function resizeSidebarRow(row)
    local frame = row.frame
    local textWidth = frame:GetWidth()
        - ROW_PADDING_X * 2
        - ROW_BUTTON_SIZE
        - ROW_TEXT_GAP
    row.name:SetWidth(textWidth)
    row.status:SetWidth(textWidth)

    local textHeight = row.name:GetStringHeight()
        + ROW_LINE_GAP
        + row.status:GetStringHeight()
    local height = PixelUtil.GetNearestPixelSize(
        math.max(ROW_BUTTON_SIZE, textHeight) + ROW_PADDING_Y * 2,
        frame:GetEffectiveScale()
    )

    -- Corner anchors give the native pixel layout a stable origin instead of
    -- combining the button's center with half of a measured font height.
    row.button:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        ROW_PADDING_X,
        -(height - ROW_BUTTON_SIZE) / 2
    )
    row.name:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        ROW_PADDING_X + ROW_BUTTON_SIZE + ROW_TEXT_GAP,
        -(height - textHeight) / 2
    )

    -- Native float readback may differ slightly from the requested size.
    if math.abs(frame:GetHeight() - height) > LAYOUT_EPSILON then
        frame:SetHeight(height)
    end

    -- Extend the icon button's native hit area over the entire row. One
    -- interaction target keeps hover, clicks, tooltips and keyboard use aligned.
    local verticalInset = (ROW_BUTTON_SIZE - height) / 2
    row.button:SetHitRectInsets(
        -ROW_PADDING_X,
        ROW_PADDING_X + ROW_BUTTON_SIZE - row.frame:GetWidth(),
        verticalInset,
        verticalInset
    )
    layoutSidebarBorder(row)
end

local function getAddonIcon(addonName)
    if not C_AddOns.DoesAddOnExist(addonName) then
        return { iconTexture = FALLBACK_ICON }
    end

    local texture = C_AddOns.GetAddOnMetadata(addonName, "IconTexture")

    if texture and texture ~= "" then
        return { iconTexture = tonumber(texture) or texture }
    end

    local atlas = C_AddOns.GetAddOnMetadata(addonName, "IconAtlas")

    if atlas and atlas ~= "" then return { iconAtlas = atlas } end

    return { iconTexture = FALLBACK_ICON }
end

function lib:_CreateSidebarRow(index)
    local settings = self:_GetSettingsLibrary()
    local layout = self._window.sidebarLayout
    local flow = layout:GetRootFlow():BeginGroup()
    local frame = CreateFrame("Frame", nil, layout:GetContent())
    frame:SetSize(flow:GetWidth(), ROW_BUTTON_SIZE + ROW_PADDING_Y * 2)
    flow:AddFrame(frame, { fillWidth = true, marginBottom = 0 })
    flow:Finish()

    local border, borderEdges = createSidebarBorder(frame)

    local backgroundAlpha = index % 2 == 0 and 0.025 or 0.01
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, backgroundAlpha)

    local highlight = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.035)
    highlight:Hide()

    local button = settings:CreateButton(frame, {
        variant = "square",
        width = ROW_BUTTON_SIZE,
        iconTexture = FALLBACK_ICON,
        iconSize = ROW_ICON_SIZE,
        onClick = function()
            lib:_SelectEntry(index, true)
        end,
    })
    button:HookScript("OnEnter", function()
        highlight:Show()
    end)
    button:HookScript("OnLeave", function()
        highlight:Hide()
    end)
    button:HookScript("OnHide", function()
        highlight:Hide()
    end)

    local name =
        settings:CreateText(frame, { text = "", fontObject = GameFontNormal })
    local status = settings:CreateText(
        frame,
        { text = "", fontObject = GameFontHighlightSmall }
    )
    status:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -ROW_LINE_GAP)

    local row = {
        flow = flow,
        frame = frame,
        button = button,
        name = name,
        status = status,
        background = background,
        backgroundAlpha = backgroundAlpha,
        border = border,
        borderEdges = borderEdges,
    }
    PixelUtil.SetRoundLayoutToNearestPixelRecursively(frame, true)
    frame:HookScript("OnSizeChanged", function()
        resizeSidebarRow(row)
    end)
    frame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if frame:IsVisible() then resizeSidebarRow(row) end
        end)
    end)

    return row
end

function lib:_RefreshSidebarRows()
    local window = self._window

    if not window or not window.frame:IsShown() then return end

    for _, row in ipairs(window.rows) do
        if row.frame:IsShown() then resizeSidebarRow(row) end
    end
end

function lib:_UpdateSidebarRow(row, entry)
    local settings = self:_GetSettingsLibrary()
    row.flow:SetShown(true)
    row.name:SetText(entry.displayName)
    row.button:SetButtonIcon(getAddonIcon(entry.controller.addonName))
    settings:SetTooltip(row.button, {
        title = entry.displayName,
        text = entry.release.title or entry.release.version,
    })
end

local function hasChildEscapeTarget()
    if GetCurrentKeyBoardFocus() or Menu.GetManager():IsAnyMenuOpen() then
        return true
    end

    -- Native dialogs (including LMS's color picker) get their own Escape first.
    -- This window is intentionally NOT in UISpecialFrames: CloseSpecialWindows
    -- hides every listed window, which would also dismiss this entire batch.
    for _, name in ipairs(UISpecialFrames) do
        local frame = _G[name]

        if frame and frame:IsShown() then return true end
    end

    return false
end

function lib:_EnsureWindow()
    if self._window then return self._window end

    local settings = self:_GetSettingsLibrary()
    local frame = CreateFrame("Frame", nil, UIParent, "DefaultPanelTemplate")
    frame:Hide()
    frame:SetRoundLayoutToNearestPixel(true)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetUserPlaced(false)
    frame:SetDontSavePosition(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame.TopTileStreaks:Hide()

    frame.TitleContainer:EnableMouse(true)
    frame.TitleContainer:RegisterForDrag("LeftButton")
    frame.TitleContainer:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end

        frame:StartMoving()
    end)
    frame.TitleContainer:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:SetScript("OnEvent", function()
        if not frame:IsShown() then return end

        C_Timer.After(0, function()
            lib:_RefreshSidebarRows()
        end)
    end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 0)
    close:SetFrameLevel(frame.TitleContainer:GetFrameLevel() + 1)
    close:SetScript("OnClick", function()
        lib:_DismissBatch()
    end)

    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end

        local dismiss = key == "ESCAPE" and not hasChildEscapeTarget()
        self:SetPropagateKeyboardInput(not dismiss)

        if dismiss then lib:_DismissBatch() end
    end)

    local window = {
        frame = frame,
        rows = {},
        popupViews = {},
    }
    self._window = window

    local sidebarHeight = HEIGHT - CONTENT_TOP - INSET
    local sidebarInsetHeight = sidebarHeight - DISMISS_HEIGHT - DISMISS_GAP
    window.sidebar = CreateFrame("Frame", nil, frame)
    window.sidebar:SetPoint("TOPLEFT", INSET, -CONTENT_TOP)
    window.sidebar:SetSize(SIDEBAR_WIDTH, sidebarHeight)

    window.sidebarInset = self:_CreateInset(window.sidebar)
    window.sidebarInset:SetPoint("TOPLEFT")
    window.sidebarInset:SetPoint("BOTTOMRIGHT", 0, DISMISS_HEIGHT + DISMISS_GAP)

    window.sidebarLayout = settings:CreateCanvasLayout(window.sidebarInset, {
        width = SIDEBAR_WIDTH,
        height = sidebarInsetHeight,
        scrollable = true,
        scrollArea = {
            preset = "inset",
            contentSpacing = "compact",
        },
    })
    window.sidebarLayout:Finalize()

    window.body = CreateFrame("Frame", nil, frame)
    window.body:SetPoint("TOPLEFT", INSET + SIDEBAR_WIDTH + 12, -CONTENT_TOP)
    window.body:SetPoint("BOTTOMRIGHT", -INSET, INSET)

    window.dismiss = settings:CreateButton(window.sidebar, {
        text = "Dismiss all",
        width = SIDEBAR_WIDTH,
        height = DISMISS_HEIGHT,
        onClick = function()
            lib:_DismissBatch()
        end,
    })
    window.dismiss:SetPoint("BOTTOMLEFT")
    PixelUtil.SetRoundLayoutToNearestPixelRecursively(window.sidebar, true)

    window.errorText = settings:CreateText(window.body, {
        text = "These update notes could not be displayed. They have not been marked as read.",
        width = 540,
        fontObject = GameFontHighlight,
    })
    window.errorText:SetPoint("TOPLEFT", 8, -8)
    window.errorText:Hide()

    frame:HookScript("OnHide", function()
        frame:StopMovingOrSizing()

        if window.selectedView then window.selectedView:CancelDrafts() end
    end)
    settings:EnableTabNavigation(frame)

    return window
end

function lib:_UpdateBadges()
    local window = self._window
    local batch = self._batch

    if not window or not batch then return end

    for index, entry in ipairs(batch.entries) do
        local isNew = self:_IsNew(entry)
        local row = window.rows[index]

        if row then
            local status = entry.release.version

            if isNew then status = status .. "  |cffffd100NEW|r" end

            row.status:SetText(status)

            local selected = batch.selected == index
            row.selected = selected
            row.button:SetSelected(selected)
            row.background:SetColorTexture(
                1,
                1,
                1,
                selected and 0.14 or row.backgroundAlpha
            )
            resizeSidebarRow(row)
        end
    end
end

function lib:_SelectEntry(index, userInitiated)
    local window, batch = self._window, self._batch

    if not window or not batch then return end

    if window.selectedView then
        window.selectedView:CancelDrafts()
        window.selectedView.frame:Hide()
    end

    batch.selected = index
    local entry = batch.entries[index]
    local view = entry.view
    window.selectedView = view
    window.errorText:SetShown(view == nil)

    if view then
        view.frame:Show()
        view:Refresh()

        if userInitiated then self:_Acknowledge(entry) end
    end

    self:_UpdateBadges()
end

function lib:_PrepareBatch(entries, manual)
    local window = self:_EnsureWindow()
    self._batch = {
        entries = entries,
        manual = manual,
        selected = 1,
    }

    local bodyOffset = SIDEBAR_WIDTH + 12
    window.sidebar:Show()
    window.body:ClearAllPoints()
    window.body:SetPoint("TOPLEFT", INSET + bodyOffset, -CONTENT_TOP)
    window.body:SetPoint("BOTTOMRIGHT", -INSET, INSET)

    local width = WIDTH - INSET * 2 - bodyOffset
    local height = HEIGHT - CONTENT_TOP - INSET
    local title = #entries == 1 and "What's New — 1 addon updated"
        or ("What's New — " .. #entries .. " addons updated")

    if manual then
        title = #entries == 1 and "Changelog — 1 addon"
            or ("Changelogs — " .. #entries .. " addons")

        if #entries == 1 and entries[1].release.unreleased then
            title = "Changelog — Unreleased preview"
        end
    end

    window.frame.TitleContainer.TitleText:SetText(title)

    for index, entry in ipairs(entries) do
        local row = window.rows[index]

        if not row then
            row = self:_CreateSidebarRow(index)
            window.rows[index] = row
        end

        self:_UpdateSidebarRow(row, entry)

        local view = window.popupViews[entry.controller.addonName]

        if view and view.entry.release ~= entry.release then
            view.frame:Hide()
            view = nil
        end

        if not view then
            view = self:_CreateView(entry, window.body, {
                width = width,
                height = height,
                popup = true,
            })
            window.popupViews[entry.controller.addonName] = view
        else
            entry.failed = view.entry.failed
            view.entry = entry
            view:SetSize(width, height)
        end

        entry.view = view

        if view then
            view.frame:SetPoint("TOPLEFT")
            view:ResetNavigation()
        end
    end

    for index = #entries + 1, #window.rows do
        window.rows[index].flow:SetShown(false)
    end

    window.sidebarLayout:RefreshLayout()
    self:_SelectEntry(1, false)
end

function lib:_RevealBatch()
    local window = self._window
    window.frame:SetScale(
        math.min(
            1,
            (UIParent:GetWidth() - 32) / WIDTH,
            (UIParent:GetHeight() - 32) / HEIGHT
        )
    )
    window.frame:Show()
    self:_RefreshSidebarRows()
end

function lib:_DismissBatch()
    if not self._batch then return end

    for _, entry in ipairs(self._batch.entries) do
        self:_Acknowledge(entry)
    end

    self._batch = nil
    self._window.frame:Hide()
    self:_Schedule()
end
