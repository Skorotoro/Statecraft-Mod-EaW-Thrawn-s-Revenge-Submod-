local R = require("eawx-plugins/new-republic/RepublicConfig")
local U = require("eawx-plugins/new-republic/RepublicUtil")

local AI = {}

function AI.update(d)
    if not d.human or d.human.Get_Faction_Name() == "REBEL" then
        return
    end
    local republic = Find_Player("REBEL")
    local independent = Find_Player("INDEPENDENT_FORCES")
    if not (republic and independent) or table.getn(U.worlds_of(republic)) == 0 then
        return
    end
    republic.Make_Ally(independent)
    independent.Make_Ally(republic)
    d.rep_ai = d.rep_ai or {next = GetCurrentTime() + U.weeks(R.AI_APPEAL_WEEKS)}
    if GetCurrentTime() < d.rep_ai.next then
        return
    end
    d.rep_ai.next = GetCurrentTime() + U.weeks(R.AI_APPEAL_WEEKS)
    if not U.chance(R.AI_APPEAL_CHANCE) then
        return
    end
    local candidates = {}
    for _, w in ipairs(U.worlds_of(independent)) do
        local n = U.jumps(d, republic, w.planet)
        if n and n <= 1 and U.strength_at(d.human, w.planet) <= 0 then
            table.insert(candidates, w)
        end
    end
    local w = U.pick(candidates)
    if w then
        d:transfer_world(w.planet, republic, false)
        d.show("Galactic HoloNet: " .. d:planet_name(w.planet) .. " asks to join the New Republic, and is welcomed.",
            nil, {r = 170, g = 200, b = 255}, 15)
    end
end

return AI
