local Pause = require("eawx-plugins/diplomacy/DiplomacyPause")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local Senate = require("eawx-plugins/diplomacy/DiplomacySenate")
local Missions = require("eawx-plugins/diplomacy/DiplomacyMissions")
local Republic = require("eawx-plugins/new-republic/Republic")
local LAYOUT = require("eawx-plugins/diplomacy/DiplomacySenateLayout")
local GLOBES = require("eawx-plugins/diplomacy/DiplomacyGlobes")
local LEADERS = require("eawx-plugins/diplomacy/DiplomacyLeaders")

local Window = {open_now = false, left = "floor", right = "chamber", page = 1}

local SHELL = "dp_senate_shell"
local DOTS_SHELL = "dp_dots_shell"
local COUNCIL_SHELL = "dp_council_shell"
local BLOC_SHELL = "dp_bloc_shell"
local LAWS_SHELL = "dp_laws_shell"

local function blocs_part()
    return Republic.part("blocs")
end

local function council_part()
    return Republic.part("council")
end

local function layer_shell(name)
    return "dp_seats_" .. name .. "_shell"
end
local BLOC_ORDER = {"Frontier", "New member", "Heartland", "Resentful"}
local BLOC_DOT = {Frontier = "frontier", Heartland = "heartland", ["New member"] = "newmember", Resentful = "occupied",
                  Military = "military", ["Worlds beyond this region"] = "beyond"}
local LORE_DOTS = {"lore1", "lore2", "lore3", "lore4"}
local RING = {yes = "dp_ring_yes.tga", no = "dp_ring_no.tga", abstain = "dp_ring_abstain.tga",
              selected = "dp_ring_selected.tga"}
local PIP = {yes = "dp_pip_yes.tga", no = "dp_pip_no.tga", abstain = "dp_pip_abstain.tga"}
local BLOC_TEXT = {
    Frontier = "Border worlds: they back wars on the enemy at their gates.",
    ["New member"] = "Recently joined worlds: they back the government.",
    Heartland = "The core worlds: wary of new wars, in favour of treaties.",
    Resentful = "Conquered worlds with a seat: they still resent the government.",
    ["Worlds beyond this region"] = "Senators of Republic worlds beyond this map.",
    Military = "The fleet's seats on the Provisional Council: they back wars.",
}
local GROUPS = {
    {key = "WAR", label = "Declare War", tip = "Declare war on another power."},
    {key = "PEACE", label = "Authorise Peace Talks", tip = "Let your diplomats offer a ceasefire without another vote."},
    {key = "ALLIANCE", label = "Authorise an Alliance", tip = "Let your diplomats offer an alliance without another vote."},
    {key = "ADMIT", label = "Admit a Member World", tip = "Associate worlds that have asked to become full members."},
    {key = "JOIN", label = "Petitions to Join", tip = "Free worlds that ask for the Republic's protection."},
    {key = "ASSOCIATE", label = "Petitions of Protected Worlds", tip = "Protected worlds that ask to become associates."},
    {key = "TAX", label = "Sector Taxes", tip = "Raise or lower the taxes of a sector's member worlds."},
    {key = "SREPEAL", label = "Force Sector Law Repeal", tip = "Have the Senate strike down a law a sector passed for itself."},
    {key = "PROTECT", label = "Authorise Protection", tip = "Let your diplomats offer a free power or world the Republic's protection."},
    {key = "CEDE", label = "Offer a World in Talks", tip = "Let one of the Republic's worlds be offered in negotiations. Few senators like it."},
}

local function republic_window()
    local ok, W = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
    return ok and type(W) == "table" and W or nil
end

local function rules()
    return CONFIG.SENATE
end

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("SENATE WINDOW gui error: " .. tostring(err))
    end
end

local function show(name, visible)
    call(GUI_Component_Visibility, name, visible and true or false)
end

local TEXTS = {}
local function text(name, value)
    value = value or " "
    if TEXTS[name] == value then
        return
    end
    TEXTS[name] = value
    call(GUI_Component_Text, name, value)
end

local function tip(name, value)
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_" .. string.upper(name) .. "_TIP", value or " ")
    end
end

local function disable(name, off)
    local ok, Panels = pcall(require, "eawx-plugins/diplomacy/DiplomacyPanels")
    if ok and type(Panels) == "table" and Panels.set_disabled then
        Panels.set_disabled(name, off)
    end
end

local ICONS = {}
local function icon(name, texture)
    if ICONS[name] == texture then
        return
    end
    ICONS[name] = texture
    call(GUI_Button_Icon, name, texture, 1, 1, 1, 1)
end

local function three(n)
    return string.format("%03d", n)
end

local function two(n)
    return string.format("%02d", n)
end

local function capital(s)
    return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

local function vote_key(v)
    return (v > 0 and "yes") or (v < 0 and "no") or "abstain"
end

local function vote_words(v)
    return (v > 0 and "votes for") or (v < 0 and "votes against") or "abstains"
end

local function opinion_ring(opinion)
    local t = M.max(-1, M.min(1, opinion / 60))
    return "dp_ring_op" .. M.round((t + 1) * 3 + 1) .. ".tga"
end

local function wrap(line, width)
    return Senate.wrap(line, width or 34)
end

local function fill_lines(prefix, count, lines, width)
    local out = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            for _, part in ipairs(wrap(line, width)) do
                table.insert(out, part)
            end
        end
    end
    for k = 1, count do
        text(prefix .. k, out[k])
        show(prefix .. k, true)
    end
end

local function bloc_key(bloc)
    local B = blocs_part()
    return BLOC_DOT[bloc] or (B and B.dot(bloc))
end

local function bloc_dot(bloc)
    local key = bloc_key(bloc)
    if key then
        return "dp_dot_" .. key .. ".tga"
    end
    Window.lore_dot = Window.lore_dot or {}
    if not Window.lore_dot[bloc] then
        local n = 0
        for _ in pairs(Window.lore_dot) do
            n = n + 1
        end
        Window.lore_dot[bloc] = LORE_DOTS[M.min(n + 1, table.getn(LORE_DOTS))]
    end
    return "dp_dot_" .. Window.lore_dot[bloc] .. ".tga"
end

local function council_seats(d)
    local seats = {}
    local by_key = council_part().seats(d)
    for _, c in ipairs(council_part().CONFIG.COUNCILLORS) do
        if by_key[c.key] then
            table.insert(seats, by_key[c.key])
        end
    end
    return seats
end

local function sorted_seats(d)
    if Republic.council(d) then
        return council_seats(d)
    end
    local by_bloc, order = {}, {}
    for _, bloc in ipairs(BLOC_ORDER) do
        by_bloc[bloc] = {}
        table.insert(order, bloc)
    end
    for _, seat in pairs(Senate.seats(d)) do
        if not by_bloc[seat.bloc] then
            by_bloc[seat.bloc] = {}
            table.insert(order, 1, seat.bloc)
        end
        table.insert(by_bloc[seat.bloc], seat)
    end
    local seats = {}
    for _, bloc in ipairs(order) do
        table.sort(by_bloc[bloc], function(a, b) return a.name < b.name end)
        for _, seat in ipairs(by_bloc[bloc]) do
            table.insert(seats, seat)
        end
    end
    return seats
end

function Window.arrange(n, rows)
    local first = table.getn(rows)
    local capacity = rows[first]
    while capacity < n and first > 1 do
        first = first - 1
        capacity = capacity + rows[first]
    end
    n = M.min(n, capacity)
    local start, acc = {}, 0
    for r = 1, table.getn(rows) do
        start[r] = acc
        acc = acc + rows[r]
    end
    local picked = {}
    local left = n
    for r = table.getn(rows), first, -1 do
        local take = left
        if r ~= first then
            take = M.min(left, M.round(n * rows[r] / capacity))
        end
        left = left - take
        for k = 1, take do
            local index = M.floor((k - 0.5) * rows[r] / take)
            table.insert(picked, {slot = start[r] + index + 1, pos = (index + 0.5) / rows[r], row = r})
        end
    end
    table.sort(picked, function(a, b)
        if a.pos ~= b.pos then
            return a.pos < b.pos
        end
        return a.row > b.row
    end)
    local slot_of = {}
    for k, p in ipairs(picked) do
        slot_of[p.slot] = k
    end
    return slot_of
end

local function motion_in_view(d)
    if Window.left == "preview" and Window.preview then
        return Window.preview
    end
    return d.senate.debate and d.senate.debate.motion
end

function Window.render(d)
    local profile = Senate.profile(d)
    local debate = d.senate.debate
    Window.seen_debate = debate
    local motion = motion_in_view(d)
    local seats = sorted_seats(d)
    local by_name = {}
    for _, seat in ipairs(seats) do
        by_name[seat.name] = seat
    end
    Window.seats, Window.by_name = seats, by_name
    if Window.selected and not by_name[Window.selected] then
        Window.selected = nil
    end
    if Window.right == "seat" and not Window.selected then
        Window.right = "chamber"
    end

    text("dp_senate_title", profile.council and "The Provisional Council" or "The Senate")
    text("dp_senate_meters", " ")
    show("dp_senate_stability", false)
    local result = motion and ((debate and debate.motion == motion and debate.failed and debate.result)
        or Senate.tally(d, motion))
    show(COUNCIL_SHELL, profile.council)
    if profile.council then
        Window.render_council(d, seats, motion, result, debate)
    else
        local chief = string.upper(tostring(GlobalValue.Get("ChiefOfState") or "DUMMY_CHIEFOFSTATE_MOTHMA"))
        local leader = LEADERS.CHIEFS and LEADERS.CHIEFS[chief]
        if not leader then
            for _, c in ipairs(Republic.CONFIG.COUNCIL.COUNCILLORS) do
                if c.candidate == chief then
                    leader = {name = c.name, icon = c.portrait}
                end
            end
        end
        show("dp_leader", leader ~= nil)
        if leader then
            icon("dp_leader", leader.icon)
            local agenda = Republic.CONFIG.CANDIDATES[chief]
            tip("dp_leader", "Chancellor " .. leader.name .. "." .. (agenda and (" " .. agenda.text) or ""))
        end
        Window.render_hemicycle(d, profile, seats, motion, result, debate)
    end
    Window.render_tally(d, seats, motion, result, debate)
    Window.render_laws(d, profile)
    Window.render_left(d, profile, debate, result)
    Window.render_right(d, profile, debate, motion, result)
end

function Window.render_council(d, seats, motion, result, debate)
    local Council = council_part()
    local C = Council.CONFIG
    local leader = Council.leader(d)
    show("dp_leader", true)
    icon("dp_leader", leader.portrait or "dp_emblem_rebel.tga")
    tip("dp_leader", leader.name .. ", leader of the Provisional Council. " .. (Council.alive(d, "MOTHMA")
        and "" or "Mon Mothma is dead: Leia Organa leads in her place."))
    for _, l in ipairs(LAYOUT.layers) do
        show(layer_shell(l.name), false)
    end
    for k = 1, 2 do
        show("dp_agg_" .. k, false)
        show("dp_ring_agg_" .. k, false)
        show("dp_agg_label_" .. k, false)
    end
    Window.slot_seat = {}
    for k = 1, LAYOUT.council_seats do
        local c = C.COUNCILLORS[k]
        local seat_name, ring_name, label = "dp_cn_seat_" .. k, "dp_cn_ring_" .. k, "dp_cn_name_" .. k
        show(seat_name, c ~= nil)
        show(ring_name, c ~= nil)
        show(label, c ~= nil)
        if c and not Council.alive(d, c.key) then
            icon(seat_name, "dp_council_empty.tga")
            icon(ring_name, RING.abstain)
            text(label, c.seat .. " (dead)")
            tip(seat_name, c.name .. " is dead. The seat stays empty: no one votes in their place.")
        elseif c then
            Window.slot_seat["cn" .. k] = c.key
            local op = Council.opinion(d, c.key)
            local ring, line
            if motion then
                local v = result.worlds[c.key] or 0
                ring = RING[vote_key(v)]
                line = capital(vote_words(v)) .. ((debate and debate.motion == motion and debate.pressured[c.key])
                    and " (under pressure)" or "") .. "."
            else
                ring = opinion_ring(op)
                line = "Cares about " .. table.concat(c.interests or {}, " and ") .. "."
            end
            if c.key == Window.selected then
                ring = RING.selected
            end
            icon(seat_name, c.portrait or "dp_emblem_rebel.tga")
            icon(ring_name, ring)
            text(label, c.seat)
            tip(seat_name, c.name .. ", Councillor for " .. Council.world_name(d, c) .. ": opinion " .. op .. ". " .. line)
        end
    end
    show("dp_seats_note", false)
    show("dp_sf_focus", false)
    show("dp_sf_focus_text", false)
    text("dp_cn_focus", "The Council's Focus")
    local focus = Council.focus(d)
    local left = Council.focus_weeks_left(d)
    disable("dp_cn_focus", focus and left > 0)
    if focus then
        text("dp_cn_focus_text", "Focus: " .. C.FOCUS[focus].name .. ((left > 0) and (" (can change in " .. left
            .. " week" .. ((left == 1) and "" or "s") .. ")") or " (can change now)"))
        tip("dp_cn_focus", C.FOCUS[focus].name .. ": " .. C.FOCUS[focus].text .. ((left > 0)
            and (" The Council can change its focus in " .. left .. " week" .. ((left == 1) and "" or "s") .. ".")
            or " Click to choose another."))
    else
        text("dp_cn_focus_text", "The Council has no focus yet.")
        tip("dp_cn_focus", "Set what the Council works for (" .. C.FOCUS_CAPITAL .. " political capital). It can "
            .. "change once every " .. C.FOCUS_WEEKS .. " weeks.")
    end
    if Window.selected then
        text("dp_hint", "Click the selected Councillor again, or right-click, to deselect them.")
    else
        text("dp_hint", "Hover over a Councillor for their vote; click them to see their card.")
    end
end

function Window.render_hemicycle(d, profile, seats, motion, result, debate)
    local layer = LAYOUT.layers[table.getn(LAYOUT.layers)]
    for _, l in ipairs(LAYOUT.layers) do
        if table.getn(seats) <= l.seats then
            layer = l
            break
        end
    end
    local shown = M.min(table.getn(seats), layer.seats)
    local slot_of = Window.arrange(shown, layer.rows)
    Window.slot_seat = {}
    for _, l in ipairs(LAYOUT.layers) do
        show(layer_shell(l.name), l == layer)
        if l == layer then
            for slot = 1, l.seats do
                local k = slot_of[slot]
                local seat = k and seats[k] or nil
                local seat_name, ring_name = "dp_seat_" .. l.name .. three(slot), "dp_ring_" .. l.name .. three(slot)
                if seat then
                    Window.slot_seat[l.name .. three(slot)] = seat.name
                    local ring, line
                    if motion then
                        local v = result.worlds[seat.name] or 0
                        ring = RING[vote_key(v)]
                        line = table.concat(Senate.vote_breakdown(d, seat, motion), " ")
                    else
                        ring = opinion_ring(seat.opinion)
                        line = "Leans: " .. Senate.lean_text(d, seat) .. "."
                    end
                    if Window.view == "blocs" and bloc_key(seat.bloc) then
                        ring = "dp_ring_b_" .. bloc_key(seat.bloc) .. ".tga"
                    end
                    if seat.name == Window.selected then
                        ring = RING.selected
                    end
                    icon(seat_name, GLOBES[seat.name] or "dp_globe_unknown.tga")
                    icon(ring_name, ring)
                    tip(seat_name, d:planet_name(seat.planet) .. ": " .. seat.bloc .. ", opinion " .. seat.opinion .. ". " .. line)
                    show(seat_name, true)
                    show(ring_name, true)
                else
                    show(seat_name, false)
                    show(ring_name, false)
                end
            end
        end
    end
    Window.shown_layer = layer.name

    local groups = {{key = 1, bloc = "Worlds beyond this region", n = profile.offmap, label = " distant"},
                    {key = 2, bloc = "Military", n = profile.military, label = " military"}}
    for _, g in ipairs(groups) do
        local visible = g.n > 0
        show("dp_agg_" .. g.key, visible)
        show("dp_ring_agg_" .. g.key, visible)
        show("dp_agg_label_" .. g.key, visible)
        if visible then
            local votes = result and result.blocs[g.bloc]
            local ring = RING.abstain
            local line = BLOC_TEXT[g.bloc]
            if votes then
                if votes.yes > votes.no and votes.yes >= votes.abstain then
                    ring = RING.yes
                elseif votes.no > votes.yes and votes.no >= votes.abstain then
                    ring = RING.no
                end
                line = votes.yes .. " for, " .. votes.no .. " against, " .. votes.abstain .. " undecided."
            end
            icon("dp_ring_agg_" .. g.key, ring)
            text("dp_agg_label_" .. g.key, g.n .. g.label)
            tip("dp_agg_" .. g.key, g.bloc .. " (" .. g.n .. " seats). " .. line)
        end
    end
    local note = table.getn(seats) .. " seats here"
    if profile.offmap > 0 then
        note = note .. ", " .. profile.offmap .. " beyond this region"
    end
    if profile.military > 0 then
        note = note .. ", " .. profile.military .. " military"
    end
    if table.getn(seats) > layer.seats then
        note = note .. " (" .. (table.getn(seats) - layer.seats) .. " not shown)"
    end
    text("dp_seats_note", note .. ".")
    show("dp_seats_note", true)
    local Focus = Republic.part("focus")
    show("dp_sf_focus", Focus ~= nil)
    show("dp_sf_focus_text", Focus ~= nil)
    if Focus then
        local now = Focus.active(d)
        local left = Focus.weeks_left(d)
        text("dp_sf_focus", "Propose a Focus")
        disable("dp_sf_focus", now ~= nil)
        if now then
            local def = Focus.def(now)
            text("dp_sf_focus_text", "Focus: " .. def.name .. " (" .. left .. " week" .. ((left == 1) and "" or "s") .. " left)")
            tip("dp_sf_focus", def.name .. ": " .. def.text .. " A new focus can be proposed in " .. left .. " week"
                .. ((left == 1) and "" or "s") .. ".")
            tip("dp_sf_focus_text", def.name .. ": " .. def.text)
        else
            text("dp_sf_focus_text", "The Senate has no focus.")
            tip("dp_sf_focus", "Propose what the Senate works for, for " .. Republic.CONFIG.SENATE_FOCUS.WEEKS
                .. " weeks. The chamber votes on it at once.")
            tip("dp_sf_focus_text", "Propose a focus: the Senate votes on it, and a passed focus holds for "
                .. Republic.CONFIG.SENATE_FOCUS.WEEKS .. " weeks.")
        end
    end
    if Window.selected then
        text("dp_hint", "Click the selected seat again, or right-click, to deselect it.")
    else
        text("dp_hint", "Hover over a seat for its vote; click it to see its senator.")
    end
end

function Window.render_tally(d, seats, motion, result, debate)
    local senate = not Republic.council(d)
    show("dp_view", senate)
    if senate then
        text("dp_view", (Window.view == "blocs") and "View: Blocs" or "View: Loyalty")
        tip("dp_view", (Window.view == "blocs") and "The seats are ringed in their bloc's colour. Click to ring them "
            .. "by loyalty (their opinion, or their vote on the motion in view)." or "The seats are ringed by loyalty "
            .. "(their opinion, or their vote on the motion in view). Click to ring them in their bloc's colour.")
    end
    if result then
        local total = M.max(1, result.yes + result.no + result.abstain)
        text("dp_tally", "For " .. result.yes .. "   |   Undecided " .. result.abstain .. "   |   Against " .. result.no)
        local yes_pips = M.round(LAYOUT.pips * result.yes / total)
        local no_pips = M.round(LAYOUT.pips * result.no / total)
        for k = 1, LAYOUT.pips do
            local pip = PIP.abstain
            if k <= yes_pips then
                pip = PIP.yes
            elseif k > LAYOUT.pips - no_pips then
                pip = PIP.no
            end
            icon("dp_pip_" .. two(k), pip)
            show("dp_pip_" .. two(k), true)
        end
        local margin = result.yes - result.no
        local verdict
        if debate and debate.motion == motion and debate.failed then
            verdict = "The motion failed."
        elseif margin > total / 4 then
            verdict = "The chamber supports it."
        elseif margin > 0 then
            verdict = "It would narrowly pass."
        elseif margin == 0 then
            verdict = "The chamber is split."
        elseif margin > -total / 4 then
            verdict = "It would narrowly fail."
        else
            verdict = "The chamber opposes it."
        end
        text("dp_verdict", verdict)
    else
        local loyal, hostile = 0, 0
        for _, seat in ipairs(seats) do
            if seat.opinion >= rules().LOYAL_OPINION then
                loyal = loyal + 1
            elseif seat.opinion <= rules().HOSTILE_OPINION then
                hostile = hostile + 1
            end
        end
        text("dp_tally", "Loyal " .. loyal .. "   |   Wavering " .. (table.getn(seats) - loyal - hostile)
            .. "   |   Hostile " .. hostile)
        for k = 1, LAYOUT.pips do
            show("dp_pip_" .. two(k), false)
        end
        text("dp_verdict", d.senate.recess and "The chamber is in recess." or "No motion is before the chamber.")
    end
end

local function laws_part()
    return Republic.part("laws")
end

local CENTRE_PARTS = {"dp_leader", "dp_tally", "dp_verdict", "dp_seats_note", "dp_view", "dp_agg_1", "dp_agg_2",
                      "dp_ring_agg_1", "dp_ring_agg_2", "dp_agg_label_1", "dp_agg_label_2"}

function Window.render_laws(d, profile)
    local Laws = laws_part()
    local on = Laws ~= nil and not profile.council
    show("dp_lw_toggle", on)
    if not on then
        Window.centre = "chamber"
        show(LAWS_SHELL, false)
        return
    end
    local L = Laws.CONFIG
    local rows = Laws.galactic_rows(d)
    local laws_view = Window.centre == "laws"
    show(LAWS_SHELL, laws_view)
    if laws_view then
        text("dp_lw_toggle", "Back to the Chamber")
        tip("dp_lw_toggle", "Show the chamber's seats again.")
    else
        text("dp_lw_toggle", "Galactic Laws (" .. table.getn(rows) .. "/" .. L.GALACTIC_MAX .. ")")
        tip("dp_lw_toggle", "The laws in force across the Republic: see them, propose a new one, change or repeal one. "
            .. "Every law is a Senate vote.")
        show("dp_tally", true)
        show("dp_verdict", true)
        return
    end
    for _, l in ipairs(LAYOUT.layers) do
        show(layer_shell(l.name), false)
    end
    for _, name in ipairs(CENTRE_PARTS) do
        show(name, false)
    end
    for k = 1, LAYOUT.pips do
        show("dp_pip_" .. two(k), false)
    end
    Window.law_rows = rows
    local cost = Laws.cost(d)
    for k = 1, LAYOUT.law_rows do
        local r = rows[k]
        for _, p in ipairs({"n", "s", "r", "c", "e", "f"}) do
            show("dp_lw_" .. p .. k, r ~= nil)
        end
        if r then
            local lines = Senate.wrap(r.def.short, 84)
            text("dp_lw_n" .. k, r.def.name)
            tip("dp_lw_n" .. k, r.def.name .. ": " .. r.def.text)
            text("dp_lw_s" .. k, r.left and (r.left .. " week" .. ((r.left == 1) and "" or "s") .. " left")
                or ("since week " .. Laws.week_number(r.since)))
            text("dp_lw_e" .. k, lines[1] or " ")
            text("dp_lw_f" .. k, (string.gsub(lines[2] or " ", "^%s+", "")))
            tip("dp_lw_e" .. k, r.def.text)
            tip("dp_lw_f" .. k, r.def.text)
            text("dp_lw_r" .. k, "Repeal")
            text("dp_lw_c" .. k, "Change")
            local why = Laws.blocked(d, r.key, "REPEAL")
            disable("dp_lw_r" .. k, why ~= nil)
            disable("dp_lw_c" .. k, why ~= nil)
            tip("dp_lw_r" .. k, "Propose repealing the " .. r.def.name .. " (" .. cost .. " political capital). The Senate "
                .. "votes next week." .. (why and (" " .. why) or ""))
            tip("dp_lw_c" .. k, "Propose another law in its place, in one vote (" .. cost .. " political capital)."
                .. (why and (" " .. why) or ""))
        end
    end
    show("dp_lw_empty", rows[1] == nil)
    text("dp_lw_empty", "No galactic law is in force yet.")
    local full = table.getn(rows) >= L.GALACTIC_MAX
    text("dp_lw_enact", "Enact a Law")
    disable("dp_lw_enact", full)
    tip("dp_lw_enact", full and ("Six laws are in force: change or repeal one first.")
        or ("Choose a law to put to the Senate (" .. cost .. " political capital). It votes next week."))
    local credits = Laws.last_credits(d)
    text("dp_lw_note", "The laws' effect on the treasury last week: " .. ((credits > 0) and "+" or "") .. credits .. " credits.")
    text("dp_hint", "Hover over a law for all it does.")
end

local option_cost_k

local function show_option_bar(visible)
    show("dp_m_up", visible)
    show("dp_m_down", visible)
    for k = 1, (LAYOUT.motion_segs or 0) do
        show("dp_m_seg" .. k, visible)
    end
end

local function hide_options()
    for k = 1, LAYOUT.motion_options do
        show("dp_m_opt_" .. k, false)
        show("dp_m_emblem_" .. k, false)
        for _, sfx in ipairs({"_n", "_i", "_c"}) do
            show("dp_m_ocost" .. k .. sfx, false)
        end
    end
    show_option_bar(false)
end

Window.seg_lit = {}
local function draw_option_bar()
    local segs = LAYOUT.motion_segs or 0
    local max = Window.opt_max or 0
    local shown = LAYOUT.motion_options
    local len = M.max(2, M.round(segs * shown / (shown + max)))
    local first = M.round((segs - len) * (Window.scroll or 0) / M.max(1, max)) + 1
    local last = first + len - 1
    for k = 1, segs do
        local piece = "track"
        if k >= first and k <= last then
            piece = (k == first and "thumb_top") or (k == last and "thumb_bot") or "thumb"
        elseif k == 1 then
            piece = "track_top"
        elseif k == segs then
            piece = "track_bot"
        end
        if Window.seg_lit[k] ~= piece then
            Window.seg_lit[k] = piece
            icon("dp_m_seg" .. k, "dp_scroll_" .. piece .. ".tga")
        end
        tip("dp_m_seg" .. k, "Scroll with the arrows or the mouse wheel.")
    end
end

local function fill_options(items)
    local n = LAYOUT.motion_options
    Window.opt_max = M.max(0, table.getn(items) - n)
    Window.scroll = M.max(0, M.min(Window.scroll or 0, Window.opt_max))
    Window.option_item = {}
    for k = 1, n do
        local item = items[Window.scroll + k]
        local name = "dp_m_opt_" .. k
        Window.option_item[k] = item
        show(name, item ~= nil)
        if item then
            local priced = item.capital ~= nil and item.capital > 0
            text(name, priced and ("        " .. item.label) or item.label)
            tip(name, item.tip)
        end
        disable(name, item ~= nil and item.disabled == true)
        option_cost_k(k, item and item.capital)
        show("dp_m_emblem_" .. k, item ~= nil and item.emblem ~= nil)
        if item and item.emblem then
            icon("dp_m_emblem_" .. k, item.emblem)
        end
    end
    show_option_bar(Window.opt_max > 0)
    if Window.opt_max > 0 then
        draw_option_bar()
    end
end

local function motion_lines(visible)
    show("dp_m_title", visible)
    for k = 1, LAYOUT.motion_lines do
        show("dp_m_line_" .. k, visible)
    end
end

option_cost_k = function(k, amount)
    local on = amount ~= nil and amount > 0
    for _, sfx in ipairs({"_n", "_i", "_c"}) do
        show("dp_m_ocost" .. k .. sfx, on)
    end
    if on then
        text("dp_m_ocost" .. k .. "_n", "(" .. amount)
        text("dp_m_ocost" .. k .. "_c", ")")
        tip("dp_m_ocost" .. k .. "_i", "Costs " .. amount .. " political capital.")
    end
end

local function motion_capital(d, m)
    if not m then
        return nil
    end
    if not Republic.council(d) then
        return Republic.CONFIG.SENATE.MOTION_CAPITAL
    end
    local Council = council_part()
    if not Council then
        return nil
    end
    local C = Council.CONFIG
    return C.VOTE_CAPITAL + ((m.kind == "LEVY") and C.LEVY_CAPITAL or 0)
end

local function choice_list(head, note, items)
    motion_lines(false)
    show("dp_m_call", false)
    show("dp_m_withdraw", false)
    text("dp_m_head", head)
    fill_options(items)
    text("dp_m_note", note)
end

function Window.render_left(d, profile, debate, result)
    local can, reason = Senate.can_propose(d)
    local Council = profile.council and council_part()
    if Council and Council.choosing(d) then
        local items = {}
        for _, k in ipairs(Council.constitutions()) do
            table.insert(items, {constitution = k.key, label = k.name, tip = k.name .. ": " .. k.text})
        end
        choice_list("Found the New Republic", "Choose the Republic's constitution.", items)
        show("dp_m_propose", false)
        return
    end
    show("dp_m_propose", true)
    if Council and Window.left == "constitution" and Window.founding then
        local items = {}
        for _, k in ipairs(Council.constitutions()) do
            table.insert(items, {found_with = k.key, label = k.name, tip = k.name .. ": " .. k.text})
        end
        choice_list("Found the New Republic", "Choose the constitution the Republic is founded with.", items)
        text("dp_m_propose", "Back")
        tip("dp_m_propose", "Back to the list of motions.")
        return
    end
    if Council and Window.left == "focus" then
        local items = {}
        local now = Council.focus(d)
        for _, key in ipairs(Council.CONFIG.FOCUS_ORDER) do
            local f = Council.CONFIG.FOCUS[key]
            local fans = {}
            for _, who in ipairs(f.favoured_by or {}) do
                table.insert(fans, Council.short(Council.BY_KEY[who]))
            end
            local spent = Council.focus_open and not Council.focus_open(d, key)
            table.insert(items, {focus = key, capital = Council.CONFIG.FOCUS_CAPITAL,
                                 label = f.name .. ((key == now) and " (now)" or (spent and " (used)" or "")),
                                 tip = f.name .. ": " .. f.text .. " Favoured by " .. table.concat(fans, ", ") .. "."
                                     .. (spent and " Already called once." or "")})
        end
        choice_list("The Council's Focus", "Costs " .. Council.CONFIG.FOCUS_CAPITAL .. " political capital; it can "
            .. "change once every " .. Council.CONFIG.FOCUS_WEEKS .. " weeks.", items)
        text("dp_m_propose", "Back")
        tip("dp_m_propose", "Back to the floor.")
        return
    end
    if Council and Window.left == "target" and Window.target then
        local I = Republic.part("influence")
        local action = I and I.ACTIONS[Window.target.key] and I.ACTIONS[Window.target.key][Window.target.tier]
        if action and action.target then
            local T = I.TARGETS[action.target]
            local keys = T.list(d)
            local items = {}
            for i = 1, table.getn(keys) do
                table.insert(items, {target = keys[i], label = T.label(d, keys[i]), tip = action.name .. ": " .. action.text})
            end
            choice_list(action.name, T.head .. ". " .. action.text, items)
            text("dp_m_propose", "Back")
            tip("dp_m_propose", "Back to the floor: nothing is spent.")
            return
        end
        Window.left, Window.target = "floor", nil
    end
    local SFocus = (not profile.council) and Republic.part("focus")
    if SFocus and Window.left == "sfocus" then
        local items = {}
        for _, key in ipairs(Republic.CONFIG.SENATE_FOCUS.ORDER) do
            local def = SFocus.def(key)
            local why = SFocus.blocked(d, key)
            table.insert(items, {sfocus = key, capital = SFocus.cost(d, key), label = def.name, disabled = why ~= nil,
                                 tip = def.name .. ": " .. def.text .. (SFocus.boosted(d, key) and " (Its minister "
                                     .. "makes it stronger.)" or "") .. (why and (" " .. why) or "")})
        end
        choice_list("The Senate's Focus", "Voted on at once; a focus holds " .. Republic.CONFIG.SENATE_FOCUS.WEEKS
            .. " weeks.", items)
        text("dp_m_propose", "Back")
        tip("dp_m_propose", "Back to the floor.")
        return
    end
    local Laws = (not profile.council) and laws_part()
    if Laws and (Window.left == "laws" or Window.left == "laws_change") then
        local items = {}
        local old = Window.left == "laws_change" and Window.law_old
        local op = old and "CHANGE" or "ENACT"
        for _, def in ipairs(Laws.possible(d)) do
            local why = Laws.blocked(d, def.key, op, old)
            table.insert(items, {law = def.key, capital = Laws.cost(d), label = def.name, disabled = why ~= nil,
                                 tip = def.name .. ": " .. def.text .. (why and (" " .. why) or "")})
        end
        local odef = old and Laws.def(old)
        choice_list(odef and ("In place of the " .. odef.name) or "Enact a Law",
            "The Senate votes on it at the start of next week.", items)
        text("dp_m_propose", "Back")
        tip("dp_m_propose", "Back to the floor.")
        return
    end
    if Window.left == "focus" or Window.left == "target" or Window.left == "sfocus" or Window.left == "laws"
            or Window.left == "laws_change" then
        Window.left = "floor"
    end
    if Window.left == "list" then
        motion_lines(false)
        show("dp_m_call", false)
        show("dp_m_withdraw", false)
        text("dp_m_propose", "Back")
        tip("dp_m_propose", Window.group and "Back to the list of motions." or "Back to the floor.")
        Window.render_list(d)
        return
    end
    hide_options()
    motion_lines(true)
    if Window.left == "preview" and Window.preview then
        local m = Window.preview
        text("dp_m_head", "Proposed Motion")
        text("dp_m_title", capital(m.label or m.text))
        local broken = ""
        local B = blocs_part()
        if B and not profile.council then
            for _, key in ipairs(B.broken_by(d, m, Senate.seats(d))) do
                broken = broken .. " It breaks your promise to the " .. B.name_of(key) .. "."
            end
        end
        fill_lines("dp_m_line_", LAYOUT.motion_lines, {capital(m.text) .. ".", m.tip or "",
            "As things stand: " .. result.yes .. " for, " .. result.no .. " against, " .. result.abstain
                .. (profile.council and " abstaining." or " undecided.")
                .. broken})
        show("dp_m_call", true)
        show("dp_m_withdraw", true)
        text("dp_m_call", "Propose This Motion")
        tip("dp_m_call", can and "The chamber deliberates until the start of next week, then votes." or (reason or " "))
        text("dp_m_withdraw", "Cancel")
        tip("dp_m_withdraw", "Back to the floor without proposing it.")
        text("dp_m_propose", "Choose Another Motion")
        tip("dp_m_propose", "Back to the list of motions.")
        text("dp_m_note", can and "Select a seat to see why it votes so." or (reason or " "))
        return
    end
    Window.left = "floor"
    text("dp_m_head", "The Floor of the " .. profile.name)
    text("dp_m_propose", "Propose a Motion")
    tip("dp_m_propose", can and "Put a motion of your own before the chamber." or (reason or " "))
    local pending = d.senate.bloc_pending
    if pending and not debate then
        local B = blocs_part()
        text("dp_m_title", capital(pending.motion.label or pending.motion.text))
        fill_lines("dp_m_line_", LAYOUT.motion_lines, {
            "The " .. (B and B.name_of(pending.motion.bloc) or "bloc") .. "'s motion to " .. pending.motion.text .. " passed.",
            "It takes effect at the start of next week, unless you veto it.",
            "A veto costs " .. profile.override_cost .. " cohesion, and the bloc's goodwill."})
        show("dp_m_call", true)
        text("dp_m_call", "Veto (Cohesion -" .. profile.override_cost .. ")")
        tip("dp_m_call", "Stop the bloc's motion before it takes effect. Cohesion -" .. profile.override_cost
            .. "; its worlds' opinion -" .. Republic.CONFIG.SENATE.VETO_OPINION .. ".")
        show("dp_m_withdraw", false)
        text("dp_m_note", "Another motion is on the " .. profile.name .. " floor.")
        return
    end
    if debate then
        local m = debate.motion
        text("dp_m_title", capital(m.label or m.text))
        local pressured = 0
        for _ in pairs(debate.pressured) do
            pressured = pressured + 1
        end
        local lines = {capital(m.text) .. "."}
        if debate.failed then
            table.insert(lines, "The motion failed: " .. result.yes .. " for, " .. result.no .. " against.")
            table.insert(lines, profile.council and "You may override the Council until next week, or put a new motion."
                or "You may override the chamber until the recess ends next week.")
        else
            table.insert(lines, "The chamber is deliberating and votes at the start of next week.")
            table.insert(lines, "As things stand: " .. result.yes .. " for, " .. result.no .. " against.")
        end
        if pressured > 0 then
            local who = profile.council and (pressured == 1 and " Councillor is" or " Councillors are")
                or (pressured == 1 and " senator is" or " senators are")
            table.insert(lines, pressured .. who .. " under pressure.")
        end
        fill_lines("dp_m_line_", LAYOUT.motion_lines, lines)
        if debate.failed then
            show("dp_m_call", true)
            if profile.council then
                text("dp_m_call", "Override the Council")
                tip("dp_m_call", "Act anyway. The Councillors who voted against it think less of you.")
            else
                text("dp_m_call", "Override (Cohesion -" .. profile.override_cost .. ")")
                tip("dp_m_call", "Act anyway. Cohesion falls, and the senators who voted against it think less of the government.")
            end
            text("dp_m_withdraw", "Let the Motion Lapse")
            tip("dp_m_withdraw", "Drop the failed motion.")
        else
            show("dp_m_call", false)
            text("dp_m_withdraw", "Withdraw the Motion")
            tip("dp_m_withdraw", "Drop the motion before the vote. The chamber does not go into recess.")
        end
        if (m.bloc or m.senate) and not debate.failed and not profile.council then
            text("dp_m_withdraw", "Veto the Motion")
            tip("dp_m_withdraw", "Strike the " .. (m.senate and "chamber's" or "bloc's") .. " motion before the vote. Every senator who stands for it ("
                .. result.yes .. " now) thinks less of the government (-" .. Republic.CONFIG.SENATE.VETO_OPINION .. ").")
        end
        show("dp_m_withdraw", not (m.bloc and not debate.failed and profile.council))
        text("dp_m_note", debate.failed and (profile.council and "Override it, or put a new motion." or "It lapses next week.")
            or (profile.council and "Win Councillors over before the vote." or "Win senators over before the vote."))
        return
    end
    show("dp_m_call", false)
    show("dp_m_withdraw", false)
    local last = d.senate.last_vote
    if d.senate.recess then
        text("dp_m_title", "In Recess")
        fill_lines("dp_m_line_", LAYOUT.motion_lines, {
            "The chamber has voted and sits in recess until the start of next week.",
            last and ("Last vote: the motion to " .. last.text .. " " .. (last.passed and "passed" or "failed") .. ", "
                .. last.yes .. " for and " .. last.no .. " against.") or "",
            profile.council and "You may still lobby the Councillors." or "You may still lobby senators and appeal to the blocs.",
        })
        text("dp_m_note", "No motions until next week.")
    else
        text("dp_m_title", "The Floor Is Open")
        fill_lines("dp_m_line_", LAYOUT.motion_lines, {
            "No motion is before the " .. profile.name .. ".",
            "Wars, treaties and new members need its approval.",
            "The chamber votes next week.",
            profile.council and ("Each motion costs " .. council_part().CONFIG.VOTE_CAPITAL .. " political capital; "
                .. "a tie goes your way.")
                or ("Each motion costs " .. Republic.CONFIG.SENATE.MOTION_CAPITAL .. " political capital."),
        })
        text("dp_m_note", " ")
    end
end

function Window.render_list(d)
    local motions = Senate.available_motions(d)
    Window.motions = motions
    local items = {}
    if (Window.group == "TAX" or Window.group == "SREPEAL") and not Window.sector then
        local seen = {}
        for _, m in ipairs(motions) do
            if m.group == Window.group and not seen[m.sector] then
                seen[m.sector] = true
                table.insert(items, {sector = m.sector, label = m.sector .. "  >",
                    tip = (Window.group == "TAX") and ("The " .. m.sector .. ": raise or lower its taxes.")
                        or ("The " .. m.sector .. ": the laws it passed for itself.")})
            end
        end
        text("dp_m_head", (Window.group == "TAX") and "Sector Taxes" or "Force Sector Law Repeal")
    elseif Window.group == "SREPEAL" then
        for i, m in ipairs(motions) do
            if m.group == "SREPEAL" and m.sector == Window.sector then
                table.insert(items, {motion = i, label = m.label, tip = capital(m.text) .. ". " .. (m.tip or ""),
                                     capital = m.capital})
            end
        end
        text("dp_m_head", Window.sector)
    elseif Window.group == "TAX" then
        for i, m in ipairs(motions) do
            if m.group == "TAX" and m.sector == Window.sector then
                table.insert(items, {motion = i, label = ((m.level > (m.from or 0)) and "Raise Taxes" or "Lower Taxes"),
                                     tip = capital(m.text) .. ". " .. (m.tip or ""), capital = motion_capital(d, m)})
            end
        end
        text("dp_m_head", Window.sector)
    elseif Window.group then
        for i, m in ipairs(motions) do
            if m.group == Window.group then
                local emblem = (m.target and m.target ~= "INDEPENDENT_FORCES") and ("dp_emblem_" .. string.lower(m.target) .. ".tga")
                    or (m.world and GLOBES[m.world])
                table.insert(items, {motion = i, label = m.label, emblem = emblem, tip = capital(m.text) .. ". " .. (m.tip or ""),
                                     capital = motion_capital(d, m)})
            end
        end
        for _, g in ipairs(GROUPS) do
            if g.key == Window.group then
                text("dp_m_head", g.label)
            end
        end
    else
        text("dp_m_head", "Propose a Motion")
        for _, g in ipairs(GROUPS) do
            local n = 0
            for _, m in ipairs(motions) do
                if m.group == g.key then
                    n = n + 1
                end
            end
            if n > 0 then
                table.insert(items, {group = g.key, label = g.label .. "  >", tip = g.tip .. " (" .. n .. " to choose from.)"})
            end
        end
        for i, m in ipairs(motions) do
            if not m.group then
                table.insert(items, {motion = i, label = m.label or capital(m.text), tip = capital(m.text) .. ". " .. (m.tip or ""),
                                     disabled = m.disabled, capital = motion_capital(d, m)})
            end
        end
    end
    fill_options(items)
    if table.getn(items) == 0 then
        text("dp_m_note", "No motions of this kind are possible now.")
    else
        text("dp_m_note", "Pick a motion to preview its vote.")
    end
end

local CARD = {"dp_c_ring", "dp_c_globe", "dp_c_name", "dp_c_bloc", "dp_c_opinion", "dp_c_lobby", "dp_c_promise",
              "dp_c_pressure", "dp_c_lcost_n", "dp_c_lcost_i", "dp_c_lcost_c"}

local COST_OF = {}
for k, name in ipairs({"dp_ci_act_1", "dp_ci_act_2", "dp_ci_act_3", "dp_ci_champion"}) do
    COST_OF["dp_ci_cost" .. k .. "_n"], COST_OF["dp_ci_cost" .. k .. "_i"], COST_OF["dp_ci_cost" .. k .. "_c"] = name, name, name
end
COST_OF.dp_c_lcost_n, COST_OF.dp_c_lcost_i, COST_OF.dp_c_lcost_c = "dp_c_lobby", "dp_c_lobby", "dp_c_lobby"
for k, name in pairs({[1] = "dp_bl_lobby", [3] = "dp_bl_promise", [4] = "dp_bl_aid"}) do
    COST_OF["dp_bl_c" .. k .. "_n"], COST_OF["dp_bl_c" .. k .. "_i"], COST_OF["dp_bl_c" .. k .. "_c"] = name, name, name
end
for k = 1, 12 do
    local name = "dp_m_opt_" .. k
    COST_OF["dp_m_ocost" .. k .. "_n"], COST_OF["dp_m_ocost" .. k .. "_i"], COST_OF["dp_m_ocost" .. k .. "_c"] = name, name, name
end

local function cost(prefix, amount, tip_text)
    text(prefix .. "_n", "(" .. amount)
    text(prefix .. "_c", ")")
    tip(prefix .. "_i", tip_text)
end

local function lobby_cost(visible)
    for _, sfx in ipairs({"_n", "_i", "_c"}) do
        show("dp_c_lcost" .. sfx, visible)
    end
    if visible then
        cost("dp_c_lcost", Republic.CONFIG.LOBBY_CAPITAL, "Costs " .. Republic.CONFIG.LOBBY_CAPITAL .. " political capital.")
    end
end

local INFLUENCE_PARTS = {"dp_ci_zoom", "dp_ci_globe", "dp_ci_home", "dp_ci_label_icon", "dp_ci_label", "dp_ci_value",
                         "dp_ci_frame", "dp_ci_act_1", "dp_ci_act_2", "dp_ci_act_3", "dp_ci_champion", "dp_ci_mark_1",
                         "dp_ci_mark_2", "dp_ci_mark_3"}
for k = 1, 4 do
    for _, sfx in ipairs({"_n", "_i", "_c"}) do
        table.insert(INFLUENCE_PARTS, "dp_ci_cost" .. k .. sfx)
    end
end

local function show_influence(visible)
    if not LAYOUT.influence_pips then
        return
    end
    for _, name in ipairs(INFLUENCE_PARTS) do
        show(name, visible)
    end
    for k = 1, LAYOUT.influence_pips do
        show("dp_ci_" .. k, visible)
    end
end

local function show_card(visible)
    for _, name in ipairs(CARD) do
        show(name, visible)
    end
    for k = 1, LAYOUT.card_lines do
        show("dp_c_line_" .. k, visible)
    end
    if not visible then
        show_influence(false)
        for k = 1, (LAYOUT.opinion_segs or 0) do
            show("dp_c_op" .. k, false)
        end
    end
end

local function show_chamber(visible)
    show("dp_p_head", visible)
    for k = 1, LAYOUT.dots do
        show("dp_dot_" .. two(k), visible)
    end
    for k = 1, LAYOUT.bloc_rows do
        show("dp_b_swatch_" .. k, visible)
        show("dp_b_row_" .. k, visible)
        show("dp_b_sub_" .. k, visible)
        show("dp_b_req_" .. k, visible)
        show("dp_b_appeal_" .. k, visible)
    end
    for k = 1, (LAYOUT.power_segs or 0) do
        show("dp_pw_" .. k, visible)
    end
    show("dp_b_up", visible)
    show("dp_b_down", visible)
end

local function show_assoc(visible)
    show("dp_a_head", visible)
    for k = 1, LAYOUT.assoc_rows do
        show("dp_a_globe_" .. k, visible)
        show("dp_a_row_" .. k, visible)
        show("dp_a_sub_" .. k, visible)
    end
end

function Window.render_right(d, profile, debate, motion, result)
    local mode = Window.right
    if profile.council and mode == "assoc" then
        mode, Window.right = "chamber", "chamber"
    end
    if mode == "bloc" and (profile.council or not Window.bloc) then
        mode, Window.right = "chamber", "chamber"
    end
    show_card(mode == "seat")
    show(DOTS_SHELL, mode == "chamber")
    show(BLOC_SHELL, mode == "bloc")
    show_chamber(mode == "chamber")
    show_assoc(mode == "assoc")
    if mode ~= "chamber" then
        Window.council_meters(d, false)
    end
    if profile.council then
        text("dp_c_assoc", "Intelligence")
        tip("dp_c_assoc", "Alliance Intelligence: spy networks, agents and operations. The rest of Republic Affairs "
            .. "opens when the New Republic is founded.")
        if mode == "seat" then
            Window.render_councillor(d, debate, motion, result)
        else
            Window.render_alliance(d)
        end
        text("dp_c_note", Window.feedback or ("Treasury " .. M.floor(d.human.Get_Credits())))
        return
    end
    show_influence(false)
    text("dp_c_assoc", (mode == "bloc") and "Back to the Chamber" or "Republic Affairs")
    tip("dp_c_assoc", (mode == "bloc") and "Back to the chamber's blocs." or ("The Republic's worlds and partners, "
        .. "sector taxes, the government, Republic Intelligence and the Jedi Order."))
    local occupied, territories = Republic.counts(d, Window.by_name)
    text("dp_c_note", Window.feedback or ("Occupied " .. occupied .. ", territories " .. territories .. ", treasury "
        .. M.floor(d.human.Get_Credits())))
    if mode == "assoc" then
        Window.render_assoc(d)
    elseif mode == "bloc" then
        Window.render_bloc(d)
    elseif mode == "seat" then
        Window.render_card(d, profile, debate, motion, result)
    else
        Window.render_chamber(d, profile, result)
    end
end

function Window.render_card(d, profile, debate, motion, result)
    local seat = Window.by_name[Window.selected]
    icon("dp_c_globe", GLOBES[seat.name] or "dp_globe_unknown.tga")
    local vote = result and result.worlds[seat.name]
    icon("dp_c_ring", vote and RING[vote_key(vote)] or opinion_ring(seat.opinion))
    tip("dp_c_globe", table.concat(Senate.vote_breakdown(d, seat, motion), " "))
    text("dp_c_name", d:planet_name(seat.planet))
    local senator, species = Republic.senator(d, seat.name)
    local function fit(line, most)
        return (string.len(line) <= most) and line or (string.sub(line, 1, most - 3) .. "...")
    end
    text("dp_c_bloc", fit(senator and ("Senator " .. senator .. ((species and species ~= "Human" and species ~= "Alien")
        and (" (" .. species .. ")") or "")) or seat.bloc, 30))
    local Parties = Republic.part("parties")
    local party = Parties and Parties.ruling(d, seat.name)
    local view = party and Parties.view(d, seat.name)
    text("dp_c_opinion", fit(party and party.name or seat.bloc, 30))
    Window.opinion_meter(seat.opinion, true)
    local lines = {}
    if party then
        table.insert(lines, "Bloc: " .. seat.bloc .. ".")
    end
    table.insert(lines, "Opinion of the government: " .. seat.opinion .. ".")
    if view and view.term then
        table.insert(lines, view.election .. ". " .. view.expected .. ".")
    elseif view then
        table.insert(lines, "Appointed by the world's ruler: no fixed term.")
    end
    if vote then
        table.insert(lines, "On this motion: " .. vote_words(vote) .. ((debate and debate.motion == motion
            and debate.pressured[seat.name]) and " (under pressure)" or "") .. ".")
    end
    if seat.founding then
        table.insert(lines, "A founding member: its vote counts " .. Republic.CONFIG.FOUNDING_WEIGHT .. " times.")
    end
    if seat.unrepresented > 0 then
        table.insert(lines, "Its bloc's grievance over unrepresented worlds: -" .. seat.unrepresented .. ".")
    end
    table.insert(lines, "Leans: " .. Senate.lean_text(d, seat) .. ".")
    local Desires = Republic.part("desires")
    for _, line in ipairs(Desires and Desires.lines(d, seat.name) or {}) do
        table.insert(lines, line)
    end
    local promise = d.senate.promises[seat.name]
    local wish = Senate.wish(d, seat)
    if promise then
        table.insert(lines, "You promised " .. promise.text .. ".")
    end
    table.insert(lines, "Hover over its globe for the numbers behind its vote; click it for the world.")
    fill_lines("dp_c_line_", LAYOUT.card_lines, lines)

    show("dp_c_lobby", false)
    lobby_cost(false)
    if promise then
        disable("dp_c_promise", false)
        text("dp_c_promise", "You Gave Your Word")
        tip("dp_c_promise", "Keep it: breaking it costs " .. rules().PROMISE_BROKEN_OPINION .. " opinion and "
            .. rules().PROMISE_BROKEN_STABILITY .. " cohesion.")
    else
        disable("dp_c_promise", false)
        text("dp_c_promise", "View Member World")
        tip("dp_c_promise", "Its entry among the member worlds: its government, parties (lobby them there), "
            .. "interests and demands.")
    end
    local deliberating = debate and not debate.failed
    show("dp_c_pressure", deliberating)
    if deliberating then
        text("dp_c_pressure", debate.pressured[seat.name] and "Under Pressure: Votes For" or "Pressure to Vote For")
        tip("dp_c_pressure", "The senator votes for the motion, but resents it: opinion -" .. rules().PRESSURE_OPINION
            .. ", cohesion -" .. rules().PRESSURE_STABILITY .. ".")
    end
end

function Window.opinion_meter(opinion, visible)
    local segs = LAYOUT.opinion_segs or 0
    local n = M.min(segs, M.round(M.abs(opinion or 0) * segs / 100))
    for k = 1, segs do
        show("dp_c_op" .. k, visible)
        if visible then
            local lit = (opinion or 0) >= 0 and k <= n or ((opinion or 0) < 0 and k > segs - n)
            icon("dp_c_op" .. k, lit and (((opinion or 0) >= 0) and "dp_op_bar_g.tga" or "dp_op_bar_r.tga")
                or "dp_op_bar_e.tga")
        end
    end
end

function Window.render_councillor(d, debate, motion, result)
    local Council = council_part()
    local C = Council.CONFIG
    local c = Council.BY_KEY[Window.selected]
    local op = Council.opinion(d, c.key)
    icon("dp_c_globe", c.portrait or "dp_emblem_rebel.tga")
    local vote = result and result.worlds[c.key]
    icon("dp_c_ring", vote and RING[vote_key(vote)] or opinion_ring(op))
    tip("dp_c_globe", table.concat(Council.vote_lines(d, c.key, motion), " "))
    Window.opinion_meter(0, false)
    text("dp_c_name", Council.short(c))
    text("dp_c_bloc", "Councillor for " .. Council.world_name(d, c))
    text("dp_c_opinion", "Opinion " .. op)
    local lines = {}
    if vote then
        table.insert(lines, "On this motion: " .. vote_words(vote) .. ((debate and debate.motion == motion
            and debate.pressured[c.key]) and " (under pressure)" or "") .. ".")
    end
    table.insert(lines, "Cares about " .. table.concat(c.interests or {}, " and ") .. ".")
    local m = Council.state(d).missions[c.key]
    local can, why = Council.can_request(d, c.key)
    local elsewhere = nil
    for _, other in pairs(Council.state(d).missions) do
        elsewhere = elsewhere or (not m and other)
    end
    if m then
        local left = M.max(0, M.ceil((m.expires - GetCurrentTime()) / CONFIG.WEEK_SECONDS))
        table.insert(lines, "Mission: " .. m.title .. " (" .. left .. " week" .. ((left == 1) and "" or "s") .. " left).")
    elseif can then
        table.insert(lines, "Would fund a mission for the Alliance.")
    elseif elsewhere then
        table.insert(lines, "Another mission is under way: " .. (elsewhere.title or "a Councillor's request") .. ".")
    else
        table.insert(lines, why)
    end
    table.insert(lines, "Hover over the portrait for the reasons behind their vote.")
    local I = LAYOUT.influence_pips and Republic.part("influence")
    if I then
        fill_lines("dp_c_line_", 4, lines, 31)
        for k = 5, LAYOUT.card_lines do
            show("dp_c_line_" .. k, false)
        end
        Window.render_influence(d, I, c)
    else
        fill_lines("dp_c_line_", LAYOUT.card_lines, lines, 31)
    end
    local lobbied = d.senate.lobbied[c.key]
    local wait = lobbied and (rules().LOBBY_SEAT_WEEKS * CONFIG.WEEK_SECONDS - (GetCurrentTime() - lobbied))
    if wait and wait > 0 then
        text("dp_c_lobby", "Lobbied Recently")
        lobby_cost(false)
        tip("dp_c_lobby", "You sought their counsel less than " .. rules().LOBBY_SEAT_WEEKS .. " weeks ago.")
    else
        text("dp_c_lobby", "Lobby        ")
        lobby_cost(true)
        tip("dp_c_lobby", "Seek their counsel and support: opinion +" .. rules().LOBBY_SEAT_OPINION .. ".")
    end
    disable("dp_c_promise", elsewhere ~= nil)
    if m then
        text("dp_c_promise", "Mission Under Way")
        tip("dp_c_promise", m.title .. ". Done: mandate +" .. C.MANDATE.MISSION_DONE .. ". Failed: mandate -"
            .. C.MANDATE.MISSION_FAILED .. ", and they won't fund the Alliance for a long while.")
    elseif elsewhere then
        text("dp_c_promise", "Mission Under Way")
        tip("dp_c_promise", "The Council funds one mission at a time: " .. (elsewhere.title or "a Councillor's request")
            .. ".")
    elseif can then
        text("dp_c_promise", "Ask for Funding")
        tip("dp_c_promise", Council.short(c) .. " pays " .. C.FUND_MIN .. "-" .. C.FUND_MAX .. " credits (more the more "
            .. "they trust you) for a mission of " .. C.MISSION_WEEKS .. " weeks.")
    else
        text("dp_c_promise", "No Funding Now")
        tip("dp_c_promise", why or " ")
    end
    local deliberating = debate and not debate.failed
    show("dp_c_pressure", deliberating)
    if deliberating then
        text("dp_c_pressure", debate.pressured[c.key] and "Under Pressure: Votes For" or "Pressure to Vote For")
        tip("dp_c_pressure", "They vote for the motion, but resent it: opinion -" .. rules().PRESSURE_OPINION .. ".")
    end
end

function Window.render_influence(d, I, c)
    local IC = council_part().CONFIG.INFLUENCE
    show_influence(true)
    show("dp_c_bloc", false)
    text("dp_ci_home", "Home: " .. council_part().world_name(d, c))
    icon("dp_ci_globe", GLOBES[c.world] or "dp_globe_unknown.tga")
    tip("dp_ci_zoom", "Show " .. council_part().world_name(d, c) .. " on the galaxy map.")
    tip("dp_ci_globe", "Show " .. council_part().world_name(d, c) .. " on the galaxy map.")
    local value = I.value(d, c.key)
    local held = I.home_held(d, c)
    local next_tier = nil
    for t, cost in ipairs(IC.TIERS) do
        if value < cost and not next_tier then
            next_tier = t
        end
    end
    text("dp_ci_label", "Galactic Influence")
    text("dp_ci_value", value .. " of " .. IC.MAX)
    local about = "Galactic Influence: how far " .. council_part().short(c) .. "'s word carries beyond the Council. "
        .. "A mission of theirs done +" .. IC.MISSION .. "; +" .. IC.BASE_WEEK .. " a week, +" .. IC.WEEK .. " more while "
        .. council_part().world_name(d, c) .. " is yours, an ally's or a protectorate's; Champion Their Cause +"
        .. IC.CHAMPION_GAIN .. " for " .. IC.CHAMPION_COST .. " political capital. Their actions open at "
        .. table.concat(IC.TIERS, ", ") .. " (the marks) and cost as much."
    local now = value .. " of " .. IC.MAX .. ". " .. (held and ("+" .. (IC.BASE_WEEK + IC.WEEK) .. " a week ("
        .. council_part().world_name(d, c) .. " is held).") or ("+" .. IC.BASE_WEEK .. " a week; "
        .. council_part().world_name(d, c) .. " is not yours, an ally's or a protectorate's (+" .. IC.WEEK .. " if it "
        .. "were).")) .. (next_tier and (" " .. (IC.TIERS[next_tier] - value) .. " more for their next action.")
        or " Every action is open.")
    tip("dp_ci_label", about)
    tip("dp_ci_label_icon", about)
    tip("dp_ci_value", now)
    tip("dp_ci_frame", now)
    local filled = M.max(0, M.min(LAYOUT.influence_pips, M.floor(value / IC.MAX * LAYOUT.influence_pips + 0.001)))
    for k = 1, LAYOUT.influence_pips do
        icon("dp_ci_" .. k, (k <= filled) and "dp_cm_dot_blue.tga" or "dp_cm_dot_empty.tga")
    end
    for t, action in ipairs(I.actions(c.key)) do
        local ok, why = I.can_use(d, c.key, t)
        text("dp_ci_act_" .. t, action.name .. "        ")
        cost("dp_ci_cost" .. t, IC.TIERS[t], "Costs " .. IC.TIERS[t] .. " Galactic Influence.")
        tip("dp_ci_act_" .. t, action.name .. ": " .. action.text .. " Costs " .. IC.TIERS[t] .. " Galactic Influence."
            .. (ok and "" or (" " .. (why or ""))))
        disable("dp_ci_act_" .. t, not ok)
    end
    text("dp_ci_champion", "Champion Their Cause        ")
    cost("dp_ci_cost4", IC.CHAMPION_COST, "Costs " .. IC.CHAMPION_COST .. " political capital.")
    tip("dp_ci_champion", "Put the Council's weight behind " .. council_part().short(c) .. "'s causes: Galactic "
        .. "Influence +" .. IC.CHAMPION_GAIN .. " for " .. IC.CHAMPION_COST .. " political capital.")
    disable("dp_ci_champion", value >= IC.MAX or Republic.capital(d) < IC.CHAMPION_COST)
end

local function council_meters(d, visible)
    local n, pips = LAYOUT.council_meters or 0, LAYOUT.council_meter_pips or 0
    for m = 1, n do
        local medallion = m <= 2
        show("dp_cm_label_" .. m, visible)
        show("dp_cm_value_" .. m, visible)
        if medallion then
            show("dp_cm_coin_" .. m, visible)
        else
            show("dp_cm_frame_" .. m, visible)
            for k = 1, pips do
                show("dp_cm_" .. m .. "_" .. k, visible)
            end
        end
        if (LAYOUT.council_meter_marks or {})[m] then
            show("dp_cm_mark_" .. m, visible)
        end
    end
    local marks = {}
    local which = Republic.council(d) and "COUNCIL" or "SENATE"
    for _, level in ipairs((Republic.CONFIG.COHESION_MARKS or {})[which] or {}) do
        marks[M.max(1, M.round(level / 5))] = level
    end
    for k = 1, pips do
        show("dp_cm_tsq_" .. k, visible and n >= 3 and marks[k] ~= nil)
    end
    if not visible then
        return
    end
    if not Republic.council(d) then
        return Window.senate_meters(d, pips)
    end
    local Council = council_part()
    local C = Council.CONFIG
    local R = Republic.CONFIG
    local mandate, capital, cohesion = Republic.mandate(d), Republic.capital(d), d.senate.stability or 0
    local cap_max = R.CAPITAL_MAX or 100
    local word = (cohesion >= 60) and "steady" or ((cohesion >= 30) and "uneasy" or "fractured")
    local meters = {
        {"Mandate", mandate .. " of 100", mandate / 100, "dp_cm_dpip_gold.tga",
         "Mandate " .. mandate .. " of 100: how far the galaxy sees the Alliance as a government rather than rebels. "
            .. "Below 100 every deal is harder; below " .. C.DECAY_BELOW .. " (the mark) sympathy falls everywhere. "
            .. "Liberations, alliances and the Councillors' missions raise it; invasions, revolts and losses lower it."},
        {"Political Capital", capital .. " of " .. cap_max, capital / cap_max, "dp_cm_dot_blue.tga",
         "Political capital: the Council's goodwill to spend. It grows every week (more with every 3 Sympathetic "
            .. "worlds you hold) and with the Councillors' missions. Every motion costs " .. C.VOTE_CAPITAL
            .. "; it also pays for lobbying, agents and championing a Councillor's cause."},
        {"Cohesion", cohesion .. " (" .. word .. ")", cohesion / 100,
         (cohesion < 30) and "dp_cm_seg_red.tga" or ((cohesion < 60) and "dp_cm_seg_amber.tga" or "dp_cm_seg_green.tga"),
         "Cohesion " .. cohesion .. ": the average sympathy of the worlds you hold, Hostile ones counting double. "
            .. "Below " .. C.RISE_COHESION .. " (the mark) the least content world may rise against the Alliance."},
    }
    local treaty_cost, other_cost = M.round((100 - mandate) * C.ACCEPT_TREATY), M.round((100 - mandate) * C.ACCEPT_OTHER)
    local decay = Council.sympathy_decay(d)
    local sympathetic = Council.sympathetic_worlds(d)
    local Sym = Republic.part("sym")
    local held, hostile, sum = 0, 0, 0
    for _, w in ipairs(require("eawx-plugins/new-republic/RepublicUtil").worlds_of(d.human)) do
        local v = Sym and Sym.value(d, w.key)
        if v then
            held, sum = held + 1, sum + v
            if v < R.SYMPATHY_HOSTILE then
                hostile = hostile + 1
            end
        end
    end
    local I = Republic.part("influence")
    local unity = I and I.cohesion_bonus(d) or 0
    local lost, drag = Council.cohesion_penalties(d)
    local now = {
        "Mandate " .. mandate .. " of 100. " .. ((mandate < 100) and ("Deals: treaties -" .. treaty_cost .. ", others -"
            .. other_cost .. ". ") or "No penalty in diplomacy. ") .. ((decay > 0) and ("Sympathy falls "
            .. M.round(decay * 10) / 10 .. " a week everywhere.") or "Sympathy holds steady."),
        "Political capital " .. capital .. " of " .. cap_max .. ". +" .. Council.capital_week(d) .. " a week: "
            .. C.CAPITAL_WEEK .. " from the Council, +" .. M.floor(sympathetic / C.CAPITAL_PER_SYMPATHETIC) .. " from "
            .. sympathetic .. " Sympathetic world" .. ((sympathetic == 1) and "" or "s") .. " (1 for every "
            .. C.CAPITAL_PER_SYMPATHETIC .. ")" .. ((Council.focus(d) == "SUPPORT") and (", +" .. C.SUPPORT_CAPITAL
            .. " from Gather Support") or "") .. ".",
        "Cohesion " .. cohesion .. ": " .. held .. " world" .. ((held == 1) and "" or "s") .. " with sympathy, average "
            .. ((held > 0) and M.round(sum / held) or 50) .. ((hostile > 0) and ("; " .. hostile .. " Hostile, counted "
            .. "double") or "") .. ((unity > 0) and ("; Unity of the Many +" .. unity) or "")
            .. ((lost > 0) and ("; worlds lost -" .. lost) or "") .. ((drag > 0) and ("; low mandate -" .. drag) or "")
            .. "."
            .. ((cohesion < C.RISE_COHESION) and " Risings are possible." or ""),
    }
    for m, meter in ipairs(meters) do
        text("dp_cm_label_" .. m, meter[1])
        text("dp_cm_value_" .. m, (m <= 2) and tostring(M.round(meter[3] * ((m == 1) and 100 or cap_max))) or meter[2])
        tip("dp_cm_label_" .. m, meter[5])
        tip("dp_cm_value_" .. m, now[m])
        if m <= 2 then
            tip("dp_cm_coin_" .. m, meter[5])
        else
            tip("dp_cm_frame_" .. m, now[m])
            local filled = M.max(0, M.min(pips, M.round(meter[3] * pips)))
            for k = 1, pips do
                icon("dp_cm_" .. m .. "_" .. k, (k <= filled) and meter[4] or "dp_cm_seg_empty.tga")
            end
        end
    end
end
Window.council_meters = council_meters

function Window.senate_meters(d, pips)
    local R = Republic.CONFIG
    local mandate, capital, cohesion = Republic.mandate(d), Republic.capital(d), d.senate.stability or 0
    local cap_max = R.CAPITAL_MAX or 100
    local word = (cohesion >= 60) and "steady" or ((cohesion >= 30) and "uneasy" or "fractured")
    local seats = table.getn(Window.seats or {})
    local income = M.round(Republic.capital_income(d, seats))
    local lift = Republic.cohesion_capital(d)
    local meters = {
        {"Mandate", mandate / 100, "Mandate " .. mandate .. " of 100: how far the chamber follows the government's lead. "
            .. "A senator's good opinion of you counts in its vote in proportion (100: in full; a bad opinion always "
            .. "counts in full). Granted bloc requests and integration missions raise it; failed ones and emergency "
            .. "decrees lower it.",
         "Mandate " .. mandate .. ": a senator of opinion +40 adds +" .. M.round(40 * R.SENATE.OPINION_WEIGHT * mandate / 100)
            .. " to its vote (+" .. R.SENATE.VOTE_FOR .. " carries it)."},
        {"Political Capital", capital / cap_max, "Political capital: the government's goodwill to spend. Every motion of "
            .. "yours costs " .. R.SENATE.MOTION_CAPITAL .. "; lobbying and promises to the blocs cost more. A united "
            .. "chamber adds to it every week, a divided one takes from it.",
         "Political capital " .. capital .. " of " .. cap_max .. ". " .. ((income >= 0) and "+" or "") .. income
            .. " a week" .. ((lift ~= 0) and (" (cohesion " .. ((lift > 0) and "+" or "") .. lift .. ")") or "") .. "."},
        {"Cohesion", cohesion / 100, "Cohesion " .. cohesion .. ": how united the chamber is. It settles towards a "
            .. "target that falls as the Republic grows and with every war it declares; below "
            .. rules().UNREST_STABILITY .. " undecided senators turn against your motions.",
         "Cohesion " .. cohesion .. " (" .. word .. "), settling towards " .. Republic.cohesion_target(d, seats) .. ". "
            .. (Republic.cohesion_breakdown and Republic.cohesion_breakdown(d, seats) or "")},
    }
    for m, meter in ipairs(meters) do
        text("dp_cm_label_" .. m, meter[1])
        text("dp_cm_value_" .. m, (m <= 2) and tostring(M.round(meter[2] * ((m == 1) and 100 or cap_max)))
            or (cohesion .. " (" .. word .. ")"))
        tip("dp_cm_label_" .. m, meter[3])
        tip("dp_cm_value_" .. m, meter[4])
        if m <= 2 then
            tip("dp_cm_coin_" .. m, meter[3])
        else
            tip("dp_cm_frame_" .. m, meter[4])
            local filled = M.max(0, M.min(pips, M.round(meter[2] * pips)))
            local seg = (cohesion < 30) and "dp_cm_seg_red.tga" or ((cohesion < 60) and "dp_cm_seg_amber.tga"
                or "dp_cm_seg_green.tga")
            for k = 1, pips do
                icon("dp_cm_" .. m .. "_" .. k, (k <= filled) and seg or "dp_cm_seg_empty.tga")
            end
        end
    end
end

function Window.render_alliance(d)
    local Council = council_part()
    local C = Council.CONFIG
    text("dp_p_head", "The Alliance of Free Planets")
    for k = 1, LAYOUT.dots do
        show("dp_dot_" .. two(k), false)
    end
    local m = Republic.mandate(d)
    local left = Council.patience_weeks(d)
    local ok, missing = Council.found_conditions(d)
    local open, envoys = 0, 0
    for _ in pairs(Council.state(d).missions) do
        open = open + 1
    end
    local ok_e, Envoys = pcall(require, "eawx-plugins/new-republic/RepublicEnvoys")
    if ok_e and Envoys then
        envoys = table.getn(Envoys.list(d))
    end
    council_meters(d, true)
    local rows = {
        {"The Mandate in Diplomacy", (m < 100) and ("Treaties -" .. M.round((100 - m) * C.ACCEPT_TREATY) .. ", other deals -"
            .. M.round((100 - m) * C.ACCEPT_OTHER)) or "The galaxy sees a government.",
         "Below a mandate of 100, every power is less willing to deal with the Alliance: treaties most of all."},
        {"The Galaxy's Patience", (not left and "No deadline in this region.") or (left > 0 and ("Take Coruscant: " .. left .. " weeks left."))
            or "Run out: sympathy falls fast.",
         "The galaxy demands a voice in its government, not a council of rebels. Take Coruscant and found the Senate "
            .. "there by 7 ABY, or sympathy falls sharply everywhere and the mandate with it."},
        {"Founding", (not left and "Not in this region.") or (ok and "Ready: put it to the Council.")
            or ("Needs: " .. (missing[1] or "")),
         (not left and "Without Coruscant there is no founding here: the Council governs as it is.") or ok and "Propose \"Found the New Republic\" from the floor." or ("To found the New Republic: " .. table.concat(missing, "; ") .. ".")},
        {"No Central Government", "Lost: " .. (Council.state(d).withheld or 0) .. " a week",
         "No world pays taxes to the Council: their base income, tax agencies included, is charged back every week "
            .. "(the top bar's income tooltip lists it). Trade, mining, the Councillors' funding and the war levy "
            .. "pay for the war."},
        {"Funding Missions: " .. open .. ". Delegates: " .. envoys .. " of 5", "Ask a Councillor; train Delegates at the capital.",
         "One funding mission at a time, from any Councillor; done, it raises the mandate. Delegates win worlds over, "
            .. "or warm a power's capital to the Alliance."},
    }
    Window.bloc_rows = {}
    for k = 1, (LAYOUT.power_segs or 0) do
        show("dp_pw_" .. k, false)
    end
    show("dp_b_up", false)
    show("dp_b_down", false)
    for k = 1, LAYOUT.bloc_rows do
        local r = rows[(k + 2) / 3]
        local above = rows[(k + 1) / 3]
        show("dp_b_swatch_" .. k, false)
        show("dp_b_appeal_" .. k, false)
        show("dp_b_req_" .. k, false)
        show("dp_b_row_" .. k, r ~= nil)
        show("dp_b_sub_" .. k, above ~= nil)
        if r then
            text("dp_b_row_" .. k, r[1])
            tip("dp_b_row_" .. k, r[3])
        end
        if above then
            text("dp_b_sub_" .. k, above[2])
        end
    end
end

local function cut(text_value, width)
    if string.len(text_value) <= width then
        return text_value
    end
    return string.sub(text_value, 1, width - 3) .. "..."
end

local function wrap(text_value, width)
    local lines, line = {}, ""
    for word in string.gfind(text_value, "%S+") do
        if line ~= "" and string.len(line) + 1 + string.len(word) > width then
            table.insert(lines, line)
            line = word
        else
            line = (line == "") and word or (line .. " " .. word)
        end
    end
    if line ~= "" then
        table.insert(lines, line)
    end
    return lines
end

local REQUEST_WIDTH = 40

function Window.render_chamber(d, profile, result)
    text("dp_p_head", "The Chamber")
    council_meters(d, true)
    local B = blocs_part()
    local blocs, counts, opinion, members = {}, {}, {}, {}
    for _, seat in ipairs(Window.seats) do
        if not counts[seat.bloc] then
            table.insert(blocs, seat.bloc)
            counts[seat.bloc], opinion[seat.bloc], members[seat.bloc] = 0, 0, {}
        end
        counts[seat.bloc] = counts[seat.bloc] + 1
        opinion[seat.bloc] = opinion[seat.bloc] + seat.opinion
        table.insert(members[seat.bloc], d:planet_name(seat.planet))
    end
    table.sort(blocs, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    if profile.offmap > 0 then
        table.insert(blocs, "Worlds beyond this region")
        counts["Worlds beyond this region"] = profile.offmap
    end
    if profile.military > 0 then
        table.insert(blocs, "Military")
        counts.Military = profile.military
    end
    local total = 0
    for _, bloc in ipairs(blocs) do
        total = total + counts[bloc]
    end
    local tips = {}
    for _, bloc in ipairs(blocs) do
        local def = B and B.def(B.key_of(bloc))
        local t = (def and def.text) or BLOC_TEXT[bloc] or bloc
        if members[bloc] then
            table.sort(members[bloc])
            t = bloc .. ": " .. t .. " Members: " .. table.concat(members[bloc], ", ") .. "."
            local want = B and B.interest(d, (function()
                local keys = {}
                for _, seat in ipairs(Window.seats) do
                    if seat.bloc == bloc then
                        table.insert(keys, seat.name)
                    end
                end
                return keys
            end)())
            if want then
                t = t .. " Its interest now: " .. want .. "."
            end
        end
        tips[bloc] = t
    end
    Window.bloc_tips = tips
    local floor_order, on_floor = {}, {}
    for _, seat in ipairs(Window.seats) do
        if not on_floor[seat.bloc] then
            on_floor[seat.bloc] = true
            table.insert(floor_order, seat.bloc)
        end
    end
    for _, bloc in ipairs(blocs) do
        if not on_floor[bloc] then
            table.insert(floor_order, bloc)
        end
    end
    local per_dot = M.max(1, M.floor((total + LAYOUT.dots - 1) / LAYOUT.dots))
    local dots = {}
    for _, bloc in ipairs(floor_order) do
        for _ = 1, M.max(1, M.round(counts[bloc] / per_dot)) do
            table.insert(dots, bloc)
        end
    end
    local slot_of = Window.arrange(table.getn(dots), LAYOUT.dot_rows)
    for slot = 1, LAYOUT.dots do
        local k = slot_of[slot]
        local name = "dp_dot_" .. two(slot)
        if k and dots[k] then
            icon(name, bloc_dot(dots[k]))
            tip(name, dots[k] .. ": " .. counts[dots[k]] .. " seats" .. ((per_dot > 1) and (" (one dot per " .. per_dot
                .. " seats)") or "") .. ".")
        else
            show(name, false)
        end
    end
    local segs = LAYOUT.power_segs or 0
    local acc, b_index = 0, 1
    for k = 1, segs do
        local at = (k - 0.5) * M.max(1, total) / segs
        while floor_order[b_index] and acc + counts[floor_order[b_index]] < at do
            acc = acc + counts[floor_order[b_index]]
            b_index = b_index + 1
        end
        local bloc = floor_order[b_index]
        show("dp_pw_" .. k, bloc ~= nil)
        if bloc then
            icon("dp_pw_" .. k, "dp_pw_" .. (bloc_key(bloc) or "core") .. ".tga")
            tip("dp_pw_" .. k, bloc .. ": " .. counts[bloc] .. " of " .. total .. " seats ("
                .. M.round(100 * counts[bloc] / M.max(1, total)) .. "%). " .. tips[bloc])
        end
    end
    local rows = LAYOUT.bloc_rows
    local asks = {}
    for k, bloc in ipairs(blocs) do
        local request = B and B.key_of(bloc) and B.request(d, B.key_of(bloc))
        asks[k] = request and wrap("Asks: " .. request.desire.text, REQUEST_WIDTH) or {}
    end
    local count = table.getn(blocs)
    Window.bloc_max = count - 1
    local used = -1
    for k = count, 1, -1 do
        used = used + 3 + table.getn(asks[k])
        if used > rows then
            break
        end
        Window.bloc_max = k - 1
    end
    Window.bloc_offset = M.max(0, M.min(Window.bloc_offset or 0, Window.bloc_max))
    show("dp_b_up", Window.bloc_max > 0)
    show("dp_b_down", Window.bloc_max > 0)
    tip("dp_b_up", "Scroll the blocs (or use the mouse wheel).")
    tip("dp_b_down", "Scroll the blocs (or use the mouse wheel).")
    Window.bloc_rows = {}
    local function row_comps(k)
        return "dp_b_row_" .. k, "dp_b_sub_" .. k, "dp_b_req_" .. k, "dp_b_appeal_" .. k, "dp_b_swatch_" .. k
    end
    for k = 1, rows do
        local row, sub, req, appeal, swatch = row_comps(k)
        show(row, false)
        show(sub, false)
        show(req, false)
        show(appeal, false)
        show(swatch, false)
    end
    local line = 1
    for n = Window.bloc_offset + 1, count do
        local bloc = blocs[n]
        if line + 1 + table.getn(asks[n]) > rows then
            break
        end
        do
            local row, _, _, _, swatch = row_comps(line)
            local _, sub, _, appeal = row_comps(line + 1)
            local key = B and B.key_of(bloc)
            Window.bloc_rows[line + 1] = key
            show(swatch, true)
            show(row, true)
            show(sub, true)
            icon(swatch, bloc_dot(bloc))
            text(row, bloc)
            tip(row, tips[bloc])
            local seats = counts[bloc] .. ((counts[bloc] == 1) and " seat" or " seats")
            local votes = result and result.blocs[bloc]
            if votes then
                text(sub, votes.yes .. " for, " .. votes.no .. " against, " .. votes.abstain .. " unsure.")
                tip(sub, "The " .. bloc .. " on this motion: " .. votes.yes .. " for, " .. votes.no .. " against, "
                    .. votes.abstain .. " undecided.")
            elseif opinion[bloc] then
                local promised = key and B.promised(d, key)
                text(sub, seats .. ", opinion " .. d.signed(M.round(opinion[bloc] / counts[bloc]))
                    .. (promised and (", promised " .. promised .. " wk") or "") .. ".")
            else
                text(sub, seats .. ((bloc == "Military") and ": they back wars." or ": off-map senators."))
            end
            local request = key and B.request(d, key)
            if request then
                local planet = FindPlanet(request.world)
                local where = planet and d:planet_name(planet) or request.world
                for m, words in ipairs(asks[n]) do
                    local _, _, req = row_comps(line + 1 + m)
                    show(req, true)
                    text(req, words)
                    tip(req, "The " .. bloc .. " asks, for " .. where .. ": " .. request.desire.text .. ". "
                        .. B.request_text(request) .. " Granted: its worlds' opinion +" .. Republic.CONFIG.SENATE.REQUEST_OPINION
                        .. ", mandate +" .. Republic.CONFIG.SENATE.REQUEST_MANDATE .. "; ignored, the reverse.")
                end
            end
            show(appeal, key ~= nil)
            if key then
                text(appeal, "Appeal")
                tip(appeal, "Appeal to the " .. bloc .. ": lobby it, hear its requests, promise to work with it, or "
                    .. "send aid to one of its worlds.")
            end
        end
        line = line + 3 + table.getn(asks[n])
    end
end

function Window.render_bloc(d)
    local B = blocs_part()
    local key = Window.bloc
    local def = B and B.def(key)
    local seats = Senate.seats(d)
    local names, sum = {}, 0
    local list = {}
    for name, seat in pairs(seats) do
        if B and B.key_of(seat.bloc) == key then
            table.insert(names, d:planet_name(seat.planet))
            table.insert(list, seat)
            sum = sum + seat.opinion
        end
    end
    if not def or table.getn(list) == 0 then
        Window.right, Window.bloc = "chamber", nil
        return Window.render_right(d, Senate.profile(d), d.senate.debate, nil, nil)
    end
    table.sort(names)
    table.sort(list, function(a, b) return a.opinion < b.opinion end)
    icon("dp_bl_swatch", "dp_dot_" .. def.dot .. ".tga")
    text("dp_bl_name", def.name)
    text("dp_bl_sub", table.getn(list) .. " seats, average opinion " .. d.signed(M.round(sum / table.getn(list))) .. ".")
    local keys = {}
    for _, seat in ipairs(list) do
        table.insert(keys, seat.name)
    end
    local want = B.interest(d, keys)
    local request = B.request(d, key)
    local lines = {want and ("Its interest now: " .. want .. ".") or "Its worlds want nothing in particular now."}
    if request then
        table.insert(lines, "Asks: " .. request.desire.text .. ". " .. B.request_text(request))
    else
        table.insert(lines, "No request before the government.")
    end
    local promised = B.promised(d, key)
    if promised then
        table.insert(lines, "Promised: no motion it opposes, " .. promised .. " weeks left; "
            .. (B.promise_met(d, key) and "a motion it backs has passed." or "pass a motion it backs."))
    end
    local about = def.text .. " Members: " .. table.concat(names, ", ") .. "."
    tip("dp_bl_name", about)
    tip("dp_bl_sub", about)
    local out = {}
    for _, line in ipairs(lines) do
        for _, part in ipairs(wrap(line, 37)) do
            table.insert(out, part)
        end
    end
    if table.getn(out) > LAYOUT.bloc_lines then
        out[LAYOUT.bloc_lines] = cut(out[LAYOUT.bloc_lines] .. " ...", 37)
    end
    for k = 1, LAYOUT.bloc_lines do
        text("dp_bl_l" .. k, out[k] or " ")
        tip("dp_bl_l" .. k, table.concat(lines, " ") .. " " .. about)
    end
    local S = Republic.CONFIG.SENATE
    local function action(name, label, why, tip_text)
        text(name, label)
        tip(name, tip_text .. (why and (" " .. why) or ""))
        disable(name, why ~= nil)
    end
    action("dp_bl_lobby", "Lobby the Bloc        ", B.can(d, key, "LOBBY"), "Favours and funding for its parties: "
        .. "on every world in the bloc, the party that leans to it (else the ruling party) gains " .. S.LOBBY_CLOUT
        .. " clout. Once in "
        .. S.LOBBY_WEEKS .. " weeks.")
    cost("dp_bl_c1", S.LOBBY_CAPITAL, "Costs " .. S.LOBBY_CAPITAL .. " political capital.")
    action("dp_bl_audience", "Request an Audience", B.can(d, key, "AUDIENCE"), "Hear what the bloc wants: it puts a "
        .. "request before the government for one of its worlds. Not while one is open; " .. S.AUDIENCE_WEEKS
        .. " weeks after the last one ended.")
    action("dp_bl_promise", "Promise Cooperation        ", B.can(d, key, "PROMISE"), "For " .. S.PROMISE_WEEKS
        .. " weeks you put no motion the bloc would vote against, and pass one it votes for: opinion +"
        .. S.PROMISE_OPINION .. " on its seats. Proposing a motion it opposes costs " .. S.PROMISE_BROKEN
        .. " opinion and " .. S.PROMISE_COHESION .. " cohesion; passing none it backs, " .. S.PROMISE_UNMET
        .. " opinion and " .. S.PROMISE_UNMET_COHESION .. " cohesion.")
    cost("dp_bl_c3", S.PROMISE_CAPITAL, "Costs " .. S.PROMISE_CAPITAL .. " political capital.")
    local aid_credits, aid_capital = B.aid_cost(d, key)
    action("dp_bl_aid", "Send Aid (" .. aid_credits .. " credits)        ", B.can(d, key, "AID"), "Relief and "
        .. "investment for one of its worlds: its opinion +" .. S.AID_OPINION .. ", fading over " .. S.AID_WEEKS
        .. " weeks. The larger the bloc, the more it costs. Choose the world below.")
    cost("dp_bl_c4", aid_capital, "Costs " .. aid_credits .. " credits and " .. aid_capital .. " political capital.")
    for _, sfx in ipairs({"_n", "_i", "_c"}) do
        show("dp_bl_c1" .. sfx, true)
        show("dp_bl_c3" .. sfx, true)
        show("dp_bl_c4" .. sfx, true)
    end
    local open = Window.aid_open == true
    show("dp_bl_aid_head", open)
    text("dp_bl_aid_head", "Send aid to (least content first):")
    Window.aid_worlds = {}
    for k = 1, LAYOUT.aid_rows do
        local seat = open and list[k]
        show("dp_bl_w" .. k, seat ~= nil and seat ~= false)
        show("dp_bl_wg" .. k, seat ~= nil and seat ~= false)
        if seat then
            Window.aid_worlds[k] = seat.name
            text("dp_bl_w" .. k, d:planet_name(seat.planet) .. " (" .. d.signed(seat.opinion) .. ")")
            tip("dp_bl_w" .. k, "Send " .. aid_credits .. " credits of aid to " .. d:planet_name(seat.planet) .. ".")
            icon("dp_bl_wg" .. k, GLOBES[seat.name] or "dp_globe_unknown.tga")
        end
    end
end

function Window.render_assoc(d)
    local worlds = Missions.associates(d)
    text("dp_a_head", "Associate Worlds (" .. table.getn(worlds) .. ")")
    for k = 1, LAYOUT.assoc_rows do
        local w = worlds[k]
        show("dp_a_globe_" .. k, w ~= nil)
        if w then
            icon("dp_a_globe_" .. k, GLOBES[w.world] or "dp_globe_unknown.tga")
            text("dp_a_row_" .. k, w.name .. ": contentment " .. w.content .. ", integration " .. w.integration .. "/" .. w.needed)
            text("dp_a_sub_" .. k, w.status)
        elseif k == 1 then
            text("dp_a_row_" .. k, "No associate worlds yet.")
            text("dp_a_sub_" .. k, "Worlds you protect are listed here.")
        else
            show("dp_a_row_" .. k, false)
            show("dp_a_sub_" .. k, false)
        end
    end
end

function Window.open(d)
    Window.d = d
    Window.open_now = true
    d.senate_window_open = true
    if Window.left ~= "list" and Window.left ~= "preview" then
        Window.left = "floor"
    end
    Window.render(d)
    show(SHELL, true)
    Pause.hold("senate")
    if Engine_Gui_Tick then
        Engine_Gui_Tick(1)
    end
    if Engine_Wheel_Capture then
        Engine_Wheel_Capture(1)
    end
    if Engine_Screen_Text then
        Engine_Screen_Text(0)
    end
end

function Window.close()
    show(SHELL, false)
    show(DOTS_SHELL, false)
    show(COUNCIL_SHELL, false)
    show(BLOC_SHELL, false)
    show(LAWS_SHELL, false)
    for _, l in ipairs(LAYOUT.layers) do
        show(layer_shell(l.name), false)
    end
    Window.open_now = false
    Window.feedback = nil
    Window.left, Window.right, Window.selected, Window.page, Window.group, Window.preview = "floor", "chamber", nil, 1, nil, nil
    Window.scroll, Window.sector, Window.bloc, Window.aid_open = 0, nil, nil, false
    Window.centre, Window.law_old = "chamber", nil
    if Window.d then
        Window.d.senate_window_open = false
    end
    Pause.release("senate")
    local ok_d, Diplomacy_Window = pcall(require, "eawx-plugins/diplomacy/DiplomacyWindow")
    local ok_r, Republic_Window = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
    local others = (ok_d and type(Diplomacy_Window) == "table" and (Diplomacy_Window.open_now
        or Diplomacy_Window.tick_hold or Diplomacy_Window.flash_hold))
        or (ok_r and type(Republic_Window) == "table" and Republic_Window.open_now)
    if Engine_Gui_Tick and not others then
        Engine_Gui_Tick(0)
    end
    if Engine_Wheel_Capture and not (ok_d and type(Diplomacy_Window) == "table" and Diplomacy_Window.open_now)
            and not (ok_r and type(Republic_Window) == "table" and Republic_Window.open_now) then
        Engine_Wheel_Capture(0)
    end
    if Engine_Screen_Text then
        Engine_Screen_Text(1)
    end
end

function Window.tick()
    if not (Window.open_now and Engine_Mouse and Engine_Screen_Size) then
        return
    end
    local mx, my, _, wheel = Engine_Mouse()
    if not wheel or wheel == 0 then
        return
    end
    local w, h = Engine_Screen_Size()
    if not h or h <= 0 then
        return
    end
    local scale = h / 768
    local x = (mx - w / 2) / scale
    local changed = false
    if x < -230 and (Window.opt_max or 0) > 0 then
        local v = M.max(0, M.min(Window.opt_max, (Window.scroll or 0) - M.round(wheel)))
        changed, Window.scroll = v ~= Window.scroll, v
    elseif x > 230 and Window.right == "chamber" and (Window.bloc_max or 0) > 0 then
        local v = M.max(0, M.min(Window.bloc_max, (Window.bloc_offset or 0) - M.round(wheel)))
        changed, Window.bloc_offset = v ~= Window.bloc_offset, v
    end
    if changed and Window.d then
        Window.render(Window.d)
    end
end

function Window.update(d)
    if Window.open_now and GetCurrentTime() >= (Window.next_refresh or 0) then
        Window.next_refresh = GetCurrentTime() + 3
        Window.render(d)
    end
end

local function say(d, ok, message)
    Window.feedback = message
end

function Window.click(d, name, button)
    if Engine_Log then
        Engine_Log("SENATE WINDOW " .. tostring(button) .. " click " .. tostring(name))
    end
    if string.find(name, "^b_senate_panel") then
        if button ~= "right" and d:senate_active() then
            if Window.open_now then
                Window.close()
            else
                Window.open(d)
            end
        end
        return
    end
    if name == "dp_senate_close" then
        Window.close()
        return
    end
    if not Window.open_now then
        return
    end
    Window.feedback = nil
    name = COST_OF[name] or name
    local _, _, slot = string.find(name, "^dp_seat_(%a%d%d%d)$")
    if not slot then
        _, _, slot = string.find(name, "^dp_ring_(%a%d%d%d)$")
    end
    if not slot then
        local _, _, k = string.find(name, "^dp_cn_seat_(%d+)$")
        if not k then
            _, _, k = string.find(name, "^dp_cn_ring_(%d+)$")
        end
        slot = k and ("cn" .. k)
    end
    local Council = Republic.council(d) and council_part()
    if button == "right" then
        if slot or name == "dp_c_globe" or name == "dp_c_ring" then
            Window.selected = nil
            Window.right = "chamber"
        end
    elseif slot then
        local seat = Window.slot_seat and Window.slot_seat[slot]
        if seat and seat == Window.selected then
            Window.selected = nil
            Window.right = "chamber"
        elseif seat then
            Window.selected = seat
            Window.right = "seat"
        end
    elseif name == "dp_view" then
        Window.view = (Window.view == "blocs") and "loyalty" or "blocs"
    elseif name == "dp_m_up" or name == "dp_m_down" then
        local v = (Window.scroll or 0) + ((name == "dp_m_up") and -1 or 1)
        Window.scroll = M.max(0, M.min(Window.opt_max or 0, v))
    elseif string.find(name, "^dp_m_seg%d+$") then
        local k = tonumber(string.sub(name, 9))
        Window.scroll = M.round((Window.opt_max or 0) * (k - 1) / M.max(1, (LAYOUT.motion_segs or 1) - 1))
    elseif name == "dp_b_up" or name == "dp_b_down" then
        local v = (Window.bloc_offset or 0) + ((name == "dp_b_up") and -1 or 1)
        Window.bloc_offset = M.max(0, M.min(Window.bloc_max or 0, v))
    elseif name == "dp_bl_lobby" and Window.bloc then
        say(d, blocs_part().lobby(d, Window.bloc, Senate.seats(d)))
    elseif name == "dp_bl_audience" and Window.bloc then
        say(d, blocs_part().audience(d, Window.bloc, Senate.seats(d)))
    elseif name == "dp_bl_promise" and Window.bloc then
        say(d, blocs_part().promise(d, Window.bloc, Senate.seats(d)))
    elseif name == "dp_bl_aid" and Window.bloc then
        local why = blocs_part().can(d, Window.bloc, "AID")
        if why then
            say(d, false, why)
        else
            Window.aid_open = not Window.aid_open
        end
    elseif string.find(name, "^dp_bl_w%d+$") and Window.bloc then
        local world = Window.aid_worlds and Window.aid_worlds[tonumber(string.sub(name, 8))]
        if world then
            say(d, blocs_part().aid(d, Window.bloc, world))
            Window.aid_open = false
        end
    elseif name == "dp_sf_focus" and not Council then
        local Focus = Republic.part("focus")
        if Focus and Focus.active(d) then
            say(d, false, Focus.blocked(d, "FLEET"))
        elseif Focus then
            local can, reason = Senate.can_propose(d)
            if can then
                Window.left = (Window.left == "sfocus") and "floor" or "sfocus"
                Window.page, Window.scroll = 1, 0
            else
                say(d, false, reason)
            end
        end
    elseif name == "dp_lw_toggle" and not Council then
        Window.centre = (Window.centre == "laws") and "chamber" or "laws"
        if Window.centre == "chamber" and (Window.left == "laws" or Window.left == "laws_change") then
            Window.left = "floor"
        end
    elseif name == "dp_lw_enact" and not Council then
        local Laws = laws_part()
        local can, reason = Senate.can_propose(d)
        if Laws and Laws.galactic_count(d) >= Laws.CONFIG.GALACTIC_MAX then
            say(d, false, "Six laws are in force: change or repeal one first.")
        elseif not can then
            say(d, false, reason)
        else
            Window.left, Window.law_old = (Window.left == "laws") and "floor" or "laws", nil
            Window.page, Window.scroll = 1, 0
        end
    elseif string.find(name, "^dp_lw_[rc]%d$") and not Council then
        local Laws = laws_part()
        local r = Window.law_rows and Window.law_rows[tonumber(string.sub(name, 8))]
        if Laws and r then
            local why = Laws.blocked(d, r.key, "REPEAL")
            if why then
                say(d, false, why)
            elseif string.sub(name, 7, 7) == "r" then
                local ok, reason = Senate.propose_from_window(d, Laws.motion(d, r.key, "REPEAL"))
                say(d, ok, ok and ("Debate opened: repeal the " .. r.def.name .. ".") or reason)
            else
                Window.left, Window.law_old = "laws_change", r.key
                Window.page, Window.scroll = 1, 0
            end
        end
    elseif name == "dp_m_propose" then
        if Window.left == "laws" or Window.left == "laws_change" then
            Window.left, Window.law_old = "floor", nil
        elseif Window.left == "focus" or Window.left == "target" or Window.left == "sfocus" then
            Window.left, Window.target = "floor", nil
        elseif Window.left == "constitution" then
            Window.left, Window.founding = "list", nil
        elseif Window.left == "list" then
            if (Window.group == "TAX" or Window.group == "SREPEAL") and Window.sector then
                Window.sector = nil
            elseif Window.group then
                Window.group = nil
            else
                Window.left = "floor"
            end
        elseif Window.left == "preview" then
            Window.left = "list"
        else
            local can, reason = Senate.can_propose(d)
            if can then
                Window.left, Window.group = "list", nil
            else
                say(d, false, reason)
            end
        end
        Window.page, Window.scroll = 1, 0
    elseif name == "dp_cn_focus" and Council then
        if Council.focus(d) and Council.focus_weeks_left(d) > 0 then
            return
        end
        Window.left = (Window.left == "focus") and "floor" or "focus"
    elseif string.find(name, "^dp_m_opt_") then
        local item = Window.option_item and Window.option_item[tonumber(string.sub(name, 10))]
        if item and item.constitution and Council then
            if Council.found(d, item.constitution) then
                Window.left, Window.right, Window.selected = "floor", "chamber", nil
                Window.close()
                return
            end
        elseif item and item.target and Window.target and Council then
            local I = Republic.part("influence")
            local t = Window.target
            Window.left, Window.target = "floor", nil
            if I then
                say(d, I.use(d, t.key, t.tier, item.target))
            end
        elseif item and item.law and not Council then
            local Laws = laws_part()
            local old = Window.left == "laws_change" and Window.law_old or nil
            local op = old and "CHANGE" or "ENACT"
            local why = Laws and Laws.blocked(d, item.law, op, old)
            if why then
                say(d, false, why)
            elseif Laws then
                local motion = Laws.motion(d, item.law, op, old)
                local ok, reason = Senate.propose_from_window(d, motion)
                Window.left, Window.law_old = "floor", nil
                say(d, ok, ok and ("Debate opened: " .. motion.text .. ".") or reason)
            end
        elseif item and item.sfocus and not Council then
            local Focus = Republic.part("focus")
            local why = Focus and Focus.blocked(d, item.sfocus)
            if why then
                say(d, false, why)
            elseif Focus then
                local ok, reason = Senate.propose_from_window(d, Focus.motion(d, item.sfocus))
                Window.left = "floor"
                say(d, ok, ok and ("Debate opened: " .. Focus.def(item.sfocus).name .. ".") or reason)
            end
        elseif item and item.focus and Council then
            local ok, why = Council.set_focus(d, item.focus)
            say(d, ok, why)
            if ok then
                Window.left = "floor"
            end
        elseif item and item.sector then
            Window.sector, Window.scroll = item.sector, 0
        elseif item and item.group then
            Window.group, Window.page, Window.scroll, Window.sector = item.group, 1, 0, nil
        elseif item and item.disabled then
            say(d, false, item.tip)
        elseif item and item.found_with and Window.founding and Council then
            local motion = {}
            for k, v in pairs(Window.founding) do
                motion[k] = v
            end
            local chosen = nil
            for _, c in ipairs(Council.constitutions()) do
                if c.key == item.found_with then
                    chosen = c
                end
            end
            motion.constitution = item.found_with
            motion.text = "found the New Republic (" .. (chosen and chosen.name or item.found_with) .. ")"
            motion.label = "Found the New Republic: " .. (chosen and chosen.name or item.found_with)
            Window.preview, Window.founding, Window.left = motion, nil, "preview"
        elseif item and item.motion and Window.motions[item.motion] then
            local motion = Window.motions[item.motion]
            if motion.kind == "FOUND" and Council then
                Window.founding, Window.left = motion, "constitution"
            else
                Window.preview = motion
                Window.left = "preview"
            end
        end
    elseif name == "dp_m_call" then
        local debate = d.senate.debate
        if Window.left == "floor" and d.senate.bloc_pending and not debate then
            say(d, Senate.veto(d))
        elseif Window.left == "preview" and Window.preview then
            local ok, reason = Senate.propose_from_window(d, Window.preview)
            if ok then
                Window.preview, Window.left, Window.group, Window.sector = nil, "floor", nil, nil
                say(d, true, "The motion is before the chamber.")
            else
                say(d, false, reason)
            end
        elseif debate and debate.failed then
            Senate.override_debate(d)
            say(d, true, "You overrode the chamber.")
        end
    elseif name == "dp_m_withdraw" then
        if Window.left == "preview" then
            Window.preview, Window.left = nil, "floor"
        elseif d.senate.debate and (d.senate.debate.motion.bloc or d.senate.debate.motion.senate) and not d.senate.debate.failed
                and not Council then
            say(d, Senate.veto_debate(d))
        else
            Senate.withdraw(d)
        end
    elseif name == "dp_c_assoc" and Window.right == "bloc" then
        Window.right, Window.bloc, Window.aid_open = "chamber", nil, false
    elseif name == "dp_c_assoc" then
        local W = republic_window()
        if W then
            Window.close()
            W.open(d, Council and "intelligence" or "members")
            return
        end
        Window.right = (Window.right == "assoc") and "chamber" or "assoc"
    elseif string.find(name, "^dp_ci_act_%d$") and Window.selected and Council then
        local I = Republic.part("influence")
        local tier = tonumber(string.sub(name, 11))
        local action = I and I.ACTIONS[Window.selected] and I.ACTIONS[Window.selected][tier]
        if action then
            local ok, why = I.can_use(d, Window.selected, tier)
            if not ok then
                say(d, false, why)
            elseif action.target then
                Window.left, Window.target, Window.page, Window.scroll = "target", {key = Window.selected, tier = tier}, 1, 0
            else
                say(d, I.use(d, Window.selected, tier))
            end
        end
    elseif name == "dp_ci_champion" and Window.selected and Council then
        local I = Republic.part("influence")
        if I then
            say(d, I.champion(d, Window.selected))
        end
    elseif name == "dp_ci_zoom" and Window.selected and Council then
        local c = Council.BY_KEY[Window.selected]
        local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
        local event = plot and plot.Get_Event("Diplomacy_Window_Camera")
        if c and event and FindPlanet(c.world) then
            event.Set_Reward_Parameter(0, c.world)
            Window.close()
            Story_Event("DIPLOMACY_WINDOW_CAMERA")
            return
        end
        say(d, false, "Their home world is not in this part of the galaxy.")
    elseif name == "dp_c_lobby" and Window.selected then
        say(d, Senate.lobby_seat(d, Window.selected))
    elseif name == "dp_c_promise" and Window.selected and Council then
        say(d, Council.request(d, Window.selected))
    elseif name == "dp_c_promise" and Window.selected and d.senate.promises[Window.selected] then
        say(d, Senate.promise(d, Window.selected))
    elseif (name == "dp_c_promise" or name == "dp_c_globe" or name == "dp_c_ring") and Window.selected and not Council then
        local W = republic_window()
        if W and W.open_member then
            local world = Window.selected
            Window.close()
            W.open_member(d, world)
            return
        end
    elseif name == "dp_c_pressure" and Window.selected then
        say(d, Senate.pressure(d, Window.selected))
    elseif string.find(name, "^dp_b_appeal_") then
        local key = Window.bloc_rows and Window.bloc_rows[tonumber(string.sub(name, 13))]
        if key and blocs_part() and not Council then
            Window.right, Window.bloc, Window.aid_open, Window.selected = "bloc", key, false, nil
        end
    end
    Window.render(d)
end

function Window.listen(d)
    DiplomacyGuiClick = function(name, button)
        name = require("eawx-plugins/diplomacy/DiplomacyClicks").name(name)
        if not name then
            return
        end
        local ok, err = pcall(Window.click, d, name, button)
        if not ok and Engine_Log then
            Engine_Log("SENATE WINDOW click error: " .. tostring(err))
        end
    end
    if Engine_Gui_Listen then
        Engine_Gui_Listen("dp_,b_senate_panel")
    end
end

return Window
