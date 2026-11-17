local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local Events = {}
local COLOR = {r = 170, g = 200, b = 255}

local BY_KEY = {}
for _, c in ipairs(R.CRISES) do
    BY_KEY[c.key] = c
end

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.events = r.events or {done = {}}
    return r.events
end

function Events.active(d)
    local s = state(d)
    if not (s and s.active) then
        return nil
    end
    local c = BY_KEY[s.active.key]
    return c and {crisis = c, left = M.max(0, M.ceil((s.active.ends - GetCurrentTime()) / U.weeks(1)))} or nil
end

local function sway_where(d, test, amount, reason)
    local Republic = require("eawx-plugins/new-republic/Republic")
    local Senate = Republic.senate
    for name, seat in pairs((Senate and Senate.seats(d)) or {}) do
        if test(name, seat) then
            Senate.sway(d, name, amount, reason)
        end
    end
end

local function apply(d, crisis, choice)
    local Republic = require("eawx-plugins/new-republic/Republic")
    local Members = require("eawx-plugins/new-republic/RepublicMembers")
    local reason = string.lower(crisis.title)
    if choice.credits then
        d.human.Give_Money(choice.credits)
    end
    if choice.cohesion and d.senate then
        d.senate.stability = U.clamp(d.senate.stability + choice.cohesion, 0, 100)
    end
    if choice.mandate and not Republic.senate_mandate(d, choice.mandate) then
        Republic.change_mandate(d, choice.mandate)
    end
    if choice.capital and d.republic then
        d.republic.capital = U.clamp(d.republic.capital + choice.capital, 0, Republic.CONFIG.CAPITAL_MAX)
    end
    for _, field in ipairs({"interest", "interest2"}) do
        local i = choice[field]
        if i then
            sway_where(d, function(name) return Members.has(d, name, i[1]) end, i[2], reason)
        end
    end
    if choice.species then
        sway_where(d, function(name) return Members.species(name) == choice.species[1] end, choice.species[2], reason)
    end
    if choice.bloc then
        sway_where(d, function(_, seat) return seat.bloc == choice.bloc[1] end, choice.bloc[2], reason)
    end
end

local function signed(v)
    return ((v > 0) and "+" or "") .. v
end

function Events.effects(choice)
    local out = {}
    if choice.credits then
        table.insert(out, ((choice.credits < 0) and "Costs " or "Brings in ") .. M.abs(choice.credits) .. " credits")
    end
    if choice.capital then
        table.insert(out, ((choice.capital < 0) and "Costs " or "Gains ") .. M.abs(choice.capital) .. " political capital")
    end
    if choice.cohesion then
        table.insert(out, "Cohesion " .. signed(choice.cohesion))
    end
    if choice.mandate then
        table.insert(out, "Mandate " .. signed(choice.mandate))
    end
    for _, field in ipairs({"interest", "interest2"}) do
        local i = choice[field]
        if i then
            table.insert(out, "Opinion " .. signed(i[2]) .. " on worlds that care about " .. string.lower(i[1]))
        end
    end
    if choice.species then
        table.insert(out, "Opinion " .. signed(choice.species[2]) .. " on " .. choice.species[1] .. " worlds")
    end
    if choice.bloc then
        table.insert(out, "Opinion " .. signed(choice.bloc[2]) .. " in the " .. choice.bloc[1])
    end
    return table.concat(out, ". ") .. "."
end

function Events.choose(d, which)
    local s = state(d)
    local active = s and s.active
    local crisis = active and BY_KEY[active.key]
    if not crisis then
        return false, "No crisis is waiting."
    end
    local choice = crisis[which]
    if which == "a" and choice.credits and d.human.Get_Credits() < -choice.credits then
        return false, "The treasury cannot pay " .. (-choice.credits) .. " credits."
    end
    if which == "a" and choice.capital and choice.capital < 0 and (d.republic.capital or 0) < -choice.capital then
        return false, "Not enough political capital."
    end
    s.active = nil
    s.done[crisis.key] = true
    apply(d, crisis, choice)
    d.show("Republic: " .. crisis.title .. ": " .. choice.text .. ". " .. Events.effects(choice), nil, COLOR, 20)
    return true, choice.text .. ". " .. Events.effects(choice)
end

function Events.week(d)
    local s = state(d)
    if not s then
        return
    end
    if s.active then
        if GetCurrentTime() >= s.active.ends then
            local crisis = BY_KEY[s.active.key]
            s.active = nil
            if crisis then
                s.done[crisis.key] = true
                apply(d, crisis, crisis.b)
                d.show("Republic: " .. crisis.title .. " was left to the Senate: " .. crisis.b.text .. ". "
                    .. Events.effects(crisis.b), nil, COLOR, 20)
            end
        end
        return
    end
    if not U.chance(R.CRISIS_CHANCE) then
        return
    end
    local year = GlobalValue.Get("GALACTIC_YEAR") or 0
    local open = {}
    for _, c in ipairs(R.CRISES) do
        if not s.done[c.key] and year >= c.from and year <= c.to then
            table.insert(open, c)
        end
    end
    local crisis = U.pick(open)
    if crisis then
        s.active = {key = crisis.key, ends = GetCurrentTime() + U.weeks(R.CRISIS_WEEKS)}
        d.show("Crisis: " .. crisis.title .. ". " .. crisis.text .. " Decide in the Republic window (Government).",
            nil, {r = 255, g = 210, b = 120}, 30)
    end
end

return Events
