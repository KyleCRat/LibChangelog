return function(lib)
    local originalAddControl = lib._AddBoundControl
    local originalLarge, originalHuge, originalSmall = GameFontNormalLarge, GameFontNormalHuge, GameFontNormalSmall
    GameFontNormalLarge, GameFontNormalHuge, GameFontNormalSmall = "large", "huge", "small"

    -- Record which LMS flow receives each piece of a real highlight. LMS owns
    -- column widths and advancing the parent past the taller column.
    local function createFlow()
        local flow = { texts = {}, controls = {} }

        function flow:BeginGroup()
            self.group = createFlow()
            return self.group
        end

        function flow:AddText(options)
            self.texts[#self.texts + 1] = options
        end

        function flow:BeginColumns()
            self.columns = {
                left = createFlow(),
                right = createFlow(),
                Finish = function(columns) columns.finished = true end,
            }
            return self.columns
        end

        function flow:AddCustom(height)
            local texture = {
                SetAllPoints = function() end,
                SetAtlas = function(self, atlas) self.atlas = atlas end,
                SetTexture = function(self, path) self.path = path end,
            }
            self.artwork = { height = height, texture = texture }
            return { CreateTexture = function() return texture end }
        end

        function flow:Finish()
            assert(not self.columns or self.columns.finished, "finish the columns before the entry")
            self.finished = true
        end

        return flow
    end

    local view = setmetatable({}, lib._viewPrototype)
    lib._AddBoundControl = function(_, owner, flow, definition)
        assert(owner == view, "controls retain the view that owns their bindings")
        flow.controls[#flow.controls + 1] = definition
    end

    local controls = { { type = "checkbox" }, { type = "button" } }

    for _, example in ipairs({
        { title = "Ordinary" },
        { title = "Featured", emphasis = "featured", label = "|cff82c5ffFEATURED|r" },
        { title = "Important", emphasis = "important", label = "|cffffb347IMPORTANT|r" },
        { title = "Requested", emphasis = "requested", label = "|cff82c5ffUSER REQUESTED|r" },
    }) do
        local root = createFlow()
        view:_AddHighlight(root, {
            title = example.title,
            emphasis = example.emphasis,
            body = "Description",
            artwork = { atlas = "example", height = 80 },
            controls = controls,
        })

        local group = root.group
        local title = group.texts[#group.texts]
        assert(title.text == example.title and title.fontObject == GameFontNormalLarge,
            "all highlight titles have the same size regardless of emphasis")
        assert(#group.texts == (example.emphasis and 2 or 1),
            "only the tag is added above an emphasized title")

        if example.emphasis then
            assert(group.texts[1].text == example.label and group.texts[1].fontObject == GameFontNormalSmall,
                "the emphasis stays a small tag")
        end

        local columns = group.columns
        assert(columns.left.texts[1].text == "Description" and #columns.left.controls == 0,
            "the description belongs in the left column")
        assert(columns.left.artwork.height == 80 and columns.left.artwork.texture.atlas == "example",
            "artwork stays with the description")
        assert(columns.right.controls[1] == controls[1] and columns.right.controls[2] == controls[2]
            and #columns.right.texts == 0, "all controls keep their order in the right column")
        assert(columns.finished and group.finished, "the next highlight follows both columns")
    end

    for _, controlList in ipairs({ false, {} }) do
        local root = createFlow()
        view:_AddHighlight(root, {
            title = "Notes only",
            body = "Full-width description",
            artwork = { texture = "example.tga" },
            controls = controlList or nil,
        })
        assert(not root.group.columns and root.group.texts[2].text == "Full-width description",
            "absent and empty control lists do not reserve an empty right column")
        assert(root.group.artwork.texture.path == "example.tga", "full-width texture artwork remains supported")
    end

    local root = createFlow()
    view:_AddHighlight(root, { title = "Action only", controls = controls })
    assert(root.group.columns.right.controls[1] == controls[1],
        "controls remain on the right when the optional description is omitted")

    lib._AddBoundControl = originalAddControl
    GameFontNormalLarge, GameFontNormalHuge, GameFontNormalSmall = originalLarge, originalHuge, originalSmall
end
