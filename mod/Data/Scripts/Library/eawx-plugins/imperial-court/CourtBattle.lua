local Battle = {}

local each = string.gfind or string.gmatch

function Battle.land()
    local data = GlobalValue.Get("COURT_BRIBES")
    local world = Engine_Battle_Planet and Engine_Battle_Planet()
    if type(data) ~= "string" or data == "" or not world then
        return 0
    end
    world = string.upper(world)
    local idle = 0
    for entry in each(data, "[^;]+") do
        local _, _, name, list = string.find(entry, "^([^=]+)=(.*)$")
        if name == world then
            for type_name, n in each(list, "([^,%*]+)%*(%d+)") do
                local left = tonumber(n) or 0
                if Find_Object_Type(type_name) then
                    for _, obj in pairs(Find_All_Objects_Of_Type(type_name) or {}) do
                        if left > 0 and TestValid(obj) and pcall(obj.Set_Garrison_Spawn, false) then
                            pcall(obj.Highlight, true)
                            left = left - 1
                            idle = idle + 1
                        end
                    end
                end
            end
        end
    end
    if idle > 0 and Engine_Log then
        Engine_Log("COURT BRIBES: " .. idle .. " garrison buildings idle on " .. world)
    end
    return idle
end

return Battle
