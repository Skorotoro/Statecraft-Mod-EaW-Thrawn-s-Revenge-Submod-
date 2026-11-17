local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")

local Field = {}
local MILITIA = "New_Republic_Defense_Trooper_Company"
local MILITIA_WEEKS = 10
local GONE_SECONDS = 12
local FLEETS = {}

function Field.attach(Order)
    local function draw_craft()
        local year = Order.year_now()
        local pool, total = {}, 0
        for _, c in ipairs(J.CRAFTS) do
            if year >= c[3] then
                local w = (c[1] == "Z95" and year < 9) and J.Z95_EARLY or c[2]
                table.insert(pool, {c[1], w})
                total = total + w
            end
        end
        local roll = GameRandom.Free_Random(1, M.max(1, total))
        for _, e in ipairs(pool) do
            roll = roll - e[2]
            if roll <= 0 then
                return e[1]
            end
        end
        return "XWING"
    end

    function Order.ensure_craft(s, p)
        if p.kind == "hero" and J.HERO_CRAFT[p.key] then
            p.craft = J.HERO_CRAFT[p.key]
            return
        end
        if p.craft or p.rank < J.PADAWAN then
            return
        end
        p.craft = draw_craft()
    end

    function Order.craft_name(p)
        for _, c in ipairs(J.CRAFTS) do
            if c[1] == p.craft then
                return c[4]
            end
        end
        return (J.HERO_CRAFT_NAME or {})[p.craft] or "starfighter"
    end

    function Order.fighter_type(s, p, commander)
        local level = commander and "_C" or ((Order.learned(s, "GUARDIAN", 2) and "_TT") or (Order.learned(s, "GUARDIAN", 1) and "_T") or "")
        if (J.HERO_CRAFT_NAME or {})[p.craft] then
            return "Jedi_Fighter_" .. p.craft .. level
        end
        local rank = (p.rank >= J.MASTER) and "M" or ((p.rank >= J.KNIGHT) and "K" or "P")
        if commander and rank == "P" then
            rank = "K"
        end
        return "Jedi_Fighter_" .. (p.craft or "XWING") .. "_" .. rank .. level
    end

    function Order.ground_type(s, p)
        if p.kind == "hero" then
            local entry = Order.HERO[p.key]
            return entry and entry.units[1]
        end
        return "Jedi_Order_" .. Order.rank_kind(p) .. Order.teaching_level(s)
    end

    local function temple_object(d)
        local t = Find_First_Object("Jedi_Temple")
        return TestValid(t) and t or nil
    end

    local function at_home(p)
        return not (p.mission or p.along_of or p.command)
    end

    local function spawn_hero(d, entry)
        local team = nil
        for _, name in ipairs(entry.units) do
            if string.find(name, "TEAM", 1, true) then
                team = name
            end
        end
        local planet = nil
        local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
        planet = ok and Deals and Deals.capital(d, d.human) or nil
        if not planet then
            local w = U.worlds_of(d.human)[1]
            planet = w and w.planet
        end
        if team and planet and Find_Object_Type(team) then
            pcall(SpawnList, {team}, planet, d.human, true, false)
        end
    end

    function Order.destroy(d, s)
        local dead, hidden, survived = {}, {}, {}
        for _, p in ipairs(s.roster) do
            if at_home(p) then
                local struck = p.temple_down and s.week - p.temple_down <= 1
                if (p.key == "LUKE" or p.key == "KYLE") and not struck then
                    table.insert(survived, p.name)
                    spawn_hero(d, Order.HERO[p.key])
                elseif Order.relic_flag and Order.relic_flag(s, "temple_guard") then
                    table.insert(hidden, Order.label(p))
                else
                    table.insert(dead, Order.label(p))
                end
            else
                Order.drop_unit(d, s, p)
                table.insert(hidden, Order.label(p))
            end
        end
        local r = d.republic
        r.jedi_founded, r.jedi_destroyed, r.jedi = false, true, nil
        GlobalValue.Set("JEDI_PARTIES", "")
        GlobalValue.Set("JEDI_TEMPLE", "")
        local lines = {"The Jedi Temple has fallen. Its halls burn, and the Order Luke Skywalker rebuilt is broken.", ""}
        if dead[1] then
            table.insert(lines, "Dead in its defence: " .. Order.names_of(dead) .. ".")
        end
        if survived[1] then
            table.insert(lines, Order.names_of(survived) .. ((table.getn(survived) == 1) and " escapes" or " escape")
                .. " the ruin, and fights on.")
        end
        if hidden[1] then
            table.insert(lines, "Away from the Temple, " .. Order.names_of(hidden) .. " go into hiding. They will not "
                .. "be seen again in this war.")
        end
        d.show("Jedi Order: the Jedi Temple has fallen. The Order is destroyed.", nil, Order.WARN, 40)
        pcall(M.show_document, lines, "The Fall of the Temple", "The Jedi Order is no more.")
    end

    local function temple_watch(d, s)
        local t = temple_object(d)
        local planet = t and Order.planet_of(t)
        local ok_owner = planet and planet.Get_Owner() == d.human
        if ok_owner then
            s.temple_world, s.temple_gone = U.key(planet), nil
        elseif s.temple_world then
            s.temple_gone = s.temple_gone or GetCurrentTime()
            if GetCurrentTime() - s.temple_gone >= GONE_SECONDS then
                Order.destroy(d, s)
                return true
            end
        end
        return false
    end

    local published = {}
    local function publish(name, value)
        if published[name] ~= value then
            published[name] = value
            GlobalValue.Set(name, value)
        end
    end

    local function party_of(s, p)
        local out = {p}
        for _, id in ipairs((p.mission and p.mission.along) or {}) do
            local st = Order.get(s, id)
            if st then
                table.insert(out, st)
            end
        end
        return out
    end

    local function lists(d, s)
        local lines = {}
        for _, p in ipairs(Order.running(s)) do
            local world = Order.location(d, p)
            if world and p.mission.unit then
                local types, ids = {}, {}
                for _, q in ipairs(party_of(s, p)) do
                    Order.ensure_craft(s, q)
                    if q.craft then
                        table.insert(types, Order.fighter_type(s, q))
                        table.insert(ids, q.id)
                    end
                end
                if types[1] then
                    table.insert(lines, world .. "|" .. table.concat(types, ",") .. "|" .. table.concat(ids, ","))
                end
            end
        end
        for _, p in ipairs(s.roster) do
            if p.command and p.command.world then
                Order.ensure_craft(s, p)
                table.insert(lines, p.command.world .. "|" .. Order.fighter_type(s, p, true) .. "|" .. p.id)
            end
        end
        publish("JEDI_PARTIES", table.concat(lines, ";"))
        local types, ids = {}, {}
        for _, p in ipairs(s.roster) do
            local t = at_home(p) and Order.ground_type(s, p)
            if t then
                table.insert(types, t)
                table.insert(ids, p.id)
            end
        end
        publish("JEDI_TEMPLE", (s.temple_world and types[1]) and (s.temple_world .. "|" .. table.concat(types, ",") .. "|"
            .. table.concat(ids, ",")) or "")
    end

    local function downs(d, s)
        local raw = GlobalValue.Get("JEDI_DOWN")
        if type(raw) ~= "string" or raw == "" then
            return
        end
        GlobalValue.Set("JEDI_DOWN", "")
        local where = GlobalValue.Get("JEDI_DOWN_WORLD")
        where = Order.world_name(d, (type(where) == "string") and where or nil)
        local leaders = {}
        for id in string.gfind(raw, "(%d+)") do
            local p = Order.get(s, tonumber(id))
            if p then
                local leader = p.along_of and Order.get(s, p.along_of) or p
                if leader.mission then
                    leader.mission.down = leader.mission.down or {}
                    leader.mission.down[p.id] = true
                    leaders[leader.id] = leader
                elseif p.command then
                    p.command, FLEETS[p.id] = nil, nil
                    if U.chance(J.DOWN_DEATH) then
                        Order.kill(d, s, p, "shot down over " .. where .. ", flying with the fleet.")
                    else
                        Order.wound(s, p)
                        Order.say(d, s, Order.label(p) .. " was shot down over " .. where .. " and ejected: wounded, "
                            .. "they make their way home.", Order.WARN)
                    end
                else
                    p.temple_down = s.week
                    Order.wound(s, p)
                    Order.say(d, s, Order.label(p) .. " fell defending the Temple, wounded but alive.", Order.WARN)
                end
            end
        end
        for _, leader in pairs(leaders) do
            local m = leader.mission
            local party = party_of(s, leader)
            local all = true
            for _, q in ipairs(party) do
                all = all and m.down[q.id] == true
            end
            if all then
                Order.party_lost(d, s, leader, "over " .. where .. ", every craft of " .. Order.label(leader) .. "'s party "
                    .. "was shot down.")
            else
                for _, q in ipairs(party) do
                    if m.down[q.id] then
                        Order.wound(s, q)
                        Order.say(d, s, Order.label(q) .. " was shot down over " .. where .. " and ejected, wounded.",
                            Order.WARN)
                    end
                end
                if m.down[leader.id] and m.stage ~= "back" then
                    m.stage, m.steered = "back", nil
                    Order.say(d, s, Order.label(leader) .. "'s party gives up the mission and turns for home.", Order.WARN)
                end
                m.down = nil
            end
        end
    end

    local function fleet_at(d, planet)
        for _, obj in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
            if TestValid(obj) and (obj.Is_Category("Capital") or obj.Is_Category("Frigate") or obj.Is_Category("Corvette")) then
                local fleet = Order.fleet_of(obj)
                if fleet and Order.planet_of(fleet) == planet then
                    return fleet
                end
            end
        end
        return nil
    end

    function Order.fleet_worlds(d)
        local out, seen = {}, {}
        for _, obj in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
            if TestValid(obj) and (obj.Is_Category("Capital") or obj.Is_Category("Frigate")) then
                local fleet = Order.fleet_of(obj)
                local planet = fleet and Order.planet_of(fleet)
                if planet and not seen[U.key(planet)] then
                    seen[U.key(planet)] = true
                    table.insert(out, {key = U.key(planet), planet = planet})
                end
            end
        end
        table.sort(out, function(a, b) return d:planet_name(a.planet) < d:planet_name(b.planet) end)
        return out
    end

    function Order.command_blocked(d, s, p)
        if not Order.learned(s, "GUARDIAN", 3) then
            return "Needs Jedi Commanders (Teachings)."
        elseif p.rank < J.KNIGHT then
            return "Only Knights and Masters command."
        end
        return Order.busy(d, s, p)
    end

    function Order.attach_fleet(d, s, p, world)
        local why = Order.command_blocked(d, s, p)
        if why then
            return why
        end
        local planet = FindPlanet(world)
        local fleet = planet and fleet_at(d, planet)
        if not fleet then
            return "No fleet of the Republic's is at " .. Order.world_name(d, world) .. " now."
        end
        Order.ensure_craft(s, p)
        p.command, FLEETS[p.id] = {world = world, since = s.week}, fleet
        local text = Order.label(p) .. " flies their " .. Order.craft_name(p) .. " to the fleet at " .. Order.world_name(d, world)
            .. ", and will fight beside it."
        Order.news(s, text)
        return text
    end

    function Order.recall_fleet(d, s, p)
        p.command, FLEETS[p.id] = nil, nil
        p.home_since = s.week
        return Order.label(p) .. " leaves the fleet and returns to the Temple."
    end

    local function commanders(d, s)
        for _, p in ipairs(s.roster) do
            local c = p.command
            if c then
                local fleet = FLEETS[p.id]
                if not (fleet and TestValid(fleet)) then
                    local planet = FindPlanet(c.world)
                    fleet = planet and fleet_at(d, planet)
                    FLEETS[p.id] = fleet
                end
                if fleet and TestValid(fleet) then
                    c.lost = nil
                    local planet = Order.planet_of(fleet)
                    if planet then
                        c.world = U.key(planet)
                    end
                else
                    c.lost = c.lost or GetCurrentTime()
                    if GetCurrentTime() - c.lost > 30 then
                        p.command, FLEETS[p.id] = nil, nil
                        if U.chance(J.DOWN_DEATH) then
                            Order.kill(d, s, p, "lost with the fleet at " .. Order.world_name(d, c.world) .. ".")
                        else
                            Order.wound(s, p)
                            Order.say(d, s, "The fleet " .. Order.label(p) .. " served with is gone; they survive, wounded, "
                                .. "and make their way home.", Order.WARN)
                        end
                    end
                end
            end
        end
    end

    local last_shield = 0
    local function shield(d, s)
        if not Order.learned(s, "GUARDIAN", 2) or GetCurrentTime() - last_shield < 5 then
            return
        end
        last_shield = GetCurrentTime()
        s.shield = s.shield or {}
        local battle = Engine_Battle_Planet and Engine_Battle_Planet()
        for _, p in ipairs(Order.running(s)) do
            local world = Order.location(d, p)
            local planet = world and FindPlanet(world)
            if planet and planet.Get_Owner() == d.human and s.week - (s.shield[world] or -100) >= MILITIA_WEEKS
                    and not (battle and string.upper(tostring(battle)) == world) then
                local threatened = false
                for faction, rel in pairs(d.relations or {}) do
                    local other = rel == "WAR" and not threatened and Find_Player(faction)
                    if other and U.strength_at(other, planet) > 0 then
                        threatened = true
                    end
                end
                if threatened and Find_Object_Type(MILITIA) then
                    s.shield[world] = s.week
                    for _ = 1, 2 do
                        pcall(Spawn_Unit, Find_Object_Type(MILITIA), planet, d.human)
                    end
                    Order.say(d, s, Order.label(p) .. " rallies " .. d:planet_name(planet) .. ": its militia stands against "
                        .. "the enemy fleet.")
                end
            end
        end
    end

    local last_tick = -100
    function Order.field_tick(d, s)
        Order.last_d, Order.last_s = d, s
        if GetCurrentTime() - last_tick < 1 then
            return
        end
        last_tick = GetCurrentTime()
        if temple_watch(d, s) then
            return
        end
        for _, p in ipairs(s.roster) do
            Order.ensure_craft(s, p)
        end
        downs(d, s)
        commanders(d, s)
        shield(d, s)
        lists(d, s)
    end
end

return Field
