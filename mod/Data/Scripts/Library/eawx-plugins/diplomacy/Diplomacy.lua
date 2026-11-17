require("deepcore/std/class")
require("eawx-util/StoryUtil")
require("eawx-util/ChangeOwnerUtilities")
require("eawx-plugins/diplomacy/DiplomacyAI")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local BUILD = require("eawx-plugins/diplomacy/DiplomacyBuild")
local FACTION_NAMES = require("eawx-plugins/diplomacy/FactionNames")
local FACTIONS = require("eawx-plugins/diplomacy/DiplomacyFactions")
local Safety = require("eawx-plugins/diplomacy/DiplomacySafety")
local Grants = require("eawx-plugins/diplomacy/DiplomacyGrants")
local Occupation = require("eawx-plugins/diplomacy/DiplomacyOccupation")
local Missions = require("eawx-plugins/diplomacy/DiplomacyMissions")
local Senate = require("eawx-plugins/diplomacy/DiplomacySenate")
local Reputation = require("eawx-plugins/diplomacy/DiplomacyReputation")
local Rebellion = require("eawx-plugins/diplomacy/DiplomacyRebellion")
local Panels = require("eawx-plugins/diplomacy/DiplomacyPanels")
local Underworld = require("eawx-plugins/diplomacy/DiplomacyUnderworld")
local Fallen = require("eawx-plugins/diplomacy/DiplomacyFallen")
local WarMissions = require("eawx-plugins/diplomacy/DiplomacyWarMissions")
local WarlordDeath = require("eawx-plugins/diplomacy/DiplomacyWarlordDeath")
local Worlds = require("eawx-plugins/diplomacy/DiplomacyWorlds")
local Opinions = require("eawx-plugins/diplomacy/DiplomacyOpinions")
local Galaxy = require("eawx-plugins/diplomacy/DiplomacyGalaxy")
local Allies = require("eawx-plugins/diplomacy/DiplomacyAllies")
require("eawx-events/GenericPopup")
local renamed = {}

Diplomacy = class()

local ENVOY = "DIPLOMACY_ENVOY"
local INDEPENDENT = "INDEPENDENT_FORCES"
local WARLORDS = "WARLORDS"

local WARLORD_FACTIONS = {}
do
    local ok, data = pcall(require, "eawx-plugins/warlords/WarlordFactions")
    if ok and type(data) == "table" then
        for _, warlord in ipairs(data.WARLORDS) do
            WARLORD_FACTIONS[warlord.faction] = true
        end
        for _, slot in ipairs(data.BREAKAWAY or {}) do
            WARLORD_FACTIONS[slot.faction] = true
        end
    end
end
function Diplomacy.publish_names()
    local keys = {INDEPENDENT_FORCES = true}
    for _, group in ipairs({FACTIONS.PLAYABLE or {}, FACTIONS.MINOR or {}, WARLORD_FACTIONS}) do
        for key in pairs(group) do
            keys[string.upper(key)] = true
        end
    end
    for key in pairs(keys) do
        GlobalValue.Set("DP_NAME_" .. key, Diplomacy.display_name(key))
        if DIPLOMACY_EMBLEM then
            GlobalValue.Set("DP_EMBLEM_" .. key, DIPLOMACY_EMBLEM(key))
        end
    end
end

function Diplomacy.refuses_talks(faction_name, human)
    return faction_name == WARLORDS
        or (WARLORD_FACTIONS[faction_name] == true and human.Get_Faction_Name() ~= "EMPIRE")
end
function Diplomacy.warlord_factions()
    return WARLORD_FACTIONS
end
local VASSAL_FACTION = "DIPLOMACY_VASSALS"

local STEP = {WAR = 0, CEASEFIRE = 1, ALLIANCE = 2, PROTECTORATE = 2, VASSAL = 3}

local NOUNS = {CEASEFIRE = "ceasefire", ALLIANCE = "alliance", VASSAL = "vassalage", PROTECTORATE = "protection"}
local STATES = {WAR = "at war", CEASEFIRE = "at peace", ALLIANCE = "allied", VASSAL = "your vassal",
                PROTECTORATE = "under your protection"}

local VERBS = {
    CEASEFIRE = "has agreed a ceasefire with",
    ALLIANCE = "has formed an alliance with",
    VASSAL = "has made a vassal of",
    PROTECTORATE = "has taken under its protection",
    WAR = "has declared war on",
}

local function protectorates()
    local ok, P = pcall(require, "eawx-plugins/new-republic/RepublicProtectorates")
    return ok and type(P) == "table" and P or nil
end

local TRIBUTE_SHARE = 0.25
local BORDER_CHECK_SECONDS = 1
local CAMPAIGN_END_GUARD_FROM = 120

local COLOR = {r = 255, g = 220, b = 120}
local COLOR_WARN = {r = 255, g = 120, b = 100}
local COLOR_DEBUG = {r = 150, g = 200, b = 255}
local COLOR_ERROR = {r = 255, g = 80, b = 80}

local function register_vassal_factions()
    local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
    local C = ModContentLoader.get("GameConstants")
    local VASSALS = require("eawx-plugins/diplomacy/DiplomacyVassals")
    local registered = {}
    for _, vassal in ipairs(VASSALS) do
        table.insert(registered, vassal)
    end
    table.insert(registered, require("eawx-plugins/diplomacy/DiplomacyInsurgents"))
    local copy_from = "INDEPENDENT_FORCES"
    local copied = {"ALL_FACTIONS_CAPITALS", "ALL_FACTIONS_BASIC_STRUCTURES", "ALL_FACTIONS_AI",
                    "ALL_FACTIONS_CRUEL_AI", "TRANSPORTS"}
    for _, vassal in ipairs(registered) do
        local key = vassal.name
        if C.ALL_FACTION_NAMES then C.ALL_FACTION_NAMES[key] = vassal.display end
        if C.ALL_FACTION_TEXTS then C.ALL_FACTION_TEXTS[key] = vassal.text end
        if C.FACTION_COLORS then C.FACTION_COLORS[key] = vassal.color end
        if C.ALL_FACTIONS_AI then C.ALL_FACTIONS_AI[key] = CONFIG.VASSAL_AI end
        if C.ALL_FACTIONS_CRUEL_AI then C.ALL_FACTIONS_CRUEL_AI[key] = CONFIG.VASSAL_AI end
        if C.ALL_FACTION_ABBREVIATIONS then C.ALL_FACTION_ABBREVIATIONS[key] = "VAS" end
        for _, table_name in ipairs(copied) do
            local t = C[table_name]
            if type(t) == "table" and t[key] == nil then
                t[key] = t[copy_from]
            end
        end
    end
end

function Diplomacy.guard_missions(d)
    local ok = pcall(require, "eawx-util/StoryUtil")
    if not ok or type(StoryUtil) ~= "table" or type(StoryUtil.FindTargetPlanet) ~= "function"
            or StoryUtil.__diplomacy_guarded then
        return
    end
    StoryUtil.__diplomacy_guarded = true
    local find = StoryUtil.FindTargetPlanet
    StoryUtil.FindTargetPlanet = function(player, connected, fortress, amount, active_only, excluded, required)
        local p = (type(player) == "string") and Find_Player(player) or player
        if amount == 1 and p and p == d.human and not required then
            local out = {}
            for _, f in ipairs(excluded or {}) do
                table.insert(out, f)
            end
            for _, f in pairs(ModContentLoader.get("GameConstants").ALL_FACTIONS_NOT_NEUTRAL or {}) do
                if string.upper(f) ~= string.upper(d.human.Get_Faction_Name()) and d:relation(f) ~= "WAR" then
                    table.insert(out, f)
                end
            end
            excluded = out
        end
        return find(player, connected, fortress, amount, active_only, excluded, required)
    end
end

function Diplomacy:new(gc)
    local ok, err = pcall(register_vassal_factions)
    if not ok then
        Diplomacy.report_error("REGISTER", err)
    end
    ok, err = pcall(Worlds.register)
    if not ok then
        Diplomacy.report_error("REGISTER", err)
    end
    if Engine_Planet_Income_Off then
        Engine_Planet_Income_Off()
    end
    self.gc = gc
    self.human = gc.HumanPlayer
    pcall(Diplomacy.guard_missions, self)
    Reputation.set_human(self.human.Get_Faction_Name())
    local me = self
    Reputation.relation_of = function(a, b)
        local us = me.human.Get_Faction_Name()
        if a == us then
            return me:relation(b)
        elseif b == us then
            return me:relation(a)
        end
        return nil
    end
    self.relations = {}
    self.vassal_credits = {}
    self.vassal_worlds = {}
    self.next_world_income = 0
    self.next_border_check = 0
    self.announced = false
    self.own_transfers = {}
    self.occupation = {}
    self.occupation_hooks = {}
    self.appeals = {}
    self.quiet_news = {}
    self.memory = {
        aggression = {},
        heroes = {},
        betrayals = {},
        peace_since = {},
        independent_attacks = {},
        lost_vassals = {},
        signed = {},
        ended_alliance = {},
    }

    gc.Events.GalacticProductionFinished:attach_listener(self.on_production_finished, self)
    gc.Events.PlanetOwnerChanged:attach_listener(self.on_planet_owner_changed, self)
    gc.Events.GalacticHeroKilled:attach_listener(self.on_hero_killed, self)
    gc.Events.TacticalBattleEnded:attach_listener(self.on_battle_end, self)
    crossplot:subscribe("SENATE_MOTION_OPTION", self.on_senate_choice, self)
    crossplot:subscribe("ALLY_CALL_OPTION", self.on_ally_call, self)
    crossplot:subscribe("CONQUEST_OPTION", self.on_conquest_choice, self)
    crossplot:subscribe("FACTION_DISPLAY_NAME_CHANGE", self.on_display_name_change, self)
    crossplot:subscribe("HUTT_UPSTART_KILLED", self.on_upstart_killed, self)
    crossplot:subscribe("TACTICAL_UNIT_DESTROYED", self.on_tactical_kill, self)
    local this = self
    Opinions.set_provider(function(a, b, add)
        return require("eawx-plugins/diplomacy/DiplomacyDeals").opinion_lines(this, a, b, add)
    end)
end

function Diplomacy:on_tactical_kill(object_name)
    if object_name == "HUTT_UPSTART" then
        self:on_upstart_killed(self.human.Get_Faction_Name())
    end
end

function Diplomacy:on_upstart_killed(owner_name)
    local ok, Underworld = pcall(require, "eawx-plugins/diplomacy/DiplomacyUnderworld")
    if ok and owner_name == self.human.Get_Faction_Name() then
        Underworld.upstart_killed(self)
    end
end

local function remember(list, key)
    if not list[key] then
        list[key] = {}
    end
    table.insert(list[key], GetCurrentTime())
end

function Diplomacy:watch_owners()
    local first = self.owners == nil
    self.owners = self.owners or {}
    self.owner_handled = self.owner_handled or {}
    self.owner_players = self.owner_players or {}
    local list = Diplomacy.planet_list
    if not list then
        list = {}
        for _, planet in pairs(FindPlanet.Get_All_Planets()) do
            table.insert(list, {planet = planet, name = string.upper(planet.Get_Type().Get_Name())})
        end
        Diplomacy.planet_list = list
    end
    local me = self.human.Get_Faction_Name()
    local seen = self.owner_players
    local held, changed = 0, {}
    for _, entry in ipairs(list) do
        local planet, name = entry.planet, entry.name
        local owner = planet.Get_Owner()
        if owner == self.human then
            held = held + 1
        end
        if owner ~= seen[name] then
            seen[name] = owner
            local now = string.upper(owner.Get_Faction_Name())
            local before = self.owners[name]
            if before ~= now then
                self.owners[name] = now
                if not first and before and (now == me or before == me) then
                    table.insert(changed, {planet = planet, name = name, new = now, old = before})
                end
            end
        end
    end
    for _, c in ipairs(changed) do
        local wrapper = self.gc.Planets[c.planet.Get_Type().Get_Name()]
        if wrapper then
            self.owner_handled[c.name] = c.new
            self:on_planet_owner_changed(wrapper, c.new, c.old, true)
        end
    end
    return held
end

function Diplomacy:on_planet_owner_changed(planet, new_owner_name, old_owner_name, seen_here)
    local name = string.upper(planet:get_name())
    local ok_f, err_f = pcall(Fallen.check, self, old_owner_name, new_owner_name, name)
    if not ok_f then
        Diplomacy.report_error("FALLEN", err_f)
    end
    if Engine_Planet_Flash then
        Engine_Planet_Flash(name, 10)
    end
    local upper_new = new_owner_name and string.upper(new_owner_name)
    if not seen_here then
        if self.owner_handled and self.owner_handled[name] == upper_new then
            self.owner_handled[name] = nil
            return
        end
        if self.owners then
            self.owners[name] = upper_new
        end
    end
    pcall(Opinions.on_world_taken, name, new_owner_name, old_owner_name)
    local revolt = DIPLOMACY_REVOLTS and DIPLOMACY_REVOLTS[name]
    if revolt then
        DIPLOMACY_REVOLTS[name] = nil
        local ok_r, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
        if ok_r and type(Republic) == "table" and GetCurrentTime() - revolt.time < 30 then
            pcall(Republic.on_revolt_seen, self, name, planet:get_readable_name(),
                old_owner_name and string.upper(old_owner_name), new_owner_name and string.upper(new_owner_name),
                revolt.kind)
        end
    end
    if self:take_own_transfer(name) then
        return
    end
    local ok_uw, err_uw = pcall(Underworld.on_owner_changed, self, planet:get_game_object(), new_owner_name, old_owner_name)
    if not ok_uw then
        Diplomacy.report_error("UNDERWORLD", err_uw)
    end
    local P = protectorates()
    if P then
        local ok_p, err_p = pcall(P.on_owner_changed, self, name, new_owner_name, old_owner_name)
        if not ok_p then
            Diplomacy.report_error("PROTECTORATE", err_p)
        end
        if new_owner_name == self.human.Get_Faction_Name() and P.reclaimed(self, name) then
            pcall(P.hand_back, self, name)
            return
        end
    end
    if self.vassal_worlds[name] then
        self.vassal_worlds[name] = nil
        table.insert(self.memory.lost_vassals, GetCurrentTime())
        Diplomacy.show("Diplomacy: " .. Diplomacy.display_name(new_owner_name) .. " has taken your vassal world "
            .. planet:get_readable_name() .. ". Other independent worlds trust your protection less.", nil, COLOR_WARN)
    end
    Occupation.stop(self, name)
    local ok_c, Conquest = pcall(require, "eawx-plugins/diplomacy/DiplomacyConquest")
    if ok_c and Conquest.applies(self, name, new_owner_name, old_owner_name) then
        Conquest.ask(self, name, planet:get_readable_name(), old_owner_name)
        return
    end
    self:conquest_effects(name, planet:get_readable_name(), new_owner_name, old_owner_name)
end

function Diplomacy:conquest_effects(name, readable, new_owner_name, old_owner_name)
    if self:senate_active() then
        if new_owner_name == self.human.Get_Faction_Name() then
            pcall(Senate.on_conquest, self, readable, old_owner_name and string.upper(old_owner_name), name)
        elseif old_owner_name and string.upper(old_owner_name) == self.human.Get_Faction_Name() then
            pcall(Senate.on_world_lost, self, name, readable)
        end
    end
    local welcomed = self.republic and self.republic.conquered and self.republic.conquered[name]
        and self.republic.conquered[name].content and GetCurrentTime() - self.republic.conquered[name].time < 5
    if new_owner_name == self.human.Get_Faction_Name() and not welcomed
            and Occupation.applies(new_owner_name, old_owner_name) then
        Occupation.start(self, name, readable)
    end
    if new_owner_name == self.human.Get_Faction_Name() and old_owner_name then
        local old = string.upper(old_owner_name)
        remember(self.memory.aggression, old)
        if old == INDEPENDENT then
            table.insert(self.memory.independent_attacks, GetCurrentTime())
        end
    end
end

function Diplomacy:on_hero_killed(hero_name, owner_name, killer_name)
    pcall(Opinions.on_hero_killed, owner_name, killer_name)
    if killer_name == self.human.Get_Faction_Name() and owner_name then
        remember(self.memory.heroes, string.upper(owner_name))
    end
    local ok, err = pcall(WarlordDeath.on_hero_killed, self, hero_name, owner_name)
    if not ok then
        Diplomacy.report_error("WARLORD_DEATH", err)
    end
    if self.republic then
        local ok_r, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
        local Laws = ok_r and Republic and Republic.part("laws")
        if Laws then
            pcall(Laws.on_hero_killed, self, owner_name, killer_name)
        end
    end
end

Diplomacy.crests = {}
function Diplomacy:on_display_name_change(faction_name, display_name, particle)
    if faction_name and particle then
        Diplomacy.crests[string.upper(faction_name)] = string.lower(particle)
    end
    if faction_name and display_name then
        renamed[string.upper(faction_name)] = display_name
        Diplomacy.name_vassal_faction(string.upper(faction_name), display_name)
    end
end

function Diplomacy.name_vassal_faction(overlord, display_name)
    local key = VASSAL_FACTION .. "_" .. overlord
    local C = ModContentLoader.get("GameConstants")
    if not (C.ALL_FACTION_NAMES and C.ALL_FACTION_NAMES[key]) then
        return
    end
    local short = display_name
    if string.sub(short, 1, 4) == "The " then
        short = string.sub(short, 5)
    end
    local name = short .. ((overlord == "REBEL") and " Associate Worlds" or " Vassals")
    C.ALL_FACTION_NAMES[key] = name
    if C.ALL_FACTION_TEXTS then C.ALL_FACTION_TEXTS[key] = name end
    renamed[key] = name
end

local VASSAL_LIST = require("eawx-plugins/diplomacy/DiplomacyVassals")

function Diplomacy:name_all_vassal_factions()
    for _, vassal in ipairs(require("eawx-plugins/diplomacy/DiplomacyVassals")) do
        local overlord = string.sub(vassal.name, string.len(VASSAL_FACTION) + 2)
        if overlord ~= "" and Find_Player(overlord) then
            Diplomacy.name_vassal_faction(overlord, Diplomacy.display_name(overlord))
        end
    end
end

local START_HOLD_FROM, START_HOLD_UNTIL = 5, 60

function Diplomacy:update()
    if Engine_Start_Hold then
        local now = GetCurrentTime()
        if not self.start_hold and now < START_HOLD_FROM then
            self.start_hold = true
            pcall(Engine_Start_Hold, 1)
        elseif self.start_hold and not self.start_hold_done and now >= START_HOLD_UNTIL then
            self.start_hold_done = true
            pcall(Engine_Start_Hold, 0)
        end
    end
    local ok, err = pcall(self.safe_update, self)
    if not ok then
        Diplomacy.report_error("UPDATE", err)
    end
end

function Diplomacy:stage_on(n)
    return true
end

function Diplomacy:mark(stage)
    if Engine_Log and self.trace_until and GetCurrentTime() < self.trace_until then
        Engine_Log("STAGE " .. stage .. " at " .. tostring(GetCurrentTime()))
    end
end

function Diplomacy:safe_update()
    if Safety.trace_left > 0 then
        Safety.trace_left = Safety.trace_left - 1
    end
    self:mark("begin")
    local ok_panels, err_panels = pcall(Panels.update, self)
    if not ok_panels then
        Diplomacy.report_error("PANELS", err_panels)
    end
    local ok_uw, err_uw = pcall(Underworld.update, self)
    if not ok_uw then
        Diplomacy.report_error("UNDERWORLD", err_uw)
    end
    if GetCurrentTime() >= (self.next_publish or 0) then
        self.next_publish = GetCurrentTime() + 30
        pcall(Diplomacy.publish_names)
    end
    local held = 0
    local ok_w, err_w = pcall(function()
        held = self:watch_owners()
    end)
    if not ok_w then
        Diplomacy.report_error("OWNERS", err_w)
    end
    if Engine_Set_Human_Planets then
        Engine_Set_Human_Planets(held)
    end
    local ok_m, err_m = pcall(WarMissions.patch, self)
    if not ok_m then
        Diplomacy.report_error("MISSIONS", err_m)
    end
    local ok_wd, err_wd = pcall(WarlordDeath.update, self)
    if not ok_wd then
        Diplomacy.report_error("WARLORD_DEATH", err_wd)
    end
    local ok_si, Sight = pcall(require, "eawx-plugins/diplomacy/DiplomacySight")
    if ok_si and Sight then
        local ok_s, err_s = pcall(Sight.update, self)
        if not ok_s then
            Diplomacy.report_error("SIGHT", err_s)
        end
    end
    if CONFIG.SAFETY_NET then
        Safety.on_screen = false
        Safety.protect(self.gc)
    end
    if not self:stage_on(1) then
        self:mark("stage limit 0: nothing else runs")
        return
    end
    if not self.announced then
        self.announced = true
        local vassals = self:vassal_player()
        local vassal_text = "none (vassal worlds become yours)"
        if vassals then
            vassal_text = vassals.Get_Faction_Name()
        end
        if CONFIG.INDEPENDENT_PEACE[self.human.Get_Faction_Name()] and Find_Player(INDEPENDENT) then
            Diplomacy.show("Diplomacy: the independent worlds are at peace with "
                .. Diplomacy.display_name(self.human.Get_Faction_Name()) .. ".")
        end
    end

    if not self.vassal_ai_set and GetCurrentTime() >= 5 then
        self.vassal_ai_set = true
        pcall(self.apply_starting_peace, self)
        pcall(self.name_all_vassal_factions, self)
        for _, vassal in ipairs(require("eawx-plugins/diplomacy/DiplomacyVassals")) do
            if Find_Player(vassal.name) then
                local ok = pcall(StoryUtil.ChangeAIPlayer, vassal.name, CONFIG.VASSAL_AI)
                if Engine_Log then Engine_Log("AI " .. vassal.name .. " -> " .. CONFIG.VASSAL_AI .. " " .. tostring(ok)) end
            end
        end
    end

    if not self:stage_on(2) then return end
    self:mark("treaties")
    self:apply_treaties()
    pcall(require("eawx-plugins/diplomacy/DiplomacyOpinions").apply)
    local ok_g, err_g = pcall(Galaxy.update, self)
    if not ok_g then
        Diplomacy.report_error("GALAXY", err_g)
    end
    pcall(require("eawx-plugins/diplomacy/DiplomacyConquest").tick, self)
    local ok_a, err_a = pcall(Allies.update, self)
    if not ok_a then
        Diplomacy.report_error("ALLIES", err_a)
    end
    local ok_j, err_j = pcall(require("eawx-plugins/diplomacy/DiplomacyJointInvasion").update, self)
    if not ok_j then
        Diplomacy.report_error("JOINT", err_j)
    end
    local ok_rep, err_rep = pcall(self.update_reputation, self)
    if not ok_rep then
        Diplomacy.report_error("REPUTATION", err_rep)
    end
    if not self:stage_on(3) then return end
    if not self:stage_on(4) then return end
    self:mark("tribute")
    self:collect_tribute()
    self:mark("income")
    self:collect_world_income()
    self:mark("markers")
    self:refresh_vassal_markers()
    self:mark("vassal watch")
    self:watch_vassal_worlds()
    self:mark("occupation")
    Occupation.update(self)
    self:mark("missions")
    Missions.update(self)
    self:mark("rebellion")
    if not self.rebellion_patched then
        local ok, patched = pcall(Rebellion.patch, self)
        self.rebellion_patched = not ok or patched
        if not ok then
            Diplomacy.report_error("REBELLION", patched)
        end
    end
    local ok_rebellion, err_rebellion = pcall(Rebellion.update, self)
    if not ok_rebellion then
        Diplomacy.report_error("REBELLION", err_rebellion)
    end
    self:mark("senate")
    if self.human.Get_Faction_Name() == "REBEL" then
        local ok_senate, err_senate = pcall(Senate.update, self)
        if not ok_senate then
            Diplomacy.report_error("SENATE", err_senate)
        end
        local ok_i, Intel = pcall(require, "eawx-plugins/new-republic/RepublicIntel")
        if ok_i and Intel and self.republic then
            local ok_jedi, Jedi_Order = pcall(require, "eawx-plugins/jedi-order/JediOrder")
            if ok_jedi and Jedi_Order then
                pcall(Jedi_Order.tick, self)
            end
            local ok_t, err_t = pcall(Intel.tick, self)
            if not ok_t then
                Diplomacy.report_error("REPUBLIC INTELLIGENCE", err_t)
            end
            local ok_l, Republic_ = pcall(require, "eawx-plugins/new-republic/Republic")
            local Laws = ok_l and Republic_ and Republic_.part("laws")
            if Laws then
                pcall(Laws.tick, self)
            end
        end
    else
        local ok_ai, RepublicAI = pcall(require, "eawx-plugins/new-republic/RepublicAI")
        if ok_ai and RepublicAI then
            local ok_r, err_r = pcall(RepublicAI.update, self)
            if not ok_r then
                Diplomacy.report_error("REPUBLIC AI", err_r)
            end
        end
    end

    if not self:stage_on(5) then return end
    self:mark("income check")
    if GetCurrentTime() >= self.next_border_check then
        self.next_border_check = GetCurrentTime() + BORDER_CHECK_SECONDS
        self:mark("campaign end check")
        self:prevent_campaign_end()
        self:mark("borders")
        self:enforce_borders()
    end
    self:mark("done")
end

function Diplomacy:relation(faction_name)
    if self.relations[faction_name] then
        return self.relations[faction_name]
    end
    local other = Find_Player(faction_name)
    if other and not self.human.Is_Enemy(other) then
        return "CEASEFIRE"
    end
    return "WAR"
end

function Diplomacy:apply_treaties()
    for faction_name, _ in pairs(self.relations) do
        local other = faction_name ~= self.secret_war and Find_Player(faction_name)
        if other then
            self.human.Make_Ally(other)
            other.Make_Ally(self.human)
        end
    end
    local vassals = self:vassal_player()
    if vassals then
        self.human.Make_Ally(vassals)
        vassals.Make_Ally(self.human)
    end
    if CONFIG.INDEPENDENT_PEACE[self.human.Get_Faction_Name()] and not self.rebellion_war
            and self.secret_war ~= INDEPENDENT then
        local independent = Find_Player(INDEPENDENT)
        if independent then
            self.human.Make_Ally(independent)
            independent.Make_Ally(self.human)
        end
    end
    local subjects = {}
    for faction_name, relation in pairs(self.relations) do
        if (relation == "VASSAL" or relation == "PROTECTORATE") and faction_name ~= self.secret_war then
            local other = Find_Player(faction_name)
            if other then
                table.insert(subjects, other)
            end
        end
    end
    if vassals then
        table.insert(subjects, vassals)
    end
    for i = 1, table.getn(subjects) do
        for j = i + 1, table.getn(subjects) do
            subjects[i].Make_Ally(subjects[j])
            subjects[j].Make_Ally(subjects[i])
        end
    end
    local human_name = self.human.Get_Faction_Name()
    for _, vassal in ipairs(VASSAL_LIST) do
        local overlord_name = string.sub(vassal.name, string.len(VASSAL_FACTION) + 2)
        if overlord_name ~= "" and overlord_name ~= human_name then
            local overlord, subject = Find_Player(overlord_name), Find_Player(vassal.name)
            if overlord and subject then
                overlord.Make_Ally(subject)
                subject.Make_Ally(overlord)
            end
        end
    end
end

function Diplomacy:vassal_player()
    if self.vassal_name == nil then
        self.vassal_name = false
        local built = {}
        for _, vassal in ipairs(require("eawx-plugins/diplomacy/DiplomacyVassals")) do
            built[vassal.name] = true
        end
        for _, name in ipairs({VASSAL_FACTION .. "_" .. self.human.Get_Faction_Name(), VASSAL_FACTION}) do
            if built[name] and Find_Player(name) then
                self.vassal_name = name
                break
            end
        end
    end
    if self.vassal_name then
        return Find_Player(self.vassal_name)
    end
    return nil
end

function Diplomacy:holds_vassal_world(name, owner)
    local w = self.vassal_worlds[name]
    if not (w and owner) then
        return false
    end
    if w.slot then
        return owner.Get_Faction_Name() == w.slot
    end
    return owner == self.human or owner == self:vassal_player()
end

function Diplomacy:is_vassal_faction(name)
    return string.sub(name, 1, string.len(VASSAL_FACTION)) == VASSAL_FACTION
end

function Diplomacy:apply_starting_peace()
    local mine = self.human.Get_Faction_Name()
    local friends = {}
    if not self.memory.neutral_started then
        self.memory.neutral_started = true
        for _, n in ipairs(CONFIG.NEUTRAL_START or {}) do
            if string.upper(n) ~= string.upper(mine) then
                table.insert(friends, n)
            end
        end
        pcall(Galaxy.start_neutral, self)
    end
    for leader, list in pairs(CONFIG.STARTING_PEACE or {}) do
        for _, other in ipairs(list) do
            if mine == leader then
                table.insert(friends, other)
            elseif mine == other then
                table.insert(friends, leader)
            end
        end
    end
    local holds = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        holds[planet.Get_Owner().Get_Faction_Name()] = true
    end
    local names = ""
    for _, name in ipairs(friends) do
        local player = Find_Player(name)
        if player and holds[name] and self:relation(name) == "WAR" then
            self:set_relation(name, "CEASEFIRE", nil, true)
            names = names .. (names ~= "" and ", " or "") .. Diplomacy.display_name(name)
        end
    end
    if names ~= "" then
        Diplomacy.show("Diplomacy: " .. Diplomacy.display_name(mine) .. " begins at peace with " .. names .. ".", nil, COLOR)
    end
end

function Diplomacy:set_relation(faction_name, relation, note, forced)
    local other = Find_Player(faction_name)
    if not other then
        return
    end
    local new_vassal = false
    local before = self:relation(faction_name)
    self.memory.signed = self.memory.signed or {}

    if relation == "WAR" then
        if before ~= "WAR" and not forced then
            self:reputation_breach(faction_name, before)
            table.insert(self.memory.betrayals, {faction_name, GetCurrentTime()})
            Opinions.event(faction_name, self.human.Get_Faction_Name(), "BETRAYED")
            Galaxy.on_human_war(self, faction_name)
            if self.republic and GetCurrentTime() >= CAMPAIGN_END_GUARD_FROM then
                local ok_s, Sym = pcall(require, "eawx-plugins/new-republic/RepublicSympathy")
                if ok_s and Sym and Sym.on_war then
                    pcall(Sym.on_war, self, faction_name)
                end
            end
            if self.pacts and self.pacts[faction_name] and GetCurrentTime() < self.pacts[faction_name] then
                table.insert(self.memory.betrayals, {faction_name, GetCurrentTime()})
                Opinions.event(faction_name, self.human.Get_Faction_Name(), "BETRAYED")
                self.pacts[faction_name] = nil
            end
        end
        self.memory.peace_since[faction_name] = nil
        self.relations[faction_name] = nil
        if self.open_borders then
            self.open_borders[faction_name] = nil
        end
        self.vassal_credits[faction_name] = nil
        self.human.Make_Enemy(other)
        other.Make_Enemy(self.human)
        local ok_trade, Trade = pcall(require, "eawx-plugins/diplomacy/DiplomacyTrade")
        if ok_trade and Trade then
            pcall(Trade.on_war, self, faction_name)
        end
    else
        if not self.memory.peace_since[faction_name] then
            self.memory.peace_since[faction_name] = GetCurrentTime()
        end
        if before ~= relation and not forced then
            self.memory.signed[faction_name] = GetCurrentTime()
        end
        self.relations[faction_name] = relation
        self.human.Make_Ally(other)
        other.Make_Ally(self.human)
        if relation == "VASSAL" then
            new_vassal = not self.vassal_credits[faction_name]
            self.vassal_credits[faction_name] = other.Get_Credits()
        else
            self.vassal_credits[faction_name] = nil
        end
    end

    if self:senate_active() then
        pcall(Senate.on_relation, self, faction_name, relation)
    end
    if not forced then
        Diplomacy.show("Diplomacy: " .. Diplomacy.display_name(self.human.Get_Faction_Name()) .. " " .. VERBS[relation]
            .. " " .. Diplomacy.display_name(faction_name) .. "." .. (note or ""))
    end
    if new_vassal and IMPERIAL_COURT_LEGITIMACY then
        pcall(IMPERIAL_COURT_LEGITIMACY, "VASSAL_FACTION", faction_name, self.human)
    end
    if new_vassal then
        local home = StoryUtil.FindFriendlyPlanet(self.human, true)
        if home then
            self:grant_units(Grants.for_faction, faction_name, home, self.human, Diplomacy.display_name(faction_name))
        end
    end
end

function Diplomacy:reputation_drop(faction_name, ranks, cause)
    local rank, before = Reputation.drop(faction_name, ranks, cause)
    if faction_name == self.human.Get_Faction_Name() and rank ~= before then
        Diplomacy.show("Reputation: " .. Diplomacy.display_name(faction_name) .. " is now seen as "
            .. Reputation.WORDS[rank] .. ". It " .. cause .. ".", nil, COLOR_WARN, 20)
    end
end

function Diplomacy:reputation_breach(faction_name, before)
    local them = Diplomacy.display_name(faction_name)
    local now = GetCurrentTime()
    local signed = self.memory.signed and self.memory.signed[faction_name]
    local age = signed and M.floor((now - signed) / CONFIG.WEEK_SECONDS)
    local ended = self.memory.ended_alliance and self.memory.ended_alliance[faction_name]
    local R = CONFIG.REPUTATION
    if before == "VASSAL" then
        self:reputation_drop(self.human.Get_Faction_Name(), 2, "attacked its own vassal, " .. them)
    elseif before == "PROTECTORATE" then
        self:reputation_drop(self.human.Get_Faction_Name(), 2, "attacked its own protectorate, " .. them)
    elseif before == "ALLIANCE" then
        self:reputation_drop(self.human.Get_Faction_Name(), 2, "attacked its ally, " .. them)
    elseif ended and now - ended < CONFIG.WEEK_SECONDS then
        self:reputation_drop(self.human.Get_Faction_Name(), 2, "ended its alliance with " .. them
            .. " and attacked them the same week")
    elseif before == "CEASEFIRE" and age and age < R.CEASEFIRE_WEEKS then
        self:reputation_drop(self.human.Get_Faction_Name(), 1, "broke a ceasefire with " .. them .. " after "
            .. age .. " week" .. ((age == 1) and "" or "s"))
    else
        return
    end
    if self.republic then
        local ok, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
        if ok and Republic then
            Republic.change_mandate(self, -Republic.CONFIG.PROTECTORATE.END_MANDATE)
        end
        for _, w in pairs(self.vassal_worlds or {}) do
            if w.stage then
                w.content = M.max(0, (w.content or 50) - 10)
            end
        end
    end
end

function Diplomacy:update_reputation()
    if GetCurrentTime() < (self.next_reputation_week or 0) then
        return
    end
    self.next_reputation_week = M.next_week(CONFIG.WEEK_SECONDS)
    local us = self.human.Get_Faction_Name()
    for _, faction in ipairs(Reputation.update()) do
        if faction == us then
            Diplomacy.show("Reputation: " .. Diplomacy.display_name(us) .. "'s word counts for more again: now "
                .. Reputation.word(us) .. ".", nil, COLOR, 15)
        end
    end
end

function Diplomacy:senate_active()
    return self.human.Get_Faction_Name() == "REBEL" and self.senate ~= nil
end

function Diplomacy:on_battle_end(mode_name)
    pcall(Allies.on_battle_end, self)
    local ok, err = pcall(Rebellion.on_battle_end, self, mode_name)
    if not ok then
        Diplomacy.report_error("REBELLION", err)
    end
    if self:senate_active() then
        pcall(Senate.on_battle_end, self, mode_name)
    end
end

function Diplomacy:on_conquest_choice(option)
    local ok, err = pcall(require("eawx-plugins/diplomacy/DiplomacyConquest").on_choice, self, option)
    if not ok then
        Diplomacy.report_error("CONQUEST", err)
    end
end

function Diplomacy:on_ally_call(option)
    local ok, err = pcall(Allies.on_call, self, option)
    if not ok then
        Diplomacy.report_error("ALLY CALL", err)
    end
end

function Diplomacy:on_senate_choice(option)
    if self:senate_active() then
        local ok, err = pcall(Senate.on_choice, self, option)
        if not ok then
            Diplomacy.report_error("SENATE", err)
        end
    end
end

function Diplomacy:with_senate(relation, target, world, enact)
    local motion = self:senate_active() and Senate.motion_for(self, relation, target, world)
    if motion then
        local ok, reason = Senate.propose(self, motion, enact)
        if not ok then
            Diplomacy.show("Diplomacy: " .. tostring(reason) .. " Try again once it can hear a new motion.", nil,
                COLOR_WARN)
        end
    else
        enact()
    end
end

function Diplomacy:on_production_finished(planet, object_type_name)
    if self:senate_active() and planet and string.upper(object_type_name) == "JEDI_TEMPLE" then
        local ok_c, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
        local Council = ok_c and Republic and Republic.part("council")
        if Council then
            pcall(Council.on_temple_built, self)
        end
    end
    if self:senate_active() and planet and string.upper(object_type_name) == "DIPLOMACY_SENATE_CHAMBER" then
        local ok_c, Republic = pcall(require, "eawx-plugins/new-republic/Republic")
        local Council = ok_c and Republic and Republic.part("council")
        if Council then
            local ok, err = pcall(Council.on_senate_built, self, planet:get_game_object())
            if not ok then
                Diplomacy.report_error("COUNCIL", err)
            end
        end
    end
    if self:senate_active() and planet then
        local ok_m, Members = pcall(require, "eawx-plugins/new-republic/RepublicMembers")
        if ok_m and Members then
            pcall(Members.on_production, self, string.upper(planet:get_name()))
        end
    end
end

function Diplomacy:admit_world(planet, world)
    local name = string.upper(planet.Get_Type().Get_Name())
    self:transfer_world(planet, self.human, true)
    self.integrated = self.integrated or {}
    self.integrated[name] = GetCurrentTime()
    local office = self.human.Get_Faction_Name() == "REBEL" and Find_Object_Type("Rebel_Office")
    if office then
        pcall(Spawn_Unit, office, planet, self.human)
    end
    Diplomacy.show("Diplomacy: crowds fill the streets of " .. world .. " as its flag is raised beside the "
        .. Diplomacy.display_name(self.human.Get_Faction_Name()) .. "'s. It joins as a full member world, "
        .. "its defenders now yours and its senator already on the way to take a seat.", nil, COLOR, 25)
end

function Diplomacy:protect_world(planet, world)
    if self.human.Get_Faction_Name() == "REBEL" then
        local P = protectorates()
        if P then
            P.protect_world(self, planet, world)
        end
        return
    end
    do
        local new_owner = self:vassal_player() or self.human
        local stays = new_owner == self.human
        local sent_to = self:transfer_world(planet, new_owner, stays)
        self.vassal_worlds[string.upper(planet.Get_Type().Get_Name())] = {since = GetCurrentTime()}
        self:mark_vassal_world(planet)
        if IMPERIAL_COURT_LEGITIMACY then
            pcall(IMPERIAL_COURT_LEGITIMACY, "VASSAL_WORLD", nil, self.human)
        end
        Diplomacy.show("Diplomacy: " .. world .. " accepts " .. Diplomacy.display_name(self.human.Get_Faction_Name())
            .. " protection and becomes your vassal world.")
        local home = planet
        if not stays then
            home = sent_to or self:nearest_friendly_planet(self.human, planet)
        end
        if home then
            self:grant_units(Grants.for_world, string.upper(planet.Get_Type().Get_Name()), home, self.human, world)
        end
        if sent_to then
            Diplomacy.show("TEXT_DIPLOMACY_SENT_TO", sent_to)
        end
    end
end

function Diplomacy:patch_emblems()
    if type(InfluenceService) ~= "table" or InfluenceService.__diplomacy_patched then
        return
    end
    local CONSTANTS = ModContentLoader.get("GameConstants")
    local original = InfluenceService.attach_particle
    local diplomacy = self
    InfluenceService.attach_particle = function(service, planet, planet_stats)
        local owner_ok, owner_name = pcall(function() return planet:get_owner().Get_Faction_Name() end)
        if not owner_ok then
            return original(service, planet, planet_stats)
        end
        local saved = CONSTANTS.PARTICLES[owner_name]
        local vassal = diplomacy.vassal_worlds[string.upper(planet:get_name())]
        if vassal and not vassal.slot then
            CONSTANTS.PARTICLES[owner_name] = "Diplomacy_Vassal_" .. diplomacy.human.Get_Faction_Name()
        end
        local ok, err = pcall(original, service, planet, planet_stats)
        CONSTANTS.PARTICLES[owner_name] = saved
        if not ok then
            error(err)
        end
    end
    InfluenceService.__diplomacy_patched = true
end

local MARKER_SECONDS = 30
function Diplomacy:refresh_vassal_markers()
    if not self.news_patched then
        local ok, err = pcall(self.patch_news, self)
        self.news_patched = true
        if not ok then
            Diplomacy.report_error("NEWS", err)
        end
    end
    if not self.emblems_patched then
        local ok, err = pcall(self.patch_emblems, self)
        self.emblems_patched = ok and InfluenceService ~= nil
        if not ok then
            Diplomacy.report_error("EMBLEMS", err)
            self.emblems_patched = true
        end
    end
    if GetCurrentTime() < (self.next_marker or 0) then
        return
    end
    self.next_marker = GetCurrentTime() + MARKER_SECONDS
    for name, w in pairs(self.vassal_worlds) do
        local planet = FindPlanet(name)
        if planet and not w.slot then
            self:mark_vassal_world(planet)
        end
    end
end

function Diplomacy:patch_news()
    if type(GalacticEventsNewsSource) ~= "table" then
        return
    end
    local event = self.gc.Events.PlanetOwnerChanged
    local diplomacy = self
    NEWS_LISTENER_WRAPPERS = NEWS_LISTENER_WRAPPERS or {}
    for _, entry in ipairs(event.Listeners or {}) do
        if entry.Listener == GalacticEventsNewsSource.on_planet_owner_changed
                or NEWS_LISTENER_WRAPPERS[entry.Listener] then
            local original = entry.Listener
            entry.Listener = function(source, planet, a2, a3, a4)
                local name = string.upper(planet:get_name())
                local since = diplomacy.quiet_news[name]
                diplomacy.quiet_news[name] = nil
                if since and GetCurrentTime() - since < 10 then
                    return
                end
                return original(source, planet, a2, a3, a4)
            end
            NEWS_LISTENER_WRAPPERS[entry.Listener] = true
        end
    end
end

function Diplomacy:mark_vassal_world(planet)
    local ok, err = pcall(planet.Attach_Particle_Effect, "Diplomacy_Vassal_" .. self.human.Get_Faction_Name())
    if not ok then
        Diplomacy.report_error("MARKER", err)
    end
end

function Diplomacy:grant_units(roll, key, where, owner, from_name)
    local ok, types = pcall(roll, key)
    if not ok then
        Diplomacy.report_error("GRANTS", types)
        return
    end
    local names = ""
    for _, unit_type in ipairs(types) do
        local spawned = pcall(Spawn_Unit, unit_type, where, owner)
        if spawned then
            if names ~= "" then
                names = names .. ", "
            end
            names = names .. Diplomacy.unit_name(unit_type.Get_Name())
        end
    end
    if names ~= "" then
        Diplomacy.show("Diplomacy: " .. from_name .. " sends you " .. names .. ".")
    end
end

function Diplomacy:mark_own_transfer(name)
    local mark = self.own_transfers[name]
    local n = (type(mark) == "table" and GetCurrentTime() - mark.t < 30) and mark.n or ((mark == true) and 1 or 0)
    self.own_transfers[name] = {n = n + 1, t = GetCurrentTime()}
end

function Diplomacy:take_own_transfer(name)
    local mark = self.own_transfers[name]
    if mark == true then
        self.own_transfers[name] = nil
        return true
    elseif type(mark) == "table" then
        if GetCurrentTime() - mark.t >= 30 or mark.n <= 1 then
            self.own_transfers[name] = nil
            return GetCurrentTime() - mark.t < 30
        end
        mark.n = mark.n - 1
        return true
    end
    return false
end

function Diplomacy:transfer_world(planet, new_owner, human_stays, evacuate, sail)
    local old_owner = planet.Get_Owner()
    local name = string.upper(planet.Get_Type().Get_Name())
    self:mark_own_transfer(name)
    self.quiet_news[name] = GetCurrentTime()

    local sailing = {}
    local function lift(player, with_structures, keep_fleets, only_structures)
        local types = {}
        local ships = {}
        for _, unit in pairs(keep_fleets and Find_All_Objects_Of_Type(player) or {}) do
            local at = TestValid(unit) and unit.Get_Planet_Location()
            if at and string.upper(at.Get_Type().Get_Name()) == name and (unit.Is_Category("Capital")
                or unit.Is_Category("Frigate") or unit.Is_Category("Corvette") or unit.Is_Category("SuperCapital")
                or unit.Is_Category("SpaceHero") or unit.Is_Category("Fighter") or unit.Is_Category("Bomber")) then
                local ok, parent = pcall(unit.Get_Parent_Object)
                if ok and parent and TestValid(parent) and parent.Get_Type().Get_Name() == "GALACTIC_FLEET" then
                    ships[tostring(parent)] = true
                end
            end
        end
        for _, unit in pairs(Find_All_Objects_Of_Type(player) or {}) do
            if TestValid(unit) then
                local at = unit.Get_Planet_Location()
                local is_diplomat = string.upper(unit.Get_Type().Get_Name()) == ENVOY
                local structure = with_structures and (unit.Is_Category("Structure") or unit.Is_Category("SpaceStructure"))
                local wanted = structure or (not only_structures and (is_diplomat or is_valid_category(unit)))
                local fleet = nil
                if keep_fleets and wanted and not is_diplomat then
                    local ok, parent = pcall(unit.Get_Parent_Object)
                    if ok and parent and TestValid(parent) and ships[tostring(parent)] then
                        fleet = parent
                    end
                end
                if fleet and at and string.upper(at.Get_Type().Get_Name()) == name then
                    if ships[tostring(fleet)] ~= "sent" then
                        ships[tostring(fleet)] = "sent"
                        table.insert(sailing, fleet)
                    end
                elseif at and string.upper(at.Get_Type().Get_Name()) == name and wanted then
                    local relevant = unit
                    if not is_diplomat then
                        relevant = get_relevant_object(unit)
                    end
                    if TestValid(relevant) then
                        table.insert(types, relevant.Get_Type())
                        relevant.Despawn()
                    end
                end
            end
        end
        return types
    end

    local yours = lift(self.human, false, sail)
    local leaving = {}
    if evacuate and old_owner ~= self.human then
        leaving = lift(old_owner)
    end
    local garrison = lift(old_owner, true, false, old_owner == self.human)

    planet.Change_Owner(new_owner)

    local function place(types, where, owner)
        for _, unit_type in pairs(types) do
            local ok, err = pcall(Spawn_Unit, unit_type, where, owner)
            if not ok then
                Diplomacy.report_error("TRANSFER", err)
            end
        end
    end
    if not evacuate then
        place(garrison, planet, new_owner)
    end
    local refuge = nil
    if table.getn(leaving) > 0 then
        refuge = self:nearest_friendly_planet(old_owner, planet)
        if refuge then
            place(leaving, refuge, old_owner)
        end
    end
    if evacuate and Engine_Log then
        Engine_Log("TRANSFER " .. name .. ": " .. table.getn(leaving) .. " units left for "
            .. (refuge and refuge.Get_Type().Get_Name() or "nowhere") .. ", " .. table.getn(garrison)
            .. " structures demolished")
    end

    local destination = planet
    if not human_stays then
        destination = self:nearest_friendly_planet(self.human, planet)
    end
    if destination then
        place(yours, destination, self.human)
        for _, fleet in ipairs(sailing) do
            if TestValid(fleet) then
                pcall(fleet.Move_To, destination)
            end
        end
    end
    if not human_stays and (table.getn(yours) > 0 or sailing[1]) then
        return destination
    end
    return nil
end

function Diplomacy:collect_world_income()
    if GetCurrentTime() < self.next_world_income then
        return
    end
    self.next_world_income = M.next_week(CONFIG.WEEK_SECONDS)
    local vassals = self:vassal_player()
    for name, _ in pairs(self.vassal_worlds) do
        local planet = FindPlanet(name)
        local owner = planet and planet.Get_Owner()
        if not self:holds_vassal_world(name, owner) then
            self.vassal_worlds[name] = nil
        elseif not self.vassal_worlds[name].slot then
            local ok, income = pcall(EvaluatePerception, "PlanetBaseIncome", self.human, planet)
            if not ok then
                income = 0
            end
            income = M.min(M.max(M.sane(income), 0), 100000)
            if owner == vassals then
                self:grow_garrison(name, planet, vassals)
                local share = M.floor(income * (1 - CONFIG.VASSAL_WORLD_KEEPS))
                if self.vassal_worlds[name].stage == "protectorate" then
                    share = 0
                end
                if share > 0 then
                    vassals.Give_Money(-share)
                    self.human.Give_Money(share)
                end
            else
                local kept = M.floor(income * CONFIG.VASSAL_WORLD_KEEPS)
                if kept > 0 then
                    self.human.Give_Money(-kept)
                end
            end
        end
    end
end

function Diplomacy:grow_garrison(name, planet, vassals)
    local world = self.vassal_worlds[name]
    local rules = CONFIG.VASSAL_DEFENSE
    world.grown = world.grown or 0
    world.next_growth = world.next_growth or (world.since + rules.GROW_WEEKS * CONFIG.WEEK_SECONDS)
    if world.grown >= rules.MAX_GROWTH or GetCurrentTime() < world.next_growth then
        return
    end
    world.next_growth = GetCurrentTime() + rules.GROW_WEEKS * CONFIG.WEEK_SECONDS
    local ok, types = pcall(Grants.for_world, name)
    if ok and types[1] then
        if pcall(Spawn_Unit, types[1], planet, vassals) then
            world.grown = world.grown + 1
        end
    end
end

function Diplomacy:watch_vassal_worlds()
    local vassals = self:vassal_player()
    if not vassals or GetCurrentTime() < (self.next_vassal_watch or 0) then
        return
    end
    self.next_vassal_watch = GetCurrentTime() + CONFIG.VASSAL_DEFENSE.ALERT_SECONDS
    for name, world in pairs(self.vassal_worlds) do
        local planet = FindPlanet(name)
        if planet and planet.Get_Owner() == vassals then
            local ok, blockaded = pcall(EvaluatePerception, "Blockaded", vassals, planet)
            local attacked = ok and type(blockaded) == "number" and blockaded > 0
            if attacked and not world.under_attack then
                Missions.adjust_content(self, name, -CONFIG.MISSIONS.ATTACK_CONTENT)
                Diplomacy.show("Diplomacy: your " .. (self:senate_active() and "associate" or "vassal") .. " world " .. self:planet_name(planet)
                    .. " is under attack. Your fleets may help defend it.", nil, COLOR_WARN)
            end
            world.under_attack = attacked
        end
    end
end

function Diplomacy:planet_name(planet)
    local name = planet.Get_Type().Get_Name()
    local wrapper = self.gc.Planets[name]
    if wrapper and wrapper.get_readable_name then
        local ok, readable = pcall(wrapper.get_readable_name, wrapper)
        if ok and type(readable) == "string" and readable ~= "" then
            return readable
        end
    end
    return Diplomacy.tidy(name)
end

function Diplomacy.signed(n)
    n = M.round(n)
    if n > 0 then
        return "+" .. n
    end
    return "" .. n
end

function Diplomacy:campaign_winner(assume)
    assume = assume or {}
    local human_name = self.human.Get_Faction_Name()
    local owners = {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = planet.Get_Owner()
        if owner and FACTIONS.PLAYABLE[owner.Get_Faction_Name()] then
            owners[owner.Get_Faction_Name()] = owner
        end
    end

    local function hostile(a_name, a, b_name, b)
        if a_name == b_name or b_name == "NEUTRAL" then
            return false
        end
        local other = nil
        if a_name == human_name then
            other = b_name
        elseif b_name == human_name then
            other = a_name
        end
        if other and assume[other] ~= nil then
            return not assume[other]
        end
        return not (a.Is_Ally(b) and b.Is_Ally(a))
    end

    for a_name, a in pairs(owners) do
        do
            local blocked = false
            for b_name, b in pairs(owners) do
                if hostile(a_name, a, b_name, b) then
                    blocked = true
                    break
                end
            end
            if not blocked then
                return a_name
            end
        end
    end
    return nil
end

function Diplomacy:prevent_campaign_end()
    if GetCurrentTime() < CAMPAIGN_END_GUARD_FROM then
        return
    end
    local winner = self:campaign_winner()
    if not winner or winner == self.human.Get_Faction_Name() then
        return
    end
    for faction_name, _ in pairs(self.relations) do
        if not self:campaign_winner({[faction_name] = false}) then
            self:set_relation(faction_name, "WAR", nil, true)
            Diplomacy.show("Diplomacy: your treaty with " .. Diplomacy.display_name(faction_name)
                .. " was dissolved: it would have let " .. Diplomacy.display_name(winner)
                .. " and its allies control every planet and end the campaign.", nil, COLOR_WARN)
            return
        end
    end
end

function Diplomacy:describe_alliances()
    local owners, names = {}, {}
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        local owner = planet.Get_Owner()
        if owner and FACTIONS.PLAYABLE[owner.Get_Faction_Name()] and not owners[owner.Get_Faction_Name()] then
            owners[owner.Get_Faction_Name()] = owner
            table.insert(names, owner.Get_Faction_Name())
        end
    end
    local text = ""
    for i = 1, table.getn(names) do
        for j = i + 1, table.getn(names) do
            local a, b = owners[names[i]], owners[names[j]]
            if not a.Is_Enemy(b) and not b.Is_Enemy(a) then
                if text ~= "" then
                    text = text .. ", "
                end
                text = text .. Diplomacy.display_name(names[i]) .. " + " .. Diplomacy.display_name(names[j])
            end
        end
    end
    if text == "" then
        return "none"
    end
    return text
end

function Diplomacy:collect_tribute()
    for faction_name, last_credits in pairs(self.vassal_credits) do
        local vassal = Find_Player(faction_name)
        if vassal then
            local credits = vassal.Get_Credits()
            local gained = credits - last_credits
            if gained > 0 then
                local tribute = M.floor(gained * TRIBUTE_SHARE)
                if tribute > 0 then
                    vassal.Give_Money(-tribute)
                    self.human.Give_Money(tribute)
                    credits = credits - tribute
                    self.last_tribute = self.last_tribute or {}
                    self.last_tribute[faction_name] = tribute
                    Diplomacy.show("Diplomacy: tribute of " .. tribute .. " credits received from "
                        .. Diplomacy.display_name(faction_name) .. ".")
                end
            end
            self.vassal_credits[faction_name] = credits
        end
    end
end

function Diplomacy:enforce_borders()
    local mine = {}
    for _, unit in pairs(Find_All_Objects_Of_Type(self.human) or {}) do
        local ok, owner = pcall(function()
            local planet = TestValid(unit) and unit.Get_Planet_Location()
            return planet and planet.Get_Owner()
        end)
        if ok and owner and owner ~= self.human then
            mine[owner] = mine[owner] or {}
            table.insert(mine[owner], unit)
        end
    end
    local vassals = self:vassal_player()
    if vassals then
        local destination = mine[vassals] and self:expel(self.human, vassals, true, mine[vassals])
        if destination then
            Diplomacy.show("Diplomacy: your troops may not land on vassal worlds; they withdrew.", nil, COLOR_WARN)
            Diplomacy.show("TEXT_DIPLOMACY_SENT_TO", destination, COLOR_WARN)
        end
    end
    for faction_name, relation in pairs(self.relations) do
        local other = Find_Player(faction_name)
        if other then
            local landed_only = relation ~= "CEASEFIRE" or (self.open_borders ~= nil and self.open_borders[faction_name] == true)
            local destination = mine[other] and self:expel(self.human, other, landed_only, mine[other])
            if destination then
                if landed_only then
                    Diplomacy.show("Diplomacy: troops may not land on " .. Diplomacy.display_name(faction_name)
                        .. " worlds.", nil, COLOR_WARN)
                else
                    Diplomacy.show("Diplomacy: your ceasefire with " .. Diplomacy.display_name(faction_name)
                        .. " closes their borders.", nil, COLOR_WARN)
                end
                Diplomacy.show("TEXT_DIPLOMACY_SENT_TO", destination, COLOR_WARN)
            end
            self:expel(other, self.human, landed_only)
        end
    end
end

function Diplomacy:nearest_friendly_planet(player, from)
    local best, best_hops, best_distance = nil, nil, nil
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            local path = Find_Path(player, from, planet)
            if path then
                local hops = table.getn(path)
                local distance = from.Get_Distance(planet)
                if not best or hops < best_hops or (hops == best_hops and distance < best_distance) then
                    best, best_hops, best_distance = planet, hops, distance
                end
            end
        end
    end
    return best or StoryUtil.FindFriendlyPlanet(player, true)
end

local GROUND = "Infantry | Vehicle | AirGunship | AirSpeeder | InfantryHero | VehicleHero"

local function is_landed(unit, relevant, planet)
    if not unit.Is_Category(GROUND) then
        return false
    end
    local parent = relevant.Get_Parent_Object()
    if not parent then
        return false
    end
    local parent_type = parent.Get_Type()
    return parent_type ~= nil
        and string.upper(parent_type.Get_Name()) == string.upper(planet.Get_Type().Get_Name())
end

local STEALTH_UNITS = require("eawx-plugins/diplomacy/StealthUnits")
local function stealthy_name(name)
    if STEALTH_UNITS[name] or string.find(name, "_OPERATIVE_", 1, true) then
        return true
    end
    for _, prefix in ipairs(STEALTH_PREFIXES or {}) do
        if string.find(name, prefix, 1, true) == 1 then
            return true
        end
    end
    return false
end
local function is_stealthed(unit)
    if stealthy_name(string.upper(unit.Get_Type().Get_Name())) then
        return true
    end
    local relevant = get_relevant_object(unit)
    return TestValid(relevant) and stealthy_name(string.upper(relevant.Get_Type().Get_Name()))
end

function Diplomacy:expel(intruder, host, landed_only, units)
    local destinations = {}
    local sent_to = nil
    for _, unit in pairs(units or Find_All_Objects_Of_Type(intruder) or {}) do
        local stage = "SCAN"
        local ok, err = pcall(function()
            if not (TestValid(unit) and is_valid_category(unit)) then
                return
            end
            if string.upper(unit.Get_Type().Get_Name()) == ENVOY or is_stealthed(unit) then
                return
            end
            local planet = unit.Get_Planet_Location()
            if not planet or planet.Get_Owner() ~= host then
                return
            end
            local relevant = get_relevant_object(unit)
            if not TestValid(relevant) then
                return
            end
            stage = "LANDED"
            if landed_only and not is_landed(unit, relevant, planet) then
                return
            end
            stage = "DESTINATION"
            local key = planet.Get_Type().Get_Name()
            if not destinations[key] then
                destinations[key] = self:nearest_friendly_planet(intruder, planet)
            end
            local destination = destinations[key]
            if not destination then
                return
            end
            stage = "RESPAWN"
            local unit_type = relevant.Get_Type()
            local spawned = Spawn_Unit(unit_type, destination, intruder)
            if not spawned or not spawned[1] then
                Diplomacy.show("Diplomacy: could not move " .. unit_type.Get_Name() .. "; it was left in place.",
                    nil, COLOR_ERROR)
                return
            end
            stage = "DESPAWN"
            relevant.Despawn()
            sent_to = destination
        end)
        if not ok then
            Diplomacy.report_error(stage, err)
        end
    end
    return sent_to
end

function Diplomacy.show(text, var, color, seconds)
    StoryUtil.ShowScreenText(text, seconds or 15, var, color or COLOR)
    if Engine_Log then
        Engine_Log("MSG " .. text)
    end
end

function Diplomacy.rename(faction_name, display_name)
    renamed[string.upper(faction_name)] = display_name
end

function Diplomacy.display_name(faction_name)
    if renamed[faction_name] then
        return renamed[faction_name]
    end
    local player = Find_Player(faction_name)
    if player then
        local ok, name = pcall(player.Get_Name)
        if ok and type(name) == "string" and name ~= "" and not string.find(name, "^TEXT_") then
            return name
        end
    end
    if FACTION_NAMES[faction_name] then
        return FACTION_NAMES[faction_name]
    end
    return Diplomacy.tidy(faction_name)
end

local UNIT_NAMES = require("eawx-plugins/diplomacy/UnitNames")
function Diplomacy.unit_name(type_name)
    return UNIT_NAMES[string.upper(type_name)] or Diplomacy.tidy(type_name)
end

function Diplomacy.tidy(name)
    local lower = string.lower(name)
    local result = ""
    local start_of_word = true
    for i = 1, string.len(lower) do
        local c = string.sub(lower, i, i)
        if c == "_" then
            result = result .. " "
            start_of_word = true
        elseif start_of_word then
            result = result .. string.upper(c)
            start_of_word = false
        else
            result = result .. c
        end
    end
    return result
end

function Diplomacy.report_error(stage, err)
    DebugMessage("Diplomacy error in %s: %s", stage, tostring(err))
    Diplomacy.show("Diplomacy: script error (" .. stage .. "): " .. tostring(err), nil, COLOR_ERROR)
end

return Diplomacy
