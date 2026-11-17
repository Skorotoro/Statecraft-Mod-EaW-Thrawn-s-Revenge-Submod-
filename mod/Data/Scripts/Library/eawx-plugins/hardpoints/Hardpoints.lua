local Hardpoints = {}

local ROWS = 6
local IMPERIAL = {
    {type = "Empire_Anti_Vehicle_Turret", uc = "UC_Empire_Anti_Vehicle_Turret", name = "Anti-Vehicle Turret", icon = "i_button_e_anti_vehicle.tga"},
    {type = "Empire_Anti_Infantry_Turret", uc = "UC_Empire_Anti_Infantry_Turret", name = "Anti-Infantry Turret", icon = "i_button_e_anti_infantry.tga"},
    {type = "Empire_Anti_Aircraft_Turret", uc = "UC_Empire_Anti_Aircraft_Turret", name = "Anti-Aircraft Turret", icon = "i_button_e_anti_aircraft.tga"},
    {type = "Empire_Bacta_Tank", uc = "UC_Empire_Bacta_Tank", name = "Bacta Tank", icon = "i_button_bacta_tank.tga"},
    {type = "Empire_Repair_Facility", uc = "UC_Empire_Repair_Facility", name = "Repair Facility", icon = "i_button_e_repair_facility.tga"},
    {type = "Empire_Sensor_Node", uc = "UC_Empire_Sensor_Node", name = "Sensor Node", icon = "i_button_sensor_node.tga"},
}
local REBEL = {
    {type = "Rebel_Anti_Vehicle_Turret", uc = "UC_Rebel_Anti_Vehicle_Turret", name = "Anti-Vehicle Turret", icon = "i_button_r_anti_vehicle.tga"},
    {type = "Rebel_Anti_Infantry_Turret", uc = "UC_Rebel_Anti_Infantry_Turret", name = "Anti-Infantry Turret", icon = "i_button_r_anti_infantry.tga"},
    {type = "Rebel_Anti_Aircraft_Turret", uc = "UC_Rebel_Anti_Aircraft_Turret", name = "Anti-Aircraft Turret", icon = "i_button_r_anti_aircraft.tga"},
    {type = "Rebel_Bacta_Tank", uc = "UC_Rebel_Bacta_Tank", name = "Bacta Tank", icon = "i_button_bacta_tank.tga"},
    {type = "Rebel_Repair_Facility", uc = "UC_Rebel_Repair_Facility", name = "Repair Facility", icon = "i_button_e_repair_facility.tga"},
    {type = "Rebel_Sensor_Node", uc = "UC_Rebel_Sensor_Node", name = "Sensor Node", icon = "i_button_sensor_node.tga"},
}
local REBEL_SET = {REBEL = true, HAPES_CONSORTIUM = true, HUTT_CARTELS = true, SSIRUUVI_IMPERIUM = true,
                   KILLIK_HIVES = true, INDEPENDENT_FORCES = true}

Hardpoints.pad = nil

local CLICK_SOUND = "GUI_Unit_Scroll_SFX"
local SOLD_SOUND = "GUI_Structure_Sold"

local function show(name, visible)
    GUI_Component_Visibility(name, visible)
end

local function text(name, words)
    GUI_Component_Text(name, words)
end

local function tip(name, words)
    if Engine_Set_Text then
        Engine_Set_Text("TEXT_" .. string.upper(name) .. "_TIP", words)
    end
end

local function close()
    Hardpoints.pad = nil
    Hardpoints.options = nil
    if Engine_Layout_Select then
        Engine_Layout_Select("0")
    end
    show("dp_hp_shell", false)
end

local function cost_of(option)
    local t = Find_Object_Type(option.uc)
    local ok, cost = pcall(function() return t.Get_Tactical_Build_Cost() end)
    return (t and ok and cost) or 200
end

local function set_of(d)
    return REBEL_SET[string.upper(d.human.Get_Faction_Name())] and REBEL or IMPERIAL
end

local function option_of(type_name)
    for _, set in ipairs({REBEL, IMPERIAL}) do
        for _, option in ipairs(set) do
            if string.upper(option.type) == string.upper(type_name) then
                return option
            end
        end
    end
end

local function sound(event)
    if Engine_Play_Sound then
        pcall(Engine_Play_Sound, event)
    end
end

local function draw(d)
    local built = Engine_Hardpoint_At(tostring(Hardpoints.pad))
    show("dp_hp_shell", true)
    if built then
        local option = option_of(built)
        text("dp_hp_title", "Hardpoint: " .. (option and option.name or built))
        for k = 1, ROWS do
            show("dp_hp_i_" .. k, k == 1 and option ~= nil)
            show("dp_hp_t_" .. k, k == 1)
        end
        if option then
            GUI_Button_Icon("dp_hp_i_1", option.icon, 1, 1, 1, 1)
            tip("dp_hp_i_1", option.name)
        end
        text("dp_hp_t_1", "Demolish")
        tip("dp_hp_t_1", "Tear it down. No credits come back.")
        Hardpoints.options = nil
        return
    end
    text("dp_hp_title", "Build a Hardpoint")
    local options = set_of(d)
    Hardpoints.options = options
    local credits = d.human.Get_Credits()
    for k = 1, ROWS do
        local option = options[k]
        show("dp_hp_i_" .. k, option ~= nil)
        show("dp_hp_t_" .. k, option ~= nil)
        if option then
            local cost = cost_of(option)
            GUI_Button_Icon("dp_hp_i_" .. k, option.icon, 1, 1, 1, 1)
            text("dp_hp_t_" .. k, option.name .. "   " .. cost)
            tip("dp_hp_t_" .. k, (credits >= cost) and ("Build it now for " .. cost .. " credits. It stands in every land "
                .. "battle here until it is destroyed or the world is lost.")
                or ("It costs " .. cost .. " credits; you have " .. credits .. "."))
            tip("dp_hp_i_" .. k, option.name)
        end
    end
end

function Hardpoints.tick(d)
    if not Engine_Layout_Open then
        return
    end
    local world = Engine_Layout_Open()
    if not world then
        if Hardpoints.pad then
            close()
        end
        return
    end
    local pick = Engine_Layout_Pick()
    if not pick then
        return
    end
    local _, _, id = string.find(pick, "^(%d+)|")
    local planet = FindPlanet(world)
    if not (id and planet and planet.Get_Owner() == d.human) then
        return
    end
    sound(CLICK_SOUND)
    Hardpoints.pad = tonumber(id)
    Engine_Layout_Select(id)
    draw(d)
end

function Hardpoints.click(d, name, button)
    if name == "dp_hp_close" or button == "right" then
        close()
        return
    end
    local _, _, row = string.find(name, "^dp_hp_[it]_(%d+)$")
    row = tonumber(row)
    if not (row and Hardpoints.pad) then
        return
    end
    local pad = tostring(Hardpoints.pad)
    if not Hardpoints.options then
        if string.find(name, "^dp_hp_t_") and Engine_Hardpoint_Remove(pad) then
            sound(SOLD_SOUND)
            close()
        end
        return
    end
    local option = Hardpoints.options[row]
    if not option then
        return
    end
    local cost = cost_of(option)
    if d.human.Get_Credits() < cost then
        return
    end
    if Engine_Hardpoint_Build(pad, option.type) then
        d.human.Give_Money(-cost)
        sound(SOLD_SOUND)
        close()
    end
end

return Hardpoints
