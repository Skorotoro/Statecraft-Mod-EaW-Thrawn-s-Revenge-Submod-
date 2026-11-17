require("PGSpawnUnits")
local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")

local Agents = {}
local A = CONFIG.AGENTS

local function list(s)
    s.agents = s.agents or {}
    return s.agents
end
Agents.list = list

function Agents.say(kind, vars, threat)
    local lines = CONFIG.INTEL_TEXT[kind]
    if not lines then
        return nil
    end
    local text = string.gsub(M.pick(lines), "{(%w+)}", function(key)
        return tostring((vars or {})[key] or "")
    end)
    Court.alert(text, threat and "threat" or "request")
    return text
end

function Agents.get(s, id)
    for _, a in ipairs(list(s)) do
        if a.id == id then
            return a
        end
    end
    return nil
end

function Agents.cap(s)
    local director = Court.char(s, s.offices.INTEL)
    if not (director and director.status == "serving") then
        return 1
    end
    local tens = M.clamp(M.round(director.skill / 10), 1, 10)
    return M.clamp(M.floor((tens + 1) / 2), 1, A.MAX)
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
    for k, def in pairs(CONFIG.AGENT_TRAITS) do
        if def.op == key then
            return k
        end
    end
    return nil
end

function Agents.trait_names(a)
    local names = {}
    for _, t in ipairs(a.traits or {}) do
        table.insert(names, CONFIG.AGENT_TRAITS[t].name)
    end
    return (table.getn(names) > 0) and table.concat(names, ", ") or nil
end

local function learnable(a, rank)
    local out = {}
    for _, k in ipairs(CONFIG.AGENT_TRAIT_ORDER) do
        local def = CONFIG.AGENT_TRAITS[k]
        local tier = def.op and CONFIG.OPS[def.op].tier or 1
        if not Agents.has(a, k) and tier <= rank and not (def.fast and a.kind == "lore") then
            table.insert(out, k)
        end
    end
    return out
end

local function learn(s, a, rank)
    if not M.chance(CONFIG.AGENT_TRAIT_CHANCE) then
        return
    end
    local pool = learnable(a, rank)
    if table.getn(pool) == 0 then
        return
    end
    local k = pool[M.random(1, table.getn(pool))]
    a.traits = a.traits or {}
    table.insert(a.traits, k)
    if CONFIG.AGENT_TRAITS[k].fast then
        a.fast = true
    end
    Court.news(s, Agents.label(s, a) .. " gains a trait: " .. CONFIG.AGENT_TRAITS[k].name .. ".")
    Agents.say("trait", {agent = Agents.label(s, a), trait = CONFIG.AGENT_TRAITS[k].name})
end

function Agents.unit(s, a)
    local empire = Court.player()
    if a.kind == "lore" then
        local c = Court.char(s, a.char)
        if not (c and c.lore) then
            return nil
        end
        local obj, owner = Court.unit_on_map(c.lore)
        return (owner == CONFIG.FACTION) and obj or nil
    end
    local types = {Agents.unit_type(a, a.unit_rank)}
    for _, t in ipairs(Agents.all_types(a)) do
        table.insert(types, t)
    end
    for _, t in ipairs(types) do
        if Find_Object_Type(t) then
            local obj = Find_First_Object(t)
            if obj and TestValid(obj) and obj.Get_Owner() == empire then
                return obj
            end
        end
    end
    return nil
end

local function slot(a)
    local n = a.type and string.gsub(a.type, "^COURT_OPERATIVE_", "")
    return n
end

local function rank_suffix(rank)
    return ((rank or 1) > 1) and ("_R" .. rank) or ""
end

function Agents.unit_type(a, rank)
    local n = slot(a)
    return n and ("COURT_OPERATIVE_AGENT_" .. n .. rank_suffix(rank)) or nil
end

function Agents.company_type(a, rank, fast)
    local n = slot(a)
    return n and ((fast and "COURT_OPERATIVE_FAST_" or "COURT_OPERATIVE_") .. n .. rank_suffix(rank)) or nil
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

function Agents.location(s, a)
    local obj = Agents.unit(s, a)
    local ok, planet = pcall(function()
        return obj and obj.Get_Planet_Location()
    end)
    return ok and planet and Court.name_of(planet) or nil
end

local function bare_name(a)
    local name = string.gsub(a.name or "", "^Agent ", "")
    return name
end

function Agents.label(s, a)
    if a.kind == "lore" then
        local c = Court.char(s, a.char)
        return c and c.name or a.name
    end
    return Agents.rank_name(a) .. " " .. bare_name(a)
end

local function rename(a)
    if a.kind == "lore" or not a.type then
        return
    end
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_" .. a.type, Agents.label(nil, a))
    end
    if Engine_Set_Object_Text then
        local types = {Agents.company_type(a, a.unit_rank, a.unit_fast), Agents.unit_type(a, a.unit_rank),
                       Agents.company_type(a, a.rank, a.fast), Agents.unit_type(a, a.rank)}
        for _, t in ipairs(types) do
            pcall(Engine_Set_Object_Text, t, "TEXT_" .. a.type, Agents.label(nil, a))
        end
    end
end

function Agents.recruit_blocked(s)
    if table.getn(list(s)) >= Agents.cap(s) then
        return "Imperial Intelligence can run only " .. Agents.cap(s) .. " operatives: a more skilled Director runs more."
    end
    local wait = (s.agent_recruited or -100) + A.RECRUIT_WEEKS - s.week
    if wait > 0 then
        return "A new operative can be recruited in " .. M.weeks(wait) .. "."
    end
    if s.authority < A.RECRUIT_AUTHORITY then
        return "Needs " .. A.RECRUIT_AUTHORITY .. " authority."
    end
    if Court.player().Get_Credits() < A.RECRUIT_CREDITS then
        return "Needs " .. A.RECRUIT_CREDITS .. " credits."
    end
    if not s.capital or not FindPlanet(s.capital) then
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
        local name = M.pick(CONFIG.FIRST_NAMES) .. " " .. M.pick(CONFIG.SURNAMES)
        local taken = false
        for _, a in ipairs(list(s)) do
            taken = taken or bare_name(a) == name
        end
        if not taken then
            return name
        end
    end
    return M.pick(CONFIG.SURNAMES)
end

function Agents.new_id(s)
    s.agent_next = (s.agent_next or 0) + 1
    return s.agent_next
end

function Agents.recruit(s)
    local why = Agents.recruit_blocked(s)
    if why then
        return false, why
    end
    local t = free_type(s)
    if not t then
        return false, "No operative is free to recruit."
    end
    local ok = pcall(SpawnList, {t}, FindPlanet(s.capital), Court.player(), true, false)
    if not ok then
        return false, "The recruit never arrived."
    end
    s.authority = s.authority - A.RECRUIT_AUTHORITY
    Court.player().Give_Money(-A.RECRUIT_CREDITS)
    s.agent_recruited = s.week
    local a = {id = Agents.new_id(s), kind = "generic", type = t, name = agent_name(s), rank = 1, xp = 0, since = s.week}
    table.insert(list(s), a)
    rename(a)
    local label = Agents.label(s, a)
    Court.news(s, label .. " joins Imperial Intelligence at " .. Court.planet_label(s.capital) .. ".")
    Agents.say("recruit", {agent = label, world = Court.planet_label(s.capital)})
    return true, label .. " reports for duty at " .. Court.planet_label(s.capital) .. "."
end

function Agents.eligible(s)
    local names = {}
    for _, n in ipairs(A.LORE) do
        names[n] = true
    end
    local busy = {}
    for _, a in ipairs(list(s)) do
        if a.char then
            busy[a.char] = true
        end
    end
    local out = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" and names[c.name] and not A.NEVER[c.name] and not c.leads and not busy[c.id]
                and s.offices.INTEL ~= c.id and c.kind == "unit" then
            table.insert(out, c)
        end
    end
    return out
end

function Agents.assign(s, c)
    if table.getn(list(s)) >= Agents.cap(s) then
        return false, "Imperial Intelligence can run only " .. Agents.cap(s) .. " operatives."
    end
    local ok = false
    for _, e in ipairs(Agents.eligible(s)) do
        ok = ok or e == c
    end
    if not ok then
        return false, c.name .. " cannot serve as an operative now."
    end
    table.insert(list(s), {id = Agents.new_id(s), kind = "lore", char = c.id, name = c.name, rank = 1, xp = 0, since = s.week})
    Court.news(s, c.name .. " now serves Imperial Intelligence.")
    return true, c.name .. " joins the operatives."
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

function Agents.safe_to_remove(obj)
    local ok, planet = pcall(function()
        return obj.Get_Planet_Location()
    end)
    if not ok or not planet then
        return false
    end
    local owner = string.upper(obj.Get_Owner().Get_Faction_Name())
    local combat = "SpaceHero | Capital | Frigate | Corvette | Fighter | Bomber | Infantry | Vehicle | InfantryHero | VehicleHero"
    for faction, _ in pairs(Court.present_factions()) do
        local player = faction ~= owner and Find_Player(faction)
        for _, other in pairs(player and Find_All_Objects_Of_Type(player, combat) or {}) do
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
    return true
end

function Agents.swap_safe(obj)
    if Agents.safe_to_remove(obj) then
        return true
    end
    local ok, planet = pcall(function()
        return obj.Get_Planet_Location()
    end)
    if not ok or not planet then
        return false
    end
    local combat = "SpaceHero | Capital | Frigate | Corvette | Fighter | Bomber | Infantry | Vehicle | InfantryHero | VehicleHero"
    for _, other in pairs(Find_All_Objects_Of_Type(Court.player(), combat) or {}) do
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

function Agents.fire(s, a)
    if a.mission then
        return false, Agents.label(s, a) .. " is on an operation: recall or finish it first."
    end
    drop(s, a)
    if a.kind ~= "lore" then
        Agents.queue_removal(s, Agents.unit(s, a))
        return true, Agents.label(s, a) .. " is retired from service."
    end
    return true, Agents.label(s, a) .. " returns to other duties."
end

function Agents.kill(s, a, why)
    drop(s, a)
    local obj = Agents.unit(s, a)
    if a.kind == "lore" then
        local c = Court.char(s, a.char)
        if c and c.status == "serving" then
            Court.remove(s, c, "dead", why)
        end
    end
    Agents.queue_removal(s, obj)
end

function Agents.gain_xp(s, a, xp)
    a.xp = (a.xp or 0) + xp
    local rank = 1
    for k, need in ipairs(A.XP) do
        if a.xp >= need then
            rank = k + 1
        end
    end
    if rank > (a.rank or 1) then
        local from, before = a.rank or 1, Agents.label(s, a)
        a.rank = rank
        rename(a)
        Court.news(s, before .. " is now " .. Agents.label(s, a) .. ".")
        Agents.say("promoted", {agent = before, rank = Agents.rank_name(a)})
        for r = from + 1, rank do
            learn(s, a, r)
        end
    end
end

function Agents.tick(s)
    for _, a in ipairs(list(s)) do
        local gone
        if a.kind == "lore" then
            local c = Court.char(s, a.char)
            gone = not c or c.status ~= "serving"
        else
            if Agents.unit(s, a) then
                a.missing = nil
            else
                a.missing = a.missing or s.week
            end
            gone = a.missing ~= nil and s.week > a.missing + 1
        end
        if gone then
            a.lost = true
        end
    end
    for _, a in ipairs(list(s)) do
        if a.fast_pending then
            a.fast, a.fast_pending = true, nil
        end
        local want = Agents.company_type(a, a.rank, a.fast)
        local stale = (a.unit_rank or 1) ~= (a.rank or 1) or (a.unit_fast or false) ~= (a.fast or false)
        if stale and a.kind ~= "lore" and not a.lost and want and Find_Object_Type(want) then
            local obj = Agents.unit(s, a)
            local ok, planet = pcall(function()
                return obj and obj.Get_Planet_Location()
            end)
            if ok and planet and Agents.swap_safe(obj) then
                obj.Despawn()
                if pcall(SpawnList, {want}, planet, Court.player(), true, false) then
                    a.unit_rank, a.unit_fast = a.rank or 1, a.fast or false
                    a.missing = nil
                end
            end
        end
    end
    local kept = {}
    for _, a in ipairs(list(s)) do
        if a.lost then
            Court.news(s, Agents.label(s, a) .. " is lost to Imperial Intelligence.")
            Agents.say("lost", {agent = Agents.label(s, a)}, true)
        else
            table.insert(kept, a)
            rename(a)
        end
    end
    s.agents = kept
    process_removals(s)
end

return Agents
