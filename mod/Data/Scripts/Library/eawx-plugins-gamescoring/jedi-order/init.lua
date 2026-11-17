require("deepcore/std/plugintargets")

return {
    type = "plugin",
    target = PluginTargets.always(),
    init = function(self, ctx)
        local JediBattle = require("eawx-plugins-gamescoring/jedi-order/JediBattle")
        return JediBattle()
    end
}
