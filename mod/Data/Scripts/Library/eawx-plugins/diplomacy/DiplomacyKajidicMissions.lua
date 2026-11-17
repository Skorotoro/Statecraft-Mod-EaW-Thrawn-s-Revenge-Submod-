local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")
local K = require("eawx-plugins/diplomacy/DiplomacyKajidii")
local U = require("eawx-plugins/diplomacy/DiplomacyUnderworld")

local R = CONFIG.UNDERWORLD
local Missions = {}
local COLOR = {r = 230, g = 200, b = 90}
local COLOR_BAD = {r = 255, g = 150, b = 90}

Missions.LAUNCH = {}

function Missions.def(key)
    if key == "turf_war" then
        return {name = "Turf War", kind = "turf", cost = R.TURF_COST, weeks = R.TURF_WEEKS,
                desc = "The strongest family against all the rest. Win: the others are expelled and the world is "
                    .. "theirs. Lose: the underworld falls back a level and the family's buildings burn."}
    end
    local def = R.MISSIONS[key]
    if def and not def.kind then
        def.kind = "unlock"
    end
    return def
end

function Missions.family_mission(f)
    return R.FAMILY_MISSION[K.FAMILIES[f].key]
end

function Missions.special_mission(f)
    return R.SPECIAL_MISSION[K.FAMILIES[f].key]
end

function Missions.placeholder(def)
    return not (def.battle and Missions.LAUNCH[def.battle])
end

function Missions.running(d, f, world)
    for _, m in pairs(d.kj and d.kj.missions or {}) do
        if (f and m.family == f) or (world and m.world == world) then
            return m
        end
    end
    return nil
end

function Missions.chance(d, m)
    if m.kind == "turf" then
        local rec = U.get(d, m.world)
        return rec and U.turf_chance(rec) or 0
    end
    local def = Missions.def(m.key)
    return def and def.chance or 0
end

function Missions.cooldown_weeks(d, f)
    local at = U.family(d, f).special_at or 0
    if GetCurrentTime() >= at then
        return 0
    end
    return M.max(1, M.ceil((at - GetCurrentTime()) / CONFIG.WEEK_SECONDS))
end

function Missions.blocked(d, key, f, world)
    local def = Missions.def(key)
    if not def then
        return "No such mission."
    end
    if Missions.running(d, f) then
        return "The " .. U.family_name(f) .. " are already on a mission."
    end
    if def.kind == "unlock" and U.family(d, f).unlocked then
        return "Already done."
    end
    if def.kind == "special" then
        if U.tier(d, f) < R.SPECIAL_TIER then
            return "The " .. U.family_name(f) .. " must reach tier " .. R.SPECIAL_TIER .. " first."
        end
        local wait = Missions.cooldown_weeks(d, f)
        if wait > 0 then
            return "Ready again in " .. wait .. (wait == 1 and " week." or " weeks.")
        end
    end
    if def.kind == "turf" then
        local rec = world and U.get(d, world)
        if not rec then
            return "No underworld here."
        end
        local blocked = U.turf_blocked(d, rec)
        if blocked then
            return blocked
        end
    elseif d.human.Get_Credits() < def.cost then
        return "You need " .. def.cost .. " credits."
    end
    return nil
end

function Missions.start(d, key, f, world)
    U.init(d)
    local blocked = Missions.blocked(d, key, f, world)
    if blocked then
        return false, blocked
    end
    local def = Missions.def(key)
    d.human.Give_Money(-def.cost)
    d.kj.next_mission = (d.kj.next_mission or 0) + 1
    local id = d.kj.next_mission
    d.kj.missions[id] = {id = id, key = key, kind = def.kind, family = f, world = world,
                         ends = GetCurrentTime() + def.weeks * CONFIG.WEEK_SECONDS}
    if def.kind == "turf" then
        U.get(d, world).turf = {family = f, mission = id}
    end
    if def.kind == "unlock" and R.PLACEHOLDER_WIN and Missions.placeholder(def) then
        Missions.finish(d, id, true)
        return true, def.name .. ": done (no mission to play yet)."
    end
    return true, def.name .. " begins for the " .. U.family_name(f) .. " (" .. def.weeks
        .. (def.weeks == 1 and " week)." or " weeks).")
end

local function apply(d, m, effects)
    if not effects then
        return ""
    end
    local parts = {}
    if effects.credits then
        d.human.Give_Money(effects.credits)
        table.insert(parts, ((effects.credits >= 0) and "+" or "") .. effects.credits .. " credits")
    end
    local rec = m.world and U.get(d, m.world)
    if rec and effects.influence then
        U.add_influence(rec, m.family, effects.influence, d)
        table.insert(parts, "+" .. effects.influence .. " influence")
    end
    if rec and effects.unrest then
        rec.unrest = M.max(0, (rec.unrest or 0) + effects.unrest)
        table.insert(parts, "+" .. effects.unrest .. " unrest")
    end
    return (table.getn(parts) > 0) and (" (" .. table.concat(parts, ", ") .. ")") or ""
end

local RESULT = {}

function RESULT.unlock(d, m, won, def, extra)
    if won then
        U.family(d, m.family).unlocked = true
        d.show("Kajidii: " .. def.name .. " succeeded. The " .. U.family_name(m.family) .. " now trust you "
            .. "with their Upstarts." .. extra, nil, COLOR)
    else
        d.show("Kajidii: " .. def.name .. " failed. The " .. U.family_name(m.family) .. " will let you try again."
            .. extra, nil, COLOR_BAD)
    end
end

function RESULT.special(d, m, won, def, extra)
    U.family(d, m.family).special_at = GetCurrentTime() + (def.cooldown or 0) * CONFIG.WEEK_SECONDS
    if won then
        d.show("Kajidii: " .. def.name .. " (" .. U.family_name(m.family) .. ") succeeded." .. extra, nil, COLOR)
    else
        d.show("Kajidii: " .. def.name .. " (" .. U.family_name(m.family) .. ") failed." .. extra, nil, COLOR_BAD)
    end
end

function RESULT.turf(d, m, won)
    U.turf_result(d, m.world, won)
end

function Missions.finish(d, id, won)
    local m = d.kj and d.kj.missions[id]
    if not m then
        return
    end
    d.kj.missions[id] = nil
    local def = Missions.def(m.key) or {}
    local extra = apply(d, m, won and def.reward or def.penalty)
    local result = RESULT[m.kind]
    if result then
        result(d, m, won, def, extra)
    end
end

function Missions.update(d)
    if not d.kj then
        return
    end
    local now = GetCurrentTime()
    for id, m in pairs(d.kj.missions) do
        if now >= m.ends and not m.launched then
            local def = Missions.def(m.key)
            local launch = def and def.battle and Missions.LAUNCH[def.battle]
            if launch then
                m.launched = launch(d, m) and true or nil
            end
            if not m.launched then
                Missions.finish(d, id, GameRandom.Free_Random(1, 100) <= Missions.chance(d, m))
            end
        end
    end
end

function Missions.weeks_left(m)
    return M.max(1, M.ceil((m.ends - GetCurrentTime()) / CONFIG.WEEK_SECONDS))
end

return Missions
