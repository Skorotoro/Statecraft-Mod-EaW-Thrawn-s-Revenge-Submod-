local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Opinions = require("eawx-plugins/diplomacy/DiplomacyOpinions")
local Reputation = require("eawx-plugins/diplomacy/DiplomacyReputation")
require("eawx-plugins/diplomacy/DiplomacyAI")

local Allies = {}

local function popup_text(tag, part, name, tooltip)
    local id = "TEXT_DIPLOMACY_" .. tag .. "_" .. part
    local object = string.gsub(string.lower(tag .. "_" .. part), "(%a)([%w]*)", function(a, b) return string.upper(a) .. b end)
    if name then
        if Engine_Set_Object_Text then
            Engine_Set_Object_Text(object, id, name)
        elseif Engine_Set_Text then
            Engine_Set_Text(id, name)
        end
    end
    if tooltip and Engine_Set_Text then
        Engine_Set_Text(id .. "_TIP", tooltip)
    end
end

local A = CONFIG.ALLIES
local MARKER = "DP_War_Target_Label"

local tasks = {}
local declined = {}
local asked = {}
local calls = {}
local next_steer, next_mark, next_week = 0, 0, 0

Allies.KINDS = {"TARGET", "WORLD", "ESCORT", "STATION"}
Allies.LABEL = {TARGET = "War target", WORLD = "Take a world", ESCORT = "Escort my fleet", STATION = "Station a fleet"}

local function log(text)
    if Engine_Log then
        Engine_Log("ALLIES " .. text)
    end
end

local function player(name)
    local ok, p = pcall(Find_Player, name)
    return ok and p or nil
end

local function weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

local function world_key(planet)
    return string.upper(planet.Get_Type().Get_Name())
end

local function at_war(a, b)
    local pa, pb = player(a), player(b)
    return pa and pb and pa.Is_Enemy(pb)
end

function Allies.bond(d, faction)
    local r = d:relation(faction)
    if r == "VASSAL" then
        return "VASSAL"
    elseif r == "ALLIANCE" or r == "PROTECTORATE" then
        return r
    end
    return nil
end

function Allies.tasks_of(faction)
    return tasks[string.upper(faction)] or {}
end

local unit_icons
local function unit_icon(unit)
    if unit_icons == nil then
        local ok, t = pcall(require, "eawx-plugins/diplomacy/DiplomacyUnitIcons")
        unit_icons = (ok and type(t) == "table") and t or {}
    end
    local ok, name = pcall(function() return unit.Get_Type().Get_Name() end)
    return ok and unit_icons[string.upper(name)] or nil
end

function Allies.fleets(p)
    local order = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(p) or {}) do
        if TestValid(unit) then
            local ok, parent = pcall(unit.Get_Parent_Object)
            if ok and parent and TestValid(parent) and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" then
                local okp, at = pcall(parent.Get_Planet_Location)
                at = okp and at or nil
                local where = at and world_key(at)
                local entry
                for _, f in ipairs(order) do
                    if (where and f.where == where) or (not where and not f.where and pcall(function()
                            if f.fleet ~= parent then error("other") end end)) then
                        entry = f
                        break
                    end
                end
                if not entry then
                    entry = {fleet = parent, size = 0, planet = at, where = where, weight = -1}
                    table.insert(order, entry)
                end
                entry.size = entry.size + 1
                local icon = unit_icon(unit)
                if icon and icon[2] > entry.weight then
                    entry.icon, entry.weight = icon[1], icon[2]
                end
            end
        end
    end
    table.sort(order, function(x, y) return x.size > y.size end)
    return order
end

local function same(a, b)
    return a and b and world_key(a) == world_key(b)
end

local function ships_of(p, fleet)
    local out = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(p) or {}) do
        if TestValid(unit) then
            local ok, parent = pcall(unit.Get_Parent_Object)
            if ok and parent == fleet then
                table.insert(out, unit)
            end
        end
    end
    return out
end

local function hold(t, p)
    t.ships = t.ships or {}
    for _, fleet in ipairs(t.fleets or {}) do
        if TestValid(fleet) then
            for _, unit in ipairs(ships_of(p, fleet)) do
                if not t.held_set then
                    t.held_set = {}
                end
                local id = tostring(unit)
                if not t.held_set[id] then
                    t.held_set[id] = true
                    table.insert(t.ships, unit)
                    pcall(function() unit.Prevent_AI_Usage(true) end)
                end
            end
        end
    end
end

local function release(t)
    for _, unit in ipairs((t and t.ships) or {}) do
        if TestValid(unit) then
            pcall(function() unit.Prevent_AI_Usage(false) end)
        end
    end
    if t then
        t.ships, t.held_set = nil, nil
    end
end

local function fleets_of_ships(t)
    local out, seen = {}, {}
    for _, unit in ipairs((t and t.ships) or {}) do
        if TestValid(unit) then
            local ok, parent = pcall(unit.Get_Parent_Object)
            if ok and parent and TestValid(parent) and not seen[tostring(parent)] then
                local okp, at = pcall(parent.Get_Planet_Location)
                if okp and at then
                    seen[tostring(parent)] = true
                    table.insert(out, parent)
                end
            end
        end
    end
    return out
end

local function ships_alive(t)
    for _, unit in ipairs((t and t.ships) or {}) do
        if TestValid(unit) then
            return true
        end
    end
    return false
end

local function drop(list, kind)
    release(list[kind])
    list[kind] = nil
end

local function steer(fleet, planet)
    if not (planet and TestValid(fleet)) then
        return false
    end
    local ok, at = pcall(fleet.Get_Planet_Location)
    if ok and at and not same(at, planet) then
        pcall(function() fleet.Move_To(planet) end)
    end
    return true
end

local function safe_path(ally, from, to)
    if not (from and to) then
        return nil
    end
    if same(from, to) then
        return {}
    end
    if not Engine_Safe_Path then
        return {world_key(to)}
    end
    local ok, text = pcall(Engine_Safe_Path, ally, world_key(from), world_key(to))
    if not ok or type(text) ~= "string" or text == "" then
        return nil
    end
    local out = {}
    for name in string.gfind(text, "[^;]+") do
        table.insert(out, name)
    end
    return out
end

local function route_fleets(ally, fleets, target)
    local hops, ok_all = {}, true
    for _, f in ipairs(target and fleets or {}) do
        local ok, at = false, nil
        if TestValid(f) then
            ok, at = pcall(f.Get_Planet_Location)
        end
        if ok and at and not same(at, target) then
            local key = world_key(at)
            if hops[key] == nil then
                local path = safe_path(ally, at, target)
                hops[key] = path and path[1] or false
            end
            local hop = hops[key] and FindPlanet(hops[key])
            if hop then
                pcall(function() f.Move_To(hop) end)
            else
                ok_all = false
            end
        end
    end
    return ok_all
end

function Allies.willingness(d, ally, kind, target, world, weeks_asked, follow)
    local factors = {}
    local function add(points, text)
        points = M.round(points or 0)
        if points ~= 0 then
            table.insert(factors, {points, text})
        end
    end
    local bond = Allies.bond(d, ally)
    if not bond then
        return -100, factors, "only your allies and vassals take requests"
    end
    if tasks[ally] and tasks[ally][kind] then
        return -100, factors, "they are already doing one: " .. string.lower(Allies.LABEL[kind])
    end
    local group = (kind == "TARGET") and "TARGET" or "PLACE"
    if group == "PLACE" and tasks[ally] and (tasks[ally].WORLD or tasks[ally].ESCORT or tasks[ally].STATION) then
        return -100, factors, "they are already taking a world, escorting or guarding for you"
    end
    local last = asked[ally .. "|" .. group]
    if last and GetCurrentTime() - last < weeks(A.REQUEST_WEEKS) then
        local left = M.ceil((weeks(A.REQUEST_WEEKS) - (GetCurrentTime() - last)) / CONFIG.WEEK_SECONDS)
        return -100, factors, "you asked them lately: again in " .. left .. " week" .. ((left == 1) and "" or "s")
    end
    if kind == "STATION" and world then
        local planet = FindPlanet(world)
        if not planet or planet.Get_Owner() ~= d.human then
            return -100, factors, "choose a world of yours"
        end
    end
    if kind ~= "ESCORT" and kind ~= "STATION" then
        if not target then
            return -100, factors, "choose a target faction first"
        end
        if not at_war(ally, target) then
            return -100, factors, "they are not at war with " .. d.display_name(target)
                .. " (ask them to join your war in Negotiations)"
        end
    end
    local ally_p = player(ally)
    if table.getn(Allies.fleets(ally_p)) == 0 then
        return -100, factors, "they have no fleet to send"
    end
    if bond == "VASSAL" then
        add(0, "your vassal obeys")
        return 0, factors, nil
    end
    add(A.BASE[kind], "what you ask of them")
    if bond == "PROTECTORATE" then
        add(A.PROTECTORATE, "a protectorate: your wars are not theirs")
    end
    add(Opinions.get(ally, d.human.Get_Faction_Name()), "their opinion of you")
    local ctx = DiplomacyAI.context(d.display_name)
    if kind == "ESCORT" or kind == "STATION" then
        target = nil
    end
    if target then
        add(-Opinions.get(ally, target) / 4, "their opinion of " .. d.display_name(target))
        local ratio = DiplomacyAI.strength(ctx, ally_p) / M.max(1, DiplomacyAI.strength(ctx, player(target)))
        add(M.max(-A.STRENGTH_CAP, M.min(A.STRENGTH_CAP, A.STRENGTH_PER_DOUBLING * M.log2(ratio))),
            "they are " .. string.format("%.1f", ratio) .. "x as strong as " .. d.display_name(target))
    end
    local planet = world and FindPlanet(world)
    if planet then
        local jumps = DiplomacyAI.jumps_to(ctx, ally_p, planet)
        if not jumps then
            return -100, factors, "they have no route to " .. d:planet_name(planet)
        end
        local reach = (kind == "STATION") and A.STATION_REACH or 1
        add(-A.PER_JUMP * A.REACH_WEIGHT * reach * M.max(0, jumps - A.FREE_JUMPS), d:planet_name(planet) .. " is "
            .. jumps .. " jumps from them")
    end
    if kind == "ESCORT" and follow then
        local ok_at, at = pcall(function() return TestValid(follow) and follow.Get_Planet_Location() end)
        local jumps = ok_at and at and DiplomacyAI.jumps_to(ctx, ally_p, at)
        if ok_at and at and not jumps then
            return -100, factors, "they have no route to " .. d:planet_name(at)
        elseif jumps then
            add(-A.PER_JUMP * A.REACH_WEIGHT * M.max(0, jumps - A.FREE_JUMPS), "your fleet is " .. jumps .. " jumps from them")
        end
    end
    local fronts = 0
    for other, _ in pairs(Opinions.world().enemies[ally] or {}) do
        local bd = Opinions.world().borders
        if other ~= target and ((bd[ally .. "|" .. other] or 0) + (bd[other .. "|" .. ally] or 0)) > 0 then
            fronts = fronts + 1
        end
    end
    add(-A.PER_FRONT * fronts, "their other fronts (" .. fronts .. ")")
    if kind == "ESCORT" or kind == "STATION" then
        add(-A.ESCORT_PER_WEEK * M.max(0, (weeks_asked or 4) - 4), "for " .. (weeks_asked or 4) .. " weeks")
    end
    local since = declined[ally .. "|" .. kind]
    if since and GetCurrentTime() - since < weeks(A.ASK_AGAIN_WEEKS) then
        add(-A.ASKED_AGAIN, "you asked lately")
    end
    local total = 0
    for _, f in ipairs(factors) do
        total = total + f[1]
    end
    return total, factors, nil
end

function Allies.join_will(d, faction, target, add)
    faction, target = string.upper(faction), string.upper(target or "")
    local human = string.upper(d.human.Get_Faction_Name())
    if target == "" or target == faction then
        return "choose another power to fight"
    end
    if not at_war(human, target) then
        return "you are not at war with " .. d.display_name(target)
    end
    if at_war(faction, target) then
        return "they are already at war with " .. d.display_name(target)
    end
    local ok, Galaxy = pcall(require, "eawx-plugins/diplomacy/DiplomacyGalaxy")
    local pact = ok and Galaxy.pact(faction, target)
    if pact and pact.kind ~= "CEASEFIRE" then
        return "they are bound to " .. d.display_name(target) .. " by " .. ((pact.kind == "VASSAL") and "vassalage" or "alliance")
    end
    local bond = Allies.bond(d, faction)
    if bond == "VASSAL" then
        add(100, "your vassal obeys")
        return nil
    end
    add(A.JOIN_BASE, "a war is a great thing to ask")
    if bond == "PROTECTORATE" then
        add(A.PROTECTORATE, "a protectorate: your wars are not theirs")
    elseif bond == nil then
        add(A.JOIN_NOT_ALLIED, "they are not your allies")
    end
    add(-Opinions.get(faction, target) / 2, "their opinion of " .. d.display_name(target))
    local ctx = DiplomacyAI.context(d.display_name)
    local ratio = DiplomacyAI.strength(ctx, player(faction)) / M.max(1, DiplomacyAI.strength(ctx, player(target)))
    add(M.max(-A.STRENGTH_CAP, M.min(A.STRENGTH_CAP, A.STRENGTH_PER_DOUBLING * M.log2(ratio))),
        "they are " .. string.format("%.1f", ratio) .. "x as strong as " .. d.display_name(target))
    local bd = Opinions.world().borders
    if ((bd[faction .. "|" .. target] or 0) + (bd[target .. "|" .. faction] or 0)) > 0 then
        add(A.JOIN_BORDER, "they share a border with " .. d.display_name(target))
    else
        add(A.JOIN_NO_BORDER, "they have no border with " .. d.display_name(target))
    end
    local fronts = 0
    for other, _ in pairs(Opinions.world().enemies[faction] or {}) do
        if ((bd[faction .. "|" .. other] or 0) + (bd[other .. "|" .. faction] or 0)) > 0 then
            fronts = fronts + 1
        end
    end
    add(-A.PER_FRONT * fronts, "their other fronts (" .. fronts .. ")")
    if pact then
        local faith = (CONFIG.GALAXY.PERSONALITY[faction] or {}).faith or 0.5
        add(-A.JOIN_BREAK_PEACE * faith, "breaking their peace with " .. d.display_name(target))
    end
    return nil
end

function Allies.join(d, faction, target)
    faction, target = string.upper(faction), string.upper(target)
    local ok, Galaxy = pcall(require, "eawx-plugins/diplomacy/DiplomacyGalaxy")
    if ok and Galaxy.pact(faction, target) then
        Galaxy.end_pact(faction, target)
        Opinions.event(target, faction, "BETRAYED")
    end
    Opinions.force_war(faction, target)
    if ok then
        pcall(Galaxy.call_to_war, d, faction, target)
    end
    Diplomacy.show("Allies: " .. d.display_name(faction) .. " join your war against " .. d.display_name(target) .. ".")
end

local function escort_fleet(d, ally, p, target)
    local found = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(p) or {}) do
        local ok, parent = pcall(function() return TestValid(unit) and unit.Get_Parent_Object() end)
        if ok and parent and TestValid(parent) and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" then
            local okp, at = pcall(parent.Get_Planet_Location)
            if okp and at then
                local entry
                for _, f in ipairs(found) do
                    if same(f.planet, at) then
                        entry = f
                        break
                    end
                end
                if not entry then
                    entry = {fleets = {}, planet = at, power = 0}
                    table.insert(found, entry)
                end
                local known = false
                for _, f in ipairs(entry.fleets) do
                    if f == parent then
                        known = true
                        break
                    end
                end
                if not known then
                    table.insert(entry.fleets, parent)
                end
                local okc, cost = pcall(function() return unit.Get_Type().Get_Build_Cost() end)
                entry.power = entry.power + ((okc and tonumber(cost) or 0) > 0 and cost or 1)
            end
        end
    end
    local ok_t, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    local safe_memo = {}
    local function safe(planet)
        local key = world_key(planet)
        if safe_memo[key] == nil then
            safe_memo[key] = true
            local ok_n, names = false, nil
            if ok_t then
                ok_n, names = pcall(Trade.neighbours, d, planet)
            end
            for _, name in ipairs(ok_n and names or {}) do
                local there = FindPlanet(name)
                local owner = there and string.upper(there.Get_Owner().Get_Faction_Name())
                if owner and at_war(ally, owner) then
                    safe_memo[key] = false
                    break
                end
            end
        end
        return safe_memo[key]
    end
    table.sort(found, function(a, b) return a.power > b.power end)
    local best, best_safe
    for _, f in ipairs(found) do
        if best_safe then
            break
        end
        local wanted = not best or safe(f.planet)
        if wanted and (not target or safe_path(ally, f.planet, target)) then
            best = best or f
            if safe(f.planet) then
                best_safe = f
            end
        end
    end
    if found[1] and not best then
        return nil, "route"
    end
    local pick = best_safe or best
    return pick and pick.fleets or nil
end

local function start(ally, kind, task)
    tasks[ally] = tasks[ally] or {}
    release(tasks[ally][kind])
    task.since = GetCurrentTime()
    task.fleets = task.fleets or {}
    tasks[ally][kind] = task
end

function Allies.stop(ally, kind)
    if tasks[ally] then
        drop(tasks[ally], kind)
    end
end

function Allies.ask(d, ally, kind, target, world, follow, weeks_asked)
    ally = string.upper(ally)
    local total, _, impossible = Allies.willingness(d, ally, kind, target, world, weeks_asked, follow)
    local name = d.display_name(ally)
    if impossible then
        log(ally .. " " .. kind .. ": impossible (" .. impossible .. ")")
        return false, name .. ": " .. impossible .. "."
    end
    asked[ally .. "|" .. ((kind == "TARGET") and "TARGET" or "PLACE")] = GetCurrentTime()
    if total < 0 then
        log(ally .. " " .. kind .. ": declined (" .. total .. ")")
        declined[ally .. "|" .. kind] = GetCurrentTime()
        return false, name .. " decline" .. ((string.sub(name, -1) == "s") and "" or "s") .. " (" .. d.signed(total) .. ")."
    end
    local task = {by = string.upper(d.human.Get_Faction_Name()), faction = target, world = world, follow = follow,
                  follow_ships = follow and ships_of(d.human, follow) or nil}
    task.ends = GetCurrentTime() + weeks((kind == "ESCORT" or kind == "STATION") and (weeks_asked or 4) or A.TASK_WEEKS)
    local escort
    if kind == "ESCORT" or kind == "STATION" then
        local goal
        if kind == "STATION" then
            goal = world and FindPlanet(world)
        elseif TestValid(follow) then
            local ok_g, at = pcall(follow.Get_Planet_Location)
            goal = ok_g and at or nil
        end
        local why
        escort, why = escort_fleet(d, ally, player(ally), goal)
        if not escort and why == "route" then
            log(ally .. " " .. kind .. ": no safe route")
            return false, name .. ": no safe route to " .. ((kind == "STATION") and d:planet_name(goal) or "your fleet")
                .. "."
        elseif not escort then
            return false, name .. ": they have no fleet to send."
        end
    end
    start(ally, kind, task)
    if escort then
        task.fleets = escort
        hold(task, player(ally))
        local ok_at, at = pcall(escort[1].Get_Planet_Location)
        log(ally .. " " .. kind .. ": accepted, sends its fleet at " .. tostring(ok_at and at and world_key(at))
            .. " (" .. table.getn(task.ships or {}) .. " ships)")
    end
    local what = (kind == "TARGET") and ("make war on " .. d.display_name(target))
        or ((kind == "WORLD") and ("take " .. d:planet_name(FindPlanet(world))))
        or ((kind == "STATION") and ("guard " .. d:planet_name(FindPlanet(world)) .. " for " .. (weeks_asked or 4)
            .. " weeks"))
        or ("escort your fleet for " .. (weeks_asked or 4) .. " weeks")
    return true, name .. " agree" .. ((string.sub(name, -1) == "s") and "" or "s") .. " to " .. what .. "."
end

local function strike_world(ally, target)
    local world = Opinions.world()
    local routes = Opinions.routes()
    for planet, owner in pairs(world.owner) do
        if owner == target then
            for other in string.gfind(routes[planet] or "", "%S+") do
                if world.owner[other] == ally and FindPlanet(planet) then
                    return planet
                end
            end
        end
    end
    for planet, owner in pairs(world.owner) do
        if owner == target and FindPlanet(planet) then
            return planet
        end
    end
    return nil
end

local function strike_fleets(ally_p, n)
    local list = {}
    for _, f in ipairs(Allies.fleets(ally_p)) do
        if f.planet and f.size >= A.MIN_FLEET then
            table.insert(list, f)
        end
    end
    if not list[1] then
        list = Allies.fleets(ally_p)
    end
    local out = {}
    for i, f in ipairs(list) do
        if table.getn(list) == 1 or i > 1 or table.getn(out) < n - 1 then
            table.insert(out, f.fleet)
        end
        if table.getn(out) >= n then
            break
        end
    end
    return out
end

local function valid_fleets(list)
    local out = {}
    for _, f in ipairs(list or {}) do
        if TestValid(f) then
            table.insert(out, f)
        end
    end
    return out
end

local function heading_to(d, fleet, memo)
    local ok, x, y = pcall(function()
        local a, b = fleet.Get_Position().Get_XYZ()
        return a, b
    end)
    if not ok or not x then
        return nil
    end
    local px, py = memo.x, memo.y
    memo.x, memo.y = x, y
    local ok_at, at = pcall(fleet.Get_Planet_Location)
    if ok_at and at then
        memo.from = at
    end
    if not px or (px == x and py == y) then
        return nil
    end
    local vx, vy = x - px, y - py
    local from = memo.from
    local ok_f, fx, fy = false, nil, nil
    if from then
        ok_f, fx, fy = pcall(function()
            local a, b = from.Get_Position().Get_XYZ()
            return a, b
        end)
    end
    if not ok_f or not fx then
        return nil
    end
    local ok_t, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    local names = from and ok_t and Trade.neighbours(d, from)
    local best, best_score = nil, nil
    for _, name in ipairs(names or {}) do
        local there = FindPlanet(name)
        local ok_p, wx, wy = false, nil, nil
        if there then
            ok_p, wx, wy = pcall(function()
                local a, b = there.Get_Position().Get_XYZ()
                return a, b
            end)
        end
        if ok_p and wx then
            local lx, ly = wx - fx, wy - fy
            local len2 = lx * lx + ly * ly
            local dot = vx * lx + vy * ly
            local score = (dot > 0 and len2 > 1) and dot * dot / (len2 * (vx * vx + vy * vy) + 0.0001) or 0
            local along = len2 > 1 and ((x - fx) * lx + (y - fy) * ly) / len2 or -1
            local ox, oy = (x - fx) - along * lx, (y - fy) - along * ly
            local slack = 0.02 * math.sqrt(len2) + 3
            if score > 0.99 and along >= -0.01 and along <= 1.01 and ox * ox + oy * oy <= slack * slack
                and (not best_score or score > best_score) then
                best, best_score = there, score
            end
        end
    end
    return best
end

local function steer_escorts(d)
    for ally, list in pairs(tasks) do
        local t = list.ESCORT
        local ally_p = t and player(ally)
        if t and not ally_p then
            drop(list, "ESCORT")
        elseif t then
            if not TestValid(t.follow) then
                t.follow = nil
                for _, unit in ipairs(t.follow_ships or {}) do
                    local ok, parent = pcall(function() return TestValid(unit) and unit.Get_Parent_Object() end)
                    if ok and parent and TestValid(parent) then
                        t.follow = parent
                        break
                    end
                end
            end
            if TestValid(t.follow) and GetCurrentTime() >= (t.next_ships or 0) then
                t.next_ships = GetCurrentTime() + A.STEER_SECONDS
                local now_ships = ships_of(d.human, t.follow)
                if now_ships[1] then
                    t.follow_ships = now_ships
                end
            end
            if not TestValid(t.follow) then
                drop(list, "ESCORT")
                log(ally .. " ESCORT: the escorted fleet is gone")
                if t.by == string.upper(d.human.Get_Faction_Name()) and Diplomacy and Diplomacy.show then
                    Diplomacy.show("Allies: the fleet " .. d.display_name(ally) .. " escorted is lost. Their escort "
                        .. "ends.")
                end
            else
                local lost = false
                if ships_alive(t) then
                    t.fleets = fleets_of_ships(t)
                else
                    release(t)
                    local ok_f, at_f = pcall(t.follow.Get_Planet_Location)
                    local best = escort_fleet(d, ally, ally_p, ok_f and at_f or nil)
                    t.fleets = best or {}
                    hold(t, ally_p)
                    if not best then
                        lost = true
                        drop(list, "ESCORT")
                        if t.by == string.upper(d.human.Get_Faction_Name()) and Diplomacy and Diplomacy.show then
                            Diplomacy.show("Allies: " .. d.display_name(ally) .. " lost the escort and have no fleet "
                                .. "left to send.")
                        end
                    end
                end
                t.memo = t.memo or {}
                local goal = heading_to(d, t.follow, t.memo)
                if goal then
                    t.goal = goal
                end
                local ok, at = pcall(t.follow.Get_Planet_Location)
                local target = not lost and (t.goal or (ok and at)) or nil
                if t.goal and ok and at and same(at, t.goal) then
                    t.goal = nil
                end
                if target and (not same(t.sent, target) or not t.sent_at
                               or GetCurrentTime() - t.sent_at >= A.STEER_SECONDS) then
                    local routed = route_fleets(ally, t.fleets, target)
                    if not routed and not t.no_route then
                        log(ally .. " ESCORT: no safe route to " .. world_key(target) .. "; the escort waits")
                    end
                    t.no_route = not routed
                end
                if target and not same(t.sent, target) then
                    log(ally .. " ESCORT: sent to " .. world_key(target) .. (t.goal and " (your fleet is on its way there)"
                        or ""))
                    t.sent, t.sent_at = target, GetCurrentTime()
                end
            end
        end
    end
end

local function steer_all(d)
    for ally, list in pairs(tasks) do
        local ally_p = player(ally)
        for kind, t in pairs(list) do
            if not ally_p then
                drop(list, kind)
            elseif kind == "ESCORT" then
            elseif kind == "STATION" then
                local planet = t.world and FindPlanet(t.world)
                if not planet or planet.Get_Owner() ~= d.human then
                    drop(list, kind)
                    if Diplomacy and Diplomacy.show then
                        Diplomacy.show("Allies: " .. d.display_name(ally) .. "'s fleet no longer guards "
                            .. (planet and d:planet_name(planet) or "your world") .. ": it is not yours any more.")
                    end
                else
                    if ships_alive(t) then
                        t.fleets = fleets_of_ships(t)
                    else
                        release(t)
                        local best = escort_fleet(d, ally, ally_p, planet)
                        t.fleets = best or {}
                        hold(t, ally_p)
                        if not best then
                            drop(list, kind)
                            if t.by == string.upper(d.human.Get_Faction_Name()) and Diplomacy and Diplomacy.show then
                                Diplomacy.show("Allies: " .. d.display_name(ally) .. " lost the fleet guarding "
                                    .. d:planet_name(planet) .. " and have none left to send.")
                            end
                        end
                    end
                    if list[kind] then
                        route_fleets(ally, t.fleets, planet)
                    end
                end
            else
                local target_world = t.world
                if kind == "TARGET" then
                    local cur = t.current and FindPlanet(t.current)
                    if not cur or string.upper(cur.Get_Owner().Get_Faction_Name()) ~= t.faction then
                        t.current = strike_world(ally, t.faction)
                        release(t)
                        t.fleets = {}
                        if not t.current then
                            drop(list, kind)
                        end
                    end
                    target_world = t.current
                end
                local planet = target_world and FindPlanet(target_world)
                if not planet then
                    if kind == "WORLD" then
                        drop(list, kind)
                    end
                else
                    local owner = string.upper(planet.Get_Owner().Get_Faction_Name())
                    if kind == "WORLD" and owner ~= t.faction then
                        drop(list, kind)
                        if Diplomacy and Diplomacy.show then
                            Diplomacy.show("Allies: " .. d.display_name(ally) .. "'s campaign against "
                                .. d:planet_name(planet) .. " is over (" .. d.display_name(owner) .. " holds it).")
                        end
                    else
                        if ships_alive(t) then
                            t.fleets = fleets_of_ships(t)
                        else
                            release(t)
                            t.fleets = strike_fleets(ally_p, A.STRIKE_FLEETS)
                            hold(t, ally_p)
                        end
                        for _, f in ipairs(t.fleets) do
                            steer(f, planet)
                        end
                    end
                end
            end
        end
    end
end

local function marked(d)
    local out = {}
    local human = string.upper(d.human.Get_Faction_Name())
    for _, list in pairs(tasks) do
        for kind, t in pairs(list) do
            if t.by == human then
                local w = (kind == "WORLD") and t.world or ((kind == "TARGET") and t.current)
                if w then
                    out[w] = true
                end
            end
        end
    end
    return out
end

local function mark(d)
    for w, _ in pairs(marked(d)) do
        local planet = FindPlanet(w)
        if planet then
            pcall(planet.Attach_Particle_Effect, MARKER)
        end
    end
end

local function ai_requests(d)
    local ok, Galaxy = pcall(require, "eawx-plugins/diplomacy/DiplomacyGalaxy")
    if not ok then
        return
    end
    local busy = 0
    for _, list in pairs(tasks) do
        for _, t in pairs(list) do
            if t.by ~= string.upper(d.human.Get_Faction_Name()) then
                busy = busy + 1
            end
        end
    end
    for _, pair_ in ipairs(Galaxy.bonds()) do
        if busy >= A.AI_TASKS_MAX then
            return
        end
        local leader, follower, kind = pair_.leader, pair_.follower, pair_.kind
        if not (tasks[follower] and tasks[follower].TARGET) and GameRandom.Free_Random(1, 100) <= A.AI_ASK_CHANCE then
            for enemy, _ in pairs(Opinions.world().enemies[leader] or {}) do
                if at_war(follower, enemy) and enemy ~= string.upper(d.human.Get_Faction_Name()) then
                    local will = (kind == "VASSAL") and 100 or (Opinions.get(follower, leader) / 2 - 10)
                    if will >= 0 then
                        start(follower, "TARGET", {by = leader, faction = enemy, ends = GetCurrentTime() + weeks(A.TASK_WEEKS)})
                        busy = busy + 1
                    end
                    break
                end
            end
        end
    end
end

local function borders(d, a, b)
    local pa, pb = Find_Player(a), Find_Player(b)
    local ok_t, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    if not (pa and pb and ok_t and Trade) then
        return true
    end
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == pa then
            for _, other in ipairs(Trade.neighbours(d, planet) or {}) do
                local there = FindPlanet(other)
                if there and there.Get_Owner() == pb then
                    return true
                end
            end
        end
    end
    return false
end

local function ai_calls(d)
    if calls[1] or GlobalValue.Get("POPUP_ACTIVE") ~= nil then
        return
    end
    local ok, Galaxy = pcall(require, "eawx-plugins/diplomacy/DiplomacyGalaxy")
    local human = string.upper(d.human.Get_Faction_Name())
    for faction, _ in pairs(Opinions.world().powers) do
        if d:relation(faction) == "ALLIANCE" and GameRandom.Free_Random(1, 100) <= A.CALL_CHANCE then
            for enemy, _ in pairs(Opinions.world().enemies[faction] or {}) do
                local defensive = ok and Galaxy.attacked_by and Galaxy.attacked_by(faction, enemy)
                local near = defensive or borders(d, faction, enemy) or GameRandom.Free_Random(1, 100) <= (A.CALL_FAR_CHANCE or 10)
                if enemy ~= human and not at_war(human, enemy) and Opinions.world().powers[enemy] and near then
                    table.insert(calls, {ally = faction, target = enemy, defensive = defensive})
                    Allies.show_call(d)
                    return
                end
            end
        end
    end
end

function Allies.show_call(d)
    local c = calls[1]
    if not c or not Engine_Set_Text then
        return
    end
    local ally, target = d.display_name(c.ally), d.display_name(c.target)
    popup_text("ALLY_CALL", "HEADER", c.defensive and "An ally under attack" or "An ally asks for help")
    popup_text("ALLY_CALL", "BODY", ally .. (c.defensive and (" was attacked by " .. target
        .. " and calls on you to stand by your alliance.") or (" asks you to join its war against " .. target .. ".")))
    popup_text("ALLY_CALL", "BODY", nil, c.defensive and ("Refusing breaks the alliance and costs "
        .. "reputation.") or "Refusing costs some of their goodwill.")
    popup_text("ALLY_CALL", "ACCEPT", "Declare war on " .. target)
    popup_text("ALLY_CALL", "ACCEPT", nil, "Your war begins at once.")
    popup_text("ALLY_CALL", "REFUSE", "Refuse")
    popup_text("ALLY_CALL", "REFUSE", nil, c.defensive and "The alliance ends; your reputation suffers."
        or "They will remember it.")
    local ok, err = pcall(GenericPopup, "ALLY_CALL", {"ACCEPT", "REFUSE"}, "ALLY_CALL_OPTION")
    if not ok and d.report_error then
        d.report_error("ALLY CALL", err)
        calls = {}
    end
end

function Allies.on_call(d, option)
    local c = table.remove(calls, 1)
    if not c then
        return
    end
    local human = string.upper(d.human.Get_Faction_Name())
    local ally, target = d.display_name(c.ally), d.display_name(c.target)
    if string.find(string.upper(option or ""), "ACCEPT") then
        local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
        local declared, message = Deals.declare_war(d, c.target, false, c.defensive)
        Diplomacy.show("Allies: " .. (message or ("You join " .. ally .. "'s war against " .. target .. ".")))
        if declared then
            Opinions.add(c.ally, human, A.ANSWERED_OPINION, 26, "answered their call to war")
        end
    elseif c.defensive then
        d:set_relation(c.ally, "CEASEFIRE", nil, true)
        d:reputation_drop(human, 1, "abandoned " .. ally .. " when it was attacked")
        Opinions.event(c.ally, human, "ABANDONED")
        Diplomacy.show("Allies: you refused " .. ally .. "'s call. Your alliance is broken.")
    else
        Opinions.add(c.ally, human, A.REFUSED_OPINION, 20, "refused their call to war")
        Diplomacy.show("Allies: you refused " .. ally .. "'s call to war. They will remember it.")
    end
end

local NAMES_PER_UPDATE, NAMES_FROM, ROUTE_SECONDS, ROUTE_SPY_TIER = 20, 30, 1, 3
local bonds_sent, lane_worlds, lane_at, lanes_done = nil, nil, 1, false
local route_list, next_route = "", 0

local function spy_tier(d, faction)
    local r = d.republic and d.republic.intel
    if r and r.spy then
        return (r.spy[faction] or {}).tier or 0
    end
    if string.upper(d.human.Get_Faction_Name()) == "EMPIRE" and type(IMPERIAL_COURT) == "table" and IMPERIAL_COURT.spy then
        return (IMPERIAL_COURT.spy[faction] or {}).tier or 0
    end
    return 0
end

local function publish_bonds(d)
    if not Engine_Border_Bonds then
        return
    end
    local human = string.upper(d.human.Get_Faction_Name())
    local seen, list = {}, {}
    local function add(a, b)
        if a and b and a ~= b and not seen[a .. "|" .. b] and not seen[b .. "|" .. a] then
            seen[a .. "|" .. b] = true
            table.insert(list, a .. "|" .. b)
        end
    end
    local shown = {}
    for faction, _ in pairs(Opinions.world().powers) do
        if Allies.bond(d, faction) then
            add(human, faction)
            table.insert(shown, faction)
        elseif faction ~= human and spy_tier(d, faction) >= ROUTE_SPY_TIER then
            table.insert(shown, faction)
        end
    end
    route_list = table.concat(shown, ";")
    local ok, Galaxy = pcall(require, "eawx-plugins/diplomacy/DiplomacyGalaxy")
    for _, b in ipairs(ok and Galaxy.bonds() or {}) do
        add(b.leader, b.follower)
    end
    table.sort(list)
    local text = table.concat(list, ";")
    if text ~= bonds_sent then
        bonds_sent = text
        pcall(Engine_Border_Bonds, text)
    end
end

local function sweep_lanes(d)
    local now = GetCurrentTime()
    if Engine_Route_Lanes and now >= next_route then
        next_route = now + ROUTE_SECONDS
        pcall(Engine_Route_Lanes, route_list)
    end
    if lanes_done or now < NAMES_FROM then
        return
    end
    if not lane_worlds then
        local ok, all = pcall(FindPlanet.Get_All_Planets)
        lane_worlds, lane_at = {}, 1
        for _, planet in pairs(ok and all or {}) do
            table.insert(lane_worlds, planet)
        end
    end
    for _ = 1, NAMES_PER_UPDATE do
        local planet = lane_worlds[lane_at]
        if not planet then
            lanes_done = true
            return
        end
        GlobalValue.Set("DP_WORLD_" .. world_key(planet), d:planet_name(planet))
        lane_at = lane_at + 1
    end
end

function Allies.update(d)
    if not A.ON then
        return
    end
    local now = GetCurrentTime()
    pcall(steer_escorts, d)
    pcall(sweep_lanes, d)
    if now >= next_steer then
        next_steer = now + A.STEER_SECONDS
        steer_all(d)
    end
    if now >= next_mark then
        next_mark = now + A.MARK_SECONDS
        mark(d)
        pcall(publish_bonds, d)
    end
    if now < next_week then
        return
    end
    next_week = now + CONFIG.WEEK_SECONDS
    for ally, list in pairs(tasks) do
        for kind, t in pairs(list) do
            if t.ends and now >= t.ends then
                drop(list, kind)
                if t.by == string.upper(d.human.Get_Faction_Name()) then
                    Diplomacy.show("Allies: " .. d.display_name(ally) .. "'s " .. string.lower(Allies.LABEL[kind])
                        .. " has run its course.")
                end
            end
        end
    end
    ai_requests(d)
    ai_calls(d)
end

function Allies.on_battle_end(d)
    local where = Engine_Battle_Planet and Engine_Battle_Planet()
    if not where then
        return
    end
    local human = string.upper(d.human.Get_Faction_Name())
    for ally, list in pairs(tasks) do
        for _, kind in ipairs({"ESCORT", "STATION"}) do
            local t = list[kind]
            for _, f in ipairs(t and valid_fleets(t.fleets) or {}) do
                local ok, at = pcall(f.Get_Planet_Location)
                if ok and at and world_key(at) == string.upper(where) then
                    Opinions.event(ally, human, "FOUGHT_BESIDE")
                    Opinions.event(human, ally, "FOUGHT_BESIDE")
                    break
                end
            end
        end
    end
end

function Allies.plans(faction)
    local out = {}
    for ally, list in pairs(tasks) do
        for kind, t in pairs(list) do
            if ally == faction or t.by == faction then
                table.insert(out, {ally = ally, kind = kind, by = t.by, faction = t.faction, world = t.world or t.current})
            end
        end
    end
    return out
end

Allies.heading_to = heading_to

return Allies
