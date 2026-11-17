local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local POPULATIONS = require("eawx-plugins/diplomacy/DiplomacyPopulations")

local U = {}

function U.weeks(n)
    return n * CONFIG.WEEK_SECONDS
end

function U.weeks_since(time)
    return M.floor((GetCurrentTime() - (time or GetCurrentTime())) / CONFIG.WEEK_SECONDS)
end

function U.clamp(x, low, high)
    return M.max(low, M.min(high, x))
end

function U.key(planet)
    return string.upper(planet.Get_Type().Get_Name())
end

function U.chance(pct)
    return GameRandom.Free_Random(1, 100) <= pct
end

function U.pick(list)
    if not list or table.getn(list) == 0 then
        return nil
    end
    return list[GameRandom.Free_Random(1, table.getn(list))]
end

function U.count(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

function U.hash(text)
    local h = 7
    for i = 1, string.len(text) do
        h = h * 31 + string.byte(text, i)
        h = h - M.floor(h / 1000003) * 1000003
    end
    return h
end

function U.populated(name)
    return POPULATIONS[name] ~= nil
end

local sector_of, sectors = nil, nil
local function load_sectors()
    if sector_of then
        return
    end
    sector_of, sectors = {}, {}
    local ok, data = pcall(require, "eawx-plugins/imperial-court/CourtSectorsData")
    if not ok or type(data) ~= "table" then
        return
    end
    for _, s in ipairs(data) do
        sectors[s.name] = {name = s.name, region = s.region, worlds = s.worlds}
        for _, w in ipairs(s.worlds or {}) do
            sector_of[w] = s.name
        end
    end
end

function U.sector_of(name)
    load_sectors()
    return sector_of[name] or "Unsectored space"
end

function U.sector(name)
    load_sectors()
    return sectors[name]
end

function U.worlds_of(player)
    local out = {}
    if not player then
        return out
    end
    for _, planet in pairs(FindPlanet.Get_All_Planets()) do
        if planet.Get_Owner() == player then
            table.insert(out, {key = U.key(planet), planet = planet})
        end
    end
    return out
end

function U.category(faction)
    faction = string.upper(faction or "")
    local aliases = CONSTANTS and CONSTANTS.ALIASES
    if faction == "EMPIRE" or (aliases and aliases[faction] == "IMPERIAL") then
        return "IMPERIAL"
    end
    if faction == "WARLORDS" or (Diplomacy and Diplomacy.warlord_factions and Diplomacy.warlord_factions()[faction]) then
        return "WARLORD"
    end
    if faction == "HUTT_CARTELS" then
        return "HUTT"
    end
    if faction == "INDEPENDENT_FORCES" or string.find(faction, "^INDEPENDENT_WORLD") then
        return "INDEPENDENT"
    end
    if CONFIG.IMPERIAL_REMNANTS and CONFIG.IMPERIAL_REMNANTS[faction] then
        return "IMPERIAL"
    end
    return "FREE"
end

function U.strength_at(player, planet)
    if not (DiplomacyAI and DiplomacyAI.strength_at and player and planet) then
        return 0
    end
    local ok, value = pcall(DiplomacyAI.strength_at, player, planet)
    return (ok and value) or 0
end

function U.jumps(d, player, planet)
    if not (DiplomacyAI and DiplomacyAI.jumps_to) then
        return nil
    end
    d.rep_ctx = d.rep_ctx or {}
    if not d.rep_ctx.time or GetCurrentTime() - d.rep_ctx.time > 5 then
        d.rep_ctx = {time = GetCurrentTime(), ctx = DiplomacyAI.context(d.display_name)}
    end
    local ok, n = pcall(DiplomacyAI.jumps_to, d.rep_ctx.ctx, player, planet)
    return ok and n or nil
end

return U
