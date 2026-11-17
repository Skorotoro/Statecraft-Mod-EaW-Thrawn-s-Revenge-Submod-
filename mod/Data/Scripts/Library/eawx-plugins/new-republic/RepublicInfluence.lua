local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Influence = {}
local C = R.COUNCIL
local I = C.INFLUENCE
local GOLD = {r = 255, g = 225, b = 140}
local WARN = {r = 255, g = 190, b = 90}

local function council()
    return require("eawx-plugins/new-republic/RepublicCouncil")
end

local function republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function sym()
    return republic().part("sym")
end

local function state(d)
    local c = council().state(d)
    c.influence = c.influence or {}
    c.said = c.said or {}
    c.effects = c.effects or {}
    return c
end

function Influence.value(d, key)
    return M.round(state(d).influence[key] or 0)
end

function Influence.add(d, key, amount)
    local c = state(d)
    c.influence[key] = M.max(0, M.min(I.MAX, (c.influence[key] or 0) + amount))
end

local function home_held(d, councillor)
    local planet = FindPlanet(councillor.world)
    if not planet then
        return false
    end
    local owner = planet.Get_Owner()
    if owner == d.human or (d.vassal_worlds and d.vassal_worlds[councillor.world]) then
        return true
    end
    local rel = d.relations and d:relation(owner.Get_Faction_Name())
    return rel == "ALLIANCE" or rel == "PROTECTORATE"
end
Influence.home_held = home_held

function Influence.week(d)
    for _, councillor in ipairs(C.COUNCILLORS) do
        if council().alive(d, councillor.key) then
            Influence.add(d, councillor.key, I.BASE_WEEK + (home_held(d, councillor) and I.WEEK or 0))
        end
    end
    Influence.weekly_effects(d)
end

function Influence.champion(d, key)
    if not council().alive(d, key) then
        return false, "That seat is empty."
    end
    if Influence.value(d, key) >= I.MAX then
        return false, "Their influence is already at its height."
    end
    if not republic().spend(d, I.CHAMPION_COST) then
        return false, "Not enough political capital (" .. I.CHAMPION_COST .. ")."
    end
    Influence.add(d, key, I.CHAMPION_GAIN)
    return true, "You champion their cause: Galactic Influence +" .. I.CHAMPION_GAIN .. "."
end

local function names(d, key)
    local planet = FindPlanet(key)
    return planet and d:planet_name(planet) or key
end

local function spawn_at(d, planet, types)
    local made = 0
    for _, t in ipairs(types) do
        if Find_Object_Type(t) and pcall(SpawnList, {t}, planet, d.human, true, false) then
            made = made + 1
        end
    end
    return made
end

local function first_type(list)
    for _, t in ipairs(list) do
        if Find_Object_Type(t) then
            return t
        end
    end
    return nil
end

local function capital_planet(d)
    local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
    local ok, planet = pcall(Deals.capital, d, d.human)
    if ok and planet then
        return planet
    end
    local worlds = U.worlds_of(d.human)
    return worlds[1] and worlds[1].planet or nil
end

local function change_sympathy(d, keys, amount)
    local Sym = sym()
    local n = 0
    for _, key in ipairs(keys) do
        if Sym and Sym.value(d, key) then
            Sym.change(d, key, amount)
            n = n + 1
        end
    end
    return n
end

local function worlds_where(test)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if test(planet) then
            table.insert(out, U.key(planet))
        end
    end
    return out
end

local function powers(d, test)
    local FACTIONS = require("eawx-plugins/diplomacy/DiplomacyFactions")
    local out = {}
    for faction, _ in pairs(FACTIONS.PLAYABLE or {}) do
        local player = Find_Player(faction)
        if player and player ~= d.human and U.worlds_of(player)[1] and (not test or test(faction)) then
            table.insert(out, faction)
        end
    end
    table.sort(out)
    return out
end

local function goodwill(d, faction, amount)
    local e = state(d).effects
    e.goodwill = e.goodwill or {}
    local old = Influence.goodwill(d, faction)
    e.goodwill[faction] = {value = old + amount, at = GetCurrentTime()}
end

function Influence.goodwill(d, faction)
    local c = d.republic and council().state(d)
    local g = c and c.effects and c.effects.goodwill and c.effects.goodwill[faction]
    if not g then
        return 0
    end
    local left = 1 - U.weeks_since(g.at) / I.GOODWILL_WEEKS
    return M.max(0, M.round(g.value * left))
end

function Influence.voice(d, faction)
    local c = d.republic and council().state(d)
    local until_time = c and c.effects and c.effects.voice and c.effects.voice[faction]
    return (until_time and GetCurrentTime() < until_time) and I.VOICE_ACCEPTANCE or 0
end

function Influence.cohesion_bonus(d)
    local c = d.republic and council().state(d)
    local at = c and c.effects and c.effects.unity_at
    if not at then
        return 0
    end
    return M.max(0, M.round(I.UNITY_COHESION * (1 - U.weeks_since(at) / I.UNITY_WEEKS)))
end

function Influence.upkeep_refund(d)
    local c = d.republic and council().state(d)
    local until_time = c and c.effects and c.effects.upkeep_until
    local ackbar = until_time and GetCurrentTime() < until_time
    local focus = c and council().active(d) and council().focus(d) == "FLEET"
    if not ackbar and not focus then
        return 0
    end
    local function perceive(name)
        local ok, v = pcall(EvaluatePerception, name, d.human)
        return (ok and type(v) == "number") and v or 0
    end
    local upkeep = M.floor(perceive("Total_Maintenance")) - 10 * perceive("LightFactory_Count")
        - 20 * perceive("HeavyFactory_Count") - 30 * perceive("AdvFactory_Count")
    local share = M.max(ackbar and I.UPKEEP_REFUND or 0, focus and C.FLEET_UPKEEP_REFUND or 0)
    return M.floor(M.max(0, upkeep) * share), ackbar and "Ackbar's command (upkeep halved)"
        or "Assemble a Fleet (upkeep halved)"
end

function Influence.weekly_effects(d)
    local refund = Influence.upkeep_refund(d)
    if refund > 0 then
        d.human.Give_Money(refund)
    end
    Influence.keep_dummies(d)
end

local DUMMIES = {fleet_until = "Council_Fleet_Drills", sorosuub_until = "Council_SoroSuub"}
function Influence.keep_dummies(d)
    local e = state(d).effects
    for field, type_name in pairs(DUMMIES) do
        local t = Find_Object_Type(type_name)
        local want = e[field] ~= nil and GetCurrentTime() < e[field]
        if t then
            local have = {}
            for _, obj in pairs(Find_All_Objects_Of_Type(t) or {}) do
                if TestValid(obj) then
                    local at = obj.Get_Planet_Location()
                    if want and at and at.Get_Owner() == d.human and not have[U.key(at)] then
                        have[U.key(at)] = true
                    else
                        obj.Despawn()
                    end
                end
            end
            if want then
                for _, w in ipairs(U.worlds_of(d.human)) do
                    if not have[w.key] then
                        pcall(Spawn_Unit, t, w.planet, d.human)
                    end
                end
            end
        end
    end
end

local COMBAT = "SpaceHero | Capital | Frigate | Corvette | Fighter | Bomber | Infantry | Vehicle | InfantryHero | VehicleHero"

local function contested(planet)
    local owner = planet.Get_Owner()
    local constants = ModContentLoader.get("GameConstants")
    for _, faction in pairs(constants and constants.ALL_FACTIONS_NOT_NEUTRAL or {}) do
        local player = Find_Player(faction)
        if player and player ~= owner then
            for _, obj in pairs(Find_All_Objects_Of_Type(player, COMBAT) or {}) do
                if TestValid(obj) then
                    local ok, where = pcall(function()
                        return obj.Get_Planet_Location()
                    end)
                    if ok and where == planet then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function capital_of(d, player)
    local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
    local ok, planet = pcall(Deals.capital, d, player)
    return ok and planet and U.key(planet) or nil
end

local function call_targets(d)
    local Sym = sym()
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = planet.Get_Owner()
        local faction = string.upper(owner.Get_Faction_Name())
        local key = U.key(planet)
        local v = Sym and Sym.value(d, key)
        if owner ~= d.human and v and v >= R.SYMPATHY_SYMPATHETIC and faction ~= "NEUTRAL"
                and U.category(faction) ~= "INDEPENDENT" and d.relations and d:relation(faction) == "WAR"
                and capital_of(d, owner) ~= key then
            table.insert(out, key)
        end
    end
    return out
end

local function revolt(d, entry, risen)
    local planet = FindPlanet(entry.key)
    if not planet then
        return true
    end
    local owner = string.upper(planet.Get_Owner().Get_Faction_Name())
    if owner ~= entry.owner or planet.Get_Owner() == d.human then
        return true
    end
    if contested(planet) then
        entry.tries = (entry.tries or 0) + 1
        return entry.tries >= I.CALL_TRIES
    end
    local Sym = sym()
    local side = string.upper(Sym and Sym.preferred(d, entry.key) or "INDEPENDENT_FORCES")
    if side == owner then
        side = "INDEPENDENT_FORCES"
    end
    local ok, player = pcall(Find_Player, side)
    if not ok or not player then
        player = Find_Player("Independent_Forces")
    end
    DIPLOMACY_REVOLTS = DIPLOMACY_REVOLTS or {}
    DIPLOMACY_REVOLTS[entry.key] = {kind = "REVOLT", time = GetCurrentTime()}
    local ours = player == d.human
    if ours then
        d.own_transfers[entry.key] = true
        d.republic.conquered[entry.key] = {time = GetCurrentTime(), free = false, content = true}
        d.republic.counts = nil
    end
    if DIPLOMACY_REVOLT_POPULATE then
        DIPLOMACY_REVOLT_POPULATE(planet, player)
    else
        ChangePlanetOwnerAndPopulate(planet, player, 4500)
    end
    table.insert(risen, d:planet_name(planet) .. (ours and " (for you)" or ""))
    return true
end

local function rise_next(d)
    local c = state(d)
    local queue = c.call_queue
    if not queue or not queue[1] then
        return
    end
    local left, risen = {}, {}
    for _, entry in ipairs(queue) do
        local ok, done = pcall(revolt, d, entry, risen)
        if ok and not done then
            table.insert(left, entry)
        elseif not ok and Engine_Log then
            Engine_Log("COUNCIL call to action: " .. tostring(done))
        end
    end
    c.call_queue = left
    if risen[1] then
        d.show("Call to Action: " .. table.concat(risen, ", ") .. ((table.getn(risen) == 1) and " revolts" or " revolt")
            .. " at Mon Mothma's call.", nil, GOLD, 25)
    end
end

function Influence.update(d)
    if GetCurrentTime() >= (Influence.next_rise or 0) then
        Influence.next_rise = GetCurrentTime() + I.CALL_SECONDS
        local ok, err = pcall(rise_next, d)
        if not ok and Engine_Log then
            Engine_Log("COUNCIL call to action: " .. tostring(err))
        end
    end
end

local function weeks_from_now(n)
    return GetCurrentTime() + U.weeks(n)
end

local TARGETS = {
    INDEPENDENT_WORLD = {
        head = "Choose an independent world",
        list = function(d)
            local Sym = sym()
            return worlds_where(function(planet)
                return U.category(planet.Get_Owner().Get_Faction_Name()) == "INDEPENDENT" and Sym ~= nil
                    and Sym.value(d, U.key(planet)) ~= nil
            end)
        end,
        label = function(d, key)
            local Sym = sym()
            return names(d, key) .. " (" .. (Sym and Sym.describe(d, key) or "?") .. ")"
        end,
    },
    OWNED_WORLD = {
        head = "Choose one of your worlds",
        list = function(d)
            local out = {}
            for _, w in ipairs(U.worlds_of(d.human)) do
                table.insert(out, w.key)
            end
            return out
        end,
        label = names,
    },
    POWER = {
        head = "Choose a power",
        list = function(d)
            return powers(d)
        end,
        label = function(d, faction)
            return d.display_name(faction)
        end,
    },
    WAR_POWER = {
        head = "Choose a power at war with you",
        list = function(d)
            return powers(d, function(faction)
                return faction ~= "EMPIRE" and d:relation(faction) == "WAR"
            end)
        end,
        label = function(d, faction)
            return d.display_name(faction)
        end,
    },
    WAR_POWER_OR_WORLD = {
        head = "Choose a power at war with you, or an independent world",
        list = function(d)
            local out = powers(d, function(faction)
                return faction ~= "EMPIRE" and d:relation(faction) == "WAR"
            end)
            for _, planet in pairs(FindPlanet.Get_All_Planets()) do
                if U.category(planet.Get_Owner().Get_Faction_Name()) == "INDEPENDENT" then
                    table.insert(out, "WORLD:" .. U.key(planet))
                end
            end
            return out
        end,
        label = function(d, target)
            local world = string.sub(target, 1, 6) == "WORLD:" and string.sub(target, 7)
            if world then
                return names(d, world) .. " (independent world)"
            end
            return d.display_name(target)
        end,
    },
    NETWORK = {
        head = "Choose a spy network",
        list = function(d)
            local Intel = require("eawx-plugins/new-republic/RepublicIntel")
            local out = {}
            for _, t in ipairs(Intel.targets(d)) do
                if Intel.network(d, t.faction).tier < Intel.max_tier(t.faction) then
                    table.insert(out, t.faction)
                end
            end
            return out
        end,
        label = function(d, target)
            local Intel = require("eawx-plugins/new-republic/RepublicIntel")
            return Intel.label(d, target) .. " (tier " .. Intel.network(d, target).tier .. ")"
        end,
    },
}
Influence.TARGETS = TARGETS

local ACTIONS = {
    MOTHMA = {
        {name = "Arrange Confidential Meeting", target = "INDEPENDENT_WORLD",
         text = "An independent world's sympathy +" .. I.MEETING_SYMPATHY .. ".",
         flavour = "In a quiet room on {target}, Mon Mothma meets its leaders without aides or holocams. When she "
             .. "leaves, they are thinking about the Alliance.",
         run = function(d, key)
             change_sympathy(d, {key}, I.MEETING_SYMPATHY)
             return true, names(d, key)
         end},
        {name = "Rally the Disheartened", text = "Sympathy +" .. I.RALLY_SYMPATHY .. " on every world you hold.",
         flavour = "Mon Mothma speaks across the HoloNet to every Alliance world: the war is long, but the Republic "
             .. "is worth it. On a hundred worlds, people listen.",
         run = function(d)
             local keys = {}
             for _, w in ipairs(U.worlds_of(d.human)) do
                 table.insert(keys, w.key)
             end
             change_sympathy(d, keys, I.RALLY_SYMPATHY)
             return true
         end},
        {name = "Broadcast a Call to Action",
         text = "Every Sympathetic world of a power at war with you revolts for the side it prefers: the owner's forces "
             .. "withdraw and the rebels' own garrison holds it (never a capital; worlds where a battle may be pending "
             .. "revolt when it is over).",
         flavour = "\"The time has come.\" Mon Mothma's voice reaches every world under its enemies' heel, and those "
             .. "who waited for a sign rise as one.",
         run = function(d)
             local keys = call_targets(d)
             if not keys[1] then
                 return false, "No Sympathetic world of a power at war with you would rise now."
             end
             local c = state(d)
             c.call_queue = c.call_queue or {}
             for _, key in ipairs(keys) do
                 local planet = FindPlanet(key)
                 table.insert(c.call_queue, {key = key, owner = string.upper(planet.Get_Owner().Get_Faction_Name())})
             end
             return true
         end},
    },
    LEIA = {
        {name = "Diplomatic Overture", target = "POWER", text = "A power's opinion of you +" .. I.OVERTURE_OPINION .. ".",
         flavour = "Leia Organa arrives in person at the court of {target}, bearing gifts and Alderaan's memory. She is "
             .. "received warmly.",
         run = function(d, faction)
             goodwill(d, faction, I.OVERTURE_OPINION)
             return true, d.display_name(faction)
         end},
        {name = "Voice of Alderaan", target = "POWER",
         text = "Every deal with a power +" .. I.VOICE_ACCEPTANCE .. " acceptance for " .. I.VOICE_WEEKS .. " weeks.",
         flavour = "Alderaan's last princess pleads the Alliance's cause before {target}. For a time, its diplomats "
             .. "are readier to listen.",
         run = function(d, faction)
             local e = state(d).effects
             e.voice = e.voice or {}
             e.voice[faction] = weeks_from_now(I.VOICE_WEEKS)
             return true, d.display_name(faction)
         end},
        {name = "The Princess's Word", target = "WAR_POWER_OR_WORLD",
         text = "A power at war with you (not the Galactic Empire) makes peace at once, or an independent world "
             .. "becomes your protectorate.",
         flavour = "Leia Organa gives {target} her word: the Alliance will stand by its promises. They believe her.",
         run = function(d, target)
             local world = string.sub(target, 1, 6) == "WORLD:" and string.sub(target, 7)
             if world then
                 local planet = FindPlanet(world)
                 if not planet or U.category(planet.Get_Owner().Get_Faction_Name()) ~= "INDEPENDENT" then
                     return false, "That world is no longer independent."
                 end
                 local P = require("eawx-plugins/new-republic/RepublicProtectorates")
                 if not P.protect_world(d, planet, d:planet_name(planet)) then
                     return false, "It cannot take the Alliance's protection now."
                 end
                 return true, d:planet_name(planet)
             end
             d:set_relation(target, "CEASEFIRE", " (Leia Organa's word)")
             return true, d.display_name(target)
         end},
    },
    ACKBAR = {
        {name = "Fleet Drills", text = "Warships 15% cheaper and 25% quicker to build for " .. I.DRILLS_WEEKS .. " weeks.",
         flavour = "Admiral Ackbar drives the fleet through exercises day and night. Shipyards and crews alike learn to "
             .. "work faster.",
         run = function(d)
             state(d).effects.fleet_until = weeks_from_now(I.DRILLS_WEEKS)
             Influence.keep_dummies(d)
             return true
         end},
        {name = "Mon Calamari Shipyards", text = "Two Mon Calamari cruisers at Dac (or the capital).",
         flavour = "The shipyards of Dac answer Ackbar's call: two star cruisers leave the slips for the Alliance.",
         run = function(d)
             local dac = FindPlanet("MON_CALAMARI")
             local planet = (dac and dac.Get_Owner() == d.human) and dac or capital_planet(d)
             local cruiser = first_type({"MC80_Liberty", "MC80B", "MC40a"})
             if not (planet and cruiser) then
                 return false, "No shipyard can deliver them now."
             end
             spawn_at(d, planet, {cruiser, cruiser})
             return true
         end},
        {name = "The Fleet Answers the Call", target = "OWNED_WORLD",
         text = "A battle group (2 Mon Calamari star cruisers, 4 escorts, fighters) at one of your worlds; fleet upkeep "
             .. "halved for " .. I.UPKEEP_WEEKS .. " weeks.",
         flavour = "Ackbar gathers every ship Mon Calamari can spare into a battle group over {target}, and the "
             .. "Council halves the fleet's upkeep to keep it flying.",
         run = function(d, key)
             local planet = FindPlanet(key)
             if not planet or planet.Get_Owner() ~= d.human then
                 return false, "That world is no longer yours."
             end
             local cruiser = first_type({"MC80_Liberty", "MC80B", "MC90"}) or "MC40a"
             local escort = first_type({"MC40a", "Nebulon_B_Frigate"})
             local corvette = first_type({"CR90", "DP20"})
             spawn_at(d, planet, {cruiser, cruiser, escort, escort, corvette, corvette, "X_Wing", "X_Wing", "A_Wing",
                                  "B_Wing"})
             state(d).effects.upkeep_until = weeks_from_now(I.UPKEEP_WEEKS)
             return true, names(d, key)
         end},
    },
    FEYLYA = {
        {name = "Bothan Whispers", target = "NETWORK", text = "A spy network +1 tier.",
         flavour = "Borsk Fey'lya calls in a favour from the SpyNet. New eyes open inside {target}.",
         run = function(d, target)
             local Intel = require("eawx-plugins/new-republic/RepublicIntel")
             Intel.raise(d, target, "Bothan whispers")
             return true, Intel.label(d, target)
         end},
        {name = "Backroom Deals",
         text = "+" .. I.BACKROOM_CAPITAL .. " political capital; every Councillor's opinion +" .. I.BACKROOM_OPINION .. ".",
         flavour = "Fey'lya works the corridors: a word here, a promise there. The Councillors find themselves "
             .. "agreeing with the government, and owing it favours.",
         run = function(d)
             local r = d.republic
             r.capital = M.min(R.CAPITAL_MAX, r.capital + I.BACKROOM_CAPITAL)
             for _, councillor in ipairs(C.COUNCILLORS) do
                 if council().alive(d, councillor.key) then
                     council().sway(d, councillor.key, I.BACKROOM_OPINION, "Fey'lya's backroom deals")
                 end
             end
             return true
         end},
        {name = "Many Bothans Died", target = "NETWORK",
         text = "A spy network to tier 3 at once; its next operation is free, sure to succeed and never caught.",
         flavour = "Fey'lya reminds the Council what the SpyNet paid for the Death Star's plans, and the SpyNet pays "
             .. "again: {target} lies open to Alliance Intelligence.",
         run = function(d, target)
             local Intel = require("eawx-plugins/new-republic/RepublicIntel")
             local n = Intel.network(d, target)
             local top = M.min(3, Intel.max_tier(target))
             local guard = 0
             while n.tier < top and guard < 5 do
                 Intel.raise(d, target, "many Bothans died")
                 guard = guard + 1
             end
             Intel.free_op(d, target)
             return true, Intel.label(d, target)
         end},
    },
    TEVV = {
        {name = "SoroSuub Contracts", text = I.TEVV_CREDITS .. " credits.",
         flavour = "Sian Tevv persuades SoroSuub's board to sell to the Alliance on credit: " .. I.TEVV_CREDITS
             .. " credits in contracts.",
         run = function(d)
             d.human.Give_Money(I.TEVV_CREDITS)
             return true
         end},
        {name = "Sullustan Volunteers", text = "Three starfighter squadrons at the capital.",
         flavour = "Sullustan pilots, the finest navigators in the galaxy, volunteer for the Alliance's starfighter "
             .. "corps.",
         run = function(d)
             local planet = capital_planet(d)
             if not planet then
                 return false, "The Alliance has no capital to send them to."
             end
             spawn_at(d, planet, {"X_Wing", "A_Wing", "B_Wing"})
             return true
         end},
        {name = "SoroSuub Joins the Cause",
         text = I.SOROSUUB_CREDITS .. " credits; every unit 20% cheaper for " .. I.SOROSUUB_WEEKS .. " weeks.",
         flavour = "SoroSuub breaks with the Empire. Its factories, its credits and its contracts serve the Alliance "
             .. "now.",
         run = function(d)
             d.human.Give_Money(I.SOROSUUB_CREDITS)
             state(d).effects.sorosuub_until = weeks_from_now(I.SOROSUUB_WEEKS)
             Influence.keep_dummies(d)
             return true
         end},
    },
    BERUSS = {
        {name = "Corellian Diplomatic Corps",
         text = "Every independent power's opinion of you +" .. I.CORPS_OPINION .. ".",
         flavour = "Doman Beruss sends the Corellian Diplomatic Corps to the galaxy's free powers. Old friendships are "
             .. "remembered.",
         run = function(d)
             for _, faction in ipairs(powers(d, function(f)
                 local kind = U.category(f)
                 return kind == "FREE" or kind == "INDEPENDENT"
             end)) do
                 goodwill(d, faction, I.CORPS_OPINION)
             end
             return true
         end},
        {name = "Corellian Engineering Contracts", target = "OWNED_WORLD",
         text = "Three Corellian corvettes and gunships at one of your worlds.",
         flavour = "Corellian Engineering delivers three ships to {target}, paid for by Beruss's friends in the "
             .. "shipyards.",
         run = function(d, key)
             local planet = FindPlanet(key)
             if not planet or planet.Get_Owner() ~= d.human then
                 return false, "That world is no longer yours."
             end
             spawn_at(d, planet, {"CR90", "CR90", "DP20"})
             return true, names(d, key)
         end},
        {name = "Corellian Accord",
         text = "The Corellia faction allies with you; without it in the galaxy, every independent world's sympathy +"
             .. I.ACCORD_SYMPATHY .. ".",
         flavour = "Doman Beruss calls in a lifetime of favours. {target}",
         run = function(d)
             if council().corellia_open and council().corellia_open(d) then
                 d:set_relation(C.CORELLIA, "ALLIANCE", " (the Corellian Accord)")
                 return true, "Corellia signs the Accord and stands with the Alliance."
             end
             change_sympathy(d, worlds_where(function(planet)
                 return U.category(planet.Get_Owner().Get_Faction_Name()) == "INDEPENDENT"
             end), I.ACCORD_SYMPATHY)
             return true, "Corellia's voice carries across the free worlds, and they listen."
         end},
    },
    KERRITHRARR = {
        {name = "Wookiee Honour Guard", target = "OWNED_WORLD", text = "Wookiee warriors at one of your worlds.",
         flavour = "Kerrithrarr's kin answer a debt older than the Rebellion: Wookiee warriors stand guard on {target}.",
         run = function(d, key)
             local planet = FindPlanet(key)
             local wookiee = first_type({"Partisan_Wookiee_Squad", "Wookiee_Flutter_Company"})
             if not planet or planet.Get_Owner() ~= d.human or not wookiee then
                 return false, "They cannot reach that world now."
             end
             spawn_at(d, planet, {wookiee, wookiee, wookiee})
             return true, names(d, key)
         end},
        {name = "Break the Chains", text = "Every Imperial-held world's sympathy +" .. I.CHAINS_SYMPATHY .. ".",
         flavour = "Kerrithrarr speaks for every people the Empire enslaved. On Imperial worlds, the slaves and their "
             .. "children listen.",
         run = function(d)
             change_sympathy(d, worlds_where(function(planet)
                 local kind = U.category(planet.Get_Owner().Get_Faction_Name())
                 return kind == "IMPERIAL" or kind == "WARLORD"
             end), I.CHAINS_SYMPATHY)
             return true
         end},
        {name = "Rise of the Free Peoples",
         text = "Native fighters (never humans) join you on every world you hold that has a native people.",
         flavour = "From Kashyyyk to the Outer Rim, the peoples the Empire despised take up arms for the Alliance.",
         run = function(d)
             local NATIVES = require("eawx-plugins/diplomacy/DiplomacyNatives")
             local n = 0
             for _, w in ipairs(U.worlds_of(d.human)) do
                 for _, t in ipairs(NATIVES[w.key] or {}) do
                     if string.find(t, "^Partisan_") then
                         n = n + spawn_at(d, w.planet, {t})
                         break
                     end
                 end
             end
             if n == 0 then
                 return false, "None of your worlds has a native people to rise."
             end
             return true
         end},
    },
    VERRINNEFRA = {
        {name = "Lommite Shipments", text = I.LOMMITE_CREDITS .. " credits.",
         flavour = "Elom's lommite mines, free of their Imperial overseers, send their first shipment to the Alliance: "
             .. I.LOMMITE_CREDITS .. " credits.",
         run = function(d)
             d.human.Give_Money(I.LOMMITE_CREDITS)
             return true
         end},
        {name = "Voice of the Small Worlds", text = "Every independent world's sympathy +" .. I.SMALL_SYMPATHY .. ".",
         flavour = "Verrinnefra speaks for the worlds no one listens to. On the galaxy's free worlds, they hear that "
             .. "the Alliance does.",
         run = function(d)
             change_sympathy(d, worlds_where(function(planet)
                 return U.category(planet.Get_Owner().Get_Faction_Name()) == "INDEPENDENT"
             end), I.SMALL_SYMPATHY)
             return true
         end},
        {name = "Unity of the Many",
         text = "Cohesion +" .. I.UNITY_COHESION .. " (fading over " .. I.UNITY_WEEKS .. " weeks); mandate +"
             .. I.UNITY_MANDATE .. ".",
         flavour = "Verrinnefra reminds the Council that the Alliance is many peoples, not one. Old quarrels are set "
             .. "aside, and the galaxy notices.",
         run = function(d)
             state(d).effects.unity_at = GetCurrentTime()
             republic().change_mandate(d, I.UNITY_MANDATE)
             return true
         end},
    },
}
Influence.ACTIONS = ACTIONS

function Influence.actions(key)
    return ACTIONS[key] or {}
end

function Influence.can_use(d, key, tier)
    local action = ACTIONS[key] and ACTIONS[key][tier]
    if not action then
        return false, "No such action."
    end
    if not council().active(d) then
        return false, "Only the Provisional Council's members can do this."
    end
    if not council().alive(d, key) then
        return false, "That seat is empty."
    end
    local cost = I.TIERS[tier]
    if Influence.value(d, key) < cost then
        return false, "Needs " .. cost .. " Galactic Influence (" .. Influence.value(d, key) .. " now)."
    end
    if action.target and not TARGETS[action.target].list(d)[1] then
        return false, "There is no one to do it for now."
    end
    return true
end

function Influence.use(d, key, tier, target)
    local ok, why = Influence.can_use(d, key, tier)
    if not ok then
        return false, why
    end
    local action = ACTIONS[key][tier]
    local done, detail = action.run(d, target)
    if not done then
        return false, detail
    end
    Influence.add(d, key, -I.TIERS[tier])
    local c = state(d)
    local id = key .. tier
    if not c.said[id] or GetCurrentTime() - c.said[id] >= U.weeks(1) then
        c.said[id] = GetCurrentTime()
        local text = string.gsub(action.flavour, "{target}", detail or "")
        d.show(council().short(council().BY_KEY[key]) .. ": " .. action.name .. ". " .. text, nil, GOLD, 30)
    end
    return true, action.name .. ": done."
end

return Influence
