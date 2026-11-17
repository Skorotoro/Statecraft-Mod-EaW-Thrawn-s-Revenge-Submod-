require("PGSpawnUnits")
local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local Court = require("eawx-plugins/imperial-court/Court")
local M = require("eawx-plugins/imperial-court/CourtMath")
local SHIPS = require("eawx-plugins/imperial-court/CourtShips")
local LORE = require("eawx-plugins/imperial-court/CourtLore")
local POOLS = SHIPS.pools
local FLAG_CLASS = {G = "Imperial II Star Destroyer", M = "Imperial I Star Destroyer", V = "Strike Cruiser",
                    S = "Allegiance battlecruiser"}

local Fleet = {}

local RANK = {grand_admiral = "G", admiral = "M", captain = "V", supreme = "S"}
local SLOT_RANK = {}
for rank, list in pairs(POOLS) do
    for _, slot in ipairs(list) do
        SLOT_RANK[slot] = rank
    end
end

local function unit_of(slot)
    local obj = Find_First_Object(slot)
    if obj and TestValid(obj) then
        return obj
    end
    return nil
end
Fleet.unit_of = unit_of

local function allegiance()
    return not IMPERIAL_COURT_ALLEGIANCE_LOCKED
end

local function rank_key(s, c)
    if c and c.status == "serving" and s and s.offices and s.offices.FLEET == c.id then
        return "supreme"
    end
    return c and c.fleet_rank
end
Fleet.rank_key = rank_key

local function pool_of(letter)
    local pool = POOLS[letter or ""]
    if letter == "S" and pool then
        return {pool[allegiance() and 1 or 2]}
    end
    return pool
end

local function fits(class, letter)
    return class == letter or (letter == "S" and class == "G")
end

local function name_ship(slot, text)
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_" .. slot, text)
    end
    if Engine_Set_Object_Text then
        pcall(Engine_Set_Object_Text, slot, "TEXT_" .. slot, text)
    end
end

local function home_of(s, c)
    local seat = Court.capital_of(s, c)
    local empire = Court.player()
    for i = 1, 2 do
        local name = (i == 1) and seat or s.capital
        local planet = name and FindPlanet(name)
        if planet and planet.Get_Owner() == empire then
            return planet
        end
    end
    return nil
end

local function lore_def(c)
    return c and c.lore and LORE.CHARACTERS[c.lore] or nil
end

local function lore_ship(c, rank)
    local def = lore_def(c)
    if not def or not rank then
        return nil
    end
    if def.ship then
        return def.ship, def.ship_price or 3000, def.ship_weeks or 2, "own"
    end
    if rank == "S" and (not allegiance() or not (LORE.FLAGS and LORE.FLAGS.S)) then
        rank = "G"
    end
    if def.flag and LORE.FLAGS and LORE.FLAGS[rank] then
        return def.flag .. "_" .. rank, LORE.FLAGS[rank].price, LORE.FLAGS[rank].weeks, "flag"
    end
    return nil
end
Fleet.lore_ship = lore_ship

local function ship_rank(c, slot)
    if SLOT_RANK[slot] then
        return SLOT_RANK[slot]
    end
    local _, _, letter = string.find(slot or "", "^COURT_FLAG_%d+_(%u)$")
    return letter
end

local function real_hero(c)
    if not c.lore then
        return nil
    end
    local obj, owner = Court.unit_on_map(c.lore)
    if obj and c.ship_granted and c.ship_kind == "own" and string.upper(obj.Get_Type().Get_Name()) == c.ship then
        return nil
    end
    return obj, owner
end

local function wants_ship(s, c)
    if c.status ~= "serving" or RANK[rank_key(s, c) or ""] == nil or c.ship_lost then
        return false
    end
    if c.ship_granted then
        return true
    end
    if c.lore then
        return real_hero(c) == nil
    end
    return not Court.own_ship(c)
end

local function remove_unit(s, obj)
    if obj and TestValid(obj) then
        local Agents = require("eawx-plugins/imperial-court/CourtOperatives")
        Agents.queue_removal(s, obj)
    end
end

function Fleet.release(s, c)
    s.ships = s.ships or {}
    if c.ship and s.ships[c.ship] == c.id then
        s.ships[c.ship] = nil
        local unit = unit_of(c.ship)
        if c.ship_granted then
            if unit and unit.Get_Owner() == Court.player() then
                remove_unit(s, unit)
            end
        elseif unit then
            name_ship(c.ship, "Imperial Flagship (no commander)")
        end
    end
    if c.ship_paid and not c.ship_launched then
        pcall(Court.player().Give_Money, c.ship_paid)
    end
    c.ship, c.ship_launched, c.ship_paid, c.ship_granted, c.ship_kind = nil, nil, nil, nil, nil
end

function Fleet.offer(s, c, rank)
    local pool = CONFIG.SHIPS.ENABLED and pool_of(RANK[rank or ""])
    if not pool or Court.own_ship(c) or c.ship_lost then
        return nil, 0
    end
    if c.lore then
        local slot, price = lore_ship(c, RANK[rank])
        if c.ship_granted and c.ship and (c.ship_kind == "own" or c.ship == slot) then
            return c.ship, 0
        end
        if not slot or real_hero(c) then
            return nil, 0
        end
        return slot, price
    end
    if c.ship and fits(SLOT_RANK[c.ship], RANK[rank]) then
        return c.ship, 0
    end
    local empire = Court.player()
    local ships = s.ships or {}
    local free
    for _, slot in ipairs(pool) do
        if ships[slot] == nil then
            local unit = unit_of(slot)
            if unit and unit.Get_Owner() == empire then
                return slot, 0
            elseif not unit then
                free = free or slot
            end
        end
    end
    if free then
        return free, SHIPS.price[free] or 0
    end
    return nil, 0
end

function Fleet.class(slot)
    if not slot then
        return "warship"
    end
    local _, _, letter = string.find(slot, "^COURT_FLAG_%d+_(%u)$")
    if letter then
        return FLAG_CLASS[letter] or "warship"
    end
    if not SHIPS.class[slot] and DIPLOMACY_UNIT_NAME then
        local ok, name = pcall(DIPLOMACY_UNIT_NAME, slot)
        if ok and name and name ~= slot then
            return name
        end
    end
    return SHIPS.class[slot] or "own flagship"
end

function Fleet.reserve(s, c, slot, price)
    s.ships = s.ships or {}
    if not slot or c.ship == slot then
        return nil
    end
    Fleet.release(s, c)
    s.ships[slot], c.ship = c.id, slot
    if c.lore and not SLOT_RANK[slot] then
        local _, _, _, kind = lore_ship(c, ship_rank(c, slot) or RANK[rank_key(s, c) or ""])
        c.ship_granted, c.ship_kind = true, kind
    end
    if price > 0 then
        c.ship_paid = price
        if c.ship_kind == "own" then
            return "Their own flagship is readied for " .. price .. " credits."
        end
        return "A new " .. Fleet.class(slot) .. " is commissioned for " .. price .. " credits."
    end
    c.ship_launched = true
    name_ship(slot, Court.full_name(c))
    return "They take command of a waiting " .. Fleet.class(slot) .. "."
end

function Fleet.label(s, c)
    if c.ship_lost then
        return (c.rebuild_until and ("Flagship: rebuilding, ready in " .. M.weeks(M.max(0, c.rebuild_until - s.week))))
            or "Flagship lost: rebuild it"
    end
    if not c.ship then
        return nil
    end
    local unit = unit_of(c.ship)
    if not unit then
        return "Flagship: awaiting launch"
    end
    local at = unit.Get_Planet_Location()
    return "Flagship: " .. Fleet.class(c.ship) .. (at and (" at " .. Court.planet_label(Court.name_of(at))) or " in hyperspace")
end

function Fleet.week(s)
    if not CONFIG.SHIPS.ENABLED then
        return
    end
    s.ships = s.ships or {}
    local empire = Court.player()
    for slot, id in pairs(s.ships) do
        local c = s.chars[id]
        local unit = unit_of(slot)
        if not c or c.status ~= "serving" or (c.ship ~= slot) then
            if c and (c.status == "rebel" or c.status == "defected") and c.faction and unit and unit.Get_Owner() == empire then
                local player = Find_Player(c.faction)
                if player then
                    pcall(unit.Change_Owner, player)
                end
                s.ships[slot] = false
            elseif unit and unit.Get_Owner() == empire and not SLOT_RANK[slot] then
                s.ships[slot] = nil
                remove_unit(s, unit)
            elseif unit and unit.Get_Owner() == empire then
                s.ships[slot] = nil
                name_ship(slot, "Imperial Flagship (no commander)")
            elseif not unit then
                s.ships[slot] = nil
            end
        elseif c.ship_granted and real_hero(c) then
            if unit and unit.Get_Owner() == empire then
                remove_unit(s, unit)
            end
            s.ships[slot] = nil
            c.ship, c.ship_launched, c.ship_paid, c.ship_granted, c.ship_kind = nil, nil, nil, nil, nil
        elseif c.ship_granted and unit and unit.Get_Owner() ~= empire then
            s.ships[slot] = nil
            c.ship, c.ship_launched, c.ship_granted, c.ship_kind = nil, nil, nil, nil
        elseif not unit and c.ship_launched then
            c.ship_missing = (c.ship_missing or 0) + 1
            if c.ship_missing >= 2 then
                c.ship_missing = nil
                Fleet.lost(s, c, slot)
            end
        elseif unit then
            c.ship_missing = nil
        end
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.ship_lost and (c.status ~= "serving" or not rank_key(s, c)) then
            c.ship_lost, c.rebuild_until = nil, nil
        elseif c.ship_lost and c.rebuild_until and s.week >= c.rebuild_until then
            local lost = c.ship_lost
            c.ship_lost, c.rebuild_until = nil, nil
            s.ships[lost.type], c.ship, c.ship_launched = c.id, lost.type, nil
            c.ship_granted, c.ship_kind = true, lost.kind
            Court.news(s, Court.full_name(c) .. "'s new flagship is ready.")
        end
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        local class = c.ship and ship_rank(c, c.ship)
        if c.ship and (not wants_ship(s, c) or (class and not fits(class, RANK[rank_key(s, c) or ""]))) then
            Fleet.release(s, c)
        end
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if wants_ship(s, c) and c.ship and not c.ship_launched and not unit_of(c.ship) then
            local home = home_of(s, c)
            if home and pcall(SpawnList, {c.ship}, home, empire, true, false) then
                c.ship_launched, c.ship_paid = true, nil
            end
        end
    end
    local spawned = 0
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        local lore_slot = wants_ship(s, c) and not c.ship and c.lore and lore_ship(c, RANK[rank_key(s, c)])
        if lore_slot and spawned < CONFIG.SHIPS.SPAWN_PER_WEEK and not unit_of(lore_slot) then
            s.ships[lore_slot], c.ship, c.ship_launched = c.id, lore_slot, nil
            local _, _, _, kind = lore_ship(c, RANK[rank_key(s, c)])
            c.ship_granted, c.ship_kind = true, kind
            spawned = spawned + 1
        elseif wants_ship(s, c) and not c.ship and not c.lore then
            do
                local rank = RANK[rank_key(s, c)]
                local waiting, free = nil, nil
                for _, slot in ipairs(pool_of(rank) or {}) do
                    if s.ships[slot] == nil then
                        local unit = unit_of(slot)
                        if unit and unit.Get_Owner() == empire then
                            waiting = waiting or slot
                        elseif not unit then
                            free = free or slot
                        end
                    end
                end
                if waiting then
                    s.ships[waiting], c.ship, c.ship_launched = c.id, waiting, true
                elseif free and spawned < CONFIG.SHIPS.SPAWN_PER_WEEK then
                    local home = home_of(s, c)
                    if home then
                        local ok = pcall(SpawnList, {free}, home, empire, true, false)
                        if ok then
                            s.ships[free], c.ship, c.ship_launched = c.id, free, true
                            spawned = spawned + 1
                        end
                    end
                end
            end
        end
    end
    Fleet.names(s)
end

function Fleet.names(s)
    for slot, id in pairs(s.ships or {}) do
        local c = id and s.chars[id]
        if c and SLOT_RANK[slot] then
            name_ship(slot, Court.full_name(c))
        end
    end
end

local function sent_to_death(s, c)
    local since = c.posted and c.posted.fleet
    if not since or s.week - since > CONFIG.SHIPS.SENT_WEEKS then
        return
    end
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if v.status == "serving" and v ~= c then
            Court.opinion(v, "Sent Courtier to their Death", CONFIG.SHIPS.SENT_OPINION, CONFIG.SHIPS.SENT_FADE)
        end
    end
    Court.news(s, Court.full_name(c) .. " dies days after taking command. The court says the throne sent them to their death.")
end

function Fleet.lost(s, c, slot)
    s.ships[slot] = nil
    local granted, kind = c.ship_granted, c.ship_kind
    c.ship, c.ship_launched, c.ship_paid, c.ship_granted, c.ship_kind = nil, nil, nil, nil, nil
    if c.status ~= "serving" then
        return
    end
    if granted and c.lore and M.chance(CONFIG.SHIPS.ESCAPE) then
        local _, price, weeks = lore_ship(c, ship_rank(c, slot) or RANK[rank_key(s, c) or ""])
        c.ship_lost = {type = slot, price = price or 0, weeks = weeks or 1, kind = kind}
        Court.alert(c.name .. " has escaped the battle. Their flagship is lost.", "request")
        Court.news(s, Court.full_name(c) .. " escapes the wreck of their flagship.")
        return
    end
    sent_to_death(s, c)
    Court.remove(s, c, "dead", "died aboard their flagship")
end

function Fleet.rebuild_blocked(s, c)
    if not c.ship_lost then
        return "Their flagship is not lost."
    end
    if c.rebuild_until then
        return "It is being rebuilt: ready in " .. M.weeks(M.max(0, c.rebuild_until - s.week)) .. "."
    end
    if Court.player().Get_Credits() < c.ship_lost.price then
        return "Needs " .. c.ship_lost.price .. " credits."
    end
    return nil
end

function Fleet.rebuild(s, c)
    local why = Fleet.rebuild_blocked(s, c)
    if why then
        return false, why
    end
    Court.player().Give_Money(-c.ship_lost.price)
    c.rebuild_until = s.week + c.ship_lost.weeks
    return true, "A new " .. Fleet.class(c.ship_lost.type) .. " is laid down for " .. c.name .. ": ready in "
        .. M.weeks(c.ship_lost.weeks) .. " (" .. c.ship_lost.price .. " credits)."
end

function Fleet.on_killed(s, hero_type)
    local slot = string.upper(hero_type or "")
    local c = s.ships and s.ships[slot] and s.chars[s.ships[slot]]
    if not c then
        return SLOT_RANK[slot] ~= nil or string.find(slot, "^COURT_FLAG_") ~= nil
    end
    if c.ship ~= slot then
        s.ships[slot] = nil
        return true
    end
    Fleet.lost(s, c, slot)
    return true
end

return Fleet
