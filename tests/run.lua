-- Library-only tests, run from this library's directory with Lua 5.1.
-- Supply a real LibStub path when running outside an addon checkout.
strmatch = string.match
dofile(arg[1] or "../LibStub/LibStub.lua")
LibStub:NewLibrary("LibModernSettings-1.0", 11)

local timers, frames, errors = {}, {}, {}
local combat, focus = false, nil

function IsLoggedIn()
    return true
end

function InCombatLockdown()
    return combat
end

function GetCurrentKeyBoardFocus()
    return focus
end

function geterrorhandler()
    return function(message)
        errors[#errors + 1] = message
    end
end

C_Timer = {
    NewTimer = function(_, callback)
        local timer = { callback = callback }

        function timer:Cancel()
            self.cancelled = true
        end

        timers[#timers + 1] = timer
        return timer
    end,
}

local function drainTimers()
    local pending = timers
    timers = {}

    for _, timer in ipairs(pending) do
        if not timer.cancelled then timer.callback() end
    end
end

function CreateFrame()
    local frame = {
        events = {},
        scripts = {},
        shown = true,
    }

    function frame:RegisterEvent(event)
        self.events[event] = true
    end

    function frame:SetScript(event, callback)
        self.scripts[event] = callback
    end

    function frame:HookScript(event, callback)
        self.scripts[event] = callback
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    frames[#frames + 1] = frame
    return frame
end

UIParent = CreateFrame()
SlashCmdList = {}

local files = {
    "LibChangelog-1.0.lua",
    "Bindings.lua",
    "View.lua",
    "Window.lua",
    "Coordinator.lua",
}

local function loadLibrary(minor)
    for _, path in ipairs(files) do
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()

        if minor then
            source = source:gsub(
                '"LibChangelog%-1%.0", %d+',
                '"LibChangelog-1.0", ' .. minor
            )
        end

        assert(loadstring(source, "@" .. path))()
    end
end

loadLibrary()
local lib = LibStub("LibChangelog-1.0")
local releaseMinor = lib._implementationMinor

local function check(condition, message)
    assert(condition, message)
end

local function register(name, version, storage, unreleased)
    storage = storage or {}
    local controller = lib:Register(name, {
        displayName = name,
        release = {
            version = version,
            unreleased = unreleased,
            notes = {},
        },
        storage = {
            get = function(key)
                return storage[key]
            end,
            set = function(key, value)
                storage[key] = value
            end,
        },
    })
    return controller, storage
end

local alpha, alphaStore = register("Alpha", "release-z")
local beta, betaStore = register("Beta", "a-1")
local preview, previewStore = register("Preview", "Unreleased", nil, true)
local pending = lib:_CollectPending()
check(
    #pending == 2 and pending[1].controller == alpha,
    "alphabetical collection excludes Unreleased"
)
check(
    alphaStore.acknowledgedVersion == nil,
    "collection is not acknowledgement"
)
check(alpha:GetAutoShowEnabled(), "new installs notify by default")

lib:_Acknowledge(pending[1])
check(
    alphaStore.acknowledgedVersion == "release-z",
    "interaction persists immediately"
)
check(#lib:_CollectPending() == 1, "only interacted release is acknowledged")
beta:SetAutoShowEnabled(false)
check(#lib:_CollectPending() == 0, "opt-out excludes future collection")
beta:SetAutoShowEnabled(true)
check(
    betaStore.acknowledgedVersion == "a-1",
    "re-enable baselines the installed release"
)
beta = register("Beta", "0-older-looking", betaStore)
check(#lib:_CollectPending() == 1, "version identities are opaque")

local failed = beta:_CreateEntry()
failed.failed = true
lib:_Acknowledge(failed)
check(
    betaStore.acknowledgedVersion == "a-1",
    "failed rendering is not acknowledged"
)
lib._sessionFailures.Beta = failed.release.version
check(
    #lib:_CollectPending() == 0,
    "failed notices are not reopened in an automatic retry loop"
)
lib._sessionFailures.Beta = nil
lib:_Acknowledge(preview:_CreateEntry())
check(
    previewStore.acknowledgedVersion == nil,
    "preview leaves released acknowledgement untouched"
)

-- Exercise the actual selection and dismissal paths with a passive view, not
-- a recreation of Blizzard templates. Native hit testing is checked in game.
lib._window = {
    frame = CreateFrame(),
    rows = {},
    errorText = {
        SetShown = function() end,
    },
}
local entry = beta:_CreateEntry()
entry.view = {
    frame = CreateFrame(),
    Refresh = function() end,
    CancelDrafts = function() end,
}
lib._batch = { entries = { entry } }
lib:_SelectEntry(1, false)
check(
    betaStore.acknowledgedVersion == "a-1",
    "auto-selected first addon remains NEW"
)
lib:_SelectEntry(1, true)
check(
    betaStore.acknowledgedVersion == "0-older-looking",
    "selecting the preview acknowledges it"
)

local gamma, gammaStore = register("Gamma", "1")
local delta, deltaStore = register("Delta", "1")
lib._batch = { entries = { gamma:_CreateEntry(), delta:_CreateEntry() } }
lib:_Suspend()
check(
    gammaStore.acknowledgedVersion == nil
        and deltaStore.acknowledgedVersion == nil,
    "automatic interruption preserves unread releases"
)
lib:_DismissBatch()
check(
    gammaStore.acknowledgedVersion == "1"
        and deltaStore.acknowledgedVersion == "1",
    "closing dismisses unread entries too"
)

dofile("tests/window.lua")(lib)

-- Coordinator: actual event/timer paths, one coordinator across embed copies.
local eventFrame = lib._eventFrame

local function event(name)
    eventFrame.scripts.OnEvent(eventFrame, name)
end

local prepared, revealed = 0, 0

lib._PrepareBatch = function(self, entries, manual)
    prepared = prepared + 1
    self._batch = { entries = entries, manual = manual }
end

lib._RevealBatch = function(self)
    revealed = revealed + 1
    self._window.frame:Show()
end

local epsilon, epsilonStore = register("Epsilon", "2")
combat = true
event("PLAYER_REGEN_DISABLED")
drainTimers()
check(prepared == 0, "combat cancels startup work")
combat = false
event("PLAYER_REGEN_ENABLED")
event("LOADING_SCREEN_ENABLED")
drainTimers()
check(prepared == 0, "loading cancels pending work")
event("LOADING_SCREEN_DISABLED")
event("READY_CHECK")
drainTimers()
check(prepared == 0, "ready checks take priority")
event("READY_CHECK_FINISHED")
drainTimers()
check(prepared == 1 and revealed == 1, "one batch opens after the safe delay")
local frozen = lib._batch
register("Late", "3")
check(
    lib._batch == frozen,
    "late registration does not replace the active batch"
)
event("CINEMATIC_START")
check(not lib._window.frame:IsShown(), "cinematic hides the window")
check(epsilonStore.acknowledgedVersion == nil, "cinematic does not acknowledge")
event("CINEMATIC_STOP")
drainTimers()
check(
    prepared == 1 and revealed == 2 and lib._batch == frozen,
    "resume retains the same batch"
)
check(
    epsilon:Show() == true,
    "manual Show uses an entry already in the active batch"
)
check(
    select(2, preview:Show()) == "batch-open",
    "manual Show does not replace another active batch"
)
combat = true
check(select(2, preview:Show()) == "not-safe", "manual Show respects combat")
combat = false

dofile("tests/commands.lua")(lib, register, function(value)
    combat = value
end, event, drainTimers)

-- Public delegation and live prototypes.
lib._CreateSettingsPage = function(_, controller, options)
    return { controller = controller, options = options }
end

check(
    alpha:CreateSettingsPage().controller == alpha,
    "settings page uses its controller"
)
local refreshed = 0
alpha.views[1] = {
    Refresh = function()
        refreshed = refreshed + 1
    end,
}
alpha:Refresh()
check(refreshed == 1, "Refresh updates retained views")
alpha.views = {}

dofile("tests/bindings.lua")(lib, function(value)
    focus = value
end, errors)
dofile("tests/views.lua")(lib)
dofile("tests/highlights.lua")(lib)
dofile("tests/generator.lua")

local frameCount = #frames
local prototype = getmetatable(alpha)
local slashHandler = SlashCmdList.LIBCHANGELOG
loadLibrary()
check(
    #frames == frameCount and lib._eventFrame == eventFrame,
    "same-MINOR embeds install nothing twice"
)
check(
    SlashCmdList.LIBCHANGELOG == slashHandler,
    "same-MINOR embeds do not replace the command"
)
local newerMinor = releaseMinor + 1
loadLibrary(newerMinor)
check(
    LibStub("LibChangelog-1.0") == lib and getmetatable(alpha) == prototype,
    "newer embed preserves library, controllers and prototypes"
)
check(
    lib._controllers.Alpha == alpha and #frames == frameCount,
    "upgrade keeps registrations and event frame"
)
local upgradedRefresh = alpha.Refresh
local upgradedShowAll = lib.ShowAll
local upgradedSlashHandler = SlashCmdList.LIBCHANGELOG
check(
    upgradedSlashHandler ~= slashHandler,
    "newer embed upgrades the shared command"
)
loadLibrary(releaseMinor)
loadLibrary(1)
check(
    alpha.Refresh == upgradedRefresh and lib._implementationMinor == newerMinor,
    "older-first/newer-first files cannot overwrite selected methods"
)
check(
    lib.ShowAll == upgradedShowAll
        and SlashCmdList.LIBCHANGELOG == upgradedSlashHandler,
    "older embeds cannot overwrite the global command or public ShowAll"
)
local otherFamily = LibStub:NewLibrary("LibChangelog-2.0", 1)
check(otherFamily ~= lib, "independent API families coexist")

local ok = pcall(function()
    lib:Register("bad", {})
end)
check(not ok, "invalid registration reports an error")
ok = pcall(function()
    alpha:SetAutoShowEnabled("yes")
end)
check(not ok, "invalid notification values are rejected")
local selectedLMSMinor = LibStub.minors["LibModernSettings-1.0"]
LibStub.minors["LibModernSettings-1.0"] = 10
check(
    not pcall(lib._GetSettingsLibrary, lib),
    "LMS releases without scroll-area and texture-button support are rejected"
)
LibStub.minors["LibModernSettings-1.0"] = 12
check(
    pcall(lib._GetSettingsLibrary, lib),
    "newer same-family LMS releases remain supported"
)
LibStub.minors["LibModernSettings-1.0"] = selectedLMSMinor

local function registerEmphasis(emphasis)
    return lib:Register("EmphasisExample", {
        displayName = "Emphasis Example",
        release = {
            version = "1",
            notes = {},
            highlights = { { title = "A useful change", emphasis = emphasis } },
        },
        storage = {
            get = function() end,
            set = function() end,
        },
    })
end

for emphasis, label in pairs({
    featured = "FEATURED",
    important = "IMPORTANT",
    requested = "USER REQUESTED",
}) do
    local controller = registerEmphasis(emphasis)
    check(
        controller.options.release.highlights[1].emphasis == emphasis,
        "supported emphasis survives registration"
    )
    check(
        lib._highlightEmphasisLabels[emphasis] == label,
        "each supported emphasis supplies its own display label"
    )
end

check(registerEmphasis(nil), "ordinary highlights do not require emphasis")
check(
    not pcall(registerEmphasis, "unsupported"),
    "unknown emphasis is still rejected"
)

dofile("examples/Controls.lua")
local example = lib._controllers.LibChangelogControlsExample
local exampleSlider = example.options.release.highlights[1].controls[2]
check(
    exampleSlider.type == "slider"
        and exampleSlider.options.minValue == 20
        and exampleSlider.options.maxValue == 60
        and exampleSlider.options.step == 1,
    "the development slider example uses LMS's required option names"
)

print(
    "LibChangelog: state, lifecycle, callbacks, generator and mixed-embed tests passed"
)
