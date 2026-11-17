require("eawx-util/StoryUtil")
require("eawx-util/PopulatePlanetUtilities")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Grants = require("eawx-plugins/diplomacy/DiplomacyGrants")
local DATA = require("eawx-plugins/diplomacy/DiplomacyRebellionData")
local POPULATIONS = require("eawx-plugins/diplomacy/DiplomacyPopulations")

local Rebellion = {}

function DIPLOMACY_CAN_RISE(name)
    return name ~= nil and POPULATIONS[string.upper(name)] ~= nil
end

local INDEPENDENT = "INDEPENDENT_FORCES"
local loyalty_table
local COLOR = {r = 255, g = 140, b = 90}

function DIPLOMACY_REVOLT_POPULATE(planet, player, power)
    local R = CONFIG.REBELLION
    power = power or R.POPULATE_POWER
    local name = string.upper(player.Get_Faction_Name())
    if name == INDEPENDENT or string.find(name, "^INDEPENDENT_WORLD") then
        return ChangePlanetOwnerAndPopulate(planet, player, power)
    end
    return ChangePlanetOwnerAndPopulate(planet, player, {power * R.FACTION_SPACE_SHARE, power / 4 * R.FACTION_LAND_SHARE},
        nil, nil, nil, R.FACTION_MAX_GROUND)
end
local CALM = {r = 170, g = 230, b = 170}

local function rules()
    return CONFIG.REBELLION
end

local function log(text)
    if Engine_Log then
        Engine_Log("REBELLION " .. text)
    end
end

local function state(d)
    d.rebellion = d.rebellion or {queue = {}, active = nil}
    return d.rebellion
end

local function has_ground(d, planet)
    for _, object in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
        if TestValid(object) and object.Get_Planet_Location() == planet then
            if object.Is_Category("Infantry") or object.Is_Category("Vehicle") or object.Is_Category("InfantryHero")
                or object.Is_Category("VehicleHero")
                or object.Is_Category("Structure") then
                return true
            end
        end
    end
    return false
end

local function revolt_faction(d, name, loyal)
    if not loyal then
        local table_ = loyalty_table()
        loyal = table_ and table_[name]
    end
    loyal = loyal and string.upper(loyal)
    if not loyal or loyal == string.upper(d.human.Get_Faction_Name()) or not Find_Player(loyal)
        or d:relation(loyal) ~= "WAR" then
        loyal = INDEPENDENT
    end
    return loyal
end

local function revolt_world(d, planet, faction)
    local owner = Find_Player(faction) or Find_Player(INDEPENDENT)
    DIPLOMACY_REVOLT_POPULATE(planet, owner)
end

local function rebels_left(planet, rebels)
    local count = 0
    for _, unit in pairs(rebels and Find_All_Objects_Of_Type(rebels) or {}) do
        if TestValid(unit) and unit ~= planet and unit.Get_Planet_Location() == planet then
            count = count + 1
        end
    end
    return count
end

local function set_rebel_war(d, faction, war)
    if faction ~= INDEPENDENT then
        return
    end
    local independent = Find_Player(INDEPENDENT)
    if not independent then
        return
    end
    d.rebellion_war = war or nil
    if war then
        d.human.Make_Enemy(independent)
        independent.Make_Enemy(d.human)
    elseif CONFIG.INDEPENDENT_PEACE[d.human.Get_Faction_Name()] then
        d.human.Make_Ally(independent)
        independent.Make_Ally(d.human)
    end
end

local function is_ship(unit)
    return unit.Is_Category("Fighter") or unit.Is_Category("Bomber") or unit.Is_Category("Corvette")
        or unit.Is_Category("Frigate") or unit.Is_Category("Capital") or unit.Is_Category("SuperCapital")
        or unit.Is_Category("SpaceHero") or unit.Is_Category("Transport")
end

local function nearest_world(d, planet)
    local best, best_distance = nil, nil
    for _, other in pairs(FindPlanet.Get_All_Planets()) do
        if other ~= planet and other.Get_Owner() == d.human then
            local distance = planet.Get_Distance(other)
            if not best_distance or distance < best_distance then
                best, best_distance = other, distance
            end
        end
    end
    return best
end

local function clear_orbit(d, planet, rebels)
    local destination = nearest_world(d, planet)
    local stations, moved = {}, 0
    for _, unit in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
        if TestValid(unit) and unit.Get_Planet_Location() == planet then
            if unit.Is_Category("SpaceStructure") then
                local unit_type = unit.Get_Type()
                if pcall(unit.Despawn) then
                    table.insert(stations, unit_type)
                end
            elseif is_ship(unit) and destination then
                local relevant = get_relevant_object and get_relevant_object(unit) or unit
                if TestValid(relevant) then
                    local unit_type = relevant.Get_Type()
                    relevant.Despawn()
                    pcall(Spawn_Unit, unit_type, destination, d.human)
                    moved = moved + 1
                end
            end
        end
    end
    for _, unit in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
        if TestValid(unit) and unit.Get_Planet_Location() == planet
            and string.upper(unit.Get_Type().Get_Name()) == "GALACTIC_FLEET" then
            pcall(unit.Despawn)
        end
    end
    local remaining = ""
    for _, unit in pairs(Find_All_Objects_Of_Type(d.human) or {}) do
        if TestValid(unit) and unit.Get_Planet_Location() == planet then
            remaining = remaining .. unit.Get_Type().Get_Name() .. (unit.Is_Category("SpaceStructure") and "(S) " or " ")
        end
    end
    for _, station in ipairs(stations) do
        remaining = remaining .. "| station " .. station.Get_Name() .. " removed "
    end
    log("left at the planet: " .. remaining)
    log("orbit cleared: " .. moved .. " ships to " .. tostring(destination and destination.Get_Type().Get_Name())
        .. ", " .. table.getn(stations) .. " stations held by the rebels")
    if moved > 0 then
        d.show("Your ships over " .. d:planet_name(planet) .. " withdraw to " .. d:planet_name(destination)
            .. " as the rebels seize the orbital stations.", nil, COLOR, 20)
    end
    return stations
end

local function garrison_strength(d, planet, player)
    local total, units = 0, {}
    for _, unit in pairs(Find_All_Objects_Of_Type(player or d.human) or {}) do
        if TestValid(unit) and unit ~= planet and unit.Get_Planet_Location() == planet and not is_ship(unit)
            and not unit.Is_Category("SpaceStructure") then
            local ok, cost = pcall(unit.Get_Type().Get_Build_Cost)
            total = total + ((ok and type(cost) == "number") and cost or 0)
            table.insert(units, unit)
        end
    end
    return total, units
end

local function army_strength(names)
    local total = 0
    for _, name in ipairs(names) do
        local unit_type = Find_Object_Type(name)
        local ok, cost = false, nil
        if unit_type then
            ok, cost = pcall(unit_type.Get_Build_Cost)
        end
        total = total + ((ok and type(cost) == "number") and cost or 500)
    end
    return total
end

function Rebellion.queue(d, planet, loyal, reason)
    local s = state(d)
    local name = string.upper(planet.Get_Type().Get_Name())
    local faction = revolt_faction(d, name, loyal)
    if not DATA.MAPS[name] then
        log("no land map for " .. name .. ": old revolt")
        return false
    end
    if not has_ground(d, planet) then
        d.show("Rebellion: with no garrison left on " .. d:planet_name(planet) .. " to stop them, the rebels "
            .. "take the planet without a fight.", nil, COLOR, 25)
        return false
    end
    if s.active and s.active.name == name then
        return true
    end
    for _, entry in ipairs(s.queue) do
        if entry.name == name then
            return true
        end
    end
    table.insert(s.queue, {name = name, faction = faction, since = GetCurrentTime()})
    local leaning = (faction == INDEPENDENT) and "for independence" or ("for " .. d.display_name(faction))
    local opening = reason and (d:planet_name(planet) .. " rises " .. leaning .. ": " .. reason)
        or ("unrest on " .. d:planet_name(planet) .. " boils over into open revolt " .. leaning)
    d.show("REBELLION: " .. opening .. ". Armed bands are rising all over the planet. Your garrison there must put "
        .. "them down, or the world is lost.", nil, COLOR, 30)
    log("queued " .. name .. " for " .. faction)
    return true
end

local choose_autoresolve

local ok_lore, LOYALTY_LORE = pcall(require, "eawx-plugins/diplomacy/DiplomacyLoyaltyLore")
if not ok_lore or type(LOYALTY_LORE) ~= "table" then
    LOYALTY_LORE = {}
end
function loyalty_table()
    local ok, t = pcall(ModContentLoader.get, "influence-policy/LoyaltyTable")
    if not (ok and type(t) == "table") then
        return nil
    end
    if not t.__diplomacy_lore then
        t.__diplomacy_lore = true
        for world, faction in pairs(LOYALTY_LORE) do
            t[world] = faction
        end
    end
    return t
end

function Rebellion.preferred(d, name)
    if d.loyal and d.loyal[name] then
        return d.loyal[name]
    end
    local t = loyalty_table()
    local loyal = t and t[name]
    return loyal and string.upper(loyal) or INDEPENDENT
end

function Rebellion.apply_loyalties(d)
    local t = loyalty_table()
    for name, faction in pairs(t and d.loyal or {}) do
        t[name] = faction
    end
end

function Rebellion.sway(d, name, faction)
    d.loyal = d.loyal or {}
    d.loyal[name] = faction
    Rebellion.apply_loyalties(d)
end

function Rebellion.rise_own(d, planet)
    if not planet or planet.Get_Owner() ~= d.human then
        return false
    end
    if Rebellion.queue(d, planet) then
        return true
    end
    local name = string.upper(planet.Get_Type().Get_Name())
    revolt_world(d, planet, revolt_faction(d, name))
    Rebellion.lost(d, name)
    return true
end

function Rebellion.lost(d, name)
    local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
    local Council = ok and Republic and Republic.part and Republic.part("council")
    if Council and Council.on_revolt then
        pcall(Council.on_revolt, d, name)
    end
end

function Rebellion.rise_alone(d, planet, faction)
    local name = string.upper(planet.Get_Type().Get_Name())
    local owner = planet.Get_Owner()
    local owner_name = owner.Get_Faction_Name()
    local tier = POPULATIONS[name] or 1
    local sizes = {
        natives = rules().NATIVES_BASE + rules().NATIVES_PER_TIER * tier,
        locals = rules().LOCAL_UNITS,
        faction = (faction == INDEPENDENT) and 0 or rules().FACTION_UNITS,
        mercenaries = 0,
        vehicle_share = rules().VEHICLE_SHARE,
        heavy_max = rules().HEAVY_VEHICLES,
        max_cost = rules().MAX_UNIT_COST,
    }
    local ok, army = pcall(Grants.rebel_army, name, faction, sizes)
    local rising = army_strength(ok and army or {})
    local garrison = garrison_strength(d, planet, owner)
    local chance = M.round(1000 * rising / M.max(1, rising + garrison))
    local won = garrison <= 0 or GameRandom.Free_Random(1, 1000) <= chance
    log("rising alone on " .. name .. " for " .. faction .. ": " .. rising .. " vs " .. garrison .. ", won " .. tostring(won))
    local readable = d:planet_name(planet)
    local side = (faction == INDEPENDENT) and "for independence" or ("for " .. d.display_name(faction))
    if won then
        DIPLOMACY_REVOLT_POPULATE(planet, Find_Player(faction) or Find_Player(INDEPENDENT))
        d.show("Uprising: the people of " .. readable .. " rise " .. side .. " and overthrow "
            .. d.display_name(owner_name) .. "'s garrison.", nil, CALM, 25)
    else
        d.show("Uprising: the people of " .. readable .. " rise " .. side .. ", and " .. d.display_name(owner_name)
            .. "'s garrison crushes them.", nil, COLOR, 25)
    end
    return true
end

function Rebellion.uprising(d, planet, led)
    local s = state(d)
    local name = string.upper(planet.Get_Type().Get_Name())
    local owner = planet.Get_Owner()
    local faction = Rebellion.preferred(d, name)
    if owner == d.human or string.upper(owner.Get_Faction_Name()) == faction then
        return false
    end
    if not led or not DATA.MAPS[name] or garrison_strength(d, planet, owner) <= 0 then
        return Rebellion.rise_alone(d, planet, faction)
    end
    if s.active and s.active.name == name then
        return true
    end
    for _, entry in ipairs(s.queue) do
        if entry.name == name then
            return true
        end
    end
    local secret = not d.human.Is_Enemy(owner) and owner.Get_Faction_Name() or nil
    table.insert(s.queue, {name = name, faction = d.human.Get_Faction_Name(), owner = owner.Get_Faction_Name(),
                           rise_for = faction, secret = secret, reverse = true, since = GetCurrentTime()})
    local side = (faction == string.upper(d.human.Get_Faction_Name())) and "the world is the Republic's"
        or ((faction == INDEPENDENT) and "the world is free" or ("the world goes to " .. d.display_name(faction)))
    d.show("UPRISING: the people of " .. d:planet_name(planet) .. " rise against " .. d.display_name(owner.Get_Faction_Name())
        .. ". Lead them against the garrison and " .. side .. ".", nil, CALM, 30)
    log("queued uprising on " .. name .. " against " .. owner.Get_Faction_Name() .. " for " .. faction
        .. (secret and " (hidden war)" or ""))
    return true
end

local function hide_war(d, faction)
    local other = faction and Find_Player(faction)
    if not other then
        return
    end
    d.secret_war = string.upper(faction)
    d.human.Make_Enemy(other)
    other.Make_Enemy(d.human)
end

function Rebellion.end_hidden_war(d)
    if d.secret_war then
        log("hidden war with " .. d.secret_war .. " ends")
        d.secret_war = nil
        pcall(d.apply_treaties, d)
    end
end

local function launch_reverse(d, entry)
    local planet = FindPlanet(entry.name)
    local owner = planet and planet.Get_Owner()
    if not owner or owner == d.human or string.upper(owner.Get_Faction_Name()) ~= string.upper(entry.owner) then
        return false
    end
    local readable = d:planet_name(planet)
    local tier = POPULATIONS[entry.name] or 1
    local sizes = {
        natives = rules().NATIVES_BASE + rules().NATIVES_PER_TIER * tier,
        locals = rules().LOCAL_UNITS,
        faction = rules().FACTION_UNITS,
        mercenaries = 0,
        vehicle_share = rules().VEHICLE_SHARE,
        heavy_max = rules().HEAVY_VEHICLES,
        max_cost = rules().MAX_UNIT_COST,
    }
    local army = Grants.rebel_army(entry.name, d.human.Get_Faction_Name(), sizes)
    entry.strength = army_strength(army)
    local vanguard, rest = {}, {}
    for _, name in ipairs(army) do
        if table.getn(vanguard) < rules().VANGUARD and Find_Object_Type(name) then
            table.insert(vanguard, name)
        else
            table.insert(rest, name)
        end
    end
    if table.getn(vanguard) == 0 then
        return false
    end
    GlobalValue.Set("DIPLOMACY_REBELLION_VANGUARD", table.concat(vanguard, ","))
    GlobalValue.Set("DIPLOMACY_REBELLION_INVADED", -1)
    GlobalValue.Set("DIPLOMACY_REBELLION_ARMY", table.concat(rest, ","))
    GlobalValue.Set("DIPLOMACY_REBELLION_OWNER", d.human.Get_Faction_Name())
    GlobalValue.Set("DIPLOMACY_REBELLION_DEFENDER", owner.Get_Faction_Name())
    GlobalValue.Set("DIPLOMACY_REBELLION_REVERSE", 1)
    GlobalValue.Set("DIPLOMACY_REBELLION_STATE", "PENDING")
    GlobalValue.Set("DIPLOMACY_REBELLION_RESULT", "")
    log("launch uprising " .. entry.name .. " against " .. entry.owner .. " on " .. DATA.MAPS[entry.name] .. ": vanguard "
        .. table.getn(vanguard) .. ", army " .. table.getn(rest))
    local units = 0
    for _, name in ipairs(vanguard) do
        if pcall(Spawn_Unit, Find_Object_Type(name), planet, d.human) then
            units = units + 1
        end
    end
    local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
    local event = plot and plot.Get_Event("Diplomacy_Rebellion_Link")
    if units == 0 or not event then
        GlobalValue.Set("DIPLOMACY_REBELLION_REVERSE", 0)
        return false
    end
    event.Set_Reward_Parameter(0, planet.Get_Type().Get_Name())
    event.Set_Reward_Parameter(2, d.human.Get_Faction_Name())
    event.Set_Reward_Parameter(3, DATA.MAPS[entry.name])
    event.Set_Reward_Parameter(4, owner.Get_Faction_Name())
    if Engine_Set_Text then
        local map = string.upper((string.gsub(DATA.MAPS[entry.name], "%.[Tt][Ee][Dd]$", "")))
        pcall(Engine_Set_Text, "MT" .. map, readable .. ": Uprising")
        pcall(Engine_Set_Text, "MB" .. map, "The people of " .. readable .. " rise against "
            .. d.display_name(entry.owner) .. ". Lead them against the garrison and free the world.")
        pcall(Engine_Set_Text, "TEXT_DIPLOMACY_REBELLION_START", "UPRISING ON " .. string.upper(readable)
            .. "! The people rise. Lead them against the garrison.")
    end
    if Engine_Rebellion_Prompt then
        DiplomacyRebellionAutoresolve = function()
            DiplomacyRebellionAutoresolve = nil
            if state(d).active == entry then
                return choose_autoresolve(d, entry)
            end
        end
        Engine_Rebellion_Prompt(1)
    end
    if entry.secret then
        hide_war(d, entry.secret)
    end
    Story_Event("DIPLOMACY_REBELLION_LINK")
    GlobalValue.Set("DIPLOMACY_REBELLION_INVADED", 1)
    entry.launched = GetCurrentTime()
    return true
end

local function launch(d, entry)
    if entry.reverse then
        return launch_reverse(d, entry)
    end
    local planet = FindPlanet(entry.name)
    local rebels = Find_Player(INDEPENDENT)
    if not planet or planet.Get_Owner() ~= d.human or not rebels then
        return false
    end
    local readable = d:planet_name(planet)
    local tier = POPULATIONS[entry.name] or 1
    local sizes = {
        natives = rules().NATIVES_BASE + rules().NATIVES_PER_TIER * tier,
        locals = rules().LOCAL_UNITS,
        faction = (entry.faction == INDEPENDENT) and 0 or rules().FACTION_UNITS,
        mercenaries = rules().MERCENARIES,
        vehicle_share = rules().VEHICLE_SHARE,
        heavy_max = rules().HEAVY_VEHICLES,
        max_cost = rules().MAX_UNIT_COST,
    }
    local army = Grants.rebel_army(entry.name, entry.faction, sizes)
    entry.strength = army_strength(army)
    set_rebel_war(d, INDEPENDENT, true)

    local count = 0
    local rest = {}
    local vanguard = {}
    for _, name in ipairs(army) do
        if count < rules().VANGUARD and Find_Object_Type(name) then
            count = count + 1
            table.insert(vanguard, name)
        else
            table.insert(rest, name)
        end
    end
    GlobalValue.Set("DIPLOMACY_REBELLION_VANGUARD", table.concat(vanguard, ","))
    GlobalValue.Set("DIPLOMACY_REBELLION_INVADED", -1)
    log("launch " .. entry.name .. " for " .. entry.faction .. " on " .. DATA.MAPS[entry.name] .. ": vanguard "
        .. count .. ", army " .. table.getn(rest) .. ": " .. table.concat(rest, ","))
    if count == 0 then
        set_rebel_war(d, INDEPENDENT, false)
        return false
    end
    GlobalValue.Set("DIPLOMACY_REBELLION_ARMY", table.concat(rest, ","))
    GlobalValue.Set("DIPLOMACY_REBELLION_OWNER", INDEPENDENT)
    GlobalValue.Set("DIPLOMACY_REBELLION_STATE", "PENDING")
    GlobalValue.Set("DIPLOMACY_REBELLION_RESULT", "")

    local units = 0
    for _, name in ipairs(vanguard) do
        if pcall(Spawn_Unit, Find_Object_Type(name), planet, rebels) then
            units = units + 1
        end
    end
    if units == 0 then
        set_rebel_war(d, INDEPENDENT, false)
        return false
    end

    local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
    local event = plot and plot.Get_Event("Diplomacy_Rebellion_Link")
    if not event then
        set_rebel_war(d, INDEPENDENT, false)
        return false
    end
    event.Set_Reward_Parameter(0, planet.Get_Type().Get_Name())
    event.Set_Reward_Parameter(2, rebels.Get_Faction_Name())
    event.Set_Reward_Parameter(3, DATA.MAPS[entry.name])
    event.Set_Reward_Parameter(4, d.human.Get_Faction_Name())
    if Engine_Set_Text then
        local map = string.upper((string.gsub(DATA.MAPS[entry.name], "%.[Tt][Ee][Dd]$", "")))
        local side = (entry.faction == INDEPENDENT) and "for independence" or ("for the " .. d.display_name(entry.faction))
        pcall(Engine_Set_Text, "MT" .. map, readable .. ": Rebellion")
        pcall(Engine_Set_Text, "MB" .. map, "The people of " .. readable .. " have risen " .. side .. ". Armed "
            .. "insurgents march on your garrison from all over the planet. Destroy every rebel force, or the "
            .. "world is lost.")
        pcall(Engine_Set_Text, "TEXT_DIPLOMACY_REBELLION_START", "REBELLION ON " .. string.upper(readable)
            .. "! Armed insurgents rise and march on your garrison. Destroy them, or the world is lost.")
    end
    if Engine_Rebellion_Prompt then
        DiplomacyRebellionAutoresolve = function()
            DiplomacyRebellionAutoresolve = nil
            if state(d).active == entry then
                return choose_autoresolve(d, entry)
            end
        end
        Engine_Rebellion_Prompt(1)
    end
    Story_Event("DIPLOMACY_REBELLION_LINK")
    GlobalValue.Set("DIPLOMACY_REBELLION_INVADED", 1)
    entry.launched = GetCurrentTime()
    return true
end

local function remove_rebels(planet, rebels)
    for _, unit in pairs(rebels and Find_All_Objects_Of_Type(rebels) or {}) do
        if TestValid(unit) and unit ~= planet and unit.Get_Planet_Location() == planet
                and not unit.Is_Category("Structure") then
            local relevant = get_relevant_object and get_relevant_object(unit) or unit
            if TestValid(relevant) then
                pcall(relevant.Despawn)
            end
        end
    end
end

local function autoresolve(d, entry, planet)
    local garrison, units = garrison_strength(d, planet)
    local rebels = entry.strength or 0
    local chance = M.round(1000 * rebels / M.max(1, rebels + garrison))
    local roll = GameRandom.Free_Random(1, 1000)
    log("autoresolve: rebels " .. rebels .. " vs garrison " .. garrison .. ", chance " .. chance .. ", roll " .. roll)
    if roll <= chance then
        return true
    end
    entry.losses = M.round(table.getn(units) * 0.6 * rebels / M.max(1, rebels + garrison))
    return false
end

local function take_losses(d, planet, count)
    local _, units = garrison_strength(d, planet)
    local lost = 0
    for _, unit in ipairs(units) do
        if lost >= count then
            break
        end
        if TestValid(unit) and not unit.Is_Category("Structure") then
            local relevant = get_relevant_object and get_relevant_object(unit) or unit
            if pcall(relevant.Despawn) then
                lost = lost + 1
            end
        end
    end
    return lost
end

choose_autoresolve = function(d, entry)
    local planet = FindPlanet(entry.name)
    if entry.reverse then
        local garrison = planet and garrison_strength(d, planet, planet.Get_Owner()) or 0
        local rising = entry.strength or 0
        local chance = M.round(1000 * rising / M.max(1, rising + garrison))
        entry.rebels_won = planet ~= nil and planet.Get_Owner() ~= d.human and GameRandom.Free_Random(1, 1000) <= chance
        entry.autoresolved = GetCurrentTime()
        log("uprising auto-resolve: " .. rising .. " vs " .. garrison .. ", won " .. tostring(entry.rebels_won))
        return
    end
    entry.rebels_won = planet and planet.Get_Owner() == d.human and autoresolve(d, entry, planet)
    entry.autoresolved = GetCurrentTime()
    log("auto-resolve chosen: rebels won " .. tostring(entry.rebels_won))
end

local function resolve_reverse(d, entry, autoresolved)
    GlobalValue.Set("DIPLOMACY_REBELLION_REVERSE", 0)
    Rebellion.end_hidden_war(d)
    local planet = FindPlanet(entry.name)
    if not planet then
        return
    end
    local won = (autoresolved and entry.rebels_won)
        or (not autoresolved and GlobalValue.Get("DIPLOMACY_REBELLION_RESULT") == "REBELS")
        or planet.Get_Owner() == d.human
    local rise_for = entry.rise_for or string.upper(d.human.Get_Faction_Name())
    local mine = rise_for == string.upper(d.human.Get_Faction_Name())
    local winner = mine and d.human or Find_Player(rise_for) or Find_Player(INDEPENDENT)
    if won and planet.Get_Owner() ~= winner then
        if not mine then
            remove_rebels(planet, d.human)
        end
        DIPLOMACY_REVOLT_POPULATE(planet, winner)
    end
    local readable = d:planet_name(planet)
    if won and mine then
        d.show("Uprising: " .. readable .. " is free. Its people raise the Republic's banner.", nil, CALM, 30)
    elseif won then
        d.show("Uprising: " .. readable .. " is free of " .. d.display_name(entry.owner) .. ". Its people rise "
            .. ((rise_for == INDEPENDENT) and "for independence." or ("for " .. d.display_name(rise_for) .. ".")),
            nil, CALM, 30)
    else
        d.show("Uprising: the rising on " .. readable .. " is crushed. Its leaders are dead or in hiding.", nil, COLOR, 25)
    end
    if entry.done then
        pcall(entry.done, planet.Get_Owner() == d.human)
    end
    if Rebellion.on_uprising then
        pcall(Rebellion.on_uprising, d, entry.name, planet.Get_Owner() == d.human)
    end
end

local function resolve(d, entry, autoresolved)
    local s = state(d)
    s.active = nil
    if entry.reverse then
        if Engine_Rebellion_Prompt then
            Engine_Rebellion_Prompt(0)
        end
        GlobalValue.Set("DIPLOMACY_REBELLION_STATE", "DONE")
        return resolve_reverse(d, entry, autoresolved)
    end
    if Engine_Rebellion_Prompt then
        Engine_Rebellion_Prompt(0)
    end
    GlobalValue.Set("DIPLOMACY_REBELLION_STATE", "DONE")
    local planet = FindPlanet(entry.name)
    local rebels = Find_Player(INDEPENDENT)
    set_rebel_war(d, INDEPENDENT, false)
    if not planet then
        return
    end
    if autoresolved and entry.rebels_won and planet.Get_Owner() ~= Find_Player(entry.faction) then
        remove_rebels(planet, rebels)
        revolt_world(d, planet, entry.faction)
    end
    if not autoresolved and GlobalValue.Get("DIPLOMACY_REBELLION_RESULT") == "REBELS"
            and planet.Get_Owner() == d.human then
        log("the rebels won on the victory point")
        remove_rebels(planet, rebels)
        revolt_world(d, planet, entry.faction)
    end
    local owner = planet.Get_Owner()
    local left = autoresolved and 0 or rebels_left(planet, rebels)
    log("after the battle: owner " .. owner.Get_Faction_Name() .. ", rebels left " .. left)
    local readable = d:planet_name(planet)
    if owner == d.human and has_ground(d, planet) then
        remove_rebels(planet, rebels)
        if autoresolved and entry.losses then
            entry.losses = take_losses(d, planet, entry.losses)
        end
        for _, station in ipairs(entry.stations or {}) do
            pcall(Spawn_Unit, station, planet, d.human)
        end
        if entry.losses and entry.losses > 0 then
            d.show("The garrison of " .. readable .. " holds, at a cost: " .. entry.losses .. " units lost.", nil, COLOR, 20)
        end
        if left == 0 then
            d.show("Rebellion crushed: the last rebel cells on " .. readable .. " are broken and their leaders "
                .. "in hiding. Order returns to the streets, for now. Unrest left to fester will rise again.",
                nil, CALM, 30)
        else
            d.show("The rebels of " .. readable .. " melt back into the population. The world is still yours, "
                .. "but the anger that drove them has not gone away.", nil, COLOR, 25)
            crossplot:publish("ADJUST_UNREST", entry.name, rules().UNDECIDED_UNREST)
        end
        return
    end
    if owner ~= d.human and owner ~= rebels then
        return
    end
    if owner ~= Find_Player(entry.faction) then
        remove_rebels(planet, rebels)
        revolt_world(d, planet, entry.faction)
    end
    for _, station in ipairs(entry.stations or {}) do
        pcall(Spawn_Unit, station, planet, Find_Player(entry.faction))
    end
    Rebellion.lost(d, entry.name)
    local who = (entry.faction == INDEPENDENT) and "declare it a free world"
        or ("raise the banner of the " .. d.display_name(entry.faction))
    d.show("Rebellion: your garrison on " .. readable .. " has been overrun. The rebels seize the planet's "
        .. "government and " .. who .. ".", nil, COLOR, 30)
end

local loyal_applied = false

function Rebellion.update(d)
    local s = state(d)
    if d.loyal and not loyal_applied then
        loyal_applied = true
        Rebellion.apply_loyalties(d)
    end
    if s.active then
        if s.active.autoresolved then
            if GetCurrentTime() - s.active.autoresolved > 1 then
                resolve(d, s.active, true)
            end
            return
        end
        local battle = GlobalValue.Get("DIPLOMACY_REBELLION_STATE")
        if s.active.launched and (battle == "LANDED"
            or GetCurrentTime() - s.active.launched > rules().LAUNCH_TIMEOUT) then
            log("battle state " .. tostring(battle))
            resolve(d, s.active, false)
        end
        return
    end
    if not s.queue[1] then
        return
    end
    if GetCurrentTime() < rules().FIRST_LAUNCH_TIME then
        return
    end
    local entry = table.remove(s.queue, 1)
    s.active = entry
    local ok, launched = pcall(launch, d, entry)
    if not ok or not launched then
        log("launch failed for " .. entry.name .. ": " .. tostring(launched))
        s.active = nil
        local planet = FindPlanet(entry.name)
        if entry.reverse then
            GlobalValue.Set("DIPLOMACY_REBELLION_REVERSE", 0)
            Rebellion.end_hidden_war(d)
            if Rebellion.on_uprising then
                pcall(Rebellion.on_uprising, d, entry.name, false)
            end
        elseif planet and planet.Get_Owner() == d.human then
            revolt_world(d, planet, entry.faction)
        end
    end
end

function Rebellion.on_battle_end(d, mode_name)
    Rebellion.end_hidden_war(d)
end

function Rebellion.patch(d)
    if type(InfluenceService) ~= "table" then
        return false
    end
    if InfluenceService.__rebellion_patched then
        return true
    end
    local original = InfluenceService.revolt
    InfluenceService.revolt = function(service, planet)
        if not DIPLOMACY_CAN_RISE(planet:get_name()) then
            return
        end
        local object = planet:get_game_object()
        if rules().ENABLED and object.Get_Owner() == d.human then
            local ok, queued = pcall(Rebellion.queue, d, object, service.LoyaltyTable[planet:get_name()])
            if ok and queued then
                return
            end
            if not ok then
                log("queue error: " .. tostring(queued))
            end
        end
        DIPLOMACY_REVOLTS = DIPLOMACY_REVOLTS or {}
        DIPLOMACY_REVOLTS[string.upper(planet:get_name())] = {kind = "REVOLT", time = GetCurrentTime()}
        local new_owner = Find_Player(service.LoyaltyTable[planet:get_name()] or INDEPENDENT) or Find_Player(INDEPENDENT)
        if new_owner == planet:get_owner() then
            new_owner = Find_Player(INDEPENDENT)
        end
        local ok, err = pcall(DIPLOMACY_REVOLT_POPULATE, object, new_owner)
        if not ok then
            log("revolt error: " .. tostring(err))
            return original(service, planet)
        end
    end
    InfluenceService.__rebellion_patched = true
    return true
end

return Rebellion
