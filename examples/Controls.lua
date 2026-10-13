-- Optional in-game development example. Load after embed.xml from a temporary
-- addon/TOC entry, never from the shipped embed. No live settings are changed.
local library = LibStub("LibChangelog-1.0")
local notifications = {}
local owner = 1
local values = {
    enabled = true,
    size = 40,
    position = "top",
    name = "Example",
    color = { r = 0.2, g = 0.6, b = 1, a = 1, mode = "custom" },
}
local controller

local function binding(controlType, key, options)
    return {
        type = controlType,
        getValue = function() return values[key] end,
        options = options,
    }
end

controller = library:Register("LibChangelogControlsExample", {
    displayName = "Changelog Controls Example",
    storage = {
        get = function(key) return notifications[key] end,
        set = function(key, value) notifications[key] = value end,
    },
    context = function() return owner, "Temporary example settings — no addon settings are changed" end,
    release = {
        version = "example-1",
        title = "Try each control",
        highlights = {
            {
                title = "LMS controls",
                emphasis = "featured",
                body = "Try Tab, Shift-Tab and Escape; expand the notes or interact to clear this addon’s NEW badge.",
                controls = {
                    binding("checkbox", "enabled", {
                        label = "Enabled",
                        onChanged = function(value) values.enabled = value end,
                    }),
                    binding("slider", "size", {
                        label = "Size (typed values may exceed the track)",
                        minValue = 20, maxValue = 60, step = 1,
                        onChanged = function(value) values.size = value end,
                    }),
                    binding("dropdown", "position", {
                        label = "Position",
                        choices = { { value = "top", label = "Top" }, { value = "bottom", label = "Bottom" } },
                        onChanged = function(value) values.position = value end,
                    }),
                    binding("textInput", "name", {
                        label = "Name (cannot be empty)",
                        onCommit = function(text)
                            if text:match("^%s*$") then return false, "Enter a name" end
                            values.name = text
                            return text
                        end,
                    }),
                    binding("color", "color", {
                        label = "Color",
                        hasOpacity = true,
                        classColor = true,
                        onChanged = function(value) values.color = value end,
                    }),
                    {
                        type = "button",
                        successMessage = "Example owner changed",
                        options = {
                            text = "Change the example's setting owner",
                            onClick = function()
                                owner = owner + 1
                                values.name = "Example " .. owner
                                controller:Refresh()
                            end,
                        },
                    },
                },
            },
        },
        notes = {
            { kind = "heading", text = "Example notes" },
            { kind = "bullet", text = "Controls are supplied by LMS; their validation and keyboard behavior remain intact." },
            { kind = "bullet", text = "Dismiss all closes the complete batch, not just the selected addon." },
        },
    },
})

local otherNotifications = {}
library:Register("LibChangelogOtherExample", {
    displayName = "Second Example Addon",
    storage = {
        get = function(key) return otherNotifications[key] end,
        set = function(key, value) otherNotifications[key] = value end,
    },
    release = {
        version = "example-2",
        title = "An update without highlights",
        notes = { { kind = "bullet", text = "The sidebar must make this second addon visible even before you select it." } },
    },
})
