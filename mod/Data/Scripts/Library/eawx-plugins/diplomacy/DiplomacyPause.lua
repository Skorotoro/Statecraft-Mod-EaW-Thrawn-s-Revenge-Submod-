local Pause = {open = {}, ours = false, probe = nil, counted = false}

local function counted()
    return Engine_Pause and Engine_Pause() ~= nil
end

local WATCH_MS = 300

local function any_open()
    for _, _ in pairs(Pause.open) do
        return true
    end
    return false
end

local function pause_now()
    Pause.probe, Pause.ours = nil, true
    Story_Event("DIPLOMACY_WINDOW_PAUSE")
end

function Pause.hold(window)
    local first = not any_open()
    Pause.open[window] = true
    if not first or Pause.ours or Pause.probe or Pause.counted then
        return
    end
    if counted() then
        Engine_Pause(1)
        Pause.counted = true
        return
    end
    if not (Engine_Gui_Tick and GetCurrentTime) then
        pause_now()
        return
    end
    Pause.probe = {clock = GetCurrentTime(), waited = 0}
    Engine_Gui_Tick(1)
end

function Pause.release(window)
    Pause.open[window] = nil
    if any_open() then
        return
    end
    Pause.probe = nil
    if Pause.counted then
        Pause.counted = false
        Engine_Pause(0)
    end
    if Pause.ours then
        Pause.ours = false
        Story_Event("DIPLOMACY_WINDOW_UNPAUSE")
    end
end

function Pause.watching()
    return Pause.probe ~= nil
end

function Pause.tick(ms)
    local probe = Pause.probe
    if not probe then
        return
    end
    probe.waited = probe.waited + ms
    if GetCurrentTime() ~= probe.clock then
        pause_now()
    elseif probe.waited >= WATCH_MS then
        Pause.probe = nil
    end
end

return Pause
