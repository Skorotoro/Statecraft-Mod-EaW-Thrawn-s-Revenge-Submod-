local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")

local Council = {}

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

function Council.attach(Order)
    function Order.seated_in(s, key)
        local id = s.council and s.council.seats and s.council.seats[key]
        return id and Order.get(s, id) or nil
    end

    function Order.can_seat(s, seat, p)
        if seat.key == "GRAND" then
            return false, "The head of the Order takes this seat."
        end
        if s.council.seats[seat.key] then
            return false, "Council seats are held for life: this one empties only if its Master dies or falls."
        end
        if p and p.rank < J.MASTER then
            return false, "Only Masters sit on the Council."
        end
        if p and seat.path and p.path ~= seat.path then
            return false, "Only a Master of the " .. J.PATHS[seat.path] .. "s may hold this seat."
        end
        return true
    end

    function Order.unseat(s, seat)
        return "Council seats are held for life."
    end

    function Order.pick_successor(s)
        local best = nil
        for key, id in pairs(s.council.seats or {}) do
            local p = key ~= "GRAND" and Order.get(s, id)
            if p and p.rank == J.MASTER and (not best or p.missions > best.missions) then
                best = p
            end
        end
        if best then
            return best
        end
        for _, p in ipairs(s.roster) do
            if p.rank == J.MASTER and (not best or p.missions > best.missions or ((p.missions == best.missions) and p.id < best.id)) then
                best = p
            end
        end
        return best
    end

    local POST_SEAT = {ENVOY = "DIPLOMACY", HUNT = "GUARDIANS", WATCH = "WATCH"}
    local POST_NAME = {ENVOY = "envoy", HUNT = "hunter", WATCH = "Watchman"}

    function Order.posted(s, kind)
        local out = {}
        for _, p in ipairs(s.roster) do
            if p.post and p.post.kind == kind then
                table.insert(out, p)
            end
        end
        return out
    end

    function Order.post_blocked(d, s, kind)
        if not Order.seated_in(s, POST_SEAT[kind]) then
            local seat = ({ENVOY = "a Keeper of the Accord", HUNT = "a Master of Guardians", WATCH = "a Watchman of the Order"})[kind]
            return "Needs " .. seat .. " on the Council."
        end
        if kind == "ENVOY" then
            local Laws = Republic().part("laws")
            if not (Laws and Laws.jedi_envoy and Laws.jedi_envoy(d)) then
                return "Jedi envoys need the Jedi Sanction Act."
            end
        elseif kind == "HUNT" and not s.hunt then
            return "Declare a Hunt first."
        end
        if table.getn(Order.posted(s, kind)) >= J.POSTS[kind] then
            return "Every " .. POST_NAME[kind] .. " post is filled (" .. J.POSTS[kind] .. ")."
        end
        return nil
    end

    function Order.postable(d, s)
        local out = {}
        for _, p in ipairs(s.roster) do
            if p.rank == J.KNIGHT and not Order.busy(d, s, p) then
                table.insert(out, p)
            end
        end
        return out
    end

    function Order.post(d, s, p, kind, place)
        local why = Order.post_blocked(d, s, kind) or Order.busy(d, s, p)
        if why then
            return why
        end
        local world = (kind ~= "HUNT") and place or Order.hunt_world(d, s)
        if world then
            local ok, why2 = Order.send_away(d, s, p, "POST", world, nil,
                ({ENVOY = "Envoy post", HUNT = "The Hunt", WATCH = "Watch post"})[kind])
            if not ok then
                return why2
            end
        end
        p.post = {kind = kind, world = world, sector = (kind == "WATCH") and world and U.sector_of(world) or nil,
                  since = s.week, given = 0}
        local where = (kind == "WATCH") and ((p.post.sector or "?") .. ", at " .. Order.world_name(d, world))
            or (world and Order.world_name(d, world))
        local text = Order.label(p) .. " is posted as " .. ({ENVOY = "an envoy", HUNT = "a hunter", WATCH = "a Watchman"})[kind]
            .. ((kind == "HUNT") and (" to the Hunt" .. (world and (", bound for " .. where) or "") .. ".") or (" to " .. where .. "."))
        Order.news(s, text)
        return text
    end

    function Order.unpost(d, s, p)
        if not p.post then
            return nil
        end
        p.post, p.home_since = nil, s.week
        if p.mission and p.mission.key == "POST" then
            Order.recall(d, s, p)
        end
        local text = Order.label(p) .. " is recalled to the Temple."
        Order.news(s, text)
        return text
    end

    function Order.post_word(d, p)
        local post = p.post
        if not post then
            return nil
        end
        if post.kind == "ENVOY" then
            return "Envoy at " .. Order.world_name(d, post.world)
        elseif post.kind == "WATCH" then
            return "Watchman over the " .. (post.sector or "?")
        end
        return "On the Hunt"
    end

    function Order.set_regimen(d, s, key)
        if not Order.seated_in(s, "TRAINING") then
            return "Needs a Master of the Path on the Council."
        end
        s.regimen = key
        local text = "The Temple's Regimen: " .. J.REGIMENS[key].name .. "."
        Order.news(s, text)
        return text
    end

    function Order.regimen(s)
        return Order.seated_in(s, "TRAINING") and s.regimen and J.REGIMENS[s.regimen] or nil
    end

    function Order.hunt_world(d, s)
        local h = s.hunt
        if not h then
            return nil
        end
        if h.kind == "THREAT" then
            local t = Order.threat(h.target)
            return t and Order.threat_world(t)
        end
        for _, f in ipairs(s.fallen) do
            if f.id == h.target and f.type then
                local obj = Order.first_of(f.type)
                local ok, planet = pcall(function() return obj and obj.Get_Planet_Location() end)
                return ok and planet and U.key(planet) or nil
            end
        end
        return nil
    end

    function Order.hunt_targets(d, s)
        local out = {}
        for _, t in ipairs(Order.threats(d, s)) do
            table.insert(out, {kind = "THREAT", target = t.key, name = t.name})
        end
        for _, f in ipairs(s.fallen) do
            table.insert(out, {kind = "FALLEN", target = f.id, name = "Dark Jedi " .. f.name})
        end
        return out
    end

    function Order.declare_hunt(d, s, kind, target, name)
        if not Order.seated_in(s, "GUARDIANS") then
            return "Needs a Master of Guardians on the Council."
        end
        s.hunt = {kind = kind, target = target, name = name, since = s.week, bonus = 0}
        local text = "The Guardians declare a Hunt: " .. name .. "."
        Order.say(d, s, text, Order.GOLD)
        return text
    end

    function Order.end_hunt(d, s)
        for _, p in ipairs(Order.posted(s, "HUNT")) do
            Order.unpost(d, s, p)
        end
        s.hunt = nil
    end

    function Order.hunt_bonus(s, key, target)
        local h = s.hunt
        if not h then
            return 0
        end
        if (key == "CONFRONT" and h.kind == "THREAT" and h.target == target)
                or (key == "REDEEM" and h.kind == "FALLEN" and h.target == target) then
            return h.bonus or 0
        end
        return 0
    end

    function Order.vision_blocked(d, s, p)
        local gm = Order.head(s)
        if not gm or not Order.teaching(d, s, gm) then
            return "The Grand Master must be at the Temple."
        end
        local wait = (s.vision_at or -100) + J.VISION_GLOBAL - s.week
        if wait > 0 then
            return "The Grand Master can seek another vision in " .. wait .. ((wait == 1) and " week." or " weeks.")
        end
        wait = p and ((p.vision_at or -100) + J.VISION_EVERY - s.week) or 0
        return (wait > 0) and ("A vision of " .. p.name .. " can be sought again in " .. wait .. " weeks.") or nil
    end

    function Order.vision(d, s, p)
        local why = Order.vision_blocked(d, s, p)
        if why then
            return why
        end
        s.vision_at, p.vision_at = s.week, s.week
        p.sensed = (p.shadow >= 1) or nil
        local gm = Order.head(s)
        local roll = GameRandom.Free_Random(1, 3)
        local text = gm.name .. " seeks a vision of " .. p.name .. ": their darkness and their gift are laid bare ("
            .. M.round(p.shadow) .. " darkness, " .. J.POTENTIAL[M.max(1, M.min(3, p.potential))].name .. "). "
        if roll == 1 and Order.new_lead then
            local lead = Order.new_lead(d, s, nil, 8)
            text = text .. (lead and ("The Force shows more: " .. lead.title .. ".") or "The vision fades.")
        elseif roll == 2 then
            p.shadow = M.max(0, p.shadow - 15)
            text = text .. "A warning, heeded: their shadow lifts."
        else
            p.xp = (p.xp or 0) + 30
            text = text .. "A lesson: +30 Training XP."
        end
        Order.say(d, s, text, Order.GOLD, 25)
        return text
    end

    function Order.trance_blocked(d, s, p)
        local healer = Order.seated_in(s, "HEALING")
        if not healer or Order.busy(d, s, healer) then
            return "Needs a Master of the Living Force at the Temple."
        end
        if not ((p.wounded or 0) > s.week) then
            return p.name .. " is not wounded."
        end
        local wait = (s.trance_at or -100) + J.TRANCE_EVERY - s.week
        return (wait > 0) and ("Another Healing Trance can be held in " .. wait .. " weeks.") or nil
    end

    function Order.trance(d, s, p)
        local why = Order.trance_blocked(d, s, p)
        if why then
            return why
        end
        s.trance_at = s.week
        p.wounded = nil
        p.shadow = M.max(0, p.shadow - 10)
        local text = Order.seated_in(s, "HEALING").name .. " holds a Healing Trance over " .. p.name .. ": whole again, and lighter."
        Order.say(d, s, text, Order.GOLD)
        return text
    end

    function Order.council_week(d, s)
        local reg = Order.regimen(s)
        if reg then
            if reg.knowledge then
                s.knowledge = s.knowledge + reg.knowledge
            end
            for _, p in ipairs(s.roster) do
                local home = not (p.mission or p.along_of or p.command or p.post)
                if home and p.rank >= J.PADAWAN and p.rank <= J.KNIGHT then
                    if reg.shadow then
                        p.shadow = M.max(0, p.shadow + reg.shadow)
                    end
                end
            end
            if reg.wound and U.chance(reg.wound) then
                local students = {}
                for _, p in ipairs(s.roster) do
                    if p.rank >= J.PADAWAN and p.rank <= J.KNIGHT and not Order.busy(d, s, p) then
                        table.insert(students, p)
                    end
                end
                local p = U.pick(students)
                if p then
                    Order.wound(s, p, 2)
                    Order.news(s, p.name .. " was hurt in the sparring circle: two weeks to mend.")
                end
            end
        end
        local Laws = Republic().part("laws")
        local act = Laws and Laws.jedi_envoy and Laws.jedi_envoy(d)
        for _, p in ipairs(Order.posted(s, "ENVOY")) do
            local post = p.post
            local planet = FindPlanet(post.world or "")
            if not act or not Order.seated_in(s, "DIPLOMACY") or not planet then
                Order.unpost(d, s, p)
            else
                local capital = nil
                local ok, Deals = pcall(require, "eawx-plugins/diplomacy/DiplomacyDeals")
                capital = ok and Deals and Deals.capital(d, d.human)
                if capital and planet == capital then
                    if (s.week - post.since) - M.floor((s.week - post.since) / J.ENVOY_TRUST_EVERY) * J.ENVOY_TRUST_EVERY == 0 then
                        Order.change_trust(s, 1)
                    end
                elseif planet.Get_Owner() == d.human then
                    local Desires = Republic().part("desires")
                    if Desires and (post.given or 0) < J.ENVOY_WORLD_MAX then
                        Desires.boost(d, post.world, 1, 52, "a Jedi envoy")
                        post.given = (post.given or 0) + 1
                    end
                else
                    local Envoys = Republic().part("envoys")
                    if Envoys and Envoys.add_opinion and (s.week - post.since) - M.floor((s.week - post.since) / J.ENVOY_COURT_EVERY) * J.ENVOY_COURT_EVERY == 0 then
                        pcall(Envoys.add_opinion, d, planet.Get_Owner().Get_Faction_Name(), 1)
                    end
                end
            end
        end
        local h = s.hunt
        if h then
            local alive = false
            for _, t in ipairs(Order.hunt_targets(d, s)) do
                alive = alive or (t.kind == h.kind and t.target == h.target)
            end
            if not alive or not Order.seated_in(s, "GUARDIANS") then
                Order.end_hunt(d, s)
                Order.news(s, "The Hunt is over.")
            else
                if Order.posted(s, "HUNT")[1] then
                    h.bonus = M.min(J.HUNT_MAX, (h.bonus or 0) + J.HUNT_RATE)
                end
                if h.kind == "FALLEN" and Order.posted(s, "HUNT")[1] and U.chance(20) and Order.add_lead then
                    for _, f in ipairs(s.fallen) do
                        local obj = f.id == h.target and Order.first_of(f.type)
                        local planet = obj and Order.planet_of(obj)
                        if planet then
                            Order.add_lead(d, s, "FALLEN", {world = U.key(planet), target = f.id, jedi = f.name,
                                                            who = "The hunters"})
                        end
                    end
                end
            end
        end
        for _, p in ipairs(Order.posted(s, "WATCH")) do
            if not Order.seated_in(s, "WATCH") then
                Order.unpost(d, s, p)
            elseif Order.new_lead and U.chance(J.WATCH_LEAD_CHANCE) then
                Order.new_lead(d, s, nil, 6, p.post.sector)
            end
        end
        local watched = {}
        for _, p in ipairs(Order.posted(s, "WATCH")) do
            watched[p.post.sector or ""] = true
        end
        for _, l in ipairs(s.leads) do
            if l.world and watched[U.sector_of(l.world) or ""] and l.expires - s.week == J.WATCH_WARN then
                Order.say(d, s, "The Watchmen warn: " .. l.title .. " will go cold in " .. J.WATCH_WARN .. " weeks.", Order.WARN)
            end
        end
    end
end

return Council
