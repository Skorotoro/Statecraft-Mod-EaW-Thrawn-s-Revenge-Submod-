local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Pause = require("eawx-plugins/diplomacy/DiplomacyPause")
local GLOBES = require("eawx-plugins/diplomacy/DiplomacyGlobes")
local LAYOUT = require("eawx-plugins/new-republic/RepublicWindowLayout")
local Republic = require("eawx-plugins/new-republic/Republic")
local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")
local IW = require("eawx-plugins/new-republic/RepublicIntelWindow")
local ok_jw, JW = pcall(require, "eawx-plugins/jedi-order/JediWindow")
JW = ok_jw and JW or nil

local function optional(name)
    local ok, mod = pcall(require, name)
    return ok and mod or nil
end
local LEADERS = optional("eawx-plugins/diplomacy/DiplomacyLeaders") or {}

local Window = {open_now = false, tab = "members", sel = {}, scroll = 0, page = 1, wscroll = 0, view = "members",
                op_filter = 1, bloc_filter = 1, petition = 1}
local SHELLS = {"dp_nr_shell", "dp_nr_coll_shell", "dp_nr_colr_shell", "dp_nr_list_shell", "dp_nr_bars_shell",
                "dp_nr_detail_shell", "dp_nr_gov_shell", "dp_nr_vote_shell", "dp_nr_jedi_shell", "dp_nr_mdet_shell", "dp_nr_jh_shell",
                "dp_nr_law_shell"}
local LAW_SHELL = "dp_nr_law_shell"
for _, shell in ipairs(LAYOUT.jt_shells) do
    table.insert(SHELLS, shell)
end
local BODY = {members = {"dp_nr_coll_shell", "dp_nr_mdet_shell"}, taxes = {"dp_nr_coll_shell", "dp_nr_colr_shell"},
              government = {"dp_nr_gov_shell", "dp_nr_vote_shell"},
              intelligence = {"dp_nr_list_shell", "dp_nr_bars_shell", "dp_nr_detail_shell"},
              jedi = {"dp_nr_jedi_shell", "dp_nr_jh_shell"}}
for _, shell in ipairs(LAYOUT.jt_shells) do
    table.insert(BODY.jedi, shell)
end
local TAB_NAMES = {chamber = "Chamber", members = "Members", taxes = "Sectors", government = "Government",
                   intelligence = "Intelligence", jedi = "The Jedi Order"}
local TAB_TIPS = {
    chamber = "Back to the Senate chamber: the motions, the seats and the blocs.",
    members = "The Republic's worlds: members, territories and occupied worlds, associates and protectorates.",
    taxes = "The Republic's sectors and their taxes. Every change of taxes is a Senate vote.",
    government = "The Chancellor, the cabinet and the coming election.",
    intelligence = "New Republic Intelligence: spy networks, agents and covert operations.",
    jedi = "The Jedi Order: its roster, missions, teachings and Council.",
}
local VIEWS = {
    {key = "members", label = "Members", tip = "Founding members and member worlds: their senators, blocs and opinion."},
    {key = "territories", label = "Territories", tip = "Occupied worlds, worlds without a Senator's Office, and bases and stations."},
    {key = "associates", label = "Associates", tip = "Associate worlds: they pay their share and send ships; one day they may ask for a seat."},
    {key = "protectorates", label = "Protectorates", tip = "Powers and worlds under the Republic's protection, and the calls to defend them."},
}
local OPINION_FILTERS = {
    {label = "Any opinion", test = function() return true end},
    {label = "Loyal (40+)", test = function(v) return v >= 40 end},
    {label = "Content (0+)", test = function(v) return v >= 0 end},
    {label = "Discontent", test = function(v) return v < 0 end},
    {label = "Hostile (-40)", test = function(v) return v <= -40 end},
}
local GOLD_C, PALE_C, GREY_C = {0.92, 0.82, 0.59}, {0.84, 0.86, 0.9}, {0.45, 0.45, 0.48}
local COHESION_THRESHOLDS = {
    {80, "Threshold 80: above it, the Core Moderates, the Liberation Front and the Republic Loyalists gain clout on their worlds."},
    {40, "Threshold 40: below it, undecided senators vote against the government."},
    {25, "Threshold 25: below it, the chamber may move a vote of no confidence."},
}
local PULSE = {0, 1, 2, 3, 4, 3, 2, 1}
local TAX_COLORS = {{0.35, 1, 0.4}, {0.2, 0.62, 0.28}, nil, {0.72, 0.22, 0.18}, {1, 0.28, 0.22}}
local FACTION = "REBEL"

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("REPUBLIC WINDOW gui error: " .. tostring(err))
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

local ROOM = LAYOUT.room or {}
local EM = 12.8
local NARROW = {["i"] = 0.24, ["l"] = 0.24, ["I"] = 0.3, ["j"] = 0.24, ["."] = 0.29, [","] = 0.29, [":"] = 0.29,
                [";"] = 0.29, ["'"] = 0.2, ["!"] = 0.29, ["|"] = 0.26, [" "] = 0.29, ["f"] = 0.3, ["t"] = 0.3,
                ["r"] = 0.35, ["("] = 0.35, [")"] = 0.35, ["-"] = 0.35}
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

local fitted = {}
local function fit(name, value)
    local room = ROOM[name]
    if not room then
        return value
    end
    local known = fitted[name]
    if known and known[1] == value then
        return known[2]
    end
    local result = value
    local limit = room[1] - 4
    if text_width(value, room[2]) > limit then
        local dots = text_width("...", room[2])
        local cut = value
        while string.len(cut) > 1 and text_width(cut, room[2]) + dots > limit do
            cut = string.sub(cut, 1, string.len(cut) - 1)
        end
        result = string.gsub(cut, "[%s,;:%-]+$", "") .. "..."
    end
    fitted[name] = {value, result}
    return result
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

local function icon(name, texture)
    if cache.icon[name] == texture then
        return
    end
    cache.icon[name] = texture
    call(GUI_Button_Icon, name, texture, 1, 1, 1, 1)
end

local function color(name, c)
    local key = c[1] .. "," .. c[2] .. "," .. c[3]
    if cache.color[name] == key then
        return
    end
    cache.color[name] = key
    call(GUI_Text_Color, name, c[1], c[2], c[3], 1)
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

local function part(name)
    return Republic.part(name)
end

local function globe(key)
    return GLOBES[key] or "dp_globe_unknown.tga"
end

local function faction_icon(faction)
    if not DIPLOMACY_EMBLEM then
        pcall(require, "eawx-plugins/diplomacy/DiplomacyWindow")
    end
    local world = type(faction) == "string" and string.sub(faction, 1, 1) == "@" and string.sub(faction, 2)
    if world then
        return globe(world)
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
    return "dp_emblem_rebel.tga"
end

local faction_colors
local function owner_color(owner)
    if faction_colors == nil then
        local ok, constants = pcall(function() return ModContentLoader.get("GameConstants") end)
        faction_colors = ok and constants and constants.FACTION_COLORS or false
    end
    local c = owner and faction_colors and faction_colors[owner]
    if not c then
        return {0.62, 0.62, 0.66}
    end
    local r, g, b = c.r / 255, c.g / 255, c.b / 255
    local mix = 0.25 + M.max(0, 0.75 - M.max(r, M.max(g, b)))
    return {r + (1 - r) * mix, g + (1 - g) * mix, b + (1 - b) * mix}
end

local function opinion_color(v)
    if v >= 40 then
        return {0.55, 0.85, 0.6}
    elseif v >= 0 then
        return {0.92, 0.82, 0.45}
    end
    return {0.95, 0.45, 0.4}
end

local function sector_rule(L)
    return "How sector laws pass: a sector holds a vote now and then (" .. L.VOTE_CHANCE .. "% a week), on a law its "
        .. "seats back or on repealing one of its own that fewer than " .. L.REPEAL_SHARE .. "% of them still back. The "
        .. "vote runs " .. L.VOTE_WEEKS[1] .. "-" .. L.VOTE_WEEKS[2] .. " weeks and passes as often as the share of seats "
        .. "backing it (a seat backs what its ruling party's bloc backs). At most " .. L.SECTOR_MAX .. " in force. You may "
        .. "veto a running vote (its worlds' opinion " .. L.VETO_OPINION .. ") or force a repeal by Senate motion. A law "
        .. "works on the sector's own member worlds unless it says otherwise."
end

local function planet_rule(L)
    return "How planetary laws pass: now and then (" .. L.EVENT_CHANCE .. "% a week) the world's strongest party "
        .. "passes a law it backs (at most " .. L.PLANET_MAX .. " in force) or repeals one it opposes that has stood "
        .. L.MIN_WEEKS .. " weeks. No Senate vote, no veto. What can pass depends on the world's government, its "
        .. "situation and its parties: lobby a party to change who is strongest. A law works on this world only "
        .. "unless it says otherwise."
end

local function signed(n)
    n = M.round(n or 0)
    return ((n > 0) and "+" or "") .. n
end

local function weeks(n)
    n = M.max(0, M.round(n))
    return n .. ((n == 1) and " week" or " weeks")
end

local function person(key)
    local entry = LEADERS.CHIEFS and LEADERS.CHIEFS[key]
    if entry then
        return entry
    end
    for _, c in ipairs(R.COUNCIL.COUNCILLORS) do
        if c.candidate == key then
            return {name = c.name, icon = c.portrait}
        end
    end
    local cand = R.CANDIDATES[key]
    return cand and {name = cand.name, icon = "dp_emblem_rebel.tga"} or nil
end

local function chief_entry()
    local key = string.upper(tostring(GlobalValue.Get("ChiefOfState") or "DUMMY_CHIEFOFSTATE_MOTHMA"))
    return key, person(key)
end

local function empty_detail(name, line)
    return {name = name, sub = line, sub2 = " ", kind = " ", stats = {}, head = " ", lines = {}, actions = {}}
end

local function intel_helpers(d)
    local Intel = require("eawx-plugins/new-republic/RepublicIntel")
    return {label = function(target) return Intel.label(d, target) end, faction_icon = faction_icon,
            owner_color = function(target) return owner_color(Intel.owner(target)) end, empty_detail = empty_detail,
            globe = globe,
            hero_icon = function(a)
                local entry = LEADERS.HEROES
                for _, lore in ipairs(R.AGENTS.LORE) do
                    if lore.name == a.lore and entry then
                        for _, t in ipairs(lore.units) do
                            if entry[t] then
                                return entry[t].icon
                            end
                        end
                    end
                end
                return nil
            end}
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

local function jedi_state(d)
    return require("eawx-plugins/jedi-order/JediOrder").state(d)
end

Window.deferred = {}
local function defer(fn)
    table.insert(Window.deferred, fn)
end

local function council(d)
    local Council = part("council")
    return Council ~= nil and Council.active(d)
end

local jedi_map
local function tab_closed(d, tab)
    if tab ~= "intelligence" and tab ~= "chamber" and council(d) then
        return "Republic Affairs opens when the New Republic is founded. Until then the Council rules, and only "
            .. "Intelligence answers to it."
    end
    if tab == "jedi" then
        if not jedi_map() then
            return "The Jedi Order: no Yavin in this galaxy, no temple to found it in."
        end
        local Council = part("council")
        if Council and not Council.jedi_open(d) then
            return "The Jedi Order: Luke Skywalker waits for a sign that the time has come."
        end
    end
    return nil
end

local jedi_yavin = nil
function jedi_map()
    if jedi_yavin == nil then
        local ok, planet = pcall(FindPlanet, "YAVIN")
        jedi_yavin = ok and planet ~= nil
    end
    return jedi_yavin
end

local function render_header(d)
    local seats = Republic.senate and Republic.senate.seats(d) or {}
    local n = U.count(seats)
    local solo = council(d)
    text("dp_nr_title", solo and "Alliance Intelligence" or "The New Republic")
    tip("dp_nr_title", solo and "Alliance Intelligence: spy networks, agents and operations, and the worlds' sympathy."
        or "The New Republic: its worlds, its government and its intelligence service.")
    for _, p in ipairs({"dp_nr_chief", "dp_nr_chief_plate", "dp_nr_chief_rank", "dp_nr_chief_name",
                        "dp_nr_stat_worlds", "dp_nr_stat_treasury"}) do
        show(p, not solo)
    end
    for _, tab in ipairs(LAYOUT.tabs) do
        show("dp_nr_tab_" .. tab, not solo or tab == "chamber")
    end
    local key, chief = chief_entry()
    local cand = R.CANDIDATES[key]
    icon("dp_nr_chief", chief and chief.icon or "dp_emblem_rebel.tga")
    icon("dp_nr_chief_plate", "dp_nr_plate.tga")
    text("dp_nr_chief_rank", "Chancellor")
    text("dp_nr_chief_name", chief and chief.name or (cand and cand.name) or "Chancellor")
    local gov = part("gov")
    local agenda = gov and gov.agenda(d)
    local chief_tip = "Chancellor " .. (chief and chief.name or "?") .. "." .. (cand and (" " .. (agenda and "Agenda: "
        or "Agenda suspended after a vote of no confidence: ") .. cand.text) or "") .. " Click for the Government."
    for _, p in ipairs({"dp_nr_chief", "dp_nr_chief_plate", "dp_nr_chief_rank", "dp_nr_chief_name"}) do
        tip(p, chief_tip)
    end
    local income = Republic.capital_income(d, n)
    local coins = {
        mandate = {tostring(Republic.mandate(d)), "Mandate " .. Republic.mandate(d) .. " of 100: how far the galaxy sees "
            .. "the Alliance as a government rather than rebels. Below 100 every deal is harder to make; below 75 "
            .. "sympathy falls everywhere. It never drifts: liberations, alliances and the Councillors' missions raise "
            .. "it; invasions, revolts and losses lower it."},
        capital = {tostring(Republic.capital(d)), "Political capital " .. Republic.capital(d) .. ", +" .. M.round(income)
            .. " a week" .. (council(d) and " (and more for every Councillor's mission done). Every motion before "
            .. "the Council costs some; it also pays for lobbying and recruiting agents." or " (less as the Senate "
            .. "grows). It pays for lobbying, appeals, backing a candidate, appointing ministers and recruiting agents.")},
    }
    if not council(d) then
        coins.mandate[2] = "Mandate " .. Republic.mandate(d) .. " of 100: the Senate's trust in your government. The "
            .. "higher it is, the more a senator's good opinion of you sways their vote. Granted bloc requests and "
            .. "integration missions raise it; ignored requests, failed missions and emergency decrees lower it."
    end
    show("dp_nr_coin_mandate", true)
    show("dp_nr_coin_mandate_n", true)
    for _, k in ipairs(LAYOUT.coins) do
        text("dp_nr_coin_" .. k .. "_n", coins[k][1])
        tip("dp_nr_coin_" .. k, coins[k][2])
        tip("dp_nr_coin_" .. k .. "_n", coins[k][2])
    end
    local value = (d.senate and d.senate.stability) or 0
    local target = solo and value or Republic.cohesion_target(d, n)
    local step = (target > value) and R.COHESION_RECOVERY or ((target < value) and -R.COHESION_DECAY or 0)
    local speed = (step == 0) and 0 or ((M.abs(step) < 2) and 1 or ((M.abs(step) < 4) and 2 or 3))
    local word = (value >= 60) and "steady" or ((value >= 30) and "uneasy" or "fractured")
    text("dp_nr_coh_label", (solo and "Alliance Cohesion: " or "Senate Cohesion: ") .. value .. " (" .. word .. ")")
    local filled = M.max(0, M.min(LAYOUT.coh_pips, M.round(value / 5)))
    local mark = M.max(1, M.min(LAYOUT.coh_pips, M.round(target / 5)))
    local hue = (value < 30) and "red" or ((value < 60) and "amber" or "blue")
    local limits = {}
    for _, t in ipairs(COHESION_THRESHOLDS) do
        limits[M.round(t[1] / 5)] = t
    end
    for k = 1, LAYOUT.coh_pips do
        local base = "dp_nr_dpip_" .. ((k <= filled) and hue or "empty")
        if k ~= filled or not Window.pulse then
            icon("dp_nr_coh_" .. k, base .. (limits[k] and "_t" or "") .. ".tga")
        end
        show("dp_nr_coh_m" .. k, k == mark)
    end
    Window.coh_pulse = (filled > 0) and {name = "dp_nr_coh_" .. filled, base = "dp_nr_dpip_" .. hue,
                                         rim = limits[filled] ~= nil} or nil
    for k = 1, LAYOUT.trend do
        show("dp_nr_coh_up" .. k, step > 0 and k <= speed)
        show("dp_nr_coh_dn" .. k, step < 0 and k <= speed)
    end
    local weariness = Republic.weariness(d)
    local gov = part("gov")
    local vacant = (not solo and gov and gov.vacancies) and gov.vacancies(d) or 0
    local coh_tip = solo and ("Alliance cohesion " .. value .. " (" .. word .. "): the average sympathy of the worlds "
        .. "you hold, Hostile ones counting double. Very low, the least content world may rise against the Alliance.")
        or "Senate cohesion " .. value .. " (" .. word .. "), " .. ((step == 0) and "holding steady" or
        ((step > 0 and "rising " or "falling ") .. M.abs(step) .. " a week")) .. ", settling towards " .. target
        .. " (the light mark): lower as the Republic grows" .. ((weariness > 0) and (", and " .. weariness .. " less for its wars")
        or "") .. ((vacant > 0) and (", " .. vacant * (R.VACANT_MINISTER_COHESION or 0) .. " less for "
        .. vacant .. " empty cabinet post" .. ((vacant > 1) and "s" or "")) or "")
        .. ". " .. Republic.cohesion_breakdown(d, n) .. " Low cohesion: votes go against you, worlds talk of "
        .. "secession, no-confidence motions."
    for _, p in ipairs({"dp_nr_coh_label", "dp_nr_coh_frame"}) do
        tip(p, coh_tip)
    end
    for k = 1, LAYOUT.coh_pips do
        tip("dp_nr_coh_" .. k, limits[k] and (limits[k][2] .. " " .. coh_tip) or coh_tip)
        tip("dp_nr_coh_m" .. k, coh_tip)
    end
    for k = 1, LAYOUT.trend do
        tip("dp_nr_coh_up" .. k, coh_tip)
        tip("dp_nr_coh_dn" .. k, coh_tip)
    end
    local bar = (LAYOUT.cbar_pips or 0) > 0
    show("dp_nr_coh_frame", not bar)
    for k = 1, LAYOUT.coh_pips do
        show("dp_nr_coh_" .. k, not bar)
        if bar then
            show("dp_nr_coh_m" .. k, false)
        end
    end
    if bar and solo then
        for k = 1, LAYOUT.trend do
            show("dp_nr_coh_up" .. k, false)
            show("dp_nr_coh_dn" .. k, false)
        end
    end
    show("dp_nr_cbar_frame", bar)
    local marks = {}
    for _, level in ipairs((R.COHESION_MARKS or {})[solo and "COUNCIL" or "SENATE"] or {}) do
        marks[M.max(1, M.round(level / 5))] = level
    end
    for k = 1, LAYOUT.cbar_pips or 0 do
        show("dp_nr_cbar_" .. k, bar)
        show("dp_nr_cbar_t" .. k, bar and marks[k] ~= nil)
        if bar and marks[k] then
            tip("dp_nr_cbar_t" .. k, "Threshold " .. marks[k] .. ". " .. coh_tip)
        end
        if bar and not solo then
            show("dp_nr_coh_m" .. k, k == mark)
        end
    end
    if bar then
        Window.coh_pulse = nil
        local seg = (value < 30) and "dp_cm_seg_red.tga" or ((value < 60) and "dp_cm_seg_amber.tga" or "dp_cm_seg_green.tga")
        local segs = M.max(0, M.min(LAYOUT.cbar_pips, M.round(value / 100 * LAYOUT.cbar_pips)))
        for k = 1, LAYOUT.cbar_pips do
            icon("dp_nr_cbar_" .. k, (k <= segs) and seg or "dp_cm_seg_empty.tga")
        end
        text("dp_nr_coh_label", "Cohesion: " .. value .. " (" .. word .. ")")
        tip("dp_nr_cbar_frame", coh_tip)
    end
    local occupied, territories = Republic.counts(d, Republic.seated_planets(d))
    local assoc, prot = 0, 0
    for _, w in pairs(d.vassal_worlds or {}) do
        if w.stage == "associate" then
            assoc = assoc + 1
        elseif w.stage == "protectorate" then
            prot = prot + 1
        end
    end
    for _, relation in pairs(d.relations or {}) do
        if relation == "PROTECTORATE" then
            prot = prot + 1
        end
    end
    text("dp_nr_stat_worlds", n .. " seats, " .. (assoc + prot) .. " partners")
    tip("dp_nr_stat_worlds", n .. " member worlds with a seat; " .. occupied .. " occupied; " .. territories
        .. " territories; " .. assoc .. " associate worlds; " .. prot .. " protectorates. Click for the Members tab.")
    local take = (d.republic.tax and d.republic.tax.last) or 0
    text("dp_nr_stat_treasury", "Taxes " .. signed(take) .. " a week")
    tip("dp_nr_stat_treasury", "Sector taxes changed the treasury by " .. signed(take) .. " credits last week (above or "
        .. "below the normal rate). Click for the Sectors tab.")
    for _, tab in ipairs(LAYOUT.tabs) do
        local name = "dp_nr_tab_" .. tab
        local label = (solo and tab == "chamber") and "Council" or TAB_NAMES[tab]
        if tab == "government" and part("events") and part("events").active(d) then
            label = label .. " (!)"
        end
        text(name, label)
        local closed = tab_closed(d, tab)
        icon(name, closed and "dp_nr_tab_off.tga" or ((Window.tab == tab) and "dp_nr_tab_sel.tga" or "dp_nr_tab.tga"))
        color(name, closed and GREY_C or GOLD_C)
        tip(name, (solo and tab == "chamber") and "Back to the Council chamber." or closed or TAB_TIPS[tab])
    end
    tip("dp_nr_close", solo and "Close: back to the Council chamber." or "Close (the galaxy resumes).")
end

local function petitions(d)
    local out = {}
    local Events = part("events")
    local crisis = Events and Events.active(d)
    if crisis then
        local c = crisis.crisis
        local function short(choice)
            return (string.gsub(choice.text, "%s*%b()", ""))
        end
        table.insert(out, {text = "Crisis: " .. c.title .. " (" .. weeks(crisis.left) .. " to decide).",
                           text2 = c.text, warn = true,
                           a = {label = short(c.a), tip = c.a.text .. ". " .. Events.effects(c.a), key = {"crisis", "a"}},
                           b = {label = short(c.b), tip = c.b.text .. ". " .. Events.effects(c.b)
                               .. " Taken if you leave it.", key = {"crisis", "b"}}})
    end
    local Jedi = part("jedi")
    local jc = Jedi and Jedi.crisis(d)
    if jc then
        local c = jc.crisis
        local function short_j(choice)
            return choice.label
        end
        table.insert(out, {text = "The Jedi Order: " .. c.title .. " (" .. weeks(jc.left) .. " left)", text2 = c.text, warn = true,
                           a = {label = short_j(c.a), tip = c.a.text .. ". " .. Jedi.effects(c.a), key = {"jedi_crisis", "a"}},
                           b = {label = short_j(c.b), tip = c.b.text .. ". " .. Jedi.effects(c.b) .. " Taken if you leave it.",
                                key = {"jedi_crisis", "b"}}})
    end
    local P = part("prot")
    for _, call in ipairs(P and P.calls(d) or {}) do
        table.insert(out, {text = "Call to Action: defend " .. call.name .. " against " .. d.display_name(call.attacker) .. ".",
                           text2 = (call.left >= 0) and (weeks(call.left) .. " left: clear its worlds' orbits and retake what it lost.")
                               or ("Overdue by " .. weeks(-call.left) .. ": the chamber's patience wears thin, and it may leave."),
                           warn = call.left < 0,
                           a = (P.call_of(d, call.key) or {}).kind == "world" and {label = "Show",
                               tip = "Show " .. call.name .. " on the map.", key = {"map", call.key}} or nil})
    end
    for _, world in ipairs(P and P.petitions(d) or {}) do
        local planet = FindPlanet(world)
        local name = planet and d:planet_name(planet) or world
        table.insert(out, {text = name .. " petitions to become an associate world.",
                           text2 = "It has done its part. Put the petition to the chamber: associates pay their share and send ships.",
                           a = {label = "Put to vote", tip = "Put the petition to the chamber.", key = {"petition", world}}})
    end
    for world, w in pairs(d.vassal_worlds or {}) do
        if w.stage == "associate" and w.requests and FindPlanet(world) then
            local name = d:planet_name(FindPlanet(world))
            table.insert(out, {text = "The associate world " .. name .. " asks to join the Republic as a member.",
                               text2 = "Put its motion to the chamber: passed, it becomes a member with a Senator's Office.",
                               a = {label = "Put to vote", tip = "Put the motion to the chamber.", key = {"admit", world}}})
        end
    end
    local Laws = part("laws")
    if Laws and not council(d) then
        for _, v in ipairs(Laws.open_votes(d)) do
            local def = Laws.def(v.vote.law)
            local name = def and def.name or v.vote.law
            table.insert(out, {text = "The " .. v.sector .. " votes " .. (v.vote.repeal and "to repeal the " or "on the ")
                .. name .. ": " .. v.vote.share .. "% back it.", text2 = def and def.short or " ",
                a = {label = "Veto", tip = "Void the vote: the sector's worlds " .. Laws.CONFIG.VETO_OPINION
                    .. " opinion.", key = {"law_veto", v.sector}},
                b = {label = "Acknowledge", tip = "Let the vote run; its result will be reported here.",
                    key = {"law_ack", v.sector}}})
        end
        for _, n in ipairs(Laws.news(d)) do
            table.insert(out, {text = n.text, text2 = n.text2, news = true,
                a = {label = "Understood", tip = "Noted: clear it from the list.", key = {"law_news", n.id}},
                b = (n.kind ~= "galactic") and {label = (n.kind == "sector") and "View Sector" or "View World",
                    tip = "Its laws.", key = {"laws_open", (n.kind == "sector") and "sector" or "planet", n.ref}} or nil})
        end
    end
    local Parties = part("parties")
    for _, n in ipairs(Parties and not council(d) and Parties.news(d) or {}) do
        table.insert(out, {text = n.text, text2 = n.text2, news = true,
                           a = {label = "Understood", tip = "Noted: clear it from the list.", key = {"ack_news", n.id}},
                           b = {label = "View World", tip = "Its entry among the member worlds.", key = {"news_world", n.world}}})
    end
    return out
end

local function ordered(list)
    local first, middle, last = {}, {}, {}
    for _, p in ipairs(list) do
        local show_only = p.a and not p.b and p.a.key and p.a.key[1] == "map"
        if p.news then
            table.insert(last, p)
        elseif (p.a or p.b) and not show_only then
            table.insert(first, p)
        else
            table.insert(middle, p)
        end
    end
    for _, p in ipairs(middle) do
        table.insert(first, p)
    end
    for _, p in ipairs(last) do
        table.insert(first, p)
    end
    return first
end

local function render_footer(d)
    local list = ordered(petitions(d))
    local count = table.getn(list)
    if Window.petition > count then
        Window.petition = 1
    end
    local p = list[Window.petition]
    Window.footer = p
    show("dp_nr_pet_a", p ~= nil and p.a ~= nil)
    show("dp_nr_pet_b", p ~= nil and p.b ~= nil)
    show("dp_nr_pet_next", count > 1)
    local news = 0
    for _, item in ipairs(list) do
        if item.news then
            news = news + 1
        end
    end
    show("dp_nr_pet_clear", news > 1)
    if news > 1 then
        text("dp_nr_pet_clear", "Clear All Messages")
        tip("dp_nr_pet_clear", "Acknowledge all " .. news .. " messages that need no decision. Matters awaiting your "
            .. "decision stay.")
    end
    if p then
        text("dp_nr_pet_text", p.text)
        text("dp_nr_pet_text2", p.text2)
        color("dp_nr_pet_text", p.warn and {1, 0.55, 0.45} or GOLD_C)
        if p.a then
            text("dp_nr_pet_a", p.a.label)
            tip("dp_nr_pet_a", p.a.tip)
        end
        if p.b then
            text("dp_nr_pet_b", p.b.label)
            tip("dp_nr_pet_b", p.b.tip)
        end
        text("dp_nr_pet_next", Window.petition .. "/" .. count)
        tip("dp_nr_pet_next", "The next matter.")
    else
        text("dp_nr_pet_text", "Nothing waits for the government.")
        color("dp_nr_pet_text", GOLD_C)
        text("dp_nr_pet_text2", "Crises, calls to defend a protectorate and petitions appear here.")
    end
    local s = d.republic.intel
    local news = s and s.news and s.news[1]
    text("dp_nr_news", news or " ")
    tip("dp_nr_news", news and table.concat(s.news, "  |  ") or " ")
    local feedback = (Window.tab ~= "intelligence") and Window.feedback or nil
    show("dp_nr_feedback", feedback ~= nil)
    text("dp_nr_feedback", feedback or " ")
end

local function split(groups, flow)
    local left, right = {}, {}
    if flow == "single" then
        for _, g in ipairs(groups) do
            table.insert(left, {head = true, a = g.head, tip = g.tip, key = g.key, selected = g.selected, lvl = g.lvl,
                                lvl_color = g.lvl_color})
            for _, r in ipairs(g.rows) do
                table.insert(left, r)
            end
        end
        return left, right
    end
    if flow then
        local all = {}
        for _, g in ipairs(groups) do
            table.insert(all, {head = true, a = g.head, tip = g.tip, key = g.key})
            for _, r in ipairs(g.rows) do
                table.insert(all, r)
            end
        end
        local half = M.ceil(table.getn(all) / 2)
        if half < LAYOUT.col_rows then
            half = LAYOUT.col_rows
        end
        local last_head = nil
        for i, r in ipairs(all) do
            if r.head then
                last_head = r
            end
            if i <= half then
                table.insert(left, r)
            else
                if table.getn(right) == 0 and not r.head and last_head then
                    table.insert(right, {head = true, a = last_head.a .. " (continued)", tip = last_head.tip, key = last_head.key})
                end
                table.insert(right, r)
            end
        end
        if left[table.getn(left)] and left[table.getn(left)].head then
            table.insert(right, 1, table.remove(left))
        end
        return left, right
    end
    for _, g in ipairs(groups) do
        local col = (table.getn(left) <= table.getn(right)) and left or right
        table.insert(col, {head = true, a = g.head, tip = g.tip, key = g.key, selected = g.selected, lvl = g.lvl,
                           lvl_color = g.lvl_color})
        for _, r in ipairs(g.rows) do
            table.insert(col, r)
        end
    end
    return left, right
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

local function draw_col_thumb()
    draw_thumb((Window.tab == "taxes") and "dp_nr_rseg" or "dp_nr_cseg", LAYOUT.col_segs, LAYOUT.col_seg, Window.scroll or 0, Window.cmax or 0, Window.cthumb or 24,
        Window.cdragging and Window.cshare or nil)
end

local function render_columns(groups, flow, bar)
    local left, right = split(groups, flow)
    local per = LAYOUT.col_rows
    local total = M.max(table.getn(left), table.getn(right))
    Window.cmax = M.max(0, total - per)
    Window.scroll = M.min(M.max(0, Window.scroll or 0), Window.cmax)
    Window.crow = {}
    for side, list in pairs({l = left, r = right}) do
        for k = 1, per do
            local row = list[Window.scroll + k]
            local p = "dp_nr_" .. side .. k
            Window.crow[side .. k] = row
            local head = row ~= nil and row.head == true
            local sub = row ~= nil and row.sub == true
            show(p, row ~= nil and not head and not sub)
            show(p .. "_a", row ~= nil and not head)
            show(p .. "_b", row ~= nil and not head)
            show(p .. "_icon", row ~= nil and not head and row.icon ~= nil)
            show(p .. "_zoom", row ~= nil and not head and row.world ~= nil)
            show(p .. "_head", head)
            show(p .. "_hlvl", head and row.lvl ~= nil)
            show(p .. "_emb", row ~= nil and not head and row.emb ~= nil)
            show(p .. "_line", head)
            show(p .. "_hit", row ~= nil)
            if row then
                local t = row.tip or row.a
                if head then
                    text(p .. "_head", row.a)
                    color(p .. "_head", row.selected and {1, 0.95, 0.65} or {0.92, 0.8, 0.5})
                    if row.lvl then
                        text(p .. "_hlvl", row.lvl)
                        color(p .. "_hlvl", row.lvl_color or GOLD_C)
                        tip(p .. "_hlvl", t)
                    end
                else
                    if row.emb then
                        icon(p .. "_emb", row.emb)
                        tip(p .. "_emb", row.emb_tip or t)
                    end
                    if not sub then
                        icon(p, row.selected and "dp_nr_row_sel.tga" or "dp_nr_row.tga")
                    end
                    text(p .. "_a", row.a)
                    text(p .. "_b", row.b or " ")
                    color(p .. "_a", row.dim and GREY_C or (row.a_color or PALE_C))
                    color(p .. "_b", row.dim and GREY_C or (row.b_color or PALE_C))
                    if row.icon then
                        icon(p .. "_icon", row.icon)
                        tip(p .. "_icon", row.icon_tip or t)
                    end
                    if row.world then
                        tip(p .. "_zoom", "Show " .. (row.label or row.a) .. " on the map.")
                    end
                    tip(p .. "_b", t)
                end
                for _, s in ipairs({"", "_a", "_head", "_hit"}) do
                    tip(p .. s, t)
                end
            end
        end
    end
    local scrolling = Window.cmax > 0
    for _, bar in ipairs({"c", "r"}) do
        local mine = scrolling and ((bar == "r") == (Window.tab == "taxes"))
        show("dp_nr_" .. bar .. "_up", mine)
        show("dp_nr_" .. bar .. "_down", mine)
        for k = 1, LAYOUT.col_segs do
            show("dp_nr_" .. bar .. "seg" .. k, mine)
            tip("dp_nr_" .. bar .. "seg" .. k, "Drag, click or use the mouse wheel to scroll.")
        end
        tip("dp_nr_" .. bar .. "_up", "Scroll up.")
        tip("dp_nr_" .. bar .. "_down", "Scroll down.")
    end
    if scrolling then
        Window.cthumb = M.max(16, LAYOUT.col_segs * LAYOUT.col_seg * per / total)
        draw_col_thumb()
    end
    Window.toggles, Window.filters = bar.toggles or {}, bar.filters or {}
    for k = 1, LAYOUT.toggles do
        local t = Window.toggles[k]
        show("dp_nr_tg" .. k, t ~= nil)
        if t then
            text("dp_nr_tg" .. k, t.label)
            tip("dp_nr_tg" .. k, t.tip)
            icon("dp_nr_tg" .. k, t.on and "dp_nr_btn_t_on.tga" or "dp_nr_btn_t.tga")
        end
    end
    for k = 1, LAYOUT.filters do
        local f = Window.filters[k]
        show("dp_nr_ft" .. k, f ~= nil)
        if f then
            text("dp_nr_ft" .. k, f.label)
            tip("dp_nr_ft" .. k, f.tip)
        end
    end
    show("dp_nr_cols_info", bar.info ~= nil)
    text("dp_nr_cols_info", bar.info or " ")
    tip("dp_nr_cols_info", bar.info_tip or bar.info or " ")
    local ctx = bar.ctx or {}
    text("dp_nr_ctx_text", ctx.text or bar.hint or " ")
    tip("dp_nr_ctx_text", ctx.tip or ctx.text or bar.hint or " ")
    Window.ctx = ctx.buttons or {}
    for k = 1, LAYOUT.ctx do
        local b = Window.ctx[k]
        show("dp_nr_ctx" .. k, b ~= nil)
        if b then
            text("dp_nr_ctx" .. k, b.label)
            tip("dp_nr_ctx" .. k, b.tip or b.label)
            icon("dp_nr_ctx" .. k, b.off and "dp_nr_btn_a_off.tga" or "dp_nr_btn_a.tga")
            color("dp_nr_ctx" .. k, b.off and GREY_C or GOLD_C)
        end
    end
    local n = table.getn(Window.ctx)
    for k = 1, LAYOUT.ctx do
        show("dp_nr_ctx_after" .. k, ctx.after ~= nil and k == n)
    end
    if ctx.after and n > 0 then
        local room = M.floor((603 - 154 * (n - 1)) / 5.5)
        local line = ctx.after
        if string.len(line) > room then
            line = string.sub(line, 1, room - 3) .. "..."
        end
        text("dp_nr_ctx_after" .. n, line)
        tip("dp_nr_ctx_after" .. n, ctx.after_tip or ctx.after)
    end
end

local function blocs_present(d)
    local seen, out = {}, {}
    for _, seat in pairs((Republic.senate and Republic.senate.seats(d)) or {}) do
        if not seen[seat.bloc] then
            seen[seat.bloc] = true
            table.insert(out, seat.bloc)
        end
    end
    table.sort(out)
    return out
end

local function member_rows(d)
    local seats = Republic.senate and Republic.senate.seats(d) or {}
    local Members = part("members")
    local demands = {}
    for _, dm in ipairs(Members and Members.demands(d) or {}) do
        demands[dm.key] = dm
    end
    local test = OPINION_FILTERS[Window.op_filter].test
    local blocs = blocs_present(d)
    local bloc = (Window.bloc_filter > 1) and blocs[Window.bloc_filter - 1] or nil
    local groups = {founding = {}, member = {}}
    for key, seat in pairs(seats) do
        if test(seat.opinion) and (not bloc or seat.bloc == bloc) then
            local status = Republic.status(d, key, true)
            local senator = Republic.senator(d, key)
            local name = d:planet_name(seat.planet)
            local interests = Members and table.concat(Members.interests(d, key), ", ") or ""
            local dm = demands[key]
            table.insert(groups[status] or groups.member, {
                icon = globe(key), a = name .. (senator and (" (" .. senator .. ")") or ""), label = name,
                b = seat.bloc .. " " .. signed(seat.opinion), b_color = opinion_color(seat.opinion), key = key,
                world = key, selected = Window.sel.members == key, opinion = seat.opinion, seat = seat, demand = dm,
                tip = name .. ": " .. Republic.STATUS_NAMES[status] .. ", " .. seat.bloc .. " bloc, opinion of the "
                    .. "government " .. signed(seat.opinion) .. (senator and (". Senator " .. senator) or "")
                    .. ((interests ~= "") and (". Interests: " .. interests) or "")
                    .. (dm and (". Wants you to " .. dm.text .. " (" .. weeks(dm.left) .. ")") or "") .. "."})
        end
    end
    local out = {}
    for _, g in ipairs({{"founding", "Founding members"}, {"member", "Member worlds"}}) do
        local rows = groups[g[1]]
        table.sort(rows, function(a, b) return a.label < b.label end)
        if table.getn(rows) > 0 then
            table.insert(out, {head = g[2] .. " (" .. table.getn(rows) .. ")", rows = rows, key = "HEAD"})
        end
    end
    return out
end

local function territory_rows(d)
    local seats = Republic.senate and Republic.senate.seats(d) or {}
    local groups = {occupied = {}, unrepresented = {}, territory = {}}
    local test = OPINION_FILTERS[Window.op_filter].test
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local key = U.key(planet)
        if planet.Get_Owner() == d.human and not seats[key] then
            local status = Republic.status(d, key, false)
            local entry = d.republic.conquered[key]
            local mood = (entry and entry.content) and 25 or -10
            if status == "territory" or test(mood) then
                local name = d:planet_name(planet)
                local note = {occupied = "occupied", unrepresented = "no Senator's Office", territory = "base or station"}
                table.insert(groups[status], {icon = globe(key), a = name, label = name, key = key, world = key,
                    b = (status == "territory") and "No politics" or ((entry and entry.content) and "Content" or "Restless"),
                    b_color = (status == "territory") and GREY_C or opinion_color(mood),
                    selected = Window.sel.members == key, status = status,
                    tip = name .. ": " .. note[status] .. ". " .. ((status == "territory") and "No seat, no opinion, no sympathy."
                        or "No seat until a Senator's Office stands there" .. ((entry and entry.content) and "; its people welcomed the Republic." or "."))})
            end
        end
    end
    local out = {}
    for _, g in ipairs({{"occupied", "Occupied worlds"}, {"unrepresented", "Without a Senator's Office"},
                        {"territory", "Territories (bases and stations)"}}) do
        local rows = groups[g[1]]
        table.sort(rows, function(a, b) return a.label < b.label end)
        if table.getn(rows) > 0 then
            table.insert(out, {head = g[2] .. " (" .. table.getn(rows) .. ")", rows = rows, key = "HEAD"})
        end
    end
    return out
end

local function associate_rows(d)
    local rows = {}
    local test = OPINION_FILTERS[Window.op_filter].test
    local Missions = optional("eawx-plugins/diplomacy/DiplomacyMissions")
    for world, w in pairs(d.vassal_worlds or {}) do
        local planet = FindPlanet(world)
        if planet and w.stage == "associate" and test((w.content or 50) - 50) then
            local name = d:planet_name(planet)
            table.insert(rows, {icon = globe(world), a = name, label = name, key = world, world = world,
                b = "Content " .. (w.content or 50), b_color = opinion_color((w.content or 50) - 50),
                selected = Window.sel.members == world, assoc = w,
                tip = name .. ": an associate world, contentment " .. (w.content or 50) .. "."
                    .. (w.requests and " It asks to join as a member." or "")
                    .. (Missions and (" " .. Missions.describe(d, world)) or "")})
        end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return (table.getn(rows) > 0) and {{head = "Associate worlds (" .. table.getn(rows) .. ")", rows = rows, key = "HEAD"}} or {}
end

local function protectorate_rows(d)
    local P = part("prot")
    local out = {}
    if not P then
        return out
    end
    local calls = {}
    for _, c in ipairs(P.calls(d)) do
        calls[c.key] = c
    end
    local powers, worlds = {}, {}
    local Sym = part("sym")
    local test = OPINION_FILTERS[Window.op_filter].test
    for _, p in ipairs(P.list(d)) do
        local c = calls[p.key]
        local note = c and ((c.left >= 0) and ("Call to action: " .. weeks(c.left)) or "Call overdue") or "At peace"
        if p.kind == "faction" then
            local opinion = 0
            if DIPLOMACY_OPINION then
                local ok, v = pcall(DIPLOMACY_OPINION, p.key, FACTION)
                opinion = (ok and type(v) == "number") and v or 0
            end
            if test(opinion) then
                table.insert(powers, {icon = faction_icon(p.key), a = p.name, label = p.name, key = p.key, b = note,
                    b_color = c and {1, 0.6, 0.45} or PALE_C, selected = Window.sel.members == p.key, prot = p,
                    tip = p.name .. ": under the Republic's protection (no tribute, no ships). Its opinion of the Republic "
                        .. signed(opinion) .. "." .. (c and (" " .. d.display_name(c.attacker) .. " attacks it.") or "")})
            end
        elseif p.stage == "protectorate" then
            local v = Sym and Sym.value(d, p.key) or 50
            local content = (p.state and p.state.content) or 50
            if test(content - 50) then
                table.insert(worlds, {icon = globe(p.key), a = p.name, label = p.name, key = p.key, world = p.key,
                    b = c and note or ("Content " .. content), b_color = c and {1, 0.6, 0.45} or opinion_color(content - 50),
                    selected = Window.sel.members == p.key, prot = p,
                    tip = p.name .. ": a protected world under its own government, contentment " .. content .. "."
                        .. (p.state.petitions and " It petitions to become an associate." or "")
                        .. (c and (" " .. d.display_name(c.attacker) .. " attacks it.") or "")})
            end
        end
    end
    table.sort(powers, function(a, b) return a.label < b.label end)
    table.sort(worlds, function(a, b) return a.label < b.label end)
    if table.getn(powers) > 0 then
        table.insert(out, {head = "Protected powers (" .. table.getn(powers) .. ")", rows = powers, key = "HEAD"})
    end
    if table.getn(worlds) > 0 then
        table.insert(out, {head = "Protected worlds (" .. table.getn(worlds) .. ")", rows = worlds, key = "HEAD"})
    end
    return out
end

local function find_row(groups, key)
    for _, g in ipairs(groups) do
        for _, r in ipairs(g.rows) do
            if r.key == key then
                return r
            end
        end
    end
    return nil
end

local function members_ctx(d, groups)
    local key = Window.sel.members
    local row = key and find_row(groups, key)
    if not row then
        return {text = "Select a world for more, and what can be done with it."}
    end
    local buttons = {}
    if row.world then
        table.insert(buttons, {label = "Planet Info", tip = "The encyclopedia entry of " .. row.label
            .. ": its history, people, terrain, weather and wildlife.", key = {"planet_info", row.world},
            off = not Engine_Planet_Info})
    end
    local after = nil
    if row.world and row.seat and part("laws") and not council(d) then
        table.insert(buttons, {label = "Planetary Laws", tip = "The laws " .. row.label .. "'s parties have passed, "
            .. "and those they could pass. " .. planet_rule(part("laws").CONFIG), key = {"laws_open", "planet", row.world}})
        local Laws = part("laws")
        local w = d.republic and d.republic.laws and d.republic.laws.planet and d.republic.laws.planet[row.world]
        local names = {}
        for key, _ in pairs((w and w.laws) or {}) do
            local def = Laws.def(key)
            if def then
                table.insert(names, def.name)
            end
        end
        table.sort(names)
        after = (names[1] ~= nil) and table.concat(names, ", ") or "No planetary laws in force."
    end
    if row.demand and row.demand.kind == "COLLECT" then
        table.insert(buttons, {label = "Pay " .. row.demand.cost, tip = "Repay the Bothan SpyNet's favours.", key = {"pay", row.key}})
    end
    if row.prot and row.prot.kind == "faction" then
        table.insert(buttons, {label = "End protection", tip = "Withdraw the Republic's protection: reputation -1 rank, "
            .. "mandate -" .. R.PROTECTORATE.END_MANDATE .. ".", key = {"end_protection", row.key}})
    elseif row.prot and row.prot.state and row.prot.state.slot then
        table.insert(buttons, {label = "End protection", tip = "Withdraw the Republic's protection: reputation -1 rank, "
            .. "mandate -" .. R.PROTECTORATE.END_MANDATE .. ".", key = {"end_protection", row.prot.state.slot}})
        if row.prot.state.petitions then
            table.insert(buttons, {label = "Put petition to vote", tip = "Put its petition to become an associate to the chamber.",
                                   key = {"petition", row.key}})
        end
        local Missions = optional("eawx-plugins/diplomacy/DiplomacyMissions")
        if Missions and Missions.talks_blocked and not row.prot.state.petitions then
            local why = Missions.talks_blocked(d, row.key)
            table.insert(buttons, {label = "Integration Talks", off = why ~= nil, key = {"talks", row.key},
                tip = "Begin integration talks: an integration mission for this world, on the way to becoming an "
                    .. "associate." .. (why and (" " .. why) or "")})
        end
    end
    if row.assoc and row.assoc.requests then
        table.insert(buttons, {label = "Put motion to vote", tip = "Put its motion to join as a member to the chamber.",
                               key = {"admit", row.key}})
    end
    return {text = row.tip, buttons = buttons, after = after,
            after_tip = after and ("In force on " .. row.label .. ": " .. string.gsub(after, "%.$", "")
                .. ". Planetary Laws shows what each does.")}
end

local function side_name(d, faction)
    if faction == "INDEPENDENT_FORCES" then
        return "independence"
    end
    return d.display_name(faction)
end

local WORLDS = optional("eawx-plugins/new-republic/RepublicWorlds") or {}

local function world_lines(key, add)
    local w = WORLDS[key]
    if w then
        local natives = w.natives or {}
        if table.getn(natives) > 0 then
            add("Native people: " .. table.concat(natives, ", ") .. ".")
        elseif w.immigrants and w.immigrants[1] then
            add("Majority people: " .. w.immigrants[1] .. ".", "No native people: most here came from elsewhere.")
        end
        local present, seen, many = {}, {}, false
        for _, list in ipairs({natives, w.immigrants or {}}) do
            for _, sp in ipairs(list) do
                if string.lower(sp) == "various" then
                    many = true
                elseif not seen[sp] then
                    seen[sp] = true
                    table.insert(present, sp)
                end
            end
        end
        if many or table.getn(present) > 4 then
            add("Peoples present: Metropolitan (" .. ((table.getn(present) > 4) and (table.getn(present) .. "+")
                or "many") .. " peoples).",
                "A world of many peoples: " .. table.concat(present, ", ") .. (many and ", and many more." or "."))
        elseif table.getn(present) > 0 then
            add("Peoples present: " .. table.concat(present, ", ") .. ".")
        end
        if w.population then
            add("Population: " .. w.population .. ".")
        end
    end
end

local function government_of(key)
    local n = table.getn(R.GOVERNMENT_TYPES)
    return R.GOVERNMENTS[key] or (Republic.is_territory(key) and "Military Administration")
        or R.GOVERNMENT_TYPES[U.hash(key) - M.floor(U.hash(key) / n) * n + 1]
end

local function gov_tip(key, extra)
    local gov = government_of(key)
    tip("dp_nr_md_sub", gov .. ": " .. (R.GOVERNMENT_TEXT[gov] or "the world's own government, under the Republic's charter.")
        .. (extra and (" " .. extra) or ""))
end

local function render_politics(d, key, view)
    local on = view ~= nil
    for k = 1, LAYOUT.md_dots do
        show("dp_nr_md_dot" .. string.format("%02d", k), on)
    end
    for _, name in ipairs({"dp_nr_md_elect", "dp_nr_md_expect", "dp_nr_md_rule1", "dp_nr_md_rule2", "dp_nr_md_cost",
                           "dp_nr_md_costi"}) do
        show(name, on)
    end
    Window.md_parties = {}
    for k = 1, LAYOUT.md_parties do
        local p = on and view.parties[k]
        for _, sfx in ipairs({"pd", "pn", "pb", "pl", "pc", "plob"}) do
            show("dp_nr_md_" .. sfx .. k, p ~= nil and p ~= false)
        end
    end
    if not on then
        return
    end
    local counts, used, rest = {}, 0, {}
    for k, p in ipairs(view.parties) do
        local exact = p.clout * LAYOUT.md_dots / 100
        counts[k] = M.floor(exact)
        used = used + counts[k]
        table.insert(rest, {k, exact - counts[k]})
    end
    table.sort(rest, function(a, b) return a[2] > b[2] end)
    for j = 1, LAYOUT.md_dots - used do
        local r = rest[j]
        if r then
            counts[r[1]] = counts[r[1]] + 1
        end
    end
    local n = 1
    for k, p in ipairs(view.parties) do
        for _ = 1, counts[k] do
            if n <= LAYOUT.md_dots then
                icon("dp_nr_md_dot" .. string.format("%02d", n), p.dot)
                tip("dp_nr_md_dot" .. string.format("%02d", n), p.name .. ": " .. p.clout .. "% of the clout ("
                    .. p.bloc_name .. "). Each dot is " .. (100 / LAYOUT.md_dots) .. "%.")
                n = n + 1
            end
        end
    end
    for k = n, LAYOUT.md_dots do
        show("dp_nr_md_dot" .. string.format("%02d", k), false)
    end
    text("dp_nr_md_elect", view.election)
    tip("dp_nr_md_elect", view.election_tip)
    text("dp_nr_md_expect", view.expected)
    tip("dp_nr_md_expect", view.expected .. ". " .. (view.term and ("The party with the most clout on the day names "
        .. "the senator; a sitting senator's party keeps a close race.") or view.election_tip))
    local Parties = part("parties")
    local why = Parties and Parties.can_lobby(d, key)
    local cost_tip = "Lobbying a party costs " .. R.PARTIES.LOBBY_CAPITAL .. " political capital (you have "
        .. M.floor(d.republic.capital or 0) .. "); one lobby a world every " .. R.PARTIES.LOBBY_WEEKS .. " weeks."
    text("dp_nr_md_cost", "Cost: " .. R.PARTIES.LOBBY_CAPITAL)
    color("dp_nr_md_cost", why and GREY_C or GOLD_C)
    tip("dp_nr_md_cost", cost_tip)
    tip("dp_nr_md_costi", cost_tip)
    for k = 1, LAYOUT.md_parties do
        local p = view.parties[k]
        if p then
            Window.md_parties[k] = p.idx
            local lean = "Leans to the " .. p.bloc_name .. ((p.bloc == "INDEPENDENCE") and ": it would take the world "
                .. "out of the Republic." or ".")
            icon("dp_nr_md_pd" .. k, p.dot)
            tip("dp_nr_md_pd" .. k, lean)
            text("dp_nr_md_pn" .. k, p.name)
            tip("dp_nr_md_pn" .. k, p.name .. (p.ruling and " (in office)" or "") .. ". " .. lean
                .. (p.entrenched and " Its leader is a figure of renown: hard to unseat." or ""))
            text("dp_nr_md_pb" .. k, p.short)
            tip("dp_nr_md_pb" .. k, p.name .. ". " .. lean)
            text("dp_nr_md_pl" .. k, p.leader)
            tip("dp_nr_md_pl" .. k, p.ruling and (p.leader .. " holds the world's seat in the Senate.")
                or (p.leader .. " leads " .. Parties.the(p.name) .. "."))
            color("dp_nr_md_pl" .. k, p.ruling and GOLD_C or PALE_C)
            text("dp_nr_md_pc" .. k, p.clout .. "%")
            tip("dp_nr_md_pc" .. k, p.name .. ": " .. p.clout .. "% of the clout on the world. The party with the "
                .. "most names the senator.")
            text("dp_nr_md_plob" .. k, "Lobby")
            tip("dp_nr_md_plob" .. k, why or ("Back " .. Parties.the(p.name) .. " with favours and funding: clout +"
                .. R.PARTIES.LOBBY_CLOUT .. ", taken from the others. Costs " .. R.PARTIES.LOBBY_CAPITAL .. " political "
                .. "capital; one lobby a world every " .. R.PARTIES.LOBBY_WEEKS .. " weeks."))
            color("dp_nr_md_plob" .. k, why and GREY_C or GOLD_C)
            icon("dp_nr_md_plob" .. k, why and "dp_nr_btn_lob_off.tga" or "dp_nr_btn_lob.tga")
        end
    end
end

local function render_member_detail(d, row, ctx, hint)
    local lines, people = {}, {}
    local function add(value, line_tip)
        table.insert(lines, {value, line_tip or value})
    end
    local function add_people(value, line_tip)
        table.insert(people, {value, line_tip or value})
    end
    Window.md_actions = {}
    Window.md_world = nil
    local view = nil
    if not row then
        icon("dp_nr_md_pic", "dp_emblem_rebel.tga")
        text("dp_nr_md_name", "The Republic's worlds")
        text("dp_nr_md_sub", hint or "Select a world or a power on the left.")
        text("dp_nr_md_kind", "Its senator, opinion, interests, demands and what can be done with it show here.")
    else
        local key = row.world or row.key
        local planet = row.world and FindPlanet(row.world)
        icon("dp_nr_md_pic", row.icon or "dp_globe_unknown.tga")
        tip("dp_nr_md_pic", row.tip or row.label)
        Window.md_world = row.world
        tip("dp_nr_md_zoom", row.world and ("Close the window and look at " .. (row.label or "it") .. " on the map.") or " ")
        text("dp_nr_md_name", row.label or row.a)
        tip("dp_nr_md_name", row.tip or row.label)
        local Members = part("members")
        local S = part("sectors")
        local Sym = part("sym")
        local sector = row.world and U.sector_of(row.world)
        if row.seat then
            local status = Republic.status(d, key, true)
            local Parties = part("parties")
            view = Parties and Parties.view(d, key)
            local senator = Republic.senator(d, key)
            text("dp_nr_md_sub", government_of(key))
            gov_tip(key, view and view.election_tip)
            text("dp_nr_md_kind", senator and ("Senator " .. senator) or "Its senator has not yet taken the seat.")
            add(Republic.STATUS_NAMES[status] .. ", " .. row.seat.bloc .. " bloc.")
            add("Opinion of the government: " .. signed(row.seat.opinion) .. ".",
                "How the senator of " .. row.label .. " sees the government (-100 to +100): it decides their votes.")
            local interests = Members and Members.interests(d, key) or {}
            if table.getn(interests) > 0 then
                add("Interests: " .. table.concat(interests, ", ") .. ".",
                    "What the world cares about: its senator votes and demands accordingly.")
            end
            local Desires = part("desires")
            local wishes = Desires and Desires.lines(d, key) or {}
            for _, line in ipairs(wishes) do
                add(line, "A wish of " .. row.label .. ": met (with or without a request), its opinion rises for a while.")
            end
            if row.demand then
                add("Wants you to " .. row.demand.text .. " (" .. weeks(row.demand.left) .. " left).",
                    "Do it in time: opinion and political capital rise; ignore it and the world resents it.")
            elseif table.getn(wishes) == 0 then
                add("Asks nothing of the government for now.")
            end
        elseif row.status then
            local entry = d.republic.conquered[key]
            local note = {occupied = "Occupied: taken by force, it has no seat yet.",
                          unrepresented = "No Senator's Office: it has no voice in the chamber.",
                          territory = "A base or station world: no people to represent."}
            text("dp_nr_md_sub", government_of(key))
            gov_tip(key)
            text("dp_nr_md_kind", note[row.status] or " ")
            add(Republic.STATUS_NAMES[row.status] .. ".")
            if row.status ~= "territory" then
                add("Mood: " .. ((entry and entry.content) and "content: its people welcomed the Republic."
                    or "restless under occupation."))
                add("Build a Senator's Office there to give it a seat in the chamber.")
                if entry and entry.time then
                    add("The Republic's since " .. weeks(U.weeks_since(entry.time)) .. " ago.")
                end
            else
                add("No seat, no opinion and no sympathy: it serves the fleet.")
            end
        elseif row.assoc then
            local w = row.assoc
            text("dp_nr_md_sub", government_of(key))
            gov_tip(key)
            text("dp_nr_md_kind", "Associate world: it pays its share and sends ships.")
            add("Contentment: " .. (w.content or 50) .. ".", "Below 50 it grows restless; high, it may ask to join as a member.")
            add(w.requests and "It asks to join as a member: put the motion to the chamber." or "It does not ask for a seat yet.")
            local Missions = optional("eawx-plugins/diplomacy/DiplomacyMissions")
            if Missions then
                add(Missions.describe(d, key))
            end
        elseif row.prot then
            local p = row.prot
            if p.kind == "faction" then
                text("dp_nr_md_sub", "Protected power")
                text("dp_nr_md_kind", "Under the Republic's protection: no tribute, no ships.")
                add(row.b .. ".", row.tip)
                local player = Find_Player(p.key)
                if player then
                    add("It holds " .. U.count(U.worlds_of(player)) .. " worlds.")
                end
            else
                local content = (p.state and p.state.content) or 50
                text("dp_nr_md_sub", government_of(key))
                gov_tip(key)
                text("dp_nr_md_kind", "Protected world: under its own government, guarded by the Republic.")
                add("Contentment: " .. content .. ".", "High contentment: it may petition to become an associate.")
                add((p.state and p.state.petitions) and "It petitions to become an associate: put it to the chamber."
                    or "It does not petition for more yet.")
                add(row.b .. ".", row.tip)
            end
        end
        if row.world then
            world_lines(key, add_people)
        end
        if sector then
            local level = S and R.TAX_LEVELS[S.level(d, sector)]
            add("Sector: " .. sector .. (level and (", taxes " .. level.name) or "") .. ".",
                "Taxes are set per sector in the Sectors tab.")
        end
        if planet and S and S.income_of then
            local ok, income = pcall(S.income_of, d, planet, Window.trade or {})
            if ok and income then
                add("Income: " .. M.round(income) .. " credits a week (base and trade).")
            end
        end
        if planet and Sym and Sym.preferred and planet.Get_Owner() ~= d.human then
            add("Its rebels look to " .. side_name(d, Sym.preferred(d, key)) .. ".",
                "When this world rises, it rises for them. A resistance cell (Intelligence) turns them to the Republic.")
        end
        for _, b in ipairs((ctx and ctx.buttons) or {}) do
            table.insert(Window.md_actions, b)
        end
    end
    for k = 1, 3 do
        local line = people[k]
        show("dp_nr_md_p" .. k, line ~= nil)
        if line then
            text("dp_nr_md_p" .. k, line[1])
            tip("dp_nr_md_p" .. k, line[2])
        end
    end
    show("dp_nr_md_zoom", Window.md_world ~= nil)
    render_politics(d, row and (row.world or row.key), view)
    local prefix, most = "dp_nr_md_l", LAYOUT.md_lines
    local other, other_most = "dp_nr_md_m", LAYOUT.md_mlines
    if view then
        prefix, most, other, other_most = other, other_most, prefix, most
    end
    for k = 1, other_most do
        show(other .. k, false)
    end
    if table.getn(lines) > most then
        local extra = {}
        for k = most + 1, table.getn(lines) do
            table.insert(extra, lines[k][1])
        end
        lines[most] = {lines[most][1], lines[most][2] .. " Also: " .. table.concat(extra, " ")}
    end
    for k = 1, most do
        local line = lines[k]
        show(prefix .. k, line ~= nil)
        if line then
            text(prefix .. k, line[1])
            tip(prefix .. k, line[2])
        end
    end
    for k = 1, LAYOUT.md_actions do
        local b = Window.md_actions[k]
        show("dp_nr_md_a" .. k, b ~= nil)
        if b then
            text("dp_nr_md_a" .. k, b.label)
            tip("dp_nr_md_a" .. k, b.tip or b.label)
            icon("dp_nr_md_a" .. k, b.off and "dp_nr_btn_m_off.tga" or "dp_nr_btn_m.tga")
            color("dp_nr_md_a" .. k, b.off and GREY_C or GOLD_C)
        end
    end
end

local function render_members(d)
    if GetCurrentTime() >= (Window.trade_at or 0) then
        local S = part("sectors")
        Window.trade, Window.trade_at = S and S.trade_income and S.trade_income(d) or {}, GetCurrentTime() + 5
    end
    local builders = {members = member_rows, territories = territory_rows, associates = associate_rows,
                      protectorates = protectorate_rows}
    local groups = builders[Window.view](d)
    local toggles = {}
    for _, v in ipairs(VIEWS) do
        table.insert(toggles, {label = v.label, tip = v.tip, on = v.key == Window.view, key = v.key})
    end
    local blocs = blocs_present(d)
    local filters = {{label = OPINION_FILTERS[Window.op_filter].label, key = "op",
                      tip = ((Window.view == "protectorates" or Window.view == "associates") and "Contentment" or "Opinion")
                          .. " filter. Click to change."}}
    if Window.view == "members" then
        table.insert(filters, {label = (Window.bloc_filter > 1) and (blocs[Window.bloc_filter - 1] or "Any bloc") or "Any bloc",
                               key = "bloc", tip = "Bloc (party) filter. Click to change."})
    end
    local count = 0
    for _, g in ipairs(groups) do
        count = count + table.getn(g.rows)
    end
    local ctx = members_ctx(d, groups)
    render_columns(groups, "single", {toggles = toggles, filters = filters, ctx = ctx,
                                      hint = (count == 0) and "Nothing here with these filters." or nil})
    render_member_detail(d, Window.sel.members and find_row(groups, Window.sel.members), ctx,
        (count == 0) and "Nothing here with these filters." or nil)
end

local function tax_emblem(d, planet, key, owner)
    if planet.Get_Owner() == d.human then
        return "dp_emblem_rebel.tga", "The New Republic's."
    end
    local w = d.vassal_worlds and d.vassal_worlds[key]
    if w and (w.stage == "associate" or w.stage == "protectorate") then
        return "dp_vassal_rebel.tga", (w.stage == "associate") and "An associate world of the Republic."
            or "Under the Republic's protection."
    end
    if owner == "INDEPENDENT_FORCES" or (w and w.slot) then
        return globe(key), "An independent world."
    elseif owner == "WARLORDS" then
        return globe(key), "Held by minor warlords."
    end
    return faction_icon(owner), d.display_name(owner) .. "."
end

local function tax_groups(d)
    local S = part("sectors")
    if not S then
        return {}
    end
    local seated = Republic.seated_planets(d)
    local by = (d.republic.tax and d.republic.tax.by_sector) or {}
    local out = {}
    for _, sec in ipairs(S.sectors(d, seated)) do
        local level = R.TAX_LEVELS[sec.level]
        local rows = {}
        local data = U.sector(sec.name)
        local worlds = (data and data.worlds) or sec.worlds
        for _, key in ipairs(worlds) do
            local planet = FindPlanet(key)
            if planet then
                local owner = string.upper(planet.Get_Owner().Get_Faction_Name())
                local ours = planet.Get_Owner() == d.human
                local member = seated[key] ~= nil
                local name = d:planet_name(planet)
                local emb, emb_tip = tax_emblem(d, planet, key, owner)
                table.insert(rows, {icon = globe(key), a = name, label = name, key = sec.name, world = key, dim = not ours,
                    emb = emb, emb_tip = emb_tip, icon_tip = name .. ": click to open it in the Members tab.",
                    b = member and "Member" or (ours and Republic.STATUS_NAMES[Republic.status(d, key, false)] or d.display_name(owner)),
                    b_color = (not ours) and owner_color(owner) or nil, selected = Window.sel.taxes == sec.name,
                    tip = name .. ": " .. (member and ("a member world, taxed at " .. level.name) or (ours and
                        "the Republic's, but not taxed by the sector (no seat)" or ("held by " .. d.display_name(owner))))
                        .. ". Click to select the " .. sec.name .. "."})
            end
        end
        local Laws = part("laws")
        local a, b = nil, nil
        if Laws then
            a, b = Laws.vote_line(d, sec.name)
        end
        if a then
            table.insert(rows, 1, {sub = true, a = a, b = b, a_color = GOLD_C, b_color = GOLD_C, key = sec.name,
                selected = Window.sel.taxes == sec.name,
                tip = "The " .. sec.name .. "'s member worlds vote among themselves; the share is how many of its seats "
                    .. "back it. Veto it from the sector's buttons or the notice below."})
        end
        local extra = Laws and Laws.tax_levels(d, sec.name) or 0
        if extra > 0 then
            level = R.TAX_LEVELS[M.min(table.getn(R.TAX_LEVELS), sec.level + extra)]
        end
        local entry = by[sec.name]
        table.insert(out, {head = sec.name, lvl = "Taxes: " .. level.name .. ((extra > 0) and " (Austerity)" or "") .. ((level.pct ~= 0) and (" (" .. signed(level.pct) .. "%)") or ""),
                           lvl_color = TAX_COLORS[sec.level], key = sec.name, selected = Window.sel.taxes == sec.name, rows = rows, sector = sec, level = level,
                           tip = sec.name .. ": taxes " .. level.name .. " on " .. table.getn(sec.worlds) .. " member world"
                               .. ((table.getn(sec.worlds) == 1) and "" or "s") .. (entry and (", income " .. M.round(entry.income)
                               .. " a week, the tax " .. signed(entry.take)) or "") .. ". Click to select it."})
    end
    return out
end

local function render_taxes(d)
    local S = part("sectors")
    local groups = tax_groups(d)
    local sel = nil
    for _, g in ipairs(groups) do
        if g.key == Window.sel.taxes then
            sel = g
        end
    end
    local ctx
    if sel and S then
        local sec, level = sel.sector, sel.level
        local can = S.can_move(d, sec.name)
        local entry = d.republic.tax and d.republic.tax.by_sector and d.republic.tax.by_sector[sec.name]
        local buttons = {}
        local lower = sec.level > 1 and R.TAX_LEVELS[sec.level - 1]
        local higher = sec.level < table.getn(R.TAX_LEVELS) and R.TAX_LEVELS[sec.level + 1]
        local wait = (not can) and "A tax motion was heard here lately: one per sector every " .. weeks(R.TAX_MOTION_WEEKS) .. "." or nil
        local Laws = part("laws")
        if Laws then
            local _, _, vote = Laws.vote_line(d, sec.name)
            local vdef = vote and Laws.def(vote.law)
            local open = Window.laws and Window.laws.kind == "sector" and Window.laws.key == sec.name
            table.insert(buttons, {label = open and "Back to Sectors" or "Sector Laws", key = {"laws_open", "sector", sec.name},
                tip = open and "Back to the sectors' list." or ("The laws the " .. sec.name
                    .. " has passed for itself, and those it could pass. " .. sector_rule(Laws.CONFIG))})
            table.insert(buttons, {label = "Veto Current Vote", key = {"law_veto", sec.name}, off = vote == nil,
                tip = vote and ("Void the vote on the " .. (vdef and vdef.name or "law") .. ": the sector's worlds "
                    .. Laws.CONFIG.VETO_OPINION .. " opinion.") or "No vote runs in the sector now."})
        end
        table.insert(buttons, {label = "Lower taxes", key = {"tax", sec.name, sec.level - 1}, off = (not lower) or (not can),
            tip = lower and ("Propose lowering the " .. sec.name .. "'s taxes to " .. lower.name .. " (" .. signed(lower.pct)
                .. "%): its members think better of the government (" .. signed(lower.opinion) .. "). Its senators vote for it."
                .. (wait and (" " .. wait) or "")) or "Taxes here are as low as they go."})
        table.insert(buttons, {label = "Raise taxes", key = {"tax", sec.name, sec.level + 1}, off = (not higher) or (not can),
            tip = higher and ("Propose raising the " .. sec.name .. "'s taxes to " .. higher.name .. " (" .. signed(higher.pct)
                .. "%): its members think less of the government (" .. signed(higher.opinion) .. "), and resent it if you lower "
                .. "them again. Its senators vote against it." .. (wait and (" " .. wait) or "")) or "Taxes here are as high as they go."})
        ctx = {text = sec.name .. ": taxes " .. level.name .. ", " .. table.getn(sec.worlds) .. " member world"
            .. ((table.getn(sec.worlds) == 1) and "" or "s") .. (entry and (", base and trade income " .. M.round(entry.income)
            .. " a week, tax " .. signed(entry.take)) or "") .. ".", buttons = buttons}
    end
    local last = (d.republic.tax and d.republic.tax.last) or 0
    local laws_open = Window.laws and Window.laws.kind == "sector"
    render_columns(groups, laws_open and "single" or false, {info = "Sector taxes on members' base and trade-port income: " .. signed(last)
        .. " credits last week. Click a sector.", info_tip = "Each sector's members are taxed at its level, Very Low (-50%) "
        .. "to Very High (+50%). Every change is a Senate vote; raising and then lowering leaves a grudge.",
        ctx = ctx, hint = (table.getn(groups) == 0) and "No member world sits in a sector yet." or
            "Select a sector to raise or lower its taxes."})
end

local function draw_list_thumb()
    draw_thumb("dp_nr_il_seg", LAYOUT.list_segs, LAYOUT.list_seg, (Window.page or 1) - 1, Window.lmax or 0,
        Window.lthumb or 24, Window.ldragging and Window.lshare or nil)
end

local function pip_color(v)
    return (v >= 60) and "green" or ((v >= 40) and "yellow" or "red")
end

local function render_list(head, cols, rows)
    text("dp_nr_il_head", head)
    for i, key in ipairs({"a", "b", "c", "bar"}) do
        text("dp_nr_il_h_" .. key, cols[i] or " ")
    end
    local per = LAYOUT.rows
    local total = table.getn(rows)
    Window.lmax = M.max(0, total - per)
    Window.page = M.min(M.max(1, Window.page or 1), Window.lmax + 1)
    local first = Window.page - 1
    Window.rows = {}
    for k = 1, per do
        local row = rows[first + k]
        local r = "dp_nr_il_r" .. k
        Window.rows[k] = row
        local head_row = row ~= nil and row.head == true
        show(r, row ~= nil and not head_row)
        show(r .. "_a", row ~= nil and not head_row)
        show(r .. "_b", row ~= nil)
        show(r .. "_c", row ~= nil)
        show(r .. "_head", head_row)
        show(r .. "_line", head_row)
        show(r .. "_icon", row ~= nil and row.icon ~= nil and not head_row)
        show(r .. "_lvl", row ~= nil and row.level ~= nil and not head_row)
        show(r .. "_hit", row ~= nil)
        if row and row.level and not head_row then
            icon(r .. "_lvl", "dp_nr_rank_" .. row.level .. ".tga")
        end
        for j = 1, LAYOUT.pips do
            show(r .. "_p" .. j, row ~= nil and row.value ~= nil and not head_row)
        end
        if row then
            if head_row then
                text(r .. "_head", row.a)
                color(r .. "_head", {0.92, 0.8, 0.5})
            else
                icon(r, row.selected and "dp_nr_lrow_sel.tga" or "dp_nr_lrow.tga")
                text(r .. "_a", row.a)
                color(r .. "_a", row.dim and GREY_C or PALE_C)
            end
            if row.icon and not head_row then
                icon(r .. "_icon", row.icon)
            end
            text(r .. "_b", row.b)
            text(r .. "_c", row.c)
            color(r .. "_b", (head_row or row.dim) and GREY_C or PALE_C)
            color(r .. "_c", (head_row or row.dim) and GREY_C or PALE_C)
            if row.value and not head_row then
                local n = M.max(0, M.min(LAYOUT.pips, M.round(row.value / 10)))
                for j = 1, LAYOUT.pips do
                    icon(r .. "_p" .. j, (j <= n) and ("dp_nr_pip_" .. (row.pips or pip_color(row.value)) .. ".tga")
                        or "dp_nr_pip_empty.tga")
                    tip(r .. "_p" .. j, row.tip or row.a)
                end
            end
            local t = row.tip or row.a
            for _, s in ipairs({"", "_icon", "_a", "_b", "_c", "_head", "_hit"}) do
                tip(r .. s, t)
            end
        end
    end
    local scrolling = Window.lmax > 0
    show("dp_nr_il_up", scrolling)
    show("dp_nr_il_down", scrolling)
    for k = 1, LAYOUT.list_segs do
        show("dp_nr_il_seg" .. k, scrolling)
        tip("dp_nr_il_seg" .. k, "Drag, click or use the mouse wheel to scroll the " .. total .. " rows.")
    end
    if scrolling then
        Window.lthumb = M.max(16, LAYOUT.list_segs * LAYOUT.list_seg * per / total)
        draw_list_thumb()
    end
end

local function render_tools(tools)
    Window.tools = {}
    for k = 1, 3 do
        local t = tools[k]
        local name = "dp_nr_il_tool" .. k
        show(name, t ~= nil)
        Window.tools[k] = t
        if t then
            text(name, t[1])
            tip(name, t[3] or t[1])
            icon(name, t[4] and "dp_nr_btn_off.tga" or "dp_nr_btn.tga")
            color(name, t[4] and GREY_C or GOLD_C)
        end
    end
end

local function draw_world_thumb()
    draw_thumb("dp_nr_id_wseg", LAYOUT.world_segs, 4, Window.wscroll or 0, Window.wmax or 0, Window.wthumb or 24,
        Window.wdragging and Window.wshare or nil)
end

local function render_detail(dd)
    show("dp_nr_id_portrait", dd.portrait ~= nil)
    show("dp_nr_id_portrait_lvl", dd.portrait ~= nil and dd.level ~= nil)
    if dd.portrait then
        icon("dp_nr_id_portrait", dd.portrait)
        tip("dp_nr_id_portrait", dd.portrait_tip or ((dd.name or "") .. ". " .. (dd.sub or "")))
        if dd.level then
            icon("dp_nr_id_portrait_lvl", "dp_nr_rank_" .. dd.level .. ".tga")
        end
    end
    text("dp_nr_id_name", dd.name)
    text("dp_nr_id_sub", dd.sub)
    text("dp_nr_id_sub2", dd.sub2)
    text("dp_nr_id_kind", dd.kind)
    for k = 1, 4 do
        local line = dd.stats and dd.stats[k]
        local value = type(line) == "table" and line[1] or line
        text("dp_nr_id_s" .. k, value)
        tip("dp_nr_id_s" .. k, type(line) == "table" and line[2] or value)
    end
    text("dp_nr_id_rh", dd.head)
    for k = 1, (LAYOUT.views or 0) do
        local v = dd.views and dd.views[k]
        show("dp_nr_id_v" .. k, v ~= nil)
        show("dp_nr_id_v" .. k .. "_n", v ~= nil)
        if v then
            icon("dp_nr_id_v" .. k, v.icon)
            tip("dp_nr_id_v" .. k, v.tip)
            text("dp_nr_id_v" .. k .. "_n", ((v.value > 0) and "+" or "") .. v.value)
            tip("dp_nr_id_v" .. k .. "_n", v.tip)
            color("dp_nr_id_v" .. k .. "_n", (v.value > 0) and {0.55, 0.85, 0.6} or ((v.value < 0) and {0.95, 0.5, 0.45}
                or PALE_C))
        end
    end
    for k = 1, LAYOUT.lines do
        local line = dd.lines and dd.lines[k]
        if dd.views then
            line = nil
        end
        local value = type(line) == "table" and line[1] or line
        text("dp_nr_id_l" .. k, (dd.worlds and " ") or value)
        tip("dp_nr_id_l" .. k, type(line) == "table" and line[2] or value)
        if not dd.worlds then
            tip("dp_nr_id_l" .. k .. "_hit", type(line) == "table" and line[2] or value)
        end
        show("dp_nr_id_l" .. k .. "_hit", (value ~= nil and value ~= " ") or dd.worlds ~= nil)
        local v = type(line) == "table" and line.value
        color("dp_nr_id_l" .. k, (v and v > 0) and {0.55, 0.85, 0.6} or ((v and v < 0) and {0.95, 0.5, 0.45} or PALE_C))
    end
    Window.actions = {}
    for k = 1, LAYOUT.actions do
        local a = dd.actions and dd.actions[k]
        local name = "dp_nr_id_a" .. k
        show(name, a ~= nil)
        Window.actions[k] = a
        if a then
            text(name, a[1])
            tip(name, a[3] or a[1])
            icon(name, a[4] and "dp_nr_btn_i_off.tga" or "dp_nr_btn_i.tga")
            color(name, a[4] and GREY_C or GOLD_C)
        end
    end
    local worlds = dd.worlds
    Window.world_rows = {}
    local per = LAYOUT.world_rows
    local total = worlds and table.getn(worlds) or 0
    Window.wmax = M.max(0, total - per)
    Window.wscroll = M.min(M.max(0, Window.wscroll or 0), Window.wmax)
    for k = 1, per do
        local w = worlds and worlds[Window.wscroll + k]
        local p = "dp_nr_id_w" .. k
        Window.world_rows[k] = w
        show(p .. "_pic", w ~= nil and w.pic ~= nil)
        local name = (w and not w.world) and (p .. "_wide") or (p .. "_name")
        show(p .. "_name", w ~= nil and w.world ~= nil)
        show(p .. "_wide", w ~= nil and not w.world)
        show(p .. "_globe", w ~= nil and w.world ~= nil)
        show(p .. "_zoom", w ~= nil and w.world ~= nil)
        show(p .. "_crest", false)
        show(p .. "_lvl", w ~= nil and w.level ~= nil)
        if w then
            if w.pic then
                icon(p .. "_pic", w.pic)
                tip(p .. "_pic", w.pic_tip or w.tip)
            end
            if w.level then
                icon(p .. "_lvl", "dp_nr_rank_" .. w.level .. ".tga")
            end
            text(name, w.text)
            tip(name, w.tip)
            tip("dp_nr_id_l" .. k .. "_hit", w.tip)
            color(name, w.color or PALE_C)
            if w.world then
                icon(p .. "_globe", globe(w.world))
                tip(p .. "_globe", (w.label or w.text) .. ".")
                tip(p .. "_zoom", "Show " .. (w.label or w.text) .. " on the map.")
            end
        end
    end
    local scrolling = Window.wmax > 0
    show("dp_nr_id_w_up", scrolling)
    show("dp_nr_id_w_down", scrolling)
    for k = 1, LAYOUT.world_segs do
        show("dp_nr_id_wseg" .. k, scrolling)
        tip("dp_nr_id_wseg" .. k, "Drag, click or use the mouse wheel to scroll the " .. total .. " " .. (dd.rows_word or "rows") .. ".")
    end
    if scrolling then
        Window.wthumb = M.max(16, LAYOUT.world_segs * 4 * per / total)
        draw_world_thumb()
    end
    local message = Window.feedback or " "
    local first, second = message, " "
    local room = ROOM["dp_nr_id_feedback"] or {400, 7}
    if text_width(message, room[2]) > room[1] - 4 then
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
    text("dp_nr_id_feedback", first)
    text("dp_nr_id_feedback2", second)
    tip("dp_nr_id_feedback", message)
    tip("dp_nr_id_feedback2", message)
end

local function render_intel(d)
    local Intel = require("eawx-plugins/new-republic/RepublicIntel")
    local s = Intel.state(d)
    local H = intel_helpers(d)
    local head, cols, rows = IW.rows(d, s, H)
    render_list(head, cols, rows)
    render_tools(IW.tools(d, s))
    local box_text, box_tip = IW.box(d, s)
    show("dp_nr_il_box", true)
    text("dp_nr_il_box", box_text)
    tip("dp_nr_il_box", box_tip)
    render_detail(IW.detail(d, s, H))
end

local function render_pick(d)
    local Gov = part("gov")
    local office = Window.pick
    local name = office
    for _, o in ipairs(Gov.offices(d)) do
        if o.key == office then
            name = o.name
        end
    end
    local rows = {}
    for _, c in ipairs(Gov.candidates_for(d, office)) do
        local p = person(c.key)
        table.insert(rows, {icon = p and p.icon or "dp_emblem_rebel.tga", a = c.name, b = c.bloc, c = "Fit " .. c.score,
                            key = c.key,
                            tip = c.name .. " (" .. string.lower(c.bloc) .. "; cares about " .. c.interests .. "): fitness "
                                .. "for the office " .. c.score .. ". Click to appoint them (" .. R.APPOINT_CAPITAL
                                .. " political capital)."})
    end
    render_list("Appoint the Minister of " .. name, {"Candidate", "Standing", "Fitness", " "}, rows)
    render_tools({{"Cancel", "pick_cancel", "Back without choosing."}})
    show("dp_nr_il_box", false)
end

local function render_government(d)
    local Gov = part("gov")
    show("dp_nr_list_shell", Window.pick ~= nil)
    show("dp_nr_bars_shell", Window.pick ~= nil)
    show("dp_nr_gov_shell", Window.pick == nil)
    if not Gov then
        return
    end
    if Window.pick then
        render_pick(d)
    else
        local key, chief = chief_entry()
        local cand = R.CANDIDATES[key]
        local agenda = Gov.agenda(d)
        icon("dp_nr_gv_chief", chief and chief.icon or "dp_emblem_rebel.tga")
        text("dp_nr_gv_chief_name", "Chancellor " .. (chief and chief.name or (cand and cand.name) or "?"))
        text("dp_nr_gv_chief_agenda", cand and ((agenda and "" or "Suspended: ") .. cand.text) or " ")
        local chief_tip = (chief and chief.name or "The Chancellor") .. ": " .. (cand and cand.text or "no agenda") .. "."
            .. ((not agenda and cand) and " The agenda is suspended after a vote of no confidence." or "")
        for _, p in ipairs({"dp_nr_gv_chief", "dp_nr_gv_chief_name", "dp_nr_gv_chief_agenda"}) do
            tip(p, chief_tip)
        end
        local seats = Republic.senate and Republic.senate.seats(d) or {}
        Window.offices = Gov.offices(d)
        for k = 1, LAYOUT.seats do
            local o = Window.offices[k]
            local p = "dp_nr_gv_s" .. k
            if o then
                local who = o.holder and person(o.holder)
                icon(p, who and who.icon or "dp_globe_unknown.tga")
                text(p .. "_office", o.name)
                text(p .. "_sub", o.holder and (Gov.councillor_of(o.holder) and "Former Councillor" or "Candidate") or " ")
                text(p .. "_name", o.holder_name or "Vacant")
                color(p .. "_name", PALE_C)
                color(p .. "_office", (Window.sel.government == o.key) and {1, 0.95, 0.65} or GOLD_C)
                local t = "Minister of " .. o.name .. ": " .. (o.holder_name or "vacant") .. ". " .. o.text
                    .. " Click to select."
                for _, sfx in ipairs({"", "_office", "_name", "_sub", "_hit"}) do
                    tip(p .. sfx, t)
                end
            end
        end
        local sel = nil
        for _, o in ipairs(Window.offices) do
            if o.key == Window.sel.government then
                sel = o
            end
        end
        Window.gov_buttons = {}
        if sel then
            local open, left = Gov.can_replace(d)
            local when = open and (" Ministers can be replaced for " .. left .. " more week" .. ((left == 1) and "" or "s") .. ".")
                or (" " .. left)
            text("dp_nr_gv_sel", "Minister of " .. sel.name .. ": " .. (sel.holder_name or "vacant") .. ". " .. sel.text)
            table.insert(Window.gov_buttons, {label = "Appoint...", key = {"pick", sel.key}, off = sel.holder ~= nil and not open,
                tip = "Choose a minister: a former Councillor or a candidate for Chancellor, not the Chancellor ("
                    .. R.APPOINT_CAPITAL .. " political capital)."
                    .. (sel.holder and when or " A vacant office can be filled at any time.")})
            table.insert(Window.gov_buttons, {label = "Dismiss", key = {"dismiss", sel.key}, off = sel.holder == nil or not open,
                tip = (sel.holder and ("Dismiss " .. (sel.holder_name or "the minister") .. ".") or "The office is vacant.")
                    .. when})
        else
            local budget = (d.republic.gov and d.republic.gov.cut_until) and ("The Defence Appropriation was cut: "
                .. R.APPROPRIATION_WITHHELD .. " credits are withheld each week.") or "The fleet is funded."
            if d.senate and d.senate.council then
                budget = "The Provisional Council decides at once: no sessions, no appropriation."
            end
            text("dp_nr_gv_sel", "Select an office. " .. budget)
        end
        for k = 1, 3 do
            local b = Window.gov_buttons[k]
            show("dp_nr_gv_a" .. k, b ~= nil)
            if b then
                text("dp_nr_gv_a" .. k, b.label)
                tip("dp_nr_gv_a" .. k, b.tip)
                icon("dp_nr_gv_a" .. k, b.off and "dp_nr_btn_a_off.tga" or "dp_nr_btn_a.tga")
                color("dp_nr_gv_a" .. k, b.off and GREY_C or GOLD_C)
            end
        end
    end
    local cands = Gov.candidates(d)
    Window.cands = cands
    local total = 0
    for _, c in ipairs(cands) do
        total = total + c.support
    end
    text("dp_nr_ev_head", "The Election of the Chancellor")
    local Council = part("council")
    local due = Council and Council.election_in and Council.election_in()
    local Goals = optional("eawx-plugins/diplomacy/DiplomacyGoals")
    text("dp_nr_ev_sub", due and Goals and Goals.week and ("Next election: week " .. Goals.week(GetCurrentTime()
        + U.weeks(due)) .. " (in " .. weeks(due) .. ").")
        or "The chamber's favourite takes office at the next election.")
    tip("dp_nr_ev_sub", "The chamber's favourite takes office at the election. Thrawn's elections: the candidate with the most support in the chamber wins. Seats lean to a "
        .. "candidate by their interests (and the Bothans to Fey'lya); backing one adds " .. R.BACK_WEIGHT .. " seats' weight.")
    local dots, given = LAYOUT.dots, 0
    local counts = {}
    for k, c in ipairs(cands) do
        counts[k] = (total > 0) and M.round(dots * c.support / total) or 0
        given = given + counts[k]
    end
    if counts[1] and given ~= dots and total > 0 then
        counts[1] = M.max(0, counts[1] + dots - given)
    end
    local order = {}
    local rows = {}
    local start = 0
    for _, n in ipairs(LAYOUT.dot_rows) do
        table.insert(rows, {start = start, n = n})
        start = start + n
    end
    local position = {}
    for ri, row in ipairs(rows) do
        for j = 0, row.n - 1 do
            table.insert(position, {index = row.start + j + 1, angle = j / M.max(1, row.n - 1), row = ri})
        end
    end
    table.sort(position, function(a, b)
        if a.angle ~= b.angle then
            return a.angle < b.angle
        end
        return a.row < b.row
    end)
    local k, left = 1, counts[1] or 0
    for _, pos in ipairs(position) do
        while k <= table.getn(counts) and left <= 0 do
            k = k + 1
            left = counts[k] or 0
        end
        order[pos.index] = (k <= table.getn(counts) and total > 0) and k or 0
        left = left - 1
    end
    for n = 1, dots do
        icon(string.format("dp_nr_ev_dot%02d", n), "dp_nr_vdot_" .. M.min(5, order[n] or 0) .. ".tga")
    end
    text("dp_nr_ev_total", total .. " votes")
    for c = 1, LAYOUT.cands do
        local cand = cands[c]
        local p = "dp_nr_ev_"
        show(p .. "sw" .. c, cand ~= nil)
        show(p .. "pic" .. c, cand ~= nil)
        show(p .. "c" .. c, cand ~= nil)
        show(p .. "c" .. c .. "_sub", cand ~= nil)
        show(p .. "back" .. c, cand ~= nil)
        if cand then
            local entry = person(cand.key)
            icon(p .. "sw" .. c, "dp_nr_vdot_" .. M.min(5, c) .. ".tga")
            icon(p .. "pic" .. c, entry and entry.icon or "dp_emblem_rebel.tga")
            local pct = (total > 0) and M.round(100 * cand.support / total) or 0
            text(p .. "c" .. c, cand.name .. ": " .. cand.support .. " (" .. pct .. "%)" .. (cand.current and ", in office" or ""))
            text(p .. "c" .. c .. "_sub", cand.text)
            text(p .. "back" .. c, cand.backed and "Backed" or "Back")
            icon(p .. "back" .. c, cand.backed and "dp_nr_btn_xs2_on.tga" or "dp_nr_btn_xs2.tga")
            local t = cand.name .. (cand.current and " (Chancellor)" or "") .. ": " .. cand.support .. " votes' "
                .. "support, " .. pct .. "%. Agenda: " .. cand.text
            tip(p .. "c" .. c, t)
            tip(p .. "c" .. c .. "_sub", t)
            tip(p .. "pic" .. c, t)
            tip(p .. "back" .. c, cand.backed and ("You back " .. cand.name .. ".") or ("Back " .. cand.name .. " at the next "
                .. "election (" .. R.BACK_CAPITAL .. " political capital, worth " .. R.BACK_WEIGHT .. " seats)."))
        end
    end
end

local function jedi_mode(d)
    return JW ~= nil and d.republic.jedi_founded == true
end

local function render_jedi_header(d, on)
    show("dp_nr_jh_shell", on)
    if not on then
        return
    end
    show("dp_nr_coh_label", false)
    show("dp_nr_coh_frame", false)
    show("dp_nr_cbar_frame", false)
    for k = 1, LAYOUT.cbar_pips or 0 do
        show("dp_nr_cbar_t" .. k, false)
        show("dp_nr_cbar_" .. k, false)
    end
    Window.coh_pulse = nil
    for k = 1, LAYOUT.coh_pips do
        show("dp_nr_coh_" .. k, false)
        show("dp_nr_coh_m" .. k, false)
    end
    for k = 1, LAYOUT.trend do
        show("dp_nr_coh_up" .. k, false)
        show("dp_nr_coh_dn" .. k, false)
    end
    for k, row in ipairs(JW.header(d)) do
        text("dp_nr_jh_t" .. k, row[1])
        tip("dp_nr_jh_t" .. k, row[2])
        tip("dp_nr_jh_i" .. k, row[2])
    end
end

local function render_jedi(d)
    local on = jedi_mode(d)
    show("dp_nr_jedi_shell", not on)
    if on then
        JW.pick_rows = LAYOUT.jt.pick_rows
        JW.render(d, jedi_state(d), {show = show, text = text, tip = tip, icon = icon, color = color, L = LAYOUT.jt})
        return
    end
    for _, shell in ipairs(LAYOUT.jt_shells) do
        show(shell, false)
    end
    text("dp_nr_jedi_head", "The Jedi Order")
    if Republic.luke_lost and Republic.luke_lost(d) then
        text("dp_nr_jedi_l1", "The last of the Jedi are finally dead, and none remain who can teach the wisdom of the old masters.")
        text("dp_nr_jedi_l2", "With Master Skywalker gone, the teachings of the Jedi have been surely lost to The Force with him...")
        text("dp_nr_jedi_l3", " ")
        return
    end
    text("dp_nr_jedi_l1", "The Order is not yet founded. Master Skywalker seeks a place strong in The Force to rekindle its teachings.")
    text("dp_nr_jedi_l2", "Build the Jedi Temple on Yavin to found a new Jedi Order.")
    text("dp_nr_jedi_l3", " ")
end

local function two_lines(value, width)
    local lines, line = {}, ""
    for word in string.gfind(value or "", "%S+") do
        local next_line = (line == "") and word or (line .. " " .. word)
        if text_width(next_line, 6) > width and line ~= "" then
            table.insert(lines, line)
            line = word
        else
            line = next_line
        end
    end
    if line ~= "" then
        table.insert(lines, line)
    end
    if table.getn(lines) > 2 then
        lines[2] = table.concat(lines, " ", 2)
    end
    return lines[1] or " ", lines[2] or " "
end

local function names(list)
    if not list or not list[1] then
        return "none"
    end
    return table.concat(list, ", ")
end

local function render_laws(d)
    local Laws = part("laws")
    local L = Laws.CONFIG
    local w = Window.laws
    local rows = {}
    if w.kind == "sector" then
        local view = Laws.sector_view(d, w.key)
        text("dp_nr_lw_title", "Sector Laws: " .. w.key .. " (" .. table.getn(view.enacted) .. " of " .. L.SECTOR_MAX .. ")")
        local a, b = Laws.vote_line(d, w.key)
        text("dp_nr_lw_sub", a and (a .. ", " .. b) or "Its member worlds vote on laws of their own from time to time.")
        tip("dp_nr_lw_sub", sector_rule(L))
        local function backers(r)
            local pro, con = {}, {}
            for _, x in ipairs(r.backers) do
                table.insert((x[1] > 0) and pro or con, x[2])
            end
            return pro, con
        end
        for _, r in ipairs(view.enacted) do
            local pro, con = backers(r)
            table.insert(rows, {def = r.def, state = "In force since week " .. Laws.week_number(r.since), pro = pro, con = con,
                                share = r.share, active = true})
        end
        for _, r in ipairs(view.possible) do
            local pro, con = backers(r)
            local voting = view.vote and view.vote.law == r.def.key
            table.insert(rows, {def = r.def, state = voting and ("Voting: " .. view.vote.share .. "%")
                or ((r.share > 0) and ("Backed by " .. r.share .. "%") or "No backers"), pro = pro, con = con, dim = r.share == 0})
        end
    else
        local planet = FindPlanet(w.key)
        local view = Laws.planet_view(d, w.key)
        text("dp_nr_lw_title", "Planetary Laws: " .. (planet and d:planet_name(planet) or w.key) .. " ("
            .. table.getn(view.enacted) .. " of " .. L.PLANET_MAX .. ")")
        text("dp_nr_lw_sub", "Its strongest party passes the laws it backs and repeals those it opposes.")
        tip("dp_nr_lw_sub", planet_rule(L))
        for _, r in ipairs(view.enacted) do
            table.insert(rows, {def = r.def, state = "In force since week " .. Laws.week_number(r.since), pro = r.pro, con = r.con,
                                active = true})
        end
        for _, r in ipairs(view.possible) do
            if r.pro[1] then
                table.insert(rows, {def = r.def, state = "Possible", pro = r.pro, con = r.con})
            end
        end
    end
    local active, possible = {}, {}
    for _, r in ipairs(rows) do
        table.insert(r.active and active or possible, r)
    end
    if not Window.law_cat then
        Window.law_cat = active[1] and "active" or "possible"
    end
    for k, cat in ipairs({"active", "possible"}) do
        local n = table.getn((cat == "active") and active or possible)
        local on = Window.law_cat == cat
        text("dp_nr_lw_cat" .. k, ((cat == "active") and "In Force (" or "Possible (") .. n .. ")")
        icon("dp_nr_lw_cat" .. k, on and "dp_nr_btn_cat_on.tga" or "dp_nr_btn_cat.tga")
        tip("dp_nr_lw_cat" .. k, (cat == "active") and "The laws in force here." or "The laws that could pass here.")
    end
    local order = {}
    for i, r in ipairs(possible) do
        order[r] = i + (r.dim and 1000 or 0)
    end
    table.sort(possible, function(a, b) return order[a] < order[b] end)
    rows = (Window.law_cat == "active") and active or possible
    local per = LAYOUT.law_rows
    local pages = M.max(1, M.ceil(table.getn(rows) / per))
    Window.law_page = M.max(1, M.min(Window.law_page or 1, pages))
    for k = 1, per do
        local r = rows[(Window.law_page - 1) * per + k]
        for _, p in ipairs({"n", "t", "e", "f", "b"}) do
            show("dp_nr_lw_" .. p .. k, r ~= nil)
        end
        if r then
            local e1, e2 = two_lines(r.def.short, (ROOM["dp_nr_lw_e" .. k] or {456})[1] - 8)
            text("dp_nr_lw_n" .. k, r.def.name)
            color("dp_nr_lw_n" .. k, r.dim and GREY_C or GOLD_C)
            text("dp_nr_lw_t" .. k, r.state)
            text("dp_nr_lw_e" .. k, e1)
            text("dp_nr_lw_f" .. k, e2)
            text("dp_nr_lw_b" .. k, "For: " .. names(r.pro) .. ".  Against: " .. names(r.con) .. ".")
            local how = (w.kind == "sector") and " (A sector law: voted by the sector's own member worlds.)"
                or " (A planetary law: passed or repealed by the world's strongest party.)"
            for _, p in ipairs({"n", "t", "e", "f"}) do
                tip("dp_nr_lw_" .. p .. k, r.def.name .. ": " .. r.def.text .. how)
            end
            tip("dp_nr_lw_b" .. k, "For: " .. names(r.pro) .. ". Against: " .. names(r.con) .. ".")
        end
    end
    if not rows[1] then
        show("dp_nr_lw_n1", true)
        text("dp_nr_lw_n1", (Window.law_cat == "active") and "No law is in force here." or "No other law could pass here now.")
        color("dp_nr_lw_n1", GREY_C)
        tip("dp_nr_lw_n1", " ")
    end
    show("dp_nr_lw_prev", pages > 1)
    show("dp_nr_lw_next", pages > 1)
    show("dp_nr_lw_page", pages > 1)
    text("dp_nr_lw_page", Window.law_page .. "/" .. pages)
    tip("dp_nr_lw_prev", "The previous page.")
    tip("dp_nr_lw_next", "The next page.")
    tip("dp_nr_lw_page", "Laws in force first, then those that could pass.")
    text("dp_nr_lw_back", "Back")
    tip("dp_nr_lw_back", (w.kind == "sector") and "Back to the sectors' list." or "Back to the world's details.")
end

function Window.render(d)
    if not (d and d.republic) then
        return
    end
    render_header(d)
    render_footer(d)
    for tab, shells in pairs(BODY) do
        if tab ~= Window.tab then
            for _, shell in ipairs(shells) do
                local used = false
                for _, mine in ipairs(BODY[Window.tab] or {}) do
                    used = used or mine == shell
                end
                if not used then
                    show(shell, false)
                end
            end
        end
    end
    local laws_on = Window.laws ~= nil and ((Window.laws.kind == "sector" and Window.tab == "taxes")
        or (Window.laws.kind == "planet" and Window.tab == "members"))
    if Window.tab ~= "jedi" then
        for _, shell in ipairs(BODY[Window.tab] or {}) do
            show(shell, not (laws_on and shell == "dp_nr_mdet_shell"))
        end
    end
    local ok, err = true, nil
    if Window.tab == "members" then
        ok, err = pcall(render_members, d)
    elseif Window.tab == "taxes" then
        ok, err = pcall(render_taxes, d)
    elseif Window.tab == "government" then
        show("dp_nr_vote_shell", true)
        ok, err = pcall(render_government, d)
    elseif Window.tab == "intelligence" then
        ok, err = pcall(render_intel, d)
    elseif Window.tab == "jedi" then
        ok, err = pcall(render_jedi, d)
    end
    pcall(render_jedi_header, d, Window.tab == "jedi" and jedi_mode(d))
    show(LAW_SHELL, laws_on)
    if laws_on then
        local ok_l, err_l = pcall(render_laws, d)
        if not ok_l and Engine_Log then
            Engine_Log("REPUBLIC WINDOW laws error: " .. tostring(err_l))
        end
    end
    if not ok and Engine_Log then
        Engine_Log("REPUBLIC WINDOW page error: " .. tostring(err))
    end
    finish_tips()
end

local function mouse()
    local mx, my, down, wheel = Engine_Mouse()
    local w, h = Engine_Screen_Size()
    if not h or h <= 0 then
        return nil
    end
    local scale = h / 768
    return (mx - w / 2) / scale, (h / 2 - my) / scale, down, wheel
end

local function bar_drag(x, y, down, wheel, bar)
    local top, segs, seg = bar.top, bar.segs, bar.seg
    if wheel and wheel ~= 0 and bar.over(x, y) and not Window[bar.flag] then
        local v = M.min(bar.max, M.max(0, bar.get() - M.round(wheel * 2)))
        if v ~= bar.get() then
            bar.set(v)
            Window.render(Window.d)
        end
    end
    if down ~= 1 then
        Window[bar.flag] = false
        return
    end
    if not Window.was_down then
        Window[bar.flag] = M.abs(x - bar.x) <= 10 and y <= top and y >= top - segs * seg
    end
    if not Window[bar.flag] then
        return
    end
    local len = bar.len or 24
    local share = M.min(1, M.max(0, (top - y - len / 2) / M.max(1, segs * seg - len)))
    bar.share(share)
    local v = M.round(share * bar.max)
    if v ~= bar.get() then
        bar.set(v)
        Window.render(Window.d)
    end
    bar.draw()
end

function Window.tick()
    if not (Window.open_now and Engine_Mouse and Engine_Screen_Size) then
        return
    end
    local x, y, down, wheel = mouse()
    if not x then
        return
    end
    local p = Window.coh_pulse
    if p and Engine_Ticks then
        local frame = PULSE[M.floor(Engine_Ticks() / 120) - M.floor(Engine_Ticks() / 960) * 8 + 1]
        Window.pulse = true
        icon(p.name, (frame == 0) and (p.base .. (p.rim and "_t" or "") .. ".tga") or (p.base .. "_w" .. frame .. ".tga"))
    end
    if (Window.tab == "members" or Window.tab == "taxes") and (Window.cmax or 0) > 0 then
        bar_drag(x, y, down, wheel, {top = LAYOUT.col_top + 9, segs = LAYOUT.col_segs, seg = LAYOUT.col_seg,
            x = (Window.tab == "taxes") and LAYOUT.col_bar_right or LAYOUT.col_bar_x, max = Window.cmax,
            flag = "cdragging", len = Window.cthumb,
            over = function(px, py) return px > -484 and px < 484 and py < LAYOUT.col_top + 20 and py > -170 end,
            get = function() return Window.scroll or 0 end, set = function(v) Window.scroll = v end,
            share = function(v) Window.cshare = v end, draw = draw_col_thumb})
    end
    local listing = Window.tab == "intelligence" or (Window.tab == "government" and Window.pick)
    if listing and (Window.lmax or 0) > 0 then
        bar_drag(x, y, down, wheel, {top = LAYOUT.list_top, segs = LAYOUT.list_segs, seg = LAYOUT.list_seg,
            x = LAYOUT.list_bar_x, max = Window.lmax, flag = "ldragging", len = Window.lthumb,
            over = function(px, py) return px > -478 and px < LAYOUT.list_bar_x + 12 and py < LAYOUT.list_top + 20
                and py > LAYOUT.list_top - LAYOUT.list_segs * LAYOUT.list_seg - 20 end,
            get = function() return (Window.page or 1) - 1 end, set = function(v) Window.page = v + 1 end,
            share = function(v) Window.lshare = v end, draw = draw_list_thumb})
    end
    if Window.tab == "intelligence" and (Window.wmax or 0) > 0 then
        bar_drag(x, y, down, wheel, {top = LAYOUT.world_top, segs = LAYOUT.world_segs, seg = 4, x = 466,
            max = Window.wmax, flag = "wdragging", len = Window.wthumb,
            over = function(px, py) return px > 34 and px < 484 and py < LAYOUT.world_top + 20
                and py > LAYOUT.world_top - LAYOUT.world_segs * 4 - 20 end,
            get = function() return Window.wscroll or 0 end, set = function(v) Window.wscroll = v end,
            share = function(v) Window.wshare = v end, draw = draw_world_thumb})
    end
    if Window.tab == "jedi" and jedi_mode(Window.d) and JW.tick(x, y, down, wheel) then
        Window.render(Window.d)
    end
    Window.was_down = down == 1
end

function Window.open_member(d, world)
    Window.view = "members"
    Window.sel.members = world
    Window.open(d, "members")
end

function Window.open(d, tab)
    Window.d = d
    Window.open_now = true
    Window.tab = tab or Window.tab or "members"
    if Window.tab == "chamber" then
        Window.tab = "members"
    end
    if tab_closed(d, Window.tab) then
        Window.tab = council(d) and "intelligence" or "members"
    end
    Window.feedback = nil
    for key, _ in pairs(cache) do
        cache[key] = {}
    end
    show("dp_nr_shell", true)
    Window.render(d)
    Pause.hold("republic")
    if Engine_Wheel_Capture then
        Engine_Wheel_Capture(1)
    end
    if Engine_Gui_Tick then
        Engine_Gui_Tick(1)
    end
    if Engine_Screen_Text then
        Engine_Screen_Text(0)
    end
end

function Window.reset_view()
    Window.sel, Window.scroll, Window.page, Window.wscroll, Window.pick = {}, 0, 1, 0, nil
    Window.laws, Window.law_page = nil, 1
    Window.petition = 1
    IW.reset()
    if JW then
        JW.reset()
    end
end

function Window.close()
    for _, shell in ipairs(SHELLS) do
        show(shell, false)
    end
    if Window.open_now then
        Pause.release("republic")
        if Engine_Wheel_Capture then
            Engine_Wheel_Capture(0)
        end
        local Diplomacy_Window = optional("eawx-plugins/diplomacy/DiplomacyWindow")
        if Engine_Gui_Tick and not (Diplomacy_Window and (Diplomacy_Window.open_now or Diplomacy_Window.tick_hold
                or Diplomacy_Window.flash_hold)) then
            Engine_Gui_Tick(0)
        end
        if Engine_Screen_Text then
            Engine_Screen_Text(1)
        end
    end
    Window.open_now = false
    Window.feedback = nil
    Window.reset_view()
end

function Window.update(d)
    local queued = Window.deferred
    Window.deferred = {}
    for _, fn in ipairs(queued) do
        local ok, err = pcall(fn)
        if not ok and Engine_Log then
            Engine_Log("REPUBLIC WINDOW deferred: " .. tostring(err))
        end
    end
    if Window.open_now and GetCurrentTime() >= (Window.next_refresh or 0) then
        Window.next_refresh = GetCurrentTime() + 3
        Window.render(d)
    end
end

local function propose(d, motion)
    local Senate = Republic.senate
    if not Senate then
        return false, "The Senate is not in session."
    end
    return Senate.propose_from_window(d, motion)
end

local function act(d, a)
    local kind = a[1]
    if kind == "map" then
        show_on_map(a[2])
        return nil
    elseif kind == "planet_info" then
        if not (Engine_Planet_Info and Engine_Planet_Info(a[2])) then
            return "The planet's information cannot be opened."
        end
        return nil
    elseif kind == "tax" then
        local S = part("sectors")
        local ok, why = propose(d, S.motion(d, a[2], a[3]))
        Window.go_chamber = ok
        return ok and "The tax motion is before the chamber." or why
    elseif kind == "pay" then
        local _, why = part("members").pay(d, a[2])
        return why
    elseif kind == "talks" then
        local Missions = optional("eawx-plugins/diplomacy/DiplomacyMissions")
        local _, why = Missions.begin_talks(d, a[2])
        return why
    elseif kind == "end_protection" then
        local _, why = part("prot").withdraw(d, a[2])
        Window.sel.members = nil
        return why
    elseif kind == "petition" then
        local planet = FindPlanet(a[2])
        local name = planet and d:planet_name(planet) or a[2]
        local ok, why = propose(d, {kind = "ADMIT_ASSOCIATE", world = a[2], petition = true, target = "INDEPENDENT_FORCES",
            text = "make " .. name .. " an associate world", label = name})
        return ok and "The petition is before the chamber." or why
    elseif kind == "admit" then
        local planet = FindPlanet(a[2])
        local name = planet and d:planet_name(planet) or a[2]
        local ok, why = propose(d, {kind = "ADMIT_MEMBER", world = a[2], target = "INDEPENDENT_FORCES",
            text = "admit " .. name .. " as a member world", label = name})
        return ok and "The motion is before the chamber." or why
    elseif kind == "crisis" then
        local _, why = part("events").choose(d, a[2])
        return why
    elseif kind == "jedi_crisis" then
        return require("eawx-plugins/jedi-order/JediOrder").choose_crisis(d, a[2])
    elseif kind == "pick" then
        local open, why = part("gov").can_appoint(d, a[2])
        if not open then
            return why
        end
        Window.pick, Window.page = a[2], 1
        return nil
    elseif kind == "law_veto" then
        local _, why = part("laws").veto(d, a[2])
        return why
    elseif kind == "law_ack" then
        part("laws").ack_vote(d, a[2])
        return nil
    elseif kind == "law_news" then
        part("laws").acknowledge(d, a[2])
        return nil
    elseif kind == "laws_open" then
        local tab = (a[2] == "sector") and "taxes" or "members"
        if Window.laws and Window.laws.kind == a[2] and Window.laws.key == a[3] and Window.tab == tab then
            Window.laws = nil
            return nil
        end
        if Window.tab ~= tab then
            Window.reset_view()
            Window.tab = tab
        end
        if tab == "members" then
            Window.view, Window.sel.members = "members", a[3]
        else
            Window.sel.taxes = a[3]
        end
        Window.laws, Window.law_page, Window.scroll, Window.law_cat = {kind = a[2], key = a[3]}, 1, 0, nil
        return nil
    elseif kind == "ack_news" then
        part("parties").acknowledge(d, a[2])
        return nil
    elseif kind == "news_world" then
        Window.reset_view()
        Window.tab, Window.view, Window.sel.members = "members", "members", a[2]
        return nil
    elseif kind == "dismiss" then
        local _, why = part("gov").dismiss(d, a[2])
        return why
    end
    return nil
end

local function run(d, a)
    Window.go_chamber = nil
    local ok, message = pcall(act, d, a)
    if not ok and Engine_Log then
        Engine_Log("REPUBLIC WINDOW act error: " .. tostring(message))
    end
    if ok and Window.go_chamber then
        Window.go_chamber = nil
        local Senate = optional("eawx-plugins/diplomacy/DiplomacySenateWindow")
        if Senate then
            Window.close()
            Senate.open(d)
        end
    end
    if not ok then
        return "That did not work."
    end
    return message
end

function Window.click(d, name, button)
    if Engine_Log then
        Engine_Log("REPUBLIC WINDOW " .. tostring(button) .. " click " .. tostring(name))
    end
    if name == "dp_nr_close" then
        Window.close()
        if council(d) then
            local Senate = optional("eawx-plugins/diplomacy/DiplomacySenateWindow")
            if Senate then
                Senate.open(d)
            end
        end
        return
    end
    if not Window.open_now then
        return
    end
    local on_jedi = Window.tab == "jedi" and jedi_mode(d)
    if button == "right" then
        if on_jedi and JW.dismiss() then
            Window.render(d)
        end
        return
    end
    Window.d = d
    Window.feedback = nil
    local Intel = require("eawx-plugins/new-republic/RepublicIntel")
    local s = Intel.state(d)
    if on_jedi and (string.find(name, "^dp_nr_jt") or name == "dp_nr_shield") then
        local message, world = JW.click(d, jedi_state(d), name)
        Window.feedback = message
        if not JW.quiet and Engine_Play_Sound then
            pcall(Engine_Play_Sound, "GUI_Button_Press_2_SFX")
        end
        if world then
            show_on_map(world)
            return
        end
        Window.render(d)
        return
    end
    if on_jedi then
        JW.dismiss()
    end
    local _, _, tab = string.find(name, "^dp_nr_tab_(%a+)$")
    local _, _, side, row, rpart = string.find(name, "^dp_nr_([lr])(%d+)(.*)$")
    local _, _, lrow = string.find(name, "^dp_nr_il_r(%d+)")
    local _, _, action = string.find(name, "^dp_nr_id_a(%d+)$")
    local _, _, tool = string.find(name, "^dp_nr_il_tool(%d+)$")
    local _, _, line = string.find(name, "^dp_nr_id_l(%d+)_hit$")
    local _, _, wrow, wpart = string.find(name, "^dp_nr_id_w(%d+)_(%a+)$")
    local _, _, ctx = string.find(name, "^dp_nr_ctx(%d+)$")
    local _, _, mda = string.find(name, "^dp_nr_md_a(%d+)$")
    local _, _, plob = string.find(name, "^dp_nr_md_plob(%d+)$")
    local _, _, tg = string.find(name, "^dp_nr_tg(%d+)$")
    local _, _, ft = string.find(name, "^dp_nr_ft(%d+)$")
    local _, _, seat = string.find(name, "^dp_nr_gv_s(%d+)")
    local _, _, gva = string.find(name, "^dp_nr_gv_a(%d+)$")
    local _, _, back = string.find(name, "^dp_nr_ev_back(%d+)$")
    if tab then
        local closed = tab_closed(d, tab)
        if closed and tab ~= "chamber" then
            Window.feedback = closed
            Window.render(d)
            return
        end
        if tab == "chamber" then
            Window.close()
            local Senate = optional("eawx-plugins/diplomacy/DiplomacySenateWindow")
            if Senate then
                Senate.open(d)
            end
            return
        end
        Window.reset_view()
        Window.tab = tab
    elseif side and row then
        local r = Window.crow and Window.crow[side .. row]
        if r and rpart == "_zoom" and r.world then
            show_on_map(r.world)
            return
        elseif r and rpart == "_icon" and r.world and Window.tab == "taxes" then
            Window.reset_view()
            Window.tab, Window.view, Window.sel.members = "members", "members", r.world
        elseif r and r.key and r.key ~= "HEAD" then
            local k = (Window.tab == "taxes") and "taxes" or "members"
            Window.sel[k] = (Window.sel[k] ~= r.key) and r.key or nil
            if Window.laws then
                local key = Window.sel[k]
                local member = key and d.republic.seated and d.republic.seated[key]
                if key and (k == "taxes" or member) then
                    Window.laws.key, Window.law_page, Window.law_cat = key, 1, nil
                else
                    Window.laws = nil
                end
            end
        end
    elseif name == "dp_nr_c_up" or name == "dp_nr_r_up" then
        Window.scroll = M.max(0, (Window.scroll or 0) - 1)
    elseif name == "dp_nr_c_down" or name == "dp_nr_r_down" then
        Window.scroll = M.min(Window.cmax or 0, (Window.scroll or 0) + 1)
    elseif string.find(name, "^dp_nr_[cr]seg%d") then
        local _, _, k = string.find(name, "(%d+)$")
        Window.scroll = M.round((tonumber(k) - 1) * (Window.cmax or 0) / M.max(1, LAYOUT.col_segs - 1))
    elseif tg then
        local t = Window.toggles and Window.toggles[tonumber(tg)]
        if t then
            Window.view, Window.sel.members, Window.scroll = t.key, nil, 0
            Window.op_filter, Window.bloc_filter = 1, 1
        end
    elseif ft then
        local f = Window.filters and Window.filters[tonumber(ft)]
        if f and f.key == "op" then
            Window.op_filter = (Window.op_filter < table.getn(OPINION_FILTERS)) and Window.op_filter + 1 or 1
        elseif f and f.key == "bloc" then
            Window.bloc_filter = (Window.bloc_filter <= table.getn(blocs_present(d))) and Window.bloc_filter + 1 or 1
        end
        Window.scroll = 0
    elseif name == "dp_nr_md_zoom" and Window.md_world then
        show_on_map(Window.md_world)
        return
    elseif plob then
        local idx = Window.md_parties and Window.md_parties[tonumber(plob)]
        local Parties = part("parties")
        if idx and Parties and Window.sel.members then
            local _, why = Parties.lobby(d, Window.sel.members, idx)
            Window.feedback = why
        end
    elseif ctx or mda then
        local b = ctx and Window.ctx and Window.ctx[tonumber(ctx)] or (mda and Window.md_actions and Window.md_actions[tonumber(mda)])
        if b and b.off then
            Window.feedback = b.tip
        elseif b then
            Window.feedback = run(d, b.key)
            if not Window.open_now then
                return
            end
        end
    elseif lrow then
        local r = Window.rows and Window.rows[tonumber(lrow)]
        if r and r.key and r.key ~= "HEAD" then
            if Window.pick then
                local _, why = part("gov").appoint(d, Window.pick, r.key)
                Window.feedback, Window.pick = why, nil
            else
                IW.row_click(r.key)
                Window.wscroll = 0
            end
        end
    elseif tool then
        local t = Window.tools and Window.tools[tonumber(tool)]
        if t and t[4] then
            Window.feedback = t[3]
        elseif t and t[2] == "pick_cancel" then
            Window.pick = nil
        elseif t then
            local message, world
            message, world = IW.action(d, s, t[2], defer)
            Window.feedback = message
            if world then
                show_on_map(world)
                return
            end
        end
    elseif action then
        local a = Window.actions and Window.actions[tonumber(action)]
        if a and a[4] then
            Window.feedback = a[5] or a[3]
        elseif a then
            local message, world
            message, world = IW.action(d, s, a[2], defer)
            Window.feedback = message
            if world then
                show_on_map(world)
                return
            end
            Window.wscroll = 0
        end
    elseif line and Window.world_rows and Window.world_rows[tonumber(line)] then
        local w = Window.world_rows[tonumber(line)]
        if w.pick ~= nil then
            Window.feedback = IW.choose(d, s, w) or nil
            Window.wscroll = 0
        elseif w.world then
            show_on_map(w.world)
            return
        end
    elseif wrow then
        local w = Window.world_rows and Window.world_rows[tonumber(wrow)]
        if w and (wpart == "zoom" or wpart == "globe") and w.world then
            show_on_map(w.world)
            return
        elseif w and w.pick ~= nil then
            Window.feedback = IW.choose(d, s, w) or nil
            Window.wscroll = 0
        end
    elseif name == "dp_nr_id_w_up" then
        Window.wscroll = M.max(0, (Window.wscroll or 0) - 1)
    elseif name == "dp_nr_id_w_down" then
        Window.wscroll = (Window.wscroll or 0) + 1
    elseif string.find(name, "^dp_nr_id_wseg%d") then
        local _, _, k = string.find(name, "(%d+)$")
        Window.wscroll = M.round((tonumber(k) - 1) * (Window.wmax or 0) / M.max(1, LAYOUT.world_segs - 1))
    elseif name == "dp_nr_il_down" then
        Window.page = M.min((Window.lmax or 0) + 1, (Window.page or 1) + 1)
    elseif name == "dp_nr_il_up" then
        Window.page = M.max(1, (Window.page or 1) - 1)
    elseif string.find(name, "^dp_nr_il_seg%d") then
        local _, _, k = string.find(name, "(%d+)$")
        Window.page = 1 + M.round((tonumber(k) - 1) * (Window.lmax or 0) / M.max(1, LAYOUT.list_segs - 1))
    elseif name == "dp_nr_il_box" then
        IW.box_click()
        Window.page = 1
    elseif seat then
        local o = Window.offices and Window.offices[tonumber(seat)]
        if o then
            Window.sel.government = (Window.sel.government ~= o.key) and o.key or nil
        end
    elseif gva then
        local b = Window.gov_buttons and Window.gov_buttons[tonumber(gva)]
        if b and b.off then
            Window.feedback = b.tip
        elseif b then
            Window.feedback = run(d, b.key)
            if not Window.open_now then
                return
            end
        end
    elseif back then
        local c = Window.cands and Window.cands[tonumber(back)]
        if c and not c.backed then
            local _, why = part("gov").back(d, c.key)
            Window.feedback = why
        end
    elseif council(d) and (string.find(name, "^dp_nr_chief") or name == "dp_nr_stat_worlds"
            or name == "dp_nr_stat_treasury") then
        Window.feedback = tab_closed(d, "members")
    elseif string.find(name, "^dp_nr_chief") then
        Window.reset_view()
        Window.tab = "government"
    elseif name == "dp_nr_stat_worlds" then
        Window.reset_view()
        Window.tab = "members"
    elseif name == "dp_nr_stat_treasury" then
        Window.reset_view()
        Window.tab = "taxes"
    elseif name == "dp_nr_lw_back" then
        Window.laws = nil
    elseif name == "dp_nr_lw_cat1" or name == "dp_nr_lw_cat2" then
        Window.law_cat, Window.law_page = (name == "dp_nr_lw_cat1") and "active" or "possible", 1
    elseif name == "dp_nr_lw_prev" then
        Window.law_page = M.max(1, (Window.law_page or 1) - 1)
    elseif name == "dp_nr_lw_next" then
        Window.law_page = (Window.law_page or 1) + 1
    elseif name == "dp_nr_pet_clear" then
        local Parties = part("parties")
        for _, n in ipairs((Parties and Parties.news(d)) or {}) do
            Parties.acknowledge(d, n.id)
        end
        local Laws = part("laws")
        for _, n in ipairs((Laws and Laws.news(d)) or {}) do
            Laws.acknowledge(d, n.id)
        end
        Window.petition = 1
    elseif name == "dp_nr_pet_next" then
        Window.petition = Window.petition + 1
    elseif name == "dp_nr_pet_a" or name == "dp_nr_pet_b" then
        local p = Window.footer
        local choice = p and ((name == "dp_nr_pet_a") and p.a or p.b)
        if choice then
            Window.feedback = run(d, choice.key)
            if not Window.open_now then
                return
            end
        end
    end
    if Window.open_now then
        Window.render(d)
    end
end

return Window
