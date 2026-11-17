local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local Senate = require("eawx-plugins/diplomacy/DiplomacySenate")
local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
local Opinions = require("eawx-plugins/diplomacy/DiplomacyOpinions")

local function views_line(d, faction)
    local v = Opinions.views(faction, string.upper(d.human.Get_Faction_Name()), 3)
    local function names(list)
        local out = {}
        for _, e in ipairs(list) do
            table.insert(out, d.display_name(e[1]))
        end
        return table.concat(out, ", ")
    end
    local parts = {}
    if v.friends[1] then
        table.insert(parts, "friendly to " .. names(v.friends))
    end
    if v.foes[1] then
        table.insert(parts, "hostile to " .. names(v.foes))
    end
    return parts[1] and (" Their views: " .. table.concat(parts, "; ") .. ".") or ""
end
local FACTIONS = require("eawx-plugins/diplomacy/DiplomacyFactions")
local LAYOUT = require("eawx-plugins/diplomacy/DiplomacyWindowLayout")
local Speech = require("eawx-plugins/diplomacy/DiplomacySpeech")
local LEADERS = require("eawx-plugins/diplomacy/DiplomacyLeaders")
local GLOBES = require("eawx-plugins/diplomacy/DiplomacyGlobes")
local Worlds = require("eawx-plugins/diplomacy/DiplomacyWorlds")
local Pause = require("eawx-plugins/diplomacy/DiplomacyPause")
local Reputation = require("eawx-plugins/diplomacy/DiplomacyReputation")
require("eawx-plugins/diplomacy/DiplomacyAI")

local Window = {open_now = false, mode = "list", deal = {}, decree = false, page = 1, tab = "major", capital = {}}

local SHELLS = {"dp_dipl_shell", "dp_dipl_list_shell", "dp_dipl_deal_shell", "dp_dipl_pick_shell", "dp_dipl_items_shell",
    "dp_dipl_speech_o_shell", "dp_dipl_speech_i_shell", "dp_dipl_rel_shell", "dp_dipl_req_shell"}
local SPEECH_WIDTH = 36
local RELATION_TEXT = {WAR = "At war", CEASEFIRE = "At peace", ALLIANCE = "Allied", VASSAL = "Your vassal",
                       PROTECTORATE = "Protected"}

local Proposals = require("eawx-plugins/diplomacy/DiplomacyProposals")

local function protectorates()
    local ok, P = pcall(require, "eawx-plugins/new-republic/RepublicProtectorates")
    return ok and type(P) == "table" and P or nil
end
local REL_ROWS = {"war", "peace", "sub1", "sub2", "sub3"}

local function call(fn, ...)
    local ok, err = pcall(fn, unpack(arg))
    if not ok and Engine_Log then
        Engine_Log("DIPLOMACY WINDOW gui error: " .. tostring(err))
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

local function fit(line, most)
    line = line or ""
    if string.len(line) <= most then
        return line
    end
    return string.sub(line, 1, most - 3) .. "..."
end

local function text_color(name, grey)
    if grey then
        call(GUI_Text_Color, name, 0.45, 0.45, 0.48, 1)
    else
        call(GUI_Text_Color, name, 0.92, 0.82, 0.59, 1)
    end
end

local CRESTS = require("eawx-plugins/diplomacy/DiplomacyCrests")

local function emblem(faction)
    if Worlds.is_slot(faction) then
        faction = "INDEPENDENT_FORCES"
    end
    local key = string.upper(faction)
    local particle = Diplomacy and Diplomacy.crests and Diplomacy.crests[key]
    if not particle then
        local ok, C = pcall(ModContentLoader.get, "GameConstants")
        if ok and C and C.PARTICLES and type(C.PARTICLES[key]) == "string" then
            particle = string.lower(C.PARTICLES[key])
        end
    end
    if particle and CRESTS[particle] then
        return CRESTS[particle]
    end
    return "dp_emblem_" .. string.lower(faction) .. ".tga"
end
DIPLOMACY_EMBLEM = emblem

local function world_icon(faction)
    if not Worlds.is_slot(faction) then
        return nil
    end
    local player = Find_Player(faction)
    local planet = player and Worlds.world_of(player)
    return planet and (GLOBES[string.upper(planet.Get_Type().Get_Name())] or "dp_globe_unknown.tga") or nil
end
DIPLOMACY_WORLD_ICON = world_icon

local function row_icon(faction)
    return world_icon(faction) or emblem(faction)
end

local function ordinal(n)
    local last = n - 10 * M.floor(n / 10)
    local teen = n - 100 * M.floor(n / 100)
    if teen >= 11 and teen <= 13 then
        return n .. "th"
    end
    return n .. ((last == 1 and "st") or (last == 2 and "nd") or (last == 3 and "rd") or "th")
end

local function wealth_word(credits)
    if credits < 3000 then
        return "Meagre"
    elseif credits < 10000 then
        return "Modest"
    elseif credits < 25000 then
        return "Rich"
    end
    return "Spectacular"
end

local function by_worlds(a, b)
    if a.worlds ~= b.worlds then
        return a.worlds > b.worlds
    end
    return a.name < b.name
end

local function holding(d, names)
    local out = {}
    for _, name in ipairs(names) do
        local player = Find_Player(name)
        if player and player ~= d.human then
            local worlds = table.getn(Deals.worlds_of(player))
            if worlds > 0 then
                table.insert(out, {name = name, player = player, worlds = worlds})
            end
        end
    end
    table.sort(out, by_worlds)
    return out
end

local function power_names(d)
    local major, minor, warlords = {}, {}, {}
    for name, _ in pairs(FACTIONS.PLAYABLE) do
        table.insert(CONFIG.MINOR_POWERS[name] and minor or major, name)
    end
    for name, _ in pairs(FACTIONS.MINOR or {}) do
        table.insert(minor, name)
    end
    for name, _ in pairs(Diplomacy.warlord_factions()) do
        table.insert(warlords, name)
    end
    return major, minor, warlords
end

local function factions(d, ctx)
    local major, minor, warlords = power_names(d)
    local names = {}
    for _, list in ipairs({major, minor, warlords}) do
        for _, name in ipairs(list) do
            table.insert(names, name)
        end
    end
    return holding(d, names)
end

DIPLOMACY_CATEGORIES = function()
    local major, minor, warlords = power_names(nil)
    local independent = Worlds.names()
    table.insert(independent, "INDEPENDENT_FORCES")
    return {{"Major Powers", major}, {"Minor Powers", minor}, {"Minor Warlords", warlords},
            {"Independent Sectors", independent}, {"Petty Warlords", {"WARLORDS"}}}
end

local function powers_list(d)
    local major, minor, warlords = power_names(d)
    local out = {}
    for _, group in ipairs({{"Major Powers", holding(d, major)}, {"Minor Powers", holding(d, minor)},
                            {"Minor Warlords", holding(d, warlords)}}) do
        if table.getn(group[2]) > 0 then
            table.insert(out, {header = group[1]})
            for _, e in ipairs(group[2]) do
                table.insert(out, e)
            end
        end
    end
    return out
end

local function minor_factions(d)
    local independent, generic = {}, {}
    local p_independent, p_warlords = Find_Player("Independent_Forces"), Find_Player("Warlords")
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = planet.Get_Owner()
        if owner == p_independent or owner == p_warlords then
            local entry = {world = string.upper(planet.Get_Type().Get_Name()), label = d:planet_name(planet),
                           kind = (owner == p_independent) and "INDEPENDENT" or "WARLORDS"}
            table.insert((owner == p_independent) and independent or generic, entry)
        end
    end
    local by_label = function(a, b) return a.label < b.label end
    table.sort(independent, by_label)
    table.sort(generic, by_label)
    local out = {}
    local talking = holding(d, Worlds.names())
    if table.getn(independent) + table.getn(talking) > 0 then
        table.insert(out, {header = "Independent Sectors"})
        for _, e in ipairs(talking) do
            table.insert(out, e)
        end
        for _, e in ipairs(independent) do
            table.insert(out, e)
        end
    end
    if table.getn(generic) > 0 then
        table.insert(out, {header = "Petty Warlords"})
        for _, e in ipairs(generic) do
            table.insert(out, e)
        end
    end
    return out
end

local RULED_BY = {
    MANDALORIANS = {"Clan rule", "the clans answer to no single leader."},
    CORELLIA = {"Five Worlds rule", "the Five Worlds govern themselves."},
    KILLIK_HIVES = {"Hive mind", "the hives think and act as one."},
    CHISS = {"Ruling Families", "the Ruling Families govern the Ascendancy."},
    SSIRUUVI_IMPERIUM = {"The Shreeftut", "the Imperium answers to the Shreeftut."},
}

local function leader(d, player)
    local name = player.Get_Faction_Name()
    if name == "REBEL" then
        local chief = GlobalValue.Get("ChiefOfState") or "DUMMY_CHIEFOFSTATE_MOTHMA"
        return LEADERS.CHIEFS[string.upper(chief)]
    end
    local function owned(entry)
        local obj = Find_First_Object(entry.type)
        return TestValid(obj) and obj.Get_Owner() == player
    end
    if IMPERIAL_COURT_FACTION_LEADER then
        local ok, lord = pcall(IMPERIAL_COURT_FACTION_LEADER, name)
        if ok and lord then
            for _, entry in ipairs(LEADERS.WARLORDS and LEADERS.WARLORDS[d.display_name(name)] or {}) do
                if entry.name == lord.name then
                    return entry
                end
            end
            return lord
        end
    end
    local list = LEADERS.WARLORDS and LEADERS.WARLORDS[d.display_name(name)] or LEADERS[name] or {}
    for _, entry in ipairs(list) do
        if owned(entry) then
            return entry
        end
    end
    for _, entries in pairs(LEADERS.WARLORDS or {}) do
        for _, entry in ipairs(entries) do
            if owned(entry) then
                return entry
            end
        end
    end
    Window.hero_cache = Window.hero_cache or {}
    local cached = Window.hero_cache[name]
    if cached and GetCurrentTime() < cached.until_time and (not cached.entry or owned(cached.entry)) then
        return cached.entry
    end
    local best, value, rank = nil, -1, -1
    for _, obj in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(obj) then
            local type_name = string.upper(obj.Get_Type().Get_Name())
            local hero = LEADERS.HEROES and LEADERS.HEROES[type_name]
            local r = hero and (hero.rank or 2)
            if hero and (r > rank or (r == rank and hero.value > value)) then
                best, value, rank = {type = type_name, name = hero.name, icon = hero.icon}, hero.value, r
            end
        end
    end
    if not best and Diplomacy.warlord_factions()[name] and LEADERS.WARLORDS then
        local lore = LEADERS.WARLORDS[d.display_name(name)]
        best = lore and lore[1]
    end
    Window.hero_cache[name] = {entry = best, until_time = GetCurrentTime() + 30}
    return best
end

local function strength_rank(d, ctx, player, list)
    local mine = DiplomacyAI.strength(ctx, player)
    local rank, total = 1, 1
    for _, f in ipairs(list) do
        if f.player ~= player then
            total = total + 1
            if DiplomacyAI.strength(ctx, f.player) > mine then
                rank = rank + 1
            end
        end
    end
    if player ~= d.human then
        if DiplomacyAI.strength(ctx, d.human) > mine then
            rank = rank + 1
        end
        total = total + 1
    end
    return rank, total
end

local function sympathy_line(d, planet)
    if not (d.republic and planet) then
        return nil
    end
    local ok, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
    local key = string.upper(planet.Get_Type().Get_Name())
    if not (ok and Sym and Sym.value(d, key)) then
        return nil
    end
    local text = Sym.describe(d, key)
    return "Sympathy: " .. text, "Its people's sympathy for the " .. d.display_name("REBEL") .. ": " .. text
        .. ". Protection needs a Sympathetic world; hover over it in the Intelligence tab's Sympathy list for more."
end

local function fill_stats(p, stats, faction, tips)
    local rep_line = nil
    if faction == "?" then
        table.insert(stats, "Reputation: ?")
        faction = nil
    elseif faction then
        table.insert(stats, "Reputation: " .. Reputation.word(faction))
        rep_line = table.getn(stats)
    end
    for k = 1, LAYOUT.stats do
        local name = p .. "stat_" .. k
        text(name, stats[k] and fit(stats[k], 40))
        if k == rep_line then
            local c = Reputation.COLORS[Reputation.rank(faction)]
            call(GUI_Text_Color, name, c.r / 255, c.g / 255, c.b / 255, 1)
            tip(name, Reputation.describe(faction))
        else
            call(GUI_Text_Color, name, 215 / 255, 220 / 255, 230 / 255, 1)
            tip(name, (tips and tips[k]) or " ")
        end
    end
end

local function fill_side(d, ctx, side, player, list, att)
    local p = "dp_d_" .. side .. "_"
    local name = player.Get_Faction_Name()
    local human = player == d.human
    if not human and Deals.locked(d, name) then
        text(p .. "faction", fit(d.display_name(name), 24))
        icon(p .. "emblem", emblem(name))
        icon(p .. "emblem2", emblem(name))
        icon(p .. "portrait", emblem(name))
        tip(p .. "portrait", d.display_name(name) .. ": sealed away from the galaxy. Nothing is known of them.")
        text(p .. "leader", fit("Leader: ?", 32))
        show(p .. "capital_globe", false)
        show(p .. "zoom", false)
        Window.capital[side] = nil
        text(p .. "capital", fit("Capital: ?", 30))
        fill_stats(p, {"Worlds: ?", "Strength: ?", "Wealth: ?", "Attitude to you: ?"}, "?")
        for _, rel in ipairs(REL_ROWS) do
            text(p .. "rel_" .. rel, ({war = "At war:", peace = "At peace:"})[rel] or " ")
            for k = 1, LAYOUT.emblems do
                show(p .. rel .. "_" .. k, false)
            end
        end
        local notes = {"Sealed away from the galaxy:", "no envoy reaches them, no word comes out."}
        for k = 1, 3 do
            text(p .. "note_" .. k, notes[k] and fit(notes[k], 40))
        end
        text(p .. "foot", fit("Attitude towards you: ?", 38))
        return
    end
    text(p .. "faction", fit(d.display_name(name), 24))
    icon(p .. "emblem", emblem(name))
    icon(p .. "emblem2", emblem(name))
    local lead = leader(d, player)
    icon(p .. "portrait", lead and lead.icon or emblem(name))
    local ruled = RULED_BY[name]
    if Worlds.is_slot(name) then
        local world = Worlds.world_of(player)
        if world then
            icon(p .. "portrait", GLOBES[string.upper(world.Get_Type().Get_Name())] or "dp_globe_unknown.tga")
        end
        ruled = {"Planetary government", "an independent world that governs itself."}
    end
    text(p .. "leader", fit(lead and lead.name or (ruled and ruled[1]) or "No known leader", 32))
    tip(p .. "portrait", lead and (lead.name .. ", leader of " .. d.display_name(name) .. ".")
        or (ruled and (d.display_name(name) .. ": " .. ruled[2])) or d.display_name(name))
    local capital = Deals.capital(d, player)
    show(p .. "capital_globe", capital ~= nil)
    show(p .. "zoom", capital ~= nil)
    Window.capital[side] = capital and string.upper(capital.Get_Type().Get_Name())
    if capital then
        icon(p .. "capital_globe", GLOBES[string.upper(capital.Get_Type().Get_Name())] or "dp_globe_unknown.tga")
        text(p .. "capital", fit("Capital: " .. d:planet_name(capital), 30))
        tip(p .. "zoom", "Show " .. d:planet_name(capital) .. " on the galaxy map.")
        tip(p .. "capital", "Show " .. d:planet_name(capital) .. " on the galaxy map.")
    else
        text(p .. "capital", fit("No capital", 30))
    end
    local rank, total = strength_rank(d, ctx, player, list)
    local stats = {"Worlds: " .. table.getn(Deals.worlds_of(player)),
                   "Strength: " .. ordinal(rank) .. " of " .. total}
    local stat_tips = {}
    local att_tip = (not human) and Deals.attitude_tip(d, ctx, player) or nil
    if human then
        table.insert(stats, "Treasury: " .. M.floor(player.Get_Credits()) .. " credits")
        if d:senate_active() then
            local mandate = d.republic and d.republic.mandate and (", mandate " .. M.round(d.republic.mandate)) or ""
            table.insert(stats, "Cohesion " .. d.senate.stability .. "%" .. mandate)
        end
    else
        table.insert(stats, "Wealth: " .. wealth_word(player.Get_Credits()))
        table.insert(stats, "Attitude to you: " .. Deals.attitude_word(att) .. " (" .. d.signed(att) .. ")")
        stat_tips[table.getn(stats)] = att_tip
    end
    if Worlds.is_slot(name) then
        local line, line_tip = sympathy_line(d, Worlds.world_of(player))
        if line then
            table.insert(stats, line)
            stat_tips[table.getn(stats)] = line_tip
        end
    end
    fill_stats(p, stats, (not Worlds.is_slot(name)) and name or nil, stat_tips)
    local groups = {war = {}, peace = {}, ally = {}, vassal = {}, prot = {}}
    local warlords = Diplomacy.warlord_factions and Diplomacy.warlord_factions() or {}
    local function rank(faction)
        if FACTIONS.PLAYABLE[faction] then
            return 1
        elseif (FACTIONS.MINOR or {})[faction] then
            return 2
        elseif warlords[faction] then
            return 3
        end
        return 4
    end
    local function add(group, faction, not_selectable)
        table.insert(groups[group], {icon = row_icon(faction), tip = d.display_name(faction), faction = faction,
                                     rank = rank(faction), not_selectable = not_selectable})
    end
    for _, f in ipairs(list) do
        if f.player ~= player then
            if human and d.relations[f.name] == "ALLIANCE" then
                add("ally", f.name)
            else
                add(player.Is_Enemy(f.player) and "war" or "peace", f.name)
            end
        end
    end
    if not human then
        local with_you = d:relation(string.upper(player.Get_Faction_Name()))
        add((with_you == "ALLIANCE") and "ally" or (player.Is_Enemy(d.human) and "war" or "peace"),
            d.human.Get_Faction_Name())
    else
        local listed = {}
        for _, f in ipairs(list) do
            listed[f.name] = true
        end
        local republic = d.human.Get_Faction_Name() == "REBEL"
        for faction, relation in pairs(d.relations) do
            if relation == "PROTECTORATE" or (relation == "VASSAL" and not republic) then
                add("prot", faction)
            elseif relation == "VASSAL" then
                add("vassal", faction)
            elseif relation == "ALLIANCE" and not listed[faction] then
                add("ally", faction)
            end
        end
        local vassals = d:vassal_player()
        if vassals and table.getn(Deals.worlds_of(vassals)) > 0 then
            add(republic and "vassal" or "prot", vassals.Get_Faction_Name(), true)
        end
    end
    local republic = d.human.Get_Faction_Name() == "REBEL"
    local used, most = Worlds.capacity(d)
    local subs = {}
    if table.getn(groups.ally) > 0 then
        table.insert(subs, {group = groups.ally, label = "Allies:"})
    end
    if human and table.getn(groups.vassal) > 0 then
        table.insert(subs, {group = groups.vassal, label = "Vassals:"})
    end
    if human and (table.getn(groups.prot) > 0 or used > 0) then
        table.insert(subs, {group = groups.prot, label = republic and "Protected:" or "Vassals:", tip = (republic and "Protectorates" or "Vassal worlds") .. ": " .. used .. " of the " .. most
            .. " independent worlds you can hold talks or treaties with at once."})
    end
    groups.sub1, groups.sub2 = (subs[1] and subs[1].group) or {}, (subs[2] and subs[2].group) or {}
    groups.sub3 = (subs[3] and subs[3].group) or {}
    local labels = {war = "At war:", peace = "At peace:", sub1 = subs[1] and subs[1].label or " ",
                    sub2 = subs[2] and subs[2].label or " ", sub3 = subs[3] and subs[3].label or " "}
    Window.emblem_targets = Window.emblem_targets or {}
    local label_tips = {sub1 = subs[1] and subs[1].tip, sub2 = subs[2] and subs[2].tip, sub3 = subs[3] and subs[3].tip}
    for _, rel in ipairs(REL_ROWS) do
        text(p .. "rel_" .. rel, labels[rel])
        tip(p .. "rel_" .. rel, label_tips[rel] or labels[rel])
        local group = groups[rel]
        for i, f in ipairs(group) do
            f.order = i
        end
        table.sort(group, function(a, b)
            if a.rank ~= b.rank then
                return a.rank < b.rank
            end
            return a.order < b.order
        end)
        local room = (rel == "sub1" or rel == "sub2" or rel == "sub3") and LAYOUT.emblems_vassal or LAYOUT.emblems
        local shown = (table.getn(group) > room) and (room - 1) or table.getn(group)
        for k = 1, LAYOUT.emblems do
            local f = group[k]
            local slot = p .. rel .. "_" .. k
            Window.emblem_targets[slot] = nil
            if k <= shown then
                show(slot, true)
                icon(slot, f.icon)
                tip(slot, f.tip)
                Window.emblem_targets[slot] = (not f.not_selectable) and f.faction or nil
            elseif k == shown + 1 and k <= room and table.getn(group) > room then
                local cut = {}
                for n = shown + 1, table.getn(group) do
                    table.insert(cut, group[n].tip)
                end
                show(slot, true)
                icon(slot, "dp_more.tga")
                tip(slot, "+ " .. table.getn(cut) .. " factions: " .. table.concat(cut, ", ") .. ".")
            else
                show(slot, false)
            end
        end
    end
    local notes = {}
    if human then
        if d:senate_active() then
            for target, relation in pairs(d.senate.mandates) do
                table.insert(notes, "Mandate: " .. ((relation == "ALLIANCE") and "alliance with " or "peace talks with ")
                    .. d.display_name(target) .. ".")
            end
        end
    else
        local relation = d:relation(name)
        table.insert(notes, "Treaty with you: " .. string.lower(RELATION_TEXT[relation] or relation) .. ".")
        local Trade = require("eawx-plugins/diplomacy/DiplomacyTrade")
        if Trade.partner(d, name) then
            local ours, theirs = Trade.value(d, name)
            table.insert(notes, "Trade agreement: +" .. ours .. " a week to you, +" .. theirs .. " to them.")
        end
        if Deals.pact_active(d, name) then
            table.insert(notes, "Non-aggression pact: " .. M.floor((d.pacts[name] - GetCurrentTime()) / CONFIG.WEEK_SECONDS + 0.999)
                .. " weeks left.")
        end
    end
    for _, t in ipairs(d.tributes or {}) do
        if (human and (t.payer == name or t.payee == name)) or (not human and (t.payer == name or t.payee == name)) then
            table.insert(notes, "Tribute: " .. t.amount .. " a week to " .. d.display_name(t.payee) .. ", " .. t.left .. " weeks.")
        end
    end
    for k = 1, 3 do
        text(p .. "note_" .. k, notes[k] and fit(notes[k], 40))
    end
    text(p .. "foot", fit(human and "Your faction" or ("Attitude towards you: " .. Deals.attitude_word(att)), 38))
    tip(p .. "foot", att_tip or " ")
end

local function hide_side(side)
    local p = "dp_d_" .. side .. "_"
    for _, part in ipairs({"faction", "portrait", "emblem", "emblem2", "leader", "capital_globe", "zoom", "capital", "foot"}) do
        show(p .. part, false)
    end
    for k = 1, LAYOUT.stats do
        show(p .. "stat_" .. k, false)
    end
    for _, rel in ipairs(REL_ROWS) do
        show(p .. "rel_" .. rel, false)
        for k = 1, LAYOUT.emblems do
            show(p .. rel .. "_" .. k, false)
        end
    end
    for k = 1, 3 do
        show(p .. "note_" .. k, false)
    end
end

local function show_side(side)
    local p = "dp_d_" .. side .. "_"
    for _, part in ipairs({"faction", "portrait", "emblem", "emblem2", "leader", "capital", "foot"}) do
        show(p .. part, true)
    end
    for k = 1, LAYOUT.stats do
        show(p .. "stat_" .. k, true)
    end
    for _, rel in ipairs(REL_ROWS) do
        show(p .. "rel_" .. rel, true)
    end
    for k = 1, 3 do
        show(p .. "note_" .. k, true)
    end
end

local function fill_world_side(d, ctx, entry)
    local p = "dp_d_r_"
    local independent = entry.kind == "INDEPENDENT"
    local owner = independent and "INDEPENDENT_FORCES" or "WARLORDS"
    local planet = FindPlanet(entry.world)
    local globe = GLOBES[entry.world] or "dp_globe_unknown.tga"
    text(p .. "faction", fit(entry.label, 24))
    icon(p .. "emblem", emblem(owner))
    icon(p .. "emblem2", emblem(owner))
    icon(p .. "portrait", globe)
    text(p .. "leader", fit(independent and "Planetary government" or "Petty warlords", 32))
    tip(p .. "portrait", entry.label .. (independent and ": an independent world that governs itself."
        or ": held by petty warlords who answer to no one."))
    show(p .. "capital_globe", true)
    show(p .. "zoom", planet ~= nil)
    icon(p .. "capital_globe", globe)
    text(p .. "capital", fit("Capital: " .. entry.label, 30))
    tip(p .. "zoom", "Show " .. entry.label .. " on the galaxy map.")
    tip(p .. "capital", "Show " .. entry.label .. " on the galaxy map.")
    Window.capital.r = entry.world
    local stats = {"Worlds: 1", "Held by: " .. d.display_name(owner)}
    local stat_tips = {}
    local att_tip = nil
    if independent and planet then
        local att = Deals.world_attitude(d, ctx, planet)
        table.insert(stats, "Attitude: " .. Deals.attitude_word(att) .. " (" .. d.signed(att) .. ")")
        att_tip = Deals.world_attitude_tip(d, ctx, planet)
        stat_tips[table.getn(stats)] = att_tip
        local total = DiplomacyAI.evaluate_world(ctx, d.human, planet, d.memory)
        table.insert(stats, "Wants your protection: " .. ((total >= 0) and "yes" or "no") .. " (" .. d.signed(total) .. ")")
        local line, line_tip = sympathy_line(d, planet)
        if line then
            table.insert(stats, line)
            stat_tips[table.getn(stats)] = line_tip
        end
    elseif not independent then
        table.insert(stats, "Hostile to all")
    end
    fill_stats(p, stats, nil, stat_tips)
    for _, rel in ipairs(REL_ROWS) do
        text(p .. "rel_" .. rel, " ")
        for k = 1, LAYOUT.emblems do
            show(p .. rel .. "_" .. k, false)
        end
    end
    local notes = independent and {"Open Negotiations to treat with it", "as a faction of its own."}
        or {"Petty warlords answer to no one", "and will not negotiate."}
    for k = 1, 3 do
        text(p .. "note_" .. k, notes[k] and fit(notes[k], 40))
    end
    text(p .. "foot", fit(independent and "Independent world" or "Held by minor warlords", 38))
    tip(p .. "foot", att_tip or " ")
end

local TAB_TIPS = {
    major = "The galaxy's powers: the great factions, then the minor powers (smaller states, the minor warlords and "
        .. "those who broke away from a court).",
    minor = "The minor factions: independent worlds, and the petty warlords' lone worlds left by the Empire's collapse.",
}

function Window.render_rows(d, ctx, list)
    Window.rows = {}
    Window.row_drawn = Window.row_drawn or {}
    for k = 1, LAYOUT.rows do
        local f = list[Window.scroll + k]
        local row = "dp_d_row_" .. k
        Window.rows[k] = (f and not f.header) and f or nil
        local key, draw = "none", nil
        if f and f.header then
            key = "h" .. f.header
            draw = function()
                text(row .. "_head", f.header)
            end
        elseif f and f.world then
            local independent = f.kind == "INDEPENDENT"
            local selected = Window.world and Window.world.world == f.world
            local att = independent and Deals.world_attitude(d, ctx, FindPlanet(f.world)) or nil
            key = "w" .. f.world .. "|" .. tostring(att) .. (selected and "*" or "")
            draw = function()
                icon(row, selected and "dp_row_sel.tga" or "dp_row.tga")
                icon(row .. "_emblem", GLOBES[f.world] or "dp_globe_unknown.tga")
                text(row, " ")
                text(row .. "_name", f.label)
                text(row .. "_rel", independent and "Independent" or "Warlord")
                text(row .. "_att", att and (Deals.attitude_word(att) .. " (" .. d.signed(att) .. ")") or "Hostile")
                text(row .. "_worlds", "1")
                local why = independent and Deals.world_attitude_tip(d, ctx, FindPlanet(f.world))
                    or "Hostile to all: petty warlords answer to no one."
                tip(row .. "_att", why)
                tip(row, f.label .. (independent and ": an independent world. Click to see it; Open Negotiations to treat with it."
                    or ": held by petty warlords who answer to no one and will not negotiate.") .. " " .. why)
            end
        elseif f then
            local att = Deals.attitude(d, ctx, f.player)
            local relation = RELATION_TEXT[d:relation(f.name)] or ""
            local sealed = Deals.locked(d, f.name)
            key = "f" .. f.name .. "|" .. relation .. "|" .. att .. "|" .. f.worlds .. ((f.name == Window.target) and "*" or "")
                .. (sealed and "?" or "")
            draw = function()
                icon(row .. "_emblem", row_icon(f.name))
                text(row, " ")
                text(row .. "_name", d.display_name(f.name))
                text(row .. "_rel", relation)
                text(row .. "_att", sealed and "?" or (Deals.attitude_word(att) .. " (" .. d.signed(att) .. ")"))
                text(row .. "_worlds", sealed and "?" or ("" .. f.worlds))
                icon(row, (f.name == Window.target) and "dp_row_sel.tga" or "dp_row.tga")
                local why = sealed and "Nothing is known of them yet." or Deals.attitude_tip(d, ctx, f.player)
                tip(row .. "_att", why)
                tip(row, d.display_name(f.name) .. ": " .. relation .. ". " .. why
                    .. (sealed and "" or views_line(d, f.name))
                    .. " Click to see them; Open Negotiations to make an offer.")
            end
        end
        if Window.row_drawn[k] ~= key then
            Window.row_drawn[k] = key
            local kind = string.sub(key, 1, 1)
            for _, part in ipairs({"", "_name", "_rel", "_att", "_worlds"}) do
                show(row .. part, kind == "w" or kind == "f")
            end
            show(row .. "_emblem", kind == "f" or kind == "w")
            show(row .. "_head", kind == "h")
            show(row .. "_line", kind == "h")
            if draw then
                draw()
            end
        end
    end
end

local function render_list(d, ctx, list)
    show("dp_d_list_head", false)
    text("dp_d_col_name", "Faction")
    text("dp_d_col_rel", "Treaty")
    text("dp_d_col_att", "Attitude")
    text("dp_d_col_worlds", "Worlds")
    local total = table.getn(list)
    local max_offset = M.max(0, total - LAYOUT.rows)
    Window.max_scroll = max_offset
    Window.scroll = M.min(M.max(0, Window.scroll or 0), max_offset)
    local scrolling = max_offset > 0
    show("dp_d_scroll_up", scrolling)
    show("dp_d_scroll_down", scrolling)
    if scrolling then
        tip("dp_d_scroll_up", "Scroll up.")
        tip("dp_d_scroll_down", "Scroll down.")
    end
    if Window.scroll_shown ~= scrolling then
        Window.scroll_shown, Window.seg_lit = scrolling, {}
        for k = 1, LAYOUT.scroll_segs do
            show("dp_d_scroll_" .. k, scrolling)
        end
    end
    if scrolling then
        Window.thumb_len = M.max(24, LAYOUT.scroll_segs * LAYOUT.scroll_seg * LAYOUT.rows / total)
        if Window.seg_tip ~= total then
            Window.seg_tip = total
            for k = 1, LAYOUT.scroll_segs do
                tip("dp_d_scroll_" .. k, "Drag or click to scroll (" .. total .. " entries).")
            end
        end
        Window.draw_thumb()
    end
    Window.row_drawn = {}
    Window.list_cache, Window.ctx_cache = list, ctx
    Window.render_rows(d, ctx, list)
    local bond = Window.target and require("eawx-plugins/diplomacy/DiplomacyAllies").bond(d, Window.target)
    local open = bond and "dp_d_open" or "dp_d_open_c"
    show("dp_d_open", bond and true or false)
    show("dp_d_requests", bond and true or false)
    show("dp_d_open_c", not bond)
    text(open, "Open Negotiations")
    local closed = true
    if Window.world and Window.world.kind == "INDEPENDENT" then
        tip(open, "Negotiate with " .. Window.world.label .. ": it treats with you as a faction of its own.")
        closed = false
    elseif Window.world then
        tip(open, Window.world.label .. " is held by minor warlords. They will not negotiate.")
    elseif Window.target and Diplomacy.refuses_talks(Window.target, d.human) then
        tip(open, d.display_name(Window.target) .. " will not negotiate: they answer only to the Galactic Empire.")
    elseif Window.target and Deals.locked(d, Window.target) then
        tip(open, d.display_name(Window.target) .. " is sealed away from the galaxy: no envoy can reach them.")
    else
        tip(open, Window.target and ("Negotiate with " .. d.display_name(Window.target) .. ".") or "Select a faction first.")
        closed = Window.target == nil
    end
    icon(open, closed and "dp_btn_off.tga" or "dp_btn.tga")
    text_color(open, closed)
    if bond then
        text("dp_d_requests", "Requests")
        icon("dp_d_requests", "dp_btn.tga")
        text_color("dp_d_requests", false)
        tip("dp_d_requests", "Ask " .. d.display_name(Window.target) .. " for help: a war target, a world to take, "
            .. "an escort for your fleet.")
    end
    text("dp_d_list_note", Window.feedback or "Select a faction to compare it with yours.")
end

local function has_item(kind, side, relation)
    for i, item in ipairs(Window.deal) do
        if item.kind == kind and (not side or item.side == side) and (not relation or item.relation == relation) then
            return i
        end
    end
    return nil
end

local SUBJECT = {VASSAL = true, PROTECTORATE = true}
local KEEPS_PEACE = {ALLIANCE = true, VASSAL = true, PROTECTORATE = true}

local function add_item(item)
    if item.kind == "PACT" then
        local i = has_item("TREATY")
        if i and KEEPS_PEACE[Window.deal[i].relation] then
            return
        end
    end
    if item.kind == "TREATY" then
        local i = has_item("TREATY")
        if i then
            table.remove(Window.deal, i)
        end
        if KEEPS_PEACE[item.relation] then
            for k = table.getn(Window.deal), 1, -1 do
                local other = Window.deal[k]
                if other.kind == "PACT" or (SUBJECT[item.relation] and other.kind == "BORDERS") then
                    table.remove(Window.deal, k)
                end
            end
        end
    elseif item.kind ~= "WORLD" then
        local i = has_item(item.kind, item.side)
        if i then
            return
        end
    end
    table.insert(Window.deal, item)
end

local function actions(d, target)
    local relation = d:relation(target)
    local steps = CONFIG.DEALS
    local list = {}
    if relation == "WAR" then
        table.insert(list, {key = "ceasefire", label = "Propose a Ceasefire", item = {kind = "TREATY", relation = "CEASEFIRE", side = "offer"}})
    elseif relation == "CEASEFIRE" then
        table.insert(list, {key = "alliance", label = "Propose an Alliance", item = {kind = "TREATY", relation = "ALLIANCE", side = "offer"}})
    end
    local P = protectorates()
    if d.human.Get_Faction_Name() == "REBEL" then
        if relation ~= "PROTECTORATE" and P and P.eligible(d, target) then
            table.insert(list, {key = "protect", label = "Offer Protection",
                item = {kind = "TREATY", relation = "PROTECTORATE", side = "offer"}})
        end
    elseif relation ~= "VASSAL" then
        table.insert(list, {key = "vassal", label = "Demand Vassalage", item = {kind = "TREATY", relation = "VASSAL", side = "demand"}})
    end
    local Trade = require("eawx-plugins/diplomacy/DiplomacyTrade")
    if relation ~= "WAR" and not Trade.partner(d, target) then
        table.insert(list, {key = "trade", label = "Trade Agreement", item = {kind = "TRADE", side = "offer"}})
    end
    if relation == "CEASEFIRE" and not Deals.pact_active(d, target) then
        table.insert(list, {key = "pact", label = "Non-aggression Pact", item = {kind = "PACT", side = "offer", weeks = steps.PACT_STEPS[1]}})
    end
    table.insert(list, {key = "credits_offer", label = "Offer Credits", item = {kind = "CREDITS", side = "offer", amount = steps.CREDIT_STEPS[2]}})
    table.insert(list, {key = "credits_demand", label = "Demand Credits", item = {kind = "CREDITS", side = "demand", amount = steps.CREDIT_STEPS[2]}})
    table.insert(list, {key = "tribute_offer", label = "Offer Tribute", item = {kind = "TRIBUTE", side = "offer", amount = steps.TRIBUTE_STEPS[1][1], weeks = steps.TRIBUTE_STEPS[1][2]}})
    table.insert(list, {key = "tribute_demand", label = "Demand Tribute", item = {kind = "TRIBUTE", side = "demand", amount = steps.TRIBUTE_STEPS[1][1], weeks = steps.TRIBUTE_STEPS[1][2]}})
    table.insert(list, {key = "joinwar", label = "Join Our War", pick = "joinwar"})
    table.insert(list, {key = "world_offer", label = "Offer a World", pick = "offer"})
    table.insert(list, {key = "world_demand", label = "Demand a World", pick = "demand"})
    if relation == "ALLIANCE" then
        table.insert(list, {key = "end_alliance", label = "End the Alliance", act = "END_ALLIANCE"})
    elseif relation == "PROTECTORATE" then
        table.insert(list, {key = "end_protection", label = "End Protection", act = "END_PROTECTION"})
    end
    if Trade.partner(d, target) then
        table.insert(list, {key = "end_trade", label = "End Trade Agreement", act = "END_TRADE"})
    end
    if relation == "CEASEFIRE" then
        if Deals.borders_open(d, target) then
            table.insert(list, {key = "close_borders", label = "Close Borders", act = "CLOSE_BORDERS"})
        else
            table.insert(list, {key = "open_borders", label = "Open Borders", item = {kind = "BORDERS", side = "offer", open = true}})
        end
    end
    if relation ~= "WAR" then
        table.insert(list, {key = "war", label = "Declare War", act = "WAR"})
    end
    return list
end

local function deal_with(extra)
    local deal = {}
    for _, item in ipairs(Window.deal) do
        if not (extra and extra.kind == "TREATY" and item.kind == "TREATY") then
            table.insert(deal, item)
        end
    end
    if extra then
        table.insert(deal, extra)
    end
    return deal
end

local function verdict_text(d, total, impossible)
    if impossible then
        return "They would refuse: " .. impossible .. "."
    end
    return (total >= 0 and "They would accept (" or "They would refuse (") .. d.signed(total) .. ")"
end

local function factor_lines(d, total, factors)
    local parts = {}
    for _, f in ipairs(factors) do
        table.insert(parts, d.signed(f[1]) .. " " .. f[2])
    end
    if table.getn(parts) == 0 then
        return "Total " .. d.signed(total) .. "."
    end
    return "Total " .. d.signed(total) .. ": " .. table.concat(parts, "; ") .. ". They accept at 0 or more."
end

local function render_items(d, side)
    local k = 0
    Window.slots = Window.slots or {}
    Window.slots[side] = {}
    for i, item in ipairs(Window.deal) do
        if item.side == side then
            k = k + 1
            if k <= LAYOUT.items then
                Window.slots[side][k] = i
                local name = "dp_d_" .. side .. "_" .. k
                text(name, Deals.label(d, item))
                local changeable = item.kind == "CREDITS" or item.kind == "TRIBUTE" or item.kind == "PACT"
                tip(name, changeable and "Click to change the amount." or Deals.label(d, item))
                show(name, true)
                show(name .. "_x", true)
                tip(name .. "_x", "Remove it from the deal.")
            end
        end
    end
    for n = k + 1, LAYOUT.items do
        show("dp_d_" .. side .. "_" .. n, false)
        show("dp_d_" .. side .. "_" .. n .. "_x", false)
    end
end

local function demandable(d, them)
    local worlds = Deals.worlds_of(them)
    if table.getn(worlds) <= 1 then
        return {}
    end
    local capital = Deals.capital(d, them)
    local keep = {}
    for _, planet in ipairs(worlds) do
        if planet ~= capital then
            table.insert(keep, planet)
        end
    end
    return keep
end

local function war_targets(d, them)
    local out = {}
    local name = them.Get_Faction_Name()
    for faction, _ in pairs(Opinions.world().powers) do
        local p = Find_Player(faction)
        if p and faction ~= name and p.Is_Enemy(d.human) and not p.Is_Enemy(them)
                and faction ~= "INDEPENDENT_FORCES" and not Worlds.is_slot(faction) then
            table.insert(out, faction)
        end
    end
    table.sort(out, function(a, b) return d.display_name(a) < d.display_name(b) end)
    return out
end

local function render_faction_picker(d, them)
    local list = war_targets(d, them)
    local pages = M.max(1, M.floor((table.getn(list) + LAYOUT.picks - 1) / LAYOUT.picks))
    if Window.page > pages then
        Window.page = 1
    end
    Window.pick_factions = {}
    for k = 1, LAYOUT.picks do
        local faction = list[(Window.page - 1) * LAYOUT.picks + k]
        local name = "dp_d_pick_" .. k
        show(name, faction ~= nil)
        show(name .. "_globe", faction ~= nil)
        if faction then
            Window.pick_factions[k] = faction
            text(name, d.display_name(faction))
            icon(name .. "_globe", emblem(faction))
            tip(name, "Ask them to declare war on " .. d.display_name(faction) .. ".")
        end
    end
    if not list[1] then
        show("dp_d_pick_1", true)
        text("dp_d_pick_1", "No power to ask them to fight")
        tip("dp_d_pick_1", "Only powers at war with you that they are not already fighting.")
    end
    show("dp_d_pick_more", pages > 1)
    text("dp_d_pick_more", "More (" .. Window.page .. "/" .. pages .. ")")
    show("dp_d_pick_back", true)
    text("dp_d_pick_back", "Back")
end

local function render_picker(d, them)
    if Window.pick == "joinwar" then
        render_faction_picker(d, them)
        return
    end
    local worlds
    if Window.pick == "demand" then
        worlds = demandable(d, them)
    else
        worlds = Deals.worlds_of(d.human)
    end
    table.sort(worlds, function(a, b) return d:planet_name(a) < d:planet_name(b) end)
    local pages = M.max(1, M.floor((table.getn(worlds) + LAYOUT.picks - 1) / LAYOUT.picks))
    if Window.page > pages then
        Window.page = 1
    end
    Window.pick_worlds = {}
    for k = 1, LAYOUT.picks do
        local planet = worlds[(Window.page - 1) * LAYOUT.picks + k]
        local name = "dp_d_pick_" .. k
        show(name, planet ~= nil)
        show(name .. "_globe", planet ~= nil)
        if planet then
            local key = string.upper(planet.Get_Type().Get_Name())
            Window.pick_worlds[k] = key
            text(name, d:planet_name(planet))
            icon(name .. "_globe", GLOBES[key] or "dp_globe_unknown.tga")
            local barred = Window.pick == "offer" and d:senate_active()
                and not Deals.senate_allows(d, Window.target, {kind = "WORLD", side = "offer", world = key})
            Window.pick_barred = Window.pick_barred or {}
            Window.pick_barred[k] = barred and not Window.decree
            text_color(name, Window.pick_barred[k])
            tip(name, ((Window.pick == "offer") and "Offer " or "Demand ") .. d:planet_name(planet) .. "."
                .. (barred and (Window.decree and " The chamber has not permitted it: forced by emergency decree."
                    or " The chamber has not permitted it: pass Offer a World in Talks, or tick the emergency decree.")
                    or ""))
        end
    end
    show("dp_d_pick_more", pages > 1)
    text("dp_d_pick_more", "More (" .. Window.page .. "/" .. pages .. ")")
    show("dp_d_pick_back", true)
    text("dp_d_pick_back", "Back")
end

local function render_deal(d, ctx, them)
    local target = Window.target
    if Window.proposal and (Window.proposal.faction ~= target or not Proposals.from(d, target)) then
        Window.proposal = nil
    end
    text("dp_d_deal_head", "Negotiating with " .. d.display_name(target))
    local picking = Window.pick ~= nil
    for _, side in ipairs({"offer", "demand"}) do
        show("dp_d_" .. side .. "_head", not picking)
    end
    text("dp_d_offer_head", "Your Offers")
    text("dp_d_demand_head", "Your Demands")
    if picking then
        for _, side in ipairs({"offer", "demand"}) do
            for n = 1, LAYOUT.items do
                show("dp_d_" .. side .. "_" .. n, false)
                show("dp_d_" .. side .. "_" .. n .. "_x", false)
            end
        end
        render_picker(d, them)
    else
        for k = 1, LAYOUT.picks do
            show("dp_d_pick_" .. k, false)
            show("dp_d_pick_" .. k .. "_globe", false)
        end
        show("dp_d_pick_more", false)
        show("dp_d_pick_back", false)
        render_items(d, "offer")
        render_items(d, "demand")
    end
    local list = actions(d, target)
    local sealed = Deals.locked(d, target)
    Window.actions = {}
    Window.act_max = M.max(0, table.getn(list) - LAYOUT.actions)
    Window.act_scroll = M.max(0, M.min(Window.act_scroll or 0, Window.act_max))
    show("dp_d_act_up", Window.act_max > 0)
    show("dp_d_act_down", Window.act_max > 0)
    if Window.act_max > 0 then
        tip("dp_d_act_up", "More actions: scroll with the arrows or the mouse wheel.")
        tip("dp_d_act_down", "More actions: scroll with the arrows or the mouse wheel.")
    end
    for k = 1, LAYOUT.actions do
        local a = list[k + Window.act_scroll]
        local name = "dp_d_act_" .. k
        show(name, a ~= nil)
        if a then
            Window.actions[k] = a
            text(name, a.label)
            local allowed, _, why = true, nil, nil
            if a.item then
                allowed, _, why = Deals.senate_allows(d, target, a.item)
            elseif a.act == "WAR" then
                allowed, _, why = Deals.senate_allows(d, target, {kind = "WAR"})
                if Deals.pact_active(d, target) then
                    allowed, why = false, "Your non-aggression pact forbids it."
                end
            elseif a.pick == "offer" then
                allowed, _, why = Deals.senate_allows(d, target, {kind = "WORLD", side = "offer"})
            end
            local usable = allowed or (Window.decree and not (a.act == "WAR" and Deals.pact_active(d, target)))
            local never = a.pick == "demand" and table.getn(demandable(d, them)) == 0
            if never then
                usable, why = false, "They will never give up their capital or their last world."
            end
            if a.key == "protect" then
                local ok_s, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
                local planet = Worlds.is_slot(target) and Worlds.world_of(Find_Player(target))
                local refused = ok_s and Sym and planet and Sym.protection_refused(d, planet)
                if refused then
                    never, usable, why = true, false, "Not on offer: " .. refused .. "."
                end
            end
            if a.key == "trade" then
                local blocked = require("eawx-plugins/diplomacy/DiplomacyTrade").blocked(d, target)
                if blocked then
                    never, usable, why = true, false, blocked
                end
            end
            if (a.key == "pact" or a.key == "open_borders") and (has_item("TREATY", nil, "VASSAL")
                    or has_item("TREATY", nil, "PROTECTORATE")) then
                usable, why = false, "Not with this offer: making them a subject brings it anyway."
            end
            if sealed then
                never, usable, why = true, false, Deals.locked_reason(d, target)
            end
            Window.actions[k].usable = usable
            Window.actions[k].why = why
            icon(name, usable and "dp_btn_a.tga" or "dp_btn_a_off.tga")
            text_color(name, not usable)
            local line
            if a.item then
                local total, factors, impossible = Deals.evaluate(d, ctx, them, deal_with(a.item))
                line = "With this in the deal: " .. verdict_text(d, total, impossible) .. ". " .. factor_lines(d, total, factors)
            elseif a.pick == "joinwar" then
                line = "Pick a power at war with you: ask " .. d.display_name(target) .. " to declare war on it."
            elseif a.pick then
                line = "Pick one of " .. ((a.pick == "offer") and "your" or "their") .. " worlds for the deal."
            elseif a.act == "WAR" then
                line = "Declare war on " .. d.display_name(target) .. " at once."
                if d.republic and Worlds.is_slot(target) then
                    line = line .. " A free world: your reputation, cohesion and the free worlds' trust will suffer."
                end
            elseif a.act == "END_TRADE" then
                line = "End the trade agreement: the lanes between you carry no shared trade."
            elseif a.act == "CLOSE_BORDERS" then
                line = "Close your borders again: neither side's ships may stay at the other's worlds. No reputation cost."
            else
                line = "End the alliance (a ceasefire remains). They will remember it."
            end
            if never then
                line = why
            elseif not allowed then
                line = why .. (Window.decree and " (Forced by emergency decree.)" or " Tick the emergency decree to force it.") .. " " .. line
            end
            tip(name, line)
        end
    end
    local total, factors, impossible = Deals.evaluate(d, ctx, them, Window.deal)
    if sealed then
        text("dp_d_verdict", "Their borders are sealed.")
        tip("dp_d_verdict", Deals.locked_reason(d, target))
    elseif table.getn(Window.deal) == 0 then
        text("dp_d_verdict", "Add offers or demands.")
        tip("dp_d_verdict", "Hover over an action to see how it would be received.")
    else
        text("dp_d_verdict", verdict_text(d, total, impossible))
        tip("dp_d_verdict", factor_lines(d, total, factors))
    end
    local senate = d:senate_active()
    show("dp_d_decree", senate)
    show("dp_d_decree_label", senate)
    if senate then
        icon("dp_d_decree", Window.decree and "dp_check_on.tga" or "dp_check_off.tga")
        text("dp_d_decree_label", "Force Offer by Emergency Decree")
        local motions = {}
        for _, item in ipairs(Window.deal) do
            local ok, motion = Deals.senate_allows(d, target, item)
            if not ok then
                table.insert(motions, motion)
            end
        end
        local line = "Act without the Senate's approval. The cost grows with how unpopular the decision is."
        if table.getn(motions) > 0 then
            local _, cost_text = Deals.decree_cost(d, motions)
            line = line .. " This deal: " .. cost_text
        end
        tip("dp_d_decree", line)
        tip("dp_d_decree_label", line)
    end
    if Window.proposal then
        local left = M.max(0, M.ceil((Window.proposal.expires - GetCurrentTime()) / CONFIG.WEEK_SECONDS))
        text("dp_d_deal_head", d.display_name(target) .. " offer you " .. Window.proposal.text)
        text("dp_d_verdict", "Their offer stands for " .. left .. " more week" .. ((left == 1) and "" or "s") .. ".")
        tip("dp_d_verdict", "Unanswered, it lapses (declined).")
        text("dp_d_propose", "Accept")
        tip("dp_d_propose", "Accept their offer as it stands.")
        text("dp_d_clear", "Decline")
        tip("dp_d_clear", "Refuse their offer.")
    else
        text("dp_d_propose", "Propose")
        tip("dp_d_propose", "Make the offer. " .. ((table.getn(Window.deal) > 0) and verdict_text(d, total, impossible) or ""))
        text("dp_d_clear", "Clear")
        tip("dp_d_clear", "Remove every offer and demand.")
    end
    text("dp_d_back", "Back")
    tip("dp_d_back", "Back to the list of factions.")
    text("dp_d_deal_note", Window.feedback or "Hover over an action for the numbers behind it.")
end

local TYPE_RATE = 45
local TYPE_SFX = "DP_Speech_Type"
local HOLD_MS = 3500
local FADE_MS = 900

local function leader_type(d, player)
    if player.Get_Faction_Name() == "REBEL" then
        return string.upper(GlobalValue.Get("ChiefOfState") or "DUMMY_CHIEFOFSTATE_MOTHMA")
    end
    local entry = leader(d, player)
    return entry and entry.type
end

local function bubble_side()
    if Engine_Screen_Size then
        local w, h = Engine_Screen_Size()
        if w and h and h > 0 and 768 * w / h / 2 >= 680 then
            return "o"
        end
    end
    return "i"
end

local function republic_open()
    local ok, R = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
    local ok_s, S = pcall(require, "eawx-plugins/diplomacy/DiplomacySenateWindow")
    return (ok and type(R) == "table" and R.open_now) or (ok_s and type(S) == "table" and S.open_now)
end

local function hide_bubble()
    show("dp_dipl_speech_o_shell", false)
    show("dp_dipl_speech_i_shell", false)
end

local function stop_bubble()
    Window.bubble = nil
    hide_bubble()
    show("dp_d_r_emblem2", Window.open_now and Window.target ~= nil)
    local ok_c, Cutscenes = pcall(require, "eawx-plugins/diplomacy/DiplomacyCutscenes")
    local playing = ok_c and Cutscenes and Cutscenes.busy()
    if Engine_Gui_Tick and not Window.tick_hold and not Window.flash_hold and not Window.open_now and not Pause.watching()
            and not republic_open() and not playing then
        Engine_Gui_Tick(0)
    end
end

local function draw_bubble()
    local b = Window.bubble
    if not b then
        hide_bubble()
        return
    end
    local p = "dp_d_sp" .. b.side
    show("dp_dipl_speech_" .. ((b.side == "o") and "i" or "o") .. "_shell", false)
    show("dp_dipl_speech_" .. b.side .. "_shell", true)
    show("dp_d_r_emblem2", false)
    local step = LAYOUT.speech_fade[1]
    for _, a in ipairs(LAYOUT.speech_fade) do
        if b.alpha <= a then
            step = a
        end
    end
    icon(p, "dp_speech_" .. b.side .. "_" .. step .. ".tga")
    tip(p, "Click to dismiss.")
    for k = 1, LAYOUT.speech_lines do
        local line = b.lines[k]
        local name = p .. "_" .. k
        local shown = 0
        if line then
            shown = M.max(0, M.min(string.len(line[1]), b.typed - line[4]))
        end
        show(name, shown > 0)
        if shown > 0 then
            text(name, string.sub(line[1], 1, shown))
            local a = b.alpha / 100
            if line[2] then
                call(GUI_Text_Color, name, 0.92, 0.78, 0.38, a)
            else
                call(GUI_Text_Color, name, 0.85, 0.85, 0.82, a)
            end
            tip(name, "Click to dismiss.")
        end
    end
end

local function start_bubble(lines)
    local translated = false
    for _, line in ipairs(lines) do
        if line[2] then
            translated = true
        end
    end
    local offsets, total, out = {0, 0}, 0, {}
    for _, line in ipairs(lines) do
        local group = (translated and not line[2]) and 2 or 1
        table.insert(out, {line[1], line[2], group, offsets[group]})
        offsets[group] = offsets[group] + string.len(line[1])
        total = M.max(total, offsets[group])
    end
    Window.bubble = {lines = out, side = bubble_side(), t = 0, typed = 0, total = total, alpha = 100,
                     done = nil, sound_at = -1000}
    if Engine_Gui_Tick then
        Engine_Gui_Tick(1)
    else
        Window.bubble.typed = total
    end
    draw_bubble()
end

function Window.draw_thumb()
    local seg, segs = LAYOUT.scroll_seg, LAYOUT.scroll_segs
    local track, len = segs * seg, Window.thumb_len or 24
    local share = (Window.scroll or 0) / M.max(1, Window.max_scroll or 0)
    if Window.dragging and Window.thumb_share then
        share = Window.thumb_share
    end
    local top = share * (track - len)
    local first, last = segs, 1
    for k = 1, segs do
        local middle = (k - 0.5) * seg
        if middle >= top and middle <= top + len then
            first, last = M.min(first, k), M.max(last, k)
        end
    end
    Window.seg_lit = Window.seg_lit or {}
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
            icon("dp_d_scroll_" .. k, "dp_scroll_" .. piece .. ".tga")
        end
    end
end

function Window.show_on_map(world)
    local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
    local event = plot and plot.Get_Event("Diplomacy_Window_Camera")
    if not (event and FindPlanet(world)) then
        return false
    end
    event.Set_Reward_Parameter(0, world)
    Window.close()
    Story_Event("DIPLOMACY_WINDOW_CAMERA")
    if Engine_Log then
        Engine_Log("DIPLOMACY WINDOW camera to " .. world)
    end
    return true
end

local function wheel_actions()
    if not (Engine_Mouse and Engine_Screen_Size) or Window.mode ~= "deal" or (Window.act_max or 0) <= 0 then
        return
    end
    local mx, _, _, wheel = Engine_Mouse()
    local w, h = Engine_Screen_Size()
    if not wheel or wheel == 0 or not h or h <= 0 then
        return
    end
    local x = (mx - w / 2) / (h / 768)
    if x < -240 or x > -28 then
        return
    end
    local v = M.max(0, M.min(Window.act_max, (Window.act_scroll or 0) - M.round(wheel)))
    if v ~= Window.act_scroll then
        Window.act_scroll = v
        Window.render(Window.d)
    end
end

local function drag_scroll()
    wheel_actions()
    if not (Engine_Mouse and Engine_Screen_Size) or Window.mode ~= "list" or (Window.max_scroll or 0) <= 0 then
        Window.dragging = false
        return
    end
    local mx, my, down, wheel = Engine_Mouse()
    if wheel and wheel ~= 0 and not Window.dragging then
        local scroll = M.min(Window.max_scroll, M.max(0, (Window.scroll or 0) - M.round(wheel * 3)))
        if scroll ~= Window.scroll then
            Window.scroll = scroll
            if Window.list_cache then
                Window.render_rows(Window.d, Window.ctx_cache, Window.list_cache)
            else
                Window.render(Window.d)
            end
            Window.draw_thumb()
        end
    end
    if down ~= 1 then
        Window.dragging, Window.was_down = false, false
        return
    end
    local w, h = Engine_Screen_Size()
    if not h or h <= 0 then
        return
    end
    local scale = h / 768
    local x, y = (mx - w / 2) / scale, (h / 2 - my) / scale
    if not Window.was_down then
        Window.was_down = true
        Window.dragging = M.abs(x - LAYOUT.scroll_x) <= 12 and y <= LAYOUT.scroll_top
            and y >= LAYOUT.scroll_top - LAYOUT.scroll_segs * LAYOUT.scroll_seg
    end
    if not Window.dragging then
        return
    end
    local len = Window.thumb_len or 24
    local span = M.max(1, LAYOUT.scroll_segs * LAYOUT.scroll_seg - len)
    local share = M.min(1, M.max(0, (LAYOUT.scroll_top - y - len / 2) / span))
    Window.thumb_share = share
    local scroll = M.round(share * Window.max_scroll)
    if scroll ~= Window.scroll then
        Window.scroll = scroll
        if Window.list_cache then
            Window.render_rows(Window.d, Window.ctx_cache, Window.list_cache)
        else
            Window.render(Window.d)
        end
    end
    Window.draw_thumb()
end

function Window.tick(ms)
    if not Window.open_now then
        stop_bubble()
        return
    end
    drag_scroll()
    Speech.watch_voice(ms)
    local b = Window.bubble
    if not b then
        return
    end
    b.t = b.t + ms
    if not b.done then
        local chars = M.floor(b.t * TYPE_RATE / 1000)
        if chars >= b.total then
            chars, b.done = b.total, b.t
        end
        if chars > b.typed and b.t - b.sound_at >= 70 then
            b.sound_at = b.t
            Speech.play_sfx(TYPE_SFX)
        end
        b.typed = chars
    elseif b.t - b.done > HOLD_MS then
        b.alpha = M.max(0, 100 - 100 * (b.t - b.done - HOLD_MS) / FADE_MS)
        if b.alpha <= 0 then
            stop_bubble()
            return
        end
    end
    draw_bubble()
end

local function dismiss_bubble()
    local b = Window.bubble
    if not b then
        return
    end
    if not Engine_Gui_Tick then
        stop_bubble()
        return
    end
    b.typed = b.total
    b.done = b.t - HOLD_MS
end

local function speak(d, kind, tier)
    local them = Window.target and Find_Player(Window.target)
    if not them then
        return
    end
    local ok, lines = pcall(Speech.say, d, Window.target, d.human.Get_Faction_Name(), leader_type(d, them), kind,
        tier, SPEECH_WIDTH)
    if not ok and Engine_Log then
        Engine_Log("SPEECH error: " .. tostring(lines))
    end
    if ok and lines then
        start_bubble(lines)
    end
end

local function greet(d)
    if Deals.locked(d, Window.target) then
        return
    end
    local them = Find_Player(Window.target)
    local ctx = DiplomacyAI.context(d.display_name)
    speak(d, "greet", Speech.standing(d, Window.target, Deals.attitude(d, ctx, them)))
end

local function render_speech(d)
    if Window.bubble and not (Window.mode == "deal" and Window.target) then
        stop_bubble()
    end
    draw_bubble()
end

function Window.render(d)
    Window.last_d = d
    if Window.talking and (Window.target ~= Window.talking or Window.mode ~= "deal") then
        pcall(Worlds.release, d, Window.talking)
        Window.talking = nil
    end
    local ctx = DiplomacyAI.context(d.display_name)
    local list = factions(d, ctx)
    if Window.target then
        local them = Find_Player(Window.target)
        if not them or table.getn(Deals.worlds_of(them)) == 0 then
            Window.target, Window.mode = nil, "list"
        end
    end
    text("dp_d_title", "Diplomacy")
    fill_side(d, ctx, "l", d.human, list)
    if Window.target and Window.mode == "rel" then
        hide_side("r")
    elseif Window.target then
        local them = Find_Player(Window.target)
        show_side("r")
        fill_side(d, ctx, "r", them, list, Deals.attitude(d, ctx, them))
    elseif Window.world and Window.mode == "list" then
        show_side("r")
        fill_world_side(d, ctx, Window.world)
    else
        hide_side("r")
    end
    if (Window.mode == "deal" or Window.mode == "req") and not Window.target then
        Window.mode = "list"
    end
    local picking = (Window.mode == "deal" and Window.pick ~= nil) or (Window.mode == "req" and Window.req_pick ~= nil)
    show("dp_dipl_list_shell", Window.mode == "list" or Window.mode == "rel")
    show("dp_dipl_rel_shell", Window.mode == "rel" and Window.target ~= nil)
    show("dp_dipl_req_shell", Window.mode == "req" and not picking)
    show("dp_dipl_deal_shell", Window.mode == "deal")
    show("dp_dipl_pick_shell", picking)
    show("dp_dipl_items_shell", Window.mode == "deal" and Window.pick == nil)
    Window.render_tabs(d)
    if Window.mode == "deal" then
        render_deal(d, ctx, Find_Player(Window.target))
    elseif Window.mode == "req" then
        Window.render_requests(d, ctx, Find_Player(Window.target))
    else
        render_list(d, ctx, (Window.tab == "minor") and minor_factions(d) or powers_list(d))
        if Window.mode == "rel" then
            Window.render_relations(d, ctx)
        end
    end
    render_speech(d)
end

function Window.render_tabs(d)
    local shown = Window.mode == "list" or Window.mode == "rel"
    for key, label in pairs({major = "Powers", minor = "Minor Factions"}) do
        show("dp_d_tab_" .. key, shown)
        if shown then
            text("dp_d_tab_" .. key, label)
            icon("dp_d_tab_" .. key, (Window.tab == key) and "dp_tab_sel.tga" or "dp_tab.tga")
            tip("dp_d_tab_" .. key, TAB_TIPS[key])
        end
    end
    for key, label in pairs({dipl = "Diplomacy", rel = "Relations"}) do
        show("dp_d_tab_" .. key, shown)
        if shown then
            local on = (key == "dipl" and Window.mode == "list") or (key == "rel" and Window.mode == "rel")
            text("dp_d_tab_" .. key, label)
            icon("dp_d_tab_" .. key, on and "dp_sub_sel.tga" or "dp_sub.tga")
            tip("dp_d_tab_" .. key, (key == "dipl") and "The factions, their treaties with you and their attitude."
                or "What each faction thinks of the others, as far as your intelligence reaches: select one.")
        end
    end
end

local function spy_tier(d, faction)
    faction = string.upper(faction)
    local r = d.republic and d.republic.intel
    if r and r.spy then
        return (r.spy[faction] or {}).tier or 0
    end
    if d.human.Get_Faction_Name() == "EMPIRE" and type(IMPERIAL_COURT) == "table" and IMPERIAL_COURT.spy then
        return (IMPERIAL_COURT.spy[faction] or {}).tier or 0
    end
    return nil
end

local function borders_human(d, faction)
    local H = string.upper(d.human.Get_Faction_Name())
    local bd = Opinions.world().borders
    return ((bd[H .. "|" .. faction] or 0) + (bd[faction .. "|" .. H] or 0)) > 0
end

local function partner(d, faction)
    return d:relation(faction) ~= "WAR"
end

local function relation_state(d, a, b)
    local H = string.upper(d.human.Get_Faction_Name())
    if a == b then
        return "self"
    end
    local Trade = require("eawx-plugins/diplomacy/DiplomacyTrade")
    if a == H or b == H then
        local other = (a == H) and b or a
        local r = d:relation(other)
        local key = ({WAR = "war", CEASEFIRE = "ceasefire", ALLIANCE = "alliance", VASSAL = "vassal",
                      PROTECTORATE = "protect"})[r] or "ceasefire"
        return key, Trade.partner(d, other), d.memory.signed and d.memory.signed[other], (r == "VASSAL") and H or nil
    end
    local pa, pb = Find_Player(a), Find_Player(b)
    if pa and pb and pa.Is_Enemy(pb) then
        return "war"
    end
    local Galaxy = require("eawx-plugins/diplomacy/DiplomacyGalaxy")
    local p = Galaxy.pact(a, b)
    if not p then
        return "peace"
    end
    local key = ({CEASEFIRE = "ceasefire", ALLIANCE = "alliance", VASSAL = "vassal"})[p.kind] or "peace"
    return key, p.trade ~= nil, p.since, p.overlord
end

local function treaty_known(d, a, b, key)
    local H = string.upper(d.human.Get_Faction_Name())
    if a == H or b == H or key == "war" or key == "self" then
        return true
    end
    if borders_human(d, a) or borders_human(d, b) or partner(d, a) or partner(d, b) then
        return true
    end
    local ta, tb = spy_tier(d, a), spy_tier(d, b)
    return (ta or 0) >= 1 or (tb or 0) >= 1
end

local REL_WORDS = {war = "At war", ceasefire = "Ceasefire", alliance = "Alliance", vassal = "Vassalage",
                   protect = "Protectorate", peace = "At peace"}

local function relations_list(d)
    local H = string.upper(d.human.Get_Faction_Name())
    local out = {H}
    local skip = {INDEPENDENT_FORCES = true, HOSTILE = true, WARLORDS = true, NEUTRAL = true, [H] = true}
    for _, v in ipairs(require("eawx-plugins/diplomacy/DiplomacyVassals")) do
        skip[string.upper(v.name)] = true
    end
    local rest = {}
    for name, _ in pairs(Opinions.world().powers) do
        if not skip[name] and not Worlds.is_slot(name) then
            table.insert(rest, name)
        end
    end
    local count = Opinions.world().count
    table.sort(rest, function(x, y)
        if (count[x] or 0) ~= (count[y] or 0) then
            return (count[x] or 0) > (count[y] or 0)
        end
        return x < y
    end)
    for _, f in ipairs(rest) do
        table.insert(out, f)
    end
    return out
end

local function weeks_ago(t)
    return t and M.max(0, M.floor((GetCurrentTime() - t) / CONFIG.WEEK_SECONDS)) or nil
end

local function cell_tip(d, a, b, key, trade, since, overlord)
    local H = string.upper(d.human.Get_Faction_Name())
    local an, bn = d.display_name(a), d.display_name(b)
    if not treaty_known(d, a, b, key) then
        return an .. " and " .. bn .. ": unknown. Your intelligence does not reach their dealings."
    end
    local line = an .. " and " .. bn .. ": " .. REL_WORDS[key]
    if key == "vassal" and overlord then
        line = line .. " (" .. d.display_name(overlord) .. " the overlord)"
    end
    local age = weeks_ago(since)
    if age and key ~= "war" and key ~= "peace" then
        line = line .. ", " .. age .. " week" .. ((age == 1) and "" or "s")
    end
    if trade then
        line = line .. "; they trade"
    end
    line = line .. "."
    local function view(x, y)
        local v = Opinions.get(x, y)
        return " " .. d.display_name(x) .. " think" .. ((string.sub(d.display_name(x), -1) == "s") and "" or "s")
            .. " of " .. ((y == H) and "you" or d.display_name(y)) .. ": " .. Deals.attitude_word(v) .. " (" .. d.signed(v) .. ")."
    end
    if a == H or b == H then
        local other = (a == H) and b or a
        line = line .. view(other, H)
    else
        if (spy_tier(d, a) or 0) >= 2 then
            line = line .. view(a, b)
        end
        if (spy_tier(d, b) or 0) >= 2 then
            line = line .. view(b, a)
        end
    end
    return line
end

local function row_tip(d, faction)
    local H = string.upper(d.human.Get_Faction_Name())
    local line = d.display_name(faction) .. ": " .. (Opinions.world().count[faction] or 0) .. " worlds."
    if faction == H then
        return line .. " Your faction."
    end
    local tier = spy_tier(d, faction)
    if tier then
        line = line .. " Your spy network: level " .. tier .. "."
    end
    if (tier or 0) >= 3 then
        local plans = {}
        for _, p in ipairs(require("eawx-plugins/diplomacy/DiplomacyAllies").plans(faction)) do
            local Allies = require("eawx-plugins/diplomacy/DiplomacyAllies")
            local what = string.lower(Allies.LABEL[p.kind]) .. (p.faction and (" " .. d.display_name(p.faction)) or "")
            if p.ally == faction then
                table.insert(plans, what .. ((p.by ~= faction) and (" for " .. d.display_name(p.by)) or ""))
            else
                table.insert(plans, d.display_name(p.ally) .. ": " .. what)
            end
        end
        line = line .. " Their plans: " .. (plans[1] and table.concat(plans, "; ") or "none known") .. "."
    end
    return line .. " Click to select them."
end

local function ops_color(name, value)
    if value == nil then
        call(GUI_Text_Color, name, 0.45, 0.45, 0.48, 1)
    elseif value >= 25 then
        call(GUI_Text_Color, name, 0.40, 0.85, 0.45, 1)
    elseif value > 5 then
        call(GUI_Text_Color, name, 0.70, 0.85, 0.50, 1)
    elseif value >= -5 then
        call(GUI_Text_Color, name, 0.84, 0.86, 0.90, 1)
    elseif value > -25 then
        call(GUI_Text_Color, name, 0.95, 0.65, 0.35, 1)
    else
        call(GUI_Text_Color, name, 0.90, 0.35, 0.30, 1)
    end
end

function Window.render_relations(d, ctx)
    local rows = LAYOUT.ops_rows
    local who = Window.target
    show("dp_dipl_rel_shell", who ~= nil)
    if not who then
        return
    end
    local H = string.upper(d.human.Get_Faction_Name())
    local known = (who == H) or ((spy_tier(d, who) or 0) >= 2)
    local list = {}
    for _, f in ipairs(relations_list(d)) do
        if f ~= who then
            local value = nil
            if known or f == H then
                value = Opinions.get(who, f)
            end
            table.insert(list, {faction = f, value = value})
        end
    end
    table.sort(list, function(x, y)
        if (x.value == nil) ~= (y.value == nil) then
            return x.value ~= nil
        end
        if x.value and y.value and x.value ~= y.value then
            return x.value > y.value
        end
        return d.display_name(x.faction) < d.display_name(y.faction)
    end)
    local pages = M.max(1, M.ceil(table.getn(list) / rows))
    Window.ops_page = M.max(1, M.min(Window.ops_page or 1, pages))
    Window.ops_shown = {}
    text("dp_d_ops_head", d.display_name(who) .. "'s opinions")
    text("dp_d_ops_sub", known and "Of every power, best first." or "Only of you: no spies in their counsels.")
    tip("dp_d_ops_sub", "You always know what a power thinks of you; what it thinks of the others needs a spy network "
        .. "of tier 2 or more on it.")
    for k = 1, rows do
        local entry = list[(Window.ops_page - 1) * rows + k]
        local base = "dp_d_ops_" .. k
        show(base .. "_e", entry ~= nil)
        show(base .. "_name", entry ~= nil)
        show(base .. "_val", entry ~= nil)
        Window.ops_shown[k] = entry and entry.faction
        if entry then
            icon(base .. "_e", emblem(entry.faction))
            text(base .. "_name", d.display_name(entry.faction))
            tip(base .. "_name", "Click to select " .. d.display_name(entry.faction) .. ".")
            text(base .. "_val", entry.value and d.signed(entry.value) or "?")
            ops_color(base .. "_val", entry.value)
        end
    end
    show("dp_d_ops_prev", pages > 1)
    show("dp_d_ops_next", pages > 1)
    show("dp_d_ops_page", pages > 1)
    if pages > 1 then
        text("dp_d_ops_page", Window.ops_page .. " / " .. pages)
    end
end

function Window.click_relations(d, name)
    local _, _, k = string.find(name, "^dp_d_ops_(%d+)_[en]a?m?e?$")
    if k then
        local f = Window.ops_shown and Window.ops_shown[tonumber(k)]
        if f and f ~= string.upper(d.human.Get_Faction_Name()) then
            Window.select_faction(d, f)
            Window.mode = "rel"
        end
        return true
    end
    if name == "dp_d_ops_prev" then
        Window.ops_page = M.max(1, (Window.ops_page or 1) - 1)
        return true
    elseif name == "dp_d_ops_next" then
        Window.ops_page = (Window.ops_page or 1) + 1
        return true
    end
    return string.find(name, "^dp_d_ops_") ~= nil
end

local REQ_KINDS = {"TARGET", "WORLD", "ESCORT", "STATION"}
local REQ_DESC = {TARGET = "They make war on the target in their own time.",
                  WORLD = "Their fleets make one of the target's worlds their first objective.",
                  ESCORT = "A fleet of theirs follows one of yours and fights beside it (it stays theirs).",
                  STATION = "A fleet of theirs guards a world of yours and helps the worlds next to it."}

local function req_world(req, kind)
    if kind == "STATION" then
        return req.station
    end
    return req.world
end

local function req_weeks(req, kind)
    if kind == "STATION" then
        return req.station_weeks or CONFIG.ALLIES.ESCORT_WEEKS[1]
    end
    return req.weeks
end

local function fleet_label(d, f)
    local at = f.planet and d:planet_name(f.planet) or "in hyperspace"
    return "Your fleet at " .. at .. " (" .. f.size .. ")"
end

local function answer_line(d, total, factors, impossible)
    local parts = {}
    for _, f in ipairs(factors or {}) do
        table.insert(parts, d.signed(f[1]) .. " " .. f[2])
    end
    if impossible then
        return "Not possible: " .. impossible .. ".", "Not possible: " .. impossible .. "."
    end
    local word = (total >= 15 and "Likely") or (total >= 0 and "Possible") or "Unlikely"
    return "Their answer: " .. word .. " (" .. d.signed(total) .. ")",
        "Total " .. d.signed(total) .. ": " .. table.concat(parts, "; ") .. ". They accept at 0 or more."
end

local function render_req_picker(d)
    local Allies = require("eawx-plugins/diplomacy/DiplomacyAllies")
    local ally = Window.req.ally
    local entries = {}
    if Window.req_pick == "target" then
        local H = string.upper(d.human.Get_Faction_Name())
        for faction, _ in pairs(Opinions.world().powers) do
            local pa, pf = Find_Player(ally), Find_Player(faction)
            if faction ~= ally and faction ~= H and pa and pf and pa.Is_Enemy(pf) and not Worlds.is_slot(faction)
                    and faction ~= "INDEPENDENT_FORCES" then
                table.insert(entries, {label = d.display_name(faction), icon = emblem(faction), value = faction,
                                       tip = "Make " .. d.display_name(faction) .. " the target."})
            end
        end
    elseif Window.req_pick == "world" and Window.req.target then
        for _, planet in ipairs(Deals.worlds_of(Find_Player(Window.req.target))) do
            local key = string.upper(planet.Get_Type().Get_Name())
            table.insert(entries, {label = d:planet_name(planet), icon = GLOBES[key] or "dp_globe_unknown.tga",
                                   value = key, tip = "Ask them to take " .. d:planet_name(planet) .. "."})
        end
    elseif Window.req_pick == "own" then
        for _, planet in ipairs(Deals.worlds_of(d.human)) do
            local key = string.upper(planet.Get_Type().Get_Name())
            table.insert(entries, {label = d:planet_name(planet), icon = GLOBES[key] or "dp_globe_unknown.tga",
                                   value = key, tip = "Ask them to guard " .. d:planet_name(planet) .. "."})
        end
    elseif Window.req_pick == "fleet" then
        for _, f in ipairs(Allies.fleets(d.human)) do
            local key = f.planet and string.upper(f.planet.Get_Type().Get_Name())
            table.insert(entries, {label = fleet_label(d, f),
                                   icon = f.icon or (key and GLOBES[key]) or "dp_globe_unknown.tga",
                                   value = f.fleet, tip = "Their escort follows this fleet."})
        end
    end
    table.sort(entries, function(x, y) return x.label < y.label end)
    local pages = M.max(1, M.ceil(table.getn(entries) / LAYOUT.picks))
    Window.page = M.max(1, Window.page or 1)
    if Window.page > pages then
        Window.page = 1
    end
    Window.req_entries = {}
    for k = 1, LAYOUT.picks do
        local e = entries[(Window.page - 1) * LAYOUT.picks + k]
        local name = "dp_d_pick_" .. k
        show(name, e ~= nil)
        show(name .. "_globe", e ~= nil)
        if e then
            Window.req_entries[k] = e.value
            text(name, e.label)
            icon(name .. "_globe", e.icon)
            tip(name, e.tip)
        end
    end
    if not entries[1] then
        show("dp_d_pick_1", true)
        text("dp_d_pick_1", (Window.req_pick == "fleet") and "You have no fleet" or "Nothing to choose")
        tip("dp_d_pick_1", (Window.req_pick == "target") and "They are at war with nobody they could target."
            or " ")
    end
    show("dp_d_pick_more", pages > 1)
    text("dp_d_pick_more", "More (" .. Window.page .. "/" .. pages .. ")")
    show("dp_d_pick_back", true)
    text("dp_d_pick_back", "Back")
end

function Window.render_requests(d, ctx, them)
    if Window.req_pick then
        render_req_picker(d)
        return
    end
    local Allies = require("eawx-plugins/diplomacy/DiplomacyAllies")
    local ally = string.upper(Window.target)
    local req = Window.req
    if req.target and not Find_Player(req.target) then
        req.target, req.world = nil, nil
    end
    text("dp_d_req_head", "Requests to " .. d.display_name(ally))
    text("dp_d_req_target_label", "Target:")
    text("dp_d_req_target", req.target and d.display_name(req.target) or "Choose a target faction")
    tip("dp_d_req_target", "A power they are at war with: the target of a war target or of a world to take.")
    local current = Allies.tasks_of(ally)
    for k, kind in ipairs(REQ_KINDS) do
        local p = "dp_d_req_" .. k
        text(p .. "_title", Allies.LABEL[kind])
        text(p .. "_desc", REQ_DESC[kind])
        local task = current[kind]
        show(p .. "_pick", kind ~= "TARGET")
        if kind == "WORLD" then
            local planet = req.world and FindPlanet(req.world)
            text(p .. "_pick", planet and d:planet_name(planet) or (req.target and "Choose a world" or "Choose a target first"))
            tip(p .. "_pick", "One of the target's worlds.")
        elseif kind == "ESCORT" then
            local f = TestValid(req.fleet) and req.fleet or nil
            local ok, at = false, nil
            if f then
                ok, at = pcall(f.Get_Planet_Location)
            end
            text(p .. "_pick", f and ("Fleet at " .. ((ok and at) and d:planet_name(at) or "sea")) or "Choose your fleet")
            tip(p .. "_pick", "The fleet of yours they escort.")
        elseif kind == "STATION" then
            local planet = req.station and FindPlanet(req.station)
            text(p .. "_pick", planet and d:planet_name(planet) or "Choose your world")
            tip(p .. "_pick", "The world of yours they guard.")
        end
        local line, why, can
        if task then
            local left = M.max(0, M.ceil((task.ends - GetCurrentTime()) / CONFIG.WEEK_SECONDS))
            local what = task.faction and d.display_name(task.faction) or ""
            if (kind == "WORLD" or kind == "STATION") and task.world and FindPlanet(task.world) then
                what = d:planet_name(FindPlanet(task.world))
            end
            line = "Under way" .. ((what ~= "") and (": " .. what) or "") .. " (" .. left .. " week" .. ((left == 1) and "" or "s") .. " left)."
            why, can = "Click Stop to call it off.", true
            text(p .. "_ask", "Stop")
        else
            local total, factors, impossible = Allies.willingness(d, ally, kind, req.target, req_world(req, kind),
                req_weeks(req, kind), req.fleet)
            if kind == "WORLD" and not req.world and not impossible then
                impossible = "choose a world"
            elseif kind == "ESCORT" and not TestValid(req.fleet) and not impossible then
                impossible = "choose your fleet"
            elseif kind == "STATION" and not req.station and not impossible then
                impossible = "choose a world of yours"
            end
            line, why = answer_line(d, total, factors, impossible)
            can = not impossible
            text(p .. "_ask", "Ask")
        end
        if (kind == "ESCORT" or kind == "STATION") and not task then
            line = "For " .. req_weeks(req, kind) .. " weeks (click to change). " .. line
        end
        text(p .. "_answer", line)
        tip(p .. "_answer", why)
        icon(p .. "_ask", can and "dp_btn_s.tga" or "dp_btn_s_off.tga")
        text_color(p .. "_ask", not can)
        tip(p .. "_ask", task and "Call it off." or ("Ask " .. d.display_name(ally) .. "."))
    end
    text("dp_d_req_back", "Back")
    tip("dp_d_req_back", "Back to the list of factions.")
    text("dp_d_req_note", Window.feedback or "Your vassals obey; allies decide. Hover an answer for its reasons.")
end

function Window.click_requests(d, name)
    local Allies = require("eawx-plugins/diplomacy/DiplomacyAllies")
    local req = Window.req
    if Window.req_pick then
        local _, _, k = string.find(name, "^dp_d_pick_(%d+)$")
        if k then
            local value = Window.req_entries and Window.req_entries[tonumber(k)]
            if value then
                if Window.req_pick == "target" then
                    if req.target ~= value then
                        req.target, req.world = value, nil
                    end
                elseif Window.req_pick == "world" then
                    req.world = value
                elseif Window.req_pick == "own" then
                    req.station = value
                else
                    req.fleet = value
                end
            end
            Window.req_pick = nil
        elseif name == "dp_d_pick_more" then
            Window.page = (Window.page or 1) + 1
        elseif name == "dp_d_pick_back" then
            Window.req_pick = nil
        end
        return string.find(name, "^dp_d_pick") ~= nil
    end
    if name == "dp_d_req_target" then
        Window.req_pick, Window.page = "target", 1
    elseif name == "dp_d_req_2_pick" then
        if req.target then
            Window.req_pick, Window.page = "world", 1
        else
            Window.feedback = "Choose a target faction first."
        end
    elseif name == "dp_d_req_3_pick" then
        Window.req_pick, Window.page = "fleet", 1
    elseif name == "dp_d_req_4_pick" then
        Window.req_pick, Window.page = "own", 1
    elseif name == "dp_d_req_3_answer" or name == "dp_d_req_4_answer" then
        local kind = (name == "dp_d_req_4_answer") and "STATION" or "ESCORT"
        local list = CONFIG.ALLIES.ESCORT_WEEKS
        local nxt = list[1]
        for i, w in ipairs(list) do
            if w == req_weeks(req, kind) then
                nxt = list[i + 1] or list[1]
            end
        end
        if kind == "STATION" then
            req.station_weeks = nxt
        else
            req.weeks = nxt
        end
    elseif name == "dp_d_req_back" then
        Window.mode, Window.req_pick = "list", nil
    else
        local _, _, k = string.find(name, "^dp_d_req_(%d)_ask$")
        local kind = k and REQ_KINDS[tonumber(k)]
        if kind then
            local ally = string.upper(Window.target)
            if Allies.tasks_of(ally)[kind] then
                Allies.stop(ally, kind)
                Window.feedback = Allies.LABEL[kind] .. " called off."
            else
                local ok, message = Allies.ask(d, ally, kind, req.target, req_world(req, kind), req.fleet,
                    req_weeks(req, kind))
                Window.feedback = message
            end
        else
            return string.find(name, "^dp_d_req_") ~= nil
        end
    end
    return true
end

function Window.open(d)
    Window.d = d
    Window.open_now = true
    Window.feedback = nil
    Window.mode, Window.pick = "list", nil
    show_side("l")
    Window.render(d)
    show("dp_dipl_shell", true)
    if Engine_Gui_Tick then
        Engine_Gui_Tick(1)
    end
    if Engine_Wheel_Capture then
        Engine_Wheel_Capture(1)
    end
    Pause.hold("diplomacy")
    if Engine_Screen_Text then
        Engine_Screen_Text(0)
    end
end

function Window.show_offer(d, offer)
    Window.world, Window.target, Window.bubble, Window.act_scroll = nil, offer.faction, nil, 0
    Window.deal = {}
    for _, item in ipairs(offer.deal) do
        local copy = {}
        for k, v in pairs(item) do
            copy[k] = v
        end
        table.insert(Window.deal, copy)
    end
    Window.mode, Window.pick, Window.proposal = "deal", nil, offer
    Window.render(d)
end

function Window.close()
    if Window.talking and Window.last_d then
        pcall(Worlds.release, Window.last_d, Window.talking)
    end
    Window.talking = nil
    for _, shell in ipairs(SHELLS) do
        show(shell, false)
    end
    Window.open_now = false
    Window.pick = nil
    Window.target, Window.world, Window.tab, Window.scroll, Window.page = nil, nil, "major", 0, 1
    Window.deal, Window.decree, Window.proposal = {}, false, nil
    stop_bubble()
    if Engine_Wheel_Capture then
        Engine_Wheel_Capture(0)
    end
    Pause.release("diplomacy")
    if Engine_Screen_Text then
        Engine_Screen_Text(1)
    end
end

local function cycle(item)
    local steps = CONFIG.DEALS
    if item.kind == "CREDITS" then
        local list = steps.CREDIT_STEPS
        for i, v in ipairs(list) do
            if v == item.amount then
                item.amount = list[i - table.getn(list) * M.floor(i / table.getn(list)) + 1]
                return
            end
        end
        item.amount = list[1]
    elseif item.kind == "TRIBUTE" then
        local list = steps.TRIBUTE_STEPS
        for i, v in ipairs(list) do
            if v[1] == item.amount and v[2] == item.weeks then
                local nxt = list[i - table.getn(list) * M.floor(i / table.getn(list)) + 1]
                item.amount, item.weeks = nxt[1], nxt[2]
                return
            end
        end
        item.amount, item.weeks = list[1][1], list[1][2]
    elseif item.kind == "PACT" then
        local list = steps.PACT_STEPS
        for i, v in ipairs(list) do
            if v == item.weeks then
                item.weeks = list[i - table.getn(list) * M.floor(i / table.getn(list)) + 1]
                return
            end
        end
        item.weeks = list[1]
    end
end

function Window.click(d, name, button)
    if Engine_Log then
        Engine_Log("DIPLOMACY WINDOW " .. tostring(button) .. " click " .. tostring(name))
    end
    if string.find(name, "^b_diplomacy_panel") then
        if button ~= "right" then
            if Window.open_now then
                Window.close()
            else
                Window.open(d)
                local offer = Proposals.first(d)
                if offer then
                    Window.show_offer(d, offer)
                end
            end
        end
        return
    end
    if name == "dp_d_close" then
        Window.close()
        return
    end
    if not Window.open_now then
        return
    end
    Window.feedback = nil
    local _, _, row = string.find(name, "^dp_d_row_(%d+)")
    if row then
        local entry = Window.rows and Window.rows[tonumber(row)]
        if entry and entry.world then
            Window.world, Window.target, Window.bubble = entry, nil, nil
            Window.feedback = entry.label .. ((entry.kind == "INDEPENDENT")
                and ": an independent world. Open Negotiations to treat with it."
                or ": held by minor warlords. They will not negotiate.")
        elseif entry and entry.name ~= Window.target then
            Window.world = nil
            Window.target = entry.name
            Window.deal = {}
            Window.bubble = nil
        end
    elseif Window.emblem_targets and Window.emblem_targets[name] then
        Window.select_faction(d, Window.emblem_targets[name])
    elseif name == "dp_d_tab_major" or name == "dp_d_tab_minor" then
        local tab = (name == "dp_d_tab_major") and "major" or "minor"
        if tab ~= Window.tab then
            Window.tab, Window.scroll, Window.world, Window.target = tab, 0, nil, nil
        end
        if Window.mode ~= "rel" then
            Window.mode = "list"
        end
    elseif name == "dp_d_tab_dipl" then
        Window.mode = "list"
    elseif name == "dp_d_tab_rel" then
        Window.mode, Window.world, Window.ops_page = "rel", nil, 1
    elseif Window.mode == "rel" and Window.click_relations(d, name) then
    elseif name == "dp_d_requests" then
        local bond = Window.target and require("eawx-plugins/diplomacy/DiplomacyAllies").bond(d, Window.target)
        if bond then
            Window.mode, Window.req_pick, Window.req = "req", nil, Window.req or {}
            if Window.req.ally ~= Window.target then
                Window.req = {ally = Window.target, weeks = CONFIG.ALLIES.ESCORT_WEEKS[1]}
            end
        else
            Window.feedback = Window.target and "Requests are for your allies, vassals and protectorates."
                or "Select one of your allies first."
        end
    elseif Window.mode == "req" and Window.click_requests(d, name) then
    elseif name == "dp_d_scroll_up" then
        Window.scroll = M.max(0, (Window.scroll or 0) - 1)
    elseif name == "dp_d_scroll_down" then
        Window.scroll = M.min(Window.max_scroll or 0, (Window.scroll or 0) + 1)
    elseif string.find(name, "^dp_d_scroll_%d") then
        local k = tonumber(string.sub(name, 13))
        Window.scroll = M.round((k - 1) * (Window.max_scroll or 0) / M.max(1, LAYOUT.scroll_segs - 1))
    elseif string.find(name, "^dp_d_[lr]_zoom$") or string.find(name, "^dp_d_[lr]_capital") then
        local world = Window.capital[string.sub(name, 6, 6)]
        if world and Window.show_on_map(world) then
            return
        end
    elseif (name == "dp_d_open" or name == "dp_d_open_c") then
        if Window.world and Window.world.kind == "INDEPENDENT" then
            local planet = FindPlanet(Window.world.world)
            local faction, why = nil, Window.world.label .. " is no longer on the map."
            if planet then
                faction, why = Worlds.open(d, planet)
            end
            if faction then
                Window.world, Window.target, Window.deal, Window.bubble, Window.act_scroll = nil, faction, {}, nil, 0
                Window.mode, Window.pick = "deal", nil
                Window.talking = faction
                greet(d)
            else
                Window.feedback = why
            end
        elseif Window.world then
            Window.feedback = Window.world.label .. " is held by minor warlords. They will not negotiate."
        elseif Window.target and Diplomacy.refuses_talks(Window.target, d.human) then
            Window.feedback = d.display_name(Window.target) .. " will not negotiate with you."
        elseif Window.target and Deals.locked(d, Window.target) then
            Window.feedback = d.display_name(Window.target) .. " is sealed away: no envoy can reach them."
        elseif Window.target then
            Window.mode, Window.pick = "deal", nil
            greet(d)
        else
            Window.feedback = "Select a faction first."
        end
    elseif string.find(name, "^dp_d_sp[oi]") then
        dismiss_bubble()
    elseif Window.proposal and (name == "dp_d_propose" or name == "dp_d_clear") then
        local offer = Window.proposal
        Window.proposal, Window.deal = nil, {}
        local _, message
        if name == "dp_d_propose" then
            _, message = Proposals.accept(d, offer)
        else
            _, message = Proposals.decline(d, offer)
        end
        Window.feedback = message
        local next_offer = Proposals.first(d)
        if next_offer then
            Window.show_offer(d, next_offer)
            Window.feedback = message
        else
            Window.mode = "list"
        end
    elseif name == "dp_d_back" then
        Window.proposal, Window.deal = nil, {}
        Window.mode, Window.pick, Window.bubble = "list", nil, nil
    elseif name == "dp_d_clear" then
        Window.deal = {}
    elseif name == "dp_d_decree" or name == "dp_d_decree_label" then
        Window.decree = not Window.decree
    elseif name == "dp_d_act_up" or name == "dp_d_act_down" then
        local v = (Window.act_scroll or 0) + ((name == "dp_d_act_up") and -1 or 1)
        Window.act_scroll = M.max(0, M.min(Window.act_max or 0, v))
    elseif string.find(name, "^dp_d_act_%d+$") then
        local a = Window.actions and Window.actions[tonumber(string.sub(name, 10))]
        if a and not a.usable then
            Window.feedback = a.why
        elseif a and a.item then
            local item = {}
            for k, v in pairs(a.item) do
                item[k] = v
            end
            add_item(item)
        elseif a and a.pick then
            Window.pick, Window.page = a.pick, 1
        elseif a and a.act == "WAR" then
            local declared, message = Deals.declare_war(d, Window.target, Window.decree)
            Window.feedback = message
            if declared then
                speak(d, "war")
            end
        elseif a and a.act == "END_ALLIANCE" then
            local _, message = Deals.break_alliance(d, Window.target)
            Window.feedback = message
        elseif a and a.act == "END_TRADE" then
            local _, message = require("eawx-plugins/diplomacy/DiplomacyTrade").cancel(d, Window.target, ", by your choice")
            Window.feedback = message
        elseif a and a.act == "CLOSE_BORDERS" then
            Deals.set_borders(d, Window.target, false)
            Window.feedback = "Borders with " .. d.display_name(Window.target) .. " closed."
        elseif a and a.act == "END_PROTECTION" and protectorates() then
            local _, message = protectorates().withdraw(d, Window.target)
            Window.feedback = message
        end
    elseif string.find(name, "^dp_d_pick_%d") and Window.pick == "joinwar" then
        local _, _, k = string.find(name, "^dp_d_pick_(%d+)")
        local faction = Window.pick_factions and Window.pick_factions[tonumber(k)]
        if faction then
            local i = has_item("JOINWAR")
            if i then
                table.remove(Window.deal, i)
            end
            add_item({kind = "JOINWAR", side = "demand", target = faction})
            Window.pick = nil
        end
    elseif string.find(name, "^dp_d_pick_%d") then
        local _, _, k = string.find(name, "^dp_d_pick_(%d+)")
        local world = Window.pick_worlds and Window.pick_worlds[tonumber(k)]
        if Window.pick_barred and Window.pick_barred[tonumber(k)] then
            world = nil
        end
        if world then
            for _, item in ipairs(Window.deal) do
                if item.kind == "WORLD" and item.world == world then
                    world = nil
                end
            end
            if world then
                add_item({kind = "WORLD", side = Window.pick, world = world})
            end
            Window.pick = nil
        end
    elseif name == "dp_d_pick_more" then
        Window.page = Window.page + 1
    elseif name == "dp_d_pick_back" then
        Window.pick = nil
    elseif string.find(name, "^dp_d_offer_") or string.find(name, "^dp_d_demand_") then
        local _, _, side, k, x = string.find(name, "^dp_d_(%a+)_(%d+)(_?x?)$")
        local index = side and Window.slots and Window.slots[side] and Window.slots[side][tonumber(k)]
        if index then
            if x == "_x" then
                table.remove(Window.deal, index)
            else
                cycle(Window.deal[index])
            end
        end
    elseif name == "dp_d_propose" then
        local ok, message, reaction = Deals.propose(d, Window.target, Window.deal, Window.decree)
        Window.feedback = message
        if ok then
            Window.deal = {}
        end
        if reaction then
            speak(d, Speech.reaction_tier(reaction))
        end
    end
    Window.render(d)
end

function Window.select_faction(d, faction)
    for _, tab in ipairs({"major", "minor"}) do
        local list = (tab == "major") and factions(d, DiplomacyAI.context(d.display_name)) or minor_factions(d)
        for i, f in ipairs(list) do
            if f.name == faction then
                Window.tab, Window.world, Window.target, Window.deal, Window.bubble = tab, nil, faction, {}, nil
                Window.scroll = M.min(Window.max_scroll or i, M.max(0, i - LAYOUT.rows))
                return true
            end
        end
    end
    return false
end

return Window
