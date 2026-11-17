local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Opinions = require("eawx-plugins/diplomacy/DiplomacyOpinions")

local Joint = {}
local J = CONFIG.JOINT
local COLOR = {r = 150, g = 210, b = 255}
local WARN = {r = 255, g = 170, b = 90}
local TARGET_LABEL, BASE_LABEL = "DP_Invasion_Target_Label", "DP_Invasion_Base_Label"
local next_steer, next_mark, next_week, next_pull = 0, 0, 0, 0
local PULL_SECONDS = 2

local function weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

local function player(name)
    local ok, p = pcall(Find_Player, name)
    return ok and p or nil
end

local function key(planet)
    return string.upper(planet.Get_Type().Get_Name())
end

local function owner_of(world)
    local planet = FindPlanet(world)
    return planet and string.upper(planet.Get_Owner().Get_Faction_Name()) or nil
end

local function state(d)
    d.joint = d.joint or {next_ask = {}}
    d.joint.next_ask = d.joint.next_ask or {}
    return d.joint
end

local function part(name)
    local ok, mod = pcall(require, "eawx-plugins/diplomacy/" .. name)
    return ok and type(mod) == "table" and mod or nil
end

local function popup_text(part_name, name, tooltip)
    local id = "TEXT_DIPLOMACY_JOINT_" .. part_name
    local object = "Joint_" .. string.upper(string.sub(part_name, 1, 1)) .. string.lower(string.sub(part_name, 2))
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

local function asking_allies(d)
    local Worlds = part("DiplomacyWorlds")
    local out = {}
    for faction, relation in pairs(d.relations or {}) do
        if relation == "ALLIANCE" and not (Worlds and Worlds.is_slot and Worlds.is_slot(faction)) and player(faction) then
            table.insert(out, faction)
        end
    end
    return out
end

local function candidates(d, ally)
    local Trade, Deals = part("DiplomacyTrade"), part("DiplomacyDeals")
    local pa = player(ally)
    if not (Trade and Deals and pa) then
        return {}
    end
    local out = {}
    for _, planet in ipairs(Deals.worlds_of(pa)) do
        for _, other in ipairs(Trade.neighbours(d, planet) or {}) do
            local owner = owner_of(other)
            local po = owner and player(owner)
            if po and owner ~= "INDEPENDENT_FORCES" and owner ~= "NEUTRAL" and d:relation(owner) == "WAR"
                    and pa.Is_Enemy(po) and owner ~= ally then
                table.insert(out, {base = key(planet), target = other, enemy = owner})
            end
        end
    end
    return out
end

local function ask(d)
    local s = state(d)
    if s.mission then
        return
    end
    local Proposals = part("DiplomacyProposals")
    if not Proposals then
        return
    end
    local now = GetCurrentTime()
    for _, ally in ipairs(asking_allies(d)) do
        if now >= (s.next_ask[ally] or 0) and not Proposals.from(d, ally)
                and GameRandom.Free_Random(1, 100) <= J.ASK_CHANCE then
            s.next_ask[ally] = now + weeks(J.ASK_COOLDOWN_WEEKS)
            local list = candidates(d, ally)
            if list[1] then
                local c = list[GameRandom.Free_Random(1, table.getn(list))]
                local target = FindPlanet(c.target)
                local name = target and d:planet_name(target) or c.target
                Proposals.add(d, ally, {{kind = "JOINT", side = "offer", target = c.target, base = c.base,
                                         enemy = c.enemy, weeks = J.WEEKS}}, "a joint invasion of " .. name)
                return
            end
        end
    end
end

function Joint.item_text(d, item)
    local target = FindPlanet(item.target)
    return "Joint invasion: " .. (target and d:planet_name(target) or item.target)
end

function Joint.show_log(d)
    local Goals = require("eawx-plugins/diplomacy/DiplomacyGoals")
    local s = state(d)
    if s.goal then
        pcall(Goals.remove, d, s.goal)
        s.goal = nil
    end
    local m = s.mission
    if not m then
        return
    end
    local target, base = FindPlanet(m.target), FindPlanet(m.base)
    local tname = target and d:planet_name(target) or m.target
    local bname = base and d:planet_name(base) or m.base
    local ok, slot = pcall(Goals.add, d, "Joint Invasion: " .. tname, {
        "With " .. d.display_name(m.ally) .. ": take " .. tname .. " from " .. d.display_name(m.enemy) .. ".",
        "Invasion target: " .. tname .. ". Base of invasion: " .. bname .. ".",
        (m.reached or m.pulled) and ("Under way: " .. d.display_name(m.ally) .. "'s fleets are with yours.")
            or ("Send a fleet of yours to " .. tname .. ": their fleets at " .. bname .. " come along."),
        "Never striking before the deadline costs their opinion of you."}, m.deadline)
    s.goal = ok and slot or nil
end

function Joint.start(d, ally, item)
    local s = state(d)
    local now = GetCurrentTime()
    s.mission = {ally = ally, enemy = item.enemy, target = item.target, base = item.base,
                 deadline = now + weeks(item.weeks or J.WEEKS), started = now}
    local target, base = FindPlanet(item.target), FindPlanet(item.base)
    local tname = target and d:planet_name(target) or item.target
    local bname = base and d:planet_name(base) or item.base
    local week = M.floor((now + weeks(item.weeks or J.WEEKS)) / CONFIG.WEEK_SECONDS)
    popup_text("HEADER", "Joint Invasion: " .. tname)
    popup_text("BODY", "Strike " .. tname .. " before week " .. week .. ". Base of Invasion: " .. bname .. ".",
        "The fleets of " .. d.display_name(ally) .. " gather at " .. bname .. " to take " .. tname .. " from "
        .. d.display_name(item.enemy) .. ". A fleet of yours sent from " .. bname .. " brings theirs along; with yours "
        .. "in orbit of " .. tname .. ", theirs join it. "
        .. "Never striking before the deadline costs their opinion of you.")
    popup_text("OK", "Understood")
    if GlobalValue.Get("POPUP_ACTIVE") == nil then
        pcall(GenericPopup, "JOINT", {"OK"}, "JOINT_OPTION")
    end
    d.show("Joint invasion with " .. d.display_name(ally) .. ": take " .. tname .. " from "
        .. d.display_name(item.enemy) .. " before week " .. week .. ". Base of Invasion: " .. bname .. ".", nil, COLOR, 25)
    pcall(Joint.show_log, d)
end

local return_army
local function release(m)
    for _, unit in ipairs((m and m.units) or {}) do
        if TestValid(unit) then
            pcall(function() unit.Prevent_AI_Usage(false) end)
        end
    end
end

local function finish(d, text, color)
    pcall(return_army, d, state(d).mission)
    release(state(d).mission)
    state(d).mission = nil
    pcall(Joint.show_log, d)
    if text then
        d.show(text, nil, color or COLOR, 20)
    end
end

local function fleets_at(p, world)
    local out = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(p) or {}) do
        if TestValid(unit) then
            local ok, at = pcall(unit.Get_Planet_Location)
            if ok and at and key(at) == world then
                local okp, parent = pcall(unit.Get_Parent_Object)
                if okp and parent and TestValid(parent) and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" then
                    table.insert(out, parent)
                end
            end
        end
    end
    return out
end

local function send(fleets, world)
    local planet = FindPlanet(world)
    if not planet then
        return
    end
    for _, fleet in ipairs(fleets) do
        if TestValid(fleet) then
            pcall(function() fleet.Move_To(planet) end)
        end
    end
end

local TRANSPORT = {IMPERIAL = "Gamma_ATR_6_Group", WARLORD = "Gamma_ATR_6_Group", OTHER = "Super_Transport_XI"}

local function transport_type(ally)
    local ok, U = pcall(require, "eawx-plugins/new-republic/RepublicUtil")
    local kind = ok and U.category(ally) or "OTHER"
    return Find_Object_Type(TRANSPORT[kind] or TRANSPORT.OTHER) or Find_Object_Type(TRANSPORT.OTHER)
end

local function raise_army(d, m, pa)
    local base = FindPlanet(m.base)
    if not base then
        return 0
    end
    local companies = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(pa) or {}) do
        if TestValid(unit) then
            local okp, parent = pcall(unit.Get_Parent_Object)
            if okp and parent == base and (unit.Is_Category("Infantry") or unit.Is_Category("Vehicle"))
                    and not unit.Is_Category("InfantryHero") and not unit.Is_Category("VehicleHero") then
                table.insert(companies, unit)
            end
        end
    end
    local n = table.getn(companies)
    local take = M.max(0, M.min(M.min(J.ARMY_UNITS, M.floor(n / 2)), n - J.ARMY_KEEP))
    local ttype = take > 0 and transport_type(m.ally)
    if not ttype then
        return 0
    end
    local types = {}
    for i = 1, take do
        table.insert(types, companies[i].Get_Type().Get_Name())
        companies[i].Despawn()
    end
    local transports = {}
    for _ = 1, M.ceil(take / 2) do
        local ok, spawned = pcall(Spawn_Unit, ttype, base, pa)
        local unit = ok and spawned and spawned[1]
        if unit and TestValid(unit) then
            pcall(function() unit.Prevent_AI_Usage(true) end)
            table.insert(transports, unit)
        end
    end
    if not transports[1] then
        pcall(SpawnList, types, base, pa, true, false)
        return 0
    end
    local ok_f, fleet = pcall(Assemble_Fleet, transports)
    local parent = transports[1].Get_Parent_Object()
    send({(ok_f and fleet) or parent}, m.target)
    m.army = {types = types, transports = transports}
    return take
end

local function transports_alive(m)
    local alive, at_target = 0, 0
    for _, unit in ipairs(m.army.transports) do
        if TestValid(unit) then
            alive = alive + 1
            local ok, at = pcall(unit.Get_Planet_Location)
            if ok and at and key(at) == m.target then
                at_target = at_target + 1
            end
        end
    end
    return alive, at_target
end

local function clear_army_flag()
    GlobalValue.Set("DP_JOINT_ARMY", "")
end

local function watch_army(d, m)
    local army = m.army
    if not army or army.landed then
        return
    end
    local alive, at_target = transports_alive(m)
    local tplanet = FindPlanet(m.target)
    local tname = tplanet and d:planet_name(tplanet) or m.target
    if alive == 0 then
        m.army = nil
        clear_army_flag()
        d.show("Joint invasion: " .. d.display_name(m.ally) .. "'s troop transports were lost before " .. tname
            .. ". Its army is gone.", nil, WARN, 20)
        return
    end
    if GlobalValue.Get("DP_JOINT_ARMY_LANDED") == m.target then
        GlobalValue.Set("DP_JOINT_ARMY_LANDED", "")
        army.landed = true
        clear_army_flag()
        for _, unit in ipairs(army.transports) do
            if TestValid(unit) then
                pcall(unit.Despawn)
            end
        end
        return
    end
    GlobalValue.Set("DP_JOINT_ARMY", (at_target > 0) and (m.target .. "|" .. m.ally .. "|" .. table.concat(army.types, ","))
        or "")
end

return_army = function(d, m)
    local army = m and m.army
    if not army or army.landed then
        return
    end
    clear_army_flag()
    local pa = player(m.ally)
    local home = FindPlanet(m.base)
    if pa and home and home.Get_Owner() ~= pa then
        home = StoryUtil and StoryUtil.FindFriendlyPlanet and StoryUtil.FindFriendlyPlanet(pa, true) or nil
    end
    for _, unit in ipairs(army.transports) do
        if TestValid(unit) then
            pcall(unit.Despawn)
        end
    end
    if pa and home then
        pcall(SpawnList, army.types, home, pa, true, false)
    end
    m.army = nil
end

local function embark(d, m, pa)
    local fleets = fleets_at(pa, m.base)
    m.units = m.units or {}
    for _, unit in pairs(Find_All_Objects_Of_Type(pa) or {}) do
        if TestValid(unit) then
            local ok, at = pcall(unit.Get_Planet_Location)
            local okp, parent = pcall(unit.Get_Parent_Object)
            if ok and at and key(at) == m.base and okp and parent and TestValid(parent)
                    and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" then
                pcall(function() unit.Prevent_AI_Usage(true) end)
                table.insert(m.units, unit)
            end
        end
    end
    send(fleets, m.target)
    if m.army_sent then
        return 0
    end
    m.army_sent = true
    local ok, n = pcall(raise_army, d, m, pa)
    return ok and n or 0
end

local function on_lane_to(d, fleet, target)
    local ok, x, y = pcall(function()
        local a, b = fleet.Get_Position().Get_XYZ()
        return a, b
    end)
    local Trade = part("DiplomacyTrade")
    if not ok or not x or not Trade then
        return false
    end
    local tx, ty = target.Get_Position().Get_XYZ()
    for _, name in ipairs(Trade.neighbours(d, target) or {}) do
        local there = FindPlanet(name)
        if there then
            local nx, ny = there.Get_Position().Get_XYZ()
            local lx, ly = tx - nx, ty - ny
            local len2 = lx * lx + ly * ly
            if len2 > 1 then
                local t = ((x - nx) * lx + (y - ny) * ly) / len2
                local px, py = nx + t * lx - x, ny + t * ly - y
                local tol2 = M.max(64, 0.0036 * len2)
                if t > 0.02 and t < 1 and px * px + py * py <= tol2 then
                    return true
                end
            end
        end
    end
    return false
end

local function run(d)
    local m = state(d).mission
    if not m then
        return
    end
    local now = GetCurrentTime()
    local H = string.upper(d.human.Get_Faction_Name())
    local tplanet = FindPlanet(m.target)
    local tname = tplanet and d:planet_name(tplanet) or m.target
    local holder = owner_of(m.target)
    if d:relation(m.ally) ~= "ALLIANCE" or not player(m.ally) then
        return finish(d, "The joint invasion of " .. tname .. " is called off: the alliance with "
            .. d.display_name(m.ally) .. " is over.")
    end
    if holder == H or holder == m.ally then
        Opinions.add(m.ally, H, J.OPINION_DONE, J.OPINION_WEEKS, "you took " .. tname .. " with them")
        return finish(d, "Joint invasion: " .. tname .. " is taken. " .. d.display_name(m.ally) .. " is grateful.")
    end
    if holder ~= m.enemy then
        return finish(d, "The joint invasion of " .. tname .. " ends: " .. d.display_name(m.enemy) .. " no longer holds it.")
    end
    if owner_of(m.base) ~= m.ally then
        return finish(d, "The joint invasion of " .. tname .. " ends: " .. d.display_name(m.ally)
            .. " lost its base of invasion.", WARN)
    end
    if now >= m.deadline + (m.reached and weeks(J.AFTER_WEEKS) or 0) then
        if not m.reached then
            Opinions.add(m.ally, H, -J.OPINION_EXPIRED, J.OPINION_WEEKS, "you never joined the invasion of " .. tname)
            return finish(d, "Joint invasion: you never struck at " .. tname .. ". " .. d.display_name(m.ally)
                .. " thinks less of you (-" .. J.OPINION_EXPIRED .. ").", WARN)
        end
        return finish(d, "The joint invasion of " .. tname .. " runs its course.")
    end
    if now >= next_mark then
        next_mark = now + J.MARK_SECONDS
        local bplanet = FindPlanet(m.base)
        if tplanet then
            pcall(tplanet.Attach_Particle_Effect, TARGET_LABEL)
        end
        if bplanet then
            pcall(bplanet.Attach_Particle_Effect, BASE_LABEL)
        end
    end
    local pa = player(m.ally)
    if not m.pulled and not m.reached and tplanet and now >= next_pull then
        next_pull = now + PULL_SECONDS
        local Allies = part("DiplomacyAllies")
        for _, f in ipairs(Allies and Allies.fleets(d.human) or {}) do
            if not f.planet and on_lane_to(d, f.fleet, tplanet) then
                m.pulled = true
                local n = embark(d, m, pa)
                d.show("Joint invasion: " .. d.display_name(m.ally) .. "'s fleets at the base set out with yours for "
                    .. tname .. ((n > 0) and (", with " .. n .. " companies of its army.") or "."), nil, COLOR, 15)
                pcall(Joint.show_log, d)
                break
            end
        end
    end
    if now < next_steer then
        return
    end
    next_steer = now + J.STEER_SECONDS
    pcall(watch_army, d, m)
    if not m.reached and fleets_at(d.human, m.target)[1] then
        m.reached = true
        local n = embark(d, m, pa)
        d.show("Joint invasion: your fleet is over " .. tname .. ". " .. d.display_name(m.ally) .. "'s fleets follow"
            .. ((n > 0) and (", with " .. n .. " companies of its army.") or "."), nil, COLOR, 20)
    end
    if not m.logged_reached and m.reached then
        m.logged_reached = true
        pcall(Joint.show_log, d)
    end
    if not m.reached and not m.pulled then
        local Allies = part("DiplomacyAllies")
        local base = FindPlanet(m.base)
        local gathered = 0
        for _, f in ipairs(Allies and Allies.fleets(pa) or {}) do
            if gathered >= J.GATHER_FLEETS then
                break
            end
            if f.planet and key(f.planet) ~= m.base and base then
                pcall(function() f.fleet.Move_To(base) end)
                gathered = gathered + 1
            elseif f.planet and key(f.planet) == m.base then
                gathered = gathered + 1
            end
        end
    end
end

function Joint.update(d)
    if not J or not J.ON or not d.human then
        return
    end
    pcall(run, d)
    local now = GetCurrentTime()
    if now >= next_week then
        next_week = now + weeks(1)
        pcall(ask, d)
    end
end

function Joint.mission(d)
    return state(d).mission
end

return Joint
