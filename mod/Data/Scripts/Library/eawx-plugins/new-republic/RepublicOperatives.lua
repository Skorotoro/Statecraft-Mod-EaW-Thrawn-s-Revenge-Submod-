require("PGSpawnUnits")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Agents = {}
local A = R.AGENTS
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 150, b = 110}

local function list(s)
    s.agents = s.agents or {}
    return s.agents
end
Agents.list = list

local LORE = {}
for _, entry in ipairs(A.LORE) do
    LORE[entry.name] = entry
end

local function weeks_text(n)
    n = M.max(0, M.round(n))
    return n .. ((n == 1) and " week" or " weeks")
end
Agents.weeks_text = weeks_text

function Agents.say(d, kind, vars, threat)
    local lines = R.INTEL_TEXT[kind]
    if not lines then
        return nil
    end
    local text = string.gsub(U.pick(lines), "{(%w+)}", function(key)
        return tostring((vars or {})[key] or "")
    end)
    d.show("Republic Intelligence: " .. text, nil, threat and WARN or COLOR, 20)
    return text
end

function Agents.news(s, text)
    s.news = s.news or {}
    table.insert(s.news, 1, text)
    while table.getn(s.news) > 12 do
        table.remove(s.news)
    end
end

function Agents.get(s, id)
    for _, a in ipairs(list(s)) do
        if a.id == id then
            return a
        end
    end
    return nil
end

function Agents.cap(d)
    local ok, Gov = pcall(require, "eawx-plugins/new-republic/RepublicGovernment")
    local bonus = (ok and Gov) and Gov.intel_bonus(d) or 0
    local found, Council = pcall(require, "eawx-plugins/new-republic/RepublicCouncil")
    local funded = (found and Council) and Council.intel_places(d) or 0
    return M.min(A.MAX, A.CAP + bonus + funded)
end

function Agents.count(s)
    return table.getn(list(s))
end

function Agents.full(d, s)
    return Agents.count(s) >= Agents.cap(d)
end

function Agents.generic_count(s)
    local n = 0
    for _, a in ipairs(list(s)) do
        if a.kind ~= "lore" then
            n = n + 1
        end
    end
    return n
end

function Agents.rank_name(a)
    return A.RANKS[a.rank or 1] or A.RANKS[1]
end

function Agents.numeral(a)
    return A.NUMERALS[a.rank or 1] or "I"
end

function Agents.has(a, key)
    for _, t in ipairs(a and a.traits or {}) do
        if t == key then
            return true
        end
    end
    return false
end

function Agents.op_trait(key)
    for k, def in pairs(R.AGENT_TRAITS) do
        if def.op == key then
            return k
        end
    end
    return nil
end

function Agents.trait_bonus(a, key)
    local E = R.AGENT_TRAIT_EFFECT
    local success, caught, cost = 0, 0, 1
    for _, t in ipairs(a and a.traits or {}) do
        local def = R.AGENT_TRAITS[t]
        if def then
            if key and (def.op == key or (def.ops and def.ops[key])) then
                success, caught = success + E.OP_SUCCESS, caught + E.OP_CAUGHT
            end
            caught = caught + (def.all_caught or 0)
            cost = cost * (def.cost or 1)
        end
    end
    return success, caught, cost
end

function Agents.trait_names(a)
    local names = {}
    for _, t in ipairs(a.traits or {}) do
        if R.AGENT_TRAITS[t] then
            table.insert(names, R.AGENT_TRAITS[t].name)
        end
    end
    return (table.getn(names) > 0) and table.concat(names, ", ") or nil
end

local function learnable(a, rank)
    local out = {}
    for _, k in ipairs(R.AGENT_TRAIT_ORDER) do
        local def = R.AGENT_TRAITS[k]
        local tier = def.op and R.OPS[def.op].tier or 1
        if not Agents.has(a, k) and tier <= rank and not (def.fast and a.kind == "lore") then
            table.insert(out, k)
        end
    end
    return out
end

local function learn(d, s, a, rank)
    if not U.chance(R.AGENT_TRAIT_CHANCE) then
        return
    end
    local pool = learnable(a, rank)
    if table.getn(pool) == 0 then
        return
    end
    local k = U.pick(pool)
    a.traits = a.traits or {}
    table.insert(a.traits, k)
    if R.AGENT_TRAITS[k].fast then
        a.fast = true
    end
    Agents.news(s, Agents.label(a) .. " gains a trait: " .. R.AGENT_TRAITS[k].name .. ".")
    Agents.say(d, "trait", {agent = Agents.label(a), trait = R.AGENT_TRAITS[k].name})
end

local function slot(a)
    return a.type and string.gsub(a.type, "^REPUBLIC_OPERATIVE_", "") or nil
end

local function rank_suffix(rank)
    return ((rank or 1) > 1) and ("_R" .. rank) or ""
end

function Agents.unit_type(a, rank)
    local n = slot(a)
    return n and ("REPUBLIC_OPERATIVE_AGENT_" .. n .. rank_suffix(rank)) or nil
end

function Agents.company_type(a, rank, fast)
    local n = slot(a)
    return n and ((fast and "REPUBLIC_OPERATIVE_FAST_" or "REPUBLIC_OPERATIVE_") .. n .. rank_suffix(rank)) or nil
end

function Agents.all_types(a)
    local out = {}
    if not slot(a) then
        return out
    end
    for r = 1, table.getn(A.RANKS) do
        table.insert(out, Agents.unit_type(a, r))
        table.insert(out, Agents.company_type(a, r, false))
        table.insert(out, Agents.company_type(a, r, true))
    end
    return out
end

local function lore_unit(d, entry)
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

function Agents.unit(d, a)
    if a.kind == "lore" then
        return lore_unit(d, LORE[a.lore])
    end
    local types = {Agents.unit_type(a, a.unit_rank)}
    for _, t in ipairs(Agents.all_types(a)) do
        table.insert(types, t)
    end
    for _, t in ipairs(types) do
        if t and Find_Object_Type(t) then
            local obj = Find_First_Object(t)
            if obj and TestValid(obj) and obj.Get_Owner() == d.human then
                return obj
            end
        end
    end
    return nil
end

function Agents.location(d, a)
    local obj = Agents.unit(d, a)
    local ok, planet = pcall(function()
        return obj and obj.Get_Planet_Location()
    end)
    return ok and planet and U.key(planet) or nil
end

function Agents.label(a)
    if a.kind == "lore" then
        return a.lore
    end
    return Agents.rank_name(a) .. " " .. (a.name or "?")
end

local function rename(a)
    if a.kind == "lore" or not a.type then
        return
    end
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_" .. a.type, Agents.label(a))
    end
    if Engine_Set_Object_Text then
        local types = {Agents.company_type(a, a.unit_rank, a.unit_fast), Agents.unit_type(a, a.unit_rank),
                       Agents.company_type(a, a.rank, a.fast), Agents.unit_type(a, a.rank)}
        for _, t in ipairs(types) do
            pcall(Engine_Set_Object_Text, t, "TEXT_" .. a.type, Agents.label(a))
        end
    end
end

function Agents.capital(d)
    local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    return ok and Deals and Deals.capital(d, d.human) or nil
end

function Agents.recruit_blocked(d, s)
    if Agents.full(d, s) then
        return "Republic Intelligence can run only " .. Agents.cap(d) .. " agents, heroes included: the Intelligence "
            .. "office and the Council's funding add more places."
    end
    local wait = (s.agent_recruited or -100) + A.RECRUIT_WEEKS - (s.week or 0)
    if wait > 0 then
        return "A new agent can be recruited in " .. weeks_text(wait) .. "."
    end
    if d.human.Get_Credits() < A.RECRUIT_CREDITS then
        return "Needs " .. A.RECRUIT_CREDITS .. " credits."
    end
    if not Agents.capital(d) then
        return "No capital to recruit at."
    end
    return nil
end

local function free_type(s)
    local used = {}
    for _, a in ipairs(list(s)) do
        if a.type then
            used[a.type] = true
        end
    end
    for _, t in ipairs(A.TYPES) do
        local free = not used[t] and Find_Object_Type(t) ~= nil
        for _, other in ipairs(free and Agents.all_types({type = t}) or {}) do
            if Find_Object_Type(other) and Find_First_Object(other) then
                free = false
            end
        end
        if free then
            return t
        end
    end
    return nil
end

local function agent_name(s)
    for _ = 1, 30 do
        local name = U.pick(R.AGENT_FIRST) .. " " .. U.pick(R.AGENT_LAST)
        local taken = false
        for _, a in ipairs(list(s)) do
            taken = taken or a.name == name
        end
        if not taken then
            return name
        end
    end
    return U.pick(R.AGENT_LAST)
end

local function new_id(s)
    s.agent_next = (s.agent_next or 0) + 1
    return s.agent_next
end

function Agents.recruit(d, s)
    local why = Agents.recruit_blocked(d, s)
    if why then
        return false, why
    end
    local t = free_type(s)
    if not t then
        return false, "No agent is free to recruit."
    end
    local capital = Agents.capital(d)
    if not pcall(SpawnList, {t}, capital, d.human, true, false) then
        return false, "The recruit never arrived."
    end
    d.human.Give_Money(-A.RECRUIT_CREDITS)
    s.agent_recruited = s.week or 0
    local a = {id = new_id(s), kind = "generic", type = t, name = agent_name(s), rank = 1, xp = 0, since = s.week or 0}
    table.insert(list(s), a)
    rename(a)
    local where = d:planet_name(capital)
    Agents.news(s, Agents.label(a) .. " joins Republic Intelligence at " .. where .. ".")
    Agents.say(d, "recruit", {agent = Agents.label(a), world = where})
    return true, Agents.label(a) .. " reports for duty at " .. where .. "."
end

local function jedi(d, name)
    for _, p in ipairs((d.republic and d.republic.jedi and d.republic.jedi.roster) or {}) do
        if p.name == name then
            return true
        end
    end
    return false
end

function Agents.eligible(d, s)
    local busy = {}
    for _, a in ipairs(list(s)) do
        if a.lore then
            busy[a.lore] = true
        end
    end
    for _, entry in ipairs(A.LORE) do
        if jedi(d, entry.name) then
            busy[entry.name] = true
        end
    end
    local out = {}
    for _, entry in ipairs(A.LORE) do
        local obj = not busy[entry.name] and lore_unit(d, entry)
        if obj then
            table.insert(out, {name = entry.name, unit = obj})
        end
    end
    return out
end

local function enlist(s, name)
    s.released = s.released or {}
    s.released[name] = nil
    local rank, traits = 1, {}
    for _, e in ipairs(A.LORE) do
        if e.name == name then
            rank = e.rank or 1
            for _, t in ipairs(e.traits or {}) do
                table.insert(traits, t)
            end
        end
    end
    table.insert(list(s), {id = new_id(s), kind = "lore", lore = name, name = name, rank = rank,
                           xp = (rank > 1) and A.XP[rank - 1] or 0, traits = traits, since = s.week or 0})
end

function Agents.assign(d, s, name)
    if Agents.full(d, s) then
        return false, "Every agent's place is taken (" .. Agents.cap(d) .. "): release one first."
    end
    for _, e in ipairs(Agents.eligible(d, s)) do
        if e.name == name then
            enlist(s, name)
            Agents.news(s, name .. " now serves Republic Intelligence.")
            return true, name .. " joins the agents."
        end
    end
    return false, name .. " cannot serve as an agent now."
end

local function drop(s, a)
    local kept = {}
    for _, other in ipairs(list(s)) do
        if other ~= a then
            table.insert(kept, other)
        end
    end
    s.agents = kept
end

local COMBAT = "SpaceHero | Capital | Frigate | Corvette | Fighter | Bomber | Infantry | Vehicle | InfantryHero | VehicleHero"

function Agents.safe_to_remove(obj)
    local ok, planet = pcall(function()
        return obj.Get_Planet_Location()
    end)
    if not ok or not planet then
        return false
    end
    local owner = obj.Get_Owner()
    for _, faction in pairs(ModContentLoader.get("GameConstants").ALL_FACTIONS_NOT_NEUTRAL or {}) do
        local player = Find_Player(faction)
        if player and player ~= owner then
            for _, other in pairs(Find_All_Objects_Of_Type(player, COMBAT) or {}) do
                if TestValid(other) then
                    local ok2, where = pcall(function()
                        return other.Get_Planet_Location()
                    end)
                    if ok2 and where == planet then
                        return false
                    end
                end
            end
        end
    end
    return true
end

function Agents.swap_safe(d, obj)
    if Agents.safe_to_remove(obj) then
        return true
    end
    local ok, planet = pcall(function()
        return obj.Get_Planet_Location()
    end)
    if not ok or not planet then
        return false
    end
    for _, other in pairs(Find_All_Objects_Of_Type(d.human, COMBAT) or {}) do
        if TestValid(other) and other ~= obj then
            local ok2, where = pcall(function()
                return other.Get_Planet_Location()
            end)
            if ok2 and where == planet then
                return false
            end
        end
    end
    return true
end

function Agents.queue_removal(s, obj)
    if not obj then
        return
    end
    if Agents.safe_to_remove(obj) then
        obj.Despawn()
        return
    end
    s.removals = s.removals or {}
    table.insert(s.removals, obj.Get_Type().Get_Name())
end

local function process_removals(s)
    local still = {}
    for _, type_name in ipairs(s.removals or {}) do
        local obj = Find_Object_Type(type_name) and Find_First_Object(type_name)
        if obj and TestValid(obj) then
            if Agents.safe_to_remove(obj) then
                obj.Despawn()
            else
                table.insert(still, type_name)
            end
        end
    end
    s.removals = still
end

function Agents.fire(d, s, a)
    a.mission = nil
    drop(s, a)
    if a.kind ~= "lore" then
        Agents.queue_removal(s, Agents.unit(d, a))
        return true, Agents.label(a) .. " retires from service."
    end
    s.released = s.released or {}
    s.released[a.lore] = true
    return true, a.lore .. " returns to other duties."
end

function Agents.leave_for_jedi(d, name)
    local ok, Intel = pcall(require, "eawx-plugins/new-republic/RepublicIntel")
    local s = ok and Intel and Intel.state(d)
    if not s then
        return
    end
    for _, a in ipairs(list(s)) do
        if a.lore == name then
            local run = a.mission and Intel.run_of(d, a.id)
            if run then
                Intel.recall(d, run)
            end
            a.mission = nil
            drop(s, a)
            Agents.news(s, name .. " leaves Republic Intelligence to serve the Jedi Order"
                .. (run and "; their operation is called off." or "."))
            return
        end
    end
end

function Agents.kill(d, s, a)
    drop(s, a)
    Agents.queue_removal(s, Agents.unit(d, a))
end

function Agents.gain_xp(d, s, a, xp)
    a.xp = (a.xp or 0) + xp
    local rank = 1
    for k, need in ipairs(A.XP) do
        if a.xp >= need then
            rank = k + 1
        end
    end
    if rank > (a.rank or 1) then
        local from, before = a.rank or 1, Agents.label(a)
        a.rank = rank
        rename(a)
        Agents.news(s, before .. " is now " .. Agents.label(a) .. ".")
        Agents.say(d, "promoted", {agent = before, rank = Agents.rank_name(a)})
        for r = from + 1, rank do
            learn(d, s, a, r)
        end
    end
end

function Agents.tick(d, s)
    for _, a in ipairs(list(s)) do
        if Agents.unit(d, a) then
            a.missing = nil
        else
            a.missing = a.missing or (s.week or 0)
        end
        if a.missing ~= nil and (s.week or 0) > a.missing + 1 then
            a.lost = true
        end
    end
    for _, a in ipairs(list(s)) do
        local want = Agents.company_type(a, a.rank, a.fast)
        local stale = (a.unit_rank or 1) ~= (a.rank or 1) or (a.unit_fast or false) ~= (a.fast or false)
        if stale and a.kind ~= "lore" and not a.lost and want and Find_Object_Type(want) then
            local obj = Agents.unit(d, a)
            local ok, planet = pcall(function()
                return obj and obj.Get_Planet_Location()
            end)
            if ok and planet and Agents.swap_safe(d, obj) then
                obj.Despawn()
                if pcall(SpawnList, {want}, planet, d.human, true, false) then
                    a.unit_rank, a.unit_fast = a.rank or 1, a.fast or false
                    a.missing = nil
                end
            end
        end
    end
    local kept = {}
    for _, a in ipairs(list(s)) do
        if a.lost then
            if a.kind ~= "lore" or a.mission then
                Agents.news(s, Agents.label(a) .. " is lost to Republic Intelligence.")
                Agents.say(d, "lost", {agent = Agents.label(a)}, true)
            end
        else
            table.insert(kept, a)
            rename(a)
        end
    end
    s.agents = kept
    process_removals(s)
end

return Agents
