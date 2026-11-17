local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")

local Trade = {}
local COLOR = {r = 150, g = 210, b = 255}

local function rules()
    return CONFIG.TRADE
end

local ROUTES = nil
local function routes()
    if ROUTES == nil then
        local ok, data = pcall(require, "eawx-plugins/imperial-court/CourtRoutes")
        ROUTES = ok and type(data) == "table" and data or false
    end
    return ROUTES or {}
end

local function key(planet)
    return string.upper(planet.Get_Type().Get_Name())
end

local NEIGHBOURS = {}
local budget, budget_time = 0, -1
function Trade.neighbours(d, planet)
    local name = key(planet)
    local list = NEIGHBOURS[name]
    if list then
        return list
    end
    local now = GetCurrentTime()
    if now ~= budget_time then
        budget, budget_time = rules().PATHS_PER_UPDATE, now
    end
    local raw = routes()[name]
    local candidates = {}
    for other in string.gfind(raw or "", "%S+") do
        table.insert(candidates, other)
    end
    if table.getn(candidates) > budget then
        return nil
    end
    list = {}
    for _, other in ipairs(candidates) do
        local there = FindPlanet(other)
        if there then
            budget = budget - 1
            local ok, path = pcall(Find_Path, d.human, planet, there)
            if ok and type(path) == "table" and table.getn(path) == 2 then
                table.insert(list, other)
            end
        end
    end
    NEIGHBOURS[name] = list
    return list
end

function Trade.partner(d, faction)
    return d.trade ~= nil and faction ~= nil and d.trade[string.upper(faction)] ~= nil
end

function Trade.border(d, faction)
    local them = Find_Player(faction)
    local out = {}
    if not them then
        return out
    end
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == d.human then
            for _, other in ipairs(Trade.neighbours(d, planet) or {}) do
                local there = FindPlanet(other)
                if there and there.Get_Owner() == them then
                    table.insert(out, {ours = planet, theirs = there})
                end
            end
        end
    end
    return out
end

local function port_value(player, planet)
    local ok, port = pcall(EvaluatePerception, "Planet_Has_Trade_Station", player, planet)
    if not ok or not port or port <= 0 then
        return 0
    end
    local ok2, hub = pcall(EvaluatePerception, "Resource_Trade_Hub", player, planet)
    return (ok2 and hub and hub > 0) and rules().HUB_ROUTE or rules().ROUTE
end

function Trade.value(d, faction)
    local ours, theirs = 0, 0
    local them = Find_Player(faction)
    for _, lane in ipairs(Trade.border(d, faction)) do
        ours = ours + port_value(d.human, lane.ours)
        theirs = theirs + port_value(them, lane.theirs)
    end
    return ours, theirs
end

function Trade.blocked(d, faction)
    if Trade.partner(d, faction) then
        return "A trade agreement already holds."
    end
    local relation = d:relation(faction)
    if not relation or relation == "WAR" then
        return "A trade agreement needs a ceasefire or better first."
    end
    if table.getn(Trade.border(d, faction)) == 0 then
        return "No hyperlane joins your worlds to theirs: trade needs a shared border."
    end
    return nil
end

function Trade.evaluate(d, faction, add)
    local ours, theirs = Trade.value(d, faction)
    add(rules().BASE, "reluctance to open their markets")
    add(theirs / rules().CREDITS_PER_POINT, "their trade ports would earn " .. theirs .. " a week")
    add(-ours / rules().RIVAL_CREDITS_PER_POINT, "yours would earn " .. ours .. " a week")
    if d.republic then
        local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
        local Laws = ok and Republic and Republic.part("laws")
        local v = Laws and Laws.trade_acceptance(d) or 0
        if v ~= 0 then
            add(v, "the Republic's Free Trade Charter")
        end
    end
end

function Trade.sign(d, faction)
    d.trade = d.trade or {}
    d.trade[string.upper(faction)] = GetCurrentTime()
    Trade.lanes(d)
    if d.republic then
        local ok, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
        if ok then
            pcall(Favour.deed, d, "TRADE")
        end
    end
end

function Trade.cancel(d, faction, why)
    if not Trade.partner(d, faction) then
        return false, "There is no trade agreement with " .. d.display_name(faction) .. "."
    end
    d.trade[string.upper(faction)] = nil
    if d.republic then
        local ok, Favour = pcall(require, "eawx-plugins/new-republic/RepublicFavour")
        if ok then
            pcall(Favour.deed, d, "TRADE_END")
        end
    end
    d.show("Diplomacy: the trade agreement with " .. d.display_name(faction) .. " ends" .. (why or "") .. ".", nil, COLOR, 15)
    Trade.lanes(d)
    return true, "The trade agreement with " .. d.display_name(faction) .. " is ended."
end

function Trade.lanes(d)
    local ok, Lanes = pcall(require, "eawx-plugins/diplomacy/DiplomacyLanes")
    if not ok or not Lanes then
        return
    end
    local mine = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == d.human then
            table.insert(mine, planet)
        end
    end
    Lanes.trade(string.upper(d.human.Get_Faction_Name()), d.trade or {}, mine)
end

local function linked(d, owner_name)
    local human = d.human.Get_Faction_Name()
    local out = {}
    if owner_name == human then
        for faction, _ in pairs(d.trade or {}) do
            out[faction] = true
        end
        for faction, relation in pairs(d.relations or {}) do
            if relation == "VASSAL" or relation == "PROTECTORATE" then
                out[faction] = true
            end
        end
        local vassals = d:vassal_player()
        if vassals then
            out[string.upper(vassals.Get_Faction_Name())] = true
        end
    elseif Trade.partner(d, owner_name) then
        out[human] = true
    end
    return out
end

local function connections(d, handler, planet)
    local object = planet:get_game_object()
    local owner = object.Get_Owner()
    local owner_name = string.upper(owner.Get_Faction_Name())
    local routes_ = handler.maxroutes * EvaluatePerception("Planet_TradeRoutes", handler.human_player, object)
    local own = tonumber(Dirty_Floor(routes_ * EvaluatePerception("Planet_ActiveTradeRoutes", handler.human_player, object)
        + 0.15))
    local allies = EvaluatePerception("Connected_Ally_Count", owner, object)
    local involved = owner == d.human or Trade.partner(d, owner_name) or d:relation(owner_name) ~= "WAR"
    local lanes = involved and Trade.neighbours(d, object)
    if lanes then
        local friends = linked(d, owner_name)
        local human_name = string.upper(d.human.Get_Faction_Name())
        local human_side_of = linked(d, human_name)
        local counted, human_side = 0, 0
        for _, other in ipairs(lanes) do
            local there = FindPlanet(other)
            local name = there and string.upper(there.Get_Owner().Get_Faction_Name())
            if name and name ~= owner_name then
                if friends[name] then
                    counted = counted + 1
                end
                if name == human_name or human_side_of[name] then
                    human_side = human_side + 1
                end
            end
        end
        if owner == d.human then
            allies = counted
        else
            allies = M.max(0, allies - human_side) + counted
        end
    end
    return own + allies
end

function Trade.patch(d)
    if type(TradePortHandler) ~= "table" then
        return false
    end
    if TradePortHandler.__trade_patched then
        return true
    end
    local original = TradePortHandler.add_dummies
    TradePortHandler.add_dummies = function(handler, planet)
        local ok, count = pcall(connections, d, handler, planet)
        if not ok then
            if Engine_Log then
                Engine_Log("TRADE connections error: " .. tostring(count))
            end
            return original(handler, planet)
        end
        local stats = handler.planets[planet]
        if stats.__current_trade_dummies ~= nil then
            handler.dummy_lifecycle_handler:remove_from_dummy_set(planet, stats.__current_trade_dummies)
            stats.__current_trade_dummies = nil
        end
        stats.had_port = true
        count = M.min(10, count)
        if count > 0 then
            local hub = EvaluatePerception("Resource_Trade_Hub", handler.human_player, planet:get_game_object())
            stats.__current_trade_dummies = {[(hub == 0) and "TRADE_INCOME_DUMMY" or "TRADE_HUB_INCOME_DUMMY"] = count}
            handler.dummy_lifecycle_handler:add_to_dummy_set(planet, stats.__current_trade_dummies)
        end
    end
    TradePortHandler.__trade_patched = true
    return true
end

local function mine_bonus(d)
    local paid = {}
    for faction, _ in pairs(d.trade or {}) do
        for _, lane in ipairs(Trade.border(d, faction)) do
            for _, planet in ipairs({lane.ours, lane.theirs}) do
                local name = key(planet)
                if not paid[name] then
                    paid[name] = true
                    local owner = planet.Get_Owner()
                    local mines = 0
                    for _, type_name in ipairs(rules().MINES) do
                        local t = Find_Object_Type(type_name)
                        for _, obj in pairs(t and Find_All_Objects_Of_Type(type_name) or {}) do
                            if TestValid(obj) and obj.Get_Owner() == owner and obj.Get_Planet_Location() == planet then
                                mines = mines + 1
                            end
                        end
                    end
                    if mines > 0 then
                        owner.Give_Money(mines * rules().MINE_BONUS)
                    end
                end
            end
        end
    end
end

local function offers(d)
    if not rules().AI_OFFERS then
        return
    end
    d.trade_offers = d.trade_offers or {}
    for faction, relation in pairs(d.relations or {}) do
        if relation ~= "WAR" and not Trade.partner(d, faction)
                and (d.trade_offers[faction] or -1e9) + rules().OFFER_GAP_WEEKS * CONFIG.WEEK_SECONDS < GetCurrentTime()
                and Find_Player(faction) and not (d.human.Get_Faction_Name() == faction) then
            local _, theirs = Trade.value(d, faction)
            if theirs >= rules().OFFER_MIN and GameRandom.Free_Random(1, 100) <= rules().OFFER_CHANCE then
                local Proposals = require("eawx-plugins/diplomacy/DiplomacyProposals")
                if Proposals.add(d, faction, {{kind = "TRADE", side = "offer"}}, "a trade agreement") then
                    d.trade_offers[faction] = GetCurrentTime()
                    return
                end
            end
        end
    end
end

function Trade.week(d)
    d.trade = d.trade or {}
    for faction, _ in pairs(d.trade) do
        if not Find_Player(faction) or d:relation(faction) == "WAR" then
            Trade.cancel(d, faction, " with the war")
        elseif table.getn(Trade.border(d, faction)) == 0 then
            Trade.cancel(d, faction, ": no border is left between you")
        end
    end
    pcall(mine_bonus, d)
    pcall(offers, d)
    Trade.lanes(d)
end

function Trade.on_war(d, faction)
    if Trade.partner(d, faction) then
        Trade.cancel(d, faction, " with the war")
    end
end

return Trade
