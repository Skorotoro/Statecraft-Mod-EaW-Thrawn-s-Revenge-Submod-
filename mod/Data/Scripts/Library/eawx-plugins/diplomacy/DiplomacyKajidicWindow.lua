local Pause = require("eawx-plugins/diplomacy/DiplomacyPause")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local K = require("eawx-plugins/diplomacy/DiplomacyKajidii")
local LAYOUT = require("eawx-plugins/diplomacy/DiplomacyKajidicLayout")
local GLOBES = require("eawx-plugins/diplomacy/DiplomacyGlobes")

local R = CONFIG.UNDERWORLD
local Window = {open_now = false, selected = nil, page = 1, tab = "space", tier = nil}
local NUMERALS = {"I", "II", "III", "IV", "V"}
local SHELLS = {"dp_kaj_shell", "dp_kaj_cards_shell", "dp_kaj_tree_shell", "dp_kaj_cols_shell"}
local function tree_shell(i)
    return "dp_kaj_tree" .. i .. "_shell"
end

local function underworld()
    local ok, U = pcall(require, "eawx-plugins/diplomacy/DiplomacyUnderworld")
    local okm, Missions = pcall(require, "eawx-plugins/diplomacy/DiplomacyKajidicMissions")
    return ok and U or nil, okm and Missions or nil
end

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("KAJIDII WINDOW gui error: " .. tostring(err))
    end
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

local ICONS = {}
local function icon(name, texture)
    if ICONS[name] == texture then
        return
    end
    ICONS[name] = texture
    call(GUI_Button_Icon, name, texture, 1, 1, 1, 1)
end

local function grey(name, off)
    if off then
        call(GUI_Text_Color, name, 0.45, 0.45, 0.48, 1)
    else
        call(GUI_Text_Color, name, 0.92, 0.82, 0.59, 1)
    end
end

local function bright(name)
    call(GUI_Text_Color, name, 1, 0.95, 0.7, 1)
end

local function family_name(i)
    return "the " .. K.FAMILIES[i].name .. " kajidic"
end

local function weeks(n)
    return n .. ((n == 1) and " week" or " weeks")
end

function Window.tier_of(d, f)
    if Window.tier then
        return Window.tier
    end
    local U = underworld()
    local tier = (U and d.underworld) and U.tier(d, f) or 0
    return M.min(tier + 1, LAYOUT.tiers)
end

local POINTS = {}
do
    local seen = {}
    for k, n in ipairs(LAYOUT.point_tiers) do
        seen[n] = (seen[n] or 0) + 1
        POINTS[k] = {tier = n, index = seen[n]}
    end
end

local function tier_special(n)
    for _, point in ipairs(R.TIERS[n] and R.TIERS[n].points or {}) do
        if point.special then
            return true
        end
    end
    return false
end
Window.tier_special = tier_special

function Window.point_short(f, point)
    if point.special then
        local _, Missions = underworld()
        local special = Missions and Missions.def(Missions.special_mission(f))
        return "special action: " .. (special and special.name or "?")
    end
    return point.short
end

function Window.tier_short(f, n)
    local parts = {}
    for _, point in ipairs(R.TIERS[n].points) do
        table.insert(parts, Window.point_short(f, point))
    end
    return table.concat(parts, "; ")
end

local function tier_need(d, f, n)
    local U, Missions = underworld()
    if not U or not d.underworld then
        return ""
    end
    local line
    if n == 1 then
        local mission = Missions and Missions.def(Missions.family_mission(f))
        line = "Needs the family's mission" .. (mission and (", " .. mission.name) or "") .. "."
    else
        local need = U.tier_worlds(d, n)
        line = "Needs " .. need .. ((need == 1) and " controlled world" or " controlled worlds") .. " (now "
            .. U.controlled(d, f) .. ")."
    end
    local tier = U.tier(d, f)
    if n <= tier then
        return line .. " Reached."
    end
    return line .. ((n == tier + 1) and " Next to reach." or " Locked.")
end

function Window.tier_tip(d, f, n, point)
    local def = R.TIERS[n]
    local gives = {}
    for _, p in ipairs(point and {point} or def.points) do
        table.insert(gives, p.unlock)
    end
    return "Tier " .. n .. ", " .. (point and point.name or def.name) .. ": " .. table.concat(gives, " ") .. " "
        .. tier_need(d, f, n)
end

local function render_family(d, f)
    local U, Missions = underworld()
    local fam = K.FAMILIES[f]
    if not U or not d.underworld then
        text("dp_kf_head", "The " .. fam.name .. " kajidic")
        for k = 1, LAYOUT.stats do
            text("dp_kf_stat" .. k, " ")
        end
        text("dp_kf_tiers", " ")
        for n = 1, LAYOUT.tiers do
            show("dp_kf_t" .. n, false)
            show("dp_kf_t" .. n .. "_icon", false)
        end
        show("dp_kf_mission", false)
        show("dp_kf_recruit", false)
        return
    end
    U.init(d)
    local tier = U.tier(d, f)
    local power = U.power(d)
    local politics = U.politics(d, power)
    local leader = U.leader_family(d)
    text("dp_kf_head", "The " .. fam.name .. " kajidic - " .. ((leader == f) and "Boss Family, " or "")
        .. ((tier > 0) and ("tier " .. tier .. ", " .. R.TIERS[tier].name) or "tier 0, outsiders"))

    local line1 = "Power: " .. M.floor(power[f].share + 0.5) .. "% of the Hutt underworld"
    if politics[f] then
        line1 = line1 .. " - " .. politics[f].text
    elseif leader == f then
        line1 = line1 .. " - the Boss Family"
    end
    text("dp_kf_stat1", line1)
    tip("dp_kf_stat1", "Power counts the family's Hutt worlds, the underworlds it controls, its influence on "
        .. "contested ones and its heroes. It sets how fast its Upstarts are ready.")
    local hutt_worlds, controlled, leading = 0, 0, 0
    for _, w in ipairs(K.worlds(d)) do
        if w.held and w.state == "hutt" and w.family == f then
            hutt_worlds = hutt_worlds + 1
        elseif not w.held and w.rec then
            if w.rec.state == "controlled" and w.rec.family == f then
                controlled = controlled + 1
            elseif w.rec.state ~= "controlled" and U.leader_of(w.rec) == f then
                leading = leading + 1
            end
        end
    end
    local owned = hutt_worlds + controlled
    text("dp_kf_stat2", "Controls " .. owned .. ((owned == 1) and " world (" or " worlds (") .. hutt_worlds .. " Hutt, "
        .. controlled .. ((controlled == 1) and " underworld); leads " or " underworlds); leads ") .. leading
        .. " contested")
    tip("dp_kf_stat2", "Controlled worlds raise the family's tier. An underworld becomes the family's own when it "
        .. "wins the Turf War there.")
    local names = {}
    for _, hero in ipairs(U.heroes(d)[f]) do
        local name = d.unit_name(hero.type)
        local seen = false
        for _, n in ipairs(names) do
            if n == name then
                seen = true
            end
        end
        if not seen then
            table.insert(names, name)
        end
    end
    text("dp_kf_stat3", "Heroes: " .. ((table.getn(names) > 0) and table.concat(names, ", ") or "none in your service"))
    tip("dp_kf_stat3", "Each Hutt hero belongs to a family. Standing on an underworld, a hero raises their family's "
        .. "influence there by " .. R.INFLUENCE_HERO_WEEK .. " a week.")
    local ops = {}
    for _, key in ipairs(R.STRUCTURE_ORDER) do
        local def = R.STRUCTURES[key]
        if def.family == fam.key then
            table.insert(ops, R.OPERATIONS[def.op].name)
        end
    end
    text("dp_kf_stat4", fam.spec[1] .. " - operations: " .. table.concat(ops, ", "))
    tip("dp_kf_stat4", "The family's buildings open these operations; the family runs them and gains the influence.")

    text("dp_kf_tiers", "Tiers")
    local sel = Window.tier_of(d, f)
    for n = 1, LAYOUT.tiers do
        local def = R.TIERS[n]
        show("dp_kf_t" .. n, def ~= nil)
        show("dp_kf_t" .. n .. "_icon", def ~= nil)
        if def then
            local need = (n == 1) and "mission" or (U.tier_worlds(d, n) .. ((U.tier_worlds(d, n) == 1) and " world" or " worlds"))
            local what = Window.tier_short(f, n)
            if table.getn(def.points) > 1 then
                local names = {}
                for _, point in ipairs(def.points) do
                    table.insert(names, point.name)
                end
                what = table.concat(names, " and ")
            end
            text("dp_kf_t" .. n, "Tier " .. n .. ", " .. def.name .. " - " .. what .. " (" .. need .. ")")
            if n == sel then
                bright("dp_kf_t" .. n)
            else
                grey("dp_kf_t" .. n, n > tier + 1)
            end
            icon("dp_kf_t" .. n .. "_icon", (n <= tier) and "dp_kf_done.tga" or ((n == tier + 1) and "dp_kf_next.tga"
                or "dp_kf_lock.tga"))
            tip("dp_kf_t" .. n, Window.tier_tip(d, f, n) .. " Click to select.")
        end
    end

    local def = R.TIERS[sel]
    local key = Missions and ((sel == 1) and Missions.family_mission(f)
        or (def and tier_special(sel) and Missions.special_mission(f))) or nil
    local mission = key and Missions.def(key)
    local running = Missions and Missions.running(d, f)
    show("dp_kf_mission", def ~= nil)
    if mission then
        local off
        if mission.kind == "unlock" and U.family(d, f).unlocked then
            text("dp_kf_mission", mission.name .. ": done")
            off = true
        elseif running then
            local now = Missions.def(running.key)
            text("dp_kf_mission", (now and now.name or "Mission") .. ": " .. weeks(Missions.weeks_left(running)) .. " left")
            off = true
        else
            if mission.kind == "special" and tier < R.SPECIAL_TIER then
                text("dp_kf_mission", mission.name .. " (at tier " .. R.SPECIAL_TIER .. ")")
            elseif mission.kind == "special" and Missions.cooldown_weeks(d, f) > 0 then
                text("dp_kf_mission", mission.name .. ": ready in " .. weeks(Missions.cooldown_weeks(d, f)))
            else
                text("dp_kf_mission", ((mission.kind == "unlock") and "Mission: " or "") .. mission.name .. " - "
                    .. mission.cost)
            end
            off = Missions.blocked(d, key, f) ~= nil
        end
        icon("dp_kf_mission", off and "dp_kf_btn_off.tga" or "dp_kf_btn.tga")
        grey("dp_kf_mission", off)
        local outcome
        if mission.kind == "unlock" then
            outcome = "Success makes the family tier 1: it will send you Hutt Upstarts."
        else
            outcome = "Success: " .. ((mission.reward and mission.reward.credits) and (mission.reward.credits
                .. " credits") or "its reward") .. "; then " .. weeks(mission.cooldown or 0) .. " before the next."
        end
        local how
        if mission.kind == "unlock" and R.PLACEHOLDER_WIN and Missions.placeholder(mission) then
            how = " " .. mission.cost .. " credits. (No mission to play yet: it succeeds at once.)"
        else
            how = " " .. mission.cost .. " credits, " .. weeks(mission.weeks) .. ", " .. mission.chance .. "% to succeed."
        end
        tip("dp_kf_mission", mission.name .. ": " .. mission.desc .. how .. " " .. outcome)
    elseif def then
        local at = Window.point and POINTS[Window.point]
        local point = at and at.tier == sel and def.points[at.index]
        text("dp_kf_mission", point and (point.name .. ": " .. point.short)
            or ("Tier " .. sel .. ", " .. def.name .. ": lasting bonuses"))
        icon("dp_kf_mission", "dp_kf_btn_off.tga")
        grey("dp_kf_mission", sel > tier)
        tip("dp_kf_mission", "A lasting bonus once the family reaches tier " .. sel .. ": nothing to start.")
    end

    local blocked = U.recruit_blocked(d, f)
    local fam_state = U.family(d, f)
    if not fam_state.unlocked then
        text("dp_kf_recruit", "Recruit Hutt Upstart (tier 1)")
    elseif GetCurrentTime() < (fam_state.upstart_at or 0) then
        text("dp_kf_recruit", "Next Upstart in " .. weeks(M.ceil((fam_state.upstart_at - GetCurrentTime())
            / CONFIG.WEEK_SECONDS)))
    else
        text("dp_kf_recruit", "Recruit Hutt Upstart - " .. R.UPSTART_COST)
    end
    icon("dp_kf_recruit", blocked and "dp_kf_btn_off.tga" or "dp_kf_btn.tga")
    grey("dp_kf_recruit", blocked ~= nil)
    tip("dp_kf_recruit", "A " .. fam.name .. " Upstart appears on one of the family's worlds (or the capital). Send it "
        .. "to another faction's populated world to start an underworld there (+" .. R.INFLUENCE_FOUNDER
        .. " influence for the family). The wait between Upstarts follows the family's power: now "
        .. weeks(M.ceil(U.upstart_weeks(d, f, power))) .. "." .. (blocked and (" " .. blocked) or ""))
end

local function status_of(d, w)
    local U = underworld()
    if w.state == "founding" then
        return "Forming " .. ((U and w.rec) and U.forming(w.rec) or 0) .. "%"
    elseif w.state == "contested" then
        return "Level " .. ((U and w.rec) and U.level(w.rec) or 0) .. ", " .. M.floor((w.share or 0) + 0.5) .. "%"
    elseif w.state == "controlled" then
        return "Controlled"
    elseif w.state == "shared" then
        return "Capital"
    elseif w.state == "network" then
        return "Network level " .. w.level
    end
    return "Hutt world"
end

local function render(d)
    local worlds = K.worlds(d)
    local counts, networks, held = {}, 0, 0
    for i = 1, LAYOUT.families do
        counts[i] = 0
    end
    for _, w in ipairs(worlds) do
        counts[w.family] = counts[w.family] + 1
        if w.held then
            held = held + 1
        else
            networks = networks + 1
        end
    end
    local total = table.getn(worlds)
    if Window.tab == "family" and not Window.selected then
        Window.tab = "space"
    end
    local family_tab = Window.tab == "family"
    show("dp_kaj_worlds_shell", not family_tab)
    show("dp_kaj_fam_shell", family_tab)

    text("dp_k_title", "The Kajidii of Hutt Space")
    local income = 0
    local ok, value = pcall(GlobalValue.Get, "HUTT_SMUGGLING_INCOME")
    if ok and type(value) == "number" then
        income = value
    end
    local U = underworld()
    local boss, boss_hero = nil, nil
    if U then
        boss, boss_hero = U.leader_family(d)
    end
    text("dp_k_summary", "Hutt worlds: " .. held .. "     Underworlds: " .. networks .. "     Smuggling income: "
        .. M.floor(income) .. " credits a week     Boss Family: " .. (boss and K.FAMILIES[boss].name or "none (the council rules)"))

    text("dp_k_tab_family", Window.selected and K.FAMILIES[Window.selected].name or "Family")
    text("dp_k_tab_space", "Hutt Space (" .. held .. ")")
    text("dp_k_tab_network", "Underworlds (" .. networks .. ")")
    icon("dp_k_tab_family", family_tab and "dp_k_tab_sel.tga" or (Window.selected and "dp_k_tab.tga" or "dp_k_tab_off.tga"))
    grey("dp_k_tab_family", not Window.selected)
    icon("dp_k_tab_space", (Window.tab == "space") and "dp_k_tab_sel.tga" or "dp_k_tab.tga")
    icon("dp_k_tab_network", (Window.tab == "network") and "dp_k_tab_sel.tga" or "dp_k_tab.tga")
    tip("dp_k_tab_family", Window.selected and ("The " .. K.FAMILIES[Window.selected].name
        .. " kajidic: its standing, tiers, mission and Upstarts.") or "Select a family below first.")
    tip("dp_k_tab_space", "Your own worlds, each held by a family; the capital is shared by all.")
    tip("dp_k_tab_network", "The underworlds your families have started on other factions' worlds.")

    if family_tab then
        render_family(d, Window.selected)
    else
        local shown = {}
        for _, w in ipairs(worlds) do
            if (w.held == (Window.tab == "space")) and (not Window.selected or w.family == Window.selected) then
                table.insert(shown, w)
            end
        end
        local pages = M.max(1, M.floor((table.getn(shown) + LAYOUT.chips - 1) / LAYOUT.chips))
        if Window.page > pages then
            Window.page = 1
        end
        Window.chips = {}
        for k = 1, LAYOUT.chips do
            local w = shown[(Window.page - 1) * LAYOUT.chips + k]
            local c = "dp_k_w" .. k
            for _, part in ipairs({"", "_globe", "_name", "_level", "_crest"}) do
                show(c .. part, w ~= nil)
            end
            Window.chips[k] = w
            if w then
                local name = d:planet_name(w.planet)
                local status = status_of(d, w)
                icon(c .. "_globe", GLOBES[w.type] or "dp_globe_unknown.tga")
                text(c .. "_name", name)
                text(c .. "_level", status)
                icon(c .. "_crest", "dp_kcrest_" .. w.family .. ".tga")
                local line = name .. ": " .. string.lower(status)
                if w.state == "shared" then
                    line = line .. " - every family has a stake here."
                elseif w.state == "founding" or w.state == "contested" then
                    line = line .. ", led by " .. family_name(w.family) .. "."
                else
                    line = line .. ", held by " .. family_name(w.family) .. "."
                end
                tip(c, line .. " Click to select the family.")
            end
        end
        show("dp_k_prev", pages > 1)
        show("dp_k_next", pages > 1)
        text("dp_k_prev", "Previous")
        text("dp_k_next", "Next (" .. Window.page .. "/" .. pages .. ")")
    end

    if Window.selected and Window.tier then
        local n = Window.tier
        local U = underworld()
        local tier = (U and d.underworld) and U.tier(d, Window.selected) or 0
        local status = (n <= tier) and "reached" or ((n == tier + 1) and "next to reach" or "locked")
        local point = Window.point and POINTS[Window.point] and R.TIERS[n].points[POINTS[Window.point].index]
        local gives = {}
        for _, p in ipairs(point and {point} or R.TIERS[n].points) do
            table.insert(gives, p.unlock)
        end
        text("dp_k_info", "The " .. K.FAMILIES[Window.selected].name .. ", tier " .. n .. ": "
            .. (point and point.name or R.TIERS[n].name) .. " (" .. status .. ")")
        text("dp_k_info2", table.concat(gives, " "))
        local need = " "
        if U and d.underworld then
            need = (n == 1) and "Needs the family's mission (the button above)."
                or ("Needs " .. U.tier_worlds(d, n) .. ((U.tier_worlds(d, n) == 1) and " controlled world" or " controlled worlds")
                .. ": the family has " .. U.controlled(d, Window.selected) .. ".")
        end
        text("dp_k_info3", Window.feedback or need)
    elseif Window.selected then
        local f = K.FAMILIES[Window.selected]
        text("dp_k_info", "The " .. f.name .. " kajidic - " .. f.spec[2])
        text("dp_k_info2", f.desc[1])
        text("dp_k_info3", Window.feedback or f.desc[2])
    else
        text("dp_k_info", "Five great kajidii divide the Hutt underworld between them.")
        text("dp_k_info2", "Each holds Hutt worlds and fights for the underworlds its Upstarts start on other factions' worlds.")
        text("dp_k_info3", Window.feedback or "Select a family to see its tiers, its mission and its Upstarts.")
    end

    for i = 1, LAYOUT.families do
        local f = K.FAMILIES[i]
        local c = "dp_k_c" .. i
        local selected = Window.selected == i
        icon(c, "dp_kcol_" .. i .. (selected and "_sel" or "") .. ".tga")
        text(c .. "_name", f.name)
        text(c .. "_spec1", f.spec[1])
        text(c .. "_spec2", f.spec[2])
        local share = (total > 0) and M.round(100 * counts[i] / total) or 0
        text(c .. "_worlds", counts[i] .. ((counts[i] == 1) and " world" or " worlds") .. " (" .. share .. "%)")
        text(c .. "_btn", selected and "Selected" or "Select")
        local line = "The " .. f.name .. " kajidic: " .. string.lower(f.spec[1]) .. ". Holds or leads " .. counts[i]
            .. " of your " .. total .. " worlds."
        if boss == i then
            line = line .. " The Boss Family: " .. (boss_hero and d.unit_name(boss_hero) or "the faction leader")
                .. " is one of theirs. " .. ((R.LEADER_PERKS[f.key] and R.LEADER_PERKS[f.key].desc) or "")
        end
        for _, part in ipairs({"", "_name", "_spec1", "_spec2", "_worlds", "_btn"}) do
            tip(c .. part, line)
        end
        show(c .. "_boss", boss == i)
        tip(c .. "_boss", line)
        local tree = selected and U ~= nil and d.underworld ~= nil
        show(tree_shell(i), tree)
        show(c, not tree)
        show(c .. "_name", not tree)
        show(c .. "_spec1", not tree)
        show(c .. "_worlds", not tree)
        local tier = tree and U.tier(d, i) or 0
        local sel = tree and Window.tier_of(d, i) or nil
        for k, at in ipairs(POINTS) do
            if tree then
                local n = at.tier
                local point = R.TIERS[n].points[at.index]
                local state = (n <= tier) and "done" or ((n == tier + 1) and "next" or "lock")
                local chosen = (Window.point == k) or (not Window.point and n == sel and at.index == 1)
                icon(c .. "_p" .. k, "dp_kt_" .. state .. "_" .. n .. (chosen and "_sel" or "") .. ".tga")
                tip(c .. "_p" .. k, Window.tier_tip(d, i, n, point) .. " Click for details.")
            end
        end
        if tree then
            text(c .. "_tname", f.name)
            tip(c .. "_tname", line)
            local at = Window.point and POINTS[Window.point]
            if at then
                text(c .. "_spec2", NUMERALS[at.tier] .. ". " .. R.TIERS[at.tier].points[at.index].name)
            else
                text(c .. "_spec2", (tier > 0) and ("Tier " .. tier .. " of " .. LAYOUT.tiers .. ", "
                    .. R.TIERS[tier].name) or "Tier 0 - not yet made")
            end
        end
    end
end

function Window.open(d)
    Window.d = d
    Window.open_now = true
    Window.page = 1
    Window.feedback = nil
    for _, shell in ipairs(SHELLS) do
        show(shell, true)
    end
    render(d)
    Pause.hold("kajidii")
    if Engine_Screen_Text then
        Engine_Screen_Text(0)
    end
end

function Window.close()
    for _, shell in ipairs(SHELLS) do
        show(shell, false)
    end
    for i = 1, LAYOUT.families do
        show(tree_shell(i), false)
    end
    show("dp_kaj_worlds_shell", false)
    show("dp_kaj_fam_shell", false)
    if Window.open_now then
        Window.selected, Window.tab, Window.tier, Window.page, Window.point = nil, "space", nil, 1, nil
        Pause.release("kajidii")
        if Engine_Screen_Text then
            Engine_Screen_Text(1)
        end
    end
    Window.open_now = false
end

function Window.click(d, name, button)
    if Engine_Log then
        Engine_Log("KAJIDII WINDOW " .. tostring(button) .. " click " .. tostring(name))
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
    if name == "dp_k_close" then
        Window.close()
        return
    end
    if not Window.open_now then
        return
    end
    Window.feedback = nil
    local _, _, family = string.find(name, "^dp_k_c(%d+)")
    local _, _, node = string.find(name, "^dp_k_c%d+_p(%d+)$")
    local _, _, chip = string.find(name, "^dp_k_w(%d+)$")
    if family and node and tonumber(family) == Window.selected then
        node = tonumber(node)
        if Window.point == node then
            Window.point, Window.tier = nil, nil
        else
            Window.point, Window.tier = node, POINTS[node].tier
        end
        Window.tab = "family"
    elseif family then
        family = tonumber(family)
        if Window.selected ~= family then
            Window.selected, Window.tab = family, "family"
        else
            Window.selected = nil
        end
        Window.tier, Window.point = nil, nil
        Window.page = 1
    elseif chip then
        local w = Window.chips and Window.chips[tonumber(chip)]
        if w then
            Window.selected, Window.tab, Window.tier, Window.point = w.family, "family", nil, nil
        end
    elseif name == "dp_k_tab_family" then
        if Window.selected then
            Window.tab = "family"
        else
            Window.feedback = "Select a family below first."
        end
    elseif name == "dp_k_tab_space" or name == "dp_k_tab_network" then
        Window.tab = (name == "dp_k_tab_space") and "space" or "network"
        Window.page, Window.tier, Window.point = 1, nil, nil
    elseif name == "dp_k_next" then
        Window.page = Window.page + 1
    elseif name == "dp_k_prev" then
        Window.page = M.max(1, Window.page - 1)
    elseif string.find(name, "^dp_kf_t%d$") and Window.selected then
        local n = tonumber(string.sub(name, 8, 8))
        Window.tier = (Window.tier ~= n) and n or nil
        Window.point = nil
    elseif name == "dp_kf_mission" and Window.selected then
        local _, Missions = underworld()
        local f = Window.selected
        local n = Window.tier_of(d, f)
        local key = Missions and ((n == 1) and Missions.family_mission(f)
            or (R.TIERS[n] and tier_special(n) and Missions.special_mission(f))) or nil
        if key then
            local _, message = Missions.start(d, key, f)
            Window.feedback = message
        end
    elseif name == "dp_kf_recruit" and Window.selected then
        local U = underworld()
        if U then
            local _, message = U.recruit(d, Window.selected)
            Window.feedback = message
        end
    end
    render(d)
end

return Window
