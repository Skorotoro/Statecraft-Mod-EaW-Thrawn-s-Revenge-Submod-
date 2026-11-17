local Clicks = {}
local PARTS = nil

local function parts()
    if PARTS == nil then
        local ok, list = pcall(require, "eawx-plugins/diplomacy/DiplomacyClickParts")
        PARTS = ok and type(list) == "table" and list or {}
    end
    return PARTS
end

local function cursor()
    if not (Engine_Cursor and Engine_Screen_Size) then
        return nil
    end
    local mx, my = Engine_Cursor()
    local w, h = Engine_Screen_Size()
    if not h or h <= 0 then
        return nil
    end
    local scale = h / 768
    return (mx - w / 2) / scale, (h / 2 - my) / scale
end

local function shown(name)
    return not Engine_Gui_Visible or Engine_Gui_Visible(name) ~= nil
end

function Clicks.pick()
    local x, y = cursor()
    if not x then
        return nil
    end
    local best, depth = nil, nil
    local seen = {}
    for name, p in pairs(parts()) do
        if (not depth or p[2] > depth) and x >= p[3] - p[5] / 2 and x <= p[3] + p[5] / 2
                and y >= p[4] - p[6] / 2 and y <= p[4] + p[6] / 2 then
            local shell_shown = seen[p[1]]
            if shell_shown == nil then
                shell_shown = shown(p[1])
                seen[p[1]] = shell_shown
            end
            if shell_shown and shown(name) then
                best, depth = name, p[2]
            end
        end
    end
    return best
end

function Clicks.name(name)
    if name == "?" then
        return Clicks.pick()
    end
    return name
end

return Clicks
