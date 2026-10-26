local MAJOR, MINOR = "LibChangelog-1.0", 2
local lib = LibStub(MAJOR, true)

if
    not lib
    or lib._implementationMinor ~= MINOR
    or not lib:_BeginModule("View", MINOR)
then
    return
end

lib._viewPrototype = lib._viewPrototype or {}
local View = lib._viewPrototype
View.__index = View

local HEADER_MIN_HEIGHT = 1
local INSET_BACKGROUND = 17 / 255

function lib:_CreateInset(parent)
    local frame = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    frame.Bg:SetColorTexture(
        INSET_BACKGROUND,
        INSET_BACKGROUND,
        INSET_BACKGROUND,
        1
    )
    return frame
end

function View:_CreateLayout(settings, options)
    local header = CreateFrame("Frame", nil, self.frame)
    header:SetPoint("TOPLEFT")
    self.headerLayout = settings:CreateCanvasLayout(header, {
        width = options.width,
        height = options.height,
        measurementFrame = options.measurementFrame,
        scrollArea = self.popup and { preset = "inset" } or nil,
        style = {
            paddingTop = 4,
            paddingBottom = 8,
        },
    })
    assert(
        type(self.headerLayout.GetContentInsets) == "function",
        "LibChangelog requires LMS's scroll-area canvas support from LibModernSettings 1.10.0 or newer"
    )

    local width = self.headerLayout:GetCanvasWidth()
    local height = self.headerLayout:GetCanvasHeight()
    self.frame:SetSize(width, height)
    self.headerHeight = HEADER_MIN_HEIGHT
    self.headerLayout:SetSize(width, self.headerHeight)

    self.body = self.popup and lib:_CreateInset(self.frame)
        or CreateFrame("Frame", nil, self.frame)
    self.body:SetPoint("TOPLEFT", 0, -self.headerHeight)
    self.body:SetPoint("BOTTOMRIGHT")

    if self.popup then self.inset = self.body end

    self.layout = settings:CreateCanvasLayout(self.body, {
        width = width,
        height = height - self.headerHeight,
        scrollable = true,
        scrollArea = self.popup and { preset = "inset" } or nil,
    })

    -- Let wrapped titles and settled font metrics set the header's height,
    -- instead of reserving empty rows above the scrolling notes.
    self.headerLayout
        :GetContent()
        :HookScript("OnSizeChanged", function(_, _, headerHeight)
            self.headerHeight = headerHeight
            self:_ResizeBody()
        end)
end

function View:_ResizeBody()
    self.body:SetPoint("TOPLEFT", 0, -self.headerHeight)
    self.layout:SetSize(
        self.frame:GetWidth(),
        self.frame:GetHeight() - self.headerHeight
    )
end

function View:_CreateHeader()
    local entry = self.entry
    local release = entry.release.version

    if entry.release.date then
        release = release .. "  |  " .. entry.release.date
    end

    local columns = self.headerLayout
        :GetRootFlow()
        :BeginColumns({ verticalAlign = "center" })
    columns.left:AddText({
        text = entry.displayName,
        fontObject = GameFontNormalLarge,
    })
    columns.left:AddText({ text = release, fontObject = GameFontHighlightSmall })
    self.autoShow = columns.right:AddControl("checkbox", {
        label = "Show changelog for " .. entry.displayName .. " on login",
        tooltip = "Show changelogs after an update. You can still open them manually when this is off.",
        value = entry.controller:GetAutoShowEnabled(),
        onChanged = function(checked)
            self:Interact()
            self.controller:SetAutoShowEnabled(checked)
        end,
    })
    columns:Finish()
    self.headerLayout:Finalize()
end

function View:SetSize(width, height)
    self.frame:SetSize(width, height)
    self.headerLayout:SetSize(width, HEADER_MIN_HEIGHT)
    self:_ResizeBody()
end

function View:Interact()
    lib:_Acknowledge(self.entry)
end

function View:ResetNavigation()
    self.notesHeader:SetExpanded(false)
    self.notesGroup:SetShown(false)
    self.layout
        :GetScrollBox()
        :ScrollToBegin(ScrollBoxConstants.NoScrollInterpolation)
end

function View:QueueRefresh()
    if self.refreshTimer then return end

    self.refreshTimer = C_Timer.NewTimer(0, function()
        self.refreshTimer = nil
        self.controller:Refresh()
    end)
end

function View:CancelDrafts()
    for _, binding in ipairs(self.bindings) do
        binding:CancelDraft()
    end
end

function View:_RefreshBindings()
    local context, label = self.controller:_GetContext()
    local changed = context ~= self.context
    local hasLabel = label ~= nil and label ~= ""

    self.context = context

    if hasLabel then
        if self.contextText then
            self.contextText:SetText(label)
        else
            self.contextText = self.contextGroup:AddText({
                text = label,
                fontObject = GameFontHighlightSmall,
            }, { marginBottom = 8 })
        end
    end

    self.contextGroup:SetShown(hasLabel)
    self.autoShow:SetValue(self.controller:GetAutoShowEnabled())

    for _, binding in ipairs(self.bindings) do
        binding:Refresh(changed)
    end

    self.headerLayout:RequestLayout()
    self.layout:RequestLayout()
end

function View:Refresh()
    if self.invoking then
        self:QueueRefresh()
        return
    end

    local ok, failure = pcall(self._RefreshBindings, self)

    if not ok then
        self.entry.failed = true
        lib._sessionFailures[self.controller.addonName] =
            self.entry.release.version
        self:CancelDrafts()
        self.messages:Show(
            "These update controls could not be refreshed",
            "error"
        )

        if self.lastError ~= failure then geterrorhandler()(failure) end

        self.lastError = failure
    else
        self.entry.failed = nil
        self.lastError = nil
    end
end

local function addNotes(flow, notes)
    for _, block in ipairs(notes) do
        if block.kind == "heading" then
            flow:AddSection(block.text)
        else
            local text = block.text:gsub("|", "||")

            if block.kind == "bullet" then text = "• " .. text end

            flow:AddText({
                text = text,
                fontObject = GameFontHighlight,
            }, {
                indent = block.kind == "bullet" and 1 or 0,
                marginBottom = 8,
            })
        end
    end
end

function View:_AddHighlight(flow, highlight)
    local group = flow:BeginGroup({ marginTop = 8 })
    local emphasis = highlight.emphasis

    if emphasis then
        local color = emphasis == "important" and "|cffffb347" or "|cff82c5ff"

        group:AddText({
            text = color .. lib._highlightEmphasisLabels[emphasis] .. "|r",
            fontObject = GameFontNormalSmall,
        }, { marginBottom = 4 })
    end

    group:AddText({
        text = highlight.title,
        fontObject = GameFontNormalLarge,
    }, { marginBottom = 8 })

    local descriptionFlow, controlsFlow = group, group
    local columns

    if highlight.controls and #highlight.controls > 0 then
        columns = group:BeginColumns()
        descriptionFlow, controlsFlow = columns.left, columns.right
    end

    if highlight.artwork then
        local artwork = highlight.artwork
        local frame = descriptionFlow:AddCustom(
            artwork.height or 120,
            { marginBottom = 8 }
        )
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()

        if artwork.atlas then
            texture:SetAtlas(artwork.atlas)
        else
            texture:SetTexture(artwork.texture)
        end
    end

    if highlight.body then
        descriptionFlow:AddText(
            { text = highlight.body },
            { marginBottom = 12 }
        )
    end

    for _, definition in ipairs(highlight.controls or {}) do
        lib:_AddBoundControl(self, controlsFlow, definition)
    end

    if columns then columns:Finish() end

    group:Finish({ marginBottom = 14 })
end

local function watchUserScrolling(view)
    local scrollBox = view.layout:GetScrollBox()
    local scrollBar = view.layout:GetScrollBar()

    -- Observe actual gestures, not OnScroll: reflow, Tab navigation and initial
    -- placement also change scroll percentage without the user reading notes.
    scrollBox:HookScript("OnMouseWheel", function(_, delta)
        if delta ~= 0 and scrollBox:GetDerivedScrollRange() > 0 then
            view:Interact()
        end
    end)

    local function onMouseDown(_, button)
        if button == "LeftButton" and scrollBox:GetDerivedScrollRange() > 0 then
            view:Interact()
        end
    end

    scrollBar.Back:HookScript("OnMouseDown", onMouseDown)
    scrollBar.Forward:HookScript("OnMouseDown", onMouseDown)
    scrollBar.Track:HookScript("OnMouseDown", onMouseDown)
    scrollBar.Track.Thumb:HookScript("OnMouseDown", onMouseDown)
end

function lib:_CreateView(entry, parent, options)
    local settings = self:_GetSettingsLibrary()
    local frame = CreateFrame("Frame", nil, parent)
    frame:Hide()

    local view = setmetatable({
        entry = entry,
        controller = entry.controller,
        frame = frame,
        bindings = {},
        popup = options.popup,
    }, View)

    local ok, failure = pcall(function()
        view:_CreateLayout(settings, options)
        view:_CreateHeader()
        view.messages = settings:CreateFlashMessages(frame)

        local flow = view.layout:GetRootFlow()
        view.contextGroup = flow:BeginGroup()
        view.contextGroup:Finish()
        view.contextGroup:SetShown(false)

        local highlights = entry.release.highlights or {}

        if entry.release.title then
            flow:AddText({
                text = entry.release.title,
                fontObject = GameFontNormalHuge,
            })
        end

        if #highlights == 0 then
            flow:AddText({
                text = "This update is installed. Expand the full changelog below to see what changed.",
            })
        end

        for _, highlight in ipairs(highlights) do
            view:_AddHighlight(flow, highlight)
        end

        local notesGroup
        view.notesHeader = flow:AddControl("expandableHeader", {
            text = "Full changelog",
            expanded = false,
            onExpandedChanged = function(_, expanded)
                view:Interact()
                notesGroup:SetShown(expanded)
            end,
        }, { marginTop = 12, marginBottom = 8 })
        notesGroup = flow:BeginGroup()
        addNotes(notesGroup, entry.release.notes)
        notesGroup:Finish()
        notesGroup:SetShown(false)
        view.notesGroup = notesGroup

        view.layout:Finalize()
        settings:EnableTabNavigation(frame)
        watchUserScrolling(view)
        view:Refresh()

        frame:HookScript("OnShow", function()
            view:Refresh()
        end)
        frame:HookScript("OnHide", function()
            view:CancelDrafts()
        end)
    end)

    if not ok then
        frame:Hide()
        entry.failed = true
        self._sessionFailures[entry.controller.addonName] =
            entry.release.version
        geterrorhandler()(failure)
        return nil, failure
    end

    entry.controller.views[#entry.controller.views + 1] = view
    return view
end

function lib:_CreateSettingsPage(controller, options)
    local entry = controller:_CreateEntry()
    local view, failure = self:_CreateView(entry, options.parent, options)
    assert(view, failure)

    local frame = view.frame
    frame.layout = view.layout

    frame.Sync = function()
        controller:Refresh()
    end

    frame.OnRefresh = frame.Sync

    return frame
end
