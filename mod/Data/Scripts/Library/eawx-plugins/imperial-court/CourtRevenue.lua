local Court = require("eawx-plugins/imperial-court/Court")
local CONFIG = require("eawx-plugins/imperial-court/CourtConfig")
local M = require("eawx-plugins/imperial-court/CourtMath")

local Revenue = {}
local R = CONFIG.REVENUE
local U = CONFIG.UNGOVERNED

local function serving_char(s, id)
    local c = Court.char(s, id)
    return (c and c.status == "serving") and c or nil
end

function Revenue.lords(s, name)
    local sector = s.sectors[(s.world and s.world[name]) or ""]
    local moff = sector and not sector.crown and serving_char(s, sector.holder) or nil
    local over = sector and sector.oversector and s.oversectors[sector.oversector]
    local gm = over and serving_char(s, over.holder) or nil
    return serving_char(s, s.governor[name]), moff, gm, sector
end

function Revenue.skill_pct(c)
    local skill = c.skill or 50
    if skill > R.HIGH then
        return R.MAX * (skill - R.HIGH) / (100 - R.HIGH)
    elseif skill < R.LOW then
        return -R.MAX * (R.LOW - skill) / R.LOW
    end
    return 0
end

function Revenue.mods(s, name)
    local out, sum = {}, 0
    local function add(text, pct, kind)
        pct = M.round(pct)
        if pct ~= 0 then
            table.insert(out, {text = text, pct = pct, kind = kind})
            sum = sum + pct
        end
    end
    local _, moff, _, sector = Revenue.lords(s, name)
    if Revenue.ungoverned(s, name) then
        add("No Governor", -R.NO_GOVERNOR, "no_governor")
    end
    if sector and not sector.crown then
        if not moff then
            add("No Moff in the " .. sector.name, -R.NO_MOFF, "no_moff")
        else
            add("Moff " .. moff.name .. "'s skill (" .. M.round(moff.skill or 0) .. ")", Revenue.skill_pct(moff), "skill")
            for _, t in ipairs(moff.traits or {}) do
                local trait = CONFIG.TRAITS[t]
                if trait and trait.income then
                    add("Moff " .. moff.name .. " is " .. string.lower(trait.name), trait.income, "traits")
                end
            end
        end
    end
    return out, M.max(-100, sum)
end

function Revenue.week(s)
    local by = {no_governor = 0, no_moff = 0, skill = 0, traits = 0}
    local total = 0
    local names = {}
    for name, _ in pairs(s.world or {}) do
        table.insert(names, name)
    end
    local empire = Court.player()
    for _, name in ipairs(Court.direct_worlds(s)) do
        local planet = FindPlanet(name)
        local ok, value = pcall(EvaluatePerception, "PlanetBaseIncome", empire, planet)
        s.world_income = s.world_income or {}
        s.world_income[name] = M.clamp((ok and tonumber(value)) or 0, 0, 100000)
        table.insert(names, name)
    end
    for _, name in ipairs(names) do
        local base = s.world_income and s.world_income[name]
        if base and base > 0 then
            local mods = Revenue.mods(s, name)
            for _, m in ipairs(mods) do
                local credits = base * m.pct / 100
                by[m.kind] = (by[m.kind] or 0) + credits
                total = total + credits
            end
        end
    end
    total = M.round(total)
    if total ~= 0 and empire then
        empire.Give_Money(total)
    end
    s.revenue = {total = total, no_governor = M.round(by.no_governor), no_moff = M.round(by.no_moff),
                 skill = M.round(by.skill), traits = M.round(by.traits)}
end

function Revenue.find_palaces(s)
    local empire = Court.player()
    local found = {}
    for _, type_name in ipairs(U.PALACES) do
        local ok, objects = pcall(function()
            if not Find_Object_Type(type_name) then
                return nil
            end
            return Find_All_Objects_Of_Type(type_name)
        end)
        for _, obj in pairs((ok and objects) or {}) do
            local ok2, name = pcall(function()
                if not TestValid(obj) or obj.Get_Owner() ~= empire then
                    return nil
                end
                local planet = obj.Get_Planet_Location()
                return planet and Court.name_of(planet)
            end)
            if ok2 and name then
                found[name] = true
            end
        end
    end
    s.world_palace = found
end

function Revenue.ungoverned(s, name)
    if name == s.capital then
        return false
    end
    local gov, moff, _, sector = Revenue.lords(s, name)
    if gov or (sector and sector.crown) then
        return false
    end
    return not (sector and moff and sector.seat == name)
end

local function preferred(name)
    local ok, Intel = pcall(require, "eawx-plugins/imperial-court/CourtIntel")
    local loyal = ok and Intel and Intel.preferred and Intel.preferred(name)
    return string.upper(loyal or "INDEPENDENT_FORCES")
end

function Revenue.rising_chance(s, name)
    if (s.stability or 100) >= U.BELOW then
        return 0, "the Empire is steady (stability " .. U.BELOW .. " or more)"
    end
    if not Revenue.ungoverned(s, name) then
        return 0, "it is governed"
    end
    local calm = s.calm and s.calm[name]
    if calm and calm > s.week then
        return 0, "calm for " .. M.weeks(calm - s.week)
    end
    if preferred(name) == CONFIG.FACTION then
        return 0, "it would rise for the Empire"
    end
    local chance = U.CHANCE * (1 + (U.BELOW - s.stability) / U.STEEP)
    if not (s.world_palace and s.world_palace[name]) then
        chance = chance * U.NO_PALACE
    end
    return chance, (s.world_palace and s.world_palace[name]) and "no Governor" or "no Governor and no Moff Palace"
end

function Revenue.calm(s, name, weeks, force)
    s.calm = s.calm or {}
    if force or not s.calm[name] or s.calm[name] <= (s.week or 0) then
        s.calm[name] = (s.week or 0) + weeks
    end
end

local function rise(s, name)
    local planet = FindPlanet(name)
    if not planet or (DIPLOMACY_CAN_RISE and not DIPLOMACY_CAN_RISE(name)) then
        return
    end
    Revenue.calm(s, name, U.AFTER_RISING, true)
    s.rebel_pending = s.rebel_pending or {}
    s.rebel_pending[name] = true
    DIPLOMACY_REVOLTS = DIPLOMACY_REVOLTS or {}
    DIPLOMACY_REVOLTS[string.upper(name)] = {kind = "REVOLT", time = GetCurrentTime()}
    local empire = Court.player()
    if DIPLOMACY_REBELLION and empire and empire.Is_Human() then
        pcall(DIPLOMACY_REBELLION, planet, "it has no Governor, and Imperial stability is down to "
            .. M.round(s.stability or 0))
    else
        (DIPLOMACY_REVOLT_POPULATE or ChangePlanetOwnerAndPopulate)(planet,
                    require("eawx-plugins/imperial-court/CourtIntel").rising_owner(name), 3000)
    end
    local label = Court.planet_label(name)
    Court.news(s, label .. " rises: with no Governor, its planetary government is too weak to hold it.")
    Court.alert(label .. " rises: nobody governs it.", "threat")
end

function Revenue.week_risings(s)
    for name, until_week in pairs(s.calm or {}) do
        if until_week <= s.week then
            s.calm[name] = nil
        end
    end
    if (s.stability or 100) >= U.BELOW then
        return
    end
    local names = {}
    for name, _ in pairs(s.world or {}) do
        table.insert(names, name)
    end
    for _, name in ipairs(Court.direct_worlds(s)) do
        table.insert(names, name)
    end
    table.sort(names)
    local risen = {}
    for _, name in ipairs(names) do
        local chance = Revenue.rising_chance(s, name)
        if chance > 0 and M.random(1, 10000) <= chance * 100 then
            table.insert(risen, name)
        end
    end
    local name = M.pick(risen)
    if name then
        rise(s, name)
    end
end

return Revenue
