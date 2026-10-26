return function(lib)
    local originalWindow, originalBatch = lib._window, lib._batch
    local originalSettings, originalCreateFrame, originalAddOns =
        lib._GetSettingsLibrary, CreateFrame, C_AddOns
    local originalAfter = C_Timer.After
    local originalPixelUtil = PixelUtil
    local deferred = {}
    local physicalHeight = 768

    PixelUtil = {
        GetPixelToUIUnitFactor = function()
            return 768 / physicalHeight
        end,
        GetNearestPixelSize = function(value, scale)
            local unit = 768 / physicalHeight / scale
            return math.floor(value / unit + 0.5) * unit
        end,
        SetRoundLayoutToNearestPixelRecursively = function(frame, enabled)
            frame:SetRoundLayoutToNearestPixel(enabled)

            for _, child in ipairs(frame.children or {}) do
                PixelUtil.SetRoundLayoutToNearestPixelRecursively(
                    child,
                    enabled
                )
            end

            for _, texture in ipairs(frame.textures or {}) do
                texture:SetRoundLayoutToNearestPixel(enabled)
            end
        end,
    }

    C_Timer.After = function(_, callback)
        deferred[#deferred + 1] = callback
    end

    -- Passive regions record layout calls from the real batch preparation code.
    -- Native rendering and hit testing still need an in-game check.
    local function region()
        return {
            shown = true,
            scripts = {},
            children = {},
            textures = {},
            events = {},
            SetShown = function(self, shown)
                self.shown = shown
            end,
            IsShown = function(self)
                return self.shown
            end,
            IsVisible = function(self)
                return self.shown
            end,
            Show = function(self)
                self.shown = true
            end,
            Hide = function(self)
                self.shown = false
            end,
            SetText = function(self, text)
                self.text = text
            end,
            SetButtonText = function(self, text)
                self.text = text
            end,
            SetSelected = function(self, selected)
                self.selected = selected
            end,
            SetButtonIcon = function(self, icon)
                self.icon = icon
            end,
            SetScript = function(self, script, callback)
                self.scripts[script] = callback
            end,
            RegisterEvent = function(self, event)
                self.events[event] = true
            end,
            HookScript = function(self, script, callback)
                local previous = self.scripts[script]

                self.scripts[script] = function(...)
                    if previous then previous(...) end

                    callback(...)
                end
            end,
            Click = function(self, button)
                self.scripts.OnClick(self, button or "LeftButton")
            end,
            SetHitRectInsets = function(self, ...)
                self.hitInsets = { ... }
            end,
            ClearAllPoints = function(self)
                self.points = {}
            end,
            SetPoint = function(self, point, ...)
                self.points = self.points or {}
                self.points[point] = { ... }
                self.pointWrites = (self.pointWrites or 0) + 1
            end,
            SetRoundLayoutToNearestPixel = function(self, enabled)
                self.roundLayout = enabled
            end,
            SetSize = function(self, width, height)
                self.width, self.height = width, height

                if self.scripts.OnSizeChanged then
                    self.scripts.OnSizeChanged(self, width, height)
                end
            end,
            SetWidth = function(self, width)
                self.width = width
            end,
            SetHeight = function(self, height)
                self.heightWrites = (self.heightWrites or 0) + 1
                self:SetSize(self.width, height)
            end,
            GetWidth = function(self)
                return self.width
            end,
            GetHeight = function(self)
                return self.height + (self.heightError or 0)
            end,
            GetRect = function(self)
                self.rectReads = (self.rectReads or 0) + 1
                return self.left or 0, self.bottom or 0, self.width, self.height
            end,
            GetEffectiveScale = function(self)
                return self.scale or 1
            end,
            GetStringHeight = function(self)
                return self.stringHeight or 12
            end,
            SetFrameStrata = function(self, strata)
                self.strata = strata
            end,
            SetFrameLevel = function(self, level)
                self.level = level
            end,
            GetFrameLevel = function(self)
                return self.level or 1
            end,
            SetToplevel = function(self, value)
                self.topLevel = value
            end,
            SetMovable = function(self, value)
                self.movable = value
            end,
            StartMoving = function(self)
                self.moving = true
            end,
            StopMovingOrSizing = function(self)
                self.moving = false
            end,
            SetUserPlaced = function(self, value)
                self.userPlaced = value
            end,
            SetDontSavePosition = function(self, value)
                self.dontSavePosition = value
            end,
            SetClampedToScreen = function(self, value)
                self.clamped = value
            end,
            EnableMouse = function(self, value)
                self.mouseEnabled = value
            end,
            EnableKeyboard = function(self, value)
                self.keyboardEnabled = value
            end,
            SetPropagateKeyboardInput = function(self, value)
                self.propagateKeys = value
            end,
            RegisterForDrag = function(self, button)
                self.dragButton = button
            end,
            CreateTexture = function(self)
                local texture = {
                    parent = self,
                    shown = true,
                    points = {},
                    SetAllPoints = function() end,
                    SetPoint = function(owner, point, ...)
                        owner.points[point] = { ... }
                    end,
                    SetRoundLayoutToNearestPixel = function(owner, enabled)
                        owner.roundLayout = enabled
                    end,
                    SetHeight = function(owner, height)
                        owner.height = height
                    end,
                    SetWidth = function(owner, width)
                        owner.width = width
                    end,
                    SetColorTexture = function(owner, ...)
                        owner.color = { ... }
                    end,
                    SetBlendMode = function(owner, mode)
                        owner.blendMode = mode
                    end,
                    SetSnapToPixelGrid = function(owner, enabled)
                        owner.snapToPixelGrid = enabled
                    end,
                    SetTexelSnappingBias = function(owner, bias)
                        owner.texelSnappingBias = bias
                    end,
                    Show = function(owner)
                        owner.shown = true
                    end,
                    Hide = function(owner)
                        owner.shown = false
                    end,
                }
                self.textures[#self.textures + 1] = texture
                return texture
            end,
        }
    end

    CreateFrame = function(_, _, parent, template)
        local frame = region()
        frame.parent, frame.template = parent, template

        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end

        if template == "DefaultPanelTemplate" then
            frame.TitleContainer = region()
            frame.TitleContainer.TitleText = region()
            frame.TopTileStreaks = region()
        elseif template == "InsetFrameTemplate" then
            frame.Bg = frame:CreateTexture()
        end

        return frame
    end

    local metadata = {
        First = { IconTexture = "first.tga" },
        Second = { IconAtlas = "second-atlas" },
        Numeric = { IconTexture = "12345" },
        Missing = { IconTexture = "", IconAtlas = "" },
    }
    C_AddOns = {
        DoesAddOnExist = function(name)
            return metadata[name] ~= nil
        end,
        GetAddOnMetadata = function(name, field)
            return metadata[name] and metadata[name][field]
        end,
    }

    local settings = {
        CreateButton = function(_, parent, options)
            local button = region()
            button.parent, button.options = parent, options
            parent.children[#parent.children + 1] = button
            button.scripts.OnClick = options.onClick

            button.scripts.OnEnter = function(self)
                self.nativeHover = true
            end

            button.scripts.OnLeave = function(self)
                self.nativeHover = false
            end

            button:SetSize(
                options.width or 34,
                options.height or options.width or 34
            )
            return button
        end,
        CreateText = function(_, parent, options)
            local text = region()
            text.parent, text.text = parent, options.text
            parent.children[#parent.children + 1] = text
            return text
        end,
        SetTooltip = function(_, owner, options)
            owner.tooltip = options
        end,
        EnableTabNavigation = function(_, frame)
            frame.tabNavigation = true
        end,
    }

    lib._GetSettingsLibrary = function()
        return settings
    end

    local function createFlow(width)
        local flow = region()
        flow.parent = region()

        flow.GetWidth = function()
            return width
        end

        flow.AddFrame = function(self, frame, options)
            self.frame, self.options = frame, options
        end

        flow.Finish = function() end

        return flow
    end

    function settings:CreateCanvasLayout(parent, options)
        parent:SetSize(options.width, options.height)
        local content = region()
        content.parent = parent
        parent.children[#parent.children + 1] = content

        -- LMS's own tests cover its geometry. Here it supplies a measured flow
        -- width so the sidebar row can be checked independently of those rules.
        local contentWidth = 195

        return {
            parent = parent,
            options = options,
            Finalize = function() end,
            RefreshLayout = function() end,
            GetContent = function()
                return content
            end,
            GetRootFlow = function()
                return {
                    BeginGroup = function()
                        return createFlow(contentWidth)
                    end,
                }
            end,
        }
    end

    lib._window = nil
    local window = lib:_EnsureWindow()
    local sidebarLayout = window.sidebarLayout
    local sidebarCanvas, sidebarOptions =
        sidebarLayout.parent, sidebarLayout.options
    assert(
        window.sidebarInset.template == "InsetFrameTemplate"
            and window.sidebarInset.parent == window.sidebar
            and sidebarCanvas == window.sidebarInset,
        "the sidebar passes its native inset directly to LMS"
    )
    assert(
        window.sidebarInset.points.TOPLEFT
            and window.sidebarInset.points.BOTTOMRIGHT[2] == 46,
        "the sidebar inset leaves room for Dismiss all and its gap"
    )
    assert(
        window.sidebar.width == sidebarCanvas.width
            and window.sidebar.height - 46 == sidebarCanvas.height,
        "the addon does not subtract LMS-owned border or scrollbar dimensions"
    )
    assert(
        sidebarOptions.scrollable
            and sidebarOptions.style == nil
            and sidebarOptions.scrollArea.preset == "inset"
            and sidebarOptions.scrollArea.contentSpacing == "compact"
            and sidebarOptions.viewportMarginBottom == nil,
        "the sidebar opts into LMS's compact inset spacing"
    )
    assert(
        window.dismiss.parent == window.sidebar
            and window.dismiss.points.BOTTOMLEFT,
        "Dismiss all remains outside the scrolling inset"
    )

    local function addEntry(name)
        local storage = {}
        local entry = {
            displayName = name,
            release = { version = "1" },
            controller = {
                addonName = name,
                options = {
                    storage = {
                        get = function(key)
                            return storage[key]
                        end,
                        set = function(key, value)
                            storage[key] = value
                        end,
                    },
                },
            },
        }
        local view = {
            entry = entry,
            popup = true,
            frame = region(),
            body = region(),
            headerHeight = 50,
            headerLayout = region(),
            layout = region(),
            SetSize = lib._viewPrototype.SetSize,
            _ResizeBody = lib._viewPrototype._ResizeBody,
            Refresh = function() end,
            CancelDrafts = function() end,
            ResetNavigation = function() end,
        }
        window.popupViews[name] = view
        return entry, storage, view
    end

    local first, firstStore, firstView = addEntry("First")
    local second, secondStore, secondView = addEntry("Second")
    lib:_PrepareBatch({ first }, false)
    assert(
        window.sidebar.shown and window.rows[1].flow.shown,
        "single-addon notifications keep the sidebar and their addon row visible"
    )
    assert(window.rows[2] == nil, "unused rows are not created")
    assert(
        window.rows[1].button.selected and firstView.frame.shown,
        "the first addon is selected and its content is visible immediately"
    )
    assert(
        firstStore.acknowledgedVersion == nil
            and window.rows[1].status.text:find("NEW", 1, true),
        "automatic initial selection does not mark the addon as read"
    )
    local firstRow = window.rows[1]
    local selectedAlpha = firstRow.background.color[4]
    assert(
        selectedAlpha > firstRow.backgroundAlpha and firstRow.border.shown,
        "initial selection highlights and outlines the full row"
    )
    assert(
        firstRow.frame.width == 195 and firstRow.name.width == 131,
        "the narrow sidebar reclaims space for the addon name without shrinking its icon"
    )
    assert(
        firstRow.button.options.variant == "square"
            and firstRow.button.options.iconSize == 28
            and firstRow.button.width == 40
            and firstRow.button.height == 40
            and firstRow.frame.height == 50
            and firstRow.button.icon.iconTexture == "first.tga",
        "larger masked icon buttons preserve the normal list row's height"
    )
    assert(
        firstRow.name.parent == firstRow.frame
            and firstRow.status.parent == firstRow.frame
            and firstRow.name.points.TOPLEFT[1] == firstRow.frame
            and firstRow.status.points.TOPLEFT[1] == firstRow.name,
        "the name and status stack beside the icon inside one row"
    )
    assert(
        firstRow.button.points.TOPLEFT[1] == firstRow.frame
            and firstRow.button.points.TOPLEFT[3] == 8
            and firstRow.button.points.TOPLEFT[4] == -5
            and firstRow.name.points.TOPLEFT[2] == "TOPLEFT"
            and firstRow.name.points.TOPLEFT[4] == -11,
        "the icon and combined name/status block are vertically centered in the row"
    )
    assert(
        firstRow.name.text == "First"
            and firstRow.status.text == "1  |cffffd100NEW|r",
        "version and unread status share the second text row"
    )
    assert(
        firstRow.frame.scripts.OnClick == nil
            and firstRow.button.hitInsets[1] == -8
            and firstRow.button.hitInsets[2] == -147
            and firstRow.button.hitInsets[3] == -5
            and firstRow.button.hitInsets[4] == -5,
        "one native button covers the full row, including text and padding"
    )
    local hover = firstRow.frame.textures[2]
    assert(not hover.shown, "rows start without a hover highlight")
    firstRow.button.scripts.OnEnter(firstRow.button)
    assert(
        hover.shown
            and firstRow.button.nativeHover
            and firstStore.acknowledgedVersion == nil,
        "hover highlights the entire row without replacing LMS hover or acknowledging notes"
    )
    firstRow.button.scripts.OnLeave(firstRow.button)
    assert(
        not hover.shown
            and not firstRow.button.nativeHover
            and firstRow.background.color[4] == selectedAlpha
            and firstRow.border.shown,
        "leaving the row clears hover while keeping its selected background and border"
    )
    firstRow.button.scripts.OnEnter(firstRow.button)
    firstRow.button.scripts.OnHide(firstRow.button)
    assert(
        not hover.shown,
        "hiding a hovered row clears its highlight before reuse"
    )
    local contentWidth = firstView.layout.width
    local contentLeft = window.body.points.TOPLEFT[1]

    lib:_PrepareBatch({ first, second }, true)
    assert(
        window.sidebar.shown
            and window.rows[1].flow.shown
            and window.rows[2].flow.shown,
        "multi-addon browsing uses the same sidebar"
    )
    assert(
        contentWidth > 0
            and firstView.layout.width == contentWidth
            and secondView.layout.width == contentWidth
            and window.body.points.TOPLEFT[1] == contentLeft,
        "content size and position do not change with the number of addons"
    )
    assert(
        window.rows[2].button.icon.iconAtlas == "second-atlas",
        "TOC atlas icons are also supported"
    )
    assert(
        firstRow.backgroundAlpha ~= window.rows[2].backgroundAlpha,
        "successive row frames have alternating backgrounds"
    )
    local secondRow = window.rows[2]
    secondRow.button.scripts.OnEnter(secondRow.button)
    local secondHover = secondRow.frame.textures[2]
    local hoveredAlpha = secondRow.background.color[4]
        + secondHover.color[4] * (1 - secondRow.background.color[4])
    assert(
        secondHover.shown
            and hoveredAlpha < selectedAlpha
            and not secondRow.border.shown,
        "hovering the lighter alternating row stays subtler than selection without gaining a border"
    )
    secondRow.button.scripts.OnLeave(secondRow.button)
    window.rows[2].button:Click("LeftButton")
    assert(
        window.rows[2].button.selected and not window.rows[1].button.selected,
        "sidebar selection uses the LMS selected-button state"
    )
    assert(
        secondRow.background.color[4] == selectedAlpha
            and secondRow.border.shown
            and firstRow.background.color[4] == firstRow.backgroundAlpha
            and not firstRow.border.shown,
        "selecting another addon transfers the full-row highlight and restores the old stripe"
    )
    assert(
        secondStore.acknowledgedVersion == "1"
            and firstStore.acknowledgedVersion == nil,
        "the full-row button uses LMS's selection path and only acknowledges that addon"
    )
    assert(
        window.rows[2].status.text == "1"
            and firstRow.status.text:find("NEW", 1, true),
        "read status updates without clearing another addon's NEW indicator"
    )

    lib:_PrepareBatch({ first }, true)
    assert(
        window.sidebar.shown
            and window.rows[1].flow.shown
            and not window.rows[2].flow.shown,
        "returning to one addon hides only unused rows, not the sidebar"
    )
    assert(
        firstView.layout.width == contentWidth
            and window.body.points.TOPLEFT[1] == contentLeft,
        "single-addon manual previews retain the shared content layout"
    )
    assert(
        window.body.points.BOTTOMRIGHT[2] == 16
            and firstView.frame.height == 586,
        "the right pane reaches the bottom inset without reserving a footer"
    )
    assert(
        firstView.layout.width == 656 and firstView.layout.height == 536,
        "reused views pass the full body size to LMS's inset layout"
    )
    assert(
        firstStore.acknowledgedVersion == nil,
        "changing batch size does not acknowledge unread notes"
    )
    lib:_PrepareBatch({ first, second }, true)
    assert(
        firstRow.background.color[4] == selectedAlpha
            and firstRow.border.shown
            and secondRow.background.color[4] == secondRow.backgroundAlpha
            and not secondRow.border.shown,
        "reusing a previously selected row does not retain its selection in a new batch"
    )

    local missing = addEntry("Missing")
    missing.release = { version = "Unreleased", unreleased = true }
    lib:_PrepareBatch({ missing }, true)
    assert(
        window.rows[1] == firstRow
            and firstRow.name.text == "Missing"
            and firstRow.status.text == "Unreleased",
        "reused rows replace all name/status text"
    )
    assert(
        firstRow.button.icon.iconTexture
                == "Interface\\Icons\\INV_Misc_QuestionMark"
            and firstRow.button.icon.iconAtlas == nil,
        "missing metadata uses a fallback without retaining an old atlas"
    )

    local numeric = addEntry("Numeric")
    lib:_PrepareBatch({ numeric }, true)
    assert(
        firstRow.button.icon.iconTexture == 12345,
        "numeric TOC icon strings become texture file IDs"
    )
    firstRow.name.stringHeight, firstRow.status.stringHeight = 48, 24
    firstRow.frame.scripts.OnShow(firstRow.frame)

    for _, callback in ipairs(deferred) do
        callback()
    end

    assert(
        firstRow.frame.height == 86 and firstRow.name.points.TOPLEFT[4] == -5,
        "wrapped or newly measurable text expands the row and recenters the text block"
    )
    assert(
        firstRow.button.hitInsets[3] == -23
            and firstRow.button.hitInsets[4] == -23,
        "wrapped rows expand their hit area to match the visible height"
    )
    firstRow.frame:SetSize(250, firstRow.frame.height)
    assert(
        firstRow.button.hitInsets[2] == -202,
        "resizing the sidebar updates the clickable width without extending into the scrollbar"
    )

    local absent = addEntry("NoTOC")
    lib:_PrepareBatch({ absent }, true)
    assert(
        firstRow.button.icon.iconTexture
            == "Interface\\Icons\\INV_Misc_QuestionMark",
        "development registrations without a real addon use the fallback"
    )

    local function assertPixelBorder()
        local frame, border = firstRow.frame, firstRow.border
        local unit = 768 / physicalHeight / frame:GetEffectiveScale()
        local topLeft = border.points.TOPLEFT
        local bottomRight = border.points.BOTTOMRIGHT
        assert(
            topLeft[1] == frame
                and topLeft[2] == "TOPLEFT"
                and bottomRight[1] == frame
                and bottomRight[2] == "BOTTOMRIGHT",
            "the border follows row bounds without reading screen coordinates"
        )
        for _, inset in ipairs({
            topLeft[3],
            -topLeft[4],
            -bottomRight[3],
            bottomRight[4],
        }) do
            assert(
                math.abs(inset / unit - 1) < 0.00001,
                "all four border edges stay one physical pixel inside the native row layout"
            )
        end
        local edges = firstRow.borderEdges
        assert(#edges == 4 and border.template == nil)

        for index, edge in ipairs(edges) do
            local thickness = index <= 2 and edge.height or edge.width
            assert(
                math.abs(thickness / unit - 1) < 0.00001
                    and edge.parent == border
                    and edge.color[4] == 0.9
                    and edge.blendMode == "BLEND"
                    and edge.snapToPixelGrid == false
                    and edge.texelSnappingBias == 0,
                "each solid stroke is one physical pixel thick without texture sharpening"
            )
        end

        local topEdge, bottomEdge, leftEdge, rightEdge = unpack(edges)
        assert(
            topEdge.points.TOPLEFT
                and topEdge.points.TOPRIGHT
                and bottomEdge.points.BOTTOMLEFT
                and bottomEdge.points.BOTTOMRIGHT
                and leftEdge.points.TOPLEFT[1] == topEdge
                and leftEdge.points.TOPLEFT[2] == "BOTTOMLEFT"
                and leftEdge.points.BOTTOMLEFT[1] == bottomEdge
                and leftEdge.points.BOTTOMLEFT[2] == "TOPLEFT"
                and rightEdge.points.TOPRIGHT[1] == topEdge
                and rightEdge.points.TOPRIGHT[2] == "BOTTOMRIGHT"
                and rightEdge.points.BOTTOMRIGHT[1] == bottomEdge
                and rightEdge.points.BOTTOMRIGHT[2] == "TOPRIGHT",
            "horizontal strokes own both corners without overlap from vertical strokes"
        )
        assert(
            border.parent == frame
                and border.mouseEnabled == false
                and frame.width == 250
                and firstRow.button.hitInsets[2] == -202,
            "the outline does not change row width or intercept its input"
        )
    end

    local function assertNativeLayout(frame)
        assert(
            frame.roundLayout,
            "every sidebar region uses native pixel layout"
        )

        for _, child in ipairs(frame.children or {}) do
            assertNativeLayout(child)
        end

        for _, texture in ipairs(frame.textures or {}) do
            assert(
                texture.roundLayout,
                "row textures use the same pixel layout"
            )
        end
    end

    assert(window.frame.roundLayout, "native dragging rounds the window layout")
    assertNativeLayout(window.sidebar)
    window.frame:Show()
    for _, sample in ipairs({
        { height = 1080, scale = 0.64 },
        { height = 1440, scale = 0.8 },
        { height = 2160, scale = 1 },
        { height = 1080, scale = 0.4 },
        { height = 1080, scale = 1.25 },
    }) do
        physicalHeight = sample.height
        firstRow.frame.scale = sample.scale
        firstRow.frame.left, firstRow.frame.bottom = 100.3, 200.7
        lib:_RefreshSidebarRows()
        assertPixelBorder()

        local pointWrites = firstRow.border.pointWrites
        firstRow.frame.bottom = 193.25
        assertPixelBorder()
        assert(
            firstRow.border.pointWrites == pointWrites
                and firstRow.frame.rectReads == nil,
            "scrolling needs no screen-coordinate reads or independent border correction"
        )

        local heightWrites = firstRow.frame.heightWrites
        firstRow.frame.heightError = 0.00001
        firstRow.frame.scripts.OnSizeChanged(firstRow.frame)
        firstRow.frame.heightError = nil
        assert(
            firstRow.frame.heightWrites == heightWrites,
            "native float readback does not rewrite row height and request another reflow"
        )
    end

    assert(
        window.frame.events.UI_SCALE_CHANGED
            and window.frame.events.DISPLAY_SIZE_CHANGED,
        "window scaling and screen-resolution changes both refresh row geometry"
    )
    for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        firstRow.frame.scale = firstRow.frame.scale + 0.15
        physicalHeight = physicalHeight + 360
        window.frame.scripts.OnEvent(window.frame, event)
        local pending = deferred
        deferred = {}

        for _, callback in ipairs(pending) do
            callback()
        end

        assertPixelBorder()
    end

    assert(window.frame.scripts.OnUpdate == nil, "idle windows do not poll")
    local borderWrites = firstRow.border.pointWrites
    local nameWrites = firstRow.name.pointWrites
    local buttonWrites = firstRow.button.pointWrites
    window.frame.TitleContainer.scripts.OnDragStart()
    assert(window.frame.moving and window.frame.scripts.OnUpdate == nil)
    firstRow.frame.left, firstRow.frame.bottom = 203.45, 317.65
    assertPixelBorder()
    window.frame.TitleContainer.scripts.OnDragStop()
    assert(not window.frame.moving and window.frame.scripts.OnUpdate == nil)
    assert(
        firstRow.border.pointWrites == borderWrites
            and firstRow.name.pointWrites == nameWrites
            and firstRow.button.pointWrites == buttonWrites,
        "native dragging moves the existing layout without independently repositioning its artwork"
    )
    window.frame.TitleContainer.scripts.OnDragStart()
    window.frame.scripts.OnHide()
    assert(
        not window.frame.moving and window.frame.scripts.OnUpdate == nil,
        "closing or suspending the window also stops native dragging"
    )

    window.frame:Hide()
    lib:_RefreshSidebarRows()
    assert(
        firstRow.border.pointWrites == borderWrites,
        "deferred scale updates do not lay out a closed window"
    )

    lib._window, lib._batch = originalWindow, originalBatch
    lib._GetSettingsLibrary, CreateFrame, C_AddOns =
        originalSettings, originalCreateFrame, originalAddOns
    C_Timer.After = originalAfter
    PixelUtil = originalPixelUtil
end
