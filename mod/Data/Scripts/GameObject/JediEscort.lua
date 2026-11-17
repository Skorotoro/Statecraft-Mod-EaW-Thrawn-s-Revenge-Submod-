require("PGStateMachine")

function Definitions()
    ServiceRate = 1
    Define_State("State_Init", State_Init)
end

function State_Init(message)
    if message == OnEnter then
        if Get_Game_Mode() == "Galactic" then
            ScriptExit()
        end
        Object.Set_Selectable(false)
        local list = GlobalValue.Get("JEDI_ESCORT_" .. string.upper(Object.Get_Type().Get_Name()))
        if type(list) == "string" then
            for name in string.gfind(list, "[^,]+") do
                local unit_type = Find_Object_Type(name)
                if unit_type then
                    Spawn_Unit(unit_type, Object.Get_Position(), Object.Get_Owner())
                end
            end
        end
        Object.Despawn()
        ScriptExit()
    end
end
