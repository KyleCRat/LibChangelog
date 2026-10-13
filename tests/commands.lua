return function(lib, register, setCombat, event, drainTimers)
    local originalControllers, originalBatch = lib._controllers, lib._batch
    lib:_Suspend()
    lib._controllers = {}
    lib._batch = nil

    local messages = {}
    local originalPrint = print
    print = function(message) messages[#messages + 1] = message end

    assert(SLASH_LIBCHANGELOG1 == "/changelog", "command belongs to the shared library")
    local shown, reason = lib:ShowAll()
    assert(not shown and reason == "no-consumers", "empty registrations do not create a window")
    SlashCmdList.LIBCHANGELOG("")
    assert(messages[1]:find("No addon changelogs are available", 1, true))

    local beta, betaStore = register("ManualBeta", "1", { autoShow = false })
    local alpha, alphaStore = register("ManualAlpha", "1", { acknowledgedVersion = "1" })
    local preview, previewStore = register("ManualPreview", "Unreleased", nil, true)
    local gamma, gammaStore = register("ManualGamma", "1")
    lib._sessionFailures.ManualBeta = "1"
    local pending = lib:_CollectPending()
    assert(#pending == 1 and pending[1].controller == gamma,
        "automatic collection still excludes read, opted-out and unreleased entries")

    local timer = lib._timer
    SlashCmdList.LIBCHANGELOG("")
    local batch = lib._batch
    assert(batch.manual and #batch.entries == 4, "command displays all registered consumers")
    assert(batch.entries[1].controller == alpha and batch.entries[2].controller == beta
        and batch.entries[3].controller == gamma and batch.entries[4].controller == preview,
        "manual browsing uses the same alphabetical order as automatic notices")
    assert(lib._window.frame:IsShown(), "manual browsing reveals the combined window")
    assert(lib._timer == nil and timer.cancelled, "manual browsing cancels the pending automatic popup")
    drainTimers()
    assert(lib._batch == batch, "cancelled automatic work cannot replace the manual batch")
    assert(alphaStore.acknowledgedVersion == "1" and gammaStore.acknowledgedVersion == nil
        and betaStore.acknowledgedVersion == nil and previewStore.acknowledgedVersion == nil,
        "opening all changelogs does not acknowledge any releases")
    assert(betaStore.autoShow == false, "manual browsing does not enable automatic notices")

    register("ManualAlpha", "2", alphaStore)
    local late, lateStore = register("ManualLate", "3")
    assert(lib._batch == batch, "registration alone does not alter the open batch")
    assert(lib:ShowAll(), "all-consumer browsing can replace an existing batch")
    assert(#lib._batch.entries == 5 and lib._batch.entries[1].release.version == "2",
        "explicit browsing collects the latest registered release and late consumers")
    assert(lib._batch.entries[4].controller == late and lateStore.acknowledgedVersion == nil
        and alphaStore.acknowledgedVersion == "1" and gammaStore.acknowledgedVersion == nil,
        "replacing a batch does not dismiss unread updates")

    local latestBatch = lib._batch
    setCombat(true)
    event("PLAYER_REGEN_DISABLED")
    shown, reason = lib:ShowAll()
    assert(not shown and reason == "not-safe" and lib._batch == latestBatch,
        "combat blocks manual opening without discarding the suspended batch")
    SlashCmdList.LIBCHANGELOG("")
    assert(#messages == 2 and messages[2]:find("can't open right now", 1, true),
        "blocked slash commands explain why the window did not open")
    assert(not lib._window.frame:IsShown(), "command cannot reveal a window during combat")
    setCombat(false)
    event("PLAYER_REGEN_ENABLED")
    event("READY_CHECK")
    assert(select(2, lib:ShowAll()) == "not-safe", "ready checks also block manual browsing")
    event("READY_CHECK_FINISHED")
    drainTimers()
    assert(lib._batch == latestBatch and lib._window.frame:IsShown(),
        "the existing combined batch resumes after interruptions")

    lib:_DismissBatch()
    assert(alphaStore.acknowledgedVersion == "2" and betaStore.acknowledgedVersion == "1"
        and gammaStore.acknowledgedVersion == "1" and lateStore.acknowledgedVersion == "3",
        "closing all changelogs dismisses the displayed releases")
    assert(previewStore.acknowledgedVersion == nil and betaStore.autoShow == false,
        "closing a manual batch preserves preview and opt-out behavior")

    lib:_Suspend()
    lib._sessionFailures.ManualBeta = nil
    lib._controllers = originalControllers
    lib._batch = originalBatch
    print = originalPrint
end
