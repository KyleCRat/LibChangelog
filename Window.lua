local MAJOR, MINOR = "LibChangelog-1.0", 1
local lib = LibStub(MAJOR, true)

if not lib or lib._implementationMinor ~= MINOR
    or not lib:_BeginModule("Window", MINOR) then return end

local WIDTH, HEIGHT = 930, 640
local SIDEBAR_WIDTH = 230
local INSET, FOOTER = 16, 52

local function hasChildEscapeTarget()
    if GetCurrentKeyBoardFocus() or Menu.GetManager():IsAnyMenuOpen() then return true end

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
        if not InCombatLockdown() then frame:StartMoving() end
    end)
    frame.TitleContainer:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 0)
    close:SetFrameLevel(frame.TitleContainer:GetFrameLevel() + 1)
    close:SetScript("OnClick", function() lib:_DismissBatch() end)

    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end

        local dismiss = key == "ESCAPE" and not hasChildEscapeTarget()
        self:SetPropagateKeyboardInput(not dismiss)
        if dismiss then lib:_DismissBatch() end
    end)

    local window = { frame = frame, rows = {}, popupViews = {} }
    self._window = window

    window.sidebar = CreateFrame("Frame", nil, frame)
    window.sidebar:SetPoint("TOPLEFT", INSET, -38)
    window.sidebarLayout = settings:CreateCanvasLayout(window.sidebar, {
        width = SIDEBAR_WIDTH,
        height = HEIGHT - 38 - FOOTER,
        scrollable = true,
    })
    window.sidebarLayout:Finalize()

    window.body = CreateFrame("Frame", nil, frame)
    window.body:SetPoint("TOPLEFT", INSET, -38)
    window.body:SetPoint("BOTTOMRIGHT", -INSET, FOOTER)

    window.footer = settings:CreateText(frame, {
        text = "",
        width = WIDTH - 270,
        fontObject = GameFontHighlightSmall,
    })
    window.footer:SetPoint("BOTTOMLEFT", INSET + 8, 21)

    window.dismiss = settings:CreateButton(frame, {
        text = "Close all updates",
        width = 200,
        onClick = function() lib:_DismissBatch() end,
    })
    window.dismiss:SetPoint("BOTTOMRIGHT", -INSET, 14)

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

    local unread = 0

    for index, entry in ipairs(batch.entries) do
        local isNew = self:_IsNew(entry)
        if isNew then unread = unread + 1 end

        local row = window.rows[index]
        if row then
            row.badge:SetText(isNew and "|cffffd100NEW|r" or "")
            row.selected:SetShown(batch.selected == index)
        end
    end

    window.footer:SetText(unread > 0 and (unread .. " unread • Close dismisses all updates")
        or "Close dismisses all updates")
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
    self._batch = { entries = entries, manual = manual, selected = 1 }

    local multiple = #entries > 1
    local bodyOffset = multiple and SIDEBAR_WIDTH + 12 or 0
    window.sidebar:SetShown(multiple)
    window.body:ClearAllPoints()
    window.body:SetPoint("TOPLEFT", INSET + bodyOffset, -38)
    window.body:SetPoint("BOTTOMRIGHT", -INSET, FOOTER)

    local width = WIDTH - INSET * 2 - bodyOffset
    local height = HEIGHT - 38 - FOOTER
    local title = #entries == 1 and "What's New — 1 addon updated"
        or ("What's New — " .. #entries .. " addons updated")
    if manual and entries[1].release.unreleased then title = "What's New — Unreleased preview" end
    window.frame.TitleContainer.TitleText:SetText(title)

    for index, entry in ipairs(entries) do
        local row = window.rows[index]

        if not row then
            local flow = window.sidebarLayout:GetRootFlow():BeginGroup()
            local button = flow:AddControl("button", {
                text = entry.displayName,
                height = 54,
                onClick = function() lib:_SelectEntry(index, true) end,
            })
            local selected = button:CreateTexture(nil, "BACKGROUND")
            selected:SetAllPoints()
            selected:SetColorTexture(0.25, 0.5, 0.8, 0.25)

            local version = flow:AddText({ text = entry.release.version, fontObject = GameFontHighlightSmall })
            local titleGroup = flow:BeginGroup()
            local updateTitle = titleGroup:AddText({
                text = entry.release.title or "Update",
                fontObject = GameFontHighlightSmall,
            })
            titleGroup:Finish()

            row = {
                flow = flow,
                button = button,
                selected = selected,
                version = version,
                title = updateTitle,
                titleGroup = titleGroup,
                badge = flow:AddText({ text = "", height = 14, fontObject = GameFontNormalSmall }),
            }
            flow:Finish({ marginBottom = 16 })
            window.rows[index] = row
        end

        row.flow:SetShown(multiple)
        row.button:SetButtonText(entry.displayName)
        row.version:SetText(entry.release.version)
        row.title:SetText(entry.release.title or "Update")
        row.titleGroup:SetShown(entry.release.title ~= nil)

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
            view.entry = entry
            view.layout:SetSize(width, height)
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
    window.frame:SetScale(math.min(1, (UIParent:GetWidth() - 32) / WIDTH,
        (UIParent:GetHeight() - 32) / HEIGHT))
    window.frame:Show()
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
