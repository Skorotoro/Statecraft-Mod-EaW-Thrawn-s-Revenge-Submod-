require("UnitSpawnerTables")
local NATIVES = require("eawx-plugins/diplomacy/DiplomacyNatives")
local REBELS = require("eawx-plugins/diplomacy/DiplomacyRebels")
local KINDS = require("eawx-plugins/diplomacy/DiplomacyRebellionData").KINDS
local M = require("eawx-plugins/diplomacy/DiplomacyMath")

local Grants = {}

local MAX_SHIP_COST = 2500
local MAX_GROUND_COST = 1500
local SHIP_CHANCE = 3
local ELITE = {"elite", "prototype", "royal", "honor", "bodyguard", "assassin", "hero", "influence", "commander", "dummy"}
local GENERIC_SHIPS = {"CR90", "DP20", "IPV1", "Customs_Corvette", "Marauder_Cruiser", "Carrack_Cruiser"}
local GENERIC_GROUND = {"PDF_Soldier_Company", "PDF_Tactical_Unit_Company", "Light_Mercenary_Company",
                        "Mercenary_Company", "Espo_Company"}

local function is_elite(name)
    local lower = string.lower(name)
    for _, word in ipairs(ELITE) do
        if string.find(lower, word, 1, true) then
            return true
        end
    end
    return false
end

local function usable(name, max_cost)
    if type(name) ~= "string" or is_elite(name) then
        return nil
    end
    local unit_type = Find_Object_Type(name)
    if not unit_type then
        return nil
    end
    local ok, cost = pcall(unit_type.Get_Build_Cost)
    if ok and type(cost) == "number" and cost > max_cost then
        return nil
    end
    return unit_type
end

local function candidates(spawn_table, max_cost)
    local year = GlobalValue.Get("GALACTIC_YEAR") or 0
    local out = {}
    for _, entry in pairs(spawn_table or {}) do
        local start, last = entry.StartYear, entry.LastYear
        if (start == nil or year >= start) and (last == nil or year <= last) then
            local unit_type = usable(entry[1], max_cost)
            if unit_type then
                table.insert(out, {unit_type, entry[2] or 1})
            end
        end
    end
    return out
end

local function from_names(names, max_cost)
    local out = {}
    for _, name in ipairs(names or {}) do
        local unit_type = usable(name, max_cost)
        if unit_type then
            table.insert(out, {unit_type, 1})
        end
    end
    return out
end

local function pick(list)
    local total = 0
    for _, item in ipairs(list) do
        total = total + item[2]
    end
    if total <= 0 then
        return nil
    end
    local roll = GameRandom.Free_Random(1, 1000) * total / 1000
    for _, item in ipairs(list) do
        roll = roll - item[2]
        if roll <= 0 then
            return item[1]
        end
    end
    return list[table.getn(list)][1]
end

local function roll_units(ships, ground)
    if table.getn(ships) == 0 then
        ships = from_names(GENERIC_SHIPS, MAX_SHIP_COST)
    end
    if table.getn(ground) == 0 then
        ground = from_names(GENERIC_GROUND, MAX_GROUND_COST)
    end
    local result = {}
    local count = GameRandom.Free_Random(1, 3)
    for i = 1, count do
        local unit_type = nil
        if GameRandom.Free_Random(1, SHIP_CHANCE) == 1 then
            unit_type = pick(ships)
        end
        unit_type = unit_type or pick(ground) or pick(ships)
        if unit_type then
            table.insert(result, unit_type)
        end
    end
    return result
end

function Grants.for_world(planet_name)
    local tables = DefineUnitTable("INDEPENDENT_FORCES", DefineRosterOverride(planet_name)) or {}
    local ground = from_names(NATIVES[planet_name], MAX_GROUND_COST)
    if table.getn(ground) == 0 then
        ground = candidates(tables.Land_Unit_Table, MAX_GROUND_COST)
    end
    return roll_units(candidates(tables.Space_Unit_Table, MAX_SHIP_COST), ground)
end

function Grants.for_faction(faction_name)
    local tables = DefineUnitTable(faction_name, nil) or {}
    return roll_units(candidates(tables.Space_Unit_Table, MAX_SHIP_COST),
        candidates(tables.Land_Unit_Table, MAX_GROUND_COST))
end

function Grants.rebel_army(planet_name, faction_name, sizes)
    local tables = DefineUnitTable("INDEPENDENT_FORCES", DefineRosterOverride(planet_name)) or {}
    local natives = from_names(REBELS[planet_name] or NATIVES[planet_name], sizes.max_cost)
    local local_units = candidates(tables.Land_Unit_Table, sizes.max_cost)
    if table.getn(local_units) == 0 then
        local_units = from_names(GENERIC_GROUND, sizes.max_cost)
    end
    local faction_units = {}
    if faction_name and faction_name ~= "INDEPENDENT_FORCES" then
        local ok, faction_tables = pcall(DefineUnitTable, faction_name, nil)
        if ok and faction_tables then
            faction_units = candidates(faction_tables.Land_Unit_Table, sizes.max_cost)
        end
    end
    local total = sizes.natives + sizes.locals + sizes.faction + (sizes.mercenaries or 0)
    local caps = {V = M.floor(total * (sizes.vehicle_share or 1)), H = sizes.heavy_max or total}
    local counts = {V = 0, H = 0}
    local army = {}
    local function kind(unit_type)
        return KINDS and KINDS[string.upper(unit_type.Get_Name())]
    end
    local function allowed(unit_type)
        local k = kind(unit_type)
        return not k or (counts.V < caps.V and (k ~= "H" or counts.H < caps.H))
    end
    local function add(list, count)
        for i = 1, count do
            local unit_type = pick(list)
            for _ = 1, 8 do
                if not unit_type or allowed(unit_type) then
                    break
                end
                unit_type = pick(list)
            end
            if unit_type and not allowed(unit_type) then
                unit_type = pick(natives) or pick(local_units)
                if unit_type and not allowed(unit_type) then
                    unit_type = nil
                end
            end
            if unit_type then
                local k = kind(unit_type)
                if k then
                    counts.V = counts.V + 1
                    if k == "H" then
                        counts.H = counts.H + 1
                    end
                end
                table.insert(army, unit_type.Get_Name())
            end
        end
    end
    if table.getn(natives) > 0 then
        add(natives, sizes.natives)
    else
        add(local_units, sizes.natives)
    end
    add(local_units, sizes.locals)
    add(faction_units, sizes.faction)
    add(from_names({"Light_Mercenary_Company", "Mercenary_Company"}, sizes.max_cost), sizes.mercenaries or 0)
    return army
end

return Grants
