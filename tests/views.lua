return function(lib)
    local owner, label = "one", "First profile"
    local changed, cancelled, requested, headerRequested = {}, 0, 0, 0
    local stored = {}
    local controller = {
        addonName = "ViewExample",
        _GetContext = function() return owner, label end,
        GetAutoShowEnabled = function() return true end,
    }
    local view = setmetatable({
        controller = controller,
        entry = { controller = controller, release = { version = "view-example" } },
        bindings = {
            {
                Refresh = function(_, ownerChanged) changed[#changed + 1] = ownerChanged end,
                CancelDraft = function() cancelled = cancelled + 1 end,
            },
        },
        contextGroup = {
            AddText = function(_, options)
                stored.label = options.text
                return { SetText = function(_, text) stored.label = text end }
            end,
            SetShown = function(_, shown) stored.contextShown = shown end,
        },
        autoShow = { SetValue = function(_, value) stored.autoShow = value end },
        headerLayout = { RequestLayout = function() headerRequested = headerRequested + 1 end },
        layout = { RequestLayout = function() requested = requested + 1 end },
        messages = { Show = function() end },
    }, lib._viewPrototype)

    view:Refresh()
    assert(changed[1] == true and stored.label == "First profile" and stored.contextShown and stored.autoShow)
    view:Refresh()
    assert(changed[2] == false, "same-owner refresh preserves drafts")
    owner, label = "two", "Second profile"
    view:Refresh()
    assert(changed[3] == true and stored.label == "Second profile", "profile ownership change reaches every binding")
    owner, label = "three", nil
    view:Refresh()
    assert(changed[4] == true and not stored.contextShown,
        "identity-only contexts still refresh bindings without reserving a notice row")
    assert(requested == 4 and headerRequested == 4,
        "refresh uses retained header and body layouts rather than reconstructing controls")

    view.contextText = nil
    view:Refresh()
    assert(view.contextText == nil and not stored.contextShown,
        "contexts without labels never create an empty text row")

    view.bindings[1].Refresh = function() error("expected failed getter") end
    view:Refresh()
    assert(view.entry.failed and cancelled == 1)
    assert(lib._sessionFailures.ViewExample == "view-example", "failed refresh cannot trigger popup retries")

    -- Record the real layout setup without recreating native scrolling.
    local originalCreateFrame = CreateFrame
    CreateFrame = function(_, _, parent, template)
        return {
            parent = parent,
            template = template,
            points = {},
            scripts = {},
            HookScript = function(self, script, callback)
                self.scripts[script] = callback
            end,
            SetPoint = function(self, point, ...)
                self.points[point] = { ... }
            end,
            SetSize = function(self, width, height)
                self.width, self.height = width, height

                if self.scripts.OnSizeChanged then
                    self.scripts.OnSizeChanged(self, width, height)
                end
            end,
            GetWidth = function(self) return self.width end,
            GetHeight = function(self) return self.height end,
        }
    end

    local settings = {
        CreateCanvasLayout = function(_, parent, options)
            parent:SetSize(options.width, options.height)
            local content = CreateFrame("Frame", nil, parent)
            local columns = { left = {}, right = {} }
            local layout = { parent = parent, options = options, texts = {} }

            function columns.left:AddText(textOptions)
                layout.texts[#layout.texts + 1] = textOptions
            end

            function columns.right:AddControl(controlType, controlOptions)
                assert(controlType == "checkbox")
                layout.checkbox = controlOptions
                return { options = controlOptions }
            end

            function columns:Finish() layout.columnsFinished = true end
            function layout:GetRootFlow()
                return {
                    BeginColumns = function(_, columnOptions)
                        layout.columnOptions = columnOptions
                        return columns
                    end,
                }
            end

            function layout:GetContent() return content end
            function layout:GetCanvasWidth() return parent:GetWidth() end
            function layout:GetCanvasHeight() return parent:GetHeight() end
            function layout:GetContentInsets() return 16, 39, 4, 8 end
            function layout:SetSize(width, height) parent:SetSize(width, height) end
            function layout:Finalize()
                assert(self.columnsFinished)
                -- LMS owns measuring the row. Verify the view uses its result.
                content:SetSize(parent:GetWidth(), 50)
            end

            return layout
        end,
    }

    local enabled, interactions = true, 0
    local headerController = {
        GetAutoShowEnabled = function() return enabled end,
        SetAutoShowEnabled = function(_, value) enabled = value end,
    }
    local entry = {
        controller = headerController,
        displayName = "Example Addon",
        release = { version = "1.2.0", date = "2026-10-12" },
    }
    local popup = setmetatable({
        frame = CreateFrame(),
        popup = true,
        entry = entry,
        controller = headerController,
        Interact = function() interactions = interactions + 1 end,
    }, lib._viewPrototype)
    popup:_CreateLayout(settings, { width = 656, height = 586 })
    popup:_CreateHeader()

    local header = popup.headerLayout
    assert(header.texts[1].text == "Example Addon" and header.texts[2].text == "1.2.0  |  2026-10-12",
        "the header stacks the addon name above its release tag and optional date")
    assert(header.columnOptions.verticalAlign == "center",
        "LMS centers the name/tag block vertically beside the login checkbox")
    assert(header.checkbox.label == "Show changelog for Example Addon on login" and header.checkbox.value,
        "the right column identifies which addon's automatic notices are controlled")
    header.checkbox.onChanged(false)
    assert(not enabled and interactions == 1, "the relocated checkbox still saves consent and acknowledges interaction")

    local canvas = popup.layout.parent
    local options = popup.layout.options
    assert(popup.inset.template == "InsetFrameTemplate" and canvas == popup.inset,
        "the popup passes its native inset directly to LMS")
    assert(popup.inset.points.TOPLEFT[2] == -50 and popup.inset.points.BOTTOMRIGHT,
        "the inset starts below the measured header and reaches the bottom of the view")
    assert(canvas.width == popup.frame.width and canvas.height == popup.frame.height - 50,
        "the addon does not subtract LMS-owned border or scrollbar dimensions")
    assert(options.scrollable and options.style == nil and options.scrollArea.preset == "inset",
        "LMS owns popup content and scrollbar spacing")
    assert(header.options.scrollArea.preset == options.scrollArea.preset
        and header.options.style.paddingLeft == nil and header.options.style.scrollbarGap == nil,
        "header columns share the body preset without duplicating its horizontal geometry")
    assert(options.viewportMarginTop == nil and options.viewportMarginBottom == nil,
        "the header and inset margins are not added a second time")

    popup:SetSize(756, 686)
    assert(header:GetCanvasWidth() == 756, "resizing reflows both header columns")
    assert(canvas.width == 756 and canvas.height == 636,
        "resizing passes the full body dimensions to LMS")
    header:GetContent():SetSize(756, 72)
    assert(popup.inset.points.TOPLEFT[2] == -72 and popup.frame.height - 72 == canvas.height,
        "wrapped titles and later font measurements resize the body without overlap")

    local measurementFrame = CreateFrame()
    entry.release = { version = "Unreleased" }
    local page = setmetatable({
        frame = CreateFrame(),
        entry = entry,
        controller = headerController,
    }, lib._viewPrototype)
    page:_CreateLayout(settings, { width = 716, height = 633, measurementFrame = measurementFrame })
    page:_CreateHeader()
    assert(page.headerLayout.texts[2].text == "Unreleased",
        "undated previews show only the release tag below the name")
    assert(not page.inset and page.layout.parent == page.body,
        "embedded settings pages retain their ordinary canvas below the header")
    assert(page.layout.options.viewportMarginTop == nil and page.layout.options.style == nil
        and page.layout.options.scrollArea == nil and page.headerLayout.options.scrollArea == nil
        and page.headerLayout.options.measurementFrame == measurementFrame,
        "settings pages use LMS measurement and defaults without a second header reservation")
    assert(page.body.points.TOPLEFT[2] == -50 and page.layout.parent.height == 633 - 50,
        "settings pages use the same compact measured header")
    page:SetSize(700, 600)
    assert(page.frame.width == 700 and page.frame.height == 600 and page.layout.parent.height == 550,
        "settings page dimensions are not reduced by popup padding")

    local outdatedSettings = {
        CreateCanvasLayout = function() return {} end,
    }
    local staleView = setmetatable({ frame = CreateFrame(), popup = true }, lib._viewPrototype)
    local succeeded, failure = pcall(staleView._CreateLayout, staleView, outdatedSettings, { width = 656, height = 586 })
    assert(not succeeded and failure:find("scroll-area canvas support", 1, true),
        "an older selected LMS canvas fails clearly instead of silently ignoring the new spacing")

    CreateFrame = originalCreateFrame
end
