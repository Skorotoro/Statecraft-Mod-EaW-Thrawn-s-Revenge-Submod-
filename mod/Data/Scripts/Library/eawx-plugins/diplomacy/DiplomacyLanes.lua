local Lanes = {}

local function names(planets)
    local out = {}
    for _, planet in pairs(planets) do
        table.insert(out, string.upper(planet.Get_Type().Get_Name()))
    end
    return table.concat(out, ";")
end

function Lanes.refresh(planets)
    if Engine_Lanes_Refresh and planets then
        pcall(Engine_Lanes_Refresh, names(planets))
    end
end

function Lanes.trade(human, partners, refresh)
    if not Engine_Trade_Lanes then
        return
    end
    local list = {}
    for faction, _ in pairs(partners) do
        table.insert(list, faction)
    end
    pcall(Engine_Trade_Lanes, human, table.concat(list, ";"))
    Lanes.refresh(refresh)
end

return Lanes
