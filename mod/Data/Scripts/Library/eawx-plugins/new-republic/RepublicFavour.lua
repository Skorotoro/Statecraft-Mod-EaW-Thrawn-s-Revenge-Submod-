local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local Goals = require("eawx-plugins/diplomacy/DiplomacyGoals")

local Favour = {}
local C = R.COUNCIL
local F = C.FAVOUR
local COLOR = {r = 170, g = 200, b = 255}

local function council()
    return require("eawx-plugins/new-republic/RepublicCouncil")
end

local function republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function active(d)
    local ok, on = pcall(council().active, d)
    return ok and on and not council().state(d).founded
end

local function state(d)
    local c = council().state(d)
    c.favour = c.favour or {next = GetCurrentTime() + U.weeks(F.FIRST_REQUEST_WEEKS)}
    return c.favour
end

function Favour.band(opinion)
    if opinion >= F.DEVOTED then
        return "Devoted", 1
    elseif opinion >= F.SUPPORTIVE then
        return "Supportive", 0.5
    elseif opinion <= F.OPPOSED then
        return "Opposed", -0.5
    elseif opinion <= F.DISGRUNTLED then
        return "Disgruntled", 0
    end
    return "Neutral", 0
end

function Favour.level(d, key)
    if not active(d) or not council().alive(d, key) then
        return 0
    end
    local _, level = Favour.band(council().opinion(d, key))
    return level
end

local function value(d, key)
    local b = F.BONUS[key]
    if not b then
        return 0
    end
    local level = Favour.level(d, key)
    if level < 0 and not b.malus then
        return 0
    end
    return b.full * level
end

function Favour.capital(d)
    return M.round(value(d, "MOTHMA"))
end

function Favour.acceptance(d)
    return M.round(value(d, "LEIA"))
end

function Favour.intel(d)
    return M.round(value(d, "FEYLYA"))
end

function Favour.line(d, key)
    local b = F.BONUS[key]
    if not b then
        return nil
    end
    local band, level = Favour.band(council().opinion(d, key))
    local now = value(d, key)
    local text = (now < 0) and string.gsub(b.text, "^%+", "") or b.text
    local gives = (now ~= 0) and (string.gsub(text, "%%d", tostring(M.round(M.abs(now))))) or "nothing now"
    if now < 0 then
        gives = "costs you: " .. gives
    end
    return "Favour: " .. band .. " (" .. b.text_full .. " when Devoted; half when Supportive). Now: " .. gives .. "."
end

local function weekly_bonuses(d)
    local human = d.human
    local refund = value(d, "ACKBAR")
    if refund > 0 then
        local ok, upkeep = pcall(EvaluatePerception, "Total_Maintenance", human)
        if ok and type(upkeep) == "number" and upkeep > 0 then
            human.Give_Money(M.round(upkeep * refund / 100))
        end
    end
    local per_world = value(d, "TEVV")
    if per_world > 0 then
        human.Give_Money(M.round(per_world * table.getn(U.worlds_of(human))))
    end
    local per_trade = value(d, "BERUSS")
    if per_trade > 0 and d.trade then
        local n = 0
        for _ in pairs(d.trade) do
            n = n + 1
        end
        human.Give_Money(M.round(per_trade * n))
    end
    local Sym = republic().part("sym")
    if not Sym then
        return
    end
    local gain = value(d, "KERRITHRARR")
    local own = value(d, "VERRINNEFRA")
    if gain <= 0 and own <= 0 then
        return
    end
    local ok, Opinions = pcall(require, "eawx-plugins/diplomacy/DiplomacyOpinions")
    local world = ok and Opinions.world() or {owner = {}}
    local routes = ok and Opinions.routes() or {}
    for planet, owner in pairs(world.owner) do
        if gain > 0 and owner == "INDEPENDENT_FORCES" and U.populated(planet) then
            for other in string.gfind(routes[planet] or "", "%S+") do
                if world.owner[other] == "REBEL" then
                    pcall(Sym.change, d, planet, gain)
                    break
                end
            end
        elseif own > 0 and owner == "REBEL" and U.populated(planet) then
            local v = Sym.value(d, planet)
            if v and v < R.SYMPATHY_SYMPATHETIC then
                pcall(Sym.change, d, planet, own)
            end
        end
    end
end

function Favour.deed(d, kind, what)
    if not active(d) then
        return
    end
    local deed = F.DEEDS[kind]
    if not deed then
        return
    end
    for _, c in ipairs(C.COUNCILLORS) do
        if council().alive(d, c.key) then
            local total = 0
            for _, interest in ipairs(c.interests or {}) do
                total = total + (deed[interest] or 0)
            end
            if total ~= 0 then
                council().sway(d, c.key, total, what or deed.text)
            end
        end
    end
    if kind == "LIBERATE" or kind == "PROTECT" then
        state(d).freed = GetCurrentTime()
    end
end

local function owner_of(key)
    local planet = FindPlanet(key)
    return planet and string.upper(planet.Get_Owner().Get_Faction_Name())
end

local function bordering_imperial_world(d)
    local ok, Opinions = pcall(require, "eawx-plugins/diplomacy/DiplomacyOpinions")
    if not ok then
        return nil
    end
    local world, routes = Opinions.world(), Opinions.routes()
    local found = {}
    for planet, owner in pairs(world.owner) do
        local kind = U.category(owner)
        if (kind == "IMPERIAL" or kind == "WARLORD") and FindPlanet(planet) then
            for other in string.gfind(routes[planet] or "", "%S+") do
                if world.owner[other] == "REBEL" then
                    table.insert(found, planet)
                    break
                end
            end
        end
    end
    if not found[1] then
        return nil
    end
    return found[GameRandom.Free_Random(1, table.getn(found))]
end

local function pick_power(d, want)
    local ok, Opinions = pcall(require, "eawx-plugins/diplomacy/DiplomacyOpinions")
    if not ok then
        return nil
    end
    local Trade = require("eawx-plugins/diplomacy/DiplomacyTrade")
    local list = {}
    for faction, _ in pairs(Opinions.world().powers) do
        if faction ~= "REBEL" and faction ~= "INDEPENDENT_FORCES" then
            local rel = d:relation(faction)
            if want == "TRADE" and rel ~= "WAR" and not Trade.partner(d, faction) and not Trade.blocked(d, faction) then
                table.insert(list, faction)
            elseif want == "PEACE" and rel == "WAR" and U.category(faction) ~= "IMPERIAL" then
                table.insert(list, faction)
            end
        end
    end
    if not list[1] then
        return nil
    end
    return list[GameRandom.Free_Random(1, table.getn(list))]
end

local function the_name(d, faction)
    local name = d.display_name(faction)
    if string.find(name, "'s ") or string.find(name, "^The ") then
        return name
    end
    return "the " .. name
end

local function make_request(d, councillor)
    local kinds = {}
    for _, interest in ipairs(councillor.interests or {}) do
        for _, k in ipairs(F.REQUESTS_BY_INTEREST[interest] or {}) do
            table.insert(kinds, k)
        end
    end
    while kinds[1] do
        local i = GameRandom.Free_Random(1, table.getn(kinds))
        local kind = table.remove(kinds, i)
        if kind == "TAKE" then
            local w = bordering_imperial_world(d)
            if w then
                return {kind = kind, world = w, text = "free " .. d:planet_name(FindPlanet(w)) .. " from " .. the_name(d, owner_of(w))}
            end
        elseif kind == "TRADE" or kind == "PEACE" then
            local f = pick_power(d, kind)
            if f then
                return {kind = kind, target = f, text = (kind == "TRADE") and ("sign a trade agreement with " .. the_name(d, f))
                    or ("make peace with " .. the_name(d, f))}
            end
        elseif kind == "FREE" then
            return {kind = kind, text = "liberate a world or take one under the Republic's protection"}
        elseif kind == "HOLD" then
            local n = table.getn(U.worlds_of(d.human)) + F.HOLD_MORE
            return {kind = kind, count = n, text = "hold " .. n .. " worlds"}
        end
    end
    return nil
end

local function done(d, r)
    if r.kind == "TAKE" then
        local o = owner_of(r.world)
        return o ~= nil and U.category(o) ~= "IMPERIAL" and U.category(o) ~= "WARLORD"
    elseif r.kind == "TRADE" then
        return require("eawx-plugins/diplomacy/DiplomacyTrade").partner(d, r.target)
    elseif r.kind == "PEACE" then
        return d:relation(r.target) ~= "WAR"
    elseif r.kind == "FREE" then
        return (state(d).freed or 0) > r.since
    elseif r.kind == "HOLD" then
        return table.getn(U.worlds_of(d.human)) >= r.count
    end
    return false
end

local function requests_week(d)
    local s = state(d)
    local r = s.request
    if r then
        local councillor = council().BY_KEY[r.key]
        if not council().alive(d, r.key) then
            Goals.remove(d, r.goal)
            s.request = nil
        elseif done(d, r) then
            Goals.remove(d, r.goal)
            s.request = nil
            council().sway(d, r.key, F.REQUEST_DONE, "you did as they asked: " .. r.text)
            republic().change_mandate(d, F.REQUEST_MANDATE)
            d.show("Council: " .. council().short(councillor) .. " thanks you for doing as they asked. Mandate +"
                .. F.REQUEST_MANDATE .. ".", nil, COLOR, 20)
        elseif GetCurrentTime() >= r.expires then
            Goals.remove(d, r.goal)
            s.request = nil
            council().sway(d, r.key, F.REQUEST_MISSED, "you ignored their request")
            d.show("Council: " .. council().short(councillor) .. " notes that you did not " .. r.text .. ".", nil, COLOR, 20)
        end
        return
    end
    if GetCurrentTime() < (s.next or 0) then
        return
    end
    s.next = GetCurrentTime() + U.weeks(F.REQUEST_WEEKS)
    local alive = {}
    for _, c in ipairs(C.COUNCILLORS) do
        if council().alive(d, c.key) then
            table.insert(alive, c)
        end
    end
    while alive[1] do
        local c = table.remove(alive, GameRandom.Free_Random(1, table.getn(alive)))
        local req = make_request(d, c)
        if req then
            req.key, req.since = c.key, GetCurrentTime()
            req.expires = GetCurrentTime() + U.weeks(F.REQUEST_DEADLINE_WEEKS)
            local title = council().short(c) .. " asks you to " .. req.text
            req.goal = Goals.add(d, title, {"Done in time: their opinion +" .. F.REQUEST_DONE .. ", mandate +"
                .. F.REQUEST_MANDATE .. ". Ignored: their opinion " .. F.REQUEST_MISSED .. "."}, req.expires)
            s.request = req
            d.show("Council: " .. title .. ". (" .. F.REQUEST_DEADLINE_WEEKS .. " weeks)", nil, COLOR, 20)
            return
        end
    end
end

function Favour.week(d)
    if not active(d) then
        return
    end
    weekly_bonuses(d)
    requests_week(d)
end

return Favour
