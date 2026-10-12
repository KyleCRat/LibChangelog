local MAJOR, MINOR = "LibChangelog-1.0", 1
local lib = LibStub(MAJOR, true)

if not lib or lib._implementationMinor ~= MINOR
    or not lib:_BeginModule("View", MINOR) then return end

lib._viewPrototype = lib._viewPrototype or {}
local View = lib._viewPrototype
View.__index = View

function View:Interact()
    lib:_Acknowledge(self.entry)
end

function View:ResetNavigation()
    self.notesHeader:SetExpanded(false)
    self.notesGroup:SetShown(false)
    self.layout:GetScrollBox():ScrollToBegin(ScrollBoxConstants.NoScrollInterpolation)
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

    self.context = context
    self.contextText:SetText(label or "")
    self.autoShow:SetValue(self.controller:GetAutoShowEnabled())

    for _, binding in ipairs(self.bindings) do
        binding:Refresh(changed)
    end

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
        lib._sessionFailures[self.controller.addonName] = self.entry.release.version
        self:CancelDrafts()
        self.messages:Show("These update controls could not be refreshed", "error")
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

local function addHighlight(view, flow, highlight)
    local group = flow:BeginGroup({ marginTop = 8 })
    local emphasis = highlight.emphasis

    if emphasis then
        group:AddText({
            text = emphasis == "important" and "|cffffb347IMPORTANT|r" or "|cff82c5ffFEATURED|r",
            fontObject = GameFontNormalSmall,
        }, { marginBottom = 4 })
    end

    group:AddText({
        text = highlight.title,
        fontObject = emphasis and GameFontNormalHuge or GameFontNormalLarge,
    }, { marginBottom = 8 })

    if highlight.artwork then
        local artwork = highlight.artwork
        local frame = group:AddCustom(artwork.height or 120, { marginBottom = 8 })
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()

        if artwork.atlas then
            texture:SetAtlas(artwork.atlas)
        else
            texture:SetTexture(artwork.texture)
        end
    end

    if highlight.body then
        group:AddText({ text = highlight.body }, { marginBottom = 12 })
    end

    for _, definition in ipairs(highlight.controls or {}) do
        lib:_AddBoundControl(view, group, definition)
    end

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
        view.layout = settings:CreateCanvasLayout(frame, {
            width = options.width,
            height = options.height,
            measurementFrame = options.measurementFrame,
            scrollable = true,
            viewportMarginTop = 86,
        })
        view.messages = settings:CreateFlashMessages(frame)
        local title = entry.displayName .. " — " .. entry.release.version
        if entry.release.date then title = title .. "  |  " .. entry.release.date end

        local heading = settings:CreateText(frame, {
            text = title,
            width = view.layout:GetContentWidth(),
            fontObject = GameFontNormalLarge,
        })
        heading:SetPoint("TOPLEFT", 8, -4)

        view.autoShow = settings:CreateCheckbox(frame, {
            label = "Show updates automatically for " .. entry.displayName,
            width = view.layout:GetContentWidth(),
            value = entry.controller:GetAutoShowEnabled(),
            onChanged = function(checked)
                view:Interact()
                entry.controller:SetAutoShowEnabled(checked)
            end,
        })
        view.autoShow:SetPoint("TOPLEFT", 8, -30)
        view.contextText = settings:CreateText(frame, {
            text = "",
            width = view.layout:GetContentWidth(),
            fontObject = GameFontHighlightSmall,
        })
        view.contextText:SetPoint("TOPLEFT", 8, -60)

        local flow = view.layout:GetRootFlow()
        local highlights = entry.release.highlights or {}

        if entry.release.title then
            flow:AddText({ text = entry.release.title, fontObject = GameFontNormalHuge })
        end

        if #highlights == 0 then
            flow:AddText({ text = "This update is installed. Expand the full changelog below to see what changed." })
        end

        for _, highlight in ipairs(highlights) do
            addHighlight(view, flow, highlight)
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

        frame:HookScript("OnShow", function() view:Refresh() end)
        frame:HookScript("OnHide", function() view:CancelDrafts() end)
    end)

    if not ok then
        frame:Hide()
        entry.failed = true
        self._sessionFailures[entry.controller.addonName] = entry.release.version
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
    frame.Sync = function() controller:Refresh() end
    frame.OnRefresh = frame.Sync

    return frame
end
