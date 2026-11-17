require("PGSpawnUnits")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local Agents = require("eawx-plugins/new-republic/RepublicOperatives")

local Intel = {}
local SPY = R.SPY
local CV = R.COVERT
local FACTION = "REBEL"
local NEUTRAL = {REBEL = true, NEUTRAL = true, HOSTILE = true}
local SHARED = {INDEPENDENT_FORCES = true, WARLORDS = true}
local WARN = {r = 255, g = 150, b = 110}

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    local s = r.intel
    if not s or s.net then
        s = {spy = {}, agents = {}, ops = {running = {}, reports = {}}, week = 0, debt = 0, abstain = {}, news = {}}
        r.intel = s
    end
    return s
end
Intel.state = state

local function week_now()
    return M.floor(GetCurrentTime() / U.weeks(1))
end

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

function Intel.planet_label(d, world)
    local planet = world and FindPlanet(world)
    return planet and d:planet_name(planet) or (world or "?")
end

function Intel.label(d, target)
    local world = Intel.world_target(target)
    if world then
        return Intel.planet_label(d, world)
    end
    return d.display_name(target)
end

local function is_vassal(name)
    return string.find(name, "^DIPLOMACY_VASSALS") ~= nil
end

function Intel.targets(d)
    local counts, out = {}, {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = string.upper(planet.Get_Owner().Get_Faction_Name())
        local name = U.key(planet)
        if SHARED[owner] then
            if not string.find(name, "REGIMEPICKER$") then
                table.insert(out, {faction = "@" .. name, worlds = 1, owner = owner})
            end
        elseif not NEUTRAL[owner] and not is_vassal(owner) then
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

function Intel.groups(d)
    local hit = Intel.groups_cache
    if hit and GetCurrentTime() >= hit.time and GetCurrentTime() - hit.time < 5 then
        return hit.value
    end
    local out = Intel.groups_now(d)
    Intel.groups_cache = {time = GetCurrentTime(), value = out}
    return out
end

function Intel.groups_now(d)
    local targets = Intel.targets(d)
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
        local group, worlds = {}, {}
        for _, name in ipairs(cat[2]) do
            local t = by_name[string.upper(name)]
            if t and not placed[t.faction] then
                placed[t.faction] = true
                table.insert(group, t)
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
        table.sort(worlds, function(a, b)
            return Intel.label(d, a.faction) < Intel.label(d, b.faction)
        end)
        for _, w in ipairs(worlds) do
            table.insert(group, w)
        end
        if table.getn(group) > 0 then
            table.insert(out, {cat[1], group})
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
    return U.category(Intel.owner(faction)) == "WARLORD"
end

function Intel.relation(d, target)
    return d:relation(Intel.owner(target)) or "WAR"
end

function Intel.capital(target)
    local world = Intel.world_target(target)
    if world then
        return FindPlanet(world)
    end
    if not DIPLOMACY_CAPITAL then
        return nil
    end
    local ok, planet = pcall(DIPLOMACY_CAPITAL, target)
    return ok and planet or nil
end

function Intel.worlds_of(target)
    local world = Intel.world_target(target)
    if world then
        return {world}
    end
    local player = Find_Player(target)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            table.insert(out, U.key(planet))
        end
    end
    table.sort(out)
    return out
end

function Intel.capital_name(target)
    local world = Intel.world_target(target)
    if world then
        return world
    end
    local planet = Intel.capital(target)
    if planet then
        return U.key(planet)
    end
    return Intel.worlds_of(target)[1]
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

local function max_tier(target)
    return Intel.world_target(target) and SPY.WORLD_MAX or SPY.MAX
end
Intel.max_tier = max_tier

function Intel.network(d, target)
    local s = state(d)
    s.spy = s.spy or {}
    local n = s.spy[target]
    if not n then
        n = {tier = SPY.PEACE[Intel.relation(d, target)] and 1 or 0, progress = 0}
        s.spy[target] = n
    end
    return n
end

function Intel.tier(d, owner, world)
    if not state(d) then
        return 0
    end
    local t = Intel.network(d, owner).tier
    if world and SHARED[string.upper(owner or "")] then
        t = M.max(t, Intel.network(d, "@" .. world).tier)
    end
    return t
end

function Intel.tier_name(tier)
    return SPY.NAMES[tier] or "?"
end

function Intel.raise(d, target, how, world)
    local s = state(d)
    local n = Intel.network(d, target)
    if n.tier >= max_tier(target) then
        return
    end
    n.tier, n.progress = n.tier + 1, 0
    Agents.news(s, "Spy network in " .. Intel.label(d, target) .. " rises to tier " .. n.tier .. " ("
        .. Intel.tier_name(n.tier) .. ")" .. (how and (": " .. how) or "") .. ".")
    Agents.say(d, world and "spy" or "tier_up", {target = Intel.label(d, target), tier = n.tier,
        tiername = Intel.tier_name(n.tier), world = world and Intel.planet_label(d, world)})
end

local function spied(d, world)
    local planet = FindPlanet(world)
    local owner = planet and string.upper(planet.Get_Owner().Get_Faction_Name())
    if owner and SHARED[owner] then
        owner = "@" .. world
    end
    if owner and not NEUTRAL[owner] and not is_vassal(owner) and Intel.network(d, owner).tier == 0
            and Intel.capital_name(owner) == world then
        Intel.raise(d, owner, "a Bothan Spy reached " .. Intel.planet_label(d, world), world)
    end
end

local spies = {}
local each = string.gfind or string.gmatch
local SPY_TYPES = {"REPUBLIC_BOTHAN_SPY_BOTHAWUI", "BOTHAN_SPY_COMPANY", "BOTHAN_SPY"}

function Intel.watch_spies(d)
    if Engine_Spied then
        for entry in each(Engine_Spied() or "", "[^;]+") do
            local _, _, world, unit = string.find(entry, "^([^|]*)|(.*)$")
            if world and world ~= "" and unit and string.find(string.upper(unit), "BOTHAN_SPY") then
                spied(d, string.upper(world))
            end
        end
        return
    end
    local now, seen = GetCurrentTime(), {}
    for _, type_name in ipairs(SPY_TYPES) do
        if Find_Object_Type(type_name) then
            for _, obj in pairs(Find_All_Objects_Of_Type(type_name) or {}) do
                if TestValid(obj) and obj.Get_Owner() == d.human then
                    local ok, planet = pcall(function()
                        return obj.Get_Planet_Location()
                    end)
                    table.insert(seen, {obj = obj, planet = ok and planet and U.key(planet) or nil, time = now})
                end
            end
        end
    end
    for _, old in ipairs(spies) do
        if old.planet and now - old.time < 15 and not TestValid(old.obj) then
            spied(d, old.planet)
        end
    end
    spies = seen
end

function Intel.bothan_builds(d)
    local ok, capital = pcall(function()
        return require("eawx-plugins/diplomacy/DiplomacyDeals").capital(d, d.human)
    end)
    local on_bothawui = ok and capital and U.key(capital) == "BOTHAWUI" or false
    local t = Find_Object_Type("REPUBLIC_BOTHAN_SPY_BOTHAWUI")
    if t then
        if on_bothawui then
            d.human.Lock_Tech(t)
        else
            d.human.Unlock_Tech(t)
        end
    end
end

local function open_by_peace(d)
    for _, t in ipairs(Intel.targets(d)) do
        if Intel.network(d, t.faction).tier == 0 and SPY.PEACE[Intel.relation(d, t.faction)] then
            Intel.raise(d, t.faction, "the Republic's envoys open doors")
        end
    end
end

local function unit_name(type_name)
    return (DIPLOMACY_UNIT_NAME and DIPLOMACY_UNIT_NAME(type_name)) or type_name
end
Intel.unit_name = unit_name

local function is_dummy(type_name)
    return string.find(type_name, "DUMMY") or string.find(type_name, "^INFLUENCE_") or unit_name(type_name) == type_name
end

function Intel.buildings(target, world)
    local player = Find_Player(Intel.owner(target))
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

local function leaders_of(d, faction)
    local out = {}
    local ok, LEADERS = pcall(require, "eawx-plugins/diplomacy/DiplomacyLeaders")
    if not ok or not LEADERS then
        return out
    end
    local lists = {LEADERS[faction] or {}}
    if d and LEADERS.WARLORDS then
        table.insert(lists, LEADERS.WARLORDS[d.display_name(faction)] or {})
    end
    for _, list in ipairs(lists) do
        for _, entry in ipairs(list) do
            out[string.upper(entry.type)] = true
        end
    end
    return out
end

function Intel.heroes(target, d)
    local only = Intel.world_target(target)
    local player = Find_Player(Intel.owner(target))
    local out, seen = {}, {}
    local leaders = d and leaders_of(d, Intel.owner(target) or "") or {}
    for t in pairs(leaders) do
        seen[t] = true
    end
    local ok, all = pcall(Find_All_Objects_Of_Type, player, "SpaceHero | InfantryHero | VehicleHero | NonCombatHero")
    for _, unit in pairs(ok and all or {}) do
        if TestValid(unit) then
            local t = string.upper(unit.Get_Type().Get_Name())
            local ok2, planet = pcall(function()
                return unit.Get_Planet_Location()
            end)
            local here = ok2 and planet and U.key(planet) or nil
            if not seen[t] and not string.find(t, "PROBE") and not string.find(t, "DUMMY") and (not only or here == only) then
                seen[t] = true
                table.insert(out, {type = t, name = unit_name(t), world = here})
            end
        end
    end
    table.sort(out, function(a, b)
        return a.name < b.name
    end)
    return out
end

local function hero_unit(target, type_name)
    local player = Find_Player(Intel.owner(target))
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

local function sym()
    local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
    return ok and Sym or nil
end

local function home(d)
    local capital = Agents.capital(d)
    return capital and U.key(capital) or nil
end

function Intel.location(d, op)
    local def = R.OPS[op.key]
    if def.at == "capital" then
        return Intel.capital_name(op.target)
    elseif def.at == "planet" then
        return op.planet
    elseif def.at == "hero" then
        local obj = op.hero and hero_unit(op.target, op.hero)
        local ok, planet = pcall(function()
            return obj and obj.Get_Planet_Location()
        end)
        return ok and planet and U.key(planet) or nil
    elseif def.at == "seat" then
        return op.seat
    elseif def.at == "home" then
        return home(d)
    end
    return nil
end

function Intel.spynet_blocked(d)
    local Republic = require("eawx-plugins/new-republic/Republic")
    local Members = require("eawx-plugins/new-republic/RepublicMembers")
    local sum, n = 0, 0
    for name, seat in pairs((Republic.senate and Republic.senate.seats(d)) or {}) do
        if Members.species(name) == "Bothan" then
            sum, n = sum + seat.opinion, n + 1
        end
    end
    if n > 0 and sum / n < R.SPYNET.REFUSES then
        return "The Bothan SpyNet refuses: the Bothan senators are angry with the government."
    end
    return nil
end

local function spynet(op)
    return op and op.agent == "SPYNET"
end
Intel.is_spynet = spynet

local function office_bonus(d)
    local ok, Gov = pcall(require, "eawx-plugins/new-republic/RepublicGovernment")
    if ok and Gov then
        local _, bonus = Gov.intel_bonus(d)
        return bonus or 0
    end
    return 0
end

local function sure(d, op)
    if op.sure then
        return true
    end
    local s = state(d)
    return op.target ~= nil and op.done == nil and s ~= nil and s.free_op ~= nil and s.free_op[op.target] == true
end

function Intel.chance(d, key, op)
    local def = R.OPS[key]
    op = op or {}
    if sure(d, op) then
        return 100
    end
    local chance = def.chance + office_bonus(d)
    local ok_f, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
    if ok_f then
        chance = chance + Favour.intel(d)
    end
    local s = state(d)
    local a = op.agent and not spynet(op) and Agents.get(s, op.agent)
    if a then
        chance = chance + CV.RANK * ((a.rank or 1) - 1) + (Agents.trait_bonus(a, key))
    elseif spynet(op) then
        chance = chance + R.SPYNET.CHANCE
    end
    if op.planet and op.target and Intel.capital_name(op.target) == op.planet and not Intel.world_target(op.target) then
        chance = chance + CV.CAPITAL
    end
    if key == "TURN" and op.target and not Intel.is_warlord(op.target) then
        chance = chance + (def.major or 0)
    end
    return U.clamp(M.round(chance), 5, 95)
end

function Intel.caught_chance(d, key, op)
    local def = R.OPS[key]
    if (def.caught or 0) == 0 or sure(d, op or {}) then
        return 0
    end
    local s = state(d)
    local a = op and op.agent and not spynet(op) and Agents.get(s, op.agent)
    local caught = def.caught - (a and 3 * ((a.rank or 1) - 1) or 0)
    if a then
        local _, extra = Agents.trait_bonus(a, key)
        caught = caught + extra
    end
    local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
    if Laws then
        local _, _, factor = Laws.intel(d, key, def.internal)
        caught = caught * factor
    end
    return U.clamp(M.round(caught), 0, 90)
end

local function rebellion(d)
    local Republic = require("eawx-plugins/new-republic/Republic")
    local Council = Republic.part("council")
    return Council ~= nil and Council.focus(d) == "REBELLION", Council
end

function Intel.needed_tier(d, key)
    local def = R.OPS[key]
    local tier = (def and def.tier) or 1
    local on, Council = rebellion(d)
    if on then
        tier = M.min(tier, Council.CONFIG.REBELLION_TIER)
    end
    return tier
end

function Intel.free_op(d, target)
    local s = state(d)
    s.free_op = s.free_op or {}
    s.free_op[target] = true
end

function Intel.cost(d, key, op)
    local s = state(d)
    if op and op.target and s and s.free_op and s.free_op[op.target] then
        return 0
    end
    local on, Council = rebellion(d)
    local cost = Intel.base_cost(d, key, op)
    local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
    if Laws and R.OPS[key] then
        cost = M.round(cost * Laws.intel(d, key, R.OPS[key].internal))
    end
    return on and M.round(cost * Council.CONFIG.REBELLION_COST) or cost
end

function Intel.base_cost(d, key, op)
    local def = R.OPS[key]
    local s = state(d)
    if spynet(op) then
        local mult = R.SPYNET.COST
        local ok, Gov = pcall(require, "eawx-plugins/new-republic/RepublicGovernment")
        if ok and Gov and Gov.agenda(d) == "SPYNET" then
            mult = mult * 0.75
        end
        return M.round(def.cost * mult)
    end
    local a = op and op.agent and Agents.get(s, op.agent)
    if a then
        local _, _, mult = Agents.trait_bonus(a, key)
        return M.round(def.cost * mult)
    end
    return def.cost
end

function Intel.blocked(d, key, target)
    local def = R.OPS[key]
    if not def then
        return "Unknown operation."
    end
    if not target then
        return "Select a target first."
    end
    if not def.internal then
        local tier = Intel.network(d, target).tier
        if tier == 0 then
            return "No spy network in " .. Intel.label(d, target) .. " yet: a Bothan Spy at their capital, or a "
                .. "ceasefire, opens one."
        elseif tier < Intel.needed_tier(d, key) then
            return "Needs a tier " .. Intel.needed_tier(d, key) .. " spy network (now tier " .. tier .. "): gather "
                .. "intelligence to build it."
        end
        local kind = U.category(Intel.owner(target) or "")
        if def.imperial and kind ~= "IMPERIAL" and kind ~= "WARLORD" then
            return "Only against the Empire and its warlords: the galaxy expects atrocities of them."
        end
        if def.war and not Intel.at_war(FACTION, target) then
            return "The Republic must be at war with " .. Intel.label(d, target) .. " for its people to rise in arms."
        end
        local s = state(d)
        local last = def.rest and s and s.exposed and s.exposed[Intel.owner(target) or ""]
        if last and week_now() < last + def.rest then
            return "Their crimes were exposed lately: again in " .. Agents.weeks_text(last + def.rest - week_now()) .. "."
        end
    end
    local least = M.round(def.cost * R.SPYNET.COST * ((rebellion(d)) and 0.2 or 1))
    if d.human.Get_Credits() < least then
        return "Needs " .. least .. " credits."
    end
    return nil
end

function Intel.pick_blocked(d, key, kind, value, op)
    local def = R.OPS[key]
    local s = state(d)
    if kind == "faction" then
        if value == op.target then
            return "Choose another power."
        end
    elseif kind == "planet" then
        local Sym = sym()
        local label = Intel.planet_label(d, value)
        if def.sympathy then
            local v = Sym and Sym.value(d, value)
            if not v or v < def.sympathy then
                return label .. ": sympathy " .. (v and M.round(v) or "unknown") .. ", needs " .. def.sympathy .. "."
            end
        end
        if def.cell and not (Sym and d.republic.sym and d.republic.sym.cells[value]) then
            return label .. " has no resistance cell: plant one first."
        end
        if def.rises and Sym then
            local planet = FindPlanet(value)
            local owner = planet and string.upper(planet.Get_Owner().Get_Faction_Name())
            local side = Sym.preferred(d, value)
            if owner == side then
                return label .. "'s rebels look to its owner: plant a resistance cell first."
            end
            if side ~= FACTION and not (d.republic.sym and d.republic.sym.cells[value]) then
                return label .. "'s rebels don't look to the Republic: only a resistance cell of ours can incite them."
            end
        end
        if key == "CELL" and d.republic.sym and d.republic.sym.cells[value] then
            return label .. " has a cell already."
        end
        if key == "BROADCAST" and d.republic.sym and (d.republic.sym.broadcast[value] or 0) > GetCurrentTime() then
            return "The Republic already broadcasts on " .. label .. "."
        end
    elseif kind == "seat" then
        local Parties = require("eawx-plugins/new-republic/Republic").part("parties")
        local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
        local label = Intel.planet_label(d, value)
        local closed = Laws and Laws.closed(d, value)
        local loyal = Laws and key == "REAPPOINT" and Laws.no_reappoint(d, value)
        if closed then
            return label .. ": " .. closed
        elseif key == "RIG" and Laws and Laws.no_rig(d, value) then
            return label .. " holds open elections by law (Universal Franchise): they cannot be rigged."
        elseif loyal then
            return label .. ": " .. loyal
        elseif key == "INVESTIGATE" and (s.abstain[value] or -1) >= s.week then
            return "Intelligence already has something on " .. label .. "'s senator."
        elseif key == "BUY" and (s.turned and s.turned[value] or -1) >= s.week then
            return label .. "'s senator is already ours."
        elseif (key == "FUND" or key == "SMEAR" or key == "RIG" or key == "REAPPOINT")
                and not (Parties and Parties.of(d, value)) then
            return label .. " has no parties to work on yet."
        elseif key == "RIG" and not Parties.elected(d, value) then
            return label .. "'s ruler appoints its senator: there is no election to rig."
        elseif key == "REAPPOINT" and Parties.elected(d, value) then
            return label .. " elects its senator: there is no ruler to persuade."
        end
    elseif kind == "party" then
        local Parties = require("eawx-plugins/new-republic/Republic").part("parties")
        local w = Parties and op.seat and Parties.of(d, op.seat)
        if not w or not w.list[value] then
            return "Choose a party."
        end
        if key == "REAPPOINT" and w.ruling == value then
            return w.list[value].name .. " holds the seat already."
        end
    elseif kind == "bloc" then
        if s.leak and s.leak.bloc == value and s.leak.ends > s.week then
            return "The " .. value .. " bloc's dealings are already in the newsfeeds."
        end
    end
    return nil
end

function Intel.agent_blocked(d, a, op)
    local def = op and R.OPS[op.key]
    if a == "SPYNET" and def and def.internal and def.at == "seat" then
        return "Work on a member world's politics needs an agent of ours on that world."
    end
    if a == "SPYNET" then
        if op and op.key == "GATHER" then
            for _, run in ipairs(state(d).ops.running) do
                if run.agent == "SPYNET" and run.key == "GATHER" and run.target == op.target then
                    return "The SpyNet already gathers intelligence on " .. Intel.label(d, op.target) .. "."
                end
            end
        end
        return Intel.spynet_blocked(d)
    end
    if a.mission then
        return Agents.label(a) .. " is busy with another operation."
    end
    local at = Intel.location(d, op)
    if not at then
        return "The target cannot be found."
    end
    local here = Agents.location(d, a)
    if here ~= at then
        return Agents.label(a) .. " must be at " .. Intel.planet_label(d, at) .. " (now "
            .. (here and ("at " .. Intel.planet_label(d, here)) or "in hyperspace") .. ")."
    end
    return nil
end

function Intel.launch(d, op)
    local s = state(d)
    local key = op.key
    local def = R.OPS[key]
    local why = Intel.blocked(d, key, op.target)
    if why then
        return false, why
    end
    for _, kind in ipairs(def.pick or {}) do
        local value = op[kind]
        if not value then
            return false, "Choose a " .. kind .. " first."
        end
        why = Intel.pick_blocked(d, key, kind, value, op)
        if why then
            return false, why
        end
    end
    local a = nil
    if spynet(op) then
        why = Intel.agent_blocked(d, "SPYNET", op)
        if why then
            return false, why
        end
    else
        a = op.agent and Agents.get(s, op.agent)
        if not a then
            return false, "Choose an agent."
        end
        why = Intel.agent_blocked(d, a, op)
        if why then
            return false, why
        end
    end
    local cost = Intel.cost(d, key, op)
    if d.human.Get_Credits() < cost then
        return false, "Needs " .. cost .. " credits."
    end
    d.human.Give_Money(-cost)
    local paid_for = s.free_op and op.target and s.free_op[op.target]
    if s.free_op and op.target then
        s.free_op[op.target] = nil
    end
    local at = Intel.location(d, op)
    local planet = at and FindPlanet(at)
    local run = {key = key, target = op.target, planet = op.planet, building = op.building, hero = op.hero,
                 faction = op.faction, seat = op.seat, bloc = op.bloc, party = op.party,
                 agent = spynet(op) and "SPYNET" or a.id, at = at,
                 owner = planet and planet.Get_Owner().Get_Faction_Name() or nil, started = s.week,
                 done = s.week + def.weeks + (function()
                     local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
                     local _, extra = 1, 0
                     if Laws then
                         _, extra = Laws.intel(d, key, def.internal)
                     end
                     return extra
                 end)(), sure = paid_for or nil}
    if def.rest and Intel.owner(op.target) then
        s.exposed = s.exposed or {}
        s.exposed[Intel.owner(op.target)] = s.week
    end
    if a then
        a.mission = key
    else
        s.debt = (s.debt or 0) + 1
        Agents.say(d, "spynet", {})
    end
    table.insert(s.ops.running, run)
    local who = a and Agents.label(a) or "the Bothan SpyNet"
    return true, def.name .. " under way: " .. who .. ", " .. Agents.weeks_text(def.weeks) .. ", "
        .. Intel.chance(d, key, run) .. "% to succeed."
end

local function finish_run(s, run)
    local kept = {}
    for _, r in ipairs(s.ops.running) do
        if r ~= run then
            table.insert(kept, r)
        end
    end
    s.ops.running = kept
    local a = run.agent ~= "SPYNET" and Agents.get(s, run.agent)
    if a then
        a.mission = nil
    end
end

function Intel.recall(d, run)
    local s = state(d)
    finish_run(s, run)
    local a = run.agent ~= "SPYNET" and Agents.get(s, run.agent)
    return true, (a and Agents.label(a) or "The SpyNet") .. " is recalled."
end

function Intel.run_of(d, agent_id)
    for _, r in ipairs(state(d).ops.running) do
        if r.agent == agent_id then
            return r
        end
    end
    return nil
end

local function report(d, s, target)
    local player = Find_Player(Intel.owner(target))
    local heroes = {}
    for _, h in ipairs(Intel.heroes(target)) do
        if table.getn(heroes) < 4 then
            table.insert(heroes, h.name)
        end
    end
    s.ops.reports = s.ops.reports or {}
    s.ops.reports[target] = {week = s.week, worlds = table.getn(Intel.worlds_of(target)),
                             credits = player and M.round(player.Get_Credits()) or 0, heroes = heroes}
end

local function battle_near(obj)
    return not Agents.safe_to_remove(obj)
end

local function turn(d, run)
    local obj = hero_unit(run.target, run.hero)
    local capital = Agents.capital(d)
    if not obj or not capital then
        return false, unit_name(run.hero) .. " could not be reached"
    end
    if battle_near(obj) then
        return nil, "a battle looms where they stand: the agent waits"
    end
    obj.Despawn()
    if not pcall(SpawnList, {run.hero}, capital, d.human, true, false) then
        return false, unit_name(run.hero) .. " never arrived"
    end
    return true, unit_name(run.hero) .. " defects and arrives at " .. d:planet_name(capital)
end

function Intel.defect(d, faction, hero_type)
    local ok, done = pcall(turn, d, {target = faction, hero = hero_type})
    return ok and done == true
end

local function senate()
    local Republic = require("eawx-plugins/new-republic/Republic")
    return Republic.senate, Republic
end

local function succeed(d, s, run)
    local target = run.target
    local label = target and Intel.label(d, target)
    local owner = target and Intel.owner(target)
    local Sym = sym()
    local key = run.key
    if key == "GATHER" then
        report(d, s, target)
        local n = Intel.network(d, target)
        if n.tier >= max_tier(target) then
            return true, "the files on " .. label .. " are ready"
        end
        if U.category(owner or "") == "INDEPENDENT" then
            Intel.raise(d, target, "new agents in place")
            return true, "the files on " .. label .. " are ready"
        end
        n.progress = n.progress + SPY.GATHER
        if n.progress >= SPY.PROGRESS then
            Intel.raise(d, target, "new agents in place")
            return true, "the files on " .. label .. " are ready"
        end
        return true, "the files on " .. label .. " are ready (intel progress " .. n.progress .. "/" .. SPY.PROGRESS .. ")"
    elseif key == "SURVEY" and d.republic.sym then
        d.republic.sym.survey[owner] = GetCurrentTime() + U.weeks(R.SYMPATHY_SURVEY_WEEKS)
        return true, "the true mood of " .. label .. "'s worlds is known"
    elseif key == "BROADCAST" and d.republic.sym then
        d.republic.sym.broadcast[run.planet] = GetCurrentTime() + U.weeks(R.SYMPATHY_BROADCAST_WEEKS)
        return true, "the Republic's voice reaches " .. Intel.planet_label(d, run.planet)
    elseif key == "AID" and Sym then
        Sym.change(d, run.planet, 15)
        return true, "the dissidents of " .. Intel.planet_label(d, run.planet) .. " are armed and fed"
    elseif key == "SABOTAGE" then
        local player = Find_Player(owner)
        local planet = FindPlanet(run.planet)
        for _, obj in pairs(player and Find_All_Objects_Of_Type(player) or {}) do
            if TestValid(obj) and obj.Get_Planet_Location() == planet
                    and string.upper(obj.Get_Type().Get_Name()) == run.building then
                obj.Despawn()
                return true, "their " .. unit_name(run.building) .. " on " .. Intel.planet_label(d, run.planet) .. " is rubble"
            end
        end
        return false, "the " .. unit_name(run.building) .. " was gone before our agent struck"
    elseif key == "CELL" and d.republic.sym then
        d.republic.sym.cells[run.planet] = true
        local ok, Rebellion = pcall(require, "eawx-plugins/diplomacy/DiplomacyRebellion")
        if ok and Rebellion and Rebellion.sway then
            pcall(Rebellion.sway, d, run.planet, FACTION)
        end
        return true, "a resistance cell is hidden on " .. Intel.planet_label(d, run.planet) .. ": its rebels look to the Republic"
    elseif key == "EXPOSE" then
        for _, faction in pairs(ModContentLoader.get("GameConstants").ALL_FACTIONS_NOT_NEUTRAL or {}) do
            if faction ~= owner and DIPLOMACY_OPINION_ADD then
                pcall(DIPLOMACY_OPINION_ADD, faction, owner, -15, 20, "the Republic exposed their atrocities")
            end
        end
        local def = R.OPS.EXPOSE
        local player = Find_Player(owner)
        s.influence = s.influence or {}
        for _, w in ipairs(player and U.worlds_of(player) or {}) do
            if Sym then
                Sym.change(d, w.key, def.sympathy)
            end
            s.influence[w.key] = {value = def.influence, owner = owner, ends = s.week + def.lasts}
        end
        Intel.publish_influence(s)
        return true, "the galaxy learns what " .. label .. " has done"
    elseif key == "DISCREDIT" then
        if DIPLOMACY_OPINION_ADD then
            pcall(DIPLOMACY_OPINION_ADD, run.faction, owner, R.OPS.DISCREDIT.opinion, 20, "rumours spread by Republic agents")
        end
        return true, Intel.label(d, run.faction) .. " now trusts " .. label .. " even less"
    elseif key == "TURN" then
        return turn(d, run)
    elseif key == "DEFECTION" and Sym then
        if Sym.join(d, run.planet, "is handed over by its governor") then
            return true, Intel.planet_label(d, run.planet) .. " is the Republic's"
        end
        return false, "the world had changed hands"
    elseif key == "UPRISING" and Sym then
        local led = d.republic.sym and d.republic.sym.cells[run.planet] ~= nil
        if Sym.rise(d, run.planet, "rises against " .. label, led) then
            return true, "the people of " .. Intel.planet_label(d, run.planet) .. " rise"
                .. (led and ": the Republic's cell leads them" or "")
        end
        return false, "the world could not rise"
    elseif key == "FUND" or key == "SMEAR" or key == "RIG" or key == "REAPPOINT" then
        local Parties = require("eawx-plugins/new-republic/Republic").part("parties")
        local party = Parties and Parties.party(d, run.seat, run.party)
        local world = Intel.planet_label(d, run.seat)
        if not party then
            return false, "the world's politics had changed"
        end
        local def = R.OPS[key]
        if key == "FUND" then
            local n = Parties.adjust(d, run.seat, run.party, def.clout)
            return true, Parties.the(party.name) .. " on " .. world .. " gains clout (+" .. M.round(n) .. ")"
        elseif key == "SMEAR" then
            local n = Parties.adjust(d, run.seat, run.party, -def.clout)
            return true, Parties.the(party.name) .. " on " .. world .. " loses clout (" .. M.round(n) .. ")"
        elseif key == "RIG" then
            if Parties.rig(d, run.seat, run.party) then
                return true, "the next election on " .. world .. " goes to " .. Parties.the(party.name)
            end
            return false, world .. " no longer holds elections"
        else
            if Parties.reappoint(d, run.seat, run.party, def.favour) then
                return true, "the ruler of " .. world .. " names a new senator"
            end
            return true, "the ruler of " .. world .. " thinks it over, and keeps the senator"
        end
    elseif key == "BUY" then
        s.turned = s.turned or {}
        s.turned[run.seat] = s.week + R.OPS.BUY.lasts
        return true, "the senator of " .. Intel.planet_label(d, run.seat) .. " votes with the government for "
            .. R.OPS.BUY.lasts .. " weeks"
    elseif key == "INVESTIGATE" then
        s.abstain[run.seat] = s.week + 3
        return true, "the senator of " .. Intel.planet_label(d, run.seat) .. " will abstain for 3 weeks"
    elseif key == "WATCH" then
        s.watch_until = GetCurrentTime() + U.weeks(4)
        return true, "every secession clock stops for 4 weeks"
    elseif key == "LEAK" then
        s.leak = {bloc = run.bloc, ends = s.week + 6}
        return true, "for 6 weeks no senator outside the " .. run.bloc .. " bloc follows its lead"
    end
    return true, "done"
end

local function party_name(d, run)
    local Parties = run.party and require("eawx-plugins/new-republic/Republic").part("parties")
    local party = Parties and run.seat and Parties.party(d, run.seat, run.party)
    return party and Parties.the(party.name) or ""
end

local function report_vars(d, run, a)
    local world = run.planet or run.at
    local capital = Agents.capital(d)
    return {agent = a and Agents.label(a) or "The SpyNet", target = run.target and Intel.label(d, run.target) or "the Senate",
            world = world and Intel.planet_label(d, world) or "", hero = run.hero and unit_name(run.hero) or "",
            other = run.faction and Intel.label(d, run.faction) or "", seat = run.seat and Intel.planet_label(d, run.seat) or "",
            bloc = run.bloc or "", building = run.building and unit_name(run.building) or "",
            party = party_name(d, run),
            capital = capital and d:planet_name(capital) or "", op = string.lower(R.OPS[run.key].name)}
end

local function caught(d, s, run, a)
    local def = R.OPS[run.key]
    local Senate, Republic = senate()
    local parts = {}
    if def.internal then
        local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
        local factor = Laws and Laws.scandal(d, run.seat) or 1
        d.senate.stability = M.max(0, d.senate.stability - M.round(R.SCANDAL_COHESION * factor))
        table.insert(parts, "the Senate learns the government spied on its own members (cohesion " .. d.senate.stability .. "%)")
        if def.exposed and run.seat and Senate then
            Senate.sway(d, run.seat, -def.exposed, "the government's agents were caught meddling in its politics")
            table.insert(parts, Intel.planet_label(d, run.seat) .. " is furious (-" .. def.exposed .. ")")
        end
    else
        local owner = Intel.owner(run.target)
        local value = M.round((def.attitude or 0) * (1 + CV.CAUGHT_TIER * (def.tier or 1)))
        if DIPLOMACY_OPINION_ADD and value ~= 0 then
            pcall(DIPLOMACY_OPINION_ADD, owner, FACTION, value, 20, "Republic spies caught")
        end
        table.insert(parts, Intel.label(d, run.target) .. " is outraged (" .. value .. ")")
        if DIPLOMACY_REPUTATION_SPYING then
            local ok, rank, before = pcall(DIPLOMACY_REPUTATION_SPYING, FACTION, owner, def.tier or 1, Intel.label(d, run.target))
            if ok and rank and rank ~= before then
                table.insert(parts, "the Republic's reputation falls")
            end
        end
        Republic.change_mandate(d, -R.SCANDAL_MANDATE)
        local Sym = sym()
        if Sym and run.planet then
            Sym.change(d, run.planet, -R.SCANDAL_SYMPATHY)
        end
        local Members = require("eawx-plugins/new-republic/RepublicMembers")
        for name, _ in pairs((Senate and Senate.seats(d)) or {}) do
            if Members.has(d, name, "Pacifist") or Members.has(d, name, "Commerce") then
                Senate.sway(d, name, -5, "the Intelligence scandal")
            end
        end
        table.insert(parts, "a scandal at home (mandate " .. Republic.mandate(d) .. ")")
    end
    local vars = report_vars(d, run, a)
    if a then
        local who = Agents.label(a)
        Agents.kill(d, s, a)
        table.insert(parts, who .. " is killed")
        Agents.say(d, def.internal and "killed_home" or "killed", vars, true)
    end
    if not def.internal and run.target then
        local n = Intel.network(d, run.target)
        if n.tier > 0 then
            n.tier = n.tier - 1
            table.insert(parts, "the spy network falls to tier " .. n.tier)
            Agents.say(d, "tier_down", {target = Intel.label(d, run.target), tier = n.tier}, true)
        end
    end
    return table.concat(parts, "; ")
end

local function resolve(d, s, run)
    local def = R.OPS[run.key]
    local a = run.agent ~= "SPYNET" and Agents.get(s, run.agent) or nil
    local who = run.target and ((run.target == FACTION) and "the Senate" or Intel.label(d, run.target)) or "the Senate"
    if run.agent ~= "SPYNET" and not a then
        finish_run(s, run)
        return def.name .. " against " .. who .. ": the agent is lost."
    end
    local caught_now = U.chance(Intel.caught_chance(d, run.key, run))
    local done, outcome
    if U.chance(Intel.chance(d, run.key, run)) then
        done, outcome = succeed(d, s, run)
        if done == nil then
            run.done = s.week + 1
            return nil
        end
    else
        done, outcome = false, "failed"
    end
    local text = def.name .. " against " .. who .. ": " .. (done and ("success, " .. outcome) or outcome) .. "."
    Agents.say(d, run.key .. (done and "_ok" or "_fail"), report_vars(d, run, a), not done)
    if a then
        Agents.gain_xp(d, s, a, done and (def.xp or 5) or M.floor((def.xp or 5) / 3))
    end
    finish_run(s, run)
    if caught_now then
        text = text .. " Exposed: " .. caught(d, s, run, a) .. "."
    end
    return text
end

function Intel.tick(d)
    local s = state(d)
    if not s then
        return
    end
    s.week = week_now()
    if GetCurrentTime() >= (s.next_heroes or 0) then
        s.next_heroes = GetCurrentTime() + 20
        Intel.bothan_builds(d)
    end
    Agents.tick(d, s)
    for _, run in ipairs(s.ops.running) do
        local a = run.agent ~= "SPYNET" and Agents.get(s, run.agent)
        local here = a and Agents.location(d, a)
        if a and here and run.at and here ~= run.at then
            run.left = true
        end
        local planet = run.at and FindPlanet(run.at)
        if run.owner and planet and planet.Get_Owner().Get_Faction_Name() ~= run.owner then
            run.moved = true
        end
    end
    local still = {}
    for _, run in ipairs(s.ops.running) do
        local lost = run.agent ~= "SPYNET" and not Agents.get(s, run.agent)
        if run.left or run.moved or lost then
            local a = run.agent ~= "SPYNET" and Agents.get(s, run.agent)
            if a then
                a.mission = nil
            end
            local name = R.OPS[run.key].name
            if run.moved then
                Agents.news(s, name .. ": " .. Intel.planet_label(d, run.at) .. " changed hands; the operation is called off.")
                d.show("Republic Intelligence: " .. name .. " is called off: " .. Intel.planet_label(d, run.at)
                    .. " changed hands.", nil, WARN, 15)
            else
                Agents.news(s, name .. ": " .. (a and (Agents.label(a) .. " left the post") or "the agent is lost")
                    .. "; the operation is abandoned.")
                Agents.say(d, a and "abandon" or "lost", {agent = a and Agents.label(a) or "the agent",
                                                          op = string.lower(name)}, true)
            end
        else
            table.insert(still, run)
        end
    end
    s.ops.running = still
    Intel.watch_spies(d)
    local Sym = sym()
    if Sym and Sym.patch_display then
        pcall(Sym.patch_display, d)
    end
end

function Intel.week(d)
    local s = state(d)
    if not s then
        return
    end
    s.week = week_now()
    open_by_peace(d)
    Intel.bothan_builds(d)
    if string.upper(d.human.Get_Faction_Name()) == "REBEL" then
        for target, n in pairs(s.spy or {}) do
            if n.tier >= 1 and n.tier < max_tier(target) then
                n.progress = n.progress + SPY.SPYNET_WEEK
                if n.progress >= SPY.PROGRESS then
                    Intel.raise(d, target, "the Bothan SpyNet")
                end
            end
        end
    end
    local due = {}
    for _, run in ipairs(s.ops.running) do
        if s.week >= run.done then
            table.insert(due, run)
        end
    end
    for _, run in ipairs(due) do
        local text = resolve(d, s, run)
        if text then
            Agents.news(s, text)
            s.ops.last = text
        end
    end
    if (s.debt or 0) >= R.SPYNET.DEBT_DEMAND then
        local Members = require("eawx-plugins/new-republic/RepublicMembers")
        if Members.bothan_demand(d) then
            s.debt = 0
        end
    end
    if s.leak and s.leak.ends <= s.week then
        s.leak = nil
    end
    Intel.watch_influence()
    Intel.publish_influence(s)
end

function Intel.publish_influence(s)
    local map = {}
    for world, e in pairs(s.influence or {}) do
        if e.ends > s.week then
            map[world] = e
        else
            s.influence[world] = nil
        end
    end
    REPUBLIC_INTEL_INFLUENCE = map
end

function Intel.watch_influence()
    if type(InfluenceService) ~= "table" or InfluenceService.__republic_watched
            or type(InfluenceService.influence_hero_effects) ~= "function" then
        return
    end
    InfluenceService.__republic_watched = true
    local hero_effects = InfluenceService.influence_hero_effects
    InfluenceService.influence_hero_effects = function(service, owner, planet_object)
        local value = hero_effects(service, owner, planet_object)
        local mods = REPUBLIC_INTEL_INFLUENCE
        if mods and next(mods) and type(value) == "number" then
            local ok, name, holder = pcall(function()
                return string.upper(planet_object.Get_Type().Get_Name()),
                    string.upper(planet_object.Get_Owner().Get_Faction_Name())
            end)
            local e = ok and mods[name]
            if e and e.owner == holder then
                value = value + e.value
            end
        end
        return value
    end
end

local leak_cache = {}
local function bloc_opposes(d, s, motion)
    local now = GetCurrentTime()
    if leak_cache.motion == motion and leak_cache.time == now then
        return leak_cache.opposes
    end
    local Senate = senate()
    local sum = 0
    for _, seat in pairs((Senate and Senate.seats(d)) or {}) do
        if seat.bloc == s.leak.bloc then
            sum = sum + (Senate.vote_of(d, seat, motion) or 0)
        end
    end
    leak_cache = {motion = motion, time = now, opposes = sum < 0}
    return sum < 0
end

function Intel.adjust_vote(d, seat, vote, motion)
    local s = d.republic and d.republic.intel
    if not s or s.net then
        return vote
    end
    if s.turned and (s.turned[seat.name] or -1) >= (s.week or 0) then
        return 1
    end
    if s.abstain and (s.abstain[seat.name] or -1) >= (s.week or 0) then
        return 0
    end
    if s.leak and s.leak.ends > (s.week or 0) and motion and seat.bloc ~= s.leak.bloc and vote < 0
            and seat.opinion > -40 and bloc_opposes(d, s, motion) then
        return 0
    end
    return vote
end

function Intel.watching(d)
    local s = d.republic and d.republic.intel
    return s ~= nil and s.watch_until ~= nil and GetCurrentTime() < s.watch_until
end

return Intel
