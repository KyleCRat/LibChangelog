local MAJOR, MINOR = "LibChangelog-1.0", 1
local lib = LibStub(MAJOR, true)

if
    not lib
    or lib._implementationMinor ~= MINOR
    or not lib:_BeginModule("Bindings", MINOR)
then
    return
end

lib._bindingPrototype = lib._bindingPrototype or {}
local Binding = lib._bindingPrototype
Binding.__index = Binding

local function pack(...)
    -- Preserve nil positions in callback argument tuples.
    -- selene: allow(mixed_table)
    return { n = select("#", ...), ... }
end

local function sameValue(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return left == right
    end

    for key, value in pairs(left) do
        if not sameValue(value, right[key]) then return false end
    end

    for key in pairs(right) do
        if left[key] == nil then return false end
    end

    return true
end

function Binding:GetEnabled()
    if InCombatLockdown() then return false, "Available after combat" end

    if self.definition.enabled then return self.definition.enabled() end

    return self.definition.options.enabled ~= false,
        self.definition.options.disabledTooltip
end

function Binding:CancelDraft()
    local control = self.control
    local controlType = self.definition.type

    if controlType == "textInput" then
        control:CancelAndClearFocus()
    elseif controlType == "slider" then
        -- SetValue cancels LMS's deferred commit. Do this after ClearFocus too,
        -- so an old profile's draft can never be written into the new profile.
        local value = control:GetValue()
        control:SetValue(value)
        control.valueBox:ClearFocus()
        control:SetValue(value)
    elseif controlType == "color" then
        control:ClosePicker()
    elseif controlType == "dropdown" then
        control.dropdown:CloseMenu()
    end
end

function Binding:Refresh(ownerChanged)
    local enabled, reason = self:GetEnabled()

    if ownerChanged or not enabled then self:CancelDraft() end

    self.frame:SetControlEnabled(enabled, reason)

    if not self.definition.getValue then return end

    local focused = GetCurrentKeyBoardFocus()

    if
        not ownerChanged
        and focused
        and (focused == self.control or focused == self.control.valueBox)
    then
        return
    end

    local value = self.definition.getValue()

    if ownerChanged or not sameValue(value, self.control:GetValue()) then
        self.control:SetValue(value)
    end
end

function Binding:Invoke(...)
    local view = self.view

    if view.entry.failed then
        return false, "These update controls could not be refreshed"
    end

    local context = view.controller:_GetContext()

    if context ~= view.context then
        view:Refresh()
        return false, "The active profile changed; try again"
    end

    local enabled, reason = self:GetEnabled()

    if not enabled then return false, reason end

    view:Interact()

    if self.definition.dismissBatch and view.popup then lib:_DismissBatch() end

    view.invoking = true
    local result = pack(pcall(self.callback, ...))
    view.invoking = false

    if not result[1] then
        view.messages:Show("This action could not be completed", "error")
        geterrorhandler()(result[2])
        view:QueueRefresh()
        return false, "This action could not be completed"
    end

    if self.definition.successMessage and result[2] ~= false then
        view.messages:Show(self.definition.successMessage, "success")
    end

    -- Run after LMS has accepted a text commit or completed a click. Preserve
    -- every callback return, including nils and validation error messages.
    view:QueueRefresh()
    return unpack(result, 2, result.n)
end

local function watchInteraction(view, frame)
    frame:HookScript("OnMouseDown", function()
        view:Interact()
    end)

    if frame:IsObjectType("EditBox") then
        frame:HookScript("OnChar", function()
            view:Interact()
        end)
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        watchInteraction(view, child)
    end
end

function lib:_AddBoundControl(view, flow, definition)
    local options = {}

    for key, value in pairs(definition.options) do
        options[key] = value
    end

    local callbackName = self._controlCallbacks[definition.type]
    local binding = setmetatable({
        view = view,
        definition = definition,
        callback = options[callbackName],
    }, Binding)

    options[callbackName] = function(...)
        return binding:Invoke(...)
    end

    if definition.getValue then options.value = definition.getValue() end

    if
        definition.type == "slider"
        or definition.type == "dropdown"
        or definition.type == "textInput"
    then
        local label = options.label
        options.label = nil
        binding.frame = flow:AddControl("field", {
            label = label or "",
            description = definition.description,
            controlType = definition.type,
            controlOptions = options,
        }, { marginBottom = 10 })
        binding.control = binding.frame:GetControl()
    else
        binding.frame =
            flow:AddControl(definition.type, options, { marginBottom = 10 })
        binding.control = binding.frame
    end

    view.bindings[#view.bindings + 1] = binding
    binding:Refresh(false)
    watchInteraction(view, binding.frame)

    return binding.control
end
