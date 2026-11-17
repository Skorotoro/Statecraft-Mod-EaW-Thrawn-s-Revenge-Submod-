local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")

local Goals = {}

local PLOT = "Conquests\\Events\\MissionRepository.xml"
local GOAL_SLOTS = 6

local function slots(d)
    d.goal_slots = d.goal_slots or {}
    return d.goal_slots
end

function Goals.week(time)
    return M.floor((time or GetCurrentTime()) / CONFIG.WEEK_SECONDS) + 1
end

function Goals.weeks_line(expires)
    return "Issued: week " .. Goals.week() .. ". Expires: week " .. Goals.week(expires) .. "."
end

function Goals.add(d, title, lines, expires)
    local used = slots(d)
    local k = nil
    for n = 1, GOAL_SLOTS do
        if not used[n] then
            k = n
            break
        end
    end
    local plot = Get_Story_Plot(PLOT)
    local event = plot and k and plot.Get_Event("Diplomacy_Goal_" .. k)
    if not event then
        return nil
    end
    used[k] = title
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_DIPLOMACY_GOAL_" .. k .. "_TITLE", title)
    end
    event.Clear_Dialog_Text()
    for _, line in ipairs(lines or {}) do
        M.add_dialog(event, line)
    end
    if expires then
        M.add_dialog(event, Goals.weeks_line(expires))
    end
    Story_Event("DIPLOMACY_GOAL_" .. k)
    return k
end

function Goals.remove(d, k)
    if k and slots(d)[k] then
        slots(d)[k] = nil
        Story_Event("DIPLOMACY_GOAL_" .. k .. "_DONE")
    end
end

function Goals.titles(d)
    local out = {}
    for k = 1, GOAL_SLOTS do
        if slots(d)[k] then
            table.insert(out, slots(d)[k])
        end
    end
    return out
end

Goals.SLOTS = GOAL_SLOTS
return Goals
