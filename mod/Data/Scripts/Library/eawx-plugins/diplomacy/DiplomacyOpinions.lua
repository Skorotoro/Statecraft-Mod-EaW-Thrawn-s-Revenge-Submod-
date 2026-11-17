require("eawx-plugins/diplomacy/DiplomacyAI")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Reputation = require("eawx-plugins/diplomacy/DiplomacyReputation")

local Opinions = {}
local R = CONFIG.OPINION

Opinions.MAX_EVENTS = 12
Opinions.GROUPS = {"Who they are", "What they've done", "How things stand"}

local events = {}
local wars = {}
local shown = {}
local world = {owner = {}, count = {}, past = {}, total = 0, powers = {}, before = {}, borders = {}, enemies = {}}
local cache = {}
local views = {}
local next_week = 0
local provider = nil

local function key(a, b)
    return string.upper(a) .. "|" .. string.upper(b)
end

local function player(name)
    local ok, p = pcall(Find_Player, name)
    return ok and p or nil
end

local function at_war(a, b)
    local pa, pb = player(a), player(b)
    if not (pa and pb) then
        return true
    end
    return pa.Is_Enemy(pb)
end

function Opinions.set_provider(fn)
    provider = fn
end

local ai_provider = nil
function Opinions.set_ai_provider(fn)
    ai_provider = fn
end

function Opinions.world()
    if world.total == 0 then
        Opinions.survey()
    end
    return world
end

function Opinions.outlook(faction)
    faction = string.upper(faction)
    if R.OUTLOOK[faction] then
        return R.OUTLOOK[faction]
    end
    if Diplomacy and Diplomacy.warlord_factions and Diplomacy.warlord_factions()[faction] then
        return "IMPERIAL"
    end
    return R.OUTLOOK_DEFAULT
end

local function outlook_pair(x, y)
    for _, rule in ipairs(R.OUTLOOK_PAIRS) do
        if (rule[1] == x and rule[2] == y) or (rule[1] == y and rule[2] == x) then
            return rule[3], rule[4]
        end
    end
    return 0, nil
end

local function who(a, b, add)
    for _, rule in ipairs(CONFIG.AFFINITY) do
        local x, y, points = rule[1], rule[2], rule[3]
        if y ~= "*" and ((x == a and y == b) or (x == b and y == a)) then
            add(points, (points >= 0) and "historic friendship" or "historic enmity")
            return
        end
    end
    local oa, ob = Opinions.outlook(a), Opinions.outlook(b)
    if (a == "EMPIRE" and ob == "IMPERIAL") or (b == "EMPIRE" and oa == "IMPERIAL") then
        add(R.IMPERIAL_GRUDGE, "old grudges among Imperials")
        return
    end
    local points, text = outlook_pair(oa, ob)
    if points ~= 0 then
        add(points, text)
    end
    for _, rule in ipairs(CONFIG.AFFINITY) do
        local x, points2 = rule[1], rule[3]
        if rule[2] == "*" and (x == b or x == a) then
            if x == "EMPIRE" then
                add(points2, "hatred of the Empire")
            else
                add(points2, "general distrust of " .. ((x == b) and "them" or "everyone"))
            end
            return
        end
    end
end

local function remember(a, b, entry)
    local k = key(a, b)
    cache[k] = nil
    local list = events[k] or {}
    events[k] = list
    table.insert(list, entry)
    while table.getn(list) > Opinions.MAX_EVENTS do
        table.remove(list, 1)
    end
end

function Opinions.event(a, b, kind)
    local def = R.EVENTS[kind]
    if not (a and b and def) or string.upper(a) == string.upper(b) then
        return
    end
    if world.total == 0 then
        Opinions.survey()
    end
    remember(a, b, {value = def.value, time = GetCurrentTime(), half = def.half, scar = def.scar, text = def.text,
                    kind = kind})
    if def.witness then
        for name, _ in pairs(world.powers) do
            if name ~= string.upper(a) and name ~= string.upper(b) then
                remember(name, b, {value = def.witness.value, time = GetCurrentTime(), half = def.witness.half,
                                   text = def.witness.text, kind = kind .. "_WITNESS"})
            end
        end
    end
    if def.scar or def.value <= -30 then
        local s = shown[key(a, b)]
        if s then
            s.snap = true
        end
    end
end

function Opinions.count(a, b, kind)
    local n = 0
    for _, e in ipairs(events[key(a, b)] or {}) do
        if e.kind == kind then
            n = n + 1
        end
    end
    return n
end

function Opinions.add(a, b, value, weeks, text)
    remember(a, b, {value = value, time = GetCurrentTime(), weeks = weeks, text = text})
end

local function done(a, b, add)
    local now = GetCurrentTime()
    local kept, sums, order, caps = {}, {}, {}, {}
    for _, e in ipairs(events[key(a, b)] or {}) do
        local weeks = (now - e.time) / CONFIG.WEEK_SECONDS
        local v
        if e.weeks then
            local left = 1 - weeks / e.weeks
            v = (left > 0) and e.value * left or nil
        else
            v = e.value * M.half_pow(weeks / e.half) + (e.scar or 0)
            if M.abs(v - (e.scar or 0)) < 0.5 and not e.scar then
                v = nil
            end
        end
        if v then
            table.insert(kept, e)
            if not sums[e.text] then
                table.insert(order, e.text)
                sums[e.text] = 0
                local def = e.kind and R.EVENTS[e.kind]
                caps[e.text] = def and def.cap
            end
            sums[e.text] = sums[e.text] + v
        end
    end
    events[key(a, b)] = kept[1] and kept or nil
    for _, text in ipairs(order) do
        local v, cap = sums[text], caps[text]
        if cap then
            v = (cap < 0) and M.max(v, cap) or M.min(v, cap)
        end
        add(v, text)
    end
end

local function borders(a, b)
    return world.borders[key(a, b)] or 0
end

local function grew(faction)
    local past = world.past[R.EXPANSION_WEEKS] or {}
    return (world.count[faction] or 0) > (past[faction] or world.count[faction] or 0)
end

local function stands(a, b, add, handled)
    local war = at_war(a, b)
    if not handled then
        if war then
            add(R.WAR, "at war")
        else
            add(R.AI_PEACE, "at peace")
        end
    end
    if not war then
        local shared = 0
        local ea, eb = world.enemies[a] or {}, world.enemies[b] or {}
        for name, _ in pairs(ea) do
            if name ~= b and eb[name] then
                shared = shared + 1
            end
        end
        add(M.min(R.SHARED_ENEMY_CAP, shared * R.SHARED_ENEMY), "common enemies")
    end
    if grew(a) and grew(b) then
        add(M.max(R.BORDER_CAP, borders(a, b) * R.BORDER_PER_WORLD), "border friction: both are expanding")
    end
    if world.total > 0 then
        local share = 100 * (world.count[b] or 0) / world.total
        if share > R.FEAR_SHARE then
            add(M.max(R.FEAR_CAP, R.FEAR_SHARE - share), "fear of their power (" .. M.round(share) .. "% of the worlds)")
        end
    end
    local rep = Reputation.opinion(b)
    if rep ~= 0 then
        local word = string.lower(Reputation.word(b))
        add(rep, (string.find(word, "^[aeiou]") and "an " or "a ") .. word .. " reputation")
    end
end

function Opinions.parts(a, b)
    a, b = string.upper(a), string.upper(b)
    local hit = cache[key(a, b)]
    local now = GetCurrentTime()
    if hit and now >= hit.time and now - hit.time < 5 then
        return hit.total, hit.groups
    end
    local groups = {{Opinions.GROUPS[1], {}}, {Opinions.GROUPS[2], {}}, {Opinions.GROUPS[3], {}}}
    local current = 1
    local function add(value, text, group)
        value = M.round(value or 0)
        if value ~= 0 and text then
            table.insert(groups[group or current][2], {text, value})
        end
    end
    if world.total == 0 then
        Opinions.survey()
    end
    who(a, b, add)
    current = 2
    done(a, b, add)
    local handled = false
    if provider then
        local ok, h = pcall(provider, a, b, add)
        handled = ok and h
    end
    if not handled and ai_provider then
        local ok, h = pcall(ai_provider, a, b, add)
        handled = ok and h
    end
    current = 3
    stands(a, b, add, handled)
    local total = 0
    for _, g in ipairs(groups) do
        for _, line in ipairs(g[2]) do
            total = total + line[2]
        end
    end
    total = M.max(-100, M.min(100, total))
    cache[key(a, b)] = {time = now, total = total, groups = groups}
    return total, groups
end

function Opinions.nudge(a, b, value)
    local k = key(string.upper(a), string.upper(b))
    cache[k] = nil
    local s = shown[k]
    if s and value then
        s.value = M.max(-100, M.min(100, s.value + value))
    end
end

function Opinions.get(a, b)
    local k = key(a, b)
    local s = shown[k]
    local war = at_war(a, b)
    if s and s.war ~= war then
        cache[k] = nil
    end
    local target, groups = Opinions.parts(a, b)
    if not s then
        s = {value = target, war = war, history = {}}
        shown[k] = s
    elseif s.snap or s.war ~= war then
        s.value, s.war, s.snap = target, war, nil
    end
    local reasons = {}
    for _, g in ipairs(groups) do
        for _, line in ipairs(g[2]) do
            table.insert(reasons, line)
        end
    end
    return s.value, reasons, groups, target
end

function Opinions.trend(a, b)
    local s = shown[key(a, b)]
    local old = s and s.history[R.TREND_WEEKS]
    if not old then
        return nil
    end
    if s.value >= old + 3 then
        return "rising"
    elseif s.value <= old - 3 then
        return "falling"
    end
    return nil
end

local ROUTES = nil
function Opinions.routes()
    if ROUTES == nil then
        local ok, data = pcall(require, "eawx-plugins/imperial-court/CourtRoutes")
        ROUTES = ok and type(data) == "table" and data or false
    end
    return ROUTES or {}
end

function Opinions.survey()
    local owner, count, total = {}, {}, 0
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local o = planet.Get_Owner()
        local name = o and string.upper(o.Get_Faction_Name())
        if name and name ~= "NEUTRAL" then
            owner[string.upper(planet.Get_Type().Get_Name())] = name
            count[name] = (count[name] or 0) + 1
            total = total + 1
        end
    end
    local powers = {}
    for name, _ in pairs(count) do
        if name ~= "INDEPENDENT_FORCES" and name ~= "HOSTILE" then
            powers[name] = true
        end
    end
    local routes, bord = Opinions.routes(), {}
    for planet, b in pairs(owner) do
        local seen = {}
        for other in string.gfind(routes[planet] or "", "%S+") do
            local a = owner[other]
            if a and a ~= b and not seen[a] then
                seen[a] = true
                bord[key(a, b)] = (bord[key(a, b)] or 0) + 1
            end
        end
    end
    local enemies = {}
    for a, _ in pairs(powers) do
        enemies[a] = {}
        for b, _ in pairs(powers) do
            if a ~= b and at_war(a, b) then
                enemies[a][b] = true
            end
        end
    end
    world.owner, world.count, world.total, world.powers = owner, count, total, powers
    world.borders, world.enemies = bord, enemies
    cache = {}
end

function Opinions.weekly()
    local now = GetCurrentTime()
    if now < next_week then
        return
    end
    next_week = now + CONFIG.WEEK_SECONDS
    local past = world.past
    table.insert(past, 1, world.count)
    while table.getn(past) > R.EXPANSION_WEEKS do
        table.remove(past)
    end
    Opinions.survey()
    for k, s in pairs(shown) do
        local _, _, a, b = string.find(k, "^(.-)|(.+)$")
        if player(a) and player(b) then
            local target = Opinions.parts(a, b)
            table.insert(s.history, 1, s.value)
            while table.getn(s.history) > R.TREND_WEEKS do
                table.remove(s.history)
            end
            if s.value < target then
                s.value = M.min(target, s.value + R.STEP)
            else
                s.value = M.max(target, s.value - R.STEP)
            end
        else
            shown[k] = nil
        end
    end
    views = {}
    for a, _ in pairs(world.powers) do
        local list = {}
        for b, _ in pairs(world.powers) do
            if a ~= b then
                table.insert(list, {b, (Opinions.get(a, b))})
            end
        end
        views[a] = list
    end
end

function Opinions.views(a, human, n)
    local friends, foes = {}, {}
    for _, v in ipairs(views[string.upper(a)] or {}) do
        if v[1] ~= human then
            if v[2] >= 15 then
                table.insert(friends, v)
            elseif v[2] <= -40 then
                table.insert(foes, v)
            end
        end
    end
    table.sort(friends, function(x, y) return x[2] > y[2] end)
    table.sort(foes, function(x, y) return x[2] < y[2] end)
    while table.getn(friends) > n do table.remove(friends) end
    while table.getn(foes) > n do table.remove(foes) end
    return {friends = friends, foes = foes}
end

function Opinions.on_world_taken(planet_name, new_owner, old_owner)
    local name = string.upper(planet_name)
    local new, old = new_owner and string.upper(new_owner), old_owner and string.upper(old_owner)
    if world.total == 0 then
        Opinions.survey()
    end
    if new and old and new ~= old and world.powers[old] ~= nil and new ~= "NEUTRAL" then
        Opinions.event(old, new, "WORLD_TAKEN")
        for p, _ in pairs(world.powers) do
            if p ~= new and p ~= old and at_war(p, old) and not at_war(p, new) then
                Opinions.event(p, new, "TOOK_FROM_ENEMY")
            end
        end
        local before = world.before[name]
        if before and before ~= new and before ~= old and world.powers[before] and not at_war(before, new) then
            Opinions.event(before, new, "FREED_WORLD")
        end
    end
    if old then
        world.before[name] = old
    end
    if new then
        world.owner[name] = new
    end
end

function Opinions.on_hero_killed(owner, killer)
    if owner and killer then
        Opinions.event(string.upper(owner), string.upper(killer), "HERO_KILLED")
    end
end

function Opinions.force_war(a, b)
    local pa, pb = Find_Player(a), Find_Player(b)
    if not (pa and pb) then
        return false
    end
    wars[key(a, b)] = true
    pa.Make_Enemy(pb)
    pb.Make_Enemy(pa)
    return true
end

function Opinions.end_war(a, b)
    wars[key(a, b)] = nil
    wars[key(b, a)] = nil
end

function Opinions.apply()
    for k, _ in pairs(wars) do
        local _, _, a, b = string.find(k, "^(.-)|(.+)$")
        local pa, pb = a and Find_Player(a), b and Find_Player(b)
        if pa and pb then
            pa.Make_Enemy(pb)
            pb.Make_Enemy(pa)
        end
    end
    Opinions.weekly()
end

function Opinions.share()
    DIPLOMACY_OPINION = function(a, b)
        local value = Opinions.get(a, b)
        return value
    end
    DIPLOMACY_OPINION_REASONS = function(a, b)
        local _, reasons = Opinions.get(a, b)
        return reasons
    end
    DIPLOMACY_OPINION_ADD = Opinions.add
    DIPLOMACY_FORCE_WAR = Opinions.force_war
end

return Opinions
