local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local K = require("eawx-plugins/diplomacy/DiplomacyKajidii")
local LAND = require("eawx-plugins/diplomacy/DiplomacyLandWorlds")
local CLOSED = require("eawx-plugins/diplomacy/DiplomacyUnderworldWorlds")
local LEADERS = require("eawx-plugins/diplomacy/DiplomacyLeaders")

local U = {}
local R = CONFIG.UNDERWORLD
local HUTTS = "HUTT_CARTELS"
local UPSTART = "HUTT_UPSTART"
local SLAVE_UNIT = "HUTT_GUARD_COMPANY"
local COLOR = {r = 230, g = 200, b = 90}
local COLOR_BAD = {r = 255, g = 150, b = 90}
local FAMILIES = table.getn(K.FAMILIES)

local INDEX = {}
for i, f in ipairs(K.FAMILIES) do
    INDEX[f.key] = i
end
U.INDEX = INDEX

function U.active(d)
    return d.human and d.human.Get_Faction_Name() == HUTTS
end

local function week()
    return CONFIG.WEEK_SECONDS
end

local function weeks_from_now(n)
    return GetCurrentTime() + n * week()
end

local function income_of(d, planet)
    local ok, value = pcall(EvaluatePerception, "PlanetBaseIncome", d.human, planet)
    if not ok then
        return 0
    end
    return M.min(M.max(M.sane(value), 0), 100000)
end

local function family_name(i)
    return K.FAMILIES[i] and K.FAMILIES[i].name or "?"
end
U.family_name = family_name

function U.has_land(type_name)
    return LAND[type_name] == true
end

local CLOSED_WHY = {
    space = "a space-only region, with nobody to corrupt",
    empty = "an uninhabited world, with nobody to corrupt",
    base = "a military base, with no civilians to corrupt",
}

function U.closed(type_name)
    local why = CLOSED[type_name]
    if not why and not LAND[type_name] then
        why = "space"
    end
    return why and CLOSED_WHY[why]
end

function U.leader_family(d)
    local hutts = Find_Player(HUTTS)
    for _, entry in ipairs(LEADERS[HUTTS] or {}) do
        local obj = Find_First_Object(entry.type)
        if TestValid(obj) and obj.Get_Owner() == hutts and R.CHARACTERS[entry.type] then
            return INDEX[R.CHARACTERS[entry.type]], entry.type
        end
    end
    for character, family in pairs(R.CHARACTERS) do
        local obj = Find_First_Object(character)
        if TestValid(obj) and obj.Get_Owner() == hutts then
            return INDEX[family], character
        end
    end
    return nil
end

function U.perk(d)
    local f = U.leader_family(d)
    return f and R.LEADER_PERKS[K.FAMILIES[f].key] or {}, f
end

function U.heroes(d)
    local hutts = Find_Player(HUTTS)
    local out = {}
    for i = 1, FAMILIES do
        out[i] = {}
    end
    for character, family in pairs(R.CHARACTERS) do
        local ok, obj = pcall(Find_First_Object, character)
        if ok and TestValid(obj) and obj.Get_Owner() == hutts then
            local where = obj.Get_Planet_Location()
            table.insert(out[INDEX[family]], {type = character, planet = where})
        end
    end
    return out
end

function U.init(d)
    if not d.underworld then
        d.underworld, d.uw_attitude = {}, {}
    end
    if not d.kj then
        d.kj = {families = {}, upstarts = {}, missions = {}}
        for i = 1, FAMILIES do
            d.kj.families[i] = {tier = 0, unlocked = false, upstart_at = 0}
        end
    end
    DIPLOMACY_UNDERWORLD_STRENGTH = function(type_name)
        local rec = d.underworld and d.underworld[string.upper(type_name or "")]
        if not rec or rec.state == "founding" then
            return 0
        end
        local f = U.leader_of(rec)
        return U.level(rec) + (f and U.tier(d, f) or 0)
    end
end

function U.family(d, f)
    U.init(d)
    return d.kj.families[f]
end

function U.controlled(d, f)
    U.init(d)
    local now = GetCurrentTime()
    if d.kj.controlled_at ~= now then
        d.kj.controlled_at, d.kj.controlled = now, {}
    end
    if not d.kj.controlled[f] then
        d.kj.controlled[f] = U.count_controlled(d, f)
    end
    return d.kj.controlled[f]
end

function U.count_controlled(d, f)
    local n = 0
    local hutts = Find_Player(HUTTS)
    local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    local capital = ok and hutts and Deals.capital(d, hutts)
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local name = string.upper(planet.Get_Type().Get_Name())
        if planet.Get_Owner() == hutts then
            if planet ~= capital and K.family_of(d, name) == f then
                n = n + 1
            end
        else
            local rec = d.underworld and d.underworld[name]
            if rec and rec.state == "controlled" and rec.family == f then
                n = n + 1
            end
        end
    end
    return n
end

function U.tier_worlds(d, n)
    U.init(d)
    if not d.kj.populated then
        local populated = 0
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            if not U.closed(string.upper(planet.Get_Type().Get_Name())) then
                populated = populated + 1
            end
        end
        d.kj.populated = populated
    end
    return M.max(R.TIER_WORLDS_MIN[n] or 0, M.ceil(d.kj.populated * (R.TIER_WORLDS[n] or 0)))
end

function U.tier(d, f)
    local fam = U.family(d, f)
    if not fam.unlocked then
        return 0
    end
    local owned = U.controlled(d, f)
    local tier = 1
    for n = 2, table.getn(R.TIERS) do
        if owned >= U.tier_worlds(d, n) then
            tier = n
        else
            break
        end
    end
    return tier
end

function U.tier_bonus(d, f, field)
    local tier = U.tier(d, f)
    local value = nil
    for n = 1, tier do
        for _, point in ipairs(R.TIERS[n].points) do
            if point[field] ~= nil then
                value = point[field]
            end
        end
    end
    return value
end

function U.power(d)
    local out, total = {}, 0
    local hutts = Find_Player(HUTTS)
    local heroes = U.heroes(d)
    for i = 1, FAMILIES do
        out[i] = {power = R.POWER_HERO * table.getn(heroes[i]), share = 0}
    end
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local name = string.upper(planet.Get_Type().Get_Name())
        if hutts and planet.Get_Owner() == hutts then
            local f = K.family_of(d, name)
            out[f].power = out[f].power + R.POWER_HUTT_WORLD
        else
            local rec = d.underworld and d.underworld[name]
            if rec and rec.state == "controlled" then
                out[rec.family].power = out[rec.family].power + R.POWER_CONTROLLED
            elseif rec then
                for i = 1, FAMILIES do
                    out[i].power = out[i].power + R.POWER_INFLUENCE * (rec.influence[i] or 0)
                end
            end
        end
    end
    for i = 1, FAMILIES do
        total = total + out[i].power
    end
    for i = 1, FAMILIES do
        out[i].share = (total > 0) and (100 * out[i].power / total) or (100 / FAMILIES)
    end
    return out
end

function U.politics(d, power)
    power = power or U.power(d)
    local leader = U.leader_family(d)
    local out = {}
    for i = 1, FAMILIES do
        local share = power[i].share
        if leader and i ~= leader and share >= R.CHALLENGE_SHARE
                and power[i].power >= R.CHALLENGE_RATIO * M.max(power[leader].power, 0.01) then
            out[i] = {state = "challenger", text = "strong enough to challenge the " .. family_name(leader)
                .. " for the leadership"}
        elseif share < R.RESTLESS_SHARE then
            out[i] = {state = "restless", text = "too weak to matter, and resentful of it"}
        end
    end
    return out
end

function U.upstart_weeks(d, f, power)
    power = power or U.power(d)
    local share = M.max(power[f].share, 1)
    local weeks = R.UPSTART_BASE_WEEKS * 20 / share * (U.tier_bonus(d, f, "cooldown") or 1)
    return M.min(R.UPSTART_MAX_WEEKS, M.max(R.UPSTART_MIN_WEEKS, weeks))
end

local function recruit_world(d, f)
    local hutts = d.human
    local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    local capital = ok and Deals.capital(d, hutts)
    local any = nil
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == hutts then
            local name = string.upper(planet.Get_Type().Get_Name())
            if planet ~= capital and K.family_of(d, name) == f then
                return planet
            end
            any = any or planet
        end
    end
    return capital or any
end

function U.recruit_blocked(d, f)
    local fam = U.family(d, f)
    if not fam.unlocked then
        return "The " .. family_name(f) .. " must complete their mission first."
    end
    if GetCurrentTime() < (fam.upstart_at or 0) then
        local left = M.max(1, M.ceil((fam.upstart_at - GetCurrentTime()) / week()))
        return "The next " .. family_name(f) .. " Upstart is ready in " .. left .. (left == 1 and " week." or " weeks.")
    end
    if d.human.Get_Credits() < R.UPSTART_COST then
        return "You need " .. R.UPSTART_COST .. " credits."
    end
    if not recruit_world(d, f) then
        return "You hold no world to recruit at."
    end
    return nil
end

function U.recruit(d, f)
    local blocked = U.recruit_blocked(d, f)
    if blocked then
        return false, blocked
    end
    local planet = recruit_world(d, f)
    local unit_type = Find_Object_Type(UPSTART)
    local ok, spawned = pcall(Spawn_Unit, unit_type, planet, d.human)
    if not ok or not spawned then
        return false, "The Upstart could not be sent."
    end
    d.human.Give_Money(-R.UPSTART_COST)
    local unit = (type(spawned) == "table") and spawned[1] or spawned
    table.insert(d.kj.upstarts, {unit = unit, family = f})
    d.kj.families[f].upstart_at = weeks_from_now(U.upstart_weeks(d, f))
    return true, "A " .. family_name(f) .. " Upstart waits at " .. d:planet_name(planet) .. "."
end

function U.claimed(rec)
    local total = 0
    for i = 1, FAMILIES do
        total = total + (rec.influence[i] or 0)
    end
    return total
end

function U.add_influence(rec, f, amount, d)
    if rec.state == "controlled" then
        return
    end
    if amount > 0 and d then
        amount = amount * (U.tier_bonus(d, f, "influence") or 1)
    end
    local mine = rec.influence[f] or 0
    if amount <= 0 then
        rec.influence[f] = M.max(0, mine + amount)
        return
    end
    amount = M.min(amount, 100 - mine)
    local free = 100 - U.claimed(rec)
    local from_free = M.min(amount, free)
    local rest = amount - from_free
    if rest > 0 then
        local rivals = 100 - free - mine
        if rivals > 0 then
            for i = 1, FAMILIES do
                if i ~= f and (rec.influence[i] or 0) > 0 then
                    rec.influence[i] = M.max(0, rec.influence[i] - rest * rec.influence[i] / rivals)
                end
            end
        end
    end
    rec.influence[f] = mine + amount
end

function U.leader_of(rec)
    if rec.state == "controlled" then
        return rec.family, 100
    end
    local best, share = nil, 0
    for i = 1, FAMILIES do
        if (rec.influence[i] or 0) > share then
            best, share = i, rec.influence[i]
        end
    end
    return best, share
end

local function strongest_rival(rec, f)
    local rival, best = nil, 0
    for i = 1, FAMILIES do
        if i ~= f and (rec.influence[i] or 0) > best then
            rival, best = i, rec.influence[i]
        end
    end
    return rival
end

function U.get(d, type_name)
    return d.underworld and d.underworld[type_name]
end

function U.level(rec)
    if rec.state == "controlled" then
        return 5
    end
    local level = 0
    for n, needed in ipairs(R.LEVEL_OPS) do
        if (rec.ops_done or 0) >= needed then
            level = n
        end
    end
    return level
end

function U.ops_to_next(rec)
    local needed = R.LEVEL_OPS[U.level(rec) + 1]
    return needed and (needed - (rec.ops_done or 0)) or nil
end

function U.slots(d, planet)
    local ok, n = pcall(EvaluatePerception, "Total_Slots", d.human, planet)
    if not ok or type(n) ~= "number" or n <= 0 then
        n = 4
    end
    return M.min(M.max(M.floor(n + 0.5), 2), 10)
end

function U.unlocked(d, rec, planet)
    if rec.state == "founding" then
        return 0
    end
    return M.min(U.slots(d, planet), R.SLOTS_BASE + R.SLOTS_PER_LEVEL * U.level(rec))
end

function U.forming(rec)
    if rec.state ~= "founding" then
        return 100
    end
    local span = M.max(1, rec.formed_at - rec.founded)
    return M.min(99, M.max(0, M.floor(100 * (GetCurrentTime() - rec.founded) / span)))
end

local function new_record()
    local rec = {state = "founding", family = nil, influence = {}, ops_done = 0, unrest = 0, structures = {},
                 op = nil, timers = {}, founded = GetCurrentTime(), formed_at = weeks_from_now(R.FOUND_WEEKS)}
    for i = 1, FAMILIES do
        rec.influence[i] = 0
    end
    return rec
end

function U.found(d, planet, family)
    U.init(d)
    local name = string.upper(planet.Get_Type().Get_Name())
    local rec = new_record()
    U.add_influence(rec, family, R.INFLUENCE_FOUNDER + (U.tier_bonus(d, family, "founder") or 0), d)
    d.underworld[name] = rec
    d.show("Underworld: a " .. family_name(family) .. " Upstart starts an underworld on " .. d:planet_name(planet)
        .. ". It forms in " .. R.FOUND_WEEKS .. " weeks.", nil, COLOR)
    U.mist(d, planet, rec)
    return rec
end

local KILL_WAIT = 3

function U.upstart_killed(d)
    U.init(d)
    d.kj.killed = (d.kj.killed or 0) + 1
    d.kj.killed_at = GetCurrentTime()
end

local function parent_size(unit)
    local ok, parent = pcall(unit.Get_Parent_Object)
    if not ok or not parent or not TestValid(parent) then
        return 0
    end
    local okc, n = pcall(parent.Get_Contained_Object_Count)
    return okc and tonumber(n) or 0
end

local function track_upstarts(d, units)
    local live, matched = {}, {}
    for _, unit in pairs(units) do
        if TestValid(unit) and unit.Get_Owner() == d.human then
            table.insert(live, unit)
        end
    end
    local free = {}
    for _, unit in ipairs(live) do
        local found = nil
        for i, entry in ipairs(d.kj.upstarts) do
            if not matched[i] and entry.unit == unit then
                found = i
                break
            end
        end
        if found then
            matched[found] = unit
        else
            table.insert(free, unit)
        end
    end
    for _, unit in ipairs(free) do
        local planet = unit.Get_Planet_Location()
        local at = planet and string.upper(planet.Get_Type().Get_Name())
        local found = nil
        for i, entry in ipairs(d.kj.upstarts) do
            if not matched[i] and not entry.gone_at and not TestValid(entry.unit) and entry.at == at then
                found = i
                break
            end
        end
        if not found then
            table.insert(d.kj.upstarts, {family = U.leader_family(d) or 2})
            found = table.getn(d.kj.upstarts)
        end
        d.kj.upstarts[found].unit = unit
        matched[found] = unit
    end
    return matched
end

function U.shop_blocked(d, planet, f)
    local name = string.upper(planet.Get_Type().Get_Name())
    local closed = U.closed(name)
    if closed then
        return closed
    end
    if planet.Get_Owner() == d.human then
        return "it is already a Hutt world"
    end
    local rec = d.underworld[name]
    if rec and rec.state == "controlled" then
        if rec.family == f then
            return "the " .. family_name(f) .. " already control it"
        end
        return "the " .. family_name(rec.family) .. " control it - no other family gets in"
    end
    return nil
end

local function send_home(d, entry, planet, why)
    local home = recruit_world(d, entry.family)
    local ok, spawned = false, nil
    if home then
        ok, spawned = pcall(Spawn_Unit, Find_Object_Type(UPSTART), home, d.human)
    end
    local unit = ok and ((type(spawned) == "table") and spawned[1] or spawned)
    if unit then
        table.insert(d.kj.upstarts, {unit = unit, family = entry.family})
    end
    d.show("Underworld: no underworld on " .. d:planet_name(planet) .. " - " .. why .. "."
        .. (unit and (" The Upstart returns to " .. d:planet_name(home) .. ".") or ""), nil, COLOR_BAD)
end

local function set_up_shop(d, entry)
    local planet = entry.at and FindPlanet(entry.at)
    if not planet then
        return
    end
    local why = U.shop_blocked(d, planet, entry.family)
    if why then
        send_home(d, entry, planet, why)
        return
    end
    local rec = d.underworld[entry.at]
    if not rec then
        U.found(d, planet, entry.family)
    else
        U.add_influence(rec, entry.family, R.INFLUENCE_UPSTART + (U.tier_bonus(d, entry.family, "founder") or 0), d)
        d.show("Underworld: a " .. family_name(entry.family) .. " Upstart joins the underworld of "
            .. d:planet_name(planet) .. ".", nil, COLOR)
    end
end

function U.scan_upstarts(d)
    local ok, units = pcall(Find_All_Objects_Of_Type, UPSTART)
    if not ok or not units then
        return
    end
    local matched = track_upstarts(d, units)
    local keep = {}
    local now = GetCurrentTime()
    for i, entry in ipairs(d.kj.upstarts) do
        local unit = matched[i]
        if unit then
            local planet = unit.Get_Planet_Location()
            entry.at = planet and string.upper(planet.Get_Type().Get_Name()) or nil
            entry.fleet = parent_size(unit)
            entry.foreign = planet and planet.Get_Owner() ~= d.human or false
            table.insert(keep, entry)
        elseif (d.kj.killed or 0) > 0 and (d.kj.killed_at or 0) >= (entry.gone_at or now) - KILL_WAIT then
            d.kj.killed = d.kj.killed - 1
        elseif entry.at and entry.foreign then
            entry.gone_at = entry.gone_at or now
            if now >= entry.gone_at + KILL_WAIT then
                set_up_shop(d, entry)
            else
                table.insert(keep, entry)
            end
        end
    end
    d.kj.upstarts = keep
    if table.getn(keep) == 0 or now > (d.kj.killed_at or 0) + 2 * KILL_WAIT then
        d.kj.killed = 0
    end
end

function U.debug_upstarts(d)
    local out = {}
    for _, entry in ipairs(d.kj and d.kj.upstarts or {}) do
        local unit = entry.unit
        local parent = nil
        if unit and TestValid(unit) then
            parent = unit.Get_Parent_Object()
        end
        table.insert(out, family_name(entry.family) .. " at " .. tostring(entry.at) .. " fleet " .. tostring(entry.fleet)
            .. " parent " .. ((parent and TestValid(parent)) and parent.Get_Type().Get_Name() or "none")
            .. (entry.gone_at and " (gone)" or "")
            .. " foreign " .. tostring(entry.foreign))
    end
    return table.getn(out) .. " upstarts: " .. table.concat(out, "; ")
end

local function has_built(rec, key)
    for _, s in pairs(rec.structures) do
        if s and s.key == key and s.ready <= GetCurrentTime() then
            return s
        end
    end
    return nil
end
U.has_built = has_built

function U.build_blocked(d, rec, key)
    local def = R.STRUCTURES[key]
    if rec.state == "founding" then
        return "The underworld is still forming."
    end
    for _, s in pairs(rec.structures) do
        if s and s.key == key then
            return "There is already a " .. def.name .. " here."
        end
    end
    local f = INDEX[def.family]
    if def.advanced and rec.state ~= "controlled" then
        if U.level(rec) < R.ADVANCED_LEVEL then
            return "Advanced: needs underworld level " .. R.ADVANCED_LEVEL .. "."
        end
        if (rec.influence[f] or 0) <= R.ADVANCED_SHARE then
            return "Advanced: the " .. family_name(f) .. " need more than " .. R.ADVANCED_SHARE .. "% influence here."
        end
    end
    if d.human.Get_Credits() < def.cost then
        return "You need " .. def.cost .. " credits."
    end
    return nil
end

function U.build(d, type_name, slot, key)
    local rec = U.get(d, type_name)
    local def = R.STRUCTURES[key]
    local planet = FindPlanet(type_name)
    if not rec or not def or not planet then
        return false, "No underworld here."
    end
    if slot > U.unlocked(d, rec, planet) then
        return false, "That slot opens at a higher underworld level."
    end
    if rec.structures[slot] then
        return false, "That slot is taken."
    end
    local blocked = U.build_blocked(d, rec, key)
    if blocked then
        return false, blocked
    end
    d.human.Give_Money(-def.cost)
    rec.structures[slot] = {key = key, family = INDEX[def.family], ready = weeks_from_now(def.weeks), gained = 0}
    return true, def.name .. " under construction for the " .. family_name(INDEX[def.family]) .. " (" .. def.weeks
        .. (def.weeks == 1 and " week)." or " weeks).")
end

function U.destroy_building(rec, slot)
    local s = rec.structures[slot]
    if s then
        U.add_influence(rec, s.family, -(s.gained or 0))
        rec.structures[slot] = nil
    end
end

local function finish_buildings(d, rec)
    for _, s in pairs(rec.structures) do
        if s and not s.done and s.ready <= GetCurrentTime() then
            s.done = true
            local before = rec.influence[s.family] or 0
            U.add_influence(rec, s.family, R.INFLUENCE_BUILD, d)
            s.gained = (rec.influence[s.family] or 0) - before
        end
    end
end

function U.op_building(key)
    for k, def in pairs(R.STRUCTURES) do
        if def.op == key then
            return k, def
        end
    end
    return nil
end

local function op_bonus(rec)
    local bonus = 0
    for _, s in pairs(rec.structures) do
        if s and s.ready <= GetCurrentTime() then
            bonus = bonus + (R.STRUCTURES[s.key].op_bonus or 0)
        end
    end
    return bonus
end

function U.op_cost(d, rec, key)
    local def = R.OPERATIONS[key]
    local cost = def.cost * (U.tier_bonus(d, INDEX[def.family], "op_cost") or 1)
    if has_built(rec, "smuggler_port") then
        cost = cost * (1 - R.STRUCTURES.smuggler_port.op_discount)
    end
    local perk = U.perk(d)
    if perk.op_cost then
        cost = cost * perk.op_cost
    end
    return M.floor(cost)
end

function U.op_chance(d, rec, key, owner)
    local def = R.OPERATIONS[key]
    local chance = def.chance + op_bonus(rec) + (U.perk(d).op_bonus or 0)
        + (U.tier_bonus(d, INDEX[def.family], "op_bonus") or 0)
    if owner and owner ~= d.human then
        chance = chance + M.floor(U.attitude(d, owner.Get_Faction_Name()) / 3)
    end
    return M.min(R.CHANCE_MAX, M.max(R.CHANCE_MIN, chance))
end

function U.op_blocked(d, rec, key, planet)
    local def = R.OPERATIONS[key]
    local building = U.op_building(key)
    if rec.op then
        return "An operation is already under way here."
    end
    if rec.turf then
        return "The Turf War is under way here."
    end
    if not building or not has_built(rec, building) then
        return "Needs a " .. R.STRUCTURES[building].name .. " here."
    end
    if def.take and rec.state == "controlled" then
        return "No rival family left to push out."
    end
    if planet.Get_Owner() == d.human then
        return "This is your own world."
    end
    if d.human.Get_Credits() < U.op_cost(d, rec, key) then
        return "You need " .. U.op_cost(d, rec, key) .. " credits."
    end
    return nil
end

function U.operate(d, type_name, key)
    local rec = U.get(d, type_name)
    local def = R.OPERATIONS[key]
    local planet = FindPlanet(type_name)
    if not rec or not def or not planet then
        return false, "No underworld here."
    end
    local blocked = U.op_blocked(d, rec, key, planet)
    if blocked then
        return false, blocked
    end
    d.human.Give_Money(-U.op_cost(d, rec, key))
    local f = INDEX[def.family]
    rec.op = {key = key, family = f, ends = weeks_from_now(def.weeks)}
    return true, def.name .. " begins, run by the " .. family_name(f) .. "."
end

local function nearest_hutt_world(d, planet)
    return d:nearest_friendly_planet(d.human, planet)
end

local function attitude_add(d, faction, amount, cap)
    d.uw_attitude[faction] = M.min(cap or R.ATTITUDE_CAP, M.max(-R.ATTITUDE_CAP, (d.uw_attitude[faction] or 0) + amount))
end

local function take_from_rival(d, rec, f, amount)
    local rival = strongest_rival(rec, f)
    if not rival then
        return nil
    end
    local take = M.min(amount, rec.influence[rival])
    rec.influence[rival] = rec.influence[rival] - take
    U.add_influence(rec, f, take, d)
    return rival
end

local function steal(d, owner, amount)
    amount = M.min(M.floor(amount), M.max(0, owner.Get_Credits()))
    owner.Give_Money(-amount)
    d.human.Give_Money(amount)
    return amount
end

local function resolve_op(d, name, rec, planet)
    local op = rec.op
    rec.op = nil
    local def = R.OPERATIONS[op.key]
    local owner = planet.Get_Owner()
    local where = d:planet_name(planet)
    local perk = U.perk(d)
    if GameRandom.Free_Random(1, 100) > U.op_chance(d, rec, op.key, owner) then
        if owner ~= d.human then
            attitude_add(d, owner.Get_Faction_Name(), R.FAIL_ATTITUDE)
        end
        d.show("Underworld: " .. def.name .. " on " .. where .. " failed - the " .. family_name(op.family)
            .. " agents were exposed.", nil, COLOR_BAD)
        return
    end
    local level = U.level(rec)
    U.add_influence(rec, op.family, R.INFLUENCE_OP, d)
    rec.ops_done = (rec.ops_done or 0) + (def.steps or 1)
    local income = income_of(d, planet)
    local text = def.name .. " on " .. where .. " succeeded"
    if def.steal then
        text = text .. ": " .. steal(d, owner, income * def.steal * (perk.income or 1)) .. " credits"
    elseif def.ransom then
        text = text .. ": a ransom of " .. steal(d, owner, income * def.ransom * (perk.ransom or 1)) .. " credits"
        attitude_add(d, owner.Get_Faction_Name(), def.attitude)
    elseif def.sabotage then
        local targets = {}
        for _, obj in pairs(Find_All_Objects_Of_Type(owner) or {}) do
            if TestValid(obj) and obj.Get_Planet_Location() == planet and obj.Is_Category("Structure")
                    and not obj.Get_Type().Is_Hero() then
                table.insert(targets, obj)
            end
        end
        if table.getn(targets) > 0 then
            local target = targets[GameRandom.Free_Random(1, table.getn(targets))]
            text = text .. ": their " .. d.unit_name(target.Get_Type().Get_Name()) .. " is rubble"
            target.Despawn()
        else
            text = text .. ", but there was nothing worth destroying"
        end
    elseif def.unrest then
        rec.unrest = M.min(R.REVOLT_AT, rec.unrest + def.unrest)
        text = text .. ": unrest " .. M.floor(rec.unrest) .. "/" .. R.REVOLT_AT
    elseif def.take then
        local rival = take_from_rival(d, rec, op.family, def.take)
        if rival then
            text = text .. ": the " .. family_name(rival) .. " lose ground to the " .. family_name(op.family)
        end
    end
    if U.level(rec) > level then
        text = text .. ". The underworld reaches level " .. U.level(rec)
    end
    d.show("Underworld: " .. text .. ".", nil, COLOR)
end

function U.turf_blocked(d, rec)
    if rec.state == "controlled" then
        return "The " .. family_name(rec.family) .. " already control this world."
    end
    if U.level(rec) < 4 then
        return "The Turf War comes at level 4."
    end
    if rec.turf or rec.op then
        return "Something is already under way here."
    end
    if not U.leader_of(rec) then
        return "No family is strong enough to fight for it."
    end
    if d.human.Get_Credits() < R.TURF_COST then
        return "You need " .. R.TURF_COST .. " credits."
    end
    return nil
end

function U.turf_chance(rec)
    local _, share = U.leader_of(rec)
    return M.min(R.CHANCE_MAX, M.max(R.CHANCE_MIN, M.floor(R.TURF_CHANCE_BASE + share * R.TURF_CHANCE_SHARE)))
end

function U.turf_result(d, type_name, won)
    local rec = U.get(d, type_name)
    local planet = FindPlanet(type_name)
    if not rec or not planet then
        return
    end
    local f = rec.turf and rec.turf.family or U.leader_of(rec)
    rec.turf = nil
    d.kj.controlled_at = nil
    if won then
        rec.state, rec.family = "controlled", f
        for i = 1, FAMILIES do
            rec.influence[i] = (i == f) and 100 or 0
        end
        d.show("Underworld: the " .. family_name(f) .. " win the Turf War - " .. d:planet_name(planet)
            .. " is theirs alone.", nil, COLOR)
        U.mist(d, planet, rec)
    else
        local level = U.level(rec)
        rec.ops_done = (level >= 2) and R.LEVEL_OPS[level - 1] or 0
        for slot, s in pairs(rec.structures) do
            if s and s.family == f then
                U.destroy_building(rec, slot)
            end
        end
        d.show("Underworld: the " .. family_name(f) .. " lose the Turf War on " .. d:planet_name(planet)
            .. ": their buildings burn and the underworld falls back a level.", nil, COLOR_BAD)
    end
end

function U.update(d)
    if not U.active(d) then
        return
    end
    U.init(d)
    U.scan_upstarts(d)
    local now = GetCurrentTime()
    for name, rec in pairs(d.underworld) do
        local planet = FindPlanet(name)
        if rec.state == "founding" and now >= rec.formed_at and planet then
            rec.state = "contested"
            d.show("Underworld: the underworld of " .. d:planet_name(planet) .. " has formed. Build there to "
                .. "start operations.", nil, COLOR)
            U.mist(d, planet, rec)
        end
        finish_buildings(d, rec)
        if rec.op and now >= rec.op.ends then
            if planet then
                resolve_op(d, name, rec, planet)
            else
                rec.op = nil
            end
        end
    end
    local ok, Missions = pcall(require, "eawx-plugins/diplomacy/DiplomacyKajidicMissions")
    if ok then
        Missions.update(d)
    end
    if now >= (d.uw_next_week or 0) then
        d.uw_next_week = now + week()
        U.weekly(d)
    end
end

function U.weekly(d)
    local perk, leader = U.perk(d)
    local fronts = 0
    local week_income = 0
    local heroes = U.heroes(d)
    for name, rec in pairs(d.underworld) do
        local planet = FindPlanet(name)
        if planet then
            local owner = planet.Get_Owner()
            local foreign = owner ~= d.human
            local faction = owner.Get_Faction_Name()
            local income = income_of(d, planet)
            rec.timers = rec.timers or {}
            for _, s in pairs(rec.structures) do
                if s and s.ready <= GetCurrentTime() then
                    local def = R.STRUCTURES[s.key]
                    local power = U.tier_bonus(d, s.family, "effect") or 1
                    U.add_influence(rec, s.family, def.advanced and R.INFLUENCE_WEEK_ADVANCED or R.INFLUENCE_WEEK, d)
                    if def.income then
                        local gain = income * def.income * power * (perk.income or 1)
                        if s.key == "spice_lab" then
                            gain = gain * (perk.spice or 1)
                        end
                        week_income = week_income + gain
                        d.human.Give_Money(M.floor(gain))
                    end
                    if def.unrest and foreign then
                        rec.unrest = rec.unrest + def.unrest
                    end
                    if def.fee and foreign then
                        local fee = steal(d, owner, income * def.fee * power * (perk.fees or 1))
                        week_income = week_income + fee
                    end
                    if def.drain and foreign then
                        owner.Give_Money(-M.min(M.floor(income * def.drain * power), M.max(0, owner.Get_Credits())))
                    end
                    if def.upkeep then
                        fronts = fronts + 1
                    end
                    if def.attitude and foreign then
                        attitude_add(d, faction, def.attitude, def.attitude_max)
                    end
                    if s.key == "slave_pens" then
                        rec.timers.pens = (rec.timers.pens or 0) + 1
                        if rec.timers.pens >= (perk.pens_every or def.every) then
                            rec.timers.pens = 0
                            local home = nearest_hutt_world(d, planet)
                            local t = Find_Object_Type(SLAVE_UNIT)
                            if home and t then
                                pcall(Spawn_Unit, t, home, d.human)
                                d.show("Underworld: slave troops from " .. d:planet_name(planet) .. " arrive at "
                                    .. d:planet_name(home) .. ".", nil, COLOR)
                            end
                        end
                    end
                    if s.key == "black_market" and foreign then
                        rec.timers.market = (rec.timers.market or 0) + 1
                        if rec.timers.market >= def.every then
                            rec.timers.market = 0
                            U.black_market(d, planet, owner)
                        end
                    end
                end
            end
            if rec.state == "contested" then
                if leader then
                    U.add_influence(rec, leader, R.INFLUENCE_LEADER_DRIFT, d)
                end
                for f = 1, FAMILIES do
                    for _, hero in ipairs(heroes[f]) do
                        if hero.planet == planet then
                            U.add_influence(rec, f, R.INFLUENCE_HERO_WEEK, d)
                        end
                    end
                end
            end
            if foreign then
                rec.unrest = M.max(0, rec.unrest - R.UNREST_DECAY)
                if rec.unrest >= R.REVOLT_AT then
                    rec.unrest = 0
                    local independents = Find_Player("INDEPENDENT_FORCES")
                    if independents and owner ~= independents then
                        d.show("Underworld: riots on " .. d:planet_name(planet) .. " - the world breaks from "
                            .. d.display_name(faction) .. "!", nil, COLOR)
                        pcall(d.transfer_world, d, planet, independents, false, true)
                    end
                end
            end
        else
            d.underworld[name] = nil
        end
    end
    U.haze(d)
    local share = M.min(fronts * R.STRUCTURES.protection_racket.upkeep, R.STRUCTURES.protection_racket.upkeep_max)
        + (perk.upkeep or 0)
    if share > 0 then
        local ok, upkeep = pcall(EvaluatePerception, "Total_Maintenance", d.human)
        if ok and type(upkeep) == "number" and upkeep > 0 then
            d.human.Give_Money(M.floor(upkeep * share))
        end
    end
    d.uw_last_income = M.floor(week_income)
end

function U.black_market(d, planet, owner)
    local kinds = {}
    for _, obj in pairs(Find_All_Objects_Of_Type(owner) or {}) do
        if TestValid(obj) and obj.Get_Planet_Location() == planet and not obj.Get_Type().Is_Hero()
                and (obj.Is_Category("Infantry") or obj.Is_Category("Vehicle")) then
            table.insert(kinds, obj.Get_Type())
        end
    end
    local home = nearest_hutt_world(d, planet)
    if table.getn(kinds) == 0 or not home then
        return
    end
    local t = kinds[GameRandom.Free_Random(1, table.getn(kinds))]
    if pcall(Spawn_Unit, t, home, d.human) then
        d.show("Underworld: the black market on " .. d:planet_name(planet) .. " delivers a stolen "
            .. d.unit_name(t.Get_Name()) .. " to " .. d:planet_name(home) .. ".", nil, COLOR)
    end
end

function U.attitude(d, faction)
    if not d.uw_attitude then
        return 0
    end
    local perk = U.active(d) and U.perk(d) or {}
    return M.min(R.ATTITUDE_CAP, M.max(-R.ATTITUDE_CAP, (d.uw_attitude[faction] or 0) + (perk.attitude or 0)))
end

function U.on_owner_changed(d, planet, new_owner_name, old_owner_name)
    if not U.active(d) or not d.underworld then
        return
    end
    local name = string.upper(planet.Get_Type().Get_Name())
    local rec = d.underworld[name]
    if not rec then
        return
    end
    if new_owner_name == HUTTS and old_owner_name ~= HUTTS then
        if has_built(rec, "bribed_officials") then
            local family = U.leader_of(rec) or U.leader_family(d) or 2
            d.kajidii_worlds = d.kajidii_worlds or {}
            d.kajidii_worlds[name] = family
            d.underworld[name] = nil
            d.show("Underworld: the bribed officials of " .. d:planet_name(planet) .. " hand the world over quietly; "
                .. "it passes to the " .. family_name(family) .. " kajidic.", nil, COLOR)
            return
        end
        d.underworld[name] = nil
        for _, other in pairs(d.underworld) do
            if other.state ~= "controlled" then
                for i = 1, FAMILIES do
                    other.influence[i] = (other.influence[i] or 0) * (1 - R.WIPE_FAVOUR / 100)
                end
            end
        end
        d.show("Underworld: the kajidii, united, tear down the underworld of " .. d:planet_name(planet)
            .. " - no family's turf is taken by the fleet. Every family loses ground elsewhere.", nil, COLOR_BAD)
    end
end

local function haze_colour(d, name, rec, capital)
    if rec then
        return (rec.state == "controlled") and rec.family or 0, (rec.state == "controlled") and "Heavy" or "Light"
    end
    if capital then
        return 0, "Heavy"
    end
    return K.family_of(d, name), "Heavy"
end

local function particle(colour, kind)
    if colour == 0 then
        return "DP_Underworld_Mist_" .. kind
    end
    return "DP_Underworld_Mist_" .. colour .. "_" .. kind
end

local function adjacent(d, a, b)
    d.uw_lanes = d.uw_lanes or {}
    local key = (a.name < b.name) and (a.name .. "|" .. b.name) or (b.name .. "|" .. a.name)
    if d.uw_lanes[key] == nil then
        local ok, path = pcall(Find_Path, d.human, a.planet, b.planet)
        d.uw_lanes[key] = ok and type(path) == "table" and table.getn(path) == 2
    end
    return d.uw_lanes[key]
end

function U.haze(d)
    if not U.active(d) then
        return
    end
    local now = GetCurrentTime()
    if d.uw_haze_time and now - d.uw_haze_time < R.HAZE_MIN_GAP then
        return
    end
    d.uw_haze_time = now
    local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    local capital = ok and Deals.capital(d, d.human)
    local hazed = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local name = string.upper(planet.Get_Type().Get_Name())
        local rec = d.underworld[name]
        if planet.Get_Owner() == d.human or rec then
            local colour, kind = haze_colour(d, name, rec, planet == capital)
            pcall(planet.Attach_Particle_Effect, particle(colour, kind))
            table.insert(hazed, {planet = planet, name = name, colour = colour})
        end
    end
    if not Engine_Spawn_Between then
        return
    end
    for i = 1, table.getn(hazed) do
        for j = i + 1, table.getn(hazed) do
            local a, b = hazed[i], hazed[j]
            if adjacent(d, a, b) then
                pcall(Engine_Spawn_Between, a.name, b.name, particle(a.colour, "Lane"), 0.08, 0.5, R.LANE_HAZE_SPACING)
                pcall(Engine_Spawn_Between, b.name, a.name, particle(b.colour, "Lane"), 0.08, 0.5, R.LANE_HAZE_SPACING)
            end
        end
    end
end

function U.mist(d, planet, rec)
    if not U.active(d) then
        return
    end
    local name = string.upper(planet.Get_Type().Get_Name())
    pcall(planet.Attach_Particle_Effect, particle(haze_colour(d, name, rec, false)))
end

return U
