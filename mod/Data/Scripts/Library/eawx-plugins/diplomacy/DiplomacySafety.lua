local Safety = {trace_left = 0, trace_planet = nil, on_screen = false}

local reported = {}

local function report(where, err)
    local text = where .. ": " .. tostring(err)
    if reported[text] then
        return
    end
    reported[text] = true
    if Engine_Log then
        Engine_Log("SCRIPT ERROR CAUGHT in " .. text)
    end
    if Safety.on_screen then
        StoryUtil.ShowScreenText("Diplomacy: script error caught in " .. text, 30, nil, {r = 255, g = 80, b = 80})
    end
end

local last_trace = nil
local function trace(text)
    if last_trace then
        StoryUtil.RemoveScreenText(last_trace)
    end
    last_trace = "[TRACE] in: " .. text
    StoryUtil.ShowScreenText(last_trace, 600, nil, {r = 255, g = 255, b = 255})
end

local function describe(obj)
    if type(obj) ~= "table" then
        return ""
    end
    local names, count = "", 0
    for key, _ in pairs(obj) do
        if type(key) == "string" and count < 3 then
            names = names .. " " .. key
            count = count + 1
        end
    end
    return " (" .. names .. " )"
end

local function planet_name(p)
    if type(p) == "table" and type(p.get_name) == "function" then
        local ok, name = pcall(p.get_name, p)
        if ok then
            return name
        end
    end
    return nil
end

local function describe_arg(a)
    if type(a) == "table" then
        if a.get_name then
            local name = planet_name(a)
            return name and (" [planet " .. tostring(name) .. "]") or (" [planet wrapper without a game object: "
                .. tostring(a.gameObject) .. "]")
        end
        return " [table]"
    elseif a ~= nil then
        return " [" .. tostring(a) .. "]"
    end
    return " [nil]"
end

local function wrap_plugin(container, where)
    local plugin = container.plugin
    if not plugin or plugin.__diplomacy_safe or type(plugin.update) ~= "function" then
        return
    end
    local original = plugin.update
    plugin.update = function(self, a1, a2, a3)
        local tracing = Safety.trace_left > 0
            and (a1 == nil or planet_name(a1) == Safety.trace_planet)
        if tracing then
            trace(where .. describe(self))
        end
        local ok, err = pcall(original, self, a1, a2, a3)
        if not ok then
            report(where, err)
        end
        if tracing then
            trace("between steps (after " .. where .. ")")
        end
    end
    plugin.__diplomacy_safe = true
end

local function wrap_listeners(event, where)
    if type(event) ~= "table" or type(event.Listeners) ~= "table" then
        return
    end
    for i, entry in ipairs(event.Listeners) do
        if not entry.__diplomacy_safe and type(entry.Listener) == "function" then
            local original = entry.Listener
            local name = where .. " #" .. i .. describe(entry.Arg)
            entry.Listener = function(a1, a2, a3, a4, a5)
                if Safety.trace_left > 0 then
                    trace(name)
                end
                local ok, err = pcall(original, a1, a2, a3, a4, a5)
                if not ok then
                    report(name .. describe_arg(a1) .. describe_arg(a2) .. describe_arg(a3), err)
                end
                if Safety.trace_left > 0 then
                    trace("between steps (after " .. name .. ")")
                end
            end
            entry.__diplomacy_safe = true
        end
    end
end

function Safety.protect(gc)
    local mod = ActiveMod
    if type(mod) == "table" then
        for i, container in ipairs(mod.plugin_containers or {}) do
            wrap_plugin(container, "campaign plugin #" .. i)
        end
        for i, container in ipairs(mod.planet_dependent_plugin_containers or {}) do
            wrap_plugin(container, "per-planet plugin #" .. i)
        end
    end
    for name, event in pairs(gc.Events or {}) do
        wrap_listeners(event, name .. " listener")
    end
end

return Safety
