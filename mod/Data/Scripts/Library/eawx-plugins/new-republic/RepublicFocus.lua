local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Focus = {}
local F = R.SENATE_FOCUS
local COLOR = {r = 170, g = 200, b = 255}

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.focus = r.focus or {}
    return r.focus
end

function Focus.active(d)
    local s = d.republic and d.republic.focus
    if s and s.key and GetCurrentTime() < (s.ends or 0) then
        return s.key
    end
    return nil
end

function Focus.weeks_left(d)
    local s = d.republic and d.republic.focus
    if not Focus.active(d) then
        return 0
    end
    return M.max(1, M.ceil((s.ends - GetCurrentTime()) / U.weeks(1)))
end

function Focus.def(key)
    return F.LIST[key]
end

function Focus.boosted(d, key)
    local def = F.LIST[key]
    local Gov = Republic().part("gov")
    return def ~= nil and def.office ~= nil and Gov ~= nil and Gov.holder(d, def.office) ~= nil
end

local function amount(d, key)
    if Focus.active(d) ~= key then
        return 0
    end
    local def = F.LIST[key]
    return Focus.boosted(d, key) and def.boosted or def.value
end

function Focus.cost(d, key)
    local Gov = Republic().part("gov")
    local Laws = Republic().part("laws")
    local agenda = Gov and Gov.agenda(d)
    local cost = F.CAPITAL
    for _, a in ipairs(F.LIST[key].agendas or {}) do
        if a == agenda then
            cost = F.CAPITAL_AGENDA
        end
    end
    return Laws and Laws.price(d, cost) or cost
end

local function jedi_ready(d)
    local j = d.republic and d.republic.jedi
    return j ~= nil and j.roster ~= nil and next(j.roster) ~= nil
end

function Focus.blocked(d, key)
    if Focus.active(d) then
        return "The Senate's focus holds for " .. Focus.weeks_left(d) .. " more week" .. ((Focus.weeks_left(d) == 1) and "" or "s") .. "."
    end
    if key == "JEDI" and not jedi_ready(d) then
        return "There is no Jedi Order yet to restore."
    end
    if (d.republic.capital or 0) < Focus.cost(d, key) then
        return "Not enough political capital (" .. Focus.cost(d, key) .. " needed)."
    end
    return nil
end

function Focus.motion(d, key)
    local def = F.LIST[key]
    return {kind = "FOCUS", focus = key, capital = Focus.cost(d, key), label = def.name,
            text = "make " .. def.name .. " the Senate's focus for " .. F.WEEKS .. " weeks",
            tip = def.name .. ": " .. def.text}
end

function Focus.stance(d, seat, motion)
    local def = F.LIST[motion.focus or ""]
    local out = {}
    if not def then
        return out
    end
    local Blocs, Members, Parties = Republic().part("blocs"), Republic().part("members"), Republic().part("parties")
    local bloc = Blocs and Blocs.key_of(seat.bloc)
    for _, b in ipairs(def.favoured or {}) do
        if b == bloc then
            table.insert(out, {"its bloc backs " .. def.name, F.BLOC_FOR})
        end
    end
    for _, b in ipairs(def.opposed or {}) do
        if b == bloc then
            table.insert(out, {"its bloc opposes " .. def.name, -F.BLOC_AGAINST})
        end
    end
    for _, i in ipairs(def.likes or {}) do
        if Members and Members.has(d, seat.name, i) then
            table.insert(out, {"it cares for " .. string.lower(i), F.INTEREST})
        end
    end
    for _, i in ipairs(def.dislikes or {}) do
        if Members and Members.has(d, seat.name, i) then
            table.insert(out, {"a " .. string.lower(i) .. " world", -F.INTEREST})
        end
    end
    local party = Parties and Parties.ruling_party(d, seat.name)
    if party then
        for _, b in ipairs(def.favoured or {}) do
            if b == party.bloc then
                table.insert(out, {"its ruling party wants it", F.PARTY})
            end
        end
        if party.bloc == "INDEPENDENCE" then
            table.insert(out, {"its separatist senator", -F.PARTY})
        end
    end
    local species = Members and Members.species(seat.name) or "Human"
    if motion.focus == "CHARTER" then
        table.insert(out, (species ~= "Human") and {"its people gain from it", F.SPECIES} or {"a human world", -F.SPECIES / 2})
    elseif motion.focus == "RIM" then
        local far = d.republic.members and d.republic.members.far and d.republic.members.far[seat.name]
        if far and far.jumps >= R.FAR_JUMPS then
            table.insert(out, {"a far world, often forgotten", F.SPECIES})
        end
    elseif motion.focus == "JEDI" then
        local trust = (d.republic.jedi and d.republic.jedi.trust) or 50
        local v = M.round((trust - 50) * F.JEDI_TRUST)
        if v ~= 0 then
            table.insert(out, {(v > 0) and "the people trust the Jedi" or "the people mistrust the Jedi", v})
        end
    elseif motion.focus == "HUNT" and seat.threat and U.category(seat.threat) == "WARLORD" then
        table.insert(out, {"a warlord at its border", F.SPECIES})
    elseif motion.focus == "FLEET" and seat.threat then
        table.insert(out, {"an enemy at its border", F.INTEREST})
    end
    return out
end

function Focus.enact(d, motion)
    local s = state(d)
    local def = F.LIST[motion.focus or ""]
    if not s or not def then
        return
    end
    s.key, s.ends, s.last = motion.focus, GetCurrentTime() + U.weeks(F.WEEKS), motion.focus
    d.show("Senate: " .. def.name .. " is the Senate's focus for " .. F.WEEKS .. " weeks. " .. def.text, nil, COLOR, 20)
end

function Focus.cohesion(d)
    return amount(d, "CORE")
end

function Focus.opinion(d, key)
    local v = 0
    local Members = Republic().part("members")
    if Focus.active(d) == "CHARTER" and Members and Members.species(key) ~= "Human" then
        v = v + amount(d, "CHARTER")
    elseif Focus.active(d) == "RIM" then
        local far = d.republic.members and d.republic.members.far and d.republic.members.far[key]
        if far and far.jumps >= R.FAR_JUMPS then
            v = v + amount(d, "RIM")
        end
    end
    return v
end

function Focus.no_drift(d)
    return Focus.active(d) == "RIM"
end

function Focus.favours(d)
    local key = Focus.active(d)
    local def = key and F.LIST[key]
    return (def and def.clout) or {}
end

function Focus.hunting(d, old_owner)
    return Focus.active(d) == "HUNT" and U.category(old_owner or "") == "WARLORD"
end

function Focus.hunted(d, key, band)
    d.republic.hunted = d.republic.hunted or {}
    local Sym = Republic().part("sym")
    d.republic.hunted[key] = {band = band, prefers = Sym and Sym.preferred and Sym.preferred(d, key) or nil}
end

function Focus.seated(d, key)
    local h = d.republic.hunted and d.republic.hunted[key]
    if not h or not Republic().senate then
        return
    end
    d.republic.hunted[key] = nil
    local friendly = h.prefers == "REBEL" and h.band ~= "HOSTILE"
    local value = friendly and F.HUNTED_ANNOYED or F.HUNTED_ANGRY
    Republic().senate.sway(d, key, -value, friendly and "the Republic took it by force in the hunt for the warlords"
        or "it was conquered in the hunt for the warlords, against its people's will")
end

function Focus.week(d)
    local s = state(d)
    if not s then
        return
    end
    if s.key and GetCurrentTime() >= (s.ends or 0) then
        local def = F.LIST[s.key]
        d.show("Senate: " .. (def and def.name or "the focus") .. " has run its course. The Chancellor may propose "
            .. "a new focus.", nil, COLOR, 15)
        s.key, s.ends = nil, nil
    end
    local key = Focus.active(d)
    if not key then
        return
    end
    if key == "FLEET" then
        local function perceive(name)
            local ok, v = pcall(EvaluatePerception, name, d.human)
            return (ok and type(v) == "number") and v or 0
        end
        local upkeep = M.floor(perceive("Total_Maintenance")) - 10 * perceive("LightFactory_Count")
            - 20 * perceive("HeavyFactory_Count") - 30 * perceive("AdvFactory_Count")
        local refund = M.floor(M.max(0, upkeep) * amount(d, "FLEET") / 100)
        if refund > 0 then
            d.human.Give_Money(refund)
        end
    elseif key == "TRADE" then
        local S = Republic().part("sectors")
        local total = 0
        for _, credits in pairs((S and S.trade_income and S.trade_income(d)) or {}) do
            total = total + credits
        end
        local bonus = M.floor(total * amount(d, "TRADE") / 100)
        if bonus > 0 then
            d.human.Give_Money(bonus)
        end
    elseif key == "REFUGEES" then
        local Sym = Republic().part("sym")
        for world in pairs(d.republic.freed_worlds or {}) do
            local planet = FindPlanet(world)
            if Sym and planet and planet.Get_Owner() == d.human then
                Sym.change(d, world, amount(d, "REFUGEES"))
            end
        end
    elseif key == "JEDI" then
        local j = d.republic.jedi
        if j then
            j.trust = U.clamp((j.trust or 50) + amount(d, "JEDI"), 0, 100)
            j.knowledge = (j.knowledge or 0) + F.JEDI_KNOWLEDGE
        end
    end
end

return Focus
