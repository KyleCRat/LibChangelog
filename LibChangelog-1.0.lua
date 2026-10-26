local MAJOR, MINOR = "LibChangelog-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

lib._implementationMinor = MINOR
lib._loadedModules = lib._loadedModules or {}
lib._controllers = lib._controllers or {}
lib._controllerPrototype = lib._controllerPrototype or {}
lib._sessionFailures = lib._sessionFailures or {}

local Controller = lib._controllerPrototype
Controller.__index = Controller

function lib:_BeginModule(name, minor)
    if self._loadedModules[name] == minor then return false end

    self._loadedModules[name] = minor
    return true
end

function lib:_GetSettingsLibrary()
    local settings, minor = LibStub("LibModernSettings-1.0", true)
    assert(
        settings and minor >= 11,
        "LibChangelog requires LibModernSettings 1.10.0 or newer"
    )

    return settings
end

local CONTROL_CALLBACKS = {
    button = "onClick",
    checkbox = "onChanged",
    slider = "onChanged",
    dropdown = "onChanged",
    textInput = "onCommit",
    color = "onChanged",
}
lib._controlCallbacks = CONTROL_CALLBACKS

-- Registration and rendering use the same supported emphasis labels.
lib._highlightEmphasisLabels = {
    featured = "FEATURED",
    important = "IMPORTANT",
    requested = "USER REQUESTED",
}

local function validateRelease(release)
    assert(type(release) == "table", "release must be a table")
    assert(
        type(release.version) == "string" and release.version ~= "",
        "release.version is required"
    )
    assert(
        type(release.notes) == "table",
        "release.notes must be an ordered list of text blocks"
    )

    for _, block in ipairs(release.notes) do
        assert(
            block.kind == "heading"
                or block.kind == "paragraph"
                or block.kind == "bullet"
                or block.kind == "code",
            "unsupported note block"
        )
        assert(type(block.text) == "string", "note text must be a string")
    end

    for _, highlight in ipairs(release.highlights or {}) do
        assert(type(highlight.title) == "string", "highlight.title is required")
        assert(
            highlight.emphasis == nil
                or lib._highlightEmphasisLabels[highlight.emphasis] ~= nil,
            "unsupported highlight emphasis"
        )

        for _, control in ipairs(highlight.controls or {}) do
            local callback = CONTROL_CALLBACKS[control.type]
            assert(callback, "unsupported highlight control type")
            assert(
                type(control.options) == "table",
                "control.options is required"
            )
            assert(
                type(control.options[callback]) == "function",
                "control callback is required"
            )
            assert(
                control.type == "button" or type(control.getValue) == "function",
                "value controls require getValue"
            )
            assert(
                not control.dismissBatch or control.type == "button",
                "only navigation buttons may dismiss the batch"
            )
        end
    end
end

-- Notification storage belongs to the consumer, outside its settings profiles.
-- Versions are opaque identities, not ordered numbers. Displaying a page never
-- writes acknowledgement; only explicit interaction or batch dismissal does.
function lib:Register(addonName, options)
    assert(
        type(addonName) == "string" and addonName ~= "",
        "addonName is required"
    )
    assert(type(options) == "table", "options are required")
    assert(type(options.displayName) == "string", "displayName is required")
    assert(
        type(options.storage) == "table"
            and type(options.storage.get) == "function"
            and type(options.storage.set) == "function",
        "storage requires get and set functions"
    )
    validateRelease(options.release)
    self:_GetSettingsLibrary()

    local controller = self._controllers[addonName]

    if not controller then
        controller = setmetatable({
            addonName = addonName,
            views = {},
        }, Controller)
        self._controllers[addonName] = controller
    end

    controller.options = options
    self:_Schedule()

    return controller
end

function Controller:GetAutoShowEnabled()
    return self.options.storage.get("autoShow") ~= false
end

function Controller:SetAutoShowEnabled(enabled)
    assert(type(enabled) == "boolean", "enabled must be a boolean")

    if enabled == self:GetAutoShowEnabled() then return end

    if enabled and not self.options.release.unreleased then
        self.options.storage.set(
            "acknowledgedVersion",
            self.options.release.version
        )
    end

    self.options.storage.set("autoShow", enabled)
    self:Refresh()
    lib:_Schedule()
end

function Controller:_CreateEntry()
    return {
        controller = self,
        release = self.options.release,
        displayName = self.options.displayName,
    }
end

function lib:_IsNew(entry)
    return not entry.release.unreleased
        and entry.controller.options.storage.get("acknowledgedVersion")
            ~= entry.release.version
end

function lib:_Acknowledge(entry)
    if entry.failed or entry.release.unreleased then return end

    entry.controller.options.storage.set(
        "acknowledgedVersion",
        entry.release.version
    )
    self:_UpdateBadges()
end

function lib:_CollectAll()
    local entries = {}

    for _, controller in pairs(self._controllers) do
        entries[#entries + 1] = controller:_CreateEntry()
    end

    table.sort(entries, function(left, right)
        local leftName, rightName =
            left.displayName:lower(), right.displayName:lower()

        if leftName == rightName then
            return left.controller.addonName < right.controller.addonName
        end

        return leftName < rightName
    end)

    return entries
end

function lib:_CollectPending()
    local entries = {}

    for _, entry in ipairs(self:_CollectAll()) do
        local controller = entry.controller

        if
            controller:GetAutoShowEnabled()
            and self:_IsNew(entry)
            and self._sessionFailures[controller.addonName]
                ~= entry.release.version
        then
            entries[#entries + 1] = entry
        end
    end

    return entries
end

function Controller:_GetContext()
    if self.options.context then return self.options.context() end
end

function Controller:Refresh()
    for _, view in ipairs(self.views) do
        view:Refresh()
    end

    lib:_UpdateBadges()
end

function Controller:Show()
    return lib:_ShowManual(self)
end

function Controller:CreateSettingsPage(options)
    return lib:_CreateSettingsPage(self, options or {})
end
