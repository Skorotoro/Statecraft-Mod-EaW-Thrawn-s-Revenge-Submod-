require("deepcore/std/class")

local DATA = require("eawx-plugins/diplomacy/DiplomacyRebellionData")

local DELAY = 3
local SAFE_DISTANCE = 700
local ORDER_SECONDS = 8
local FIGHTING = {"Infantry", "Vehicle", "InfantryHero", "VehicleHero", "AirSpeeder", "AirGunship"}

local function is_fighting(object)
    for _, category in ipairs(FIGHTING) do
        if object.Is_Category(category) then
            return true
        end
    end
    return false
end

local function log(text)
    if Engine_Log then
        Engine_Log("REBELLION " .. text)
    end
end

local function split(list)
    local out = {}
    for name in string.gfind(list or "", "([^,]+)") do
        table.insert(out, name)
    end
    return out
end

local function distance_to(point, objects)
    local best = nil
    for _, object in ipairs(objects) do
        local distance = point.Get_Distance(object)
        if not best or distance < best then
            best = distance
        end
    end
    return best or 999999
end

local function reverse()
    return GlobalValue.Get("DIPLOMACY_REBELLION_REVERSE") == 1
end

local function rising_points(human)
    local defenders = {}
    for _, object in pairs(Find_All_Objects_Of_Type(human) or {}) do
        if TestValid(object) then
            table.insert(defenders, object)
        end
    end
    local all = {}
    local names = {"Attacker Entry Position"}
    for _, name in ipairs(DATA.MARKERS or {}) do
        table.insert(names, name)
    end
    for _, name in ipairs(names) do
        for _, point in pairs(Find_All_Objects_Of_Type(name) or {}) do
            if TestValid(point) then
                table.insert(all, {point = point, distance = distance_to(point, defenders)})
            end
        end
    end
    local good = {}
    for _, entry in ipairs(all) do
        if entry.distance >= SAFE_DISTANCE then
            table.insert(good, entry)
        end
    end
    if table.getn(good) < 2 then
        good = all
    end
    table.sort(good, function(a, b) return a.distance > b.distance end)
    local points = {}
    for _, entry in ipairs(good) do
        table.insert(points, entry.point)
    end
    return points
end

RebellionLanding = class()

function RebellionLanding:new()
    self.seen_at = nil
    self.attacking = false
end

function RebellionLanding:attack()
    local rebels = Find_Player(GlobalValue.Get("DIPLOMACY_REBELLION_OWNER") or "Independent_Forces")
    local human = Find_Player("local")
    local buildings = {}
    for _, object in pairs(Find_All_Objects_Of_Type(human) or {}) do
        if TestValid(object) and object.Is_Category("Structure") then
            table.insert(buildings, object)
        end
    end
    local sent = 0
    for _, unit in pairs(rebels and Find_All_Objects_Of_Type(rebels) or {}) do
        if TestValid(unit) and is_fighting(unit) then
            local target, best = nil, nil
            for _, building in ipairs(buildings) do
                local distance = unit.Get_Distance(building)
                if not best or distance < best then
                    target, best = building, distance
                end
            end
            if not TestValid(target) then
                target = Find_Nearest(unit, human, true)
            end
            if TestValid(target) and pcall(unit.Attack_Move, target) then
                sent = sent + 1
            end
        end
    end
    return sent, table.getn(buildings)
end

function RebellionLanding:update()
    if Get_Game_Mode() ~= "Land" then
        self.seen_at = nil
        self.heartbeat = nil
        self.attacking = false
        self.point_taken = nil
        return
    end
    if self.attacking and not self.reverse and GetCurrentTime() >= self.next_orders then
        self.next_orders = GetCurrentTime() + ORDER_SECONDS
        local ok, sent, buildings = pcall(self.attack, self)
        if self.first_orders then
            self.first_orders = false
            log("attack orders: " .. tostring(ok) .. " " .. tostring(sent) .. " units, " .. tostring(buildings)
                .. " buildings to take")
        end
    end
    if self.attacking and not self.point_taken then
        local rebels = Find_Player(GlobalValue.Get("DIPLOMACY_REBELLION_OWNER") or "Independent_Forces")
        local ok, points = pcall(Find_All_Objects_Of_Type, "Victory_Point")
        for _, point in pairs(ok and points or {}) do
            if TestValid(point) and rebels and point.Get_Owner() == rebels then
                self.point_taken = true
                GlobalValue.Set("DIPLOMACY_REBELLION_RESULT", "REBELS")
                log("the rebels hold the victory point")
            end
        end
    end
    if self.heartbeat and GetCurrentTime() - self.heartbeat >= 10 then
        self.heartbeat = GetCurrentTime()
        log("battle still running, time " .. tostring(GetCurrentTime()))
    end
    if GlobalValue.Get("DIPLOMACY_REBELLION_STATE") ~= "PENDING" then
        return
    end
    local now = GetCurrentTime()
    self.seen_at = self.seen_at or now
    if now - self.seen_at < DELAY then
        return
    end
    GlobalValue.Set("DIPLOMACY_REBELLION_STATE", "LANDED")
    self:land()
end

function RebellionLanding:land()
    local insurgents = Find_Player(GlobalValue.Get("DIPLOMACY_REBELLION_OWNER") or "Independent_Forces")
    local human = Find_Player("local")
    local up = reverse()
    if up then
        human = Find_Player(GlobalValue.Get("DIPLOMACY_REBELLION_DEFENDER") or "Independent_Forces")
    end
    local points = rising_points(human)
    local army = split(GlobalValue.Get("DIPLOMACY_REBELLION_ARMY"))
    if not insurgents or table.getn(points) == 0 then
        log("no rebels landed: insurgents " .. tostring(insurgents) .. ", points " .. table.getn(points))
        return
    end
    local landed = 0
    local index = GameRandom.Free_Random(1, table.getn(points))
    for _, name in ipairs(army) do
        local unit_type = Find_Object_Type(name)
        if unit_type and pcall(Spawn_Unit, unit_type, points[index], insurgents) then
            landed = landed + 1
        end
        index = index + 1
        if index > table.getn(points) then
            index = 1
        end
    end
    log("landed " .. landed .. " of " .. table.getn(army) .. " companies at " .. table.getn(points) .. " points")
    self.heartbeat = GetCurrentTime()
    self.attacking = true
    self.reverse = up
    self.first_orders = true
    self.next_orders = GetCurrentTime() + 2
end

return RebellionLanding
