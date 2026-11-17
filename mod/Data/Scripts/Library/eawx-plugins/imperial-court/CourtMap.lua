local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local Court = require("eawx-plugins/imperial-court/Court")

local Map = {}

Map.MODES = {"off", "sectors", "loyalty"}
Map.NAMES = {off = "Map: off", sectors = "Map: sectors", loyalty = "Map: loyalty"}
local SECTOR_COLOURS = 10
local LOYAL, WAVERING, DISLOYAL = 11, 12, 13
local REFRESH = 30

function Map.next_mode(s)
    local now = s.map_mode or "off"
    for i, mode in ipairs(Map.MODES) do
        if mode == now then
            s.map_mode = Map.MODES[i + 1] or Map.MODES[1]
            break
        end
    end
    s.map_time = nil
    Map.refresh(s)
    return s.map_mode
end

local function sector_colour(s, key)
    s.sector_colours = s.sector_colours or {}
    if not s.sector_colours[key] then
        s.next_colour = (s.next_colour or 0) + 1
        local n = s.next_colour
        while n > SECTOR_COLOURS do
            n = n - SECTOR_COLOURS
        end
        s.sector_colours[key] = n
    end
    return s.sector_colours[key]
end

local function lord_of(s, name)
    local gov = Court.char(s, s.governor[name])
    if gov and gov.status == "serving" then
        return gov
    end
    local sector = s.sectors[s.world[name] or ""]
    return sector and Court.char(s, sector.holder)
end

function Map.refresh(s)
    local mode = s.map_mode or "off"
    if mode == "off" or not s.ready then
        return
    end
    local now = GetCurrentTime()
    if s.map_time and now - s.map_time < REFRESH then
        return
    end
    s.map_time = now
    local empire = Court.player()
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == empire then
            local name = Court.name_of(planet)
            local colour
            if mode == "sectors" then
                local key = s.world[name]
                colour = key and sector_colour(s, key) or nil
            else
                local lord = lord_of(s, name)
                if lord then
                    colour = (lord.loyalty >= 60) and LOYAL or ((lord.loyalty >= 40) and WAVERING or DISLOYAL)
                end
            end
            if colour then
                pcall(planet.Attach_Particle_Effect, "DP_Court_Mist_" .. colour)
            end
        end
    end
end

local COLOUR_NAMES = {"red", "blue", "gold", "green", "violet", "orange", "cyan", "pink", "lime", "indigo"}
function Map.colour_name(s, key)
    return COLOUR_NAMES[sector_colour(s, key)] or ""
end

return Map
