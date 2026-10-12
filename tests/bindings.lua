return function(lib, setFocus, errors)
    local function pack(...) return { n = select("#", ...), ... } end
    local Binding = lib._bindingPrototype
    local owner = "first"
    local interacted, queued, cancelled = 0, 0, 0
    local view = {
        context = owner,
        entry = {},
        controller = { _GetContext = function() return owner end },
        Interact = function() interacted = interacted + 1 end,
        Refresh = function(self) self.context = owner end,
        QueueRefresh = function() queued = queued + 1 end,
        messages = { Show = function() end },
    }

    local passed = {}
    local binding = setmetatable({
        definition = { type = "textInput", options = {} },
        view = view,
        callback = function(...)
            passed = pack(...)
            return nil, "validation-error", nil, 4
        end,
    }, Binding)
    local result = pack(binding:Invoke("draft", nil, "context"))
    assert(passed.n == 3 and passed[3] == "context")
    assert(result.n == 4 and result[1] == nil and result[2] == "validation-error" and result[4] == 4)
    assert(interacted == 1 and queued == 1, "callback arity and nil returns are preserved")

    owner = "second"
    assert(binding:Invoke("old draft") == false and interacted == 1,
        "stale owner cannot commit to the new profile")
    binding.definition.enabled = function() return false, "disabled" end
    assert(select(2, binding:Invoke("blocked")) == "disabled")
    binding.definition.enabled = nil
    binding.callback = function() error("expected callback failure") end
    assert(binding:Invoke() == false and #errors == 1, "action errors are reported, not propagated into LMS")

    local value, sets = 0, 0
    binding.control = {
        GetValue = function() return value end,
        SetValue = function(_, nextValue)
            value = nextValue
            sets = sets + 1
        end,
        CancelAndClearFocus = function() cancelled = cancelled + 1 end,
    }
    binding.frame = { SetControlEnabled = function() end }
    binding.definition.getValue = function() return 900 end
    binding.definition.type = "textInput"
    setFocus(binding.control)
    binding:Refresh(false)
    assert(sets == 0, "ordinary refresh leaves the focused draft alone")
    binding:Refresh(true)
    assert(cancelled == 1 and value == 900, "owner replacement cancels before syncing new values")
    setFocus(nil)

    binding.definition.type = "slider"
    binding.control.valueBox = { ClearFocus = function() end }
    binding:Refresh(true)
    assert(value == 900, "library does not clamp slider values to a display range")

    local savedColor = { r = 1, g = 0, b = 0, a = 0.5, mode = "class", custom = { r = 0.2 } }
    binding.definition.type = "color"
    binding.control.ClosePicker = function() cancelled = cancelled + 1 end
    binding.definition.getValue = function() return savedColor end
    binding:Refresh(true)
    assert(value == savedColor and value.custom.r == 0.2, "color mode and custom value stay intact")
    local oldSets = sets
    binding:Refresh(false)
    assert(sets == oldSets, "unchanged colors do not close picker drafts")

    for controlType, callbackName in pairs(lib._controlCallbacks) do
        binding.definition.type = controlType
        binding.callback = function(first, second) return first, second end
        local output = pack(binding:Invoke("value", "extra"))
        assert(output.n == 2 and output[1] == "value" and output[2] == "extra", callbackName)
    end
end
