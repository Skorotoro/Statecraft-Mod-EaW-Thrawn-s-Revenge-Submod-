local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")
local Fleet = require("eawx-plugins/imperial-court/CourtFleet")

local Actions = {}
local A = CONFIG.ACTIONS
local O = CONFIG.OPINION

local function settle_petitions(s, kind, title, key, c)
    local ok, Politics = pcall(require, "eawx-plugins/imperial-court/CourtPolitics")
    if ok and Politics and Politics.settle_by_appointment then
        pcall(Politics.settle_by_appointment, s, kind, title, key, c)
    end
end

local function spend(s, amount)
    amount = M.round(amount)
    if s.authority < amount then
        return false, "Needs " .. amount .. " authority (you have " .. M.floor(s.authority) .. ")."
    end
    s.authority = s.authority - amount
    return true
end

function Actions.cost(s, base)
    return M.round(base * (Court.regime(s).office_cost or 1))
end

local function serving(c)
    return c and c.status == "serving"
end

function Actions.protected(s, c, what)
    if not c then
        return nil
    end
    if c.leads then
        return c.name .. " rules the Empire: the throne cannot touch them."
    end
    if c.heir then
        local claim = CONFIG.REGIMES[c.heir] and CONFIG.REGIMES[c.heir].title or "the throne"
        local why = {dismiss = "dismissed", arrest = "arrested", fleet = "sent out with a fleet", title = "given a lesser title",
                     revoke = "stripped of their rank"}
        return c.name .. " cannot be " .. (why[what] or "touched") .. ": their claim (" .. claim .. ") gives them too "
            .. "much leverage at court."
    end
    if c.protected and c.protected == s.regime and (what == "dismiss" or what == "arrest" or what == "revoke") then
        local ruler = Court.regime(s).leader
        local why = {dismiss = "dismissed", arrest = "arrested", revoke = "stripped of their rank"}
        return c.name .. " cannot be " .. why[what] .. ": " .. ruler .. " placed them and protects them."
    end
    return nil
end

function Actions.dismissal(s, c, kind)
    local since = c.posted and c.posted[kind]
    if not since then
        return 1
    end
    local weeks = s.week - since
    if weeks <= 0 then
        return nil, c.name .. " was appointed only this week: the court would think the throne mad."
    end
    local D = CONFIG.DISMISS
    if weeks < D.PROBATION then
        return 1 + D.EARLY * (D.PROBATION - weeks) / D.PROBATION
    end
    return 1
end

local function posted(s, c, kind)
    c.posted = c.posted or {}
    c.posted[kind] = s.week
end
Actions.posted = posted

function Actions.passed_over(s, chosen, key)
    local W = CONFIG.WANTS
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and v ~= chosen and Court.wants_office(s, v) == key then
            local nature = 1
            for _, t in ipairs(v.traits) do
                nature = nature * (W.NATURE[t] or 1)
            end
            local other = Court.office_of(s, v) and W.OTHER_POST or 1
            Court.opinion(v, "passed over for " .. Court.office_def(s, key).name, M.round(W.PASSED * nature * other), W.WEEKS)
        end
    end
end

function Actions.title_options(s, c)
    local out = {}
    local has_over = c.title == "grand_moff" and s.oversectors[c.holds or ""] ~= nil
    for _, key in ipairs(Court.sorted_keys(s.oversectors)) do
        local over = s.oversectors[key]
        if over.holder ~= c.id and not has_over then
            local holder = Court.char(s, over.holder)
            table.insert(out, {title = "grand_moff", key = key, label = "Grand Moff of the " .. over.name,
                               holder = holder})
        end
    end
    for _, sector in ipairs(Court.sector_list(s)) do
        if not sector.crown and sector.holder ~= c.id and table.getn(sector.worlds) > 0 then
            table.insert(out, {title = "moff", key = sector.key, label = "Moff of the " .. sector.name,
                               holder = Court.char(s, sector.holder)})
        end
    end
    local worlds = {}
    for _, sector in ipairs(Court.sector_list(s)) do
        for _, name in ipairs(sector.worlds) do
            if name ~= sector.seat then
                table.insert(worlds, name)
            end
        end
    end
    for _, name in ipairs(Court.unsectored(s, s.held)) do
        table.insert(worlds, name)
    end
    local leaving = (c.title == "governor" and c.holds) and (" (leaving " .. Court.planet_label(c.holds) .. ")") or ""
    for _, name in ipairs(worlds) do
        if s.governor[name] ~= c.id then
            local word = Court.is_station(name) and CONFIG.COMMANDER.name or "Governor"
            table.insert(out, {title = "governor", key = name, label = word .. " of " .. Court.planet_label(name) .. leaving,
                               holder = Court.char(s, s.governor[name])})
        end
    end
    local vacant, held = {}, {}
    for _, o in ipairs(out) do
        table.insert(o.holder and held or vacant, o)
    end
    for _, o in ipairs(held) do
        table.insert(vacant, o)
    end
    return vacant
end

function Actions.title_words(s, title, key)
    if title == "grand_moff" and s.oversectors[key] then
        return "Grand Moff of the " .. s.oversectors[key].name
    elseif title == "moff" and s.sectors[key] then
        return "Moff of the " .. s.sectors[key].name
    end
    return ((Court.is_station(key) and CONFIG.COMMANDER.name) or "Governor") .. " of " .. Court.planet_label(key)
end

function Actions.title_cost(s, title, key)
    local holder
    if title == "grand_moff" then
        holder = s.oversectors[key] and s.oversectors[key].holder
    elseif title == "moff" then
        holder = s.sectors[key] and s.sectors[key].holder
    else
        holder = s.governor[key]
    end
    local c = Court.char(s, holder)
    return Actions.cost(s, (c and c.status == "serving") and A.APPOINT or CONFIG.VACANT.APPOINT)
end

function Actions.grant_title(s, c, title, key)
    if not serving(c) then
        return false, "They no longer serve."
    end
    local blocked = Actions.protected(s, c, "title")
    if blocked then
        return false, blocked
    end
    if title == "grand_moff" and c.title == "grand_moff" and s.oversectors[c.holds or ""] and c.holds ~= key then
        return false, c.name .. " already rules the " .. s.oversectors[c.holds].name .. ": one oversector each."
    end
    local holder
    if title == "grand_moff" then
        holder = Court.char(s, s.oversectors[key] and s.oversectors[key].holder)
    elseif title == "moff" then
        holder = Court.char(s, s.sectors[key] and s.sectors[key].holder)
    else
        holder = Court.char(s, s.governor[key])
    end
    local weight = 1
    if holder and holder ~= c then
        local why
        weight, why = Actions.dismissal(s, holder, "title")
        why = why or Actions.protected(s, holder, "revoke")
        if why then
            return false, why
        end
    end
    local ok, why = spend(s, Actions.title_cost(s, title, key))
    if not ok then
        return false, why
    end
    local old = Court.set_title(s, c, title, key)
    posted(s, c, "title")
    Court.opinion(c, "granted a title", O.GRANTED_TITLE, 10)
    if c.traitor then
        Actions.traitor_rewarded(s, c)
    end
    if old and old ~= c then
        Court.opinion(old, "replaced by " .. c.name, M.round(O.FIRED * weight), 10)
        for _, id in ipairs(s.order) do
            local v = s.chars[id]
            if serving(v) and Court.is_friend(v, old.id) then
                Court.opinion(v, "their friend " .. old.name .. " was replaced", O.FRIEND_PUNISHED, 12)
            end
        end
    end
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and Court.is_rival(v, c.id) then
            Court.opinion(v, "their rival " .. c.name .. " was rewarded", O.RIVAL_REWARDED, 12)
        end
    end
    if Court.regime(s).merit and c.skill < 40 then
        for _, id in ipairs(s.order) do
            local v = s.chars[id]
            if serving(v) and v ~= c and v.title ~= "courtier" then
                Court.opinion(v, "an unworthy appointment", -3, 8)
            end
        end
    end
    settle_petitions(s, "title", title, key, c)
    local what = Actions.title_words(s, title, key)
    Court.news(s, c.name .. " is made " .. what .. ".")
    return true, Court.full_name(c) .. " is now " .. what .. "."
end

function Actions.revoke_blocked(s, c)
    if c.traitor then
        return nil
    end
    if Court.regime(s).revoke == "reason" and c.loyalty >= 40 then
        return "The " .. Court.regime(s).title .. " protects its own: only a disloyal lord (below 40) can be stripped."
    end
    return nil
end

function Actions.revoke(s, c, title, key)
    if not serving(c) or c.title == "courtier" then
        return false, "They hold no title."
    end
    local why = Actions.revoke_blocked(s, c) or Actions.protected(s, c, "revoke")
    if why then
        return false, why
    end
    local weight
    weight, why = Actions.dismissal(s, c, "title")
    if not weight then
        return false, why
    end
    local costly = Court.regime(s).revoke == "cost"
    local ok
    ok, why = spend(s, A.REVOKE * (costly and 2 or 1))
    if not ok then
        return false, why
    end
    local holding
    if title then
        holding = "the title of " .. Actions.title_words(s, title, key)
        Court.vacate(s, c, title, key)
    else
        holding = "their rank of Grand Moff"
        Court.vacate(s, c)
    end
    Court.opinion(c, "stripped of their title", M.round(O.REVOKED * (costly and 1.5 or 1) * weight), 10)
    if c.traitor then
        Court.news(s, "The traitor " .. c.name .. " is stripped of " .. (holding or "their title") .. "; nobody objects.")
        return true, c.name .. " loses " .. (holding or "their title") .. ". A traitor: the court approves."
    end
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and Court.is_friend(v, c.id) then
            Court.opinion(v, "their friend " .. c.name .. " was stripped", O.FRIEND_PUNISHED, 16)
        end
    end
    Court.news(s, c.name .. " is stripped of " .. (holding or "their title") .. ".")
    return true, c.name .. " loses " .. (holding or "their title") .. "."
end

function Actions.appoint_office(s, c, key)
    if not serving(c) then
        return false, "They no longer serve."
    end
    if s.offices[key] == c.id then
        return false, "They already hold it."
    end
    local old = Court.char(s, s.offices[key])
    if old and old.status == "serving" then
        return false, old.name .. " holds it: dismiss them first."
    end
    local own = Court.office_of(s, c)
    local why = (own and Actions.protected(s, c, "dismiss")) or (old and Actions.protected(s, old, "dismiss"))
    if why then
        return false, why
    end
    if key == "FLEET" and Actions.fleet_cooldown(s, c) > 0 then
        return false, c.name .. " was dismissed from command lately: they can be appointed again in "
            .. M.weeks(Actions.fleet_cooldown(s, c)) .. "."
    end
    local weight = 1
    if old then
        weight, why = Actions.dismissal(s, old, "office")
        if not weight then
            return false, why
        end
    end
    local slot, price = nil, 0
    if key == "FLEET" then
        slot, price = Fleet.offer(s, c, "supreme")
        if slot and price > 0 and Court.player().Get_Credits() < price then
            return false, "Needs " .. price .. " credits for a new " .. Fleet.class(slot) .. "."
        end
    end
    local ok
    ok, why = spend(s, Actions.cost(s, A.APPOINT))
    if not ok then
        return false, why
    end
    for k, id in pairs(s.offices) do
        if id == c.id then
            s.offices[k] = nil
        end
    end
    s.offices[key] = c.id
    posted(s, c, "office")
    local ship = ""
    if key == "FLEET" then
        c.fleet_rank = nil
        if price > 0 then
            Court.player().Give_Money(-price)
        end
        ship = Fleet.reserve(s, c, slot, price)
        ship = ship and (" " .. ship) or ""
    end
    Court.opinion(c, "appointed " .. Court.office_def(s, key).name, O.GRANTED_OFFICE, 10)
    if c.traitor then
        Actions.traitor_rewarded(s, c)
    end
    if old and old ~= c then
        Court.opinion(old, "dismissed from office", M.round(O.FIRED * weight), 10)
    end
    Actions.passed_over(s, c, key)
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and Court.is_rival(v, c.id) then
            Court.opinion(v, "their rival " .. c.name .. " was rewarded", O.RIVAL_REWARDED, 12)
        end
    end
    settle_petitions(s, "office", nil, key, c)
    Court.news(s, c.name .. " becomes " .. Court.office_def(s, key).name .. ".")
    return true, c.name .. " is now " .. Court.office_def(s, key).name .. " (" .. Actions.cost(s, A.APPOINT) .. " authority)." .. ship
end

function Actions.dismiss_office(s, key)
    local c = Court.char(s, s.offices[key])
    if not c then
        return false, "The office is vacant."
    end
    local why = Actions.protected(s, c, "dismiss")
    if why then
        return false, why
    end
    local weight
    weight, why = Actions.dismissal(s, c, "office")
    if not weight then
        return false, why
    end
    local cost = Actions.cost(s, A.DISMISS)
    local ok
    ok, why = spend(s, cost)
    if not ok then
        return false, why
    end
    s.offices[key] = nil
    if key == "FLEET" then
        c.fleet_dismissed = s.week
    end
    Court.opinion(c, "dismissed from office", M.round(O.FIRED * weight), 10)
    return true, c.name .. " is dismissed" .. ((weight > 1) and " so soon after their appointment: they take it hard." or ".")
        .. " (" .. cost .. " authority)"
end

function Actions.dismissal_text(s, c, kind, base)
    local weight, why = Actions.dismissal(s, c, kind)
    if not weight then
        return why
    end
    return M.round(base * weight) .. " opinion" .. ((weight > 1) and (" (appointed " .. M.weeks(s.week - c.posted[kind])
        .. " ago: more than usual)") or "")
end

function Actions.honour_blocked(s, c)
    if c and c.honoured and s.week - c.honoured < CONFIG.HONOUR_WEEKS then
        return c.name .. " was honoured recently: again in " .. M.weeks(CONFIG.HONOUR_WEEKS - (s.week - c.honoured)) .. "."
    end
    return nil
end

function Actions.honour(s, c)
    if not serving(c) then
        return false, "They no longer serve."
    end
    local blocked = Actions.honour_blocked(s, c)
    if blocked then
        return false, blocked
    end
    local ok, why = spend(s, Actions.cost(s, A.HONOUR))
    if not ok then
        return false, why
    end
    c.honoured = s.week
    Court.opinion(c, "honoured by the throne", O.HONOURED, 10)
    return true, c.name .. " is honoured (+" .. O.HONOURED .. " opinion)."
end

function Actions.tribute(s, c)
    if not serving(c) or c.title == "courtier" then
        return false, "They have no lands to tax."
    end
    if c.tribute_week and s.week < c.tribute_week + 8 then
        return false, "They paid tribute lately (again in " .. M.weeks(c.tribute_week + 8 - s.week) .. ")."
    end
    local credits = M.round(Court.power(s, c) * A.TRIBUTE_PER_POWER)
    if s.awol[c.holds or ""] then
        return false, "They ignore the throne's demands."
    end
    Court.player().Give_Money(credits)
    c.tribute_week = s.week
    Court.opinion(c, "made to pay tribute", O.TRIBUTE, 10)
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and v ~= c and (v.title == "moff" or v.title == "grand_moff") then
            Court.opinion(v, "a fellow Moff squeezed for tribute", O.TRIBUTE_PEERS, 6)
        end
    end
    return true, c.name .. " pays " .. credits .. " credits. The other Moffs take note."
end

function Actions.minder(s, c)
    if not serving(c) then
        return false, "They no longer serve."
    end
    if c.minder then
        c.minder = nil
        return true, "The minder is recalled from " .. c.name .. "."
    end
    local ok, why = spend(s, A.MINDER)
    if not ok then
        return false, why
    end
    c.minder = true
    return true, "An Intelligence officer now watches " .. c.name .. "."
end

function Actions.bribe(s, c)
    if not serving(c) then
        return false, "They no longer serve."
    end
    if Court.player().Get_Credits() < A.BRIBE_CREDITS then
        return false, "Needs " .. A.BRIBE_CREDITS .. " credits."
    end
    Court.player().Give_Money(-A.BRIBE_CREDITS)
    local value = Court.has_trait(c, "corrupt") and 18 or 12
    Court.opinion(c, "a generous gift", value, 10)
    return true, c.name .. " accepts the gift (+" .. value .. " opinion)."
end

function Actions.arrest(s, c)
    if not serving(c) then
        return false, "They no longer serve."
    end
    local blocked = Actions.protected(s, c, "arrest")
    if blocked then
        return false, blocked
    end
    local ok, why = spend(s, A.ARREST)
    if not ok then
        return false, why
    end
    if c.loyalty < 30 and Court.power(s, c) >= 6 and M.chance(60) then
        Court.break_away(s, c, "resisted arrest")
        return true, c.name .. " resists arrest and breaks away!"
    end
    Court.remove(s, c, "exiled", "is arrested and sent into exile")
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and Court.is_friend(v, c.id) then
            Court.opinion(v, "their friend " .. c.name .. " was arrested", O.FRIEND_PUNISHED * 2, 20)
        elseif serving(v) and v.loyalty < 50 then
            Court.opinion(v, "fear of arrest", -3, 8)
        end
    end
    s.stability = M.max(0, s.stability - 2)
    return true, c.name .. " is in chains."
end

function Actions.traitor_rewarded(s, c)
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and v ~= c then
            Court.opinion(v, "a traitor rewarded: " .. c.name, CONFIG.TRAITOR.APPOINTED, 16)
        end
    end
    s.stability = M.max(0, s.stability - CONFIG.TRAITOR.STABILITY)
    Court.news(s, "The court seethes: the traitor " .. c.name .. " is rewarded.")
end

function Actions.raise_blocked(s)
    local R = CONFIG.RAISE
    local ready = (s.raise_week or -100) + R.COOLDOWN
    if s.week < ready then
        return "The court still resents the last upstart: again in " .. M.weeks(ready - s.week) .. "."
    end
    if s.authority < R.AUTHORITY then
        return "Needs " .. R.AUTHORITY .. " authority."
    end
    return nil
end

function Actions.raise_officer(s)
    local why = Actions.raise_blocked(s)
    if why then
        return false, why
    end
    s.authority = s.authority - CONFIG.RAISE.AUTHORITY
    s.raise_week = s.week
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) then
            Court.opinion(v, "a nobody raised to power", CONFIG.RAISE.OPINION, CONFIG.RAISE.WEEKS)
        end
    end
    local c = Court.new_char(s, nil, "courtier")
    c.temper = M.random(4, 12)
    Court.settle_loyalty(s, c)
    Court.news(s, c.name .. " is raised from the ranks. The court resents the upstart.")
    return true, c.name .. " joins the court, eager to serve. The lords resent it.", c
end

function Actions.fleet_eligible(c, rank)
    local def = CONFIG.ADMIRALTY[rank]
    if c.title == "governor" then
        return false
    end
    if not def.from or c.fleet_rank == def.from then
        return true
    end
    for _, title in ipairs(def.titles or {}) do
        if c.title == title then
            return true
        end
    end
    return false
end

function Actions.fleet_sources(rank)
    local def = CONFIG.ADMIRALTY[rank]
    local names = {CONFIG.ADMIRALTY[def.from].name .. "s"}
    for _, title in ipairs(def.titles or {}) do
        table.insert(names, CONFIG.TITLES[title].name .. "s")
    end
    local n = table.getn(names)
    if n == 1 then
        return names[1]
    end
    local last = names[n]
    table.remove(names, n)
    return table.concat(names, ", ") .. " or " .. last
end

function Actions.fleet_cooldown(s, c)
    if not c.fleet_dismissed then
        return 0
    end
    return M.max(0, CONFIG.FLEET_COOLDOWN - (s.week - c.fleet_dismissed))
end

local function rank_index(rank)
    for i, key in ipairs(CONFIG.ADMIRALTY_ORDER) do
        if key == rank then
            return i
        end
    end
    return 99
end

function Actions.fleet_blocked(s, c, rank)
    local def = CONFIG.ADMIRALTY[rank]
    if not serving(c) then
        return "They no longer serve."
    end
    local protected = Actions.protected(s, c, "fleet")
    if protected then
        return protected
    end
    if c.fleet_rank == rank then
        return "They already hold that rank."
    end
    if c.fleet_rank and rank_index(rank) > rank_index(c.fleet_rank) then
        local rank = CONFIG.ADMIRALTY[c.fleet_rank].name
        return (string.find(rank, "^[AEIOU]") and "An " or "A ") .. rank .. " cannot be appointed below their station: "
            .. "dismiss them from the Admiralty first."
    end
    local wait = Actions.fleet_cooldown(s, c)
    if wait > 0 then
        return c.name .. " was dismissed from command lately: they can be appointed again in " .. M.weeks(wait) .. "."
    end
    if c.title == "governor" then
        return "A Governor cannot leave their world for a fleet command."
    end
    if s.offices.FLEET == c.id then
        return "The Supreme Commander of the Fleet already commands every fleet."
    end
    if not Actions.fleet_eligible(c, rank) then
        return "Only " .. Actions.fleet_sources(rank) .. " can be made " .. def.name .. "."
    end
    if table.getn(Court.fleet_members(s, rank)) >= Court.fleet_seats(s, rank) then
        return "Every " .. def.name .. "'s command is taken: dismiss one first."
    end
    if s.authority < Actions.cost(s, def.cost) then
        return "Needs " .. Actions.cost(s, def.cost) .. " authority."
    end
    local slot, price = Fleet.offer(s, c, rank)
    if slot and price > 0 and Court.player().Get_Credits() < price then
        return "Needs " .. price .. " credits for a new " .. Fleet.class(slot) .. "."
    end
    return nil
end

function Actions.appoint_fleet(s, c, rank)
    local why = Actions.fleet_blocked(s, c, rank)
    if why then
        return false, why
    end
    local def = CONFIG.ADMIRALTY[rank]
    local slot, price = Fleet.offer(s, c, rank)
    spend(s, Actions.cost(s, def.cost))
    if price > 0 then
        Court.player().Give_Money(-price)
    end
    c.fleet_rank = rank
    posted(s, c, "fleet")
    Court.opinion(c, "given the rank of " .. def.name, def.opinion, 10)
    if rank == "grand_admiral" then
        Actions.passed_over_rank(s, c, rank)
    end
    if c.traitor then
        Actions.traitor_rewarded(s, c)
    end
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if serving(v) and Court.is_rival(v, c.id) then
            Court.opinion(v, "their rival " .. c.name .. " was rewarded", O.RIVAL_REWARDED, 12)
        end
    end
    local ship = Fleet.reserve(s, c, slot, price)
    ship = ship and (" " .. ship) or ((not Court.own_ship(c)) and " A flagship is readied for them." or "")
    Court.news(s, c.name .. " is made " .. def.name .. ".")
    return true, Court.full_name(c) .. " takes command." .. ship
end

function Actions.dismiss_fleet(s, c)
    if not serving(c) or not c.fleet_rank then
        return false, "They hold no command."
    end
    local weight, why = Actions.dismissal(s, c, "fleet")
    if not weight then
        return false, why
    end
    local name = CONFIG.ADMIRALTY[c.fleet_rank].name
    c.fleet_rank = nil
    c.fleet_dismissed = s.week
    Court.opinion(c, "relieved of command", M.round(O.FIRED * weight), 10)
    return true, c.name .. " is relieved of command as " .. name .. " (no new command for "
        .. M.weeks(CONFIG.FLEET_COOLDOWN) .. ")."
end

function Actions.passed_over_rank(s, chosen, rank)
    local W = CONFIG.WANTS
    for _, c in ipairs(Court.fleet_members(s, CONFIG.ADMIRALTY[rank].from or "")) do
        if c ~= chosen and Court.power(s, c) >= W.MIN_POWER then
            local nature = 1
            for _, t in ipairs(c.traits) do
                nature = nature * (W.NATURE[t] or 1)
            end
            Court.opinion(c, "passed over for " .. CONFIG.ADMIRALTY[rank].name, M.round(W.PASSED * 0.6 * nature), W.WEEKS)
        end
    end
end

function Actions.direct_group(s, name, held)
    held = held or Court.held()
    local group, seen, queue, head = {}, {[name] = true}, {name}, 1
    while queue[head] and head < 500 do
        local w = queue[head]
        table.insert(group, w)
        for _, other in ipairs(Court.lanes(w)) do
            if held[other] and not s.world[other] and not seen[other] then
                seen[other] = true
                table.insert(queue, other)
            end
        end
        head = head + 1
    end
    return group
end

function Actions.proclaim(s, name)
    local held = Court.held()
    if not held[name] or s.world[name] then
        return false, "Only worlds ruled directly can form a new sector."
    end
    local group = Actions.direct_group(s, name, held)
    local P = CONFIG.PROCLAIM
    if table.getn(group) < P.WORLDS then
        return false, "A sector needs " .. P.WORLDS .. " connected worlds ruled directly (here: " .. table.getn(group) .. ")."
    end
    if Court.player().Get_Credits() < P.CREDITS then
        return false, "Needs " .. P.CREDITS .. " credits."
    end
    local ok, why = spend(s, P.AUTHORITY)
    if not ok then
        return false, why
    end
    Court.player().Give_Money(-P.CREDITS)
    local used = {}
    for _, sector in pairs(s.sectors) do
        used[sector.name] = true
    end
    local sector_name
    for _, n in ipairs(CONFIG.PROCLAIM_NAMES) do
        if not used[n .. " Sector"] then
            sector_name = n .. " Sector"
            break
        end
    end
    s.proclaimed = (s.proclaimed or 0) + 1
    sector_name = sector_name or ("New Sector " .. s.proclaimed)
    local key = "P_" .. s.proclaimed
    s.sectors[key] = {key = key, name = sector_name, worlds = {}, seat = group[1], proclaimed = true}
    for _, w in ipairs(group) do
        s.world[w] = key
    end
    Court.index_worlds(s)
    local GEO = require("eawx-plugins/imperial-court/CourtGeo")
    local region = GEO[group[1]] and GEO[group[1]].region or "Outer Rim"
    s.sectors[key].region = region
    if s.oversectors[region] then
        s.sectors[key].oversector = region
    end
    Court.news(s, "The throne proclaims the " .. sector_name .. " (" .. table.getn(group) .. " worlds). It awaits a Moff.")
    return true, "The " .. sector_name .. " is proclaimed. Appoint its Moff.", key
end

return Actions
