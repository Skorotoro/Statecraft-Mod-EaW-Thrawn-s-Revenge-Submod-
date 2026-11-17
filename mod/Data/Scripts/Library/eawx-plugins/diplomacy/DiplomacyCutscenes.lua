local Pause = require("eawx-plugins/diplomacy/DiplomacyPause")
local ok_list, LIST = pcall(require, "eawx-plugins/diplomacy/DiplomacyCutsceneList")
if not ok_list or type(LIST) ~= "table" then
    LIST = {movies = {}}
end

local Cutscenes = {queue = {}, playing = nil}

local LONGEST = 600

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("CUTSCENE gui error: " .. tostring(err))
    end
end

local function shape()
    local width = 1365
    if Engine_Screen_Size then
        local ok, w, h = pcall(Engine_Screen_Size)
        if ok and w and h and h > 0 then
            width = 768 * w / h
        end
    end
    local best, gap = "169", nil
    for v, vw in pairs(LIST.shapes or {}) do
        local g = (vw > width) and (vw - width) or (width - vw)
        if not gap or g < gap then
            best, gap = v, g
        end
    end
    return best
end

local function size_for(sizes)
    local tall = false
    if Engine_Screen_Size then
        local ok, _, h = pcall(Engine_Screen_Size)
        tall = ok and h ~= nil and h > 1080
    end
    local best = nil
    for _, v in ipairs(sizes or {}) do
        if not best or (tall and v > best) or (not tall and v < best) then
            best = v
        end
    end
    return best or 1080
end

function Cutscenes.available(key)
    return LIST.movies[key] ~= nil
end

local WINDOWS = {"eawx-plugins/diplomacy/DiplomacyWindow", "eawx-plugins/diplomacy/DiplomacySenateWindow",
    "eawx-plugins/diplomacy/DiplomacyKajidicWindow", "eawx-plugins/new-republic/RepublicWindow",
    "eawx-plugins/imperial-court/CourtWindow"}

local function close_windows()
    for _, path in ipairs(WINDOWS) do
        local ok, W = pcall(require, path)
        if ok and type(W) == "table" and W.open_now and W.close then
            pcall(W.close)
        end
    end
end

local function guard(on)
    if on and not Cutscenes.real then
        Cutscenes.real = {tick = Engine_Gui_Tick, text = Engine_Screen_Text}
        if Cutscenes.real.tick then
            Engine_Gui_Tick = function(state)
                if state ~= 0 then
                    return Cutscenes.real.tick(state)
                end
            end
        end
        if Cutscenes.real.text then
            Engine_Screen_Text = function(state)
                if state == 0 then
                    return Cutscenes.real.text(state)
                end
            end
        end
    elseif not on and Cutscenes.real then
        Engine_Gui_Tick, Engine_Screen_Text = Cutscenes.real.tick, Cutscenes.real.text
        Cutscenes.real = nil
    end
end

local function start(entry)
    close_windows()
    local movie = LIST.movies[entry.key]
    local size = size_for(movie.sizes)
    local v = shape()
    entry.shell = "dp_cut" .. v .. "_shell"
    call(GUI_Component_Text, "dp_cut" .. v .. "_title", entry.title or movie.title)
    call(GUI_Component_Visibility, entry.shell, true)
    Pause.hold("cutscene")
    if Engine_Screen_Text then
        Engine_Screen_Text(0)
    end
    if Engine_Escape_Capture then
        Engine_Escape_Capture(1)
    end
    if Engine_Movie_Rect and Engine_Screen_Size then
        local ok_s, w, h = pcall(Engine_Screen_Size)
        if ok_s and w and h and w > 0 and h > 0 then
            local aspect, movie = w / h, 16 / 9
            if aspect > movie then
                local mw = movie / aspect
                Engine_Movie_Rect((1 - mw) / 2, 0, mw, 1)
            else
                local mh = aspect / movie
                Engine_Movie_Rect(0, (1 - mh) / 2, 1, mh)
            end
        end
    end
    local ok, block = pcall(Play_Bink_Movie, "Dp_Cutscene_" .. entry.key .. "_" .. size)
    if not ok then
        if Engine_Log then
            Engine_Log("CUTSCENE " .. entry.key .. " failed: " .. tostring(block))
        end
        block = nil
    end
    entry.block, entry.ms = block, 0
    Cutscenes.playing = entry
    if Engine_Gui_Tick then
        Engine_Gui_Tick(1)
    end
    guard(true)
end

local function finish()
    local entry = Cutscenes.playing
    Cutscenes.playing = nil
    if Engine_Escape_Capture then
        Engine_Escape_Capture(0)
    end
    if Engine_Movie_Rect then
        Engine_Movie_Rect()
    end
    guard(false)
    call(GUI_Component_Visibility, entry.shell, false)
    Pause.release("cutscene")
    if Engine_Screen_Text then
        Engine_Screen_Text(1)
    end
    if entry.after then
        local ok, err = pcall(entry.after)
        if not ok and Engine_Log then
            Engine_Log("CUTSCENE after " .. entry.key .. ": " .. tostring(err))
        end
    end
    local next_entry = table.remove(Cutscenes.queue, 1)
    if next_entry then
        start(next_entry)
    end
end

function Cutscenes.play(key, title, after)
    if not Cutscenes.available(key) then
        if after then
            pcall(after)
        end
        return false
    end
    local entry = {key = key, title = title, after = after}
    if Cutscenes.playing then
        table.insert(Cutscenes.queue, entry)
    else
        start(entry)
    end
    return true
end

function Cutscenes.tick(ms)
    local entry = Cutscenes.playing
    if not entry then
        return false
    end
    entry.ms = entry.ms + (ms or 0)
    local done = entry.block == nil or entry.ms > LONGEST * 1000
    if not done and Engine_Escape_Pressed and Engine_Escape_Pressed() > 0 then
        pcall(Stop_Bink_Movie)
        done = true
    end
    if not done then
        local ok, finished = pcall(function() return entry.block.IsFinished() end)
        done = (not ok) or finished == true
    end
    if done then
        finish()
    end
    return true
end

function Cutscenes.busy()
    return Cutscenes.playing ~= nil
end

return Cutscenes
