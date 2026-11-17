local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")
local Politics = require("eawx-plugins/imperial-court/CourtPolitics")
local Actions = require("eawx-plugins/imperial-court/CourtActions")
local Intel = require("eawx-plugins/imperial-court/CourtIntel")
local IW = require("eawx-plugins/imperial-court/CourtIntelWindow")
local Fleet = require("eawx-plugins/imperial-court/CourtFleet")
local Map = require("eawx-plugins/imperial-court/CourtMap")
local LAYOUT = require("eawx-plugins/imperial-court/CourtLayout")

local function optional(name)
    local ok, mod = pcall(require, name)
    return ok and mod or nil
end
local Pause = optional("eawx-plugins/diplomacy/DiplomacyPause")
local GLOBES = optional("eawx-plugins/diplomacy/DiplomacyGlobes") or {}
local LORE = require("eawx-plugins/imperial-court/CourtLore")

local Window = {open_now = false, tab = "realm", page = 1, sel = {}, petition = 1, filter = "all", more = false,
                wscroll = 0}
local SHELLS = {"dp_imp_shell", "dp_imp_list_shell", "dp_imp_bars_shell", "dp_imp_detail_shell", "dp_imp_succ_shell",
                "dp_imp_court_shell"}
local TAB_NAMES = {realm = "Realm", hierarchy = "Court", court = "Council", admiralty = "Admiralty",
                   factions = "Factions", legitimacy = "Legitimacy", intelligence = "Intelligence"}
local TAB_TIPS = {
    realm = "The oversectors, sectors and unsectored systems of the Empire, and who holds them.",
    hierarchy = "The court: every Grand Moff, Moff, Governor and Commander, and the officers without lands. Their loyalty, and why.",
    court = "The Council: the offices around the throne, who holds them, and what they do for you.",
    admiralty = "The fleet's commands: Grand Admirals, Admirals and Captains. Appointed officers get a flagship.",
    factions = "The factions among the lords, their demands, and the lords at risk of leaving.",
    legitimacy = "The Imperial powers' legitimacy, and the race to integrate the minor warlords.",
    intelligence = "Covert operations of Imperial Intelligence against other powers.",
}

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("COURT WINDOW gui error: " .. tostring(err))
    end
end

local cache = {shown = {}, text = {}, tip = {}, icon = {}, color = {}}
local pass = {texts = {}, tips = {}}

local function show(name, visible)
    visible = visible and true or false
    if cache.shown[name] == visible then
        return
    end
    cache.shown[name] = visible
    call(GUI_Component_Visibility, name, visible)
end

local CHARS = LAYOUT.chars or {}
local ROOM = LAYOUT.room or {}
local EM = 12.8
local NARROW = {["i"] = 0.24, ["l"] = 0.24, ["I"] = 0.3, ["j"] = 0.24, ["."] = 0.29, [","] = 0.29, [":"] = 0.29,
                [";"] = 0.29, ["'"] = 0.2, ["!"] = 0.29, ["|"] = 0.26, [" "] = 0.29, ["f"] = 0.3, ["t"] = 0.3,
                ["r"] = 0.35, ["("] = 0.35, [")"] = 0.35, ["-"] = 0.35, ["["] = 0.29, ["]"] = 0.29}
local WIDE = {["m"] = 0.86, ["w"] = 0.74, ["M"] = 0.86, ["W"] = 0.97, ["%"] = 0.9, ["@"] = 1.0}
local function letter(ch)
    local w = NARROW[ch] or WIDE[ch]
    if w then
        return w
    elseif string.find(ch, "%u") then
        return 0.69
    elseif string.find(ch, "%d") then
        return 0.56
    end
    return 0.53
end

local function text_width(value, size)
    local units = 0
    for i = 1, string.len(value) do
        units = units + letter(string.sub(value, i, i))
    end
    return units * EM * size / 7
end
Window.text_width = text_width

local function fit(name, value)
    local room = ROOM[name]
    if not room then
        local n = CHARS[name]
        if not n or string.len(value) <= n then
            return value
        end
        room = {n * 6, 7}
    end
    local limit = room[1] - 4
    if text_width(value, room[2]) <= limit then
        return value
    end
    local dots = text_width("...", room[2])
    local cut = value
    while string.len(cut) > 1 and text_width(cut, room[2]) + dots > limit do
        cut = string.sub(cut, 1, string.len(cut) - 1)
    end
    local whole = cut
    for i = string.len(cut), M.max(1, string.len(cut) - 16), -1 do
        if string.sub(cut, i, i) == " " then
            cut = string.sub(cut, 1, i - 1)
            break
        end
    end
    if string.len(cut) < string.len(whole) / 2 then
        cut = whole
    end
    cut = string.gsub(cut, "[%s,;:%-]+$", "")
    return cut .. "..."
end

local function sentence(value)
    value = string.gsub(value or "", "^%s+", "")
    if value == "" then
        return " "
    end
    value = string.gsub(value, "^%l", string.upper)
    if not string.find(value, "[%.!%?%)%%\"']$") then
        value = value .. "."
    end
    return value
end

local function tip(name, value)
    value = sentence(value)
    pass.tips[name] = true
    if cache.tip[name] == value then
        return
    end
    cache.tip[name] = value
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_" .. string.upper(name) .. "_TIP", value)
    end
end

local function text(name, value)
    local full = value or " "
    pass.texts[name] = full
    value = fit(name, full)
    if cache.text[name] == value then
        return
    end
    cache.text[name] = value
    call(GUI_Component_Text, name, value)
end

local function stability_thresholds()
    return {
        {CONFIG.UNGOVERNED.BELOW, "Threshold " .. CONFIG.UNGOVERNED.BELOW .. ": below it, crises strike the court (AWOL "
            .. "Moffs, risings) and unmanaged worlds may rise."},
        {CONFIG.CRISIS.PROCLAIM_BELOW, "Threshold " .. CONFIG.CRISIS.PROCLAIM_BELOW .. ": below it, lords may proclaim "
            .. "themselves warlords."},
        {CONFIG.UNREST.BELOW, "Threshold " .. CONFIG.UNREST.BELOW .. ": below it, unrest spreads to the worlds."},
        {CONFIG.UNREST.DEEP, "Threshold " .. CONFIG.UNREST.DEEP .. ": below it, the unrest runs deeper still."},
    }
end
local PULSE = {0, 1, 2, 3, 4, 3, 2, 1}

local function icon(name, texture)
    if cache.icon[name] == texture then
        return
    end
    cache.icon[name] = texture
    call(GUI_Button_Icon, name, texture, 1, 1, 1, 1)
end

local function color(name, r, g, b)
    local key = r .. "," .. g .. "," .. b
    if cache.color[name] == key then
        return
    end
    cache.color[name] = key
    call(GUI_Text_Color, name, r, g, b, 1)
end

local function finish_tips()
    for name, full in pairs(pass.texts) do
        if not pass.tips[name] then
            tip(name, (full ~= " ") and full or " ")
        end
        pass.tips[name] = nil
    end
    pass.texts, pass.tips = {}, {}
end

local function cap(value)
    return (string.gsub(value or "", "^%l", string.upper))
end

local function pale(name)
    color(name, 0.84, 0.86, 0.9)
end

local function grey(name)
    color(name, 0.45, 0.45, 0.48)
end

local function loyalty_color(name, v)
    if v >= 60 then
        color(name, 0.55, 0.85, 0.6)
    elseif v >= 40 then
        color(name, 0.92, 0.82, 0.45)
    else
        color(name, 0.95, 0.45, 0.4)
    end
end

local function pip_color(v)
    if v >= 60 then
        return "green"
    elseif v >= 40 then
        return "yellow"
    end
    return "red"
end

local function weeks(n)
    return M.weeks(n)
end

local function select_why(ok, why)
    if ok then
        return nil
    end
    return why
end

local function label(faction)
    return Intel.label(faction)
end
local world_entry
local function label_of_faction(faction)
    return Intel.label(faction)
end

local function faction_icon(faction)
    if not DIPLOMACY_EMBLEM then
        pcall(require, "eawx-plugins/diplomacy/DiplomacyWindow")
    end
    if DIPLOMACY_WORLD_ICON then
        local ok, texture = pcall(DIPLOMACY_WORLD_ICON, faction)
        if ok and type(texture) == "string" then
            return texture
        end
    end
    if DIPLOMACY_EMBLEM then
        local ok, texture = pcall(DIPLOMACY_EMBLEM, faction)
        if ok and type(texture) == "string" then
            return texture
        end
    end
    return Intel.is_warlord(faction) and "dp_imark_yellow.tga" or "dp_imark_grey.tga"
end

function Window.held_sectors(s)
    local n = 0
    for _, sector in pairs(s.sectors) do
        if table.getn(sector.worlds) > 0 then
            n = n + 1
        end
    end
    return n
end

function Window.speed(trend)
    if not trend then
        return 0
    end
    local a = M.abs(trend)
    return (a < 0.5) and 0 or ((a < 2) and 1 or ((a < 4) and 2 or 3))
end

function Window.trend_text(now, target, trend)
    local speed = Window.speed(trend)
    local way = (speed == 0) and "holding" or (((trend > 0) and "rising" or "falling") .. " about "
        .. (M.round(M.abs(trend) * 10) / 10) .. " a week (the " .. ((trend > 0) and "green" or "red") .. " chevrons)")
    return "Loyalty " .. M.round(now) .. ", heading for " .. M.round(target) .. " (the gold-framed pip), " .. way .. "."
end

local function draw_thumb(prefix, segs, seg, scroll, max, len, share)
    local track = segs * seg
    share = share or (scroll / M.max(1, max))
    local top = share * (track - len)
    local first, last = segs, 1
    for k = 1, segs do
        local middle = (k - 0.5) * seg
        if middle >= top and middle <= top + len then
            first, last = M.min(first, k), M.max(last, k)
        end
    end
    for k = 1, segs do
        local piece = "track"
        if k >= first and k <= last then
            piece = (k == first and "thumb_top") or (k == last and "thumb_bot") or "thumb"
        elseif k == 1 then
            piece = "track_top"
        elseif k == segs then
            piece = "track_bot"
        end
        icon(prefix .. k, "dp_scroll_" .. piece .. ".tga")
    end
end

local function draw_list_thumb()
    draw_thumb("dp_il_seg", LAYOUT.list_segs, LAYOUT.list_seg, (Window.page or 1) - 1, Window.lmax or 0,
        Window.lthumb_len or 24, Window.ldragging and Window.lthumb_share or nil)
end

local SORT_WORDS = {rank = "rank", skill = "skill", loyalty = "loyalty"}

local function render_list(head, cols, rows, head_tip)
    text("dp_il_head", head)
    tip("dp_il_head", head_tip or head)
    text("dp_il_h_a", cols[1] or " ")
    local sort = Window.pick and Window.pick.sort
    for _, col in ipairs({{"b", 2}, {"c", 3}, {"bar", 4}}) do
        local key = Window.sortable and Window.sortable[col[1]]
        local name = "dp_il_h_" .. col[1]
        text(name, cols[col[2]] or " ")
        tip(name, key and ("Click to sort by " .. SORT_WORDS[key] .. "; click again to reverse.") or (cols[col[2]] or " "))
        local on = key ~= nil and sort ~= nil and sort.key == key
        show(name .. "_ar", on)
        if on then
            icon(name .. "_ar", sort.up and "dp_scroll_up.tga" or "dp_scroll_down.tga")
            tip(name .. "_ar", sort.up and "Lowest first." or "Highest first.")
        end
    end
    local per = LAYOUT.rows
    local total = table.getn(rows)
    Window.lmax = M.max(0, total - per)
    Window.page = M.min(M.max(1, Window.page or 1), Window.lmax + 1)
    local first = Window.page - 1
    Window.rows = {}
    for k = 1, per do
        local row = rows[first + k]
        local r = "dp_il_r" .. k
        Window.rows[k] = row
        local head = row ~= nil and row.head == true
        show(r, row ~= nil and not head)
        show(r .. "_a", row ~= nil and not head)
        show(r .. "_b", row ~= nil)
        show(r .. "_c", row ~= nil)
        show(r .. "_head", head)
        show(r .. "_line", head)
        show(r .. "_icon", row ~= nil and row.icon ~= nil and not head)
        show(r .. "_lvl", row ~= nil and row.level ~= nil and not head)
        if row and row.level and not head then
            icon(r .. "_lvl", "dp_rank_" .. row.level .. ".tga")
        end
        show(r .. "_hit", row ~= nil)
        show(r .. "_hicon", head and row.icon ~= nil)
        if head and row.icon then
            icon(r .. "_hicon", row.icon)
        end
        for j = 1, LAYOUT.pips do
            show(r .. "_p" .. j, row ~= nil and row.value ~= nil and not head)
        end
        local speed = Window.speed(row and not head and row.trend)
        show(r .. "_tr", speed > 0)
        if speed > 0 then
            icon(r .. "_tr", "dp_il_tr_" .. ((row.trend > 0) and "up" or "dn") .. speed .. ".tga")
        end
        if row then
            if head then
                text(r .. "_head", row.a)
                if row.selected then
                    color(r .. "_head", 1, 0.92, 0.6)
                else
                    color(r .. "_head", 0.92, 0.8, 0.5)
                end
            else
                icon(r, row.selected and "dp_i_row_sel.tga" or "dp_i_row.tga")
                text(r .. "_a", row.a)
            end
            if row.icon and not head then
                icon(r .. "_icon", row.icon)
            end
            text(r .. "_b", row.b)
            text(r .. "_c", row.c)
            if head then
                grey(r .. "_b")
                grey(r .. "_c")
            elseif row.dim then
                grey(r .. "_a")
                grey(r .. "_b")
                grey(r .. "_c")
            else
                pale(r .. "_a")
                pale(r .. "_b")
                if row.c_value then
                    loyalty_color(r .. "_c", row.c_value)
                else
                    pale(r .. "_c")
                end
            end
            if row.value and not head then
                local n = M.clamp(M.round(row.value / 10), 0, LAYOUT.pips)
                local mark = row.mark and M.clamp(M.round(row.mark / 10), 1, LAYOUT.pips)
                for j = 1, LAYOUT.pips do
                    local base = (j <= n) and ("dp_ipip_" .. (row.pips or pip_color(row.value))) or "dp_ipip_empty"
                    icon(r .. "_p" .. j, base .. ((j == mark) and "_m" or "") .. ".tga")
                end
            end
            local t = row.tip or (row.a .. ".")
            for _, part in ipairs({"", "_icon", "_hicon", "_a", "_b", "_c", "_head", "_hit"}) do
                tip(r .. part, t)
            end
            if row.icon_tip then
                tip(r .. "_icon", row.icon_tip)
                tip(r .. "_hicon", row.icon_tip)
            end
            if row.value and not head then
                local bar_tip = t .. ((row.mark ~= nil) and (" " .. Window.trend_text(row.value, row.mark, row.trend)) or "")
                for j = 1, LAYOUT.pips do
                    tip(r .. "_p" .. j, bar_tip)
                end
                tip(r .. "_tr", bar_tip)
            end
        end
    end
    local scrolling = Window.lmax > 0
    show("dp_il_up", scrolling)
    show("dp_il_down", scrolling)
    for k = 1, LAYOUT.list_segs do
        show("dp_il_seg" .. k, scrolling)
        tip("dp_il_seg" .. k, "Drag, click or use the mouse wheel to scroll the " .. total .. " rows.")
    end
    tip("dp_il_up", "Scroll up.")
    tip("dp_il_down", "Scroll down.")
    if scrolling then
        Window.lthumb_len = M.max(16, LAYOUT.list_segs * LAYOUT.list_seg * per / total)
        draw_list_thumb()
    end
end

local function render_tools(tools)
    Window.tools = {}
    for k = 1, 3 do
        local t = tools[k]
        local name = "dp_il_tool" .. k
        show(name, t ~= nil)
        Window.tools[k] = t
        if t then
            text(name, t[1])
            tip(name, t[3] or t[1])
            icon(name, t[4] and "dp_i_btn_off.tga" or "dp_i_btn.tga")
            if t[4] then
                grey(name)
            else
                color(name, 0.92, 0.82, 0.59)
            end
        end
    end
end

local function draw_world_thumb()
    draw_thumb("dp_id_wseg", LAYOUT.world_segs or 0, 4, Window.wscroll or 0, Window.wmax or 0, Window.wthumb_len or 24,
        Window.wdragging and Window.wthumb_share or nil)
end

local function render_detail(d)
    show("dp_id_portrait", d.portrait ~= nil)
    Window.portrait_char = d.portrait and d.char or nil
    show("dp_id_portrait_lvl", d.portrait ~= nil and d.level ~= nil)
    if d.portrait and d.level then
        icon("dp_id_portrait_lvl", "dp_rank_" .. d.level .. ".tga")
    end
    if d.portrait then
        icon("dp_id_portrait", d.portrait)
        local tip_text = d.portrait_tip or ((d.name or "") .. ". " .. (d.sub or ""))
        if d.char and d.char.status == "serving" and not (Window.tab == "hierarchy" and Window.sel.hierarchy == d.char.id) then
            tip_text = tip_text .. "\nClick to open their page in the Hierarchy."
        end
        tip("dp_id_portrait", tip_text)
    end
    text("dp_id_name", d.name)
    text("dp_id_sub", d.sub)
    text("dp_id_sub2", d.sub2)
    text("dp_id_kind", d.kind)
    tip("dp_id_name", d.name_tip or d.name)
    tip("dp_id_kind", d.kind_tip or d.kind)
    for k = 1, 4 do
        local line = d.stats and d.stats[k]
        local value = type(line) == "table" and line[1] or line
        text("dp_id_s" .. k, value)
        tip("dp_id_s" .. k, type(line) == "table" and line[2] or value)
    end
    text("dp_id_rh", d.head)
    tip("dp_id_rh", d.head_tip or d.head)
    Window.line_keys = {}
    for k = 1, (LAYOUT.views or 0) do
        local v = d.views and d.views[k]
        show("dp_id_v" .. k, v ~= nil)
        show("dp_id_v" .. k .. "_n", v ~= nil)
        if v then
            icon("dp_id_v" .. k, v.icon)
            tip("dp_id_v" .. k, v.tip)
            text("dp_id_v" .. k .. "_n", M.signed(v.value))
            tip("dp_id_v" .. k .. "_n", v.tip)
            if v.value > 0 then
                color("dp_id_v" .. k .. "_n", 0.55, 0.85, 0.6)
            elseif v.value < 0 then
                color("dp_id_v" .. k .. "_n", 0.95, 0.5, 0.45)
            else
                pale("dp_id_v" .. k .. "_n")
            end
        end
    end
    for k = 1, LAYOUT.lines do
        local line = d.lines and d.lines[k]
        if d.views then
            line = nil
        end
        local value = type(line) == "table" and line[1] or line
        text("dp_id_l" .. k, value)
        tip("dp_id_l" .. k, type(line) == "table" and line[2] or value)
        show("dp_id_l" .. k .. "_hit", (value ~= nil and value ~= " ") or (d.worlds ~= nil))
        tip("dp_id_l" .. k .. "_hit", type(line) == "table" and line[2] or value)
        Window.line_keys[k] = type(line) == "table" and line.key or nil
        local v = type(line) == "table" and line.value
        if v and v > 0 then
            color("dp_id_l" .. k, 0.55, 0.85, 0.6)
        elseif v and v < 0 then
            color("dp_id_l" .. k, 0.95, 0.5, 0.45)
        elseif type(line) == "table" and line.selected then
            color("dp_id_l" .. k, 1, 0.9, 0.55)
        else
            pale("dp_id_l" .. k)
        end
    end
    Window.actions = {}
    for k = 1, LAYOUT.actions do
        local a = d.actions and d.actions[k]
        local name = "dp_id_a" .. k
        show(name, a ~= nil)
        Window.actions[k] = a
        if a then
            text(name, a[1])
            tip(name, a[3] or a[1])
            icon(name, a[4] and "dp_i_btn_a_off.tga" or "dp_i_btn_a.tga")
            if a[4] then
                grey(name)
            else
                color(name, 0.92, 0.82, 0.59)
            end
        end
    end
    local worlds = d.worlds
    Window.world_rows = {}
    local per = LAYOUT.world_rows
    local total = worlds and table.getn(worlds) or 0
    Window.wmax = M.max(0, total - per)
    Window.wscroll = M.min(M.max(0, Window.wscroll or 0), Window.wmax)
    for k = 1, per do
        local w = worlds and worlds[Window.wscroll + k]
        local p = "dp_id_w" .. k
        Window.world_rows[k] = w
        show(p .. "_pic", w ~= nil)
        show(p .. "_name", w ~= nil)
        show(p .. "_globe", w ~= nil and w.world ~= nil)
        show(p .. "_zoom", w ~= nil and w.world ~= nil)
        show(p .. "_crest", w ~= nil and w.crest ~= nil)
        show(p .. "_lvl", w ~= nil and w.level ~= nil)
        if w and w.level then
            icon(p .. "_lvl", "dp_rank_" .. w.level .. ".tga")
        end
        if w and w.crest then
            icon(p .. "_crest", w.crest)
            tip(p .. "_crest", (w.crest_tip or "") .. ".")
        end
        if w then
            icon(p .. "_pic", w.pic)
            tip(p .. "_pic", w.pic_tip)
            text(p .. "_name", w.text)
            tip(p .. "_name", w.tip)
            tip("dp_id_l" .. k .. "_hit", w.tip)
            color(p .. "_name", w.color[1], w.color[2], w.color[3])
            if w.world then
                icon(p .. "_globe", GLOBES[w.world] or "dp_globe_unknown.tga")
                tip(p .. "_globe", w.label .. ".")
                tip(p .. "_zoom", "Show " .. w.label .. " on the map.")
            end
        end
    end
    local scrolling = Window.wmax > 0
    show("dp_id_w_up", scrolling)
    show("dp_id_w_down", scrolling)
    for k = 1, LAYOUT.world_segs or 0 do
        show("dp_id_wseg" .. k, scrolling)
        tip("dp_id_wseg" .. k, "Drag, click or use the mouse wheel to scroll the " .. total .. " " .. (d.rows_word or "worlds") .. ".")
    end
    if scrolling then
        Window.wthumb_len = M.max(16, (LAYOUT.world_segs or 0) * 4 * per / total)
        draw_world_thumb()
    end
    tip("dp_id_w_up", "Scroll up the " .. (d.rows_word or "worlds") .. ".")
    tip("dp_id_w_down", "Scroll down the " .. (d.rows_word or "worlds") .. ".")
    if worlds then
        for k = 1, LAYOUT.lines do
            text("dp_id_l" .. k, " ")
            tip("dp_id_l" .. k, " ")
            Window.line_keys[k] = nil
        end
    end
    local message = Window.feedback or " "
    local room = ROOM["dp_id_feedback"] or {400, 7}
    local first, second = message, Window.feedback2
    if text_width(message, room[2]) > room[1] - 4 and not second then
        local n = string.len(message)
        while n > 1 and text_width(string.sub(message, 1, n), room[2]) > room[1] - 4 do
            n = n - 1
        end
        local cut = n + 1
        for i = n, M.max(1, n - 20), -1 do
            if string.sub(message, i, i) == " " then
                cut = i
                break
            end
        end
        first, second = string.sub(message, 1, cut - 1), string.sub(message, cut + 1)
    end
    text("dp_id_feedback", first)
    text("dp_id_feedback2", second or " ")
    tip("dp_id_feedback", message)
    tip("dp_id_feedback2", message)
end

local function empty_detail(name, line)
    return {name = name, sub = line, sub2 = " ", kind = " ", stats = {}, head = " ", lines = {}, actions = {}}
end

local function kind_icon(c)
    return Court.portrait(c)
end

local function char_tip(s, c)
    if not c then
        return "Vacant."
    end
    if c.status ~= "serving" then
        return Court.full_name(c) .. ": " .. c.status .. "."
    end
    local holding = Court.holding_name(s, c)
    local office = Court.office_of(s, c)
    local stand
    if c.leads then
        stand = " Rules the Empire from the court."
    else
        stand = " Loyalty " .. M.round(c.loyalty) .. " (" .. Court.loyalty_word(c.loyalty) .. "), power "
            .. M.round(Court.power(s, c)) .. ", influence " .. M.round(c.influence or 0) .. "."
    end
    return Court.full_name(c) .. (holding and (", " .. Court.title_name(c) .. " of " .. holding) or "")
        .. (office and (", " .. Court.office_def(s, office).name) or "") .. "." .. stand .. Window.heir_text(c)
        .. " " .. Court.kind_text(c)
end

local function portrait_tip(s, c)
    local def = c and c.lore and LORE.CHARACTERS[c.lore]
    if def and def.tip then
        return Court.full_name(c) .. "\n" .. def.tip
    end
    return char_tip(s, c)
end
Window.portrait_tip = portrait_tip

function Window.heir_text(c)
    if c and c.protected and not c.heir then
        return " Protected by the throne: cannot be dismissed, arrested or stripped of their rank."
    end
    if not c or not c.heir then
        return ""
    end
    local regime = CONFIG.REGIMES[c.heir]
    return " Claims the throne (" .. (regime and regime.title or "?") .. "): their leverage as a likely successor keeps "
        .. "them beyond dismissal, arrest, fleet commands and lesser titles."
end

local function short_holding(s, c)
    local h = Court.holding_name(s, c)
    if h then
        h = string.gsub(h, "^the ", "")
        return h
    end
    local office = Court.office_of(s, c)
    if office then
        return Court.office_def(s, office).short
    end
    if c.fleet_rank then
        return CONFIG.ADMIRALTY[c.fleet_rank].name
    end
    return "At court"
end

local function traits_text(c)
    local names = {}
    for _, t in ipairs(c.traits) do
        table.insert(names, CONFIG.TRAITS[t].name)
    end
    return table.getn(names) > 0 and table.concat(names, ", ") or "none"
end

local function traits_tip(c)
    local parts = {}
    for _, t in ipairs(c.traits) do
        table.insert(parts, CONFIG.TRAITS[t].name .. ": " .. CONFIG.TRAITS[t].desc)
    end
    return table.concat(parts, " ")
end

local function leaning(s, c)
    if c.loyalist then
        return "Loyalist: makes no trouble while their loyalty holds above " .. CONFIG.LOYALISTS.LEAVE .. "."
    end
    local parts = {}
    for _, key in ipairs(CONFIG.FACTION_ORDER) do
        local v = c.interest and c.interest[key]
        if v and v > 0 then
            table.insert(parts, CONFIG.FACTIONS[key].name .. " " .. v)
        end
    end
    local joined = c.faction_key and ("In the " .. CONFIG.FACTIONS[c.faction_key].name .. " faction.") or "In no faction."
    if table.getn(parts) == 0 then
        return joined
    end
    return joined .. " Interest: " .. table.concat(parts, ", ") .. "."
end

local function ties_line(s, c)
    local parts, full = {}, {}
    for _, kind in ipairs({"rivals", "friends"}) do
        local short, long = {}, {}
        for _, v in ipairs(Court.ties(s, c, kind)) do
            local _, _, last = string.find(v.name, "(%S+)$")
            table.insert(short, last or v.name)
            table.insert(long, Court.full_name(v))
        end
        local word = (kind == "rivals") and "Rivals" or "Friends"
        table.insert(parts, word .. ": " .. ((table.getn(short) > 0) and table.concat(short, ", ") or "none"))
        table.insert(full, word .. ": " .. ((table.getn(long) > 0) and table.concat(long, ", ") or "none") .. ".")
    end
    return {table.concat(parts, "   "), table.concat(full, " ") .. " Rewarding a rival annoys them; punishing a friend "
        .. "angers them. Lords who take each other's titles feud; comrades in a faction grow close."}
end

local function char_detail(s, c)
    local d = {portrait = Court.portrait(c), name = Court.full_name(c), portrait_tip = portrait_tip(s, c), char = c}
    local office = Court.office_of(s, c)
    if c.status ~= "serving" then
        local why = {dead = "Dead.", exiled = "In exile.", rebel = "Broke away: now rules " .. (c.faction and label(c.faction) or "their own state") .. ".",
                     defected = "Defected to " .. (c.faction and label(c.faction) or "a rival") .. ".",
                     throne = "Left the court for the throne.", gone = "Back with the troops: no place at court."}
        d.sub = why[c.status] or c.status
        d.sub2, d.kind, d.stats, d.head, d.lines, d.actions = " ", Court.kind_text(c), {}, " ", {}, {}
        return d
    end
    local holding = Court.holding_name(s, c)
    d.sub = (holding and (Court.title_name(c) .. " of " .. holding) or "At court, without lands")
        .. (office and (" - " .. Court.office_def(s, office).name) or "")
        .. (c.fleet_rank and (" - " .. CONFIG.ADMIRALTY[c.fleet_rank].name) or "")
    local liege = Court.liege(s, c)
    d.sub2 = "Answers to " .. (liege and Court.full_name(liege) or ("the throne (" .. Court.regime(s).leader .. ")"))
    d.kind = Court.kind_text(c) .. " Traits: " .. traits_text(c) .. "."
    d.kind_tip = traits_tip(c)
    local target, reasons, speed = Court.loyalty_target(s, c)
    local way = (Window.speed(speed) == 0) and "holding" or (((speed > 0) and "rising " or "falling ")
        .. (M.round(M.abs(speed) * 10) / 10) .. " a week")
    local loyalty_line = {"Loyalty " .. M.round(c.loyalty) .. " (" .. Court.loyalty_word(c.loyalty) .. "), heading for "
        .. M.round(target) .. ", " .. way, "Loyalty is the sum of the reasons below as they stand now. Lasting causes "
        .. "build up or wear off over a few weeks (stability's over about ten); one-off acts fade away. The list bar "
        .. "shows it: the gold-framed pip is where it is heading, the chevrons how fast it moves. Below 35 a lord may "
        .. "defect; below 30 a Moff may break away."}
    if c.leads then
        loyalty_line = {"Rules the Empire from the court: beyond loyalty and factions.",
                        "The Empire's true ruler, governing in another's name."}
    end
    d.stats = {
        loyalty_line,
        {"Influence " .. M.round(c.influence) .. "   Power " .. M.round(Court.power(s, c)) .. "   Ambition " .. c.ambition
            .. "   Skill " .. c.skill,
         "Influence: standing at court, spent on petitions. Power: their worlds and forces. Ambition: how much they want. "
            .. "Skill: how well they run an office."},
        ties_line(s, c),
        {(Fleet.label(s, c) and (Fleet.label(s, c) .. ". ") or "") .. (c.minder and "Watched by a minder. " or "")
            .. leaning(s, c) .. ((c.prefers and not s.no_succession) and (" Would back " .. CONFIG.REGIMES[c.prefers].leader
            .. ".") or "") .. (Court.isolation(s, c) > 0 and " Cut off from the core." or ""),
         "Factions: each lord weighs what they want, their power and their chances, and joins the faction they want "
            .. "most (at " .. CONFIG.INTEREST .. " or more). Loyalists make no trouble."},
    }
    d.head = "Why they feel this way"
    table.sort(reasons, function(a, b)
        return M.max(a.value, -a.value) > M.max(b.value, -b.value)
    end)
    d.lines = {}
    for k = 1, M.min(LAYOUT.lines, table.getn(reasons)) do
        local r = reasons[k]
        local goal = (r.goal and M.round(r.goal) ~= r.value) and (" (to " .. M.signed(M.round(r.goal)) .. ")") or ""
        local why = (r.weeks and (" A one-off: fades away over " .. M.weeks(r.weeks) .. ".")) or ((goal ~= "")
            and (" Moving towards " .. M.signed(M.round(r.goal)) .. " over the coming weeks.") or " Holding.")
        d.lines[k] = {M.signed(r.value) .. goal .. "  " .. r.text, cap(r.text) .. ": " .. M.signed(r.value) .. " loyalty now." .. why,
                      value = r.value}
    end
    if table.getn(reasons) > LAYOUT.lines then
        local rest = {}
        for k = LAYOUT.lines, table.getn(reasons) do
            table.insert(rest, reasons[k].text .. " " .. M.signed(reasons[k].value))
        end
        d.lines[LAYOUT.lines] = {"And " .. (table.getn(reasons) - LAYOUT.lines + 1) .. " more...", table.concat(rest, ", ") .. "."}
    end
    local regime = Court.regime(s)
    local no_title = Actions.protected(s, c, "title")
    local no_office = office and Actions.protected(s, c, "dismiss")
    if not Window.more then
        d.actions = {
            {"Grant title", "grant", no_title or ("Give them a sector, an oversector or a world ("
                .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority). The old holder resents it."), no_title ~= nil},
            {"Appoint to office", "office", no_office or ("Give them a seat on the Council ("
                .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority)."), no_office ~= nil},
            {"Honour (" .. Actions.cost(s, CONFIG.ACTIONS.HONOUR) .. ")", "honour", "+" .. CONFIG.OPINION.HONOURED
                .. " opinion for 12 weeks, for " .. Actions.cost(s, CONFIG.ACTIONS.HONOUR) .. " authority."},
            {"Demand tribute", "tribute", "They pay " .. M.round(Court.power(s, c) * CONFIG.ACTIONS.TRIBUTE_PER_POWER)
                .. " credits (" .. CONFIG.OPINION.TRIBUTE .. " opinion). Once every 8 weeks.", c.title == "courtier"},
            {c.minder and "Recall minder" or "Send minder", "minder", c.minder and "Recall the operative watching them."
                or ("An Intelligence operative watches them (planned in the Intelligence tab): out of every faction, no "
                .. "defection or secession while it lasts; " .. CONFIG.LOYALTY.MINDER .. " loyalty.")},
            {"More...", "more", "Bribe, revoke, dismiss, arrest."},
        }
    else
        local revoke_why = (c.title ~= "courtier") and (Actions.revoke_blocked(s, c) or Actions.protected(s, c, "revoke")) or nil
        local revoke_base = M.round(CONFIG.OPINION.REVOKED * ((regime.revoke == "cost") and 1.5 or 1))
        if not revoke_why and c.title ~= "courtier" and not Actions.dismissal(s, c, "title") then
            local _
            _, revoke_why = Actions.dismissal(s, c, "title")
        end
        local dismiss_why = office and (Actions.protected(s, c, "dismiss") or select_why(Actions.dismissal(s, c, "office")))
        local arrest_why = Actions.protected(s, c, "arrest")
        d.actions = {
            {"Bribe (" .. CONFIG.ACTIONS.BRIBE_CREDITS .. ")", "bribe", "A generous gift: +12 opinion, fading over 10 weeks (corrupt lords +18)."},
            {"Revoke title", "revoke", revoke_why or ("Strip one of their titles, chosen next (" .. (CONFIG.ACTIONS.REVOKE * ((regime.revoke == "cost") and 2 or 1))
                .. " authority): " .. Actions.dismissal_text(s, c, "title", revoke_base) .. "; their friends resent it."),
                c.title == "courtier" or revoke_why ~= nil},
            {"Dismiss from office", "dismiss", dismiss_why or (office and ("They lose their seat on the Council ("
                .. Actions.dismissal_text(s, c, "office", CONFIG.OPINION.FIRED) .. ").") or "They hold no office."),
                office == nil or dismiss_why ~= nil},
            {"Arrest", "arrest", arrest_why or ("Imperial Intelligence attempts the arrest (planned in the Intelligence tab): "
                .. "every title and post at once, then the Imperial Prison."), arrest_why ~= nil},
            nil,
            {"Back", "back", "The other actions."},
        }
        d.actions[5] = {"Show on map", "map", "Close the window and look at their seat.", table.getn(Court.worlds_of(s, c)) == 0}
    end
    return d
end

local function surname(c)
    if not c then
        return "Vacant"
    end
    local _, _, last = string.find(c.name, "(%S+)$")
    return last or c.name
end

local function sector_row(s, sector, indent)
    local c = Court.char(s, sector.holder)
    local iso = 0
    for _, name in ipairs(sector.worlds) do
        if s.isolated[name] then
            iso = iso + 1
        end
    end
    local note = sector.crown and "the throne's own" or (s.awol[sector.key] and "not answering"
        or ((iso > 0) and (iso .. " cut off") or ""))
    local n = table.getn(sector.worlds)
    local mark, trend
    if c and c.status == "serving" and not c.leads then
        local _
        mark, _, trend = Court.loyalty_target(s, c)
    end
    return {icon = sector.crown and "dp_imark_gold.tga" or Court.portrait(c), icon_tip = (not sector.crown and c) and portrait_tip(s, c) or nil,
            a = indent .. sector.name, mark = mark, trend = trend,
            b = sector.crown and "The throne" or (c and c.name or "Vacant"), c = tostring(n),
            value = c and c.loyalty or nil, key = sector.key, selected = Window.sel.realm == sector.key,
            dim = not c and not sector.crown,
            tip = sector.name .. ": " .. n .. ((n == 1) and " world, " or " worlds, ") .. (sector.crown and "ruled by the throne"
                or (c and ("held by " .. Court.full_name(c) .. ", loyalty " .. M.round(c.loyalty))
                or "no Moff: its worlds go unmanaged")) .. ((note ~= "") and (" (" .. note .. ")") or "")
                .. ". Click for its worlds."}
end

local function sector_rows(s)
    local rows = {}
    local listed = {}
    for _, okey in ipairs(Court.sorted_keys(s.oversectors)) do
        local over = s.oversectors[okey]
        local gm = Court.char(s, over.holder)
        local sectors = {}
        for _, sector in ipairs(Court.sector_list(s)) do
            if sector.oversector == okey and table.getn(sector.worlds) > 0 then
                table.insert(sectors, sector)
            end
        end
        table.insert(rows, {head = true, a = over.name, b = gm and gm.name or "No Grand Moff", icon = gm and Court.portrait(gm),
                            icon_tip = gm and portrait_tip(s, gm) or nil,
                            c = table.getn(sectors) .. " sect.", key = "O_" .. okey,
                            selected = Window.sel.realm == "O_" .. okey,
                            tip = over.name .. ": " .. table.getn(sectors) .. " sectors under "
                                .. (gm and Court.full_name(gm) or "no Grand Moff") .. ". Click for the oversector."})
        for _, sector in ipairs(sectors) do
            listed[sector.key] = true
            table.insert(rows, sector_row(s, sector, ""))
        end
    end
    local rest = {}
    for _, sector in ipairs(Court.sector_list(s)) do
        if not listed[sector.key] and table.getn(sector.worlds) > 0 then
            table.insert(rest, sector)
        end
    end
    if table.getn(rest) > 0 then
        table.insert(rows, {head = true, a = (table.getn(rows) > 0) and "Other sectors" or "Sectors", b = "Moff",
                            c = "Worlds", key = "HEAD"})
        for _, sector in ipairs(rest) do
            table.insert(rows, sector_row(s, sector, ""))
        end
    end
    local free = Court.unsectored(s, s.held)
    if table.getn(free) > 0 then
        table.insert(rows, {head = true, a = "Unsectored systems", b = "Governor", c = " ", key = "HEAD",
                            tip = "Worlds in no sector: each has its own Governor (a Commander on a base or station). "
                                .. CONFIG.PROCLAIM.WORLDS .. " connected ones can be proclaimed a new sector."})
        for _, name in ipairs(free) do
            local gov = Court.char(s, s.governor[name])
            local word = Court.is_station(name) and CONFIG.COMMANDER.name or "Governor"
            local mark, trend
            if gov and gov.status == "serving" then
                local _
                mark, _, trend = Court.loyalty_target(s, gov)
            end
            table.insert(rows, {icon = Court.portrait(gov), icon_tip = gov and portrait_tip(s, gov) or nil,
                                a = Court.planet_label(name), b = gov and gov.name or "Vacant",
                                c = Court.is_station(name) and "Base" or "World", value = gov and gov.loyalty or nil,
                                mark = mark, trend = trend,
                                key = "U_" .. name, selected = Window.sel.realm == "U_" .. name, dim = not gov,
                                tip = Court.planet_label(name) .. ": " .. (gov and (word .. " " .. gov.name .. ", loyalty "
                                    .. M.round(gov.loyalty)) or ("no " .. string.lower(word) .. ": nobody manages it"))
                                    .. ". Click for the system."})
        end
    end
    return rows
end

local faction_colors
local function owner_color(s, owner)
    if faction_colors == nil then
        local ok, constants = pcall(function()
            return ModContentLoader.get("GameConstants")
        end)
        faction_colors = ok and constants and constants.FACTION_COLORS or false
    end
    local c = owner and faction_colors and faction_colors[owner]
    if not c then
        return {0.62, 0.62, 0.66}
    end
    local r, g, b = c.r / 255, c.g / 255, c.b / 255
    local lift = M.max(0, 0.75 - M.max(r, M.max(g, b)))
    local mix = 0.25 + lift
    return {r + (1 - r) * mix, g + (1 - g) * mix, b + (1 - b) * mix}
end

world_entry = function(s, sector, name)
    local label = Court.planet_label(name)
    local owner = Court.owner_of(s, name)
    local mine = owner == CONFIG.FACTION and s.world[name] == sector.key
    local seat = name == sector.seat and mine
    local lord = mine and Court.char(s, seat and sector.holder or s.governor[name]) or nil
    local word = seat and "Moff" or (Court.is_station(name) and CONFIG.COMMANDER.name or "Governor")
    local text_ = label .. (seat and " (seat)" or "") .. (mine and (lord and (" - " .. lord.name) or " - vacant")
        or (" - " .. (owner and label_of_faction(owner) or "unknown")))
    local why
    if not mine then
        why = label .. " is held by " .. (owner and label_of_faction(owner) or "nobody we know") .. "."
    elseif lord then
        why = label .. ": " .. word .. " " .. lord.name .. ", loyalty " .. M.round(lord.loyalty) .. "."
    else
        why = label .. ": no " .. string.lower(word) .. ". Nobody manages it."
    end
    if mine and s.isolated[name] then
        why = why .. " Cut off from the core."
    end
    return {world = name, label = label, text = text_, tip = why, color = owner_color(s, owner),
            crest = owner and faction_icon(owner) or nil, crest_tip = owner and label_of_faction(owner) or nil,
            pic = mine and Court.portrait(lord) or "dp_ip_vacant.tga",
            pic_tip = mine and (lord and portrait_tip(s, lord) or ("No " .. string.lower(word) .. " on " .. label .. "."))
                or (label .. " is not ours."),
            lord = lord}
end

local function world_detail(s, name)
    local gov = Court.char(s, s.governor[name])
    local word = Court.is_station(name) and CONFIG.COMMANDER.name or "Governor"
    local d = {portrait = Court.portrait(gov), name = Court.planet_label(name), portrait_tip = portrait_tip(s, gov), char = gov}
    d.sub = gov and (word .. " " .. gov.name .. ", loyalty " .. M.round(gov.loyalty) .. " (" .. Court.loyalty_word(gov.loyalty) .. ")")
        or ("No " .. string.lower(word) .. ": nobody manages it.")
    d.sub2 = "An unsectored system, answering to the throne."
    d.kind = Court.is_station(name) and "A base or station: no population, so a Commander rules it." or " "
    local geo = require("eawx-plugins/imperial-court/CourtGeo")[name]
    local since = s.vacant_since["W_" .. name]
    d.stats = {
        "Worth " .. (geo and geo.value or 0) .. " credits a week to its owner.",
        (s.depth[name] and (s.depth[name] .. " jumps from the capital.")) or (s.isolated[name] and "Cut off from the core."
            or "No route to the capital."),
        {since and ("Unmanaged for " .. M.weeks(s.week - since) .. ".") or "Managed.",
         "Unmanaged worlds cost stability and try the Moffs' patience, the more so the richer they are and the "
            .. "longer they go without a lord."},
        " ",
    }
    d.head = " "
    d.lines = {}
    local group = Actions.direct_group(s, name, s.held)
    d.actions = {
        {"Appoint " .. word, "appoint_world", "Choose who rules " .. Court.planet_label(name) .. " ("
            .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority)."},
        {"Proclaim a sector", "proclaim_here", "This world and the unsectored worlds connected to it ("
            .. table.getn(group) .. ") become a new sector. Needs " .. CONFIG.PROCLAIM.WORLDS .. ", "
            .. CONFIG.PROCLAIM.AUTHORITY .. " authority and " .. CONFIG.PROCLAIM.CREDITS .. " credits.",
         table.getn(group) < CONFIG.PROCLAIM.WORLDS},
        {"Show on map", "map", "Close the window and look at " .. Court.planet_label(name) .. "."},
    }
    if gov then
        table.insert(d.actions, {"The " .. string.lower(word) .. "...", "goto_char", "Open their page in the Court tab."})
    end
    return d
end

local function oversector_detail(s, okey)
    local over = s.oversectors[okey]
    if not over then
        return empty_detail("The oversector is gone", " ")
    end
    local gm = Court.char(s, over.holder)
    local d = {portrait = Court.portrait(gm), name = over.name, portrait_tip = portrait_tip(s, gm), char = gm}
    d.sub = gm and Court.full_name(gm) or "No Grand Moff"
    d.sub2 = gm and ("Loyalty " .. M.round(gm.loyalty) .. " (" .. Court.loyalty_word(gm.loyalty) .. "), power "
        .. M.round(Court.power(s, gm))) or "The Moffs here answer to the throne directly."
    d.kind = s.early and "Too early in the war for Grand Moffs: the throne may still name one." or " "
    d.stats = {}
    d.head = "Sectors"
    d.lines = {}
    local k = 0
    for _, sector in ipairs(Court.sector_list(s)) do
        if sector.oversector == okey and k < LAYOUT.lines then
            k = k + 1
            local moff = Court.char(s, sector.holder)
            d.lines[k] = {sector.name .. ": " .. (moff and Court.full_name(moff) or "no Moff"), char_tip(s, moff),
                          key = moff and moff.id or nil}
        end
    end
    d.actions = {
        {"Appoint Grand Moff", "appoint_gm", "Choose who holds the " .. over.name .. " ("
            .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority). The Moffs below them become their vassals."},
    }
    if gm then
        table.insert(d.actions, {"Honour Grand Moff", "honour", "+" .. CONFIG.OPINION.HONOURED .. " opinion ("
            .. Actions.cost(s, CONFIG.ACTIONS.HONOUR) .. " authority)."})
        table.insert(d.actions, {"The Grand Moff...", "goto_char", "Open their page in the Court tab."})
    end
    return d
end

local function lord_line(s, c, post, empty)
    if not c then
        return {empty, empty .. ".", value = -1}
    end
    local text_ = post .. ": " .. c.name .. " - loyalty " .. M.round(c.loyalty) .. ", skill " .. M.round(c.skill or 0)
    if string.len(text_ .. ", " .. traits_text(c)) <= 68 then
        text_ = text_ .. ", " .. traits_text(c)
    end
    return {text_,
            char_tip(s, c) .. " Traits: " .. traits_text(c) .. ". Click for their page.", key = c.id}
end

local function mod_line(text_, value, tip_)
    return {text_, tip_ or text_, value = value}
end

local function system_detail(s, sector, name)
    local ok, Revenue = pcall(require, "eawx-plugins/imperial-court/CourtRevenue")
    local label = Court.planet_label(name)
    local mine = Court.owner_of(s, name) == CONFIG.FACTION and s.world[name] == sector.key
    local gov, moff, gm
    if ok and Revenue then
        gov, moff, gm = Revenue.lords(s, name)
    end
    local d = {name = label}
    d.sub = "System of the " .. sector.name .. ((name == sector.seat) and " (its seat)" or "")
    d.sub2 = mine and " " or (label .. " is not ours now.")
    d.kind = " "
    local base = s.world_income and s.world_income[name]
    local mods, sum = {}, 0
    local chance, why = 0, "it is not ours"
    if ok and Revenue and mine then
        mods, sum = Revenue.mods(s, name)
        chance, why = Revenue.rising_chance(s, name)
    end
    local palace = s.world_palace and s.world_palace[name]
    d.stats = {
        {"Income: " .. (base and (M.round(base) .. " credits a week") or "not measured yet"),
         "What the world yields before its lords' modifiers (measured weekly)."},
        {"Lords' modifiers: " .. M.signed(sum) .. "%" .. (base and (" (" .. M.signed(M.round(base * sum / 100))
            .. " credits a week)") or ""), "The sum of the modifiers below, paid or taken by the court each week."},
        {(chance > 0) and ("Risk of rising: " .. string.format("%.1f", chance) .. "% a week") or "No risk of rising",
         (chance > 0) and ("It may rise: " .. why .. ", and Imperial stability is below " .. CONFIG.UNGOVERNED.BELOW
             .. ".") or ("It will not rise on its own now: " .. why .. ".")},
        {palace and "Moff Palace: built" or "Moff Palace: none", palace and "A Moff Palace halves the risk of a rising."
            or "Without a Moff Palace a world nobody governs rises twice as often."},
    }
    d.head = "Lords and modifiers of " .. label
    d.lines = {}
    local seat = name == sector.seat
    local function add(line)
        if table.getn(d.lines) < LAYOUT.lines then
            table.insert(d.lines, line)
        end
    end
    add(lord_line(s, gov, Court.is_station(name) and CONFIG.COMMANDER.name or "Governor",
        seat and "No Governor (the Moff rules the seat)" or "No Governor"))
    add(lord_line(s, moff, "Moff", sector.crown and "The throne rules this sector" or "No Moff"))
    add(lord_line(s, gm, "Grand Moff", "No Grand Moff"))
    for _, m in ipairs(mods) do
        add(mod_line(m.text .. ": " .. M.signed(m.pct) .. "% income", m.pct))
    end
    if table.getn(mods) == 0 and mine then
        add(mod_line("No modifiers on its income"))
    end
    if (s.unrest or 0) > 0 and mine then
        add(mod_line("Unrest across the Empire: -" .. s.unrest .. " influence", -1))
    end
    local calm = s.calm and s.calm[name]
    if calm and calm > s.week then
        add(mod_line("Calm for " .. M.weeks(calm - s.week) .. " (no risings)", 1))
    end
    if s.isolated[name] then
        add(mod_line("Cut off from the core: its lord's loyalty falls", -1))
    end
    d.actions = {
        {"Back", "sys_back", "Return to the " .. sector.name .. "."},
        {"Show on map", "sys_map", "Close the window and look at " .. label .. "."},
    }
    if mine and not seat then
        table.insert(d.actions, {"Appoint Governor", "sys_gov", "Choose who governs " .. label .. " ("
            .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority)."})
    end
    return d
end

local function realm_detail(s)
    local key = Window.sel.realm
    if type(key) == "string" and string.find(key, "^U_") then
        return world_detail(s, string.sub(key, 3))
    elseif type(key) == "string" and string.find(key, "^O_") then
        return oversector_detail(s, string.sub(key, 3))
    end
    local sector = s.sectors[key or ""]
    if not sector then
        local d = empty_detail("The Realm", "Select an oversector, a sector or a system.")
        d.sub2 = Window.held_sectors(s) .. " sectors, " .. Court.world_count(s) .. " worlds."
        d.kind = s.focus or " "
        local unmanaged = table.getn(s.unmanaged or {})
        d.stats = {
            {(unmanaged > 0) and (unmanaged .. " worlds have no lord to manage them.") or "Every world has a lord.",
             "A sector without a Moff, or an unsectored world without a Governor, goes unmanaged: stability and the "
                .. "Moffs' loyalty suffer, the more so the richer the world and the longer it waits."},
            " ", " ", " "}
        d.head = "Oversectors"
        local k = 0
        for _, okey in ipairs(Court.sorted_keys(s.oversectors)) do
            k = k + 1
            if k <= LAYOUT.lines then
                local over = s.oversectors[okey]
                local gm = Court.char(s, over.holder)
                d.lines[k] = {over.name .. ": " .. (gm and Court.full_name(gm) or "no Grand Moff"), char_tip(s, gm)}
            end
        end
        if k == 0 then
            d.head = " "
        end
        return d
    end
    local picked = Window.sel_world and Window.sel_world.sector == sector.key and Window.sel_world.world
    if picked and Window.sys_details then
        return system_detail(s, sector, picked)
    end
    local c = Court.char(s, sector.holder)
    local d = {portrait = sector.crown and nil or Court.portrait(c), name = sector.name, portrait_tip = portrait_tip(s, c), char = c}
    d.sub = sector.crown and ("Ruled by the throne: " .. Court.regime(s).leader) or (c and Court.full_name(c)
        or "No Moff: its worlds go unmanaged")
    local over = sector.oversector and s.oversectors[sector.oversector]
    local gm = over and Court.char(s, over.holder)
    d.sub2 = over and (over.name .. (gm and (", " .. Court.full_name(gm)) or ", no Grand Moff")) or (sector.region or " ")
    if s.map_mode == "sectors" then
        d.sub2 = d.sub2 .. " (" .. Map.colour_name(s, sector.key) .. " on the map)"
    end
    d.kind = c and (Court.kind_text(c) .. " Traits: " .. traits_text(c) .. ".") or " "
    local governed, iso = 0, 0
    for _, name in ipairs(sector.worlds) do
        if s.governor[name] then
            governed = governed + 1
        end
        if s.isolated[name] then
            iso = iso + 1
        end
    end
    d.stats = {
        "Worlds: " .. table.getn(sector.worlds) .. (sector.seat and (", seat " .. Court.planet_label(sector.seat)) or ""),
        "Governors: " .. governed .. " of " .. M.max(0, table.getn(sector.worlds) - 1) .. " worlds",
        {(iso > 0) and (iso .. ((iso == 1) and " world is" or " worlds are") .. " cut off from the core.") or "Connected to the core.",
         "Worlds with no Imperial hyperlane path to the capital: their lord's loyalty falls."},
        c and ("Moff's loyalty " .. M.round(c.loyalty) .. " (" .. Court.loyalty_word(c.loyalty) .. "), power " .. M.round(Court.power(s, c)))
            or (s.awol[key] and "Not answering the throne." or " "),
    }
    local members = Court.sector_members(s, sector)
    d.head = "Worlds of the sector (" .. table.getn(sector.worlds) .. " of " .. table.getn(members) .. " held)"
    d.head_tip = "Every world of the " .. sector.name .. ", whoever holds it now: green ours, yellow a rival Imperial "
        .. "power or warlord, red another power, grey independent. Portrait: its Governor or Commander (the Moff "
        .. "rules the seat). Click a system to select it, a portrait for the lord, the globe or magnifier to see the world."
    d.lines = {}
    d.worlds = {}
    for _, name in ipairs(members) do
        local w = world_entry(s, sector, name)
        if name == picked then
            w.text = "> " .. w.text
        end
        table.insert(d.worlds, w)
    end
    d.actions = {
        {"Appoint Moff", "appoint_moff", "Choose who holds the " .. sector.name .. " (" .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority).",
         sector.crown},
        {"Appoint Governor", "appoint_gov", "Choose a world of the sector, then its Governor or Commander.", table.getn(sector.worlds) < 2},
        {"Show on map", "map", "Close the window and look at the sector's seat.", not sector.seat},
    }
    if c then
        table.insert(d.actions, {"Honour Moff", "honour", "+" .. CONFIG.OPINION.HONOURED .. " opinion ("
            .. Actions.cost(s, CONFIG.ACTIONS.HONOUR) .. " authority)."})
        table.insert(d.actions, {"Demand tribute", "tribute", "They pay " .. M.round(Court.power(s, c) * CONFIG.ACTIONS.TRIBUTE_PER_POWER) .. " credits."})
        table.insert(d.actions, {"The Moff...", "goto_char", "Open their page in the Court tab."})
    end
    if picked then
        table.insert(d.actions, 1, {"System details", "sys_details", "Every modifier on " .. Court.planet_label(picked)
            .. " and its Governor, Moff and Grand Moff."})
        if table.getn(d.actions) > LAYOUT.actions then
            table.remove(d.actions)
        end
    end
    return d
end

local function vassals_of(s, c)
    local n = 0
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if v.status == "serving" and v ~= c and Court.liege(s, v) == c then
            n = n + 1
        end
    end
    return n
end

local function char_row(s, c, liege_col)
    local c_text, c_tip
    if c.status ~= "serving" then
        c_text = cap(c.status)
    elseif liege_col then
        local n = vassals_of(s, c)
        local liege = Court.liege(s, c)
        if n > 0 then
            c_text, c_tip = "Liege (" .. n .. ")", " Liege of " .. n .. ((n == 1) and " vassal." or " vassals.")
        elseif liege then
            c_text, c_tip = surname(liege), " Vassal of " .. Court.full_name(liege) .. "."
        else
            c_text, c_tip = "Throne", " Answers to the throne."
        end
    else
        c_text = tostring(M.round(c.loyalty))
    end
    local target, speed
    if c.status == "serving" and not c.leads then
        local _
        target, _, speed = Court.loyalty_target(s, c)
    end
    if c.leads then
        c_text = "Rules"
    end
    return {icon = kind_icon(c), icon_tip = portrait_tip(s, c), a = Court.full_name(c), b = short_holding(s, c), c = c_text,
            c_value = (not liege_col and c.status == "serving" and not c.leads) and c.loyalty or nil,
            value = (c.status == "serving" and not c.leads) and c.loyalty or nil, mark = target, trend = speed,
            key = c.id, selected = Window.sel.hierarchy == c.id, dim = c.status ~= "serving",
            tip = char_tip(s, c) .. (c_tip or "") .. " Click for details."}
end

local function wanted(c)
    if Window.filter == "lore" then
        return c.kind ~= "generated"
    elseif Window.filter == "generated" then
        return c.kind == "generated"
    end
    return true
end

local function hierarchy_rows(s)
    local rows, done = {}, {}
    local function section(title, list, b, tip_text)
        local shown = {}
        for _, c in ipairs(list) do
            if not done[c.id] then
                done[c.id] = true
                if wanted(c) then
                    table.insert(shown, c)
                end
            end
        end
        if table.getn(shown) > 0 then
            table.insert(rows, {head = true, a = title .. " (" .. table.getn(shown) .. ")", b = b or "Holds",
                                c = "Liege", key = "HEAD", tip = tip_text})
            for _, c in ipairs(shown) do
                table.insert(rows, char_row(s, c, true))
            end
        end
    end
    local gms, moffs, govs, court, gone = {}, {}, {}, {}, {}
    for _, okey in ipairs(Court.sorted_keys(s.oversectors)) do
        local gm = Court.char(s, s.oversectors[okey].holder)
        if gm then
            table.insert(gms, gm)
        end
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" and c.title == "grand_moff" and not s.oversectors[c.holds or ""] then
            table.insert(gms, c)
        end
    end
    for _, sector in ipairs(Court.sector_list(s)) do
        local moff = Court.char(s, sector.holder)
        if moff then
            table.insert(moffs, moff)
        end
    end
    for _, name in ipairs(Court.sorted_keys(s.governor)) do
        local gov = Court.char(s, s.governor[name])
        if gov then
            table.insert(govs, gov)
        end
    end
    for _, id in ipairs(s.order) do
        local c = s.chars[id]
        if c.status == "serving" then
            table.insert(court, c)
        else
            table.insert(gone, c)
        end
    end
    table.sort(court, function(a, b)
        local oa, ob = Court.office_of(s, a) and 1 or 0, Court.office_of(s, b) and 1 or 0
        if oa ~= ob then
            return oa > ob
        end
        return a.id < b.id
    end)
    section("Grand Moffs", gms, "Oversector", "Grand Moffs hold the oversectors; the Moffs there are their vassals.")
    section("Moffs", moffs, "Sector", "Moffs hold the sectors and rule their seats.")
    section("Governors and Commanders", govs, "World", "Governors hold single worlds; Commanders rule bases and stations.")
    section("Court and candidates", court, "Office", "Officers without lands: candidates for titles, offices and commands.")
    if Window.departed then
        section("The departed", gone, "Fate", "The dead, the exiled, rebels and defectors.")
    end
    return rows
end

local function admiralty_rows(s)
    local rows = {}
    local supreme = Court.char(s, s.offices.FLEET)
    table.insert(rows, {head = true, a = "Supreme Commander", b = "Flagship", c = "Liege", key = "HEAD",
                        tip = Court.office_def(s, "FLEET").name .. ": above every fleet rank, appointed in the Council. "
                            .. "Their skill sets how many Admirals and Captains can serve."})
    if supreme and supreme.status == "serving" then
        local row = char_row(s, supreme, true)
        local label = Fleet.label(s, supreme)
        row.b = cap(Court.own_ship(supreme) and "Own ship" or (label and string.gsub(label, "^Flagship: ", "") or "Awaiting one"))
        row.key = supreme.id
        row.selected = Window.sel.admiralty == supreme.id
        table.insert(rows, row)
    else
        table.insert(rows, {icon = "dp_ip_vacant.tga", a = "Vacant", b = " ", c = " ", dim = true, key = "SC",
                            selected = Window.sel.admiralty == "SC",
                            tip = "No Supreme Commander of the Fleet: appoint one in the Council tab."})
    end
    for _, rank in ipairs(CONFIG.ADMIRALTY_ORDER) do
        local def = CONFIG.ADMIRALTY[rank]
        local members = Court.fleet_members(s, rank)
        local seats = Court.fleet_seats(s, rank)
        table.insert(rows, {head = true, a = def.name .. "s (" .. table.getn(members) .. " of " .. seats .. ")",
                            b = "Flagship", c = "Liege", key = "HEAD", tip = def.name .. ": " .. def.desc})
        for _, c in ipairs(members) do
            local row = char_row(s, c, true)
            local label = Fleet.label(s, c)
            row.b = Court.own_ship(c) and "Own ship" or (label and string.gsub(label, "^Flagship: ", "") or "Awaiting one")
            row.b = cap(row.b)
            row.key = c.id
            row.selected = Window.sel.admiralty == c.id
            table.insert(rows, row)
        end
        for _ = table.getn(members) + 1, seats do
            table.insert(rows, {icon = "dp_ip_vacant.tga", a = "Vacant command", b = " ", c = " ", dim = true,
                                key = "V_" .. rank, selected = Window.sel.admiralty == "V_" .. rank,
                                tip = "A vacant " .. def.name .. "'s command. Click to choose an officer."})
        end
    end
    return rows
end

local function admiralty_detail(s)
    local key = Window.sel.admiralty
    if key == "SC" then
        local d = empty_detail("Supreme Commander of the Fleet", "Vacant. The seat is filled in the Council tab.")
        d.portrait = "dp_ip_vacant.tga"
        d.sub2 = "Without one: 2 Grand Admirals, 2 Admirals, 4 Captains."
        d.kind = "Flagship: an Allegiance, or an Imperial II while it is locked."
        d.actions = {{"Go to the Council", "goto_council", "Open the Council tab at this seat."}}
        return d
    end
    if type(key) == "string" and string.find(key, "^V_") then
        local rank = string.sub(key, 3)
        local def = CONFIG.ADMIRALTY[rank]
        local d = empty_detail("A vacant " .. def.name .. "'s command", def.desc)
        d.portrait = "dp_ip_vacant.tga"
        d.sub2 = "Costs " .. Actions.cost(s, def.cost) .. " authority. Power +" .. def.power .. ", stability +" .. def.stability
            .. " while they are loyal."
        d.kind = (def.from and ("Raised from the " .. Actions.fleet_sources(rank) .. ". ") or "")
            .. "Officers without a ship of their own are given a flagship."
        d.actions = {{"Appoint...", "pick_fleet", "Choose an officer for the command (Governors cannot leave their worlds)."}}
        return d
    end
    local c = type(key) == "number" and s.chars[key]
    if c then
        local d = char_detail(s, c)
        if c.fleet_rank then
            d.actions = {
                {"Relieve of command", "dismiss_fleet", select_why(Actions.dismissal(s, c, "fleet")) or ("They lose their "
                    .. "rank (" .. Actions.dismissal_text(s, c, "fleet", CONFIG.OPINION.FIRED) .. ")."),
                 select_why(Actions.dismissal(s, c, "fleet")) ~= nil},
                {"Honour (" .. Actions.cost(s, CONFIG.ACTIONS.HONOUR) .. ")", "honour", "+" .. CONFIG.OPINION.HONOURED
                    .. " opinion for 12 weeks."},
                {"Grant title", "grant", "Give them a sector, an oversector or a world as well."},
                {"Their page", "goto_char", "Open their page in the Court tab."},
            }
        elseif s.offices.FLEET == c.id then
            d.actions = {
                {"Go to the Council", "goto_council", "The Supreme Commander is appointed and dismissed in the Council."},
                {"Their page", "goto_char", "Open their page in the Court tab."},
            }
        end
        if c.fleet_rank or s.offices.FLEET == c.id then
            if c.ship_lost then
                local why = Fleet.rebuild_blocked(s, c)
                table.insert(d.actions, 1, {"Rebuild Flagship", "rebuild_ship", why or ("Lay down a new "
                    .. Fleet.class(c.ship_lost.type) .. " for them: " .. c.ship_lost.price .. " credits, ready in "
                    .. M.weeks(c.ship_lost.weeks) .. "."), why ~= nil})
            end
        end
        return d
    end
    local d = empty_detail("The Admiralty", "The fleet's commands, and who holds them.")
    d.sub2 = "Lore officers hold the rank their history gives them."
    d.head = "How it works"
    d.lines = {
        "Captain, Admiral, Grand Admiral: one rank at a time.",
        "Moffs may be made Admirals; Grand Moffs Grand Admirals.",
        "An officer without a ship of their own gets a flagship.",
        "Its fate is theirs: if the ship is lost, so are they.",
        "Loyal commanders steady the Empire; each adds power.",
        "Appointing a traitor insults the whole court.",
        "The Supreme Commander's skill sets the Admiral and Captain seats.",
    }
    return d
end

local function office_effect(s, key)
    local def = Court.office_def(s, key)
    local strength = Court.office_strength(s, key)
    local value = M.round(M.max(strength, -strength) * (CONFIG.OFFICE_VALUES[key] or 0))
    if strength < 0 then
        return "Against you: " .. def.risk, strength
    elseif strength == 0 then
        return "Vacant: no effect.", 0
    end
    return string.format(def.bonus, value), strength
end

local function office_skill(c, key)
    local skill = c.skill
    for _, t in ipairs(c.traits) do
        local trait = CONFIG.TRAITS[t]
        skill = skill + ((trait.skill and trait.skill[key]) or 0)
    end
    return M.clamp(skill, 0, 100)
end

local function ruler_portrait(regime_key, state, unit)
    local regime = CONFIG.REGIMES[regime_key] or CONFIG.REGIMES.EMPIRE
    unit = unit or regime.figure
    local i = unit and Court.LORE_BY_UNIT[unit]
    local base = i and LORE.CHARACTERS[i] and LORE.CHARACTERS[i].portrait
    if not base or base == "dp_ip_lore" then
        return (state == "unknown") and "dp_ip_gen_1.tga" or ((state == "now") and "dp_ip_lore_g.tga" or "dp_ip_lore_s.tga")
    end
    return base .. ((state == "now") and "_g.tga" or ((state == "past") and "_d.tga"
        or ((state == "next") and "_s.tga" or "_x.tga")))
end

local function render_court(s)
    local regime = Court.regime(s)
    icon("dp_ic_throne", ruler_portrait(s.regime, "now"))
    text("dp_ic_leader", cap(regime.emperor or regime.leader))
    text("dp_ic_regime", regime.emperor and ("Ruled for him by " .. regime.leader) or regime.title)
    local throne_tip = (regime.emperor and (regime.emperor .. " sits on the throne; " .. regime.leader .. " and the "
        .. regime.title .. " rule in his name. ") or (regime.title .. ". ")) .. regime.perks .. " " .. regime.flaws
        .. " Click for the regime's rules."
    tip("dp_ic_throne", throne_tip)
    tip("dp_ic_leader", throne_tip)
    tip("dp_ic_regime", throne_tip)
    for k, key in ipairs(CONFIG.OFFICE_ORDER) do
        if k > LAYOUT.seats then
            break
        end
        local seat = "dp_ic_s" .. k
        local def = Court.office_def(s, key)
        local c = Court.char(s, s.offices[key])
        icon(seat, Court.portrait(c))
        text(seat .. "_office", def.short)
        text(seat .. "_name", c and c.name or "Vacant")
        text(seat .. "_loy", c and (Court.loyalty_word(c.loyalty) .. " " .. M.round(c.loyalty)) or " ")
        if c then
            loyalty_color(seat .. "_loy", c.loyalty)
        end
        if Window.sel.court == key then
            color(seat .. "_office", 1, 0.9, 0.55)
        else
            color(seat .. "_office", 0.92, 0.82, 0.59)
        end
        local effect = office_effect(s, key)
        local t = def.name .. ": " .. (c and char_tip(s, c) or "vacant.") .. " " .. effect .. " Click for the office."
        for _, part in ipairs({"", "_office", "_name", "_loy", "_hit"}) do
            tip(seat .. part, t)
        end
        if c then
            tip(seat, portrait_tip(s, c))
        end
    end
end

local function court_detail(s)
    local key = Window.sel.court
    if key == "PRISON" then
        return IW.prison_detail(s, Window.intel_helpers())
    end
    if not key or key == "THRONE" then
        local regime = Court.regime(s)
        local d = empty_detail(regime.leader, regime.title)
        d.sub2 = "Stability settles at " .. regime.stability .. " under this regime."
        d.kind = "Titles: " .. ((regime.revoke == "free") and "stripped at will." or ((regime.revoke == "cost") and
            "stripping one costs double." or "only disloyal lords can be stripped."))
        d.stats = {"Perks: " .. regime.perks, "Flaws: " .. regime.flaws,
                   "Crisis events: x" .. (regime.crisis or 1) .. "   Breakaways: x" .. (regime.breakaway or 1)
                       .. "   Defections: x" .. (regime.defect or 1),
                   "Authority +" .. (regime.authority or 0) .. " a week   Covert operations " .. M.signed(regime.covert or 0) .. "%"}
        d.head = "The offices"
        d.lines = {}
        for k = 1, M.min(LAYOUT.lines, table.getn(CONFIG.OFFICE_ORDER)) do
            local okey = CONFIG.OFFICE_ORDER[k]
            local effect = office_effect(s, okey)
            d.lines[k] = {Court.office_def(s, okey).short .. ": " .. effect, nil}
        end
        return d
    end
    local def = Court.office_def(s, key)
    local c = Court.char(s, s.offices[key])
    local effect, strength = office_effect(s, key)
    local d = {portrait = Court.portrait(c), name = def.name, portrait_tip = portrait_tip(s, c), char = c}
    d.sub = c and Court.full_name(c) or "Vacant"
    d.sub2 = effect
    d.kind = c and (Court.kind_text(c) .. " Traits: " .. traits_text(c) .. ".") or " "
    d.stats = {
        c and ("Loyalty " .. M.round(c.loyalty) .. " (" .. Court.loyalty_word(c.loyalty) .. "), skill " .. c.skill) or " ",
        {"When loyal: " .. string.format(def.bonus, CONFIG.OFFICE_VALUES[key] or 0) .. " (at full skill)",
         "The bonus grows with the holder's skill and loyalty."},
        "Below " .. CONFIG.OFFICE_RISK .. " loyalty: " .. def.risk,
        "Holding an office: +" .. CONFIG.OFFICE_INFLUENCE .. " influence a week.",
    }
    d.head = "Who wants it"
    d.head_tip = "Lords who expect this office for themselves (by their rank, their history and their nature). Passed "
        .. "over for another, they take offence; less if they hold another office, none if too weak to matter."
    d.lines = {}
    for _, id in ipairs(s.order) do
        local v = s.chars[id]
        if v.status == "serving" and Court.wants_office(s, v) == key and table.getn(d.lines) < LAYOUT.lines then
            local own = Court.office_of(s, v)
            table.insert(d.lines, {Court.full_name(v) .. ((own == key) and " - holds it" or (own and (" - holds "
                .. Court.office_def(s, own).short) or "")), char_tip(s, v) .. " Wants to be " .. def.name .. ". Click for their page.",
                key = v.id})
        end
    end
    if table.getn(d.lines) == 0 then
        d.lines[1] = {"Nobody at court expects it.", "No lord's rank, history or nature makes them expect this office."}
    end
    local dismiss_why = c and (Actions.protected(s, c, "dismiss") or select_why(Actions.dismissal(s, c, "office")))
    d.actions = {
        {"Appoint...", "pick_office_cand", "Choose who holds it: select a lord to see how they would serve and what it "
            .. "would stir up, then appoint them (" .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority).",
         c ~= nil and Actions.protected(s, c, "dismiss") ~= nil},
        {"Dismiss", "dismiss_office", dismiss_why or (c and ("Leave the office vacant (" .. Actions.cost(s, CONFIG.ACTIONS.DISMISS)
            .. " authority; " .. Actions.dismissal_text(s, c, "office", CONFIG.OPINION.FIRED) .. " for the holder).") or "The office is vacant."),
         not c or dismiss_why ~= nil},
    }
    if c then
        table.insert(d.actions, {"Holder's page", "goto_char", "Open their page in the Court tab."})
    end
    return d
end

local function faction_rows(s)
    local rows = {}
    for _, key in ipairs(CONFIG.FACTION_ORDER) do
        local def = CONFIG.FACTIONS[key]
        if key == "succession" and s.no_succession then
            def = nil
        end
        if def then
        local f = s.factions[key] or {members = {}, strength = 0, progress = 0}
        local n = table.getn(f.members or {})
        local value = def.threshold and f.progress or f.strength
        table.insert(rows, {icon = "dp_imark_" .. (CONFIG.FACTION_MARK[key] or "yellow") .. ".tga",
                            a = def.name, b = n .. ((n == 1) and " lord" or " lords"), c = (f.strength or 0) .. "%",
                            value = value, pips = (key == "loyalists") and "green" or "red", key = "F_" .. key,
                            selected = Window.sel.factions == "F_" .. key,
                            tip = def.name .. ": " .. def.goal .. " Strength " .. (f.strength or 0) .. "% of the lords' power"
                                .. (def.threshold and (", demands at " .. def.threshold .. "%; ultimatum " .. M.round(f.progress or 0) .. "% ready.") or ".")})
        end
    end
    local risks = Politics.risks(s)
    table.insert(rows, {head = true, a = "Lords at risk (" .. table.getn(risks) .. ")", b = " ", c = " ", key = "HEAD"})
    for _, r in ipairs(risks) do
        local c = r.char
        table.insert(rows, {icon = kind_icon(c), a = Court.full_name(c), b = r.short or r.text, c = tostring(M.round(c.loyalty)), c_value = c.loyalty,
                            value = r.level, pips = "red", key = c.id, selected = Window.sel.factions == c.id,
                            tip = Court.full_name(c) .. ": " .. r.text .. ". Click for details and what you can do."})
    end
    return rows
end

local function faction_detail(s)
    local key = Window.sel.factions
    if type(key) == "number" then
        return char_detail(s, s.chars[key])
    end
    if type(key) ~= "string" or not string.find(key, "^F_") then
        local d = empty_detail("Factions", "Unhappy or mighty lords band together.")
        d.sub2 = "Act on the lords at risk before they do."
        d.head = "How it works"
        d.lines = {
            "Loyal lords stand with the Loyalists and make no trouble.",
            "The rest weigh each faction: wants, power and chances.",
            "Autonomy and Independence press demands once strong.",
            "An ultimatum refused: their most disloyal lords rise.",
            "Defection needs no ultimatum: a warning comes first.",
            "Minders, Intelligence and counter-intelligence help.",
        }
        return d
    end
    local fkey = string.sub(key, 3)
    local def = CONFIG.FACTIONS[fkey]
    local f = s.factions[fkey] or {members = {}, strength = 0, progress = 0}
    local leader = Court.char(s, f.leader)
    local d = {portrait = leader and Court.portrait(leader) or nil, name = def.name .. " faction", portrait_tip = portrait_tip(s, leader), char = leader}
    d.sub = def.goal
    d.sub2 = leader and ("Led by " .. Court.full_name(leader)) or "No members."
    d.kind = " "
    d.stats = {
        "Strength: " .. (f.strength or 0) .. "% of the lords' power" .. (def.threshold and (" (demands at " .. def.threshold .. "%)") or ""),
        def.threshold and ("Ultimatum: " .. M.round(f.progress or 0) .. "% ready") or " ",
        def.ultimatum and ("Demand: " .. def.ultimatum) or " ",
        " ",
    }
    d.head = "Members"
    d.lines = {}
    if fkey == "succession" then
        local by = {}
        for _, id in ipairs(f.members or {}) do
            local c = s.chars[id]
            by[c.prefers] = (by[c.prefers] or 0) + Court.power(s, c)
        end
        local k = 0
        for regime, power in pairs(by) do
            k = k + 1
            if k <= LAYOUT.lines then
                d.lines[k] = {CONFIG.REGIMES[regime].title .. ": power " .. M.round(power), nil}
            end
        end
    else
        d.worlds, d.rows_word = {}, "members"
        for _, id in ipairs(f.members or {}) do
            local c = s.chars[id]
            if c then
                local lc = (c.loyalty >= 60) and {0.55, 0.85, 0.6} or ((c.loyalty >= 40) and {0.92, 0.82, 0.45} or {0.95, 0.45, 0.4})
                table.insert(d.worlds, {text = Court.full_name(c) .. " - loyalty " .. M.round(c.loyalty) .. ", power "
                                            .. M.round(Court.power(s, c)), tip = char_tip(s, c) .. " " .. leaning(s, c)
                                            .. " Click for their page.", color = lc, pic = Court.portrait(c),
                                        pic_tip = portrait_tip(s, c), lord = c, label = c.name})
            end
        end
        if table.getn(d.worlds) == 0 then
            d.worlds = nil
            d.lines[1] = {"No members.", "Nobody belongs to this faction now."}
        end
    end
    d.actions = {}
    if leader then
        d.actions = {
            {"Honour the leader", "honour_leader", "+" .. CONFIG.OPINION.HONOURED .. " opinion for " .. Court.full_name(leader) .. "."},
            {"Watch the leader", "minder_leader", "An Intelligence minder for " .. Court.full_name(leader) .. ": no ultimatums "
                .. "or secession while it lasts."},
            {"Arrest the leader", "arrest_leader", "Imperial Intelligence attempts to arrest " .. Court.full_name(leader) .. "."},
            {"Leader's page", "goto_leader", "Open their page in the Court tab."},
        }
    end
    return d
end

local function legitimacy_rows(s)
    local rows = {}
    local legit = Court.legitimacy()
    if legit then
        local list = {}
        for faction, entry in pairs(legit) do
            table.insert(list, {faction = faction, entry = entry})
        end
        table.sort(list, function(a, b)
            return a.entry.legitimacy > b.entry.legitimacy
        end)
        for i, item in ipairs(list) do
            local mine = item.faction == CONFIG.FACTION
            table.insert(rows, {icon = faction_icon(item.faction),
                                a = label(item.faction), b = M.round(item.entry.legitimacy) .. " points",
                                c = M.round(item.entry.share) .. "%", value = item.entry.share * 2, pips = mine and "blue" or "grey",
                                key = "L_" .. item.faction, selected = Window.sel.legitimacy == "L_" .. item.faction,
                                tip = label(item.faction) .. ": " .. M.round(item.entry.legitimacy) .. " legitimacy, "
                                    .. M.round(item.entry.share) .. "% of all Imperial legitimacy."})
        end
    else
        table.insert(rows, {a = "Legitimacy is not tracked in this campaign.", b = " ", c = " ", key = "NONE", dim = true})
    end
    local warlords = s.no_race and {} or Politics.warlords(s)
    if s.no_race then
        return rows
    end
    table.insert(rows, {head = true, a = "Integration race (" .. table.getn(warlords) .. ")", b = "Leading rival",
                        c = "You", key = "HEAD"})
    for _, w in ipairs(warlords) do
        local rec = s.integration[w.faction] or {empire = 0, rivals = {}}
        local best, best_v = nil, 0
        for rival, v in pairs(rec.rivals or {}) do
            if v > best_v then
                best, best_v = rival, v
            end
        end
        local ready = rec.empire >= CONFIG.INTEGRATION.FEALTY_AT
        table.insert(rows, {icon = faction_icon(w.faction), a = w.display,
                            b = best and (label(best) .. " " .. M.round(best_v) .. "%") or "None",
                            c = M.round(rec.empire) .. "%", value = rec.empire, pips = ready and "green" or "blue",
                            key = "W_" .. w.faction, selected = Window.sel.legitimacy == "W_" .. w.faction,
                            tip = w.display .. " (" .. table.getn(w.worlds) .. " worlds): your influence " .. M.round(rec.empire)
                                .. "%; fealty at " .. CONFIG.INTEGRATION.FEALTY_AT .. "% with " .. Politics.bar(w) .. "% legitimacy."})
    end
    return rows
end

local function legitimacy_detail(s)
    local key = Window.sel.legitimacy or ""
    if string.find(key, "^L_") then
        local faction = string.sub(key, 3)
        local legit = Court.legitimacy() or {}
        local entry = legit[faction] or {legitimacy = 0, share = 0}
        local d = empty_detail(label(faction), M.round(entry.legitimacy) .. " legitimacy, " .. M.round(entry.share) .. "% of the whole.")
        d.sub2 = "Up with worlds taken; down with worlds lost."
        d.portrait = faction_icon(faction)
        d.portrait_tip = label(faction) .. "."
        return d
    end
    if string.find(key, "^W_") then
        local faction = string.sub(key, 3)
        local w
        for _, entry in ipairs(Politics.warlords(s)) do
            if entry.faction == faction then
                w = entry
            end
        end
        if not w then
            return empty_detail("The warlord is gone", " ")
        end
        local rec = s.integration[faction] or {empire = 0, rivals = {}}
        local share = Court.legitimacy_share()
        local d = empty_detail(w.display, table.getn(w.worlds) .. " worlds. Fealty needs " .. CONFIG.INTEGRATION.FEALTY_AT
            .. "% influence and " .. Politics.bar(w) .. "% legitimacy.")
        d.sub2 = "Your legitimacy " .. M.round(share) .. "%. " .. (Politics.borders(w, CONFIG.FACTION, s)
            and "Borders the Empire: influence grows faster." or "Not on your borders.")
        d.head = "The race"
        local list = {{"the Empire", rec.empire}}
        for rival, v in pairs(rec.rivals or {}) do
            table.insert(list, {label(rival), v})
        end
        table.sort(list, function(a, b)
            return a[2] > b[2]
        end)
        for k = 1, M.min(LAYOUT.lines, table.getn(list)) do
            d.lines[k] = {list[k][1] .. ": " .. M.round(list[k][2]) .. "%", nil}
        end
        local why
        if rec.empire < CONFIG.INTEGRATION.FEALTY_AT then
            why = "Influence " .. M.round(rec.empire) .. "%: needs " .. CONFIG.INTEGRATION.FEALTY_AT .. "%."
        elseif share < Politics.bar(w) then
            why = "Legitimacy " .. M.round(share) .. "%: needs " .. Politics.bar(w) .. "%."
        end
        d.actions = {
            {"Demand fealty", "fealty", why or ("Their worlds join the Empire as a sector; their leader becomes your Moff ("
                .. CONFIG.ACTIONS.FEALTY .. " authority)."), why ~= nil},
            {"Sway (" .. CONFIG.OPS.SWAY.cost .. ")", "op_SWAY", (Intel.blocked(s, "SWAY", faction) or ("Covert: +"
                .. CONFIG.OPS.SWAY.influence .. "% influence over them; an operative must be at their capital. Plans it in the "
                .. "Intelligence tab.")), Intel.blocked(s, "SWAY", faction) ~= nil},
            {"Intelligence", "op_PAGE", "Their page in the Intelligence tab: spy network and operations."},
        }
        return d
    end
    local d = empty_detail("Legitimacy", "Every Imperial power claims the throne.")
    d.sub2 = "Your share: " .. M.round(Court.legitimacy_share()) .. "%."
    d.kind = s.no_race and " " or ("The integration race: enough influence over a minor warlord and enough legitimacy, "
        .. "and they swear fealty.")
    d.succession = true
    return d
end

local SUCC_RULES = {
    "A power with 3 worlds left and its leaders dead joins the most legitimate.",
    "Two absorptions and over 60% of all legitimacy: the Emperor returns.",
    "Above a 30% share your lords grow loyal; below it, or outpaced, they waver.",
    "Rising legitimacy may bring lore groups to your side.",
    "Regime changes cost legitimacy; fealty, vassals and whole sectors add to it.",
    " ",
}
local SUCC_ALT = {after = "PESTAGE", key = "CCOGM"}

local function next_ruler(s)
    return Court.next_regime(s)
end

local function ruler_state(s, key)
    if key == s.regime then
        return "now"
    elseif s.seen_regimes and s.seen_regimes[key] then
        return "past"
    elseif key == next_ruler(s) or (key == SUCC_ALT.key and s.regime == SUCC_ALT.after) then
        return "next"
    end
    return "unknown"
end

local function ruler_tip(s, key, state)
    local regime = CONFIG.REGIMES[key]
    if state == "unknown" then
        return "Not yet known: a ruler still to come."
    end
    local who = (regime.rank or regime.title) .. " " .. (regime.name or regime.leader)
    local when = (state == "now") and "Rules now." or ((state == "past") and "Ruled before." or "Next in line.")
    local event = ""
    if state == "next" and CONFIG.SUCCESSION_EVENTS[key] and not s.no_succession then
        local _, why = Politics.succession_ready(s, key)
        event = " " .. why
    end
    local unit = regime.leader_figure or regime.figure
    local i = unit and Court.LORE_BY_UNIT[unit]
    local bio = i and LORE.CHARACTERS[i] and LORE.CHARACTERS[i].bio
    return who .. ": " .. regime.title .. (regime.emperor and (" (for " .. regime.emperor .. ")") or "") .. ". " .. when
        .. event .. " " .. regime.perks .. " " .. regime.flaws .. (bio and (" " .. bio) or "")
end

local function ruler_slot(s, slot, key)
    local state = ruler_state(s, key)
    local regime = CONFIG.REGIMES[key]
    local unit = regime.leader_figure or regime.figure
    icon(slot, ruler_portrait(key, state, unit))
    local _, _, last = string.find(regime.name or regime.leader, "(%S+)$")
    text(slot .. "_name", (state == "unknown") and "?" or (last or regime.leader))
    local ready = state == "next" and CONFIG.SUCCESSION_EVENTS[key] and Politics.succession_ready(s, key)
    if state == "now" then
        color(slot .. "_name", 1, 0.86, 0.45)
    elseif ready then
        color(slot .. "_name", 0.55, 0.9, 0.6)
    elseif state == "next" then
        pale(slot .. "_name")
    else
        grey(slot .. "_name")
    end
    local t = ruler_tip(s, key, state)
    tip(slot, t)
    tip(slot .. "_name", t)
    show(slot .. "_hl", ready and true or false)
    tip(slot .. "_hl", t)
    Window.succ_slots[slot] = key
    Window.succ_slots[slot .. "_name"] = key
    Window.succ_slots[slot .. "_hl"] = key
end

local function render_succession(s)
    Window.succ_slots = {}
    text("dp_isc_head", s.no_succession and "The ruler" or "The succession")
    tip("dp_isc_head", s.no_succession and "This campaign has no succession: the ruler holds on, or falls."
        or "The Empire's rulers in order, as Thrawn's regime events bring them. Gold: the ruler now; named: the next "
            .. "in line (green when their succession can be set in motion: click them); greyed: rulers past; shadows: "
            .. "still to come. The Grand Moffs' committee may take Isard's place; the Emperor may return below.")
    local list = s.no_succession and {s.regime} or CONFIG.SUCCESSION
    for k = 1, LAYOUT.succession do
        local key = list[k]
        local slot = "dp_isc_" .. k
        show(slot, key ~= nil)
        show(slot .. "_name", key ~= nil)
        show(slot .. "_hl", false)
        if k < LAYOUT.succession then
            show("dp_isc_arrow" .. k, key ~= nil and list[k + 1] ~= nil)
        end
        if key then
            ruler_slot(s, slot, key)
        end
    end
    local back = not s.no_succession and CONFIG.SUCCESSION_RETURN
    for _, part in ipairs({"dp_isc_down", "dp_isc_right", "dp_isc_return", "dp_isc_return_name", "dp_isc_return_hl"}) do
        show(part, back and true or false)
    end
    if back then
        ruler_slot(s, "dp_isc_return", back)
        if ruler_state(s, back) == "unknown" then
            local t = "The Emperor's return: possible after Thrawn, once legitimacy allows. Not yet known."
            tip("dp_isc_return", t)
            tip("dp_isc_return_name", t)
        else
            text("dp_isc_return_name", "Palpatine")
        end
    end
    local alt = not s.no_succession and SUCC_ALT.key
    for _, part in ipairs({"dp_isc_alt_arrow", "dp_isc_alt", "dp_isc_alt_name", "dp_isc_alt_hl"}) do
        show(part, alt and true or false)
    end
    if alt then
        ruler_slot(s, "dp_isc_alt", alt)
    end
    text("dp_isc_rules_head", "Integration Rules")
    tip("dp_isc_rules_head", "How legitimacy works among the Imperial powers.")
    for k = 1, LAYOUT.rules do
        text("dp_isc_rule" .. k, SUCC_RULES[k] or " ")
    end
end

local function pick_rows(s)
    local p = Window.pick
    local rows = {}
    if p.kind == "title" then
        local c = s.chars[p.char]
        for _, o in ipairs(Actions.title_options(s, c)) do
            local place = (o.title == "governor") and Court.planet_label(o.key)
                or ((o.title == "moff") and s.sectors[o.key].name or s.oversectors[o.key].name)
            table.insert(rows, {icon = Court.portrait(o.holder), a = place,
                                b = (o.title == "governor" and Court.is_station(o.key)) and CONFIG.COMMANDER.name
                                    or CONFIG.TITLES[o.title].name, c = o.holder and surname(o.holder) or "Vacant", key = o,
                                tip = o.label .. (o.holder and (": now held by " .. Court.full_name(o.holder) .. ", who would resent it.") or ": vacant.")
                                    .. " Click to grant it to " .. c.name .. "."})
        end
        return "Grant " .. c.name .. " a title", {"Place", "Title", "Holder", " "}, rows
    elseif p.kind == "revoke" then
        local c = s.chars[p.char]
        local list = {}
        for _, h in ipairs(Court.holdings(s, c)) do
            table.insert(list, h)
        end
        table.sort(list, function(a, b)
            return Court.RANK[a.title] > Court.RANK[b.title]
        end)
        for _, h in ipairs(list) do
            local words = Actions.title_words(s, h.title, h.key)
            local capital = Court.capital_of(s, c)
            local seat = (h.title == "moff" and s.sectors[h.key] and s.sectors[h.key].seat == capital)
                or (h.title == "governor" and h.key == capital)
            table.insert(rows, {icon = Court.portrait(c), a = words, b = seat and "Capital" or " ", c = " ", key = h,
                                tip = words .. ". Click to strip " .. c.name .. " of it"
                                    .. (seat and " (their capital: the next holding becomes it)." or ".")})
        end
        return "Revoke one of " .. c.name .. "'s titles", {"Title", " ", " ", " "}, rows
    elseif p.kind == "office" then
        local c = s.chars[p.char]
        for _, key in ipairs(CONFIG.OFFICE_ORDER) do
            local holder = Court.char(s, s.offices[key])
            table.insert(rows, {icon = Court.portrait(holder), a = Court.office_def(s, key).name,
                                b = holder and holder.name or "Vacant", c = " ", key = key,
                                tip = Court.office_def(s, key).name .. ". Click to appoint " .. c.name .. "."})
        end
        return "Appoint " .. c.name .. " to an office", {"Office", "Holder", " ", " "}, rows
    elseif p.kind == "char" then
        local list = {}
        for _, id in ipairs(s.order) do
            local c = s.chars[id]
            if c.status == "serving" and (not p.filter or p.filter(c)) then
                table.insert(list, c)
            end
        end
        local function skill_of(c)
            return p.office and office_skill(c, p.office) or c.skill
        end
        local function rank_of(c)
            return CONFIG.TITLES[c.title] and CONFIG.TITLES[c.title].rank or 0
        end
        local by = {rank = rank_of, skill = skill_of, loyalty = function(c) return c.loyalty end}
        local sort = p.sort and by[p.sort.key]
        table.sort(list, function(a, b)
            if sort then
                local va, vb = sort(a), sort(b)
                if va ~= vb then
                    if p.sort.up then
                        return va < vb
                    end
                    return va > vb
                end
                return a.name < b.name
            end
            if a.title ~= b.title then
                return rank_of(a) < rank_of(b)
            end
            return a.loyalty > b.loyalty
        end)
        for _, c in ipairs(list) do
            local row = char_row(s, c, false)
            row.key = c.id
            row.selected = p.sel == c.id
            row.b = CONFIG.TITLES[c.title] and CONFIG.TITLES[c.title].name or "Courtier"
            if c.fleet_rank and CONFIG.ADMIRALTY[c.fleet_rank] then
                row.b = row.b .. ", " .. CONFIG.ADMIRALTY[c.fleet_rank].name
            end
            row.c, row.c_value = tostring(M.round(skill_of(c))), nil
            row.tip = char_tip(s, c) .. " Rank: " .. row.b .. ". Skill " .. M.round(skill_of(c)) .. ", loyalty "
                .. M.round(c.loyalty) .. "."
                .. (c.traitor and " A traitor: the court would be insulted." or "")
                .. (p.blocked and p.blocked(c) and (" " .. p.blocked(c)) or " Click to see how they would serve.")
            row.dim = p.blocked and p.blocked(c) ~= nil
            table.insert(rows, row)
        end
        local why = Actions.raise_blocked(s)
        if table.getn(rows) == 0 then
            table.insert(rows, {a = "Nobody can take this post.", b = " ", c = " ", key = "HEAD", dim = true,
                                tip = "Nobody at court qualifies yet."})
        end
        Window.sortable = {b = "rank", c = "skill", bar = "loyalty"}
        if p.no_raise then
            return p.head, {"Name", "Rank", "Skill", "Loyalty"}, rows
        end
        table.insert(rows, {icon = "dp_ip_gen_1.tga", a = "Raise a new officer", b = "From the ranks", c = " ", key = "NEW",
                            dim = why ~= nil,
                            tip = why or ("Raise a nobody for it (" .. CONFIG.RAISE.AUTHORITY .. " authority more). Every lord "
                                .. "resents it (" .. CONFIG.RAISE.OPINION .. " opinion), and it can be done only every "
                                .. M.weeks(CONFIG.RAISE.COOLDOWN) .. ".")})
        return p.head, {"Name", "Rank", "Skill", "Loyalty"}, rows
    elseif p.kind == "world" then
        for _, name in ipairs(p.worlds) do
            local gov = Court.char(s, s.governor[name])
            table.insert(rows, {icon = Court.portrait(gov), a = Court.planet_label(name),
                                b = gov and gov.name or "Vacant", c = Court.is_station(name) and "Base" or "World", key = name,
                                tip = Court.planet_label(name) .. ". Click to choose."})
        end
        return p.head, {"World", "Governor", "Kind", " "}, rows
    end
    return "Choose", {}, rows
end

local function do_pick(s, key)
    local p = Window.pick
    local ok, message
    if p.kind == "title" then
        ok, message = Actions.grant_title(s, s.chars[p.char], key.title, key.key)
    elseif p.kind == "revoke" then
        ok, message = Actions.revoke(s, s.chars[p.char], key.title, key.key)
    elseif p.kind == "office" then
        ok, message = Actions.appoint_office(s, s.chars[p.char], key)
    elseif p.kind == "char" then
        local c = s.chars[key]
        if key == "NEW" then
            local _
            ok, message, c = Actions.raise_officer(s)
            if not ok then
                Window.pick, Window.feedback = nil, message
                return
            end
            p.sel, Window.feedback = c.id, message
            return
        end
        p.sel = (p.sel ~= key) and key or nil
        return
    elseif p.kind == "world" then
        Window.pick = nil
        p.done(key)
        return
    end
    Window.pick = nil
    Window.feedback = message
end

local function pick_detail(s)
    local p = Window.pick
    local c = p and p.kind == "char" and p.sel and s.chars[p.sel]
    if not c then
        if p and p.kind == "char" then
            return empty_detail(p.head or "Choose", "Click a lord on the left to see how they would serve, then appoint them.")
        end
        return empty_detail("Choose from the list", "Click an entry on the left, or Cancel.")
    end
    local d = {portrait = Court.portrait(c), name = Court.full_name(c), portrait_tip = portrait_tip(s, c), char = c}
    d.sub = p.head or "Choose"
    local target, _, speed = Court.loyalty_target(s, c)
    d.sub2 = "Loyalty " .. M.round(c.loyalty) .. " (" .. Court.loyalty_word(c.loyalty) .. "), heading for " .. M.round(target)
    d.kind = Court.kind_text(c) .. " Traits: " .. traits_text(c) .. "."
    d.kind_tip = traits_tip(c)
    local wants = Court.wants_office(s, c)
    local skill = p.office and office_skill(c, p.office) or c.skill
    d.stats = {
        {"Skill " .. skill .. (p.office and (" for " .. Court.office_def(s, p.office).short) or "") .. "   Influence "
            .. M.round(c.influence or 0) .. "   Power " .. M.round(Court.power(s, c)),
         "Skill: how well they would run it (their nature adds to it). Influence: their pull at court. Power: their "
            .. "lands and forces."},
        {"Now: " .. short_holding(s, c) .. ((wants and (", wants to be " .. Court.office_def(s, wants).short)) or ""),
         wants and ("They expect the office of " .. Court.office_def(s, wants).name .. ".") or "They expect no office."},
        {Window.trend_text(c.loyalty, target, speed), "Where their loyalty stands and is heading before you act."},
        " ",
    }
    d.head = "If you appoint them"
    d.lines = {}
    local O = CONFIG.OPINION
    local gain = p.office and O.GRANTED_OFFICE or (p.rank and CONFIG.ADMIRALTY[p.rank].opinion) or O.GRANTED_TITLE
    table.insert(d.lines, {"+" .. gain .. " opinion: honoured by it (fades over " .. M.weeks(10) .. ")",
                           "A one-off: strongest at once, gone in ten weeks.", value = gain})
    if p.office and wants == p.office then
        table.insert(d.lines, {"The office they wanted: no longer passed over", "They expected this post.", value = 1})
    end
    if p.holder then
        local old = p.holder()
        if old and old ~= c then
            local weight = Actions.dismissal(s, old, p.office and "office" or "title") or 1
            table.insert(d.lines, {M.round(O.FIRED * weight) .. " opinion for " .. old.name .. ", replaced",
                                   char_tip(s, old), value = -1})
        end
    end
    local rivals = {}
    for _, v in ipairs(Court.ties(s, c, "rivals")) do
        table.insert(rivals, v.name)
    end
    if table.getn(rivals) > 0 then
        table.insert(d.lines, {O.RIVAL_REWARDED .. " opinion for their rivals: " .. table.concat(rivals, ", "),
                               "Rivals resent a rival's reward.", value = -1})
    end
    if p.office then
        local passed = {}
        for _, id in ipairs(s.order) do
            local v = s.chars[id]
            if v ~= c and v.status == "serving" and Court.wants_office(s, v) == p.office then
                table.insert(passed, v.name)
            end
        end
        if table.getn(passed) > 0 then
            table.insert(d.lines, {"Passed over and offended: " .. table.concat(passed, ", "),
                                   "Lords who expected this office take offence (fading over ten weeks).", value = -1})
        end
    end
    if c.traitor then
        table.insert(d.lines, {CONFIG.TRAITOR.APPOINTED .. " opinion for the whole court: a traitor rewarded",
                               "The court does not forgive treason.", value = -1})
    end
    local why = p.blocked and p.blocked(c)
    d.actions = {
        {"Appoint " .. c.name, "confirm_pick", why or ("Appoint " .. Court.full_name(c) .. (p.office and (" ("
            .. Actions.cost(s, CONFIG.ACTIONS.APPOINT) .. " authority).") or ".")), why ~= nil},
        {"Cancel", "cancel_pick", "Back without appointing anyone."},
    }
    return d
end

local function render_header(s)
    local regime = Court.regime(s)
    text("dp_i_title", "The Imperial Court")
    tip("dp_i_title", "The Imperial Court under " .. regime.leader .. ": " .. regime.title .. ".")
    local legit = Court.legitimacy()
    local share = legit and M.round(Court.legitimacy_share()) or nil
    local rival = Court.top_rival()
    local sectors = Window.held_sectors(s)
    local unmanaged = table.getn(s.unmanaged or {})
    local target, reasons = Court.stability_target(s)
    local ruler_tip = (regime.rank or regime.title) .. " " .. (regime.name or regime.leader) .. ": " .. regime.title
        .. (regime.emperor and (", in the name of " .. regime.emperor) or "") .. ". " .. regime.perks .. " " .. regime.flaws
        .. " Click for the Council."
    icon("dp_i_ruler", ruler_portrait(s.regime, "now", regime.leader_figure))
    icon("dp_i_ruler_plate", "dp_i_ruler_plate.tga")
    text("dp_i_ruler_rank", regime.rank or regime.title)
    text("dp_i_ruler_name", cap(regime.name or regime.leader))
    for _, part in ipairs({"dp_i_ruler", "dp_i_ruler_plate", "dp_i_ruler_rank", "dp_i_ruler_name"}) do
        tip(part, ruler_tip)
    end
    local coins = {
        authority = {tostring(M.floor(s.authority)), "Authority: " .. M.floor(s.authority) .. " of " .. CONFIG.AUTHORITY.MAX
            .. ", +" .. regime.authority .. " a week (more with a loyal Grand Vizier). It pays for appointments, honours, "
            .. "commands and decrees."},
        legitimacy = {share and (share .. "%") or "-", share and ("Legitimacy: your share of all Imperial legitimacy is "
            .. share .. "%" .. (rival and (". Leading rival: " .. label(rival)) or "") .. ". Above 30% it steadies the "
            .. "Empire and its lords; below, or outpaced by a rival, it shakes them. Fealty and integrations raise it; "
            .. "regime changes and risings lower it.") or "Legitimacy is not tracked in this campaign."},
    }
    for _, key in ipairs(LAYOUT.coins) do
        text("dp_i_coin_" .. key .. "_n", coins[key][1])
        tip("dp_i_coin_" .. key, coins[key][2])
        tip("dp_i_coin_" .. key .. "_n", coins[key][2])
    end
    local rev = s.revenue or {}
    local taxes = (s.week_taxes or 0) + (rev.total or 0)
    local sources = {"Stability: " .. M.signed(s.week_taxes or 0)}
    if (rev.no_governor or 0) ~= 0 then
        table.insert(sources, "Worlds nobody governs (-" .. CONFIG.REVENUE.NO_GOVERNOR .. "%): " .. M.signed(rev.no_governor))
    end
    if (rev.no_moff or 0) ~= 0 then
        table.insert(sources, "Sectors without a Moff (-" .. CONFIG.REVENUE.NO_MOFF .. "%): " .. M.signed(rev.no_moff))
    end
    if (rev.skill or 0) ~= 0 then
        table.insert(sources, "The Moffs' skill: " .. M.signed(rev.skill))
    end
    if (rev.traits or 0) ~= 0 then
        table.insert(sources, "The Moffs' natures (corrupt, administrator): " .. M.signed(rev.traits))
    end
    local taxes_tip = "Taxes: " .. M.signed(taxes) .. " credits a week.\n" .. table.concat(sources, "\n")
        .. (((s.week_credits or 0) ~= 0) and ("\nThe Fleet and Industry offices (paid apart): " .. M.signed(s.week_credits))
            or "")
    local stats = {
        realm = {sectors .. " sectors, " .. Court.world_count(s) .. " worlds", sectors .. " sectors and "
            .. Court.world_count(s) .. " worlds." .. ((unmanaged > 0) and (" " .. unmanaged .. " of them have no lord to "
            .. "manage them: stability and the Moffs' patience suffer.") or " Every world has a lord.")},
        treasury = {"Taxes " .. M.signed(taxes) .. " a week", taxes_tip},
    }
    for _, key in ipairs(LAYOUT.stats) do
        local name = "dp_i_stat_" .. key
        text(name, stats[key][1])
        tip(name, stats[key][2])
    end
    if unmanaged > 0 then
        color("dp_i_stat_realm", 0.95, 0.7, 0.45)
    else
        pale("dp_i_stat_realm")
    end
    text("dp_i_stab_label", "Imperial Stability: " .. M.round(s.stability) .. " (" .. Court.stability_word(s.stability) .. ")")
    local n = M.clamp(M.round(s.stability / 5), 0, LAYOUT.stab_pips)
    local colour = (s.stability < 30) and "red" or ((s.stability < 60) and "yellow" or "green")
    local mark = M.clamp(M.round(target / 5), 1, LAYOUT.stab_pips)
    local step = (target - s.stability) * CONFIG.STABILITY.DRIFT
    local speed = (M.abs(step) < 0.5) and 0 or ((M.abs(step) < 2) and 1 or ((M.abs(step) < 4) and 2 or 3))
    local limits = {}
    for _, t in ipairs(stability_thresholds()) do
        limits[M.round(t[1] / 5)] = t
    end
    for k = 1, LAYOUT.stab_pips do
        local base = "dp_ipip_" .. ((k <= n) and colour or "empty")
        if k ~= n or not Window.pulse then
            icon("dp_i_stab_" .. k, base .. (limits[k] and "_t" or "") .. ".tga")
        end
        show("dp_i_stab_m" .. k, k == mark)
    end
    Window.stab_pulse = (n > 0) and {name = "dp_i_stab_" .. n, base = "dp_ipip_" .. colour, rim = limits[n] ~= nil} or nil
    for k = 1, LAYOUT.trend or 0 do
        show("dp_i_stab_up" .. k, step > 0 and k <= speed)
        show("dp_i_stab_dn" .. k, step < 0 and k <= speed)
    end
    local parts = {}
    for _, r in ipairs(reasons) do
        table.insert(parts, r.text .. " " .. M.signed(r.value))
    end
    local way = (speed == 0) and "holding steady" or ((step > 0 and "rising" or "falling") .. " by about "
        .. M.round(M.abs(step) * 10) / 10 .. " a week")
    local stab_tip = "Imperial stability " .. M.round(s.stability) .. " (" .. Court.stability_word(s.stability)
        .. "), " .. way .. ", settling towards " .. M.round(target) .. " (the gold mark): " .. table.concat(parts, ", ")
        .. ". The chevrons show which way it moves and how fast. Low stability costs taxes, emboldens the lords and, "
        .. "below 60, brings crisis events (AWOL Moffs, risings, proclamations); far below, unrest spreads to the worlds."
    for _, part in ipairs({"dp_i_stab_label", "dp_i_stab_frame"}) do
        tip(part, stab_tip)
    end
    for k = 1, LAYOUT.stab_pips do
        tip("dp_i_stab_" .. k, limits[k] and (limits[k][2] .. " " .. stab_tip) or stab_tip)
        tip("dp_i_stab_m" .. k, stab_tip)
    end
    for k = 1, LAYOUT.trend or 0 do
        tip("dp_i_stab_up" .. k, stab_tip)
        tip("dp_i_stab_dn" .. k, stab_tip)
    end
    for _, tab in ipairs(LAYOUT.tabs) do
        local name = "dp_i_tab_" .. tab
        local risks = (tab == "factions") and table.getn(Politics.risks(s)) or 0
        text(name, TAB_NAMES[tab] .. ((risks > 0) and (" (" .. risks .. ")") or ""))
        icon(name, (Window.tab == tab) and "dp_i_tab_sel.tga" or "dp_i_tab.tga")
        tip(name, TAB_TIPS[tab] .. ((risks > 0) and (" " .. risks .. " lords at risk.") or ""))
    end
    tip("dp_i_close", "Close the court (the galaxy resumes).")
end

local function render_footer(s)
    local count = table.getn(s.petitions)
    if Window.petition > count then
        Window.petition = 1
    end
    local p = s.petitions[Window.petition]
    show("dp_ip_grant", p ~= nil)
    show("dp_ip_refuse", p ~= nil)
    show("dp_ip_next", count > 1)
    if p then
        local yes, no, yes_tip, no_tip = Politics.petition_answers(s, p)
        text("dp_ip_text", Politics.petition_text(s, p))
        local left = weeks(M.max(0, p.expires - s.week + 1))
        text("dp_ip_text2", "Answer within " .. left .. " (ignored, it counts as refused). " .. yes .. ": " .. yes_tip)
        tip("dp_ip_text", Politics.petition_text(s, p) .. " Answer within " .. left .. ".")
        tip("dp_ip_text2", yes .. ": " .. yes_tip .. " " .. no_tip .. " Left unanswered, it counts as refused.")
        text("dp_ip_grant", yes)
        text("dp_ip_refuse", no)
        tip("dp_ip_grant", yes .. ": " .. yes_tip)
        tip("dp_ip_refuse", no_tip)
        text("dp_ip_next", Window.petition .. "/" .. count)
        tip("dp_ip_next", "The next petition.")
        if p.kind == "ultimatum" or p.kind == "awol" then
            color("dp_ip_text", 1, 0.55, 0.45)
        else
            color("dp_ip_text", 0.92, 0.82, 0.59)
        end
    else
        text("dp_ip_text", "No petitions before the throne.")
        color("dp_ip_text", 0.92, 0.82, 0.59)
        text("dp_ip_text2", "Ambitious lords ask for titles, offices and favours; factions present their ultimatums here.")
        tip("dp_ip_text", "Petitions and ultimatums appear here.")
        tip("dp_ip_text2", " ")
    end
    text("dp_ip_news", s.news[1] or " ")
    local older = {}
    for k = 1, M.min(8, table.getn(s.news)) do
        table.insert(older, s.news[k])
    end
    tip("dp_ip_news", table.concat(older, "  |  "))
end

Window.realm_detail = realm_detail
Window.admiralty_detail = admiralty_detail
Window.court_detail = court_detail
function Window.intel_helpers()
    local function target_icon(target)
        local world = Intel.world_target(target)
        if world then
            return GLOBES[world] or "dp_globe_unknown.tga"
        end
        return faction_icon(target)
    end
    local function target_color(s, target)
        return owner_color(s, Intel.owner(target))
    end
    return {label = label, faction_icon = target_icon, owner_color = target_color, empty_detail = empty_detail}
end
Window.faction_detail = faction_detail
Window.legitimacy_detail = legitimacy_detail
Window.pick_detail = pick_detail
Window.pick_rows = pick_rows
Window.sector_rows = sector_rows
Window.hierarchy_rows = hierarchy_rows
Window.admiralty_rows = admiralty_rows
Window.faction_rows = faction_rows
Window.legitimacy_rows = legitimacy_rows

local function render(s)
    if not s or not s.ready then
        text("dp_i_title", "The Imperial Court")
        for _, key in ipairs(LAYOUT.stats) do
            text("dp_i_stat_" .. key, " ")
        end
        text("dp_i_ruler_name", "Assembling...")
        tip("dp_i_ruler_name", "The court assembles shortly after a new campaign starts. Come back in a few moments.")
        for _, shell in ipairs({"dp_imp_list_shell", "dp_imp_bars_shell", "dp_imp_detail_shell", "dp_imp_succ_shell",
                                "dp_imp_court_shell"}) do
            show(shell, false)
        end
        finish_tips()
        return
    end
    render_header(s)
    render_footer(s)
    local court_tab = Window.tab == "court" and not Window.pick
    show("dp_imp_list_shell", not court_tab)
    show("dp_imp_bars_shell", not court_tab)
    show("dp_imp_court_shell", court_tab)
    show("dp_imp_detail_shell", true)
    local succession = Window.tab == "legitimacy" and not Window.pick and not Window.sel.legitimacy
    local raise_why = Actions.raise_blocked(s)
    local raise_tool = {"Raise an officer", "raise", raise_why or ("A nobody joins the court (" .. CONFIG.RAISE.AUTHORITY
        .. " authority). Every lord resents it (" .. CONFIG.RAISE.OPINION .. " opinion); once every "
        .. M.weeks(CONFIG.RAISE.COOLDOWN) .. "."), raise_why ~= nil}
    local detail
    Window.sortable = nil
    if Window.pick then
        local head, cols, rows = Window.pick_rows(s)
        render_list(head, cols, rows)
        render_tools({{"Cancel", "cancel", "Back without choosing."}})
    elseif Window.tab == "realm" then
        render_list("The Realm", {"Sector", "Moff", "Worlds", "Loyalty"}, Window.sector_rows(s),
            "The oversectors, their sectors, then the unsectored systems. Portraits: gold frame in the field, silver "
                .. "known to history, black silhouette raised from the ranks.")
        render_tools({{Map.NAMES[s.map_mode or "off"], "map_mode", "Colour the galactic map: each Imperial world in its "
                          .. "sector's colour, or its lord's loyalty (green, yellow, red). Click to switch; the haze fades "
                          .. "once it is off."}, raise_tool})
        detail = Window.realm_detail(s)
    elseif Window.tab == "hierarchy" then
        local names = {all = "Everyone", lore = "Known to history", generated = "Raised from the ranks"}
        render_list("The Court", {"Name", "Holds", "Liege", "Loyalty"}, Window.hierarchy_rows(s),
            "Grand Moffs, Moffs, Governors and Commanders, then the court. Liege: whom they answer to, or how many "
                .. "vassals they have.")
        render_tools({
            {"Show: " .. names[Window.filter], "filter", "Gold frame: in the field (a unit on the map). Silver: known to "
                .. "history. Black silhouette: raised from the ranks. Click to filter."},
            {Window.departed and "Hide the departed" or "Show the departed", "departed", "The dead, the exiled, rebels and defectors."},
            raise_tool,
        })
        detail = Window.sel.hierarchy and s.chars[Window.sel.hierarchy] and char_detail(s, s.chars[Window.sel.hierarchy])
            or empty_detail("The Court", "Select a lord to see their loyalty, and why.")
    elseif Window.tab == "court" then
        render_court(s)
        detail = Window.court_detail(s)
    elseif Window.tab == "admiralty" then
        render_list("The Admiralty", {"Officer", "Flagship", "Liege", "Loyalty"}, Window.admiralty_rows(s),
            "The fleet's commands by rank. Click a vacant command to fill it.")
        render_tools({raise_tool})
        detail = Window.admiralty_detail(s)
    elseif Window.tab == "factions" then
        render_list("Factions at Court", {"Faction / lord", "Members / risk", "Strength", "Ultimatum / risk"}, Window.faction_rows(s))
        render_tools({})
        detail = Window.faction_detail(s)
    elseif Window.tab == "legitimacy" then
        render_list("Legitimacy among the Imperial Powers", {"Power", "Legitimacy", "Share", "Share"}, Window.legitimacy_rows(s))
        render_tools({})
        detail = Window.legitimacy_detail(s)
    elseif Window.tab == "intelligence" then
        local H = Window.intel_helpers()
        local head, cols, rows = IW.rows(s, H)
        render_list(head, cols, rows)
        render_tools(IW.tools(s))
        detail = IW.detail(s, H)
    end
    if Window.pick then
        detail = Window.pick_detail(s)
    end
    show("dp_imp_succ_shell", succession)
    if succession then
        render_succession(s)
    end
    local box = Window.tab == "intelligence" and not Window.pick
    show("dp_il_box", box)
    if box then
        local box_text, box_tip = IW.box(s)
        text("dp_il_box", box_text)
        tip("dp_il_box", box_tip)
    end
    if court_tab then
        local n = table.getn(IW.prisoners(s))
        text("dp_ic_prison", "Imperial Prison (" .. n .. ")")
        tip("dp_ic_prison", "The court's prisoners, arrested by Imperial Intelligence. Click to see them.")
    end
    render_detail(detail or empty_detail(" ", " "))
    finish_tips()
end
Window.render = render

local function list_tick(x, y, down, wheel)
    local top, segs, seg = LAYOUT.list_top, LAYOUT.list_segs, LAYOUT.list_seg
    local over = x > -478 and x < LAYOUT.list_bar_x + 12 and y < top + 20 and y > top - segs * seg - 20
    if wheel and wheel ~= 0 and over and not Window.ldragging then
        local v = M.min(Window.lmax + 1, M.max(1, (Window.page or 1) - M.round(wheel * 2)))
        if v ~= Window.page then
            Window.page = v
            render(IMPERIAL_COURT)
        end
    end
    if down ~= 1 then
        Window.ldragging = false
        return
    end
    if not Window.lwas_down then
        Window.ldragging = M.abs(x - LAYOUT.list_bar_x) <= 10 and y <= top and y >= top - segs * seg
    end
    if not Window.ldragging then
        return
    end
    local len = Window.lthumb_len or 24
    local span = M.max(1, segs * seg - len)
    Window.lthumb_share = M.min(1, M.max(0, (top - y - len / 2) / span))
    local v = 1 + M.round(Window.lthumb_share * Window.lmax)
    if v ~= Window.page then
        Window.page = v
        render(IMPERIAL_COURT)
    end
    draw_list_thumb()
end

local function world_tick(x, y, down, wheel)
    local top, segs = LAYOUT.world_top or 3, LAYOUT.world_segs or 0
    local over = x > 34 and x < 484 and y < top + 20 and y > top - segs * 4 - 20
    if wheel and wheel ~= 0 and over and not Window.wdragging then
        local v = M.min(Window.wmax, M.max(0, (Window.wscroll or 0) - M.round(wheel * 2)))
        if v ~= Window.wscroll then
            Window.wscroll = v
            render(IMPERIAL_COURT)
        end
    end
    if down ~= 1 then
        Window.wdragging = false
        return
    end
    if not Window.wwas_down then
        Window.wdragging = M.abs(x - 466) <= 12 and y <= top and y >= top - segs * 4
    end
    if not Window.wdragging then
        return
    end
    local len = Window.wthumb_len or 24
    local span = M.max(1, segs * 4 - len)
    Window.wthumb_share = M.min(1, M.max(0, (top - y - len / 2) / span))
    local v = M.round(Window.wthumb_share * Window.wmax)
    if v ~= Window.wscroll then
        Window.wscroll = v
        render(IMPERIAL_COURT)
    end
    draw_world_thumb()
end

function Window.tick()
    Window.ticks = (Window.ticks or 0) + 1
    local p = Window.open_now and Window.stab_pulse
    if p and Engine_Ticks then
        local t = Engine_Ticks()
        local frame = PULSE[M.floor(t / 120) - M.floor(t / 960) * 8 + 1]
        Window.pulse = true
        icon(p.name, (frame == 0) and (p.base .. (p.rim and "_t" or "") .. ".tga") or (p.base .. "_w" .. frame .. ".tga"))
    end
    local lists = (Window.lmax or 0) > 0 and (Window.tab ~= "court" or Window.pick ~= nil)
    if not (Window.open_now and Engine_Mouse and Engine_Screen_Size) or (not lists and (Window.wmax or 0) <= 0) then
        Window.wdragging, Window.ldragging = false, false
        return
    end
    local mx, my, down, wheel = Engine_Mouse()
    local w, h = Engine_Screen_Size()
    if not h or h <= 0 then
        return
    end
    local scale = h / 768
    local x, y = (mx - w / 2) / scale, (h / 2 - my) / scale
    if lists then
        list_tick(x, y, down, wheel)
    end
    if (Window.wmax or 0) > 0 then
        world_tick(x, y, down, wheel)
    end
    if down == 1 then
        Window.wwas_down, Window.lwas_down = true, true
    else
        Window.wwas_down, Window.lwas_down = false, false
    end
end

function Window.open(d)
    Window.d = d
    Window.open_now = true
    Window.feedback, Window.feedback2, Window.pick = nil, nil, nil
    for key, _ in pairs(cache) do
        cache[key] = {}
    end
    show("dp_imp_shell", true)
    render(IMPERIAL_COURT)
    if Pause then
        Pause.hold("court")
    end
    if Engine_Wheel_Capture then
        Engine_Wheel_Capture(1)
    end
    if Engine_Screen_Text then
        Engine_Screen_Text(0)
    end
end

function Window.reset_view()
    Window.sel, Window.page, Window.wscroll, Window.more, Window.pick = {}, 1, 0, false, nil
    Window.filter, Window.departed, Window.petition = "all", false, 1
    IW.reset()
end

function Window.close()
    for _, shell in ipairs(SHELLS) do
        show(shell, false)
    end
    if Window.open_now then
        Window.reset_view()
        Window.tab = "realm"
        if Pause then
            Pause.release("court")
        end
        if Engine_Wheel_Capture then
            Engine_Wheel_Capture(0)
        end
        if Engine_Screen_Text then
            Engine_Screen_Text(1)
        end
    end
    Window.open_now = false
end

local function show_on_map(world)
    local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
    local event = plot and plot.Get_Event("Diplomacy_Window_Camera")
    if not (event and world and FindPlanet(world)) then
        return false
    end
    event.Set_Reward_Parameter(0, world)
    Window.close()
    Story_Event("DIPLOMACY_WINDOW_CAMERA")
    return true
end

local function select_world(s, world)
    local key = Window.sel.realm
    if Window.sel_world and Window.sel_world.sector == key and Window.sel_world.world == world then
        Window.sel_world = nil
    else
        Window.sel_world = {sector = key, world = world}
    end
    Window.sys_details = false
end

local function goto_char(c)
    if c then
        Window.tab, Window.sel.hierarchy, Window.page, Window.more = "hierarchy", c.id, 1, false
    end
end

local function char_action(s, c, key)
    if key == "grant" then
        Window.pick, Window.page = {kind = "title", char = c.id}, 1
    elseif key == "office" then
        Window.pick, Window.page = {kind = "office", char = c.id}, 1
    elseif key == "honour" or key == "honour_leader" then
        return Actions.honour(s, c)
    elseif key == "tribute" then
        return Actions.tribute(s, c)
    elseif key == "minder" or key == "minder_leader" then
        for _, run in ipairs(s.ops.running or {}) do
            if run.key == "MINDER" and run.char == c.id then
                return Intel.recall(s, run)
            end
        end
        local why = IW.start(s, "MINDER", CONFIG.FACTION, {char = c.id})
        if why then
            return false, why
        end
        Window.tab, Window.page, Window.pick, Window.more = "intelligence", 1, nil, false
        return true, "Choose the operative who will watch " .. c.name .. "."
    elseif key == "bribe" then
        return Actions.bribe(s, c)
    elseif key == "revoke" then
        local list = Court.holdings(s, c)
        if table.getn(list) == 0 then
            return Actions.revoke(s, c)
        elseif table.getn(list) == 1 then
            return Actions.revoke(s, c, list[1].title, list[1].key)
        end
        Window.pick, Window.page = {kind = "revoke", char = c.id}, 1
        return true, "Choose which title " .. c.name .. " loses."
    elseif key == "dismiss" then
        local office = Court.office_of(s, c)
        if office then
            return Actions.dismiss_office(s, office)
        end
    elseif key == "arrest" or key == "arrest_leader" then
        local why = IW.start(s, "ARREST", CONFIG.FACTION, {char = c.id})
        if why then
            return false, why
        end
        Window.tab, Window.page, Window.pick, Window.more = "intelligence", 1, nil, false
        return true, "Choose the operative who will make the arrest."
    elseif key == "map" then
        local worlds = Court.worlds_of(s, c)
        local seat = (c.title == "moff" and s.sectors[c.holds]) and s.sectors[c.holds].seat or worlds[1]
        show_on_map(seat)
    elseif key == "goto_char" or key == "goto_leader" then
        goto_char(c)
    elseif key == "dismiss_fleet" then
        return Actions.dismiss_fleet(s, c)
    elseif key == "rebuild_ship" then
        local _, message = Fleet.rebuild(s, c)
        return message
    elseif key == "more" then
        Window.more = true
    elseif key == "back" then
        Window.more = false
    end
    return nil
end

local function pick_holder(head, done, holder)
    local s = IMPERIAL_COURT
    Window.pick, Window.page = {kind = "char", head = head, done = done, holder = holder,
                                blocked = function(c)
                                    return Actions.protected(s, c, "title")
                                end}, 1
end
Window.pick_holder = pick_holder

local function detail_action(s, a)
    local key = a[2]
    local ok, message
    if Window.pick and (key == "confirm_pick" or key == "cancel_pick") then
        local p = Window.pick
        local c = p.sel and s.chars[p.sel]
        if key == "cancel_pick" or not c then
            Window.pick = nil
            return
        end
        local why = p.blocked and p.blocked(c)
        if why then
            Window.feedback = why
            return
        end
        ok, message = p.done(c)
        if ok then
            Window.pick = nil
        end
        Window.feedback = message
        return
    end
    if Window.tab == "hierarchy" or (Window.tab == "factions" and type(Window.sel.factions) == "number") then
        local c = s.chars[(Window.tab == "hierarchy") and Window.sel.hierarchy or Window.sel.factions]
        if c then
            ok, message = char_action(s, c, key)
        end
    elseif Window.tab == "factions" then
        local f = s.factions[string.sub(Window.sel.factions or "F_", 3)]
        local leader = f and Court.char(s, f.leader)
        if leader then
            ok, message = char_action(s, leader, key)
        end
    elseif Window.tab == "realm" and type(Window.sel.realm) == "string" and string.find(Window.sel.realm, "^U_") then
        local world = string.sub(Window.sel.realm, 3)
        local word = Court.is_station(world) and CONFIG.COMMANDER.name or "Governor"
        if key == "appoint_world" then
            pick_holder("Choose the " .. word .. " of " .. Court.planet_label(world), function(c)
                return Actions.grant_title(s, c, "governor", world)
            end, function()
                return Court.char(s, s.governor[world])
            end)
        elseif key == "proclaim_here" then
            local _, msg, new_key = Actions.proclaim(s, world)
            message = msg
            if new_key then
                Window.sel.realm = new_key
            end
        elseif key == "map" then
            show_on_map(world)
        elseif key == "goto_char" then
            goto_char(Court.char(s, s.governor[world]))
        end
    elseif Window.tab == "realm" and type(Window.sel.realm) == "string" and string.find(Window.sel.realm, "^O_") then
        local okey = string.sub(Window.sel.realm, 3)
        local over = s.oversectors[okey]
        local gm = over and Court.char(s, over.holder)
        if over and key == "appoint_gm" then
            pick_holder("Choose the Grand Moff of the " .. over.name, function(c)
                return Actions.grant_title(s, c, "grand_moff", okey)
            end, function()
                return Court.char(s, over.holder)
            end)
        elseif gm then
            ok, message = char_action(s, gm, key)
        end
    elseif Window.tab == "admiralty" then
        local sel = Window.sel.admiralty
        if key == "goto_council" then
            Window.tab, Window.sel.court, Window.page, Window.more, Window.pick = "court", "FLEET", 1, false, nil
        elseif key == "pick_fleet" and type(sel) == "string" and CONFIG.ADMIRALTY[string.sub(sel, 3)] then
            local rank = string.sub(sel, 3)
            local from = CONFIG.ADMIRALTY[rank].from
            Window.pick = {kind = "char", head = "Choose the " .. CONFIG.ADMIRALTY[rank].name
                               .. (from and (" (" .. Actions.fleet_sources(rank) .. ")") or ""), page = 1, rank = rank,
                           filter = from and function(c)
                               return Actions.fleet_eligible(c, rank)
                           end or nil, no_raise = from ~= nil,
                           blocked = function(c)
                               return Actions.fleet_blocked(s, c, rank)
                           end,
                           done = function(c)
                               local done, msg = Actions.appoint_fleet(s, c, rank)
                               if done then
                                   Window.sel.admiralty = c.id
                               end
                               return done, msg
                           end}
            Window.page = 1
        elseif type(sel) == "number" and s.chars[sel] then
            ok, message = char_action(s, s.chars[sel], key)
        end
    elseif Window.tab == "realm" then
        local sector = s.sectors[Window.sel.realm or ""]
        local picked = sector and Window.sel_world and Window.sel_world.sector == sector.key and Window.sel_world.world
        if picked and key == "sys_details" then
            Window.sys_details = true
        elseif key == "sys_back" then
            Window.sys_details = false
        elseif picked and key == "sys_map" then
            show_on_map(picked)
        elseif picked and key == "sys_gov" then
            pick_holder("Choose the Governor of " .. Court.planet_label(picked), function(c)
                return Actions.grant_title(s, c, "governor", picked)
            end, function()
                return Court.char(s, s.governor[picked])
            end)
        elseif key == "proclaim" then
            local direct = Court.direct_worlds(s)
            Window.pick = {kind = "world", worlds = direct, head = "Proclaim a sector: choose its seat",
                           done = function(world)
                               local _, msg, new_key = Actions.proclaim(s, world)
                               Window.feedback = msg
                               if new_key then
                                   Window.sel.realm = new_key
                               end
                           end}
            Window.page = 1
        elseif sector and key == "appoint_moff" then
            pick_holder("Choose the Moff of the " .. sector.name, function(c)
                return Actions.grant_title(s, c, "moff", sector.key)
            end, function()
                return Court.char(s, sector.holder)
            end)
        elseif sector and key == "appoint_gov" then
            local worlds = {}
            for _, name in ipairs(sector.worlds) do
                if name ~= sector.seat then
                    table.insert(worlds, name)
                end
            end
            Window.pick = {kind = "world", worlds = worlds, head = "Choose a world of the " .. sector.name,
                           done = function(world)
                               pick_holder("Choose the Governor of " .. Court.planet_label(world), function(c)
                                   return Actions.grant_title(s, c, "governor", world)
                               end, function()
                                   return Court.char(s, s.governor[world])
                               end)
                           end}
            Window.page = 1
        elseif sector and key == "map" then
            show_on_map(sector.seat)
        elseif sector and sector.holder then
            ok, message = char_action(s, s.chars[sector.holder], key)
        end
    elseif Window.tab == "court" then
        local office = Window.sel.court
        if key == "dismiss_office" and office then
            ok, message = Actions.dismiss_office(s, office)
        elseif key == "pick_office_cand" and office then
            Window.pick = {kind = "char", head = "Choose the " .. Court.office_def(s, office).name, office = office,
                           holder = function()
                               return Court.char(s, s.offices[office])
                           end,
                           blocked = function(c)
                               if s.offices[office] == c.id then
                                   return "They hold it already."
                               end
                               local holder = Court.char(s, s.offices[office])
                               if holder and holder.status == "serving" then
                                   return holder.name .. " holds it: dismiss them first."
                               end
                               local cost = Actions.cost(s, CONFIG.ACTIONS.APPOINT)
                               if s.authority < cost then
                                   return "Needs " .. cost .. " authority."
                               end
                               return Court.office_of(s, c) and Actions.protected(s, c, "dismiss") or nil
                           end,
                           done = function(c)
                               return Actions.appoint_office(s, c, office)
                           end}
            Window.page = 1
        elseif key == "raise" then
            ok, message = Actions.raise_officer(s)
        elseif key == "goto_char" and office then
            goto_char(Court.char(s, s.offices[office]))
        end
    elseif Window.tab == "legitimacy" then
        local faction = string.sub(Window.sel.legitimacy or "W_", 3)
        if key == "fealty" then
            ok, message = Politics.fealty(s, faction)
        elseif key == "op_PAGE" then
            Window.tab, Window.page, Window.more = "intelligence", 1, false
            IW.reset()
            IW.row_click(s, "T_" .. faction)
        elseif key == "op_SWAY" then
            local why = IW.start(s, "SWAY", faction)
            if why then
                message = why
            else
                Window.tab, Window.page, Window.more = "intelligence", 1, false
                IW.sel = "T_" .. faction
                message = "Choose the operative at their capital."
            end
        end
    elseif Window.tab == "intelligence" then
        local world
        message, world = IW.action(s, key)
        if world then
            show_on_map(world)
        end
    end
    if message then
        Window.feedback = message
    end
end

function Window.click(d, name, button)
    IMPERIAL_COURT_IN_CLICK = true
    local ok, err = pcall(Window.click_now, d, name, button)
    IMPERIAL_COURT_IN_CLICK = nil
    if not ok then
        error(err)
    end
end

function Window.click_now(d, name, button)
    if Engine_Log then
        Engine_Log("COURT WINDOW " .. tostring(button) .. " click " .. tostring(name))
    end
    if string.find(name, "^b_senate_panel") then
        if button ~= "right" then
            if Window.open_now then
                Window.close()
            else
                Window.open(d)
            end
        end
        return
    end
    if name == "dp_i_close" then
        Window.close()
        return
    end
    if not Window.open_now then
        return
    end
    local s = IMPERIAL_COURT
    if not s or not s.ready then
        render(s)
        return
    end
    Window.feedback, Window.feedback2 = nil, nil
    local _, _, tab = string.find(name, "^dp_i_tab_(%a+)$")
    local _, _, row = string.find(name, "^dp_il_r(%d+)")
    local _, _, action = string.find(name, "^dp_id_a(%d+)$")
    local _, _, tool = string.find(name, "^dp_il_tool(%d+)$")
    local _, _, seat = string.find(name, "^dp_ic_s(%d+)")
    local _, _, line = string.find(name, "^dp_id_l(%d+)")
    local _, _, wrow, wpart = string.find(name, "^dp_id_w(%d+)_(%a+)$")
    if tab then
        Window.reset_view()
        Window.tab = tab
    elseif row then
        local r = Window.rows and Window.rows[tonumber(row)]
        if r and r.key ~= "HEAD" then
            if Window.pick then
                do_pick(s, r.key)
            elseif Window.tab == "realm" then
                Window.sel.realm = (Window.sel.realm ~= r.key) and r.key or nil
                Window.wscroll = 0
            elseif Window.tab == "hierarchy" then
                Window.sel.hierarchy = (Window.sel.hierarchy ~= r.key) and r.key or nil
                Window.more = false
            elseif Window.tab == "admiralty" then
                Window.sel.admiralty = (Window.sel.admiralty ~= r.key) and r.key or nil
                Window.more = false
            elseif Window.tab == "factions" then
                Window.sel.factions = (Window.sel.factions ~= r.key) and r.key or nil
                Window.more = false
            elseif Window.tab == "legitimacy" then
                Window.sel.legitimacy = (Window.sel.legitimacy ~= r.key) and r.key or nil
            elseif Window.tab == "intelligence" then
                IW.row_click(s, r.key)
            end
        end
    elseif action then
        local a = Window.actions and Window.actions[tonumber(action)]
        if a and not a[4] then
            detail_action(s, a)
        elseif a then
            Window.feedback = a[5] or a[3]
        end
    elseif tool then
        local t = Window.tools and Window.tools[tonumber(tool)]
        local key = t and t[2]
        if t and t[4] then
            Window.feedback = t[3]
            key = nil
        end
        if key == "cancel" then
            Window.pick = nil
        elseif key == "raise" then
            local _, message = Actions.raise_officer(s)
            Window.feedback = message
        elseif key == "filter" then
            Window.filter = (Window.filter == "all") and "lore" or ((Window.filter == "lore") and "generated" or "all")
            Window.page = 1
        elseif key == "departed" then
            Window.departed = not Window.departed
        elseif key == "map_mode" then
            local mode = Map.next_mode(s)
            Window.feedback = (mode == "off") and "The map haze fades within a minute." or ("Map mode: " .. mode .. ".")
        elseif key and string.find(key, "^iw_") then
            local message, world = IW.action(s, key)
            Window.feedback = message
            if world then
                show_on_map(world)
            end
        end
    elseif seat then
        local key = CONFIG.OFFICE_ORDER[tonumber(seat)]
        Window.sel.court = (Window.sel.court ~= key) and key or nil
    elseif name == "dp_ic_throne" or name == "dp_ic_leader" or name == "dp_ic_regime" then
        Window.sel.court = "THRONE"
    elseif line and string.find(name, "_hit$") and Window.world_rows and Window.world_rows[tonumber(line)] then
        local w = Window.world_rows[tonumber(line)]
        if w.pick ~= nil then
            Window.feedback = IW.choose(s, w)
        elseif w.world and Window.tab == "realm" and s.sectors[Window.sel.realm or ""] then
            select_world(s, w.world)
        elseif w.lord then
            goto_char(w.lord)
        elseif w.world then
            show_on_map(w.world)
        end
    elseif line then
        local key = Window.line_keys and Window.line_keys[tonumber(line)]
        if key and s.chars[key] then
            goto_char(s.chars[key])
        end
    elseif wrow then
        local w = Window.world_rows and Window.world_rows[tonumber(wrow)]
        if w and w.pick ~= nil and wpart ~= "zoom" and wpart ~= "globe" then
            Window.feedback = IW.choose(s, w)
        elseif w and (wpart == "zoom" or wpart == "globe") then
            show_on_map(w.world)
        elseif w and wpart == "name" and w.world and Window.tab == "realm" and s.sectors[Window.sel.realm or ""] then
            select_world(s, w.world)
        elseif w and w.lord then
            goto_char(w.lord)
        end
    elseif name == "dp_id_portrait" and Window.portrait_char and not Window.pick then
        local c = Window.portrait_char
        if c.status == "serving" and not (Window.tab == "hierarchy" and Window.sel.hierarchy == c.id) then
            goto_char(c)
        end
    elseif name == "dp_id_w_up" then
        Window.wscroll = M.max(0, (Window.wscroll or 0) - 1)
    elseif name == "dp_id_w_down" then
        Window.wscroll = (Window.wscroll or 0) + 1
    elseif string.find(name, "^dp_id_wseg%d") then
        local _, _, k = string.find(name, "(%d+)$")
        Window.wscroll = M.round((tonumber(k) - 1) * (Window.wmax or 0) / M.max(1, (LAYOUT.world_segs or 1) - 1))
    elseif Window.succ_slots and Window.succ_slots[name] and Window.tab == "legitimacy" then
        local key = Window.succ_slots[name]
        if ruler_state(s, key) == "next" and CONFIG.SUCCESSION_EVENTS[key] then
            local _, message = Politics.fire_succession(s, key)
            Window.feedback = message
        else
            Window.feedback = ruler_tip(s, key, ruler_state(s, key))
        end
    elseif string.find(name, "^dp_i_ruler") then
        Window.tab, Window.sel.court, Window.pick, Window.more = "court", "THRONE", nil, false
    elseif name == "dp_il_box" then
        IW.box_click(s)
    elseif name == "dp_ic_prison" then
        Window.sel.court = (Window.sel.court ~= "PRISON") and "PRISON" or nil
    elseif name == "dp_il_down" then
        Window.page = M.min((Window.lmax or 0) + 1, (Window.page or 1) + 1)
    elseif name == "dp_il_up" then
        Window.page = M.max(1, (Window.page or 1) - 1)
    elseif string.find(name, "^dp_il_seg%d") then
        local _, _, k = string.find(name, "(%d+)$")
        Window.page = 1 + M.round((tonumber(k) - 1) * (Window.lmax or 0) / M.max(1, LAYOUT.list_segs - 1))
    elseif string.find(name, "^dp_il_h_") and Window.pick and Window.sortable then
        local _, _, col = string.find(name, "^dp_il_h_(%a+)")
        local key = Window.sortable[col]
        if key then
            local sort = Window.pick.sort
            if sort and sort.key == key then
                sort.up = not sort.up
            else
                Window.pick.sort = {key = key, up = false}
            end
            Window.page = 1
        end
    elseif name == "dp_ip_next" then
        Window.petition = Window.petition + 1
    elseif name == "dp_ip_grant" or name == "dp_ip_refuse" then
        local p = s.petitions[Window.petition]
        if p then
            local _, message = Politics.answer(s, p, name == "dp_ip_grant")
            Window.feedback = message
        end
    end
    if Window.open_now then
        render(s)
    end
end

return Window
