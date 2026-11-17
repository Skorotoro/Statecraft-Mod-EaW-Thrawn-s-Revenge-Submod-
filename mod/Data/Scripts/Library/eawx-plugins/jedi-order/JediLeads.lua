local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")

local Leads = {}

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

function Leads.attach(Order)
    local function fill(text, f)
        text = string.gsub(text, "{world}", f.world_name or "?")
        text = string.gsub(text, "{owner}", f.owner or "?")
        text = string.gsub(text, "{jedi}", f.jedi or "?")
        text = string.gsub(text, "{threat}", f.threat or "?")
        text = string.gsub(text, "{who}", f.who or "Luke")
        return (string.gsub(text, "^%l", string.upper))
    end

    local function count_waiting(s)
        return Order.count_rank(s, J.INITIATE) - Order.count_rank(s, J.PADAWAN)
    end

    local function open_lead(s, kind, world, key)
        for _, l in ipairs(s.leads) do
            if l.kind == kind and (l.world == world or (key and l.key == key)) then
                return l
            end
        end
        return nil
    end

    function Order.add_lead(d, s, kind, f)
        local def = J.LEADS[kind]
        if not def or not f.world or open_lead(s, kind, f.world, f.key) or Order.world_locked(f.world) then
            return nil
        end
        local planet = FindPlanet(f.world)
        f.world_name = planet and d:planet_name(planet) or f.world
        f.who = f.who or U.pick(J.LEAD_FROM)
        local lead = {id = s.next_lead, kind = kind, mission = def.mission, target = f.target or f.world, world = f.world,
                      title = fill(def.title, f), text = fill(U.pick(def.texts), f), expires = s.week + J.LEAD_WEEKS,
                      dark = def.dark, holocron = def.holocron, reveal = def.reveal, key = f.key}
        s.next_lead = s.next_lead + 1
        table.insert(s.leads, lead)
        Order.say(d, s, "A lead: " .. lead.title .. ". " .. lead.text .. " (Missions, Active Leads.)",
            def.dark and Order.WARN or Order.COLOR, 25)
        return lead
    end

    function Order.leads(d, s)
        local out = {}
        for _, l in ipairs(s.leads) do
            table.insert(out, l)
        end
        table.sort(out, function(a, b) return a.expires < b.expires end)
        return out
    end

    function Order.mission_closed(d, s, key)
        local def = J.MISSIONS[key]
        local Laws = Republic().part("laws")
        if def.law and not (Laws and Laws.jedi_envoy and Laws.jedi_envoy(d)) then
            return def.name .. " needs the Jedi Sanction Act."
        elseif key == "ANSWER" and not Order.answer_requests(d, s)[1] then
            return "No bloc asks for anything a Jedi could give in person now."
        elseif not def.open and not def.event and not Order.leads_for(d, s, key)[1] then
            return "No lead for " .. def.name .. " now: wait for one (Active Leads)."
        end
        return nil
    end

    function Order.answer_requests(d, s)
        local out = {}
        local Blocs = Republic().part("blocs")
        local R = require("eawx-plugins/new-republic/RepublicConfig")
        for _, def in ipairs(R.BLOCS) do
            local req = Blocs and Blocs.request(d, def.key)
            if req and req.desire and J.ANSWER_DESIRES[req.desire.kind] then
                table.insert(out, {def = def, req = req})
            end
        end
        return out
    end

    function Order.leads_for(d, s, mission)
        local out = {}
        for _, l in ipairs(Order.leads(d, s)) do
            if l.mission == mission then
                table.insert(out, l)
            end
        end
        return out
    end

    function Order.take_lead(d, s, id)
        for i, l in ipairs(s.leads) do
            if l.id == id then
                table.remove(s.leads, i)
                return l
            end
        end
        for _, l in ipairs(Order.leads(d, s)) do
            if l.id == id then
                return l
            end
        end
        return nil
    end

    local function peopled_worlds(min_force, side_test)
        local out = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local k = U.key(planet)
            local f = Order.force_of(k)
            if f >= min_force and Order.peopled(k) and (not side_test or side_test(Order.side_of(k))) then
                table.insert(out, {key = k, planet = planet, force = f})
            end
        end
        return out
    end

    local function by_force(list)
        local total = 0
        for _, e in ipairs(list) do
            total = total + e.force + 5
        end
        if total <= 0 then
            return nil
        end
        local roll = GameRandom.Free_Random(1, total)
        for _, e in ipairs(list) do
            roll = roll - (e.force + 5)
            if roll <= 0 then
                return e
            end
        end
        return list[1]
    end

    local GEN = {}
    GEN.CHILD = function(d, s)
        local e = by_force(peopled_worlds(1))
        return e and {world = e.key}
    end
    GEN.FAMILY = GEN.CHILD
    GEN.REFUGEES = function(d, s)
        local e = U.pick(peopled_worlds(1))
        return e and {world = e.key}
    end
    GEN.HERMIT = function(d, s)
        local e = by_force(peopled_worlds(30))
        return e and U.chance(40) and {world = e.key}
    end
    GEN.NIGHTSISTER = function(d, s)
        if FindPlanet("DATHOMIR") and U.chance(60) then
            return {world = "DATHOMIR"}
        end
        local e = U.pick(peopled_worlds(1, function(side) return side >= J.DARK_SITE end))
        return e and {world = e.key}
    end
    GEN.UNREST = function(d, s)
        local Senate = Republic().senate
        local worst, low = nil, 0
        for name, seat in pairs((Senate and Senate.seats(d)) or {}) do
            if seat.opinion < low then
                worst, low = name, seat.opinion
            end
        end
        return worst and {world = worst}
    end
    GEN.TURMOIL = function(d, s)
        local Senate = Republic().senate
        local list = {}
        for name, seat in pairs((Senate and Senate.seats(d)) or {}) do
            if seat.opinion <= -30 then
                table.insert(list, name)
            end
        end
        local Sym = Republic().part("sym")
        for _, e in ipairs((Sym and Sym.list(d)) or {}) do
            if U.category(e.owner) == "INDEPENDENT" and U.chance(15) then
                table.insert(list, e.key)
            end
        end
        local w = U.pick(list)
        return w and {world = w}
    end
    GEN.RUINS = function(d, s)
        local list = {}
        for _, r in ipairs(J.RUINS) do
            if FindPlanet(r.world) then
                table.insert(list, r.world)
            end
        end
        for _, e in ipairs(peopled_worlds(J.LORE_FORCE)) do
            table.insert(list, e.key)
        end
        local w = U.pick(list)
        return w and {world = w}
    end
    GEN.HOLOCRON = function(d, s)
        return U.chance(50) and GEN.RUINS(d, s)
    end
    GEN.THREAT = function(d, s)
        local t = U.pick(Order.threats(d, s))
        local w = t and Order.threat_world(t)
        return w and {world = w, target = t.key, threat = t.name}
    end
    GEN.FALLEN = function(d, s)
        local f = U.pick(s.fallen)
        local obj = f and Order.first_of(f.type)
        local planet = obj and Order.planet_of(obj)
        return planet and {world = U.key(planet), target = f.id, jedi = f.name}
    end
    GEN.DARK_SITE = function(d, s)
        local list = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local k = U.key(planet)
            if Order.dark_site(k) then
                table.insert(list, k)
            end
        end
        local w = U.pick(list)
        return w and {world = w}
    end
    local WEIGHT = {CHILD = 4, FAMILY = 2, HERMIT = 1, REFUGEES = 2, NIGHTSISTER = 1, UNREST = 3, TURMOIL = 2, RUINS = 3,
                    HOLOCRON = 1, THREAT = 2, FALLEN = 2, DARK_SITE = 2}

    function Order.lead_week(d, s)
        Order.meditations(d, s)
        local kept = {}
        for _, l in ipairs(s.leads) do
            if s.week >= l.expires then
                if l.dark then
                    s.darkness = M.min(100, (s.darkness or 0) + J.ORDER_SHADOW.LEAD_DARKNESS)
                    local text = "The lead went unanswered: " .. l.title .. ". The Order's darkness grows."
                    if l.kind == "THREAT" and not (s.hunt and s.hunt.kind == "THREAT" and s.hunt.target == l.target) then
                        local planet = FindPlanet(l.world)
                        local owner = planet and planet.Get_Owner()
                        if owner and owner ~= d.human and Find_Object_Type("Imperial_Dark_Jedi_Company") then
                            pcall(SpawnList, {"Imperial_Dark_Jedi_Company"}, planet, owner, true, false)
                            text = text .. " Its Dark Jedi gather new followers."
                        end
                    end
                    Order.say(d, s, text, Order.WARN)
                elseif l.kind == "CHILD" and U.chance(25) then
                    s.darkness = M.min(100, (s.darkness or 0) + 2)
                    Order.say(d, s, "The child on " .. Order.world_name(d, l.world) .. " is gone: someone else found them first.",
                        Order.WARN)
                else
                    Order.news(s, "The trail has gone cold: " .. l.title .. ".")
                end
            else
                table.insert(kept, l)
            end
        end
        s.leads = kept
        if table.getn(s.leads) >= J.LEAD_MAX then
            return
        end
        local Laws = Republic().part("laws")
        local chance = J.LEAD_CHANCE + J.LEAD_SEEKER * (s.teachings.SEEKER or 0)
            + ((Laws and Laws.jedi_envoy and Laws.jedi_envoy(d)) and J.LEAD_SANCTION or 0)
        if Order.learned(s, "SEEKER", 1) then
            chance = chance * 1.25
        end
        if not U.chance(chance) then
            return
        end
        Order.new_lead(d, s)
    end

    function Order.new_lead(d, s, kinds, tries, sector)
        local dark = Order.shadow_mult(s, "DARK_LEADS") * (Order.relic_mult and Order.relic_mult(s, "dark_leads") or 1)
        local pool, total = {}, 0
        for _, kind in ipairs(kinds or J.LEAD_ORDER) do
            local w = (WEIGHT[kind] or 1) * (J.LEADS[kind].dark and dark or 1)
            table.insert(pool, {kind, w})
            total = total + w
        end
        if not pool[1] then
            return nil
        end
        for _ = 1, (tries or 4) do
            local roll, kind = GameRandom.Free_Random(1, M.max(1, M.floor(total * 10))) / 10, nil
            for _, e in ipairs(pool) do
                roll = roll - e[2]
                if not kind and roll <= 0 then
                    kind = e[1]
                end
            end
            kind = kind or pool[1][1]
            local ok, f = pcall(GEN[kind], d, s)
            if ok and f and sector and U.sector_of(f.world or "") ~= sector then
                f = nil
            end
            local lead = ok and f and Order.add_lead(d, s, kind, f)
            if lead then
                return lead
            end
        end
        return nil
    end

    function Order.meditate_blocked(d, s, p)
        if p.rank < J.GRAND_MASTER then
            return "Only the Grand Master meditates for the Order."
        elseif s.knowledge < J.MEDITATE_KNOWLEDGE then
            return "Needs " .. J.MEDITATE_KNOWLEDGE .. " Knowledge."
        elseif table.getn(s.leads) >= J.LEAD_MAX then
            return "The Order has all the leads it can follow."
        end
        return Order.busy(d, s, p)
    end

    function Order.meditate(d, s, p)
        local why = Order.meditate_blocked(d, s, p)
        if why then
            return why
        end
        s.knowledge = s.knowledge - J.MEDITATE_KNOWLEDGE
        p.meditate_until = s.week + J.MEDITATE_WEEKS
        local text = Order.label(p) .. " withdraws to meditate on the Force."
        Order.news(s, text)
        return text
    end

    local function meditations(d, s)
        for _, p in ipairs(s.roster) do
            if p.meditate_until and s.week >= p.meditate_until then
                p.meditate_until = nil
                local lead = Order.new_lead(d, s, nil, 12)
                if not lead then
                    Order.say(d, s, Order.label(p) .. " meditated on the Force, and it was silent.")
                end
            end
        end
    end
    Order.meditations = meditations

    local function join_named(d, s, c, year)
        local traits = {}
        for _, t in ipairs(c.traits) do
            table.insert(traits, t)
        end
        local rank = Order.rank_for(c.rank, year)
        local p = Order.add(s, {kind = "class", key = c.key, name = c.name, species = c.species, home = c.home, rank = rank, female = c.female,
                                path = (rank >= J.KNIGHT) and c.path or nil, wanted_path = c.path, potential = c.potential,
                                traits = traits, shadow = c.shadow, missions = (rank >= J.MASTER) and J.TRIAL_MISSIONS or 0,
                                spy = c.spy, joined_week = s.week})
        Order.pair_lore(d, s)
        return p
    end
    Order.join_named = join_named

    function Order.named_week(d, s)
        if not U.chance(J.NAMED_CHANCE) then
            return
        end
        local year = Order.year_now()
        local open = {}
        for _, c in ipairs(J.CLASS) do
            if not s.seen[c.key] and year >= c.from and (not c.to or year <= c.to) and not Order.by_key(s, c.key)
                    and not open_lead(s, "NAMED", nil, c.key) then
                table.insert(open, c)
            end
        end
        local c = U.pick(open)
        if not c then
            return
        end
        local rank = Order.rank_for(c.rank, year)
        if rank <= J.INITIATE and count_waiting(s) >= Order.initiate_cap(s) then
            return
        end
        local home = nil
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            if d:planet_name(planet) == c.home or U.key(planet) == string.upper(string.gsub(c.home, " ", "_")) then
                home = U.key(planet)
            end
        end
        if home and not U.chance(J.NAMED_ARRIVE) then
            Order.add_lead(d, s, "NAMED", {world = home, key = c.key, jedi = c.name})
            return
        end
        local p = join_named(d, s, c, year)
        Order.say(d, s, c.name .. " of " .. c.home .. " comes to the Temple: " .. Order.rank_name(p) .. ".", Order.GOLD)
    end

    local function student(d, s, world, potential, shadow)
        local p = Order.found_student(d, s, world)
        if potential then
            p.potential = M.max(p.potential, potential)
        end
        if shadow then
            p.shadow = M.max(p.shadow, shadow)
        end
        return p
    end

    function Order.seek_result(d, s, p, m)
        local where = Order.world_name(d, m.world)
        local lead = m.lead
        local room = count_waiting(s) < Order.initiate_cap(s)
        if not Order.peopled(m.world) then
            return Order.label(p) .. " found no one on " .. where .. ": no one lives there to be found."
        end
        local kind = lead and lead.kind
        if kind == "NAMED" and lead.key then
            local c = Order.CLASS_BY_KEY[lead.key]
            if c and not Order.by_key(s, c.key) then
                local q = join_named(d, s, c, Order.year_now())
                return Order.label(p) .. " finds " .. q.name .. " on " .. where .. ": they join the Order as "
                    .. string.lower(Order.rank_name(q)) .. "."
            end
        elseif kind == "HERMIT" and U.chance(J.HERMIT_CHANCE) then
            local q = Order.found_student(d, s, m.world)
            q.rank, q.path, q.potential = U.chance(25) and J.MASTER or J.KNIGHT, U.pick(J.PATH_ORDER), 2
            q.missions = (q.rank >= J.MASTER) and J.TRIAL_MISSIONS or 0
            return Order.label(p) .. " finds " .. q.name .. " on " .. where .. ", who survived the Purge in hiding: "
                .. Order.label(q) .. " joins the Order."
        elseif not room then
            return Order.label(p) .. " found someone on " .. where .. ", but the Temple has no room for another Initiate."
        elseif kind == "CHILD" then
            local q = student(d, s, m.world, U.chance(40) and 3 or 2)
            return Order.label(p) .. " brings home the gifted one from " .. where .. ": " .. q.name .. "."
        elseif kind == "FAMILY" and U.chance(J.FAMILY_CHANCE) then
            local a = student(d, s, m.world)
            local b = (count_waiting(s) < Order.initiate_cap(s)) and student(d, s, m.world) or nil
            return Order.label(p) .. " brings two of the family from " .. where .. ": " .. a.name
                .. (b and (" and " .. b.name) or "") .. "."
        elseif kind == "NIGHTSISTER" then
            local q = student(d, s, m.world, 3, 20)
            q.species = "Human"
            return Order.label(p) .. " brings the runaway witch from " .. where .. ": " .. q.name .. ". The Temple watches her."
        end
        local force = Order.force_of(m.world) + ((kind == "REFUGEES") and J.REFUGEE_FORCE or 0)
        local side = Order.side_of(m.world)
        local chance = Order.seek_chance(s, m.world, lead)
        local extra = ""
        if U.chance(J.SEEK_KNOWLEDGE_CHANCE) then
            local k = GameRandom.Free_Random(J.SEEK_KNOWLEDGE[1], J.SEEK_KNOWLEDGE[2])
            s.knowledge = s.knowledge + k
            extra = " Old writings found there: Knowledge +" .. k .. "."
        end
        local tries = (kind == "REFUGEES") and 2 or 1
        for _ = 1, tries do
            local roll = GameRandom.Free_Random(1, 100)
            if force > 0 and count_waiting(s) < Order.initiate_cap(s) and roll <= chance then
                local q = student(d, s, m.world, nil, (side > 0) and M.floor(side / 2) or nil)
                return Order.label(p) .. " returns from " .. where .. " with someone gifted: " .. q.name .. "." .. extra
            elseif roll <= chance + J.SEEK_LEAD_BAND + M.floor(force / J.SEEK_LEAD_FORCE) then
                local people = {"CHILD", "FAMILY", "REFUGEES"}
                local other = {}
                if force >= 30 then
                    table.insert(other, "HERMIT")
                end
                if force >= J.LORE_FORCE then
                    table.insert(other, "RUINS")
                    table.insert(other, "HOLOCRON")
                end
                if side >= J.DARK_SITE then
                    table.insert(other, "NIGHTSISTER")
                    table.insert(other, "DARK_SITE")
                end
                local elsewhere = {"RUINS", "HERMIT", "UNREST", "TURMOIL", "DARK_SITE"}
                local kinds = (other[1] and not U.chance(J.SEEK_LEAD_PEOPLE)) and other or people
                local new = U.chance(J.SEEK_LEAD_HERE) and Order.add_lead(d, s, U.pick(kinds), {world = m.world, who = p.name})
                    or Order.new_lead(d, s, U.chance(J.SEEK_LEAD_PEOPLE) and people or elsewhere, 6)
                if new then
                    return Order.label(p) .. " searched " .. where .. " and came away with " .. U.pick(J.SEEK_LEAD_TEXTS)
                        .. ": " .. new.title .. "." .. extra
                end
            end
        end
        if side < -J.SEEK_SIDE then
            local f = U.pick(J.SEEK_LIGHT)
            if f[1] == "healer" then
                local Sym = Republic().part("sym")
                local Desires = Republic().part("desires")
                local planet = FindPlanet(m.world)
                if planet and planet.Get_Owner() == d.human and Desires then
                    Desires.boost(d, m.world, 5, 10, "the Jedi's visit")
                elseif Sym then
                    Sym.change(d, m.world, 5)
                end
            elseif f[1] == "calm" then
                p.shadow = M.max(0, p.shadow - 10)
            elseif f[1] == "echo" and force >= 40 then
                s.knowledge = s.knowledge + 4
            end
            return Order.label(p) .. " searched " .. where .. " and found " .. f[2] .. "." .. extra
        elseif side > J.SEEK_SIDE then
            local f = (force >= 40) and U.pick(J.SEEK_DARK) or J.SEEK_DARK[1]
            if f[1] == "aspirant" and U.chance(50) then
                local q = student(d, s, m.world, nil, 30)
                return Order.label(p) .. " found " .. f[2] .. " on " .. where .. ", and brought them home anyway: "
                    .. q.name .. ", a troubled student."
            end
            Order.raise_shadow(p, 3)
            Order.add_lead(d, s, "DARK_SITE", {world = m.world})
            return Order.label(p) .. " searched " .. where .. " and found only " .. f[2] .. "."
        end
        p.xp = (p.xp or 0) + 5
        return Order.label(p) .. " searched " .. where .. " and found " .. U.pick(J.SEEK_NONE) .. "." .. extra
    end

    function Order.seek_chance(s, world, lead)
        if (lead and (lead.kind == "CHILD" or lead.kind == "NIGHTSISTER"))
                or (Order.relic_flag and Order.relic_flag(s, "seek_certain", world)) then
            return 100
        end
        local force = Order.force_of(world) + ((lead and lead.kind == "REFUGEES") and J.REFUGEE_FORCE or 0)
        if force <= 0 or not Order.peopled(world) then
            return 0
        end
        local v = M.max(J.SEEK_FLOOR, M.min(J.SEEK_MAX, force * J.SEEK_STUDENT_SCALE))
        v = v + (s.charter.ATTACH == "OLD" and -5 or 0) + (s.charter.ATTACH == "LUKE" and 8 or 0)
        return U.clamp(M.round(v), 0, 100)
    end

    local ok_w, WL = pcall(require, "eawx-plugins/jedi-order/JediWorldLore")
    WL = (ok_w and type(WL) == "table") and WL or {LORE = {}, GENERIC = {}}
    function Order.force_lore(world)
        local force, side = Order.force_of(world), Order.side_of(world)
        local text = WL.LORE[world]
        if not text then
            for _, row in ipairs(WL.GENERIC) do
                if not text and force >= row[1] then
                    text = row[2]
                end
            end
            text = (text or "") .. ((side >= 30 and WL.DARK) or (side <= -30 and WL.LIGHT) or "")
        end
        return text
    end

    function Order.seek_word(chance, world)
        if chance >= 100 then
            return "a student, certain"
        end
        local force = world and Order.force_of(world) or chance
        for _, row in ipairs(J.FORCE_WORDS) do
            if force >= row[1] then
                return "Force: " .. row[2]
            end
        end
        return "Force: absent"
    end
end

return Leads
