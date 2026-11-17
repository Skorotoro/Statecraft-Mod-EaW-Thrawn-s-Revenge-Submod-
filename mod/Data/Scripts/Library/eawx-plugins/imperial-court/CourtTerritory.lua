local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")

local T = {}

local function serving(c)
    return c and c.status == "serving"
end

local function sector_name(s, key)
    return (s.sectors[key or ""] and s.sectors[key].name) or "a sector"
end

local function over_name(s, key)
    return (s.oversectors[key or ""] and s.oversectors[key].name) or "an oversector"
end

local function rival_chance(a, b, chance, news, s)
    if serving(a) and serving(b) and a ~= b and not Court.is_rival(a, b.id) and M.chance(chance) then
        if Court.add_tie(a, b, "rivals") and news then
            Court.news(s, news)
        end
        return true
    end
    return false
end

function T.after_grant(s, c, title, key)
    local X = CONFIG.TERRITORY
    local sector_key, over_key = Court.holding_place(s, {title = title, key = key})
    if c.title == "moff" or c.title == "grand_moff" then
        local sector = (title == "governor") and sector_key and s.sectors[sector_key]
        local moff = sector and Court.char(s, sector.holder)
        if serving(moff) and moff ~= c then
            Court.opinion(moff, c.name .. " was given lands in their sector", X.INFRINGED, X.WEEKS)
            rival_chance(moff, c, X.INFRINGED_RIVAL, Court.full_name(moff) .. " takes it ill that "
                .. Court.full_name(c) .. " holds lands in the " .. sector_name(s, sector_key) .. ".", s)
        end
    end
    if c.title == "grand_moff" and title ~= "grand_moff" and over_key then
        local gm = s.oversectors[over_key] and Court.char(s, s.oversectors[over_key].holder)
        if serving(gm) and gm ~= c then
            Court.opinion(gm, c.name .. " was given lands in their oversector", X.INFRINGED, X.WEEKS)
            rival_chance(gm, c, X.INFRINGED_RIVAL, Court.full_name(gm) .. " resents " .. Court.full_name(c)
                .. "'s new lands in the " .. over_name(s, over_key) .. ".", s)
        end
    end
    T.one_liege(s)
end

function T.one_liege(s)
    local X = CONFIG.TERRITORY
    for _, id in ipairs(s.order) do
        local m = s.chars[id]
        if serving(m) and m.title == "moff" then
            local overs, list = {}, {}
            for _, h in ipairs(Court.holdings(s, m)) do
                local _, over_key = Court.holding_place(s, h)
                local over = over_key and s.oversectors[over_key]
                local gm = over and Court.char(s, over.holder)
                if serving(gm) and gm ~= m then
                    if not overs[over_key] then
                        overs[over_key] = {key = over_key, gm = gm, since = over.since or 0, holdings = {}}
                        table.insert(list, overs[over_key])
                    end
                    table.insert(overs[over_key].holdings, h)
                end
            end
            if table.getn(list) >= 2 then
                table.sort(list, function(a, b)
                    if a.since ~= b.since then
                        return a.since > b.since
                    end
                    return a.key < b.key
                end)
                local newest = list[1]
                for _, h in ipairs(newest.holdings) do
                    Court.vacate(s, m, h.title, h.key)
                    Court.give_holding(s, newest.gm, h.title, h.key)
                end
                Court.touch_holdings()
                Court.sync_title(s, m)
                Court.sync_title(s, newest.gm)
                Court.opinion(m, "their lands were given to " .. newest.gm.name, X.LANDS_TAKEN, X.WEEKS)
                for k = 2, table.getn(list) do
                    local other = list[k].gm
                    Court.opinion(other, newest.gm.name .. " took their Moff's lands", X.VASSAL_TAKEN, X.WEEKS)
                    rival_chance(other, newest.gm, X.VASSAL_TAKEN_RIVAL, nil, s)
                end
                local n = table.getn(newest.holdings)
                Court.news(s, Court.full_name(m) .. " cannot answer to two Grand Moffs: " .. n
                    .. ((n == 1) and " holding" or " holdings") .. " in the " .. over_name(s, newest.key) .. " pass to "
                    .. Court.full_name(newest.gm) .. ".")
            end
        end
    end
end

function T.coveted(s, c)
    if not serving(c) then
        return nil
    end
    local own = {}
    for _, h in ipairs(Court.holdings(s, c)) do
        if h.title == "moff" then
            own[h.key] = true
        end
    end
    local best, best_n
    local function consider(key)
        local sector = s.sectors[key or ""]
        if sector and not sector.crown and not own[key] and table.getn(sector.worlds) > 0 then
            local n = table.getn(sector.worlds)
            if not best or n > best_n or (n == best_n and key < best) then
                best, best_n = key, n
            end
        end
    end
    if c.title == "moff" then
        for _, h in ipairs(Court.holdings(s, c)) do
            if h.title == "governor" then
                consider(s.world[h.key])
            end
        end
    elseif c.title == "grand_moff" and c.holds then
        for key, _ in pairs(own) do
            if s.sectors[key] and s.sectors[key].oversector == c.holds then
                return nil
            end
        end
        for key, sector in pairs(s.sectors) do
            if sector.oversector == c.holds then
                consider(key)
            end
        end
    end
    return best
end

local function hoarding(s, c)
    local count, out = {}, {}
    for _, h in ipairs(Court.holdings(s, c)) do
        local sector_key, over_key = Court.holding_place(s, h)
        local area = (c.title == "grand_moff") and sector_key or ((c.title == "moff") and over_key or nil)
        if area and h.title ~= "grand_moff" then
            count[area] = (count[area] or 0) + 1
        end
    end
    for area, n in pairs(count) do
        if n > 1 then
            out[area] = n - 1
        end
    end
    return out
end

local function lord_in(s, v, area, by_sector)
    for _, h in ipairs(Court.holdings(s, v)) do
        local sector_key, over_key = Court.holding_place(s, h)
        if (by_sector and sector_key == area) or (not by_sector and over_key == area) then
            return true
        end
    end
    return false
end

local COVET_TEXTS = {
    "{a} openly covets the seat of the {sector}, held by {b}.",
    "{a} tells the court that {b} is unfit to rule the {sector}.",
    "{a} courts the officers of the {sector} behind {b}'s back.",
    "{a} and {b} quarrel over the tithes of the {sector}.",
}

local function fill(text, a, b, sector)
    text = string.gsub(text, "{a}", Court.full_name(a))
    text = string.gsub(text, "{b}", b and Court.full_name(b) or "nobody")
    text = string.gsub(text, "{sector}", sector)
    return text
end

local function denunciations(s)
    local X = CONFIG.TERRITORY.DENOUNCE
    local Politics = require("eawx-plugins/imperial-court/CourtPolitics")
    if table.getn(s.petitions) >= CONFIG.PETITION_MAX then
        return
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if serving(c) and not c.leads and not c.heir and not c.traitor
                and (c.title ~= "courtier" or Court.office_of(s, c) or c.fleet_rank)
                and not Politics.pending(s, "denounce", c.id) and not T.denounced(s, c.id)
                and s.week - ((s.denounce_week or {})[c.id] or -99) >= X.COOLDOWN then
            local rivals = Court.ties(s, c, "rivals")
            local backers = {}
            for _, r in ipairs(rivals) do
                if serving(r) and not r.leads then
                    table.insert(backers, r)
                end
            end
            local n = table.getn(backers)
            if n >= X.MIN_RIVALS and M.chance(X.PER_RIVAL * n) then
                table.sort(backers, function(a, b)
                    return (a.influence or 0) > (b.influence or 0)
                end)
                local ids = {}
                for _, b in ipairs(backers) do
                    table.insert(ids, b.id)
                end
                s.denounce_week = s.denounce_week or {}
                s.denounce_week[c.id] = s.week
                Politics.add_petition(s, {char = backers[1].id, kind = "denounce", target = c.id, backers = ids,
                                          weeks = X.WEEKS})
                return
            end
        end
    end
end

function T.denounced(s, id)
    local entry = s.denounced and s.denounced[id]
    if entry and entry.until_week >= s.week then
        return true
    end
    for _, p in ipairs(s.petitions or {}) do
        if p.kind == "denounce" and p.target == id then
            return true
        end
    end
    return false
end

function T.week(s)
    local X = CONFIG.TERRITORY
    local lords = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if serving(c) then
            table.insert(lords, c)
            c.agitated = nil
        end
    end
    for _, c in ipairs(lords) do
        local key = T.coveted(s, c)
        if key then
            if not c.covet or c.covet.key ~= key then
                c.covet = {key = key, since = s.week}
            end
            local holder = Court.char(s, s.sectors[key].holder)
            if serving(holder) and holder ~= c then
                local name = sector_name(s, key)
                if not rival_chance(c, holder, X.COVET_RIVAL, Court.full_name(c) .. " and " .. Court.full_name(holder)
                        .. " become rivals over the seat of the " .. name .. ".", s)
                        and Court.is_rival(c, holder.id) and M.chance(X.COVET_EVENT) then
                    Court.news(s, fill(M.pick(COVET_TEXTS), c, holder, name))
                end
            end
        else
            c.covet = nil
        end
        for area, excess in pairs(hoarding(s, c)) do
            local by_sector = c.title == "grand_moff"
            for _, v in ipairs(lords) do
                if v ~= c and lord_in(s, v, area, by_sector) then
                    v.agitated = v.agitated or {}
                    table.insert(v.agitated, {id = c.id, excess = excess,
                                              place = by_sector and sector_name(s, area) or over_name(s, area)})
                    rival_chance(v, c, X.HOARD_RIVAL * excess, Court.full_name(v) .. " turns on " .. Court.full_name(c)
                        .. ", who holds too much of the " .. (by_sector and sector_name(s, area) or over_name(s, area))
                        .. ".", s)
                end
            end
        end
        if c.title == "grand_moff" then
            local seen = {}
            for _, h in ipairs(Court.holdings(s, c)) do
                local _, over_key = Court.holding_place(s, h)
                local over = over_key and s.oversectors[over_key]
                local gm = over and Court.char(s, over.holder)
                if serving(gm) and gm ~= c and not seen[gm.id] then
                    seen[gm.id] = true
                    rival_chance(gm, c, X.TRESPASS_RIVAL, Court.full_name(gm) .. " will not forgive "
                        .. Court.full_name(c) .. " for holding lands in the " .. over_name(s, over_key) .. ".", s)
                end
            end
        end
    end
    denunciations(s)
end

function T.loyalty_parts(s, c)
    local X = CONFIG.TERRITORY
    local out = {}
    if c.covet and s.sectors[c.covet.key] then
        local weeks = s.week - (c.covet.since or s.week)
        local v = M.min(X.COVET_CAP, X.COVET_BASE + weeks * X.COVET_PER_WEEK)
        table.insert(out, {-v, "covets the seat of the " .. sector_name(s, c.covet.key)})
    end
    if c.agitated then
        local total, first = 0, nil
        for _, a in ipairs(c.agitated) do
            total = total + X.HOARD * a.excess
            first = first or a
        end
        local other = first and Court.char(s, first.id)
        local who = (table.getn(c.agitated) == 1 and other) and (other.name .. " holds too much of the " .. first.place)
            or "lords hoarding lands around them"
        table.insert(out, {-M.min(X.HOARD_CAP, total), who})
    end
    return out
end

return T
