require("deepcore/std/class")

local DELAY = 3
local SPREAD = 60

local function log(text)
    if Engine_Log then
        Engine_Log("JEDI BATTLE " .. text)
    end
end

local function split(text, sep)
    local out = {}
    if type(text) ~= "string" then
        return out
    end
    for part in string.gfind(text, "([^" .. sep .. "]+)") do
        table.insert(out, part)
    end
    return out
end

local function battle_world()
    if not Engine_Battle_Planet then
        return nil
    end
    local ok, name = pcall(Engine_Battle_Planet)
    return ok and type(name) == "string" and string.upper(name) or nil
end

local function anchor(human, land)
    local first = nil
    for _, object in pairs(Find_All_Objects_Of_Type(human) or {}) do
        if TestValid(object) then
            if land and object.Is_Category("Structure") then
                return object
            end
            first = first or object
        end
    end
    return first
end

local function spawn(type_name, at, human, k)
    local unit_type = Find_Object_Type(type_name)
    if not unit_type or not at then
        return nil
    end
    local ok, pos = pcall(function()
        local p = at.Get_Position()
        local x, y, z = p.Get_XYZ()
        return Create_Position(x + (k - 1) * SPREAD, y + SPREAD, z)
    end)
    local ok2, list = pcall(Spawn_Unit, unit_type, ok and pos or at.Get_Position(), human)
    if not ok2 then
        return nil
    end
    if type(list) == "table" then
        return list[1]
    end
    return list
end

JediBattle = class()

function JediBattle:new()
    self.mode = nil
end

function JediBattle:reset()
    self.started, self.done, self.watch = nil, nil, {}
end

function JediBattle:roster(mode, world)
    local out = {}
    if mode == "Space" then
        for _, line in ipairs(split(GlobalValue.Get("JEDI_PARTIES"), ";")) do
            local parts = split(line, "|")
            if parts[1] == world then
                local types, ids = split(parts[2], ","), split(parts[3], ",")
                for k, t in ipairs(types) do
                    table.insert(out, {t, ids[k]})
                end
            end
        end
    else
        local parts = split(GlobalValue.Get("JEDI_TEMPLE"), "|")
        if parts[1] == world then
            local planet = FindPlanet(world)
            local human = Find_Player("local")
            if planet and human and planet.Get_Owner() == human then
                local types, ids = split(parts[2], ","), split(parts[3], ",")
                for k, t in ipairs(types) do
                    table.insert(out, {t, ids[k]})
                end
            end
        end
    end
    return out
end

function JediBattle:start(mode)
    local world = battle_world()
    local human = Find_Player("local")
    if not (world and human) then
        return
    end
    local list = self:roster(mode, world)
    if not list[1] then
        return
    end
    local at = anchor(human, mode == "Land")
    for k, entry in ipairs(list) do
        local unit = spawn(entry[1], at, human, k)
        if unit and TestValid(unit) then
            table.insert(self.watch, {unit = unit, id = entry[2]})
        end
    end
    GlobalValue.Set("JEDI_DOWN_WORLD", world)
    log(mode .. " at " .. world .. ": " .. table.getn(self.watch) .. " Jedi on the field")
end

function JediBattle:update()
    local mode = Get_Game_Mode()
    if mode ~= "Space" and mode ~= "Land" then
        if self.mode then
            self.mode = nil
            self:reset()
        end
        return
    end
    if mode ~= self.mode then
        self.mode = mode
        self:reset()
        self.at = GetCurrentTime()
    end
    if not self.started then
        if GetCurrentTime() - self.at < DELAY then
            return
        end
        self.started = true
        local ok, err = pcall(self.start, self, mode)
        if not ok then
            log("start failed: " .. tostring(err))
        end
        return
    end
    local down = nil
    for _, w in ipairs(self.watch) do
        if not w.down and not TestValid(w.unit) then
            w.down = true
            down = (down or "") .. w.id .. ","
        end
    end
    if down then
        local before = GlobalValue.Get("JEDI_DOWN")
        GlobalValue.Set("JEDI_DOWN", ((type(before) == "string") and before or "") .. down)
    end
end

return JediBattle
