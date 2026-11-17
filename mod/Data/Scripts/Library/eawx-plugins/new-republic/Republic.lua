local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local Occupation = require("eawx-plugins/diplomacy/DiplomacyOccupation")
local POPULATIONS = require("eawx-plugins/diplomacy/DiplomacyPopulations")
local geo_ok, GEO = pcall(require, "eawx-plugins/imperial-court/CourtGeo")
if not geo_ok or type(GEO) ~= "table" then
    GEO = {}
end

local Republic = {CONFIG = R}

local PARTS = {prot = "RepublicProtectorates", sectors = "RepublicSectors", members = "RepublicMembers",
               gov = "RepublicGovernment", sym = "RepublicSympathy", intel = "RepublicIntel", events = "RepublicEvents",
               council = "RepublicCouncil", envoys = "RepublicEnvoys", influence = "RepublicInfluence",
               desires = "RepublicDesires", blocs = "RepublicBlocs", parties = "RepublicParties", focus = "RepublicFocus",
               jedi = "JediOrder", laws = "RepublicLaws"}
local loaded = {}
local function part(name)
    if loaded[name] == nil then
        local ok, mod = pcall(require, (PARTS[name] == "JediOrder") and "eawx-plugins/jedi-order/JediOrder"
        or ("eawx-plugins/new-republic/" .. PARTS[name]))
        loaded[name] = (ok and type(mod) == "table") and mod or false
    end
    return loaded[name] or nil
end
Republic.part = part

local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}

local function weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

local function sqrt(x)
    if x <= 0 then
        return 0
    end
    local r = x
    for _ = 1, 20 do
        r = (r + x / r) / 2
    end
    return r
end

local function clamp(x, low, high)
    return M.max(low, M.min(high, x))
end

local function key_of(planet)
    return string.upper(planet.Get_Type().Get_Name())
end

function Republic.setup(d)
    if d.republic then
        return d.republic
    end
    local r = {mandate = R.MANDATE_START, capital = R.CAPITAL_START, conquered = {}, founding = {}, senators = {},
               declared = {}, alarm = nil, salt = {}}
    local wanted = {}
    for _, name in ipairs(R.FOUNDING) do
        wanted[name] = true
    end
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local name = key_of(planet)
        if wanted[name] and planet.Get_Owner() == d.human then
            r.founding[name] = true
        end
    end
    d.republic = r
    local Council = part("council")
    if Council then
        Council.state(d)
    end
    return r
end

function Republic.council(d)
    local Council = part("council")
    return Council ~= nil and Council.active(d)
end

function Republic.is_territory(name)
    local geo = GEO[name]
    return not POPULATIONS[name] or (geo ~= nil and geo.station == true)
end

function Republic.is_founding(d, name)
    return d.republic ~= nil and d.republic.founding[name] == true
end

function Republic.status(d, name, seated)
    if Republic.is_territory(name) then
        return "territory"
    elseif seated then
        return Republic.is_founding(d, name) and "founding" or "member"
    elseif d.republic and d.republic.conquered[name] then
        return "occupied"
    end
    return "unrepresented"
end

Republic.STATUS_NAMES = {founding = "Founding member", member = "Member world", occupied = "Occupied",
                         unrepresented = "Unrepresented", territory = "Territory"}

function Republic.counts(d, seated)
    local r = d.republic
    if not r then
        return 0, 0
    end
    if r.counts and GetCurrentTime() - r.counts.time < 3 then
        return r.counts.occupied, r.counts.territories
    end
    local occupied, territories = 0, 0
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == d.human then
            local status = Republic.status(d, key_of(planet), seated and seated[key_of(planet)])
            if status == "occupied" then
                occupied = occupied + 1
            elseif status == "territory" then
                territories = territories + 1
            end
        end
    end
    r.counts = {time = GetCurrentTime(), occupied = occupied, territories = territories}
    return occupied, territories
end

function Republic.vote_weight(d, name)
    local Laws = part("laws")
    return (Republic.is_founding(d, name) and R.FOUNDING_WEIGHT or 1) * ((Laws and Laws.weight(d, name)) or 1)
end

function Republic.opinion_bonus(d, name, bloc)
    local value = Republic.is_founding(d, name) and R.FOUNDING_OPINION or 0
    local S, Members, Gov = part("sectors"), part("members"), part("gov")
    if S then
        value = value + S.opinion(d, name)
    end
    if Members then
        value = value + Members.opinion(d, name)
    end
    if Gov then
        value = value + Gov.opinion(d, name, bloc)
    end
    local Desires = part("desires")
    if Desires then
        value = value + Desires.opinion(d, name)
    end
    local Parties, Focus = part("parties"), part("focus")
    if Parties and not Republic.council(d) then
        value = value + (Parties.opinion(d, name))
    end
    if Focus and not Republic.council(d) then
        value = value + Focus.opinion(d, name)
    end
    local Laws = part("laws")
    if Laws and not Republic.council(d) then
        value = value + (Laws.opinion(d, name, bloc))
    end
    return value
end

function Republic.seat_vote(d, seat, motion)
    if motion.kind == "TAX" then
        local S, Members = part("sectors"), part("members")
        if S then
            return S.vote(d, seat, motion, Members and Members.interests(d, seat.name), Republic.at_war(d))
        end
        return 0
    elseif motion.kind == "APPROPRIATION" or motion.kind == "BILL" or motion.kind == "NO_CONFIDENCE" then
        local Gov = part("gov")
        return Gov and Gov.vote(d, seat, motion) or 0
    end
    local rules = CONFIG.SENATE
    if seat.opinion >= rules.LOYAL_OPINION or seat.opinion <= rules.HOSTILE_OPINION then
        return nil
    end
    local Members = part("members")
    if not Members then
        return nil
    end
    if motion.kind == "WAR" then
        if Members.has(d, seat.name, "Pacifist") then
            return -1
        end
        local U = require("eawx-plugins/new-republic/RepublicUtil")
        local kind = U.category(motion.target or "")
        if (kind == "IMPERIAL" or kind == "WARLORD") and (Members.has(d, seat.name, "Liberation")
                or Members.has(d, seat.name, "Reparations")) then
            return 1
        end
    elseif motion.kind == "TREATY" then
        if Members.has(d, seat.name, "Commerce") or Members.has(d, seat.name, "Pacifist") then
            return 1
        end
    end
    return nil
end

function Republic.adjust_vote(d, seat, motion, vote)
    local Intel, Gov = part("intel"), part("gov")
    if Intel then
        vote = Intel.adjust_vote(d, seat, vote, motion)
    end
    if vote < 0 and Gov and Gov.agenda(d) == "ADMISSIONS" and seat.opinion >= 0
            and (motion.kind == "ADMIT_MEMBER" or motion.kind == "ADMIT_ASSOCIATE") then
        vote = 0
    end
    return vote
end

function Republic.must_abstain(d, seat)
    local s = d.republic and d.republic.intel
    return s ~= nil and not s.net and s.abstain ~= nil and (s.abstain[seat.name] or -1) >= (s.week or 0)
end

function Republic.cares_for_defence(d, seat)
    local Blocs, Members = part("blocs"), part("members")
    return (Blocs ~= nil and Blocs.key_of(seat.bloc) == "FRONTIER")
        or (Members ~= nil and Members.has(d, seat.name, "Security")) or false
end

function Republic.pass_rule(d, motion, result)
    if result.yes + result.no + result.abstain < R.SUPERMAJORITY_SEATS then
        return result.passed
    end
    local Laws = part("laws")
    if motion.kind == "WAR" and Laws and Laws.war_majority(d) then
        return result.passed
    end
    if motion.kind == "WAR" or motion.kind == "ADMIT_MEMBER" or motion.kind == "ADMIT_ASSOCIATE" then
        local cast = result.weighed_yes + result.weighed_no
        return cast > 0 and result.weighed_yes >= R.SUPERMAJORITY * cast
    end
    return result.passed
end

function Republic.admission_bonus(d)
    local Gov = part("gov")
    return (Gov and Gov.agenda(d) == "ADMISSIONS") and 2 or 0
end

function Republic.at_war(d)
    for _ in pairs((d.republic and d.republic.declared) or {}) do
        return true
    end
    return d.senate ~= nil and next(d.senate.approved or {}) ~= nil
end

function Republic.watching(d)
    local Intel = part("intel")
    return Intel ~= nil and Intel.watching(d)
end

function Republic.motions(d)
    local out = {}
    local P, S = part("prot"), part("sectors")
    if P then
        for _, world in ipairs(P.petitions(d)) do
            local planet = FindPlanet(world)
            local name = planet and d:planet_name(planet) or world
            table.insert(out, {kind = "ADMIT_ASSOCIATE", world = world, petition = true, target = "INDEPENDENT_FORCES",
                group = "ASSOCIATE", label = name, text = "make " .. name .. " an associate world",
                tip = name .. ", under the Republic's protection, has done its part and petitions to become an "
                    .. "associate: it pays its share and sends ships."})
        end
    end
    for world, appeal in pairs(d.appeals or {}) do
        local planet = FindPlanet(world)
        if planet and GetCurrentTime() < appeal.expires then
            local name = d:planet_name(planet)
            table.insert(out, {kind = "ADMIT_ASSOCIATE", world = world, petition = true, join = true,
                target = "INDEPENDENT_FORCES", group = "JOIN", label = name,
                text = "take " .. name .. " under the Republic's protection",
                tip = "The people of " .. name .. " ask to join the Republic. If the motion passes, the world takes "
                    .. "the Republic's protection at once."})
        end
    end
    if S then
        for _, m in ipairs(S.motions(d, Republic.seated_planets(d))) do
            table.insert(out, m)
        end
    end
    local Jedi = part("jedi")
    for _, m in ipairs(Jedi and Jedi.motions(d) or {}) do
        table.insert(out, m)
    end
    local Laws = part("laws")
    for _, m in ipairs(Laws and Laws.repeal_motions(d) or {}) do
        table.insert(out, m)
    end
    return out
end

function Republic.seated_planets(d)
    local out = {}
    for key, seat in pairs((Republic.senate and d.senate and Republic.senate.seats(d)) or {}) do
        out[key] = seat.planet
    end
    return out
end

function Republic.enacts(motion)
    return motion.kind == "TAX" or (motion.kind == "ADMIT_ASSOCIATE" and motion.petition == true)
        or motion.kind == "JEDI_RESTRAIN" or motion.kind == "JEDI_FUND" or motion.kind == "FOCUS"
        or motion.kind == "LAW" or motion.kind == "SREPEAL"
end

function Republic.enact_motion(d, motion)
    if motion.kind == "TAX" then
        local S = part("sectors")
        if S then
            S.enact(d, motion)
        end
    elseif motion.kind == "ADMIT_ASSOCIATE" and motion.petition then
        local P = part("prot")
        local planet = motion.join and FindPlanet(motion.world)
        if P and planet then
            P.protect_world(d, planet, d:planet_name(planet))
        elseif P and not motion.join then
            P.make_associate(d, motion.world)
        end
    elseif motion.kind == "FOCUS" then
        local Focus = part("focus")
        if Focus then
            Focus.enact(d, motion)
        end
    elseif motion.kind == "JEDI_RESTRAIN" or motion.kind == "JEDI_FUND" then
        local Jedi = part("jedi")
        if Jedi then
            Jedi.enact(d, motion)
        end
    elseif motion.kind == "LAW" or motion.kind == "SREPEAL" then
        local Laws = part("laws")
        if Laws then
            Laws.enact(d, motion)
        end
    end
end

function Republic.secession_rules(d, name, threshold, needed)
    if Republic.is_founding(d, name) then
        return M.min(threshold, R.FOUNDING_SECESSION_OPINION), M.max(needed, R.FOUNDING_SECESSION_WEEKS)
    end
    return threshold, needed
end

function Republic.mandate(d)
    return d.republic and M.round(d.republic.mandate) or R.MANDATE_START
end

function Republic.capital(d)
    local r = d.republic
    if not r then
        return 0
    end
    r.capital = clamp(r.capital, 0, R.CAPITAL_MAX)
    return M.floor(r.capital)
end

function Republic.change_mandate(d, amount)
    local r = d.republic
    if r and Republic.council(d) then
        r.mandate = clamp(r.mandate + amount, 0, 100)
    end
end

function Republic.senate_mandate(d, amount)
    local r = d.republic
    if not r or Republic.council(d) then
        return false
    end
    r.mandate = clamp(r.mandate + amount, 0, 100)
    return true
end

local LUKE = {"LUKE_SKYWALKER_JEDI", "LUKE_SKYWALKER_JEDI_TEAM", "LUKE_JEDI_XWING"}
function Republic.luke_lost(d)
    local r = d.republic
    if not r or r.jedi_founded then
        return false
    end
    for _, t in ipairs(LUKE) do
        local obj = Find_Object_Type(t) and Find_First_Object(t)
        if obj and TestValid(obj) then
            r.luke_seen = true
            return false
        end
    end
    return r.luke_seen == true
end

function Republic.spend(d, amount)
    local r = d.republic
    if not r or r.capital < amount then
        return false
    end
    r.capital = clamp(r.capital - amount, 0, R.CAPITAL_MAX)
    return true
end

function Republic.capital_income(d, seats)
    local Council = part("council")
    if Council and Council.active(d) then
        return Council.capital_week(d)
    end
    local income = R.CAPITAL_BASE + R.CAPITAL_PER_ROOT_SEAT * sqrt(seats) - R.CAPITAL_UPKEEP_PER_SEAT * seats
    return M.max(0, income) + Republic.cohesion_capital(d)
end

function Republic.cohesion_capital(d)
    local cohesion = (d.senate and d.senate.stability) or 50
    for _, step in ipairs(R.SENATE.CAPITAL_COHESION) do
        if cohesion >= step[1] then
            return step[2]
        end
    end
    return 0
end

function Republic.founding_cohesion(d)
    local b = d.senate and d.senate.cohesion_boost
    if not b then
        return 0
    end
    return M.max(0, b.v - M.floor((GetCurrentTime() - b.t0) / weeks(1)))
end

function Republic.weariness(d)
    local n = 0
    for _ in pairs((d.republic and d.republic.declared) or {}) do
        n = n + 1
    end
    local value = M.min(R.WEARINESS_MAX, n * R.WEARINESS_PER_WAR)
    local Gov = part("gov")
    if Gov then
        value = Gov.weariness(d, value)
    end
    local Laws = part("laws")
    if Laws and not Republic.council(d) then
        value = Laws.weariness(d, value)
    end
    return value
end

function Republic.cohesion_parts(d, seats)
    local Gov = part("gov")
    local Council = part("council")
    local c = Council and d.republic and Council.state(d)
    local solo = Republic.council(d)
    local out = {{"base", R.COHESION_BASE}}
    local function add(label, value)
        value = M.round(value or 0)
        if value ~= 0 then
            table.insert(out, {label, value})
        end
    end
    add("a chamber of " .. seats .. " seats", -R.COHESION_PER_ROOT_SEAT * sqrt(seats))
    add("the wars the Republic declared", -Republic.weariness(d))
    if Gov then
        add("the cabinet (Justice, empty posts)", Gov.cohesion_bonus(d))
    end
    add("the constitution", (c and c.constitution == "ENDURES") and Council.CONFIG.CONSTITUTION_COHESION or 0)
    add("the founding (fading)", Republic.founding_cohesion(d))
    if part("focus") and not solo then
        add("the Senate's focus", part("focus").cohesion(d))
    end
    if part("laws") and not solo then
        add("the galactic laws", part("laws").cohesion(d))
    end
    return out
end

function Republic.cohesion_target(d, seats)
    local total = 0
    for _, p in ipairs(Republic.cohesion_parts(d, seats)) do
        total = total + p[2]
    end
    return M.max(R.COHESION_MIN_TARGET, M.round(total))
end

function Republic.cohesion_breakdown(d, seats)
    local parts, total = {}, 0
    for k, p in ipairs(Republic.cohesion_parts(d, seats)) do
        total = total + p[2]
        table.insert(parts, (k == 1) and ("base " .. p[2]) or (p[1] .. " " .. ((p[2] > 0) and "+" or "") .. p[2]))
    end
    local floor = (total < R.COHESION_MIN_TARGET) and (", never under " .. R.COHESION_MIN_TARGET) or ""
    return "Its target: " .. table.concat(parts, ", ") .. floor .. ". Each week it moves towards it, up "
        .. R.COHESION_RECOVERY .. " or down " .. R.COHESION_DECAY .. "; events, broken promises and overridden votes "
        .. "move it at once."
end

function Republic.attitude(d, faction)
    local r = d.republic
    if not r then
        return 0
    end
    local att = 0
    local Envoys, Council = part("envoys"), part("council")
    if Envoys then
        att = att + Envoys.opinion(d, faction)
    end
    local U = require("eawx-plugins/new-republic/RepublicUtil")
    if Council and Council.state(d).constitution == "ALL" and U.category(faction) == "INDEPENDENT" then
        att = att + Council.CONFIG.CONSTITUTION_OPINION
    end
    local Jedi = part("jedi")
    if Jedi then
        att = att + Jedi.attitude(d)
    end
    local Gov = part("gov")
    if Gov and Gov.agenda(d) == "CORELLIA" and d.relations and d:relation(faction) ~= "WAR" then
        att = att + 5
    end
    local Laws = part("laws")
    if Laws then
        att = att + Laws.attitude(d, faction)
    end
    if not Occupation.applies(d.human.Get_Faction_Name(), faction) then
        return att
    end
    if r.alarm then
        local left = 1 - (GetCurrentTime() - r.alarm) / weeks(R.ALARM_WEEKS)
        if left > 0 then
            att = att - M.round(R.ALARM_ATTITUDE * left)
        end
    end
    if r.alarm_minor then
        local left = 1 - (GetCurrentTime() - r.alarm_minor) / weeks(R.ALARM_WEEKS)
        if left > 0 then
            att = att - M.round(R.ALARM_ATTITUDE * left / 4)
        end
    end
    return att
end

function Republic.on_conquest(d, name, readable, old_owner)
    local r = d.republic
    if not r or not old_owner then
        return false
    end
    local against_free = Occupation.applies(d.human.Get_Faction_Name(), old_owner)
    r.lost = r.lost or {}
    if r.lost[name] and GetCurrentTime() - r.lost[name] < weeks(R.RECLAIM_WEEKS) then
        against_free = false
    end
    local Council_part = part("council")
    if Council_part and Council_part.sanctioned and Council_part.sanctioned(d, name) then
        against_free = false
    end
    if not Republic.is_territory(name) then
        r.conquered[name] = {time = GetCurrentTime(), free = against_free}
        r.counts = nil
    end
    r.politics = r.politics or {}
    r.politics.taken = GetCurrentTime()
    local kind = require("eawx-plugins/new-republic/RepublicUtil").category(old_owner)
    if kind == "IMPERIAL" or kind == "WARLORD" then
        r.politics.freed = GetCurrentTime()
        r.freed_worlds = r.freed_worlds or {}
        r.freed_worlds[name] = true
    elseif against_free then
        r.politics.invaded = GetCurrentTime()
    end
    local Members = part("members")
    if Members then
        pcall(Members.on_conquest, d, old_owner)
    end
    local Laws = part("laws")
    if Laws then
        pcall(Laws.on_conquest, d, name, old_owner)
    end
    local Sym, Council = part("sym"), part("council")
    local value = Sym and not Republic.is_territory(name) and Sym.value(d, name, old_owner)
    if value and r.amnesty and (kind == "IMPERIAL" or kind == "WARLORD") then
        Sym.change(d, name, R.AMNESTY.SYMPATHY, old_owner)
        value = Sym.value(d, name, old_owner)
    end
    if Council and not value and Council.home_freed then
        pcall(Council.home_freed, d, name)
    end
    if Sym and Council and value then
        local band = Council.on_conquest(d, name, readable, old_owner, value)
        if band == "SYMPATHETIC" then
            r.conquered[name].content = true
            against_free = false
            Occupation.stop(d, name)
        elseif band == "HOSTILE" and not against_free then
            r.alarm_minor = GetCurrentTime()
        end
    end
    if not against_free then
        return false
    end
    r.alarm = GetCurrentTime()
    if d.senate and not Republic.council(d) then
        d.senate.stability = M.max(0, d.senate.stability - R.INVASION_COHESION)
    end
    if d.reputation_drop and GetCurrentTime() >= (r.next_reputation_drop or 0) then
        r.next_reputation_drop = GetCurrentTime() + weeks(1)
        d:reputation_drop(d.human.Get_Faction_Name(), 1, "invaded " .. readable .. ", a free world")
    end
    d.show("The galaxy watches: the " .. d.display_name("REBEL") .. " invaded " .. readable .. ", a world that never "
        .. "threatened it. Independent worlds and free powers trust it less.", nil, WARN, 25)
    return true
end

local REVOLT_TEXT = {
    JOINED = {"The people of {world} rise against {old} and raise the {us}'s banner over their capital.",
              "On {world}, crowds storm the Imperial garrison. By nightfall the {us}'s colours fly from every spire.",
              "{world} casts off {old}'s rule and asks to stand with the {us}. Its people have chosen."},
    FREE = {"{world} throws off {old}'s rule and declares itself free. Its people answer to no one now.",
            "The Imperial governor of {world} flees as the planet declares its independence from {old}.",
            "{world} rises against {old}. It wants no masters, the {us} included, but it is free."},
    SWITCHED = {"{world} rises against {old}, and the rebels open its gates to {new}.",
                "The garrison on {world} turns its guns on {old}'s officers and goes over to {new}."},
    LORD = {"An Imperial lord breaks with {old}: {world} and the worlds around it go over to {new}.",
            "The Empire's heirs turn on each other again. {new} takes {world} without a shot fired."},
}
local revolt_said = {}

local function fill_revolt(d, text, readable, old, new)
    text = string.gsub(text, "{world}", readable)
    text = string.gsub(text, "{old}", d.display_name(old))
    text = string.gsub(text, "{new}", d.display_name(new))
    return (string.gsub(text, "{us}", d.display_name("REBEL")))
end

function Republic.on_revolt_seen(d, key, readable, old, new, kind)
    local U = require("eawx-plugins/new-republic/RepublicUtil")
    local from = U.category(old or "")
    if not d.republic or not old or not new or kind == "BREAKAWAY" or (from ~= "IMPERIAL" and from ~= "WARLORD") then
        return
    end
    local lines
    if kind == "LORD" then
        if revolt_said[new] and GetCurrentTime() - revolt_said[new] < 10 then
            return
        end
        revolt_said[new] = GetCurrentTime()
        if (d.memory and d.memory.breakaway_news or {})[new] then
            return
        end
        lines = REVOLT_TEXT.LORD
    elseif new == d.human.Get_Faction_Name() then
        lines = REVOLT_TEXT.JOINED
    elseif U.category(new) == "INDEPENDENT" then
        lines = REVOLT_TEXT.FREE
    else
        lines = REVOLT_TEXT.SWITCHED
    end
    local color = (new == d.human.Get_Faction_Name()) and {r = 255, g = 225, b = 140} or {r = 170, g = 200, b = 255}
    d.show("Revolt: " .. fill_revolt(d, U.pick(lines), readable, old, new), nil, color, 25)
end

local BREAKAWAY_TEXT = {
    "{leader} breaks with the Empire and proclaims {faction}: {n} under a new banner. Another heir of the Emperor "
        .. "carves out a throne, and the Imperial remnant grows weaker.",
    "{faction} is born: {leader} takes {n} out of the Empire. Coruscant's grip loosens a little more.",
    "{leader} answers to no Emperor now. {faction} declares independence with {n}, and the Empire bleeds again.",
}
function Republic.on_breakaway(d, faction, display, leader, worlds)
    if not d.republic then
        return
    end
    d.memory = d.memory or {}
    d.memory.breakaway_news = d.memory.breakaway_news or {}
    if d.memory.breakaway_news[faction] then
        return
    end
    d.memory.breakaway_news[faction] = true
    local n = table.getn(worlds or {})
    for _, w in ipairs(worlds or {}) do
        local mark = DIPLOMACY_REVOLTS and DIPLOMACY_REVOLTS[string.upper(w)]
        if mark then
            mark.kind = "BREAKAWAY"
        end
    end
    local text = require("eawx-plugins/new-republic/RepublicUtil").pick(BREAKAWAY_TEXT)
    text = string.gsub(text, "{leader}", leader or display)
    text = string.gsub(text, "{faction}", display or faction)
    text = string.gsub(text, "{n}", n .. ((n == 1) and " world" or " worlds"))
    d.show("Breakaway: " .. text, nil, {r = 170, g = 200, b = 255}, 25)
end

function Republic.on_world_lost(d, name)
    local r = d.republic
    if not r then
        return
    end
    local Council = part("council")
    if Council then
        pcall(Council.on_world_lost, d, name)
    end
    r.conquered[name] = nil
    r.founding[name] = nil
    r.lost = r.lost or {}
    r.lost[name] = GetCurrentTime()
    r.politics = r.politics or {}
    r.politics.lost = GetCurrentTime()
    if r.senators[name] then
        r.senators[name] = nil
        r.salt[name] = (r.salt[name] or 0) + 1
    end
    r.counts = nil
end

function Republic.on_relation(d, faction, relation)
    local r = d.republic
    if not r then
        return
    end
    local Council = part("council")
    if Council then
        pcall(Council.on_relation, d, faction, relation)
    end
    if relation == "WAR" then
        r.declared[faction] = true
        local Members = part("members")
        if Members then
            pcall(Members.on_war, d)
        end
    else
        r.declared[faction] = nil
    end
end

function Republic.week(d, seated)
    local r = d.republic
    if not r then
        return
    end
    pcall(Republic.luke_lost, d)
    local seats = 0
    for _ in pairs(seated) do
        seats = seats + 1
    end
    local council = Republic.council(d)
    for name, entry in pairs(r.conquered) do
        local planet = FindPlanet(name)
        if not planet or planet.Get_Owner() ~= d.human then
            r.conquered[name] = nil
        elseif seated[name] then
            r.conquered[name] = nil
            if not entry.content and part("laws") then
                part("laws").mark_occupied(d, name)
            end
            local Focus = part("focus")
            if Focus then
                pcall(Focus.seated, d, name)
            end
            d.show("Republic: " .. d:planet_name(planet) .. " has a Senator's Office at last. Its people send a senator "
                .. "to the chamber, and the occupation ends.", nil, COLOR)
        end
    end
    r.counts = nil
    local Laws = part("laws")
    if Laws and not council and next(r.seated or {}) then
        for key in pairs(seated) do
            if not r.seated[key] then
                pcall(Laws.on_joined, d, key)
            end
        end
    end
    if not council then
        r.capital = clamp(r.capital + Republic.capital_income(d, seats), 0, R.CAPITAL_MAX)
    end
    r.seated = {}
    for key, _ in pairs(seated) do
        r.seated[key] = true
    end
    Republic.week_parts(d, seated)
    if d.senate and not council then
        local target = Republic.cohesion_target(d, seats)
        local now = d.senate.stability
        if now < target then
            d.senate.stability = M.min(target, now + R.COHESION_RECOVERY)
        elseif now > target then
            d.senate.stability = M.max(target, now - R.COHESION_DECAY)
        end
    end
end

local SENATE_ONLY = {sectors = true, members = true, parties = true, focus = true, gov = true, events = true, laws = true}

function Republic.week_parts(d, seated)
    local steps = {
        {"council", "week"}, {"prot", "week"}, {"prot", "check_associates"}, {"sectors", "week", true},
        {"members", "week", true}, {"parties", "week", true}, {"focus", "week"}, {"gov", "week", true}, {"envoys", "week"}, {"sym", "week"}, {"intel", "week"},
        {"events", "week"}, {"jedi", "week"}, {"laws", "week", true},
    }
    local council = Republic.council(d)
    for _, step in ipairs(steps) do
        local mod = not (council and SENATE_ONLY[step[1]]) and part(step[1])
        if mod and mod[step[2]] then
            local ok, err
            if step[3] then
                ok, err = pcall(mod[step[2]], d, seated)
            else
                ok, err = pcall(mod[step[2]], d)
            end
            if not ok and Engine_Log then
                Engine_Log("REPUBLIC " .. step[1] .. "." .. step[2] .. ": " .. tostring(err))
            end
        end
    end
end

local function hash(text)
    local h = 7
    for i = 1, string.len(text) do
        h = h * 31 + string.byte(text, i)
        h = h - M.floor(h / 1000003) * 1000003
    end
    return h
end

local function pick(list, h)
    return list[h - M.floor(h / table.getn(list)) * table.getn(list) + 1]
end

local function lore_senator(name)
    local year = GlobalValue.Get("GALACTIC_YEAR") or 0
    local chief = string.upper(tostring(GlobalValue.Get("ChiefOfState") or ""))
    for _, entry in ipairs(R.LORE_SENATORS[name] or {}) do
        local busy = entry[1] == "Leia Organa" and string.find(chief, "LEIA")
        if year >= entry[2] and year <= entry[3] and not busy then
            return entry[1], entry[4]
        end
    end
    return nil
end

function Republic.senator(d, name)
    local r = d.republic
    if not r then
        return nil
    end
    local known = r.senators[name]
    if known then
        return known.name, known.species
    end
    local salt = r.salt[name] or 0
    local person, species = nil, nil
    if salt == 0 then
        person, species = lore_senator(name)
    end
    if not person then
        species = R.SPECIES[name] or "Human"
        local pool = R.NAMES[species] or R.NAMES.Human
        local taken = {}
        for _, s in pairs(r.senators) do
            taken[s.name] = true
        end
        for try = 0, 12 do
            local h = hash(name .. "#" .. salt .. "/" .. try)
            if pool.single then
                person = pick(pool.single, h)
            else
                person = pick(pool.first, h) .. " " .. pick(pool.last, hash(name .. "*" .. salt .. "/" .. try))
            end
            if not taken[person] then
                break
            end
        end
    end
    r.senators[name] = {name = person, species = species}
    return person, species
end

return Republic
