local M = {}

function M.sane(x)
    if type(x) ~= "number" or x ~= x then
        return 0
    end
    if x > 1e12 then
        return 1e12
    end
    if x < -1e12 then
        return -1e12
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
    local power, steps = 1, 0
    while power * 2 <= x and steps < 64 do
        power, steps = power * 2, steps + 1
    end
    local result = 0
    steps = 0
    while power >= 1 and steps < 64 do
        if result + power <= x then
            result = result + power
        end
        power, steps = power / 2, steps + 1
    end
    return result
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

function M.clamp(x, lo, hi)
    return M.max(lo, M.min(hi, x))
end

function M.mod(x, n)
    return x - M.floor(x / n) * n
end

function M.random(lo, hi)
    if not hi then
        lo, hi = 1, lo
    end
    if hi <= lo then
        return lo
    end
    return GameRandom.Free_Random(lo, hi)
end

function M.chance(p)
    if p <= 0 then
        return false
    end
    return GameRandom.Free_Random(1, 10000) <= p * 100
end

function M.pick(list)
    local n = table.getn(list)
    if n == 0 then
        return nil
    end
    return list[M.random(1, n)]
end

function M.weeks(n)
    n = M.round(n)
    return n .. ((n == 1) and " week" or " weeks")
end

function M.signed(n)
    n = M.round(n)
    if n > 0 then
        return "+" .. n
    end
    return tostring(n)
end

return M
