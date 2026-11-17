require("deepcore/std/class")
require("PGSpawnUnits")
require("deepcore/crossplot/crossplot")
require("eawx-util/StoryUtil")
require("eawx-util/ChangeOwnerUtilities")
require("eawx-util/PopulatePlanetUtilities")
require("eawx-util/UnitUtil")
require("eawx-plugins/warlords/WarlordOwners")

Warlords = class()

local DATA = require("eawx-plugins/warlords/WarlordFactions")

local GRACE = 3
local FALLBACK = 10
local NEW_CAMPAIGN = 20

local function register_factions()
    local C = ModContentLoader.get("GameConstants")
    local copied = {"ALL_FACTIONS_CAPITALS", "ALL_FACTIONS_BASIC_STRUCTURES", "ALL_FACTIONS_AI",
                    "ALL_FACTIONS_CRUEL_AI", "TRANSPORTS"}
    local function register(key, display, text, color)
        if C.ALL_FACTION_NAMES then C.ALL_FACTION_NAMES[key] = display end
        if C.ALL_FACTION_TEXTS then C.ALL_FACTION_TEXTS[key] = text end
        if C.FACTION_COLORS and color then C.FACTION_COLORS[key] = color end
        for _, table_name in ipairs(copied) do
            local t = C[table_name]
            if type(t) == "table" and t[key] == nil then
                t[key] = t["WARLORDS"] or t["INDEPENDENT_FORCES"]
            end
        end
        if C.ALL_FACTION_ABBREVIATIONS and C.ALL_FACTION_ABBREVIATIONS[key] == nil then
            C.ALL_FACTION_ABBREVIATIONS[key] = C.ALL_FACTION_ABBREVIATIONS["WARLORDS"] or "WAR"
        end
    end
    for _, warlord in ipairs(DATA.WARLORDS) do
        if C.ALL_FACTIONS_CAPITALS and C.ALL_FACTIONS_CAPITALS[warlord.faction] == nil then
            local homes = {}
            for _, era in ipairs(warlord.eras) do
                for _, planet in ipairs(era.planets) do
                    table.insert(homes, planet)
                end
            end
            C.ALL_FACTIONS_CAPITALS[warlord.faction] = {STRUCTURE = nil, LOCATION = homes}
        end
        register(warlord.faction, warlord.display, warlord.text, warlord.color)
    end
    for _, slot in ipairs(DATA.BREAKAWAY) do
        register(slot.faction, "Breakaway Sector", slot.text, nil)
    end
end

local function at_year(eras, year)
    local best = nil
    for _, era in ipairs(eras or {}) do
        if year >= era.year and (best == nil or era.year > best.year) then
            best = era
        end
    end
    return best
end

local function planets_at(warlord, year)
    if warlord.start and year < warlord.start then
        return nil
    end
    if warlord.last and year > warlord.last then
        return nil
    end
    local era = at_year(warlord.eras, year)
    return era and era.planets
end

local waiting = {}

local function spawn_heroes(warlord, year, home, player, sources)
    local era = at_year(warlord.heroes, year)
    local spawn = {}
    for _, name in ipairs(era and era.units or {}) do
        if Find_Object_Type(name) then
            local existing = Find_All_Objects_Of_Type(name) or {}
            local alive = nil
            for _, obj in pairs(existing) do
                if not alive and TestValid(obj) then
                    alive = obj
                end
            end
            if table.getn(existing) == 0 then
                table.insert(spawn, name)
            elseif not alive then
                table.insert(waiting, {name = name, home = home, player = player, until_time = GetCurrentTime() + 30})
            elseif sources[alive.Get_Owner().Get_Faction_Name()] then
                for _, obj in pairs(existing) do
                    local relevant = TestValid(obj) and get_relevant_object and get_relevant_object(obj) or obj
                    if TestValid(relevant) then
                        pcall(relevant.Despawn)
                    end
                end
                table.insert(waiting, {name = name, home = home, player = player, until_time = GetCurrentTime() + 30})
            end
        end
    end
    if table.getn(spawn) > 0 then
        SpawnList(spawn, home, player, true, false)
    end
end

function Warlords.spawn_waiting()
    local left = {}
    for _, entry in ipairs(waiting) do
        local alive = nil
        for _, obj in pairs(Find_All_Objects_Of_Type(entry.name) or {}) do
            if TestValid(obj) then
                alive = obj
            end
        end
        if not alive and TestValid(entry.home) then
            pcall(SpawnList, {entry.name}, entry.home, entry.player, true, false)
            for _, obj in pairs(Find_All_Objects_Of_Type(entry.name) or {}) do
                if TestValid(obj) then
                    alive = obj
                end
            end
        end
        if not alive and GetCurrentTime() < entry.until_time then
            table.insert(left, entry)
        end
    end
    waiting = left
end

local function quiet_news(gc, quiet)
    if type(GalacticEventsNewsSource) == "table" and not GalacticEventsNewsSource.__warlords_quiet then
        GalacticEventsNewsSource.__warlords_quiet = true
        local notify = GalacticEventsNewsSource.notify
        GalacticEventsNewsSource.notify = function(source, news, a2, a3)
            local headline = type(news) == "table" and news.headline
            if headline and WARLORDS_PLACED_AT and GetCurrentTime() - WARLORDS_PLACED_AT < 20
                    and string.find(headline, " has conquered ", 1, true) then
                return
            end
            return notify(source, news, a2, a3)
        end
    end
    if type(GalacticEventsNewsSource) ~= "table" or not gc.Events or not gc.Events.PlanetOwnerChanged then
        return
    end
    NEWS_LISTENER_WRAPPERS = NEWS_LISTENER_WRAPPERS or {}
    for _, entry in ipairs(gc.Events.PlanetOwnerChanged.Listeners or {}) do
        if entry.Listener == GalacticEventsNewsSource.on_planet_owner_changed
                or NEWS_LISTENER_WRAPPERS[entry.Listener] then
            local original = entry.Listener
            entry.Listener = function(source, planet, a2, a3, a4)
                local since = quiet[string.upper(planet:get_name())]
                if since and GetCurrentTime() - since < 10 then
                    return
                end
                return original(source, planet, a2, a3, a4)
            end
            NEWS_LISTENER_WRAPPERS[entry.Listener] = true
        end
    end
end

function Warlords:new(gc)
    self.gc = gc
    self.quiet = {}
    self.placed = GetCurrentTime() > NEW_CAMPAIGN
    self.started_at = nil
    self.choosing = false
    self.chosen = false
    local ok, err = pcall(register_factions)
    if not ok then
        StoryUtil.ShowScreenText("Warlords: " .. tostring(err), 20, nil, {r = 255, g = 120, b = 120})
    end
    crossplot:subscribe("WARLORD_START", self.on_start, self)
    crossplot:subscribe("POPUPEVENT", self.on_popup, self)
    crossplot:subscribe("INITIALIZE_PROTEUS_LEGITIMACY", self.on_chosen, self)
end

function Warlords:on_start()
    if not self.started_at then
        self.started_at = GetCurrentTime()
    end
end

function Warlords:on_popup(event_name)
    if event_name == "WARLORD_CHOICE" then
        self.choosing = true
    end
end

function Warlords:on_chosen()
    self.chosen = true
    self.started_at = GetCurrentTime()
end

function Warlords:update()
    if table.getn(waiting) > 0 then
        Warlords.spawn_waiting()
    end
    if self.placed then
        return
    end
    if not self.news_patched then
        self.news_patched = true
        pcall(quiet_news, self.gc, self.quiet)
    end
    local now = GetCurrentTime()
    if self.started_at then
        if self.choosing and not self.chosen then
            return
        end
        if now < self.started_at + GRACE then
            return
        end
    elseif now < FALLBACK then
        return
    end
    self.placed = true
    local ok, err = pcall(self.place, self)
    if not ok then
        StoryUtil.ShowScreenText("Warlords: " .. tostring(err), 20, nil, {r = 255, g = 120, b = 120})
    end
end

local function governing_faction(warlord, year, on_map)
    for _, name in ipairs(planets_at(warlord, year) or {}) do
        local planet = on_map[name] and FindPlanet(name)
        if planet and string.upper(planet.Get_Owner().Get_Faction_Name()) == "EMPIRE" then
            return planet.Get_Owner()
        end
    end
    return nil
end

local SECONDARY = nil

local function station_kind(obj)
    local t = obj.Get_Type()
    local name = t and string.upper(t.Get_Name())
    if not name then
        return nil
    end
    if string.find(name, "STAR_BASE", 1, true) then
        return "base"
    end
    if not SECONDARY then
        SECONDARY = {}
        local ok, lists = pcall(require, "StructureCategoryLists")
        for _, list in pairs(ok and type(lists) == "table" and lists or {}) do
            for _, n in pairs(list) do
                SECONDARY[string.upper(n)] = true
            end
        end
    end
    if SECONDARY[name] or string.find(name, "SHIPYARD_LEVEL", 1, true) then
        return "other"
    end
    return nil
end

local function stations_at(owner, planets)
    local wanted, out = {}, {}
    for _, planet in ipairs(planets) do
        wanted[planet] = string.upper(planet.Get_Type().Get_Name())
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(owner) or {}) do
        local kind = TestValid(obj) and station_kind(obj)
        if kind then
            local ok, at = pcall(function()
                return obj.Get_Planet_Location()
            end)
            local name = ok and at and wanted[at]
            if name then
                out[name] = out[name] or {}
                table.insert(out[name], {type = string.upper(obj.Get_Type().Get_Name()), kind = kind})
            end
        end
    end
    return out
end

local function restore_stations(planets, player, stations)
    if string.find(string.upper(player.Get_Faction_Name()), "^WARLORD_") then
        for _, list in pairs(stations) do
            for _, s in ipairs(list) do
                s.type = string.gsub(s.type, "^.-_SHIPYARD_LEVEL_", "EMPIRE_SHIPYARD_LEVEL_")
            end
        end
    end
    local have = stations_at(player, planets)
    for _, planet in ipairs(planets) do
        local name = string.upper(planet.Get_Type().Get_Name())
        local mine, base = {}, false
        for _, s in ipairs(have[name] or {}) do
            mine[s.type] = (mine[s.type] or 0) + 1
            base = base or s.kind == "base"
        end
        for _, s in ipairs(stations[name] or {}) do
            if s.kind == "base" and base then
            elseif (mine[s.type] or 0) > 0 then
                mine[s.type] = mine[s.type] - 1
            elseif Find_Object_Type(s.type) then
                pcall(SpawnList, {s.type}, planet, player, true, false)
                base = base or s.kind == "base"
            end
        end
    end
end

function Warlords.starbase_levels(planets)
    local levels = {}
    for _, planet in ipairs(planets) do
        local ok, level = pcall(EvaluatePerception, "StarbaseLevel", planet.Get_Owner(), planet)
        levels[planet] = (ok and type(level) == "number") and level or 0
    end
    return levels
end

function Warlords.restore_starbases(levels, player)
    local table_ = nil
    local ok_t, units = pcall(DefineUnitTable, player.Get_Faction_Name())
    if ok_t and type(units) == "table" and type(units.Starbase_Table) == "table" then
        table_ = units.Starbase_Table
    end
    for planet, level in pairs(levels) do
        local ok, now = pcall(EvaluatePerception, "StarbaseLevel", player, planet)
        if level > 0 and ok and now == 0 and planet.Get_Owner() == player then
            local name = table_ and table_[level] or ("Empire_Star_Base_" .. level)
            local t = Find_Object_Type(name) or Find_Object_Type("Empire_Star_Base_" .. level)
            if t then
                pcall(Spawn_Unit, t, planet, player)
            end
        end
    end
end

local function bare(planet, player)
    local ok, level = pcall(EvaluatePerception, "StarbaseLevel", player, planet)
    if ok and type(level) == "number" and level > 0 then
        return false
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(player) or {}) do
        if TestValid(obj) and obj.Get_Planet_Location() == planet and obj.Is_Category("Structure") then
            return false
        end
    end
    return true
end

local function build_up(planets, player)
    for _, planet in ipairs(planets) do
        if planet.Get_Owner() == player and bare(planet, player) then
            pcall(ChangePlanetOwnerAndPopulate, planet, player, 0, "WARLORDS", false)
        end
    end
end

local function ships_at(owner, planets)
    local wanted, out = {}, {}
    for _, planet in ipairs(planets) do
        wanted[planet] = true
    end
    for _, obj in pairs(Find_All_Objects_Of_Type(owner) or {}) do
        if TestValid(obj) then
            local at = obj.Get_Planet_Location()
            if at and wanted[at] and (obj.Is_Category("Capital") or obj.Is_Category("Frigate")
                    or obj.Is_Category("Corvette") or obj.Is_Category("SuperCapital") or obj.Is_Category("SpaceHero")) then
                table.insert(out, {planet = at, type = obj.Get_Type()})
                obj.Despawn()
            end
        end
    end
    return out
end

local function bring_ships(ships, player)
    for _, ship in ipairs(ships) do
        if ship.planet.Get_Owner() == player then
            pcall(Spawn_Unit, ship.type, ship.planet, player)
        end
    end
end

function Warlords:place()
    WARLORDS_PLACED_AT = GetCurrentTime()
    pcall(quiet_news, self.gc, self.quiet)
    local year = GlobalValue.Get("GALACTIC_YEAR") or 0
    local p_warlords = Find_Player("Warlords")
    local on_map = StoryUtil.GetSafePlanetTable()
    local claimed = {}
    for _, warlord in ipairs(DATA.WARLORDS) do
        local mine = {}
        for _, name in ipairs(planets_at(warlord, year) or {}) do
            if on_map[name] and not claimed[name] then
                local planet = FindPlanet(name)
                if planet and planet.Get_Owner() == p_warlords then
                    claimed[name] = true
                    self.quiet[name] = GetCurrentTime()
                    table.insert(mine, planet)
                end
            end
        end
        local liege = table.getn(mine) > 0 and governing_faction(warlord, year, on_map)
        local stations = table.getn(mine) > 0 and stations_at(p_warlords, mine) or {}
        local levels = Warlords.starbase_levels(mine)
        if liege then
            local ships = ships_at(p_warlords, mine)
            ChangePlanetOwnerAndReplace(mine, liege, 3)
            Warlords.restore_starbases(levels, liege)
            restore_stations(mine, liege, stations)
            bring_ships(ships, liege)
            build_up(mine, liege)
        elseif table.getn(mine) > 0 then
            local player = Find_Player(warlord.faction)
            local ships = ships_at(p_warlords, mine)
            ChangePlanetOwnerAndReplace(mine, player, 3)
            Warlords.restore_starbases(levels, player)
            restore_stations(mine, player, stations)
            bring_ships(ships, player)
            build_up(mine, player)
            spawn_heroes(warlord, GlobalValue.Get("GALACTIC_YEAR") or 0, mine[1], player, {WARLORDS = true})
        end
    end
    local petty = {}
    for name in pairs(on_map) do
        local planet = FindPlanet(name)
        if planet and planet.Get_Owner() == p_warlords then
            table.insert(petty, planet)
        end
    end
    build_up(petty, p_warlords)
end

function Warlords.governor_of(planet_name)
    planet_name = string.upper(planet_name or "")
    local planet = FindPlanet(planet_name)
    if not planet then
        return nil
    end
    local owner = planet.Get_Owner().Get_Faction_Name()
    local year = GlobalValue.Get("GALACTIC_YEAR") or 0
    for _, warlord in ipairs(DATA.WARLORDS) do
        local held = owner == "EMPIRE"
        for _, faction in ipairs(warlord.overrides) do
            if faction == owner then
                held = true
            end
        end
        if held then
            for _, name in ipairs(planets_at(warlord, year) or {}) do
                if name == planet_name then
                    local surname = string.gsub(warlord.title or "", "^%S+%s+", "")
                    return warlord, "Moff " .. surname
                end
            end
        end
    end
    return nil
end

function Warlords.break_away(planet_name, whole_sector)
    local warlord = Warlords.governor_of(planet_name)
    if not warlord then
        return nil
    end
    local planet = FindPlanet(string.upper(planet_name))
    local source = planet.Get_Owner()
    local worlds = {planet}
    if whole_sector then
        local year = GlobalValue.Get("GALACTIC_YEAR") or 0
        local on_map = StoryUtil.GetSafePlanetTable()
        for _, name in ipairs(planets_at(warlord, year) or {}) do
            local other = on_map[name] and FindPlanet(name)
            if other and other ~= planet and other.Get_Owner() == source then
                table.insert(worlds, other)
            end
        end
    end
    local player = Find_Player(warlord.faction)
    local stations = stations_at(source, worlds)
    local levels = Warlords.starbase_levels(worlds)
    ChangePlanetOwnerAndRetreatHeroes(worlds, player, nil, 3)
    Warlords.restore_starbases(levels, player)
    restore_stations(worlds, player, stations)
    if not WARLORD_BROKE_AWAY then
        WARLORD_BROKE_AWAY = {}
    end
    if not WARLORD_BROKE_AWAY[warlord.key] then
        WARLORD_BROKE_AWAY[warlord.key] = true
        spawn_heroes(warlord, GlobalValue.Get("GALACTIC_YEAR") or 0, planet, player,
            {[string.upper(source.Get_Faction_Name())] = true, WARLORDS = true})
    end
    return player
end

function Warlords.raise(key, home, player, source)
    local warlord = nil
    for _, entry in ipairs(DATA.WARLORDS) do
        if entry.key == key then
            warlord = entry
        end
    end
    if not warlord or not home then
        return false
    end
    if not WARLORD_BROKE_AWAY then
        WARLORD_BROKE_AWAY = {}
    end
    if WARLORD_BROKE_AWAY[key] then
        return false
    end
    WARLORD_BROKE_AWAY[key] = true
    spawn_heroes(warlord, GlobalValue.Get("GALACTIC_YEAR") or 0, home, player,
        {[string.upper(source or "EMPIRE")] = true, WARLORDS = true})
    return true
end

return Warlords
