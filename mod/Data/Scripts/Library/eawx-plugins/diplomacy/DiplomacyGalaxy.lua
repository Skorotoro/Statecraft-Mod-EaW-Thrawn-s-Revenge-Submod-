local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Opinions = require("eawx-plugins/diplomacy/DiplomacyOpinions")
local Reputation = require("eawx-plugins/diplomacy/DiplomacyReputation")
local Worlds = require("eawx-plugins/diplomacy/DiplomacyWorlds")

local Galaxy = {}
local G = CONFIG.GALAXY
local NEWS = {r = 190, g = 205, b = 230}

local pacts = {}
local recent = {}
local budget = 0
local next_week = 0
local vassal_ai = {}
local aggressors = {}

local function pair(a, b)
    a, b = string.upper(a), string.upper(b)
    if a < b then
        return a .. "|" .. b
    end
    return b .. "|" .. a
end

local function split(k)
    local _, _, a, b = string.find(k, "^(.-)|(.+)$")
    return a, b
end

local function player(name)
    local ok, p = pcall(Find_Player, name)
    return ok and p or nil
end

local function weeks_since(t)
    return (GetCurrentTime() - (t or 0)) / CONFIG.WEEK_SECONDS
end

local function trait(faction, name)
    local p = G.PERSONALITY[faction] or {}
    return p[name] or G.PERSONALITY_DEFAULT[name] or 0.5
end

function Galaxy.pact(a, b)
    return pacts[pair(a, b)]
end

local function name_of(d, faction)
    return d.display_name(faction)
end

local function news(d, text)
    table.insert(recent, 1, {text = text, time = GetCurrentTime()})
    while table.getn(recent) > G.REPORT_LINES do
        table.remove(recent)
    end
    if G.NEWS then
        Diplomacy.show("Galaxy: " .. text, nil, NEWS, 12)
    end
end

local function powers(d)
    local human = string.upper(d.human.Get_Faction_Name())
    local skip = {INDEPENDENT_FORCES = true, HOSTILE = true, WARLORDS = true, NEUTRAL = true, [human] = true}
    for _, v in ipairs(require("eawx-plugins/diplomacy/DiplomacyVassals")) do
        skip[string.upper(v.name)] = true
    end
    local out = {}
    for name, _ in pairs(Opinions.world().powers) do
        if not skip[name] and not Worlds.is_slot(name) then
            out[name] = true
        end
    end
    return out
end

local function worlds(faction)
    return Opinions.world().count[faction] or 0
end

local function fronts(faction, list)
    local world = Opinions.world()
    local n = 0
    for other, _ in pairs(world.enemies[faction] or {}) do
        if (world.borders[faction .. "|" .. other] or 0) + (world.borders[other .. "|" .. faction] or 0) > 0 then
            n = n + 1
        end
    end
    return n
end

local function bordering(a, b)
    local bd = Opinions.world().borders
    return (bd[a .. "|" .. b] or 0) + (bd[b .. "|" .. a] or 0)
end

local function at_war(a, b)
    local pa, pb = player(a), player(b)
    return pa and pb and pa.Is_Enemy(pb)
end

local function allies_of(faction)
    local out = {}
    for k, p in pairs(pacts) do
        local a, b = split(k)
        if (a == faction or b == faction) and (p.kind == "ALLIANCE" or p.kind == "VASSAL") then
            table.insert(out, {other = (a == faction) and b or a, pact = p})
        end
    end
    return out
end

local function set_ai(faction, subject)
    if subject then
        vassal_ai[faction] = true
        pcall(StoryUtil.ChangeAIPlayer, faction, CONFIG.VASSAL_AI)
    elseif vassal_ai[faction] then
        vassal_ai[faction] = nil
        local C = CONSTANTS or {}
        local cruel = GlobalValue and GlobalValue.Get("CRUEL_ON") == 1
        local ai = cruel and C.ALL_FACTIONS_CRUEL_AI and C.ALL_FACTIONS_CRUEL_AI[faction]
            or (C.ALL_FACTIONS_AI and C.ALL_FACTIONS_AI[faction])
        if ai then
            pcall(StoryUtil.ChangeAIPlayer, faction, ai)
        end
    end
end

local function sign(d, a, b, kind, overlord)
    local k = pair(a, b)
    local old = pacts[k]
    pacts[k] = {kind = kind, overlord = overlord, since = GetCurrentTime(), trade = old and old.trade}
    Opinions.end_war(a, b)
    local pa, pb = player(a), player(b)
    if pa and pb then
        pa.Make_Ally(pb)
        pb.Make_Ally(pa)
    end
    if kind == "VASSAL" then
        set_ai((overlord == a) and b or a, true)
    end
end

local function end_pact(a, b)
    local k = pair(a, b)
    local p = pacts[k]
    if p and p.kind == "VASSAL" then
        set_ai((p.overlord == a) and b or a, false)
    end
    pacts[k] = nil
end

local function declare(d, a, b, why)
    aggressors[b .. "|" .. a] = GetCurrentTime()
    local p = pacts[pair(a, b)]
    end_pact(a, b)
    Opinions.force_war(a, b)
    if p then
        Opinions.event(b, a, "BETRAYED")
        Reputation.drop(a, 1, "broke its " .. string.lower(p.kind == "VASSAL" and "vassalage" or p.kind)
            .. " with " .. name_of(d, b))
    end
    news(d, "War: " .. name_of(d, a) .. " against " .. name_of(d, b) .. (why and ("; " .. why) or "") .. ".")
    Galaxy.call_to_war(d, a, b)
end

function Galaxy.call_to_war(d, a, b, a_is_human)
    for _, e in ipairs(allies_of(b)) do
        local ally, p = e.other, e.pact
        local subject = p.kind == "VASSAL" and p.overlord == b
        if ally ~= a and not at_war(ally, a) and (subject or bordering(ally, a) > 0) then
            local join = subject
            if not join then
                local will = G.JOIN_BASE + Opinions.get(ally, b) / 2 - Opinions.get(ally, a) / 2
                    + G.JOIN_FAITH * trait(ally, "faith") - G.JOIN_PER_FRONT * fronts(ally, powers(d))
                join = will >= 0
            end
            if join then
                if a_is_human then
                    d:set_relation(ally, "WAR", nil, true)
                else
                    end_pact(ally, a)
                    Opinions.force_war(ally, a)
                end
                news(d, "Call to war: " .. name_of(d, ally) .. " stands with " .. name_of(d, b) .. " against "
                    .. name_of(d, a) .. ".")
            else
                end_pact(ally, b)
                pacts[pair(ally, b)] = {kind = "CEASEFIRE", since = GetCurrentTime(), trade = p.trade}
                Opinions.event(b, ally, "ABANDONED")
                Reputation.drop(ally, 1, "abandoned " .. name_of(d, b))
                news(d, "Call to war refused: " .. name_of(d, ally) .. " abandons " .. name_of(d, b) .. "; their "
                    .. ((p.kind == "VASSAL") and "protection" or "alliance") .. " is broken.")
            end
        end
    end
    if a_is_human then
        return
    end
    for _, e in ipairs(allies_of(a)) do
        local ally, p = e.other, e.pact
        local subject = p.kind == "VASSAL" and p.overlord == a
        if ally ~= b and not at_war(ally, b) and (subject or bordering(ally, b) > 0) then
            local will = G.ASSIST_BASE + Opinions.get(ally, a) / 2 - Opinions.get(ally, b) / 2
                + 10 * trait(ally, "aggression")
            if subject or will >= 0 then
                end_pact(ally, b)
                Opinions.force_war(ally, b)
                news(d, "Call to war: " .. name_of(d, ally) .. " stands with " .. name_of(d, a) .. " against "
                    .. name_of(d, b) .. ".")
            else
                Opinions.add(a, ally, G.DECLINED_OPINION, 20, "declined to join their war")
            end
        end
    end
end

local function neighbours_of(d, n)
    local out = {}
    local ok_t, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    local pn = Find_Player(n)
    if not (ok_t and Trade and pn) then
        return out
    end
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == pn then
            for _, other in ipairs(Trade.neighbours(d, planet) or {}) do
                local there = FindPlanet(other)
                local owner = there and there.Get_Owner()
                if owner and owner ~= pn then
                    out[string.upper(owner.Get_Faction_Name())] = true
                end
            end
        end
    end
    return out
end

function Galaxy.start_neutral(d)
    local neutral = {}
    for _, n in ipairs(CONFIG.NEUTRAL_START or {}) do
        neutral[n] = true
    end
    for _, n in ipairs(CONFIG.NEUTRAL_START or {}) do
        if player(n) then
            local near = neighbours_of(d, n)
            local foes = {}
            for other in pairs(powers(d)) do
                if near[other] and not neutral[other] and other ~= "REBEL" then
                    foes[other] = true
                end
            end
            if next(foes) == nil and powers(d)["EMPIRE"] then
                foes["EMPIRE"] = true
            end
            for other in pairs(powers(d)) do
                if other ~= n and at_war(n, other) and not foes[other] then
                    sign(d, n, other, "CEASEFIRE")
                end
            end
        end
    end
end

function Galaxy.end_pact(a, b)
    end_pact(string.upper(a), string.upper(b))
end

function Galaxy.attacked_by(victim, attacker)
    local t = aggressors[string.upper(victim) .. "|" .. string.upper(attacker)]
    return t ~= nil and weeks_since(t) < 26
end

function Galaxy.bonds()
    local out = {}
    for k, p in pairs(pacts) do
        local a, b = split(k)
        if p.kind == "ALLIANCE" then
            table.insert(out, {leader = a, follower = b, kind = "ALLIANCE"})
            table.insert(out, {leader = b, follower = a, kind = "ALLIANCE"})
        elseif p.kind == "VASSAL" then
            table.insert(out, {leader = p.overlord, follower = (p.overlord == a) and b or a, kind = "VASSAL"})
        end
    end
    return out
end

function Galaxy.on_human_war(d, f)
    pcall(Galaxy.call_to_war, d, string.upper(d.human.Get_Faction_Name()), string.upper(f), true)
end

local function ratio(a, b)
    return M.max(1, worlds(a)) / M.max(1, worlds(b))
end

local function feared_near(a, b, list)
    local world = Opinions.world()
    for f, _ in pairs(list) do
        if f ~= a and f ~= b and world.total > 0 and 100 * worlds(f) / world.total > CONFIG.OPINION.FEAR_SHARE then
            return f
        end
    end
    return nil
end

local function peace_will(x, y, list)
    local w = Opinions.get(x, y) - CONFIG.OPINION.WAR + G.PEACE_BASE
    w = w + G.PER_FRONT * M.max(0, fronts(x, list) - 1)
    if ratio(y, x) >= 1.5 then
        w = w + G.LOSING
    end
    return w - 20 * trait(x, "aggression")
end

local function alliance_will(x, y, list)
    local w = Opinions.get(x, y) + G.ALLIANCE_BASE + 30 * (trait(x, "sociability") - 0.5)
    local shared = 0
    for e, _ in pairs(Opinions.world().enemies[x] or {}) do
        if (Opinions.world().enemies[y] or {})[e] then
            shared = shared + 1
        end
    end
    w = w + M.min(G.SHARED_CAP, shared * G.SHARED_ENEMY)
    if feared_near(x, y, list) then
        w = w + G.COALITION
    end
    return w
end

local function trade_will(x, y)
    return Opinions.get(x, y) / 2 + G.TRADE_BASE + 30 * trait(x, "trade")
end

local function war_desire(x, y, list)
    local p = pacts[pair(x, y)]
    local w = -Opinions.get(x, y) + G.WAR_BASE + 40 * trait(x, "aggression")
    if ratio(x, y) >= 1.5 then
        w = w + G.STRONGER
    end
    w = w - G.WAR_PER_FRONT * fronts(x, list)
    if p then
        w = w - G.TREATY_RESPECT * trait(x, "faith") - ((p.kind == "ALLIANCE") and G.ALLIANCE_RESPECT or 0)
    end
    return w
end

local function decide(d)
    local list = powers(d)
    local best, best_score = nil, 0
    local function consider(score, action)
        if score > best_score then
            best, best_score = action, score
        end
    end
    for a0, _ in pairs(list) do
        for b0, _ in pairs(list) do
            local a, b = a0, b0
            if a < b then
                local k = pair(a, b)
                local p = pacts[k]
                local war = at_war(a, b)
                local border = bordering(a, b)
                local age = p and weeks_since(p.since) or 0
                if war and border > 0 then
                    local wa, wb = peace_will(a, b, list), peace_will(b, a, list)
                    if M.min(wa, wb) >= 0 then
                        consider(M.min(wa, wb) + 1, function() Galaxy.make_peace(d, a, b) end)
                    end
                    for _, s in ipairs({{a, b}, {b, a}}) do
                        local weak, strong = s[1], s[2]
                        if border > 0 and ratio(strong, weak) >= G.VASSAL_RATIO and worlds(weak) <= G.VASSAL_MAX_WORLDS then
                            local w = Opinions.get(weak, strong) / 2 + 10 * M.log2(ratio(strong, weak)) + G.LOSING
                                - 40 * trait(weak, "pride") + G.VASSAL_BASE
                            if w >= 0 and Opinions.get(strong, weak) > G.OVERLORD_MIN then
                                consider(w + 1, function() Galaxy.make_vassal(d, strong, weak) end)
                            end
                        end
                    end
                elseif not war and p and age >= G.MIN_WEEKS then
                    if p.kind == "CEASEFIRE" then
                        local wa, wb = alliance_will(a, b, list), alliance_will(b, a, list)
                        if M.min(wa, wb) >= 0 and trait(a, "sociability") > 0.1 and trait(b, "sociability") > 0.1 then
                            consider(M.min(wa, wb) + 1, function() Galaxy.make_alliance(d, a, b) end)
                        end
                    end
                    if p.kind == "VASSAL" then
                        local subject = (p.overlord == a) and b or a
                        local overlord = p.overlord
                        if ratio(overlord, subject) < G.FREE_RATIO and Opinions.get(subject, overlord) < G.FREE_OPINION then
                            consider(20, function() Galaxy.break_free(d, overlord, subject) end)
                        end
                    else
                        for _, s in ipairs({{a, b}, {b, a}}) do
                            local x, y, alliance = s[1], s[2], p.kind == "ALLIANCE"
                            local w = war_desire(x, y, list)
                            if border > 0 and w >= G.WAR_BAR then
                                consider(w - G.WAR_BAR + 1, function()
                                    declare(d, x, y, alliance and "the alliance is broken" or nil)
                                end)
                            end
                        end
                    end
                    if not p.trade and border > 0 and p.kind ~= "VASSAL" then
                        local wa, wb = trade_will(a, b), trade_will(b, a)
                        if M.min(wa, wb) >= 0 then
                            consider(M.min(wa, wb) / 2 + 1, function() Galaxy.make_trade(d, a, b) end)
                        end
                    end
                end
            end
        end
    end
    if best then
        best()
        return true
    end
    return false
end

local function is_capital(d, faction, planet_name)
    local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
    local pl = player(faction)
    if not (ok and pl) then
        return true
    end
    local cap = Deals.capital(d, pl)
    return cap and string.upper(cap.Get_Type().Get_Name()) == planet_name
end

function Galaxy.make_peace(d, a, b)
    local winner, loser = a, b
    if ratio(b, a) > 1 then
        winner, loser = b, a
    end
    local terms = ""
    if ratio(winner, loser) >= G.TERMS_RATIO and Opinions.count(loser, winner, "WORLD_TAKEN") > 0 then
        local world = Opinions.world()
        local routes = Opinions.routes()
        local taken = nil
        if worlds(loser) >= 3 then
            for planet, owner in pairs(world.owner) do
                if owner == loser and not taken then
                    for other in string.gfind(routes[planet] or "", "%S+") do
                        if world.owner[other] == winner then
                            taken = planet
                            break
                        end
                    end
                end
            end
        end
        local p = taken and FindPlanet(taken)
        if p and not is_capital(d, loser, taken) then
            pcall(d.transfer_world, d, p, player(winner), false, true)
            terms = "; " .. d:planet_name(p) .. " goes to " .. name_of(d, winner)
        else
            local pl, pw = player(loser), player(winner)
            local credits = pl and M.floor(pl.Get_Credits() * G.TERMS_CREDITS) or 0
            if credits > 0 then
                pl.Give_Money(-credits)
                pw.Give_Money(credits)
                terms = "; " .. credits .. " credits paid to " .. name_of(d, winner)
            end
        end
    end
    sign(d, a, b, "CEASEFIRE")
    news(d, "Peace: " .. name_of(d, a) .. " and " .. name_of(d, b) .. terms .. ".")
end

function Galaxy.make_alliance(d, a, b)
    sign(d, a, b, "ALLIANCE")
    news(d, "Alliance: " .. name_of(d, a) .. " and " .. name_of(d, b) .. ".")
end

function Galaxy.make_trade(d, a, b)
    local p = pacts[pair(a, b)]
    if p then
        p.trade = GetCurrentTime()
        news(d, "Trade: " .. name_of(d, a) .. " and " .. name_of(d, b) .. ".")
    end
end

function Galaxy.make_vassal(d, overlord, subject)
    sign(d, overlord, subject, "VASSAL", overlord)
    news(d, "Vassal: " .. name_of(d, subject) .. " under " .. name_of(d, overlord) .. ".")
    for enemy, _ in pairs(Opinions.world().enemies[overlord] or {}) do
        if enemy ~= subject and not at_war(subject, enemy) and player(enemy) then
            Opinions.force_war(subject, enemy)
        end
    end
end

function Galaxy.break_free(d, overlord, subject)
    end_pact(overlord, subject)
    sign(d, overlord, subject, "CEASEFIRE")
    news(d, "Independence: " .. name_of(d, subject) .. " breaks free of " .. name_of(d, overlord) .. ".")
end

local function weekly(d)
    local list = powers(d)
    for k, p in pairs(pacts) do
        local a, b = split(k)
        if not (list[a] and list[b]) then
            end_pact(a, b)
        else
            if p.trade then
                local credits = M.min(G.TRADE_CAP, G.TRADE_PER_BORDER * bordering(a, b))
                local pa, pb = player(a), player(b)
                if pa and pb and credits > 0 then
                    pa.Give_Money(credits)
                    pb.Give_Money(credits)
                end
            end
            if p.kind == "VASSAL" then
                local subject = (p.overlord == a) and b or a
                local ps, po = player(subject), player(p.overlord)
                local credits = ps and M.floor(ps.Get_Credits() * G.TRIBUTE) or 0
                if credits > 0 and po then
                    ps.Give_Money(-credits)
                    po.Give_Money(credits)
                end
                if not vassal_ai[subject] then
                    set_ai(subject, true)
                end
            end
        end
    end
end

local SYNC_SECONDS = 5
local next_sync = 0

local function sync_subjects(d)
    local H = string.upper(d.human.Get_Faction_Name())
    local list = powers(d)
    local bonds = {}
    for k, p in pairs(pacts) do
        if p.kind == "VASSAL" then
            local a, b = split(k)
            table.insert(bonds, {overlord = p.overlord, subject = (p.overlord == a) and b or a})
        end
    end
    for f, _ in pairs(list) do
        local r = d:relation(f)
        if r == "VASSAL" or r == "PROTECTORATE" then
            table.insert(bonds, {overlord = H, subject = f})
        end
    end
    local function war(a, b)
        if a == H then
            return d:relation(b) == "WAR"
        elseif b == H then
            return d:relation(a) == "WAR"
        end
        return at_war(a, b) and true or false
    end
    for _, bond in ipairs(bonds) do
        local O, S = bond.overlord, bond.subject
        local others = {[H] = true}
        for f, _ in pairs(list) do
            others[f] = true
        end
        for X, _ in pairs(others) do
            if X ~= O and X ~= S and player(X) and player(S) then
                local ow, sw = war(O, X), war(S, X)
                if ow and not sw then
                    if X == H then
                        d:set_relation(S, "WAR", nil, true)
                    else
                        end_pact(S, X)
                        Opinions.force_war(S, X)
                    end
                elseif sw and not ow then
                    if X == H then
                        d:set_relation(S, "CEASEFIRE", nil, true)
                    else
                        sign(d, S, X, "CEASEFIRE")
                    end
                end
            end
        end
    end
end

function Galaxy.update(d)
    if not G.ON then
        return
    end
    if GetCurrentTime() >= next_sync then
        next_sync = GetCurrentTime() + SYNC_SECONDS
        pcall(sync_subjects, d)
    end
    for k, _ in pairs(pacts) do
        local a, b = split(k)
        local pa, pb = player(a), player(b)
        if pa and pb then
            pa.Make_Ally(pb)
            pb.Make_Ally(pa)
        end
    end
    local now = GetCurrentTime()
    if now < next_week then
        return
    end
    next_week = now + CONFIG.WEEK_SECONDS
    weekly(d)
    budget = M.min(G.BUDGET_MAX, budget + G.CHANGES_PER_WEEK)
    if budget >= 1 and decide(d) then
        budget = budget - 1
    end
end

function Galaxy.opinion_lines(a, b, add)
    local p = pacts[pair(a, b)]
    if not p then
        return false
    end
    local R = CONFIG.OPINION
    if p.kind == "ALLIANCE" then
        add(R.ALLIANCE, "their alliance", 3)
    elseif p.kind == "VASSAL" then
        add(R.SUBJECT, (p.overlord == b) and "their overlord" or "their vassal", 3)
    else
        add(R.CEASEFIRE, "a ceasefire", 3)
    end
    if p.trade then
        add(M.min(R.TRADE_CAP, weeks_since(p.trade) * R.TRADE_PER_WEEK), "their trade", 2)
    end
    return true
end

function Galaxy.report(d)
    local lines = {}
    local groups = {ALLIANCE = {}, CEASEFIRE = {}, VASSAL = {}, TRADE = {}}
    for k, p in pairs(pacts) do
        local a, b = split(k)
        if p.kind == "VASSAL" then
            local subject = (p.overlord == a) and b or a
            table.insert(groups.VASSAL, name_of(d, subject) .. " (of " .. name_of(d, p.overlord) .. ")")
        else
            table.insert(groups[p.kind], name_of(d, a) .. " and " .. name_of(d, b))
        end
        if p.trade then
            table.insert(groups.TRADE, name_of(d, a) .. " and " .. name_of(d, b))
        end
    end
    local function line(title, list)
        if list[1] then
            table.sort(list)
            table.insert(lines, title .. ": " .. table.concat(list, "; ") .. ".")
        end
    end
    line("Alliances", groups.ALLIANCE)
    line("Ceasefires", groups.CEASEFIRE)
    line("Vassals", groups.VASSAL)
    line("Trade", groups.TRADE)
    if not lines[1] then
        table.insert(lines, "No treaties between the other powers yet.")
    end
    if recent[1] then
        local events = {}
        for i = 1, M.min(table.getn(recent), 6) do
            local r = recent[i]
            local ago = M.floor(weeks_since(r.time))
            table.insert(events, r.text .. ((ago > 0) and (" (" .. ago .. " week" .. ((ago == 1) and "" or "s") .. " ago)")
                or " (this week)"))
        end
        table.insert(lines, "Lately: " .. table.concat(events, " "))
    end
    return lines
end

Opinions.set_ai_provider(Galaxy.opinion_lines)

return Galaxy
