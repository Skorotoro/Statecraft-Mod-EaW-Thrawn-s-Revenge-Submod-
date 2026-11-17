local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")
local Court = require("eawx-plugins/imperial-court/Court")
local LAYOUT = require("eawx-plugins/imperial-court/CourtLayout")

local Panel = {sel = nil, variant = nil, shown = false, ids = {}, human = false, owners = {}}

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("COURT PANEL gui error: " .. tostring(err))
    end
end

local function P(part)
    return "dp_cl" .. Panel.variant .. "_" .. part
end

local function tip(name, value)
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_" .. string.upper(name) .. "_TIP", value or " ")
    end
end

local function pick_variant()
    local width = 1365
    if Engine_Screen_Size then
        local w, h = Engine_Screen_Size()
        if w and h and h > 0 then
            width = 768 * w / h
        end
    end
    local best, gap = nil, nil
    for v, wv in pairs(LAYOUT.panel_variants or {}) do
        local g = M.max(wv - width, width - wv)
        if not gap or g < gap then
            best, gap = v, g
        end
    end
    return best
end

local function hide()
    if Panel.shown and Panel.variant then
        call(GUI_Component_Visibility, P("shell"), false)
    end
    Panel.shown = false
end

local function current()
    local name
    if Engine_Zoomed_Planet then
        name = Engine_Zoomed_Planet()
    elseif Engine_Selected_Planet then
        name = Engine_Selected_Planet()
    end
    return name and string.upper(name) or nil
end

local function describe(s, c, post, extra)
    if not c then
        return post .. ": vacant. Nobody holds it, and the world goes unmanaged. Click to appoint someone."
    end
    return post .. ": " .. Court.full_name(c) .. ", appointed in week " .. (c.since or 0) .. ". Loyalty " .. M.round(c.loyalty)
        .. " (" .. Court.loyalty_word(c.loyalty) .. "), power " .. M.round(Court.power(s, c)) .. ". " .. Court.kind_text(c)
        .. (extra or "") .. " Click for their page at court."
end

local function lords_of(s, name)
    local sector = s.sectors[s.world[name] or ""]
    local label = Court.planet_label(name)
    local below, below_post, below_word, above, above_post, liege
    if sector and not sector.crown then
        above, above_post = Court.char(s, sector.holder), "Moff of the " .. sector.name
        local over = sector.oversector and s.oversectors[sector.oversector]
        liege = over and Court.char(s, over.holder)
    end
    if sector and sector.seat == name and not sector.crown then
        below, below_post, below_word = above, "Seat of the " .. sector.name .. ", governed by its Moff", "Moff"
    elseif Court.is_station(name) then
        below, below_post, below_word = Court.char(s, s.governor[name]), "Commander of " .. label, CONFIG.COMMANDER.name
    else
        below, below_post, below_word = Court.char(s, s.governor[name]), "Governor of " .. label, "Governor"
    end
    return below, below_post, below_word, above, above_post, sector, liege
end

function Panel.render(s, name)
    Court.no_lookups = true
    local ok, err = pcall(Panel.draw, s, name)
    Court.no_lookups = nil
    if not ok then
        error(err)
    end
end

function Panel.draw(s, name)
    local below, below_post, below_word, above, above_post, sector, liege = lords_of(s, name)
    local crown = sector and sector.crown
    call(GUI_Button_Icon, P("below"), crown and "dp_imark_gold.tga" or Court.portrait(below), 1, 1, 1, 1)
    local below_tip = crown and ("The throne's own world: " .. Court.regime(s).leader .. " rules it.")
        or describe(s, below, below_post)
    tip(P("below"), below_tip)
    call(GUI_Component_Text, P("below_cap"), crown and "Throne" or below_word)
    tip(P("below_cap"), below_tip)
    local has_above = above_post ~= nil
    for _, part in ipairs({"above", "above_cap", "frame_moff"}) do
        call(GUI_Component_Visibility, P(part), has_above)
    end
    if has_above then
        call(GUI_Button_Icon, P("above"), Court.portrait(above), 1, 1, 1, 1)
        local above_tip = describe(s, above, above_post, liege and (" Answers to " .. Court.full_name(liege) .. ".") or nil)
        tip(P("above"), above_tip)
        call(GUI_Component_Text, P("above_cap"), "Moff")
        tip(P("above_cap"), above_tip)
    end
    Panel.ids = {below = below and below.id, above = above and above.id}
    local below_post_key
    if crown then
        below_post_key = nil
    elseif sector and sector.seat == name then
        below_post_key = {title = "moff", key = sector.key, name = sector.name}
    else
        below_post_key = {title = "governor", key = name, name = Court.planet_label(name)}
    end
    Panel.posts = {below = below_post_key,
                   above = (sector and not crown) and {title = "moff", key = sector.key, name = sector.name} or nil}
end

function Panel.refresh(s)
    local empire = Court.player()
    Panel.human = empire ~= nil and empire.Is_Human()
    local sel = Panel.human and current()
    if not sel then
        return
    end
    local planet = FindPlanet(sel)
    local owner = planet and string.upper(planet.Get_Owner().Get_Faction_Name())
    local below, _, _, above = lords_of(s, sel)
    for _, c in ipairs({below or false, above or false}) do
        if c and c.holds and c.title == "governor" then
            Court.planet_label(c.holds)
        end
    end
    Court.planet_label(sel)
    if owner ~= Panel.owners[sel] then
        Panel.owners[sel] = owner
        Panel.refresh_at = 0
    end
end

function Panel.tick(blocked)
    local s = IMPERIAL_COURT
    if blocked or type(s) ~= "table" or not s.ready or not Panel.human or not (Engine_Zoomed_Planet or Engine_Selected_Planet) then
        hide()
        Panel.sel = nil
        return
    end
    if not Panel.cleaned then
        Panel.cleaned = true
        for v, _ in pairs(LAYOUT.panel_variants or {}) do
            call(GUI_Component_Visibility, "dp_cl" .. v .. "_shell", false)
        end
    end
    local v = pick_variant()
    if not v then
        return
    end
    if Panel.variant and Panel.variant ~= v then
        hide()
    end
    Panel.variant = v
    local sel = current()
    local now = GetCurrentTime()
    local ms = Engine_Ticks and Engine_Ticks() or 0
    if sel ~= Panel.sel then
        hide()
        Panel.sel, Panel.zoom_at, Panel.refresh_at = sel, ms, 0
        return
    end
    if Engine_Ticks and ms - (Panel.zoom_at or 0) < CONFIG.PANEL_DELAY_MS and ms >= (Panel.zoom_at or 0) then
        return
    end
    if Panel.shown and now < (Panel.refresh_at or 0) then
        return
    end
    Panel.refresh_at = now + 2
    local owner = sel and (Panel.owners[sel] or (s.owners and s.owners[sel]))
    if owner ~= CONFIG.FACTION then
        hide()
        return
    end
    Panel.render(s, sel)
    if not Panel.shown then
        call(GUI_Component_Visibility, P("shell"), true)
        Panel.shown = true
    end
end

function Panel.click(name)
    local s = IMPERIAL_COURT
    local part = string.find(name, "_above") and "above" or "below"
    local id = Panel.ids[part]
    local c = s and id and s.chars[id]
    local ok, Window = pcall(require, "eawx-plugins/imperial-court/CourtWindow")
    if not (ok and Window and s and s.ready) then
        return
    end
    if c then
        Window.tab, Window.sel.hierarchy, Window.page, Window.more, Window.pick = "hierarchy", c.id, 1, false, nil
    else
        local post = Panel.posts and Panel.posts[part]
        if not post then
            return
        end
        local Actions = require("eawx-plugins/imperial-court/CourtActions")
        Window.tab, Window.page, Window.more, Window.pick = "realm", 1, false, nil
        if post.title == "moff" then
            Window.sel.realm = post.key
            Window.pick_holder("Choose the Moff of the " .. post.name, function(lord)
                return Actions.grant_title(s, lord, "moff", post.key)
            end, function()
                return Court.char(s, s.sectors[post.key] and s.sectors[post.key].holder)
            end)
        else
            local word = Court.is_station(post.key) and CONFIG.COMMANDER.name or "Governor"
            Window.sel.realm = s.world[post.key] or ("U_" .. post.key)
            Window.pick_holder("Choose the " .. word .. " of " .. post.name, function(lord)
                return Actions.grant_title(s, lord, "governor", post.key)
            end, function()
                return Court.char(s, s.governor[post.key])
            end)
        end
    end
    if Window.open_now then
        Window.render(s)
    else
        local pick = Window.pick
        Window.open(Window.d)
        if pick and not Window.pick then
            Window.pick = pick
            Window.render(s)
        end
    end
end

return Panel
