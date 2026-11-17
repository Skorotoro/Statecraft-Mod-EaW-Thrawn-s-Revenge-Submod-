local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Senate = require("eawx-plugins/diplomacy/DiplomacySenate")
local POPULATIONS = require("eawx-plugins/diplomacy/DiplomacyPopulations")
require("eawx-plugins/diplomacy/DiplomacyAI")

local Underworld = require("eawx-plugins/diplomacy/DiplomacyUnderworld")
local Worlds = require("eawx-plugins/diplomacy/DiplomacyWorlds")
local Reputation = require("eawx-plugins/diplomacy/DiplomacyReputation")
local Trade = require("eawx-plugins/diplomacy/DiplomacyTrade")
local Opinions = require("eawx-plugins/diplomacy/DiplomacyOpinions")
local Deals = {}

local function rules()
    return CONFIG.DEALS
end

local function weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

local RELATION_NOUN = {CEASEFIRE = "a ceasefire", ALLIANCE = "an alliance", VASSAL = "vassalage",
                       PROTECTORATE = "protection"}

local function Republic_mandate(d)
    local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
    return (ok and Republic and Republic.mandate(d)) or 0
end

local function republic_part(name)
    local ok, mod = pcall(require, "eawx-plugins/new-republic/" .. name)
    return ok and type(mod) == "table" and mod or nil
end

function Deals.label(d, item)
    if item.kind == "TREATY" then
        if item.relation == "PROTECTORATE" then
            return "The Republic's protection"
        end
        return (item.relation == "VASSAL") and "Become our vassal" or ((item.relation == "ALLIANCE") and "Alliance" or "Ceasefire")
    elseif item.kind == "CREDITS" then
        return item.amount .. " credits"
    elseif item.kind == "WORLD" then
        local planet = FindPlanet(item.world)
        return "World: " .. (planet and d:planet_name(planet) or item.world)
    elseif item.kind == "TRIBUTE" then
        return item.amount .. " credits a week, " .. item.weeks .. " weeks"
    elseif item.kind == "PACT" then
        return "Non-aggression, " .. item.weeks .. " weeks"
    elseif item.kind == "TRADE" then
        return "Trade agreement"
    elseif item.kind == "BORDERS" then
        return item.open and "Open borders" or "Close borders"
    elseif item.kind == "JOINWAR" then
        return "Join our war: " .. d.display_name(item.target)
    elseif item.kind == "JOINT" then
        return require("eawx-plugins/diplomacy/DiplomacyJointInvasion").item_text(d, item)
    end
    return "?"
end

local function money_factor(player, steps)
    steps = steps or rules().MONEY_FACTORS
    local credits = player and player.Get_Credits() or 0
    for _, step in ipairs(steps) do
        if credits < step[1] then
            return step[2]
        end
    end
    return steps[table.getn(steps)][2]
end

function Deals.gift_opinion(d, faction)
    local total = 0
    local keep = {}
    for _, g in ipairs(d.gifts and d.gifts[faction] or {}) do
        local left = 1 - (GetCurrentTime() - g[2]) / weeks(g[3])
        if left > 0 then
            total = total + g[1] * left
            table.insert(keep, g)
        end
    end
    if d.gifts and d.gifts[faction] then
        d.gifts[faction] = keep[1] and keep or nil
    end
    return M.round(M.min(total, rules().GIFT_TOTAL_CAP or total))
end

local function record_gift(d, target, deal)
    local r = rules()
    local them = Find_Player(target)
    for _, item in ipairs(deal) do
        if item.side ~= "offer" or item.kind == "TREATY" or item.kind == "PACT" or item.kind == "TRADE"
                or item.kind == "BORDERS" then
            return
        end
    end
    local credits, world, length = 0, 0, 0
    for _, item in ipairs(deal) do
        if item.kind == "CREDITS" or item.kind == "TRIBUTE" then
            local amount = item.amount * (item.weeks or 1)
            credits = credits + money_factor(them, r.GIFT_FACTORS) * amount / r.GIFT_CREDITS
            length = M.max(length, M.min(r.GIFT_MAX_WEEKS, r.GIFT_WEEKS + M.floor(amount / r.GIFT_CREDITS_PER_WEEK)))
        elseif item.kind == "WORLD" then
            world = world + r.GIFT_WORLD + r.GIFT_WORLD_PER_TIER * (POPULATIONS[item.world] or 0)
            length = M.max(length, r.GIFT_WORLD_WEEKS)
        end
    end
    local points = M.min(r.GIFT_CAP, credits) + world
    if points >= 1 and length > 0 then
        d.gifts = d.gifts or {}
        d.gifts[target] = d.gifts[target] or {}
        local before = Deals.gift_opinion(d, target)
        table.insert(d.gifts[target], {M.round(points), GetCurrentTime(), length})
        Opinions.nudge(target, d.human.Get_Faction_Name(), Deals.gift_opinion(d, target) - before)
    end
end

local function band_cost(d, ctx, them, half)
    local cost = rules().BAND_COST[Deals.attitude_word(Deals.attitude(d, ctx, them))] or 0
    return half and cost * CONFIG.SUBJECT_INDEPENDENT_BAND or cost
end

function Deals.borders_open(d, faction)
    return d.open_borders ~= nil and d.open_borders[faction] == true
end

function Deals.set_borders(d, faction, open)
    d.open_borders = d.open_borders or {}
    d.open_borders[faction] = open and true or nil
end

local function world_tier(name)
    return POPULATIONS[name] or 0
end

local function is_capital(d, player, name)
    local cap = Deals.capital(d, player)
    return cap and string.upper(cap.Get_Type().Get_Name()) == name
end

function Deals.capital(d, player)
    local C = ModContentLoader.get("GameConstants")
    local entry = C.ALL_FACTIONS_CAPITALS and C.ALL_FACTIONS_CAPITALS[player.Get_Faction_Name()]
    if entry and entry.STRUCTURE then
        for _, obj in pairs(Find_All_Objects_Of_Type(entry.STRUCTURE) or {}) do
            if TestValid(obj) and obj.Get_Owner() == player then
                return obj.Get_Planet_Location()
            end
        end
    end
    if entry and not entry.STRUCTURE and entry.LOCATION then
        local owned = Deals.worlds_of(player)
        for _, home in ipairs(entry.LOCATION) do
            for _, planet in ipairs(owned) do
                if string.upper(planet.Get_Type().Get_Name()) == home then
                    return planet
                end
            end
        end
    end
    local owned = Deals.worlds_of(player)
    if table.getn(owned) == 1 then
        return owned[1]
    end
    return nil
end

local function worlds_of(player)
    local out = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            table.insert(out, planet)
        end
    end
    return out
end

local function borders_interest(d, them)
    local enemy = nil
    for faction, _ in pairs(Opinions.world().powers or {}) do
        local p = Find_Player(faction)
        if p and p ~= them and p ~= d.human and them.Is_Enemy(p) and d.human.Is_Enemy(p)
                and faction ~= "INDEPENDENT_FORCES" and faction ~= "NEUTRAL" then
            enemy = faction
            break
        end
    end
    local border = false
    local mine = {}
    for _, planet in ipairs(worlds_of(d.human)) do
        mine[string.upper(planet.Get_Type().Get_Name())] = true
    end
    for _, planet in ipairs(worlds_of(them)) do
        for _, other in ipairs(Trade.neighbours(d, planet) or {}) do
            if mine[other] then
                border = true
                break
            end
        end
        if border then
            break
        end
    end
    return enemy, border
end
Deals.worlds_of = worlds_of

local world_cache = {}
function Deals.world_attitude(d, ctx, planet)
    if not planet then
        return 0
    end
    local key = planet.Get_Type().Get_Name()
    local now = GetCurrentTime()
    local hit = world_cache[key]
    if hit and now >= hit.time and now - hit.time < 10 then
        return hit.value
    end
    local total = DiplomacyAI.evaluate_world(ctx, d.human, planet, d.memory)
    local value = total - CONFIG.WORLD.BASE
    local parts = {{value, "your borders, its threats and your record with free worlds"}}
    local Sym = d.republic and republic_part("RepublicSympathy")
    local ok, sym = false, nil
    if Sym then
        ok, sym = pcall(Sym.value, d, string.upper(key))
    end
    if ok and type(sym) == "number" then
        local share = rules().SYMPATHY_SHARE
        parts = {{share * (sym - 50) * 1.2, "its people's sympathy (" .. M.round(sym) .. ")"},
                 {(1 - share) * value, "your borders, its threats and your record with free worlds"}}
        value = share * (sym - 50) * 1.2 + (1 - share) * value
    end
    local grudge = d.memory.world_grudges and d.memory.world_grudges[string.upper(key)]
    if grudge then
        local left = grudge.value * M.half_pow((now - grudge.time) / CONFIG.WEEK_SECONDS / CONFIG.CONQUEST.GRUDGE_HALF)
        if M.abs(left) >= 1 then
            table.insert(parts, {left, "you invaded it before you set it free"})
            value = value + left
        else
            d.memory.world_grudges[string.upper(key)] = nil
        end
    end
    local marks = d.republic and d.memory.occupation_marks
    if marks and marks[1] then
        local RC = republic_part("RepublicConfig")
        local fade = RC and RC.OCCUPY_COSTS and RC.OCCUPY_COSTS.FADE_WEEKS or 8
        local sum, kept = 0, {}
        for _, mark in ipairs(marks) do
            local left = M.min(0, mark.value + (now - mark.time) / CONFIG.WEEK_SECONDS / fade)
            if left < 0 then
                sum = sum + left
                table.insert(kept, mark)
            end
        end
        d.memory.occupation_marks = kept
        if M.round(sum) ~= 0 then
            table.insert(parts, {sum, "the worlds you occupied against their people's will"})
            value = value + sum
        end
    end
    value = M.max(-100, M.min(100, M.round(value)))
    world_cache[key] = {time = now, value = value, parts = parts}
    return value
end

function Deals.world_attitude_tip(d, ctx, planet)
    local att = Deals.world_attitude(d, ctx, planet)
    local hit = planet and world_cache[planet.Get_Type().Get_Name()]
    local lines = {}
    for _, p in ipairs(hit and hit.parts or {}) do
        if M.round(p[1]) ~= 0 then
            table.insert(lines, d.signed(M.round(p[1])) .. " " .. p[2])
        end
    end
    return "Attitude " .. Deals.attitude_word(att) .. " (" .. d.signed(att) .. "): "
        .. ((lines[1] and table.concat(lines, "; ")) or "nothing for or against you") .. "."
end

function Deals.opinion_lines(d, a, b, add)
    local human = string.upper(d.human.Get_Faction_Name())
    if b ~= human or a == human then
        return false
    end
    local R = CONFIG.OPINION
    local now = GetCurrentTime()
    local function weeks_since(t)
        return t and M.max(0, (now - t) / CONFIG.WEEK_SECONDS) or 0
    end
    local relation = d:relation(a)
    local since = d.memory.peace_since[a]
    if since and relation ~= "WAR" then
        add(M.min(R.PEACE_CAP, weeks_since(since) * R.PEACE_PER_WEEK), "your peace has held", 2)
    end
    if relation == "ALLIANCE" and d.memory.signed and d.memory.signed[a] then
        add(M.min(R.ALLIANCE_CAP, M.floor(weeks_since(d.memory.signed[a]) / 10) * R.ALLIANCE_PER_10_WEEKS),
            "your alliance has held", 2)
    end
    if d.trade and d.trade[a] then
        add(M.min(R.TRADE_CAP, weeks_since(d.trade[a]) * R.TRADE_PER_WEEK), "your trade agreement", 2)
    end
    add(Deals.gift_opinion(d, a), "your gifts", 2)
    add(Underworld.attitude(d, a), "the underworld's dealings", 2)
    local Influence = d.republic and republic_part("RepublicInfluence")
    if Influence then
        add(Influence.goodwill(d, a), "the Councillors' diplomacy", 2)
    end
    if IMPERIAL_COURT_ATTITUDE and human == "EMPIRE" then
        local ok, value = pcall(IMPERIAL_COURT_ATTITUDE, a)
        if ok and type(value) == "number" then
            add(value, "the Imperial court's doings", 2)
        end
    end
    if relation == "WAR" then
        add(R.WAR, "at war with you", 3)
    elseif relation == "ALLIANCE" then
        add(R.ALLIANCE, "your alliance", 3)
    elseif relation == "VASSAL" or relation == "PROTECTORATE" then
        add(R.SUBJECT, "you are their overlord", 3)
    else
        add(R.CEASEFIRE, "a ceasefire", 3)
    end
    if d.republic then
        local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
        if ok then
            add(Republic.attitude(d, a), "the Republic's standing", 3)
        end
    end
    return true
end

function Deals.attitude(d, ctx, them)
    local name = them.Get_Faction_Name()
    if Worlds.is_slot(name) then
        local att = Deals.world_attitude(d, ctx, Worlds.world_of(them)) + Deals.gift_opinion(d, name)
        local _, _, groups = Opinions.get(name, d.human.Get_Faction_Name())
        for _, line in ipairs(groups[2][2]) do
            if line[1] ~= "your gifts" then
                att = att + line[2]
            end
        end
        return M.max(-100, M.min(100, M.round(att)))
    end
    local value = Opinions.get(name, d.human.Get_Faction_Name())
    return value
end

function Deals.attitude_tip(d, ctx, them)
    local name = them.Get_Faction_Name()
    local att = Deals.attitude(d, ctx, them)
    local head = "Attitude " .. Deals.attitude_word(att) .. " (" .. d.signed(att) .. ")"
    if Worlds.is_slot(name) then
        local lines = {d.signed(Deals.world_attitude(d, ctx, Worlds.world_of(them))) .. " its view of you as a lone world"}
        local _, _, groups = Opinions.get(name, d.human.Get_Faction_Name())
        for _, line in ipairs(groups[2][2]) do
            table.insert(lines, d.signed(line[2]) .. " " .. line[1])
        end
        return head .. ": " .. table.concat(lines, "; ") .. "."
    end
    local _, _, groups, target = Opinions.get(name, d.human.Get_Faction_Name())
    local trend = Opinions.trend(name, d.human.Get_Faction_Name())
    if trend then
        head = head .. ", " .. trend
    end
    local parts = {}
    for _, g in ipairs(groups) do
        local lines = g[2]
        table.sort(lines, function(x, y) return M.abs(x[2]) > M.abs(y[2]) end)
        if lines[1] then
            local texts = {}
            for _, line in ipairs(lines) do
                table.insert(texts, d.signed(line[2]) .. " " .. line[1])
            end
            table.insert(parts, g[1] .. ": " .. table.concat(texts, ", "))
        end
    end
    local tip = head .. ". " .. ((parts[1] and table.concat(parts, ". ")) or "Nothing for or against you") .. "."
    if target ~= att then
        tip = tip .. " Moving toward " .. d.signed(target) .. "."
    end
    return tip
end

function Deals.attitude_word(att)
    if att <= -40 then
        return "Hostile"
    elseif att <= -10 then
        return "Unfriendly"
    elseif att < 15 then
        return "Indifferent"
    elseif att < 40 then
        return "Friendly"
    end
    return "Very friendly"
end

function Deals.evaluate(d, ctx, them, deal)
    local factors, impossible = {}, nil
    local function add(points, text)
        points = M.round(points)
        if points ~= 0 then
            table.insert(factors, {points, text})
        end
    end
    local name = them.Get_Faction_Name()
    local current = d:relation(name)
    local treaty = nil
    for _, item in ipairs(deal) do
        if item.kind == "TREATY" then
            treaty = item
        end
    end
    if treaty then
        local total, tf = DiplomacyAI.evaluate(ctx, d.human, them, current, treaty.relation, d.memory,
            Deals.attitude(d, ctx, them))
        for _, f in ipairs(tf) do
            add(f[1], f[2])
        end
        if current ~= "WAR" or treaty.relation ~= "CEASEFIRE" then
        end
    else
        add(Deals.attitude(d, ctx, them) / 3, "their attitude towards you")
    end
    local their_worlds = table.getn(worlds_of(them))
    local demanded_worlds = 0
    local money = money_factor(them)
    local subject = treaty and (treaty.relation == "VASSAL" or treaty.relation == "PROTECTORATE")
    if subject and not Worlds.is_slot(name) and their_worlds >= rules().SUBJECT_FROM_WORLD then
        local cost = 0
        for k = rules().SUBJECT_FROM_WORLD, M.min(their_worlds, rules().SUBJECT_TO_WORLD) do
            cost = cost + rules().SUBJECT_FIRST + rules().SUBJECT_STEP * (k - rules().SUBJECT_FROM_WORLD)
        end
        add(-cost, "a power of " .. their_worlds .. " worlds won't be anyone's subject")
    end
    if subject then
        add(band_cost(d, ctx, them, Worlds.is_slot(name)), "they are " .. string.lower(Deals.attitude_word(
            Deals.attitude(d, ctx, them))) .. " towards you")
    end
    for _, item in ipairs(deal) do
        if item.kind == "CREDITS" and item.side == "offer" then
            add(money * item.amount / rules().CREDITS_PER_POINT, "your payment of " .. item.amount .. " credits")
        elseif item.kind == "CREDITS" then
            add(-money_factor(them, rules().DEMAND_FACTORS) * item.amount / rules().DEMANDED_CREDITS_PER_POINT,
                "your demand for " .. item.amount .. " credits")
            if them.Get_Credits() < item.amount then
                impossible = "they cannot pay " .. item.amount .. " credits"
            end
        elseif item.kind == "WORLD" and item.side == "offer" then
            local tier = world_tier(item.world)
            add(rules().WORLD_OFFERED + rules().WORLD_PER_TIER * tier, "a world for them")
        elseif item.kind == "WORLD" then
            demanded_worlds = demanded_worlds + 1
            local tier = world_tier(item.world)
            add(-(rules().WORLD_DEMANDED + rules().WORLD_DEMANDED_PER_TIER * tier), "giving up a world")
            if demanded_worlds == 1 then
                add(band_cost(d, ctx, them, false), "they are " .. string.lower(Deals.attitude_word(
                    Deals.attitude(d, ctx, them))) .. " towards you")
            end
            if is_capital(d, them, item.world) then
                impossible = "they will never give up their capital"
            end
        elseif item.kind == "TRIBUTE" and item.side == "offer" then
            add(money * item.amount * item.weeks / rules().TRIBUTE_PER_POINT, "your tribute")
        elseif item.kind == "TRIBUTE" then
            add(-money_factor(them, rules().DEMAND_FACTORS) * item.amount * item.weeks / rules().DEMANDED_TRIBUTE_PER_POINT,
                "tribute they would pay")
        elseif item.kind == "BORDERS" and item.open then
            add(rules().BORDERS_BASE + Deals.attitude(d, ctx, them) / 3, "open borders")
            local enemy, border = borders_interest(d, them)
            if enemy then
                add(rules().BORDERS_COMMON_ENEMY, "a common enemy: " .. d.display_name(enemy))
            end
            if border then
                add(rules().BORDERS_NEIGHBOURS, "your worlds border theirs")
            end
            if current ~= "CEASEFIRE" then
                impossible = "open borders need a ceasefire"
            end
        elseif item.kind == "TRADE" then
            Trade.evaluate(d, name, add)
            local why = Trade.blocked(d, name)
            if why and not (treaty and treaty.relation == "CEASEFIRE") then
                impossible = string.lower(string.sub(why, 1, 1)) .. string.sub(why, 2, -2)
            end
        elseif item.kind == "JOINWAR" then
            local why = require("eawx-plugins/diplomacy/DiplomacyAllies").join_will(d, name, item.target, add)
            if why then
                impossible = why
            end
        elseif item.kind == "PACT" then
            local ratio = DiplomacyAI.strength(ctx, d.human) / M.max(1, DiplomacyAI.strength(ctx, them))
            add((ratio > 1) and rules().PACT_WEAKER or rules().PACT_STRONGER, "safety from your forces")
            if current == "WAR" and not (treaty and treaty.relation ~= "VASSAL") then
                impossible = "a non-aggression pact needs peace first"
            elseif current == "ALLIANCE" or current == "VASSAL" or current == "PROTECTORATE"
                or (treaty and (treaty.relation == "ALLIANCE" or treaty.relation == "VASSAL"
                                or treaty.relation == "PROTECTORATE")) then
                impossible = "your treaty already keeps the peace"
            end
        end
    end
    local binding, trade = treaty ~= nil, false
    for _, item in ipairs(deal) do
        if item.kind == "PACT" or item.kind == "TRADE" then
            binding = true
        elseif (item.kind == "CREDITS" and item.side ~= "offer") or item.kind == "TRIBUTE" or item.kind == "WORLD" then
            trade = true
        end
    end
    if binding or trade then
        local us = d.human.Get_Faction_Name()
        add(Reputation.penalty(us, binding), "your " .. string.lower(Reputation.word(us)) .. " reputation")
    end
    if treaty and d.republic then
        local Gov = republic_part("RepublicGovernment")
        if Gov then
            local ok, points, why = pcall(Gov.treaty_bonus, d)
            if ok and points and points ~= 0 then
                add(points, why)
            end
        end
        local Sym = republic_part("RepublicSympathy")
        if Sym and Worlds.is_slot(name) then
            local ok, points = pcall(Sym.offer_bonus, d, Worlds.world_of(them))
            if ok and points and points ~= 0 then
                add(points, "its people's sympathy for the Republic")
            end
            if treaty.relation == "PROTECTORATE" then
                local ok2, why = pcall(Sym.protection_refused, d, Worlds.world_of(them))
                if ok2 and why then
                    impossible = why
                end
            end
        end
        local Council = republic_part("RepublicCouncil")
        if Council and treaty.relation == "ALLIANCE" then
            local ok, points = pcall(Council.alliance_bonus, d, name)
            if ok and points and points ~= 0 then
                add(points, "Doman Beruss's friends in their government")
            end
        end
    end
    local Influence = d.republic and republic_part("RepublicInfluence")
    if Influence then
        local ok_v, voice = pcall(Influence.voice, d, name)
        if ok_v and voice and voice ~= 0 then
            add(voice, "Leia Organa's voice for the Alliance")
        end
    end
    if d.republic then
        local Council = republic_part("RepublicCouncil")
        local ok, points = false, 0
        if Council then
            ok, points = pcall(Council.acceptance, d, treaty ~= nil)
        end
        if ok and points and points ~= 0 then
            add(points, "the Alliance's mandate (" .. Republic_mandate(d) .. ")")
        end
    end
    if d.republic then
        local Favour = republic_part("RepublicFavour")
        local ok, points = false, 0
        if Favour then
            ok, points = pcall(Favour.acceptance, d)
        end
        if ok and points and points ~= 0 then
            add(points, "Leia Organa's " .. ((points > 0) and "support" or "displeasure"))
        end
    end
    if demanded_worlds > 0 and demanded_worlds >= their_worlds then
        impossible = "they would have no worlds left"
    end
    local total = 0
    for _, f in ipairs(factors) do
        total = total + f[1]
    end
    table.sort(factors, function(x, y) return M.abs(x[1]) > M.abs(y[1]) end)
    return total, factors, impossible
end

function Deals.senate_allows(d, target, item)
    if not d:senate_active() then
        return true
    end
    local name = d.display_name(target)
    if item.kind == "TREATY" and item.relation == "PROTECTORATE" then
        local ok_c, Council = pcall(require, "eawx-plugins/new-republic/RepublicCouncil")
        local planet = Worlds.is_slot(target) and Worlds.world_of(Find_Player(target))
        local key = planet and string.upper(planet.Get_Type().Get_Name())
        local appeal = key and d.appeals and d.appeals[key]
        if ok_c and Council and Council.active(d) and appeal and GetCurrentTime() < appeal.expires then
            if appeal.approved then
                return true
            end
            return false, nil, "The Council must first approve " .. d:planet_name(planet) .. "'s petition (a motion in "
                .. "the Council chamber)."
        end
        if Senate.authorised(d, "protect_ok", Senate.protect_key(target)) then
            return true
        end
        return false, {kind = "PROTECT_AUTH", target = target, world = Senate.protect_key(target),
                       text = "authorise protection for " .. name},
            "Needs a passed motion (Authorise Protection)."
    end
    if item.kind == "TREATY" then
        if item.relation == "VASSAL" then
            return false, {kind = "TREATY", target = target, relation = "VASSAL", text = "take " .. name .. " as a vassal"},
                "The Senate has no mandate for vassalage."
        end
        local order = {CEASEFIRE = 1, ALLIANCE = 2}
        local granted = d.senate.mandates[target]
        if granted and (order[granted] or 0) >= order[item.relation] then
            return true
        end
        return false, Senate.motion_for(d, item.relation, target),
            "Needs a Senate mandate (" .. ((item.relation == "ALLIANCE") and "Authorise an Alliance" or "Authorise Peace Talks") .. ")."
    elseif item.kind == "WAR" then
        if d.senate.approved[target] then
            return true
        end
        return false, Senate.motion_for(d, "WAR", target), "Needs the Senate's approval (Declare War)."
    elseif item.kind == "WORLD" and item.side == "offer" then
        if item.world and Senate.authorised(d, "cede_ok", item.world) then
            return true
        end
        if not item.world then
            for key, ends in pairs(d.senate.cede_ok or {}) do
                if ends > GetCurrentTime() then
                    return true
                end
            end
        end
        return false, {kind = "CEDE", target = target, text = "cede a world to " .. name},
            "Offering a world needs a passed motion (Offer a World in Talks), or an emergency decree."
    end
    return true
end

function Deals.decree_opposition(d, motion)
    local against, total = {}, 0
    if motion.kind == "CEDE" then
        local seats = Senate.seats(d)
        local Council = d.republic and republic_part("RepublicCouncil")
        if Council and Council.active(d) then
            seats = Council.seats(d)
        end
        for name, seat in pairs(seats) do
            total = total + 1
            if seat.opinion < CONFIG.SENATE.LOYAL_OPINION then
                table.insert(against, name)
            end
        end
        return (total > 0) and (table.getn(against) / total) or 1, against
    end
    local result = Senate.tally(d, motion)
    for name, vote in pairs(result.worlds) do
        if vote < 0 then
            table.insert(against, name)
        end
    end
    return result.no / M.max(1, result.yes + result.no + result.abstain), against
end

function Deals.decree_cost(d, motions)
    local share, against = 0, {}
    for _, motion in ipairs(motions) do
        local s, list = Deals.decree_opposition(d, motion)
        share = M.max(share, s)
        for _, name in ipairs(list) do
            against[name] = true
        end
    end
    local n = 0
    for _ in pairs(against) do
        n = n + 1
    end
    local r = CONFIG.SENATE
    local cost = {stability = r.DECREE_STABILITY + M.round(r.DECREE_STABILITY_SCALE * share), opinion = r.DECREE_OPINION,
                  secession = share >= r.DECREE_SECESSION_SHARE, against = against, share = share, count = n}
    local council = d.republic and republic_part("RepublicCouncil")
    local members = (council and council.active(d)) and " Councillor(s)" or " senator(s)"
    local text = "Cohesion -" .. cost.stability .. "; " .. n .. members .. " against it lose " .. cost.opinion
        .. " opinion (" .. M.round(share * 100) .. "% of the chamber opposed)"
    if cost.secession then
        text = text .. "; hostile worlds move closer to secession"
    end
    return cost, text .. "."
end

local function apply_decree(d, cost, what)
    d.senate.stability = M.max(0, d.senate.stability - cost.stability)
    for name, _ in pairs(cost.against) do
        Senate.sway(d, name, -cost.opinion, "the emergency decree to " .. what)
    end
    if cost.secession then
        for name, seat in pairs(Senate.seats(d)) do
            if seat.opinion <= CONFIG.SENATE.HOSTILE_OPINION then
                d.senate.anger[name] = (d.senate.anger[name] or 0) + CONFIG.SENATE.DECREE_SECESSION_WEEKS
            end
        end
    end
    d.senate.overrides = d.senate.overrides + 1
    local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
    local lost = ok and Republic and Republic.senate_mandate and Republic.senate_mandate(d,
        -Republic.CONFIG.SENATE.DECREE_MANDATE)
    d.show(Senate.profile(d).name .. ": the Chancellor acts by emergency decree to " .. what .. ". Cohesion falls to "
        .. d.senate.stability .. "%" .. (lost and (", mandate to " .. Republic.mandate(d)) or "") .. ".", nil,
        {r = 255, g = 190, b = 90}, 25)
end

function Deals.locked(d, faction)
    local ok, names = pcall(GlobalValue.Get, "LOCKED_PLANETS")
    if not ok or type(names) ~= "table" then
        return false
    end
    local locked = {}
    for _, name in pairs(names) do
        if type(name) == "string" then
            locked[string.upper(name)] = true
        end
    end
    local player = Find_Player(faction)
    local any = false
    for _, planet in ipairs(player and Deals.worlds_of(player) or {}) do
        any = true
        if not locked[string.upper(planet.Get_Type().Get_Name())] then
            return false
        end
    end
    return any
end

function Deals.locked_reason(d, faction)
    return d.display_name(faction) .. " has sealed its borders. No envoy can reach them while they are locked away."
end

function Deals.propose(d, target, deal, decree)
    if table.getn(deal) == 0 then
        return false, "Add an offer or a demand first."
    end
    if Deals.locked(d, target) then
        return false, Deals.locked_reason(d, target)
    end
    local them = Find_Player(target)
    local motions = {}
    for _, item in ipairs(deal) do
        local ok, motion, why = Deals.senate_allows(d, target, item)
        if not ok then
            if not decree then
                return false, why
            end
            table.insert(motions, motion)
        end
    end
    for _, item in ipairs(deal) do
        if item.kind == "CREDITS" and item.side == "offer" and d.human.Get_Credits() < item.amount then
            return false, "You cannot pay " .. item.amount .. " credits."
        end
        if item.kind == "TREATY" and item.relation ~= "VASSAL" then
            pcall(Senate.on_offer, d, target, item.relation)
        end
    end
    local ctx = DiplomacyAI.context(d.display_name)
    local total, factors, impossible = Deals.evaluate(d, ctx, them, deal)
    if impossible then
        return false, d.display_name(target) .. " refuse: " .. impossible .. ".",
            {accepted = false, total = -100}
    end
    if total < 0 and not CONFIG.ALWAYS_ACCEPT then
        return false, d.display_name(target) .. " refuse (" .. d.signed(total) .. "). Biggest obstacle: "
            .. DiplomacyAI.describe(DiplomacyAI.only(factors, -1), 1) .. ".", {accepted = false, total = total}
    end
    for _, item in ipairs(deal) do
        if item.kind == "TREATY" and item.relation ~= "VASSAL" and d:relation(target) == "WAR" then
            local winner = d:campaign_winner({[target] = true})
            if winner then
                return false, "This treaty would let " .. d.display_name(winner) .. " and its allies control every "
                    .. "planet, which ends the campaign."
            end
        end
    end
    if table.getn(motions) > 0 then
        local cost = Deals.decree_cost(d, motions)
        apply_decree(d, cost, "make this agreement with " .. d.display_name(target))
    end
    Deals.execute(d, target, deal, total)
    local offered = false
    for _, item in ipairs(deal) do
        if item.side == "offer" or item.kind == "TREATY" or item.kind == "PACT" or item.kind == "TRADE"
                or item.kind == "JOINWAR" then
            offered = true
        end
    end
    return true, d.display_name(target) .. " accept (" .. d.signed(total) .. ").",
        {accepted = true, total = total, extortion = not offered}
end

function Deals.execute(d, target, deal, total)
    local them = Find_Player(target)
    for _, item in ipairs(deal) do
        if item.kind == "TREATY" and item.relation == "PROTECTORATE" and Worlds.is_slot(target) then
            local planet = Worlds.world_of(them)
            if planet then
                d:protect_world(planet, d:planet_name(planet))
            end
        elseif item.kind == "TREATY" then
            d:set_relation(target, item.relation, " (" .. d.signed(total) .. ")")
        elseif item.kind == "CREDITS" and item.side == "offer" then
            d.human.Give_Money(-item.amount)
            them.Give_Money(item.amount)
        elseif item.kind == "CREDITS" then
            them.Give_Money(-item.amount)
            d.human.Give_Money(item.amount)
        elseif item.kind == "WORLD" then
            local planet = FindPlanet(item.world)
            if planet then
                d:transfer_world(planet, (item.side == "offer") and them or d.human, item.side ~= "offer", true)
                if item.side == "offer" and d.republic and POPULATIONS[item.world] then
                    Deals.faux_pas(d, d:planet_name(planet))
                end
            end
        elseif item.kind == "TRIBUTE" then
            table.insert(d.tributes, {payer = (item.side == "offer") and d.human.Get_Faction_Name() or target,
                                      payee = (item.side == "offer") and target or d.human.Get_Faction_Name(),
                                      amount = item.amount, left = item.weeks})
        elseif item.kind == "PACT" then
            d.pacts[target] = GetCurrentTime() + weeks(item.weeks)
        elseif item.kind == "TRADE" then
            Trade.sign(d, target)
        elseif item.kind == "BORDERS" then
            Deals.set_borders(d, target, item.open)
        elseif item.kind == "JOINWAR" then
            require("eawx-plugins/diplomacy/DiplomacyAllies").join(d, target, item.target)
        elseif item.kind == "JOINT" then
            require("eawx-plugins/diplomacy/DiplomacyJointInvasion").start(d, target, item)
        end
    end
    record_gift(d, target, deal)
    d.show("Diplomacy: agreement with " .. d.display_name(target) .. ": " .. Deals.summary(d, deal) .. ".", nil,
        {r = 150, g = 210, b = 255}, 20)
end

function Deals.faux_pas(d, readable)
    local cost = rules().FAUX_PAS
    for name, _ in pairs(Senate.seats(d)) do
        Senate.sway(d, name, -cost.OPINION, "the Republic gave " .. readable .. " away")
    end
    for faction, relation in pairs(d.relations or {}) do
        if (relation == "VASSAL" or relation == "PROTECTORATE") and DIPLOMACY_OPINION_ADD then
            pcall(DIPLOMACY_OPINION_ADD, faction, d.human.Get_Faction_Name(), -cost.OPINION, 20,
                "the Republic gave " .. readable .. " away")
        end
    end
    local Sym = republic_part("RepublicSympathy")
    local U = republic_part("RepublicUtil")
    if Sym and U then
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            if U.category(planet.Get_Owner().Get_Faction_Name()) == "INDEPENDENT" and Sym.value(d, U.key(planet)) then
                Sym.change(d, U.key(planet), -cost.SYMPATHY)
            end
        end
    end
    d.show("Diplomacy: the galaxy watches the " .. d.display_name("REBEL") .. " hand " .. readable .. " and its people "
        .. "to another power. Its own worlds and the free worlds trust it less.", nil, {r = 255, g = 190, b = 90}, 25)
end

local function lower_first(text)
    return string.lower(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

function Deals.summary(d, deal)
    local out = {}
    for _, item in ipairs(deal) do
        table.insert(out, ((item.side == "demand") and "they give " or "") .. lower_first(Deals.label(d, item)))
    end
    return table.concat(out, ", ")
end

function Deals.declare_war(d, target, decree, defending)
    if Deals.locked(d, target) then
        return false, Deals.locked_reason(d, target)
    end
    if Deals.pact_active(d, target) then
        return false, "Your non-aggression pact with " .. d.display_name(target) .. " forbids it."
    end
    local ok, motion, why = Deals.senate_allows(d, target, {kind = "WAR"})
    if not ok and not decree then
        return false, why
    end
    if not ok then
        apply_decree(d, Deals.decree_cost(d, {motion}), "declare war on " .. d.display_name(target))
    end
    if defending then
        d:set_relation(target, "WAR", nil, true)
        Opinions.add(target, string.upper(d.human.Get_Faction_Name()), -20, 20, "sided with the world it attacked")
    else
        d:set_relation(target, "WAR")
    end
    Trade.on_war(d, target)
    return true, "War is declared on " .. d.display_name(target) .. "."
end

function Deals.break_alliance(d, target)
    local signed = d.memory.signed and d.memory.signed[target]
    local age = signed and M.floor((GetCurrentTime() - signed) / CONFIG.WEEK_SECONDS)
    d:set_relation(target, "CEASEFIRE", " (the alliance is ended)")
    d.memory.ended_alliance = d.memory.ended_alliance or {}
    d.memory.ended_alliance[target] = GetCurrentTime()
    if age and age < CONFIG.REPUTATION.ALLIANCE_WEEKS then
        d:reputation_drop(d.human.Get_Faction_Name(), 1, "ended its alliance with " .. d.display_name(target)
            .. " after " .. age .. " week" .. ((age == 1) and "" or "s"))
    end
    table.insert(d.memory.betrayals, {target, GetCurrentTime()})
    Opinions.event(target, d.human.Get_Faction_Name(), "BETRAYED")
    return true, "The alliance with " .. d.display_name(target) .. " is ended."
end

function Deals.pact_active(d, target)
    return d.pacts[target] and GetCurrentTime() < d.pacts[target]
end

local trade_ready = false

function Deals.update(d)
    d.tributes = d.tributes or {}
    d.pacts = d.pacts or {}
    local ok_p, Proposals = pcall(require, "eawx-plugins/diplomacy/DiplomacyProposals")
    if ok_p and Proposals then
        pcall(Proposals.update, d)
    end
    if not trade_ready then
        local ok, patched = pcall(Trade.patch, d)
        trade_ready = not ok or patched
        pcall(Trade.lanes, d)
    end
    if GetCurrentTime() < (d.next_deal_week or weeks(1)) then
        return
    end
    d.next_deal_week = M.next_week(weeks(1))
    local ok_trade, err_trade = pcall(Trade.week, d)
    if not ok_trade and Engine_Log then
        Engine_Log("TRADE week error: " .. tostring(err_trade))
    end
    local keep = {}
    for _, t in ipairs(d.tributes) do
        local payer, payee = Find_Player(t.payer), Find_Player(t.payee)
        if payer and payee and payer.Get_Credits() >= t.amount then
            payer.Give_Money(-t.amount)
            payee.Give_Money(t.amount)
            t.left = t.left - 1
            if t.left > 0 then
                table.insert(keep, t)
            end
        elseif payer and payee then
            d.show("Diplomacy: " .. d.display_name(t.payer) .. " could not pay its tribute; the agreement lapses.", nil,
                {r = 255, g = 190, b = 90})
        end
    end
    d.tributes = keep
    local ctx = nil
    for target, _ in pairs(d.open_borders or {}) do
        local them = Find_Player(target)
        if not them or d:relation(target) ~= "CEASEFIRE" then
            d.open_borders[target] = nil
        else
            ctx = ctx or DiplomacyAI.context(d.display_name)
            if Deals.attitude_word(Deals.attitude(d, ctx, them)) == "Hostile" then
                d.open_borders[target] = nil
                d.show("Diplomacy: " .. d.display_name(target) .. " closes its borders to you.", nil,
                    {r = 255, g = 190, b = 90}, 20)
            end
        end
    end
    for target, ends in pairs(d.pacts) do
        if GetCurrentTime() >= ends then
            d.pacts[target] = nil
            d.show("Diplomacy: the non-aggression pact with " .. d.display_name(target) .. " has expired.", nil,
                {r = 150, g = 210, b = 255})
        end
    end
end

return Deals
