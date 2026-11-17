require("deepcore/std/class")
require("eawx-util/StoryUtil")
local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local Court = require("eawx-plugins/imperial-court/Court")

ImperialCourt = class()

function ImperialCourt:new(gc)
    self.gc = gc
    self.state = Court.new_state()
    self.fresh = GetCurrentTime() <= CONFIG.NEW_CAMPAIGN
    self.errors = 0
    IMPERIAL_COURT = self.state
    gc.Events.PlanetOwnerChanged:attach_listener(self.on_planet_owner_changed, self)
    gc.Events.GalacticHeroKilled:attach_listener(self.on_hero_killed, self)
    IMPERIAL_COURT_ATTITUDE = function(faction_name)
        local s = IMPERIAL_COURT
        if type(s) ~= "table" or not s.attitude then
            return 0
        end
        local value = s.attitude[string.upper(faction_name or "")] or 0
        local regime = s.ready and Court.regime(s)
        if regime and regime.coalition and faction_name ~= CONFIG.FACTION then
            value = value + regime.coalition
        end
        return value
    end
    IMPERIAL_COURT_FACTION_LEADER = function(faction_name)
        local s = IMPERIAL_COURT
        local id = type(s) == "table" and s.breakaway_leader and s.breakaway_leader[string.upper(faction_name or "")]
        local c = id and s.chars and s.chars[id]
        if not c or c.status == "dead" then
            return nil
        end
        return {name = c.name, icon = Court.portrait(c)}
    end
    IMPERIAL_COURT_BREAKAWAY = function(faction_name)
        local s = IMPERIAL_COURT
        local id = type(s) == "table" and s.breakaway_leader and s.breakaway_leader[string.upper(faction_name or "")]
        local c = id and s.chars and s.chars[id]
        return c and {name = c.name, dead = c.status == "dead"} or nil
    end
    IMPERIAL_COURT_BREAKAWAYS = function()
        local out = {}
        local s = IMPERIAL_COURT
        for faction, id in pairs(type(s) == "table" and s.breakaway_leader or {}) do
            local c = s.chars and s.chars[id]
            if c then
                out[faction] = {name = c.name, dead = c.status == "dead"}
            end
        end
        return out
    end
    local plugin = self
    IMPERIAL_COURT_HERO_LEAVES = function(obj)
        local s = plugin.state
        if not s.ready then
            return false
        end
        local ok, done = pcall(Court.hero_leaves, s, obj)
        return ok and done or false
    end
    IMPERIAL_COURT_LEGITIMACY = function(kind, faction, player)
        local s = plugin.state
        if not s.ready or (player and player ~= Court.player()) then
            return
        end
        if kind == "VASSAL_FACTION" and faction then
            local Intel = require("eawx-plugins/imperial-court/CourtIntel")
            if Intel.is_warlord(string.upper(faction)) then
                kind = "VASSAL_WARLORD"
            end
        end
        local gain = CONFIG.LEGITIMACY_GAINS[kind]
        if gain then
            Court.add_legitimacy(CONFIG.FACTION, gain)
            local what = {VASSAL_WORLD = "A world becomes our vassal", WORLD_REVOLTS = "A foreign world rises for the Empire",
                          VASSAL_FACTION = "A power bends the knee as our vassal", VASSAL_WARLORD = "A warlord bends the knee as our vassal"}
            Court.news(s, (what[kind] or "A triumph") .. ": legitimacy +" .. gain .. ".")
        end
    end
    IMPERIAL_COURT_OFFER = function(object_name, player)
        local s = plugin.state
        local ok, mine = pcall(function()
            local empire = Court.player()
            return empire ~= nil and empire.Is_Human() and (player == nil or player == empire)
        end)
        if not (s.ready and ok and mine) then
            return false
        end
        s.offered = s.offered or {}
        s.offered[string.upper(object_name)] = true
        return true
    end
    local Panel = require("eawx-plugins/imperial-court/CourtPlanetPanel")
    IMPERIAL_COURT_PANEL_TICK = function(blocked)
        local ok, Window = pcall(require, "eawx-plugins/imperial-court/CourtWindow")
        local serial = Engine_Battle_Serial and Engine_Battle_Serial()
        if serial and serial ~= plugin.battle_serial then
            if plugin.battle_serial and ok and Window and Window.open_now then
                pcall(Window.close)
            end
            plugin.battle_serial = serial
        end
        if ok and Window and Window.open_now then
            pcall(Window.tick)
        end
        local ok2, err = pcall(Panel.tick, blocked or (ok and Window and Window.open_now))
        if not ok2 and Engine_Log and err ~= plugin.panel_error then
            plugin.panel_error = err
            Engine_Log("COURT PANEL error: " .. tostring(err))
        end
    end
    IMPERIAL_COURT_PANEL_CLICK = function(name)
        pcall(Panel.click, name)
    end
end

function ImperialCourt:on_planet_owner_changed(planet, new_owner_name, old_owner_name)
    local s = self.state
    if s.ready then
        pcall(Court.on_owner_changed, s, string.upper(planet:get_name()), string.upper(new_owner_name or ""),
            string.upper(old_owner_name or ""))
        pcall(require("eawx-plugins/imperial-court/CourtIntel").on_owner_changed, s, string.upper(planet:get_name()))
    end
end

function ImperialCourt:on_hero_killed(hero_name, owner_name)
    local s = self.state
    if s.ready and string.upper(owner_name or "") == CONFIG.FACTION then
        pcall(Court.on_hero_killed, s, hero_name)
    end
end

function ImperialCourt:watch_revolts()
    if type(InfluenceService) ~= "table" or InfluenceService.__court_watched then
        return
    end
    local plugin = self
    local hero_effects = InfluenceService.influence_hero_effects
    if type(hero_effects) == "function" then
        InfluenceService.influence_hero_effects = function(service, owner, planet_object)
            IMPERIAL_COURT_INFLUENCE_SERVICE = service
            local value = hero_effects(service, owner, planet_object)
            local unrest = IMPERIAL_COURT_UNREST or 0
            if unrest > 0 and type(value) == "number" and owner == Court.player() then
                value = value - unrest
            end
            local mods = IMPERIAL_COURT_INFLUENCE
            if mods and type(value) == "number" then
                local ok, name = pcall(function()
                    return string.upper(planet_object.Get_Type().Get_Name())
                end)
                if ok and mods[name] then
                    value = value + mods[name]
                end
            end
            return value
        end
    end
    local update = InfluenceService.update
    if type(update) == "function" then
        InfluenceService.update = function(service, planet)
            local stats = service.planets and service.planets[planet]
            if stats and (stats.unrestLevel or 0) >= 3 and (stats.ownerInfluence or 0) >= CONFIG.REVOLT_BELOW then
                stats.unrestLevel = 2
            end
            return update(service, planet)
        end
    end
    local original = InfluenceService.revolt
    InfluenceService.revolt = function(service, planet)
        local ok, name = pcall(function()
            return string.upper(planet:get_game_object().Get_Type().Get_Name())
        end)
        if ok and name and plugin.state.rebel_pending then
            plugin.state.rebel_pending[name] = true
        end
        pcall(function()
            local loyal = service.LoyaltyTable and service.LoyaltyTable[planet:get_name()]
            local owner = planet:get_owner()
            if loyal and string.upper(loyal) == CONFIG.FACTION and owner ~= Court.player() and plugin.state.ready then
                IMPERIAL_COURT_LEGITIMACY("WORLD_REVOLTS")
            end
        end)
        return original(service, planet)
    end
    InfluenceService.__court_watched = true
end

local ALLEGIANCE = "ALLEGIANCE_BATTLECRUISER"
function ImperialCourt:watch_locks()
    local s = self.state
    if s.allegiance_locked ~= nil and IMPERIAL_COURT_ALLEGIANCE_LOCKED == nil then
        IMPERIAL_COURT_ALLEGIANCE_LOCKED = s.allegiance_locked
    end
    if type(UnitUtil) ~= "table" or type(UnitUtil.SetLockList) ~= "function" or UnitUtil.__court_watched then
        return
    end
    local original = UnitUtil.SetLockList
    local plugin = self
    UnitUtil.SetLockList = function(faction, lock_list, state)
        pcall(function()
            if string.upper(tostring(faction)) ~= CONFIG.FACTION then
                return
            end
            for _, unit in pairs(lock_list or {}) do
                if string.upper(unit) == ALLEGIANCE then
                    IMPERIAL_COURT_ALLEGIANCE_LOCKED = (state == false)
                    plugin.state.allegiance_locked = IMPERIAL_COURT_ALLEGIANCE_LOCKED
                end
            end
        end)
        return original(faction, lock_list, state)
    end
    UnitUtil.__court_watched = true
end

function ImperialCourt:update()
    local s = self.state
    IMPERIAL_COURT = s
    pcall(self.watch_locks, self)
    if self.errors > 5 or not Court.player() then
        return
    end
    local now = GetCurrentTime()
    if not s.ready then
        if not self.fresh or now < CONFIG.SETUP_AFTER then
            return
        end
        if GlobalValue.Get("PROGRESS_REGIME") == true and type(GlobalValue.Get("IMPERIAL_REGIME_NAME")) ~= "string"
                and now < CONFIG.REGIME_WAIT then
            return
        end
        local ok, err = pcall(Court.setup, s)
        if not ok then
            self.errors = self.errors + 1
            Court.log("setup error: " .. tostring(err))
            self.state = Court.new_state()
            IMPERIAL_COURT = self.state
            return
        end
        s.next_week = now + CONFIG.WEEK_SECONDS
        return
    end
    self:watch_revolts()
    if s.deferred then
        Court.run_deferred(s)
    end
    pcall(require("eawx-plugins/imperial-court/CourtPlanetPanel").refresh, s)
    if not DiplomacyGuiTick then
        IMPERIAL_COURT_PANEL_TICK(false)
    end
    pcall(require("eawx-plugins/imperial-court/CourtMap").refresh, s)
    local ok_tick, tick_err = pcall(require("eawx-plugins/imperial-court/CourtIntel").tick, s)
    if not ok_tick and tick_err ~= self.intel_error then
        self.intel_error = tick_err
        Court.log("intel error: " .. tostring(tick_err))
    end
    if s.next_week - now > CONFIG.WEEK_SECONDS * 1.5 then
        Court.log("week clock reset (next " .. tostring(s.next_week) .. ", now " .. tostring(now) .. ")")
        s.next_week = now + CONFIG.WEEK_SECONDS
    end
    if now >= s.next_week then
        s.next_week = now + CONFIG.WEEK_SECONDS
        local ok, err = pcall(Court.week, s)
        if not ok then
            self.errors = self.errors + 1
            Court.log("week error: " .. tostring(err))
        end
    end
end

return ImperialCourt
