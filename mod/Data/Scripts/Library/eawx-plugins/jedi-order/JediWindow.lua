local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local J = require("eawx-plugins/jedi-order/JediConfig")
local Order = require("eawx-plugins/jedi-order/JediOrder")
local ok_g, GLOBES = pcall(require, "eawx-plugins/diplomacy/DiplomacyGlobes")
GLOBES = (ok_g and type(GLOBES) == "table") and GLOBES or {}

local JW = {page = "order", sel = nil, flow = nil, preset = nil, scroll = 0, list = 0, strip = 0, go = 0, bpage = 0,
            hits = {}, run_sel = nil}
local CARD_LINE = 54
local PANEL_LINE = 58
local GOLD_C, PALE_C, GREY_C, WHITE_C = {0.92, 0.82, 0.59}, {0.84, 0.86, 0.9}, {0.5, 0.5, 0.53}, {1, 1, 1}

local function Republic()
    return require("eawx-plugins/new-republic/Republic")
end

function JW.reset()
    JW.page, JW.sel, JW.flow, JW.preset, JW.run_sel = "order", nil, nil, nil, nil
    JW.scroll, JW.list, JW.strip, JW.go, JW.bpage = 0, 0, 0, 0, 0
end

function JW.dismiss()
    if JW.sel and string.sub(JW.sel, 1, 2) == "P_" then
        JW.sel = nil
        return true
    end
    return false
end

local function wrap(text, out, width)
    local rest = text
    while string.len(rest) > width do
        local cut = width
        while cut > 1 and string.sub(rest, cut, cut) ~= " " do
            cut = cut - 1
        end
        if cut <= 1 then
            cut = width
        end
        table.insert(out, string.sub(rest, 1, cut - 1))
        rest = string.sub(rest, cut + 1)
    end
    table.insert(out, rest)
    return out
end

local function weeks_word(w)
    if w == M.floor(w) then
        return w .. ((w == 1) and " week" or " weeks")
    end
    return string.format("%.1f", w) .. " weeks"
end

local function icon_of(p)
    if p.kind == "hero" then
        local entry = Order.HERO[p.key]
        if entry and entry.icon then
            return entry.icon
        end
    end
    if p.rank <= J.INITIATE then
        return J.INITIATE_ICON
    end
    local female = p.female or (p.female == nil and p.kind ~= "hero" and false)
    if p.rank >= J.KNIGHT and p.path then
        return (female and J.PATH_ICON_F or J.PATH_ICON_M)[p.path] or J.STUDENT_ICON
    end
    return female and J.STUDENT_ICON_F or J.STUDENT_ICON
end

local function grey_of(icon)
    return (string.gsub(icon, "%.tga$", "_g.tga"))
end

local function away(p)
    return p.mission ~= nil or p.along_of ~= nil or p.command ~= nil or p.post ~= nil or p.trials_until ~= nil
end

local function world_word(d, world)
    local planet = world and FindPlanet(world)
    return planet and d:planet_name(planet) or nil
end

local function where_word(d, s, p)
    local leader = p.along_of and Order.get(s, p.along_of) or p
    local m = leader.mission
    if m then
        local name = Order.mission_name(m)
        local at = world_word(d, m.world)
        if p.along_of then
            name = "With " .. leader.name .. ": " .. name
        end
        if m.stage == "leave" then
            return name .. ", leaving the Temple"
        elseif m.stage == "out" then
            return name .. (at and (", flying to " .. at) or "")
        elseif m.stage == "there" then
            return name .. (at and (" at " .. at) or "")
        end
        return name .. ", flying home"
    elseif p.command then
        return "With the fleet" .. (world_word(d, p.command.world) and (" at " .. world_word(d, p.command.world)) or "")
    elseif p.post then
        return Order.post_word(d, p) or "Posted"
    elseif (p.wounded or 0) > s.week then
        return "Recovering"
    elseif (p.counsel_until or 0) > s.week then
        return "In counsel"
    elseif (p.retreat_until or 0) > s.week then
        return "On retreat"
    elseif (p.vigil_until or 0) > s.week then
        return "Keeping the Vigil"
    elseif Order.seat_of(s, p) then
        return "On the Council"
    end
    return "At the Temple"
end

local function rank_path(p)
    return Order.rank_name(p) .. ((p.path and p.rank >= J.KNIGHT) and (", " .. J.PATHS[p.path]) or "")
end

function JW.header(d)
    local s = Order.state(d)
    return {
        {"Knowledge " .. s.knowledge, "Knowledge " .. s.knowledge .. ": what has been recovered of the old Order. Masters at "
            .. "the Temple add 1 a week each, Recover the Lore adds more. It pays for Teachings."},
        {"Trust " .. s.trust, "Public Trust " .. s.trust .. " of 100: how the galaxy sees the Jedi. Moves with their "
            .. "results. It makes missions likelier to succeed. At " .. J.TRUST_HIGH .. "+ Mandate rises by 1 a month; below "
            .. J.TRUST_LOW .. " the Senate can vote to restrain the Order."},
        {"Shadow of the Dark Side: " .. Order.shadow_word(s), "The Shadow of the Dark Side over the Order: " .. Order.shadow_word(s)
            .. ". " .. (Order.shadow_known and Order.shadow_known(s) and "The Order sees it clearly for now. " or "The Order "
            .. "cannot see its own Shadow until a Disturbance in the Force is followed to its source (a lead). ")
            .. "It is the darkness in its Jedi and what the Order has let pass (dark leads left alone, falls). Uneasy: dark "
            .. "leads come more often. Disturbance: slower training, Public Trust falls, students darken. Dark: missions "
            .. "fail more, trust falls faster, the darkest are pushed to the edge, and the Senate may restrain the Order. "
            .. "Each Jedi's own shadow is hidden until an Intuitive Master or the Grand Master senses it. The Vigil, Cleanse "
            .. "a Dark Site, ending threats, rest and counsel lift it."},
    }
end

local function hide_med(G, base)
    G.show(base, false)
    G.show(base .. "_f", false)
    G.show(base .. "_n1", false)
    G.show(base .. "_n2", false)
    G.show(base .. "_n3", false)
end

local function draw_med(G, base, p, frame, tip_text, key, name_color, status)
    local first, rest = p.name, " "
    local at = string.find(p.name, " ", 1, true)
    if at then
        first, rest = string.sub(p.name, 1, at - 1), string.sub(p.name, at + 1)
    end
    local off = away(p)
    G.show(base, true)
    G.show(base .. "_f", true)
    G.show(base .. "_n1", true)
    G.show(base .. "_n2", true)
    G.show(base .. "_n3", (status or off) and true or false)
    G.icon(base, off and grey_of(icon_of(p)) or icon_of(p))
    G.icon(base .. "_f", off and "dp_nr_jt_f1.tga" or frame)
    G.text(base .. "_n1", first)
    G.text(base .. "_n2", rest)
    G.color(base .. "_n1", off and GREY_C or (name_color or PALE_C))
    G.color(base .. "_n2", off and GREY_C or (name_color or PALE_C))
    if status or off then
        G.text(base .. "_n3", status or "On Mission")
    end
    G.tip(base, tip_text)
    G.tip(base .. "_f", tip_text)
    JW.hits[base] = key
end

local function frame_of(s, p, offered)
    if offered then
        return "dp_nr_jt_foffer.tga"
    elseif JW.sel == "P_" .. p.id then
        return "dp_nr_jt_fsel.tga"
    elseif p.sign and p.sensed then
        return "dp_nr_jt_fdark.tga"
    end
    return "dp_nr_jt_f" .. M.min(p.rank, 5) .. ".tga"
end

local function lineages(s)
    local groups, knights, padawans = {}, {}, {}
    local by_id = {}
    for _, p in ipairs(s.roster) do
        if p.rank == J.MASTER then
            local g = {master = p, k = {}, p = {}}
            table.insert(groups, g)
            by_id[p.id] = g
        end
    end
    for _, p in ipairs(s.roster) do
        if p.rank == J.KNIGHT or p.rank == J.PADAWAN then
            local g = p.master and by_id[p.master]
            if g then
                table.insert((p.rank == J.KNIGHT) and g.k or g.p, p)
            else
                table.insert((p.rank == J.KNIGHT) and knights or padawans, p)
            end
        end
    end
    return groups, knights, padawans
end

local function slot_x(L, slot)
    return L.gx + (slot - 1) * L.gstep
end

local function initiate_x(L, k)
    local slot = M.floor((k + 1) / 2)
    return slot_x(L, slot) + ((k - 2 * M.floor(k / 2) == 1) and -L.sstep / 2 or L.sstep / 2), slot
end

local function card_rect(L)
    if JW.card_at then
        return {x = L.card_x[JW.card_at[1]], y = L.card_y[JW.card_at[2]], w = L.card_w, h = L.card_h}
    end
    return nil
end

local function covered(rect, x, y, w, h)
    if not rect then
        return false
    end
    return M.abs(x - rect.x) < (w + rect.w) / 2 and M.abs(y - rect.y) < (h + rect.h) / 2
end

local function med_covered(L, rect, x, y)
    return covered(rect, x, y - 13, 2 * L.r + 10, 2 * L.r + 32)
end

local function offered(s, p)
    local flow = JW.flow
    if flow and flow.student_of then
        return Order.untakeable(s, p) == nil and not away(p)
    elseif flow and flow.watch_of then
        return p.rank >= J.MASTER and p.id ~= flow.watch_of and not away(p)
    end
    return false
end

local function person_tip(d, s, p, hint)
    local parts = {Order.label(p) .. ": " .. rank_path(p) .. ", " .. p.species .. " of " .. p.home .. "."}
    table.insert(parts, "Doing: " .. where_word(d, s, p) .. ".")
    local master = p.master and Order.get(s, p.master)
    if master then
        table.insert(parts, "Master: " .. master.name .. ".")
    end
    local students = {}
    for _, st in ipairs(Order.students(s, p)) do
        table.insert(students, st.name)
    end
    if students[1] then
        table.insert(parts, "Students: " .. table.concat(students, ", ") .. ".")
    end
    local traits = {}
    for _, t in ipairs(p.traits or {}) do
        if J.TRAITS[t] then
            table.insert(traits, J.TRAITS[t].name)
        end
    end
    if traits[1] then
        table.insert(parts, "Traits: " .. table.concat(traits, ", ") .. ".")
    end
    table.insert(parts, "Potential: " .. J.POTENTIAL[M.max(1, M.min(3, p.potential))].name .. ".")
    if p.rank == J.PADAWAN then
        table.insert(parts, "Training XP " .. M.floor(p.xp or 0) .. " of " .. J.XP_KNIGHT .. ".")
    elseif p.rank == J.KNIGHT then
        table.insert(parts, "Missions " .. p.missions .. " of " .. J.TRIAL_MISSIONS .. ", XP " .. M.floor(p.xp or 0) .. " of " .. J.XP_MASTER .. ".")
    elseif p.rank >= J.MASTER then
        table.insert(parts, "Missions done: " .. p.missions .. ".")
    end
    if p.craft then
        table.insert(parts, "Flies: " .. Order.craft_name(p) .. ".")
    end
    if p.sensed or Order.learned(s, "SEEKER", 3) then
        table.insert(parts, "Darkness " .. M.round(p.shadow) .. " of 100" .. (p.sensed and " (sensed)." or "."))
    end
    table.insert(parts, Order.mood(s, p))
    if hint then
        table.insert(parts, hint)
    else
        table.insert(parts, "Click for more.")
    end
    return table.concat(parts, " ")
end

function JW.box_rows(L, knights, padawans)
    local per = 3 * L.free_n
    local all = {}
    for _, q in ipairs(knights) do
        table.insert(all, q)
    end
    for _, q in ipairs(padawans) do
        table.insert(all, q)
    end
    local rows, spill = {k = {}, p = {}, x = {}}, {}
    for i = JW.bpage * per + 1, M.min(table.getn(all), (JW.bpage + 1) * per) do
        local q = all[i]
        local own = rows[(q.rank == J.KNIGHT) and "k" or "p"]
        if table.getn(own) < L.free_n then
            table.insert(own, q)
        else
            table.insert(spill, q)
        end
    end
    for _, q in ipairs(spill) do
        for _, r in ipairs({"x", "k", "p"}) do
            if q and table.getn(rows[r]) < L.free_n then
                table.insert(rows[r], q)
                q = nil
            end
        end
    end
    return rows
end

local function places(L, s, groups, knights, padawans)
    local out = {}
    local head = Order.head(s)
    if head then
        out[head.id] = {x = L.gm_x, y = L.gm, tier = "gm", where = "gm"}
    end
    for slot = 1, L.groups do
        local g = groups[slot + JW.scroll]
        if g then
            local cx = slot_x(L, slot)
            out[g.master.id] = {x = cx, y = L.m, tier = "m", slot = slot}
            for tier, list in pairs({k = g.k, p = g.p}) do
                local n = table.getn(list)
                for j, q in ipairs(list) do
                    out[q.id] = {x = (n == 1) and cx or (cx + (j - 1.5) * L.sstep), y = L[tier], tier = tier, slot = slot}
                end
            end
            if table.getn(g.k) == 1 and table.getn(g.p) == 1 then
                out[g.k[1].id].x, out[g.p[1].id].x = cx - L.sstep / 2, cx + L.sstep / 2
            end
        end
    end
    for row, list in pairs(JW.box_rows(L, knights, padawans)) do
        for n, q in pairs(list) do
            out[q.id] = {x = L.free_x + (n - 1) * L.free_step, y = L["box_" .. row], tier = (q.rank == J.KNIGHT) and "k" or "p",
                         where = "box", n = n}
        end
    end
    local k = 0
    for _, p in ipairs(s.roster) do
        if p.rank == J.INITIATE and k < L.ini then
            k = k + 1
            local x, slot = initiate_x(L, k)
            out[p.id] = {x = x, y = L.i, tier = "i", slot = slot, n = k}
        end
    end
    return out
end

local function anchor_for(at)
    local row = ((at.tier == "gm") and 1) or ((at.tier == "m" or at.tier == "k") and 2) or 3
    if at.where == "gm" then
        return {1, 1}
    elseif at.where == "box" then
        return {4, row}
    end
    local centre = (at.slot <= 3) and (at.slot + 2) or (at.slot - 2)
    return {centre - 1, row}
end

local function card_actions(d, s, p)
    local out = {}
    local gone = away(p)
    local function add(label, key, tip, off, why)
        if gone then
            off, why = true, p.name .. " is away: " .. where_word(d, s, p) .. "."
        end
        table.insert(out, {label = label, key = key, tip = off and (why or tip) or tip, off = off})
    end
    if p.post then
        table.insert(out, {label = "Recall from Post", key = "jw_unpost", tip = p.name .. " returns to the Temple."})
    elseif gone then
        table.insert(out, {label = "Find on Map", key = "jw_find", tip = "Show where " .. p.name .. " is on the galaxy map."})
    end
    local gm = Order.head(s)
    if gm and gm ~= p and not p.post then
        local why = Order.vision_blocked(d, s, p)
        table.insert(out, {label = "Seek a Vision", key = "jw_vision", off = why ~= nil, tip = why or (gm.name
            .. " seeks a vision of " .. p.name .. ": their darkness and potential laid bare, and a lead, a warning or a lesson.")})
    end
    if (p.wounded or 0) > s.week and Order.seated_in(s, "HEALING") then
        local why = Order.trance_blocked(d, s, p)
        table.insert(out, {label = "Healing Trance", key = "jw_trance", off = why ~= nil, tip = why or ("The Master of "
            .. "Healing heals " .. p.name .. " at once and lifts their shadow. Once in " .. J.TRANCE_EVERY .. " weeks.")})
    end
    if p.rank >= J.KNIGHT then
        local busy = Order.busy(d, s, p) or Order.send_blocked(d, s)
        add("Send on a Mission", "jw_send", "Choose a mission for them.", busy ~= nil, busy)
    end
    if p.rank == J.MASTER then
        local full = table.getn(Order.students(s, p)) >= Order.student_cap(p)
        add("Take a Student", "jw_student", "Choose an Initiate, or a Padawan or Knight without a Master.", full, "They already have two students.")
    end
    if p.rank == J.KNIGHT and p.master then
        add("Leave Their Master", "jw_leave", "They go on alone and gain Training XP at half the rate, and their Master has room for another "
            .. "student. Another Master can take them after " .. J.REPAIR_WEEKS .. " weeks.")
    end
    if p.rank >= J.GRAND_MASTER then
        local why = Order.meditate_blocked(d, s, p)
        add("Meditate on the Force", "jw_meditate", "Costs " .. J.MEDITATE_KNOWLEDGE .. " Knowledge; " .. p.name .. " meditates for "
            .. J.MEDITATE_WEEKS .. " week" .. ((J.MEDITATE_WEEKS == 1) and "" or "s") .. " (teaching no one), and the Force shows "
            .. "the Order a lead.", why ~= nil, why)
    end
    if (p.rank == J.PADAWAN or p.rank == J.KNIGHT) and Order.trial_blocked then
        local why = Order.trial_blocked(d, s, p)
        if why ~= "hidden" then
            add("Face the Trial", "jw_trial", Order.trial_tip(d, s, p) or "No world fit for their trial can be reached now.",
                why ~= nil, why)
        end
    end
    if Order.learned(s, "SEEKER", 3) and p.rank <= J.KNIGHT and Order.holocron_fits(d, s, p) then
        local why = Order.holocron_blocked(s)
        add("The Holocron", "jw_holocron", "Once a year, the Holocron lets them pass their next trial at once, in visions.",
            why ~= nil, why)
    end
    if p.rank == J.INITIATE then
        add("Turn Away", "jw_turn_away", "They are sent home and leave the Order for good.", p.trials_until ~= nil,
            p.name .. " is facing the Jedi Trials.")
    end
    if p.sensed then
        local busy = Order.busy(d, s, p)
        local q = Order.counsellor(d, s, p)
        add("Counsel Them", "jw_counsel", "A Master (their own, else an Intuitive Master) takes them aside for "
            .. J.SHADOW.COUNSEL_WEEKS .. " weeks: their shadow -" .. J.SHADOW.COUNSEL .. ". Both are busy meanwhile.",
            busy ~= nil or q == nil, busy or "No Master is free to counsel them.")
        local light = Order.light_world(d)
        add("Retreat to the Light", "jw_retreat", "They spend " .. J.SHADOW.RETREAT_WEEKS .. " weeks in retreat"
            .. (light and (" on " .. d:planet_name(light)) or "") .. ": shadow -" .. J.SHADOW.RETREAT .. " a week, no training.",
            busy ~= nil, busy)
        if p.watch then
            add("Trust Them", "jw_unwatch", "Their watching Master steps back.")
        elseif p.rank >= J.PADAWAN and p.rank <= J.KNIGHT and not p.master then
            add("Assign a Master", "jw_watch", "A Master keeps watch over them: their shadow lifts faster.")
        end
    end
    if p.command then
        add("Recall from the Fleet", "jw_recall_fleet", "They leave the fleet and return to the Temple.")
    elseif p.rank >= J.KNIGHT and Order.learned(s, "GUARDIAN", 3) then
        local why = Order.command_blocked(d, s, p)
        add("Attach to a Fleet", "jw_attach", "They fly with one of your fleets: +10% damage to the forces with them in "
            .. "battle; their shadow rises a point a week while they serve.", why ~= nil, why)
    end
    return out
end

local function card_lines(d, s, p)
    local out = {}
    local master = p.master and Order.get(s, p.master)
    local who = {}
    for _, st in ipairs(Order.students(s, p)) do
        table.insert(who, st.name)
    end
    table.insert(out, "Doing: " .. where_word(d, s, p) .. ".")
    if master then
        table.insert(out, "Master: " .. master.name .. ".")
    elseif table.getn(who) > 0 then
        table.insert(out, "Students: " .. table.concat(who, ", ") .. ".")
    elseif p.rank == J.MASTER then
        table.insert(out, "No students yet.")
    elseif p.rank == J.PADAWAN or p.rank == J.KNIGHT then
        local wait = (p.repair_at or 0) - s.week
        table.insert(out, "No Master: Training XP at half the rate" .. ((wait > 0) and (", free to be taken in " .. wait .. " weeks.") or "."))
    end
    if p.rank == J.PADAWAN then
        table.insert(out, "Training XP " .. M.floor(p.xp or 0) .. " of " .. J.XP_KNIGHT .. " to become a Knight.")
    elseif p.rank == J.KNIGHT then
        table.insert(out, "For the Trial: " .. p.missions .. " of " .. J.TRIAL_MISSIONS .. " missions, Training XP "
            .. M.floor(p.xp or 0) .. " of " .. J.XP_MASTER .. ".")
    end
    local names = {}
    for _, t in ipairs(p.traits or {}) do
        local def = J.TRAITS[t]
        if def then
            table.insert(names, def.name)
        end
    end
    if table.getn(names) > 0 then
        table.insert(out, "Traits: " .. table.concat(names, ", ") .. ".")
    end
    wrap(Order.mood(s, p), out, CARD_LINE)
    return out
end

local function render_card(d, s, G, p)
    local L = G.L
    for col = 1, table.getn(L.card_x) do
        for row = 1, table.getn(L.card_y) do
            local shell = "dp_nr_jtc" .. col .. "_" .. row .. "_shell"
            G.show(shell, JW.card_at ~= nil and JW.card_at[1] == col and JW.card_at[2] == row)
        end
    end
    if not (JW.card_at and p) then
        return
    end
    local base = "dp_nr_jtc" .. JW.card_at[1] .. "_" .. JW.card_at[2] .. "_"
    local potential = J.POTENTIAL[M.max(1, M.min(3, p.potential))]
    G.text(base .. "title", p.name)
    G.text(base .. "sub", rank_path(p) .. ". Potential " .. p.potential .. " of 3: " .. potential.name .. ".")
    G.tip(base .. "sub", "Potential sets how fast they gain Training XP: Slow, Moderate or Fast.")
    local shown = p.sensed or Order.learned(s, "SEEKER", 3)
    G.text(base .. "sub2", p.species .. ", of " .. p.home .. "." .. (shown and (" Darkness " .. M.round(p.shadow) .. ".") or "")
        .. (p.craft and (" Flies a" .. ((string.find(Order.craft_name(p), "^[AEIOU]") and "n ") or " ") .. Order.craft_name(p) .. ".") or ""))
    G.tip(base .. "sub2", shown and ("Their darkness: " .. M.round(p.shadow) .. " of 100" .. (p.sensed and ", sensed by a Master" or "")
        .. ". From " .. J.SHADOW.DARK_EVENT .. " the dark side tests them; from " .. J.SHADOW.FALL .. " a failure or a loss can "
        .. "make them fall. How readily it takes them: x" .. string.format("%.1f", Order.susceptibility(p)) .. ".")
        or "Their own shadow is hidden: an Intuitive Master or the Grand Master at the Temple may sense it.")
    local trait_tip = {}
    for _, t in ipairs(p.traits or {}) do
        local def = J.TRAITS[t]
        if def then
            table.insert(trait_tip, def.name .. ": " .. def.text)
        end
    end
    local lines = card_lines(d, s, p)
    for k = 1, L.card_lines do
        G.text(base .. "l" .. k, lines[k] or " ")
        G.tip(base .. "l" .. k, table.concat(trait_tip, " "))
    end
    JW.actions = card_actions(d, s, p)
    for k = 1, L.card_btns do
        local a = JW.actions[k]
        G.show(base .. "a" .. k, a ~= nil)
        if a then
            G.text(base .. "a" .. k, a.label)
            G.tip(base .. "a" .. k, a.tip)
            G.color(base .. "a" .. k, a.off and GREY_C or GOLD_C)
        end
    end
    G.tip(base .. "x", "Close.")
end

local function render_hbar(G, max_scroll)
    local L = G.L
    local on = max_scroll > 0
    G.show("dp_nr_jth_shell", on)
    JW.hmax = max_scroll
    if not on then
        return
    end
    local n = L.hbar_segs
    local len = M.max(2, M.round(n * L.groups / (L.groups + max_scroll)))
    local first = M.round((n - len) * JW.scroll / max_scroll) + 1
    JW.hlen = len
    for k = 1, n do
        G.icon("dp_nr_jth_s" .. k, (k >= first and k < first + len) and "dp_nr_jt_hs_thumb.tga" or "dp_nr_jt_hs_track.tga")
        G.tip("dp_nr_jth_s" .. k, "Drag, click or use the mouse wheel to see more of the Masters.")
    end
    G.tip("dp_nr_jth_left", "The Masters before these.")
    G.tip("dp_nr_jth_right", "The Masters after these.")
end

local function render_order(d, s, G)
    local L = G.L
    JW.hits = {}
    local groups, knights, padawans = lineages(s)
    local max_scroll = M.max(0, table.getn(groups) - L.groups)
    JW.scroll = M.max(0, M.min(JW.scroll, max_scroll))
    local box_pages = M.max(1, M.ceil((table.getn(knights) + table.getn(padawans)) / (3 * L.free_n)))
    JW.bpage = M.min(JW.bpage, box_pages - 1)
    local picking = JW.flow and (JW.flow.student_of or JW.flow.watch_of)
    local where = places(L, s, groups, knights, padawans)
    local sel = JW.sel and string.sub(JW.sel, 1, 2) == "P_" and Order.get(s, tonumber(string.sub(JW.sel, 3))) or nil
    if sel and not where[sel.id] then
        sel, JW.sel = nil, nil
    end
    JW.card_at = (sel and not picking) and anchor_for(where[sel.id]) or nil
    local rect = card_rect(L)

    local function person(base, p, name_color, status)
        local at = where[p.id]
        if at and not med_covered(L, rect, at.x, at.y) then
            draw_med(G, base, p, frame_of(s, p, offered(s, p)), person_tip(d, s, p), "P_" .. p.id, name_color, status)
        else
            hide_med(G, base)
        end
    end

    local head = Order.head(s)
    if head then
        person("dp_nr_jto_gm", head, GOLD_C)
    else
        hide_med(G, "dp_nr_jto_gm")
    end
    local waiting = Order.count_rank(s, J.INITIATE) - Order.count_rank(s, J.PADAWAN)
    local teaching = 0
    for _, p in ipairs(s.roster) do
        teaching = teaching + (Order.teaching(d, s, p) and 1 or 0)
    end
    local stat = "Initiates " .. waiting .. " of " .. Order.initiate_cap(s) .. ". Masters teaching: " .. teaching
        .. ". Missions: " .. table.getn(Order.running(s)) .. " of " .. Order.mission_limit(s) .. "."
    local top = {}
    if picking then
        top[1] = JW.flow.student_of and "Take a Student: click a glowing Jedi." or "Assign a Master: click a glowing Master."
    else
        top[1] = s.dormant and "The Order is dormant: no Master is left to lead it." or stat
        if s.news[1] then
            wrap(s.news[1], top, 60)
        end
    end
    local how = "A Master teaches up to two students, and a Master who is away teaches nobody: that is the choice at the heart of "
        .. "the Order. The Grand Master takes no students of their own, but Padawans without a Master gain Training XP at "
        .. "half the rate while they are at the Temple. Knights go on missions alone; Padawans go only with their Master."
    for k = 1, 3 do
        local y = L.gm + 10 - (k - 1) * 15
        local on = not covered(rect, -213, y, 330, 15)
        G.show("dp_nr_jto_top" .. k, on)
        if on then
            G.text("dp_nr_jto_top" .. k, top[k] or " ")
            G.tip("dp_nr_jto_top" .. k, how)
        end
    end
    local cancel = picking or (JW.flow and JW.flow.attach_of)
    G.show("dp_nr_jto_cancel", cancel ~= nil)
    if cancel then
        G.text("dp_nr_jto_cancel", "Cancel")
        G.tip("dp_nr_jto_cancel", "Choose no one.")
    end
    local vigil_on = not picking and not covered(rect, L.assign_x + 142, L.gm + 12, 136, 22)
    G.show("dp_nr_jto_vigil", vigil_on)
    if vigil_on then
        local why = Order.vigil_blocked(s)
        G.text("dp_nr_jto_vigil", "Hold a Vigil")
        G.color("dp_nr_jto_vigil", why and GREY_C or GOLD_C)
        G.tip("dp_nr_jto_vigil", "Every Jedi at the Temple meditates together for " .. J.VIGIL_WEEKS .. " weeks: no training, "
            .. "no missions, each one's shadow -" .. J.VIGIL_SHADOW .. ", the Order's darkness -" .. J.VIGIL_DARKNESS
            .. ". Once in " .. J.VIGIL_EVERY .. " weeks." .. (why and (" " .. why) or ""))
    end
    local eligible = Order.eligible(d, s)
    local can_assign = table.getn(eligible) > 0 and not picking and not covered(rect, L.assign_x, L.gm + 12, 136, 22)
    G.show("dp_nr_jto_assign", can_assign)
    if can_assign then
        G.text("dp_nr_jto_assign", "Assign a Hero")
        G.tip("dp_nr_jto_assign", "Heroes in the field who can serve (" .. table.getn(eligible) .. ") join the Order and go to the Temple.")
    end

    for key, tier in pairs({GM = {L.gm, "Grand Master"}, M = {L.m, "Masters"}, K = {L.k, "Knights"}, P = {L.p, "Padawans"}, I = {L.i, "Initiates"}}) do
        G.show("dp_nr_jto_lab" .. key, not covered(rect, -428, tier[1] + 18, 84, 12))
        G.text("dp_nr_jto_lab" .. key, tier[2])
    end

    for slot = 1, L.groups do
        local g = groups[slot + JW.scroll]
        local cx = slot_x(L, slot)
        if g then
            person("dp_nr_jto_m" .. slot, g.master, nil)
        else
            hide_med(G, "dp_nr_jto_m" .. slot)
        end
        local nk, np = g and table.getn(g.k) or 0, g and table.getn(g.p) or 0
        local mixed = nk == 1 and np == 1
        local function student(tier, side, q)
            local base = "dp_nr_jts_" .. tier .. slot .. side
            if q then
                person(base, q, nil)
            else
                hide_med(G, base)
            end
        end
        student("k", "L", (nk == 2 and g.k[1]) or (mixed and g.k[1]) or nil)
        student("k", "R", (nk == 2 and g.k[2]) or nil)
        student("k", "C", (nk == 1 and not mixed and g.k[1]) or nil)
        student("p", "L", (np == 2 and g.p[1]) or nil)
        student("p", "R", (np == 2 and g.p[2]) or (mixed and g.p[1]) or nil)
        student("p", "C", (np == 1 and not mixed and g.p[1]) or nil)
        local both = g ~= nil and (nk == 2 or np == 2 or mixed)
        local under = not covered(rect, cx, L.p, L.sstep + 10, 2 * (L.m - L.p))
        local parts = {
            {"stem", g ~= nil and (nk + np) > 0}, {"bar", both},
            {"lk", both and (nk == 2 or mixed)}, {"rk", both and nk == 2},
            {"lp", both and np == 2}, {"rp", both and (np == 2 or mixed)},
            {"ck", g ~= nil and nk == 1 and not mixed}, {"cp", g ~= nil and np == 1 and not mixed},
        }
        for _, part in ipairs(parts) do
            G.show("dp_nr_jto_" .. part[1] .. slot, part[2] and under)
        end
    end

    local n = 0
    for _, p in ipairs(s.roster) do
        if p.rank == J.INITIATE and n < L.ini then
            n = n + 1
            person("dp_nr_jto_i" .. n, p, nil)
        end
    end
    for k = n + 1, L.ini do
        hide_med(G, "dp_nr_jto_i" .. k)
    end
    local empty = n == 0 and not covered(rect, L.steps_x, L.i, 300, 16)
    G.show("dp_nr_jto_noini", empty)
    if empty then
        G.text("dp_nr_jto_noini", "No Initiates are waiting.")
    end

    G.show("dp_nr_jtb_shell", true)
    G.text("dp_nr_jtb_head", "Without a Master")
    G.tip("dp_nr_jtb_head", "Knights and Padawans without a Master. They gain Training XP at half the rate (Padawans while the "
        .. "Grand Master is at the Temple); a Master can take them as students.")
    local box = JW.box_rows(L, knights, padawans)
    for _, row in ipairs({"k", "p", "x"}) do
        for k = 1, L.free_n do
            local q = box[row][k]
            if q then
                person("dp_nr_jtb_" .. row .. k, q, nil)
            else
                hide_med(G, "dp_nr_jtb_" .. row .. k)
            end
        end
    end
    G.show("dp_nr_jtb_none", knights[1] == nil and padawans[1] == nil)
    G.text("dp_nr_jtb_none", "Every Jedi has a Master.")
    G.show("dp_nr_jtb_left", JW.bpage > 0)
    G.show("dp_nr_jtb_right", JW.bpage < box_pages - 1)
    G.tip("dp_nr_jtb_left", "Those before these.")
    G.tip("dp_nr_jtb_right", "Those after these.")

    local fallen = s.fallen
    for k = 1, L.fallen do
        local f = fallen[k]
        local x = L.fallen_x + (k - 1) * L.fallen_step
        if f and not med_covered(L, rect, x, L.gm) then
            local first, rest = f.name, " "
            local at = string.find(f.name, " ", 1, true)
            if at then
                first, rest = string.sub(f.name, 1, at - 1), string.sub(f.name, at + 1)
            end
            G.show("dp_nr_jto_f" .. k, true)
            G.show("dp_nr_jto_f" .. k .. "_f", true)
            G.show("dp_nr_jto_f" .. k .. "_n1", true)
            G.show("dp_nr_jto_f" .. k .. "_n2", true)
            G.show("dp_nr_jto_f" .. k .. "_n3", false)
            G.icon("dp_nr_jto_f" .. k, J.FALLEN_ICON)
            G.icon("dp_nr_jto_f" .. k .. "_f", "dp_nr_jt_fdark.tga")
            G.text("dp_nr_jto_f" .. k .. "_n1", first)
            G.text("dp_nr_jto_f" .. k .. "_n2", rest)
            G.tip("dp_nr_jto_f" .. k, f.name .. " has fallen. A Master on a Redeem mission may bring them home.")
        else
            hide_med(G, "dp_nr_jto_f" .. k)
        end
    end
    G.show("dp_nr_jto_flab", fallen[1] ~= nil and not covered(rect, L.fallen_x + 58, L.gm + 24, 160, 14))
    G.text("dp_nr_jto_flab", "The Fallen")

    render_hbar(G, max_scroll)
    render_card(d, s, G, sel)
end

local function hide_cards(G)
    local L = G.L
    for col = 1, table.getn(L.card_x) do
        for row = 1, table.getn(L.card_y) do
            G.show("dp_nr_jtc" .. col .. "_" .. row .. "_shell", false)
        end
    end
    JW.card_at = nil
end

local function force_words(world)
    local f, side = Order.force_of(world), Order.side_of(world)
    local strength = (f >= 60 and "the Force is strong there") or (f >= 30 and "the Force stirs there") or (f > 0 and "the Force is faint there")
        or "the Force is all but absent there"
    local hold = (side >= J.DARK_SITE and ", and the dark side holds it") or (side > 0 and ", with a shadow over it")
        or (side <= -J.DARK_SITE and ", and the light holds it") or (side < 0 and ", touched by the light") or ""
    return strength .. hold
end

local function odds_rows(d, s, flow)
    local rows = {}
    local p = Order.get(s, flow.jedi)
    local key = flow.mission
    local def = J.MISSIONS[key]
    local function taken(row)
        local there = row.world and Order.mission_at(s, row.world)
        if there then
            row.pick, row.tip = false, Order.label(there) .. " is already on a mission there."
            row.text = row.text .. " (taken)"
        end
        return row
    end
    if not def.open and not def.event then
        for _, l in ipairs(Order.leads_for(d, s, key)) do
            local odds = Order.odds(d, s, p, key, l.world, false)
            table.insert(rows, taken({text = l.title .. " (" .. Order.odds_word(odds) .. ")", tip = l.text,
                                      world = FindPlanet(l.world or "") and l.world or nil, pick = l.target, lead = l}))
        end
        return rows
    end
    local seek = key == "SEEK"
    local function seek_label(world, lead)
        local chance = Order.seek_chance(s, world, lead)
        return Order.seek_word(chance, world), chance
    end
    if seek then
        for _, l in ipairs(Order.leads_for(d, s, key)) do
            local word, chance = seek_label(l.world, l)
            table.insert(rows, taken({text = l.title .. " (" .. word .. ")", tip = "A lead: " .. l.text .. " Chance of a student: "
                                      .. chance .. "%.", world = FindPlanet(l.world or "") and l.world or nil,
                                      pick = l.world, lead = l}))
        end
    end
    local function add_row(value, world, label, tip)
        local planet = world and FindPlanet(world)
        local side = world and Order.side_of(world) or 0
        local warn = (side > 0) and (" The dark side there will weigh on " .. p.name .. ".") or ""
        local row
        if seek then
            local word, chance = seek_label(world)
            row = {text = label .. " (" .. word .. ")", tip = (world and Order.force_lore(world) or "") .. " Chance of a student: "
                .. chance .. "%; a lead or another finding otherwise." .. warn, world = planet and world or nil, pick = value}
            local wait = Order.seek_cooldown(s, world)
            if wait then
                row.pick, row.tip, row.text = false, label .. ": " .. wait, label .. " (searched lately)"
            end
        else
            local odds = Order.odds(d, s, p, key, world, false)
            row = {text = label .. " (" .. Order.odds_word(odds) .. ")", tip = (tip or label) .. warn,
                   world = planet and world or nil, pick = value}
        end
        if world and Order.world_locked(world) then
            row.pick, row.tip, row.text = false, label .. " is closed to the galaxy for now.", label .. " (closed)"
        end
        table.insert(rows, taken(row))
    end
    local Rep = Republic()
    if key == "MEDIATE" or key == "PEACE" then
        local Senate = Rep.senate
        local list = {}
        for name, seat in pairs(Senate and Senate.seats(d) or {}) do
            table.insert(list, {name = name, value = seat.opinion})
        end
        table.sort(list, function(a, b) return a.value < b.value end)
        for _, e in ipairs(list) do
            local planet = FindPlanet(e.name)
            if planet then
                add_row(e.name, e.name, d:planet_name(planet), d:planet_name(planet) .. ": opinion " .. M.round(e.value) .. ".")
            end
        end
        for world, w in pairs(d.vassal_worlds or {}) do
            local planet = FindPlanet(world)
            if planet and (w.stage == "protectorate" or w.stage == "associate") then
                add_row(world, world, d:planet_name(planet), d:planet_name(planet) .. ": a " .. w.stage .. ".")
            end
        end
        if key == "PEACE" then
            local Sym = Rep.part("sym")
            for _, e in ipairs(Sym and Sym.list(d) or {}) do
                local cat = U.category(e.owner)
                if cat == "INDEPENDENT" or cat == "WARLORD" then
                    add_row(e.key, e.key, e.name, e.name .. ": sympathy for the Republic " .. e.text .. ".")
                end
            end
        end
    elseif key == "SEEK" or key == "LORE" then
        local list = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local k = U.key(planet)
            local f = Order.force_of(k)
            local ruin = Order.ruin(k)
            local fits = (key == "SEEK" and f > 0 and Order.peopled(k)) or (key == "LORE" and (f >= J.LORE_FORCE or ruin ~= nil))
            if fits then
                table.insert(list, {key = k, planet = planet, force = f + (ruin and 100 or 0), ruin = ruin})
            end
        end
        table.sort(list, function(a, b)
            if a.force ~= b.force then
                return a.force > b.force
            end
            return a.key < b.key
        end)
        for _, e in ipairs(list) do
            local name = d:planet_name(e.planet)
            local label = (key == "LORE" and e.ruin and (name .. ": " .. e.ruin.name)) or name
            local dark = key == "LORE" and Order.dark_site(e.key) and " A dark site." or ""
            add_row(e.key, e.key, label, Order.force_lore(e.key) .. dark)
        end
    elseif key == "CONFRONT" then
        for _, t in ipairs(Order.threats(d, s)) do
            add_row(t.key, Order.threat_world(t), t.name, t.name .. ".")
        end
    elseif key == "ANSWER" then
        for _, e in ipairs(Order.answer_requests(d, s)) do
            add_row(e.def.key, e.req.world, "The " .. e.def.name, "The " .. e.def.name .. " asks for " .. e.req.desire.text .. ".")
        end
    elseif key == "REDEEM" then
        for _, f in ipairs(s.fallen) do
            local obj = Order.first_of(f.type)
            local ok, planet = pcall(function() return obj and obj.Get_Planet_Location() end)
            local world = ok and planet and U.key(planet) or nil
            add_row(f.id, world, f.name, "Try to bring " .. f.name .. " home.")
        end
    elseif key == "ENVOY" then
        local Envoys = Rep.part("envoys")
        local courts = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            if Envoys and Envoys.power_capital and Envoys.power_capital(d, planet) then
                local k = U.key(planet)
                courts[k] = true
                local who = d.display_name(planet.Get_Owner().Get_Faction_Name())
                add_row(k, k, d:planet_name(planet) .. " (" .. who .. ")", "The court of " .. who .. " at "
                    .. d:planet_name(planet) .. ": its opinion of the Republic +" .. J.ENVOY_OPINION .. ".")
            end
        end
        local Sym = Rep.part("sym")
        for _, e in ipairs(Sym and Sym.list(d) or {}) do
            local planet = FindPlanet(e.key)
            if planet and planet.Get_Owner() ~= d.human and not courts[e.key] then
                add_row(e.key, e.key, e.name, e.name .. ": sympathy for the Republic " .. e.text .. ".")
            end
        end
    end
    local Laws = Rep.part("laws")
    if Laws then
        local open = {}
        for _, r in ipairs(rows) do
            if not (r.world and Laws.closed(d, r.world)) then
                table.insert(open, r)
            end
        end
        rows = open
    end
    return rows
end

local function target_world(d, s, flow)
    local key, target = flow.mission, flow.target
    if flow.lead_world then
        return flow.lead_world
    end
    if key == "CONFRONT" then
        local t = Order.threat(target)
        return t and Order.threat_world(t)
    elseif key == "ANSWER" then
        local Blocs = Republic().part("blocs")
        local req = Blocs and Blocs.request(d, target)
        return req and req.world
    elseif key == "REDEEM" then
        for _, f in ipairs(s.fallen) do
            if f.id == target then
                local obj = Order.first_of(f.type)
                local ok, planet = pcall(function() return obj and obj.Get_Planet_Location() end)
                return ok and planet and U.key(planet) or nil
            end
        end
        return nil
    end
    return target
end

local function paths_word(def)
    local names = {}
    for _, path in ipairs(J.PATH_ORDER) do
        if def.best[path] then
            table.insert(names, J.PATHS[path])
        end
    end
    return ((table.getn(names) > 0) and ("Best: " .. table.concat(names, ", ")) or "Any Path") .. "."
end

function JW.slot_index(k, per_col)
    local col, row = M.floor((k - 1) / per_col), (k - 1) - M.floor((k - 1) / per_col) * per_col
    return row * 2 + col + 1
end

local function render_chooser(d, s, G, rows, heading)
    local L = G.L
    JW.choices = rows
    G.show("dp_nr_jtw_shell", rows ~= nil)
    if not rows then
        return
    end
    G.text("dp_nr_jtw_head", heading)
    local per = 2 * L.pick_rows
    local max_go = M.max(0, M.ceil(table.getn(rows) / per) - 1)
    JW.list = M.min(JW.list, max_go)
    JW.pick_rows = L.pick_rows
    for k = 1, per do
        local r = rows[JW.list * per + JW.slot_index(k, L.pick_rows)]
        local name = "dp_nr_jtw_r" .. k
        G.show(name, r ~= nil)
        G.show(name .. "_hit", r ~= nil)
        G.show(name .. "_zoom", r ~= nil and r.world ~= nil)
        G.show(name .. "_globe", r ~= nil and r.world ~= nil)
        if r and r.world then
            G.icon(name .. "_globe", GLOBES[r.world] or "dp_globe_unknown.tga")
        end
        local side = (r and r.world) and Order.side_of(r.world) or 0
        G.show(name .. "_sith", side > 0)
        if side > 0 then
            local tier = M.max(1, M.min(5, M.ceil(side / 20)))
            G.icon(name .. "_sith", "dp_sith_" .. tier .. ".tga")
            G.tip(name .. "_sith", "A dark side presence: " .. ({"faint", "felt", "strong", "heavy", "overwhelming"})[tier] .. ".")
        end
        if r then
            local shown = r.text
            if string.len(shown) > L.pick_chars then
                local _, _, head, tail = string.find(shown, "^(.-)( %b())$")
                head, tail = head or shown, tail or ""
                shown = string.sub(head, 1, M.max(8, L.pick_chars - string.len(tail) - 3)) .. "..." .. tail
            end
            G.text(name, shown)
            G.tip(name .. "_hit", r.text .. ". " .. (r.tip or ""))
            G.tip(name .. "_zoom", "Show on the map.")
            G.color(name, (r.pick == false) and GREY_C or ((r.lead and JW.flow) and GOLD_C or PALE_C))
        end
    end
    JW.list_max = max_go
    local segs = L.pick_segs or 0
    local len = M.max(1, M.floor(segs / (max_go + 1)))
    local first = (max_go > 0) and (M.round((segs - len) * JW.list / max_go) + 1) or 1
    for k = 1, segs do
        G.show("dp_nr_jtw_s" .. k, max_go > 0)
        if max_go > 0 then
            G.icon("dp_nr_jtw_s" .. k, (k >= first and k < first + len) and "dp_scroll_thumb.tga" or "dp_scroll_track.tga")
            G.tip("dp_nr_jtw_s" .. k, "Page " .. (JW.list + 1) .. " of " .. (max_go + 1) .. ": click to jump, or use the wheel.")
        end
    end
    G.show("dp_nr_jtw_up", JW.list > 0)
    G.show("dp_nr_jtw_down", JW.list < max_go)
    G.tip("dp_nr_jtw_up", "The page before.")
    G.tip("dp_nr_jtw_down", "The next page.")
    if table.getn(rows) == 0 then
        G.show("dp_nr_jtw_r1", true)
        G.text("dp_nr_jtw_r1", "There is nowhere for this mission now.")
        G.color("dp_nr_jtw_r1", PALE_C)
    end
end

local function journey(s, p)
    local m = p.mission
    if m.stage == "leave" then
        return "Leaving", 0
    elseif m.stage == "out" then
        return "Flying out", 0
    elseif m.stage == "back" then
        return "Flying home", 1
    end
    if m.key == "POST" then
        return "At their post", 1
    end
    local total = (m.weeks or J.MISSIONS[m.key].weeks) * J.WEEK_SECONDS
    local left = M.max(0, (m.ends or 0) - GetCurrentTime())
    return weeks_word(M.ceil(2 * left / J.WEEK_SECONDS) / 2) .. " left", U.clamp(1 - left / M.max(1, total), 0, 1)
end

local function render_missions(d, s, G)
    local L = G.L
    local flow = JW.flow and JW.flow.mission and JW.flow or nil
    local running = Order.running(s)
    G.text("dp_nr_jtm_head1", "Under way (" .. table.getn(running) .. " of " .. Order.mission_limit(s) .. ")")
    local max_go = M.max(0, table.getn(running) - L.run_rows)
    JW.go = M.min(JW.go, max_go)
    JW.hits = {}
    local chosen = JW.run_sel and Order.get(s, JW.run_sel)
    if not (chosen and chosen.mission) then
        chosen, JW.run_sel = nil, nil
    end
    for k = 1, L.run_rows do
        local p = running[k + JW.go]
        local b = "dp_nr_jtm_r" .. k
        for _, part in ipairs({"", "_f", "_name", "_what", "_left", "_hit"}) do
            G.show(b .. part, p ~= nil)
        end
        G.show(b .. "_sel", p ~= nil and chosen == p)
        for seg = 1, L.run_segs do
            G.show(b .. "_b" .. seg, p ~= nil)
        end
        if p then
            G.icon(b, icon_of(p))
            G.icon(b .. "_f", "dp_nr_jt_f" .. M.min(p.rank, 5) .. ".tga")
            local with = {}
            for _, id in ipairs(p.mission.along or {}) do
                local st = Order.get(s, id)
                if st then
                    table.insert(with, st.name)
                end
            end
            G.text(b .. "_name", p.name .. ((with[1] ~= nil) and (" and " .. table.getn(with) .. ((table.getn(with) == 1) and " student" or " students")) or ""))
            G.text(b .. "_what", where_word(d, s, p))
            local word, share = journey(s, p)
            G.text(b .. "_left", word)
            for seg = 1, L.run_segs do
                G.icon(b .. "_b" .. seg, (seg <= M.round(share * L.run_segs)) and "dp_op_bar_g.tga" or "dp_op_bar_e.tga")
            end
            local tip = person_tip(d, s, p, ((with[1] ~= nil) and ("With them: " .. table.concat(with, " and ") .. ". ") or "")
                .. "Click to choose them; then Call Home brings them back.")
            G.tip(b .. "_hit", tip)
            G.tip(b, tip)
            G.tip(b .. "_f", tip)
            JW.hits[b .. "_hit"] = "R_" .. p.id
        end
    end
    local segs = L.run_bar_segs or 0
    local len = M.max(2, M.floor(segs * L.run_rows / M.max(1, table.getn(running))))
    local first = (max_go > 0) and (M.round((segs - len) * JW.go / max_go) + 1) or 1
    for k = 1, segs do
        G.show("dp_nr_jtm_rs" .. k, max_go > 0)
        if max_go > 0 then
            G.icon("dp_nr_jtm_rs" .. k, (k >= first and k < first + len) and "dp_scroll_thumb.tga" or "dp_scroll_track.tga")
            G.tip("dp_nr_jtm_rs" .. k, "Journeys " .. (JW.go + 1) .. "-" .. M.min(table.getn(running), JW.go + L.run_rows)
                .. " of " .. table.getn(running) .. ": click to jump.")
        end
    end
    JW.go_max = max_go
    G.show("dp_nr_jtm_none", running[1] == nil)
    G.text("dp_nr_jtm_none", "No Jedi are away.")
    G.show("dp_nr_jtm_rup", JW.go > 0)
    G.show("dp_nr_jtm_rdown", JW.go < max_go)
    G.tip("dp_nr_jtm_rup", "Earlier journeys.")
    G.tip("dp_nr_jtm_rdown", "Later journeys.")

    local leads = Order.leads(d, s)
    G.text("dp_nr_jtm_leads", JW.leads_open and "Mission Cards" or ("Active Leads (" .. table.getn(leads) .. ")"))
    G.tip("dp_nr_jtm_leads", JW.leads_open and "Back to the mission cards." or ("News that opens a mission at a world: "
        .. table.getn(leads) .. " open. Every mission but Seek the Force needs one; a lead lasts " .. J.LEAD_WEEKS
        .. " weeks, and a dark one left alone darkens the Order."))
    local listing = (flow and flow.step == 2) or (JW.leads_open and not flow)
    G.show("dp_nr_jtmc_shell", not listing)
    G.text("dp_nr_jtm_head2", (JW.preset and Order.get(s, JW.preset)) and ("Send " .. Order.get(s, JW.preset).name) or "Send a Jedi")
    for k, key in ipairs(J.MISSION_ORDER) do
        local def = J.MISSIONS[key]
        local on = flow and flow.mission == key
        local n = table.getn(Order.leads_for(d, s, key))
        local tier = J.TIER_NAMES[def.tier or 1]
        local why = Order.mission_closed(d, s, key)
        local state = def.open and "always open" or ((n == 0) and "no leads" or (n .. ((n == 1) and " lead" or " leads")))
        if def.event then
            state = why and "needs the Sanction Act" or ((key == "ANSWER") and (table.getn(Order.answer_requests(d, s))
                .. " requests") or "open")
        end
        G.icon("dp_nr_jtm_c" .. k .. "_i", def.icon)
        G.text("dp_nr_jtm_c" .. k .. "_t", def.name)
        G.color("dp_nr_jtm_c" .. k .. "_t", on and WHITE_C or (why and GREY_C or GOLD_C))
        G.text("dp_nr_jtm_c" .. k .. "_w", tier .. ": " .. state)
        G.text("dp_nr_jtm_c" .. k .. "_p", paths_word(def))
        G.tip("dp_nr_jtm_c" .. k .. "_hit", def.name .. " (" .. tier .. ((def.tier == 3) and ", Masters only, alone" or "")
            .. "; " .. weeks_word(def.weeks) .. " at the world, and the journey): " .. def.text .. (why and (" " .. why) or ""))
    end

    local function strip_buttons(a, b, c)
        for k, btn in ipairs({a or false, b or false, c or false}) do
            local name = "dp_nr_jtm_b" .. k
            G.show(name, btn ~= false)
            if btn then
                G.text(name, btn[1])
                G.tip(name, btn[2])
            end
        end
    end
    local title, line1, line2 = "Choose a mission.", "Click a card above. Hover over it to see what it does.", " "
    local free = nil
    JW.buttons = {}
    if chosen and not flow then
        local m = chosen.mission
        title = Order.label(chosen) .. ": " .. where_word(d, s, chosen) .. "."
        line1 = (m.stage == "back") and "They are on their way home." or "Call Home ends the mission at once: they fly back to the Temple."
        JW.buttons = {"jw_close_run", "jw_call_home", "jw_run_find"}
        strip_buttons({"Close", "Choose no one."}, (m.stage ~= "back") and {"Call Home", "They give up the mission and fly back to the Temple."} or nil,
            {"Find on Map", "Show where " .. chosen.name .. " is on the galaxy map."})
    elseif flow and flow.step == 1 then
        local def = J.MISSIONS[flow.mission]
        title = def.name .. ": choose a Jedi."
        line1 = weeks_word(def.weeks) .. " at the world, and the journey. " .. paths_word(def) .. (def.master and " Masters only." or "")
        if flow.lead_title then
            line2 = "The lead: " .. flow.lead_title .. "."
        end
        free = Order.free_jedi(d, s, flow.mission)
        if table.getn(free) == 0 then
            line2 = def.master and "No Master is free." or "No Knight or Master is free."
        end
        JW.buttons = {"jw_back"}
        strip_buttons({"Cancel", "Choose another mission."})
    elseif flow and flow.step == 2 then
        local def = J.MISSIONS[flow.mission]
        local p = Order.get(s, flow.jedi)
        title = def.name .. ": " .. p.name .. " goes where?"
        line1 = "Choose from the list above."
        JW.buttons = {"jw_back"}
        strip_buttons({"Back", "Go back a step."})
    elseif flow and flow.step == 3 then
        local def = J.MISSIONS[flow.mission]
        local p = Order.get(s, flow.jedi)
        local world = target_world(d, s, flow)
        local planet = world and FindPlanet(world)
        title = p.name .. (planet and (" to " .. d:planet_name(planet)) or "") .. ": the odds look " .. Order.odds_word(Order.odds(d, s, p, flow.mission, world, false)) .. "."
        local lines = wrap(flow.lead_text or def.short or def.text, {}, 92)
        line1, line2 = lines[1], lines[2] or " "
        JW.strip_tip = (flow.lead_text and (flow.lead_text .. " ") or "") .. def.text
        JW.buttons = {"jw_back", "jw_confirm"}
        local come = (p.rank >= J.MASTER and (def.tier or 1) < 3) and Order.can_come(d, s, p) or {}
        local names = {}
        for _, st in ipairs(come) do
            table.insert(names, st.name)
        end
        strip_buttons({"Back", "Go back a step."}, {"Send Alone", "They leave at once, alone."},
            (names[1] ~= nil) and {"With Students", "They take " .. table.concat(names, " and ") .. ": the students gain twice the XP from it, "
                .. "but the mission is a little harder and their shadow rises."} or nil)
        if names[1] ~= nil then
            JW.buttons[3] = "jw_confirm_along"
        end
    else
        strip_buttons()
    end
    G.text("dp_nr_jtm_title", title)
    G.text("dp_nr_jtm_l1", line1)
    G.text("dp_nr_jtm_l2", line2)
    local strip_tip = (flow and flow.step == 3 and JW.strip_tip) or (line1 .. " " .. line2)
    G.tip("dp_nr_jtm_l1", strip_tip)
    G.tip("dp_nr_jtm_l2", strip_tip)

    local shown = free and table.getn(free) > 0
    if shown then
        JW.strip = M.min(JW.strip, M.max(0, table.getn(free) - L.strip_meds))
    end
    for k = 1, L.strip_meds do
        local base = "dp_nr_jtm_s" .. k
        local p = free and free[k + JW.strip]
        G.show(base, p ~= nil)
        G.show(base .. "_f", p ~= nil)
        if p then
            local best = p.path and J.MISSIONS[flow.mission].best[p.path]
            G.icon(base, icon_of(p))
            G.icon(base .. "_f", best and "dp_nr_jt_foffer.tga" or ("dp_nr_jt_f" .. M.min(p.rank, 5) .. ".tga"))
            local tip = person_tip(d, s, p, (best and "This mission is their Path's. " or "") .. "Click to send them.")
            G.tip(base, tip)
            G.tip(base .. "_f", tip)
            JW.hits[base] = "F_" .. p.id
        end
    end
    G.show("dp_nr_jtm_sleft", shown and JW.strip > 0)
    G.show("dp_nr_jtm_sright", shown and JW.strip < table.getn(free) - L.strip_meds)
    G.tip("dp_nr_jtm_sleft", "The Jedi before these.")
    G.tip("dp_nr_jtm_sright", "The Jedi after these.")

    if listing and not flow then
        local rows = {}
        for _, l in ipairs(leads) do
            local def = J.MISSIONS[l.mission]
            local left = M.max(0, l.expires - s.week)
            table.insert(rows, {text = l.title .. " (" .. left .. " wk)", world = FindPlanet(l.world or "") and l.world or nil,
                                tip = l.text .. " Mission: " .. def.name .. ". " .. left .. " weeks left."
                                    .. (l.dark and " A dark lead: left alone, it darkens the Order." or ""),
                                lead = l})
        end
        render_chooser(d, s, G, rows, "Active Leads")
        if not rows[1] then
            G.text("dp_nr_jtw_r1", "No leads now. Seek the Force is always open.")
        end
    elseif listing then
        render_chooser(d, s, G, odds_rows(d, s, flow), "Choose where")
    else
        render_chooser(d, s, G, nil)
    end
end

local function render_panel(G, title, sub, lines, a, b)
    local L = G.L
    G.text("dp_nr_jtp_title", title)
    G.text("dp_nr_jtp_sub", sub)
    for k = 1, L.panel_lines do
        G.text("dp_nr_jtp_l" .. k, lines[k] or " ")
    end
    JW.panel_buttons = {a or false, b or false}
    for k, btn in ipairs(JW.panel_buttons) do
        local name = "dp_nr_jtp_a" .. k
        G.show(name, btn ~= false)
        if btn then
            G.text(name, btn.label)
            G.tip(name, btn.tip)
            G.color(name, btn.off and GREY_C or GOLD_C)
        end
    end
end

local function render_teachings(d, s, G)
    for i, path in ipairs(J.TEACHING_PATHS) do
        G.text("dp_nr_jtt_h" .. i, "The " .. J.PATHS[path])
        G.tip("dp_nr_jtt_h" .. i, J.PATH_TEXT[path])
        for tier, t in ipairs(J.TEACHINGS[path]) do
            local base = "dp_nr_jtt_n" .. i .. "_" .. tier
            local status, why = Order.teaching_state(s, path, tier)
            local word = (status == "learned") and "Learned" or ((status == "closed") and "Closed" or (J.TEACHING_COST[tier] .. " Knowledge"))
            local frame = (JW.sel == "T_" .. path .. "_" .. tier) and "dp_nr_jt_fsel.tga"
                or ((status == "learned") and "dp_nr_jt_f5.tga" or ((status == "open" or status == "dear") and "dp_nr_jt_f3.tga" or "dp_nr_jt_f1.tga"))
            G.icon(base, J.PATH_ICON[path])
            G.icon(base .. "_f", frame)
            G.text(base .. "_t", t.name)
            G.color(base .. "_t", (status == "learned") and GOLD_C or ((status == "closed" or status == "locked") and GREY_C or PALE_C))
            G.text(base .. "_c", word)
            G.tip(base, t.name .. ": " .. t.text .. (why and (" " .. why) or ""))
        end
    end
    for i, q in ipairs(J.CHARTER) do
        local status, why = Order.charter_state(s, q)
        local answer = s.charter[q.key]
        local name = (status == "locked") and "Locked" or "Undecided"
        if answer then
            name = (q.a.key == answer) and q.a.name or q.b.name
        end
        G.text("dp_nr_jtt_q" .. i .. "_t", q.name)
        G.text("dp_nr_jtt_q" .. i .. "_a", name)
        G.color("dp_nr_jtt_q" .. i .. "_t", (status == "locked") and GREY_C or ((JW.sel == "C_" .. q.key) and WHITE_C or GOLD_C))
        G.color("dp_nr_jtt_q" .. i .. "_a", (status == "locked") and GREY_C or PALE_C)
        G.tip("dp_nr_jtt_q" .. i .. "_hit", (status == "locked") and (q.name .. ": " .. why) or (q.text .. " Click to read the two answers."))
    end
    G.text("dp_nr_jtt_ch", "The Charter")
    local sel = JW.sel or ""
    local _, _, path, tier = string.find(sel, "^T_(%a+)_(%d)$")
    if path then
        tier = tonumber(tier)
        local t = J.TEACHINGS[path][tier]
        local status, why = Order.teaching_state(s, path, tier)
        local lines = wrap(t.text, {}, PANEL_LINE)
        table.insert(lines, " ")
        table.insert(lines, "Cost: " .. J.TEACHING_COST[tier] .. " Knowledge (you have " .. s.knowledge .. ").")
        if tier == 3 then
            table.insert(lines, " ")
            wrap("The Order's crowning teaching: learning it closes the third tier of the other two Paths.", lines, PANEL_LINE)
        end
        if why then
            table.insert(lines, " ")
            wrap(why, lines, PANEL_LINE)
        end
        render_panel(G, t.name, "The Path of the " .. J.PATHS[path] .. ", tier " .. tier .. ".", lines,
            (status ~= "learned") and {label = "Learn", key = "jw_learn", tip = (status == "open") and "The Order takes it up." or why, off = status ~= "open"} or nil)
        return
    end
    for _, q in ipairs(J.CHARTER) do
        if q.key == string.sub(sel, 3) and string.sub(sel, 1, 2) == "C_" then
            local status, why = Order.charter_state(s, q)
            local answer = s.charter[q.key]
            local lines = {}
            wrap(q.text, lines, PANEL_LINE)
            table.insert(lines, " ")
            for _, which in ipairs({"a", "b"}) do
                local option = q[which]
                if not answer or answer == option.key then
                    wrap(option.name .. ": " .. option.text, lines, PANEL_LINE)
                    table.insert(lines, " ")
                end
            end
            if status == "decided" then
                table.insert(lines, "This is settled, and cannot be changed.")
                render_panel(G, q.name, "The Order's Charter.", lines)
            elseif status == "locked" then
                wrap(why, lines, PANEL_LINE)
                render_panel(G, q.name, "The Order's Charter: not yet open.", lines)
            else
                render_panel(G, q.name, "The Order's Charter.", lines,
                    {label = q.a.name, key = "jw_charter_a", tip = q.a.text .. " This cannot be undone."},
                    {label = q.b.name, key = "jw_charter_b", tip = q.b.text .. " This cannot be undone."})
            end
            return
        end
    end
    local lines = {}
    wrap("Knowledge pays for Teachings, tier by tier, from the foot of each pillar upward. The first two tiers of every Path are open to all; the third is the Order's crowning teaching, and learning one closes the others.", lines, PANEL_LINE)
    table.insert(lines, " ")
    wrap("The Charter settles what kind of institution the Order is. Its three questions open one at a time, the first once the Order has a Council. Each answer is permanent, and each lists what it does.", lines, PANEL_LINE)
    table.insert(lines, " ")
    table.insert(lines, "Click a Teaching or a tablet to read it.")
    render_panel(G, "Teachings and the Charter", "What the Order becomes.", lines)
end

local function render_council(d, s, G)
    local L = G.L
    JW.hits = {}
    for i, seat in ipairs(J.SEATS) do
        local id = s.council.seats[seat.key]
        local p = id and Order.get(s, id)
        local base = "dp_nr_jtk_s" .. i
        G.icon(base, p and icon_of(p) or J.VACANT_ICON)
        G.icon(base .. "_f", (JW.sel == "S_" .. seat.key) and "dp_nr_jt_fsel.tga" or (p and "dp_nr_jt_f5.tga" or "dp_nr_jt_f1.tga"))
        G.text(base .. "_t", seat.name)
        G.text(base .. "_h", p and p.name or "Vacant")
        G.tip(base, seat.name .. (seat.path and (" (a " .. J.PATHS[seat.path] .. "'s seat)") or "") .. ": " .. seat.text)
        JW.hits[base] = "S_" .. seat.key
    end
    local choosing = JW.flow and JW.flow.seat
    local masters = {}
    if choosing then
        for _, m in ipairs(s.roster) do
            local seat_path = nil
            for _, seat in ipairs(J.SEATS) do
                if seat.key == choosing then
                    seat_path = seat.path
                end
            end
            if m.rank == J.MASTER and not Order.seat_of(s, m) and not away(m) and (not seat_path or m.path == seat_path) then
                table.insert(masters, m)
            end
        end
    end
    G.show("dp_nr_jtk_choose", choosing ~= nil)
    if choosing then
        G.text("dp_nr_jtk_choose", (table.getn(masters) > 0) and "Choose a Master for this seat." or "No Master is free for this seat.")
    end
    for k = 1, L.council_meds do
        local base = "dp_nr_jtk_m" .. k
        local m = masters[k]
        if m then
            draw_med(G, base, m, "dp_nr_jt_f4.tga", person_tip(d, s, m, "Click to seat them."), "K_" .. m.id)
        else
            hide_med(G, base)
        end
    end
    local sel = JW.sel or ""
    if string.sub(sel, 1, 2) == "S_" then
        for _, seat in ipairs(J.SEATS) do
            if seat.key == string.sub(sel, 3) then
                local id = s.council.seats[seat.key]
                local p = id and Order.get(s, id)
                local lines = wrap(seat.text, {}, PANEL_LINE)
                if seat.path then
                    table.insert(lines, "Held by a Master of the " .. J.PATHS[seat.path] .. "s.")
                end
                table.insert(lines, " ")
                local a, b = nil, nil
                if choosing then
                    a = {label = "Cancel", key = "jw_back", tip = "Keep the seat as it is."}
                elseif not p and seat.key ~= "GRAND" then
                    wrap("Vacant. A seat is held for life: it empties only if its Master dies or falls.", lines, PANEL_LINE)
                    local ok, why = Order.can_seat(s, seat)
                    a = {label = "Appoint", key = "jw_appoint", tip = ok and "Choose a Master for this seat, for life." or why, off = not ok}
                else
                    wrap("Held for life: the seat empties only if its Master dies or falls.", lines, PANEL_LINE)
                    table.insert(lines, " ")
                    local extra, ab = JW.seat_work(d, s, seat.key)
                    for _, line in ipairs(extra) do
                        wrap(line, lines, PANEL_LINE)
                    end
                    a, b = ab[1], ab[2]
                end
                render_panel(G, seat.name, p and Order.label(p) or "Vacant.", lines, a, b)
                return
            end
        end
    end
    local lines = {}
    wrap("Seven seats, each with its own work, held for life. Click a seat to see what it does and who holds it.", lines, PANEL_LINE)
    render_panel(G, "The Jedi Council", "The Order's Masters.", lines)
end

function JW.seat_work(d, s, key)
    local lines, a, b = {}, nil, nil
    local function posts(kind, noun)
        local list = Order.posted(s, kind)
        if not list[1] then
            table.insert(lines, "No " .. noun .. " posted (up to " .. J.POSTS[kind] .. ").")
        end
        for _, q in ipairs(list) do
            table.insert(lines, q.name .. ": " .. (Order.post_word(d, q) or "") .. ".")
        end
    end
    if key == "TRAINING" then
        local reg = Order.regimen(s)
        table.insert(lines, "Regimen: " .. (reg and (reg.name .. ". " .. reg.text) or "none chosen."))
        a = {label = "Set the Regimen", key = "jw_regimen", tip = "Choose how the Temple trains: Forms, Meditation or Study."}
    elseif key == "DIPLOMACY" then
        posts("ENVOY", "envoys")
        local why = Order.post_blocked(d, s, "ENVOY")
        a = {label = "Post an Envoy", key = "jw_post_ENVOY", off = why ~= nil, tip = why or ("A Knight goes as a standing "
            .. "envoy: a member world's opinion +1 a week (to +" .. J.ENVOY_WORLD_MAX .. "), a foreign court's opinion of "
            .. "the Republic +1 every " .. J.ENVOY_COURT_EVERY .. " weeks; at the Republic's capital, Public Trust +1 every "
            .. J.ENVOY_TRUST_EVERY .. " weeks.")}
    elseif key == "LORE" then
        local n = table.getn((Order.relics_state(s).list) or {})
        table.insert(lines, "The Reliquary holds " .. n .. ((n == 1) and " artifact." or " artifacts."))
        a = {label = "Open the Reliquary", key = "jw_reliquary", tip = "The Order's artifacts: research, use, or seal them away."}
    elseif key == "GUARDIANS" then
        local h = s.hunt
        table.insert(lines, h and ("The Hunt: " .. h.name .. " (+" .. (h.bonus or 0) .. "% against it).") or "No Hunt declared.")
        posts("HUNT", "hunters")
        a = {label = h and "End the Hunt" or "Declare a Hunt", key = h and "jw_end_hunt" or "jw_hunt",
             tip = h and "The hunters come home." or "Name a dark threat or a fallen Jedi to hunt."}
        local why = Order.post_blocked(d, s, "HUNT")
        b = {label = "Post a Hunter", key = "jw_post_HUNT", off = why ~= nil, tip = why or ("A Knight joins the Hunt: +"
            .. J.HUNT_RATE .. "% a week against the hunted (to +" .. J.HUNT_MAX .. "%).")}
    elseif key == "HEALING" then
        local wait = (s.trance_at or -100) + J.TRANCE_EVERY - s.week
        table.insert(lines, (wait > 0) and ("A Healing Trance can be held again in " .. wait .. " weeks.")
            or "A Healing Trance can be held now: open a wounded Jedi's card.")
    elseif key == "WATCH" then
        posts("WATCH", "Watchmen")
        local why = Order.post_blocked(d, s, "WATCH")
        a = {label = "Post a Watchman", key = "jw_post_WATCH", off = why ~= nil, tip = why or ("A Knight watches over a "
            .. "sector: leads there come more often and warn before they go cold.")}
    elseif key == "GRAND" then
        local why = Order.vision_blocked(d, s)
        table.insert(lines, why or "A vision can be sought now: open a Jedi's card.")
    end
    return lines, {a, b}
end

function JW.render_council_choice(d, s, G)
    local flow = JW.flow
    if not (flow and (flow.regimen or flow.hunt or flow.post)) then
        render_chooser(d, s, G, nil)
        return
    end
    local rows, head = {}, ""
    if flow.regimen then
        head = "Choose the Regimen"
        for _, key in ipairs(J.REGIMEN_ORDER) do
            local r = J.REGIMENS[key]
            table.insert(rows, {text = r.name, pick = key, tip = r.text})
        end
    elseif flow.hunt then
        head = "Choose what to hunt"
        for _, t in ipairs(Order.hunt_targets(d, s)) do
            table.insert(rows, {text = t.name, pick = t, tip = "Hunt " .. t.name .. "."})
        end
    elseif flow.step == 1 then
        head = "Choose a Knight to post"
        for _, q in ipairs(Order.postable(d, s)) do
            table.insert(rows, {text = q.name, pick = q.id, tip = person_tip(d, s, q, "Click to post them.")})
        end
    elseif flow.post == "ENVOY" then
        head = "Choose where they go"
        local seen = {}
        for _, w in ipairs(U.worlds_of(d.human)) do
            if Order.peopled(w.key) then
                seen[w.key] = true
                table.insert(rows, {text = d:planet_name(w.planet), pick = w.key, world = w.key,
                                    tip = "A member world of the Republic."})
            end
        end
        local Envoys = Republic().part("envoys")
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            local k = U.key(planet)
            if not seen[k] and Envoys and Envoys.power_capital and Envoys.power_capital(d, planet) then
                table.insert(rows, {text = d:planet_name(planet) .. " (" .. d.display_name(planet.Get_Owner().Get_Faction_Name())
                    .. ")", pick = k, world = k, tip = "A foreign court."})
            end
        end
    elseif flow.post == "WATCH" then
        head = "Choose the world they watch from"
        for _, w in ipairs(U.worlds_of(d.human)) do
            local sector = U.sector_of(w.key)
            if sector then
                table.insert(rows, {text = d:planet_name(w.planet), pick = w.key, world = w.key,
                                    tip = "From " .. d:planet_name(w.planet) .. ", they watch over the " .. sector .. "."})
            end
        end
        table.sort(rows, function(a, b) return a.text < b.text end)
    end
    render_chooser(d, s, G, rows, head)
end

local REL_LINE = 82
local function relic_rows(s)
    local list = {}
    for _, item in ipairs((Order.relics_state(s).list) or {}) do
        table.insert(list, item)
    end
    table.sort(list, function(a, b)
        local ta, tb = Order.relic_def(a).tier, Order.relic_def(b).tier
        if ta ~= tb then
            return ta > tb
        end
        return a.id < b.id
    end)
    return list
end

local function render_reliquary(d, s, G)
    local L = G.L
    local list = relic_rows(s)
    local tiers = Order.relics_tiers or {"Minor", "Major", "Fabled"}
    G.text("dp_nr_jtr_head", "The Reliquary (" .. table.getn(list) .. ")")
    local max_go = M.max(0, table.getn(list) - L.rel_rows)
    JW.rel_go = M.max(0, M.min(JW.rel_go or 0, max_go))
    JW.rel_max = max_go
    JW.rel_rows = {}
    local chosen = nil
    for _, item in ipairs(list) do
        if item.id == JW.relic then
            chosen = item
        end
    end
    for k = 1, L.rel_rows do
        local item = list[k + JW.rel_go]
        local base = "dp_nr_jtr_r" .. k
        G.show(base, item ~= nil)
        G.show(base .. "_s", item ~= nil)
        G.show(base .. "_hit", item ~= nil)
        if item then
            JW.rel_rows[k] = item.id
            G.text(base, Order.relic_known_name(item))
            G.color(base, (item == chosen) and WHITE_C or ((item.sealed or item.stolen_by) and GREY_C or GOLD_C))
            G.text(base .. "_s", tiers[Order.relic_def(item).tier] .. ", " .. Order.relic_state_word(s, item))
            G.tip(base .. "_hit", Order.relic_known_name(item) .. ". Click to see it.")
        end
    end
    local segs = L.rel_segs
    local len = M.max(2, M.floor(segs * L.rel_rows / M.max(1, table.getn(list))))
    local first = (max_go > 0) and (M.round((segs - len) * JW.rel_go / max_go) + 1) or 1
    for k = 1, segs do
        G.show("dp_nr_jtr_s" .. k, max_go > 0)
        if max_go > 0 then
            G.icon("dp_nr_jtr_s" .. k, (k >= first and k < first + len) and "dp_scroll_thumb.tga" or "dp_scroll_track.tga")
            G.tip("dp_nr_jtr_s" .. k, "Click to jump, or use the wheel.")
        end
    end
    G.show("dp_nr_jtr_up", JW.rel_go > 0)
    G.show("dp_nr_jtr_down", JW.rel_go < max_go)
    local lore = Order.lore_master(s)
    G.show("dp_nr_jtr_img", chosen ~= nil)
    G.show("dp_nr_jtr_ped", true)
    local lines = {}
    if not chosen then
        G.text("dp_nr_jtr_title", "The Reliquary")
        G.text("dp_nr_jtr_sub", lore and ("Kept by " .. Order.label(lore) .. ", Master of the Archives.") or "No Master of the Archives keeps it.")
        wrap("Artifacts found on Recover the Lore, and in the dark places Confront the Darkness and Cleanse a Dark Site "
            .. "reach, come here unknown. The Master of the Archives researches them one step at a time: their story and first "
            .. "effect, then the rest. Only with a Master of the Archives do their effects work; a dark one's darkness works from "
            .. "the day it is found. Click an artifact on the left.", lines, REL_LINE)
        for k = 1, L.rel_effects do
            G.text("dp_nr_jtr_e" .. k, " ")
        end
        for k = 1, 3 do
            G.show("dp_nr_jtr_b" .. k, false)
        end
        G.text("dp_nr_jtr_note", (table.getn(list) == 0) and "The Reliquary is empty." or " ")
    else
        local def = Order.relic_def(chosen)
        G.text("dp_nr_jtr_title", Order.relic_known_name(chosen))
        G.text("dp_nr_jtr_sub", tiers[def.tier] .. " artifact, found on " .. Order.world_name(d, chosen.world) .. " in week "
            .. (chosen.week or 0) .. ". " .. Order.relic_state_word(s, chosen) .. ".")
        G.icon("dp_nr_jtr_img", "dp_rel_" .. def.kind .. ".tga")
        G.tip("dp_nr_jtr_img", Order.relic_known_name(chosen) .. ".")
        if chosen.step >= 1 then
            wrap(def.desc, lines, REL_LINE)
            wrap(def.history, lines, REL_LINE)
        else
            wrap("Its story is unknown. The Master of the Archives can research it.", lines, REL_LINE)
        end
        for k = 1, L.rel_effects do
            local e = def.effects[k]
            local name = "dp_nr_jtr_e" .. k
            if not e then
                G.text(name, " ")
                G.tip(name, " ")
            elseif chosen.step < k then
                G.text(name, k .. ". ???")
                G.color(name, GREY_C)
                G.tip(name, "Unknown: research it to learn what it does.")
            else
                local on = Order.relic_active(s, chosen, k, def)
                local spent = chosen.spent and chosen.spent[k]
                G.text(name, k .. ". " .. (e.dark and "Dark: " or "") .. e.text .. (spent and " (spent)" or "")
                    .. ((not on and not spent and not e.dark and not lore) and " (needs a Master of the Archives)" or ""))
                G.color(name, on and (e.dark and {0.95, 0.45, 0.4} or PALE_C) or GREY_C)
                G.tip(name, e.text)
            end
        end
        local function button(k, label, key, why, tip)
            G.show("dp_nr_jtr_b" .. k, true)
            G.text("dp_nr_jtr_b" .. k, label)
            G.color("dp_nr_jtr_b" .. k, why and GREY_C or GOLD_C)
            G.tip("dp_nr_jtr_b" .. k, why or tip)
            JW.rel_buttons = JW.rel_buttons or {}
            JW.rel_buttons[k] = {key = key, off = why ~= nil, tip = why or tip}
        end
        JW.rel_buttons = {}
        local cost = Order.relics_research_cost and Order.relics_research_cost(def.tier) or {0, 0}
        button(1, "Research", "jw_rel_research", Order.research_blocked(d, s, chosen),
            "The Master of the Archives studies it: " .. cost[1] .. " weeks and " .. cost[2] .. " Knowledge for the next step.")
        local usable = Order.relic_usable(s, chosen)
        button(2, "Use", "jw_rel_use", (not usable) and "Nothing in it can be used now (its single-use effects, once known)." or nil,
            "Call on its single use: " .. ((usable and def.effects[usable].text) or "") .. " Once spent, it is gone.")
        button(3, "Seal Away", "jw_rel_seal", (chosen.sealed or chosen.stolen_by) and "It is beyond reach." or nil,
            "Lock it away for good: every effect ends, and it can never be undone. Sealing a dark artifact may darken the "
            .. "Master of the Archives.")
        local research = Order.relics_state(s).research
        G.text("dp_nr_jtr_note", (research and research.id == chosen.id) and ("Being researched: " .. M.max(0, research.ends - s.week)
            .. " weeks left.") or (lore and " " or "Seat a Master of the Archives to research it and wake its effects."))
    end
    for k = 1, L.rel_lines do
        G.text("dp_nr_jtr_h" .. k, lines[k] or " ")
        G.tip("dp_nr_jtr_h" .. k, table.concat(lines, " "))
    end
end

function JW.render(d, s, G)
    JW.G = G
    local page = JW.page
    if page == "council" and not s.council.open then
        page, JW.page = "order", "order"
    end
    G.show("dp_nr_jt_shell", true)
    G.show("dp_nr_jto_shell", page == "order")
    G.show("dp_nr_jts_shell", page == "order")
    if page ~= "order" then
        G.show("dp_nr_jtb_shell", false)
        G.show("dp_nr_jth_shell", false)
        JW.hmax = 0
    end
    G.show("dp_nr_jtm_shell", page == "missions")
    if page ~= "missions" then
        G.show("dp_nr_jtmc_shell", false)
        G.show("dp_nr_jtw_shell", false)
    end
    G.show("dp_nr_jtt_shell", page == "teachings")
    G.show("dp_nr_jtk_shell", page == "council")
    G.show("dp_nr_jtr_shell", page == "reliquary")
    local council_choice = page == "council" and JW.flow and (JW.flow.regimen or JW.flow.post or JW.flow.hunt)
    G.show("dp_nr_jtp_shell", page == "teachings" or (page == "council" and not council_choice))
    for k, key in ipairs({"order", "missions", "teachings", "council", "reliquary"}) do
        local name = "dp_nr_jt_page" .. k
        G.text(name, ({"The Order", "Missions", "Teachings", "Council", "Reliquary"})[k])
        G.color(name, (page == key) and WHITE_C or ((key == "council" and not s.council.open) and GREY_C or GOLD_C))
    end
    G.tip("dp_nr_jt_page5", "The Reliquary: the artifacts the Order has found.")
    G.tip("dp_nr_jt_page1", "Who the Jedi are and what they are doing.")
    G.tip("dp_nr_jt_page2", "Send the Jedi out, and see who is away.")
    G.tip("dp_nr_jt_page3", "What the Order becomes: its Teachings and its Charter.")
    G.tip("dp_nr_jt_page4", s.council.open and "The Jedi Council: seven seats, each with its own work, held for life."
        or ("The Masters will ask for a Council once the Order has " .. J.COUNCIL_MASTERS .. " of them."))
    if page == "order" then
        render_order(d, s, G)
    else
        hide_cards(G)
        if page == "missions" then
            render_missions(d, s, G)
        elseif page == "teachings" then
            render_teachings(d, s, G)
        elseif page == "reliquary" then
            render_reliquary(d, s, G)
        else
            render_council(d, s, G)
            JW.render_council_choice(d, s, G)
        end
    end
    if page == "order" and JW.flow and JW.flow.assign then
        local rows = {}
        for _, e in ipairs(Order.eligible(d, s)) do
            table.insert(rows, {text = e.name, pick = e.key, tip = e.name .. " joins at their own rank, and goes to the Temple."})
        end
        G.show("dp_nr_jtmc_shell", false)
        render_chooser(d, s, G, rows, "Choose a hero")
    elseif page == "order" and JW.flow and JW.flow.attach_of then
        local rows = {}
        for _, w in ipairs(Order.fleet_worlds(d)) do
            table.insert(rows, {text = d:planet_name(w.planet), pick = w.key, world = w.key,
                                tip = "Join the fleet at " .. d:planet_name(w.planet) .. "."})
        end
        G.show("dp_nr_jtmc_shell", false)
        render_chooser(d, s, G, rows, "Choose a fleet")
    elseif page == "order" then
        render_chooser(d, s, G, nil)
    end
end

local function vbar(x, y, down, key, bx, top, segs, max_go)
    if down ~= 1 then
        JW.vdrag = nil
        return nil
    end
    local bottom = top - segs * 10
    if not JW.vdown and M.abs(x - bx) <= 9 and y <= top and y >= bottom then
        JW.vdrag = key
    end
    if JW.vdrag ~= key or max_go <= 0 then
        return nil
    end
    return M.round(U.clamp((top - y) / M.max(1, top - bottom), 0, 1) * max_go)
end

function JW.tick(x, y, down, wheel)
    local G = JW.G
    if G and x and y then
        local L = G.L
        local moved = false
        local function set(field, value)
            if value and value ~= JW[field] then
                JW[field], moved = value, true
            end
        end
        if JW.page == "missions" and JW.choices and L.pick_bar_x then
            set("list", vbar(x, y, down, "pick", L.pick_bar_x, L.pick_bar_top, L.pick_segs, JW.list_max or 0))
        end
        if JW.page == "missions" then
            set("go", vbar(x, y, down, "run", L.run_bar_x, L.run_bar_top, L.run_bar_segs, JW.go_max or 0))
            if wheel and wheel ~= 0 and x < L.run_bar_x + 12 and (JW.go_max or 0) > 0 then
                set("go", M.max(0, M.min(JW.go_max, (JW.go or 0) - (wheel > 0 and 1 or -1))))
            end
        end
        if JW.page == "reliquary" then
            set("rel_go", vbar(x, y, down, "rel", L.rel_bar_x, L.rel_bar_top, L.rel_segs, JW.rel_max or 0))
        end
        JW.vdown = down == 1
        if moved then
            return true
        end
        if JW.page == "missions" and wheel and wheel ~= 0 and x < L.run_bar_x + 12 then
            return false
        end
    end
    if G and JW.page == "reliquary" and wheel and wheel ~= 0 and (JW.rel_max or 0) > 0 then
        local before = JW.rel_go or 0
        JW.rel_go = M.max(0, M.min(JW.rel_max, before - (wheel > 0 and 1 or 0) + (wheel < 0 and 1 or 0)))
        return JW.rel_go ~= before
    end
    if G and JW.choices and wheel and wheel ~= 0 and (JW.list_max or 0) > 0 then
        local before = JW.list
        JW.list = M.max(0, M.min(JW.list_max, JW.list - (wheel > 0 and 1 or 0) + (wheel < 0 and 1 or 0)))
        if JW.list ~= before then
            return true
        end
    end
    if JW.page ~= "order" or not G or (JW.hmax or 0) <= 0 then
        JW.hdrag = false
        return false
    end
    local L = G.L
    local before = JW.scroll
    local over = y > L.hbar_y - 10 and y < L.gm + 30 and x > L.hbar_x0 and x < L.hbar_x1
    if wheel and wheel ~= 0 and over then
        JW.scroll = M.max(0, M.min(JW.hmax, JW.scroll - (wheel > 0 and 1 or -1)))
    end
    if down ~= 1 then
        JW.hdrag = false
    else
        local x0, x1 = L.hbar_x0 + 18, L.hbar_x1 - 18
        if not JW.was_down then
            JW.hdrag = M.abs(y - L.hbar_y) <= 8 and x >= x0 and x <= x1
        end
        if JW.hdrag then
            local seg = (x1 - x0) / L.hbar_segs
            local len = (JW.hlen or 2) * seg
            local share = U.clamp((x - x0 - len / 2) / M.max(1, (x1 - x0) - len), 0, 1)
            JW.scroll = M.round(share * JW.hmax)
        end
    end
    JW.was_down = down == 1
    return JW.scroll ~= before
end

local function send(d, s, along)
    local flow = JW.flow
    local world = target_world(d, s, flow)
    local ok, message = Order.start(d, s, Order.get(s, flow.jedi), flow.mission, flow.target, world, along, flow.lead)
    if ok then
        JW.flow, JW.sel, JW.preset = nil, nil, nil
    end
    return message
end

local function run_action(d, s, key)
    local sel = JW.sel or ""
    local p = string.find(sel, "^P_") and Order.get(s, tonumber(string.sub(sel, 3))) or nil
    if key == "jw_back" then
        local flow = JW.flow
        if flow and flow.mission and flow.step > 1 and not (flow.step == 2 and JW.preset) then
            flow.step = flow.step - 1
        else
            JW.flow, JW.sel, JW.preset = nil, nil, nil
        end
    elseif key == "jw_confirm" then
        return send(d, s, false)
    elseif key == "jw_confirm_along" then
        return send(d, s, true)
    elseif key == "jw_close_run" then
        JW.run_sel = nil
    elseif key == "jw_run_find" then
        local q = JW.run_sel and Order.get(s, JW.run_sel)
        local world = q and Order.location(d, q)
        if q and not world then
            return q.name .. " is between worlds: in hyperspace."
        end
        return nil, world
    elseif key == "jw_call_home" then
        local q = JW.run_sel and Order.get(s, JW.run_sel)
        JW.run_sel = nil
        return q and Order.recall(d, s, q)
    elseif key == "jw_learn" then
        local _, _, path, tier = string.find(sel, "^T_(%a+)_(%d)$")
        return path and Order.learn(d, s, path, tonumber(tier))
    elseif key == "jw_charter_a" or key == "jw_charter_b" then
        for _, q in ipairs(J.CHARTER) do
            if q.key == string.sub(sel, 3) then
                return Order.decide_charter(d, s, q, string.sub(key, -1))
            end
        end
    elseif key == "jw_appoint" then
        JW.flow = {seat = string.sub(sel, 3)}
    elseif key == "jw_regimen" then
        JW.flow, JW.list = {regimen = true}, 0
    elseif key == "jw_reliquary" then
        JW.page, JW.sel, JW.flow = "reliquary", nil, nil
    elseif key == "jw_hunt" then
        JW.flow, JW.list = {hunt = true}, 0
    elseif key == "jw_end_hunt" then
        Order.end_hunt(d, s)
        return "The Hunt is called off."
    elseif string.find(key, "^jw_post_") then
        JW.flow, JW.list = {post = string.sub(key, 9), step = 1}, 0
    elseif key == "jw_rel_research" or key == "jw_rel_use" or key == "jw_rel_seal" then
        local item = nil
        for _, it in ipairs((Order.relics_state(s).list) or {}) do
            if it.id == JW.relic then
                item = it
            end
        end
        if not item then
            return nil
        end
        if key == "jw_rel_research" then
            return Order.research(d, s, item)
        elseif key == "jw_rel_use" then
            return Order.use_relic(d, s, item)
        end
        return Order.seal(d, s, item)
    elseif key == "jw_unseat" then
        for _, seat in ipairs(J.SEATS) do
            if seat.key == string.sub(sel, 3) then
                return Order.unseat(s, seat)
            end
        end
    elseif p then
        if key == "jw_send" then
            JW.page, JW.preset, JW.sel, JW.flow = "missions", p.id, nil, nil
            return "Choose a mission for " .. p.name .. "."
        elseif key == "jw_student" then
            JW.flow, JW.sel = {student_of = p.id}, nil
        elseif key == "jw_leave" then
            return Order.leave_master(s, p)
        elseif key == "jw_watch" then
            JW.flow, JW.sel = {watch_of = p.id}, nil
        elseif key == "jw_unwatch" then
            p.watch = nil
            return "Their Master steps back. " .. p.name .. " is trusted to find their own way."
        elseif key == "jw_holocron" then
            return Order.raise_with_holocron(d, s, p)
        elseif key == "jw_trial" then
            JW.sel = nil
            return Order.start_trial(d, s, p)
        elseif key == "jw_turn_away" then
            JW.sel = nil
            return Order.turn_away(s, p)
        elseif key == "jw_unpost" then
            JW.sel = nil
            return Order.unpost(d, s, p)
        elseif key == "jw_vision" then
            JW.sel = nil
            return Order.vision(d, s, p)
        elseif key == "jw_trance" then
            JW.sel = nil
            return Order.trance(d, s, p)
        elseif key == "jw_find" then
            local world = Order.location(d, p) or (p.command and p.command.world)
                or (p.along_of and Order.location(d, Order.get(s, p.along_of) or p))
            if not world then
                return p.name .. " is between worlds: in hyperspace."
            end
            return nil, world
        elseif key == "jw_meditate" then
            JW.sel = nil
            return Order.meditate(d, s, p)
        elseif key == "jw_counsel" then
            JW.sel = nil
            return Order.counsel(d, s, p)
        elseif key == "jw_retreat" then
            JW.sel = nil
            return Order.retreat(d, s, p)
        elseif key == "jw_attach" then
            JW.flow, JW.sel, JW.list = {attach_of = p.id}, nil, 0
        elseif key == "jw_recall_fleet" then
            JW.sel = nil
            return Order.recall_fleet(d, s, p)
        end
    end
    return nil
end

local function click_person(d, s, id)
    local p = Order.get(s, id)
    local flow = JW.flow
    if flow and flow.student_of then
        if not (p and offered(s, p)) then
            return p and (Order.untakeable(s, p) or (p.name .. " is away.")) or nil
        end
        local master = Order.get(s, flow.student_of)
        JW.flow = nil
        if master then
            local _, message = Order.take_student(d, s, master, p)
            return message
        end
    elseif flow and flow.watch_of then
        if not (p and offered(s, p)) then
            return p and (p.name .. " cannot keep watch.") or nil
        end
        local charge = Order.get(s, flow.watch_of)
        JW.flow = nil
        if charge then
            charge.watch = p.id
            return "A Master keeps watch over " .. charge.name .. "."
        end
    else
        local key = "P_" .. id
        JW.sel = (JW.sel ~= key) and key or nil
    end
    return nil
end

function JW.click(d, s, name)
    JW.quiet = false
    local _, _, page = string.find(name, "^dp_nr_jt_page(%d)$")
    if page then
        local to = ({"order", "missions", "teachings", "council", "reliquary"})[tonumber(page)]
        if to == "council" and not s.council.open then
            return "The Masters will ask for a Council once the Order has " .. J.COUNCIL_MASTERS .. " of them."
        end
        JW.page, JW.sel, JW.flow, JW.preset, JW.run_sel, JW.leads_open = to, nil, nil, nil, nil, false
        JW.list, JW.strip, JW.go = 0, 0, 0
        return nil
    end
    local _, _, action = string.find(name, "^dp_nr_jtc%d+_%d+_a(%d+)$")
    if action then
        local a = JW.actions and JW.actions[tonumber(action)]
        if a and a.off then
            return a.tip
        elseif a then
            local message, world = run_action(d, s, a.key)
            return message, world
        end
        return nil
    end
    if string.find(name, "^dp_nr_jtc%d+_%d+_") then
        if string.find(name, "_x$") then
            JW.sel = nil
        else
            JW.quiet = true
        end
        return nil
    end
    local hit = JW.hits[name] or JW.hits[(string.gsub(name, "_n[123]$", ""))]
    if hit then
        local kind, id = string.sub(hit, 1, 2), string.sub(hit, 3)
        if kind == "P_" then
            return click_person(d, s, tonumber(id))
        elseif kind == "R_" then
            id = tonumber(id)
            JW.run_sel = (JW.run_sel ~= id) and id or nil
            JW.flow, JW.preset = nil, nil
            return nil
        elseif kind == "F_" then
            JW.flow.jedi, JW.flow.step, JW.list = tonumber(id), JW.flow.lead and 3 or 2, 0
            return nil
        elseif kind == "S_" then
            JW.sel, JW.flow = (JW.sel ~= hit) and hit or nil, nil
            return nil
        elseif kind == "K_" then
            local seat_key = JW.flow and JW.flow.seat
            local m = Order.get(s, tonumber(id))
            JW.flow = nil
            for _, seat in ipairs(J.SEATS) do
                if seat.key == seat_key and m then
                    return Order.seat(d, s, seat, m)
                end
            end
            return nil
        end
    end
    local closed = JW.page == "order" and JW.dismiss()
    if name == "dp_nr_shield" or string.find(name, "^dp_nr_jt_") or string.find(name, "^dp_nr_jto_lab")
            or string.find(name, "^dp_nr_jto_top") or name == "dp_nr_jtb_head" or name == "dp_nr_jto_flab" then
        JW.quiet = not closed
        return nil
    end
    local _, _, rel_row = string.find(name, "^dp_nr_jtr_r(%d+)")
    if rel_row then
        JW.relic = JW.rel_rows and JW.rel_rows[tonumber(rel_row)]
        return nil
    elseif name == "dp_nr_jtr_up" then
        JW.rel_go = M.max(0, (JW.rel_go or 0) - 1)
        return nil
    elseif name == "dp_nr_jtr_down" then
        JW.rel_go = (JW.rel_go or 0) + 1
        return nil
    elseif string.find(name, "^dp_nr_jtr_s%d+") then
        local _, _, k = string.find(name, "^dp_nr_jtr_s(%d+)")
        k = tonumber(k)
        JW.rel_go = M.round((k - 1) / M.max(1, ((JW.G and JW.G.L.rel_segs) or 1) - 1) * (JW.rel_max or 0))
        return nil
    end
    local _, _, rel_b = string.find(name, "^dp_nr_jtr_b(%d)$")
    if rel_b then
        local b = JW.rel_buttons and JW.rel_buttons[tonumber(rel_b)]
        if b and b.off then
            return b.tip
        end
        return b and run_action(d, s, b.key)
    end
    if string.find(name, "^dp_nr_jtr_") then
        JW.quiet = true
        return nil
    end
    if name == "dp_nr_jto_vigil" then
        return Order.vigil(d, s)
    elseif name == "dp_nr_jtm_leads" then
        JW.leads_open, JW.flow, JW.run_sel, JW.list = not JW.leads_open, nil, nil, 0
        return nil
    elseif name == "dp_nr_jto_cancel" then
        JW.flow = nil
    elseif name == "dp_nr_jto_assign" then
        JW.flow, JW.sel, JW.list = {assign = true}, nil, 0
    elseif name == "dp_nr_jth_left" then
        JW.scroll = M.max(0, JW.scroll - 1)
    elseif name == "dp_nr_jth_right" then
        JW.scroll = M.min(JW.hmax or 0, JW.scroll + 1)
    elseif string.find(name, "^dp_nr_jth_s%d+$") then
        local k = tonumber(string.sub(name, 12))
        JW.scroll = M.round((k - 1) / M.max(1, (JW.G and JW.G.L.hbar_segs or 40) - 1) * (JW.hmax or 0))
    elseif name == "dp_nr_jtb_left" then
        JW.bpage = M.max(0, JW.bpage - 1)
    elseif name == "dp_nr_jtb_right" then
        JW.bpage = JW.bpage + 1
    elseif name == "dp_nr_jtm_rup" then
        JW.go = M.max(0, JW.go - 1)
    elseif name == "dp_nr_jtm_rdown" then
        JW.go = JW.go + 1
    elseif string.find(name, "^dp_nr_jtm_rs%d+") then
        local _, _, k = string.find(name, "^dp_nr_jtm_rs(%d+)")
        k = tonumber(k)
        local segs = (JW.G and JW.G.L.run_bar_segs) or 1
        JW.go = M.round((k - 1) / M.max(1, segs - 1) * (JW.go_max or 0))
    elseif name == "dp_nr_jtm_sleft" then
        JW.strip = M.max(0, JW.strip - 1)
    elseif name == "dp_nr_jtm_sright" then
        JW.strip = JW.strip + 1
    elseif name == "dp_nr_jtw_up" then
        JW.list = M.max(0, JW.list - 1)
    elseif name == "dp_nr_jtw_down" then
        JW.list = JW.list + 1
    elseif string.find(name, "^dp_nr_jtw_s%d+") then
        local _, _, k = string.find(name, "^dp_nr_jtw_s(%d+)")
        k = tonumber(k)
        local segs = (JW.G and JW.G.L.pick_segs) or 1
        JW.list = M.round((k - 1) / M.max(1, segs - 1) * (JW.list_max or 0))
    else
        local _, _, card = string.find(name, "^dp_nr_jtm_c(%d+)_hit$")
        if card then
            local key = J.MISSION_ORDER[tonumber(card)]
            local why = Order.mission_closed(d, s, key)
            if why then
                return why
            end
            JW.run_sel = nil
            if JW.flow and JW.flow.mission == key then
                JW.flow = nil
            else
                local preset = JW.preset and Order.get(s, JW.preset)
                if preset and J.MISSIONS[key].master and preset.rank < J.MASTER then
                    return "Only a Master can go on " .. J.MISSIONS[key].name .. "."
                end
                JW.flow = {mission = key, step = JW.preset and 2 or 1, jedi = JW.preset}
            end
            JW.list, JW.strip = 0, 0
            return nil
        end
        local _, _, button = string.find(name, "^dp_nr_jtm_b(%d)$")
        if button then
            local key = JW.buttons and JW.buttons[tonumber(button)]
            if key then
                return run_action(d, s, key)
            end
            return nil
        end
        local _, _, row, part = string.find(name, "^dp_nr_jtw_r(%d+)_(%a+)$")
        if row then
            local per = 2 * (JW.pick_rows or 8)
            local r = JW.choices and JW.choices[JW.list * per + JW.slot_index(tonumber(row), JW.pick_rows or 8)]
            if not r then
                return nil
            end
            if part == "zoom" then
                return nil, r.world
            end
            if r.pick == false then
                return r.tip
            end
            local flow = JW.flow
            if r.lead and not flow then
                local l = r.lead
                JW.leads_open = false
                if J.MISSIONS[l.mission].master and JW.preset and Order.get(s, JW.preset)
                        and Order.get(s, JW.preset).rank < J.MASTER then
                    return "Only a Master can go on " .. J.MISSIONS[l.mission].name .. "."
                end
                JW.flow = {mission = l.mission, step = JW.preset and 3 or 1, jedi = JW.preset, target = l.target,
                           lead = l.id, lead_world = l.world, lead_title = l.title, lead_text = l.text}
                return nil
            elseif flow and flow.mission then
                flow.target, flow.step = r.pick, 3
                if r.lead then
                    flow.lead, flow.lead_world, flow.lead_title, flow.lead_text = r.lead.id, r.lead.world, r.lead.title, r.lead.text
                else
                    flow.lead, flow.lead_world, flow.lead_title, flow.lead_text = nil, nil, nil, nil
                end
            elseif flow and flow.attach_of then
                JW.flow = nil
                local q = Order.get(s, flow.attach_of)
                return q and Order.attach_fleet(d, s, q, r.pick)
            elseif flow and flow.regimen then
                JW.flow = nil
                return Order.set_regimen(d, s, r.pick)
            elseif flow and flow.hunt then
                JW.flow = nil
                return Order.declare_hunt(d, s, r.pick.kind, r.pick.target, r.pick.name)
            elseif flow and flow.post and flow.step == 1 then
                flow.knight, flow.step, JW.list = r.pick, 2, 0
                if flow.post == "HUNT" then
                    JW.flow = nil
                    local q = Order.get(s, r.pick)
                    return q and Order.post(d, s, q, "HUNT")
                end
                return nil
            elseif flow and flow.post and flow.step == 2 then
                JW.flow = nil
                local q = Order.get(s, flow.knight)
                return q and Order.post(d, s, q, flow.post, r.pick)
            elseif flow and flow.assign then
                JW.flow = nil
                local _, message = Order.assign(d, s, r.pick)
                return message
            end
            return nil
        end
        local _, _, panel = string.find(name, "^dp_nr_jtp_a(%d)$")
        if panel then
            local a = JW.panel_buttons and JW.panel_buttons[tonumber(panel)]
            if a and a.off then
                return a.tip
            elseif a then
                return run_action(d, s, a.key)
            end
            return nil
        end
        local _, _, i, tier = string.find(name, "^dp_nr_jtt_n(%d)_(%d)")
        if i then
            local key = "T_" .. J.TEACHING_PATHS[tonumber(i)] .. "_" .. tier
            JW.sel = (JW.sel ~= key) and key or nil
            return nil
        end
        local _, _, q = string.find(name, "^dp_nr_jtt_q(%d)")
        if q then
            local key = "C_" .. J.CHARTER[tonumber(q)].key
            JW.sel = (JW.sel ~= key) and key or nil
            return nil
        end
        JW.quiet = not closed
    end
    return nil
end

return JW
