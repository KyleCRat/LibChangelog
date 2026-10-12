local MAJOR, MINOR = "LibChangelog-1.0", 1
local lib = LibStub(MAJOR, true)

if not lib or lib._implementationMinor ~= MINOR
    or not lib:_BeginModule("Coordinator", MINOR) then return end

local STARTUP_DELAY = 2
lib._lifecycle = lib._lifecycle or { worldReady = IsLoggedIn() }

function lib:_CanShow()
    local state = self._lifecycle

    return state.worldReady and not state.loading and not state.cinematic
        and not state.readyCheck and not InCombatLockdown() and UIParent:IsShown()
        and not (CinematicFrame and CinematicFrame:IsShown())
        and not (MovieFrame and MovieFrame:IsShown())
        and not (ReadyCheckFrame and ReadyCheckFrame:IsShown())
end

function lib:_Schedule()
    if self._timer then
        self._timer:Cancel()
        self._timer = nil
    end

    if not self:_CanShow() or not next(self._controllers) then return end
    if self._window and self._window.frame:IsShown() then return end

    self._timer = C_Timer.NewTimer(STARTUP_DELAY, function()
        self._timer = nil
        if not self:_CanShow() then return end

        if not self._batch then
            local entries = self:_CollectPending()
            if #entries == 0 then return end

            self:_PrepareBatch(entries)
        end

        self:_RevealBatch()
    end)
end

function lib:_Suspend()
    if self._timer then
        self._timer:Cancel()
        self._timer = nil
    end

    -- Retain the frozen batch. Automatic interruptions never acknowledge it.
    if self._window then self._window.frame:Hide() end
end

function lib:_ShowManual(controller)
    if not self:_CanShow() then return false, "not-safe" end

    if self._batch then
        for index, entry in ipairs(self._batch.entries) do
            if entry.controller == controller then
                self:_SelectEntry(index, true)
                self:_RevealBatch()
                return true
            end
        end

        return false, "batch-open"
    end

    if self._timer then
        self._timer:Cancel()
        self._timer = nil
    end

    self:_PrepareBatch({ controller:_CreateEntry() }, true)
    self:_RevealBatch()
    return true
end

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD()
    lib._lifecycle.worldReady = true
    lib._lifecycle.readyCheck = false
    lib:_Schedule()
end

function handlers.PLAYER_LEAVING_WORLD()
    lib._lifecycle.worldReady = false
    lib:_Suspend()
end

function handlers.LOADING_SCREEN_ENABLED()
    lib._lifecycle.loading = true
    lib:_Suspend()
end

function handlers.LOADING_SCREEN_DISABLED()
    lib._lifecycle.loading = false
    lib:_Schedule()
end

function handlers.CINEMATIC_START()
    lib._lifecycle.cinematic = true
    lib:_Suspend()
end

function handlers.CINEMATIC_STOP()
    lib._lifecycle.cinematic = false
    lib:_Schedule()
end

function handlers.READY_CHECK()
    lib._lifecycle.readyCheck = true
    lib:_Suspend()
end

function handlers.READY_CHECK_FINISHED()
    lib._lifecycle.readyCheck = false
    lib:_Schedule()
end

local function refreshControls()
    for _, controller in pairs(lib._controllers) do
        controller:Refresh()
    end
end

function handlers.PLAYER_REGEN_DISABLED()
    lib:_Suspend()
    refreshControls()
end

function handlers.PLAYER_REGEN_ENABLED()
    refreshControls()
    lib:_Schedule()
end

lib._eventHandlers = handlers
lib._eventFrame = lib._eventFrame or CreateFrame("Frame")
local frame = lib._eventFrame

-- World and cinematic transitions postpone all registered addons together.
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("LOADING_SCREEN_ENABLED")
frame:RegisterEvent("LOADING_SCREEN_DISABLED")
frame:RegisterEvent("CINEMATIC_START")
frame:RegisterEvent("CINEMATIC_STOP")

-- Preparation and combat take priority over update notices.
frame:RegisterEvent("READY_CHECK")
frame:RegisterEvent("READY_CHECK_FINISHED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    lib._eventHandlers[event]()
end)

if not lib._visibilityHooksInstalled then
    lib._visibilityHooksInstalled = true
    UIParent:HookScript("OnHide", function() lib:_Suspend() end)
    UIParent:HookScript("OnShow", function() lib:_Schedule() end)

    if MovieFrame then
        MovieFrame:HookScript("OnShow", function() lib:_Suspend() end)
        MovieFrame:HookScript("OnHide", function() lib:_Schedule() end)
    end

    if ReadyCheckFrame then
        ReadyCheckFrame:HookScript("OnHide", function() lib:_Schedule() end)
    end
end
