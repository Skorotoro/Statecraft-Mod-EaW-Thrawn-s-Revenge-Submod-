require("deepcore/std/plugintargets")

return {
    type = "plugin",
    target = PluginTargets.interval(1),
    init = function(self, ctx)
        require("eawx-plugins/warlords/Warlords")
        return Warlords(ctx.galactic_conquest)
    end
}
