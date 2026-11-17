require("deepcore/std/plugintargets")

return {
    type = "plugin",
    target = PluginTargets.always(),
    init = function(self, ctx)
        local RebellionLanding = require("eawx-plugins-gamescoring/diplomacy-rebellion/RebellionLanding")
        return RebellionLanding()
    end
}
