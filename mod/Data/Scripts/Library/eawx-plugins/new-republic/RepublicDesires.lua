local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Desires = {}
local S = R.SENATE
local COLOR = {r = 170, g = 200, b = 255}

local BY_INTEREST = {
    Security = {"FRONT", "GARRISON"}, Commerce = {"TRADE", "BUDGET", "PEACE", "INVEST"}, Liberation = {"LIBERATE", "FRONT"},
    Pacifist = {"PEACE"}, Autonomy = {"LOWER_TAX", "UNIFY"}, ["Species rights"] = {"SEAT", "PROTECT"},
    Reparations = {"LIBERATE"}, Industry = {"SHIPS", "INVEST"},
}
local LORE = {CORELLIA = "UNIFY", BOTHAWUI = "TRADE", KOTHLIS = "TRADE", MON_CALAMARI = "SHIPS", SULLUST = "INVEST",
              CHANDRILA = "PEACE", KASHYYYK = "LIBERATE", ELOM = "PROTECT", SLUIS_VAN = "SHIPS", KUAT = "INVEST"}
local INVEST = {"MINING_FACILITY", "TRADESTATION", "BANK_RESERVE", "SMUGGLER_CANTINA"}
local INVEST_ANYWHERE = {"TRADESTATION", "BANK_RESERVE", "SMUGGLER_CANTINA"}

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.desires = r.desires or {worlds = {}, temp = {}, invest = {}, ships = {}}
    return r.desires
end

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

function Desires.boost(d, key, v, wk, why)
    local s = state(d)
    if not s then
        return
    end
    s.temp[key] = s.temp[key] or {}
    table.insert(s.temp[key], {v = v, t0 = GetCurrentTime(), wk = wk, why = why})
end

function Desires.opinion(d, key)
    local s = state(d)
    local list = s and s.temp[key]
    if not list then
        return 0, {}
    end
    local total, why = 0, {}
    for _, b in ipairs(list) do
        local left = 1 - (GetCurrentTime() - b.t0) / U.weeks(b.wk)
        if left > 0 then
            local v = M.round(b.v * left)
            if v ~= 0 then
                total = total + v
                table.insert(why, {b.why, v})
            end
        end
    end
    return total, why
end

local function prune(s)
    for key, list in pairs(s.temp) do
        local keep = {}
        for _, b in ipairs(list) do
            if GetCurrentTime() - b.t0 < U.weeks(b.wk) then
                table.insert(keep, b)
            end
        end
        s.temp[key] = (table.getn(keep) > 0) and keep or nil
    end
end

local function neighbours(d, planet)
    local ok, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    local list = ok and Trade and Trade.neighbours(d, planet)
    return list or {}
end

local function at_war(d, faction)
    return faction ~= nil and d.relations ~= nil and d:relation(faction) == "WAR"
end

local function friendly(d, key)
    local planet = FindPlanet(key)
    if not planet then
        return true
    end
    local owner = planet.Get_Owner()
    if owner == d.human or owner == d:vassal_player() then
        return true
    end
    local w = d.vassal_worlds and d.vassal_worlds[key]
    if w and (w.stage == "protectorate" or w.stage == "associate") then
        return true
    end
    local relation = d:relation(owner.Get_Faction_Name())
    return relation == "PROTECTORATE" or relation == "VASSAL" or relation == "ALLIANCE"
end

local function protected(d, key)
    local planet = FindPlanet(key)
    if not planet then
        return true
    end
    if planet.Get_Owner() == d.human or planet.Get_Owner() == d:vassal_player() then
        return true
    end
    local w = d.vassal_worlds and d.vassal_worlds[key]
    if w and (w.stage == "protectorate" or w.stage == "associate") then
        return true
    end
    return d:relation(planet.Get_Owner().Get_Faction_Name()) == "PROTECTORATE"
end

local function count_investment(d, s)
    s.invest, s.invest_kinds = {}, {}
    local ok, all = pcall(Find_All_Objects_Of_Type, d.human, "Structure | SpaceStructure")
    for _, obj in pairs(ok and all or {}) do
        if TestValid(obj) then
            local t = string.upper(obj.Get_Type().Get_Name())
            local hit = string.find(t, "_HQ$") ~= nil
            local kind
            for _, prefix in ipairs(INVEST) do
                if string.find(t, "^" .. prefix) then
                    hit, kind = true, prefix
                end
            end
            if hit then
                local planet = obj.Get_Planet_Location()
                if planet then
                    local key = U.key(planet)
                    s.invest[key] = (s.invest[key] or 0) + 1
                    if kind then
                        s.invest_kinds[key] = s.invest_kinds[key] or {}
                        s.invest_kinds[key][kind] = true
                    end
                end
            end
        end
    end
end

local function net_income(d)
    local ok, Income = pcall(require, "eawx-plugins/diplomacy/DiplomacyIncome")
    if ok and Income then
        local ok2, _, _, net = pcall(Income.rows, d)
        if ok2 and net then
            return net
        end
    end
    return nil
end

local function sector_left(d, sector)
    local data = U.sector(sector)
    if not data then
        return nil
    end
    local left = 0
    for _, w in ipairs(data.worlds or {}) do
        if FindPlanet(w) and not friendly(d, w) then
            left = left + 1
        end
    end
    return left
end

local function tax_level(d, sector)
    local ok, Sectors = pcall(require, "eawx-plugins/new-republic/RepublicSectors")
    return ok and Sectors and Sectors.level(d, sector) or R.TAX_NORMAL
end

local function candidates(d, s, key, planet)
    local out = {}
    local name = d:planet_name(planet)
    local near = neighbours(d, planet)
    local threat = nil
    for _, other in ipairs(near) do
        local there = FindPlanet(other)
        local owner = there and there.Get_Owner().Get_Faction_Name()
        if owner and at_war(d, owner) then
            threat = threat or owner
            local kind = U.category(owner)
            local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
            if (kind == "IMPERIAL" or kind == "WARLORD") and ok and Sym and Sym.liberation(d, other) then
                table.insert(out, {kind = "LIBERATE", world = other, target = owner,
                                   text = "free " .. d:planet_name(there) .. " from " .. d.display_name(owner)})
            end
        elseif there and U.category(there.Get_Owner().Get_Faction_Name()) == "INDEPENDENT" and not protected(d, other) then
            table.insert(out, {kind = "PROTECT", world = other,
                               text = "the Republic's protection for " .. d:planet_name(there)})
        end
    end
    if threat then
        table.insert(out, {kind = "FRONT", target = threat,
                           text = "the front moved away (peace with " .. d.display_name(threat)
                               .. ", or its neighbouring worlds taken)"})
        if U.strength_at(d.human, planet) <= 0 then
            table.insert(out, {kind = "GARRISON", text = "warships in orbit of " .. name})
        end
        table.insert(out, {kind = "PEACE", target = threat, text = "peace with " .. d.display_name(threat)})
    end
    local okt, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
    if okt and Trade then
        for faction, relation in pairs(d.relations or {}) do
            local kind = U.category(faction)
            if relation ~= "WAR" and (kind == "FREE" or kind == "HUTT") and not Trade.blocked(d, faction)
                    and Find_Player(faction) then
                table.insert(out, {kind = "TRADE", target = faction,
                                   text = "a trade agreement with " .. d.display_name(faction)})
            end
        end
    end
    local room = false
    for _, kind in ipairs(INVEST_ANYWHERE) do
        room = room or not (s.invest_kinds and s.invest_kinds[key] and s.invest_kinds[key][kind])
    end
    if (s.invest[key] or 0) < 2 and room then
        table.insert(out, {kind = "INVEST", world = key, base = s.invest[key] or 0,
                           text = "investment on " .. name .. " (a corporation, mine, trade port or bank)"})
    end
    local sector = U.sector_of(key)
    for other, entry in pairs((d.senate and d.senate.unrepresented) or {}) do
        local there = FindPlanet(other)
        if there and U.sector_of(other) == sector then
            table.insert(out, {kind = "SEAT", world = other,
                               text = "a Senator's Office for " .. d:planet_name(there)})
        end
    end
    if s.net and s.net < 2000 then
        table.insert(out, {kind = "BUDGET", base = s.net + S.BUDGET_RAISE,
                           text = "a balanced budget: the Republic's income up by " .. S.BUDGET_RAISE})
    end
    local left = sector ~= "Unsectored space" and sector_left(d, sector)
    if left and left > 0 and left <= S.UNIFY_LEFT then
        table.insert(out, {kind = "UNIFY", sector = sector,
                           text = "the " .. sector .. " united under the Republic and its friends (" .. left .. " to go)"})
    end
    local level = tax_level(d, sector)
    if level > R.TAX_NORMAL then
        table.insert(out, {kind = "LOWER_TAX", sector = sector, base = level, text = "lower taxes in the " .. sector})
    end
    local Members = Republic().part("members")
    if Members and Members.has(d, key, "Industry") then
        table.insert(out, {kind = "SHIPS", world = key, text = "ships ordered from the yards of " .. name})
    end
    return out
end

function Desires.check(d, key, desire)
    local k = desire.kind
    local s = state(d)
    local Laws = Republic().part("laws")
    if (k == "SHIPS" or k == "INVEST") and Laws and Laws.industry_met(d, key) then
        return true
    end
    if k == "LIBERATE" then
        local there = FindPlanet(desire.world)
        if not there then
            return nil
        end
        if there.Get_Owner() == d.human then
            return true
        end
        return (at_war(d, there.Get_Owner().Get_Faction_Name())) and false or nil
    elseif k == "PROTECT" then
        return protected(d, desire.world)
    elseif k == "FRONT" or k == "GARRISON" then
        local planet = FindPlanet(key)
        if not planet then
            return nil
        end
        local threatened = false
        for _, other in ipairs(neighbours(d, planet)) do
            local there = FindPlanet(other)
            if there and at_war(d, there.Get_Owner().Get_Faction_Name()) then
                threatened = true
            end
        end
        if k == "FRONT" then
            return not threatened
        end
        if not threatened then
            return nil
        end
        return U.strength_at(d.human, planet) > 0
    elseif k == "PEACE" then
        return not at_war(d, desire.target)
    elseif k == "TRADE" then
        local ok, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
        if ok and Trade and Trade.partner(d, desire.target) then
            return true
        end
        return (not at_war(d, desire.target) and Find_Player(desire.target) ~= nil) and false or nil
    elseif k == "INVEST" then
        return (s.invest[desire.world] or 0) > (desire.base or 0)
    elseif k == "SEAT" then
        local there = FindPlanet(desire.world)
        if not there or there.Get_Owner() ~= d.human then
            return nil
        end
        return not (d.senate and d.senate.unrepresented[desire.world])
    elseif k == "BUDGET" then
        return s.net ~= nil and s.net >= desire.base
    elseif k == "UNIFY" then
        local left = sector_left(d, desire.sector)
        return left ~= nil and left == 0
    elseif k == "LOWER_TAX" then
        return tax_level(d, desire.sector) < desire.base
    elseif k == "SHIPS" then
        return s.ships[desire.world] == true
    end
    return nil
end

local function wanted(d, key, seat)
    local n = 1 + U.hash(key .. "desires") - M.floor(U.hash(key .. "desires") / 3) * 3
    local Blocs = Republic().part("blocs")
    if Blocs and seat and Blocs.key_of(seat.bloc) == "AGGRIEVED" then
        n = M.max(1, n - 1)
    end
    return n
end

local function weight(d, key, kind, bloc_def)
    local w = 1
    local Members = Republic().part("members")
    if Members then
        for _, interest in ipairs(Members.interests(d, key)) do
            for _, k in ipairs(BY_INTEREST[interest] or {}) do
                if k == kind then
                    w = w + 3
                end
            end
        end
    end
    for _, k in ipairs((bloc_def and bloc_def.desires) or {}) do
        if k == kind then
            w = w + 2
        end
    end
    if LORE[key] == kind then
        w = w + 4
    end
    return w + GameRandom.Free_Random(0, 2)
end

local function same(a, b)
    return a.kind == b.kind and a.target == b.target and a.world == b.world and a.sector == b.sector
end

function Desires.week(d, seated, seats)
    local s = state(d)
    if not s then
        return
    end
    count_investment(d, s)
    s.net = net_income(d)
    prune(s)
    local Blocs = Republic().part("blocs")
    local pleased = {}
    for key, planet in pairs(seated) do
        local list = s.worlds[key] or {}
        local keep = {}
        for _, desire in ipairs(list) do
            local met = Desires.check(d, key, desire)
            if met == true then
                Desires.boost(d, key, S.DESIRE_OPINION, S.DESIRE_WEEKS, "its wish met: " .. desire.text)
                table.insert(pleased, d:planet_name(planet))
            elseif met == false then
                table.insert(keep, desire)
            end
        end
        local seat = seats and seats[key]
        local n = wanted(d, key, seat)
        if table.getn(keep) < n and (table.getn(keep) == 0 or U.chance(50)) then
            local pool = candidates(d, s, key, planet)
            local def = Blocs and seat and Blocs.def(Blocs.key_of(seat.bloc))
            local best, best_w = nil, -1
            for _, c in ipairs(pool) do
                local dup = false
                for _, have in ipairs(keep) do
                    if same(have, c) or have.kind == c.kind then
                        dup = true
                    end
                end
                if not dup and Desires.check(d, key, c) == false then
                    local w = weight(d, key, c.kind, def)
                    if w > best_w then
                        best, best_w = c, w
                    end
                end
            end
            if best then
                best.since = GetCurrentTime()
                table.insert(keep, best)
            end
        end
        s.worlds[key] = keep
    end
    for key in pairs(s.worlds) do
        if not seated[key] then
            s.worlds[key] = nil
        end
    end
    s.ships = {}
    if table.getn(pleased) > 0 then
        d.show("Senate: " .. table.concat(pleased, ", ") .. ((table.getn(pleased) == 1) and " sees" or " see")
            .. " a wish fulfilled (opinion +" .. S.DESIRE_OPINION .. ", fading).", nil, COLOR, 15)
    end
end

function Desires.of(d, key)
    local s = state(d)
    return (s and s.worlds[key]) or {}
end

function Desires.on_production(d, key)
    local s = state(d)
    if s then
        s.ships[key] = true
    end
end

function Desires.stance(d, key, motion)
    local value, why = 0, nil
    local function add(v, text)
        if M.abs(v) > M.abs(value) then
            value, why = v, text
        end
    end
    for _, desire in ipairs(Desires.of(d, key)) do
        local k = desire.kind
        if motion.kind == "TREATY" then
            if (k == "PEACE" or k == "FRONT") and desire.target == motion.target then
                add(25, "it wants " .. desire.text)
            elseif k == "TRADE" and desire.target == motion.target then
                add(10, "it wants " .. desire.text)
            elseif k == "LIBERATE" and desire.target == motion.target then
                add(-15, "it wants to " .. desire.text)
            end
        elseif motion.kind == "WAR" then
            if k == "LIBERATE" and desire.target == motion.target then
                add(20, "it wants to " .. desire.text)
            elseif k == "FRONT" and desire.target == motion.target then
                add(10, "it wants " .. desire.text)
            elseif (k == "PEACE" or k == "TRADE") and desire.target == motion.target then
                add(-20, "it wants " .. desire.text)
            elseif k == "PEACE" then
                add(-10, "it wants " .. desire.text)
            end
        elseif motion.kind == "TAX" then
            local up = (motion.level or 0) > (motion.from or tax_level(d, motion.sector))
            if k == "BUDGET" then
                add(up and 20 or -15, "it wants " .. desire.text)
            elseif k == "LOWER_TAX" and desire.sector == motion.sector then
                add(up and -25 or 25, "it wants " .. desire.text)
            end
        elseif motion.kind == "ADMIT_ASSOCIATE" or motion.kind == "ADMIT_MEMBER" then
            if (k == "PROTECT" and desire.world == motion.world)
                    or (k == "UNIFY" and motion.world and U.sector_of(motion.world) == desire.sector) then
                add(15, "it wants " .. desire.text)
            end
        elseif motion.kind == "ACT" and motion.act == "FRONTIER_FUND" then
            if k == "FRONT" or k == "GARRISON" then
                add(15, "it wants " .. desire.text)
            end
        end
    end
    return value, why
end

function Desires.lines(d, key)
    local out = {}
    for _, desire in ipairs(Desires.of(d, key)) do
        table.insert(out, "Wants " .. desire.text .. ".")
    end
    return out
end

return Desires
