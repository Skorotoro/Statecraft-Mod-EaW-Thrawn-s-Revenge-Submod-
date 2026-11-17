require("deepcore/std/plugintargets")
require("eawx-plugins/diplomacy/Diplomacy")

return {
    type = "plugin",
    target = PluginTargets.interval(1),
    init = function(self, ctx)
        return Diplomacy(ctx.galactic_conquest)
    end
}
