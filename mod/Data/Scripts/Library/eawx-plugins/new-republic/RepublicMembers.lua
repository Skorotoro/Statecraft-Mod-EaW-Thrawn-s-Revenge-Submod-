local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Members = {}
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.members = r.members or {interests = {}, demands = {}, pledged = {}, far = {}, drift = {}}
    return r.members
end

function Members.interests(d, key)
    local s = state(d)
    if s and s.interests[key] then
        return s.interests[key]
    end
    local list = R.WORLD_INTERESTS[key]
    if not list then
        local h = U.hash(key)
        local species = R.SPECIES[key]
        local pool = {"Security", "Commerce", "Liberation", "Pacifist", "Autonomy", "Industry", "Reparations"}
        local first = pool[M.floor(h / 7) - M.floor(M.floor(h / 7) / table.getn(pool)) * table.getn(pool) + 1]
        if species and species ~= "Human" then
            list = {"Species rights", first}
        else
            local second = pool[h - M.floor(h / table.getn(pool)) * table.getn(pool) + 1]
            list = (second == first) and {first} or {first, second}
        end
    end
    if s then
        s.interests[key] = list
    end
    return list
end

function Members.has(d, key, interest)
    for _, i in ipairs(Members.interests(d, key)) do
        if i == interest then
            return true
        end
    end
    return false
end

function Members.species(key)
    return R.SPECIES[key] or "Human"
end

function Members.opinion(d, key)
    local s = state(d)
    return -((s and s.drift[key]) or 0)
end

local function at_war_with(d, category)
    local out = {}
    for _, faction in pairs(ModContentLoader.get("GameConstants").ALL_FACTIONS_NOT_NEUTRAL or {}) do
        local other = Find_Player(faction)
        if other and other ~= d.human and U.count(U.worlds_of(other)) > 0 then
            local war = d.human.Is_Enemy(other)
            if (category == "war" and war) or (category == "peace_imperial" and not war and U.category(faction) == "IMPERIAL") then
                table.insert(out, faction)
            end
        end
    end
    return out
end

local function liberation_target(d)
    local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
    if not ok or not Sym then
        return nil
    end
    local pool = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local kind = U.category(planet.Get_Owner().Get_Faction_Name())
        if (kind == "IMPERIAL" or kind == "WARLORD") and Sym.liberation(d, U.key(planet)) then
            table.insert(pool, planet)
        end
    end
    return U.pick(pool)
end

local function liberate(d, deadline)
    local planet = liberation_target(d)
    if not planet then
        return nil
    end
    return {kind = "LIBERATE", world = U.key(planet), deadline = deadline,
            text = "free " .. d:planet_name(planet) .. " from " .. d.display_name(planet.Get_Owner().Get_Faction_Name())}
end

local function new_demand(d, key, planet)
    local name = d:planet_name(planet)
    local kinds = {}
    for _, i in ipairs(Members.interests(d, key)) do
        table.insert(kinds, i)
    end
    local interest = U.pick(kinds)
    local deadline = GetCurrentTime() + U.weeks(R.DEMAND_WEEKS)
    if interest == "Security" then
        return {kind = "GARRISON", text = "station warships at " .. name, deadline = deadline}
    elseif interest == "Industry" then
        return {kind = "SHIPS", text = "commission ships or troops at " .. name, deadline = deadline}
    elseif interest == "Commerce" then
        local f = U.pick(at_war_with(d, "war"))
        if f then
            return {kind = "PEACE", target = f, text = "make peace with " .. d.display_name(f), deadline = deadline}
        end
    elseif interest == "Liberation" then
        local demand = liberate(d, deadline)
        if demand then
            return demand
        end
    elseif interest == "Pacifist" then
        return {kind = "NO_WAR", text = "declare no new war for " .. R.DEMAND_WEEKS .. " weeks", deadline = deadline}
    elseif interest == "Autonomy" then
        local ok, S = pcall(require, "eawx-plugins/new-republic/RepublicSectors")
        local sector = U.sector_of(key)
        if ok and S and S.level(d, sector) > 1 then
            return {kind = "TAX", sector = sector, base = S.level(d, sector),
                    text = "lower taxes in the " .. sector, deadline = deadline}
        end
    elseif interest == "Species rights" then
        local waiting = d.senate and U.count(d.senate.unrepresented) or 0
        if waiting > 0 then
            return {kind = "SEAT", base = waiting, text = "give an unrepresented world its Senator's Office",
                    deadline = deadline}
        end
    elseif interest == "Reparations" then
        local f = U.pick(at_war_with(d, "peace_imperial"))
        if f then
            return {kind = "WAR", target = f, text = "declare war on " .. d.display_name(f), deadline = deadline}
        end
        local demand = liberate(d, deadline)
        if demand then
            return demand
        end
    end
    return {kind = "GARRISON", text = "station warships at " .. name, deadline = deadline}
end

function Members.bothan_demand(d)
    local s = state(d)
    if not s then
        return
    end
    for key, _ in pairs((d.republic and d.republic.seated) or {}) do
        if Members.species(key) == "Bothan" and not s.demands[key] then
            local planet = FindPlanet(key)
            if planet then
                s.demands[key] = {kind = "COLLECT", cost = 1500, deadline = GetCurrentTime() + U.weeks(R.DEMAND_WEEKS),
                                  text = "repay the SpyNet's favours (1500 credits)"}
                d.show("Republic: the Bothan delegation of " .. d:planet_name(planet) .. " calls in the SpyNet's favours: "
                    .. "1500 credits.", nil, WARN, 20)
                return true
            end
        end
    end
    return false
end

local function done(d, key, demand, planet)
    if demand.kind == "GARRISON" then
        return U.strength_at(d.human, planet) > 0
    elseif demand.kind == "PEACE" then
        return d:relation(demand.target) ~= "WAR"
    elseif demand.kind == "WAR" then
        return d:relation(demand.target) == "WAR"
    elseif demand.kind == "TAX" then
        local ok, S = pcall(require, "eawx-plugins/new-republic/RepublicSectors")
        return ok and S and S.level(d, demand.sector) < demand.base
    elseif demand.kind == "SEAT" then
        return d.senate and U.count(d.senate.unrepresented) < demand.base
    elseif demand.kind == "LIBERATE" and demand.world then
        local planet = FindPlanet(demand.world)
        return planet ~= nil and planet.Get_Owner() == d.human
    elseif demand.kind == "NO_WAR" then
        return not demand.broken and GetCurrentTime() >= demand.deadline
    end
    return demand.met == true
end

local function settle(d, key, demand, met)
    local s = state(d)
    s.demands[key] = nil
    local planet = FindPlanet(key)
    local name = planet and d:planet_name(planet) or key
    local Republic = require("eawx-plugins/new-republic/Republic")
    if met then
        if Republic.senate then
            Republic.senate.sway(d, key, R.DEMAND_DONE_OPINION, "you granted its demand to " .. demand.text)
        end
        d.republic.capital = M.min(Republic.CONFIG.CAPITAL_MAX, d.republic.capital + R.DEMAND_DONE_CAPITAL)
        d.show("Republic: " .. name .. " is satisfied (" .. demand.text .. "). Opinion +" .. R.DEMAND_DONE_OPINION
            .. ", political capital +" .. R.DEMAND_DONE_CAPITAL .. ".", nil, COLOR, 15)
    else
        if Republic.senate then
            Republic.senate.sway(d, key, -R.DEMAND_FAILED_OPINION, "you ignored its demand to " .. demand.text)
        end
        d.show("Republic: " .. name .. " resents that its demand was ignored (" .. demand.text .. ").", nil, WARN, 15)
    end
end

function Members.demands(d)
    local s = state(d)
    local out = {}
    for key, demand in pairs((s and s.demands) or {}) do
        local planet = FindPlanet(key)
        if planet then
            table.insert(out, {key = key, name = d:planet_name(planet), text = demand.text, kind = demand.kind,
                               cost = demand.cost, left = M.floor((demand.deadline - GetCurrentTime()) / U.weeks(1))})
        end
    end
    table.sort(out, function(a, b) return a.left < b.left end)
    return out
end

function Members.pay(d, key)
    local s = state(d)
    local demand = s and s.demands[key]
    if not demand or demand.kind ~= "COLLECT" then
        return false, "Nothing to pay."
    end
    if d.human.Get_Credits() < demand.cost then
        return false, "The treasury cannot pay " .. demand.cost .. " credits."
    end
    d.human.Give_Money(-demand.cost)
    demand.met = true
    settle(d, key, demand, true)
    if d.republic.intel then
        d.republic.intel.debt = 0
    end
    return true, "The Bothans are paid."
end

function Members.on_production(d, key)
    local ok, Desires = pcall(require, "eawx-plugins/new-republic/RepublicDesires")
    if ok and Desires then
        Desires.on_production(d, key)
    end
    local s = state(d)
    local demand = s and s.demands[key]
    if demand and demand.kind == "SHIPS" then
        demand.met = true
    end
end

function Members.on_conquest(d, old_owner)
    local s = state(d)
    if not s then
        return
    end
    local kind = U.category(old_owner)
    if kind == "IMPERIAL" or kind == "WARLORD" then
        for _, demand in pairs(s.demands) do
            if demand.kind == "LIBERATE" and not demand.world then
                demand.met = true
            end
        end
    end
end

function Members.on_war(d)
    local s = state(d)
    for _, demand in pairs((s and s.demands) or {}) do
        if demand.kind == "NO_WAR" then
            demand.broken = true
        end
    end
end

local function capital_planet(d)
    local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    if ok and Deals then
        local okc, cap = pcall(Deals.capital, d, d.human)
        if okc then
            return cap
        end
    end
    return nil
end

function Members.week(d, seated)
    local s = state(d)
    if not s then
        return
    end
    local Republic = require("eawx-plugins/new-republic/Republic")
    for key, demand in pairs(s.demands) do
        local planet = FindPlanet(key)
        if not planet or not seated[key] then
            s.demands[key] = nil
        elseif done(d, key, demand, planet) then
            settle(d, key, demand, true)
        elseif GetCurrentTime() >= demand.deadline or demand.broken then
            settle(d, key, demand, false)
        end
    end
    local seats = U.count(seated)
    local limit = 1 + M.floor(seats / R.DEMAND_PER_SEATS)
    local ok, Gov = pcall(require, "eawx-plugins/new-republic/RepublicGovernment")
    if ok and Gov and Gov.agenda(d) == "SPYNET" then
        limit = limit + 1
    end
    if not Republic.part("desires") and U.count(s.demands) < limit and U.chance(R.DEMAND_CHANCE) then
        local free = {}
        for key, _ in pairs(seated) do
            if not s.demands[key] then
                table.insert(free, key)
            end
        end
        local key = U.pick(free)
        if key then
            local demand = new_demand(d, key, seated[key])
            s.demands[key] = demand
            d.show("Republic: the senator of " .. d:planet_name(seated[key]) .. " asks the government to " .. demand.text
                .. " within " .. R.DEMAND_WEEKS .. " weeks.", nil, COLOR, 20)
        end
    end
    local seats_info = Republic.senate and Republic.senate.seats(d) or {}
    for key, seat in pairs(seats_info) do
        local Laws = Republic.part("laws")
        local factor = Laws and Laws.pledges(d, key) or 1
        if factor > 0 and (Members.has(d, key, "Security") or Members.has(d, key, "Industry")) and seat.opinion >= R.PLEDGE_OPINION
                and GetCurrentTime() - (s.pledged[key] or -U.weeks(R.PLEDGE_WEEKS)) >= U.weeks(R.PLEDGE_WEEKS / factor)
                and U.chance(R.PLEDGE_CHANCE * factor) then
            s.pledged[key] = GetCurrentTime()
            local okg, Grants = pcall(require, "eawx-plugins/diplomacy/DiplomacyGrants")
            if okg and Grants then
                d:grant_units(Grants.for_world, key, seat.planet, d.human, "The people of " .. d:planet_name(seat.planet))
            end
        end
    end
    if U.count(d.republic.declared) > 0 then
        for key, _ in pairs(seats_info) do
            if Members.has(d, key, "Pacifist") then
                Republic.senate.sway(d, key, -1, "the war drags on")
            end
        end
    end
    local cap = capital_planet(d)
    for key, planet in pairs(seated) do
        local far = s.far[key]
        if cap and (not far or GetCurrentTime() - far.time > U.weeks(10)) then
            local path = Find_Path(d.human, cap, planet)
            far = {jumps = path and (table.getn(path) - 1) or 0, time = GetCurrentTime()}
            s.far[key] = far
        end
        local reached = (Republic.part("focus") and Republic.part("focus").no_drift(d))
            or (Republic.part("laws") and Republic.part("laws").no_drift(d, key))
        if far and far.jumps >= R.FAR_JUMPS and U.strength_at(d.human, planet) <= 0 and not reached then
            s.drift[key] = M.min(R.FAR_OPINION_CAP, (s.drift[key] or 0) + 1)
        elseif s.drift[key] then
            s.drift[key] = s.drift[key] > 1 and (s.drift[key] - 1) or nil
        end
    end
end

return Members
