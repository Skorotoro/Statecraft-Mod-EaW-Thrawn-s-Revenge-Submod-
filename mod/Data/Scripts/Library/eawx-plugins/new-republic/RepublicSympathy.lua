local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Sym = {}
local COLOR = {r = 170, g = 200, b = 255}

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.sym = r.sym or {value = {}, jumps = {}, broadcast = {}, cells = {}, survey = {}}
    return r.sym
end

local function territory(key)
    local Republic = require("eawx-plugins/new-republic/Republic")
    return Republic.is_territory(key)
end

local function ours(d, planet)
    local owner = planet.Get_Owner()
    return owner == d.human or owner == d:vassal_player()
        or (d.vassal_worlds[string.upper(planet.Get_Type().Get_Name())] ~= nil)
end

local function start_value(d, key, owner_name)
    local value
    if R.SYMPATHY_LORE[key] then
        value = R.SYMPATHY_LORE[key]
    elseif owner_name == "REBEL" then
        value = R.SYMPATHY_START.OWN
    else
        value = R.SYMPATHY_START[U.category(owner_name)] or 30
    end
    local me = string.upper(d.human.Get_Faction_Name())
    if string.upper(owner_name or "") == me then
        return value
    end
    local preferred = Sym.preferred(d, key)
    if preferred == me then
        value = M.max(value, R.SYMPATHY_START.PREFERS)
    elseif not R.SYMPATHY_LORE[key] then
        if preferred == "EMPIRE" then
            value = M.min(value, R.SYMPATHY_START.PREFERS_EMPIRE)
        elseif preferred and R.SYMPATHY_HOSTILE_PREFERRED[string.upper(preferred)] and key ~= "GEONOSIS" then
            value = M.min(value, R.SYMPATHY_START.PREFERS_EMPIRE)
        elseif preferred == "INDEPENDENT_FORCES" then
            value = R.SYMPATHY_START.PREFERS_INDEPENDENT
        end
    end
    return value
end

function Sym.value(d, key, owner_name)
    local s = state(d)
    if not s then
        return nil
    end
    if not owner_name then
        local planet = FindPlanet(key)
        if planet and planet.Get_Owner() == d.human and not Sym.own_counted(d) then
            return nil
        end
    end
    if s.value[key] == nil then
        local planet = FindPlanet(key)
        if not planet or territory(key) then
            return nil
        end
        s.value[key] = start_value(d, key, owner_name or planet.Get_Owner().Get_Faction_Name())
    end
    return s.value[key]
end

function Sym.on_war(d, faction)
    if not state(d) then
        return
    end
    local independent = U.category(faction) == "INDEPENDENT"
    for _, w in ipairs(U.worlds_of(Find_Player(faction))) do
        local v = Sym.value(d, w.key)
        if v then
            Sym.change(d, w.key, independent and (M.min(v, R.SYMPATHY_WAR_INDEPENDENT) - v) or R.SYMPATHY_WAR_OTHER)
        end
    end
end

function Sym.change(d, key, amount, owner_name)
    local s = state(d)
    local v = Sym.value(d, key, owner_name)
    if s and v then
        s.value[key] = U.clamp(v + amount, 0, 100)
        s.pending = s.pending or {}
        s.pending[key] = (s.pending[key] or 0) + (s.value[key] - v)
        Sym.note_tier(d, key, v, s.value[key])
    end
end

local TIER_COLORS = {Hostile = {r = 255, g = 80, b = 70}, Wary = {r = 255, g = 230, b = 80},
                     Sympathetic = {r = 100, g = 255, b = 100}}
function Sym.note_tier(d, key, before, after)
    if not (before and after) or Sym.word(before) == Sym.word(after) then
        return
    end
    local s = state(d)
    s.tier_news = s.tier_news or {}
    s.tier_news[key] = {from = s.tier_news[key] and s.tier_news[key].from or Sym.word(before), to = Sym.word(after)}
end

function Sym.tier_news(d)
    local s = state(d)
    if not (s and s.tier_news) then
        return
    end
    local news = {}
    for key, n in pairs(s.tier_news) do
        local planet = FindPlanet(key)
        if planet and n.from ~= n.to and (planet.Get_Owner() == d.human or Sym.visible(d, key)) then
            table.insert(news, {key = key, name = d:planet_name(planet), from = n.from, to = n.to})
        end
    end
    s.tier_news = nil
    if table.getn(news) == 0 then
        return
    end
    table.sort(news, function(a, b)
        return a.name < b.name
    end)
    if table.getn(news) <= 3 then
        for _, n in ipairs(news) do
            local rising = (n.to == "Sympathetic") or (n.to == "Wary" and n.from == "Hostile")
            d.show("Sympathy: " .. n.name .. " is " .. n.to .. " now (was " .. n.from .. "). "
                .. (rising and ("Its people warm to the " .. d.display_name("REBEL") .. ".") or "Its people are turning away."),
                nil, TIER_COLORS[n.to], 20)
        end
        return
    end
    local up, down = {}, {}
    for _, n in ipairs(news) do
        local rising = (n.to == "Sympathetic") or (n.to == "Wary" and n.from == "Hostile")
        table.insert(rising and up or down, n.name .. " (" .. n.to .. ")")
    end
    if up[1] then
        d.show("Sympathy rises on " .. table.getn(up) .. " worlds: " .. table.concat(up, ", ") .. ".", nil,
            TIER_COLORS.Sympathetic, 25)
    end
    if down[1] then
        d.show("Sympathy falls on " .. table.getn(down) .. " worlds: " .. table.concat(down, ", ") .. ".", nil,
            TIER_COLORS.Hostile, 25)
    end
end

function Sym.word(value)
    for _, w in ipairs(R.SYMPATHY_WORDS) do
        if value < w[1] then
            return w[2]
        end
    end
    return "Sympathetic"
end

local function jumps(d, key, planet)
    local s = state(d)
    local j = s.jumps[key]
    if not j or GetCurrentTime() - j.time > U.weeks(10) then
        if (s.budget or 0) <= 0 then
            return j and j.n or 99
        end
        s.budget = s.budget - 1
        j = {n = U.jumps(d, d.human, planet) or 99, time = GetCurrentTime()}
        s.jumps[key] = j
    end
    return j.n
end

function Sym.visible(d, key)
    local s = state(d)
    local planet = FindPlanet(key)
    if not (s and planet) then
        return false
    end
    if planet.Get_Owner() == d.human or jumps(d, key, planet) <= 1 then
        return true
    end
    local owner = planet.Get_Owner().Get_Faction_Name()
    if (s.survey[owner] or 0) > GetCurrentTime() then
        return true
    end
    local ok, Intel = pcall(require, "eawx-plugins/new-republic/RepublicIntel")
    return ok and Intel and Intel.tier(d, owner, key) >= 2
end

function Sym.trend(d, key)
    local s = state(d)
    return s and s.trend and s.trend[key] or 0
end

function Sym.band_color(value)
    if value < R.SYMPATHY_HOSTILE then
        return "red"
    elseif value < R.SYMPATHY_SYMPATHETIC then
        return "yellow"
    end
    return "green"
end

function Sym.describe(d, key)
    local v = Sym.value(d, key)
    if not v then
        return "None"
    end
    if Sym.visible(d, key) then
        return M.round(v) .. " (" .. Sym.word(v) .. ")"
    end
    return Sym.word(v)
end

local TIER_COLORS = {red = {r = 255, g = 70, b = 60}, yellow = {r = 255, g = 230, b = 70},
                     green = {r = 90, g = 255, b = 90}, grey = {r = 160, g = 160, b = 160}}
function Sym.patch_display(d)
    local C = rawget(_G, "PlanetInformationDisplayComponent")
    if type(C) ~= "table" or C.__sympathy_patched then
        return
    end
    local basic = C.render_basic_planet_information
    C.render_basic_planet_information = function(display, owner_name, color)
        basic(display, owner_name, color)
        pcall(function()
            if not (d.relations and d.relations[string.upper(owner_name or "")] == "PROTECTORATE") then
                return
            end
            local K = rawget(_G, "CONSTANTS") or ModContentLoader.get("GameConstants")
            local mine = K and K.FACTION_COLORS and K.FACTION_COLORS[d.human.Get_Faction_Name()]
                or {r = 150, g = 200, b = 255}
            local note = Engine_Glued_Text and "~ (Your Protectorate)" or "(Your Protectorate)"
            StoryUtil.ShowScreenText(note, -1, nil, mine, false)
            table.insert(display.current_text, note)
        end)
    end
    local original = C.render_influence_information
    C.render_influence_information = function(display, color)
        original(display, color)
        local ok, line, word, color = pcall(function()
            local planet = display.selected_planet and display.selected_planet:get_game_object()
            if not planet or (planet.Get_Owner() == d.human and not Sym.own_counted(d)) then
                return nil
            end
            local key = U.key(planet)
            local v = Sym.value(d, key)
            if not v then
                return "Sympathy:", "Unpopulated", TIER_COLORS.grey
            end
            return "Sympathy for the " .. (Sym.own_counted(d) and "Alliance" or "Republic") .. ":", Sym.describe(d, key),
                TIER_COLORS[Sym.band_color(v)]
        end)
        if ok and line then
            if Engine_Glued_Text then
                StoryUtil.ShowScreenText(line, -1, nil, {r = 150, g = 200, b = 255}, false)
                StoryUtil.ShowScreenText("~" .. word, -1, nil, color, false)
                table.insert(display.current_text, line)
                table.insert(display.current_text, "~" .. word)
            else
                line = line .. " " .. word
                StoryUtil.ShowScreenText(line, -1, nil, {r = 150, g = 200, b = 255}, false)
                table.insert(display.current_text, line)
            end
        end
    end
    C.__sympathy_patched = true
end

function Sym.offer_bonus(d, planet)
    if not planet then
        return 0
    end
    local v = Sym.value(d, U.key(planet))
    if v and v >= R.SYMPATHY_SYMPATHETIC then
        return M.round((v - R.SYMPATHY_SYMPATHETIC) / 4)
    end
    return 0
end

function Sym.protection_refused(d, planet)
    local v = planet and Sym.value(d, U.key(planet))
    if v and v < R.SYMPATHY_SYMPATHETIC then
        return "its people are not Sympathetic to the Republic (" .. Sym.describe(d, U.key(planet)) .. ")"
    end
    return nil
end

local liberation_target = false
function Sym.patch_liberation(d)
    local Mission = rawget(_G, "TakePlanetEnemyMission")
    local SU = rawget(_G, "StoryUtil")
    if type(Mission) ~= "table" or type(SU) ~= "table" or Mission.__sympathy_patched then
        return
    end
    Mission.__sympathy_patched = true
    local begin = Mission.Begin
    Mission.Begin = function(self, a, b, c)
        liberation_target = self.player == d.human
        local ok, err = pcall(begin, self, a, b, c)
        liberation_target = false
        if not ok then
            error(err)
        end
    end
    local find = SU.FindTargetPlanet
    SU.FindTargetPlanet = function(player, connected, fortress, amount, active_only, excluded, required)
        if not liberation_target then
            return find(player, connected, fortress, amount, active_only, excluded, required)
        end
        local list = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local owner = planet.Get_Owner()
            local key = U.key(planet)
            local v = Sym.value(d, key)
            if v and v >= R.SYMPATHY_SYMPATHETIC and owner ~= d.human and U.category(owner.Get_Faction_Name()) ~= "INDEPENDENT"
                    and owner.Get_Faction_Name() ~= "NEUTRAL" and not ours(d, planet)
                    and EvaluatePerception("Is_Owned_By_Enemy", player, planet) == 1
                    and d:relation(string.upper(owner.Get_Faction_Name())) == "WAR"
                    and EvaluatePerception("Is_Connected_To_Me", player, planet) == 1 then
                table.insert(list, planet)
            end
        end
        return U.pick(list)
    end
end

function Sym.liberation(d, key)
    local v = Sym.value(d, key)
    return v ~= nil and v >= R.SYMPATHY_LIBERATION
end

function Sym.rise(d, key, how, led)
    local planet = FindPlanet(key)
    if not planet or ours(d, planet) then
        return false
    end
    local ok, Rebellion = pcall(require, "eawx-plugins/diplomacy/DiplomacyRebellion")
    if not ok or not Rebellion or not Rebellion.uprising then
        return false
    end
    local ok2, rose = pcall(Rebellion.uprising, d, planet, led)
    if ok2 and rose then
        state(d).cells[key] = nil
        return true
    end
    return false
end

function Sym.preferred(d, key)
    local ok, Rebellion = pcall(require, "eawx-plugins/diplomacy/DiplomacyRebellion")
    return ok and Rebellion and Rebellion.preferred and Rebellion.preferred(d, key) or "INDEPENDENT_FORCES"
end

function Sym.join(d, key, how)
    local planet = FindPlanet(key)
    if not planet or ours(d, planet) then
        return false
    end
    d:transfer_world(planet, d.human, true)
    local r = d.republic
    r.conquered[key] = {time = GetCurrentTime(), free = false, content = true}
    r.counts = nil
    local s = state(d)
    s.cells[key], s.broadcast[key] = nil, nil
    d.show("Republic: " .. d:planet_name(planet) .. " " .. how .. " and joins the Republic. Build a Senator's Office "
        .. "there to give it a seat.", nil, COLOR, 25)
    return true
end

local function own_counted(d)
    local Republic = require("eawx-plugins/new-republic/Republic")
    return Republic.council(d)
end
Sym.own_counted = own_counted

function Sym.week(d)
    local s = state(d)
    if not s then
        return
    end
    s.budget = 30
    pcall(Sym.patch_liberation, d)
    local Republic = require("eawx-plugins/new-republic/Republic")
    local r = d.republic
    local Council = Republic.part("council")
    local decay = Council and Council.sympathy_decay(d) or 0
    local support = (Council and Council.focus(d) == "SUPPORT") and Council.CONFIG.SUPPORT_SYMPATHY or 0
    local count_own = own_counted(d)
    local rep = 1
    if DIPLOMACY_REPUTATION then
        local ok, rank = pcall(DIPLOMACY_REPUTATION, d.human.Get_Faction_Name())
        rep = ok and rank or 1
    end
    local court_unrest = 0
    if IMPERIAL_COURT_STABILITY then
        local ok, value = pcall(IMPERIAL_COURT_STABILITY)
        if ok and type(value) == "number" and value < 40 then
            court_unrest = R.SYMPATHY_COURT_UNREST
        end
    end
    local alarm = r.alarm and GetCurrentTime() - r.alarm < U.weeks(Republic.CONFIG.ALARM_WEEKS)
    s.trend = {}
    local pending = s.pending or {}
    s.pending = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local key = U.key(planet)
        if U.populated(key) and not territory(key) then
            local owner = planet.Get_Owner()
            local owner_name = owner.Get_Faction_Name()
            local own = owner == d.human
            local v = (count_own or not own) and Sym.value(d, key)
            if own and not count_own then
                s.value[key] = nil
            end
            if v then
                local n = own and 0 or jumps(d, key, planet)
                local target = start_value(d, key, owner_name)
                if n <= 2 then
                    target = target + M.min(R.SYMPATHY_NEAR_CAP, R.SYMPATHY_NEAR_MEMBER * (3 - n))
                end
                target = target + (R.SYMPATHY_REPUTATION[rep] or 0)
                if U.category(owner_name) == "IMPERIAL" then
                    target = target + court_unrest
                end
                if alarm and n <= 3 then
                    target = target - R.SYMPATHY_ALARM
                end
                if U.strength_at(owner, planet) > 5000 then
                    target = target - R.SYMPATHY_GARRISON
                end
                if v < target then
                    v = M.min(target, v + R.SYMPATHY_DRIFT)
                elseif v > target then
                    v = M.max(target, v - R.SYMPATHY_DRIFT)
                end
                if (s.broadcast[key] or 0) > GetCurrentTime() then
                    v = v + 2
                end
                if s.cells[key] then
                    v = v + 1
                end
                if own then
                    v = v + support
                end
                local before = Sym.value(d, key)
                s.value[key] = U.clamp(v - decay, 0, 100)
                s.trend[key] = s.value[key] - (before or s.value[key]) + (pending[key] or 0)
                Sym.note_tier(d, key, before, s.value[key])
                if not own and s.cells[key] and s.value[key] >= R.SYMPATHY_UPRISING and U.category(owner_name) ~= "INDEPENDENT"
                        and Sym.preferred(d, key) == string.upper(d.human.Get_Faction_Name())
                        and U.chance(R.SYMPATHY_RISE_CHANCE) then
                    Sym.rise(d, key, "rises against " .. d.display_name(owner_name), false)
                end
            end
        end
    end
end

function Sym.list(d, filter_owner)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local key = U.key(planet)
        if U.populated(key) and not territory(key) and not ours(d, planet) then
            local owner = planet.Get_Owner().Get_Faction_Name()
            if not filter_owner or owner == filter_owner then
                local v = Sym.value(d, key) or 0
                local visible = Sym.visible(d, key)
                local text = visible and (M.round(v) .. " (" .. Sym.word(v) .. ")") or Sym.word(v)
                table.insert(out, {key = key, name = d:planet_name(planet), owner = owner, value = v, visible = visible,
                                   text = text, cell = state(d).cells[key] == true})
            end
        end
    end
    table.sort(out, function(a, b)
        if a.visible ~= b.visible then
            return a.visible
        end
        return a.value > b.value
    end)
    return out
end

return Sym
