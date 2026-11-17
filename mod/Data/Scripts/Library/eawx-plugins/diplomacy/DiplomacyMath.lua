local M = {}

local LN2 = 0.69314718055994530942
local LIMIT = 1e12

function M.sane(x)
    if type(x) ~= "number" or x ~= x then
        return 0
    end
    if x > LIMIT then
        return LIMIT
    end
    if x < -LIMIT then
        return -LIMIT
    end
    return x
end

function M.floor(x)
    x = M.sane(x)
    if x < 0 then
        local f = M.floor(-x)
        if f == -x then
            return x
        end
        return -f - 1
    end
    local power = 1
    local steps = 0
    while power * 2 <= x and steps < 64 do
        power = power * 2
        steps = steps + 1
    end
    local result = 0
    steps = 0
    while power >= 1 and steps < 64 do
        if result + power <= x then
            result = result + power
        end
        power = power / 2
        steps = steps + 1
    end
    return result
end

function M.ceil(x)
    local f = M.floor(x)
    if f < M.sane(x) then
        return f + 1
    end
    return f
end

function M.round(x)
    x = M.sane(x)
    if x >= 0 then
        return M.floor(x + 0.5)
    end
    return -M.floor(-x + 0.5)
end

function M.abs(x)
    x = M.sane(x)
    if x < 0 then
        return -x
    end
    return x
end

function M.min(a, b)
    a, b = M.sane(a), M.sane(b)
    if a < b then
        return a
    end
    return b
end

function M.max(a, b)
    a, b = M.sane(a), M.sane(b)
    if a > b then
        return a
    end
    return b
end

local function ln_1_to_2(x)
    local y = (x - 1) / (x + 1)
    local y2 = y * y
    local term, sum = y, 0
    for k = 1, 25, 2 do
        sum = sum + term / k
        term = term * y2
    end
    return 2 * sum
end

function M.log2(x)
    x = M.sane(x)
    if x <= 1e-12 then
        x = 1e-12
    end
    local n = 0
    local steps = 0
    while x >= 2 and steps < 64 do
        x = x / 2
        n = n + 1
        steps = steps + 1
    end
    while x < 1 and steps < 128 do
        x = x * 2
        n = n - 1
        steps = steps + 1
    end
    return n + ln_1_to_2(x) / LN2
end

function M.half_pow(t)
    t = M.sane(t)
    if t <= 0 then
        return 1
    end
    if t >= 64 then
        return 0
    end
    local result = 1
    while t >= 1 do
        result = result / 2
        t = t - 1
    end
    local z = -t * LN2
    local term, sum = 1, 1
    for k = 1, 12 do
        term = term * z / k
        sum = sum + term
    end
    return result * sum
end

M.DIALOG_WIDTH = 90

function M.add_dialog(event, text)
    if string.find(text, "^TEXT_[%w_]+$") then
        event.Add_Dialog_Text(text)
        return
    end
    while string.len(text) > M.DIALOG_WIDTH do
        local cut = M.DIALOG_WIDTH
        for i = M.DIALOG_WIDTH, 50, -1 do
            if string.sub(text, i, i) == " " then
                cut = i
                break
            end
        end
        event.Add_Dialog_Text((string.gsub(string.sub(text, 1, cut), "%%", "%%%%")))
        text = "   " .. string.sub(text, cut + 1)
    end
    event.Add_Dialog_Text((string.gsub(text, "%%", "%%%%")))
end

function M.next_week(week_seconds)
    return (M.floor(GetCurrentTime() / week_seconds) + 1) * week_seconds
end

function M.show_document(lines, title, info)
    if Engine_Set_Text then
        pcall(Engine_Set_Text, "TEXT_DIPLOMACY_PANEL_TITLE", title or "Diplomacy")
        pcall(Engine_Set_Text, "TEXT_DIPLOMACY_PANEL_INFO", info or " ")
    end
    local plot = Get_Story_Plot("Conquests\\Events\\MissionRepository.xml")
    local event = plot and plot.Get_Event("Diplomacy_Panel_Display")
    if not event then
        return false
    end
    event.Clear_Dialog_Text()
    for _, line in ipairs(lines) do
        M.add_dialog(event, line)
    end
    Story_Event("DIPLOMACY_PANEL_DISPLAY")
    return true
end

return M
