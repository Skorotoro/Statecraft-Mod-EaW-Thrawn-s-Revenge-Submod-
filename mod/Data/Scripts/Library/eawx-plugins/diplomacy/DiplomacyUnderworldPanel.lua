local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local K = require("eawx-plugins/diplomacy/DiplomacyKajidii")
local U = require("eawx-plugins/diplomacy/DiplomacyUnderworld")
local LAYOUT = require("eawx-plugins/diplomacy/DiplomacyUnderworldLayout")

local R = CONFIG.UNDERWORLD
local Panel = {sel = nil, open = false, picking = nil, chosen = {}, refresh_at = 0, variant = nil}

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("UNDERWORLD PANEL gui error: " .. tostring(err))
    end
end

local function P(part)
    return "dp_uw" .. Panel.variant .. "_" .. part
end

local function show(name, visible)
    call(GUI_Component_Visibility, name, visible and true or false)
end

local function text(name, value)
    call(GUI_Component_Text, name, value or " ")
end

local function tip(name, value)
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_" .. string.upper(name) .. "_TIP", value or " ")
    end
end

local function slot_tip(k, value)
    for _, part in ipairs({"", "_icon", "_text"}) do
        tip(P("slot_" .. k .. part), value)
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

local function color(name, gold)
    if gold then
        call(GUI_Text_Color, name, 0.95, 0.80, 0.40, 1)
    else
        call(GUI_Text_Color, name, 0.75, 0.77, 0.80, 1)
    end
end

local function grey(name, off)
    if off then
        call(GUI_Text_Color, name, 0.45, 0.45, 0.48, 1)
    else
        call(GUI_Text_Color, name, 0.92, 0.82, 0.59, 1)
    end
end

local function weeks_left(t)
    return M.max(1, M.floor((t - GetCurrentTime()) / CONFIG.WEEK_SECONDS + 0.999))
end

local function pick_variant()
    local width = 1365
    if Engine_Screen_Size then
        local w, h = Engine_Screen_Size()
        if w and h and h > 0 then
            width = 768 * w / h
        end
    end
    local best, gap = "169", nil
    for v, wv in pairs(LAYOUT.variants) do
        local g = M.abs(wv - width)
        if not gap or g < gap then
            best, gap = v, g
        end
    end
    return best
end

local function hide_variant(v)
    show("dp_uw" .. v .. "_shell", false)
    show("dp_uw" .. v .. "_toggle_shell", false)
end

local function render_choices(d, rec)
    local built = {}
    for _, s in pairs(rec.structures) do
        if s then
            built[s.key] = true
        end
    end
    Panel.choices = {}
    local k = 0
    for _, key in ipairs(R.STRUCTURE_ORDER) do
        if not built[key] and k < LAYOUT.slots then
            k = k + 1
            Panel.choices[k] = key
            local def = R.STRUCTURES[key]
            local blocked = U.build_blocked(d, rec, key)
            show(P("slot_" .. k), true)
            show(P("slot_" .. k .. "_icon"), true)
            show(P("slot_" .. k .. "_text"), true)
            icon(P("slot_" .. k), blocked and "dp_uw_slot_locked.tga" or "dp_uw_slot_pick.tga")
            icon(P("slot_" .. k .. "_icon"), def.icon)
            text(P("slot_" .. k .. "_text"), def.cost .. " cr")
            grey(P("slot_" .. k .. "_text"), blocked ~= nil)
            slot_tip(k, def.name .. " (" .. (def.advanced and "advanced, " or "") .. "the "
                .. U.family_name(U.INDEX[def.family]) .. "), " .. def.cost .. " credits, " .. def.weeks
                .. (def.weeks == 1 and " week" or " weeks") .. ": " .. def.desc .. " Opens the "
                .. R.OPERATIONS[def.op].name .. " operation; +" .. R.INFLUENCE_BUILD .. " influence when built."
                .. (blocked and (" " .. blocked) or ""))
        end
    end
    for n = k + 1, LAYOUT.slots do
        show(P("slot_" .. n), false)
        show(P("slot_" .. n .. "_icon"), false)
        show(P("slot_" .. n .. "_text"), false)
    end
end

local function state_line(d, rec)
    if rec.state == "founding" then
        return "Forming - " .. U.forming(rec) .. "%"
    elseif rec.state == "controlled" then
        return "Controlled by the " .. U.family_name(rec.family) .. " - level 5"
    end
    local next_ops = U.ops_to_next(rec)
    return "Contested - level " .. U.level(rec) .. (next_ops and (" (" .. next_ops .. " more operation"
        .. (next_ops == 1 and "" or "s") .. " to the next)") or " (ready for the Turf War)")
end

function Panel.render(d)
    local rec = Panel.sel and U.get(d, Panel.sel)
    local planet = Panel.sel and FindPlanet(Panel.sel)
    local v = pick_variant()
    if Panel.variant and Panel.variant ~= v then
        hide_variant(Panel.variant)
    end
    Panel.variant = v
    local bare = planet ~= nil and rec == nil and planet.Get_Owner() ~= d.human
    local visible = (rec ~= nil or bare) and not Panel.blocked
    show(P("toggle_shell"), visible)
    show(P("shell"), visible and Panel.open and rec ~= nil)
    if not visible or not planet then
        return
    end
    if not rec then
        local closed = U.closed(Panel.sel)
        show(P("toggle"), true)
        show(P("toggle_up"), false)
        text(P("toggle"), closed and "No underworld" or "Underworld: none")
        grey(P("toggle"), closed ~= nil)
        tip(P("toggle"), closed and ("No underworld can form here: " .. d:planet_name(planet) .. " is " .. closed .. ".")
            or ("No underworld here yet. Drop a Hutt Upstart on the orange ring over " .. d:planet_name(planet)
            .. " to start one."))
        return
    end
    grey(P("toggle"), false)
    show(P("toggle"), not Panel.open)
    show(P("toggle_up"), Panel.open)
    text(P("toggle"), "Underworld")
    text(P("toggle_up"), "Planet view")
    tip(P("toggle"), "Show your underworld on this world: its families, buildings and operations.")
    tip(P("toggle_up"), "Back to the world's own buildings.")
    if not Panel.open then
        return
    end
    local owner = planet.Get_Owner()
    local unlocked = U.unlocked(d, rec, planet)
    text(P("title"), Panel.picking and ("Choose a building for slot " .. Panel.picking)
        or ("Underworld of " .. d:planet_name(planet)))
    local info = {}
    if Panel.picking then
        table.insert(info, "Each building belongs to a family and opens its operation")
        table.insert(info, "Advanced: level " .. R.ADVANCED_LEVEL .. " and over " .. R.ADVANCED_SHARE
            .. "% for the family")
    else
        table.insert(info, state_line(d, rec))
        table.insert(info, unlocked .. " of " .. U.slots(d, planet) .. " slots")
        table.insert(info, d.display_name(owner.Get_Faction_Name()) .. " world")
        table.insert(info, "Unrest " .. M.floor(rec.unrest) .. "/" .. R.REVOLT_AT)
    end
    text(P("info"), table.concat(info, "     |     "))

    if Panel.picking then
        text(P("act"), "Cancel")
        icon(P("act"), "dp_uw_act.tga")
        grey(P("act"), false)
        tip(P("act"), "Back to the slots.")
    else
        local ok, Missions = pcall(require, "eawx-plugins/diplomacy/DiplomacyKajidicMissions")
        local turf = ok and Missions.def("turf_war")
        local blocked = U.turf_blocked(d, rec)
        local leader = U.leader_of(rec)
        if rec.turf then
            local m = ok and d.kj.missions[rec.turf.mission]
            text(P("act"), "Turf War " .. (m and Missions.weeks_left(m) or 1) .. "w")
        else
            text(P("act"), "Turf War " .. R.TURF_COST)
        end
        icon(P("act"), blocked and "dp_uw_act_off.tga" or "dp_uw_act.tga")
        grey(P("act"), blocked ~= nil)
        tip(P("act"), (turf and turf.desc or "") .. (leader and (" The " .. U.family_name(leader) .. " would fight, "
            .. U.turf_chance(rec) .. "% to win.") or "") .. (blocked and (" " .. blocked) or ""))
    end

    local _, leader = U.perk(d)
    local top = U.leader_of(rec)
    for i = 1, table.getn(K.FAMILIES) do
        local f = K.FAMILIES[i]
        local share
        if rec.state == "controlled" then
            share = (rec.family == i) and "rules" or "-"
        else
            share = M.floor((rec.influence[i] or 0) + 0.5) .. "%"
        end
        text(P("fam_" .. i .. "_text"), "   " .. f.name .. " " .. share)
        show(P("fam_" .. i .. "_boss"), leader == i)
        color(P("fam_" .. i .. "_text"), top == i)
        icon(P("fam_" .. i .. "_text"), (top == i) and "dp_uw_fam_sel.tga" or "dp_uw_fam.tga")
        local line = "The " .. f.name .. " kajidic: " .. string.lower(f.spec[1]) .. ". "
        if rec.state ~= "controlled" then
            line = line .. M.floor((rec.influence[i] or 0) + 0.5) .. "% of this underworld ("
                .. M.floor(100 - U.claimed(rec) + 0.5) .. "% unclaimed). "
        end
        if top == i then
            line = line .. "The strongest family here. "
        end
        if leader == i then
            line = line .. "The Boss Family (star): the faction leader is one of theirs. " .. R.LEADER_PERKS[f.key].desc
        end
        tip(P("fam_" .. i), line)
        tip(P("fam_" .. i .. "_text"), line)
        tip(P("fam_" .. i .. "_boss"), line)
    end

    local slots = U.slots(d, planet)
    Panel.op_keys = {}
    if Panel.picking then
        render_choices(d, rec)
        for i = 1, LAYOUT.ops do
            show(P("op_" .. i), false)
        end
    else
        for k = 1, LAYOUT.slots do
            local s = rec.structures[k]
            show(P("slot_" .. k), true)
            show(P("slot_" .. k .. "_icon"), true)
            show(P("slot_" .. k .. "_text"), true)
            if k > slots then
                icon(P("slot_" .. k), "dp_uw_slot_locked.tga")
                icon(P("slot_" .. k .. "_icon"), "dp_uw_none.tga")
                text(P("slot_" .. k .. "_text"), "no slot")
                grey(P("slot_" .. k .. "_text"), true)
                slot_tip(k, d:planet_name(planet) .. " has only " .. slots .. " ground slots.")
            elseif k > unlocked and not s then
                local needed = M.max(0, M.ceil((k - R.SLOTS_BASE) / R.SLOTS_PER_LEVEL))
                icon(P("slot_" .. k), "dp_uw_slot_locked.tga")
                icon(P("slot_" .. k .. "_icon"), "dp_uw_lock.tga")
                text(P("slot_" .. k .. "_text"), (rec.state == "founding") and "forming" or ("level " .. needed))
                grey(P("slot_" .. k .. "_text"), true)
                slot_tip(k, (rec.state == "founding") and "The underworld is still forming."
                    or ("Locked: this slot opens at underworld level " .. needed .. ". Levels come from "
                    .. "completed operations."))
            else
                icon(P("slot_" .. k), "dp_uw_slot.tga")
                if s then
                    local def = R.STRUCTURES[s.key]
                    icon(P("slot_" .. k .. "_icon"), def.icon)
                    text(P("slot_" .. k .. "_text"), (s.ready > GetCurrentTime()) and ("building " .. weeks_left(s.ready) .. "w")
                        or def.short or def.name)
                    grey(P("slot_" .. k .. "_text"), false)
                    slot_tip(k, def.name .. " (the " .. U.family_name(s.family) .. "): " .. def.desc)
                    if s.ready <= GetCurrentTime() then
                        Panel.op_keys[k] = def.op
                    end
                else
                    icon(P("slot_" .. k .. "_icon"), "dp_uw_empty.tga")
                    text(P("slot_" .. k .. "_text"), " ")
                    grey(P("slot_" .. k .. "_text"), false)
                    slot_tip(k, "An empty slot: click to build here.")
                end
            end
        end
        for i = 1, LAYOUT.ops do
            local key = Panel.op_keys[i]
            local def = key and R.OPERATIONS[key]
            show(P("op_" .. i), def ~= nil)
            if def then
                local cost = U.op_cost(d, rec, key)
                local blocked = U.op_blocked(d, rec, key, planet)
                local chance = U.op_chance(d, rec, key, owner)
                if rec.op and rec.op.key == key then
                    text(P("op_" .. i), def.name .. " " .. weeks_left(rec.op.ends) .. "w")
                else
                    text(P("op_" .. i), def.name)
                end
                icon(P("op_" .. i), blocked and "dp_uw_op_off.tga" or "dp_uw_op.tga")
                grey(P("op_" .. i), blocked ~= nil)
                tip(P("op_" .. i), def.name .. ", run by the " .. U.family_name(U.INDEX[def.family]) .. ": " .. def.desc
                    .. " Cost " .. cost .. " credits, " .. def.weeks .. (def.weeks == 1 and " week" or " weeks")
                    .. ", success " .. chance .. "%. Success: +" .. R.INFLUENCE_OP .. " influence for the family and "
                    .. (def.steps or 1) .. " towards the next level." .. (blocked and (" " .. blocked) or ""))
            end
        end
    end
    local note = Panel.feedback
    if not note then
        note = (leader and ("Boss Family (star): the " .. U.family_name(leader) .. ".") or "No Hutt leader: the council rules.")
            .. " Operations need their building; each family runs its own."
    end
    text(P("note"), note)
end

local function on_select(d, sel)
    Panel.sel, Panel.picking, Panel.feedback = sel, nil, nil
    local rec = sel and U.get(d, sel)
    if rec then
        if Panel.chosen[sel] ~= nil then
            Panel.open = Panel.chosen[sel]
        else
            local any = false
            for _, s in pairs(rec.structures) do
                if s then
                    any = true
                end
            end
            Panel.open = any
        end
    end
    Panel.render(d)
end

function Panel.tick(d, blocked)
    if not U.active(d) or not d.underworld then
        return
    end
    if (blocked and true or false) ~= (Panel.blocked and true or false) then
        Panel.blocked = blocked
        Panel.render(d)
        return
    end
    local sel = Panel.force or (Engine_Selected_Planet and Engine_Selected_Planet()) or nil
    local has = sel ~= nil and U.get(d, sel) ~= nil
    if sel ~= Panel.sel or has ~= Panel.had then
        Panel.had = has
        on_select(d, sel)
    elseif Panel.sel and GetCurrentTime() >= Panel.refresh_at then
        Panel.refresh_at = GetCurrentTime() + 1
        Panel.render(d)
    end
end

function Panel.click(d, name, button)
    if Engine_Log then
        Engine_Log("UNDERWORLD PANEL " .. tostring(button) .. " click " .. tostring(name))
    end
    if button == "right" or not Panel.sel then
        return
    end
    local part = string.gsub(name, "^dp_uw%d+_", "")
    Panel.feedback = nil
    local rec = U.get(d, Panel.sel)
    if (part == "toggle" or part == "toggle_up") and not rec then
        return
    elseif part == "toggle" or part == "toggle_up" then
        Panel.open = not Panel.open
        Panel.chosen[Panel.sel] = Panel.open
        Panel.picking = nil
    elseif part == "act" and rec then
        if Panel.picking then
            Panel.picking = nil
        else
            local ok, Missions = pcall(require, "eawx-plugins/diplomacy/DiplomacyKajidicMissions")
            local leader = U.leader_of(rec)
            if ok and leader then
                local _, message = Missions.start(d, "turf_war", leader, Panel.sel)
                Panel.feedback = message
            else
                Panel.feedback = U.turf_blocked(d, rec) or "No family is strong enough to fight for it."
            end
        end
    elseif string.find(part, "^fam_%d") and rec then
        local f = tonumber(string.sub(part, 5, 5))
        Panel.feedback = "The " .. U.family_name(f) .. ": " .. M.floor((rec.influence[f] or 0) + 0.5)
            .. "% here. Their buildings, operations and heroes raise it."
    elseif string.find(part, "^slot_%d") and rec then
        part = string.gsub(part, "_icon$", "")
        part = string.gsub(part, "_text$", "")
        local _, _, k = string.find(part, "^slot_(%d+)")
        k = tonumber(k)
        local planet = FindPlanet(Panel.sel)
        if Panel.picking then
            local key = Panel.choices and Panel.choices[k]
            if key then
                local built, message = U.build(d, Panel.sel, Panel.picking, key)
                Panel.feedback = message
                if built then
                    Panel.picking = nil
                end
            end
        elseif planet and k > U.unlocked(d, rec, planet) and not rec.structures[k] then
            Panel.feedback = (rec.state == "founding") and "The underworld is still forming."
                or "This slot opens at a higher underworld level."
        elseif rec.structures[k] then
            Panel.feedback = R.STRUCTURES[rec.structures[k].key].desc
        else
            Panel.picking = k
        end
    elseif string.find(part, "^op_%d") and rec then
        local _, _, i = string.find(part, "^op_(%d+)")
        local key = Panel.op_keys and Panel.op_keys[tonumber(i)]
        if key then
            local _, message = U.operate(d, Panel.sel, key)
            Panel.feedback = message
        end
    end
    Panel.render(d)
end

return Panel
