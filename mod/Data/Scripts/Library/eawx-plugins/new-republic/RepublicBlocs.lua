local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local Goals = require("eawx-plugins/diplomacy/DiplomacyGoals")

local Blocs = {}
local S = R.SENATE
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}

local BY_KEY, BY_NAME = {}, {}
for _, def in ipairs(R.BLOCS) do
    BY_KEY[def.key] = def
    BY_NAME[def.name] = def
end

function Blocs.def(key)
    return key and BY_KEY[key]
end

function Blocs.key_of(name)
    local def = name and BY_NAME[name]
    return def and def.key
end

function Blocs.name_of(key)
    local def = BY_KEY[key]
    return def and def.name
end

function Blocs.dot(name)
    local def = name and BY_NAME[name]
    return def and def.dot
end

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function state(d)
    if not d.senate then
        return nil
    end
    local b = d.senate.blocs
    if not b then
        b = {of = {}, small = {}, gone = {}, requests = {}, ended = {}, lobbied = {}, promise = {},
             next_motion = GetCurrentTime() + U.weeks(S.BLOC_MOTION_WEEKS[1])}
        d.senate.blocs = b
    end
    b.kept = b.kept or {}
    b.goals = b.goals or {}
    return b
end

local function has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then
            return true
        end
    end
    return false
end

local function fits(d, name, threat, raw)
    local Members, Desires = Republic().part("members"), Republic().part("desires")
    local interests = Members and Members.interests(d, name) or {}
    local species = Members and Members.species(name) or "Human"
    local desires = Desires and Desires.of(d, name) or {}
    local entry = d.senate.opinion and d.senate.opinion[name]
    local opinion = entry and entry.value or 0
    local aggrieved = (d.occupation and d.occupation[name] ~= nil) or opinion <= -30
    local Parties = not raw and Republic().part("parties")
    local ruling = Parties and Parties.ruling_bloc(d, name)
    local out = {}
    for _, def in ipairs(R.BLOCS) do
        local score = U.hash(name .. def.key) - M.floor(U.hash(name .. def.key) / 4) * 4
        for _, i in ipairs(interests) do
            if has(def.interests, i) then
                score = score + 10
            end
        end
        for _, desire in ipairs(desires) do
            if has(def.desires, desire.kind) then
                score = score + 4
            end
        end
        if R.LORE_BLOC[name] == def.key then
            score = score + 12
        end
        if def.key == "FRONTIER" and threat then
            score = score + 15
        elseif def.key == "ALIEN" and species ~= "Human" then
            score = score + 6
        elseif def.key == "BOTHAN" then
            score = score + ((species == "Bothan") and 30 or -50)
        elseif def.key == "AGGRIEVED" then
            score = score + (aggrieved and 30 or -15)
        elseif def.key == "LOYALIST" then
            score = score + ((ruling == "LOYALIST") and 40 or -60)
        end
        out[def.key] = score
    end
    if ruling == "INDEPENDENCE" then
        out.AUTONOMY = out.AUTONOMY + R.PARTIES.RULING_BLOC / 2
    elseif ruling and out[ruling] then
        out[ruling] = out[ruling] + R.PARTIES.RULING_BLOC
    end
    return out
end

function Blocs.fits(d, name)
    return fits(d, name, nil, true)
end

local function best(scores, b, current)
    local key, value = nil, -999
    for _, def in ipairs(R.BLOCS) do
        if not b.gone[def.key] then
            local v = scores[def.key] + ((def.key == current) and S.STICKY or 0)
            if v > value then
                key, value = def.key, v
            end
        end
    end
    return key
end

function Blocs.of(d, name, threat)
    local b = state(d)
    if not b then
        return nil
    end
    local key = b.of[name]
    if not key or b.gone[key] then
        key = best(fits(d, name, threat), b, nil)
        b.of[name] = key
    end
    return BY_KEY[key].name
end

local function regroup(d, b, seats)
    local count, total = {}, 0
    local scores = {}
    for name, seat in pairs(seats) do
        scores[name] = fits(d, name, seat.threat)
        local key = best(scores[name], b, b.of[name])
        if key ~= b.of[name] and b.of[name] then
            local planet = FindPlanet(name)
            d.show("Senate: " .. (planet and d:planet_name(planet) or name) .. " crosses the floor to the "
                .. BY_KEY[key].name .. ".", nil, COLOR, 12)
        end
        b.of[name] = key
        count[key] = (count[key] or 0) + 1
        total = total + 1
    end
    for name in pairs(b.of) do
        if not seats[name] then
            b.of[name] = nil
        end
    end
    for _, def in ipairs(R.BLOCS) do
        local n = count[def.key] or 0
        if not b.gone[def.key] and n > 0 and n < S.MERGE_SEATS and total >= S.MERGE_CHAMBER then
            b.small[def.key] = (b.small[def.key] or 0) + 1
            if b.small[def.key] >= S.MERGE_WEEKS then
                b.gone[def.key], b.small[def.key] = true, nil
                b.requests[def.key], b.promise[def.key] = nil, nil
                Blocs.drop_goal(d, def.key)
                local joined = nil
                for name, key in pairs(b.of) do
                    if key == def.key then
                        b.of[name] = best(scores[name], b, nil)
                        joined = joined or BY_KEY[b.of[name]].name
                    end
                end
                d.show("Senate: the " .. def.name .. " is too small to stand alone and dissolves"
                    .. (joined and ("; its senators join the " .. joined) or "") .. ".", nil, COLOR, 20)
            end
        else
            b.small[def.key] = nil
        end
    end
    for _, def in ipairs(R.BLOCS) do
        if b.gone[def.key] then
            local want = 0
            for name in pairs(seats) do
                local top, value = nil, -999
                for _, other in ipairs(R.BLOCS) do
                    if scores[name][other.key] > value then
                        top, value = other.key, scores[name][other.key]
                    end
                end
                if top == def.key then
                    want = want + 1
                end
            end
            if want >= S.FORM_SEATS then
                b.gone[def.key] = nil
                d.show("Senate: a new bloc forms in the chamber: the " .. def.name .. ".", nil, COLOR, 20)
            end
        end
    end
end

function Blocs.list(d, seats)
    local by = {}
    local out = {}
    for name, seat in pairs(seats) do
        local key = Blocs.key_of(seat.bloc)
        if key then
            if not by[key] then
                by[key] = {key = key, name = seat.bloc, seats = {}, def = BY_KEY[key]}
                table.insert(out, by[key])
            end
            table.insert(by[key].seats, name)
        end
    end
    table.sort(out, function(a, b)
        if table.getn(a.seats) ~= table.getn(b.seats) then
            return table.getn(a.seats) > table.getn(b.seats)
        end
        return a.name < b.name
    end)
    return out
end

local DESIRE_WORDS = {FRONT = "moving the front away", GARRISON = "warships for its worlds", PEACE = "peace",
    TRADE = "trade agreements", INVEST = "investment in its worlds", PROTECT = "protecting its neighbours",
    LIBERATE = "freeing the Empire's worlds", SEAT = "seats for unrepresented worlds", BUDGET = "a balanced budget",
    UNIFY = "uniting its sectors", LOWER_TAX = "lower taxes", SHIPS = "ship contracts"}
function Blocs.interest(d, names)
    local Desires = Republic().part("desires")
    local count, top, most = {}, nil, 0
    for _, name in ipairs(names or {}) do
        for _, desire in ipairs(Desires and Desires.of(d, name) or {}) do
            count[desire.kind] = (count[desire.kind] or 0) + 1
            if count[desire.kind] > most then
                top, most = desire.kind, count[desire.kind]
            end
        end
    end
    return top and DESIRE_WORDS[top] or nil
end

local function category(faction)
    return U.category(faction or "")
end

local function bloc_stance(def, seat, motion)
    local t = def.stance or {}
    local kind = motion.kind
    if t.ANY and not motion.bloc then
        return t.ANY + ((kind == "TAX" and (motion.level or 0) < (motion.from or 99)) and (t.TAX_DOWN or 0) or 0)
    end
    if kind == "WAR" then
        if seat.threat and seat.threat == motion.target and t.WAR_THREAT then
            return t.WAR_THREAT
        end
        local cat = category(motion.target)
        if (cat == "IMPERIAL" or cat == "WARLORD") and t.WAR_IMPERIAL then
            return t.WAR_IMPERIAL
        end
        return t.WAR or 0
    elseif kind == "TREATY" then
        if seat.threat and seat.threat == motion.target and t.TREATY_THREAT then
            return t.TREATY_THREAT
        end
        local cat = category(motion.target)
        if (cat == "IMPERIAL" or cat == "WARLORD") and t.TREATY_IMPERIAL then
            return t.TREATY_IMPERIAL
        end
        return t.TREATY or 0
    elseif kind == "ADMIT_ASSOCIATE" then
        return t.ADMIT or 0
    elseif kind == "ADMIT_MEMBER" then
        return (t.ADMIT or 0) + (t.ADMIT_MEMBER or 0)
    elseif kind == "TAX" then
        local up = (motion.level or 0) > (motion.from or 0)
        return up and (t.TAX_UP or 0) or (t.TAX_DOWN or 0)
    elseif kind == "ACT" then
        return t[motion.act] or 0
    elseif kind == "INTEL" then
        return t.INTEL or 0
    elseif kind == "APPROPRIATION" or kind == "NO_CONFIDENCE" then
        return t[kind] or 0
    end
    return 0
end

local function CONFIG_UNREST()
    return require("eawx-plugins/diplomacy/DiplomacyConfig").SENATE.UNREST_STABILITY
end

function Blocs.score(d, seat, motion)
    local parts, total = {}, 0
    local function add(v, text)
        v = M.round(v)
        if v ~= 0 then
            total = total + v
            table.insert(parts, {text, v})
        end
    end
    local def = BY_NAME[seat.bloc]
    if def then
        add(bloc_stance(def, seat, motion), "the " .. def.name .. "'s line")
    end
    local Members = Republic().part("members")
    local function interest(i)
        return Members and Members.has(d, seat.name, i)
    end
    local kind = motion.kind
    if kind == "WAR" then
        if interest("Pacifist") then
            add(-15, "a pacifist world")
        end
        local cat = category(motion.target)
        if (cat == "IMPERIAL" or cat == "WARLORD") and (interest("Liberation") or interest("Reparations")) then
            add(15, "it wants the Empire's worlds freed")
        end
    elseif kind == "TREATY" then
        if interest("Commerce") or interest("Pacifist") then
            add(10, "it wants trade and peace")
        end
    elseif kind == "TAX" then
        local Sectors = Republic().part("sectors")
        if Sectors then
            add(25 * (Sectors.vote(d, seat, motion, Members and Members.interests(d, seat.name),
                Republic().at_war(d)) or 0), (U.sector_of(seat.name) == motion.sector) and "its own sector's taxes"
                or "its view of taxes")
        end
    elseif kind == "APPROPRIATION" or kind == "BILL" or kind == "NO_CONFIDENCE" then
        local Gov = Republic().part("gov")
        if Gov then
            add(25 * (Gov.vote(d, seat, motion) or 0), "its view of the bill")
        end
    elseif kind == "ADMIT_ASSOCIATE" or kind == "ADMIT_MEMBER" then
        add(5, "a new world costs it little")
    elseif kind == "CEDE_AUTH" then
        local b = state(d)
        local owner = b and b.of[motion.world]
        local mine = Blocs.key_of(seat.bloc)
        if seat.name == motion.world then
            add(S.CEDE_OWN, "it is its own world")
        elseif not owner then
            add(S.CEDE_TERRITORY, "giving away a territory")
        elseif owner == mine then
            add(S.CEDE_BLOC, "a world of its own bloc")
        elseif mine == "TRADE" or mine == "BOTHAN" then
            add(S.CEDE_PRAGMATIC, "a price worth paying, perhaps")
        else
            add(S.CEDE_OTHERS, "giving away the Republic's worlds")
        end
    elseif kind == "PROTECT_AUTH" then
        local Desires = Republic().part("desires")
        for _, desire in ipairs((Desires and Desires.of(d, seat.name)) or {}) do
            if desire.kind == "PROTECT" and desire.world == motion.world then
                add(S.PROTECT_WISH, "it wants that world protected")
                break
            end
        end
    elseif kind == "ACT" and motion.act == "UNITY" then
        add(10, "the Chancellor speaks for all")
    elseif kind == "FOCUS" then
        local Focus = Republic().part("focus")
        for _, p in ipairs((Focus and Focus.stance(d, seat, motion)) or {}) do
            add(p[2], p[1])
        end
    end
    local Laws = Republic().part("laws")
    if Laws then
        for _, p in ipairs(Laws.stance(d, seat, motion)) do
            add(p[2], p[1])
        end
    end
    local Desires = Republic().part("desires")
    if Desires then
        local v, why = Desires.stance(d, seat.name, motion)
        add(v, why or "its wishes")
    end
    if motion.bloc and Blocs.key_of(seat.bloc) == motion.bloc then
        add(40, "its own bloc's motion")
    end
    local opinion_counts = not motion.bloc and kind ~= "NO_CONFIDENCE"
    if opinion_counts then
        local mandate = Republic().mandate(d)
        local o = seat.opinion
        if o > 0 then
            add(o * S.OPINION_WEIGHT * mandate / 100, "its opinion of you (" .. o .. ", mandate " .. mandate .. ")")
        else
            add(o * S.OPINION_WEIGHT, "its opinion of you (" .. o .. ")")
        end
    end
    if d.senate.stability < CONFIG_UNREST() and total > -S.VOTE_FOR and total < S.VOTE_FOR then
        add(S.UNREST_STANCE, "the chamber's low cohesion")
    end
    return total, parts, opinion_counts
end

function Blocs.vote(d, seat, motion)
    local score = Blocs.score(d, seat, motion)
    if score >= S.VOTE_FOR then
        return 1
    elseif score <= -S.VOTE_FOR then
        return -1
    end
    return 0
end

function Blocs.vote_lines(d, seat, motion)
    local score, parts = Blocs.score(d, seat, motion)
    local lines = {}
    for _, p in ipairs(parts) do
        table.insert(lines, ((p[2] > 0) and "+" or "") .. p[2] .. " " .. p[1])
    end
    local verdict = (score >= S.VOTE_FOR and "votes for") or (score <= -S.VOTE_FOR and "votes against")
        or "is undecided until the vote"
    return score, lines, verdict
end

local function support(d, seats, names, motion)
    local copy = {}
    for k, v in pairs(motion) do
        copy[k] = v
    end
    copy.bloc = "?"
    local sum, n = 0, 0
    for _, name in ipairs(names) do
        local seat = seats[name]
        if seat then
            sum, n = sum + Blocs.score(d, seat, copy), n + 1
        end
    end
    return (n > 0) and (sum / n) or 0
end

local SKIP = {UNITY = true}

local function propose_one(d, seats)
    local Senate = Republic().senate
    if not Senate or not Senate.can_propose(d) then
        return
    end
    local list = Blocs.list(d, seats)
    if table.getn(list) == 0 then
        return
    end
    local motions = Senate.available_motions(d)
    local best_bloc, best_motion, best_value = nil, nil, 15
    for _, bloc in ipairs(list) do
        if table.getn(bloc.seats) >= S.MERGE_SEATS then
            for _, m in ipairs(motions) do
                if not (m.kind == "ACT" and SKIP[m.act]) and not m.disabled and m.kind ~= "FOUND" then
                    local v = support(d, seats, bloc.seats, m) + GameRandom.Free_Random(0, 6)
                    if v > best_value then
                        best_bloc, best_motion, best_value = bloc, m, v
                    end
                end
            end
        end
    end
    if not best_motion then
        return
    end
    local motion = {}
    for k, v in pairs(best_motion) do
        motion[k] = v
    end
    motion.bloc = best_bloc.key
    motion.label = "The " .. best_bloc.name .. ": " .. (motion.label or motion.text)
    if motion.mandate then
        motion.text = string.gsub(motion.text, "^authorise ", "permit ")
    end
    Senate.open_bloc_debate(d, motion)
end

function Blocs.enactor(d, motion)
    local Senate = Republic().senate
    if motion.kind == "WAR" then
        return function()
            d.senate.approved[motion.target] = true
            d.show("Senate: war on " .. d.display_name(motion.target) .. " is approved. Declare it when you choose.",
                nil, COLOR, 20)
        end
    elseif motion.kind == "TREATY" and motion.mandate then
        return function()
            d.senate.mandates[motion.target] = motion.relation
            d.show("Senate: you may offer " .. ((motion.relation == "ALLIANCE") and "an alliance" or "a ceasefire")
                .. " to " .. d.display_name(motion.target) .. " without another vote, whenever you choose.", nil, COLOR, 20)
        end
    end
    return Senate.enactor(d, motion)
end

local function week_number(time)
    return Goals.week and Goals.week(time) or M.floor(time / U.weeks(1)) + 1
end

function Blocs.request_text(req)
    return "Issued: week " .. week_number(req.issued) .. ". Expires: week " .. week_number(req.deadline) .. "."
end

local function how_to(d, desire, name)
    local function world(key)
        local planet = key and FindPlanet(key)
        return planet and d:planet_name(planet) or (key or name)
    end
    local function power(faction)
        return faction and d.display_name(faction) or "them"
    end
    local k = desire.kind
    if k == "LIBERATE" then
        return "Take " .. world(desire.world) .. " from " .. power(desire.target) .. "."
    elseif k == "PROTECT" then
        return "Offer " .. world(desire.world) .. " the Republic's protection (Diplomacy; the Senate must authorise it "
            .. "first), or bring it into the Republic."
    elseif k == "FRONT" then
        return "Make peace with " .. power(desire.target) .. ", or take its worlds next to " .. name .. "."
    elseif k == "GARRISON" then
        return "Station warships in orbit of " .. name .. "."
    elseif k == "PEACE" then
        return "Agree a ceasefire with " .. power(desire.target) .. " (Diplomacy; the Senate must authorise peace talks)."
    elseif k == "TRADE" then
        return "Sign a trade agreement with " .. power(desire.target) .. " (Diplomacy)."
    elseif k == "INVEST" then
        return "Build a corporation, a mine, a trade port or a bank on " .. name .. "."
    elseif k == "SEAT" then
        return "Build a Senator's Office on " .. world(desire.world) .. "."
    elseif k == "BUDGET" then
        return "Raise the Republic's income by " .. S.BUDGET_RAISE .. " credits a week."
    elseif k == "UNIFY" then
        return "Bring the last free worlds of the " .. (desire.sector or "sector") .. " under the Republic or its friends."
    elseif k == "LOWER_TAX" then
        return "Lower the taxes of the " .. (desire.sector or "sector") .. " (a Sector Taxes motion)."
    elseif k == "SHIPS" then
        return "Order ships from the yards of " .. name .. "."
    end
    return "Give " .. name .. " what it asks for."
end

local function post_goal(d, b, key, req, name)
    if b.goals[key] then
        Goals.remove(d, b.goals[key])
        b.goals[key] = nil
    end
    local lines = {"The " .. BY_KEY[key].name .. " asks the government, for " .. name .. ", for " .. req.desire.text .. ".",
                   how_to(d, req.desire, name),
                   "Granted: the bloc's worlds' opinion +" .. S.REQUEST_OPINION .. ", the mandate +" .. S.REQUEST_MANDATE
                       .. ". Ignored: opinion -" .. S.REQUEST_OPINION .. ", the mandate -" .. S.REQUEST_MANDATE .. "."}
    if Republic().part("jedi") then
        table.insert(lines, "A Jedi of the Order may answer the call in person (Answer a Call).")
    end
    local ok, slot = pcall(Goals.add, d, "Senate: " .. BY_KEY[key].name .. "'s Request", lines, req.deadline)
    b.goals[key] = ok and slot or nil
end

local function drop_goal(d, b, key)
    if b.goals[key] then
        pcall(Goals.remove, d, b.goals[key])
        b.goals[key] = nil
    end
end
Blocs.drop_goal = function(d, key)
    local b = state(d)
    if b then
        drop_goal(d, b, key)
    end
end

function Blocs.issue(d, key, seats, asked)
    local b = state(d)
    if b.requests[key] then
        return false, "The bloc already has a request before the government."
    end
    local Desires = Republic().part("desires")
    if not Desires then
        return false, "Nothing to ask."
    end
    local pool = {}
    for name, seat in pairs(seats) do
        if Blocs.key_of(seat.bloc) == key then
            for _, desire in ipairs(Desires.of(d, name)) do
                if Desires.check(d, name, desire) == false then
                    table.insert(pool, {name = name, desire = desire})
                end
            end
        end
    end
    local pick = U.pick(pool)
    if not pick then
        return false, "Its worlds want nothing the government can give now."
    end
    local now = GetCurrentTime()
    local req = {world = pick.name, desire = pick.desire, issued = now, deadline = now + U.weeks(S.REQUEST_WEEKS)}
    b.requests[key] = req
    local planet = FindPlanet(pick.name)
    local name = planet and d:planet_name(planet) or pick.name
    d.show("Senate: the " .. BY_KEY[key].name .. ", for " .. name .. ", asks the government for " .. pick.desire.text
        .. ". " .. Blocs.request_text(req) .. " (Mission log.)", nil, COLOR, 25)
    post_goal(d, b, key, req, name)
    return true, asked and ("The " .. BY_KEY[key].name .. " asks for " .. pick.desire.text .. ".") or nil
end

local function settle_requests(d, b, seats)
    local Desires = Republic().part("desires")
    for key, req in pairs(b.requests) do
        local met = Desires and Desires.check(d, req.world, req.desire)
        local def = BY_KEY[key]
        if met == true or met == nil or GetCurrentTime() >= req.deadline then
            b.requests[key] = nil
            b.ended[key] = GetCurrentTime()
            drop_goal(d, b, key)
            if met == true then
                Blocs.sway_bloc(d, key, seats, S.REQUEST_OPINION, "you granted its request")
                Republic().senate_mandate(d, S.REQUEST_MANDATE)
                d.show("Senate: the " .. def.name .. "'s request is granted (" .. req.desire.text .. "). Its worlds' "
                    .. "opinion +" .. S.REQUEST_OPINION .. ", mandate " .. Republic().mandate(d) .. ".", nil, COLOR, 20)
            elseif met == false then
                Blocs.sway_bloc(d, key, seats, -S.REQUEST_OPINION, "you ignored its request")
                Republic().senate_mandate(d, -S.REQUEST_MANDATE)
                d.show("Senate: the " .. def.name .. "'s request lapsed unanswered (" .. req.desire.text .. "). Its "
                    .. "worlds' opinion -" .. S.REQUEST_OPINION .. ", mandate " .. Republic().mandate(d) .. ".", nil, WARN, 20)
            end
        end
    end
end

function Blocs.request(d, key)
    local b = state(d)
    return b and b.requests[key]
end

function Blocs.grant(d, key, seats)
    local b = state(d)
    if not (b and b.requests[key]) then
        return
    end
    b.requests[key] = nil
    b.ended[key] = GetCurrentTime()
    drop_goal(d, b, key)
    Blocs.sway_bloc(d, key, seats, S.REQUEST_OPINION, "a Jedi answered its call")
    Republic().senate_mandate(d, S.REQUEST_MANDATE)
end

function Blocs.sway_bloc(d, key, seats, amount, reason)
    local Senate = Republic().senate
    for name, seat in pairs(seats) do
        if Blocs.key_of(seat.bloc) == key then
            Senate.sway(d, name, amount, reason)
        end
    end
end

local function weeks_left(time)
    return M.max(1, M.ceil((time - GetCurrentTime()) / U.weeks(1)))
end

function Blocs.aid_cost(d, key)
    local b = state(d)
    local seats = 0
    for _, k in pairs((b and b.of) or {}) do
        if k == key then
            seats = seats + 1
        end
    end
    seats = M.max(1, seats)
    return seats * S.AID_CREDITS_SEAT, M.min(S.AID_CAPITAL_MAX, M.max(S.AID_CAPITAL_MIN, seats * S.AID_CAPITAL_SEAT))
end

function Blocs.can(d, key, action)
    local b = state(d)
    if action == "LOBBY" then
        local last = b.lobbied[key]
        if last and GetCurrentTime() - last < U.weeks(S.LOBBY_WEEKS) then
            return "Lobbied recently: again in " .. weeks_left(last + U.weeks(S.LOBBY_WEEKS)) .. " weeks."
        end
        if Republic().capital(d) < S.LOBBY_CAPITAL then
            return "Not enough political capital (" .. S.LOBBY_CAPITAL .. ")."
        end
    elseif action == "AUDIENCE" then
        if b.requests[key] then
            return "Its request is still before the government."
        end
        local ended = b.ended[key]
        if ended and GetCurrentTime() - ended < U.weeks(S.AUDIENCE_WEEKS) then
            return "It was heard recently: again in " .. weeks_left(ended + U.weeks(S.AUDIENCE_WEEKS)) .. " weeks."
        end
    elseif action == "PROMISE" then
        if (b.promise[key] or 0) > GetCurrentTime() then
            return "You promised already: " .. weeks_left(b.promise[key]) .. " weeks left."
        end
        if Republic().capital(d) < S.PROMISE_CAPITAL then
            return "Not enough political capital (" .. S.PROMISE_CAPITAL .. ")."
        end
    elseif action == "AID" then
        local credits, capital = Blocs.aid_cost(d, key)
        if d.human.Get_Credits() < credits then
            return "The treasury cannot spare " .. credits .. " credits."
        end
        if Republic().capital(d) < capital then
            return "Not enough political capital (" .. capital .. ")."
        end
    end
    return nil
end

function Blocs.lobby(d, key, seats)
    local why = Blocs.can(d, key, "LOBBY")
    if why then
        return false, why
    end
    Republic().spend(d, S.LOBBY_CAPITAL)
    state(d).lobbied[key] = GetCurrentTime()
    local Parties = Republic().part("parties")
    local n = 0
    for name, seat in pairs(seats) do
        if Blocs.key_of(seat.bloc) == key and Parties then
            local w = Parties.of(d, name)
            local idx = w and w.ruling
            for k, party in ipairs((w and w.list) or {}) do
                if party.bloc == key then
                    idx = k
                end
            end
            if idx and Parties.adjust(d, name, idx, S.LOBBY_CLOUT) > 0 then
                n = n + 1
            end
        end
    end
    return true, "The " .. BY_KEY[key].name .. " is lobbied: its parties gain clout (+" .. S.LOBBY_CLOUT
        .. ") on " .. n .. ((n == 1) and " world." or " worlds.")
end

function Blocs.audience(d, key, seats)
    local why = Blocs.can(d, key, "AUDIENCE")
    if why then
        return false, why
    end
    return Blocs.issue(d, key, seats, true)
end

function Blocs.promise(d, key, seats)
    local why = Blocs.can(d, key, "PROMISE")
    if why then
        return false, why
    end
    Republic().spend(d, S.PROMISE_CAPITAL)
    state(d).promise[key] = GetCurrentTime() + U.weeks(S.PROMISE_WEEKS)
    state(d).kept[key] = nil
    Blocs.sway_bloc(d, key, seats, S.PROMISE_OPINION, "you promised to work with its bloc")
    return true, "You promise the " .. BY_KEY[key].name .. " to put no motion it opposes for " .. S.PROMISE_WEEKS
        .. " weeks, and to pass one it backs: opinion +" .. S.PROMISE_OPINION .. "."
end

function Blocs.promise_met(d, key)
    local b = state(d)
    return (b and b.kept[key]) == true
end

function Blocs.on_passed(d, motion, result)
    local b = state(d)
    if not b or motion.bloc or not (result and result.blocs) then
        return
    end
    for key, ends in pairs(b.promise) do
        local votes = ends > GetCurrentTime() and not b.kept[key] and result.blocs[BY_KEY[key].name]
        if votes and votes.yes > votes.no then
            b.kept[key] = true
            d.show("Senate: the " .. BY_KEY[key].name .. " counts the motion to " .. motion.text .. " as the "
                .. "cooperation you promised.", nil, COLOR, 20)
        end
    end
end

function Blocs.broken_by(d, motion, seats)
    local b = state(d)
    local out = {}
    if not b or motion.bloc then
        return out
    end
    for key, ends in pairs(b.promise) do
        if ends > GetCurrentTime() then
            local yes, no = 0, 0
            for _, seat in pairs(seats) do
                if Blocs.key_of(seat.bloc) == key then
                    local v = Blocs.vote(d, seat, motion)
                    if v > 0 then
                        yes = yes + 1
                    elseif v < 0 then
                        no = no + 1
                    end
                end
            end
            if no > yes then
                table.insert(out, key)
            end
        end
    end
    return out
end

function Blocs.break_promises(d, motion, seats)
    local b = state(d)
    for _, key in ipairs(Blocs.broken_by(d, motion, seats)) do
        b.promise[key] = nil
        b.kept[key] = nil
        Blocs.sway_bloc(d, key, seats, -S.PROMISE_BROKEN, "you broke your promise to its bloc")
        d.senate.stability = M.max(0, d.senate.stability - S.PROMISE_COHESION)
        d.show("Senate: you broke your promise to the " .. BY_KEY[key].name .. ". Its worlds' opinion -"
            .. S.PROMISE_BROKEN .. ", cohesion -" .. S.PROMISE_COHESION .. ".", nil, WARN, 20)
    end
end

function Blocs.aid(d, key, world)
    local why = Blocs.can(d, key, "AID")
    if why then
        return false, why
    end
    local Desires = Republic().part("desires")
    if not Desires then
        return false, "No one to send it to."
    end
    local credits, capital = Blocs.aid_cost(d, key)
    d.human.Give_Money(-credits)
    Republic().spend(d, capital)
    Desires.boost(d, world, S.AID_OPINION, S.AID_WEEKS, "aid from the government")
    local planet = FindPlanet(world)
    return true, "Aid reaches " .. (planet and d:planet_name(planet) or world) .. ": opinion +" .. S.AID_OPINION
        .. ", fading over " .. S.AID_WEEKS .. " weeks."
end

function Blocs.promised(d, key)
    local b = state(d)
    local ends = b and b.promise[key]
    return (ends and ends > GetCurrentTime()) and weeks_left(ends) or nil
end

function Blocs.week(d, seats)
    local b = state(d)
    if not b then
        return
    end
    regroup(d, b, seats)
    settle_requests(d, b, seats)
    for key, ends in pairs(b.promise) do
        if ends <= GetCurrentTime() then
            b.promise[key] = nil
            if not b.kept[key] then
                Blocs.sway_bloc(d, key, seats, -S.PROMISE_UNMET, "you never passed a motion it backs")
                d.senate.stability = M.max(0, d.senate.stability - S.PROMISE_UNMET_COHESION)
                d.show("Senate: your promise to the " .. BY_KEY[key].name .. " ran out with no motion it backs passed. "
                    .. "Its worlds' opinion -" .. S.PROMISE_UNMET .. ", cohesion -" .. S.PROMISE_UNMET_COHESION .. ".",
                    nil, WARN, 20)
            end
            b.kept[key] = nil
        end
    end
    for _, bloc in ipairs(Blocs.list(d, seats)) do
        local ended = b.ended[bloc.key]
        if not b.requests[bloc.key] and table.getn(bloc.seats) >= S.MERGE_SEATS
                and (not ended or GetCurrentTime() - ended >= U.weeks(S.AUDIENCE_WEEKS)) and U.chance(S.REQUEST_CHANCE) then
            Blocs.issue(d, bloc.key, seats)
        end
    end
    if GetCurrentTime() >= (b.next_motion or 0) then
        local spread = S.BLOC_MOTION_WEEKS
        b.next_motion = GetCurrentTime() + U.weeks(GameRandom.Free_Random(spread[1], spread[2]))
        pcall(propose_one, d, seats)
    end
end

return Blocs
