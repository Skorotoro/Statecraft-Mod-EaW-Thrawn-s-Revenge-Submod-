local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")
local Intel = require("eawx-plugins/imperial-court/CourtIntel")
local Agents = require("eawx-plugins/imperial-court/CourtOperatives")

local IW = {view = "targets", sel = nil, flow = nil, assign = false, more = false}
local GREY = {0.5, 0.5, 0.53}
local PALE = {0.85, 0.82, 0.74}
local AGENT_ICON = "i_button_isb_infiltrator.tga"
local PROMPTS = {planet = "Choose a world", building = "Choose a building", hero = "Choose a hero",
                 faction = "Choose the power to blame", char = "Choose a member of the court", agent = "Choose an operative",
                 confirm = "Confirm the plan"}
local FACTION_PROMPT = {INCITE_WAR = "Choose the power to turn on them", STAGE_ATTACK = "Choose the power to blame"}

local function weeks_left(s, run)
    if run.open then
        return "Open"
    end
    return M.weeks(M.max(0, run.done - s.week))
end

local function agent_icon(s, a)
    if a.kind == "lore" then
        return Court.portrait(Court.char(s, a.char))
    end
    return AGENT_ICON
end

local function agent_where(s, a)
    local here = Agents.location(s, a)
    return here and Court.planet_label(here) or "In hyperspace"
end

local function rank_text(a)
    return Agents.rank_name(a) .. " (" .. Agents.numeral(a) .. ")"
end

local function op_name(s, a)
    if a.kind == "lore" then
        return Agents.label(s, a) .. ", " .. Agents.rank_name(a)
    end
    return Agents.label(s, a)
end

local function traits_text(a)
    local names = Agents.trait_names(a)
    return names and (" Traits: " .. names .. ".") or " No traits yet."
end

local function next_xp(a)
    local need = CONFIG.AGENTS.XP[a.rank or 1]
    if not need then
        return 100
    end
    local prev = CONFIG.AGENTS.XP[(a.rank or 1) - 1] or 0
    return M.clamp(100 * ((a.xp or 0) - prev) / (need - prev), 0, 100)
end

function IW.reset()
    IW.view, IW.sel, IW.flow, IW.assign, IW.more = "targets", nil, nil, false, false
end

function IW.box(s)
    local n, cap = table.getn(Agents.list(s)), Agents.cap(s)
    local text = "Imperial Operatives " .. n .. "/" .. cap
    local tip = (IW.view == "agents") and "Back to the foreign powers." or
        ("Your operatives: where they are, their rank and their missions. The Director's skill allows " .. cap .. ".")
    return text, tip
end

function IW.box_click(s)
    IW.view = (IW.view == "agents") and "targets" or "agents"
    IW.sel, IW.flow, IW.assign, IW.more = nil, nil, false, false
end

local function target_rows(s, H)
    local rows = {}
    local running = Intel and s.ops.running or {}
    if table.getn(running) > 0 then
        table.insert(rows, {head = true, a = "Operations under way (" .. table.getn(running) .. ")", b = " ", c = " ", key = "HEAD"})
        for _, run in ipairs(running) do
            local def = CONFIG.OPS[run.key]
            local a = Agents.get(s, run.agent)
            local c = run.char and Court.char(s, run.char)
            local what = c and c.name or (run.target and H.label(run.target)) or "The court"
            table.insert(rows, {icon = a and agent_icon(s, a) or AGENT_ICON, a = def.short or def.name, b = what,
                                c = weeks_left(s, run),
                                value = run.open and 100 or M.clamp(100 * (s.week - run.started + Court.week_fraction(s))
                                    / M.max(1, run.done - run.started), 0, 100),
                                pips = "blue", key = "R_" .. run.agent, selected = IW.sel == "R_" .. run.agent,
                                tip = def.name .. ": " .. what .. ", by " .. (a and Agents.label(s, a) or "?") .. " at "
                                    .. (run.at and Court.planet_label(run.at) or "?") .. ". Click for details."})
        end
    end
    table.insert(rows, {head = true, a = "The Imperial Court", b = " ", c = " ", key = "HEAD"})
    local director = Intel.director(s)
    table.insert(rows, {icon = H.faction_icon(CONFIG.FACTION), a = "Internal affairs", b = "Tier " .. CONFIG.SPY.MAX,
                        c = director and ("Loyalty " .. M.round(director.loyalty)) or "No Director",
                        value = 100, pips = "gold", key = "T_" .. CONFIG.FACTION, selected = IW.sel == "T_" .. CONFIG.FACTION,
                        tip = "Operations against members of the court: minders, treason, arrest, assassination. Only "
                            .. "while the Director is loyal (" .. CONFIG.COVERT.DIRECTOR_LOYALTY .. "+)."})
    for _, group in ipairs(Intel.groups(s)) do
        table.insert(rows, {head = true, a = group[1] .. " (" .. table.getn(group[2]) .. ")", b = "Network", c = "Progress", key = "HEAD"})
        for _, t in ipairs(group[2]) do
            local n = Intel.network(s, t.faction)
            local full = n.tier >= CONFIG.SPY.MAX
            local report = s.ops.reports and s.ops.reports[t.faction]
            local att = s.attitude[t.faction] or 0
            table.insert(rows, {icon = H.faction_icon(t.faction), a = H.label(t.faction), indent = true,
                                b = "Tier " .. n.tier, c = (n.tier == 0) and "-" or (full and "Max" or (n.progress .. "%")),
                                value = (n.tier > 0) and (full and 100 or n.progress) or nil, pips = full and "gold" or "blue",
                                key = "T_" .. t.faction, selected = IW.sel == "T_" .. t.faction,
                                tip = H.label(t.faction) .. ": " .. t.worlds .. " worlds; spy network tier " .. n.tier .. " ("
                                    .. Intel.tier_name(n.tier) .. ")" .. ((n.tier > 0 and not full) and (", intel progress "
                                    .. n.progress .. "/" .. CONFIG.SPY.PROGRESS) or "") .. ((att ~= 0) and (", attitude "
                                    .. M.signed(att) .. " from our dealings") or "") .. (report and (". Last report: week "
                                    .. report.week) or ". No report yet") .. ". Click to plan an operation."})
        end
    end
    return "Imperial Intelligence", {"Target", "Network", "Progress", "Progress"}, rows
end

local function agent_rows(s, H)
    local rows = {}
    local list = Agents.list(s)
    for _, a in ipairs(list) do
        local run = Intel.run_of(s, a.id)
        table.insert(rows, {icon = agent_icon(s, a), level = a.rank or 1, a = Agents.label(s, a), b = agent_where(s, a),
                            c = Agents.rank_name(a),
                            value = next_xp(a), pips = "blue", key = "A_" .. a.id, selected = IW.sel == "A_" .. a.id,
                            tip = Agents.label(s, a) .. ", " .. rank_text(a) .. ", " .. (a.xp or 0) .. " experience, at "
                                .. agent_where(s, a) .. "." .. traits_text(a) .. " " .. (run and ("On a mission: "
                                .. CONFIG.OPS[run.key].name .. ", " .. weeks_left(s, run) .. ".") or "Free for a mission.")})
    end
    for _ = table.getn(list) + 1, Agents.cap(s) do
        table.insert(rows, {icon = "dp_imark_empty.tga", a = "Vacant", b = " ", c = " ", key = "A_NEW", dim = true,
                            tip = "A free place: recruit an operative, or assign a hero known for spycraft."})
    end
    return "Imperial Operatives", {"Operative", "Location", "Rank", "Experience"}, rows
end

function IW.rows(s, H)
    if IW.view == "agents" then
        return agent_rows(s, H)
    end
    return target_rows(s, H)
end

function IW.tools(s)
    if IW.view == "agents" then
        local why = Agents.recruit_blocked(s)
        local A = CONFIG.AGENTS
        local eligible = table.getn(Agents.eligible(s))
        local full = table.getn(Agents.list(s)) >= Agents.cap(s)
        return {
            {"Recruit operative", "iw_recruit", why or ("A new agent joins at the capital (" .. A.RECRUIT_AUTHORITY .. " authority, "
                .. A.RECRUIT_CREDITS .. " credits). Once every " .. M.weeks(A.RECRUIT_WEEKS) .. "."), why ~= nil},
            {"Assign a hero", "iw_assign", full and "No free place for another operative." or ((eligible == 0)
                and "No hero known for spycraft is in the field." or ("Heroes known for spycraft (" .. eligible
                .. " in the field) can serve as operatives.")), full or eligible == 0},
            {"Foreign powers", "iw_targets", "Back to the foreign powers."},
        }
    end
    return {
        {"Imperial Intelligence", "iw_home", "The Director, counter-intelligence and the latest reports."},
        {"Counter-intel (" .. CONFIG.OPS.COUNTER.cost .. ")", "iw_counter", CONFIG.OPS.COUNTER.desc,
         Intel.blocked(s, "COUNTER", nil) ~= nil},
    }
end

function IW.row_click(s, key)
    if type(key) ~= "string" then
        return
    end
    if key == "A_NEW" then
        IW.sel = nil
        return
    end
    IW.flow, IW.assign, IW.more = nil, false, false
    IW.sel = (IW.sel ~= key) and key or nil
end

local function steps(key)
    local list = {}
    for _, kind in ipairs(CONFIG.OPS[key].pick or {}) do
        table.insert(list, kind)
    end
    table.insert(list, "agent")
    table.insert(list, "confirm")
    return list
end

function IW.start(s, key, target, preset)
    local why = Intel.blocked(s, key, target)
    if why then
        return why
    end
    local flow = {key = key, target = target, step = 1, steps = steps(key), preset_steps = {}}
    for k, v in pairs(preset or {}) do
        flow[k] = v
        flow.preset_steps[k] = true
    end
    while flow.steps[flow.step] ~= "agent" and flow.steps[flow.step] ~= "confirm" and flow[flow.steps[flow.step]] do
        flow.step = flow.step + 1
    end
    IW.flow, IW.assign = flow, false
    IW.view = "targets"
    return nil
end

local function choice(text, tip, color, pick, off, pic, pic_tip, world)
    return {text = text, tip = off and (tip .. " " .. off) or tip, color = off and GREY or color, pick = pick, off = off,
            pic = pic, pic_tip = pic_tip or tip, world = world, label = world and Court.planet_label(world) or nil}
end

local function agents_at(s, world)
    local n = 0
    for _, a in ipairs(Agents.list(s)) do
        if Agents.location(s, a) == world then
            n = n + 1
        end
    end
    return n
end

local function flow_choices(s, H, flow, kind)
    local out = {}
    local key = flow.key
    if kind == "planet" then
        for _, world in ipairs(Intel.worlds_of(flow.target)) do
            local where = Court.planet_label(world)
            local n = agents_at(s, world)
            local extra = ""
            if key == "INCITE" or key == "PROPAGANDA" then
                extra = " Loyalty " .. (Intel.influence(world) or "?") .. ", would rise for " .. H.label(string.upper(Intel.preferred(world))) .. "."
            end
            local capital = Intel.capital_name(flow.target) == world
            table.insert(out, choice(where .. (capital and " (capital)" or "") .. ((n > 0) and (" - " .. n .. " operative" .. ((n > 1) and "s" or "")) or ""),
                where .. "." .. extra .. (capital and " Their capital: harder." or ""), H.owner_color(s, flow.target),
                world, Intel.pick_blocked(s, key, "planet", world, flow), H.faction_icon(flow.target), nil, world))
        end
    elseif kind == "building" then
        local seen = {}
        for _, b in ipairs(Intel.buildings(flow.target, flow.planet)) do
            seen[b.type] = (seen[b.type] or 0) + 1
            if seen[b.type] == 1 then
                table.insert(out, choice(b.name, b.name .. " on " .. Court.planet_label(flow.planet) .. ".", PALE, b.type, nil,
                    H.faction_icon(flow.target)))
            end
        end
        for _, row in ipairs(out) do
            if seen[row.pick] > 1 then
                row.text = row.text .. " (" .. seen[row.pick] .. ")"
            end
        end
    elseif kind == "hero" then
        for _, h in ipairs(Intel.heroes(flow.target)) do
            local where = h.world and Court.planet_label(h.world) or "in hyperspace"
            table.insert(out, choice(h.name .. " - " .. where, h.name .. ", now " .. (h.world and ("at " .. where) or where)
                .. ". Your operative must be where they are.", PALE, h.type, (not h.world) and "They are in hyperspace." or nil,
                H.faction_icon(flow.target)))
        end
    elseif kind == "faction" then
        for _, t in ipairs(Intel.targets(s)) do
            if t.faction ~= flow.target and not Intel.world_target(t.faction) then
                local opinion = Intel.opinion(t.faction, flow.target)
                table.insert(out, choice(H.label(t.faction) .. " (thinks " .. M.signed(opinion) .. " of them)",
                    H.label(t.faction) .. "'s opinion of " .. H.label(flow.target) .. ": " .. M.signed(opinion) .. ".",
                    H.owner_color(s, t.faction), t.faction, Intel.pick_blocked(s, key, "faction", t.faction, flow),
                    H.faction_icon(t.faction)))
            end
        end
    elseif kind == "char" then
        local list = {}
        for _, id in ipairs(s.order) do
            local c = s.chars[id]
            if c.status == "serving" and not c.leads then
                table.insert(list, c)
            end
        end
        table.sort(list, function(a, b)
            local ra = CONFIG.TITLES[a.title] and CONFIG.TITLES[a.title].rank or 0
            local rb = CONFIG.TITLES[b.title] and CONFIG.TITLES[b.title].rank or 0
            if ra ~= rb then
                return ra > rb
            end
            return a.name < b.name
        end)
        for _, c in ipairs(list) do
            local where = Intel.char_location(s, c)
            table.insert(out, choice(Court.full_name(c) .. " - loyalty " .. M.round(c.loyalty),
                Court.full_name(c) .. ", at " .. (where and Court.planet_label(where) or "?") .. (c.traitor and ". A branded traitor." or "."),
                PALE, c.id, Intel.pick_blocked(s, key, "char", c.id, flow), Court.portrait(c)))
        end
    elseif kind == "agent" then
        for _, a in ipairs(Agents.list(s)) do
            local probe = {key = flow.key, target = flow.target, planet = flow.planet, hero = flow.hero, char = flow.char, agent = a.id}
            local off = Intel.agent_blocked(s, a, probe)
            local row = choice(op_name(s, a) .. " - " .. agent_where(s, a),
                Agents.label(s, a) .. ", " .. rank_text(a) .. ", at " .. agent_where(s, a) .. "." .. traits_text(a) .. " "
                .. (off and "" or (Intel.chance(s, flow.key, probe) .. "% to succeed, " .. Intel.cost(s, flow.key, probe)
                .. " credits.")), PALE, a.id, off, agent_icon(s, a))
            row.level = a.rank or 1
            table.insert(out, row)
        end
    end
    return out
end

local function plan_lines(s, H, flow)
    local def = CONFIG.OPS[flow.key]
    local a = Agents.get(s, flow.agent)
    local lines = {}
    local c = flow.char and Court.char(s, flow.char)
    local target = c and Court.full_name(c) or H.label(flow.target)
    table.insert(lines, {"Target: " .. target .. (flow.planet and (", " .. Court.planet_label(flow.planet)) or "")
        .. (flow.building and (", " .. Intel.unit_name(flow.building)) or "") .. (flow.hero and (", " .. Intel.unit_name(flow.hero)) or "")
        .. (flow.faction and (" (" .. H.label(flow.faction) .. ")") or ""), nil})
    table.insert(lines, {"Operative: " .. (a and op_name(s, a) or "?"),
        a and (Agents.label(s, a) .. ", " .. rank_text(a) .. "." .. traits_text(a)) or nil})
    if (def.caught or 0) == 0 then
        table.insert(lines, {"Success: " .. Intel.chance(s, flow.key, flow) .. "%   The operative cannot be caught.", nil})
    else
        local anger = M.round((def.attitude or 0) * (1 + CONFIG.COVERT.CAUGHT_TIER * (def.tier or 1)))
        table.insert(lines, {"Success: " .. Intel.chance(s, flow.key, flow) .. "%   Caught: " .. Intel.caught_chance(s, flow.key, flow)
            .. "% (the operative dies" .. (def.internal and "" or (", the network loses a tier, their anger " .. anger)) .. ")", nil})
    end
    table.insert(lines, {"Cost: " .. Intel.cost(s, flow.key, flow) .. " credits" .. ((def.authority or 0) > 0 and (", " .. def.authority .. " authority") or "")
        .. ", " .. (def.open and "until recalled" or M.weeks(def.weeks)), nil})
    if def.caught_fails then
        table.insert(lines, {"If caught, the plot fails.", nil})
    end
    return lines
end

local function flow_detail(s, H)
    local flow = IW.flow
    local def = CONFIG.OPS[flow.key]
    local kind = flow.steps[flow.step]
    local target = (flow.target == CONFIG.FACTION) and "the court" or H.label(flow.target)
    local d = H.empty_detail(def.name .. ": " .. target, (kind == "faction" and FACTION_PROMPT[flow.key]) or PROMPTS[kind] or " ")
    d.portrait = (flow.target == CONFIG.FACTION) and nil or H.faction_icon(flow.target)
    d.sub2 = "Step " .. flow.step .. " of " .. table.getn(flow.steps) .. "."
    d.kind = def.desc
    d.stats = {" ", " ", " ", " "}
    d.head = (kind == "confirm") and "The plan" or ((kind == "faction" and FACTION_PROMPT[flow.key]) or PROMPTS[kind])
    if kind == "confirm" then
        d.lines = plan_lines(s, H, flow)
        d.actions = {{"Confirm", "iw_confirm", "Launch the operation."}, {"Back", "iw_back", "The previous choice."},
                     {"Cancel", "iw_cancel", "Drop the plan."}}
    else
        d.worlds = flow_choices(s, H, flow, kind)
        d.rows_word = (kind == "planet") and "worlds" or "choices"
        if table.getn(d.worlds) == 0 then
            d.worlds = nil
            d.lines = {{(kind == "agent") and "No operatives: recruit one first." or "Nothing to choose from.", nil}}
        end
        d.actions = {{"Back", "iw_back", "The previous choice."}, {"Cancel", "iw_cancel", "Drop the plan."}}
    end
    return d
end

function IW.choose(s, w)
    if IW.assign then
        local c = Court.char(s, w.pick)
        if not c then
            return nil
        end
        local _, message = Agents.assign(s, c)
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

local function home_detail(s, H)
    local director = Intel.director(s)
    local strength = Court.office_strength(s, "INTEL")
    local d = H.empty_detail("Imperial Intelligence", "Director: " .. (director and Court.full_name(director) or "vacant"))
    d.portrait = director and Court.portrait(director) or nil
    d.sub2 = (strength < 0) and "The Director works against you: operations fail more, plots stay hidden."
        or ("Operations " .. M.signed(CONFIG.COVERT.DIRECTOR * strength + (Court.regime(s).covert or 0)) .. "% from the Director and the regime.")
    d.kind = ((s.ops.counter_until or 0) > 0 and s.week <= s.ops.counter_until) and ("Counter-intelligence sweeps until week "
        .. s.ops.counter_until .. ".") or "No counter-intelligence sweep."
    d.stats = {{s.ops.last or "No operation has reported yet.", s.ops.last},
               "Operatives: " .. table.getn(Agents.list(s)) .. " of " .. Agents.cap(s), " ", " "}
    d.head = "Latest reports"
    d.lines = {}
    local k = 0
    for _, line in ipairs(s.news or {}) do
        if k < 6 and (string.find(line, "Intelligence") or string.find(line, "network") or string.find(line, "against")
                or string.find(line, "Operative") or string.find(line, "Agent")) then
            k = k + 1
            d.lines[k] = {line, line}
        end
    end
    if k == 0 then
        d.lines[1] = {"Select a power to plan an operation; the box at the top right lists your operatives.", nil}
    end
    d.actions = {}
    return d
end

local function op_buttons(s, target, keys)
    local actions = {}
    for _, key in ipairs(keys) do
        local def = CONFIG.OPS[key]
        local why = Intel.blocked(s, key, target)
        table.insert(actions, {(def.short or def.name) .. " (" .. def.cost .. ")", "iw_op_" .. key,
            def.name .. ((def.tier and not def.internal) and (" (tier " .. def.tier .. ")") or "") .. ": " .. def.desc
                .. " Base " .. Intel.chance(s, key, {target = target}) .. "% to succeed, " .. (((def.caught or 0) == 0) and "never caught. "
                or (Intel.caught_chance(s, key, {}) .. "% to be caught" .. (def.internal and ". " or (" (their anger "
                .. M.round((def.attitude or 0) * (1 + CONFIG.COVERT.CAUGHT_TIER * (def.tier or 1))) .. "). ")))) .. (def.open and "Until recalled." or M.weeks(def.weeks) .. ".") .. (why and (" " .. why) or ""),
            why ~= nil, why})
    end
    return actions
end

local function internal_detail(s, H)
    local director = Intel.director(s)
    local d = H.empty_detail("Internal affairs", "Operations against members of the court.")
    d.portrait = director and Court.portrait(director) or nil
    d.sub2 = director and ("Director " .. director.name .. ", loyalty " .. M.round(director.loyalty) .. " (needs "
        .. CONFIG.COVERT.DIRECTOR_LOYALTY .. ").") or "No Director: these operations are closed."
    d.kind = "Your operative must be where the target is: their hero, else their seat, else the capital."
    d.stats = {" ", " ", " ", " "}
    d.head = "Watched by minders"
    d.lines = {}
    for _, run in ipairs(s.ops.running) do
        if run.key == "MINDER" and table.getn(d.lines) < 6 then
            local c = Court.char(s, run.char)
            local a = Agents.get(s, run.agent)
            table.insert(d.lines, {(c and c.name or "?") .. " - " .. (a and Agents.label(s, a) or "?"), nil})
        end
    end
    if table.getn(d.lines) == 0 then
        d.lines[1] = {"Nobody.", nil}
    end
    d.actions = op_buttons(s, CONFIG.FACTION, CONFIG.INTERNAL_ORDER)
    return d
end

local PAGE1 = {"GATHER", "SWAY", "BRIBE", "SABOTAGE", "PROPAGANDA"}
local PAGE2 = {"STAGE_ATTACK", "ASSASSINATE", "DEFECTION", "INCITE", "INCITE_WAR"}

local function target_detail(s, H, target)
    local n = Intel.network(s, target)
    local d = H.empty_detail(H.label(target), " ")
    d.portrait = H.faction_icon(target)
    d.portrait_tip = H.label(target) .. "."
    local worlds = table.getn(Intel.worlds_of(target))
    local capital = Intel.capital_name(target)
    if n.tier == 0 then
        d.sub = "No spy network: tier 0."
        d.sub2 = worlds .. " worlds."
        d.kind = "A probe droid spying on their capital, or a ceasefire, opens a network."
        d.stats = {"Network: none", "Worlds: " .. worlds, " ", " "}
        d.head = "Capital"
        if capital then
            local where = Court.planet_label(capital)
            d.worlds = {{world = capital, label = where, text = where .. " (capital)", color = H.owner_color(s, target),
                         tip = where .. ": the capital of " .. H.label(target) .. ". Send a probe droid to spy on it.",
                         pic = H.faction_icon(target), pic_tip = H.label(target) .. "."}}
        else
            d.lines = {{"Their capital is unknown.", nil}}
        end
        return d
    end
    local report = s.ops.reports and s.ops.reports[target]
    d.sub = report and ("Report, week " .. report.week .. ": " .. report.worlds .. " worlds, " .. report.credits .. " credits")
        or (worlds .. " worlds; no report yet: gather intelligence.")
    d.sub2 = (report and table.getn(report.heroes) > 0) and ("Leaders: " .. table.concat(report.heroes, ", ")) or " "
    local att = s.attitude[target] or 0
    d.kind = "Capital: " .. (capital and Court.planet_label(capital) or "unknown") .. ((att ~= 0) and (". Their attitude to us: "
        .. M.signed(att) .. ".") or ".")
    local full = n.tier >= CONFIG.SPY.MAX
    d.stats = {{"Network: tier " .. n.tier .. " (" .. Intel.tier_name(n.tier) .. ")", "Each tier opens more operations; "
                .. "gathering intelligence builds the network."},
               full and "Intel progress: complete" or ("Intel progress: " .. n.progress .. "/" .. CONFIG.SPY.PROGRESS), " ", " "}
    d.head = (n.tier >= 2) and "Their views" or "Their views (tier 2)"
    d.lines = {}
    if n.tier >= 2 then
        local views = {}
        for _, t in ipairs(Intel.targets(s)) do
            if t.faction ~= target and not Intel.world_target(t.faction) then
                table.insert(views, {faction = t.faction, value = Intel.opinion(target, t.faction)})
            end
        end
        table.insert(views, {faction = CONFIG.FACTION, value = Intel.opinion(target, CONFIG.FACTION)})
        table.sort(views, function(a, b)
            local wa = string.find(a.faction, "^WARLORD") ~= nil
            local wb = string.find(b.faction, "^WARLORD") ~= nil
            if wa ~= wb then
                return wb
            end
            return M.max(a.value, -a.value) > M.max(b.value, -b.value)
        end)
        d.views = {}
        for _, v in ipairs(views) do
            local _, reasons = Intel.opinion(target, v.faction)
            local why = {}
            for _, r in ipairs(reasons) do
                table.insert(why, r[1] .. " " .. M.signed(r[2]))
            end
            table.insert(d.views, {icon = H.faction_icon(v.faction), value = v.value,
                tip = H.label(target) .. " on " .. H.label(v.faction) .. ": " .. M.signed(v.value)
                    .. ((table.getn(why) > 0) and (" (" .. table.concat(why, ", ") .. ")") or "") .. "."})
        end
    else
        d.lines[1] = {"Their views of the other powers need a tier 2 network.", nil}
    end
    d.actions = op_buttons(s, target, IW.more and PAGE2 or PAGE1)
    table.insert(d.actions, IW.more and {"Back", "iw_less", "The first operations."}
        or {"More...", "iw_more", "Staged attacks, assassination, defection, revolt, war."})
    return d
end

local function run_detail(s, H, run)
    local def = CONFIG.OPS[run.key]
    local a = Agents.get(s, run.agent)
    local c = run.char and Court.char(s, run.char)
    local d = H.empty_detail(def.name, (c and Court.full_name(c)) or (run.target and H.label(run.target)) or " ")
    d.portrait = a and agent_icon(s, a) or nil
    d.sub2 = "Operative: " .. (a and op_name(s, a) or "?")
    d.kind = def.desc
    d.stats = {"At " .. (run.at and Court.planet_label(run.at) or "?"), run.open and "Until recalled" or ("Reports in " .. weeks_left(s, run)),
               "Success: " .. Intel.chance(s, run.key, run) .. "%", "Caught: " .. Intel.caught_chance(s, run.key, run) .. "%"}
    d.head = "The operation"
    d.lines = {{"The operative must stay at " .. (run.at and Court.planet_label(run.at) or "the target") .. " until it is done.", nil}}
    d.actions = {{run.open and "Recall" or "Abort", "iw_recall", run.open and "End the watch." or "Call it off (the money is lost)."}}
    return d
end

local function agent_detail(s, H, a)
    local run = Intel.run_of(s, a.id)
    local d = H.empty_detail(Agents.label(s, a), "Rank: " .. rank_text(a) .. ", " .. (a.xp or 0) .. " experience.")
    d.portrait = agent_icon(s, a)
    d.level = a.rank or 1
    d.sub2 = "At " .. agent_where(s, a) .. "." .. (a.fast and (a.unit_fast and " Flies a classified agent vessel."
        or " A classified agent vessel waits for them (when no battle looms where they stand).") or "")
    d.kind = (a.kind == "lore") and "A hero serving Imperial Intelligence." or "An agent of Imperial Intelligence."
    d.stats = {run and ("Mission: " .. CONFIG.OPS[run.key].name) or "No mission", run and weeks_left(s, run) or " ",
               "Rank bonus: +" .. CONFIG.COVERT.RANK * ((a.rank or 1) - 1) .. "% success", " "}
    d.head = "Traits"
    d.lines = {}
    for _, t in ipairs(a.traits or {}) do
        local def = CONFIG.AGENT_TRAITS[t]
        table.insert(d.lines, {def.name, def.name .. ": " .. def.desc, value = 1})
    end
    if table.getn(d.lines) == 0 then
        d.lines[1] = {"None yet.", "Each rank gained brings a " .. CONFIG.AGENT_TRAIT_CHANCE .. "% chance of a trait."}
    end
    table.insert(d.lines, {" ", nil})
    table.insert(d.lines, {"Move the operative on the galaxy map to where an operation must take place, then plan it from a "
        .. "power's page.", nil})
    d.actions = {{(a.kind == "lore") and "Release" or "Dismiss", "iw_fire", (a.kind == "lore") and "They return to other duties."
                    or "The agent retires (their unit leaves).", run ~= nil},
                 {"Show on map", "iw_map", "Close the window and look at their world.", Agents.location(s, a) == nil}}
    if run then
        table.insert(d.actions, {run.open and "Recall" or "Abort", "iw_recall", "End their mission."})
    end
    return d
end

local function assign_detail(s, H)
    local d = H.empty_detail("Assign a hero", "Heroes known for spycraft, in the field.")
    d.kind = "Never the ruler, Isard or the Director."
    d.stats = {" ", " ", " ", " "}
    d.head = "Choose a hero"
    d.worlds = {}
    for _, c in ipairs(Agents.eligible(s)) do
        local where = Intel.char_location(s, c)
        table.insert(d.worlds, choice(Court.full_name(c) .. " - " .. (where and Court.planet_label(where) or "?"),
            Court.full_name(c) .. ": click to make them an operative.", PALE, c.id, nil, Court.portrait(c)))
    end
    d.rows_word = "heroes"
    if table.getn(d.worlds) == 0 then
        d.worlds = nil
        d.lines = {{"No hero known for spycraft is in the field.", nil}}
    end
    d.actions = {{"Cancel", "iw_cancel", "Back."}}
    return d
end

function IW.detail(s, H)
    if IW.flow then
        return flow_detail(s, H)
    end
    if IW.assign then
        return assign_detail(s, H)
    end
    local sel = IW.sel or ""
    if string.find(sel, "^R_") then
        local run = Intel.run_of(s, tonumber(string.sub(sel, 3)))
        if run then
            return run_detail(s, H, run)
        end
    elseif string.find(sel, "^A_") then
        local a = Agents.get(s, tonumber(string.sub(sel, 3)))
        if a then
            return agent_detail(s, H, a)
        end
    elseif sel == "T_" .. CONFIG.FACTION then
        return internal_detail(s, H)
    elseif string.find(sel, "^T_") then
        return target_detail(s, H, string.sub(sel, 3))
    end
    return home_detail(s, H)
end

function IW.action(s, key)
    local sel = IW.sel or ""
    if key == "iw_more" then
        IW.more = true
    elseif key == "iw_less" then
        IW.more = false
    elseif string.find(key, "^iw_op_") then
        local op = string.sub(key, 7)
        local target = string.sub(sel, 3)
        return IW.start(s, op, target)
    elseif key == "iw_back" and IW.flow then
        local flow = IW.flow
        flow.step = flow.step - 1
        while flow.step >= 1 and flow.preset_steps and flow.preset_steps[flow.steps[flow.step]] do
            flow.step = flow.step - 1
        end
        if flow.step < 1 then
            IW.flow = nil
        end
    elseif key == "iw_cancel" then
        IW.flow, IW.assign = nil, false
    elseif key == "iw_confirm" and IW.flow then
        local ok, message = Intel.launch(s, IW.flow)
        if ok then
            IW.flow = nil
        end
        return message
    elseif key == "iw_recall" then
        local run
        if string.find(sel, "^R_") or string.find(sel, "^A_") then
            run = Intel.run_of(s, tonumber(string.sub(sel, 3)))
        end
        if run then
            local _, message = Intel.recall(s, run)
            IW.sel = nil
            return message
        end
    elseif key == "iw_fire" then
        local a = Agents.get(s, tonumber(string.sub(sel, 3)))
        if a then
            local ok, message = Agents.fire(s, a)
            if ok then
                IW.sel = nil
            end
            return message
        end
    elseif key == "iw_map" then
        local a = Agents.get(s, tonumber(string.sub(sel, 3)))
        return nil, a and Agents.location(s, a)
    elseif key == "iw_recruit" then
        local _, message = Agents.recruit(s)
        return message
    elseif key == "iw_assign" then
        IW.assign, IW.flow = true, nil
    elseif key == "iw_targets" then
        IW.view, IW.sel = "targets", nil
    elseif key == "iw_home" then
        IW.sel, IW.flow, IW.assign, IW.more = nil, nil, false, false
    elseif key == "iw_counter" then
        local _, message = Intel.launch(s, {key = "COUNTER"})
        return message
    end
    return nil
end

function IW.prisoners(s)
    local out = {}
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "imprisoned" then
            table.insert(out, c)
        end
    end
    return out
end

function IW.prison_detail(s, H)
    local list = IW.prisoners(s)
    local d = H.empty_detail("The Imperial Prison", table.getn(list) .. " prisoner" .. ((table.getn(list) == 1) and "" or "s") .. ".")
    d.sub2 = "Prisoners hold no titles, join no faction and sway nobody."
    d.kind = "Arrests are made by Imperial Intelligence (Intelligence tab, Internal affairs)."
    d.stats = {" ", " ", " ", " "}
    d.head = "Prisoners"
    d.worlds = {}
    for _, c in ipairs(list) do
        table.insert(d.worlds, {text = c.name .. (c.traitor and " (traitor)" or "") .. " - since week " .. (c.left_week or "?"),
                                tip = c.name .. ": furious and disloyal, but powerless.", color = GREY, pic = Court.portrait(c),
                                pic_tip = c.name .. "."})
    end
    d.rows_word = "prisoners"
    if table.getn(d.worlds) == 0 then
        d.worlds = nil
        d.lines = {{"The cells are empty.", nil}}
    end
    return d
end

return IW
