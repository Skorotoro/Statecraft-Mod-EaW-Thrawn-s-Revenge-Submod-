require("PGSpawnUnits")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")

local Order = {}
STEALTH_PREFIXES = STEALTH_PREFIXES or {}
table.insert(STEALTH_PREFIXES, "JEDI_ORDER_")
table.insert(STEALTH_PREFIXES, "JEDI_MISSION_")
table.insert(STEALTH_PREFIXES, "JEDI_HERO_")
table.insert(STEALTH_PREFIXES, "JEDI_ESCORT_")
local ok_w, WORLDS = pcall(require, "eawx-plugins/jedi-order/JediWorlds")
WORLDS = (ok_w and WORLDS) or {FORCE = {}, SIDE = {}}
local ok_p, POPULATED = pcall(require, "eawx-plugins/diplomacy/DiplomacyPopulations")
POPULATED = (ok_p and type(POPULATED) == "table") and POPULATED or nil
local ok_l, LAND = pcall(require, "eawx-plugins/diplomacy/DiplomacyLandWorlds")
LAND = (ok_l and type(LAND) == "table") and LAND or nil
local COLOR = {r = 150, g = 215, b = 190}
local WARN = {r = 255, g = 150, b = 110}
local GOLD = {r = 255, g = 225, b = 140}

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.jedi = r.jedi or {knowledge = 0, trust = J.START_TRUST, roster = {}, next_id = 1, week = 0, seen = {}, released = {},
                        teachings = {}, charter = {}, fallen = {}, ended = {}, news = {},
                        crisis = {queue = {}, done = {}}, council = {seats = {}}}
    local s = r.jedi
    if r.jedi_destroyed and s.week == 0 and not s.seeded then
        s.seeded = true
    end
    s.leads, s.next_lead, s.darkness, s.cleansed = s.leads or {}, s.next_lead or 1, s.darkness or 0, s.cleansed or {}
    return s
end
Order.state = state

function Order.founded(d)
    return d.republic ~= nil and d.republic.jedi_founded == true
end

local function year_now()
    return GlobalValue.Get("GALACTIC_YEAR") or 0
end

local function start_year()
    return GlobalValue.Get("GC_START_YEAR") or year_now()
end

local function news(s, text)
    table.insert(s.news, 1, text)
    while table.getn(s.news) > 12 do
        table.remove(s.news)
    end
end
Order.news = news

local function say(d, s, text, color, seconds)
    news(s, text)
    d.show("Jedi Order: " .. text, nil, color or COLOR, seconds or 20)
end

local function fill(line, p)
    return (string.gsub(line, "{name}", p.name))
end

function Order.get(s, id)
    for _, p in ipairs(s.roster) do
        if p.id == id then
            return p
        end
    end
    return nil
end

local function by_key(s, key)
    for _, p in ipairs(s.roster) do
        if p.key == key then
            return p
        end
    end
    return nil
end

local function has_trait(p, key)
    for _, t in ipairs(p.traits or {}) do
        if t == key then
            return true
        end
    end
    return false
end
Order.has_trait = has_trait

local function learned(s, path, tier)
    return (s.teachings[path] or 0) >= tier
end
Order.learned = learned

local function seated(s, seat)
    local id = s.council.seats[seat]
    return id and Order.get(s, id) or nil
end

local function seat_of(s, p)
    for key, id in pairs(s.council.seats) do
        if id == p.id then
            return key
        end
    end
    return nil
end
Order.seat_of = seat_of

local function count_rank(s, low)
    local n = 0
    for _, p in ipairs(s.roster) do
        if p.rank >= low then
            n = n + 1
        end
    end
    return n
end
Order.count_rank = count_rank

function Order.rank_name(p)
    return J.RANKS[p.rank] or J.RANKS[1]
end

function Order.label(p)
    if p.rank >= J.GRAND_MASTER then
        return "Grand Master " .. p.name
    elseif p.rank == J.MASTER then
        return "Master " .. p.name
    elseif p.rank == J.KNIGHT then
        return "Knight " .. p.name
    end
    return p.name
end

local function rank_for(table_of_ranks, year)
    local rank = J.INITIATE
    for _, row in ipairs(table_of_ranks) do
        if year >= row[1] then
            rank = row[2]
        end
    end
    return rank
end

local function add(s, fields)
    fields.id = s.next_id
    s.next_id = s.next_id + 1
    fields.shadow = fields.shadow or 0
    fields.traits = fields.traits or {}
    fields.missions = fields.missions or 0
    fields.xp = fields.xp or 0
    fields.home_since = s.week - J.REST_WEEKS
    table.insert(s.roster, fields)
    if fields.key then
        s.seen[fields.key] = true
    end
    return fields
end

local HERO = {}
for _, h in ipairs(J.HEROES) do
    HERO[h.key] = h
end
Order.HERO = HERO

local function hero_unit(d, entry)
    for _, t in ipairs(entry and entry.units or {}) do
        if Find_Object_Type(t) then
            for _, obj in pairs(Find_All_Objects_Of_Type(t) or {}) do
                if TestValid(obj) and obj.Get_Owner() == d.human then
                    return obj
                end
            end
        end
    end
    return nil
end

local function owned(d, type_name)
    local out = {}
    if Find_Object_Type(type_name) then
        for _, obj in pairs(Find_All_Objects_Of_Type(type_name) or {}) do
            if TestValid(obj) and obj.Get_Owner() == d.human then
                table.insert(out, obj)
            end
        end
    end
    return out
end

local function first_of(type_name)
    if not Find_Object_Type(type_name) then
        return nil
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(type_name) or {}) do
        if TestValid(obj) then
            return obj
        end
    end
    return nil
end
Order.first_of = first_of

function Order.unit_of(d, p)
    local m = p.mission
    return m and m.unit and owned(d, m.unit)[1] or nil
end

local function planet_of(obj)
    local ok, planet = pcall(function()
        return obj and obj.Get_Planet_Location()
    end)
    return ok and planet or nil
end

function Order.location(d, p)
    if p.mission and p.mission.unit then
        local planet = planet_of(Order.unit_of(d, p))
        return planet and U.key(planet) or nil
    end
    local temple = Order.temple(d)
    return temple and U.key(temple) or nil
end

local function join_hero(d, s, entry)
    local traits = {}
    for _, t in ipairs(entry.traits) do
        table.insert(traits, t)
    end
    local ok, Agents = pcall(require, "eawx-plugins/new-republic/RepublicOperatives")
    if ok and Agents and Agents.leave_for_jedi then
        pcall(Agents.leave_for_jedi, d, entry.name)
    end
    return add(s, {kind = "hero", key = entry.key, name = entry.name, species = entry.species, home = entry.home,
                   rank = rank_for(entry.rank, year_now()), path = entry.path, potential = entry.potential, traits = traits})
end

function Order.eligible(d, s)
    local out = {}
    for _, entry in ipairs(J.HEROES) do
        if not by_key(s, entry.key) and hero_unit(d, entry) then
            table.insert(out, entry)
        end
    end
    return out
end

function Order.assign(d, s, key)
    local entry = HERO[key]
    if not (entry and not by_key(s, key) and hero_unit(d, entry)) then
        return false, "They cannot serve the Order now."
    end
    s.released[key] = nil
    local p = join_hero(d, s, entry)
    news(s, p.name .. " joins the Order, and goes to the Temple.")
    return true, p.name .. " joins the Order, and goes to the Temple."
end

function Order.temple(d)
    local temple = Find_First_Object("Jedi_Temple")
    local planet = TestValid(temple) and planet_of(temple)
    if planet and planet.Get_Owner() == d.human then
        return planet
    end
    local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    return ok and Deals and Deals.capital(d, d.human) or nil
end

local function temple_key(d)
    local planet = Order.temple(d)
    return planet and U.key(planet) or nil
end

function Order.busy(d, s, p)
    if p.post then
        return p.name .. " is posted: " .. (Order.post_word and Order.post_word(d, p) or "away") .. "."
    elseif p.trials_until then
        return p.name .. " is facing the Jedi Trials."
    elseif p.mission then
        return p.name .. ((p.mission.key == "TRIAL") and " is away on their trial."
            or ((p.mission.key == "RETREAT") and " is on retreat." or " is on a mission."))
    elseif (p.wounded or 0) > s.week then
        return p.name .. " is recovering for " .. (p.wounded - s.week) .. " more weeks."
    elseif p.key == "LUKE" and (s.struck_until or 0) > s.week then
        return "Luke lies between life and death."
    elseif seat_of(s, p) then
        return p.name .. " sits on the Council: seated Masters do not leave the Temple."
    elseif p.along_of then
        return p.name .. " is away with their Master."
    elseif p.command then
        return p.name .. " serves with a fleet."
    elseif (p.counsel_until or 0) > s.week then
        return p.name .. " is in counsel for " .. (p.counsel_until - s.week) .. " more weeks."
    elseif (p.retreat_until or 0) > s.week then
        return p.name .. " is on retreat for " .. (p.retreat_until - s.week) .. " more weeks."
    elseif (p.vigil_until or 0) > s.week then
        return p.name .. " keeps the Vigil."
    elseif (p.meditate_until or 0) > s.week then
        return p.name .. " meditates on the Force."
    end
    return nil
end

function Order.teaching(d, s, p)
    if p.rank < J.MASTER or p.mission or p.command or p.post or (p.wounded or 0) > s.week or (p.vigil_until or 0) > s.week
            or (p.retreat_until or 0) > s.week or (p.meditate_until or 0) > s.week then
        return false
    end
    return not (p.key == "LUKE" and (s.struck_until or 0) > s.week)
end

function Order.student_cap(p)
    return (p.rank == J.MASTER) and J.STUDENTS or 0
end

function Order.head(s)
    for _, p in ipairs(s.roster) do
        if p.rank >= J.GRAND_MASTER then
            return p
        end
    end
    return nil
end

function Order.students(s, p)
    local out = {}
    for _, other in ipairs(s.roster) do
        if other.master == p.id and (other.rank == J.PADAWAN or other.rank == J.KNIGHT) then
            table.insert(out, other)
        end
    end
    return out
end

function Order.padawans(s, p)
    local out = {}
    for _, other in ipairs(Order.students(s, p)) do
        if other.rank == J.PADAWAN then
            table.insert(out, other)
        end
    end
    return out
end

function Order.leave_master(s, p)
    if p.rank ~= J.KNIGHT or not p.master then
        return nil
    end
    p.master, p.repair_at = nil, s.week + J.REPAIR_WEEKS
    local text = p.name .. " goes on alone."
    news(s, text)
    return text
end

function Order.untakeable(s, p)
    if p.rank == J.INITIATE then
        return p.trials_until and (p.name .. " is facing the Jedi Trials.")
            or (Order.initiate_trial_blocked and Order.initiate_trial_blocked(s, p)) or nil
    elseif (p.rank == J.PADAWAN or p.rank == J.KNIGHT) and not p.master then
        local wait = (p.repair_at or 0) - s.week
        return (wait > 0) and (p.name .. " left their Master lately: another can take them in " .. wait .. " weeks.") or nil
    end
    return p.name .. " is not free to be taught."
end

function Order.initiate_cap(s)
    return (learned(s, "SEEKER", 2) and J.INITIATE_CAP_TAUGHT or J.INITIATE_CAP)
        + ((Order.seated_in and Order.seated_in(s, "TRAINING")) and J.TRAINING_INITIATES or 0)
end

function Order.trial_missions(s)
    return M.max(1, J.TRIAL_MISSIONS - ((Order.seated_in and Order.seated_in(s, "TRAINING")) and 1 or 0)
        - (Order.relic_sum and Order.relic_sum(s, "trial_missions") or 0))
end

function Order.take_student(d, s, master, student)
    if table.getn(Order.students(s, master)) >= Order.student_cap(master) then
        return false, master.name .. " already has all the students they can teach."
    end
    local why = Order.untakeable(s, student)
    if why then
        return false, why
    end
    local text = student.name .. " becomes the student of " .. master.name .. "."
    if student.rank == J.INITIATE and Order.begin_initiate_trial then
        return Order.begin_initiate_trial(d, s, master, student)
    end
    student.master = master.id
    news(s, text)
    return true, text
end

local LEANS = {PEACEMAKER = "CONSULAR", COMPASSIONATE = "CONSULAR", DUELLIST = "GUARDIAN", RECKLESS = "GUARDIAN",
               PROUD = "GUARDIAN", DISCIPLINED = "GUARDIAN", SCHOLAR = "SEEKER", TEACHER = "SEEKER", GRIEVING = "SEEKER"}
local function knight_path(p)
    if p.wanted_path then
        return p.wanted_path
    end
    local weight = {GUARDIAN = 1, CONSULAR = 1, SEEKER = 1}
    for _, t in ipairs(p.traits or {}) do
        if LEANS[t] then
            weight[LEANS[t]] = weight[LEANS[t]] + 3
        end
    end
    local roll = GameRandom.Free_Random(1, weight.GUARDIAN + weight.CONSULAR + weight.SEEKER)
    for _, path in ipairs(J.PATH_ORDER) do
        if roll <= weight[path] then
            return path
        end
        roll = roll - weight[path]
    end
    return "GUARDIAN"
end

local function knight(s, p)
    p.rank, p.xp, p.path = J.KNIGHT, 0, knight_path(p)
end

function Order.holocron_blocked(s)
    if not learned(s, "SEEKER", 3) then
        return "Needs the Great Holocron (Teachings)."
    end
    local wait = (s.holocron or -100) + 52 - s.week
    return (wait > 0) and ("The Holocron can teach again in " .. wait .. " weeks.") or nil
end

function Order.turn_away(s, p)
    if p.rank ~= J.INITIATE then
        return p.name .. " is no longer an Initiate."
    end
    for i, other in ipairs(s.roster) do
        if other == p then
            table.remove(s.roster, i)
            break
        end
    end
    local text = p.name .. " is turned away from the Order, and goes home to " .. (p.home or "their world") .. "."
    news(s, text)
    return text
end

function Order.holocron_fits(d, s, p)
    if p.rank == J.INITIATE then
        return not p.trials_until
    end
    return (p.rank == J.PADAWAN or p.rank == J.KNIGHT) and Order.trial_blocked
        and Order.trial_blocked(d, s, p) == nil
end

function Order.raise_with_holocron(d, s, p)
    local why = Order.holocron_blocked(s)
    if why then
        return why
    end
    if not Order.holocron_fits(d, s, p) then
        return p.name .. "'s trial is not open."
    end
    s.holocron = s.week
    local text
    if p.rank == J.INITIATE then
        p.rank, p.xp, p.master = J.PADAWAN, 0, nil
        text = "The Holocron tests " .. p.name .. " in the Temple's heart: they pass the Jedi Trials, a Padawan."
    elseif p.rank == J.PADAWAN then
        local tr = Order.trial_of and Order.trial_of(d, s, p)
        knight(s, p)
        p.path, p.trial = (tr and tr.path) or p.path, nil
        text = "The Holocron sets " .. p.name .. " their trial in visions, and they pass it: a Jedi Knight of the "
            .. J.PATHS[p.path] .. "s."
    else
        p.trial = nil
        Order.make_master(d, s, p)
        text = "The Holocron sets " .. p.name .. " their trial in visions, and they pass it: a Jedi Master."
    end
    news(s, text)
    return text
end

local function seed(d, s)
    s.seeded = true
    for _, entry in ipairs(J.HEROES) do
        if hero_unit(d, entry) or (entry.always and start_year() >= entry.always and not s.released[entry.key]) then
            join_hero(d, s, entry)
        end
    end
    local year = start_year()
    if year >= J.FIRST_YEAR then
        for _, c in ipairs(J.CLASS) do
            if year >= c.from and (not c.to or year <= c.to) then
                local traits = {}
                for _, t in ipairs(c.traits) do
                    table.insert(traits, t)
                end
                local rank = rank_for(c.rank, year)
                add(s, {kind = "class", key = c.key, name = c.name, species = c.species, home = c.home, rank = rank, female = c.female,
                        path = (rank >= J.KNIGHT) and c.path or nil, wanted_path = c.path, potential = c.potential,
                        traits = traits, shadow = c.shadow, missions = (rank >= J.MASTER) and J.TRIAL_MISSIONS or 0})
            else
                s.seen[c.key] = s.seen[c.key] or (c.to ~= nil and year > c.to) or nil
            end
        end
        Order.pair_lore(d, s)
        s.knowledge = M.max(0, year - J.FIRST_YEAR) * 3
    end
end

local function arrivals(d, s)
    if s.week < (s.arrival_at or 0) or count_rank(s, J.INITIATE) - count_rank(s, J.PADAWAN) >= Order.initiate_cap(s) then
        return
    end
    local year = year_now()
    for _, c in ipairs(J.CLASS) do
        if not s.seen[c.key] and year >= c.from and (not c.to or year <= c.to) then
            local traits = {}
            for _, t in ipairs(c.traits) do
                table.insert(traits, t)
            end
            add(s, {kind = "class", key = c.key, name = c.name, species = c.species, home = c.home, rank = J.INITIATE,
                    wanted_path = c.path, potential = c.potential, traits = traits, shadow = c.shadow})
            s.arrival_at = s.week + 3
            say(d, s, c.name .. " of " .. c.home .. " comes to the Temple, asking to be taught.")
            return
        end
    end
end

local RC = require("eawx-plugins/new-republic/RepublicConfig")
local function people_of(world, native_pct)
    local native = world and RC.SPECIES and RC.SPECIES[world]
    if native and native ~= "Alien" and RC.NAMES[native] and U.chance(native_pct) then
        return native
    end
    if U.chance(50) then
        return "Human"
    end
    local list = {}
    for species, _ in pairs(RC.NAMES or {}) do
        if species ~= "Human" and species ~= "Alien" then
            table.insert(list, species)
        end
    end
    table.sort(list)
    return U.pick(list) or "Human"
end
Order.people_of = people_of

local function species_name(species, female)
    if species == "Human" then
        return U.pick(female and J.HUMAN_FEMALE or J.HUMAN_MALE) .. " " .. U.pick(J.LAST_NAMES)
    end
    local pool = RC.NAMES and RC.NAMES[species]
    if pool and pool.single then
        return U.pick(pool.single)
    elseif pool and pool.first then
        return U.pick(pool.first) .. (pool.last and (" " .. U.pick(pool.last)) or "")
    end
    return U.pick(J.FIRST_NAMES) .. " " .. U.pick(J.LAST_NAMES)
end

local function new_name(s, species, female)
    s.names_used = s.names_used or {}
    local firsts = {}
    for _, p in ipairs(s.roster) do
        s.names_used[p.name] = true
        local _, _, first = string.find(p.name, "^(%S+)")
        firsts[first or p.name] = true
    end
    local fallback = nil
    for try = 1, 60 do
        local name = (species or female ~= nil) and species_name(species or "Human", female)
            or (U.pick(J.FIRST_NAMES) .. " " .. U.pick(J.LAST_NAMES))
        local _, _, first = string.find(name, "^(%S+)")
        if not s.names_used[name] then
            fallback = fallback or name
            if not firsts[first or name] then
                s.names_used[name] = true
                return name
            end
        end
    end
    fallback = fallback or (U.pick(J.FIRST_NAMES) .. " " .. U.pick(J.LAST_NAMES))
    s.names_used[fallback] = true
    return fallback
end

local function generated_master(d, s)
    local traits = {}
    local trait = U.pick(J.TRAIT_ORDER)
    if trait then
        table.insert(traits, trait)
    end
    local worlds = U.worlds_of(d.human)
    local w = U.pick(worlds)
    local species, female = people_of(w and w.key, 50), U.chance(50)
    return add(s, {kind = "found", name = new_name(s, species, female), species = species, female = female,
                   home = w and d:planet_name(w.planet) or "Coruscant",
                   rank = J.MASTER, path = U.pick(J.PATH_ORDER), potential = 2, traits = traits,
                   missions = J.TRIAL_MISSIONS, stand_in = s.week == 0 or nil})
end

local CLASS_BY_KEY = {}
for _, c in ipairs(J.CLASS) do
    CLASS_BY_KEY[c.key] = c
end

function Order.pair_lore(d, s)
    local function room(m)
        return m and m.rank == J.MASTER and table.getn(Order.students(s, m)) < Order.student_cap(m)
    end
    for pass = 1, 2 do
        for _, p in ipairs(s.roster) do
            if p.rank == J.PADAWAN and not p.master then
                local c = p.key and CLASS_BY_KEY[p.key]
                local lore = c and c.master and by_key(s, c.master)
                if room(lore) then
                    p.master = lore.id
                elseif pass == 2 then
                    local m = nil
                    for _, other in ipairs(s.roster) do
                        if not m and room(other) then
                            m = other
                        end
                    end
                    p.master = (m or generated_master(d, s)).id
                end
            end
        end
    end
end

function Order.lore_students(d, s, hero)
    if hero.rank ~= J.MASTER then
        return
    end
    for _, p in ipairs(s.roster) do
        local c = p.key and CLASS_BY_KEY[p.key]
        if p.rank == J.PADAWAN and c and c.master == hero.key and table.getn(Order.students(s, hero)) < Order.student_cap(hero) then
            local old = p.master and Order.get(s, p.master)
            p.master = hero.id
            if old and old.stand_in and table.getn(Order.students(s, old)) == 0 then
                for i, other in ipairs(s.roster) do
                    if other == old then
                        table.remove(s.roster, i)
                        break
                    end
                end
            end
        end
    end
end

local function found_student(d, s, world)
    local traits = {U.pick(J.TRAIT_ORDER)}
    if U.chance(J.SECOND_TRAIT) then
        local second = U.pick(J.TRAIT_ORDER)
        if second ~= traits[1] then
            table.insert(traits, second)
        end
    end
    local roll = GameRandom.Free_Random(1, 100)
    local planet = FindPlanet(world)
    local species, female = people_of(world, J.FOUND_NATIVE), U.chance(50)
    return add(s, {kind = "found", name = new_name(s, species, female), species = species, female = female,
                   home = planet and d:planet_name(planet) or world,
                   rank = J.INITIATE, potential = (roll > 90) and 3 or ((roll > 40) and 2 or 1), traits = traits})
end

function Order.change_trust(s, amount)
    if amount > 0 and learned(s, "CONSULAR", 2) then
        amount = M.ceil(amount * 1.5)
    end
    s.trust = U.clamp(s.trust + amount, 0, 100)
end

local function shadow_average(s)
    local total, n = 0, 0
    for _, p in ipairs(s.roster) do
        total, n = total + p.shadow, n + 1
    end
    return (n > 0) and (total / n) or 0
end

function Order.shadow_word(s)
    local avg = shadow_average(s)
    for _, row in ipairs(J.SHADOW_WORDS) do
        if avg < row[1] then
            return row[2]
        end
    end
    return "Dark"
end

local function raise_shadow(p, amount)
    if amount > 0 and Order.susceptibility then
        amount = M.ceil(amount * Order.susceptibility(p))
    end
    p.shadow = U.clamp(p.shadow + amount, 0, 100)
    if p.key == "LUKE" then
        p.shadow = M.min(p.shadow, J.SHADOW.WARN - 1)
    end
end

Order.raise_shadow = raise_shadow

function Order.mood(s, p)
    if p.sign and p.sensed then
        return fill(p.sign, p)
    end
    local pool = {}
    local rank_pool = J.MOODS_RANK and J.MOODS_RANK[M.max(1, M.min(table.getn(J.MOODS_RANK), p.rank or 1))]
    for _, line in ipairs(rank_pool or J.MOODS) do
        table.insert(pool, line)
    end
    for _, t in ipairs(p.traits or {}) do
        for _, line in ipairs((J.MOODS_TRAIT or {})[t] or {}) do
            table.insert(pool, line)
        end
    end
    local n = table.getn(pool)
    local k = p.id * 7 + s.week
    return fill(pool[1 + k - M.floor(k / n) * n], p)
end

local function grieve(s, p)
    local amount = J.SHADOW.GRIEF
    if s.charter.ATTACH == "OLD" then
        amount = M.floor(amount / 2)
    elseif s.charter.ATTACH == "LUKE" then
        amount = M.floor(amount * 1.5)
    end
    for _, other in ipairs(s.roster) do
        if other.id == p.master or other.master == p.id then
            local extra = has_trait(other, "GRIEVING") and 5 or 0
            raise_shadow(other, amount + extra)
            other.grief_week = s.week
        elseif p.master and other.master == p.master and other ~= p then
            raise_shadow(other, J.SHADOW.PEER_DEATH)
            other.grief_week = s.week
        end
    end
    if Order.after_loss then
        Order.after_loss(s, p)
    end
end

function Order.vacate(s, p)
    for key, id in pairs(s.council.seats) do
        if id == p.id then
            s.council.seats[key] = nil
        end
    end
end

local function strip(s, p)
    Order.vacate(s, p)
    grieve(s, p)
    local kept = {}
    for _, other in ipairs(s.roster) do
        if other ~= p then
            table.insert(kept, other)
        end
        if other.master == p.id then
            other.master = nil
        end
        if other.watch == p.id then
            other.watch = nil
        end
        if other.along_of == p.id then
            other.along_of, other.home_since = nil, s.week
        end
    end
    s.roster = kept
end

local function intel_remove(d, obj)
    if not TestValid(obj) then
        return
    end
    local ok, Intel = pcall(require, "eawx-plugins/new-republic/RepublicIntel")
    local ok2, Agents = pcall(require, "eawx-plugins/new-republic/RepublicOperatives")
    if ok and ok2 and Intel and Agents then
        Agents.queue_removal(Intel.state(d), obj)
    else
        obj.Despawn()
    end
end

local function successor(d, s)
    local best = Order.pick_successor and Order.pick_successor(s)
    for _, p in ipairs(s.roster) do
        if not Order.pick_successor and p.rank == J.MASTER and (not best or p.missions > best.missions) then
            best = p
        end
    end
    if best then
        Order.vacate(s, best)
    end
    if best then
        best.rank = J.GRAND_MASTER
        s.council.seats.GRAND = best.id
        s.council.replace_until = s.week + J.COUNCIL_REPLACE_WEEKS
        s.dormant = nil
    else
        s.dormant = true
    end
    return best
end

local function luke_gone(d, s)
    Order.change_trust(s, -25)
    local next_one = successor(d, s)
    if next_one then
        say(d, s, "Luke Skywalker is gone. " .. next_one.name .. " is the Order's most senior Master, and leads it now.", GOLD, 30)
    else
        say(d, s, "Luke Skywalker is gone, and no Master is left. The Order is dormant until a Knight becomes a Master.", WARN, 30)
    end
    Order.push_crisis(s, "WHO_LEADS")
end

function Order.kill(d, s, p, how, quiet)
    Order.drop_unit(d, s, p)
    if p.kind == "hero" then
        s.released[p.key] = true
    end
    strip(s, p)
    Order.change_trust(s, -2)
    if not quiet then
        d.show("Jedi Order: " .. Order.label(p) .. " is dead: " .. how .. " The Order will remember them.", nil, GOLD, 30)
    end
    news(s, Order.label(p) .. " is dead.")
    if p.key == "LUKE" then
        luke_gone(d, s)
    end
end

local function free_fallen_type(s)
    for n = 1, J.FALLEN_TYPES do
        local used = false
        for _, f in ipairs(s.fallen) do
            used = used or f.n == n
        end
        if not used then
            return n
        end
    end
    return nil
end

local function first_world_of(faction)
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if string.upper(planet.Get_Owner().Get_Faction_Name()) == faction then
            return planet
        end
    end
    return nil
end

local function fallen_home()
    for _, faction in ipairs(J.DARK_POWERS) do
        local planet = first_world_of(faction)
        if planet then
            return planet
        end
    end
    return first_world_of("INDEPENDENT_FORCES")
end

local function rename_fallen(f)
    local label = "Dark Jedi " .. f.name
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_JEDI_FALLEN_" .. f.n, label)
    end
    if Engine_Set_Object_Text then
        pcall(Engine_Set_Object_Text, "JEDI_FALLEN_" .. f.n, "TEXT_JEDI_FALLEN_" .. f.n, label)
    end
end

function Order.fall(d, s, p)
    if not Order.get(s, p.id) then
        return
    end
    Order.drop_unit(d, s, p)
    if p.kind == "hero" then
        s.released[p.key] = true
    end
    local students = Order.students(s, p)
    if Order.relic_theft then
        Order.relic_theft(d, s, p, Order.seated_in and Order.seated_in(s, "LORE") == p)
    end
    if p.post and Order.unpost then
        Order.unpost(d, s, p)
    end
    local struck = {}
    if p.kind ~= "hero" then
        local leader = p.along_of and Order.get(s, p.along_of) or p
        local function together(q)
            if not (p.mission or p.along_of) then
                return not (q.mission or q.along_of or q.command)
            end
            local ql = q.along_of and Order.get(s, q.along_of) or q
            return ql == leader and (q.mission or q.along_of) ~= nil
        end
        for _, q in ipairs(s.roster) do
            local close = q ~= p and (q.id == p.master or q.master == p.id or (p.master and q.master == p.master))
            if close and together(q) and q.key ~= "LUKE" then
                if U.chance(J.FALL_KILL) then
                    table.insert(struck, {q, true})
                elseif U.chance(J.FALL_WOUND) then
                    table.insert(struck, {q, false})
                end
            end
        end
    end
    strip(s, p)
    Order.change_trust(s, -10)
    for _, e in ipairs(struck) do
        if e[2] then
            Order.kill(d, s, e[1], "struck down by " .. p.name .. " in the moment of their fall.")
        else
            Order.wound(s, e[1])
            say(d, s, p.name .. " turned on " .. Order.label(e[1]) .. " as they fell: wounded, but alive.", WARN, 25)
        end
    end
    s.darkness = M.min(100, (s.darkness or 0) + J.ORDER_SHADOW.LEAD_DARKNESS)
    local followers = {}
    for _, st in ipairs(students) do
        raise_shadow(st, 20)
        if st.shadow > 50 and U.chance(25) then
            table.insert(followers, st)
        end
    end
    local n, home = free_fallen_type(s), fallen_home()
    local where = "the dark places of the galaxy"
    if n and home then
        local f = {n = n, id = p.id, name = p.name, key = p.key, kind = p.kind, species = p.species, home = p.home,
                   path = p.path, potential = p.potential, traits = p.traits, type = "JEDI_FALLEN_" .. n, rank = p.rank,
                   week = s.week, female = p.female}
        if Find_Object_Type(f.type) and pcall(SpawnList, {f.type}, home, home.Get_Owner(), true, false) then
            table.insert(s.fallen, f)
            rename_fallen(f)
            where = d:planet_name(home)
        end
    end
    if home and Order.fighter_type and p.craft then
        pcall(SpawnList, {Order.fighter_type(s, p)}, home, home.Get_Owner(), true, false)
    end
    d.show("Jedi Order: " .. p.name .. " has fallen to the dark side, and is gone to " .. where
        .. ". A Redeem mission may yet bring them home.", nil, WARN, 30)
    news(s, p.name .. " has fallen to the dark side.")
    for _, st in ipairs(followers) do
        say(d, s, st.name .. " follows " .. p.name .. " into the dark.", WARN, 25)
        Order.fall(d, s, st)
    end
end

local PATH_LETTER = {GUARDIAN = "G", CONSULAR = "C", SEEKER = "S"}

local function teaching_level(s)
    return learned(s, "GUARDIAN", 1) and "_T" or ""
end
Order.teaching_level = teaching_level

local function rank_kind(p)
    if p.rank <= J.PADAWAN then
        return "P"
    end
    return ((p.rank >= J.MASTER) and "M_" or "K_") .. (PATH_LETTER[p.path or p.wanted_path or "GUARDIAN"] or "G")
end
Order.rank_kind = rank_kind

local function free_slot(s)
    local used = {}
    for _, p in ipairs(s.roster) do
        if p.mission and p.mission.slot then
            used[p.mission.slot] = true
        end
    end
    for n = 1, J.UNIT_SLOTS do
        if not used[n] then
            return n
        end
    end
    return nil
end

local function marker_of(p)
    return (p.kind == "hero") and ("JEDI_ESCORT_" .. p.key) or ("JEDI_ESCORT_M" .. p.mission.slot)
end

local function unit_type(s, p)
    if p.kind == "hero" then
        return "Jedi_Hero_" .. p.key
    end
    local level = teaching_level(s)
    if rank_kind(p) == "P" and level == "_C" then
        level = "_T"
    end
    return "Jedi_Mission_" .. p.mission.slot .. "_" .. rank_kind(p) .. level .. (p.female and "_F" or "")
end

local said = {}
local function set_text(id, value)
    if said[id] ~= value and Engine_Set_Text then
        said[id] = value
        pcall(Engine_Set_Text, id, value)
    end
end

local function rename_unit(p, s)
    local m = p.mission
    if not (m and m.unit) then
        return
    end
    local with = {}
    for _, id in ipairs(m.along or {}) do
        local st = s and Order.get(s, id)
        if st then
            table.insert(with, st.name .. " (" .. Order.rank_name(st) .. ")")
        end
    end
    local craft = (p.craft and Order.craft_name) and Order.craft_name(p) or nil
    local bio = Order.label(p) .. ((p.path and p.rank >= J.KNIGHT) and (", of the Path of the " .. J.PATHS[p.path] .. "s") or "")
        .. ", on " .. Order.mission_name(m) .. "." .. (craft and (" In space: their " .. craft .. ".") or "")
        .. ((with[1] ~= nil) and (" With them: " .. table.concat(with, ", ") .. ".") or " Travelling alone.")
    if p.kind == "hero" then
        set_text("TEXT_JEDI_HERO_" .. p.key .. "_WITH", (with[1] ~= nil) and ("With them: " .. table.concat(with, ", ") .. ".") or " ")
        return
    end
    if not m.slot then
        return
    end
    local label = (p.rank >= J.MASTER and "Jedi Master " or "Jedi Knight ") .. p.name
    local text = "TEXT_JEDI_MISSION_" .. m.slot
    set_text(text, label)
    set_text(text .. "_BIO", bio)
    set_text(text .. "_CLASS", Order.rank_name(p))
    if Engine_Set_Object_Text and said[m.unit .. "#"] ~= label then
        said[m.unit .. "#"] = label
        pcall(Engine_Set_Object_Text, m.unit, text, label)
    end
end

local function fleet_of(obj)
    local ok, parent = pcall(function()
        return obj.Get_Parent_Object()
    end)
    if not (ok and parent and TestValid(parent)) then
        return nil
    end
    local ok2, name = pcall(function()
        return parent.Get_Type().Get_Name()
    end)
    if ok2 and name and string.find(string.upper(name), "FLEET", 1, true) then
        return parent
    end
    return nil
end

local STILL = 0.5
local function steer(m, obj, world, here)
    local now = GetCurrentTime()
    if here ~= m.steer_at then
        m.steer_at, m.steer_since = here, now
    end
    if m.steered and now - M.max(m.steered, m.steer_since) < STILL then
        return
    end
    local fleet = fleet_of(obj)
    local planet = world and FindPlanet(world)
    if fleet and planet then
        m.steered = now
        pcall(function()
            fleet.Move_To(planet)
        end)
    end
end

local function hold(obj)
    pcall(function()
        obj.Set_Selectable(false)
    end)
end

function Order.drop_unit(d, s, p)
    local obj = Order.unit_of(d, p)
    if obj then
        intel_remove(d, obj)
    end
end

local function seconds(key, m)
    return ((m and m.weeks) or J.MISSIONS[key].weeks) * J.WEEK_SECONDS
end

function Order.mission_name(m)
    return m.name or J.MISSIONS[m.key].name
end

local function leave(d, s, p)
    local m = p.mission
    local temple = Order.temple(d)
    local now = GetCurrentTime()
    m.seen = now
    if not temple then
        m.stage, m.ends = "there", now + seconds(m.key, m)
        return
    end
    if p.kind ~= "hero" then
        m.slot = m.slot or free_slot(s)
        if not m.slot then
            return
        end
    end
    m.unit = unit_type(s, p)
    local escorts = {}
    local level = (teaching_level(s) ~= "") and "_T" or ""
    for _, id in ipairs(m.along or {}) do
        local st = Order.get(s, id)
        if st then
            table.insert(escorts, "Jedi_Order_" .. rank_kind(st) .. level)
        end
    end
    GlobalValue.Set("JEDI_ESCORT_" .. marker_of(p), table.concat(escorts, ","))
    if not (Find_Object_Type(m.unit) and pcall(SpawnList, {m.unit}, temple, d.human, true, false)) then
        m.stage, m.ends = "there", now + seconds(m.key, m)
        return
    end
    rename_unit(p, s)
    if m.world and m.world ~= U.key(temple) then
        m.stage = "out"
    else
        m.stage, m.ends = "there", now + seconds(m.key, m)
    end
end

local function home_now(d, s, p)
    Order.drop_unit(d, s, p)
    local m = p.mission
    if m and m.key == "POST" then
        p.post = nil
    end
    for _, id in ipairs(m and m.along or {}) do
        local st = Order.get(s, id)
        if st then
            st.along_of, st.home_since = nil, s.week
        end
    end
    p.mission = nil
    p.home_since = s.week
end
Order.home_now = home_now

function Order.threat(key)
    for _, t in ipairs(J.THREATS) do
        if t.key == key then
            return t
        end
    end
    return nil
end

local function threat_unit(t)
    for _, name in ipairs(t.units or {}) do
        local obj = first_of(name)
        if obj then
            return obj
        end
    end
    return nil
end

function Order.threat_world(t)
    local planet = planet_of(threat_unit(t))
    if planet then
        return U.key(planet)
    end
    if t.world and FindPlanet(t.world) then
        return t.world
    end
    planet = t.faction and first_world_of(t.faction)
    return planet and U.key(planet) or nil
end

function Order.threats(d, s)
    local out, year = {}, year_now()
    for _, t in ipairs(J.THREATS) do
        local open = not s.ended[t.key]
        if open and t.chain then
            open = s.chain == "kun"
        elseif open and t.from then
            open = year >= t.from and year <= (t.to or 1000) and (t.units == nil or threat_unit(t) ~= nil)
        elseif open and t.faction then
            open = first_world_of(t.faction) ~= nil or threat_unit(t) ~= nil
        end
        if open and t.world and not FindPlanet(t.world) then
            open = false
        end
        if open then
            table.insert(out, t)
        end
    end
    return out
end

local function end_threat(d, s, t)
    s.ended[t.key] = true
    intel_remove(d, threat_unit(t))
    local planet = t.world and FindPlanet(t.world)
    if t.lock and planet and Find_Object_Type(t.lock) and planet.Get_Owner() ~= d.human then
        pcall(function() planet.Get_Owner().Lock_Tech(Find_Object_Type(t.lock)) end)
    end
    if t.chain then
        s.chain = "done"
        s.knowledge = s.knowledge + 30
        Order.change_trust(s, 10)
    end
end

function Order.peopled(world)
    if POPULATED then
        return POPULATED[world] ~= nil
    end
    return true
end

function Order.force_of(world)
    local v = WORLDS.FORCE[world]
    if v then
        return v
    elseif LAND and not LAND[world] then
        return 0
    end
    return Order.peopled(world) and J.FORCE_DEFAULT or J.FORCE_BARREN
end

function Order.side_of(world)
    return world and WORLDS.SIDE[world] or 0
end

function Order.dark_site(world)
    local r = Order.ruin(world)
    return Order.side_of(world) >= J.DARK_SITE or (r ~= nil and r.dark == true)
end

function Order.running(s)
    local out = {}
    for _, p in ipairs(s.roster) do
        if p.mission then
            table.insert(out, p)
        end
    end
    return out
end

function Order.mission_limit(s)
    return M.max(1, count_rank(s, J.MASTER) + 1 - (s.restrained and 1 or 0))
end

local function sympathy_of(d, world)
    local planet = FindPlanet(world)
    if not planet or planet.Get_Owner() == d.human then
        return 0
    end
    local Sym = Republic().part("sym")
    local v = Sym and Sym.value(d, world)
    return v and M.round((v - 50) / 5) or 0
end

function Order.odds(d, s, p, key, world, along, target)
    local def = J.MISSIONS[key]
    local chance = def.base + (p.rank - J.KNIGHT) * 10 + (s.trust - 50) / 5
    if p.path and def.best[p.path] then
        chance = chance + 15
    end
    if has_trait(p, "RECKLESS") then
        chance = chance + 5
    end
    if (key == "MEDIATE" or key == "PEACE") then
        chance = chance + (has_trait(p, "PEACEMAKER") and 15 or 0) + (learned(s, "CONSULAR", 1) and 10 or 0)
            + (seated(s, "DIPLOMACY") and 10 or 0)
    elseif key == "CONFRONT" then
        chance = chance + (has_trait(p, "DUELLIST") and 15 or 0) + (learned(s, "GUARDIAN", 1) and 10 or 0)
            + (seated(s, "GUARDIANS") and 10 or 0)
    elseif key == "SEEK" or key == "LORE" then
        chance = chance + (learned(s, "SEEKER", 1) and 10 or 0)
        if key == "LORE" and has_trait(p, "SCHOLAR") then
            chance = chance + 15
        end
    end
    if Order.relic_odds then
        chance = chance + Order.relic_odds(s, key)
        if p.key == "CORRAN" then
            chance = chance + Order.relic_sum(s, "corran")
        end
    end
    if Order.seated_in then
        if (key == "ANSWER" or key == "ENVOY") and Order.seated_in(s, "DIPLOMACY") then
            chance = chance + 10
        elseif key == "CLEANSE" and Order.seated_in(s, "GUARDIANS") then
            chance = chance + 10
        end
    end
    if Order.hunt_bonus and target then
        chance = chance + Order.hunt_bonus(s, key, target)
    end
    if Order.shadow_effect then
        chance = chance + Order.shadow_effect(s, "ODDS")
    end
    if along then
        chance = chance - 5
    end
    if world then
        local side = Order.side_of(world)
        chance = chance + sympathy_of(d, world) - ((side > 0) and (side / 10) or (side / 20))
    end
    return U.clamp(M.round(chance), 5, 95)
end

function Order.odds_word(chance)
    for _, row in ipairs(J.ODDS_WORDS) do
        if chance >= row[1] then
            return row[2]
        end
    end
    return "dangerous"
end

function Order.free_jedi(d, s, key)
    local out = {}
    local low = (key and J.MISSIONS[key].master) and J.MASTER or J.KNIGHT
    for _, p in ipairs(s.roster) do
        if p.rank >= low and not Order.busy(d, s, p) then
            table.insert(out, p)
        end
    end
    return out
end

function Order.send_blocked(d, s)
    local n = 0
    for _, q in ipairs(Order.running(s)) do
        if not J.MISSIONS[q.mission.key].free then
            n = n + 1
        end
    end
    if n >= Order.mission_limit(s) then
        return "The Order can run " .. Order.mission_limit(s) .. " missions at once (one more than it has Masters)."
            .. (s.restrained and " The Senate's restraint takes one away." or "")
    end
    return nil
end

function Order.ruin(world)
    for _, r in ipairs(J.RUINS) do
        if r.world == world then
            return r
        end
    end
    return nil
end

function Order.can_come(d, s, p)
    local out = {}
    for _, st in ipairs(Order.students(s, p)) do
        if not Order.busy(d, s, st) then
            table.insert(out, st)
        end
    end
    return out
end

function Order.start(d, s, p, key, target, world, with_students, lead_id)
    local why = Order.busy(d, s, p) or Order.send_blocked(d, s)
    if why then
        return false, why
    end
    local def = J.MISSIONS[key]
    if def.master and p.rank < J.MASTER then
        return false, "Only a Master can go on " .. def.name .. "."
    end
    local Laws = Republic().part("laws")
    if def.law and not (Laws and Laws.jedi_envoy(d)) then
        return false, def.name .. " needs the Jedi Sanction Act."
    end
    if world and Order.world_locked(world) then
        return false, Order.world_name(d, world) .. " is closed to the galaxy for now."
    end
    local there = world and Order.mission_at(s, world)
    if there then
        return false, Order.label(there) .. " is already on a mission at " .. Order.world_name(d, world) .. "."
    end
    local closed = Laws and world and Laws.closed(d, world)
    if closed then
        return false, closed
    end
    if p.kind ~= "hero" and not free_slot(s) then
        return false, "Too many Jedi are travelling: wait for one to come home."
    end
    if s.week - (p.home_since or -100) < J.REST_WEEKS then
        raise_shadow(p, J.REST_SHADOW)
    end
    local along, names = {}, {}
    if with_students and (def.tier or 1) < 3 then
        for _, st in ipairs(Order.can_come(d, s, p)) do
            st.along_of = p.id
            table.insert(along, st.id)
            table.insert(names, st.name)
        end
    end
    p.mission = {key = key, target = target, world = world, stage = "leave", along = along, started = s.week}
    if lead_id and Order.take_lead then
        p.mission.lead = Order.take_lead(d, s, lead_id)
    end
    if p.kind ~= "hero" then
        p.mission.slot = free_slot(s)
    end
    local text = Order.label(p) .. " leaves for " .. def.name .. ((names[1] ~= nil) and (", with " .. table.concat(names, " and ")) or "") .. "."
    news(s, text)
    return true, text
end

function Order.send_away(d, s, p, key, world, weeks, name)
    if p.mission then
        return false, p.name .. " is already away."
    end
    if world and Order.world_locked(world) then
        return false, Order.world_name(d, world) .. " is closed to the galaxy for now."
    end
    if p.kind ~= "hero" and not free_slot(s) then
        return false, "Too many Jedi are travelling: wait for one to come home."
    end
    p.mission = {key = key, world = world, stage = "leave", along = {}, started = s.week, weeks = weeks or 100000,
                 name = name}
    if p.kind ~= "hero" then
        p.mission.slot = free_slot(s)
    end
    return true, nil
end

function Order.world_locked(world)
    local ok, names = pcall(GlobalValue.Get, "LOCKED_PLANETS")
    if not ok or type(names) ~= "table" or not world then
        return false
    end
    for _, name in pairs(names) do
        if type(name) == "string" and string.upper(name) == world then
            return true
        end
    end
    return false
end

function Order.mission_at(s, world)
    for _, p in ipairs(s.roster) do
        if p.mission and p.mission.world == world and not J.MISSIONS[p.mission.key].free then
            return p
        end
    end
    return nil
end

function Order.seek_cooldown(s, world, lead)
    local last = s.sought and s.sought[world]
    if lead or not last then
        return nil
    end
    local wait = last + M.round(J.SEEK_COOLDOWN + J.SEEK_COOLDOWN_FORCE * Order.force_of(world)) - s.week
    return (wait > 0) and ("Searched lately: the Force there is quiet for " .. wait .. " more weeks.") or nil
end

function Order.recall(d, s, p)
    local m = p.mission
    if not m then
        return nil
    end
    if m.stage == "leave" then
        home_now(d, s, p)
    else
        m.stage, m.steered, m.outcome = "back", nil, nil
    end
    return Order.label(p) .. " is called home."
end

local function world_name(d, world)
    local planet = world and FindPlanet(world)
    return planet and d:planet_name(planet) or (world or "?")
end

local function succeed(d, s, p, m)
    local where = world_name(d, m.world)
    local Rep = Republic()
    local key = m.key
    if key == "MEDIATE" then
        local Desires = Rep.part("desires")
        if Desires then
            Desires.boost(d, m.world, J.MEDIATE_OPINION, J.MEDIATE_WEEKS, "a Jedi mediator")
        end
        if d.senate and d.senate.anger and d.senate.anger[m.world] then
            local left = d.senate.anger[m.world] - J.MEDIATE_ANGER
            d.senate.anger[m.world] = (left > 0) and left or nil
        end
        local w = d.vassal_worlds and d.vassal_worlds[m.world]
        local ok, Missions = pcall(require, "eawx-plugins/diplomacy/DiplomacyMissions")
        if w and ok and Missions then
            if w.stage == "protectorate" and Missions.credit then
                Missions.credit(d, m.world)
            elseif Missions.adjust_content then
                Missions.adjust_content(d, m.world, J.MEDIATE_OPINION)
            end
        end
        return Order.label(p) .. " brings the people of " .. where .. " to the table."
    elseif key == "PEACE" then
        local planet = FindPlanet(m.world)
        if planet and planet.Get_Owner() == d.human then
            local Desires = Rep.part("desires")
            if Desires then
                Desires.boost(d, m.world, J.PEACE_OPINION, J.PEACE_WEEKS, "the Jedi keep the peace")
            end
            s.peace = s.peace or {}
            s.peace[m.world] = {ends = s.week + J.PEACE_WEEKS}
        else
            local Sym = Rep.part("sym")
            if Sym then
                Sym.change(d, m.world, J.PEACE_SYMPATHY)
            end
        end
        return Order.label(p) .. " keeps the peace on " .. where .. "."
    elseif key == "ENVOY" then
        local planet = FindPlanet(m.world)
        local Envoys = Rep.part("envoys")
        if planet and Envoys and Envoys.power_capital and Envoys.power_capital(d, planet) then
            local faction = planet.Get_Owner().Get_Faction_Name()
            Envoys.add_opinion(d, faction, J.ENVOY_OPINION)
            local extra = ""
            if learned(s, "CONSULAR", 3) and d.senate and d.senate.mandates then
                local war = d.relations and d.relations[faction] == "WAR"
                d.senate.mandates[faction] = war and "CEASEFIRE" or "ALLIANCE"
                extra = " You may offer " .. d.display_name(faction) .. (war and " a ceasefire" or " an alliance")
                    .. " without another Senate vote."
            end
            return Order.label(p) .. " speaks for the Republic at " .. where .. "; " .. d.display_name(faction)
                .. " thinks better of it." .. extra
        end
        local Sym = Rep.part("sym")
        if Sym and planet and planet.Get_Owner() ~= d.human then
            Sym.change(d, m.world, J.ENVOY_SYMPATHY)
        end
        return Order.label(p) .. " wins the people of " .. where .. " over to the Republic."
    elseif key == "SEEK" and Order.seek_result then
        return Order.seek_result(d, s, p, m)
    elseif key == "SEEK" then
        local presence = Order.force_of(m.world)
        local hint = J.SEEK_HINTS[0]
        if presence >= 60 then
            hint = J.SEEK_HINTS[60]
        elseif presence >= 40 then
            hint = J.SEEK_HINTS[40]
        end
        local chance = presence + (s.charter.ATTACH == "OLD" and -10 or 0) + (s.charter.ATTACH == "LUKE" and 15 or 0)
        local waiting = count_rank(s, J.INITIATE) - count_rank(s, J.PADAWAN)
        if not Order.peopled(m.world) then
            return Order.label(p) .. " found no one on " .. where .. ": no one lives there to be found."
        end
        if waiting < Order.initiate_cap(s) and U.chance(chance) then
            local student = found_student(d, s, m.world)
            local side = Order.side_of(m.world)
            if side > 0 then
                raise_shadow(student, M.floor(side / 2))
            end
            return Order.label(p) .. " returns from " .. where .. " with a student, " .. student.name .. ": " .. hint .. "."
        end
        return Order.label(p) .. " found no student on " .. where .. ": " .. hint .. "."
    elseif key == "LORE" then
        local ruin = Order.ruin(m.world) or {knowledge = M.max(5, M.floor(Order.force_of(m.world) / 5)), name = where}
        if Order.dark_site(m.world) then
            s.dark_lore = true
        end
        local gain = ruin.knowledge + (has_trait(p, "SCHOLAR") and 4 or 0)
        if s.charter.DARK == "DESTROY" then
            gain = M.ceil(gain * 0.75)
        elseif s.charter.DARK == "STUDY" then
            gain = M.ceil(gain * 1.5)
        end
        if Order.dark_site(m.world) and U.chance(30) then
            Order.push_crisis(s, "DARK", p.id, "HOLOCRON")
        end
        if U.chance(J.HOLOCRON_CHANCE) or (m.lead and m.lead.holocron) then
            gain = gain + J.HOLOCRON_KNOWLEDGE
            s.knowledge = s.knowledge + gain
            return Order.label(p) .. " brings a holocron out of " .. ruin.name .. ": Knowledge +" .. gain .. "."
        end
        s.knowledge = s.knowledge + gain
        return Order.label(p) .. " returns from " .. ruin.name .. ": Knowledge +" .. gain .. "."
    elseif key == "CONFRONT" then
        local t = Order.threat(m.target)
        if t then
            end_threat(d, s, t)
            Order.change_trust(s, 8)
            s.darkness = M.max(0, (s.darkness or 0) - 5)
            return Order.label(p) .. " has ended it: " .. t.name .. " is no more."
        end
    elseif key == "ANSWER" then
        local Blocs = Rep.part("blocs")
        if Blocs and Blocs.grant then
            Blocs.grant(d, m.target, Rep.senate and Rep.senate.seats(d) or {})
        end
        return Order.label(p) .. " has answered the call at " .. where .. "."
    elseif key == "CLEANSE" and Order.cleanse then
        return Order.cleanse(d, s, p, m)
    elseif key == "REDEEM" then
        for i, f in ipairs(s.fallen) do
            if f.id == m.target then
                table.remove(s.fallen, i)
                intel_remove(d, first_of(f.type))
                local rank = (Order.relic_flag and Order.relic_flag(s, "redeem_rank") and f.rank) or J.KNIGHT
                local back = add(s, {kind = (f.kind == "hero") and "found" or f.kind, name = f.name, key = (f.kind ~= "hero") and f.key or nil,
                        species = f.species, home = f.home, rank = M.max(J.KNIGHT, rank), path = f.path, potential = f.potential,
                        traits = f.traits, shadow = 30, female = f.female})
                if Order.relic_recover then
                    Order.relic_recover(d, s, f.id, f.name .. " is redeemed.")
                    for _, item in ipairs((s.relics and s.relics.list) or {}) do
                        if item.stolen_by == back.id then
                            item.stolen_by = nil
                        end
                    end
                end
                Order.change_trust(s, 5)
                return Order.label(p) .. " has brought " .. f.name .. " back to the light."
            end
        end
    end
    return Order.label(p) .. " has done what was asked."
end

local function finish_mission(d, s, p)
    local m = p.mission
    local def = J.MISSIONS[m.key]
    if m.key == "TRIAL" and Order.trial_done then
        return Order.trial_done(d, s, p, m)
    elseif def.free then
        m.stage, m.steered = "back", nil
        if m.key == "RETREAT" then
            say(d, s, Order.label(p) .. " ends their retreat and is on their way home.")
        end
        return
    end
    local along = {}
    for _, id in ipairs(m.along or {}) do
        local st = Order.get(s, id)
        if st then
            table.insert(along, st)
        end
    end
    if m.key == "CONFRONT" then
        raise_shadow(p, J.SHADOW.CONFRONT)
    elseif m.key == "LORE" and Order.dark_site(m.world) and s.charter.DARK ~= "DESTROY" then
        raise_shadow(p, J.SHADOW.DARK_SITE + ((s.charter.DARK == "STUDY") and J.SHADOW.STUDY or 0))
    end
    if m.key == "SEEK" and m.world then
        s.sought = s.sought or {}
        s.sought[m.world] = s.week
    end
    local success = U.chance(Order.odds(d, s, p, m.key, m.world, along[1] ~= nil, m.target))
    if m.key == "CONFRONT" and s.sure_confront then
        success, s.sure_confront = true, nil
    end
    local function rate(q)
        return J.MISSION_XP_RATE[M.max(1, M.min(3, q.potential or 2))]
    end
    local function gain(xp)
        p.xp = (p.xp or 0) + xp * rate(p)
        for _, st in ipairs(along) do
            st.xp = (st.xp or 0) + (learned(s, "SEEKER", 2) and 3 or 2) * xp * rate(st)
            if Order.cap_xp then
                Order.cap_xp(st)
            end
        end
        if Order.cap_xp then
            Order.cap_xp(p)
        end
    end
    m.stage, m.steered = "back", nil
    if success then
        p.missions = p.missions + 1
        gain(J.XP_SUCCESS)
        local Laws = Republic().part("laws")
        Order.change_trust(s, M.round(J.TRUST_SUCCESS * ((Laws and Laws.jedi_trust(d)) or 1)))
        local text = succeed(d, s, p, m)
        if Order.relic_find and (m.key == "LORE" or m.key == "CONFRONT" or m.key == "CLEANSE") then
            text = text .. Order.relic_find(d, s, p, m.world, m.key)
        end
        local k = J.MISSION_KNOWLEDGE[m.key]
        if k then
            s.knowledge = s.knowledge + k
            text = text .. " Knowledge +" .. k .. "."
        end
        say(d, s, text .. " They are on their way home.")
        return
    end
    gain(J.XP_FAILURE)
    local public = def.trust_risk or (m.key == "LORE" and Order.dark_site(m.world))
    if public then
        Order.change_trust(s, -J.TRUST_FAILURE)
    end
    local death = (def.death + M.max(0, M.floor(Order.side_of(m.world) / 5))) * Order.death_mult(s)
    if (def.tier or 1) < 3 and learned(s, "CONSULAR", 2) then
        death = 0
    end
    if Order.mission_fall and Order.mission_fall(d, s, p, m) then
        return
    end
    if U.chance(death) then
        local names = {}
        for _, st in ipairs(along) do
            table.insert(names, st.name)
        end
        home_now(d, s, p)
        Order.kill(d, s, p, "lost on " .. string.lower(def.name) .. " at " .. world_name(d, m.world) .. "."
            .. ((names[1] ~= nil) and (" " .. table.concat(names, " and ") .. " bring them home.") or ""))
    elseif U.chance(25) then
        Order.wound(s, p)
        say(d, s, Order.label(p) .. " failed at " .. world_name(d, m.world) .. " and is coming home wounded.", WARN)
    else
        say(d, s, Order.label(p) .. " failed: " .. def.name .. " at " .. world_name(d, m.world) .. "."
            .. (public and (" Public Trust -" .. J.TRUST_FAILURE .. ".") or ""), WARN)
    end
end

function Order.heal_mult(s)
    return ((Order.seated_in and Order.seated_in(s, "HEALING")) and J.HEALING_HEAL or 1)
        * (Order.relic_mult and Order.relic_mult(s, "heal") or 1)
end

function Order.death_mult(s)
    return ((Order.seated_in and Order.seated_in(s, "GUARDIANS")) and J.GUARDIAN_DEATH or 1)
        * (Order.relic_mult and Order.relic_mult(s, "death") or 1)
end

function Order.wound(s, p, weeks)
    local base = weeks or (learned(s, "CONSULAR", 2) and M.ceil(J.WOUND_WEEKS / 2) or J.WOUND_WEEKS)
    p.wounded = s.week + M.max(1, M.ceil(base * (weeks and 1 or Order.heal_mult(s))))
    for _, other in ipairs(s.roster) do
        if other ~= p and (other.id == p.master or other.master == p.id or (p.master and other.master == p.master)) then
            raise_shadow(other, J.SHADOW.WOUND_NEAR)
        end
    end
end

local function names_of(list)
    local n = table.getn(list)
    return (n > 1) and (table.concat(list, ", ", 1, n - 1) .. " and " .. list[n]) or (list[1] or "")
end
Order.names_of = names_of

function Order.party_lost(d, s, p, how)
    local m = p.mission
    local party = {p}
    for _, id in ipairs((m and m.along) or {}) do
        local st = Order.get(s, id)
        if st then
            table.insert(party, st)
        end
    end
    Order.drop_unit(d, s, p)
    p.mission = nil
    local dead, alive, doomed = {}, {}, {}
    for _, q in ipairs(party) do
        q.along_of, q.home_since = nil, s.week
        if U.chance(J.DOWN_DEATH * Order.death_mult(s)) then
            table.insert(dead, Order.label(q))
            table.insert(doomed, q)
        else
            table.insert(alive, Order.label(q))
            Order.wound(s, q)
        end
    end
    for _, q in ipairs(doomed) do
        Order.kill(d, s, q, "", true)
    end
    local text = "Jedi Order: " .. how .. " "
    if dead[1] then
        text = text .. names_of(dead) .. ((table.getn(dead) == 1) and " is" or " are") .. " dead; the Order will remember them. "
    end
    if alive[1] then
        text = text .. names_of(alive) .. ((table.getn(alive) == 1) and " survives" or " survive") .. ", wounded, and "
            .. "makes their way home."
    end
    d.show(text, nil, GOLD, 30)
end

local function unit_lost(d, s, p)
    Order.party_lost(d, s, p, "the ship carrying " .. Order.label(p) .. " was destroyed on the way to "
        .. world_name(d, p.mission.world) .. ".")
end

function Order.travel(d, s)
    local now = GetCurrentTime()
    local temple = Order.temple(d)
    local home = temple and U.key(temple)
    for _, p in ipairs(Order.running(s)) do
        local m = p.mission
        if m.stage == "leave" then
            leave(d, s, p)
        elseif not m.unit then
            if m.stage == "there" and now >= (m.ends or 0) then
                finish_mission(d, s, p)
            elseif m.stage == "back" then
                home_now(d, s, p)
            end
        else
            local obj = Order.unit_of(d, p)
            if not obj then
                if now - (m.seen or now) > J.LOST_SECONDS then
                    unit_lost(d, s, p)
                end
            else
                m.seen = now
                hold(obj)
                local planet = planet_of(obj)
                local here = planet and U.key(planet)
                if m.leg_stage ~= m.stage then
                    m.leg_stage, m.leg_at = m.stage, now
                end
                local late = now - m.leg_at > J.LEG_SECONDS
                if m.stage == "out" then
                    if here == m.world then
                        m.stage, m.ends, m.steered = "there", now + seconds(m.key, m), nil
                    elseif late then
                        m.stage, m.steered = "back", nil
                        say(d, s, Order.label(p) .. " could not get through to " .. world_name(d, m.world) .. ", and turns back.", WARN)
                    elseif here then
                        steer(m, obj, m.world, here)
                    end
                elseif m.stage == "there" then
                    if here and here ~= m.world then
                        steer(m, obj, m.world, here)
                    elseif now >= (m.ends or 0) then
                        finish_mission(d, s, p)
                    end
                elseif m.stage == "back" then
                    if not home or here == home or late then
                        home_now(d, s, p)
                    elseif here then
                        steer(m, obj, home, here)
                    end
                end
            end
        end
    end
end

function Order.teaching_state(s, path, tier)
    local have = s.teachings[path] or 0
    if tier <= have then
        return "learned"
    end
    if tier > have + 1 then
        return "locked", "Learn the tier before it first."
    end
    if tier == 3 then
        for _, other in ipairs(J.TEACHING_PATHS) do
            if other ~= path and (s.teachings[other] or 0) >= 3 then
                return "closed", "Closed: the Order's crowning teaching is the " .. J.PATHS[other] .. "s'."
            end
        end
    end
    if s.knowledge < J.TEACHING_COST[tier] and not s.free_teaching then
        return "dear", "Needs " .. J.TEACHING_COST[tier] .. " Knowledge."
    end
    return "open"
end

function Order.learn(d, s, path, tier)
    local status, why = Order.teaching_state(s, path, tier)
    if status ~= "open" then
        return why or "Already learned."
    end
    if s.free_teaching then
        s.free_teaching = nil
    else
        s.knowledge = s.knowledge - J.TEACHING_COST[tier]
    end
    s.teachings[path] = tier
    if path == "GUARDIAN" and tier >= 2 then
        Order.change_trust(s, -5)
    end
    local name = J.TEACHINGS[path][tier].name
    news(s, "The Order takes up a new teaching: " .. name .. ".")
    return "The Order takes up a new teaching: " .. name .. "."
end

local function sway_interest(d, interest, amount, reason)
    local Rep = Republic()
    local Members = Rep.part("members")
    local Senate = Rep.senate
    if not (Members and Senate) then
        return
    end
    for name in pairs(Senate.seats(d) or {}) do
        if Members.has(d, name, interest) then
            Senate.sway(d, name, amount, reason)
        end
    end
end

function Order.charter_state(s, question)
    if s.charter[question.key] then
        return "decided"
    end
    if question.key == "ORDERS" then
        if not s.council.open then
            return "locked", "Opens once the Order has a Council."
        end
    elseif question.key == "ATTACH" then
        if not s.charter.ORDERS then
            return "locked", "Opens after Politics is settled."
        elseif count_rank(s, J.KNIGHT) < J.CHARTER_JEDI then
            return "locked", "Opens once the Order has " .. J.CHARTER_JEDI .. " Knights and Masters (it has " .. count_rank(s, J.KNIGHT) .. ")."
        end
    elseif question.key == "DARK" then
        if not s.charter.ATTACH then
            return "locked", "Opens after Attachments is settled."
        elseif not s.dark_lore then
            return "locked", "Opens once a Jedi has searched a dark site and come back with what they found."
        end
    end
    return "open"
end

function Order.decide_charter(d, s, question, which)
    local status, why = Order.charter_state(s, question)
    if status == "decided" then
        return "The Order has already answered this."
    elseif status == "locked" then
        return why
    end
    local answer = question[which]
    s.charter[question.key] = answer.key
    if answer.key == "SENATE" then
        Republic().senate_mandate(d, 5)
        s.senate_order_at = s.week + J.SENATE_ORDER_WEEKS
    elseif answer.key == "APART" then
        sway_interest(d, "Autonomy", 10, "the Jedi stand apart")
        sway_interest(d, "Security", -10, "the Jedi stand apart")
    end
    local text = "The Order's Charter, " .. question.name .. ": " .. answer.name .. "."
    say(d, s, text, GOLD)
    return text
end

function Order.can_seat(s, seat, p)
    if seat.key == "GRAND" then
        return false, "The head of the Order takes this seat."
    end
    if s.council.seats[seat.key] and (s.council.replace_until or -1) < s.week then
        return false, "A sitting member can be replaced only after a new Grand Master takes up the title."
    end
    if p and p.rank < J.MASTER then
        return false, "Only Masters sit on the Council."
    end
    return true
end

function Order.seat(d, s, seat, p)
    local ok, why = Order.can_seat(s, seat, p)
    if not ok then
        return why
    end
    if p.mission or p.along_of then
        return p.name .. " is away."
    end
    Order.vacate(s, p)
    s.council.seats[seat.key] = p.id
    local text = Order.label(p) .. " takes the seat of " .. seat.name .. "."
    news(s, text)
    return text
end

function Order.unseat(s, seat)
    local ok, why = Order.can_seat(s, seat)
    if not ok then
        return why
    end
    s.council.seats[seat.key] = nil
    return "The seat of " .. seat.name .. " stands empty."
end

function Order.push_crisis(s, key, person, event)
    for _, q in ipairs(s.crisis.queue) do
        if q.key == key and q.person == person and q.event == event then
            return
        end
    end
    table.insert(s.crisis.queue, {key = key, person = person, event = event})
end

local function named(def, name)
    local out = {}
    for k, v in pairs(def) do
        out[k] = (type(v) == "string") and string.gsub(v, "{name}", name) or v
    end
    return out
end

local function crisis_def(s, active)
    local p = active.person and Order.get(s, active.person)
    local name = p and p.name or "A Jedi"
    if active.key == "DARK" then
        local e = J.DARK_EVENTS[active.event or ""]
        if not e then
            return nil
        end
        return {title = (string.gsub(e.title, "{name}", name)), text = (string.gsub(e.text, "{name}", name)),
                a = named(e.a, name), b = named(e.b, name)}
    elseif active.key ~= "EDGE" then
        return J.CRISES[active.key]
    end
    local master = p and p.master and Order.get(s, p.master)
    local a = {label = "Bring them home", text = name .. " is brought home and watched", trust = -5, redeem = true}
    if master and not Order.busy(nil, s, master) then
        a = {label = "Send their Master", text = master.name .. " goes to " .. name, master_help = true}
    end
    return {title = name .. " Stands at the Edge",
            text = name .. " has gone very far into the dark. " .. (master and (master.name .. " might reach them, or ")
                or "Bring them home by force of will, or ") .. "trust them to find their own way.",
            a = a, b = {label = "Trust them", text = name .. " is trusted to find their own way", gamble = true}}
end

function Order.effects(choice)
    local out = {}
    local function signed(v)
        return ((v > 0) and "+" or "") .. v
    end
    if choice.trust then
        table.insert(out, "Public Trust " .. signed(choice.trust))
    end
    if choice.knowledge then
        table.insert(out, "Knowledge " .. signed(choice.knowledge))
    end
    if choice.mandate then
        table.insert(out, "Mandate " .. signed(choice.mandate))
    end
    if choice.shadow then
        table.insert(out, (choice.shadow > 0) and "The shadow deepens over the whole Order" or "The shadow lifts a little from the whole Order")
    end
    if choice.interest then
        table.insert(out, "Opinion " .. signed(choice.interest[2]) .. " on worlds that care about " .. string.lower(choice.interest[1]))
    end
    if choice.redeem then
        table.insert(out, "Their shadow lifts, but they cannot serve for " .. J.WOUND_WEEKS .. " weeks")
    end
    if choice.gamble then
        table.insert(out, "They may come back from it (40%), or fall")
    end
    if choice.master_help then
        table.insert(out, "Their Master may reach them (60%: both far lighter); else the Master is darkened by it")
    end
    if choice.pshadow then
        table.insert(out, (choice.pshadow > 0) and "Their shadow deepens" or "Their shadow lifts")
    end
    if choice.pxp then
        table.insert(out, "Training XP " .. signed(choice.pxp))
    end
    if choice.close then
        table.insert(out, "Those close to them " .. ((choice.close < 0) and "find some peace too" or "are darkened too"))
    end
    if choice.darkness then
        table.insert(out, (choice.darkness > 0) and "The Order's darkness grows" or "The Order's darkness lessens")
    end
    if choice.watch then
        table.insert(out, "Their Master keeps watch over them")
    end
    if choice.fall then
        table.insert(out, "If the dark is strong in them, they may fall")
    end
    if choice.expel then
        table.insert(out, "He leaves the Order and goes over to the Empire as a Dark Jedi")
    end
    if choice.redeem_spy then
        table.insert(out, "A slim chance (" .. J.REDEEM_SPY .. "%) he stays, cleared; else he falls")
    end
    if choice.opens_council then
        table.insert(out, "Opens the Council page: five seats, each with its own bonus")
    end
    if choice.credits then
        table.insert(out, "Credits " .. signed(choice.credits))
    end
    if choice.student then
        table.insert(out, "A new Initiate at the Temple")
    end
    if choice.order_mission then
        table.insert(out, "A free Jedi goes to mediate at the unhappiest member world")
    end
    if choice.chain then
        table.insert(out, "The student may not come back the same")
    end
    if choice.ends_chain then
        table.insert(out, "Ends the matter")
    end
    return table.concat(out, ". ") .. "."
end

function Order.crisis(d)
    local s = state(d)
    local active = s and s.crisis.active
    if not active then
        return nil
    end
    local def = crisis_def(s, active)
    return def and {crisis = def, left = M.max(0, active.ends - s.week)} or nil
end

local function order_mission(d, s)
    local Senate = Republic().senate
    local worst, low = nil, 1000
    for name, seat in pairs(Senate and Senate.seats(d) or {}) do
        if seat.opinion < low then
            worst, low = name, seat.opinion
        end
    end
    local free = Order.free_jedi(d, s)
    for _, p in ipairs(free) do
        if worst and p.kind ~= "hero" then
            Order.start(d, s, p, "MEDIATE", worst, worst)
            return
        end
    end
end

local function apply_choice(d, s, active, choice)
    if choice.trust then
        Order.change_trust(s, choice.trust)
    end
    if choice.knowledge then
        s.knowledge = M.max(0, s.knowledge + choice.knowledge)
    end
    if choice.mandate then
        Republic().senate_mandate(d, choice.mandate)
    end
    if choice.shadow then
        for _, p in ipairs(s.roster) do
            raise_shadow(p, choice.shadow)
        end
    end
    if choice.interest then
        sway_interest(d, choice.interest[1], choice.interest[2], "the Jedi Order")
    end
    if choice.credits then
        d.human.Give_Money(choice.credits)
    end
    if choice.student then
        local w = U.pick(U.worlds_of(d.human))
        found_student(d, s, w and w.key or "CORUSCANT")
    end
    if choice.darkness and not active.person then
        s.darkness = U.clamp((s.darkness or 0) + choice.darkness, 0, 100)
    end
    if choice.opens_council then
        s.council.open = true
        local head = nil
        for _, p in ipairs(s.roster) do
            if p.rank >= J.GRAND_MASTER then
                head = p
            end
        end
        if head then
            s.council.seats.GRAND = head.id
        end
    end
    if choice.order_mission then
        order_mission(d, s)
    end
    if choice.chain then
        s.chain, s.chain_at = "temple", s.week + 8
    elseif choice.ends_chain then
        s.chain = "closed"
    end
    local p = active.person and Order.get(s, active.person)
    if p and Order.apply_dark_choice then
        Order.apply_dark_choice(d, s, p, choice)
        p = Order.get(s, p.id)
    end
    if p and choice.redeem then
        raise_shadow(p, -30)
        p.sign = nil
        p.wounded = s.week + J.WOUND_WEEKS
        if p.mission then
            Order.recall(d, s, p)
        end
    elseif p and choice.gamble then
        if U.chance(60) then
            Order.fall(d, s, p)
        else
            raise_shadow(p, -10)
            say(d, s, p.name .. " pulls back from the edge, on their own.")
        end
    elseif p and choice.master_help then
        local master = p.master and Order.get(s, p.master)
        if master and U.chance(60) then
            raise_shadow(p, -25)
            raise_shadow(master, -25)
            say(d, s, master.name .. " reaches " .. p.name .. " in time: they come back to the light together.", GOLD)
        elseif master then
            raise_shadow(master, 15)
            say(d, s, master.name .. " could not reach " .. p.name .. ", and carries the darkness of trying.", WARN)
        end
    end
end

function Order.choose_crisis(d, which)
    local s = state(d)
    local active = s and s.crisis.active
    if not active then
        return "No matter is waiting."
    end
    local def = crisis_def(s, active)
    local choice = def[which]
    s.crisis.active = nil
    if active.key ~= "DARK" and active.key ~= "EDGE" then
        s.crisis.done[active.key] = true
    end
    apply_choice(d, s, active, choice)
    local text = def.title .. ": " .. choice.text .. ". " .. Order.effects(choice)
    news(s, def.title .. ": " .. choice.text .. ".")
    return text
end

local function crisis_week(d, s)
    local c = s.crisis
    if c.active then
        if s.week >= c.active.ends then
            local active = c.active
            local def = crisis_def(s, active)
            c.active = nil
            if not def then
                return
            end
            if active.key ~= "DARK" and active.key ~= "EDGE" then
                c.done[active.key] = true
            end
            apply_choice(d, s, active, def.b)
            d.show("Jedi Order: " .. def.title .. " was left to the Order: " .. def.b.text .. ". " .. Order.effects(def.b), nil, COLOR, 20)
        end
        return
    end
    local nxt = table.remove(c.queue, 1)
    if not nxt then
        if not c.done.PURPOSE and s.week >= 4 then
            nxt = {key = "PURPOSE"}
        elseif U.chance(J.CRISIS_CHANCE) then
            local open = {}
            for _, key in ipairs(J.CRISIS_ORDER) do
                if not c.done[key] then
                    table.insert(open, {key = key})
                end
            end
            nxt = U.pick(open)
        end
    end
    if nxt and nxt.person and not Order.get(s, nxt.person) then
        nxt = nil
    end
    if nxt then
        c.active = {key = nxt.key, person = nxt.person, event = nxt.event, ends = s.week + J.CRISIS_WEEKS}
        local def = crisis_def(s, c.active)
        if not def then
            c.active = nil
            return
        end
        d.show("Jedi Order: " .. def.title .. ". " .. def.text .. " Decide in the Republic window.", nil, GOLD, 30)
    end
end

local function chain_week(d, s)
    if s.chain == "closed" or s.chain == "done" or s.chain == "kun" then
        return
    end
    if not s.chain then
        if temple_key(d) == "YAVIN" and Order.shadow_level(s) >= 3 and not s.crisis.done.STUDENT_ASKS
                and not s.chain_asked then
            s.chain_asked = true
            Order.push_crisis(s, "STUDENT_ASKS")
        end
        return
    end
    if s.chain == "temple" and s.week >= (s.chain_at or 0) then
        local victim = by_key(s, "KYP") or by_key(s, "GANTORIS")
        for _, p in ipairs(s.roster) do
            if not victim and p.rank <= J.KNIGHT and p.key ~= "LUKE" then
                victim = p
            end
        end
        if victim then
            raise_shadow(victim, 40)
            say(d, s, victim.name .. " came back from the old temple changed, and speaks of a teacher who is not Luke.", WARN)
        end
        s.chain, s.chain_at = "voice", s.week + 8
    elseif s.chain == "voice" and s.week >= (s.chain_at or 0) then
        s.chain = "kun"
        s.struck_until = s.week + 12
        Order.push_crisis(s, "STRUCK_DOWN")
    end
end

function Order.motions(d)
    local out = {}
    if not Order.founded(d) then
        return out
    end
    local s = state(d)
    if (s.trust < J.TRUST_LOW or Order.shadow_level(s) >= 4) and not s.restrained then
        table.insert(out, {kind = "JEDI_RESTRAIN", label = "Restrain the Jedi Order", text = "restrain the Jedi Order",
                           tip = "Public Trust in the Jedi is very low. Passed: the Order runs one mission fewer, and Public Trust +10."})
    end
    if s.week - (s.funded or -100) >= J.FUND_WEEKS then
        table.insert(out, {kind = "JEDI_FUND", label = "Fund the Jedi Order", text = "fund the Jedi Order for a year",
                           tip = "Passed: Knowledge +5, Public Trust +5, and an Order that Stands Apart escapes doubled upkeep for a year."})
    end
    return out
end

function Order.enact(d, motion)
    local s = state(d)
    if motion.kind == "JEDI_RESTRAIN" then
        s.restrained = true
        Order.change_trust(s, 10)
        say(d, s, "The Senate restrains the Order: one mission fewer at a time, until Public Trust recovers.", WARN)
    elseif motion.kind == "JEDI_FUND" then
        s.funded = s.week
        s.knowledge = s.knowledge + 5
        Order.change_trust(s, 5)
        say(d, s, "The Senate funds the Order for a year.")
    end
end

function Order.attitude(d)
    local s = d.republic and d.republic.jedi
    return (s and learned(s, "CONSULAR", 3)) and 10 or 0
end

local function heroes_home(d, s)
    for _, p in ipairs(s.roster) do
        if p.kind == "hero" then
            local entry = HERO[p.key]
            for _, t in ipairs(entry and entry.units or {}) do
                for _, obj in ipairs(owned(d, t)) do
                    intel_remove(d, obj)
                end
            end
        end
    end
end

local function heroes_week(d, s)
    for _, entry in ipairs(J.HEROES) do
        local always = entry.always and start_year() >= entry.always
        if not by_key(s, entry.key) and not s.released[entry.key] and (hero_unit(d, entry) or always) then
            local p = join_hero(d, s, entry)
            say(d, s, p.name .. " joins the Order, and goes to the Temple.")
            if entry.key == "LUKE" then
                s.dormant = nil
            end
        end
    end
end

local function training_week(d, s)
    local head = Order.head(s)
    for _, p in ipairs(s.roster) do
        if (p.rank == J.PADAWAN or p.rank == J.KNIGHT) and not p.mission and not p.along_of and not Order.busy(d, s, p) then
            local master = p.master and Order.get(s, p.master)
            local gain, teacher = 0, nil
            local base = J.XP_BY_POTENTIAL[M.max(1, M.min(3, p.potential))]
            if master and Order.teaching(d, s, master) then
                gain, teacher = base, master
            elseif not master and p.rank == J.KNIGHT then
                gain = base / 2
            elseif not master and head and Order.teaching(d, s, head) then
                gain, teacher = (Order.relic_flag and Order.relic_flag(s, "unpadawan")) and base or (base / 2), head
            end
            if gain > 0 then
                if teacher and has_trait(teacher, "TEACHER") then
                    gain = gain * 1.25
                end
                if learned(s, "SEEKER", 2) then
                    gain = gain * 1.25
                end
                if seated(s, "TRAINING") then
                    gain = gain * 1.25
                end
                gain = gain * (Order.shadow_mult and Order.shadow_mult(s, "XP") or 1)
                gain = gain * (1 + (Order.relic_sum and Order.relic_sum(s, "xp") or 0) / 100)
                local reg = Order.regimen and Order.regimen(s)
                gain = gain * (reg and reg.xp or 1)
            end
            p.xp = (p.xp or 0) + gain
            if Order.cap_xp then
                Order.cap_xp(p)
            end
        end
    end
end

function Order.make_master(d, s, p)
    p.rank, p.master, p.xp = J.MASTER, nil, 0
    if Order.promoted then
        Order.promoted(d, s, p, J.KNIGHT)
    end
    if s.dormant then
        s.dormant = nil
        successor(d, s)
    end
end

local function shadow_week(d, s)
    local edge = nil
    for _, p in ipairs(s.roster) do
        local dv = 0
        local leader = p.along_of and Order.get(s, p.along_of) or p
        local m = leader.mission
        if m and m.stage == "there" then
            local side = Order.side_of(m.world)
            dv = dv + ((side > 0) and M.ceil(side / J.SIDE_SHADOW) or -M.floor(-side / J.SIDE_SHADOW))
        end
        if p.post then
            dv = dv + ((p.post.kind == "HUNT") and 1 or 0)
        elseif p.mission and p.mission.key == "RETREAT" then
            dv = dv - ((p.mission.stage == "there") and (J.SHADOW.REST + J.SHADOW.RETREAT) or 0)
        elseif p.mission or p.along_of then
            dv = dv + (has_trait(p, "PROUD") and 1 or 0) + (has_trait(p, "RECKLESS") and 1 or 0)
                + (has_trait(p, "GRIEVING") and 1 or 0)
            if s.charter.ORDERS == "SENATE" and s.week - M.floor(s.week / 2) * 2 == 0 then
                dv = dv + 1
            end
            if s.charter.DARK == "STUDY" and p.path == "SEEKER" then
                dv = dv + 1
            end
        elseif p.command then
            dv = dv + 1
        else
            dv = dv - J.SHADOW.REST - (has_trait(p, "COMPASSIONATE") and 1 or 0)
                - (Order.relic_sum and Order.relic_sum(s, "rest") or 0)
            local master = p.master and Order.get(s, p.master)
            if master and Order.teaching(d, s, master) then
                dv = dv - J.SHADOW.MASTER
            end
            if p.rank <= J.KNIGHT and Order.shadow_effect then
                dv = dv + Order.shadow_effect(s, "STUDENTS")
            end
            if (p.retreat_until or 0) > s.week then
                dv = dv - J.SHADOW.RETREAT
            end
            if (p.vigil_until or 0) > s.week then
                dv = dv - M.ceil(J.VIGIL_SHADOW / J.VIGIL_WEEKS)
            end
        end
        if p.watch then
            dv = dv - J.SHADOW.ASSIGNED
        end
        raise_shadow(p, dv)
        if p.shadow < J.SHADOW.SIGN then
            p.sign = nil
        elseif not p.sign then
            p.sign = U.pick(J.SIGNS)
            if p.sensed then
                news(s, fill(p.sign, p))
            end
        end
        if p.shadow >= J.SHADOW.WARN and p.sensed and s.week >= (p.warn_at or 0) then
            p.warn_at = s.week + 8
            d.show("Jedi Order: " .. fill(p.sign or J.SIGNS[1], p) .. " See them in the Order's roster.", nil, WARN, 20)
        end
        if p.shadow >= J.SHADOW.EDGE and not edge then
            edge = p
        end
    end
    if edge and not (s.crisis.active and s.crisis.active.key == "EDGE") then
        local queued = false
        for _, q in ipairs(s.crisis.queue) do
            queued = queued or q.key == "EDGE"
        end
        if not queued then
            Order.push_crisis(s, "EDGE", edge.id)
        end
    end
end

local function peace_week(d, s)
    d.influence_mods = d.influence_mods or {}
    for world, entry in pairs(s.peace or {}) do
        if s.week >= entry.ends then
            if entry.applied and d.influence_mods[world] == entry.applied then
                local rest = entry.applied - J.PEACE_INFLUENCE
                d.influence_mods[world] = (rest ~= 0) and rest or nil
            end
            s.peace[world] = nil
        elseif entry.applied == nil or d.influence_mods[world] ~= entry.applied then
            entry.applied = (d.influence_mods[world] or 0) + J.PEACE_INFLUENCE
            d.influence_mods[world] = entry.applied
        end
    end
end

local function upkeep_week(d, s)
    local cost = count_rank(s, J.PADAWAN) * J.UPKEEP
    if s.charter.ORDERS == "SENATE" then
        cost = M.floor(cost / 2)
    elseif s.charter.ORDERS == "APART" and s.week - (s.funded or -100) >= J.FUND_WEEKS then
        cost = cost * 2
    end
    d.human.Give_Money(-cost)
end

function Order.week(d)
    if not Order.founded(d) then
        return
    end
    local s = state(d)
    s.week = s.week + 1
    if not s.seeded then
        seed(d, s)
    end
    heroes_week(d, s)
    if Order.named_week then
        Order.named_week(d, s)
    else
        arrivals(d, s)
    end
    training_week(d, s)
    if Order.trials_week then
        Order.trials_week(d, s)
    end
    shadow_week(d, s)
    if Order.dark_week then
        Order.dark_week(d, s)
    end
    if Order.lead_week then
        Order.lead_week(d, s)
    end
    if Order.relic_week then
        Order.relic_week(d, s)
    end
    if Order.council_week then
        Order.council_week(d, s)
    end
    chain_week(d, s)
    peace_week(d, s)
    upkeep_week(d, s)
    s.knowledge_part = s.knowledge_part or 0
    for _, p in ipairs(s.roster) do
        if Order.teaching(d, s, p) then
            s.knowledge_part = s.knowledge_part + J.MASTER_KNOWLEDGE
        end
    end
    if s.knowledge_part >= 1 then
        local whole = M.floor(s.knowledge_part)
        s.knowledge, s.knowledge_part = s.knowledge + whole, s.knowledge_part - whole
    end
    s.knowledge = s.knowledge + (learned(s, "SEEKER", 3) and 2 or 0) + (seated(s, "LORE") and 1 or 0)
    if s.trust >= J.TRUST_HIGH and s.week - M.floor(s.week / 4) * 4 == 0 then
        Republic().senate_mandate(d, 1)
    end
    if s.restrained and s.trust >= 60 then
        s.restrained = nil
        say(d, s, "With trust restored, the Senate lifts its restraint on the Order.")
    end
    if s.charter.ORDERS == "SENATE" and s.week >= (s.senate_order_at or 0) then
        s.senate_order_at = s.week + J.SENATE_ORDER_WEEKS
        s.crisis.done.SENATE_ASKS = nil
        Order.push_crisis(s, "SENATE_ASKS")
    end
    if not s.council.open and count_rank(s, J.MASTER) >= J.COUNCIL_MASTERS and s.week >= (s.council.ask_at or 0) then
        s.council.ask_at = s.week + J.COUNCIL_ASK_AGAIN
        Order.push_crisis(s, "COUNCIL")
    end
    crisis_week(d, s)
end

function Order.tick(d)
    if Order.founded(d) and start_year() > 0 and not d.republic.jedi_destroyed
            and not (d.republic.jedi and d.republic.jedi.seeded) then
        seed(d, state(d))
    end
    local s = d.republic and d.republic.jedi
    if not s then
        return
    end
    if s.seeded and s.week == 0 then
        for _, entry in ipairs(J.HEROES) do
            if not by_key(s, entry.key) and not s.released[entry.key] and hero_unit(d, entry) then
                local p = join_hero(d, s, entry)
                Order.lore_students(d, s, p)
            end
        end
    end
    heroes_home(d, s)
    Order.travel(d, s)
    if Order.field_tick then
        Order.field_tick(d, s)
    end
    for _, p in ipairs(s.roster) do
        rename_unit(p, s)
    end
    for _, f in ipairs(s.fallen) do
        rename_fallen(f)
    end
end

Order.say, Order.add, Order.by_key, Order.rank_for, Order.owned, Order.intel_remove = say, add, by_key, rank_for, owned, intel_remove
Order.first_world_of, Order.year_now, Order.start_year, Order.temple_key = first_world_of, year_now, start_year, temple_key
Order.world_name, Order.found_student, Order.fill, Order.hero_unit, Order.knight = world_name, found_student, fill, hero_unit, knight
Order.knight_path, Order.free_slot = knight_path, free_slot
Order.planet_of, Order.fleet_of, Order.shadow_average, Order.threat_unit = planet_of, fleet_of, shadow_average, threat_unit
Order.CLASS_BY_KEY, Order.COLOR, Order.WARN, Order.GOLD = CLASS_BY_KEY, COLOR, WARN, GOLD
Order.shadow_level = function() return 1 end
Order.shadow_word = Order.shadow_word
for _, name in ipairs({"JediLeads", "JediDark", "JediField", "JediReliquary", "JediCouncil", "JediTrials"}) do
    local ok, part = pcall(require, "eawx-plugins/jedi-order/" .. name)
    if ok and type(part) == "table" and part.attach then
        part.attach(Order)
    end
end

return Order
