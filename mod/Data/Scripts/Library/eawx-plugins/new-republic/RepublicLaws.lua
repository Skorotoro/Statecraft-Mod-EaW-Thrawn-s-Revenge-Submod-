local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local L = require("eawx-plugins/new-republic/RepublicLawsConfig")
local ok_pop, POPULATIONS = pcall(require, "eawx-plugins/diplomacy/DiplomacyPopulations")
POPULATIONS = (ok_pop and type(POPULATIONS) == "table") and POPULATIONS or {}
local ok_vol, VOLUNTEERS = pcall(require, "eawx-plugins/new-republic/RepublicVolunteers")
VOLUNTEERS = (ok_vol and type(VOLUNTEERS) == "table") and VOLUNTEERS or {}

local Laws = {CONFIG = L}
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}

local BY_KEY, TIER = {}, {}
for tier, list in pairs({galactic = L.GALACTIC, sector = L.SECTOR, planet = L.PLANET}) do
    for _, def in ipairs(list) do
        BY_KEY[def.key] = def
        TIER[def.key] = tier
    end
end

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function part(name)
    return Republic().part(name)
end

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.laws = r.laws or {}
    local s = r.laws
    s.galactic = s.galactic or {}
    s.sector = s.sector or {}
    s.planet = s.planet or {}
    s.news = s.news or {}
    s.info = s.info or {}
    s.wtags = s.wtags or {}
    s.guard = s.guard or {}
    s.militia = s.militia or {}
    return s
end
Laws.state = state

local function has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then
            return true
        end
    end
    return false
end

local function weeks_since(time)
    return M.floor((GetCurrentTime() - (time or GetCurrentTime())) / U.weeks(1))
end

function Laws.def(key)
    return BY_KEY[key]
end

function Laws.tier(key)
    return TIER[key]
end

function Laws.week_number(time)
    return M.floor((time or GetCurrentTime()) / U.weeks(1)) + 1
end

local function founded(d)
    return d.republic ~= nil and not Republic().council(d)
end

local function jedi_founded(d)
    local j = d.republic and d.republic.jedi
    return j ~= nil and j.roster ~= nil and next(j.roster) ~= nil
end
Laws.jedi_founded = jedi_founded

local function seated(d)
    local s = d.republic and d.republic.seated
    if s and next(s) then
        return s
    end
    local out = {}
    for key in pairs(Republic().seated_planets(d)) do
        out[key] = true
    end
    return out
end

local function is_member(d, key)
    local s = d.republic and d.republic.seated
    return not (s and next(s)) or s[key] == true
end

local function region_of(key)
    local sec = U.sector(U.sector_of(key))
    return sec and sec.region or ""
end

local function nonhuman(key)
    local Members = part("members")
    return (Members and Members.species(key) or "Human") ~= "Human"
end

local function bloc_key_of(d, key, bloc_name)
    local Blocs = part("blocs")
    if not Blocs then
        return nil
    end
    if bloc_name then
        return Blocs.key_of(bloc_name)
    end
    local b = d.senate and d.senate.blocs
    return b and b.of and b.of[key]
end

local function law_bloc(d, key, bloc)
    local Parties = part("parties")
    return (Parties and Parties.law_bloc) and Parties.law_bloc(d, key, bloc) or bloc
end

local function party_bloc(d, key)
    local Parties = part("parties")
    local p = Parties and Parties.ruling_party(d, key)
    return p and law_bloc(d, key, p.bloc)
end

local function fits(d, key, who, bloc)
    if who == "ALL" then
        return true
    end
    local kind, arg = string.sub(who, 1, 2), string.sub(who, 3)
    if kind == "B:" then
        return bloc_key_of(d, key, bloc) == arg or (bloc == nil and party_bloc(d, key) == arg)
    elseif kind == "I:" then
        local Members = part("members")
        return Members ~= nil and Members.has(d, key, arg)
    elseif kind == "W:" then
        return key == arg
    elseif kind == "R:" then
        local region = region_of(key)
        return (arg == "CORE" and L.CORE_REGIONS[region] == true) or (arg == "MIDOUTER" and L.MIDOUTER_REGIONS[region] == true)
    elseif who == "NONHUMAN" then
        return nonhuman(key)
    elseif who == "HUMAN" then
        return not nonhuman(key)
    elseif who == "FREED" then
        return d.republic.freed_worlds ~= nil and d.republic.freed_worlds[key] == true
    elseif who == "TIER1" then
        return POPULATIONS[key] == 1
    elseif who == "TIER3" then
        return POPULATIONS[key] == 3
    elseif who == "MINING" or who == "NOT_MINING" or who == "SHIPYARD" then
        local s = state(d)
        local tags = s and s.wtags[key] or {}
        if who == "NOT_MINING" then
            return not tags.MINING
        end
        return tags[who] == true
    end
    return false
end

local SCOPES = {OTHERS = true, NEIGHBOURS = true, OUTSIDE = true}
local function scope_of(who)
    local a, b = string.find(who, ":", 1, true)
    if a then
        local scope = string.sub(who, 1, a - 1)
        if SCOPES[scope] then
            return scope, string.sub(who, b + 1)
        end
    end
    return nil, who
end

function Laws.active(d)
    local out = {}
    local s = d.republic and d.republic.laws
    if not s or not founded(d) then
        return out
    end
    for key, entry in pairs(s.galactic or {}) do
        if BY_KEY[key] then
            table.insert(out, {def = BY_KEY[key], entry = entry, tier = "galactic"})
        end
    end
    for name, sec in pairs(s.sector or {}) do
        for key, entry in pairs(sec.laws or {}) do
            if BY_KEY[key] then
                table.insert(out, {def = BY_KEY[key], entry = entry, tier = "sector", sector = name})
            end
        end
    end
    for world, w in pairs(s.planet or {}) do
        if is_member(d, world) then
            for key, entry in pairs(w.laws or {}) do
                if BY_KEY[key] then
                    table.insert(out, {def = BY_KEY[key], entry = entry, tier = "planet", world = world})
                end
            end
        end
    end
    return out
end

function Laws.galactic_on(d, key)
    local s = d.republic and d.republic.laws
    return founded(d) and s ~= nil and s.galactic ~= nil and s.galactic[key] ~= nil
end

local function covers(a, key)
    if a.tier == "galactic" then
        return true
    elseif a.tier == "sector" then
        return U.sector_of(key) == a.sector
    end
    return a.world == key
end

local function reaches(d, a, scope, key)
    if not scope then
        return covers(a, key)
    end
    local sector = a.sector or (a.world and U.sector_of(a.world))
    if scope == "OTHERS" then
        return a.world ~= nil and key ~= a.world and U.sector_of(key) == sector
    elseif scope == "OUTSIDE" then
        return U.sector_of(key) ~= sector
    elseif scope == "NEIGHBOURS" then
        local s = state(d)
        local info = s and s.info[sector]
        return info ~= nil and info.next ~= nil and info.next[U.sector_of(key)] == true
    end
    return false
end

local function laws_on(d, key)
    local out = {}
    for _, a in ipairs(Laws.active(d)) do
        if covers(a, key) then
            table.insert(out, a)
        end
    end
    return out
end
Laws.on = laws_on

function Laws.flag(d, name, world)
    for _, a in ipairs(Laws.active(d)) do
        local f = a.def.flags
        if f and f[name] ~= nil and (world == nil or covers(a, world)) then
            return f[name], a
        end
    end
    return nil
end

local function gflag(d, name)
    for _, a in ipairs(Laws.active(d)) do
        if a.tier == "galactic" and a.def.flags and a.def.flags[name] ~= nil then
            return a.def.flags[name], a
        end
    end
    return nil
end
Laws.gflag = gflag

local function at_war(d)
    return Republic().at_war(d)
end

function Laws.opinion(d, key, bloc)
    local total, parts = 0, {}
    local function add(v, text)
        if v ~= 0 then
            total = total + v
            table.insert(parts, {text, v})
        end
    end
    local war = nil
    for _, a in ipairs(Laws.active(d)) do
        local def = a.def
        local sum = 0
        for _, rule in ipairs(def.opinion or {}) do
            local scope, who = scope_of(rule[1])
            if reaches(d, a, scope, key) and fits(d, key, who, bloc) then
                sum = sum + rule[2]
            end
        end
        if covers(a, key) then
            local built = a.entry.built and a.entry.built[key]
            if built then
                sum = sum + built
            end
            local f = def.flags or {}
            if f.war_opinion or f.peace_opinion then
                if war == nil then
                    war = at_war(d)
                end
                sum = sum + ((war and f.war_opinion) or ((not war) and f.peace_opinion) or 0)
            end
            if f.calm_opinion and a.sector then
                local s = state(d)
                local info = s.info[a.sector]
                if info and not (info.tags and info.tags.FRONT) then
                    sum = sum + f.calm_opinion
                end
            end
        end
        add(sum, def.name)
    end
    return total, parts
end

function Laws.opinion_cap(d, key)
    local v = Laws.flag(d, "opinion_cap", key)
    return v
end

function Laws.no_fall(d, key)
    return Laws.flag(d, "no_fall", key) ~= nil
end

function Laws.no_secession(d, key)
    return Laws.flag(d, "no_secession", key) ~= nil
end

function Laws.closed(d, key, what)
    local v, a = Laws.flag(d, "closed", key)
    if not v then
        return nil
    end
    if what == "envoy" and a.def.key ~= "ISOLATION" then
        return nil
    end
    return a.def.name .. " bars it on this world."
end

local function bloc_of_seat(seat)
    local Blocs = part("blocs")
    return Blocs and Blocs.key_of(seat.bloc)
end

local function law_view(d, seat, def, sign, out)
    local bloc = bloc_of_seat(seat)
    local party = party_bloc(d, seat.name)
    local function add(text, v)
        if v ~= 0 then
            table.insert(out, {text, v * sign})
        end
    end
    local keep = sign < 0
    if bloc and has(def.pro, bloc) then
        add(keep and ("its bloc wants to keep the " .. def.name) or ("its bloc backs the " .. def.name), L.BLOC_FOR)
    elseif bloc and has(def.con, bloc) then
        add(keep and ("its bloc wants the " .. def.name .. " gone") or ("its bloc opposes the " .. def.name), -L.BLOC_AGAINST)
    end
    if party and party ~= bloc then
        if has(def.pro, party) then
            add(keep and "its ruling party would keep it" or "its ruling party wants it", L.PARTY)
        elseif has(def.con, party) then
            add(keep and "its ruling party wants it gone" or "its ruling party is against it", -L.PARTY)
        end
    end
    local own = 0
    for _, rule in ipairs(def.opinion or {}) do
        local scope, who = scope_of(rule[1])
        if not scope and fits(d, seat.name, who, seat.bloc) then
            own = own + rule[2]
        end
    end
    if def.build and fits(d, seat.name, def.build[1], seat.bloc) then
        own = own + def.build[2] * def.build[3]
    end
    for _, inc in ipairs(def.income or {}) do
        if fits(d, seat.name, inc[3], seat.bloc) then
            own = own + M.round(inc[2] / 5)
        end
    end
    if keep then
        add((own > 0) and ("it would lose what the " .. def.name .. " gives it") or ("it would be rid of the "
            .. def.name .. "'s cost"), own)
    else
        add((own > 0) and ("it gains by the " .. def.name) or ("it would pay for the " .. def.name), own)
    end
    if def.key == "SENATE_REFORM" then
        add(POPULATIONS[seat.name] == 3 and "its vote would count double" or "small worlds lose weight",
            (POPULATIONS[seat.name] == 3) and 15 or -5)
    elseif def.jedi or def.key == "JEDI_SANCTION" then
        local trust = (d.republic.jedi and d.republic.jedi.trust) or 50
        add((trust >= 50) and "the people trust the Jedi" or "the people mistrust the Jedi", M.round((trust - 50) * 0.4))
    end
end

local function interest_sign(d, seat, motion)
    local Members = part("members")
    if not Members then
        return 0
    end
    local function i(name)
        return Members.has(d, seat.name, name)
    end
    if motion.kind == "WAR" then
        if i("Pacifist") then
            return -1
        end
        local cat = U.category(motion.target or "")
        if (cat == "IMPERIAL" or cat == "WARLORD") and (i("Liberation") or i("Reparations")) then
            return 1
        end
        if i("Security") and seat.threat == motion.target then
            return 1
        end
    elseif motion.kind == "TREATY" then
        if i("Commerce") or i("Pacifist") then
            return 1
        end
    elseif motion.kind == "TAX" then
        return ((motion.level or 0) > (motion.from or 0)) and ((i("Commerce") or i("Autonomy")) and -1 or 0) or 0
    elseif motion.kind == "APPROPRIATION" then
        return (i("Security") or i("Industry")) and 1 or 0
    end
    return 0
end

function Laws.stance(d, seat, motion)
    local out = {}
    if not founded(d) then
        return out
    end
    if motion.kind == "LAW" then
        local def = BY_KEY[motion.law or ""]
        if def then
            law_view(d, seat, def, (motion.op == "REPEAL") and -1 or 1, out)
        end
        local old = motion.old and BY_KEY[motion.old]
        if old then
            law_view(d, seat, old, -1, out)
        end
        return out
    elseif motion.kind == "SREPEAL" then
        local def = BY_KEY[motion.law or ""]
        local bloc = bloc_of_seat(seat)
        if U.sector_of(seat.name) == motion.sector and def then
            law_view(d, seat, def, -1, out)
            table.insert(out, {"its own sector's law", -15})
        elseif bloc == "AUTONOMY" or bloc == "ALIEN" then
            table.insert(out, {"Coruscant overruling a sector", -15})
        elseif bloc == "CORE" then
            table.insert(out, {"the Senate's authority", 10})
        end
        return out
    end
    local kind = motion.kind
    if kind == "FOCUS" and motion.focus == "FLEET" then
        kind = "FLEET_FOCUS"
    end
    for _, a in ipairs(laws_on(d, seat.name)) do
        for _, st in ipairs(a.def.stance or {}) do
            if st[1] == kind then
                table.insert(out, {a.def.name, st[2]})
            end
        end
        local f = a.def.flags or {}
        if f.referendum and motion.kind == "WAR" and seat.opinion < L.REFERENDUM_OPINION then
            table.insert(out, {"its people vote down the war (Referendum Act)", -100})
        end
        if f.consensus then
            local sign = interest_sign(d, seat, motion)
            if sign ~= 0 then
                table.insert(out, {"its interests decide (Consensus Rule)", 40 * sign})
            end
        end
    end
    return out
end

function Laws.weight(d, key)
    local w = gflag(d, "populous_weight")
    if w and POPULATIONS[key] == 3 then
        return w
    end
    return 1
end

function Laws.war_majority(d)
    return gflag(d, "war_majority") ~= nil
end

function Laws.weariness(d, value)
    local f = gflag(d, "weariness")
    return f and M.round(value * f) or value
end

function Laws.cohesion(d)
    local v, war = 0, nil
    for _, a in ipairs(Laws.active(d)) do
        if a.tier == "galactic" then
            v = v + (a.def.cohesion or 0)
            if a.def.cohesion_war then
                if war == nil then
                    war = at_war(d)
                end
                v = v + (war and a.def.cohesion_war or 0)
            end
        end
    end
    return v
end

function Laws.price(d, amount)
    if gflag(d, "motion_half") then
        return M.max(1, M.ceil(amount / 2))
    end
    return amount
end

function Laws.attitude(d, faction)
    local v = 0
    local cat = U.category(faction or "")
    for _, a in ipairs(Laws.active(d)) do
        local f = a.def.flags or {}
        if f.imperial_attitude and (cat == "IMPERIAL" or cat == "WARLORD") then
            v = v + f.imperial_attitude
        end
        if f.neighbour_attitude and a.sector then
            local s = state(d)
            local info = s.info[a.sector]
            if info and info.powers and info.powers[string.upper(faction or "")] then
                v = v + f.neighbour_attitude
            end
        end
    end
    return v
end

function Laws.treaty_acceptance(d)
    return gflag(d, "treaty_acceptance") or 0
end

function Laws.trade_acceptance(d)
    return gflag(d, "trade_acceptance") or 0
end

function Laws.envoy_speed(d)
    return gflag(d, "envoy_speed") or 1
end

function Laws.jedi_trust(d)
    return gflag(d, "jedi_trust") or 1
end

function Laws.jedi_envoy(d)
    return gflag(d, "jedi_envoy") ~= nil and jedi_founded(d)
end

function Laws.no_drift(d, key)
    return gflag(d, "no_drift") ~= nil or Laws.flag(d, "no_drift", key) ~= nil
end

function Laws.pledges(d, key)
    local v = Laws.flag(d, "pledges", key)
    if v == 2 then
        local _, a = Laws.flag(d, "pledges", key)
        local s = state(d)
        if a and a.def.key == "CLAN_LEVY" and not ((s.wtags[key] or {}).FRONT) then
            return 1
        end
    end
    return v or 1
end

function Laws.no_focus(d, key)
    return Laws.flag(d, "no_focus", key) ~= nil
end

function Laws.favours(d, key)
    local out = {}
    for _, a in ipairs(laws_on(d, key)) do
        local who = a.def.clout_who
        if not who or fits(d, key, who) then
            for bloc, v in pairs(a.def.clout or {}) do
                out[bloc] = (out[bloc] or 0) + v
            end
        end
    end
    return out
end

function Laws.clout_speed(d, key)
    return Laws.flag(d, "slow_clout", key) or 1
end

function Laws.fatigue_weeks(d, key, term)
    return Laws.flag(d, "early_fatigue", key) and (term or 0) or 0
end

function Laws.party_week(d, key, w)
    local Parties = part("parties")
    if not Parties or not w then
        return
    end
    local top = Laws.flag(d, "top_clout", key)
    if top then
        local best = 1
        for k, p in ipairs(w.list) do
            if p.clout > w.list[best].clout then
                best = k
            end
        end
        Parties.adjust(d, key, best, top)
    end
    local ruling = Laws.flag(d, "ruling_clout", key)
    if ruling then
        Parties.adjust(d, key, w.ruling, ruling)
    end
end

function Laws.no_rig(d, key)
    return Laws.flag(d, "no_rig", key) ~= nil
end

function Laws.term_limits(d, key)
    return Laws.flag(d, "term_limits", key) ~= nil
end

function Laws.incumbent_clout(d, key)
    return Laws.flag(d, "incumbent_clout", key) or 0
end

function Laws.no_replace(d, key)
    return Laws.flag(d, "no_replace", key) ~= nil
end

function Laws.no_reappoint(d, key)
    local v, a = Laws.flag(d, "no_reappoint", key)
    if v == nil then
        return nil
    end
    if v == 0 or weeks_since(a.entry.since) < v then
        return a.def.name .. " protects the ruler's choice."
    end
    return nil
end

function Laws.intel(d, op_key, internal, world)
    local cost, extra, caught = 1, 0, 1
    if internal then
        cost = gflag(d, "internal_cost") or 1
        extra = gflag(d, "internal_weeks") or 0
    end
    local c = gflag(d, "caught")
    if c and c[op_key] then
        caught = c[op_key]
    end
    return cost, extra, caught
end

function Laws.scandal(d, world)
    if gflag(d, "internal_safe") or (world and Laws.flag(d, "internal_safe_here", world)) then
        return 0
    end
    return gflag(d, "scandal") or 1
end

local function upkeep_pct(d)
    return gflag(d, "upkeep") or 0
end

function Laws.tax_factor(d, sector)
    local pct = 0
    for _, a in ipairs(Laws.active(d)) do
        if a.def.tax and (a.tier == "galactic" or a.sector == sector) then
            pct = pct + a.def.tax
        end
    end
    return M.max(0, 1 + pct / 100)
end

function Laws.tax_levels(d, sector)
    local n = 0
    for _, a in ipairs(Laws.active(d)) do
        if a.def.tax_level and a.sector == sector then
            n = n + a.def.tax_level
        end
    end
    return n
end

function Laws.industry_met(d, key)
    return Laws.flag(d, "industry_met", key) ~= nil
end

local function trade_ports(d)
    local S = part("sectors")
    local ok, t = false, nil
    if S and S.trade_income then
        ok, t = pcall(S.trade_income, d)
    end
    return (ok and t) or {}
end

local function neighbours(d, planet)
    local ok, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    local list = ok and Trade and Trade.neighbours(d, planet)
    return list or {}
end

local function capital_world(d)
    local t = Find_Object_Type("NewRep_Capital")
    if t then
        for _, obj in pairs(Find_All_Objects_Of_Type(t) or {}) do
            if TestValid(obj) and obj.Get_Owner() == d.human then
                local p = obj.Get_Planet_Location()
                if p then
                    return U.key(p)
                end
            end
        end
    end
    return nil
end

local function retag(d, seats)
    local s = state(d)
    local ports = trade_ports(d)
    local mines, yards = {}, {}
    local okf, all = pcall(Find_All_Objects_Of_Type, d.human, "Structure | SpaceStructure")
    for _, obj in pairs(okf and all or {}) do
        if TestValid(obj) then
            local t = string.upper(obj.Get_Type().Get_Name())
            local p = obj.Get_Planet_Location()
            if p and string.find(t, "^MINING_FACILITY") then
                mines[U.key(p)] = (mines[U.key(p)] or 0) + 1
            end
        end
    end
    for n = L.SHIPYARD_LEVEL, 5 do
        local t = Find_Object_Type("Rebel_Star_Base_" .. n)
        for _, obj in pairs((t and Find_All_Objects_Of_Type(t)) or {}) do
            if TestValid(obj) and obj.Get_Owner() == d.human then
                local p = obj.Get_Planet_Location()
                if p then
                    yards[U.key(p)] = true
                end
            end
        end
    end
    s.mines = mines
    local capital = capital_world(d)
    local S = part("sectors")
    s.wtags, s.info = {}, {}
    for key, seat in pairs(seats) do
        local planet = seat.planet
        local tags = {}
        tags.PORT = ports[key] ~= nil or nil
        tags.MINING = mines[key] ~= nil or nil
        tags.SHIPYARD = yards[key] or nil
        tags.POPULOUS = POPULATIONS[key] == 3 or nil
        tags.ALIEN = nonhuman(key) or nil
        tags.FREED = (d.republic.freed_worlds and d.republic.freed_worlds[key]) or nil
        tags.OCCUPIED = (d.republic.laws.occupied and d.republic.laws.occupied[key]) or nil
        tags.CAPITAL = (capital == key) or nil
        tags.AGRARIAN = L.AGRARIAN[key] or nil
        tags.HOSTILE = seat.opinion <= L.ISOLATION_OPINION or nil
        if S and S.income_of then
            local ok, income = pcall(S.income_of, d, planet, ports)
            tags.POOR = (ok and income and income < L.POOR_INCOME) or nil
        end
        local sector = U.sector_of(key)
        local info = s.info[sector] or {tags = {}, next = {}, powers = {}, seats = 0, peace = 0, alien = 0}
        s.info[sector] = info
        info.seats = info.seats + 1
        if bloc_of_seat(seat) == "PEACE" then
            info.peace = info.peace + 1
        end
        if tags.ALIEN then
            info.alien = info.alien + 1
        end
        for _, t in ipairs({"PORT", "MINING", "SHIPYARD", "FREED"}) do
            if tags[t] then
                info.tags[(t == "PORT" and "TRADE") or (t == "FREED" and "REBEL") or t] = true
            end
        end
        local region = region_of(key)
        if L.CORE_REGIONS[region] then
            info.tags.CORE = true
        elseif L.RIM_REGIONS[region] then
            info.tags.RIM = true
        end
        for _, other in ipairs(neighbours(d, planet)) do
            local there = FindPlanet(other)
            if there then
                local owner = there.Get_Owner()
                local osec = U.sector_of(other)
                if osec ~= sector then
                    info.next[osec] = true
                end
                if owner ~= d.human then
                    local name = string.upper(owner.Get_Faction_Name())
                    local cat = U.category(name)
                    if cat ~= "INDEPENDENT" then
                        info.tags.BORDER = true
                        info.powers[name] = true
                    end
                    if d.human.Is_Enemy(owner) and cat ~= "INDEPENDENT" then
                        info.tags.FRONT = true
                        tags.FRONT = true
                    end
                end
            end
        end
        s.wtags[key] = tags
    end
    for _, info in pairs(s.info) do
        if info.alien * 2 > info.seats then
            info.tags.ALIEN = true
        end
        if info.peace * 2 > info.seats then
            info.tags.PEACE_MAJORITY = true
        end
    end
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

function Laws.galactic_rows(d)
    local s = state(d)
    local out = {}
    if not s then
        return out
    end
    for key, entry in pairs(s.galactic) do
        local def = BY_KEY[key]
        if def then
            local left = def.lapse and M.max(0, def.lapse - weeks_since(entry.since)) or nil
            table.insert(out, {key = key, def = def, since = entry.since, left = left})
        end
    end
    table.sort(out, function(a, b) return a.since < b.since end)
    return out
end

function Laws.galactic_count(d)
    local s = state(d)
    return s and count(s.galactic) or 0
end

function Laws.cost(d)
    return Laws.price(d, L.CAPITAL)
end

function Laws.blocked(d, key, op, old)
    local s = state(d)
    local def = BY_KEY[key]
    if not s or not def then
        return "No such law."
    end
    if not founded(d) then
        return "Only the Senate of the founded Republic passes laws."
    end
    if op ~= "REPEAL" then
        if s.galactic[key] then
            return "The " .. def.name .. " is already law."
        end
        if def.jedi and not jedi_founded(d) then
            return "It needs the Jedi Order founded."
        end
        if op == "ENACT" and count(s.galactic) >= L.GALACTIC_MAX then
            return "Six laws are in force: change or repeal one first."
        end
    end
    if (d.republic.capital or 0) < Laws.cost(d) then
        return "Not enough political capital (" .. Laws.cost(d) .. " needed)."
    end
    local can, why = Republic().senate.can_propose(d)
    if not can then
        return why
    end
    return nil
end

function Laws.motion(d, key, op, old)
    local def, odef = BY_KEY[key], old and BY_KEY[old]
    local text, label
    if op == "REPEAL" then
        text, label = "repeal the " .. def.name, "Repeal: " .. def.name
    elseif op == "CHANGE" and odef then
        text, label = "replace the " .. odef.name .. " with the " .. def.name, def.name
    else
        text, label = "enact the " .. def.name, def.name
    end
    return {kind = "LAW", law = key, op = op, old = old, capital = Laws.cost(d), label = label, text = text,
            tip = def.name .. ": " .. def.text .. ((op == "CHANGE" and odef) and (" It replaces the " .. odef.name .. ".") or "")}
end

local function news(d, text, text2, kind, ref)
    local s = state(d)
    d.republic.news_id = (d.republic.news_id or 0) + 1
    table.insert(s.news, 1, {id = d.republic.news_id, text = text, text2 = text2, kind = kind, ref = ref})
    while table.getn(s.news) > 10 do
        table.remove(s.news)
    end
end

function Laws.news(d)
    local s = d.republic and d.republic.laws
    return (s and s.news) or {}
end

function Laws.acknowledge(d, id)
    local s = state(d)
    local kept = {}
    for _, n in ipairs(s.news) do
        if n.id ~= id then
            table.insert(kept, n)
        end
    end
    s.news = kept
end

local apply_on, apply_off

local function remove(d, a_tier, key, scope, why)
    local s = state(d)
    local list
    if a_tier == "galactic" then
        list = s.galactic
    elseif a_tier == "sector" then
        list = s.sector[scope] and s.sector[scope].laws
    else
        list = s.planet[scope] and s.planet[scope].laws
    end
    if list and list[key] then
        list[key] = nil
        apply_off(d, BY_KEY[key], scope)
    end
end

local function add(d, a_tier, key, scope)
    local s = state(d)
    local def = BY_KEY[key]
    for _, other in ipairs(def.excludes or {}) do
        remove(d, a_tier, other, scope)
    end
    local entry = {since = GetCurrentTime()}
    if a_tier == "galactic" then
        s.galactic[key] = entry
    elseif a_tier == "sector" then
        s.sector[scope] = s.sector[scope] or {laws = {}}
        s.sector[scope].laws[key] = entry
    else
        s.planet[scope] = s.planet[scope] or {laws = {}}
        s.planet[scope].laws[key] = entry
        s.planet[scope].changed = GetCurrentTime()
    end
    apply_on(d, def, scope)
end

function Laws.enact(d, motion)
    local def = BY_KEY[motion.law or ""]
    if not def then
        return
    end
    if motion.kind == "SREPEAL" then
        remove(d, "sector", motion.law, motion.sector)
        local Senate = Republic().senate
        for key in pairs(seated(d)) do
            if U.sector_of(key) == motion.sector and Senate then
                Senate.sway(d, key, L.REPEAL_OPINION, "the Senate struck down its sector's law")
            end
        end
        if d.senate then
            d.senate.stability = M.max(0, d.senate.stability - L.REPEAL_COHESION)
        end
        d.show("Senate: the " .. def.name .. " of the " .. motion.sector .. " is struck down. Its worlds resent it.", nil, WARN, 20)
        return
    end
    if motion.op == "REPEAL" then
        remove(d, "galactic", motion.law)
        d.show("Senate: the " .. def.name .. " is repealed.", nil, COLOR, 20)
        return
    end
    if motion.op == "CHANGE" and motion.old then
        remove(d, "galactic", motion.old)
    end
    if Laws.galactic_count(d) >= L.GALACTIC_MAX then
        d.show("Senate: six laws are already in force; the " .. def.name .. " lapses.", nil, WARN, 20)
        return
    end
    add(d, "galactic", motion.law)
    d.show("Senate: the " .. def.name .. " is law. " .. def.text, nil, COLOR, 25)
end

function Laws.possible(d)
    local out = {}
    local s = state(d)
    for _, def in ipairs(L.GALACTIC) do
        if not s.galactic[def.key] and (not def.jedi or jedi_founded(d)) then
            table.insert(out, def)
        end
    end
    return out
end

local function sector_seats(d, sector, seats)
    local out = {}
    for key, seat in pairs(seats) do
        if U.sector_of(key) == sector then
            table.insert(out, seat)
        end
    end
    return out
end

local function backs(d, seat, def)
    local bloc = party_bloc(d, seat.name) or bloc_of_seat(seat)
    if bloc and has(def.pro, bloc) then
        return 1
    elseif bloc and has(def.con, bloc) then
        return -1
    end
    return 0
end
Laws.backs = backs

local function share(d, list, def, sign)
    if table.getn(list) == 0 then
        return 0
    end
    local n = 0
    for _, seat in ipairs(list) do
        if backs(d, seat, def) == sign then
            n = n + 1
        end
    end
    return M.round(100 * n / table.getn(list))
end

local function fits_sector(info, def)
    if def.need and not (info.tags and info.tags[def.need]) then
        return false
    end
    if not def.tags then
        return true
    end
    for _, t in ipairs(def.tags) do
        if info.tags and info.tags[t] then
            return true
        end
    end
    return false
end

function Laws.sector_view(d, sector)
    local s = state(d)
    local Senate = Republic().senate
    local seats = Senate and Senate.seats(d) or {}
    local list = sector_seats(d, sector, seats)
    local sec = s.sector[sector] or {laws = {}}
    local info = s.info[sector] or {tags = {}}
    local enacted, possible = {}, {}
    for _, def in ipairs(L.SECTOR) do
        local backers = {}
        for _, seat in ipairs(list) do
            local b = backs(d, seat, def)
            if b ~= 0 then
                local party = part("parties") and part("parties").ruling_party(d, seat.name)
                table.insert(backers, {b, party and party.name or seat.bloc, seat.name})
            end
        end
        local row = {def = def, share = share(d, list, def, 1), against = share(d, list, def, -1), backers = backers}
        if sec.laws[def.key] then
            row.since = sec.laws[def.key].since
            table.insert(enacted, row)
        elseif fits_sector(info, def) then
            table.insert(possible, row)
        end
    end
    return {enacted = enacted, possible = possible, vote = sec.vote, seats = table.getn(list)}
end

function Laws.vote_line(d, sector)
    local s = state(d)
    local v = s and s.sector[sector] and s.sector[sector].vote
    if not v then
        return nil
    end
    local def = BY_KEY[v.law]
    local left = M.max(1, M.ceil((v.ends - GetCurrentTime()) / U.weeks(1)))
    return ((v.repeal and "Voting to repeal: " or "Voting: ") .. (def and def.name or v.law)),
        v.share .. "%   " .. left .. " wk", v
end

local function open_vote(d, sector, def, pct, repeal)
    local s = state(d)
    s.sector[sector] = s.sector[sector] or {laws = {}}
    local w = GameRandom.Free_Random(L.VOTE_WEEKS[1], L.VOTE_WEEKS[2])
    d.republic.news_id = (d.republic.news_id or 0) + 1
    s.sector[sector].vote = {law = def.key, share = pct, repeal = repeal or nil, ends = GetCurrentTime() + U.weeks(w),
                             id = d.republic.news_id}
end

local function close_vote(d, sector, sec)
    local v = sec.vote
    sec.vote = nil
    local def = BY_KEY[v.law]
    if not def then
        return
    end
    local passed = U.chance(v.share)
    local verb
    if v.repeal then
        verb = passed and "repealed" or "kept"
        if passed then
            remove(d, "sector", def.key, sector)
        end
    else
        verb = passed and "passed" or "rejected"
        if passed and count(sec.laws) < L.SECTOR_MAX then
            add(d, "sector", def.key, sector)
        end
    end
    sec.last = GetCurrentTime()
    news(d, "The " .. sector .. " " .. verb .. " the " .. def.name .. ".", def.short, "sector", sector)
end

local function sector_week(d, seats)
    local s = state(d)
    local rate = L.VOTE_CHANCE * (gflag(d, "sector_votes") or 1)
    local sectors = {}
    for key in pairs(seats) do
        sectors[U.sector_of(key)] = true
    end
    for name in pairs(sectors) do
        local sec = s.sector[name] or {laws = {}}
        s.sector[name] = sec
        local list = sector_seats(d, name, seats)
        local info = s.info[name] or {tags = {}}
        for key, entry in pairs(sec.laws) do
            local def = BY_KEY[key]
            if def and def.lapse and weeks_since(entry.since) >= def.lapse then
                remove(d, "sector", key, name)
                news(d, "The " .. name .. "'s " .. def.name .. " has run its course.", def.short, "sector", name)
            end
        end
        if sec.vote then
            if GetCurrentTime() >= sec.vote.ends then
                close_vote(d, name, sec)
            end
        elseif table.getn(list) > 0 and U.chance(rate) then
            local repeal = nil
            for key in pairs(sec.laws) do
                local def = BY_KEY[key]
                if def and share(d, list, def, 1) < L.REPEAL_SHARE and U.chance(L.REPEAL_CHANCE * 10) then
                    repeal = def
                end
            end
            if repeal then
                open_vote(d, name, repeal, M.max(1, 100 - share(d, list, repeal, 1)), true)
            elseif count(sec.laws) < L.SECTOR_MAX then
                local options, weights = {}, 0
                for _, def in ipairs(L.SECTOR) do
                    if not sec.laws[def.key] and fits_sector(info, def) then
                        local pct = share(d, list, def, 1)
                        local excluded = false
                        for _, ex in ipairs(def.excludes or {}) do
                            excluded = excluded or sec.laws[ex] ~= nil
                        end
                        if pct > 0 and not excluded then
                            table.insert(options, {def, pct})
                            weights = weights + pct
                        end
                    end
                end
                if weights > 0 then
                    local roll = GameRandom.Free_Random(1, weights)
                    for _, o in ipairs(options) do
                        roll = roll - o[2]
                        if roll <= 0 then
                            open_vote(d, name, o[1], o[2], false)
                            break
                        end
                    end
                end
            end
        end
    end
end

function Laws.veto(d, sector)
    local s = state(d)
    local sec = s and s.sector[sector]
    if not (sec and sec.vote) then
        return false, "No vote runs there."
    end
    local def = BY_KEY[sec.vote.law]
    sec.vote = nil
    local Senate = Republic().senate
    for key in pairs(seated(d)) do
        if U.sector_of(key) == sector and Senate then
            Senate.sway(d, key, L.VETO_OPINION, "the government vetoed its sector's vote")
        end
    end
    return true, "Vetoed: the " .. sector .. "'s vote on the " .. (def and def.name or "law") .. " is void."
end

function Laws.ack_vote(d, sector)
    local s = state(d)
    local sec = s and s.sector[sector]
    if sec and sec.vote then
        sec.vote.seen = true
    end
end

function Laws.open_votes(d)
    local out = {}
    local s = d.republic and d.republic.laws
    for name, sec in pairs((s and s.sector) or {}) do
        if sec.vote and not sec.vote.seen then
            table.insert(out, {sector = name, vote = sec.vote})
        end
    end
    table.sort(out, function(a, b) return a.sector < b.sector end)
    return out
end

function Laws.repeal_motions(d)
    local out = {}
    local s = d.republic and d.republic.laws
    if not s or not founded(d) or gflag(d, "no_force_repeal") then
        return out
    end
    for name, sec in pairs(s.sector) do
        for key in pairs(sec.laws or {}) do
            local def = BY_KEY[key]
            if def then
                table.insert(out, {kind = "SREPEAL", law = key, sector = name, group = "SREPEAL", label = def.name,
                    capital = Laws.price(d, L.REPEAL_CAPITAL), text = "strike down the " .. name .. "'s " .. def.name,
                    tip = def.name .. ": " .. def.text .. " Passed, the sector's worlds " .. L.REPEAL_OPINION
                        .. " and cohesion -" .. L.REPEAL_COHESION .. "."})
            end
        end
    end
    return out
end

local function kind_of(d, key)
    local Parties = part("parties")
    local w = Parties and Parties.of(d, key)
    return w and w.kind
end

local function fits_world(d, key, def, tags, kind, party)
    if def.kinds and not has(def.kinds, kind) then
        return false
    end
    if def.party and not has(def.party, party) then
        return false
    end
    if def.tags then
        local any = false
        for _, t in ipairs(def.tags) do
            any = any or (tags[t] == true)
        end
        if not any then
            return false
        end
    end
    return true
end

function Laws.planet_view(d, key)
    local s = state(d)
    local w = s.planet[key] or {laws = {}}
    local kind = kind_of(d, key)
    local tags = s.wtags[key] or {}
    local Parties = part("parties")
    local pw = Parties and Parties.of(d, key)
    local function sides(def)
        local pro, con = {}, {}
        for _, p in ipairs((pw and pw.list) or {}) do
            local b = law_bloc(d, key, p.bloc)
            if has(def.pro, b) then
                table.insert(pro, p.name)
            elseif has(def.con, b) then
                table.insert(con, p.name)
            end
        end
        return pro, con
    end
    local enacted, possible = {}, {}
    for _, def in ipairs(L.PLANET) do
        local pro, con = sides(def)
        if w.laws[def.key] then
            table.insert(enacted, {def = def, since = w.laws[def.key].since, pro = pro, con = con})
        elseif fits_world(d, key, def, tags, kind, party_bloc(d, key)) then
            table.insert(possible, {def = def, pro = pro, con = con})
        end
    end
    return {enacted = enacted, possible = possible, kind = kind}
end

local function min_weeks(d, key)
    local v = Laws.flag(d, "min_weeks", key)
    return M.max(L.MIN_WEEKS, v or 0)
end

local function planet_event(d, key, seat)
    local s = state(d)
    local Parties = part("parties")
    local pw = Parties and Parties.of(d, key)
    if not pw then
        return
    end
    local w = s.planet[key] or {laws = {}}
    s.planet[key] = w
    local lock = Laws.flag(d, "consensus", key)
    if lock and weeks_since(w.changed) < lock then
        return
    end
    local top = pw.list[1]
    for _, p in ipairs(pw.list) do
        if p.clout > top.clout then
            top = p
        end
    end
    local top_bloc = law_bloc(d, key, top.bloc)
    local planet = FindPlanet(key)
    local world = planet and d:planet_name(planet) or key
    local oppose = {}
    for lk, entry in pairs(w.laws) do
        local def = BY_KEY[lk]
        if def and has(def.con, top_bloc) and weeks_since(entry.since) >= min_weeks(d, key) then
            table.insert(oppose, def)
        end
    end
    local tags = s.wtags[key] or {}
    local kind = pw.kind
    local options = {}
    for _, def in ipairs(L.PLANET) do
        local clash = false
        for lk in pairs(w.laws) do
            local other = BY_KEY[lk]
            clash = clash or has(def.excludes, lk) or (other ~= nil and has(other.excludes, def.key))
        end
        if not w.laws[def.key] and not clash and has(def.pro, top_bloc) and fits_world(d, key, def, tags, kind,
                law_bloc(d, key, pw.list[pw.ruling].bloc)) then
            table.insert(options, def)
        end
    end
    local repeal = U.pick(oppose)
    local new = U.pick(options)
    if repeal and (not new or U.chance(50) or count(w.laws) >= L.PLANET_MAX) then
        remove(d, "planet", repeal.key, key)
        w.changed = GetCurrentTime()
        news(d, world .. ": " .. Parties.the(top.name) .. " repeals the " .. repeal.name .. ".", repeal.short, "planet", key)
        return
    end
    if new and count(w.laws) < L.PLANET_MAX then
        add(d, "planet", new.key, key)
        news(d, world .. ": " .. Parties.the(top.name) .. " passes the " .. new.name .. ".", new.short, "planet", key)
    end
end

local function spawn(d, type_name, key, n)
    local t = Find_Object_Type(type_name)
    local planet = FindPlanet(key)
    if not t or not planet or planet.Get_Owner() ~= d.human then
        return
    end
    for _ = 1, (n or 1) do
        pcall(Spawn_Unit, t, planet, d.human)
    end
end

apply_on = function(d, def, scope)
    if not def then
        return
    end
    local f = def.flags or {}
    if f.mandate then
        Republic().senate_mandate(d, f.mandate)
    end
    if f.garrison_now and scope then
        spawn(d, L.GARRISON, scope, 1)
    end
    if f.purge and scope then
        local s = state(d)
        local w = s.planet[scope]
        if w and w.laws[def.key] then
            w.laws[def.key].until_ = GetCurrentTime() + U.weeks(10)
        end
        local Sym = part("sym")
        local sector = U.sector_of(scope)
        local data = U.sector(sector)
        for _, other in ipairs((data and data.worlds) or {}) do
            local p = FindPlanet(other)
            if Sym and p and U.category(p.Get_Owner().Get_Faction_Name()) == "IMPERIAL" then
                Sym.change(d, other, -5)
            end
        end
    end
    if def.dummy then
        Laws.keep_dummies(d)
    end
    if f.volunteers then
        Laws.keep_units(d)
    end
end

apply_off = function(d, def, scope)
    if not def then
        return
    end
    local f = def.flags or {}
    if f.mandate then
        Republic().senate_mandate(d, -f.mandate)
    end
    if def.dummy then
        Laws.keep_dummies(d)
    end
    if f.volunteers then
        Laws.keep_units(d)
    end
end

function Laws.keep_dummies(d)
    local wanted = {}
    for _, def in pairs(BY_KEY) do
        if def.dummy then
            for _, t in ipairs(type(def.dummy) == "table" and def.dummy or {def.dummy}) do
                wanted[t] = wanted[t] or {}
            end
        end
    end
    local s = state(d)
    for _, a in ipairs(Laws.active(d)) do
        if a.def.dummy then
            for key in pairs(seated(d)) do
                if covers(a, key) and fits(d, key, a.def.dummy_who or "ALL") then
                    for _, t in ipairs(type(a.def.dummy) == "table" and a.def.dummy or {a.def.dummy}) do
                        wanted[t][key] = true
                    end
                end
            end
        end
    end
    for type_name, worlds in pairs(wanted) do
        local t = Find_Object_Type(type_name)
        if t then
            local have = {}
            for _, obj in pairs(Find_All_Objects_Of_Type(t) or {}) do
                if TestValid(obj) then
                    local at = obj.Get_Planet_Location()
                    local key = at and U.key(at)
                    if key and worlds[key] and not have[key] and obj.Get_Owner() == d.human and at.Get_Owner() == d.human then
                        have[key] = true
                    else
                        obj.Despawn()
                    end
                end
            end
            for key in pairs(worlds) do
                if not have[key] then
                    local planet = FindPlanet(key)
                    if planet and planet.Get_Owner() == d.human then
                        pcall(Spawn_Unit, t, planet, d.human)
                    end
                end
            end
        end
    end
    s.dummies_at = GetCurrentTime()
end

function Laws.keep_units(d)
    local open = {}
    local sentient = Laws.galactic_on(d, "SENTIENT_RIGHTS")
    local s = state(d)
    for key in pairs(seated(d)) do
        if VOLUNTEERS[key] and ((sentient and nonhuman(key)) or (s.planet[key] and s.planet[key].laws.MOOT)) then
            open[key] = true
        end
    end
    s.units = s.units or {}
    for key, v in pairs(VOLUNTEERS) do
        local want = open[key] == true
        if (s.units[key] == true) ~= want then
            local t = Find_Object_Type(v.type)
            if t then
                if want then
                    d.human.Unlock_Tech(t)
                else
                    d.human.Lock_Tech(t)
                end
            end
            s.units[key] = want or nil
        end
    end
end

function Laws.on_joined(d, key)
    if gflag(d, "garrison_join") then
        spawn(d, L.GARRISON, key, 1)
    end
end

function Laws.mark_occupied(d, key)
    local s = state(d)
    if s then
        s.occupied = s.occupied or {}
        s.occupied[key] = true
    end
end

function Laws.on_conquest(d, key, old_owner)
    if not founded(d) then
        return
    end
    local cat = U.category(old_owner or "")
    if cat ~= "IMPERIAL" and cat ~= "WARLORD" then
        return
    end
    local Sym = part("sym")
    local amnesty = gflag(d, "amnesty")
    if amnesty then
        if Sym then
            Sym.change(d, key, 5, old_owner)
        end
        local ok_i, Intel = pcall(require, "eawx-plugins/new-republic/RepublicIntel")
        local came = {}
        if ok_i and Intel and Intel.heroes then
            for _, hero in ipairs(Intel.heroes(old_owner, d) or {}) do
                if U.chance(amnesty) and Intel.defect(d, old_owner, hero.type) then
                    table.insert(came, hero.name)
                end
            end
        end
        if came[1] then
            d.show("Imperial Amnesty Act: " .. table.concat(came, ", ") .. " came over to the Republic.", nil, COLOR, 20)
        end
    end
    if gflag(d, "tribunals") and Sym then
        Sym.change(d, key, -10, old_owner)
    end
    local planet = FindPlanet(key)
    for _, a in ipairs(Laws.active(d)) do
        local f = a.def.flags or {}
        if f.memorial and a.sector and planet and Sym then
            local near = false
            local data = U.sector(a.sector)
            for _, w in ipairs((data and data.worlds) or {}) do
                local p = FindPlanet(w)
                if p and p.Get_Owner() == d.human then
                    local ok, path = pcall(Find_Path, d.human, p, planet)
                    if ok and type(path) == "table" and table.getn(path) - 1 <= 2 then
                        near = true
                        break
                    end
                end
            end
            if near then
                Sym.change(d, key, f.memorial, old_owner)
            end
        end
    end
end

function Laws.on_hero_killed(d, owner_name, killer_name)
    local v = gflag(d, "tribunals")
    if not v or string.upper(killer_name or "") ~= string.upper(d.human.Get_Faction_Name()) then
        return
    end
    local cat = U.category(owner_name or "")
    if cat ~= "IMPERIAL" and cat ~= "WARLORD" then
        return
    end
    local Desires, Senate = part("desires"), Republic().senate
    for key, seat in pairs((Senate and Senate.seats(d)) or {}) do
        local b = bloc_of_seat(seat)
        if (b == "LIBERATION" or b == "AGGRIEVED") and Desires then
            Desires.boost(d, key, v, 10, "an Imperial war criminal brought down")
        end
    end
end

local last_tick = 0
function Laws.tick(d)
    if not founded(d) or GetCurrentTime() - last_tick < 5 then
        return
    end
    last_tick = GetCurrentTime()
    local s = state(d)
    for _, a in ipairs(Laws.active(d)) do
        local f = a.def.flags or {}
        if f.militia and a.world and GetCurrentTime() - (s.militia[a.world] or -U.weeks(f.militia)) >= U.weeks(f.militia) then
            local planet = FindPlanet(a.world)
            local battle = Engine_Battle_Planet and Engine_Battle_Planet()
            if planet and planet.Get_Owner() == d.human and not (battle and string.upper(tostring(battle)) == a.world) then
                local threatened = false
                for faction, rel in pairs(d.relations or {}) do
                    if rel == "WAR" and not threatened then
                        local p = Find_Player(faction)
                        if p and U.strength_at(p, planet) > 0 then
                            threatened = true
                        end
                    end
                end
                if threatened then
                    s.militia[a.world] = GetCurrentTime()
                    spawn(d, L.GARRISON, a.world, 2)
                    d.show("Self-Defence Force: " .. d:planet_name(planet) .. " raises its militia against the enemy fleet.",
                        nil, COLOR, 15)
                end
            end
        end
    end
end

local function perceive(d, name)
    local ok, v = pcall(EvaluatePerception, name, d.human)
    return (ok and type(v) == "number") and v or 0
end

local function credits(d, seats)
    local S = part("sectors")
    local s = state(d)
    local trade = trade_ports(d)
    local total = 0
    local cache = {}
    local function income(key, kind)
        local c = cache[key]
        if not c then
            local planet = seats[key] and seats[key].planet
            local ok, base = false, 0
            if planet then
                ok, base = pcall(EvaluatePerception, "PlanetBaseIncome", d.human, planet)
            end
            c = {base = M.max(0, M.sane((ok and base) or 0)), trade = trade[key] or 0,
                 mining = ((s.mines or {})[key] or 0) * L.MINING_INCOME}
            c.all = c.base + c.trade + c.mining
            cache[key] = c
        end
        return c[kind] or 0
    end
    for _, a in ipairs(Laws.active(d)) do
        local def = a.def
        total = total + (def.credits or 0)
        for _, inc in ipairs(def.income or {}) do
            for key in pairs(seats) do
                if covers(a, key) and fits(d, key, inc[3]) then
                    total = total + income(key, inc[1]) * inc[2] / 100
                end
            end
        end
        if def.flags and def.flags.purge and a.entry.until_ and GetCurrentTime() < a.entry.until_ then
            total = total - income(a.world, "all") * 0.2
        end
    end
    local pct = upkeep_pct(d)
    if pct > 0 then
        local upkeep = M.floor(perceive(d, "Total_Maintenance")) - 10 * perceive(d, "LightFactory_Count")
            - 20 * perceive(d, "HeavyFactory_Count") - 30 * perceive(d, "AdvFactory_Count")
        total = total - M.max(0, upkeep) * pct / 100
    end
    total = M.round(total)
    if total ~= 0 then
        d.human.Give_Money(total)
    end
    s.last_credits = total
end

function Laws.last_credits(d)
    local s = d.republic and d.republic.laws
    return (s and s.last_credits) or 0
end

local function border_sympathy(d, seats)
    local Sym = part("sym")
    if not Sym then
        return
    end
    for _, a in ipairs(Laws.active(d)) do
        local v = a.def.flags and a.def.flags.border_sympathy
        if v then
            local done = {}
            for key, seat in pairs(seats) do
                if covers(a, key) then
                    for _, other in ipairs(neighbours(d, seat.planet)) do
                        local p = FindPlanet(other)
                        if p and not done[other] and U.category(p.Get_Owner().Get_Faction_Name()) == "INDEPENDENT" then
                            done[other] = true
                            Sym.change(d, other, v)
                        end
                    end
                end
            end
        end
    end
end

function Laws.week(d, seated_planets)
    local s = state(d)
    if not s or not founded(d) then
        return
    end
    local Senate = Republic().senate
    local seats = Senate and Senate.seats(d) or {}
    for key in pairs(s.planet) do
        if not seated_planets[key] then
            s.planet[key] = nil
        end
    end
    pcall(retag, d, seats)
    for key, entry in pairs(s.galactic) do
        local def = BY_KEY[key]
        if not def or (def.lapse and weeks_since(entry.since) >= def.lapse) or (def.jedi and not jedi_founded(d)) then
            remove(d, "galactic", key)
            if def then
                news(d, "The " .. def.name .. " has lapsed.", def.short, "galactic")
            end
        end
    end
    for _, a in ipairs(Laws.active(d)) do
        local b = a.def.build
        if b then
            a.entry.built = a.entry.built or {}
            for key in pairs(seats) do
                if covers(a, key) and fits(d, key, b[1]) then
                    local v = (a.entry.built[key] or 0) + b[2]
                    a.entry.built[key] = M.max(-b[3], M.min(b[3], v))
                end
            end
        end
        if a.def.capital then
            d.republic.capital = M.max(0, M.min(R.CAPITAL_MAX, (d.republic.capital or 0) + a.def.capital))
        end
        local f = a.def.flags or {}
        if f.guard and a.world and weeks_since(s.guard[a.world]) >= f.guard then
            if s.guard[a.world] then
                spawn(d, L.ELITE, a.world, 1)
            end
            s.guard[a.world] = GetCurrentTime()
        end
    end
    pcall(credits, d, seats)
    pcall(border_sympathy, d, seats)
    pcall(sector_week, d, seats)
    for key, seat in pairs(seats) do
        if U.chance(L.EVENT_CHANCE) then
            pcall(planet_event, d, key, seat)
        end
    end
    Laws.keep_dummies(d)
    Laws.keep_units(d)
end

return Laws
