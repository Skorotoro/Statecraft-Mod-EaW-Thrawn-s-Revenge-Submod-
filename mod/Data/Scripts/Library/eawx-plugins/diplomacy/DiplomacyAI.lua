local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")

DiplomacyAI = {}

local STEP = {WAR = 0, CEASEFIRE = 1, ALLIANCE = 2, PROTECTORATE = 2, VASSAL = 3}

function DiplomacyAI.context(name_of)
    return {strength = {}, planets = {}, jumps = {}, name_of = name_of}
end

local function planets_of(ctx, player)
    local name = player.Get_Faction_Name()
    if not ctx.planets[name] then
        local list = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            if planet.Get_Owner() == player then
                table.insert(list, planet)
            end
        end
        ctx.planets[name] = list
    end
    return ctx.planets[name]
end

function DiplomacyAI.strength(ctx, player)
    local name = player.Get_Faction_Name()
    if not ctx.strength[name] then
        local total = table.getn(planets_of(ctx, player)) * CONFIG.PLANET_STRENGTH
        for _, unit in pairs(Find_All_Objects_Of_Type(player) or {}) do
            if TestValid(unit) and is_valid_category(unit) then
                local ok, rating = pcall(unit.Get_Type().Get_Combat_Rating)
                if ok then
                    total = total + M.min(M.max(M.sane(rating), 0), 1000000)
                end
            end
        end
        ctx.strength[name] = M.max(total, 1)
    end
    return ctx.strength[name]
end

function DiplomacyAI.jumps(ctx, a, b)
    local key = a.Get_Faction_Name() .. "|" .. b.Get_Faction_Name()
    if ctx.jumps[key] == nil then
        local best_a, best_b, best_d = nil, nil, nil
        for _, pa in pairs(planets_of(ctx, a)) do
            for _, pb in pairs(planets_of(ctx, b)) do
                local d = pa.Get_Distance(pb)
                if not best_d or d < best_d then
                    best_a, best_b, best_d = pa, pb, d
                end
            end
        end
        local result = false
        if best_a then
            local path = Find_Path(a, best_a, best_b)
            if path then
                result = M.max(table.getn(path) - 1, 1)
            end
        end
        ctx.jumps[key] = result
    end
    return ctx.jumps[key] or nil
end

local function scaled(ratio, rule)
    local points = rule.per_doubling * M.log2(ratio)
    return M.max(-rule.cap, M.min(rule.cap, points))
end

function DiplomacyAI.decay(time)
    local weeks = (GetCurrentTime() - time) / CONFIG.WEEK_SECONDS
    return M.half_pow(weeks / CONFIG.HALF_LIFE_WEEKS)
end

function DiplomacyAI.far(add, jumps)
    if not jumps then
        add(CONFIG.FAR_TREATY + 3 * CONFIG.FAR_PER_JUMP, "you are far beyond reach of their worlds")
    elseif jumps > CONFIG.FAR_JUMPS then
        add(CONFIG.FAR_TREATY + CONFIG.FAR_PER_JUMP * (jumps - CONFIG.FAR_JUMPS - 1),
            "your nearest world is " .. jumps .. " jumps away")
    end
end

function DiplomacyAI.evaluate(ctx, human, target, current, request, memory, opinion)
    local factors = {}
    local function add(points, text)
        points = M.round(points)
        if points ~= 0 then
            table.insert(factors, {points, text})
        end
    end
    local them_name = target.Get_Faction_Name()
    local us = human.Get_Faction_Name()
    local protection = request == "PROTECTORATE"
    local subject = protection or request == "VASSAL"
    if protection then
        request = "ALLIANCE"
    end

    local ok_w, Worlds = pcall(require, "eawx-plugins/diplomacy/DiplomacyWorlds")
    local lone = ok_w and Worlds and Worlds.is_slot(them_name)
    if subject then
        add(lone and CONFIG.SUBJECT_INDEPENDENT_BASE or (protection and CONFIG.BASE.PROTECTORATE or CONFIG.BASE.VASSAL),
            "reluctance to commit")
    else
        add(CONFIG.BASE[request], "reluctance to commit")
    end
    if STEP[request] - STEP[current] > 1 then
        add(CONFIG.SKIPPED_STEP * (STEP[request] - STEP[current] - 1), "too big a step from " .. string.lower(current))
    end
    local alone = request == "ALLIANCE" and (CONFIG.ISOLATIONIST or {})[string.upper(target.Get_Faction_Name())]
    if alone then
        local year = GlobalValue.Get("GALACTIC_YEAR")
        if not alone.to_year or (tonumber(year) or 0) <= alone.to_year then
            add(alone.points, "they keep to themselves")
        end
    end

    add(opinion or 0, "their opinion of you")

    local ratio = DiplomacyAI.strength(ctx, human) / DiplomacyAI.strength(ctx, target)
    local strength_text = "you are " .. string.format("%.1f", ratio) .. "x their strength"
    add(scaled(ratio, CONFIG.STRENGTH[request]), strength_text)
    local jumps = DiplomacyAI.jumps(ctx, human, target)
    if jumps and jumps <= CONFIG.THREAT_JUMPS and ratio > 1 then
        add(CONFIG.THREAT[request], "your forces are " .. jumps .. " jump(s) from their worlds")
    end
    if STEP[request] >= STEP.ALLIANCE then
        DiplomacyAI.far(add, jumps)
    end

    local strongest, strongest_ratio, fronts = nil, 1, 0
    for _, faction in pairs(CONSTANTS.ALL_FACTIONS_NOT_NEUTRAL) do
        if faction ~= us and faction ~= them_name then
            local other = Find_Player(faction)
            if other and target.Is_Enemy(other) and table.getn(planets_of(ctx, other)) > 0 then
                local near = DiplomacyAI.jumps(ctx, other, target)
                if near and near <= CONFIG.THREAT_JUMPS then
                    fronts = fronts + 1
                    if human.Is_Enemy(other) then
                        local r = DiplomacyAI.strength(ctx, other) / DiplomacyAI.strength(ctx, target)
                        if r > strongest_ratio then
                            strongest, strongest_ratio = faction, r
                        end
                    end
                end
            end
        end
    end
    if strongest then
        add(scaled(strongest_ratio, CONFIG.COMMON_ENEMY[request]),
            "common enemy: " .. ctx.name_of(strongest) .. " (" .. string.format("%.1f", strongest_ratio) .. "x their strength)")
    end
    if fronts > 0 then
        add(M.min(CONFIG.FRONTS_CAP, fronts * CONFIG.PER_OTHER_FRONT[request]),
            "fighting on " .. fronts .. " other front(s)")
    end
    if protection and fronts > 0 then
        local ok, R = pcall(require, "eawx-plugins/new-republic/RepublicConfig")
        add(ok and R.PROTECTORATE.OFFER_POINTS or 12, "the Republic's protection against their enemies")
    end

    local total = 0
    for _, factor in pairs(factors) do
        total = total + factor[1]
    end
    table.sort(factors, function(x, y) return M.abs(x[1]) > M.abs(y[1]) end)
    return total, factors
end

local function same_planet(a, b)
    return a and b and a.Get_Type().Get_Name() == b.Get_Type().Get_Name()
end

function DiplomacyAI.jumps_to(ctx, player, planet)
    local best, best_d = nil, nil
    for _, own in pairs(planets_of(ctx, player)) do
        local d = own.Get_Distance(planet)
        if not best_d or d < best_d then
            best, best_d = own, d
        end
    end
    if not best then
        return nil
    end
    if same_planet(best, planet) then
        return 0
    end
    local path = Find_Path(player, best, planet)
    if not path then
        return nil
    end
    return M.max(table.getn(path) - 1, 1)
end

function DiplomacyAI.strength_at(player, planet)
    local total = 0
    for _, unit in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(unit) and is_valid_category(unit) and same_planet(unit.Get_Planet_Location(), planet) then
            local ok, rating = pcall(unit.Get_Type().Get_Combat_Rating)
            if ok then
                total = total + M.min(M.max(M.sane(rating), 0), 1000000)
            end
        end
    end
    return total
end

function DiplomacyAI.evaluate_world(ctx, human, planet, memory)
    local rules = CONFIG.WORLD
    local factors = {}
    local function add(points, text)
        points = M.round(points)
        if points ~= 0 then
            table.insert(factors, {points, text})
        end
    end
    local owner = planet.Get_Owner()
    local us = human.Get_Faction_Name()

    add(rules.BASE, "a world values its independence")
    local family = CONSTANTS.ALIASES[us] or us
    if rules.FAMILY[us] then
        add(rules.FAMILY[us][1], rules.FAMILY[us][2])
    elseif rules.FAMILY[family] then
        add(rules.FAMILY[family][1], rules.FAMILY[family][2])
    end

    local jumps = DiplomacyAI.jumps_to(ctx, human, planet)
    if jumps and jumps <= 1 then
        add(rules.BORDER, "it borders your territory")
    else
        add(rules.NOT_BORDER, "it is far from your territory")
    end
    DiplomacyAI.far(add, jumps)

    local threats = 0
    for _, faction in pairs(CONSTANTS.ALL_FACTIONS_NOT_NEUTRAL) do
        local other = Find_Player(faction)
        if other and other ~= human and other ~= owner and owner.Is_Enemy(other) then
            local near = DiplomacyAI.jumps_to(ctx, other, planet)
            if near and near <= CONFIG.THREAT_JUMPS then
                threats = threats + 1
            end
        end
    end
    if threats > 0 then
        add(M.min(rules.THREATENED_CAP, threats * rules.THREATENED_PER),
            threats .. " hostile neighbour(s) threaten it")
    end

    local yours = DiplomacyAI.strength_at(human, planet)
    if yours > 0 then
        local garrison = M.max(DiplomacyAI.strength_at(owner, planet), 1)
        add(scaled(M.max(yours / garrison, 1), rules.FLEET), "your forces in orbit")
    end

    local attacks = 0
    for _, time in pairs(memory.independent_attacks or {}) do
        attacks = attacks + rules.ATTACKED_INDEPENDENT * DiplomacyAI.decay(time)
    end
    add(M.max(attacks, rules.ATTACKED_CAP), "you attacked other independent worlds")

    local lost = 0
    for _, time in pairs(memory.lost_vassals or {}) do
        lost = lost + rules.LOST_VASSAL * DiplomacyAI.decay(time)
    end
    add(M.max(lost, rules.LOST_VASSAL_CAP), "you failed to protect your vassal worlds")

    local ok, Reputation = pcall(require, "eawx-plugins/diplomacy/DiplomacyReputation")
    if ok then
        add(Reputation.penalty(us, true), "your " .. string.lower(Reputation.word(us)) .. " reputation")
    end

    local total = 0
    for _, factor in pairs(factors) do
        total = total + factor[1]
    end
    table.sort(factors, function(x, y) return M.abs(x[1]) > M.abs(y[1]) end)
    return total, factors
end

function DiplomacyAI.only(factors, sign)
    local out = {}
    for i = 1, table.getn(factors) do
        if factors[i][1] * sign > 0 then
            table.insert(out, factors[i])
        end
    end
    return out
end

function DiplomacyAI.describe(factors, limit)
    local text = ""
    local count = table.getn(factors)
    if count == 0 then
        return "nothing in particular"
    end
    if limit and limit < count then
        count = limit
    end
    for i = 1, count do
        local factor = factors[i]
        local sign = ""
        if factor[1] > 0 then
            sign = "+"
        end
        if i > 1 then
            text = text .. ", "
        end
        text = text .. sign .. factor[1] .. " " .. factor[2]
    end
    return text
end

return DiplomacyAI
