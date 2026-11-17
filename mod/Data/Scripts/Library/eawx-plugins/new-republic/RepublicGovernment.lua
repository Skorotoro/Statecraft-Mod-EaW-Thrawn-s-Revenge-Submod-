local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Gov = {}
local COLOR = {r = 170, g = 200, b = 255}
local WARN = {r = 255, g = 190, b = 90}

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.gov = r.gov or {cabinet = {}, next_session = GetCurrentTime() + U.weeks(R.SESSION_WEEKS)}
    return r.gov
end

local function senate()
    local Republic = require("eawx-plugins/new-republic/Republic")
    return Republic.senate, Republic
end

local function members()
    local ok, Members = pcall(require, "eawx-plugins/new-republic/RepublicMembers")
    return ok and Members or nil
end

function Gov.chief()
    local ok, value = pcall(GlobalValue.Get, "ChiefOfState")
    return ok and value or nil
end

function Gov.chief_name()
    local c = R.CANDIDATES[Gov.chief() or ""]
    return c and c.name or "the Chancellor"
end

function Gov.agenda(d)
    local s = state(d)
    if s and s.suspended_until and GetCurrentTime() < s.suspended_until then
        return nil
    end
    local c = R.CANDIDATES[Gov.chief() or ""]
    return c and c.agenda or nil
end

function Gov.holder(d, office)
    local s = state(d)
    return s and s.cabinet[office]
end

local function has_office(d, office)
    return Gov.holder(d, office) ~= nil
end

function Gov.treaty_bonus(d)
    local points, why = 0, {}
    if Gov.agenda(d) == "DIPLOMACY" then
        points = points + 8
        table.insert(why, Gov.chief_name() .. "'s diplomacy")
    end
    if has_office(d, "STATE") then
        points = points + 5
        table.insert(why, "the Minister of State")
    end
    local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
    local accord = Laws and Laws.treaty_acceptance(d) or 0
    if accord ~= 0 then
        points = points + accord
        table.insert(why, "the Diplomatic Immunity Accord")
    end
    return points, table.concat(why, " and ")
end

function Gov.tax_bonus(d)
    return ((Gov.agenda(d) == "COMMERCE") and 10 or 0) + (has_office(d, "FINANCE") and 5 or 0)
end

function Gov.weariness(d, value)
    if Gov.agenda(d) == "HAWK" then
        value = value / 2
    end
    if has_office(d, "DEFENCE") then
        value = value - 3
    end
    return M.max(0, M.round(value))
end

local function justice(d)
    if not has_office(d, "JUSTICE") then
        return 0
    end
    local c = d.republic and d.republic.council
    return (c and c.constitution == "LAWS") and 2 or 1
end

function Gov.vacancies(d)
    local s = state(d)
    if not s or (d.senate and d.senate.council) then
        return 0
    end
    local n = 0
    for _, office in ipairs(R.CABINET) do
        if not s.cabinet[office.key] then
            n = n + 1
        end
    end
    return n
end

function Gov.cohesion_bonus(d)
    return 3 * justice(d) - (R.VACANT_MINISTER_COHESION or 0) * Gov.vacancies(d)
end

function Gov.intel_bonus(d)
    if has_office(d, "INTELLIGENCE") then
        return 2, 5
    end
    return 0, 0
end

function Gov.opinion(d, key, bloc)
    local value = 0
    local agenda = Gov.agenda(d)
    if agenda == "SPECIES" and R.SPECIES[key] and R.SPECIES[key] ~= "Human" then
        value = value + 10
    elseif agenda == "DEFENCE" and bloc == "Frontier Defence Caucus" then
        value = value + 8
    end
    if bloc == "The Aggrieved" then
        value = value + 5 * justice(d)
    end
    return value
end

local function councillor_of(key)
    for _, c in ipairs(R.COUNCIL.COUNCILLORS) do
        if c.candidate == key then
            return c
        end
    end
    return nil
end
Gov.councillor_of = councillor_of

local function alive(d, key)
    local c = councillor_of(key)
    if not c then
        return true
    end
    local ok, Council = pcall(require, "eawx-plugins/new-republic/RepublicCouncil")
    return not (ok and Council) or Council.alive(d, c.key)
end
Gov.alive = alive

function Gov.person_name(key)
    return R.CANDIDATES[key] and R.CANDIDATES[key].name or tostring(key)
end

local function valid(key)
    if key == "DUMMY_CHIEFOFSTATE_SHESH" then
        local ok, era = pcall(GlobalValue.Get, "CURRENT_ERA")
        return ok and (era or 0) >= 7
    end
    return true
end

function Gov.candidates(d)
    local Senate = senate()
    local s = state(d)
    local Members = members()
    local support = {}
    for key, _ in pairs(R.CANDIDATES) do
        if valid(key) and alive(d, key) then
            support[key] = 0
        end
    end
    local current = Gov.chief()
    for name, seat in pairs((Senate and Senate.seats(d)) or {}) do
        local best, best_score = current, -1
        for key, _ in pairs(support) do
            local c = R.CANDIDATES[key]
            local score = 0
            for _, interest in ipairs(c.interests) do
                if Members and Members.has(d, name, interest) then
                    score = score + 2
                end
            end
            if key == "DUMMY_CHIEFOFSTATE_FEYLYA" and Members and Members.species(name) == "Bothan" then
                score = score + 5
            end
            if key == current and seat.opinion >= 20 then
                score = score + 1
            end
            if score > best_score or (score == best_score and key == current) then
                best, best_score = key, score
            end
        end
        if best and support[best] then
            support[best] = support[best] + (seat.weight or 1)
        end
    end
    if s and s.backed and support[s.backed] then
        support[s.backed] = support[s.backed] + R.BACK_WEIGHT
    end
    local out = {}
    for key, value in pairs(support) do
        local c = R.CANDIDATES[key]
        table.insert(out, {key = key, name = c.name, agenda = c.agenda, text = c.text, support = value,
                           current = key == current, backed = s and s.backed == key})
    end
    table.sort(out, function(a, b)
        if a.support ~= b.support then
            return a.support > b.support
        end
        return a.name < b.name
    end)
    return out
end

function Gov.back(d, key)
    local s = state(d)
    local _, Republic = senate()
    if not (s and R.CANDIDATES[key]) then
        return false, "No such candidate."
    end
    if s.backed == key then
        return false, "You already back " .. R.CANDIDATES[key].name .. "."
    end
    if not Republic.spend(d, R.BACK_CAPITAL) then
        return false, "Backing a candidate costs " .. R.BACK_CAPITAL .. " political capital."
    end
    s.backed = key
    return true, "You back " .. R.CANDIDATES[key].name .. " at the next election."
end

function Gov.offices(d)
    local out = {}
    for _, office in ipairs(R.CABINET) do
        local holder = Gov.holder(d, office.key)
        table.insert(out, {key = office.key, name = office.name, text = office.text, holder = holder,
                           holder_name = holder and Gov.person_name(holder) or nil})
    end
    return out
end

function Gov.can_replace(d)
    local s = state(d)
    if s and s.window_until and GetCurrentTime() < s.window_until then
        return true, M.max(1, M.ceil((s.window_until - GetCurrentTime()) / U.weeks(1)))
    end
    return false, "Ministers can be replaced only in the " .. R.MINISTER_WINDOW_WEEKS .. " weeks after an election."
end

function Gov.can_appoint(d, office)
    local s = state(d)
    if s and office and not s.cabinet[office] then
        return true, 0
    end
    return Gov.can_replace(d)
end

function Gov.open_window(d)
    local s = state(d)
    if s then
        s.window_until = GetCurrentTime() + U.weeks(R.MINISTER_WINDOW_WEEKS)
    end
end

local OFFICE_INTEREST = {STATE = {"Pacifist", "Commerce"}, DEFENCE = {"Security"}, FINANCE = {"Commerce", "Industry"},
                         JUSTICE = {"Reparations", "Species rights"}, INTELLIGENCE = {"Security", "Autonomy"}}
function Gov.candidates_for(d, office)
    local s = state(d)
    local taken = {}
    for _, key in pairs((s and s.cabinet) or {}) do
        taken[key] = true
    end
    local chief = Gov.chief()
    local out = {}
    for key, c in pairs(R.CANDIDATES) do
        if valid(key) and alive(d, key) and key ~= chief and not taken[key] then
            local fit = 0
            for _, want in ipairs(OFFICE_INTEREST[office] or {}) do
                for _, interest in ipairs(c.interests or {}) do
                    if interest == want then
                        fit = fit + 20
                    end
                end
            end
            table.insert(out, {key = key, name = c.name, score = fit,
                               bloc = councillor_of(key) and "Councillor" or "Candidate",
                               interests = table.concat(c.interests or {}, ", ")})
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.name < b.name
    end)
    return out
end

function Gov.appoint(d, office, key)
    local s = state(d)
    local _, Republic = senate()
    if not (s and R.CANDIDATES[key]) then
        return false, "No such person."
    end
    local open, why = Gov.can_appoint(d, office)
    if not open then
        return false, why
    end
    if key == Gov.chief() or not alive(d, key) then
        return false, Gov.person_name(key) .. " cannot serve as a minister now."
    end
    for _, other in pairs(s.cabinet) do
        if other == key then
            return false, Gov.person_name(key) .. " already holds an office."
        end
    end
    if not Republic.spend(d, R.APPOINT_CAPITAL) then
        return false, "An appointment costs " .. R.APPOINT_CAPITAL .. " political capital."
    end
    s.cabinet[office] = key
    local office_name = office
    for _, o in ipairs(R.CABINET) do
        if o.key == office then
            office_name = o.name
        end
    end
    return true, Gov.person_name(key) .. " takes the office of " .. office_name .. "."
end

function Gov.dismiss(d, office)
    local s = state(d)
    local old = s and s.cabinet[office]
    if not old then
        return false, "The office is empty."
    end
    local open, why = Gov.can_replace(d)
    if not open then
        return false, why
    end
    s.cabinet[office] = nil
    return true, Gov.person_name(old) .. " leaves the office."
end

function Gov.vote(d, seat, motion)
    local Members = members()
    local function has(i)
        return Members and Members.has(d, seat.name, i)
    end
    if motion.kind == "APPROPRIATION" then
        if has("Security") or has("Industry") then
            return 1
        elseif has("Pacifist") or has("Commerce") then
            return -1
        end
        if has_office(d, "DEFENCE") or Gov.agenda(d) == "DEFENCE" then
            return 1
        end
        return (seat.opinion >= 0) and 1 or -1
    elseif motion.kind == "BILL" then
        local bill = nil
        for _, b in ipairs(R.BILLS) do
            if b.key == motion.bill then
                bill = b
            end
        end
        if bill then
            if (bill.interest and has(bill.interest)) or (bill.bloc and seat.bloc == bill.bloc)
                    or (motion.world and U.sector_of(seat.name) == U.sector_of(motion.world)) then
                return 1
            elseif bill.against and has(bill.against) then
                return -1
            end
        end
        return (seat.opinion >= 0) and 1 or 0
    elseif motion.kind == "NO_CONFIDENCE" then
        if seat.opinion < 0 then
            return 1
        elseif seat.opinion >= 20 then
            return -1
        end
        return 0
    end
    return nil
end

local function bill_of(key)
    for _, b in ipairs(R.BILLS) do
        if b.key == key then
            return b
        end
    end
    return nil
end

function Gov.enact(d, motion)
    local s = state(d)
    local Senate, Republic = senate()
    if motion.kind == "APPROPRIATION" then
        s.cut_pending, s.cut_until = nil, nil
        d.show("Senate: the Defence Appropriation passes. The fleet is funded.", nil, COLOR, 15)
    elseif motion.kind == "BILL" then
        local bill = bill_of(motion.bill)
        if bill.cost > 0 then
            if d.human.Get_Credits() < bill.cost then
                d.show("Senate: the treasury cannot pay for the bill (" .. bill.cost .. " credits). It lapses.", nil, WARN)
                return
            end
            d.human.Give_Money(-bill.cost)
        end
        local Members = members()
        for name, seat in pairs(Senate.seats(d)) do
            if (bill.interest and Members and Members.has(d, name, bill.interest)) or (bill.bloc and seat.bloc == bill.bloc)
                    or (motion.world and U.sector_of(name) == U.sector_of(motion.world)) then
                Senate.sway(d, name, bill.opinion, "the bill to " .. motion.text)
            elseif bill.against and Members and Members.has(d, name, bill.against) then
                Senate.sway(d, name, -bill.opinion, "the bill to " .. motion.text)
            end
        end
        d.show("Senate: the bill to " .. motion.text .. " becomes law.", nil, COLOR, 15)
        if bill.key == "AMNESTY" then
            pcall(Gov.amnesty, d)
        end
    elseif motion.kind == "NO_CONFIDENCE" then
        s.suspended_until = GetCurrentTime() + U.weeks(R.ELECTION_WEEKS or 10)
        Republic.change_mandate(d, -R.NO_CONFIDENCE_MANDATE)
        d.senate.stability = M.min(100, d.senate.stability + 10)
        d.show("Senate: the chamber has no confidence in " .. Gov.chief_name() .. ". Their agenda is suspended until "
            .. "the next election; the chamber's favourite stands in their place.", nil, WARN, 25)
    end
end

local function propose(d, motion)
    local Senate = senate()
    if not Senate or not Senate.can_propose(d) then
        return false
    end
    motion.senate = true
    return Senate.open_debate(d, motion, function() Gov.enact(d, motion) end)
end

local function in_office(d, s, c)
    if c.candidate == Gov.chief() then
        return true
    end
    for _, key in pairs(s.cabinet) do
        if key == c.candidate then
            return true
        end
    end
    return false
end

local function hero_objects(d, c)
    local out = {}
    for _, t in ipairs(c.units or {}) do
        local tp = Find_Object_Type(t)
        for _, obj in pairs(tp and Find_All_Objects_Of_Type(tp) or {}) do
            if TestValid(obj) and obj.Get_Owner() == d.human then
                table.insert(out, {obj = obj, type = t})
            end
        end
    end
    return out
end

function Gov.sync_heroes(d)
    local s = state(d)
    local ok_c, Council = pcall(require, "eawx-plugins/new-republic/RepublicCouncil")
    if not (s and ok_c and Council and Council.founded(d)) then
        return
    end
    local ok_a, Agents = pcall(require, "eawx-plugins/new-republic/RepublicOperatives")
    s.heroes = s.heroes or {}
    for _, c in ipairs(R.COUNCIL.COUNCILLORS) do
        if c.units and c.candidate and Council.alive(d, c.key) then
            local busy = in_office(d, s, c)
            if busy and not s.heroes[c.key] then
                local found = hero_objects(d, c)
                local safe = found[1] ~= nil
                for _, f in ipairs(found) do
                    if ok_a and Agents and not Agents.safe_to_remove(f.obj) then
                        safe = false
                    end
                end
                if safe then
                    local stored = found[1].type
                    for _, f in ipairs(found) do
                        if string.find(f.type, "_TEAM$") or string.find(f.type, "HOME_ONE") then
                            stored = f.type
                        end
                    end
                    for _, f in ipairs(found) do
                        if TestValid(f.obj) then
                            f.obj.Despawn()
                        end
                    end
                    s.heroes[c.key] = stored
                    d.show("Republic: " .. c.name .. " takes up office in the government and leaves the field.", nil,
                        COLOR, 20)
                end
            elseif not busy and s.heroes[c.key] then
                local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
                local ok, capital = pcall(Deals.capital, d, d.human)
                if ok and capital and Find_Object_Type(s.heroes[c.key])
                        and pcall(SpawnList, {s.heroes[c.key]}, capital, d.human, true, false) then
                    s.heroes[c.key] = nil
                    d.show("Republic: out of office, " .. c.name .. " returns to the field at " .. d:planet_name(capital)
                        .. ".", nil, COLOR, 20)
                end
            end
        elseif s.heroes[c.key] and not Council.alive(d, c.key) then
            s.heroes[c.key] = nil
        end
    end
end

function Gov.hero_in_office(d, key)
    local s = d.republic and d.republic.gov
    return s ~= nil and s.heroes ~= nil and s.heroes[key] ~= nil
end

function Gov.week(d, seated)
    local s = state(d)
    if not s then
        return
    end
    local leader = Gov.candidates(d)[1]
    if leader then
        pcall(GlobalValue.Set, "ChiefOfStatePreference", leader.key)
    end
    local chief = Gov.chief()
    if s.chief and chief and chief ~= s.chief then
        local c = R.CANDIDATES[chief]
        s.backed = nil
        s.suspended_until = nil
        if c then
            d.show("Republic: the Senate elects " .. c.name .. " Chancellor. Agenda: " .. c.text, nil, COLOR, 25)
        end
    end
    if s.chief ~= chief then
        Gov.open_window(d)
    end
    s.chief = chief
    for office, key in pairs(s.cabinet) do
        if key == chief then
            s.cabinet[office] = nil
            d.show("Republic: " .. Gov.person_name(key) .. " leaves the cabinet to become Chancellor. Appoint a new "
                .. "minister in the government tab.", nil, COLOR, 20)
        elseif not R.CANDIDATES[key] or not alive(d, key) then
            s.cabinet[office] = nil
        end
    end
    pcall(Gov.sync_heroes, d)
    if Gov.agenda(d) == "SMALL_WORLDS" and not d.senate.council then
        local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
        if ok and Sym then
            for _, planet in pairs(FindPlanet.Get_All_Planets()) do
                if U.category(planet.Get_Owner().Get_Faction_Name()) == "INDEPENDENT" and Sym.value(d, U.key(planet)) then
                    Sym.change(d, U.key(planet), 1)
                end
            end
        end
    end
    if s.cut_pending and not (d.senate.debate and d.senate.debate.motion and d.senate.debate.motion.kind == "APPROPRIATION") then
        s.cut_pending = nil
        s.cut_until = GetCurrentTime() + U.weeks(R.SESSION_WEEKS)
        d.show("Senate: the Defence Appropriation failed. Credits are withheld from the fleet until the next session.",
            nil, WARN, 20)
    end
    if s.cut_until then
        if GetCurrentTime() < s.cut_until then
            d.human.Give_Money(-R.APPROPRIATION_WITHHELD)
        else
            s.cut_until = nil
        end
    end
    if d.senate.council then
        return
    end
    if d.senate.stability < R.NO_CONFIDENCE_COHESION
            and GetCurrentTime() - (s.last_confidence or -U.weeks(R.NO_CONFIDENCE_WEEKS)) >= U.weeks(R.NO_CONFIDENCE_WEEKS) then
        local motion = {kind = "NO_CONFIDENCE", text = "declare no confidence in " .. Gov.chief_name(),
                        label = "No Confidence", tip = "Filed by the chamber: cohesion is very low."}
        if propose(d, motion) then
            s.last_confidence = GetCurrentTime()
            return
        end
    end
    if GetCurrentTime() >= (s.next_session or 0) then
        local motion = {kind = "APPROPRIATION", text = "pass the Defence Appropriation", label = "Defence Appropriation",
                        tip = "The fleet's budget. Failed and not overridden, " .. R.APPROPRIATION_WITHHELD
                            .. " credits are withheld each week until the next session."}
        if propose(d, motion) then
            s.next_session = GetCurrentTime() + U.weeks(R.SESSION_WEEKS)
            s.cut_pending = true
        end
    elseif U.chance(R.BILL_CHANCE / 4) then
        local bill = U.pick(R.BILLS)
        local world = nil
        local keys = {}
        for key, _ in pairs(seated) do
            table.insert(keys, key)
        end
        world = U.pick(keys)
        local text = bill.text
        if string.find(text, "{world}") then
            if not world then
                return
            end
            text = string.gsub(text, "{world}", d:planet_name(seated[world]))
        end
        propose(d, {kind = "BILL", bill = bill.key, world = world, text = text,
                    label = string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2),
                    tip = bill.tip .. ((bill.cost > 0) and (" Costs " .. bill.cost .. " credits if passed.") or "")})
    end
end

function Gov.amnesty(d)
    local A = R.AMNESTY
    local Senate, Republic = senate()
    d.republic.amnesty = true
    local ok_i, Intel = pcall(require, "eawx-plugins/new-republic/RepublicIntel")
    local seen, came = {}, {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local faction = string.upper(planet.Get_Owner().Get_Faction_Name())
        local kind = U.category(faction)
        if not seen[faction] and (kind == "IMPERIAL" or kind == "WARLORD") and d:relation(faction) == "WAR" then
            seen[faction] = true
            for _, hero in ipairs(ok_i and Intel.heroes(faction, d) or {}) do
                if U.chance(A.DEFECT) and Intel.defect(d, faction, hero.type) then
                    table.insert(came, hero.name)
                end
            end
        end
    end
    local ok_b, Blocs = pcall(require, "eawx-plugins/new-republic/RepublicBlocs")
    local aggrieved = ok_b and Blocs.name_of("AGGRIEVED")
    local Members = Republic.part("members")
    for name, seat in pairs(Senate.seats(d)) do
        if (aggrieved and seat.bloc == aggrieved) or (Members and Members.has(d, name, "Liberation")) then
            Senate.sway(d, name, -A.OPINION, "the Imperial Amnesty")
        end
    end
    if d.senate then
        d.senate.stability = M.max(0, d.senate.stability - A.COHESION)
    end
    d.show("The Imperial Amnesty is law: cohesion -" .. A.COHESION .. ", Liberation and Aggrieved worlds' opinion -"
        .. A.OPINION .. (came[1] and (". Defected: " .. table.concat(came, ", ") .. ".") or ". No Imperial hero came over yet."),
        nil, COLOR, 25)
end

return Gov
