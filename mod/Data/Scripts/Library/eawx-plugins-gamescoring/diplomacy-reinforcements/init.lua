require("deepcore/std/plugintargets")

return {
    type = "plugin",
    target = PluginTargets.always(),
    init = function(self, ctx)
        local Reinforcements = require("eawx-plugins-gamescoring/diplomacy-reinforcements/Reinforcements")
        return Reinforcements()
    end
}
