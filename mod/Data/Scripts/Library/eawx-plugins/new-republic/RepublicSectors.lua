local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local S = {}
local COLOR = {r = 170, g = 200, b = 255}

local function state(d)
    local r = d.republic
    if not r then
        return nil
    end
    r.tax = r.tax or {level = {}, motion = {}, raised = {}, grudge = {}, last = 0}
    return r.tax
end

function S.level(d, sector)
    local s = state(d)
    return (s and s.level[sector]) or R.TAX_NORMAL
end

function S.level_name(level)
    return R.TAX_LEVELS[level].name
end

function S.sectors(d, seated)
    local by = {}
    for key, _ in pairs(seated or {}) do
        local sector = U.sector_of(key)
        by[sector] = by[sector] or {name = sector, worlds = {}}
        table.insert(by[sector].worlds, key)
    end
    local out = {}
    for name, entry in pairs(by) do
        entry.level = S.level(d, name)
        table.sort(entry.worlds)
        table.insert(out, entry)
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function agenda(d)
    local ok, Gov = pcall(require, "eawx-plugins/new-republic/RepublicGovernment")
    return ok and Gov and Gov.agenda(d) or nil
end

function S.opinion(d, key)
    local s = state(d)
    if not s then
        return 0
    end
    local sector = U.sector_of(key)
    local value = R.TAX_LEVELS[S.level(d, sector)].opinion
    if value < 0 and agenda(d) == "AUTONOMY" then
        value = M.round(value / 2)
    end
    local g = s.grudge[sector]
    if g then
        local left = 1 - (GetCurrentTime() - g.start) / U.weeks(g.weeks)
        if left <= 0 then
            s.grudge[sector] = nil
        else
            value = value + M.round(g.value * left)
        end
    end
    return value
end

local function trade_income(d)
    local out = {}
    for type_name, credits in pairs(R.TRADE_DUMMIES) do
        if Find_Object_Type(type_name) then
            for _, obj in pairs(Find_All_Objects_Of_Type(type_name) or {}) do
                if TestValid(obj) and obj.Get_Owner() == d.human then
                    local ok, planet = pcall(function() return obj.Get_Planet_Location() end)
                    if ok and planet then
                        local key = U.key(planet)
                        out[key] = (out[key] or 0) + credits
                    end
                end
            end
        end
    end
    return out
end

local function income_of(d, planet, trade)
    local ok, value = pcall(EvaluatePerception, "PlanetBaseIncome", d.human, planet)
    return M.min(M.max(M.sane((ok and value) or 0), 0), 100000) + (trade[U.key(planet)] or 0)
end
S.trade_income = trade_income
S.income_of = income_of

function S.week(d, seated)
    local s = state(d)
    if not s then
        return
    end
    local bonus = 0
    local ok, Gov = pcall(require, "eawx-plugins/new-republic/RepublicGovernment")
    if ok and Gov then
        bonus = Gov.tax_bonus(d)
    end
    d.influence_mods = d.influence_mods or {}
    local Occupation = require("eawx-plugins/diplomacy/DiplomacyOccupation")
    local total = 0
    local trade = trade_income(d)
    local c = d.republic and d.republic.council
    local laws = (c and c.constitution == "LAWS") and 1 or 0
    s.by_sector = {}
    for key, planet in pairs(seated or {}) do
        local sector = U.sector_of(key)
        local Laws = require("eawx-plugins/new-republic/Republic").part("laws")
        local lvl = S.level(d, sector) + ((Laws and Laws.tax_levels(d, sector)) or 0)
        local level = R.TAX_LEVELS[M.min(table.getn(R.TAX_LEVELS), lvl)]
        local income = income_of(d, planet, trade)
        local entry = s.by_sector[sector] or {income = 0, take = 0}
        s.by_sector[sector] = entry
        entry.income = entry.income + income
        if level.pct ~= 0 then
            local credits = income * level.pct / 100
            if credits > 0 then
                credits = credits * (1 + bonus / 100) * ((Laws and Laws.tax_factor(d, sector)) or 1)
            end
            entry.take = entry.take + M.round(credits)
            total = total + credits
        end
        local influence = level.influence + laws
        if influence ~= 0 then
            d.influence_mods[key] = influence
            pcall(Occupation.hook, d, key)
        elseif d.influence_mods[key] then
            d.influence_mods[key] = nil
        end
    end
    total = M.round(total)
    if total ~= 0 then
        d.human.Give_Money(total)
    end
    s.last = total
end

function S.can_move(d, sector)
    local s = state(d)
    local last = s and s.motion[sector]
    return not last or GetCurrentTime() - last >= U.weeks(R.TAX_MOTION_WEEKS)
end

function S.motion(d, sector, level)
    local now = S.level(d, sector)
    local verb = (level > now) and "raise" or "lower"
    return {kind = "TAX", sector = sector, level = level, from = now, group = "TAX",
            label = sector .. ": " .. S.level_name(level),
            text = verb .. " taxes in the " .. sector .. " to " .. string.lower(S.level_name(level)),
            tip = "Now " .. string.lower(S.level_name(now)) .. ". Its members' income " .. ((R.TAX_LEVELS[level].pct >= 0)
                and "+" or "") .. R.TAX_LEVELS[level].pct .. "%; their opinion " .. ((R.TAX_LEVELS[level].opinion >= 0)
                and "+" or "") .. R.TAX_LEVELS[level].opinion .. ". The sector's own senators vote "
                .. ((level > now) and "against it." or "for it.")}
end

function S.motions(d, seated)
    local out = {}
    for _, sec in ipairs(S.sectors(d, seated)) do
        if S.can_move(d, sec.name) then
            if sec.level > 1 then
                table.insert(out, S.motion(d, sec.name, sec.level - 1))
            end
            if sec.level < table.getn(R.TAX_LEVELS) then
                table.insert(out, S.motion(d, sec.name, sec.level + 1))
            end
        end
    end
    return out
end

function S.vote(d, seat, motion, interests, at_war)
    local now = S.level(d, motion.sector)
    local raise = motion.level > now
    if U.sector_of(seat.name) == motion.sector then
        return raise and -1 or 1
    end
    for _, i in ipairs(interests or {}) do
        if i == "Commerce" and raise then
            return -1
        elseif i == "Security" and raise and at_war then
            return 1
        elseif i == "Autonomy" and raise then
            return -1
        end
    end
    return (seat.opinion >= 10) and 1 or 0
end

function S.enact(d, motion)
    local s = state(d)
    if not s then
        return
    end
    local now = S.level(d, motion.sector)
    s.level[motion.sector] = motion.level
    s.motion[motion.sector] = GetCurrentTime()
    if motion.level > now then
        s.raised[motion.sector] = (s.raised[motion.sector] or 0) + (motion.level - now)
    elseif (s.raised[motion.sector] or 0) > 0 then
        local levels = s.raised[motion.sector]
        s.grudge[motion.sector] = {value = -R.GRUDGE_OPINION * levels, start = GetCurrentTime(),
                                   weeks = M.min(R.GRUDGE_MAX_WEEKS, R.GRUDGE_WEEKS_PER_LEVEL * levels)}
        s.raised[motion.sector] = 0
    end
    d.show("Republic: taxes in the " .. motion.sector .. " are now " .. string.lower(S.level_name(motion.level))
        .. ".", nil, COLOR, 20)
end

return S
