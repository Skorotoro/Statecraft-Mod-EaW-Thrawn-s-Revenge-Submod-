local DATA = require("eawx-plugins/diplomacy/DiplomacySpeechLines")
local VOICES = require("eawx-plugins/diplomacy/DiplomacyVoices")

local Speech = {last = {}}

local IMPERIAL = {}
for _, name in ipairs(DATA.IMPERIAL) do
    IMPERIAL[name] = true
end

local function epithet(d, speaker, listener)
    local own = DATA.EPITHETS[speaker] or {}
    local phrase = own[listener] or (IMPERIAL[listener] and own.IMPERIAL)
    if phrase then
        return phrase
    end
    local name = d.display_name(listener)
    if string.find(name, "^The ") then
        return "t" .. string.sub(name, 2)
    end
    if string.find(name, "'s ") then
        return name
    end
    return "the " .. name
end

function Speech.standing(d, target, attitude)
    local relation = d:relation(target)
    if relation == "ALLIANCE" or relation == "VASSAL" then
        return "ally"
    end
    if attitude >= 30 or (relation == "CEASEFIRE" and attitude >= 10) then
        return "friendly"
    end
    if attitude <= -20 or (relation == "WAR" and attitude < 0) then
        return "hostile"
    end
    return "neutral"
end

function Speech.reaction_tier(reaction)
    local total = reaction.total or 0
    if reaction.accepted then
        if reaction.extortion then
            return "accept", "extortion"
        elseif total >= 40 then
            return "accept", "generous"
        elseif total >= 12 then
            return "accept", "standard"
        end
        return "accept", "close"
    end
    if total >= -15 then
        return "refuse", "close"
    elseif total >= -50 then
        return "refuse", "standard"
    end
    return "refuse", "insulting"
end

local VOICE_MOOD = {
    greet = {ally = "greet_good", friendly = "greet_good", neutral = "greet", hostile = "greet_bad"},
    accept = {generous = "accept_good", standard = "accept", close = "accept_bad", extortion = "accept_bad"},
    refuse = {close = "refuse", standard = "refuse", insulting = "refuse_bad"},
}
local VOICE_FALLBACK = {
    greet = {"greet", "greet_good", "greet_bad"},
    greet_good = {"greet_good", "greet", "accept_good", "accept"},
    greet_bad = {"greet_bad", "greet", "refuse_bad", "refuse"},
    accept = {"accept", "accept_good", "accept_bad", "greet"},
    accept_good = {"accept_good", "accept", "greet_good"},
    accept_bad = {"accept_bad", "accept", "greet_bad"},
    refuse = {"refuse", "refuse_bad", "greet_bad"},
    refuse_bad = {"refuse_bad", "refuse", "greet_bad"},
    war = {"war", "refuse_bad", "greet_bad"},
}

local function sound_source()
    local ok, planets = pcall(FindPlanet.Get_All_Planets)
    if ok and planets then
        for _, planet in pairs(planets) do
            if TestValid(planet) then
                return planet
            end
        end
    end
    return nil
end

function Speech.play_sfx(event)
    if Engine_Play_Sound then
        local ok, handle = pcall(Engine_Play_Sound, event)
        return ok and (type(handle) ~= "number" or handle > 0), handle
    end
    local source = sound_source()
    if not source then
        return false
    end
    local ok = pcall(source.Play_SFX_Event, event)
    return ok
end

local function play_voice(leader_type, speaker, kind, tier)
    if Speech.voice_handle and Engine_Stop_Sound then
        pcall(Engine_Stop_Sound, Speech.voice_handle)
        Speech.voice_handle = nil
    end
    local voice = (leader_type and VOICES.VOICE_OF[leader_type]) or VOICES.FACTION_VOICE[speaker]
    local events = voice and VOICES.EVENTS[voice]
    if not events then
        return
    end
    local mood = (kind == "war") and "war" or (VOICE_MOOD[kind] and VOICE_MOOD[kind][tier])
    for _, m in ipairs(mood and VOICE_FALLBACK[mood] or {}) do
        local event = events[m]
        if type(event) == "table" then
            event = event[GameRandom.Free_Random(1, table.getn(event))]
        end
        if event then
            local ok, handle = Speech.play_sfx(event)
            if Engine_Log then
                Engine_Log("VOICE " .. event .. " " .. tostring(handle) .. (ok and "" or " failed"))
            end
            if ok then
                Speech.voice_handle = handle
                Speech.voice_watch = {event = event, handle = handle, t = 0, retried = false}
                return
            end
        end
    end
end

function Speech.watch_voice(ms)
    local w = Speech.voice_watch
    if not w or not Engine_Sound_Playing then
        return
    end
    w.t = w.t + (ms or 0)
    if w.t < 350 then
        return
    end
    local state = Engine_Sound_Playing(w.handle)
    if state == -1 and w.t < 1500 then
        return
    end
    Speech.voice_watch = nil
    if state == 1 or w.retried or Speech.voice_handle ~= w.handle then
        return
    end
    local ok, handle = Speech.play_sfx(w.event)
    if Engine_Log then
        Engine_Log("VOICE retry " .. w.event .. " " .. tostring(state) .. " -> " .. tostring(handle))
    end
    if ok then
        Speech.voice_handle = handle
        Speech.voice_watch = {event = w.event, handle = handle, t = 0, retried = true}
    end
end

local function wrap(text, width, out)
    out = out or {}
    local line = ""
    local rest = text
    while rest ~= "" do
        local _, _, word, gap, tail = string.find(rest, "^(%S+)(%s*)(.*)$")
        if not word then
            break
        end
        if line == "" then
            line = word
        elseif string.len(line) + 1 + string.len(word) <= width then
            line = line .. " " .. word
        else
            table.insert(out, line)
            line = word
        end
        rest = tail
    end
    if line ~= "" then
        table.insert(out, line)
    end
    return out
end

local function next_index(i, n)
    if i >= n then
        return 1
    end
    return i + 1
end

local function fill(text, them)
    local out = string.gsub(text, "{them}", them)
    return string.upper(string.sub(out, 1, 1)) .. string.sub(out, 2)
end

function Speech.say(d, speaker, listener, leader_type, kind, tier, width)
    local own = DATA.BY_NAME[d.display_name(speaker)] or DATA.LINES[speaker] or DATA.LINES.WARLORDS
    local pool
    if kind == "war" then
        pool = own.war
    else
        pool = own[kind] and own[kind][tier]
    end
    if not pool or table.getn(pool) == 0 then
        return nil
    end
    local key = speaker .. kind .. (tier or "")
    local pick = GameRandom.Free_Random(1, table.getn(pool))
    if table.getn(pool) > 1 and pick == Speech.last[key] then
        pick = next_index(pick, table.getn(pool))
    end
    Speech.last[key] = pick
    local line = pool[pick]
    local them = epithet(d, speaker, listener)
    local lines = {}
    if type(line) == "table" then
        for _, l in ipairs(wrap(fill(line[1], them), width)) do
            table.insert(lines, {l, true})
        end
        for _, l in ipairs(wrap("(" .. fill(line[2], them) .. ")", width)) do
            table.insert(lines, {l, false})
        end
    else
        for _, l in ipairs(wrap(fill(line, them), width)) do
            table.insert(lines, {l, false})
        end
    end
    play_voice(leader_type, speaker, kind, tier)
    return lines
end

return Speech
