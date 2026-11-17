local WarMissions = {}

local CLASSES = {"TakePlanetAnyMission", "TakePlanetEnemyMission"}
local COLOR = {r = 255, g = 220, b = 120}

local function at_war(d, player)
    return player ~= d.human and d:relation(string.upper(player.Get_Faction_Name())) == "WAR"
end

local function patch_class(d, class)
    local begin = class.Begin
    class.Begin = function(self, reward_group, week_start, excluded)
        if self.player ~= d.human then
            return begin(self, reward_group, week_start, excluded)
        end
        local without = {}
        for _, faction in pairs(excluded or {}) do
            table.insert(without, faction)
        end
        local constants = ModContentLoader.get("GameConstants")
        for _, faction in pairs(constants and constants.ALL_FACTIONS_NOT_NEUTRAL or {}) do
            local player = Find_Player(faction)
            if player and player ~= d.human and not at_war(d, player) then
                table.insert(without, faction)
            end
        end
        return begin(self, reward_group, week_start, without)
    end
    local update = class.update
    class.update = function(self)
        if self.Active and self.player == d.human and self.Target and self.RewardGroupTable then
            local owner = self.Target.Get_Owner()
            if owner ~= d.human and not at_war(d, owner) then
                local world = self.Target.Get_Type() and d:planet_name(self.Target) or "the target"
                pcall(self.Reset, self)
                d.show("Mission called off: you are no longer at war with " .. d.display_name(owner.Get_Faction_Name())
                    .. ", so " .. world .. " is no longer a target.", nil, COLOR, 15)
                return
            end
        end
        return update(self)
    end
end

function WarMissions.patch(d)
    if WarMissions.done or GetCurrentTime() < (WarMissions.next_at or 0) then
        return
    end
    WarMissions.next_at = GetCurrentTime() + 5
    local all = true
    for _, name in ipairs(CLASSES) do
        local class = rawget(_G, name)
        if type(class) ~= "table" then
            all = false
        elseif not class.__war_patched then
            class.__war_patched = true
            patch_class(d, class)
        end
    end
    WarMissions.done = all
end

return WarMissions
