local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")
local R = require("eawx-plugins/jedi-order/JediRelics")

local Rel = {}
local BY_KEY = {}
for _, a in ipairs(R.ARTIFACTS) do
    BY_KEY[a.key] = a
end
for _, a in ipairs(R.GENERIC) do
    a.tier = 1
    a.generic = true
    BY_KEY[a.key] = a
end
for _, a in pairs(BY_KEY) do
    for _, e in ipairs(a.effects) do
        if e.lore_shadow_every then
            local chance, amount = R.LORE_DARK.CHANCE[a.tier], R.LORE_DARK.AMOUNT[a.tier]
            local every = (e.lore_shadow_every[2] == 1) and "each week" or ("every " .. e.lore_shadow_every[2] .. " weeks")
            e.text = string.gsub(e.text, "the Master of the Archives %+1 shadow[^,.;]*",
                "the Master of the Archives +" .. amount .. " shadow " .. every .. " (" .. chance .. "%% each time)")
        end
    end
end
Rel.R = R

function Rel.attach(Order)
    local function state(s)
        s.relics = s.relics or {list = {}, found = {}, next = 1}
        return s.relics
    end
    Order.relics_state = state
    Order.relics_tiers = R.TIERS
    function Order.relics_research_cost(tier)
        return R.RESEARCH[tier]
    end

    function Order.relic_def(item)
        return item and BY_KEY[item.key]
    end

    local function count(def)
        return table.getn((def and def.effects) or {})
    end

    local function lore_master(s)
        local id = s.council and s.council.seats and s.council.seats.LORE
        return id and Order.get(s, id) or nil
    end
    Order.lore_master = lore_master

    local function active(s, item, i, def)
        if item.sealed or item.stolen_by or (item.spent and item.spent[i]) then
            return false
        end
        local e = def.effects[i]
        if e.dark then
            return true
        end
        return item.step >= i and lore_master(s) ~= nil
    end
    Order.relic_active = active

    local function each(s, fn)
        for _, item in ipairs(state(s).list) do
            local def = BY_KEY[item.key]
            if def then
                for i, e in ipairs(def.effects) do
                    if active(s, item, i, def) then
                        fn(e, item, i)
                    end
                end
            end
        end
    end

    function Order.relic_sum(s, field)
        local v = 0
        each(s, function(e)
            if type(e[field]) == "number" then
                v = v + e[field]
            end
        end)
        return v
    end

    function Order.relic_mult(s, field)
        local v = 1
        each(s, function(e)
            if type(e[field]) == "number" then
                v = v * e[field]
            end
        end)
        return v
    end

    function Order.relic_flag(s, field, arg)
        local found = false
        each(s, function(e)
            if e[field] and (arg == nil or e[field] == arg) then
                found = true
            end
        end)
        return found
    end

    function Order.relic_odds(s, mission)
        local v = 0
        each(s, function(e)
            local o = e.odds
            if o then
                local list = (type(o[1]) == "table") and o or {o}
                for _, pair in ipairs(list) do
                    if pair[1] == mission or pair[1] == "ALL" then
                        v = v + pair[2]
                    end
                end
            end
        end)
        return v
    end

    local function add(s, key, world, finder)
        local st = state(s)
        local item = {id = st.next, key = key, world = world, step = 0, week = s.week, finder = finder and finder.id,
                      spent = {}}
        st.next = st.next + 1
        table.insert(st.list, item)
        if not BY_KEY[key].generic then
            st.found[key] = true
        end
        local def = BY_KEY[key]
        for _, e in ipairs(def.effects) do
            if e.dark and e.finder_shadow and finder then
                Order.raise_shadow(finder, e.finder_shadow)
            end
        end
        return item
    end

    local function left_at(s, world, dark_only)
        local out = {{}, {}, {}}
        for _, a in ipairs(R.ARTIFACTS) do
            if a.world == world and not state(s).found[a.key] and (not dark_only or a.dark) then
                table.insert(out[a.tier], a)
            end
        end
        return out
    end

    function Order.relic_find(d, s, p, world, how)
        if not world then
            return ""
        end
        local left = left_at(s, world, how ~= "LORE")
        local pick = nil
        if how == "CLEANSE" then
            pick = U.pick(left[3]) or U.pick(left[2])
            if not pick then
                s.knowledge = s.knowledge + R.CLEANSE_KNOWLEDGE
                return " The site held nothing more: Knowledge +" .. R.CLEANSE_KNOWLEDGE .. "."
            end
        elseif how == "CONFRONT" then
            if U.chance(R.CONFRONT_FIND) then
                pick = U.pick(left[2]) or U.pick(left[1])
            end
        else
            for tier = 3, 1, -1 do
                if not pick and left[tier][1] and U.chance(R.FIND[tier]) then
                    pick = U.pick(left[tier])
                end
            end
            if not pick and not (left[1][1] or left[2][1] or left[3][1])
                    and (Order.force_of(world) >= J.LORE_FORCE or Order.ruin(world)) and U.chance(R.GENERIC_FIND) then
                pick = U.pick(R.GENERIC)
            end
        end
        if not pick then
            return ""
        end
        add(s, pick.key, world, p)
        return " Among what they found: an artifact of the " .. string.lower(R.TIERS[pick.tier]) .. " kind, its story "
            .. "unknown. It goes to the Reliquary."
    end

    function Order.relic_known_name(item)
        local def = BY_KEY[item.key]
        return (item.step >= 1) and def.name or ("Unknown " .. string.lower(R.TIERS[def.tier]) .. " artifact")
    end

    function Order.relic_is_known_dark(item)
        local def = BY_KEY[item.key]
        return def.dark and item.step >= count(def)
    end

    function Order.relic_state_word(s, item)
        local def = BY_KEY[item.key]
        if item.stolen_by then
            return "Stolen"
        elseif item.sealed then
            return "Sealed"
        end
        local research = state(s).research
        if research and research.id == item.id then
            return "Research " .. M.max(0, research.ends - s.week) .. " wk"
        end
        local n = count(def)
        if item.step >= n then
            return Order.relic_is_known_dark(item) and "Known, dark" or "Known"
        end
        return (item.step == 0) and "Unresearched" or (item.step .. "/" .. n .. " known")
    end

    function Order.research_blocked(d, s, item)
        local def = BY_KEY[item.key]
        local cost = R.RESEARCH[def.tier]
        if not lore_master(s) then
            return "Only a Master of the Archives can research artifacts: seat one on the Council."
        elseif item.sealed or item.stolen_by then
            return "It is beyond reach."
        elseif item.step >= count(def) then
            return "Everything it holds is known."
        elseif state(s).research then
            return "The Master of the Archives is studying another artifact."
        elseif s.knowledge < cost[2] then
            return "Needs " .. cost[2] .. " Knowledge."
        end
        return nil
    end

    function Order.research(d, s, item)
        local why = Order.research_blocked(d, s, item)
        if why then
            return why
        end
        local cost = R.RESEARCH[BY_KEY[item.key].tier]
        s.knowledge = s.knowledge - cost[2]
        state(s).research = {id = item.id, ends = s.week + cost[1]}
        local text = lore_master(s).name .. " begins to study " .. Order.relic_known_name(item) .. " (" .. cost[1] .. " weeks)."
        Order.news(s, text)
        return text
    end

    function Order.relic_usable(s, item)
        local def = BY_KEY[item.key]
        for i, e in ipairs(def.effects) do
            if e.once and item.step >= i and not (item.spent and item.spent[i]) and not item.sealed and not item.stolen_by then
                return i
            end
        end
        return nil
    end

    local function use_once(d, s, o)
        local out = {}
        if o.knowledge then
            s.knowledge = s.knowledge + o.knowledge
            table.insert(out, "Knowledge +" .. o.knowledge)
        end
        if o.trust then
            Order.change_trust(s, o.trust)
            table.insert(out, "Public Trust +" .. o.trust)
        end
        if o.free_teaching then
            s.free_teaching = true
            table.insert(out, "the next Teaching costs nothing")
        end
        if o.padawans_xp then
            for _, p in ipairs(s.roster) do
                if p.rank == J.PADAWAN then
                    p.xp = (p.xp or 0) + o.padawans_xp
                end
            end
            table.insert(out, "every Padawan +" .. o.padawans_xp .. " XP")
        end
        if o.leads and Order.new_lead then
            local n = 0
            for _ = 1, o.leads do
                if Order.new_lead(d, s, nil, 8) then
                    n = n + 1
                end
            end
            table.insert(out, n .. ((n == 1) and " lead" or " leads"))
        end
        if o.free_cleanse then
            local world = Order.darkest_world and Order.darkest_world(d, s)
            if world then
                s.cleansed[world] = (s.cleansed[world] or 0) + J.CLEANSE_SIDE
                table.insert(out, "the darkness of " .. Order.world_name(d, world) .. " drained")
            end
        end
        if o.trial then
            local best = nil
            for _, p in ipairs(s.roster) do
                if p.rank == J.KNIGHT and (not best or (p.xp or 0) + 40 * p.missions > (best.xp or 0) + 40 * best.missions) then
                    best = p
                end
            end
            if best then
                best.rank, best.master, best.xp = J.MASTER, nil, 0
                table.insert(out, best.name .. " passes the Trial and is a Jedi Master")
            end
        end
        if o.sure_confront then
            s.sure_confront = true
            table.insert(out, "the next Confront the Darkness cannot fail")
        end
        if o.reveal then
            s.reveal_until = s.week + o.reveal
            for _, p in ipairs(s.roster) do
                p.sensed = p.shadow >= J.SHADOW.SIGN or nil
            end
            table.insert(out, "every Jedi's darkness is laid bare")
        end
        if o.initiates_ready then
            s.initiates_ready = true
            table.insert(out, "the Initiates are ready for a Master")
        end
        if o.heal_all then
            for _, p in ipairs(s.roster) do
                p.wounded = nil
            end
            table.insert(out, "every wounded Jedi healed")
        end
        if o.purge then
            for _, p in ipairs(s.roster) do
                p.shadow = M.max(0, p.shadow - o.purge)
            end
            table.insert(out, "every Jedi's shadow -" .. o.purge)
        end
        return table.concat(out, ", ")
    end

    function Order.use_relic(d, s, item)
        local i = Order.relic_usable(s, item)
        if not i then
            return "Nothing in it can be used now."
        end
        if not lore_master(s) and not BY_KEY[item.key].effects[i].dark then
            return "Only a Master of the Archives can call on it."
        end
        item.spent = item.spent or {}
        item.spent[i] = true
        local what = use_once(d, s, BY_KEY[item.key].effects[i].once)
        local text = BY_KEY[item.key].name .. " is called on: " .. what .. "."
        Order.say(d, s, text, Order.GOLD)
        return text
    end

    function Order.seal(d, s, item)
        if item.sealed then
            return "It is sealed already."
        elseif item.stolen_by then
            return "It is beyond reach."
        end
        item.sealed = true
        local research = state(s).research
        if research and research.id == item.id then
            state(s).research = nil
        end
        local def = BY_KEY[item.key]
        local text = Order.relic_known_name(item) .. " is sealed away, for good."
        local m = lore_master(s)
        if def.dark and m and U.chance(R.LORE_DARK.SEAL_CHANCE[def.tier]) then
            Order.raise_shadow(m, R.LORE_DARK.SEAL_AMOUNT[def.tier])
            text = text .. " Sealing it cost " .. m.name .. " something."
        end
        Order.news(s, text)
        return text
    end

    local function strength(item)
        local def = BY_KEY[item.key]
        return def.tier * 10 + item.step
    end

    function Order.relic_theft(d, s, p, was_lore)
        local pool = {}
        for _, item in ipairs(state(s).list) do
            if not item.sealed and not item.stolen_by then
                table.insert(pool, item)
            end
        end
        if not pool[1] then
            return
        end
        local taken = {}
        if was_lore then
            table.sort(pool, function(a, b) return strength(a) > strength(b) end)
            for i = 1, M.min(3, table.getn(pool)) do
                table.insert(taken, pool[i])
            end
        else
            local chance = R.STEAL_BASE
            for _, t in ipairs(p.traits or {}) do
                chance = chance + (R.STEAL_TRAITS[t] and R.STEAL_TRAIT or 0)
            end
            local m = lore_master(s)
            if m and m ~= p and Order.has_trait(m, "INTUITIVE") then
                chance = chance - R.STEAL_INTUITIVE
            end
            if U.chance(chance) then
                table.insert(taken, U.pick(pool))
            end
        end
        local names = {}
        for _, item in ipairs(taken) do
            item.stolen_by = p.id
            table.insert(names, Order.relic_known_name(item))
        end
        if names[1] then
            Order.say(d, s, p.name .. " took from the Reliquary: " .. table.concat(names, ", ") .. ".", Order.WARN, 25)
        end
    end

    function Order.relic_recover(d, s, fallen_id, how)
        local names = {}
        for _, item in ipairs(state(s).list) do
            if item.stolen_by == fallen_id then
                item.stolen_by = nil
                table.insert(names, Order.relic_known_name(item))
            end
        end
        if names[1] then
            Order.say(d, s, how .. " The Reliquary has back: " .. table.concat(names, ", ") .. ".", Order.GOLD)
        end
    end

    local function every(e_pair, s)
        return e_pair and (s.week - M.floor(s.week / e_pair[2]) * e_pair[2] == 0)
    end

    function Order.relic_week(d, s)
        local st = state(s)
        local m = lore_master(s)
        local r = st.research
        if r and s.week >= r.ends then
            st.research = nil
            for _, item in ipairs(st.list) do
                if item.id == r.id and m and not item.sealed and not item.stolen_by then
                    local def = BY_KEY[item.key]
                    item.step = item.step + 1
                    local e = def.effects[item.step]
                    local text = m.name .. " has learned more of " .. def.name .. ": "
                        .. ((item.step == 1) and "its story, and " or "") .. e.text
                    if e.dark then
                        text = text .. " It is a dark artifact."
                    end
                    Order.say(d, s, text, e.dark and Order.WARN or Order.GOLD, 25)
                end
            end
        end
        if m then
            for _, item in ipairs(st.list) do
                local def = BY_KEY[item.key]
                if item.step >= count(def) and not item.sealed and not item.stolen_by then
                    s.knowledge = s.knowledge + R.LORE_KNOWLEDGE[def.tier]
                end
            end
        end
        local half = Order.relic_flag(s, "ysalamir")
        local kweek = 0
        each(s, function(e, item)
            if e.kweek then
                kweek = kweek + e.kweek
            end
            if every(e.trust_every, s) then
                Order.change_trust(s, e.trust_every[1])
            end
            if every(e.darkness_every, s) then
                s.darkness = M.min(100, (s.darkness or 0) + e.darkness_every[1])
            end
            local tier = BY_KEY[item.key].tier
            if every(e.lore_shadow_every, s) and m and U.chance(R.LORE_DARK.CHANCE[tier]) then
                local amount = R.LORE_DARK.AMOUNT[tier]
                Order.raise_shadow(m, half and M.ceil(amount / 2) or amount)
            end
            if every(e.students_shadow_every, s) then
                for _, p in ipairs(s.roster) do
                    if p.rank <= J.KNIGHT and not (p.mission or p.along_of) then
                        Order.raise_shadow(p, e.students_shadow_every[1])
                    end
                end
            end
        end)
        s.knowledge_part = (s.knowledge_part or 0) + kweek
        for i = table.getn(s.fallen), 1, -1 do
            local f = s.fallen[i]
            if f.type and not Order.first_of(f.type) and s.week - (f.week or 0) > 2 then
                table.remove(s.fallen, i)
                Order.say(d, s, "The Dark Jedi " .. f.name .. " is no more.", Order.GOLD)
                Order.relic_recover(d, s, f.id, "With " .. f.name .. " defeated,")
            end
        end
    end
end

return Rel
