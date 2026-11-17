require("deepcore/std/plugintargets")

local original

local function unit_destroyed(object, killer)
    if TestValid(object) and object.Get_Type().Get_Name() == "HUTT_UPSTART" then
        crossplot:publish("HUTT_UPSTART_KILLED", object.Get_Owner().Get_Faction_Name())
    end
    return original(object, killer)
end

local function update()
end

return {
    type = "plugin",
    target = PluginTargets.always(),
    init = function(self, ctx)
        original = Galactic_Unit_Destroyed_Event
        if original then
            Galactic_Unit_Destroyed_Event = unit_destroyed
        end
        return {update = update}
    end
}
