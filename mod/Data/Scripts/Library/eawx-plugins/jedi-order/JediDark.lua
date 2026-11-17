local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")

local Dark = {}
local SH, OS = J.SHADOW, J.ORDER_SHADOW

function Dark.attach(Order)
    local function has_trait(p, key)
        return Order.has_trait(p, key)
    end

    function Order.susceptibility(p)
        local S = J.SUSCEPTIBLE
        local v = S.RANK[M.max(1, M.min(table.getn(S.RANK), p.rank or 1))] or 1
        for _, t in ipairs(p.traits or {}) do
            v = v + (S.TRAIT[t] or 0)
        end
        v = v - M.min(S.MISSION_EASE_MAX, (p.missions or 0) * S.MISSION_EASE)
        return U.clamp(v, S.MIN, S.MAX)
    end

    function Order.order_shadow(s)
        return U.clamp(M.round(Order.shadow_average(s) + (s.darkness or 0)), 0, 100)
    end

    function Order.shadow_level(s)
        local v = Order.order_shadow(s)
        for k, row in ipairs(J.SHADOW_WORDS) do
            if v < row[1] then
                return k
            end
        end
        return table.getn(J.SHADOW_WORDS)
    end

    function Order.shadow_known(s)
        return (s.known_until or -1) > s.week or Order.learned(s, "SEEKER", 3)
            or (Order.relic_flag and Order.relic_flag(s, "always_shadow"))
    end

    function Order.true_shadow_word(s)
        return J.SHADOW_WORDS[Order.shadow_level(s)][2]
    end

    function Order.shadow_word(s)
        if Order.shadow_known(s) then
            return Order.true_shadow_word(s)
        end
        return (Order.shadow_level(s) >= 3) and "Something Stirs" or "Quiet"
    end

    function Order.shadow_effect(s, key)
        local list = OS[key]
        return (list and list[Order.shadow_level(s)]) or 0
    end

    function Order.shadow_mult(s, key)
        local list = OS[key]
        return (list and list[Order.shadow_level(s)]) or 1
    end

    local function fall_chance(p)
        if p.shadow < SH.FALL then
            return 0
        end
        return (p.shadow - SH.FALL) * SH.FALL_RATE * Order.susceptibility(p)
    end

    local function maybe_fall(d, s, p, why)
        if d and U.chance(fall_chance(p)) then
            Order.say(d, s, why, Order.WARN, 30)
            Order.fall(d, s, p)
            return true
        end
        return false
    end

    function Order.mission_fall(d, s, p, m)
        local where = Order.world_name(d, m.world)
        if maybe_fall(d, s, p, "On " .. where .. ", failure broke " .. p.name .. ".") then
            return true
        end
        return false
    end

    function Order.after_loss(s, gone)
        local d = Order.last_d
        for _, other in ipairs(s.roster) do
            local close = other ~= gone and (other.id == gone.master or other.master == gone.id
                or (gone.master and other.master == gone.master))
            if close then
                if not maybe_fall(d, s, other, "Grief over " .. gone.name .. " has broken " .. other.name .. ".") then
                    if other.shadow >= SH.DARK_EVENT then
                        Order.push_crisis(s, "DARK", other.id, "CALLS")
                    end
                end
            end
        end
    end

    function Order.promoted(d, s, p, old_rank)
        p.rank_week = s.week
        for _, other in ipairs(s.roster) do
            local peer = other ~= p and other.rank == old_rank and ((p.master and other.master == p.master)
                or (other.id < p.id and (other.rank_week or 0) <= (p.rank_week or 0)))
            if peer then
                local proud = has_trait(other, "COMPETITIVE") or has_trait(other, "PROUD")
                Order.raise_shadow(other, SH.PASSED * (proud and 2 or 1))
                if has_trait(other, "COMPETITIVE") and other.shadow >= SH.DARK_EVENT - 10 then
                    Order.push_crisis(s, "DARK", other.id, "POWER")
                end
            end
        end
    end

    local function event_for(d, s, p)
        local open = {}
        local function threat_open(key)
            for _, t in ipairs(Order.threats(d, s)) do
                if t.key == key then
                    return true
                end
            end
            return false
        end
        if p.rank <= J.KNIGHT then
            table.insert(open, "RAGE")
        end
        if threat_open("LUMIYA") then
            table.insert(open, "WHISPER")
        end
        if threat_open("PROPHETS") then
            table.insert(open, "ENVOY")
        end
        if has_trait(p, "COMPETITIVE") or has_trait(p, "PROUD") then
            table.insert(open, "POWER")
        end
        if p.grief_week and s.week - p.grief_week <= 12 then
            table.insert(open, "CALLS")
        end
        if has_trait(p, "COMPETITIVE") or has_trait(p, "PROUD") then
            table.insert(open, "RIVAL")
        end
        if has_trait(p, "EMOTIONAL") or has_trait(p, "GRIEVING") then
            table.insert(open, "HATRED")
            table.insert(open, "VISION")
        end
        if p.missions and p.missions > 0 then
            table.insert(open, "AMULET")
        end
        if p.rank <= J.PADAWAN or has_trait(p, "RECKLESS") then
            table.insert(open, "VISION")
        end
        table.insert(open, "DOUBT")
        return U.pick(open)
    end

    local function senser(d, s, other_than)
        local all = Order.relic_flag and Order.relic_flag(s, "sense_all")
        local seated = {}
        for _, key in ipairs({"HEALING", "WATCH"}) do
            local q = Order.seated_in and Order.seated_in(s, key)
            if q then
                seated[q.id] = true
            end
        end
        for _, q in ipairs(s.roster) do
            if q ~= other_than and q.rank >= J.MASTER and (has_trait(q, "INTUITIVE") or q.rank >= J.GRAND_MASTER
                    or seated[q.id] or all) and Order.teaching(d, s, q) then
                return q
            end
        end
        return nil
    end
    Order.senser = senser

    local function at_home(p)
        return not (p.mission or p.along_of or p.command)
    end

    function Order.dark_week(d, s)
        Order.last_d, Order.last_s = d, s
        local fade = OS.DARKNESS_FADE + (Order.learned(s, "CONSULAR", 1) and 1 or 0)
        s.darkness = U.clamp((s.darkness or 0) - fade + OS.FALLEN_DARKNESS * table.getn(s.fallen or {}), 0, 100)
        local trust = Order.shadow_effect(s, "TRUST")
        if trust ~= 0 then
            Order.change_trust(s, trust)
        end
        for _, p in ipairs(s.roster) do
            if p.shadow < SH.SIGN then
                p.sensed = nil
            elseif not p.sensed and ((p.shadow >= SH.SENSE and at_home(p))
                    or (p.shadow >= J.WATCH_SENSE and Order.seated_in and Order.seated_in(s, "WATCH"))) then
                local q = senser(d, s, p) or (Order.seated_in and Order.seated_in(s, "WATCH"))
                if q then
                    p.sensed = true
                    Order.say(d, s, q.name .. " senses a darkness in " .. p.name .. ". It can be faced now: see their card.",
                        Order.WARN, 25)
                end
            end
            if (p.counsel_until or -1) == s.week then
                p.shadow = M.max(0, p.shadow - SH.COUNSEL - (p.counsel_extra or 0))
                Order.news(s, p.name .. "'s counsel is done; they are lighter for it.")
            end
            if (p.vigil_until or -1) == s.week then
                p.vigil_until = nil
            end
        end
        for _, p in ipairs(s.roster) do
            if U.chance(J.SMALL_CHANCE) then
                local dark = U.chance(50)
                local e = U.pick(dark and J.SMALL_DARK or J.SMALL_LIGHT)
                if dark then
                    Order.raise_shadow(p, e[2])
                else
                    p.shadow = M.max(0, p.shadow - e[2])
                end
                Order.news(s, (string.gsub(e[1], "{name}", p.name)))
            end
            if p.shadow >= SH.FALL and p.key ~= "LUKE"
                    and U.chance((p.shadow - SH.FALL) * J.TURN_RATE * Order.susceptibility(p)) then
                Order.push_crisis(s, "EDGE", p.id)
            end
        end
        local mult = Order.shadow_mult(s, "EVENTS") * (Order.relic_mult and Order.relic_mult(s, "devents") or 1)
        local waiting = 0
        for _, q in ipairs(s.crisis.queue) do
            waiting = waiting + ((q.key == "DARK") and 1 or 0)
        end
        for _, p in ipairs(s.roster) do
            if p.shadow >= SH.DARK_EVENT and waiting < 3 then
                local chance = (p.shadow - SH.DARK_EVENT + 1) * SH.DARK_EVENT_RATE * Order.susceptibility(p) * mult
                if U.chance(chance) then
                    local key = event_for(d, s, p)
                    if key then
                        Order.push_crisis(s, "DARK", p.id, key)
                        waiting = waiting + 1
                    end
                end
            end
        end
        local push = Order.shadow_effect(s, "EDGE_PUSH")
        if push > 0 and U.chance(push) then
            local darkest = nil
            for _, p in ipairs(s.roster) do
                if p.key ~= "LUKE" and (not darkest or p.shadow > darkest.shadow) then
                    darkest = p
                end
            end
            if darkest and darkest.shadow < SH.EDGE then
                darkest.shadow = SH.EDGE
            end
        end
        local spy = Order.by_key(s, "BRAKISS")
        if spy and not spy.joined_week then
            spy.joined_week = s.week
        end
        if spy and not s.brakiss_seen and s.week - (spy.joined_week or 0) >= 6 and senser(d, s, spy) then
            s.brakiss_seen = true
            Order.push_crisis(s, "DARK", spy.id, "BRAKISS")
        end
        if Order.shadow_level(s) >= 3 and not Order.shadow_known(s) and Order.add_lead then
            local open = false
            for _, l in ipairs(s.leads) do
                open = open or l.kind == "DISTURBANCE"
            end
            if not open and U.chance(30) then
                Order.add_lead(d, s, "DISTURBANCE", {world = Order.darkest_world(d, s)})
            end
        end
    end

    function Order.darkest_world(d, s)
        local best, value = nil, 0
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local k = U.key(planet)
            local v = Order.side_of(k)
            if v > value then
                best, value = k, v
            end
        end
        return best or Order.temple_key(d)
    end

    function Order.apply_dark_choice(d, s, p, choice)
        if choice.pshadow then
            if choice.pshadow < 0 then
                p.shadow = M.max(0, p.shadow + choice.pshadow)
            else
                Order.raise_shadow(p, choice.pshadow)
            end
        end
        if choice.pxp then
            p.xp = M.max(0, (p.xp or 0) + choice.pxp)
        end
        if choice.close then
            for _, other in ipairs(s.roster) do
                if other ~= p and (other.id == p.master or other.master == p.id) then
                    if choice.close < 0 then
                        other.shadow = M.max(0, other.shadow + choice.close)
                    else
                        Order.raise_shadow(other, choice.close)
                    end
                end
            end
        end
        if choice.darkness then
            s.darkness = U.clamp((s.darkness or 0) + choice.darkness, 0, 100)
        end
        if choice.watch and p.master then
            p.watch = p.master
        end
        if choice.expel then
            Order.say(d, s, p.name .. " leaves the Temple for the Empire. He will be back, in another robe.", Order.WARN, 30)
            Order.fall(d, s, p)
            return
        end
        if choice.redeem_spy then
            if U.chance(J.REDEEM_SPY) then
                p.shadow, p.spy = 10, nil
                Order.say(d, s, p.name .. " breaks with his masters in the Empire, and stays: a student, nothing more.", Order.GOLD)
            else
                Order.say(d, s, p.name .. " could not be reached.", Order.WARN)
                Order.fall(d, s, p)
            end
            return
        end
        if choice.fall then
            maybe_fall(d, s, p, p.name .. " gave in to the dark side.")
        end
    end

    function Order.counsellor(d, s, p)
        local master = p.master and Order.get(s, p.master)
        if master and not Order.busy(d, s, master) then
            return master
        end
        for _, q in ipairs(s.roster) do
            if q ~= p and q.rank >= J.MASTER and (has_trait(q, "INTUITIVE") or q.rank >= J.GRAND_MASTER)
                    and not Order.busy(d, s, q) then
                return q
            end
        end
        return nil
    end

    function Order.counsel(d, s, p)
        if Order.busy(d, s, p) then
            return Order.busy(d, s, p)
        end
        local q = Order.counsellor(d, s, p)
        if not q then
            return "No Master is free to counsel them."
        end
        p.counsel_until, q.counsel_until = s.week + SH.COUNSEL_WEEKS, s.week + SH.COUNSEL_WEEKS
        p.counsel_extra = (Order.seated_in and Order.seated_in(s, "HEALING")) and J.HEALING_COUNSEL or 0
        local text = q.name .. " takes " .. p.name .. " aside for " .. SH.COUNSEL_WEEKS .. " weeks of counsel."
        Order.news(s, text)
        return text
    end

    function Order.light_world(d)
        local best, value = nil, 0
        for _, w in ipairs(U.worlds_of(d.human)) do
            local v = -Order.side_of(w.key)
            if v > value then
                best, value = w.planet, v
            end
        end
        return best
    end

    function Order.retreat(d, s, p)
        if Order.busy(d, s, p) then
            return Order.busy(d, s, p)
        end
        local planet = Order.light_world(d)
        if planet and Order.send_away(d, s, p, "RETREAT", U.key(planet), SH.RETREAT_WEEKS, "Retreat") then
            p.retreat_until = nil
        else
            p.retreat_until = s.week + SH.RETREAT_WEEKS
        end
        local text = p.name .. " goes on retreat" .. (planet and (" to " .. d:planet_name(planet)) or "") .. " for "
            .. SH.RETREAT_WEEKS .. " weeks."
        Order.news(s, text)
        return text
    end

    function Order.vigil_blocked(s)
        local wait = (s.vigil_at or -100) + J.VIGIL_EVERY - s.week
        if wait > 0 then
            return "The Order kept a Vigil lately: again in " .. wait .. " weeks."
        end
        return nil
    end

    function Order.vigil(d, s)
        local why = Order.vigil_blocked(s)
        if why then
            return why
        end
        local n = 0
        for _, p in ipairs(s.roster) do
            if at_home(p) and not Order.busy(d, s, p) then
                p.vigil_until = s.week + J.VIGIL_WEEKS
                n = n + 1
            end
        end
        if n == 0 then
            return "No one is at the Temple to keep a Vigil."
        end
        s.vigil_at = s.week
        s.darkness = M.max(0, (s.darkness or 0) - J.VIGIL_DARKNESS)
        if Order.relic_flag and Order.relic_flag(s, "vigil_heals") then
            for _, p in ipairs(s.roster) do
                if at_home(p) then
                    p.wounded = nil
                end
            end
        end
        local text = "The Order keeps a Vigil: " .. n .. " Jedi meditate together for " .. J.VIGIL_WEEKS .. " weeks."
        Order.say(d, s, text, Order.GOLD)
        return text
    end

    local base_side = Order.side_of
    function Order.side_of(world)
        local s = Order.last_s
        local taken = s and s.cleansed and s.cleansed[world or ""] or 0
        return U.clamp(base_side(world) - taken, -100, 100)
    end

    function Order.cleanse(d, s, p, m)
        local where = Order.world_name(d, m.world)
        s.cleansed[m.world] = (s.cleansed[m.world] or 0) + J.CLEANSE_SIDE
        s.darkness = M.max(0, (s.darkness or 0) - J.CLEANSE_DARKNESS)
        local text = Order.label(p) .. " has sealed the darkness on " .. where .. "."
        if m.world == "YAVIN" and s.chain and s.chain ~= "done" and s.chain ~= "closed" then
            s.chain = "done"
            s.ended.EXAR_KUN = true
            text = text .. " Exar Kun's spirit is bound in his temple for good."
        end
        if m.lead and m.lead.reveal then
            s.known_until = s.week + OS.KNOWN_WEEKS
            local darkest = nil
            for _, q in ipairs(s.roster) do
                if not darkest or q.shadow > darkest.shadow then
                    darkest = q
                end
            end
            if darkest and darkest.shadow >= SH.SIGN then
                darkest.sensed = true
            end
            text = text .. " Now the Order sees its own Shadow: " .. Order.true_shadow_word(s) .. ", fed by the darkness in "
                .. "its Jedi (" .. M.round(Order.shadow_average(s)) .. ") and by what the Order has let pass ("
                .. M.round(s.darkness) .. ")" .. ((darkest and darkest.sensed) and (". The darkest of them is "
                .. darkest.name) or "") .. "."
        end
        return text
    end
end

return Dark
