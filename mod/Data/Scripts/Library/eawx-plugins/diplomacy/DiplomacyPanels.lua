require("eawx-util/StoryUtil")
local Pause = require("eawx-plugins/diplomacy/DiplomacyPause")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local Senate = require("eawx-plugins/diplomacy/DiplomacySenate")
local Missions = require("eawx-plugins/diplomacy/DiplomacyMissions")
local FACTIONS = require("eawx-plugins/diplomacy/DiplomacyFactions")
local SenateWindow = require("eawx-plugins/diplomacy/DiplomacySenateWindow")
local DiplomacyWindow = require("eawx-plugins/diplomacy/DiplomacyWindow")
local KajidicWindow = require("eawx-plugins/diplomacy/DiplomacyKajidicWindow")
local UnderworldPanel = require("eawx-plugins/diplomacy/DiplomacyUnderworldPanel")
local Underworld = require("eawx-plugins/diplomacy/DiplomacyUnderworld")
local Income = require("eawx-plugins/diplomacy/DiplomacyIncome")
local Deals = require("eawx-plugins/diplomacy/DiplomacyDeals")
local PANEL = require("eawx-plugins/diplomacy/DiplomacyPanelLayout")
local Clicks = require("eawx-plugins/diplomacy/DiplomacyClicks")
local Proposals = require("eawx-plugins/diplomacy/DiplomacyProposals")
local Rebellion = require("eawx-plugins/diplomacy/DiplomacyRebellion")

local function court_window()
    local ok, window = pcall(require, "eawx-plugins/imperial-court/CourtWindow")
    return ok and window or nil
end

local Panels = {}

local PLOT = "Conquests\\Events\\MissionRepository.xml"
local STATES = {WAR = "At war", CEASEFIRE = "At peace", ALLIANCE = "Allied", VASSAL = "Your vassal"}

local INTERNAL = {
    REBEL = "The Senate - the New Republic's Senate: cohesion, blocs and how every seat leans.",
    HUTT_CARTELS = "The Kajidii - the great crime families of Hutt Space and the worlds they hold.",
    EMPIRE = "The Imperial Court - the Moffs and Grand Moffs, the court offices, the factions and the race for legitimacy.",
}

local function share(d)
    DIPLOMACY_DISPLAY_NAME = function(faction_name)
        return d.display_name(faction_name)
    end
    DIPLOMACY_PLANET_NAME = function(planet)
        return d:planet_name(planet)
    end
    DIPLOMACY_UNIT_NAME = function(type_name)
        return d.unit_name(type_name)
    end
    DIPLOMACY_RENAME = function(faction_name, display_name)
        return d.rename(faction_name, display_name)
    end
    DIPLOMACY_SET_RELATION = function(faction_name, relation)
        return d:set_relation(faction_name, relation, nil, true)
    end
    DIPLOMACY_REBELLION = function(planet, reason)
        return Rebellion.queue(d, planet, nil, reason)
    end
    DIPLOMACY_LEADER = function(faction_name)
        local ok, leaders = pcall(require, "eawx-plugins/diplomacy/DiplomacyLeaders")
        local player = Find_Player(faction_name)
        for _, entry in ipairs(ok and leaders[string.upper(faction_name)] or {}) do
            local unit = Find_First_Object(entry.type)
            if unit and TestValid(unit) and unit.Get_Owner() == player then
                return unit
            end
        end
        return nil
    end
    DIPLOMACY_CAPITAL = function(faction_name)
        local player = Find_Player(faction_name)
        return player and Deals.capital(d, player) or nil
    end
    DIPLOMACY_RELATION = function(faction_name)
        return d:relation(string.upper(faction_name))
    end
    require("eawx-plugins/diplomacy/DiplomacyOpinions").share()
    require("eawx-plugins/diplomacy/DiplomacyReputation").share()
end

function Panels.setup(d)
    local plot = Get_Story_Plot(PLOT)
    if not plot then
        return false
    end
    if Engine_Set_Text then
        local tip = INTERNAL[d.human.Get_Faction_Name()]
            or ("Internal Affairs - " .. d.display_name(d.human.Get_Faction_Name())
                .. "'s inner workings (coming in a later version).")
        pcall(Engine_Set_Text, "TEXT_TOOLTIP_SENATE_PANEL", tip)
    end
    pcall(DiplomacyWindow.close)
    pcall(SenateWindow.close)
    pcall(KajidicWindow.close)
    local Court = court_window()
    if Court then
        pcall(Court.close)
    end
    pcall(share, d)
    Panels.listen(d)
    Panels.place(d)
    return true
end

Panels.disabled = {}
function Panels.set_disabled(name, off)
    off = off and true or nil
    if Panels.disabled[name] == off then
        return
    end
    Panels.disabled[name] = off
    if Panels.pressed ~= name then
        pcall(GUI_Component_Enable, name, not off)
    end
end

function Panels.press_look()
    if not Engine_Gui_Pressed then
        return
    end
    local held = Engine_Gui_Pressed() ~= nil
    if held == Panels.held then
        return
    end
    Panels.held = held
    if Panels.pressed then
        pcall(GUI_Component_Enable, Panels.pressed, not Panels.disabled[Panels.pressed])
        Panels.pressed = nil
    end
    if held then
        local name = Clicks.pick()
        if name and not string.find(name, "shield$") and not Panels.disabled[name] then
            Panels.pressed = name
            pcall(GUI_Component_Enable, name, false)
        end
    end
end

local SUFFIXES = {"", "_e"}

local function set_pair(key, visible)
    for _, suffix in ipairs(SUFFIXES) do
        for _, button in ipairs({"b_diplomacy_panel_", "b_senate_panel_"}) do
            pcall(GUI_Component_Visibility, button .. key .. suffix, visible)
        end
    end
end

function Panels.show_pair(key)
    for _, off in ipairs(PANEL.offsets) do
        local other = string.format("%03d", off)
        set_pair(other, other == key)
    end
    set_pair("v", key == "v")
end

function Panels.place(d)
    if not Engine_Screen_Size then
        return
    end
    local w, h = Engine_Screen_Size()
    if not w or not h or h <= 0 then
        return
    end
    if w == Panels.screen_w and h == Panels.screen_h and Panels.pair then
        Panels.show_pair(Panels.pair)
        return
    end
    Panels.screen_w, Panels.screen_h = w, h
    local width = 768 * w / h
    local target = (width - PANEL.edge) / 2
    local key = "v"
    if target >= PANEL.half_width then
        local best = nil
        for _, off in ipairs(PANEL.offsets) do
            if not best or M.abs(off - target) < M.abs(best - target) then
                best = off
            end
        end
        key = string.format("%03d", best)
    end
    Panels.pair = key
    Panels.show_pair(key)
    if Engine_Log then
        Engine_Log("PANEL buttons for " .. w .. "x" .. h .. ": " .. key .. " (gap centre " .. M.round(target) .. ")")
    end
end

function Panels.listen(d)
    DiplomacyGuiClick = function(name, button)
        name = Clicks.name(name)
        if not name then
            return
        end
        local ok, err = pcall(function()
            local hutts = d.human.Get_Faction_Name() == "HUTT_CARTELS"
            local Court = court_window()
            local court = Court and d.human.Get_Faction_Name() == "EMPIRE"
            if string.find(name, "^b_") and Court and Court.open_now and not string.find(name, "^b_senate_panel") then
                Court.close()
            end
            if string.find(name, "^dp_i[a-z]?_") and Court then
                Court.click(d, name, button)
            elseif court and string.find(name, "^b_senate_panel") then
                if DiplomacyWindow.open_now then
                    DiplomacyWindow.close()
                end
                Court.click(d, name, button)
            elseif string.find(name, "^dp_nr_") then
                local ok_w, W = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
                if ok_w and W then
                    W.click(d, name, button)
                end
            elseif string.find(name, "^dp_hp_") then
                local ok_hp, Hardpoints_Menu = pcall(require, "eawx-plugins/hardpoints/Hardpoints")
                if ok_hp and Hardpoints_Menu then
                    Hardpoints_Menu.click(d, name, button)
                end
            elseif string.find(name, "^dp_uw%d") then
                UnderworldPanel.click(d, name, button)
            elseif string.find(name, "^dp_cl%d") then
                if IMPERIAL_COURT_PANEL_CLICK and button ~= "right" then
                    IMPERIAL_COURT_PANEL_CLICK(name)
                end
            elseif string.find(name, "^dp_d_") or string.find(name, "^b_diplomacy_panel") then
                if string.find(name, "^b_") and SenateWindow.open_now then
                    SenateWindow.close()
                end
                local ok_w, W = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
                if string.find(name, "^b_") and ok_w and W and W.open_now then
                    W.close()
                end
                if string.find(name, "^b_") and KajidicWindow.open_now then
                    KajidicWindow.close()
                end
                DiplomacyWindow.click(d, name, button)
            elseif string.find(name, "^dp_kf?_") or (hutts and string.find(name, "^b_senate_panel")) then
                if string.find(name, "^b_") and DiplomacyWindow.open_now then
                    DiplomacyWindow.close()
                end
                KajidicWindow.click(d, name, button)
            else
                if string.find(name, "^b_senate_panel") and DiplomacyWindow.open_now then
                    DiplomacyWindow.close()
                end
                local ok_w, W = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
                if string.find(name, "^b_") and ok_w and W and W.open_now then
                    W.close()
                    if string.find(name, "^b_senate_panel") then
                        return
                    end
                end
                if string.find(name, "^b_senate_panel") and not d:senate_active() then
                    if button ~= "right" then
                        Panels.show_internal(d)
                    end
                    return
                end
                SenateWindow.click(d, name, button)
            end
        end)
        if not ok and Engine_Log then
            Engine_Log("WINDOW click error: " .. tostring(err))
        end
    end
    DiplomacyGuiTick = function(ms)
        pcall(Pause.tick, ms)
        local ok_c, Cutscenes = pcall(require, "eawx-plugins/diplomacy/DiplomacyCutscenes")
        if ok_c and Cutscenes then
            pcall(Cutscenes.tick, ms)
        end
        local ok_uw, err_uw = pcall(UnderworldPanel.tick, d,
            DiplomacyWindow.open_now or KajidicWindow.open_now or SenateWindow.open_now)
        if not ok_uw and Engine_Log and err_uw ~= Panels.last_uw_error then
            Panels.last_uw_error = err_uw
            Engine_Log("UNDERWORLD PANEL error: " .. tostring(err_uw))
        end
        if IMPERIAL_COURT_PANEL_TICK then
            pcall(IMPERIAL_COURT_PANEL_TICK, DiplomacyWindow.open_now or SenateWindow.open_now)
        end
        if DiplomacyWindow.flash_hold or Proposals.drawn_count then
            pcall(Proposals.draw, d, Panels.pair)
        end
        local ok_hp, Hardpoints_Menu = pcall(require, "eawx-plugins/hardpoints/Hardpoints")
        if ok_hp and Hardpoints_Menu then
            pcall(Hardpoints_Menu.tick, d)
        end
        local ok_r, Republic_Window = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
        if ok_r and Republic_Window and Republic_Window.open_now then
            pcall(Republic_Window.tick)
        end
        if SenateWindow.open_now then
            pcall(SenateWindow.tick)
        end
        local ok, err = pcall(DiplomacyWindow.tick, ms)
        if not ok then
            if Engine_Log then
                Engine_Log("WINDOW tick error: " .. tostring(err))
            end
            if Engine_Gui_Tick then
                Engine_Gui_Tick(0)
            end
        end
        pcall(Panels.press_look)
    end
    if Engine_Gui_Listen then
        Engine_Gui_Listen("dp_,b_senate_panel,b_diplomacy_panel")
    end
    local follows = d.human.Get_Faction_Name() == "HUTT_CARTELS" or (d.human.Get_Faction_Name() == "EMPIRE"
        and IMPERIAL_COURT_PANEL_TICK ~= nil)
    if follows and Engine_Gui_Tick then
        DiplomacyWindow.tick_hold = true
        Engine_Gui_Tick(1)
    end
end

function Panels.update(d)
    if not d.panels_ready then
        d.panels_ready = Panels.setup(d)
    end
    pcall(Panels.place, d)
    pcall(UnderworldPanel.tick, d, DiplomacyWindow.open_now or KajidicWindow.open_now or SenateWindow.open_now)
    if IMPERIAL_COURT_PANEL_TICK then
        pcall(IMPERIAL_COURT_PANEL_TICK, DiplomacyWindow.open_now or SenateWindow.open_now)
    end
    pcall(Income.update, d)
    local ok, err = pcall(Deals.update, d)
    if not ok and Engine_Log then
        Engine_Log("DEALS error: " .. tostring(err))
    end
    if d:senate_active() then
        local debate = d.senate.debate
        if debate and debate ~= SenateWindow.seen_debate and not SenateWindow.open_now then
            SenateWindow.left, SenateWindow.right = "motion", "seat"
            SenateWindow.open(d)
        end
        Panels.last_debate = debate
        SenateWindow.update(d)
        local ok_w, W = pcall(require, "eawx-plugins/new-republic/RepublicWindow")
        if ok_w and W then
            W.update(d)
        end
    end
end

local function world_count(player)
    local count = 0
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            count = count + 1
        end
    end
    return count
end

function Panels.show_diplomacy(d)
    local human_name = d.human.Get_Faction_Name()
    local lines = {}
    local groups = {VASSAL = {}, ALLIANCE = {}, CEASEFIRE = {}, WAR = {}}
    for name, _ in pairs(FACTIONS.PLAYABLE) do
        local player = name ~= human_name and Find_Player(name)
        local worlds = player and world_count(player) or 0
        if worlds > 0 then
            local relation = d:relation(name)
            table.insert(groups[relation], d.display_name(name) .. " (" .. worlds
                .. (worlds == 1 and " world)" or " worlds)"))
        end
    end
    for _, relation in ipairs({"VASSAL", "ALLIANCE", "CEASEFIRE", "WAR"}) do
        if groups[relation][1] then
            table.sort(groups[relation])
            table.insert(lines, STATES[relation] .. ": " .. table.concat(groups[relation], ", ") .. ".")
        end
    end

    local vassals = {}
    for name, _ in pairs(d.vassal_worlds) do
        local planet = FindPlanet(name)
        if planet then
            table.insert(vassals, d:planet_name(planet))
        end
    end
    table.sort(vassals)
    table.insert(lines, "")
    if vassals[1] then
        table.insert(lines, "Vassal worlds under your protection (" .. table.getn(vassals) .. "): "
            .. table.concat(vassals, ", ") .. ".")
    else
        table.insert(lines, "No single worlds are under your protection yet: offer it to an independent world in "
            .. "the Diplomacy window.")
    end

    local appeals = {}
    for name, _ in pairs(d.appeals or {}) do
        local planet = FindPlanet(name)
        if planet and Missions.has_appeal(d, name) then
            table.insert(appeals, d:planet_name(planet))
        end
    end
    if appeals[1] then
        table.sort(appeals)
        table.insert(lines, "Worlds asking to join you: " .. table.concat(appeals, ", ") .. ".")
    end
    table.insert(lines, "")
    table.insert(lines, "Between the other powers:")
    local ok_g, Galaxy = pcall(require, "eawx-plugins/diplomacy/DiplomacyGalaxy")
    if ok_g then
        for _, line in ipairs(Galaxy.report(d)) do
            table.insert(lines, line)
        end
    end
    table.insert(lines, "")
    table.insert(lines, "Open the Diplomacy window to negotiate: ceasefires, alliances, vassalage and trade.")
    M.show_document(lines, "Diplomacy", "The state of the galaxy as the " .. d.display_name(human_name)
        .. "'s envoys see it.")
end

function Panels.show_internal(d)
    local human_name = d.human.Get_Faction_Name()
    if human_name == "REBEL" then
        if SenateWindow.open_now then
            SenateWindow.close()
        else
            SenateWindow.open(d)
        end
        return
    end
    M.show_document({
        "Every faction will have its own inner workings here: the court of an empire, the cartel's "
            .. "families, a warlord's officers.",
        "This one is still being drafted; it arrives in a later version of the Diplomacy submod.",
    }, "Internal Affairs", d.display_name(human_name) .. ": the inner workings of your government.")
end

return Panels
