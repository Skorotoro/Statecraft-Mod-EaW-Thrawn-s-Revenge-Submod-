require("eawx-util/ChangeOwnerUtilities")
require("eawx-util/PopulatePlanetUtilities")
require("PGSpawnUnits")
local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")
local Agents = require("eawx-plugins/imperial-court/CourtOperatives")

local Intel = {}
local SPY = CONFIG.SPY
local CV = CONFIG.COVERT

local NEUTRAL = {EMPIRE = true, NEUTRAL = true, HOSTILE = true}
local MAJOR = {REBEL = true, HAPES_CONSORTIUM = true, HUTT_CARTELS = true, CORPORATE_SECTOR = true, EMPIREOFTHEHAND = true,
               CHISS = true, YEVETHA = true}

local SHARED = {INDEPENDENT_FORCES = true, WARLORDS = true}

function Intel.world_target(target)
    if type(target) == "string" and string.sub(target, 1, 1) == "@" then
        return string.sub(target, 2)
    end
    return nil
end

function Intel.owner(target)
    local world = Intel.world_target(target)
    if not world then
        return target
    end
    local planet = FindPlanet(world)
    return planet and string.upper(planet.Get_Owner().Get_Faction_Name()) or "INDEPENDENT_FORCES"
end

local function label(faction)
    local world = Intel.world_target(faction)
    if world then
        return Court.planet_label(world)
    end
    return Court.faction_label(faction)
end
Intel.label = label

local function ops(s)
    s.ops.running = s.ops.running or {}
    return s.ops
end

function Intel.targets(s)
    local counts = {}
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = string.upper(planet.Get_Owner().Get_Faction_Name())
        local name = Court.name_of(planet)
        if SHARED[owner] then
            if not string.find(name, "REGIMEPICKER$") then
                table.insert(out, {faction = "@" .. name, worlds = 1, owner = owner})
            end
        elseif not NEUTRAL[owner] and not string.find(owner, "^DIPLOMACY_VASSALS") then
            counts[owner] = (counts[owner] or 0) + 1
        end
    end
    for faction, n in pairs(counts) do
        table.insert(out, {faction = faction, worlds = n})
    end
    table.sort(out, function(a, b)
        if a.worlds ~= b.worlds then
            return a.worlds > b.worlds
        end
        return a.faction < b.faction
    end)
    return out
end

local GROUP_ORDER = {}
function Intel.groups(s)
    local targets = Intel.targets(s)
    local by_name = {}
    for _, t in ipairs(targets) do
        by_name[t.faction] = t
    end
    local out, placed = {}, {}
    local ok, cats = false, nil
    if DIPLOMACY_CATEGORIES then
        ok, cats = pcall(DIPLOMACY_CATEGORIES)
    end
    for _, cat in ipairs(ok and cats or {}) do
        local list, worlds = {}, {}
        for _, name in ipairs(cat[2]) do
            local t = by_name[string.upper(name)]
            if t and not placed[t.faction] then
                placed[t.faction] = true
                table.insert(list, t)
            end
            if SHARED[string.upper(name)] then
                for _, w in ipairs(targets) do
                    if w.owner == string.upper(name) and not placed[w.faction] then
                        placed[w.faction] = true
                        table.insert(worlds, w)
                    end
                end
            end
        end
        table.sort(list, function(a, b)
            if a.worlds ~= b.worlds then
                return a.worlds > b.worlds
            end
            return a.faction < b.faction
        end)
        table.sort(worlds, function(a, b)
            return label(a.faction) < label(b.faction)
        end)
        for _, w in ipairs(worlds) do
            table.insert(list, w)
        end
        if table.getn(list) > 0 then
            table.insert(out, {cat[1], list})
        end
    end
    local rest = {}
    for _, t in ipairs(targets) do
        if not placed[t.faction] then
            table.insert(rest, t)
        end
    end
    if table.getn(rest) > 0 then
        table.insert(out, {(table.getn(out) > 0) and "Other Powers" or "Foreign Powers", rest})
    end
    return out
end

function Intel.is_warlord(faction)
    local data = Court.warlord_data()
    for _, w in ipairs(data and data.WARLORDS or {}) do
        if w.faction == faction then
            return true
        end
    end
    return false
end

function Intel.relation(faction)
    if not DIPLOMACY_RELATION then
        return "WAR"
    end
    local ok, relation = pcall(DIPLOMACY_RELATION, Intel.owner(faction))
    return ok and relation or "WAR"
end

function Intel.capital(faction)
    local world = Intel.world_target(faction)
    if world then
        return FindPlanet(world)
    end
    if not DIPLOMACY_CAPITAL then
        return nil
    end
    local ok, planet = pcall(DIPLOMACY_CAPITAL, faction)
    return ok and planet or nil
end

function Intel.capital_name(faction)
    local world = Intel.world_target(faction)
    if world then
        return world
    end
    local planet = Intel.capital(faction)
    if planet then
        return Court.name_of(planet)
    end
    return Intel.worlds_of(faction)[1]
end

function Intel.opinion(a, b)
    if not DIPLOMACY_OPINION then
        return 0, {}
    end
    a, b = Intel.owner(a), Intel.owner(b)
    local ok, value = pcall(DIPLOMACY_OPINION, a, b)
    local ok2, reasons = pcall(DIPLOMACY_OPINION_REASONS, a, b)
    return ok and value or 0, ok2 and reasons or {}
end

function Intel.at_war(a, b)
    local pa, pb = Find_Player(Intel.owner(a)), Find_Player(Intel.owner(b))
    return not (pa and pb) or pa.Is_Enemy(pb)
end

function Intel.network(s, faction)
    s.spy = s.spy or {}
    local n = s.spy[faction]
    if not n then
        n = {tier = SPY.PEACE[Intel.relation(faction)] and 1 or 0, progress = 0}
        s.spy[faction] = n
    end
    return n
end

function Intel.tier_name(tier)
    return SPY.NAMES[tier] or "?"
end

function Intel.raise(s, faction, how, world)
    local n = Intel.network(s, faction)
    if n.tier >= SPY.MAX then
        return
    end
    n.tier, n.progress = n.tier + 1, 0
    Court.news(s, "Spy network in " .. label(faction) .. " rises to tier " .. n.tier .. " (" .. Intel.tier_name(n.tier) .. ")"
        .. (how and (": " .. how) or "") .. ".")
    Agents.say(world and "probe" or "tier_up", {target = label(faction), tier = n.tier, tiername = Intel.tier_name(n.tier),
                                                world = world and Court.planet_label(world)})
end

local probes = {}
local each = string.gfind or string.gmatch

local function probe_spied(s, world)
    local planet = FindPlanet(world)
    local owner = planet and string.upper(planet.Get_Owner().Get_Faction_Name())
    if owner and SHARED[owner] then
        owner = "@" .. world
    end
    if owner and owner ~= CONFIG.FACTION and not NEUTRAL[owner] and Intel.network(s, owner).tier == 0 then
        local capital = Intel.capital(owner)
        if not capital or Court.name_of(capital) == world then
            Intel.raise(s, owner, "a probe droid spied on " .. Court.planet_label(world), world)
        end
    end
end

function Intel.watch_probes(s)
    if Engine_Spied then
        local data = Engine_Spied()
        for entry in each(data or "", "[^;]+") do
            local _, _, world, unit = string.find(entry, "^([^|]*)|(.*)$")
            if world and world ~= "" and unit and string.find(string.upper(unit), "PROBE") then
                probe_spied(s, string.upper(world))
            end
        end
        return
    end
    local now = GetCurrentTime()
    local empire = Court.player()
    local seen = {}
    for _, type_name in ipairs(SPY.PROBES) do
        if Find_Object_Type(type_name) then
            for _, obj in pairs(Find_All_Objects_Of_Type(type_name) or {}) do
                if TestValid(obj) and obj.Get_Owner() == empire then
                    local ok, planet = pcall(function()
                        return obj.Get_Planet_Location()
                    end)
                    table.insert(seen, {obj = obj, planet = ok and planet and Court.name_of(planet) or nil, time = now})
                end
            end
        end
    end
    for _, old in ipairs(probes) do
        if old.planet and now - old.time < 15 and not TestValid(old.obj) then
            local planet = FindPlanet(old.planet)
            local owner = planet and string.upper(planet.Get_Owner().Get_Faction_Name())
            if owner and owner ~= CONFIG.FACTION and not NEUTRAL[owner] and Intel.capital_name(owner) == old.planet
                    and Intel.network(s, owner).tier == 0 then
                Intel.raise(s, owner, "a probe droid spied on " .. Court.planet_label(old.planet), old.planet)
            end
        end
    end
    probes = seen
end

local function open_by_peace(s)
    for _, t in ipairs(Intel.targets(s)) do
        if Intel.network(s, t.faction).tier == 0 and SPY.PEACE[Intel.relation(t.faction)] then
            Intel.raise(s, t.faction, "our envoys open doors")
        end
    end
end

function Intel.worlds_of(faction)
    local world = Intel.world_target(faction)
    if world then
        return {world}
    end
    local player = Find_Player(faction)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            table.insert(out, Court.name_of(planet))
        end
    end
    table.sort(out)
    return out
end

local function unit_name(type_name)
    return (DIPLOMACY_UNIT_NAME and DIPLOMACY_UNIT_NAME(type_name)) or type_name
end
Intel.unit_name = unit_name

local function is_dummy(type_name)
    return string.find(type_name, "DUMMY") or string.find(type_name, "^INFLUENCE_") or unit_name(type_name) == type_name
end

function Intel.buildings(faction, world)
    local player = Find_Player(Intel.owner(faction))
    local planet = FindPlanet(world)
    local out = {}
    for _, obj in pairs(player and planet and Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(obj) and obj.Get_Planet_Location() == planet and obj.Is_Category("Structure")
                and not obj.Get_Type().Is_Hero() then
            local t = string.upper(obj.Get_Type().Get_Name())
            if not is_dummy(t) then
                table.insert(out, {type = t, name = unit_name(t)})
            end
        end
    end
    return out
end

function Intel.heroes(faction)
    local only = Intel.world_target(faction)
    local player = Find_Player(Intel.owner(faction))
    local out, seen = {}, {}
    local ok, all = pcall(Find_All_Objects_Of_Type, player, "SpaceHero | InfantryHero | VehicleHero | NonCombatHero")
    for _, unit in pairs(ok and all or {}) do
        if TestValid(unit) then
            local t = string.upper(unit.Get_Type().Get_Name())
            local ok2, planet = pcall(function()
                return unit.Get_Planet_Location()
            end)
            local here = ok2 and planet and Court.name_of(planet) or nil
            if not seen[t] and not string.find(t, "PROBE") and (not only or here == only) then
                seen[t] = true
                table.insert(out, {type = t, name = unit_name(t), world = ok2 and planet and Court.name_of(planet) or nil})
            end
        end
    end
    table.sort(out, function(a, b)
        return a.name < b.name
    end)
    return out
end

local function hero_unit(faction, type_name)
    local player = Find_Player(Intel.owner(faction))
    if not (player and Find_Object_Type(type_name)) then
        return nil
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(type_name) or {}) do
        if TestValid(obj) and obj.Get_Owner() == player then
            return obj
        end
    end
    return nil
end

function Intel.char_location(s, c)
    if c.lore then
        local obj = Court.unit_on_map(c.lore)
        local ok, planet = pcall(function()
            return obj and obj.Get_Planet_Location()
        end)
        if ok and planet then
            return Court.name_of(planet)
        end
    end
    return Court.capital_of(s, c) or s.capital
end

function Intel.influence(world)
    local service = IMPERIAL_COURT_INFLUENCE_SERVICE
    for _, entry in pairs(service and service.planets or {}) do
        if string.upper(entry.object_name or "") == world then
            return entry.ownerInfluence
        end
    end
    return nil
end

local function loyalty_table()
    local service = IMPERIAL_COURT_INFLUENCE_SERVICE
    if service and service.LoyaltyTable then
        return service.LoyaltyTable
    end
    local ok, t = pcall(ModContentLoader.get, "influence-policy/LoyaltyTable")
    return ok and t or nil
end

function Intel.preferred(world)
    local t = loyalty_table()
    return t and t[world] or "INDEPENDENT_FORCES"
end

function Intel.location(s, op)
    local def = CONFIG.OPS[op.key]
    if def.at == "capital" then
        return Intel.capital_name(op.target)
    elseif def.at == "planet" then
        return op.planet
    elseif def.at == "hero" then
        local obj = op.hero and hero_unit(op.target, op.hero)
        local ok, planet = pcall(function()
            return obj and obj.Get_Planet_Location()
        end)
        return ok and planet and Court.name_of(planet) or nil
    elseif def.at == "char" then
        local c = Court.char(s, op.char)
        return c and Intel.char_location(s, c)
    end
    return nil
end

function Intel.director(s)
    local d = Court.char(s, s.offices.INTEL)
    return (d and d.status == "serving") and d or nil
end

function Intel.denounced(s, id)
    local ok, T = pcall(require, "eawx-plugins/imperial-court/CourtTerritory")
    return ok and T and T.denounced(s, id) or false
end

local function any_denounced(s)
    for _, id in ipairs(s.order) do
        if s.chars[id].status == "serving" and Intel.denounced(s, id) then
            return true
        end
    end
    return false
end

local function director_problem(s)
    local d = Intel.director(s)
    if not d then
        return "Needs a Director of Imperial Intelligence."
    elseif d.loyalty < CV.DIRECTOR_LOYALTY then
        return "The Director (" .. d.name .. ", loyalty " .. M.round(d.loyalty) .. ") cannot be trusted with the court: "
            .. "needs loyalty " .. CV.DIRECTOR_LOYALTY .. "."
    end
    return nil
end
Intel.director_problem = director_problem

function Intel.chance(s, key, op)
    local def = CONFIG.OPS[key]
    op = op or {}
    local chance = def.chance + CV.DIRECTOR * Court.office_strength(s, "INTEL") + (Court.regime(s).covert or 0)
    local a = op.agent and Agents.get(s, op.agent)
    if a then
        local TE = CONFIG.AGENT_TRAIT_EFFECT
        chance = chance + CV.RANK * ((a.rank or 1) - 1)
        local trait = Agents.op_trait(key)
        if trait and Agents.has(a, trait) then
            chance = chance + TE.OP_SUCCESS
        end
        if def.internal and Agents.has(a, "FEARED") then
            chance = chance + TE.COURT_SUCCESS
        end
    end
    if op.planet and op.target and Intel.capital_name(op.target) == op.planet then
        chance = chance + (def.capital or CV.CAPITAL)
    end
    if key == "DEFECTION" and op.target then
        if op.target == "REBEL" then
            chance = chance + def.republic
        elseif not Intel.is_warlord(op.target) then
            chance = chance + def.major
        end
    elseif key == "INCITE" and op.planet then
        chance = chance + def.per_influence * (6 - (Intel.influence(op.planet) or 5))
    elseif key == "INCITE_WAR" and op.faction and op.target then
        chance = chance - Intel.opinion(op.faction, op.target) / 4
    elseif key == "TREASON" or key == "ARREST" or key == "MURDER" then
        local c = Court.char(s, op.char)
        if c then
            chance = chance + (50 - c.loyalty) * CV.LOYALTY_EASE * ((key == "TREASON") and 1 or 0.5)
            if key == "TREASON" and Intel.denounced(s, c.id) then
                chance = chance + CONFIG.TERRITORY.DENOUNCE.TREASON_BONUS
            end
            if key == "ARREST" and c.traitor then
                chance = chance + def.traitor
            end
        end
    end
    if def.chance >= 100 then
        return 100
    end
    return M.clamp(M.round(chance), 5, 95)
end

function Intel.caught_chance(s, key, op)
    local def = CONFIG.OPS[key]
    local a = op and op.agent and Agents.get(s, op.agent)
    local caught = def.caught * (1 - 0.5 * Court.office_strength(s, "INTEL")) - (a and 3 * ((a.rank or 1) - 1) or 0)
    if (def.caught or 0) == 0 then
        return 0
    end
    if a then
        local TE = CONFIG.AGENT_TRAIT_EFFECT
        local trait = Agents.op_trait(key)
        if trait and Agents.has(a, trait) then
            caught = caught + TE.OP_CAUGHT
        end
        if Agents.has(a, "DISGUISE") then
            caught = caught + TE.DISGUISE_CAUGHT
        end
    end
    return M.clamp(M.round(caught), 0, 90)
end

function Intel.cost(s, key, op)
    local def = CONFIG.OPS[key]
    local a = op and op.agent and Agents.get(s, op.agent)
    if a and Agents.has(a, "CONNECTED") then
        return M.round(def.cost * CONFIG.AGENT_TRAIT_EFFECT.CONNECTED_COST)
    end
    return def.cost
end

function Intel.blocked(s, key, target)
    local def = CONFIG.OPS[key]
    if not def then
        return "Unknown operation."
    end
    if key == "COUNTER" then
        if Court.player().Get_Credits() < def.cost then
            return "Needs " .. def.cost .. " credits."
        end
        return nil
    end
    if not target then
        return "Select a target first."
    end
    if def.internal then
        local problem = director_problem(s)
        if problem and not ((key == "TREASON" or key == "ARREST") and any_denounced(s)) then
            return problem
        end
    else
        local tier = Intel.network(s, target).tier
        if tier == 0 then
            return "No spy network in " .. label(target) .. " yet: a probe droid spying on their capital, or a ceasefire, opens one."
        elseif tier < (def.tier or 1) then
            return "Needs a tier " .. def.tier .. " spy network (now tier " .. tier .. "): gather intelligence to build it."
        end
        if key ~= "GATHER" and not Intel.director(s) then
            return "Needs a Director of Imperial Intelligence: appoint one in the Council first."
        end
    end
    if Court.player().Get_Credits() < def.cost then
        return "Needs " .. def.cost .. " credits."
    end
    if (def.authority or 0) > s.authority then
        return "Needs " .. def.authority .. " authority."
    end
    if table.getn(Agents.list(s)) == 0 then
        return "No operatives: recruit one first (Imperial Operatives, top right of the list)."
    end
    return nil
end

function Intel.pick_blocked(s, key, kind, value, op)
    local def = CONFIG.OPS[key]
    if kind == "faction" then
        if value == op.target then
            return "Choose another power."
        end
        if key == "INCITE_WAR" and Intel.at_war(value, op.target) then
            return label(value) .. " is already at war with " .. label(op.target) .. "."
        end
    elseif kind == "char" then
        local c = s.chars[value]
        if not c or c.status ~= "serving" then
            return "They no longer serve."
        end
        if c.leads then
            return c.name .. " rules the Empire."
        end
        if s.offices.INTEL == c.id and key ~= "MINDER" then
            return c.name .. " is the Director: Intelligence will not move against its own head."
        end
        if not def.protected_ok then
            local Actions = require("eawx-plugins/imperial-court/CourtActions")
            local why = Actions.protected(s, c, "arrest")
            if why then
                return why
            end
        end
        if key == "MINDER" and c.minder then
            return "A minder already watches " .. c.name .. "."
        end
        if key == "TREASON" and c.traitor then
            return c.name .. " is already branded a traitor."
        end
        if (key == "TREASON" or key == "ARREST") and director_problem(s) and not Intel.denounced(s, c.id) then
            return "Without a loyal Director, Intelligence moves only against a lord their rivals have denounced."
        end
        for _, a in ipairs(Agents.list(s)) do
            if a.kind == "lore" and a.char == c.id then
                return c.name .. " is one of your operatives."
            end
        end
    elseif kind == "building" and key == "SABOTAGE" then
        return nil
    elseif kind == "planet" and key == "BRIBE" then
        local b = s.bribes and s.bribes[value]
        if b and b.ends > s.week then
            return Court.planet_label(value) .. " is bribed already."
        end
    elseif kind == "planet" and key == "PROPAGANDA" then
        local p = s.propaganda and s.propaganda[value]
        if p then
            return "Propaganda already works on " .. Court.planet_label(value) .. "."
        end
    end
    return nil
end

function Intel.agent_blocked(s, a, op)
    if a.mission then
        return Agents.label(s, a) .. " is busy with another operation."
    end
    local at = Intel.location(s, op)
    if not at then
        return "The target cannot be found."
    end
    local here = Agents.location(s, a)
    if here ~= at then
        return Agents.label(s, a) .. " must be at " .. Court.planet_label(at) .. " (now "
            .. (here and ("at " .. Court.planet_label(here)) or "in hyperspace") .. ")."
    end
    return nil
end

function Intel.launch(s, op)
    local key = op.key
    local def = CONFIG.OPS[key]
    local why = Intel.blocked(s, key, op.target)
    if why then
        return false, why
    end
    if key == "COUNTER" then
        Court.player().Give_Money(-def.cost)
        ops(s).counter_until = s.week + def.lasts
        return true, "Counter-intelligence sweeps until week " .. ops(s).counter_until .. "."
    end
    for _, kind in ipairs(def.pick or {}) do
        local value = op[kind]
        if not value then
            return false, "Choose a " .. kind .. " first."
        end
        why = Intel.pick_blocked(s, key, kind, value, op)
        if why then
            return false, why
        end
    end
    local a = op.agent and Agents.get(s, op.agent)
    if not a then
        return false, "Choose an operative."
    end
    why = Intel.agent_blocked(s, a, op)
    if why then
        return false, why
    end
    Court.player().Give_Money(-Intel.cost(s, key, op))
    s.authority = s.authority - (def.authority or 0)
    local run = {key = key, target = op.target, planet = op.planet, building = op.building, hero = op.hero,
                 faction = op.faction, char = op.char, agent = a.id, at = Intel.location(s, op), started = s.week,
                 done = s.week + def.weeks, tier = (not def.internal) and Intel.network(s, op.target).tier or nil}
    a.mission = key
    table.insert(ops(s).running, run)
    if key == "MINDER" then
        local c = Court.char(s, op.char)
        c.minder = a.id
        Court.opinion(c, "watched by Intelligence", -4, 6)
        run.open = true
        Agents.say("MINDER_ok", {agent = Agents.label(s, a), char = c.name})
        return true, Agents.label(s, a) .. " now watches " .. c.name .. "."
    end
    return true, def.name .. " under way: " .. Agents.label(s, a) .. ", " .. M.weeks(def.weeks) .. ", "
        .. Intel.chance(s, key, run) .. "% to succeed."
end

local function finish_run(s, run)
    local kept = {}
    for _, r in ipairs(ops(s).running) do
        if r ~= run then
            table.insert(kept, r)
        end
    end
    ops(s).running = kept
    local a = Agents.get(s, run.agent)
    if a then
        a.mission = nil
    end
end

function Intel.recall(s, run)
    if run.key == "MINDER" then
        local c = Court.char(s, run.char)
        if c then
            c.minder = nil
            local a = Agents.get(s, run.agent)
            Agents.say("MINDER_end", {agent = a and Agents.label(s, a) or "The operative", char = c.name})
        end
    end
    finish_run(s, run)
    local a = Agents.get(s, run.agent)
    return true, (a and Agents.label(s, a) or "The operative") .. " is recalled."
end

function Intel.run_of(s, agent_id)
    for _, r in ipairs(ops(s).running) do
        if r.agent == agent_id then
            return r
        end
    end
    return nil
end

local function report(s, target)
    local player = Find_Player(Intel.owner(target))
    local worlds = table.getn(Intel.worlds_of(target))
    local heroes = {}
    for _, h in ipairs(Intel.heroes(target)) do
        if table.getn(heroes) < 4 then
            table.insert(heroes, h.name)
        end
    end
    ops(s).reports = ops(s).reports or {}
    ops(s).reports[target] = {week = s.week, worlds = worlds, credits = M.round(player.Get_Credits()), heroes = heroes}
end

local function publish_bribes(s)
    local parts = {}
    for world, b in pairs(s.bribes or {}) do
        if b.ends > s.week then
            local types = {}
            for t, n in pairs(b.types) do
                table.insert(types, t .. "*" .. n)
            end
            table.insert(parts, world .. "=" .. table.concat(types, ","))
        end
    end
    GlobalValue.Set("COURT_BRIBES", table.concat(parts, ";"))
end

local function bribe(s, run)
    local garrisons = {}
    local ok, G = pcall(require, "eawx-plugins/imperial-court/CourtGarrisons")
    for _, b in ipairs(Intel.buildings(run.target, run.planet)) do
        if ok and G[b.type] then
            table.insert(garrisons, b.type)
        end
    end
    local n = table.getn(garrisons)
    if n == 0 then
        return false, "there was no garrison to bribe on " .. Court.planet_label(run.planet)
    end
    local types, count = {}, 0
    local want = M.floor((n + 1) / 2)
    while count < want do
        local k = M.random(1, table.getn(garrisons))
        local t = table.remove(garrisons, k)
        types[t] = (types[t] or 0) + 1
        count = count + 1
    end
    s.bribes = s.bribes or {}
    s.bribes[run.planet] = {faction = run.target, ends = s.week + CONFIG.OPS.BRIBE.lasts, types = types, count = count}
    publish_bribes(s)
    return true, count .. " of " .. n .. " garrison buildings on " .. Court.planet_label(run.planet) .. " will send no troops for "
        .. M.weeks(CONFIG.OPS.BRIBE.lasts)
end

local function sabotage(s, run)
    local player = Find_Player(Intel.owner(run.target))
    local planet = FindPlanet(run.planet)
    for _, obj in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(obj) and obj.Get_Planet_Location() == planet
                and string.upper(obj.Get_Type().Get_Name()) == run.building then
            obj.Despawn()
            return true, "their " .. unit_name(run.building) .. " on " .. Court.planet_label(run.planet) .. " is rubble"
        end
    end
    return false, "the " .. unit_name(run.building) .. " was gone before our agent struck"
end

local function propaganda(s, run)
    local t = loyalty_table()
    if not t then
        return false, "the world would not listen"
    end
    s.propaganda = s.propaganda or {}
    s.propaganda[run.planet] = {old = t[run.planet] or false, ends = s.week + CONFIG.OPS.PROPAGANDA.lasts, owner = run.target}
    t[run.planet] = CONFIG.FACTION
    return true, Court.planet_label(run.planet) .. " would rise for the Empire for " .. M.weeks(CONFIG.OPS.PROPAGANDA.lasts)
end

local function end_propaganda(s, world)
    local p = s.propaganda and s.propaganda[world]
    local t = loyalty_table()
    if p and t then
        t[world] = p.old or nil
    end
    if s.propaganda then
        s.propaganda[world] = nil
    end
end

local function publish_influence(s)
    local map = {}
    for world, e in pairs(s.influence_mods or {}) do
        if e.ends > s.week then
            map[world] = e.value
        end
    end
    IMPERIAL_COURT_INFLUENCE = map
end

local function stage_attack(s, run)
    local def = CONFIG.OPS.STAGE_ATTACK
    s.influence_mods = s.influence_mods or {}
    s.influence_mods[run.planet] = {value = def.influence, ends = s.week + def.lasts}
    publish_influence(s)
    if DIPLOMACY_OPINION_ADD then
        pcall(DIPLOMACY_OPINION_ADD, Intel.owner(run.target), run.faction, def.opinion, def.lasts * 2,
            "blamed for an attack on " .. Court.planet_label(run.planet))
    end
    return true, "an atrocity on " .. Court.planet_label(run.planet) .. " is blamed on " .. label(run.faction)
        .. "; " .. label(run.target) .. " will not forget it"
end

local function battle_near(obj)
    return not Agents.safe_to_remove(obj)
end

local function assassinate(s, run)
    local obj = hero_unit(run.target, run.hero)
    if not obj then
        return false, unit_name(run.hero) .. " could not be found"
    end
    if battle_near(obj) then
        return nil, "a battle looms at " .. Court.planet_label(run.at) .. ": the agent waits"
    end
    obj.Despawn()
    return true, unit_name(run.hero) .. " is dead"
end

local function defection(s, run)
    local obj = hero_unit(run.target, run.hero)
    local capital = s.capital and FindPlanet(s.capital)
    if not obj or not capital then
        return false, unit_name(run.hero) .. " could not be reached"
    end
    if battle_near(obj) then
        return nil, "a battle looms at " .. Court.planet_label(run.at) .. ": the agent waits"
    end
    obj.Despawn()
    local ok = pcall(SpawnList, {run.hero}, capital, Court.player(), true, false)
    if not ok then
        return false, unit_name(run.hero) .. " never arrived"
    end
    return true, unit_name(run.hero) .. " defects and arrives at " .. Court.planet_label(s.capital)
end

function Intel.rising_owner(world)
    local planet = FindPlanet(world)
    local new_owner = string.upper(Intel.preferred(world) or "INDEPENDENT_FORCES")
    if planet and new_owner == string.upper(planet.Get_Owner().Get_Faction_Name()) then
        new_owner = "INDEPENDENT_FORCES"
    end
    local ok, player = pcall(Find_Player, new_owner)
    if not ok or not player then
        player = Find_Player("Independent_Forces")
    end
    return player
end

local function incite(s, run)
    local planet = FindPlanet(run.planet)
    if not planet then
        return false, "the world is gone"
    end
    if DIPLOMACY_CAN_RISE and not DIPLOMACY_CAN_RISE(run.planet) then
        return false, "nobody lives there to rise"
    end
    local new_owner = Intel.preferred(run.planet)
    local current = string.upper(planet.Get_Owner().Get_Faction_Name())
    if string.upper(new_owner) == current then
        new_owner = "INDEPENDENT_FORCES"
    end
    local player = Find_Player(new_owner)
    if not player then
        return false, "nobody came to lead the rising"
    end
    DIPLOMACY_REVOLTS = DIPLOMACY_REVOLTS or {}
    DIPLOMACY_REVOLTS[string.upper(run.planet)] = {kind = "REVOLT", time = GetCurrentTime()}
    if DIPLOMACY_REVOLT_POPULATE then
        DIPLOMACY_REVOLT_POPULATE(planet, player, 4500)
    else
        ChangePlanetOwnerAndPopulate(planet, player, 4500)
    end
    if string.upper(new_owner) == CONFIG.FACTION and IMPERIAL_COURT_LEGITIMACY then
        pcall(IMPERIAL_COURT_LEGITIMACY, "WORLD_REVOLTS")
    end
    return true, Court.planet_label(run.planet) .. " rises against " .. label(run.target) .. " for " .. label(string.upper(new_owner))
end

local function incite_war(s, run)
    local def = CONFIG.OPS.INCITE_WAR
    if DIPLOMACY_OPINION_ADD then
        pcall(DIPLOMACY_OPINION_ADD, run.faction, Intel.owner(run.target), def.opinion, 20, "forged proof of treachery")
    end
    if not (DIPLOMACY_FORCE_WAR and DIPLOMACY_FORCE_WAR(run.faction, Intel.owner(run.target))) then
        return false, label(run.faction) .. " would not listen"
    end
    return true, label(run.faction) .. " accuses " .. label(run.target) .. " of treachery and declares war"
end

local function rivals_and_friends(s, c, rivals, friends, why)
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if v.status == "serving" and v ~= c then
            if Court.is_friend(v, c.id) then
                Court.opinion(v, why .. " (" .. c.name .. ", a friend)", friends, 16)
            elseif rivals ~= 0 and Court.has_tie(v, c.id, "rivals") then
                Court.opinion(v, why .. " (" .. c.name .. ", a rival)", rivals, 12)
            end
        end
    end
end

local function everyone(s, c, value, text, weeks)
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if v.status == "serving" and v ~= c then
            Court.opinion(v, text, value, weeks)
        end
    end
end

local function hero_of(s, c)
    if not c.lore then
        return nil
    end
    local obj, owner = Court.unit_on_map(c.lore)
    return (owner == CONFIG.FACTION) and obj or nil
end

local function treason(s, run)
    local c = Court.char(s, run.char)
    if not c or c.status ~= "serving" then
        return false, "they are beyond reach"
    end
    c.traitor = true
    Court.opinion(c, "branded a traitor", -20, 20)
    return true, c.name .. " is branded a traitor: every title can now be taken from them freely"
end

local function arrest(s, run)
    local c = Court.char(s, run.char)
    if not c or c.status ~= "serving" then
        return false, "they are beyond reach"
    end
    local hero = hero_of(s, c)
    rivals_and_friends(s, c, CV.ARREST_RIVALS, CV.ARREST_FRIENDS, "arrested")
    if not c.traitor then
        everyone(s, c, CV.ARREST_TYRANNY, "an arrest without proof", 12)
        s.stability = M.max(0, s.stability - CV.ARREST_STABILITY)
    end
    Court.remove(s, c, "imprisoned", "is arrested and thrown into the Imperial Prison")
    c.loyalty = 0
    Court.opinion(c, "imprisoned", CV.PRISON_LOYALTY)
    if hero then
        Agents.queue_removal(s, hero)
    end
    return true, c.name .. " is in the Imperial Prison" .. (c.traitor and "" or "; the court calls it tyranny")
end

local function murder(s, run)
    local c = Court.char(s, run.char)
    if not c or c.status ~= "serving" then
        return false, "they are beyond reach"
    end
    local hero = hero_of(s, c)
    Court.remove(s, c, "dead", "dies in a tragic accident")
    if hero then
        Agents.queue_removal(s, hero)
    end
    return true, c.name .. " dies; it looks like an accident"
end

local function succeed(s, run)
    local def = CONFIG.OPS[run.key]
    local target = run.target
    if run.key == "GATHER" then
        report(s, target)
        local n = Intel.network(s, target)
        if n.tier >= SPY.MAX then
            return true, "the files on " .. label(target) .. " are ready"
        end
        n.progress = n.progress + SPY.GATHER
        if n.progress >= SPY.PROGRESS then
            Intel.raise(s, target, "new agents in place")
            return true, "the files on " .. label(target) .. " are ready"
        end
        return true, "the files on " .. label(target) .. " are ready (intel progress " .. n.progress .. "/" .. SPY.PROGRESS .. ")"
    elseif run.key == "SWAY" then
        if Intel.is_warlord(target) then
            local rec = s.integration[target] or {empire = 0, rivals = {}}
            s.integration[target] = rec
            rec.empire = M.min(100, rec.empire + def.influence)
            return true, "your influence over " .. label(target) .. " grows by " .. def.influence .. "%"
        end
        s.attitude[target] = (s.attitude[target] or 0) + 10
        return true, label(target) .. " warms to the Empire"
    elseif run.key == "BRIBE" then
        return bribe(s, run)
    elseif run.key == "SABOTAGE" then
        return sabotage(s, run)
    elseif run.key == "PROPAGANDA" then
        return propaganda(s, run)
    elseif run.key == "STAGE_ATTACK" then
        return stage_attack(s, run)
    elseif run.key == "ASSASSINATE" then
        return assassinate(s, run)
    elseif run.key == "DEFECTION" then
        return defection(s, run)
    elseif run.key == "INCITE" then
        return incite(s, run)
    elseif run.key == "INCITE_WAR" then
        return incite_war(s, run)
    elseif run.key == "TREASON" then
        return treason(s, run)
    elseif run.key == "ARREST" then
        return arrest(s, run)
    elseif run.key == "MURDER" then
        return murder(s, run)
    end
    return true, "done"
end

local function report_vars(s, run, a)
    local c = run.char and Court.char(s, run.char)
    local world = run.planet or run.at
    return {agent = a and Agents.label(s, a) or "Our operative", target = run.target and label(run.target) or "the court",
            world = world and Court.planet_label(world) or "", hero = run.hero and unit_name(run.hero) or "",
            other = run.faction and label(run.faction) or "", char = c and c.name or "",
            building = run.building and unit_name(run.building) or "", capital = s.capital and Court.planet_label(s.capital) or "",
            op = string.lower(CONFIG.OPS[run.key].name)}
end

local function caught(s, run, a)
    local def = CONFIG.OPS[run.key]
    local parts = {}
    if def.internal then
        local c = Court.char(s, run.char)
        if run.key == "MURDER" then
            everyone(s, c, CV.MURDER_CAUGHT, "the throne's assassins exposed", 16)
            s.stability = M.max(0, s.stability - CV.MURDER_STABILITY)
            table.insert(parts, "the court is horrified")
        elseif c then
            Court.opinion(c, "Intelligence moved against them", CV.TREASON_CAUGHT, 16)
            table.insert(parts, c.name .. " knows")
        end
    elseif run.target then
        local value = M.round((def.attitude or 0) * (1 + CV.CAUGHT_TIER * (def.tier or 1)))
        s.attitude[run.target] = (s.attitude[run.target] or 0) + value
        if DIPLOMACY_OPINION_ADD then
            pcall(DIPLOMACY_OPINION_ADD, Intel.owner(run.target), CONFIG.FACTION, value, 20, "Imperial spies caught")
        end
        table.insert(parts, label(run.target) .. " is outraged (" .. value .. ")")
        if DIPLOMACY_REPUTATION_SPYING then
            local ok, rank, before = pcall(DIPLOMACY_REPUTATION_SPYING, CONFIG.FACTION, Intel.owner(run.target),
                def.tier or 1, label(run.target))
            if ok and rank and rank ~= before then
                table.insert(parts, "the Empire's reputation falls")
            end
        end
    end
    local vars = report_vars(s, run, a)
    if a then
        local who = Agents.label(s, a)
        Agents.kill(s, a, "is caught and executed")
        table.insert(parts, who .. " is executed")
        Agents.say(def.internal and "killed_court" or "killed", vars, true)
    end
    if not def.internal and run.target then
        local n = Intel.network(s, run.target)
        if n.tier > 0 then
            n.tier = n.tier - 1
            table.insert(parts, "the spy network falls to tier " .. n.tier)
            Agents.say("tier_down", {target = label(run.target), tier = n.tier}, true)
        end
    end
    return table.concat(parts, "; ")
end

local function resolve(s, run)
    local def = CONFIG.OPS[run.key]
    local a = Agents.get(s, run.agent)
    local who = run.target and ((run.target == CONFIG.FACTION) and "the court" or label(run.target)) or "the court"
    if not a then
        finish_run(s, run)
        return def.name .. " against " .. who .. ": the operative is lost."
    end
    local caught_now = M.chance(Intel.caught_chance(s, run.key, run))
    local done, outcome
    if caught_now and def.caught_fails then
        done, outcome = false, "exposed"
    elseif M.chance(Intel.chance(s, run.key, run)) then
        done, outcome = succeed(s, run)
        if done == nil then
            run.done = s.week + 1
            return nil
        end
    else
        done, outcome = false, "failed"
    end
    local text = def.name .. " against " .. who .. ": " .. (done and ("success, " .. outcome) or outcome) .. "."
    Agents.say(run.key .. (done and "_ok" or "_fail"), report_vars(s, run, a), not done)
    if done then
        Agents.gain_xp(s, a, def.xp or 5)
    else
        Agents.gain_xp(s, a, M.floor((def.xp or 5) / 3))
    end
    finish_run(s, run)
    if caught_now then
        text = text .. " Caught: " .. caught(s, run, a) .. "."
    end
    return text
end

function Intel.on_owner_changed(s, world)
    local kept = {}
    for _, run in ipairs(ops(s).running) do
        local def = CONFIG.OPS[run.key]
        if not run.open and not def.internal and (run.planet == world or run.at == world) then
            local a = Agents.get(s, run.agent)
            if a then
                a.mission = nil
            end
            local text = def.name .. ": " .. Court.planet_label(world) .. " changed hands; the operation is called off."
            Court.news(s, text)
            Court.alert(text, "request")
        else
            table.insert(kept, run)
        end
    end
    ops(s).running = kept
    if s.propaganda and s.propaganda[world] then
        end_propaganda(s, world)
    end
    if s.bribes and s.bribes[world] then
        s.bribes[world] = nil
        publish_bribes(s)
    end
end

function Intel.tick(s)
    Agents.tick(s)
    for _, run in ipairs(ops(s).running) do
        local a = Agents.get(s, run.agent)
        local here = a and Agents.location(s, a)
        if a and here and run.at and here ~= run.at and not run.open then
            run.left = true
        elseif a and here and run.open and run.key == "MINDER" then
            local c = Court.char(s, run.char)
            if c and c.status == "serving" then
                run.at = Intel.char_location(s, c)
            end
        end
    end
    local still = {}
    for _, run in ipairs(ops(s).running) do
        if run.left or not Agents.get(s, run.agent) then
            local a = Agents.get(s, run.agent)
            if run.key == "MINDER" then
                local c = Court.char(s, run.char)
                if c then
                    c.minder = nil
                end
            end
            if a then
                a.mission = nil
            end
            local text = CONFIG.OPS[run.key].name .. ": " .. (a and (Agents.label(s, a) .. " left the post") or "the operative is lost")
                .. "; the operation is abandoned."
            Court.news(s, text)
            Agents.say(a and "abandon" or "lost", {agent = a and Agents.label(s, a) or "the operative",
                                                   op = string.lower(CONFIG.OPS[run.key].name)}, true)
        else
            table.insert(still, run)
        end
    end
    ops(s).running = still
    Intel.watch_probes(s)
end

function Intel.week(s)
    open_by_peace(s)
    for _, run in ipairs(ops(s).running) do
        local c = run.key == "MINDER" and Court.char(s, run.char)
        if c and c.status ~= "serving" then
            run.ended = true
        end
    end
    local list = {}
    for _, run in ipairs(ops(s).running) do
        table.insert(list, run)
    end
    for _, run in ipairs(list) do
        if run.ended then
            finish_run(s, run)
        elseif not run.open and s.week >= run.done then
            local text = resolve(s, run)
            if text then
                Court.news(s, text)
                ops(s).last = text
            end
        end
    end
    for world, p in pairs(s.propaganda or {}) do
        if p.ends <= s.week then
            end_propaganda(s, world)
            Court.news(s, "Propaganda on " .. Court.planet_label(world) .. " fades.")
            Agents.say("PROPAGANDA_end", {world = Court.planet_label(world)})
        end
    end
    for world, b in pairs(s.bribes or {}) do
        if b.ends <= s.week then
            s.bribes[world] = nil
        end
    end
    publish_bribes(s)
    publish_influence(s)
end

return Intel
