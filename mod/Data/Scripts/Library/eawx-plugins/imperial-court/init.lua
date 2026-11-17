require("deepcore/std/plugintargets")

return {
    type = "plugin",
    target = PluginTargets.interval(1),
    init = function(self, ctx)
        require("eawx-plugins/imperial-court/ImperialCourt")
        return ImperialCourt(ctx.galactic_conquest)
    end
}
