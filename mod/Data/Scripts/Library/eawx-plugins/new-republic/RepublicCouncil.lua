local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local Goals = require("eawx-plugins/diplomacy/DiplomacyGoals")

local Council = {}
local C = R.COUNCIL
Council.CONFIG = C
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}
local GOLD = {r = 255, g = 225, b = 140}

local BY_KEY = {}
for _, c in ipairs(C.COUNCILLORS) do
    BY_KEY[c.key] = c
end
Council.BY_KEY = BY_KEY

local function republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function cutscene(key, after)
    local ok, Cutscenes = pcall(require, "eawx-plugins/diplomacy/DiplomacyCutscenes")
    if ok and type(Cutscenes) == "table" then
        Cutscenes.play(key, nil, after)
    else
        after()
    end
end

local function senate_rules()
    return require("eawx-plugins/diplomacy/DiplomacyConfig").SENATE
end

local function start_year()
    local year = GlobalValue.Get("GC_START_YEAR")
    if type(year) ~= "number" then
        year = GlobalValue.Get("GALACTIC_YEAR") or 0
    end
    return year
end

function Council.state(d)
    local r = d.republic
    if not r then
        return nil
    end
    if not r.council then
        local founded = start_year() > C.LAST_YEAR
        local jedi = start_year() >= C.JEDI_YEAR
        r.council = {founded = founded, dead = {}, absent = {}, seen = {}, missions = {}, cooldown = {}, focus = nil,
                     focus_since = nil, levy_at = nil, liberated = {}, allied = {}, jedi = jedi,
                     jedi_at = (founded and not jedi) and GetCurrentTime() + U.weeks(C.JEDI_WEEKS) or nil,
                     jedi_start = jedi or nil}
        if not founded then
            r.mandate = C.MANDATE.START_BY_YEAR[start_year()] or C.MANDATE.START
        else
            r.corellia_ally_pending = true
        end
    end
    if r.corellia_ally_pending and d.relations then
        r.corellia_ally_pending = nil
        pcall(function()
            local corellia = Find_Player("CORELLIA")
            local holds = false
            for _, planet in pairs(FindPlanet.Get_All_Planets()) do
                if planet.Get_Owner() == corellia then
                    holds = true
                    break
                end
            end
            if corellia and holds and d:relation("CORELLIA") ~= "ALLIANCE" then
                d:set_relation("CORELLIA", "ALLIANCE", nil, true)
            end
        end)
    end
    return r.council
end

function Council.active(d)
    local c = d.republic and Council.state(d)
    return c ~= nil and not c.founded
end

function Council.founded(d)
    local c = d.republic and Council.state(d)
    return c == nil or c.founded == true
end

function Council.jedi_open(d)
    local c = d.republic and Council.state(d)
    return c == nil or c.jedi == true
end

local named = nil
local function set_name(text_id, value)
    if Engine_Set_Text then
        pcall(Engine_Set_Text, text_id, value)
    end
end

function Council.apply_names(d, force)
    local c = Council.state(d)
    if not c then
        return
    end
    local want = (c.founded and "founded") or (c.senate_seat and "senate") or "council"
    if named == want and not force then
        return
    end
    named = want
    local name = c.founded and C.FOUNDED_NAME or C.NAME
    if crossplot then
        pcall(crossplot.publish, crossplot, "FACTION_DISPLAY_NAME_CHANGE", "REBEL", name)
    end
    set_name("TEXT_FACTION_NEW_REPUBLIC", name)
    local capital = (c.founded or c.senate_seat) and C.FOUNDED_CAPITAL_NAME or C.CAPITAL_NAME
    set_name(C.CAPITAL_TEXT, capital)
    if Engine_Set_Object_Text then
        pcall(Engine_Set_Object_Text, C.CAPITAL, C.CAPITAL_TEXT, capital)
    end
end

local function opinion_entry(d, key)
    d.senate.opinion = d.senate.opinion or {}
    local o = d.senate.opinion[key]
    if not o then
        o = {value = BY_KEY[key] and BY_KEY[key].opinion or 0, events = {}}
        d.senate.opinion[key] = o
    end
    return o
end

function Council.opinion(d, key)
    if not d.senate then
        return BY_KEY[key] and BY_KEY[key].opinion or 0
    end
    return M.round(opinion_entry(d, key).value)
end

function Council.sway(d, key, amount, reason)
    if not d.senate or not BY_KEY[key] then
        return
    end
    opinion_entry(d, key)
    republic().senate.sway(d, key, amount, reason)
end

function Council.alive(d, key)
    local c = Council.state(d)
    return c ~= nil and not c.dead[key]
end

function Council.leader(d)
    local best = nil
    for _, c in ipairs(C.COUNCILLORS) do
        if c.lead and Council.alive(d, c.key) and (not best or c.lead < best.lead) then
            best = c
        end
    end
    return best or BY_KEY.MOTHMA
end

function Council.short(c)
    return c.short or c.name
end

function Council.seats(d)
    local out = {}
    for _, c in ipairs(C.COUNCILLORS) do
        if Council.alive(d, c.key) then
            out[c.key] = {name = c.key, councillor = c, opinion = Council.opinion(d, c.key), bloc = "Council",
                          weight = 1, base_opinion = Council.opinion(d, c.key), unrepresented = 0, founding = false,
                          founding_bonus = 0, planet = FindPlanet(c.world)}
        end
    end
    return out
end

local function has(c, interest)
    for _, i in ipairs(c.interests or {}) do
        if i == interest then
            return true
        end
    end
    return false
end

function Council.vote(d, key, motion)
    local c = BY_KEY[key]
    local debate = d.senate and d.senate.debate
    if debate and debate.motion == motion and debate.pressured[key] then
        return 1
    end
    local op = Council.opinion(d, key)
    if op >= senate_rules().LOYAL_OPINION then
        return 1
    elseif op <= senate_rules().HOSTILE_OPINION then
        return -1
    end
    local kind = U.category(motion.target or "")
    local vote = 0
    if motion.kind == "WAR" then
        if has(c, "Pacifist") then
            vote = -1
        elseif (kind == "IMPERIAL" or kind == "WARLORD") and (has(c, "Liberation") or has(c, "Security")) then
            vote = 1
        end
    elseif motion.kind == "TREATY" then
        if has(c, "Commerce") or has(c, "Pacifist") or (motion.relation == "ALLIANCE" and has(c, "Species rights")) then
            vote = 1
        elseif kind == "IMPERIAL" and has(c, "Liberation") then
            vote = -1
        end
    elseif motion.kind == "LEVY" then
        if has(c, "Security") or has(c, "Liberation") or has(c, "Industry") then
            vote = 1
        elseif has(c, "Commerce") or has(c, "Autonomy") or has(c, "Pacifist") then
            vote = -1
        end
    elseif motion.kind == "INVADE" then
        vote = (key == "ACKBAR" or key == "FEYLYA") and 0 or -1
    elseif motion.kind == "APPEAL" then
        if has(c, "Species rights") or has(c, "Pacifist") or has(c, "Liberation") or has(c, "Autonomy") then
            vote = 1
        end
    elseif motion.kind == "INTEL" then
        if has(c, "Security") or has(c, "Liberation") then
            vote = 1
        elseif has(c, "Commerce") then
            vote = -1
        end
    elseif motion.kind == "FOUND" then
        vote = (op >= -10) and 1 or 0
    end
    if vote == 0 and op >= 15 then
        vote = 1
    elseif vote == 0 and op <= -15 then
        vote = -1
    end
    return vote
end

function Council.tally(d, motion)
    local result = {yes = 0, no = 0, abstain = 0, blocs = {}, worlds = {}, weighed_yes = 0, weighed_no = 0}
    result.blocs.Council = {yes = 0, no = 0, abstain = 0}
    for key, _ in pairs(Council.seats(d)) do
        local vote = Council.vote(d, key, motion)
        result.worlds[key] = vote
        local slot = (vote > 0 and "yes") or (vote < 0 and "no") or "abstain"
        result[slot] = result[slot] + 1
        result.blocs.Council[slot] = result.blocs.Council[slot] + 1
    end
    result.weighed_yes, result.weighed_no = result.yes, result.no
    result.passed = result.yes >= result.no
    return result
end

function Council.vote_lines(d, key, motion)
    local c = BY_KEY[key]
    local o = opinion_entry(d, key)
    local lines = {Council.short(c) .. " of " .. Council.world_name(d, c) .. ". Opinion of the government: "
        .. Council.opinion(d, key) .. "."}
    for _, event in ipairs(o.events or {}) do
        table.insert(lines, "  " .. event .. ".")
    end
    local interests = table.concat(c.interests or {}, ", ")
    table.insert(lines, "Cares about: " .. interests .. ".")
    local ok_f, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
    local favour = ok_f and Favour.line(d, key)
    if favour then
        table.insert(lines, favour)
    end
    table.insert(lines, "Votes with the government at " .. senate_rules().LOYAL_OPINION .. " or more; against it at "
        .. senate_rules().HOSTILE_OPINION .. " or less.")
    if motion then
        local v = Council.vote(d, key, motion)
        table.insert(lines, (v > 0 and "Votes for.") or (v < 0 and "Votes against.") or "Abstains.")
    end
    return lines
end

function Council.world_name(d, c)
    local planet = FindPlanet(c.world)
    if planet then
        return d:planet_name(planet)
    end
    return d.tidy and d.tidy(c.world) or c.world
end

local function check_deaths(d)
    local c = Council.state(d)
    local Gov = republic().part("gov")
    for _, councillor in ipairs(C.COUNCILLORS) do
        local away = Gov and Gov.hero_in_office and Gov.hero_in_office(d, councillor.key)
        if councillor.units and not c.dead[councillor.key] and not away then
            local alive = false
            for _, t in ipairs(councillor.units) do
                local obj = Find_Object_Type(t) and Find_First_Object(t)
                if obj and TestValid(obj) then
                    alive = true
                end
            end
            if alive then
                c.seen[councillor.key], c.absent[councillor.key] = true, nil
            elseif c.seen[councillor.key] then
                c.absent[councillor.key] = (c.absent[councillor.key] or 0) + 1
                if c.absent[councillor.key] >= 2 then
                    Council.on_death(d, councillor)
                end
            end
        end
    end
end

function Council.on_death(d, councillor)
    local c = Council.state(d)
    local leader_before = Council.leader(d)
    c.dead[councillor.key] = true
    if d.senate and d.senate.opinion then
        d.senate.opinion[councillor.key] = nil
    end
    if c.founded then
        d.show("Republic: " .. councillor.name .. " is dead. The Republic mourns; their place in its government stands "
            .. "empty.", nil, WARN, 30)
        return
    end
    republic().change_mandate(d, -C.MANDATE.COUNCILLOR_KILLED)
    local text = "Council: " .. councillor.name .. " is dead. Their seat on the Council stands empty, and the galaxy "
        .. "wonders whether the Alliance can survive its losses. Mandate " .. republic().mandate(d) .. "."
    local leader = Council.leader(d)
    if leader ~= leader_before then
        text = text .. " " .. leader.name .. " now leads the Council."
        if leader.chief then
            pcall(GlobalValue.Set, "ChiefOfState", leader.chief)
        end
    end
    d.show(text, nil, WARN, 30)
end

function Council.pay_vote(d)
    if republic().spend(d, C.VOTE_CAPITAL) then
        return true
    end
    return false, "Every motion before the Council costs " .. C.VOTE_CAPITAL .. " political capital."
end

function Council.lobby(d, key)
    if not Council.alive(d, key) then
        return false, "That seat is empty."
    end
    local rules = senate_rules()
    local last = d.senate.lobbied[key]
    if last and GetCurrentTime() - last < U.weeks(rules.LOBBY_SEAT_WEEKS) then
        return false, "They were lobbied recently."
    end
    if not republic().spend(d, R.LOBBY_CAPITAL) then
        return false, "Not enough political capital (" .. R.LOBBY_CAPITAL .. ")."
    end
    d.senate.lobbied[key] = GetCurrentTime()
    Council.sway(d, key, rules.LOBBY_SEAT_OPINION, "you sought their counsel")
    return true, "Lobbied: opinion +" .. rules.LOBBY_SEAT_OPINION .. "."
end

local function base_income(d)
    local taxes = Engine_Taxes and Engine_Taxes()
    if type(taxes) == "number" then
        return M.round(M.min(M.max(M.sane(taxes), 0), 1000000))
    end
    local total = 0
    for _, w in ipairs(U.worlds_of(d.human)) do
        local ok, value = pcall(EvaluatePerception, "PlanetBaseIncome", d.human, w.planet)
        total = total + M.min(M.max(M.sane((ok and value) or 0), 0), 100000)
    end
    return M.round(total)
end
Council.base_income = base_income

function Council.sympathetic_worlds(d)
    local Sym = republic().part("sym")
    local n = 0
    for _, w in ipairs(U.worlds_of(d.human)) do
        local v = Sym and Sym.value(d, w.key)
        if v and v >= R.SYMPATHY_SYMPATHETIC then
            n = n + 1
        end
    end
    return n
end

function Council.capital_week(d)
    local support = (Council.focus(d) == "SUPPORT") and C.SUPPORT_CAPITAL or 0
    local favour = 0
    local ok, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
    if ok then
        favour = Favour.capital(d)
    end
    return M.max(0, C.CAPITAL_WEEK + M.floor(Council.sympathetic_worlds(d) / C.CAPITAL_PER_SYMPATHETIC) + support + favour)
end

function Council.levy_ready(d)
    return true
end

function Council.intel_places(d)
    local c = d.republic and Council.state(d)
    return c and c.intel_funded or 0
end

function Council.intel_ready(d)
    local c = Council.state(d)
    return (c.intel_funded or 0) < C.INTEL_MAX
        and (not c.intel_at or GetCurrentTime() - c.intel_at >= U.weeks(C.INTEL_WEEKS))
end

local capital_key

function Council.found_conditions(d)
    local missing = {}
    local coruscant = FindPlanet(C.SENATE_WORLD)
    if not coruscant then
        table.insert(missing, "there is no Coruscant in this region")
        return false, missing
    elseif coruscant.Get_Owner() ~= d.human then
        table.insert(missing, "hold Coruscant")
    elseif not Council.senate_built(d) then
        table.insert(missing, "build the New Republic Senate on Coruscant")
    end
    if republic().mandate(d) < 100 then
        table.insert(missing, "mandate 100 (now " .. republic().mandate(d) .. ")")
    end
    return missing[1] == nil, missing
end

function Council.senate_built(d)
    for _, type_name in ipairs({C.CAPITAL, C.SENATE_BUILDING}) do
        local t = Find_Object_Type(type_name)
        for _, obj in pairs(t and Find_All_Objects_Of_Type(t) or {}) do
            if TestValid(obj) and obj.Get_Owner() == d.human then
                local at = obj.Get_Planet_Location()
                if at and U.key(at) == C.SENATE_WORLD then
                    return true
                end
            end
        end
    end
    return false
end

local border_worlds

function Council.sanctioned(d, key)
    local c = d.republic and Council.state(d)
    return c ~= nil and c.sanctioned ~= nil and c.sanctioned[key] ~= nil and GetCurrentTime() < c.sanctioned[key]
end

function Council.motions(d)
    local out = {}
    local c = Council.state(d)
    if c.choosing then
        return out
    end
    if Council.levy_ready(d) then
        local credits = M.round(base_income(d) * C.LEVY_SHARE)
        table.insert(out, {kind = "LEVY", text = "raise a war levy", label = "War Levy",
            tip = "Every world held pays a full week's base income once (about " .. credits .. " credits now). Costs "
                .. C.LEVY_CAPITAL .. " political capital; sympathy on your worlds -" .. C.LEVY_SYMPATHY .. "."})
    end
    if Council.intel_ready(d) then
        local poor = d.human.Get_Credits() < C.INTEL_CREDITS
        table.insert(out, {kind = "INTEL", text = "fund intelligence operations", label = "Fund Intelligence",
            disabled = poor,
            tip = "Alliance Intelligence gets one more agent place (" .. Council.intel_places(d) .. " of " .. C.INTEL_MAX
                .. " funded so far). Costs " .. C.INTEL_CREDITS .. " credits. Once in " .. C.INTEL_WEEKS .. " weeks."
                .. (poor and (" The treasury can't pay for it now (" .. C.INTEL_CREDITS .. " credits).") or "")})
    end
    for _, w in ipairs(border_worlds(d)) do
        local sanctioned = c.sanctioned and c.sanctioned[w.key] and GetCurrentTime() < c.sanctioned[w.key]
        if w.independent and not sanctioned then
            local world = d:planet_name(w.planet)
            table.insert(out, {kind = "INVADE", target = "INDEPENDENT_FORCES", world = w.key, group = "WAR",
                text = "declare war on " .. world, label = world .. " (independent)",
                tip = "Make war on " .. world .. ", a free world on the border. Sanctioned, the invasion costs no "
                    .. "reputation for " .. C.INVADE_WEEKS .. " weeks; its people's sympathy still counts, and most "
                    .. "Councillors dislike it (opinion -" .. C.INVADE_OPINION .. " from those who care for peace and "
                    .. "the free worlds)."})
        end
    end
    for key, appeal in pairs(d.appeals or {}) do
        local planet = FindPlanet(key)
        if planet and not appeal.approved and GetCurrentTime() < appeal.expires then
            local world = d:planet_name(planet)
            table.insert(out, {kind = "APPEAL", target = key, text = "approve " .. world .. "'s petition",
                label = "Approve " .. world .. "'s Petition",
                tip = "The people of " .. world .. " ask to join the Alliance. If the Council approves, the world "
                    .. "takes the Alliance's protection at once (mandate +" .. C.APPEAL_MANDATE .. ")."})
        end
    end
    local ok, missing = Council.found_conditions(d)
    local coruscant = FindPlanet(C.SENATE_WORLD)
    if coruscant and coruscant.Get_Owner() == d.human then
        table.insert(out, {kind = "FOUND", text = "found the New Republic", label = "Found the New Republic",
            target = "REBEL", disabled = not ok,
            tip = "The Alliance becomes the New Republic: the Councillors give up their seats, the Senate convenes, and "
                .. "you choose its constitution." .. (ok and "" or (" Not yet: " .. table.concat(missing, "; ")
                .. "."))})
    end
    return out
end

function Council.enact(d, motion)
    if motion.kind == "LEVY" then
        local c = Council.state(d)
        c.levy_at = GetCurrentTime()
        local credits = M.round(base_income(d) * C.LEVY_SHARE)
        republic().spend(d, M.min(C.LEVY_CAPITAL, republic().capital(d)))
        d.human.Give_Money(credits)
        local Sym = republic().part("sym")
        for _, w in ipairs(U.worlds_of(d.human)) do
            if Sym then
                Sym.change(d, w.key, -C.LEVY_SYMPATHY)
            end
        end
        d.show("Council: the war levy is raised: " .. credits .. " credits. The worlds that paid it resent the Alliance "
            .. "a little more.", nil, COLOR, 20)
    elseif motion.kind == "INTEL" then
        local c = Council.state(d)
        if d.human.Get_Credits() < C.INTEL_CREDITS then
            d.show("Council: the treasury cannot pay for more agents (" .. C.INTEL_CREDITS .. " credits).", nil, WARN, 20)
            return
        end
        d.human.Give_Money(-C.INTEL_CREDITS)
        c.intel_funded, c.intel_at = (c.intel_funded or 0) + 1, GetCurrentTime()
        d.show(Council.active(d) and "Council: intelligence operations are funded. Alliance Intelligence can run one "
            .. "more agent." or "Senate: intelligence operations are funded. Republic Intelligence can run one more "
            .. "agent.", nil, COLOR, 20)
    elseif motion.kind == "INVADE" then
        local c = Council.state(d)
        c.sanctioned = c.sanctioned or {}
        c.sanctioned[motion.world] = GetCurrentTime() + U.weeks(C.INVADE_WEEKS)
        for _, councillor in ipairs(C.COUNCILLORS) do
            if has(councillor, "Pacifist") or has(councillor, "Species rights") or has(councillor, "Autonomy") then
                Council.sway(d, councillor.key, -C.INVADE_OPINION, "you made war on a free world")
            end
        end
        local planet = FindPlanet(motion.world)
        d.show("Council: the Councillors sanction the invasion of " .. (planet and d:planet_name(planet) or motion.world)
            .. ". Some of them will not forget it.", nil, WARN, 20)
    elseif motion.kind == "APPEAL" then
        local appeal = d.appeals and d.appeals[motion.target]
        local planet = FindPlanet(motion.target)
        if appeal and planet then
            appeal.approved = true
            d.show("Council: the Councillors approve " .. d:planet_name(planet) .. "'s petition.", nil, COLOR, 20)
            local P = republic().part("prot")
            if not (P and P.protect_world(d, planet, d:planet_name(planet))) then
                pcall(function() require("eawx-plugins/diplomacy/DiplomacyMissions").show_appeals(d) end)
                d.show("Council: offer " .. d:planet_name(planet) .. " the Alliance's protection in the Diplomacy "
                    .. "window once a place is free.", nil, COLOR, 20)
            end
        end
    elseif motion.kind == "FOUND" then
        if motion.constitution and Council.found(d, motion.constitution) then
            return
        end
        Council.state(d).choosing = true
        d.show("Council: the Councillors vote to found the New Republic. Choose its constitution in the Council window.",
            nil, GOLD, 30)
    end
end

function Council.focus(d)
    local c = d.republic and Council.state(d)
    if c and c.focus and c.focus_until and GetCurrentTime() >= c.focus_until then
        c.focus, c.focus_until = nil, nil
        d.show("Council: the Crusade to Coruscant has run its course. Choose the Council's next focus.", nil, COLOR, 20)
    end
    return c and not c.founded and c.focus or nil
end

function Council.focus_open(d, key)
    local c = Council.state(d)
    return not (C.FOCUS[key] and C.FOCUS[key].once and c.used_focus and c.used_focus[key])
end

function Council.focus_weeks_left(d)
    local c = Council.state(d)
    if not c.focus_since then
        return 0
    end
    return M.max(0, C.FOCUS_WEEKS - U.weeks_since(c.focus_since))
end

function Council.set_focus(d, key)
    local c = Council.state(d)
    if not C.FOCUS[key] or c.founded then
        return false, "No such focus."
    end
    if c.focus == key then
        return false, "The Council's focus is already " .. C.FOCUS[key].name .. "."
    end
    if not Council.focus_open(d, key) then
        return false, C.FOCUS[key].name .. " can be called only once."
    end
    local left = Council.focus_weeks_left(d)
    if c.focus and left > 0 then
        return false, "The Council can change its focus in " .. left .. " week(s)."
    end
    if not republic().spend(d, C.FOCUS_CAPITAL) then
        return false, "Setting the Council's focus takes " .. C.FOCUS_CAPITAL .. " political capital."
    end
    c.focus, c.focus_since = key, GetCurrentTime()
    c.focus_until = C.FOCUS[key].weeks and (GetCurrentTime() + U.weeks(C.FOCUS[key].weeks)) or nil
    if C.FOCUS[key].once then
        c.used_focus = c.used_focus or {}
        c.used_focus[key] = true
    end
    for _, who in ipairs(C.FOCUS[key].favoured_by or {}) do
        Council.sway(d, who, C.FOCUS_OPINION, "the Council's focus: " .. C.FOCUS[key].name)
    end
    Council.keep_dummies(d)
    return true, "The Council's focus: " .. C.FOCUS[key].name .. "."
end

function Council.keep_dummies(d)
    local c = Council.state(d)
    local wanted = {}
    local fleet = C.FOCUS.FLEET.dummy
    local Gov = republic().part("gov")
    wanted[fleet] = (not c.founded and c.focus == "FLEET") or (c.founded and Gov ~= nil and Gov.agenda(d) == "FLEET")
    wanted.Constitution_Endures = c.founded and c.constitution == "ENDURES"
        and GetCurrentTime() < (c.endures_until or 0)
    for type_name, want in pairs(wanted) do
        local t = Find_Object_Type(type_name)
        if t then
            local have = {}
            for _, obj in pairs(Find_All_Objects_Of_Type(t) or {}) do
                if TestValid(obj) then
                    local at = obj.Get_Planet_Location()
                    if want and at and obj.Get_Owner() == d.human and at.Get_Owner() == d.human and not have[U.key(at)] then
                        have[U.key(at)] = true
                    else
                        obj.Despawn()
                    end
                end
            end
            if want then
                for _, w in ipairs(U.worlds_of(d.human)) do
                    if not have[w.key] then
                        pcall(Spawn_Unit, t, w.planet, d.human)
                    end
                end
            end
        end
    end
end

local function influence()
    return republic().part("influence")
end

function Council.add_influence(d, key, amount)
    local I = influence()
    if I then
        I.add(d, key, amount)
    end
end

function Council.influence_week(d)
    local I = influence()
    if I then
        local ok, err = pcall(I.week, d)
        if not ok and Engine_Log then
            Engine_Log("COUNCIL influence: " .. tostring(err))
        end
    end
end

local function relation(d, faction)
    return d.relations and d:relation(faction) or "WAR"
end

local corellia_open

function corellia_open(d)
    local FACTIONS = require("eawx-plugins/diplomacy/DiplomacyFactions")
    if not (FACTIONS.PLAYABLE and FACTIONS.PLAYABLE[C.CORELLIA]) then
        return false
    end
    local player = Find_Player(C.CORELLIA)
    if not player or player == d.human then
        return false
    end
    for _ in ipairs(U.worlds_of(player)) do
        return relation(d, C.CORELLIA) ~= "ALLIANCE" and relation(d, C.CORELLIA) ~= "PROTECTORATE"
    end
    return false
end

Council.corellia_open = corellia_open

function border_worlds(d)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local key = U.key(planet)
        local owner = planet.Get_Owner()
        if owner ~= d.human and U.populated(key) and not republic().is_territory(key)
                and owner.Get_Faction_Name() ~= "NEUTRAL" and not (d.vassal_worlds and d.vassal_worlds[key]) then
            local n = U.jumps(d, d.human, planet)
            if n and n <= 1 then
                table.insert(out, {key = key, planet = planet,
                                   independent = U.category(owner.Get_Faction_Name()) == "INDEPENDENT"})
            end
        end
    end
    return out
end

local function choose_mission(d, councillor)
    local home = FindPlanet(councillor.world)
    local options = {}
    if home and home.Get_Owner() ~= d.human and U.populated(councillor.world)
            and not (d.vassal_worlds and d.vassal_worlds[councillor.world]) then
        local kind = U.category(home.Get_Owner().Get_Faction_Name())
        if kind == "IMPERIAL" or kind == "WARLORD" then
            return {kind = "LIBERATE", world = councillor.world}
        elseif kind == "INDEPENDENT" then
            table.insert(options, {kind = "PROTECT", world = councillor.world})
        end
    end
    if councillor.key == "BERUSS" and corellia_open(d) then
        table.insert(options, {kind = "CORELLIA", target = C.CORELLIA})
    end
    local Sym = republic().part("sym")
    local sympathy, protect = {}, {}
    for _, w in ipairs(border_worlds(d)) do
        local v = Sym and Sym.value(d, w.key)
        if v and v < R.SYMPATHY_SYMPATHETIC and v >= R.SYMPATHY_SYMPATHETIC - 30 then
            table.insert(sympathy, w.key)
        end
        if w.independent then
            table.insert(protect, w.key)
        end
    end
    if sympathy[1] then
        table.insert(options, {kind = "SYMPATHY", world = U.pick(sympathy)})
    end
    if protect[1] then
        table.insert(options, {kind = "PROTECT", world = U.pick(protect)})
    end
    return U.pick(options)
end

local function world_label(d, key)
    local planet = FindPlanet(key)
    return planet and d:planet_name(planet) or key
end

function Council.mission_text(d, councillor, m)
    local who = Council.short(councillor)
    local world = m.world and world_label(d, m.world)
    if m.kind == "LIBERATE" then
        return "Liberate " .. world, {
            who .. " asks the Alliance to free " .. world .. ", their home, and pays for the campaign.",
            "Take " .. world .. " within " .. C.MISSION_WEEKS .. " weeks."}
    elseif m.kind == "SYMPATHY" then
        return "Win Over " .. world, {
            who .. " funds a campaign of hearts and minds on " .. world .. ", at the Alliance's border.",
            "Bring its people to Sympathetic within " .. C.MISSION_WEEKS .. " weeks: Delegates, broadcasts, aid."}
    elseif m.kind == "PROTECT" then
        return "Protect " .. world, {
            who .. " wants the free world of " .. world .. " under the Alliance's shield before the warlords take it.",
            "Make it a protectorate within " .. C.MISSION_WEEKS .. " weeks (it must be Sympathetic to accept)."}
    end
    return "Ally With Corellia", {
        "Doman Beruss still has friends in the Corellian government, and she means to use them.",
        "While this mission lasts, Corellia is more willing to ally with the Alliance (+" .. C.CORELLIA_BONUS .. ").",
        "If Corellia is our ally when the New Republic is founded, it will join it as a protectorate.",
        "Sign an alliance with Corellia within " .. C.MISSION_WEEKS .. " weeks."}
end

function Council.can_request(d, key)
    local c = Council.state(d)
    if not Council.alive(d, key) then
        return false, "That seat is empty."
    end
    for _, m in pairs(c.missions) do
        return false, "Finish the open mission first: " .. (m.title or "a Councillor's request") .. "."
    end
    local ready = c.cooldown[key]
    if ready and GetCurrentTime() < ready then
        return false, "They can't spare more for " .. M.ceil((ready - GetCurrentTime()) / U.weeks(1)) .. " week(s)."
    end
    return true
end

function Council.request(d, key)
    local ok, why = Council.can_request(d, key)
    if not ok then
        return false, why
    end
    local councillor = BY_KEY[key]
    local m = choose_mission(d, councillor)
    if not m then
        return false, Council.short(councillor) .. " has nothing to fund right now."
    end
    local standing = U.clamp((Council.opinion(d, key) + 100) / 200, 0, 1)
    m.credits = M.round((C.FUND_MIN + (C.FUND_MAX - C.FUND_MIN) * standing) / 100) * 100
    m.expires = GetCurrentTime() + U.weeks(C.MISSION_WEEKS)
    local title, lines = Council.mission_text(d, councillor, m)
    m.title = Council.short(councillor) .. ": " .. title
    local now = M.round(m.credits / 2)
    m.rest = m.credits - now
    table.insert(lines, "Funding: " .. now .. " credits now, " .. m.rest .. " more when it is done. Done: mandate +"
        .. C.MANDATE.MISSION_DONE .. ", Galactic Influence +" .. C.INFLUENCE.MISSION .. ". Failed: mandate -"
        .. C.MANDATE.MISSION_FAILED .. ".")
    m.goal = Goals.add(d, m.title, lines, m.expires)
    Council.state(d).missions[key] = m
    d.human.Give_Money(now)
    return true, "Funded: +" .. now .. " credits now, " .. m.rest .. " on completion."
end

local function mission_done(d, m)
    if m.kind == "LIBERATE" then
        local planet = FindPlanet(m.world)
        return planet ~= nil and planet.Get_Owner() == d.human
    elseif m.kind == "SYMPATHY" then
        local Sym = republic().part("sym")
        local v = Sym and Sym.value(d, m.world)
        return v ~= nil and v >= R.SYMPATHY_SYMPATHETIC
    elseif m.kind == "PROTECT" then
        return d.vassal_worlds ~= nil and d.vassal_worlds[m.world] ~= nil
    elseif m.kind == "CORELLIA" then
        local rel = relation(d, C.CORELLIA)
        return rel == "ALLIANCE" or rel == "PROTECTORATE"
    end
    return false
end

local function check_missions(d)
    local c = Council.state(d)
    for key, m in pairs(c.missions) do
        local councillor = BY_KEY[key]
        if c.dead[key] then
            c.missions[key] = nil
            Goals.remove(d, m.goal)
        elseif mission_done(d, m) then
            c.missions[key] = nil
            Goals.remove(d, m.goal)
            c.cooldown[key] = GetCurrentTime() + U.weeks(C.COOLDOWN_WEEKS)
            republic().change_mandate(d, C.MANDATE.MISSION_DONE)
            local r = d.republic
            r.capital = M.min(R.CAPITAL_MAX, r.capital + C.MISSION_CAPITAL)
            Council.sway(d, key, C.MISSION_DONE_OPINION, "you did what they asked")
            if m.rest and m.rest > 0 then
                d.human.Give_Money(m.rest)
            end
            Council.add_influence(d, key, C.INFLUENCE.MISSION)
            d.show("Council: " .. m.title .. ", done. " .. Council.short(councillor) .. " is pleased"
                .. ((m.rest and m.rest > 0) and (" and pays the rest: " .. m.rest .. " credits") or "") .. ". Mandate "
                .. republic().mandate(d) .. ".", nil, COLOR, 20)
        elseif GetCurrentTime() >= m.expires then
            c.missions[key] = nil
            Goals.remove(d, m.goal)
            c.cooldown[key] = GetCurrentTime() + U.weeks(2 * C.COOLDOWN_WEEKS)
            republic().change_mandate(d, -C.MANDATE.MISSION_FAILED)
            Council.sway(d, key, -C.MISSION_FAILED_OPINION, "you took their credits and failed them")
            d.show("Council: " .. m.title .. ", failed. " .. Council.short(councillor) .. " won't fund the Alliance "
                .. "again for a while. Mandate " .. republic().mandate(d) .. ".", nil, WARN, 20)
        end
    end
end

function Council.alliance_bonus(d, faction)
    local c = d.republic and Council.state(d)
    local m = c and not c.founded and c.missions.BERUSS
    if m and m.kind == "CORELLIA" and faction == C.CORELLIA then
        return C.CORELLIA_BONUS
    end
    return 0
end

function Council.acceptance(d, treaty)
    if not Council.active(d) then
        return 0
    end
    local missing = 100 - republic().mandate(d)
    if missing <= 0 then
        return 0
    end
    return -M.round(missing * (treaty and C.ACCEPT_TREATY or C.ACCEPT_OTHER))
end

function Council.on_relation(d, faction, rel)
    local ok_f, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
    if ok_f then
        local kind = U.category(faction)
        local deed = (rel == "WAR" and ((kind == "IMPERIAL" or kind == "WARLORD") and "WAR_IMPERIAL" or "WAR"))
            or (rel == "CEASEFIRE" and "PEACE") or (rel == "ALLIANCE" and "ALLIANCE") or nil
        if deed then
            pcall(Favour.deed, d, deed)
        end
    end
    local c = d.republic and Council.state(d)
    if c and not c.founded and rel == "ALLIANCE" and not c.allied[faction] then
        c.allied[faction] = true
        republic().change_mandate(d, C.MANDATE.ALLIANCE)
        d.show("Council: the alliance with " .. d.display_name(faction) .. " shows the galaxy the Alliance is a "
            .. "government, not a rebellion. Mandate " .. republic().mandate(d) .. ".", nil, COLOR, 20)
    end
end

function Council.on_revolt(d, key)
    if Council.active(d) then
        republic().change_mandate(d, -C.MANDATE.REVOLT)
    end
end

function Council.on_world_lost(d, key)
    if not Council.active(d) then
        return
    end
    local ok_f, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
    if ok_f and U.populated(key) then
        pcall(Favour.deed, d, "LOST")
    end
    local state = Council.state(d)
    state.losses = state.losses or {}
    table.insert(state.losses, GetCurrentTime())
    if U.populated(key) and not republic().is_territory(key) then
        republic().change_mandate(d, -C.MANDATE.WORLD_LOST)
    end
    for _, c in ipairs(C.COUNCILLORS) do
        if c.world == key then
            Council.sway(d, c.key, -C.HOME_LOST_OPINION, "the Alliance lost their home world")
        end
    end
end

function Council.occupy_cost(band, old_owner)
    local base = R.OCCUPY_COSTS[band]
    if not base then
        return nil
    end
    local kind = U.category(old_owner or "")
    local mult = R.OCCUPY_COSTS.MULT[(kind == "IMPERIAL" or kind == "WARLORD") and "IMPERIAL" or "OTHER"]
    local cost = {}
    for k, v in pairs(base) do
        cost[k] = v * mult
    end
    return cost
end

local function occupation_costs(d, key, band, spared, old_owner)
    local cost = Council.occupy_cost(band, old_owner)
    if not cost then
        return
    end
    local Senate = republic().senate
    if d.senate and Senate and Senate.sway then
        pcall(Senate.sway, d, key, -cost.joined, "occupied against its people's will")
    end
    if spared then
        return
    end
    d.memory.occupation_marks = d.memory.occupation_marks or {}
    table.insert(d.memory.occupation_marks, {time = GetCurrentTime(), value = -cost.independents})
    local Sym = republic().part("sym")
    if Sym then
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local k = U.key(planet)
            if k ~= key and Sym.value(d, k) then
                Sym.change(d, k, -cost.sympathy)
            end
        end
    end
    if Council.state(d).founded and d.senate and not Council.active(d) then
        d.senate.stability = M.max(0, d.senate.stability - cost.cohesion)
    end
end

function Council.on_conquest(d, key, readable, old_owner, value)
    local c = Council.state(d)
    local band = "WARY"
    if value then
        band = (value < R.SYMPATHY_HOSTILE and "HOSTILE") or (value >= R.SYMPATHY_SYMPATHETIC and "SYMPATHETIC") or "WARY"
    end
    local kind = U.category(old_owner)
    local independent = kind == "INDEPENDENT"
    local crusade = Council.focus(d) == "CRUSADE" and (kind == "IMPERIAL" or kind == "WARLORD")
    local Focus = republic().part("focus")
    local hunt = c.founded and Focus ~= nil and Focus.hunting(d, old_owner)
    if hunt then
        Focus.hunted(d, key, band)
    end
    local free_of_cost = crusade or hunt
    local Sym = republic().part("sym")
    if band == "HOSTILE" then
        if not c.founded then
            republic().change_mandate(d, -(crusade and C.MANDATE.WARY_INVASION or C.MANDATE.HOSTILE_INVASION))
            if not free_of_cost then
                for _, councillor in ipairs(C.COUNCILLORS) do
                    Council.sway(d, councillor.key, -C.HOSTILE_INVASION_OPINION, "you invaded " .. readable
                        .. " against its people's will")
                end
            end
        end
        occupation_costs(d, key, band, free_of_cost, old_owner)
        if c.founded then
            d.show("The people of " .. readable .. " never wanted us. The galaxy calls it a conquest.", nil, WARN, 20)
        end
    elseif band == "WARY" then
        if not c.founded then
            republic().change_mandate(d, -C.MANDATE.WARY_INVASION)
        end
        occupation_costs(d, key, band, free_of_cost, old_owner)
    else
        if not c.founded and not c.liberated[key] and not independent then
            c.liberated[key] = true
            republic().change_mandate(d, C.MANDATE.LIBERATED)
        end
        Council.welcome(d, key, readable)
    end
    local ok_f, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
    if ok_f then
        if band == "HOSTILE" then
            pcall(Favour.deed, d, "OCCUPY_HOSTILE")
        elseif band == "WARY" then
            pcall(Favour.deed, d, "OCCUPY_WARY")
        end
        if kind == "IMPERIAL" or kind == "WARLORD" then
            pcall(Favour.deed, d, "IMPERIAL_TAKEN")
        end
    end
    if not c.founded and band ~= "SYMPATHETIC" then
        Council.invasion_text(d, band, readable, old_owner)
    end
    Council.home_freed(d, key)
    return band
end

function Council.home_freed(d, key)
    if not Council.active(d) or Council.state(d).founded then
        return
    end
    for _, councillor in ipairs(C.COUNCILLORS) do
        if councillor.world == key then
            Council.sway(d, councillor.key, C.HOME_FREED_OPINION, "you freed their home world")
        end
    end
end

function Council.invasion_text(d, band, readable, old_owner)
    local T = C.INVASION_TEXT[band]
    if not T then
        return
    end
    local function fill(text)
        text = string.gsub(text, "{world}", readable)
        return (string.gsub(text, "{owner}", d.display_name(old_owner or "")))
    end
    local lines = {fill(U.pick(T.lines))}
    local tail = band ~= "TERRITORY" and C.INVASION_TEXT.OWNER[U.category(old_owner)]
    if tail then
        table.insert(lines, "")
        table.insert(lines, fill(tail))
    end
    table.insert(lines, "")
    table.insert(lines, "Mandate " .. republic().mandate(d) .. ".")
    pcall(M.show_document, lines, T.title .. ": " .. readable, d.display_name("REBEL"))
end

function Council.welcome(d, key, readable)
    local planet = FindPlanet(key)
    if not planet then
        return
    end
    local ok, Grants = pcall(require, "eawx-plugins/diplomacy/DiplomacyGrants")
    local joined = 0
    if ok and Grants then
        local types = {}
        for _ = 1, 3 do
            for _, t in ipairs(Grants.for_world(key) or {}) do
                if not string.find(string.upper(t.Get_Name()), "DROID", 1, true) then
                    table.insert(types, t)
                end
            end
        end
        local n = M.min(GameRandom.Free_Random(1, C.WELCOME_UNITS), table.getn(types))
        for i = 1, n do
            if pcall(Spawn_Unit, types[i], planet, d.human) then
                joined = joined + 1
            end
        end
    end
    d.show("Crowds line the streets of " .. readable .. " to cheer the " .. d.display_name("REBEL") .. "'s troops as "
        .. "liberators." .. (joined > 0 and " Some of its own defenders take up arms beside them." or ""), nil, GOLD, 25)
end

local lock_temple
local seed_opinion

function Council.patience_weeks(d)
    if not FindPlanet(C.SENATE_WORLD) then
        return nil
    end
    local year = GlobalValue.Get("GALACTIC_YEAR") or 0
    local month = GlobalValue.Get("GALACTIC_MONTH") or 1
    return (C.PATIENCE_YEAR - year) * C.WEEKS_PER_YEAR - (month - 1)
end

function Council.cohesion_penalties(d)
    local c = Council.state(d)
    local lost, keep = 0, {}
    for _, at in ipairs(c.losses or {}) do
        local left = C.LOST_COHESION - U.weeks_since(at)
        if left > 0 then
            lost = lost + left
            table.insert(keep, at)
        end
    end
    c.losses = keep
    return lost, c.mandate_drag or 0
end

local function mandate_drag_week(d)
    local c = Council.state(d)
    local m = republic().mandate(d)
    if m < C.LOW_MANDATE then
        c.mandate_drag = (c.mandate_drag or 0) + M.ceil((C.LOW_MANDATE - m) / C.LOW_MANDATE_STEP)
    else
        c.mandate_drag = M.max(0, (c.mandate_drag or 0) - 1)
    end
end

function Council.cohesion(d)
    local lost, drag = Council.cohesion_penalties(d)
    return M.max(0, Council.base_cohesion(d) - lost - drag)
end

function Council.base_cohesion(d)
    local Sym = republic().part("sym")
    if not Sym then
        return 50
    end
    local total, weight = 0, 0
    for _, w in ipairs(U.worlds_of(d.human)) do
        local v = Sym.value(d, w.key)
        if v then
            local n = (v < R.SYMPATHY_HOSTILE) and 2 or 1
            total, weight = total + v * n, weight + n
        end
    end
    local I = influence()
    local bonus = I and I.cohesion_bonus(d) or 0
    if weight == 0 then
        return M.min(100, 50 + bonus)
    end
    return M.min(100, M.round(total / weight) + bonus)
end

function capital_key(d)
    local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
    local ok, planet = pcall(Deals.capital, d, d.human)
    return ok and planet and U.key(planet) or nil
end

local function risings(d)
    local Sym = republic().part("sym")
    local Rebellion = require("eawx-plugins/diplomacy/DiplomacyRebellion")
    if not (Sym and Rebellion.rise_own) then
        return
    end
    local capital = capital_key(d)
    if republic().mandate(d) <= 0 then
        for _, w in ipairs(U.worlds_of(d.human)) do
            if w.key ~= capital and Sym.value(d, w.key) and U.chance(C.ZERO_RISE_CHANCE) then
                pcall(Rebellion.rise_own, d, w.planet)
            end
        end
        return
    end
    if d.senate.stability >= C.RISE_COHESION or not U.chance(C.RISE_CHANCE) then
        return
    end
    local worst, low = nil, nil
    for _, w in ipairs(U.worlds_of(d.human)) do
        local v = Sym.value(d, w.key)
        if v and w.key ~= capital and (not low or v < low) then
            worst, low = w, v
        end
    end
    if worst then
        pcall(Rebellion.rise_own, d, worst.planet)
    end
end

function Council.week(d)
    local c = Council.state(d)
    if not c then
        return
    end
    if not c.founded then
        c.senate_seat = Council.senate_built(d) or nil
    end
    Council.apply_names(d)
    lock_temple(d)
    pcall(seed_opinion, d)
    if c.founded then
        Council.week_founded(d)
        return
    end
    pcall(check_deaths, d)
    check_missions(d)
    mandate_drag_week(d)
    local r = d.republic
    r.capital = M.min(R.CAPITAL_MAX, r.capital + Council.capital_week(d))
    Council.influence_week(d)
    local ok_f, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
    if ok_f then
        pcall(Favour.week, d)
    end
    c.withheld = base_income(d)
    local withheld = M.min(c.withheld, M.max(0, d.human.Get_Credits()))
    if withheld > 0 then
        d.human.Give_Money(-withheld)
    end
    local left = Council.patience_weeks(d)
    if left and left <= 0 then
        republic().change_mandate(d, -C.PATIENCE_MANDATE)
        if left == 0 then
            d.show("Council: 7 ABY, and still no Republic. The galaxy demands a voice in its government: take Coruscant "
                .. "and found the Senate. Until then sympathy falls everywhere.", nil, WARN, 30)
        end
    end
    if d.senate then
        d.senate.stability = Council.cohesion(d)
        risings(d)
    end
    Council.keep_dummies(d)
end

function Council.sympathy_decay(d)
    if not Council.active(d) then
        return 0
    end
    local decay = 0
    local m = republic().mandate(d)
    if m < C.DECAY_BELOW then
        decay = decay + (C.DECAY_BELOW - m) / C.DECAY_STEP
    end
    local left = Council.patience_weeks(d)
    if left and left < 0 then
        local year = M.min(table.getn(C.PATIENCE_DECAY), M.floor(-left / C.WEEKS_PER_YEAR) + 1)
        decay = decay + C.PATIENCE_DECAY[year]
    end
    return decay
end

function Council.on_senate_built(d, planet)
    if not planet or U.key(planet) ~= C.SENATE_WORLD then
        return
    end
    local t = Find_Object_Type(C.CAPITAL)
    if not t then
        return
    end
    local built = Find_Object_Type(C.SENATE_BUILDING)
    for _, obj in pairs(built and Find_All_Objects_Of_Type(built) or {}) do
        if TestValid(obj) and obj.Get_Owner() == d.human then
            obj.Despawn()
        end
    end
    local c = Council.state(d)
    if c then
        c.senate_seat = true
    end
    local here = false
    for _, obj in pairs(Find_All_Objects_Of_Type(t) or {}) do
        if TestValid(obj) and obj.Get_Owner() == d.human then
            local at = obj.Get_Planet_Location()
            if at and U.key(at) == C.SENATE_WORLD then
                here = true
            else
                obj.Despawn()
            end
        end
    end
    if not here then
        pcall(Spawn_Unit, t, planet, d.human)
    end
    Council.apply_names(d)
    d.show("The Senate on Coruscant is restored. Coruscant is the capital of the "
        .. d.display_name("REBEL") .. " now.", nil, GOLD, 30)
end

function Council.constitutions()
    return C.CONSTITUTIONS
end

function Council.choosing(d)
    local c = d.republic and Council.state(d)
    return c ~= nil and c.choosing == true
end

function Council.found(d, key)
    local c = Council.state(d)
    if c.founded then
        return false
    end
    local chosen = nil
    for _, k in ipairs(C.CONSTITUTIONS) do
        if k.key == key then
            chosen = k
        end
    end
    if not chosen then
        return false
    end
    local Republic = republic()
    local r = d.republic
    c.choosing, c.founded, c.constitution, c.founded_at = nil, true, key, GetCurrentTime()
    c.focus = nil
    c.jedi_at = GetCurrentTime() + U.weeks(C.JEDI_WEEKS)
    r.mandate = R.SENATE.MANDATE_FOUNDED
    for _, councillor in ipairs(C.COUNCILLORS) do
        if d.senate and d.senate.opinion then
            d.senate.opinion[councillor.key] = nil
        end
    end
    for k, m in pairs(c.missions) do
        Goals.remove(d, m.goal)
        c.missions[k] = nil
    end
    if d.senate then
        d.senate.council = false
        d.senate.debate = nil
        d.senate.stability = M.min(100, senate_rules().NORMAL_STABILITY + R.SENATE.FOUNDING_COHESION)
        d.senate.cohesion_boost = {v = R.SENATE.FOUNDING_COHESION, t0 = GetCurrentTime()}
    end
    local Desires = Republic.part("desires")
    if Desires then
        for _, w in ipairs(U.worlds_of(d.human)) do
            if U.populated(w.key) then
                Desires.boost(d, w.key, R.SENATE.FOUNDING_OPINION, R.SENATE.FOUNDING_OPINION, "the founding of the Republic")
            end
        end
    end
    r.founding = {}
    for _, councillor in ipairs(C.COUNCILLORS) do
        local planet = FindPlanet(councillor.world)
        if U.populated(councillor.world) and planet and planet.Get_Owner() == d.human then
            r.founding[councillor.world] = true
        end
    end
    local P = Republic.part("prot")
    if P then
        for world, w in pairs(d.vassal_worlds or {}) do
            if w.stage == "protectorate" then
                pcall(P.make_associate, d, world)
            end
        end
    end
    if relation(d, C.CORELLIA) == "ALLIANCE" then
        pcall(d.set_relation, d, C.CORELLIA, "PROTECTORATE", nil, true)
    end
    if key == "ALL" then
        local Sym = Republic.part("sym")
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local k = U.key(planet)
            if Sym and planet.Get_Owner() ~= d.human and Sym.value(d, k) then
                local n = U.jumps(d, d.human, planet)
                if n and n <= 2 then
                    Sym.change(d, k, C.CONSTITUTION_SYMPATHY)
                end
            end
        end
    elseif key == "ENDURES" then
        c.endures_until = GetCurrentTime() + U.weeks(C.CONSTITUTION_WEEKS)
        if d.senate then
            d.senate.stability = M.min(100, d.senate.stability + C.CONSTITUTION_COHESION)
        end
    end
    Council.apply_names(d, true)
    Council.keep_dummies(d)
    lock_temple(d)
    local Gov = Republic.part("gov")
    if Gov and Gov.open_window then
        Gov.open_window(d)
    end
    cutscene("FOUNDING", function() Council.announce_founding(d, chosen) end)
    return true
end

function Council.announce_founding(d, chosen)
    d.show("THE NEW REPUBLIC: on Coruscant, the Councillors lay down their seats and the Senate convenes. The "
        .. "Alliance of Free Planets is the New Republic now, under " .. chosen.name .. ".", nil, GOLD, 40)
    pcall(M.show_document, {
        "In the Grand Convocation Chamber, beneath the dome the Emperor once filled with his Senate's silence, the "
            .. "delegates of a hundred worlds stand as the Charter is read.",
        "",
        "The Provisional Council has done what it set out to do. Its members give up their seats, and the New "
            .. "Republic Senate convenes for the first time.",
        "",
        "Constitution: " .. chosen.name .. ". " .. chosen.text,
        "",
        "Republic Affairs is open: the Senate, its members, sectors and taxes. Every world with a Senator's Office "
            .. "takes a seat.",
    }, "The New Republic", "The founding of a free galaxy.")
end

function Council.week_founded(d)
    local c = Council.state(d)
    pcall(check_deaths, d)
    Council.keep_dummies(d)
    if not c.jedi and c.jedi_at and GetCurrentTime() >= c.jedi_at then
        c.jedi_at = nil
        local ok_y, yavin = pcall(FindPlanet, C.JEDI_WORLD)
        if not (ok_y and yavin) then
            return
        end
        c.jedi = true
        local t = Find_Object_Type(C.JEDI_TEMPLE)
        if t then
            d.human.Unlock_Tech(t)
        end
        cutscene("JEDI_VISION", function() Council.announce_vision(d) end)
    end
end

function Council.announce_vision(d)
    do
        d.show("Luke Skywalker has had a vision: the Jedi Order may be reborn. The Jedi Order tab is open.", nil, GOLD, 30)
        pcall(M.show_document, {
            "On a quiet night, far from the Senate's halls, Luke Skywalker is not alone.",
            "",
            "Obi-Wan Kenobi stands before him one last time, as he stood on Hoth and on Dagobah, more light than man.",
            "",
            "\"The Republic is reborn, Luke. Now the Jedi must be, too. Pass on what you have learned. A new "
                .. "generation is waiting.\"",
            "",
            "And then he is gone, and does not return.",
            "",
            "The Jedi Order tab in Republic Affairs is open. The Jedi Temple can be built on Yavin.",
        }, "A Last Visit", "Obi-Wan Kenobi's Force ghost speaks to Luke.")
    end
end

function Council.on_temple_built(d)
    local r = d.republic
    if not r or r.jedi_founded then
        return
    end
    r.jedi_founded = true
    lock_temple(d)
    cutscene("JEDI_ORDER", function()
        d.show("The Jedi Order is restored: on Yavin, Luke Skywalker takes his first students.", nil, GOLD, 30)
        pcall(M.show_document, {
            "In the ancient temple on Yavin 4, where the Rebellion once hid from the Death Star, a new generation "
                .. "gathers.",
            "",
            "Luke Skywalker, last of the old Order and first of the new, begins to teach what Obi-Wan and Yoda "
                .. "taught him.",
            "",
            "The Jedi Order is restored.",
        }, "The Jedi Order", "A new hope for the Force.")
    end)
end

function seed_opinion(d)
    local c = Council.state(d)
    if not c or c.opinion_seeded or not d.senate or start_year() <= C.LAST_YEAR then
        return
    end
    c.opinion_seeded = true
    local lists, years = R.START_OPINION, {}
    for year in pairs(lists) do
        if type(year) == "number" and year <= start_year() then
            table.insert(years, year)
        end
    end
    table.sort(years)
    local value = {}
    for _, year in ipairs(years) do
        for world, v in pairs(lists[year]) do
            value[world] = v
        end
    end
    local Senate = republic().senate
    for _, w in ipairs(U.worlds_of(d.human)) do
        if U.populated(w.key) and not republic().is_territory(w.key) then
            local v = value[w.key] or lists.DEFAULT
            if v ~= 0 and Senate and Senate.sway then
                Senate.sway(d, w.key, v, "its standing in " .. start_year() .. " ABY")
            end
        end
    end
end

function lock_temple(d)
    local c = Council.state(d)
    local t = Find_Object_Type(C.JEDI_TEMPLE)
    if c and t then
        if c.jedi then
            d.human.Unlock_Tech(t)
        else
            d.human.Lock_Tech(t)
        end
    end
    local r = d.republic
    if c and r and c.jedi_start and t then
        c.jedi_start = nil
        r.jedi_founded = true
        local yavin = FindPlanet(C.JEDI_WORLD)
        local temple = Find_First_Object(C.JEDI_TEMPLE)
        if yavin and yavin.Get_Owner() == d.human and not TestValid(temple) then
            pcall(Spawn_Unit, t, yavin, d.human)
        end
    end
    local knights = Find_Object_Type(C.JEDI_KNIGHTS)
    if c and r and knights then
        if not r.jedi_founded then
            local temple = Find_First_Object(C.JEDI_TEMPLE)
            if TestValid(temple) and temple.Get_Owner() == d.human then
                r.jedi_founded = true
            end
        end
        local ok_j, Jedi = pcall(require, "eawx-plugins/jedi-order/JediOrder")
        if r.jedi_founded and not (ok_j and Jedi) then
            if c.knights_locked then
                c.knights_locked = nil
                d.human.Unlock_Tech(knights)
            end
        else
            c.knights_locked = true
            d.human.Lock_Tech(knights)
        end
    end
    local chamber = Find_Object_Type(C.SENATE_BUILDING)
    if c and chamber then
        local standing = Council.senate_built(d) and true or false
        if standing ~= c.chamber_locked then
            c.chamber_locked = standing
            if standing then
                d.human.Lock_Tech(chamber)
            else
                d.human.Unlock_Tech(chamber)
            end
        end
    end
    local tax = Find_Object_Type(C.TAX_AGENCY)
    if c and tax then
        if c.founded then
            if c.tax_locked then
                c.tax_locked = nil
                d.human.Unlock_Tech(tax)
            end
        else
            c.tax_locked = true
            d.human.Lock_Tech(tax)
        end
    end
end

local MISSION_CLASSES = {"BuildStructuresGroundMission", "BuildStructuresSpaceMission", "RaiseInfluenceMission",
    "RaiseInfrastructureMission", "TakePlanetAnyMission", "TakePlanetEnemyMission"}
local DISPLAY_EVENTS = {BuildStructuresGroundMission = "BuildStructuresGround_01",
    BuildStructuresSpaceMission = "BuildStructuresSpace_01"}

local function thrawn_mission_gain(reward, count)
    local value = 0
    local t = reward and Find_Object_Type(reward)
    if t then
        local ok, cost = pcall(t.Get_Build_Cost)
        value = (ok and type(cost) == "number" and cost or 0) * (count or 1)
    end
    local gain = C.MISSION_MANDATE_STEPS[1][2]
    for _, step in ipairs(C.MISSION_MANDATE_STEPS) do
        if value >= step[1] then
            gain = step[2]
        end
    end
    return gain
end

local function mandate_line(self)
    local n = thrawn_mission_gain(self.Reward, self.RewardCount)
    return "Council: done, mandate +" .. n .. "; failed, mandate -" .. n .. "."
end

function Council.thrawn_mission_done(d, reward, count)
    if not Council.active(d) then
        return
    end
    local gain = thrawn_mission_gain(reward, count)
    republic().change_mandate(d, gain)
    d.show("Council: the galaxy hears of the Alliance's success. Mandate +" .. gain .. " (" .. republic().mandate(d)
        .. ").", nil, COLOR, 15)
end

function Council.thrawn_mission_failed(d, reward, count)
    if not Council.active(d) then
        return
    end
    local loss = thrawn_mission_gain(reward, count)
    republic().change_mandate(d, -loss)
    d.show("Council: the galaxy hears that the Alliance failed its task. Mandate -" .. loss .. " ("
        .. republic().mandate(d) .. ").", nil, WARN, 15)
end

local function patch_missions(d)
    for _, name in ipairs(MISSION_CLASSES) do
        local class = rawget(_G, name)
        if type(class) == "table" and type(class.Fulfil) == "function" and not class.__council_patched then
            class.__council_patched = true
            local fulfil = class.Fulfil
            class.Fulfil = function(self)
                local reward, count = self.Reward, self.RewardCount
                local result = fulfil(self)
                if reward and self.Reward == nil and self.player == d.human then
                    pcall(Council.thrawn_mission_done, d, reward, count)
                end
                return result
            end
            local failed = class.Failed
            if type(failed) == "function" then
                class.Failed = function(self)
                    local reward, count = self.Reward, self.RewardCount
                    local result = failed(self)
                    if reward and self.Reward == nil and self.player == d.human then
                        pcall(Council.thrawn_mission_failed, d, reward, count)
                    end
                    return result
                end
            end
            local display = class.UpdateDisplay
            local event_name = DISPLAY_EVENTS[name]
            if event_name and type(display) == "function" then
                class.UpdateDisplay = function(self)
                    local result = display(self)
                    if self.player == d.human and Council.active(d) and self.Reward then
                        local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
                        local event = plot and plot.Get_Event(event_name)
                        if event then
                            pcall(event.Add_Dialog_Text, "TEXT_NONE")
                            pcall(M.add_dialog, event, mandate_line(self))
                        end
                    end
                    return result
                end
            end
            local begin = class.Begin
            if type(begin) == "function" and not event_name then
                class.Begin = function(self, a, b, c)
                    if self.player ~= d.human or not Council.active(d) then
                        return begin(self, a, b, c)
                    end
                    local plot_of, announce = Get_Story_Plot, Story_Event
                    local last = nil
                    Get_Story_Plot = function(path)
                        local plot = plot_of(path)
                        if not plot then
                            return plot
                        end
                        return setmetatable({Get_Event = function(name)
                            last = plot.Get_Event(name)
                            return last
                        end}, {__index = function(_, k)
                            return plot[k]
                        end})
                    end
                    Story_Event = function(tag)
                        if last and type(tag) == "string" and string.find(tag, "_ASSIGN$") then
                            pcall(M.add_dialog, last, mandate_line(self))
                            pcall(last.Add_Dialog_Text, "TEXT_NONE")
                        end
                        return announce(tag)
                    end
                    local ok, err = pcall(begin, self, a, b, c)
                    Get_Story_Plot, Story_Event = plot_of, announce
                    if not ok then
                        error(err)
                    end
                end
            end
        end
    end
end

function Council.election_in()
    local G = rawget(_G, "REPUBLIC_ELECTIONS")
    if type(G) ~= "table" or type(G.LastElectionTime) ~= "number" or type(G.CyclesBetweenElections) ~= "number" then
        return nil
    end
    return M.max(1, G.CyclesBetweenElections - G.LastElectionTime)
end

local function patch_elections(d)
    local G = rawget(_G, "GovernmentNewRepublic")
    if type(G) ~= "table" or G.__council_patched or type(G.ElectionHeld) ~= "function" then
        return
    end
    G.__council_patched = true
    local update = G.update
    if type(update) == "function" then
        G.update = function(self)
            REPUBLIC_ELECTIONS = self
            return update(self)
        end
    end
    local held = G.ElectionHeld
    G.ElectionHeld = function(self)
        if Council.active(d) then
            return
        end
        if type(self.CoSOptions) == "table" then
            self.CoSOptions.DUMMY_CHIEFOFSTATE_ACKBAR = self.CoSOptions.DUMMY_CHIEFOFSTATE_ACKBAR or "Ackbar_Loop"
            self.CoSOptions.DUMMY_CHIEFOFSTATE_BERUSS = self.CoSOptions.DUMMY_CHIEFOFSTATE_BERUSS or ""
            self.CoSOptions.DUMMY_CHIEFOFSTATE_VERRINNEFRA = self.CoSOptions.DUMMY_CHIEFOFSTATE_VERRINNEFRA or ""
        end
        return held(self)
    end
end

local loaded = false
function Council.update(d)
    if not d.republic then
        return
    end
    Council.apply_names(d)
    if not loaded then
        loaded = true
        lock_temple(d)
        pcall(seed_opinion, d)
        pcall(patch_elections, d)
        REPUBLIC_BREAKAWAY_NEWS = function(faction, display, leader, worlds)
            republic().on_breakaway(d, faction, display, leader, worlds)
        end
        local Envoys = republic().part("envoys")
        if Envoys then
            pcall(Envoys.unlock, d)
        end
    end
    local Envoys = republic().part("envoys")
    if Envoys and Envoys.update then
        pcall(Envoys.update, d)
    end
    if not Council.missions_patched and GetCurrentTime() >= (Council.next_patch or 0) then
        Council.next_patch = GetCurrentTime() + 10
        pcall(patch_missions, d)
        Council.missions_patched = type(rawget(_G, "ReconMission")) == "table"
    end
    if GetCurrentTime() >= (Council.next_deaths or 0) then
        Council.next_deaths = GetCurrentTime() + 3
        pcall(check_deaths, d)
    end
    if Council.active(d) and d.senate and GetCurrentTime() >= (Council.next_cohesion or 0) then
        Council.next_cohesion = GetCurrentTime() + 5
        d.senate.stability = Council.cohesion(d)
    end
    if Council.active(d) and influence() then
        influence().update(d)
    end
    if GetCurrentTime() >= (Council.next_tier_news or 0) then
        Council.next_tier_news = GetCurrentTime() + 2
        local Sym = republic().part("sym")
        if Sym and Sym.tier_news then
            pcall(Sym.tier_news, d)
        end
    end
    if Council.active(d) and GetCurrentTime() >= (Council.next_missions or 0) then
        Council.next_missions = GetCurrentTime() + 2
        local ok, err = pcall(check_missions, d)
        if not ok and Engine_Log then
            Engine_Log("COUNCIL missions: " .. tostring(err))
        end
    end
end

return Council
