return function(lib)
    local owner, label = "one", "First profile"
    local changed, cancelled, requested = {}, 0, 0
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
        contextText = { SetText = function(_, text) stored.label = text end },
        autoShow = { SetValue = function(_, value) stored.autoShow = value end },
        layout = { RequestLayout = function() requested = requested + 1 end },
        messages = { Show = function() end },
    }, lib._viewPrototype)

    view:Refresh()
    assert(changed[1] == true and stored.label == "First profile" and stored.autoShow)
    view:Refresh()
    assert(changed[2] == false, "same-owner refresh preserves drafts")
    owner, label = "two", "Second profile"
    view:Refresh()
    assert(changed[3] == true and stored.label == "Second profile", "profile ownership change reaches every binding")
    assert(requested == 3, "refresh uses retained layout rather than reconstructing controls")

    view.bindings[1].Refresh = function() error("expected failed getter") end
    view:Refresh()
    assert(view.entry.failed and cancelled == 1)
    assert(lib._sessionFailures.ViewExample == "view-example", "failed refresh cannot trigger popup retries")
end
