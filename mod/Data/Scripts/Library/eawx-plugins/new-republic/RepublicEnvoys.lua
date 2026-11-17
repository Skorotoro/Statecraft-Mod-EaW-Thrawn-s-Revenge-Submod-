local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Envoys = {}
local E = R.ENVOYS

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.envoys = r.envoys or {opinion = {}}
    return r.envoys
end

local unlocked = false
function Envoys.unlock(d)
    if unlocked or not d.human or d.human.Get_Faction_Name() ~= "REBEL" then
        return
    end
    unlocked = true
    local t = Find_Object_Type(E.TYPE)
    if t then
        d.human.Unlock_Tech(t)
    end
end

local function speed(d)
    local Republic = require("eawx-plugins/new-republic/Republic")
    local Council = Republic.part("council")
    return (Council and Council.focus(d) == "SUPPORT") and 2 or 1
end

function Envoys.opinion(d, faction)
    local s = state(d)
    return (s and s.opinion[faction]) or 0
end

local COLOR = {r = 150, g = 200, b = 255}

local function power_capital(d, planet)
    local owner = planet.Get_Owner()
    local faction = owner.Get_Faction_Name()
    if owner == d.human or U.category(faction) == "INDEPENDENT" or faction == "NEUTRAL"
        or d:relation(string.upper(faction)) == "WAR" then
        return false
    end
    local ok_c, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    local ok, capital = false, nil
    if ok_c then
        ok, capital = pcall(Deals.capital, d, owner)
    end
    return ok and capital == planet
end

Envoys.power_capital = power_capital

function Envoys.add_opinion(d, faction, amount)
    local s = state(d)
    if s then
        s.opinion[faction] = M.min(E.OPINION_CAP, (s.opinion[faction] or 0) + amount)
    end
end

local function announce(d, key)
    local planet = FindPlanet(key)
    if not planet then
        return
    end
    local owner = planet.Get_Owner()
    local faction = owner.Get_Faction_Name()
    local world = d:planet_name(planet)
    if power_capital(d, planet) then
        d.show("Delegate: the Republic's delegate is received at the court of " .. d.display_name(faction) .. " on " .. world
            .. ". Their opinion of the Republic will warm (+" .. E.OPINION .. " a week, up to +" .. E.OPINION_CAP .. ").",
            nil, COLOR, 20)
    elseif owner == d.human and not require("eawx-plugins/new-republic/RepublicSympathy").own_counted(d) then
        d.show("Delegate: the Republic's delegate settles on " .. world .. ". Its people are the Republic's own: there is "
            .. "no one to win over here.", nil, COLOR, 20)
    else
        d.show("Delegate: the Republic's delegate settles on " .. world .. " and begins to win its people over (sympathy +"
            .. E.SYMPATHY * speed(d) .. " a week).", nil, COLOR, 20)
    end
end

local function bring_back(d, planet)
    if planet and Find_Object_Type(E.TYPE) then
        pcall(SpawnList, {E.TYPE}, planet, d.human, true, false)
        return planet
    end
    return nil
end

local sent_posted = nil
local function send_posted(s)
    if not Engine_Envoy_Posted then
        return
    end
    local names = {}
    for key, _ in pairs(s.posted) do
        table.insert(names, key)
    end
    table.sort(names)
    local list = table.concat(names, ";")
    if list ~= sent_posted then
        sent_posted = list
        Engine_Envoy_Posted(list)
    end
end

local function units_of(d)
    local out = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(E.TYPE) or {}) do
        if TestValid(unit) and unit.Get_Owner() == d.human then
            table.insert(out, unit)
        end
    end
    return out
end

local applied, limit_set = nil, nil
local function keep_limit(d, s)
    local t = unlocked and Find_Object_Type(E.TYPE)
    if not t then
        return
    end
    local posted = U.count(s.posted)
    local limit = M.max(1, E.MAX - posted)
    if Engine_Set_Build_Limit and limit ~= limit_set then
        limit_set = limit
        Engine_Set_Build_Limit(E.TYPE, limit)
    end
    local full = table.getn(units_of(d)) + posted >= E.MAX
    if full ~= applied then
        applied = full
        if full then
            d.human.Lock_Tech(t)
        else
            d.human.Unlock_Tech(t)
        end
    end
end

local function drops_and_recalls(d, s)
    local ok, placed = pcall(function()
        return Engine_Envoy_Slots and Engine_Envoy_Slots()
    end)
    if ok and type(placed) == "string" then
        for name in string.gfind(placed, "[^;]+") do
            local key = string.upper(name)
            if s.posted[key] then
                local planet = FindPlanet(key)
                bring_back(d, planet)
                d.show("Delegate: " .. (planet and d:planet_name(planet) or key) .. " already has the Republic's "
                    .. "delegate. The new one waits in orbit.", nil, COLOR, 15)
            else
                s.posted[key] = true
                pcall(announce, d, key)
            end
        end
    end
    local ok_r, recalled = pcall(function()
        return Engine_Envoy_Recalls and Engine_Envoy_Recalls()
    end)
    if ok_r and type(recalled) == "string" then
        for name in string.gfind(recalled, "[^;]+") do
            local key = string.upper(name)
            if Engine_Log then
                Engine_Log("ENVOY recall clicked at " .. key .. (s.posted[key] and "" or " (none posted)"))
            end
            if s.posted[key] then
                s.posted[key] = nil
                local planet = FindPlanet(key)
                bring_back(d, planet)
                d.show("Delegate: the Republic's delegate leaves its post on " .. (planet and d:planet_name(planet) or key)
                    .. " and waits in orbit for new orders.", nil, COLOR, 15)
            end
        end
    end
    send_posted(s)
    keep_limit(d, s)
end

local function own_world(d, planet)
    return planet.Get_Owner() == d.human and not require("eawx-plugins/new-republic/RepublicSympathy").own_counted(d)
end

local function leave_own_worlds(d, s)
    for key in pairs(s.posted) do
        local planet = FindPlanet(key)
        if planet and own_world(d, planet) then
            s.posted[key] = nil
            bring_back(d, planet)
            d.show("Delegate: " .. d:planet_name(planet) .. " is the Republic's own world. Its delegate waits in orbit "
                .. "for new orders.", nil, COLOR, 15)
        end
    end
end

local sent_worlds, next_worlds = nil, 0
function Envoys.update(d)
    local s = state(d)
    if not s or GetCurrentTime() < (Envoys.next_at or 0) then
        return
    end
    Envoys.next_at = GetCurrentTime() + 1
    s.posted = s.posted or {}
    if Engine_Envoy_Worlds and GetCurrentTime() >= next_worlds then
        next_worlds = GetCurrentTime() + 5
        local names = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local name = planet.Get_Type().Get_Name()
            if U.populated(string.upper(name)) and not own_world(d, planet) then
                table.insert(names, name)
            end
        end
        local list = table.concat(names, ";")
        if list ~= sent_worlds then
            sent_worlds = list
            Engine_Envoy_Worlds(list)
        end
        leave_own_worlds(d, s)
    end
    drops_and_recalls(d, s)
end

function Envoys.list(d)
    local s = state(d)
    local out = {}
    if not s then
        return out
    end
    s.posted = s.posted or {}
    for key, _ in pairs(s.posted) do
        local planet = FindPlanet(key)
        if planet then
            table.insert(out, {planet = planet, working = true, posted = true})
        end
    end
    for _, unit in pairs(units_of(d)) do
        local planet = unit.Get_Planet_Location()
        table.insert(out, {unit = unit, planet = planet, working = planet ~= nil and not Engine_Envoy_Slots})
    end
    return out
end

function Envoys.week(d)
    local s = state(d)
    if not s then
        return
    end
    Envoys.unlock(d)
    local list = Envoys.list(d)
    if not list[1] then
        return
    end
    local Sym = require("eawx-plugins/new-republic/RepublicSympathy")
    local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
    local n = speed(d) * ((Laws and Laws.envoy_speed(d)) or 1)
    for _, e in ipairs(list) do
        local planet = e.working and e.planet
        if planet and Laws and Laws.closed(d, U.key(planet), "envoy") then
            planet = nil
        end
        if planet then
            local faction = planet.Get_Owner().Get_Faction_Name()
            local owner = planet.Get_Owner()
            if power_capital(d, planet) then
                s.opinion[faction] = M.min(E.OPINION_CAP, (s.opinion[faction] or 0) + E.OPINION * n)
            elseif (owner ~= d.human or Sym.own_counted(d)) and Sym.value(d, U.key(planet)) then
                Sym.change(d, U.key(planet), E.SYMPATHY * n)
            end
        end
    end
end

return Envoys
