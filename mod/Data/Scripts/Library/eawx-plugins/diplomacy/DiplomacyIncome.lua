local M = require("eawx-plugins/diplomacy/DiplomacyMath")
local CONFIG = require("eawx-plugins/diplomacy/DiplomacyConfig")

local Income = {next_at = 0}
local REFRESH = 4

local function patch_display()
    local class = ShipCrewDisplayComponent
    if Income.patched or type(class) ~= "table" or type(class.render) ~= "function" then
        return
    end
    Income.patched = true
    local render = class.render
    class.render = function(self)
        Income.display = self
        local shown = Income.shown
        if shown and tonumber(self.UpkeepCost) ~= nil then
            self.UpkeepCost, self.NetIncome = shown.upkeep, shown.net
        end
        return render(self)
    end
end

local function perceive(name, player, target)
    local ok, value
    if target then
        ok, value = pcall(EvaluatePerception, name, player, target)
    else
        ok, value = pcall(EvaluatePerception, name, player)
    end
    if not ok then
        return 0
    end
    return M.min(M.max(M.sane(value), -10000000), 10000000)
end

local function signed(n)
    if n > 0 then
        return "+" .. n
    end
    return "" .. n
end

function Income.rows(d)
    local human = d.human
    local out, total = {}, 0
    local function add(label, amount)
        amount = M.floor(amount + 0.5)
        if amount ~= 0 then
            table.insert(out, {label, amount})
            total = total + amount
        end
    end

    local upkeep = M.floor(perceive("Total_Maintenance", human)) - 10 * perceive("LightFactory_Count", human)
        - 20 * perceive("HeavyFactory_Count", human) - 30 * perceive("AdvFactory_Count", human)
    add("Fleet upkeep", -M.max(0, upkeep))
    local upkeep_paid = M.max(0, upkeep)

    if human.Get_Faction_Name() == "HUTT_CARTELS" then
        local ok, smuggling = pcall(GlobalValue.Get, "HUTT_SMUGGLING_INCOME")
        if ok and type(smuggling) == "number" then
            add("Smuggling network", smuggling)
        end
    end

    local vassals = d:vassal_player()
    for name, w in pairs(d.vassal_worlds or {}) do
        local planet = FindPlanet(name)
        local owner = planet and planet.Get_Owner()
        if owner and not w.slot then
            local income = M.min(M.max(perceive("PlanetBaseIncome", human, planet), 0), 100000)
            if owner == vassals then
                add("Vassal world " .. d:planet_name(planet), income * (1 - CONFIG.VASSAL_WORLD_KEEPS))
            elseif owner == human then
                add("Vassal world " .. d:planet_name(planet) .. " (its share)", -income * CONFIG.VASSAL_WORLD_KEEPS)
            end
        end
    end

    for faction, amount in pairs(d.last_tribute or {}) do
        add("Tribute from " .. d.display_name(faction), amount)
    end

    local me = human.Get_Faction_Name()
    for _, t in ipairs(d.tributes or {}) do
        if t.payee == me then
            add("Tribute from " .. d.display_name(t.payer) .. " (" .. t.left .. " wk)", t.amount)
        elseif t.payer == me then
            add("Tribute to " .. d.display_name(t.payee) .. " (" .. t.left .. " wk)", -t.amount)
        end
    end

    local found, Council = pcall(require, "eawx-plugins/new-republic/RepublicCouncil")
    if found and Council and d.republic and Council.active(d) then
        add("No Central Government", -Council.base_income(d))
        local ok_i, Influence = pcall(require, "eawx-plugins/new-republic/RepublicInfluence")
        if ok_i and Influence then
            local refund, why = Influence.upkeep_refund(d)
            refund = refund or 0
            add(why or "Upkeep halved", refund)
            upkeep_paid = upkeep_paid - M.floor(refund + 0.5)
        end
    end

    table.insert(out, {" ", 0, " "})
    local net = M.floor(perceive("Current_Income", human)) + total
    table.insert(out, {"Net income per week", net})
    return out, total, net, M.max(0, upkeep_paid)
end

function Income.update(d)
    if not Engine_Income_Rows or GetCurrentTime() < Income.next_at then
        return
    end
    Income.next_at = GetCurrentTime() + REFRESH
    pcall(patch_display)
    local ok, rows, total, net, upkeep = pcall(Income.rows, d)
    if not ok then
        if Engine_Log then
            Engine_Log("INCOME tooltip error: " .. tostring(rows))
        end
        return
    end
    local tab, newline = string.char(9), string.char(10)
    local text = ""
    for _, row in ipairs(rows) do
        text = text .. row[1] .. tab .. (row[3] or signed(row[2])) .. newline
    end
    pcall(Engine_Income_Rows, text)
    local before = Income.shown
    Income.shown = {net = net, upkeep = upkeep}
    if Income.display and (not before or before.net ~= net or before.upkeep ~= upkeep) then
        Income.display.__needs_update = true
    end
    if Engine_Shown_Income then
        Engine_Shown_Income(total or 0)
    end
end

return Income
