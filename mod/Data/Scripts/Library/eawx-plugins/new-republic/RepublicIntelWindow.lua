local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local Intel = require("eawx-plugins/new-republic/RepublicIntel")
local Agents = require("eawx-plugins/new-republic/RepublicOperatives")

local IW = {view = "targets", sel = nil, flow = nil, assign = false, more = false}
local GREY = {0.5, 0.5, 0.53}
local PALE = {0.85, 0.82, 0.74}
local AGENT_ICON = "i_button_rep_op_1.tga"
local SPYNET_ICON = "i_button_bothan_spy.tga"
local FACTION = "REBEL"
local PROMPTS = {planet = "Choose a world", building = "Choose a building", hero = "Choose a hero",
                 faction = "Choose the other power", seat = "Choose a senator's world", bloc = "Choose a bloc",
                 party = "Choose a party",
                 agent = "Choose an agent", confirm = "Confirm the plan"}
local FACTION_PROMPT = {DISCREDIT = "Choose the power to turn against them"}

local function council(d)
    local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
    return ok and Republic and Republic.council(d) or false
end

local function service(d)
    return council(d) and "Alliance Intelligence" or "Republic Intelligence"
end

local function weeks_left(s, run)
    return Agents.weeks_text(M.max(0, run.done - s.week))
end

local function agent_icon(H, a)
    if a == "SPYNET" then
        return SPYNET_ICON
    end
    if a.kind == "lore" then
        return H.hero_icon(a) or AGENT_ICON
    end
    return "i_button_rep_op_" .. (a.rank or 1) .. ".tga"
end

local function agent_where(d, a)
    local here = Agents.location(d, a)
    return here and Intel.planet_label(d, here) or "In hyperspace"
end

local function rank_text(a)
    return Agents.rank_name(a) .. " (" .. Agents.numeral(a) .. ")"
end

local function op_name(a)
    if a == "SPYNET" then
        return "The Bothan SpyNet"
    end
    if a.kind == "lore" then
        return Agents.label(a) .. ", " .. Agents.rank_name(a)
    end
    return Agents.label(a)
end

local function traits_text(a)
    local names = Agents.trait_names(a)
    return names and (" Traits: " .. names .. ".") or " No traits yet."
end

local function next_xp(a)
    local need = R.AGENTS.XP[a.rank or 1]
    if not need then
        return 100
    end
    local prev = R.AGENTS.XP[(a.rank or 1) - 1] or 0
    return U.clamp(100 * ((a.xp or 0) - prev) / (need - prev), 0, 100)
end

function IW.reset()
    Intel.groups_cache = nil
    IW.view, IW.sel, IW.flow, IW.assign, IW.more = "targets", nil, nil, false, false
end

function IW.box(d, s)
    local n, cap = Agents.count(s), Agents.cap(d)
    local heroes = n - Agents.generic_count(s)
    local text = "NRI Agents " .. n .. "/" .. cap
    local tip = (IW.view == "agents") and "Back to the foreign powers." or
        ("Your agents: where they are, their rank and their missions. The NRI runs " .. cap .. " agents (more with "
            .. "the Intelligence office), heroes included" .. ((heroes > 0) and (" (" .. heroes .. " now)") or "") .. ".")
    return text, tip
end

function IW.box_click()
    IW.view = (IW.view == "agents") and "targets" or "agents"
    IW.sel, IW.flow, IW.assign, IW.more = nil, nil, false, false
end

local function target_rows(d, s, H)
    local rows = {}
    local running = s.ops.running
    if table.getn(running) > 0 then
        table.insert(rows, {head = true, a = "Operations under way (" .. table.getn(running) .. ")", b = " ", c = " ", key = "HEAD"})
        for k, run in ipairs(running) do
            local def = R.OPS[run.key]
            local a = (run.agent == "SPYNET") and "SPYNET" or Agents.get(s, run.agent)
            local what = run.seat and Intel.planet_label(d, run.seat) or (run.target and (run.target ~= FACTION)
                and H.label(run.target)) or "The Senate"
            table.insert(rows, {icon = a and agent_icon(H, a) or AGENT_ICON, a = def.short or def.name, b = what,
                                c = weeks_left(s, run),
                                value = U.clamp(100 * (s.week - run.started) / M.max(1, run.done - run.started), 0, 100),
                                pips = "blue", key = "R_" .. k, selected = IW.sel == "R_" .. k,
                                tip = def.name .. ": " .. what .. ", by " .. (a and op_name(a) or "?") .. " at "
                                    .. (run.at and Intel.planet_label(d, run.at) or "?") .. ". Click for details."})
        end
    end
    if not council(d) then
        table.insert(rows, {head = true, a = "The Republic", b = " ", c = " ", key = "HEAD"})
        table.insert(rows, {icon = H.faction_icon(FACTION), a = "Internal affairs", b = "The Senate", c = " ",
                            key = "T_" .. FACTION, selected = IW.sel == "T_" .. FACTION,
                            tip = "Operations on the Republic's own chamber: investigate a senator, watch the separatists, "
                                .. "leak a bloc's dealings. Exposed, they cost cohesion heavily."})
    end
    for _, group in ipairs(Intel.groups(d)) do
        table.insert(rows, {head = true, a = group[1] .. " (" .. table.getn(group[2]) .. ")", b = "Network", c = "Progress", key = "HEAD"})
        for _, t in ipairs(group[2]) do
            local n = Intel.network(d, t.faction)
            local full = n.tier >= Intel.max_tier(t.faction)
            local report = s.ops.reports and s.ops.reports[t.faction]
            table.insert(rows, {icon = H.faction_icon(t.faction), a = H.label(t.faction), indent = true,
                                b = "Tier " .. n.tier, c = (n.tier == 0) and "-" or (full and "Max" or (n.progress .. "%")),
                                value = (n.tier > 0) and (full and 100 or n.progress) or nil, pips = full and "gold" or "blue",
                                key = "T_" .. t.faction, selected = IW.sel == "T_" .. t.faction,
                                tip = H.label(t.faction) .. ": " .. t.worlds .. " world" .. ((t.worlds == 1) and "" or "s")
                                    .. "; spy network tier " .. n.tier .. " (" .. Intel.tier_name(n.tier) .. ")"
                                    .. ((n.tier > 0 and not full) and (", intel progress " .. n.progress .. "/" .. R.SPY.PROGRESS) or "")
                                    .. (report and (". Last report: week " .. report.week) or ". No report yet")
                                    .. ". Click to plan an operation."})
        end
    end
    return service(d), {"Target", "Network", "Progress", " "}, rows
end

local function agent_rows(d, s, H)
    local rows = {}
    for _, a in ipairs(Agents.list(s)) do
        local run = Intel.run_of(d, a.id)
        table.insert(rows, {icon = agent_icon(H, a), level = a.rank or 1, a = Agents.label(a), b = agent_where(d, a),
                            c = (a.kind == "lore") and "Hero" or Agents.rank_name(a),
                            value = next_xp(a), pips = "blue", key = "A_" .. a.id, selected = IW.sel == "A_" .. a.id,
                            tip = Agents.label(a) .. ", " .. rank_text(a) .. ", " .. (a.xp or 0) .. " experience, at "
                                .. agent_where(d, a) .. "." .. traits_text(a) .. " " .. (run and ("On a mission: "
                                .. R.OPS[run.key].name .. ", " .. weeks_left(s, run) .. ".") or "Free for a mission.")})
    end
    for _ = Agents.count(s) + 1, Agents.cap(d) do
        table.insert(rows, {icon = "dp_nr_pip_empty.tga", a = "Vacant", b = " ", c = " ", key = "A_NEW", dim = true,
                            tip = "A free place: recruit an agent, or assign a hero."})
    end
    return council(d) and "Alliance Agents" or "Republic Agents", {"Agent", "Location", "Rank", "Experience"}, rows
end

local function sympathy_group(d, owner)
    local kind = U.category(owner)
    if owner == string.upper(d.human.Get_Faction_Name()) then
        return "OWN", "Our worlds"
    elseif kind == "INDEPENDENT" then
        return "INDEPENDENT", "Independent worlds"
    elseif owner == "WARLORDS" then
        return "WARLORDS", "Petty warlords"
    end
    return owner, nil
end

local function sympathy_worlds(d, Sym)
    local now = GetCurrentTime()
    local cache = IW.sym_cache
    if cache and now - cache.time < 5 and now >= cache.time then
        return cache.worlds
    end
    local worlds = Sym.list(d)
    if Sym.own_counted(d) then
        local own = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local key = U.key(planet)
            local v = planet.Get_Owner() == d.human and Sym.value(d, key)
            if v then
                table.insert(own, {key = key, name = d:planet_name(planet), owner = string.upper(d.human.Get_Faction_Name()),
                                   value = v, visible = true, text = Sym.describe(d, key)})
            end
        end
        table.sort(own, function(a, b) return a.value > b.value end)
        for _, w in ipairs(worlds) do
            table.insert(own, w)
        end
        worlds = own
    end
    IW.sym_cache = {time = now, worlds = worlds}
    return worlds
end

local function sympathy_rows(d, s, H)
    local rows = {}
    local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
    local worlds = ok and Sym and sympathy_worlds(d, Sym) or {}
    local groups, order = {}, {}
    for _, w in ipairs(worlds) do
        local key, title = sympathy_group(d, w.owner)
        local g = groups[key]
        if not g then
            g = {key = key, title = title or H.label(w.owner), worlds = {}, total = 0}
            groups[key] = g
            table.insert(order, g)
        end
        table.insert(g.worlds, w)
        g.total = g.total + w.value
    end
    local LAST = {OWN = 0, INDEPENDENT = 2, WARLORDS = 3}
    table.sort(order, function(a, b)
        local ra, rb = LAST[a.key] or 1, LAST[b.key] or 1
        if ra ~= rb then
            return ra < rb
        end
        if table.getn(a.worlds) ~= table.getn(b.worlds) then
            return table.getn(a.worlds) > table.getn(b.worlds)
        end
        return a.title < b.title
    end)
    IW.open = IW.open or {}
    for _, g in ipairs(order) do
        local n = table.getn(g.worlds)
        local open = IW.open[g.key] == true
        table.insert(rows, {head = true, a = (open and "- " or "+ ") .. g.title .. " (" .. n .. ")", b = " ",
                            c = "Average " .. Sym.word(g.total / n), key = "G_" .. g.key,
                            tip = g.title .. ": " .. n .. " world" .. ((n == 1) and "" or "s") .. ". Click to "
                                .. (open and "close" or "open") .. " the list."})
        if open then
            for _, w in ipairs(g.worlds) do
                local marks = {}
                if d.republic.sym and d.republic.sym.cells[w.key] then
                    table.insert(marks, "resistance cell")
                end
                if w.visible and w.value >= R.SYMPATHY_LIBERATION and U.category(w.owner) ~= "INDEPENDENT"
                        and g.key ~= "OWN" then
                    table.insert(marks, "liberation target")
                end
                local trend = w.visible and M.round(Sym.trend(d, w.key) * 10) / 10 or 0
                local moving = (trend ~= 0) and (" " .. ((trend > 0) and "+" or "") .. trend .. "/wk") or ""
                table.insert(rows, {icon = H.globe(w.key), a = w.name, b = H.label(w.owner), c = w.text .. moving,
                                    indent = true, value = w.visible and w.value or nil, pips = Sym.band_color(w.value),
                                    key = "S_" .. w.key, selected = IW.sel == "S_" .. w.key,
                                    tip = w.name .. " (" .. H.label(w.owner) .. "): sympathy " .. w.text
                                        .. ((trend ~= 0) and (", " .. ((trend > 0) and "rising " or "falling ")
                                        .. M.abs(trend) .. " last week") or (w.visible and ", steady" or ""))
                                        .. ((table.getn(marks) > 0) and (", " .. table.concat(marks, ", ")) or "")
                                        .. (w.visible and "." or ". Known only roughly: a tier 2 network or a survey "
                                        .. "shows it exactly.")})
            end
        end
    end
    local whom = (ok and Sym and Sym.own_counted(d)) and "the Alliance" or "the Republic"
    return "Sympathy for " .. whom, {"World", "Held by", "Sympathy", "Sympathy"}, rows
end

function IW.rows(d, s, H)
    if IW.view == "agents" then
        return agent_rows(d, s, H)
    elseif IW.view == "sympathy" then
        return sympathy_rows(d, s, H)
    end
    return target_rows(d, s, H)
end

function IW.tools(d, s)
    if IW.view == "agents" then
        local why = Agents.recruit_blocked(d, s)
        local A = R.AGENTS
        local eligible = table.getn(Agents.eligible(d, s))
        return {
            {"Recruit agent", "iw_recruit", why or ("A new agent joins at the capital (" .. A.RECRUIT_CREDITS .. " credits). Once every "
                .. Agents.weeks_text(A.RECRUIT_WEEKS) .. "."), why ~= nil},
            {"Assign a hero", "iw_assign", (eligible == 0) and "No hero who can serve is in the field (Han Solo, Lando "
                .. "Calrissian, Luke Skywalker, Kyle Katarn, Mirax Terrik)." or ("Heroes who can serve (" .. eligible
                .. " in the field) join the agents."), eligible == 0},
            {"Foreign powers", "iw_targets", "Back to the foreign powers."},
        }
    end
    return {
        {service(d), "iw_home", "The latest reports, the Bothan SpyNet's debt."},
        {(IW.view == "sympathy") and "Foreign powers" or "Sympathy", (IW.view == "sympathy") and "iw_targets" or "iw_sympathy",
         (IW.view == "sympathy") and "Back to the foreign powers." or "How the galaxy's worlds feel about the Republic."},
    }
end

function IW.row_click(key)
    if type(key) ~= "string" or key == "A_NEW" then
        IW.sel = nil
        return
    end
    if string.sub(key, 1, 2) == "G_" then
        IW.open = IW.open or {}
        local g = string.sub(key, 3)
        IW.open[g] = not IW.open[g] or nil
        return
    end
    IW.flow, IW.assign, IW.more = nil, false, false
    IW.sel = (IW.sel ~= key) and key or nil
end

local function steps(key)
    local list = {}
    for _, kind in ipairs(R.OPS[key].pick or {}) do
        table.insert(list, kind)
    end
    table.insert(list, "agent")
    table.insert(list, "confirm")
    return list
end

function IW.start(d, key, target)
    local why = Intel.blocked(d, key, target)
    if why then
        return why
    end
    IW.flow, IW.assign = {key = key, target = target, step = 1, steps = steps(key)}, false
    IW.view = "targets"
    return nil
end

local function choice(d, text, tip, color, pick, off, pic, pic_tip, world)
    return {text = text, tip = off and (tip .. " " .. off) or tip, color = off and GREY or color, pick = pick, off = off,
            pic = pic, pic_tip = pic_tip or tip, world = world, label = world and Intel.planet_label(d, world) or nil}
end

local function agents_at(d, s, world)
    local n = 0
    for _, a in ipairs(Agents.list(s)) do
        if Agents.location(d, a) == world then
            n = n + 1
        end
    end
    return n
end

local function flow_choices(d, s, H, flow, kind)
    local out = {}
    local key = flow.key
    if kind == "planet" then
        local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
        for _, world in ipairs(Intel.worlds_of(flow.target)) do
            local where = Intel.planet_label(d, world)
            local n = agents_at(d, s, world)
            local v = ok and Sym and Sym.value(d, world)
            local capital = Intel.capital_name(flow.target) == world
            table.insert(out, choice(d, where .. (capital and " (capital)" or "") .. (v and (" - sympathy " .. M.round(v)) or "")
                .. ((n > 0) and (" - " .. n .. " agent" .. ((n > 1) and "s" or "")) or ""),
                where .. "." .. (capital and " Their capital: harder." or ""), H.owner_color(flow.target), world,
                Intel.pick_blocked(d, key, "planet", world, flow), H.faction_icon(flow.target), nil, world))
        end
    elseif kind == "building" then
        local seen = {}
        for _, b in ipairs(Intel.buildings(flow.target, flow.planet)) do
            seen[b.type] = (seen[b.type] or 0) + 1
            if seen[b.type] == 1 then
                table.insert(out, choice(d, b.name, b.name .. " on " .. Intel.planet_label(d, flow.planet) .. ".", PALE,
                    b.type, nil, H.faction_icon(flow.target)))
            end
        end
        for _, row in ipairs(out) do
            if seen[row.pick] > 1 then
                row.text = row.text .. " (" .. seen[row.pick] .. ")"
            end
        end
    elseif kind == "hero" then
        for _, h in ipairs(Intel.heroes(flow.target, d)) do
            local where = h.world and Intel.planet_label(d, h.world) or "in hyperspace"
            table.insert(out, choice(d, h.name .. " - " .. where, h.name .. ", now " .. (h.world and ("at " .. where) or where)
                .. ". Your agent must be where they are.", PALE, h.type, (not h.world) and "They are in hyperspace." or nil,
                H.faction_icon(flow.target)))
        end
    elseif kind == "faction" then
        for _, t in ipairs(Intel.targets(d)) do
            if t.faction ~= flow.target and not Intel.world_target(t.faction) then
                local opinion = Intel.opinion(t.faction, flow.target)
                table.insert(out, choice(d, H.label(t.faction) .. " (thinks " .. d.signed(opinion) .. " of them)",
                    H.label(t.faction) .. "'s opinion of " .. H.label(flow.target) .. ": " .. d.signed(opinion) .. ".",
                    H.owner_color(t.faction), t.faction, Intel.pick_blocked(d, key, "faction", t.faction, flow),
                    H.faction_icon(t.faction)))
            end
        end
    elseif kind == "seat" then
        local Republic = require("eawx-plugins/new-republic/Republic")
        local list = {}
        for name, seat in pairs((Republic.senate and Republic.senate.seats(d)) or {}) do
            table.insert(list, {name = name, seat = seat})
        end
        table.sort(list, function(a, b) return a.seat.opinion < b.seat.opinion end)
        for _, e in ipairs(list) do
            local label = Intel.planet_label(d, e.name)
            table.insert(out, choice(d, label .. " - " .. e.seat.bloc .. ", opinion " .. d.signed(e.seat.opinion),
                label .. "'s senator (" .. e.seat.bloc .. " bloc), opinion of the government " .. d.signed(e.seat.opinion) .. ".",
                PALE, e.name, Intel.pick_blocked(d, key, "seat", e.name, flow), H.globe(e.name), nil, e.name))
        end
    elseif kind == "bloc" then
        local Republic = require("eawx-plugins/new-republic/Republic")
        local blocs = {}
        for _, seat in pairs((Republic.senate and Republic.senate.seats(d)) or {}) do
            blocs[seat.bloc] = blocs[seat.bloc] or {n = 0, sum = 0}
            blocs[seat.bloc].n = blocs[seat.bloc].n + 1
            blocs[seat.bloc].sum = blocs[seat.bloc].sum + seat.opinion
        end
        local names = {}
        for name, _ in pairs(blocs) do
            table.insert(names, name)
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local b = blocs[name]
            local avg = M.round(b.sum / b.n)
            table.insert(out, choice(d, name .. " - " .. b.n .. " seats, opinion " .. d.signed(avg),
                "The " .. name .. " bloc: " .. b.n .. " seats, their opinion of the government " .. d.signed(avg) .. ".",
                PALE, name, Intel.pick_blocked(d, key, "bloc", name, flow), "dp_nr_vdot_1.tga"))
        end
    elseif kind == "party" then
        local Republic = require("eawx-plugins/new-republic/Republic")
        local Parties = Republic.part("parties")
        local view = Parties and flow.seat and Parties.view(d, flow.seat)
        for _, p in ipairs((view and view.parties) or {}) do
            table.insert(out, choice(d, p.name .. " - " .. p.short .. ", clout " .. p.clout .. "%" .. (p.ruling and " (in office)" or ""),
                p.name .. ": leans to the " .. p.bloc_name .. ", clout " .. p.clout .. "%, led by " .. p.leader .. ".",
                PALE, p.idx, Intel.pick_blocked(d, key, "party", p.idx, flow), p.dot))
        end
    elseif kind == "agent" then
        local probe = {key = flow.key, target = flow.target, planet = flow.planet, hero = flow.hero, seat = flow.seat,
                       agent = "SPYNET"}
        local off = Intel.agent_blocked(d, "SPYNET", probe)
        table.insert(out, choice(d, "The Bothan SpyNet - anywhere",
            "The Bothan SpyNet: no agent needs to be there, +" .. R.SPYNET.CHANCE .. "% to succeed, cheaper; the Bothan "
                .. "senators will collect the favour (" .. (s.debt or 0) .. " owed now). "
                .. (off and "" or (Intel.chance(d, flow.key, probe) .. "% to succeed, " .. Intel.cost(d, flow.key, probe)
                .. " credits.")), PALE, "SPYNET", off, SPYNET_ICON))
        for _, a in ipairs(Agents.list(s)) do
            probe.agent = a.id
            off = Intel.agent_blocked(d, a, probe)
            local row = choice(d, op_name(a) .. " - " .. agent_where(d, a),
                Agents.label(a) .. ", " .. rank_text(a) .. ", at " .. agent_where(d, a) .. "." .. traits_text(a) .. " "
                .. (off and "" or (Intel.chance(d, flow.key, probe) .. "% to succeed, " .. Intel.cost(d, flow.key, probe)
                .. " credits.")), PALE, a.id, off, agent_icon(H, a))
            row.level = a.rank or 1
            table.insert(out, row)
        end
    end
    return out
end

local function party_text(d, flow)
    local Parties = flow.party and require("eawx-plugins/new-republic/Republic").part("parties")
    local party = Parties and flow.seat and Parties.party(d, flow.seat, flow.party)
    return party and (", " .. Parties.the(party.name)) or ""
end

local function plan_lines(d, s, H, flow)
    local def = R.OPS[flow.key]
    local a = (flow.agent == "SPYNET") and "SPYNET" or Agents.get(s, flow.agent)
    local lines = {}
    local target = flow.seat and Intel.planet_label(d, flow.seat) or ((flow.target == FACTION) and "the Senate" or H.label(flow.target))
    table.insert(lines, {"Target: " .. target .. (flow.planet and (", " .. Intel.planet_label(d, flow.planet)) or "")
        .. (flow.building and (", " .. Intel.unit_name(flow.building)) or "") .. (flow.hero and (", " .. Intel.unit_name(flow.hero)) or "")
        .. (flow.faction and (" (" .. H.label(flow.faction) .. ")") or "") .. (flow.bloc and (", the " .. flow.bloc .. " bloc") or "")
        .. party_text(d, flow), nil})
    table.insert(lines, {"Agent: " .. (a and op_name(a) or "?"),
        (a and a ~= "SPYNET") and (Agents.label(a) .. ", " .. rank_text(a) .. "." .. traits_text(a)) or nil})
    if (def.caught or 0) == 0 then
        table.insert(lines, {"Success: " .. Intel.chance(d, flow.key, flow) .. "%   The agent cannot be caught.", nil})
    else
        local anger = M.round((def.attitude or 0) * (1 + R.COVERT.CAUGHT_TIER * (def.tier or 1)))
        table.insert(lines, {"Success: " .. Intel.chance(d, flow.key, flow) .. "%   Exposed: " .. Intel.caught_chance(d, flow.key, flow)
            .. "% (" .. ((a == "SPYNET") and "" or "the agent dies, ") .. (def.internal and "the chamber learns of it"
            or ("a scandal, the network loses a tier, their anger " .. anger)) .. ")", nil})
    end
    table.insert(lines, {"Cost: " .. Intel.cost(d, flow.key, flow) .. " credits, " .. Agents.weeks_text(def.weeks), nil})
    return lines
end

local function flow_detail(d, s, H)
    local flow = IW.flow
    local def = R.OPS[flow.key]
    local kind = flow.steps[flow.step]
    local target = (flow.target == FACTION) and (flow.seat and Intel.planet_label(d, flow.seat) or "the Senate")
        or H.label(flow.target)
    local prompt = (kind == "faction" and FACTION_PROMPT[flow.key]) or PROMPTS[kind] or " "
    local dd = H.empty_detail(def.name .. ": " .. target, prompt)
    dd.portrait = (flow.target == FACTION) and H.faction_icon(FACTION) or H.faction_icon(flow.target)
    dd.sub2 = "Step " .. flow.step .. " of " .. table.getn(flow.steps) .. "."
    dd.kind = def.desc
    dd.stats = {" ", " ", " ", " "}
    dd.head = (kind == "confirm") and "The plan" or prompt
    if kind == "confirm" then
        dd.lines = plan_lines(d, s, H, flow)
        dd.actions = {{"Confirm", "iw_confirm", "Launch the operation."}, {"Back", "iw_back", "The previous choice."},
                      {"Cancel", "iw_cancel", "Drop the plan."}}
    else
        dd.worlds = flow_choices(d, s, H, flow, kind)
        dd.rows_word = (kind == "planet") and "worlds" or "choices"
        if table.getn(dd.worlds) == 0 then
            dd.worlds = nil
            dd.lines = {{"Nothing to choose from.", nil}}
        end
        dd.actions = {{"Back", "iw_back", "The previous choice."}, {"Cancel", "iw_cancel", "Drop the plan."}}
    end
    return dd
end

function IW.choose(d, s, w)
    if IW.assign then
        local _, message = Agents.assign(d, s, w.pick)
        IW.assign = false
        return message
    end
    local flow = IW.flow
    if not flow then
        return nil
    end
    if w.off then
        return w.off
    end
    local kind = flow.steps[flow.step]
    if kind == "confirm" then
        return nil
    end
    flow[kind] = w.pick
    flow.step = flow.step + 1
    if kind == "planet" then
        flow.building = nil
    end
    return nil
end

local function home_detail(d, s, H)
    local dd = H.empty_detail(council(d) and "Alliance Intelligence" or "New Republic Intelligence", "Agents: " .. Agents.count(s) .. " of " .. Agents.cap(d)
        .. " places, " .. (Agents.count(s) - Agents.generic_count(s)) .. " of them heroes.")
    dd.portrait = H.faction_icon(FACTION)
    local blocked = Intel.spynet_blocked(d)
    dd.sub2 = blocked or ("The Bothan SpyNet works for us; the Bothans are owed " .. (s.debt or 0) .. " favour"
        .. (((s.debt or 0) == 1) and "" or "s") .. ".")
    dd.kind = "A Bothan Spy (built at the capital or Bothawui) sent to a power's capital opens a network there."
    dd.stats = {{s.ops.last or "No operation has reported yet.", s.ops.last}, " ", " ", " "}
    dd.head = "Latest reports"
    dd.lines = {}
    for k, line in ipairs(s.news or {}) do
        if k <= 6 then
            dd.lines[k] = {line, line}
        end
    end
    if table.getn(dd.lines) == 0 then
        dd.lines[1] = {"Select a power to plan an operation; the box at the top right lists your agents.", nil}
    end
    dd.actions = {}
    return dd
end

local function op_buttons(d, s, target, keys)
    local actions = {}
    for _, key in ipairs(keys) do
        local def = R.OPS[key]
        local why = Intel.blocked(d, key, target)
        table.insert(actions, {(def.short or def.name) .. " (" .. Intel.cost(d, key, {}) .. ")", "iw_op_" .. key,
            def.name .. ((def.tier and not def.internal) and (" (tier " .. Intel.needed_tier(d, key) .. ")") or "") .. ": " .. def.desc
                .. " Base " .. Intel.chance(d, key, {target = target}) .. "% to succeed, " .. (((def.caught or 0) == 0)
                and "never exposed. " or (Intel.caught_chance(d, key, {}) .. "% to be exposed. ")) .. Agents.weeks_text(def.weeks)
                .. "." .. (why and (" " .. why) or ""), why ~= nil, why})
    end
    return actions
end

local function internal_detail(d, s, H)
    local dd = H.empty_detail("Internal affairs", "Operations on the Republic's own chamber.")
    dd.portrait = H.faction_icon(FACTION)
    dd.sub2 = "On a member world's politics the agent works there; on the chamber, at the capital."
    dd.kind = "Exposed, they cost the Senate's cohesion " .. R.SCANDAL_COHESION .. "."
    dd.stats = {" ", " ", " ", " "}
    dd.head = "Under watch"
    dd.lines = {}
    for name, until_week in pairs(s.abstain or {}) do
        if until_week >= s.week and table.getn(dd.lines) < 6 then
            table.insert(dd.lines, {Intel.planet_label(d, name) .. "'s senator abstains (" .. Agents.weeks_text(until_week - s.week + 1) .. ")", nil})
        end
    end
    if s.leak and s.leak.ends > s.week then
        table.insert(dd.lines, {"The " .. s.leak.bloc .. " bloc stands alone (" .. Agents.weeks_text(s.leak.ends - s.week) .. ")", nil})
    end
    if Intel.watching(d) then
        table.insert(dd.lines, {"The separatists are watched: no secession clock runs.", nil})
    end
    for name, until_week in pairs(s.turned or {}) do
        if until_week >= s.week and table.getn(dd.lines) < 7 then
            table.insert(dd.lines, {Intel.planet_label(d, name) .. "'s senator votes with us (" .. Agents.weeks_text(until_week - s.week + 1) .. ")", nil})
        end
    end
    if table.getn(dd.lines) == 0 then
        dd.lines[1] = {"Nothing under way.", nil}
    end
    local first, second = {}, {}
    for k, key in ipairs(R.INTERNAL_ORDER) do
        table.insert((k <= 5) and first or second, key)
    end
    if (IW.more or 0) >= 1 then
        dd.actions = op_buttons(d, s, FACTION, second)
        table.insert(dd.actions, {"Back", "iw_less", "The cheaper operations."})
    else
        dd.actions = op_buttons(d, s, FACTION, first)
        table.insert(dd.actions, {"More...", "iw_more", "The dearest operations: turn a senator, force a reappointment, rig an election."})
    end
    return dd
end

local PAGE1 = {"GATHER", "SURVEY", "BROADCAST", "AID", "SABOTAGE"}
local PAGE2 = {"CELL", "EXPOSE", "DISCREDIT", "TURN", "DEFECTION"}
local PAGE3 = {"UPRISING"}

local function target_detail(d, s, H, target)
    local n = Intel.network(d, target)
    local dd = H.empty_detail(H.label(target), " ")
    dd.portrait = H.faction_icon(target)
    dd.portrait_tip = H.label(target) .. "."
    local worlds = table.getn(Intel.worlds_of(target))
    local capital = Intel.capital_name(target)
    if n.tier == 0 then
        dd.sub = "No spy network: tier 0."
        dd.sub2 = worlds .. " world" .. ((worlds == 1) and "" or "s") .. "."
        dd.kind = "A Bothan Spy (built at the capital or Bothawui) spying on their capital, or a ceasefire, opens one."
        dd.stats = {"Network: none", "Worlds: " .. worlds, " ", " "}
        dd.head = "Capital"
        if capital then
            local where = Intel.planet_label(d, capital)
            dd.worlds = {{world = capital, label = where, text = where .. " (capital)", color = H.owner_color(target),
                          tip = where .. ": the capital of " .. H.label(target) .. ". Send a Bothan Spy there.",
                          pic = H.faction_icon(target), pic_tip = H.label(target) .. "."}}
        else
            dd.lines = {{"Their capital is unknown.", nil}}
        end
        return dd
    end
    local report = s.ops.reports and s.ops.reports[target]
    dd.sub = report and ("Report, week " .. report.week .. ": " .. report.worlds .. " worlds, " .. report.credits .. " credits")
        or (worlds .. " worlds; no report yet: gather intelligence.")
    dd.sub2 = (report and table.getn(report.heroes) > 0) and ("Leaders: " .. table.concat(report.heroes, ", ")) or " "
    dd.kind = "Capital: " .. (capital and Intel.planet_label(d, capital) or "unknown") .. ". Treaty with the Republic: "
        .. string.lower(Intel.relation(d, target)) .. "."
    local full = n.tier >= Intel.max_tier(target)
    dd.stats = {{"Network: tier " .. n.tier .. " (" .. Intel.tier_name(n.tier) .. ")", "Each tier opens more operations; "
                 .. "gathering intelligence builds the network."},
                full and "Intel progress: complete" or ("Intel progress: " .. n.progress .. "/" .. R.SPY.PROGRESS), " ", " "}
    dd.head = (n.tier >= 2) and "Their views" or "Their views (tier 2)"
    dd.lines = {}
    if n.tier >= 2 and not Intel.world_target(target) then
        local views = {}
        for _, t in ipairs(Intel.targets(d)) do
            if t.faction ~= target and not Intel.world_target(t.faction) then
                table.insert(views, {faction = t.faction, value = Intel.opinion(target, t.faction)})
            end
        end
        table.insert(views, {faction = FACTION, value = Intel.opinion(target, FACTION)})
        table.sort(views, function(a, b)
            local wa = string.find(a.faction, "^WARLORD") ~= nil
            local wb = string.find(b.faction, "^WARLORD") ~= nil
            if wa ~= wb then
                return wb
            end
            return M.max(a.value, -a.value) > M.max(b.value, -b.value)
        end)
        dd.views = {}
        for _, v in ipairs(views) do
            local _, reasons = Intel.opinion(target, v.faction)
            local why = {}
            for _, r in ipairs(reasons) do
                table.insert(why, r[1] .. " " .. d.signed(r[2]))
            end
            table.insert(dd.views, {icon = H.faction_icon(v.faction), value = v.value,
                tip = H.label(target) .. " on " .. H.label(v.faction) .. ": " .. d.signed(v.value)
                    .. ((table.getn(why) > 0) and (" (" .. table.concat(why, ", ") .. ")") or "") .. "."})
        end
    else
        dd.lines[1] = {(n.tier >= 2) and "A single world: no views of the powers." or "Their views of the other powers need a tier 2 network.", nil}
    end
    local page = (IW.more == 2) and PAGE3 or ((IW.more == 1) and PAGE2 or PAGE1)
    dd.actions = op_buttons(d, s, target, page)
    table.insert(dd.actions, (IW.more == 2) and {"Back", "iw_less", "The first operations."}
        or {"More...", "iw_more", (IW.more == 1) and "Tier 5: uprisings." or "Tiers 3 and 4: cells, exposés, defections."})
    return dd
end

local function run_detail(d, s, H, run)
    local def = R.OPS[run.key]
    local a = (run.agent == "SPYNET") and "SPYNET" or Agents.get(s, run.agent)
    local dd = H.empty_detail(def.name, (run.seat and Intel.planet_label(d, run.seat)) or (run.target and run.target ~= FACTION
        and H.label(run.target)) or "The Senate")
    dd.portrait = a and agent_icon(H, a) or nil
    dd.sub2 = "Agent: " .. (a and op_name(a) or "?")
    dd.kind = def.desc
    dd.stats = {"At " .. (run.at and Intel.planet_label(d, run.at) or "?"), "Reports in " .. weeks_left(s, run),
                "Success: " .. Intel.chance(d, run.key, run) .. "%", "Exposed: " .. Intel.caught_chance(d, run.key, run) .. "%"}
    dd.head = "The operation"
    dd.lines = {{(a == "SPYNET") and "The SpyNet works on its own." or ("The agent must stay at "
        .. (run.at and Intel.planet_label(d, run.at) or "the target") .. " until it is done."), nil}}
    dd.actions = {{"Abort", "iw_recall", "Call it off (the money is lost)."}}
    return dd
end

local function agent_detail(d, s, H, a)
    local run = Intel.run_of(d, a.id)
    local dd = H.empty_detail(Agents.label(a), "Rank: " .. rank_text(a) .. ", " .. (a.xp or 0) .. " experience.")
    dd.portrait = agent_icon(H, a)
    dd.level = a.rank or 1
    dd.sub2 = "At " .. agent_where(d, a) .. "." .. (a.fast and (a.unit_fast and " Flies a fast courier."
        or " A fast courier waits for them (when no battle looms where they stand).") or "")
    dd.kind = (a.kind == "lore") and "A hero serving Republic Intelligence (besides the agents' cap)."
        or "An agent of New Republic Intelligence."
    dd.stats = {run and ("Mission: " .. R.OPS[run.key].name) or "No mission", run and weeks_left(s, run) or " ",
                "Rank bonus: +" .. R.COVERT.RANK * ((a.rank or 1) - 1) .. "% success", " "}
    dd.head = "Traits"
    dd.lines = {}
    for _, t in ipairs(a.traits or {}) do
        local def = R.AGENT_TRAITS[t]
        if def then
            table.insert(dd.lines, {def.name, def.name .. ": " .. def.desc, value = 1})
        end
    end
    if table.getn(dd.lines) == 0 then
        dd.lines[1] = {"None yet.", "Each rank gained brings a " .. R.AGENT_TRAIT_CHANCE .. "% chance of a trait."}
    end
    table.insert(dd.lines, {" ", nil})
    table.insert(dd.lines, {"Move the agent on the galaxy map to where an operation must take place, then plan it from a "
        .. "power's page.", nil})
    dd.actions = {{(a.kind == "lore") and "Release" or "Dismiss", "iw_fire", (a.kind == "lore") and "They return to other duties."
                    or "The agent retires (their unit leaves).", run ~= nil},
                  {"Show on map", "iw_map", "Close the window and look at their world.", Agents.location(d, a) == nil}}
    if run then
        table.insert(dd.actions, {"Abort", "iw_recall", "End their mission."})
    end
    return dd
end

local function world_detail(d, s, H, key)
    local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
    local planet = FindPlanet(key)
    local owner = planet and string.upper(planet.Get_Owner().Get_Faction_Name()) or "?"
    local dd = H.empty_detail(Intel.planet_label(d, key), "Held by " .. H.label(owner) .. ".")
    dd.portrait = H.globe(key)
    local v = ok and Sym and Sym.value(d, key)
    dd.sub2 = "Sympathy for the Republic: " .. (ok and Sym and Sym.describe(d, key) or "unknown") .. "."
    dd.kind = "40: cheaper offers; 60: liberation; 70: negotiated defection; 80 and a cell: an uprising."
    dd.stats = {" ", " ", " ", " "}
    dd.head = "What Intelligence knows"
    dd.lines = {}
    local sym_state = d.republic.sym or {}
    if sym_state.cells and sym_state.cells[key] then
        table.insert(dd.lines, {"A resistance cell is hidden here (sympathy +1 a week).", nil, value = 1})
    end
    if sym_state.broadcast and (sym_state.broadcast[key] or 0) > GetCurrentTime() then
        table.insert(dd.lines, {"The Republic broadcasts here (sympathy +2 a week).", nil, value = 1})
    end
    if v and v >= R.SYMPATHY_LIBERATION and U.category(owner) ~= "INDEPENDENT" then
        table.insert(dd.lines, {"A liberation target: taking it costs no mandate.", nil, value = 1})
    end
    if table.getn(dd.lines) == 0 then
        dd.lines[1] = {"Nothing more is known.", nil}
    end
    dd.actions = {{"Show on map", "iw_map_world", "Close the window and look at " .. Intel.planet_label(d, key) .. "."}}
    return dd
end

local function assign_detail(d, s, H)
    local dd = H.empty_detail("Assign a hero", "Heroes who can go unseen, or are spies, in the field.")
    dd.kind = "A hero takes an agent's place."
    dd.stats = {" ", " ", " ", " "}
    dd.head = "Choose a hero"
    dd.worlds = {}
    for _, e in ipairs(Agents.eligible(d, s)) do
        local ok, planet = pcall(function() return e.unit.Get_Planet_Location() end)
        local where = ok and planet and d:planet_name(planet) or "in hyperspace"
        table.insert(dd.worlds, choice(d, e.name .. " - " .. where, e.name .. ": click to make them an agent.", PALE, e.name,
            nil, H.hero_icon({lore = e.name}) or AGENT_ICON))
    end
    dd.rows_word = "heroes"
    if table.getn(dd.worlds) == 0 then
        dd.worlds = nil
        dd.lines = {{"No hero who can serve is in the field.", nil}}
    end
    dd.actions = {{"Cancel", "iw_cancel", "Back."}}
    return dd
end

function IW.detail(d, s, H)
    if IW.flow then
        return flow_detail(d, s, H)
    end
    if IW.assign then
        return assign_detail(d, s, H)
    end
    local sel = IW.sel or ""
    if string.find(sel, "^R_") then
        local run = s.ops.running[tonumber(string.sub(sel, 3))]
        if run then
            return run_detail(d, s, H, run)
        end
    elseif string.find(sel, "^A_") then
        local a = Agents.get(s, tonumber(string.sub(sel, 3)))
        if a then
            return agent_detail(d, s, H, a)
        end
    elseif string.find(sel, "^S_") then
        return world_detail(d, s, H, string.sub(sel, 3))
    elseif sel == "T_" .. FACTION then
        return internal_detail(d, s, H)
    elseif string.find(sel, "^T_") then
        return target_detail(d, s, H, string.sub(sel, 3))
    end
    return home_detail(d, s, H)
end

function IW.action(d, s, key, defer)
    local sel = IW.sel or ""
    if key == "iw_more" then
        IW.more = (IW.more == 1) and 2 or 1
    elseif key == "iw_less" then
        IW.more = false
    elseif string.find(key, "^iw_op_") then
        return IW.start(d, string.sub(key, 7), string.sub(sel, 3))
    elseif key == "iw_back" and IW.flow then
        local flow = IW.flow
        flow.step = flow.step - 1
        if flow.step < 1 then
            IW.flow = nil
        end
    elseif key == "iw_cancel" then
        IW.flow, IW.assign = nil, false
    elseif key == "iw_confirm" and IW.flow then
        local ok, message = Intel.launch(d, IW.flow)
        if ok then
            IW.flow = nil
        end
        return message
    elseif key == "iw_recall" then
        local run
        if string.find(sel, "^R_") then
            run = s.ops.running[tonumber(string.sub(sel, 3))]
        elseif string.find(sel, "^A_") then
            run = Intel.run_of(d, tonumber(string.sub(sel, 3)))
        end
        if run then
            local _, message = Intel.recall(d, run)
            IW.sel = nil
            return message
        end
    elseif key == "iw_fire" then
        local a = Agents.get(s, tonumber(string.sub(sel, 3)))
        if a then
            local run = a.mission and Intel.run_of(d, a.id)
            if run then
                Intel.recall(d, run)
            end
            IW.sel = nil
            defer(function() Agents.fire(d, s, a) end)
            return (a.kind == "lore") and (a.lore .. " returns to other duties.") or (Agents.label(a) .. " retires from service.")
        end
    elseif key == "iw_map" then
        local a = Agents.get(s, tonumber(string.sub(sel, 3)))
        return nil, a and Agents.location(d, a)
    elseif key == "iw_map_world" then
        return nil, string.sub(sel, 3)
    elseif key == "iw_recruit" then
        local _, message = Agents.recruit(d, s)
        return message
    elseif key == "iw_assign" then
        IW.assign, IW.flow = true, nil
    elseif key == "iw_targets" then
        IW.view, IW.sel = "targets", nil
    elseif key == "iw_sympathy" then
        IW.view, IW.sel, IW.flow = "sympathy", nil, nil
    elseif key == "iw_home" then
        IW.sel, IW.flow, IW.assign, IW.more = nil, nil, false, false
    end
    return nil
end

return IW
